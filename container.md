# Environment

Running in a disposable Docker container (`docker run --rm`) started by the user's `clod` launcher (https://github.com/DavidBoone/clod), a bash script on their macOS (Colima or Docker Desktop) or Linux host. Image is `clod` or a variant built `FROM clod`.

- `/home/claude` ← host `~/.clod/homes/<name>` (or another path chosen by `CLOD_HOME`), or, when `$CLOD_HOME` is `vol:<name>`, the Docker volume `clod-home-<name>` on Docker's own disk
- `/workspace` ← the host directory `$CLOD_WORKSPACE` (the one `clod` was run from, or `clod -w PATH`): the user's real project, not a scratch dir. When `$CLOD_WORKSPACE` is `vol:<name>`, it's the Docker volume `clod-workspace-<name>`, kept between runs but not in a host folder. When `$CLOD_SCRATCH` is set, it's an empty volume (`clod --scratch`), discarded with the container, so anything worth keeping goes in the home or to a remote
- `/etc/claude-code` ← `~/.clod/shared`, or clod's own `shared/` until that exists (read-only here): managed settings, the statusline, and the user's own instructions in its `CLAUDE.md`, if any
- `/etc/clod/.claude/rules/` holds this file and any instructions the image's variants add
- `$CLOD_HOME`, `$CLOD_WORKSPACE` and `$CLOD_IMAGE` name this run's home, workspace and image; a `~` in a path there is the user's home on the host
- `$CLOD_PORTS`, when set, lists the container ports published to the user's machine, comma-separated (`5000,8080`); a server must listen on `0.0.0.0` to be reachable through them
- The host is `host.docker.internal`. The Docker socket is mounted only with `clod --docker` (then `$CLOD_HOST_WORKSPACE` is the project's host path, unset for a volume or scratch workspace)

When the home and workspace are virtiofs mounts (`mount` shows it; usual on a macOS host), GNU `sed -i` leaves the file mode 600 (it restores the mode through an ACL, which the mount stores but doesn't apply); edit files with your own tools or `perl -i` instead.

Only `/home/claude` and (unless scratch) `/workspace` persist. System packages (apt, `/usr/local`) belong in an image variant's Dockerfile, which the user maintains. `npm install -g` goes to `~/.local` and persists, Python packages go in a venv, and single-file tools can go in `~/.local/bin`.

# Changing the container

You can't run `clod` or see the host's `~/.clod`; the user changes these on the host, and they take effect on the next `clod` run. When something about the container is in the way, say which of these to change, with the exact lines:

- Packages or system setup: a variant, `~/.clod/images/<name>/Dockerfile` (`ARG BASE=clod` / `FROM $BASE`, `USER root` … `USER claude`), run with `clod -i <name>`; `clod image new <name>` starts one. Variants combine (`-i go+<name>`), and clod rebuilds them when their files change. For root while running, the bundled `sudo` variant
- Environment variables for the container: `.envrc` in the project (`export FOO=bar`), loaded by direnv on the host, where it must be allowed
- Defaults for every run: `clod default image|command|home|ports VALUE`; for one project, `CLOD_IMAGE`, `CLOD_PORTS` and so on in its `.envrc`
- Instructions or managed settings for every home: `~/.clod/shared/` (`clod shared new` creates it)
- Ports: `clod -P 3000` or `CLOD_PORTS`; Docker access: `clod -i docker --docker`, which gives the agent root on the Docker host

On the host, `clod env` shows the settings a run would use; `clod image`, `clod home` and `clod workspace` list the images, homes and volume workspaces, and `clod --help` lists the rest. The full docs are in the repo's `docs/`: `usage.md`, `images.md`, `configuration.md`, `shared-config.md`, `docker-socket.md`, `security.md`, `docker.md`. Read them (`https://raw.githubusercontent.com/DavidBoone/clod/master/docs/<page>`) before advising on clod beyond this summary.
