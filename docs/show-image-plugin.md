# show-image: inline pictures in Claude Code

## BLUF

- **What:** a Claude Code plugin that draws a picture file (PNG, JPEG, GIF, WebP, TIFF, BMP)
  inline in the terminal transcript, so Claude can show you a chart, screenshot or diagram
  it made instead of handing you a path.
- **Two entry points:** a tool Claude calls (`show_image`, full name
  `mcp__show-image__show_image`) and a slash command you type (`/show-image PATH`).
- **Where it works:** terminals with a graphics protocol, kitty and Ghostty. Elsewhere the row
  shows the path only. On claude.ai or other non-terminal surfaces it shows
  "`PATH (shown in the terminal only)`".
- **One-way:** the user sees the picture; Claude doesn't. The tool returns only `#<id> <path>`.
  To look at an image itself, Claude still uses `Read`.
- **Size:** ~170 lines of TSX plus a 35-line Python converter. No MCP server process: the tool is
  registered in-process through Claude Code's plugin hook API (`$.tool.register`), which is why
  it is named like an MCP tool.
- **Dependencies:** Claude Code with plugin `hooks` modules (built on 2.1.295). PNGs under 2 MiB
  need nothing else. Every other format, and oversized PNGs, go through `python3` + Pillow.
- **Where it lives:** `/etc/clod/plugins/show-image/` in the `clod` container image. The
  entrypoint passes `--plugin-dir=<folder>` for every folder under `/etc/clod/plugins/`.
- **Typical use:** after a Playwright/Chromium screenshot of a UI change, or a matplotlib chart,
  Claude calls `show_image` so the reviewer sees it in place. We also use it for "reaction
  images" (e.g. a fixed image when tests pass), configured in `~/.claude/CLAUDE.md`.

---

## How it works

### Flow

```
show_image {path}  ─┐                                 ┌─ ToolResult row ─┐
                    ├─ hold(path) ─ PNG ≤ 2 MiB? ─yes─┤                  ├─ draw(): path + <Image>
/show-image PATH   ─┘      │              no          └─ CommandOutput ──┘
                           └─ python3 convert.py PATH 1200 2097152 → base64 PNG
```

1. **Hold.** `hold()` reads the file as bytes (`$.fs.read(path, {as: 'bytes'})`, base64). If it
   is a PNG (magic bytes checked) and its base64 is ≤ `ceil(2 MiB / 3) * 4` characters, it is
   used as is. Otherwise, including when the read throws (unreadable, or over the 4 MiB read
   cap), it runs `convert.py`.
2. **Convert.** `convert.py PATH MAX_SIDE MAX_BYTES` opens the file with Pillow, takes frame 0,
   applies EXIF rotation, normalises odd modes to RGB/RGBA, thumbnails to 1200 px on the long
   side, and re-encodes as PNG. While the result is over 2 MiB, it shrinks the side by ¾ and
   retries, down to 64 px. It prints base64 to stdout. On failure it exits non-zero with a
   message, and the plugin reports the **last line of stderr**.
3. **Store.** Each held image gets an incrementing id (`count` atom) and is pushed onto a
   `held` atom: `{id, path, png, width, height, toolUseId?}`. Width and height come from the
   PNG's IHDR chunk, decoded from the first 32 base64 characters. Only the last **20**
   (`KEEP`) are kept, so the transcript doesn't hold unbounded base64.
4. **Answer.** The tool and the command both answer `#<id> <path>`; errors are
   `<path>: <reason>` with `isError` / exit code 1. That short text is all that enters the model
   context. The picture stays in plugin state.
5. **Render.** `ui.render` hooks swap the plain row for a picture:
   - `ToolResult` where `props.tool` is the show_image tool and the output parses as
     `#<id> <path>`.
   - `CommandOutput` for command `show-image`. Its text arrives prefixed with the plugin name
     (`show-image: #3 /path`), so the parser accepts an optional `name: ` prefix.
   - `ToolGroup`: when calls are collapsed (focus view, or a run of reads), no `ToolResult` row
     is drawn. The hook renders the group's own line (`next(e)`), then the pictures of any
     show_image calls in it, matched by `tool_use_id`. It passes through when expanded.
   - An id that has dropped out of `held` renders `PATH (no longer held)`.
6. **Sizing.** A cell is taken as ~8 px wide and twice as tall as wide.
   `columns = min(60, viewport.columns - 4, ceil(width/8))`,
   `rows = round(columns * height / width / 2)`. If rows exceed 30, it caps rows at 30 and
   recomputes columns from the aspect ratio. Both have a minimum of 1. It renders
   `<Box column><Text dim>{path}</Text><Image key="image" source={{png}} columns rows alt/></Box>`.

### Design choices worth keeping

- **Return a reference, not the image.** The model gets `#id path`, so a picture costs a few
  tokens of context, not megabytes of base64, and the render hook finds the bytes by id.
