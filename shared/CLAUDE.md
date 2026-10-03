# Environment

Running in a disposable Docker container (`docker run --rm`) started by the user's `clod` launcher. Image is `clod` or a variant built `FROM clod`.

- `/home/claude` ← host `~/.clod/homes/<name>` (or another path chosen by `CLOD_HOME`)
- `/workspace` ← the host directory `clod` was run from: the user's real project, not a scratch dir
- `/etc/claude-code` ← `~/.clod/shared` (read-only here): managed settings, statusline, this file
- `$CLOD_HOME`, `$CLOD_IMAGE` and (only when a login is borrowed) `$CLOD_CREDS` name this run's home, image and login source

Only `/home/claude` and `/workspace` persist. Anything installed system-wide (apt, global pip/npm, `/usr/local`) is lost on exit; lasting system tooling belongs in a Dockerfile, and single-file tools can go in `~/.local/bin`.
