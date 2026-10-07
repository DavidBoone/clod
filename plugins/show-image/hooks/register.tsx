import { atom, read, update } from 'claude-code'
import type { EngineInterface, Register, RenderInput } from 'claude-code'

import type { Held } from '../types'

const KEEP = 20
const MAX_COLUMNS = 60
const MAX_ROWS = 30
const TOOL = 'mcp__show-image__show_image'
const TOOL_PATTERN = /^mcp__show-image__show_image$/
const held = atom({ plugin: 'show-image', key: 'held' } as const, [])
const count = atom({ plugin: 'show-image', key: 'count' } as const, 0)

const BASE64 = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/'

// The bytes that whole groups of four base64 characters stand for.
function decode(base64: string): number[] {
  const bytes: number[] = []
  for (let i = 0; i + 4 <= base64.length; i += 4) {
    const n = [0, 1, 2, 3].reduce((acc, k) => (acc << 6) | BASE64.indexOf(base64[i + k] ?? 'A'), 0)
    bytes.push((n >> 16) & 255, (n >> 8) & 255, n & 255)
  }
  return bytes
}

// The PNG's width and height, from its IHDR chunk; null when it is not a PNG.
function pngSize(base64: string): { width: number; height: number } | null {
  const b = decode(base64.slice(0, 32))
  const isPng = b[0] === 0x89 && b[1] === 0x50 && b[2] === 0x4e && b[3] === 0x47
  if (!isPng || b.length < 24) return null
  const word = (i: number) =>
    ((b[i] ?? 0) << 24) | ((b[i + 1] ?? 0) << 16) | ((b[i + 2] ?? 0) << 8) | (b[i + 3] ?? 0)
  return { width: word(16), height: word(20) }
}

// The command and the tool answer `#<id> <path>`; a command's row carries it
// after the plugin's name (`show-image: #<id> <path>`).
function heldRef(text: string): { id: string; path: string } | undefined {
  const match = /^(?:[\w-]+: )?#(\d+) (.*)$/s.exec(text)
  return match?.[1] === undefined || match[2] === undefined
    ? undefined
    : { id: match[1], path: match[2] }
}

// An Image's `png` source takes at most 2 MiB.
const MAX_PNG_BYTES = 2 * 1024 * 1024
const MAX_PNG_BASE64 = Math.ceil(MAX_PNG_BYTES / 3) * 4
// The longest side, in pixels, of a picture convert.py writes.
const MAX_SIDE = 1200

// The file's first frame as a PNG, through Pillow; the error text otherwise.
async function convert($: EngineInterface, path: string): Promise<string | { png: string }> {
  const script = `${$.plugin.root}/convert.py`
  let ran
  try {
    ran = await $.process.run(['python3', script, path, String(MAX_SIDE), String(MAX_PNG_BYTES)])
  } catch {
    return 'needs converting to a small enough PNG, and python3 is not installed'
  }
  if (ran.exitCode !== 0) {
    return ran.stderr.trim().split('\n').pop() || 'could not convert it'
  }

  return { png: ran.stdout.trim() }
}

// Reads a picture (a small enough PNG as it is, any other through Pillow) and
// keeps it for the rows that draw it; the error text otherwise.
async function hold($: EngineInterface, path: string, toolUseId?: string): Promise<Held | string> {
  if (path === '') return 'no file named'
  let png: string | undefined
  try {
    png = (await $.fs.read(path, { as: 'bytes' })).base64
  } catch {
    // Over 4 MiB, or unreadable: convert.py says which.
  }
  if (png === undefined || pngSize(png) === null || png.length > MAX_PNG_BASE64) {
    const converted = await convert($, path)
    if (typeof converted === 'string') return converted
    png = converted.png
  }
  const size = pngSize(png)
  if (size === null) return 'convert.py wrote no PNG'
  const id = String((await read($, count)) + 1)
  await update($, count, () => Number(id))
  const item: Held = { id, path, png, ...size, ...(toolUseId === undefined ? {} : { toolUseId }) }
  await update($, held, list => [...list, item].slice(-KEEP))

  return item
}

