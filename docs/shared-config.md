# Shared config and the statusline

![The clod statusline: on the first line the model and effort, the home and image, the published ports and the git branch; on the second tokens, lines changed, context use, idle time, and 5-hour and 7-day rate limits](statusline.svg)

Claude Code reads managed settings and a managed `CLAUDE.md` from
`/etc/claude-code`, for every home. Until `~/.clod/shared` exists, clod mounts
this repo's [`shared/`](../shared) there, which updates with `git pull`:

- `statusline.sh` is the statusline, on two lines: the model, the home
  (`⌂`) and image (`⬢`), the published ports (`⇄`, TCP only, as links to
  `localhost` where the terminal supports them, right when the host port is
  the container's) and the git branch with its count of
  changed files; then tokens, context use, cache idle time and rate limits.
  A rate limit's bar shows usage against how much of its window has passed.
  Its last usage cell is red when usage is ahead, yellow when it's within 5
  points behind, and green otherwise; any usage past the elapsed part is red.
- `managed-settings.json` turns that statusline on.

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
`CLAUDE.md` there, and any other
[managed settings](https://code.claude.com/docs/en/settings) in
`managed-settings.json` or `managed-settings.d/*.json`. Managed settings take
precedence over a home's own settings, so keep per-client config in the homes.

Claude Code reads only one source of managed settings, and an organisation's
server-managed settings, where it has them, take the place of
`/etc/claude-code`'s file. So the entrypoint also passes
`managed-settings.json` to Claude Code as `--settings`, which keeps it, the
statusline included, in effect either way: below the organisation's settings,
but still above a home's own. `managed-settings.d/*.json` isn't passed, so
settings there apply only when the file is the managed source.

What Claude is told about the container (the mounts, what persists, the
`CLOD_*` variables) comes with the image, from [`container.md`](../container.md),
so your `CLAUDE.md` only needs your own additions.

Changes to `statusline.sh` show up on its next refresh. To turn it off, remove
`statusLine` from `managed-settings.json`; homes can then set their own in
`~/.claude/settings.json`. To log each turn's cache reads and writes, create
`~/.claude/cache-turns.log` in a home (`touch`); the script appends to it
while it exists.