- **Fast path stays dependency-free.** PNG detection and IHDR parsing are hand-rolled (a tiny
  base64 decoder), so screenshots never spawn Python.
- **Tool description steers usage.** It says to use the tool for pictures that help *the user*,
  not for images Claude needs to inspect, and that Claude won't see the result. Without that,
  models call it expecting to see the image.
- `isDeferred: false` puts the tool in the initial tool list, so no ToolSearch round trip is
  needed.

## File layout

```
show-image/
├── .claude-plugin/plugin.json   name, version, description, "types": "./types/index.d.ts"
├── hooks/hooks.json             { "modules": ["./register.tsx"] }
├── hooks/register.tsx           all behaviour (registration, tool, command, render hooks)
├── types/index.d.ts             Held type + PluginState augmentation for the atoms
├── convert.py                   Pillow fallback converter
└── tests/show-image.test.ts     8 tests on claude-code/testing
```

## Loading it

- In the clod image: automatic, through `--plugin-dir=/etc/clod/plugins/show-image` from
  `/usr/local/bin/clod-entrypoint`.
- Elsewhere: `claude --plugin-dir=/path/to/show-image`, or package it in a plugin marketplace.
- Prerequisites for non-PNG input: `python3` and Pillow (`apt install python3-pil` or
  `pip install pillow`; built against Pillow 12.2).
- Terminal: kitty or Ghostty for actual pixels.

## Tests

`tests/show-image.test.ts` uses `claude-code/testing` and stubs `fs.read` / `process.run`:

| Test | Asserts |
|---|---|
| `/show-image` with a PNG | answer `#1 /tmp/a.png`; the mounted row has an element keyed `image` with `source {png}` and the path text |
| `/show-image` with no path | `/show-image: no file named` |
| non-PNG | spawns `python3 …/convert.py /tmp/a.gif 1200 2097152` |
| convert error | the answer is the last stderr line |
| no python3 | `needs converting to a small enough PNG, and python3 is not installed` |
| stale id | the row says `no longer held` |
| tool call | result `#1 /tmp/b.png`; the ToolResult row draws the image |
| collapsed ToolGroup | the group line is kept and the image is drawn under it |

## Recreating it: agent checklist

1. Create the layout above with `plugin.json` and `hooks.json` exactly as shown.
2. Write `types/index.d.ts` and `convert.py` from the appendix verbatim.
3. Write `hooks/register.tsx` from the appendix. Read the `plugin-authoring` skill first if the
   hook API (`on`, `$.fs`, `$.process`, `$.ui.resolve`, `atom/read/update`) is unfamiliar. The
   API names in the source are authoritative for Claude Code 2.1.29x.
4. Copy the tests and run them with Claude Code's plugin test runner (see `plugin-authoring`).
5. Launch with `--plugin-dir`, then smoke-test:
   `/show-image /some/screenshot.png`, a JPEG (to exercise Pillow), a missing file (to check the
   error text), and a tool call from the model in focus view (to exercise the ToolGroup path).
6. Optional: add a line to `CLAUDE.md` saying when to show images, e.g. "after a UI change,
   screenshot it and call show_image".

---

## Appendix: source

### `types/index.d.ts`

```ts
export type Held = {
  id: string
  path: string
  png: string
  width: number
  height: number
  /** The show_image call that held it; absent for /show-image. */
  toolUseId?: string
}

declare module 'claude-code' {
  interface PluginState {
    'show-image': { held: Held[]; count: number }
  }
}
```

### `convert.py`

```python
"""Prints a picture file's first frame as a base64 PNG of at most MAX_BYTES.

Usage: python3 convert.py PATH MAX_SIDE MAX_BYTES
"""
import base64
import io
import sys

try:
    from PIL import Image, ImageOps
except ImportError:
    sys.exit("Pillow (python3-pil) is not installed")

path, max_side, max_bytes = sys.argv[1], int(sys.argv[2]), int(sys.argv[3])
try:
    with Image.open(path) as image:
        image.seek(0)
        image = ImageOps.exif_transpose(image)
        if image.mode not in ("1", "L", "LA", "P", "RGB", "RGBA"):
            image = image.convert("RGBA" if "A" in image.getbands() else "RGB")
        side = max_side
        while True:
            image.thumbnail((side, side))
            out = io.BytesIO()
            image.save(out, "PNG")
            if out.tell() <= max_bytes or side < 64:
                break
            side = side * 3 // 4
except (OSError, ValueError, Image.DecompressionBombError) as err:
    sys.exit(str(err))
if out.tell() > max_bytes:
    sys.exit("too large to show")
sys.stdout.write(base64.b64encode(out.getvalue()).decode())
```

### `hooks/register.tsx`

```tsx
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
```

### `tests/show-image.test.ts`

