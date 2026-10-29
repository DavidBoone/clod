# Shared config and the statusline

![The clod statusline in five columns over two lines: the model over its effort, context use over token counts, the idle time, the home over the image and ports, and the git branch over lines changed, with the 5-hour and 7-day rate limits at the right](statusline.svg)

clod mounts the shared config read-only at `/etc/clod-shared` in every
container, for every home, and the entrypoint passes its `settings.json` to
Claude Code as `--settings`. The instructions for every agent come from there
too: the entrypoint composes the shared config's `AGENTS.md` (or a `CLAUDE.md`
kept from before it) with the image's own into the `AGENTS.md` each agent
reads globally — Codex's `$CODEX_HOME/AGENTS.md`, OpenCode's
`~/.config/opencode/AGENTS.md` and Gemini CLI's `~/.gemini/GEMINI.md` written
in the home, and, for Claude Code, `/etc/clod/CLAUDE.md`, which also gets a
shared `CLAUDE.md` beside the `AGENTS.md`. Until `~/.clod/shared` exists, clod mounts this repo's
[`shared/`](../shared) there, which updates with `git pull`:

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
clod shared           # lists the shared config: where it is and its files
clod shared new       # copies the starter to ~/.clod/shared
clod shared diff      # shows how yours differs from the starter
clod shared edit      # opens its AGENTS.md in $VISUAL, $EDITOR or vi
clod shared edit settings.json  # or another file there
```

From then on clod mounts `~/.clod/shared` in place of the starter, so keep
everything you want from it there. Updates to the repo's `shared/` reach you
only when you merge them in. `clod shared new` on an existing one lists the
starter's files yours lacks or differs on; `clod shared diff` shows the
differences. `clod shared new --force` replaces yours with the starter,
keeping yours as a backup. Put your own instructions in an `AGENTS.md` there,
which every agent reads, and settings for every home in `settings.json`. A
`CLAUDE.md` from before `AGENTS.md` still reaches every agent while it is the
only one; once you add an `AGENTS.md`, rename the `CLAUDE.md` to it, or keep
only Claude-specific instructions in it, since Claude Code gets both (`clod
shared new` points this out; an identical copy is read once).

`settings.json` isn't a managed source: Claude Code doesn't read it itself.
Passed as `--settings`, it takes precedence over a home's own settings, so keep
per-client config in the homes, but an organisation's server-managed settings
take precedence over it. Claude Code reads only one source of managed
settings, and server-managed settings take the place of `/etc/claude-code`'s,
so settings kept there would be skipped. Real policy can still go in
`managed-settings.json` or `managed-settings.d/*.json` (see
[managed settings](https://code.claude.com/docs/en/settings)), where it applies
unless the organisation has server-managed settings.

`/etc/claude-code` is the image's, so a devcontainer or variant that has its
own managed settings keeps them. clod mounts the files there that Claude Code
reads from the shared config one by one, beside the image's own: its
`managed-settings.json` as `managed-settings.d/50-clod.json`, which Claude Code
applies after the image's `managed-settings.json` (and before any of the
image's drop-ins named after it), each file in its `managed-settings.d/` and
each entry in its `.claude/` folders (`agents/`, `skills/` and the like), and
its other files, such as `statusline.sh`. A file of the same name in the image
is hidden by the shared one. `AGENTS.md`, `CLAUDE.md`, `settings.json` and
other hidden files (`.git`) stay only in `/etc/clod-shared`.

Only the last `--settings` Claude Code is given applies, so the entrypoint
leaves `settings.json` out when you pass your own (`clod -- --settings
mine.json`); put what you need from it in yours.

A `~/.clod/shared` from before `settings.json` has `statusLine` in
`managed-settings.json`. Move it to a `settings.json` beside it (`clod shared
new` points this out), and delete `managed-settings.json` if nothing else is
left in it.

What the agents are told about the container (the mounts, what persists, the
`CLOD_*` variables) comes with the image, from [`container.md`](../container.md),
so your `AGENTS.md` only needs your own additions.

Changes to `statusline.sh` show up on its next refresh. To turn it off, remove
`statusLine` from `settings.json`; homes can then set their own in
`~/.claude/settings.json`. To log each turn's cache reads and writes, create
`~/.claude/cache-turns.log` in a home (`touch`); the script appends to it
while it exists.