// The held image `id` as a transcript row draws it: its path, then the picture.
async function draw(
  $: EngineInterface,
  e: RenderInput<'CommandOutput' | 'ToolResult' | 'ToolGroup'>,
  item: Held | undefined,
  path: string,
) {
  if (e.surface !== 'terminal' || item === undefined) {
    const { Text } = $.ui.resolve(e)
    const why = item === undefined ? 'no longer held' : 'shown in the terminal only'
    return <Text dimColor>{path} ({why})</Text>
  }

  const { Box, Text, Image } = $.ui.resolve(e)
  // A terminal cell is about 8 pixels wide and twice as tall as it is wide.
  let columns = Math.min(MAX_COLUMNS, (e.viewport?.columns ?? 80) - 4, Math.ceil(item.width / 8))
  let rows = Math.round((columns * item.height) / item.width / 2)
  if (rows > MAX_ROWS) {
    rows = MAX_ROWS
    columns = Math.round((rows * 2 * item.width) / item.height)
  }

  return (
    <Box flexDirection="column">
      <Text dimColor>{path}</Text>
      <Image
        key="image"
        source={{ png: item.png }}
        columns={Math.max(1, columns)}
        rows={Math.max(1, rows)}
        alt={`(image: ${path})`}
      />
    </Box>
  )
}

export const register: Register = on => {
  on('session.start', async ($, e, next) => {
    await $.command.register({
      name: 'show-image',
      description: 'Show a picture (PNG, JPEG, GIF, WebP, ...) inline in the conversation',
      argumentHint: '<path>',
    })
    await $.tool.register({
      name: 'show_image',
      description:
        'Show the user a picture file (PNG, JPEG, GIF, WebP, TIFF, BMP; an animation shows ' +
        'its first frame) inline in the terminal transcript. Use it when a picture you made ' +
        'or found would help the user (a chart, screenshot, diagram), not for images you ' +
        'only need to look at yourself. The user sees the image; you do not.',
      inputSchema: {
        type: 'object',
        properties: {
          path: { type: 'string', description: 'Absolute path of the picture file' },
        },
        required: ['path'],
      },
      isDeferred: false,
    })

    return next(e)
  })

  on('command.run', { command: 'show-image' }, async ($, e) => {
    const path = e.args.trim()
    const item = await hold($, path)
    if (typeof item === 'string') return { text: `${path || '/show-image'}: ${item}`, exitCode: 1 }

    return { text: `#${item.id} ${path}` }
  })

  on('ui.render', { component: 'CommandOutput' }, async ($, e, next) => {
    const ref = heldRef(e.props.text)
    if (e.props.command !== 'show-image' || e.props.isErrored || ref === undefined) {
      return next(e)
    }

    const item = (await read($, held)).find(one => one.id === ref.id)

    return draw($, e, item, ref.path)
  })

  on('tool.call', { tool: TOOL_PATTERN }, async ($, e) => {
    const input = e as unknown as { path?: unknown }
    const path = typeof input.path === 'string' ? input.path : ''
    const item = await hold($, path, e.tool_use_id)
    if (typeof item === 'string') return { result: `${path}: ${item}`, isError: true as const }

    return { result: `#${item.id} ${path}` }
  })

  on('ui.render', { component: 'ToolResult' }, async ($, e, next) => {
    const ref = typeof e.props.output === 'string' ? heldRef(e.props.output) : undefined
    if (e.props.tool !== TOOL || e.props.isErrored || ref === undefined) {
      return next(e)
    }

    const item = (await read($, held)).find(one => one.id === ref.id)

    return draw($, e, item, ref.path)
  })

  // A collapsed run of tool calls (focus view, or a run of reads) draws no
  // ToolResult rows: the images its show_image calls held go under its line.
  on('ui.render', { component: 'ToolGroup' }, async ($, e, next) => {
    const ids = e.props.calls
      .filter(call => call.tool === TOOL && !call.isRunning && !call.isErrored)
      .map(call => call.tool_use_id)
    const list = await read($, held)
    const items = ids.flatMap(id => list.filter(one => id !== undefined && one.toolUseId === id))
    if (e.props.isExpanded || items.length === 0) {
      return next(e)
    }

    const { Box } = $.ui.resolve(e)
    const line = await next(e)
    const pictures = await Promise.all(items.map(item => draw($, e, item, item.path)))

    return (
      <Box flexDirection="column">
        {line}
        {pictures}
      </Box>
    )
  })
}