```ts
import { expect, test } from 'claude-code/testing'

// A 1x1 PNG.
const PNG =
  'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAIAAACQd1PeAAAADElEQVR4nGP4z8AAAAMBAQDJ/pLvAAAAAElFTkSuQmCC'
const TEXT = 'aGVsbG8gd29ybGQ='
const TOOL = 'mcp__show-image__show_image'
const RUN = {
  command: 'show-image',
  origin: { kind: 'composer' },
  presentation: { isFullscreen: false, columns: 120 },
} as const
const ran = (exitCode: number, stdout: string, stderr = '') => ({
  value: { exitCode, stdout, stderr, isStdoutTruncated: false, isStderrTruncated: false },
})
const row = (text: string) =>
  ({
    plugin: 'show-image',
    surface: 'terminal',
    component: 'CommandOutput',
    props: { command: 'show-image', args: '', text, isErrored: false },
  }) as const

test('/show-image draws a PNG inline in its output row', async ($, on) => {
  on('fs.read', () => ({ value: { base64: PNG } }))
  const out = await $.command.run({ ...RUN, args: '/tmp/a.png' })
  expect(out.text).toBe('#1 /tmp/a.png')

  // the row's text carries the plugin's name before the command's answer
  const ui = await $.ui.mount(row(`show-image: ${out.text}`))
  expect((await ui.find({ key: 'image' }))?.props.source).toEqual({ png: PNG })
  expect(await ui.find({ type: 'Text', text: '/tmp/a.png' })).toBeDefined()
  await ui.unmount()
})

test('/show-image without a path is an error', async $ => {
  const out = await $.command.run({ ...RUN, args: '' })
  expect(out.text).toBe('/show-image: no file named')
})

test('another format goes through convert.py', async ($, on) => {
  on('fs.read', () => ({ value: { base64: TEXT } }))
  on('process.run', (_, e) => {
    expect(e.argv[0]).toBe('python3')
    expect(e.argv[1]?.endsWith('/convert.py')).toBe(true)
    expect(e.argv.slice(2)).toEqual(['/tmp/a.gif', '1200', String(2 * 1024 * 1024)])
    return ran(0, PNG)
  })
  const out = await $.command.run({ ...RUN, args: '/tmp/a.gif' })
  expect(out.text).toBe('#1 /tmp/a.gif')
})

test("convert.py's last line of errors is the answer", async ($, on) => {
  on('fs.read', () => ({ value: { base64: TEXT } }))
  on('process.run', () => ran(1, '', 'Traceback\ncannot identify image file /tmp/a.txt\n'))
  const out = await $.command.run({ ...RUN, args: '/tmp/a.txt' })
  expect(out.text).toBe('/tmp/a.txt: cannot identify image file /tmp/a.txt')
})

test('without python3 another format is an error', async ($, on) => {
  on('fs.read', () => ({ value: { base64: TEXT } }))
  on('process.run', () => {
    throw new Error('spawn python3 ENOENT')
  })
  const out = await $.command.run({ ...RUN, args: '/tmp/a.gif' })
  expect(out.text).toBe(
    '/tmp/a.gif: needs converting to a small enough PNG, and python3 is not installed',
  )
})

test('a row whose image is no longer held says so', async $ => {
  const ui = await $.ui.mount(row('show-image: #7 /tmp/old.png'))
  expect(await ui.find({ type: 'Text', text: /no longer held/ })).toBeDefined()
  await ui.unmount()
})

test('the show_image tool draws the picture in its result row', async ($, on) => {
  on('fs.read', () => ({ value: { base64: PNG } }))
  const out = await $.tool.call({ tool: TOOL, path: '/tmp/b.png' } as never)
  expect(out.result).toBe('#1 /tmp/b.png')

  const ui = await $.ui.mount({
    plugin: 'show-image',
    surface: 'terminal',
    component: 'ToolResult',
    props: { tool_use_id: 't1', tool: TOOL, output: out.result, isErrored: false },
  } as never)
  expect((await ui.find({ key: 'image' }))?.props.source).toEqual({ png: PNG })
  await ui.unmount()
})

test('a collapsed tool group draws its pictures under its line', async ($, on) => {
  on('fs.read', () => ({ value: { base64: PNG } }))
  on('ui.render', { component: 'ToolGroup' }, (inner, e) => {
    const { Text } = inner.ui.resolve(e)
    return h(Text, {}, 'Ran 1 tool') as never
  })
  await $.tool.call({ tool: TOOL, tool_use_id: 't9', path: '/tmp/c.png' } as never)

  const call = { tool_use_id: 't9', tool: TOOL, input: { path: '/tmp/c.png' } }
  const ui = await $.ui.mount({
    plugin: 'show-image',
    surface: 'terminal',
    component: 'ToolGroup',
    props: {
      calls: [{ ...call, isRunning: false, isErrored: false, isInterrupted: false }],
      isActive: false,
      isExpanded: false,
    },
  } as never)
  expect(await ui.find({ type: 'Text', text: 'Ran 1 tool' })).toBeDefined()
  expect((await ui.find({ key: 'image' }))?.props.source).toEqual({ png: PNG })
  await ui.unmount()
})
```
