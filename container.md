# Environment

Running in a disposable Docker container (`docker run --rm`) started by the user's `clod` launcher (https://github.com/DavidBoone/clod) on their macOS or Linux host. Image is `clod` (Debian trixie), a variant built `FROM clod`, or, when `$CLOD_IMAGE` starts with `devcontainer`, the project's devcontainer, whose lifecycle commands, mounts and ports aren't used, so run any setup they'd do yourself.

- `/home/claude` ← the home named `$CLOD_HOME` (`~/.clod/homes/<name>` on the host, or a path); `/workspace` ← the user's real project `$CLOD_WORKSPACE`, not a scratch dir. `$CLOD_IMAGE` names the image as `-i` does. `vol:<name>` means a Docker volume with no host folder; `$CLOD_SCRATCH` means an empty workspace discarded with the container, so keep anything worth keeping in the home or a remote
- `/etc/claude-code` ← the user's `~/.clod/shared` (read-only; clod's bundled one until they run `clod shared new`): settings and their own instructions. `/etc/clod/AGENTS.md` is this file; variants add `/etc/clod/AGENTS.d/`
- Files for the user: put them under `/workspace` or `/home/claude` and give the host path via `$CLOD_WORKSPACE_PATH` or `$CLOD_HOME_PATH` (a `~` there is the host user's home), never `/tmp` or other container paths. They're unset for a volume or scratch mount, which has no host folder: say so
- `$CLOD_PORTS` lists the container ports published; the host port may differ (`-P 8080:3000`, or clod moved a busy one), so ask the user which; servers must listen on `0.0.0.0`. The host is `host.docker.internal`; the Docker socket is mounted only with `clod --docker`
- `$CLOD_CLIPBOARD_URL` (from `clod --clipboard`) lets Ctrl+V paste images; without it, it can't
- The `show_image` tool (or the user's `/show-image PATH`) draws a picture inline in kitty or Ghostty; elsewhere they see its path
- `$TERM` is `xterm`; `$TERM_PROGRAM`, `$LC_TERMINAL`, `$COLORTERM` and their versions are the host terminal's, where it sets them

On virtiofs mounts (usual on macOS) GNU `sed -i` leaves files mode 600; use `perl -i` or your own edit tools.

Give `rm` literal paths and keep it out of generated scripts: an `rm` whose path is only known at run time (`rm -f "$dir/x"` with `dir=$(…)`) or one inside `bash -c "$(…)"` prompts even in bypass mode and stalls the session.

Worktrees made here hold `/workspace/…` paths the host can't follow; if the user wants one on the host, suggest git 2.48 or later's `git config --global worktree.useRelativePaths true` (and `git worktree repair --relative-paths` for existing ones), noting older git then refuses the repository.

Only `/home/claude` and (unless scratch) `/workspace` persist. System packages belong in a variant's Dockerfile; `npm install -g` goes to `~/.local`, Python packages in a venv, single-file tools in `~/.local/bin`.

# Changing the container

You can't run `clod` or see the host's `~/.clod`; the user changes these on the host, effective next run. When the container is in the way, say what to change, with exact lines:

- Docs and man pages for installed packages: `clod default base full`
- Packages: a variant Dockerfile (`ARG BASE=clod` / `FROM $BASE`, `USER root` … `USER claude`; `clod image new <name>`, `clod image edit <name>`), run with `clod -i <name>`, combinable (`-i go+<name>`); root while running: the `sudo` variant
- A project with a `.devcontainer`: `clod -i devcontainer` (`devcontainer:PATH/` for another folder), or `clod default devcontainer auto`; `clod image new NAME devcontainer:PATH/+sudo` makes a variant on it (also a short name for a long spec); its packages come from the devcontainer config
- Environment variables: the project's `.envrc` (direnv, allowed on the host)
- Defaults: `clod default image|base|command|home|ports|ports-busy|clipboard|quiet|devcontainer VALUE` (`clipboard on` enables paste), or `CLOD_*` in a project's `.envrc`
- Instructions or settings for every home: `~/.clod/shared/` (`clod shared new` creates it)
- A slow home, or one `chown` fails in: a volume home (`clod home mv NAME vol:NAME`, login included; `clod home cp` copies)
- Ports: `clod -P 3000`; Docker access: `clod -i docker --docker` (root on the Docker host)

`clod env` shows a run's settings; `clod image`, `clod home` and `clod workspace` list those; `clod help` shows the rest. Read the docs (`https://raw.githubusercontent.com/DavidBoone/clod/master/docs/<page>`: `usage.md`, `images.md`, `configuration.md`, `shared-config.md`, `docker-socket.md`, `security.md`, `docker.md`) before advising beyond this.
