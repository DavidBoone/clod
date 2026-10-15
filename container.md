# Environment

Running in a disposable Docker container (`docker run --rm`) started by the user's `clod` launcher (https://github.com/DavidBoone/clod) on their macOS or Linux host. Image is `clod` (Debian trixie), a variant built `FROM clod`, or, when `$CLOD_IMAGE` starts with `devcontainer`, the project's devcontainer, whose lifecycle commands, mounts and ports aren't used, so run any setup they'd do yourself.

- `/home/claude` ← the host home `$CLOD_HOME`; `/workspace` ← the user's real project `$CLOD_WORKSPACE`, not a scratch dir. `vol:<name>` means a Docker volume with no host folder; `$CLOD_SCRATCH` means an empty workspace discarded with the container, so keep anything worth keeping in the home or a remote
- `/etc/claude-code` ← the user's `~/.clod/shared` (read-only): settings and their own instructions. `/etc/clod/AGENTS.md` is this file plus variants' `/etc/clod/AGENTS.d/`
- Files for the user: put them under `/workspace` or `/home/claude` and give the host path via `$CLOD_WORKSPACE_PATH` or `$CLOD_HOME_PATH` (unset for volumes), never `/tmp` or other container paths
- `$CLOD_PORTS` lists published ports; servers must listen on `0.0.0.0`. The host is `host.docker.internal`; the Docker socket only with `clod --docker`
- `$CLOD_CLIPBOARD_URL` (from `clod --clipboard`) lets Ctrl+V paste images; without it, it can't
- The `show_image` tool draws a picture inline in kitty or Ghostty

On virtiofs mounts (usual on macOS) GNU `sed -i` leaves files mode 600; use `perl -i` or your own edit tools.

Give `rm` literal paths and keep it out of generated scripts: an `rm` on a computed path prompts even in bypass mode and stalls the session.

Worktrees made here hold `/workspace/…` paths the host can't follow; if the user wants one on the host, suggest git 2.48's `worktree.useRelativePaths`, noting older git then refuses the repository.

Only `/home/claude` and (unless scratch) `/workspace` persist. System packages belong in a variant's Dockerfile; `npm install -g` goes to `~/.local`, Python packages in a venv, single-file tools in `~/.local/bin`.

# Changing the container

You can't run `clod` or see the host's `~/.clod`; the user changes these on the host, effective next run. When the container is in the way, say what to change, with exact lines:

- Packages: a variant Dockerfile (`clod image new <name>`, `clod image edit <name>`), run with `clod -i <name>`; root while running: the `sudo` variant
- Environment variables: the project's `.envrc` (direnv, allowed on the host)
- Defaults: `clod default KEY VALUE`, or `CLOD_*` in a project's `.envrc`
- Instructions or settings for every home: `~/.clod/shared/`
- Ports: `clod -P 3000`; Docker access: `clod -i docker --docker` (root on the Docker host)

`clod env` and `clod help` show the rest. Read the docs (`https://raw.githubusercontent.com/DavidBoone/clod/master/docs/<page>`: `usage.md`, `images.md`, `configuration.md`, `shared-config.md`, `docker-socket.md`, `security.md`, `docker.md`) before advising beyond this.
