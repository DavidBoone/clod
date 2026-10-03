# Environment

Running in a disposable Docker container (`docker run --rm`) started by the user's `clod` launcher. Image is `clod` or a variant built `FROM clod`.

- `/home/claude` ← host `~/.clod/homes/<name>` (or another path chosen by `CLOD_HOME`)
- `/workspace` ← the host directory `clod` was run from: the user's real project, not a scratch dir
- `/etc/claude-code` ← `~/.clod/shared`, or clod's own `shared/` until that exists (read-only here): managed settings, statusline, this file
- `$CLOD_HOME`, `$CLOD_IMAGE` and (only when a login is borrowed) `$CLOD_CREDS` name this run's home, image and login source

Only `/home/claude` and `/workspace` persist. System packages (apt, `/usr/local`) belong in an image variant's Dockerfile, which the user maintains. `npm install -g` goes to `~/.local` and persists, Python packages go in a venv, and single-file tools can go in `~/.local/bin`.
