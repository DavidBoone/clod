# Shared config and the statusline

![The clod statusline in five columns over two lines: the model over its effort, context use over token counts, the idle time, the home over the image and ports, and the git branch over lines changed, with the 5-hour and 7-day rate limits at the right](statusline.svg)

Claude Code reads managed settings and a managed `CLAUDE.md` from
`/etc/claude-code`, for every home, and the entrypoint passes its
`settings.json` to Claude Code as `--settings`. Until `~/.clod/shared` exists,
clod mounts this repo's [`shared/`](../shared) there, which updates with `git pull`:

- `statusline.sh` is the statusline, in five columns over two lines: the
  model (`✨`) over its effort (`⚡`); context use over the session's input
  and output tokens, subagents included; the cache idle time over a
  cache-miss warning; the home (`🏠`) over the image (`📦`) and the
  published ports (`⇄`, TCP only, as links to `localhost` where the terminal
  supports them, right when the host port is the container's); and the git
  branch (`🪾`, or `🌿` and its folder in a linked worktree) with its count
  of changed files, over the lines changed. The 5-hour and 7-day rate limits
  sit at the right end of the two lines, their bars 10 to 20 cells wide as
  the terminal allows. A rate limit's bar shows usage against how much of its
  window has passed. Its last usage cell is red when usage is ahead, yellow
  when it's within 5 points behind, and green otherwise; any usage past the
  elapsed part is red.
- `settings.json` turns that statusline on.

To customise them, make your own copy and edit that:

```bash
clod shared new       # copies the starter to ~/.clod/shared
clod shared diff      # shows how yours differs from the starter
```

From then on clod mounts `~/.clod/shared` in place of the starter, so keep
everything you want from it there. Updates to the repo's `shared/` reach you
only when you merge them in. `clod shared new` on an existing one lists the
starter's files yours lacks or differs on; `clod shared diff` shows the
differences. `clod --force shared new` replaces yours with the starter,
keeping yours as a backup. Put your own instructions for Claude in a
`CLAUDE.md` there, and settings for every home in `settings.json`.

`settings.json` isn't a managed source: Claude Code doesn't read it itself.
Passed as `--settings`, it takes precedence over a home's own settings, so keep
per-client config in the homes, but an organisation's server-managed settings
take precedence over it. Claude Code reads only one source of managed
settings, and server-managed settings take the place of `/etc/claude-code`'s,
so settings kept there would be skipped. Real policy can still go in
`managed-settings.json` or `managed-settings.d/*.json` (see
[managed settings](https://code.claude.com/docs/en/settings)), where it applies
unless the organisation has server-managed settings.

Only the last `--settings` Claude Code is given applies, so the entrypoint
leaves `settings.json` out when you pass your own (`clod -- --settings
mine.json`); put what you need from it in yours.

A `~/.clod/shared` from before `settings.json` has `statusLine` in
`managed-settings.json`. Move it to a `settings.json` beside it (`clod shared
new` points this out), and delete `managed-settings.json` if nothing else is
left in it.

What Claude is told about the container (the mounts, what persists, the
`CLOD_*` variables) comes with the image, from [`container.md`](../container.md),
so your `CLAUDE.md` only needs your own additions.

Changes to `statusline.sh` show up on its next refresh. To turn it off, remove
`statusLine` from `settings.json`; homes can then set their own in
`~/.claude/settings.json`. To log each turn's cache reads and writes, create
`~/.claude/cache-turns.log` in a home (`touch`); the script appends to it
while it exists.
