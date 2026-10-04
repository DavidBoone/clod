# Shared config and the statusline

![The clod statusline: home and image, model and effort, tokens, lines changed, context use, idle time, and 5-hour and 7-day rate limits](statusline.svg)

Claude Code reads managed settings and a managed `CLAUDE.md` from
`/etc/claude-code`, for every home. Until `~/.clod/shared` exists, clod mounts
this repo's [`shared/`](../shared) there, which updates with `git pull`:

- `statusline.sh` is the statusline: the home, image, model, tokens, context
  use, cache idle time and rate limits.
- `managed-settings.json` turns that statusline on.

To customise them, make your own copy and edit that:

```bash
clod shared new       # copies the starter to ~/.clod/shared
clod shared diff      # shows how yours differs from the starter
```

From then on clod mounts `~/.clod/shared` in place of the starter, so keep
everything you want from it there. Updates to the repo's `shared/` reach you
only when you merge them in. Run `clod shared new` again to compare: it lists
the starter's files that yours is missing or differs on. `clod shared diff`
shows the differences line by line, and `clod --force shared new` replaces
yours with the starter, keeping yours as a backup. Put your own instructions for Claude in a
`CLAUDE.md` there, and any other
[managed settings](https://code.claude.com/docs/en/settings) in
`managed-settings.json` or `managed-settings.d/*.json`. Managed settings take
precedence over a home's own settings, so keep per-client config in the homes.

What Claude is told about the container (the mounts, what persists, the
`CLOD_*` variables) comes with the image, from [`container.md`](../container.md),
so your `CLAUDE.md` only needs your own additions.

Changes to `statusline.sh` show up on its next refresh. To turn it off, remove
`statusLine` from `managed-settings.json`; homes can then set their own in
`~/.claude/settings.json`. To log each turn's cache reads and writes, create
`~/.claude/cache-turns.log` in a home (`touch`); the script appends to it
while it exists.
