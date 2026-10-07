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
