# Running the image without clod

The `clod` script is a convenience. Everything it sets up is a `docker build`
and a `docker run`, which you can type yourself or wrap in a few lines of
shell. This page shows how, and what the script adds that you then do without.

## Build the image

Clone the repo and build it as it is:

```bash
git clone https://github.com/DavidBoone/clod.git ~/.clod/src
docker build -t clod ~/.clod/src
```

The build needs only `Dockerfile`, `entrypoint.sh` and `container.md` (what
Claude is told about the container), so you can instead copy those three files
into a directory of your own, change them as you like, and build from there.

On a Linux host, give the container's `claude` user your uid and gid, so files
it writes to the workspace and home belong to you:

```bash
docker build -t clod \
  --build-arg CLOD_UID=$(id -u) --build-arg CLOD_GID=$(id -g) ~/.clod/src
```

On macOS, Docker Desktop and Colima map ownership on their own, so the default
(1000) is fine.

The image keeps whatever it was built with. To pick up changes to the repo,
`git -C ~/.clod/src pull` and build again; to also refresh Debian's packages
and Node, add `--pull --no-cache`. The image a build replaces is left untagged;
`docker image prune` removes it.

## Run it

```bash
mkdir -p ~/.clod/homes/default
docker run -it --rm --pull=never \
  -v ~/.clod/homes/default:/home/claude \
  -v "$PWD":/workspace \
  -v ~/.clod/src/shared:/etc/claude-code:ro \
  -e TZ=Europe/London \
  clod
```

Each piece:

- **`-it`** gives the agent your terminal. Leave out `-t` when piping, as in
  `... clod claude -p "..." | less`.
- **`--rm`** deletes the container on exit. Only the two read-write mounts
  persist.
- **`--pull=never`** stops Docker from looking for an image called `clod` on
  Docker Hub when yours isn't built.
- **`-v ~/.clod/homes/default:/home/claude`** is the container's home. It holds
  the Claude and Codex logins, settings, history, and Claude Code itself, which
  installs there on first run and updates itself. Any directory works; create
  it first, since on Linux Docker creates a missing one owned by root. This is
  the same home the `clod` script uses by default, so the two can share it.
- **`-v "$PWD":/workspace`** is the project, read-write. The image's working
  directory is `/workspace`, and a new home is set to trust it.
- **`-v ~/.clod/src/shared:/etc/claude-code:ro`** is the managed config Claude
  Code reads for every home: the statusline and the settings that turn it on.
  Use your own copy (such as `~/.clod/shared`) to change them or to add a
  `CLAUDE.md` of your own instructions. Read-only, so the agent can't edit its
  own instructions. Leave it out and Claude runs without the statusline.
- **`-e TZ=...`** sets the timezone, which is otherwise UTC. Use your host's
  zone name, as found under `/usr/share/zoneinfo`.
- **`clod`** is the image. A variant goes here instead (see below).

On Linux, also add `--add-host=host.docker.internal:host-gateway`, so the agent
can reach services on your machine at `host.docker.internal`. Docker Desktop
and Colima provide that name already.

Arguments after the image go to its entrypoint. The first chooses what runs,
and the rest go to it:

| Arguments       | Runs |
|-----------------|------|
| (none)          | Claude Code |
| `claude [args]` | Claude Code with its own arguments |
| `codex [args]`  | Codex, installed into the home on first run |
| `bash`, `zsh`   | a shell |

Anything else also runs Claude Code, with all the arguments passed to it.
Claude Code gets `--dangerously-skip-permissions` unless its arguments include
`--permission-mode`, `--dangerously-skip-permissions` or
`--allow-dangerously-skip-permissions`. Codex always runs with
`--dangerously-bypass-approvals-and-sandbox`.

Other `docker run` options work as usual:

- `-p 127.0.0.1:5173:5173` publishes a port on your machine's localhost; a
  server in the container must listen on `0.0.0.0`. Without the `127.0.0.1:`,
  Docker publishes it on every network interface.
- `-e NAME=value` or `--env-file FILE` passes variables in.
- `-e CLOD_HOME=default -e CLOD_IMAGE=clod` shows the home and image in the
  statusline, which reads those variables.

## A shell function

Paste this into `~/.zshrc` or `~/.bashrc`. It works in both, and adds the Linux
pieces only on Linux:

```bash
clod() {
  local home="$HOME/.clod/homes/default" shared="$HOME/.clod/shared"
  local image="${CLOD_IMAGE:-clod}" dir="${PWD%/}/" tz tty= host=
  [ -d "$shared" ] || shared="$HOME/.clod/src/shared"
  tz="${TZ:-$(readlink /etc/localtime 2>/dev/null)}"
  tz="${tz##*zoneinfo/}"
  [ -t 0 ] && [ -t 1 ] && tty=-t
  [ "$(uname)" = Linux ] && host=--add-host=host.docker.internal:host-gateway
  case "$HOME/" in
    "$dir"*) echo "clod: refusing to mount $PWD as /workspace" >&2; return 1 ;;
  esac
  mkdir -p "$home"
  docker run -i $tty $host --rm --pull=never \
    -v "$home":/home/claude \
    -v "$PWD":/workspace \
    -v "$shared":/etc/claude-code:ro \
    -e TZ="$tz" -e CLOD_HOME=default -e CLOD_IMAGE="$image" \
    "$image" "$@"
}
```

Then, from a project directory:

```bash
clod                       # Claude Code
clod claude --resume       # Claude Code with its own arguments
clod codex                 # Codex
clod bash                  # a shell
CLOD_IMAGE=clod-mine clod  # a variant
```

It uses `~/.clod/shared` if you have one and the repo's `shared/` otherwise,
takes the timezone from `$TZ` or `/etc/localtime`, and adds `-t` only when
attached to a terminal. It refuses to run from your home directory or any
directory above it, which would show the agent everything in your home. If you
also have the `clod` script on your `PATH`, give the function another name.

## A variant by hand

A variant is a `Dockerfile` that starts `FROM clod`:

```dockerfile
# ~/.clod/images/mine/Dockerfile
FROM clod
USER root
RUN apt-get install -y postgresql-client
USER claude
```

Apt lists are kept in the base, so `apt-get install` needs no `apt-get update`.
Switch back to `USER claude` at the end, since the entrypoint and home expect
it. Build and tag it yourself:

```bash
docker build -t clod-mine ~/.clod/images/mine
```

and run it by putting `clod-mine` in place of `clod` in the run command. The
repo's [`images/`](../images) directory has examples for Go, Rust, Python,
.NET, PHP and browsers.

A variant can give Claude instructions about itself: copy a Markdown file into
`/etc/clod/.claude/rules/`, which the entrypoint has Claude Code load.

```dockerfile
COPY CLAUDE.md /etc/clod/.claude/rules/mine.md
```

A variant is built from the base as it was at the time, so rebuild it after
rebuilding the base.

## What you give up

The agent runs with its permission prompts off. What it can reach is what you
mount and the network, so the mounts are the whole of its limits: anything in
the home or workspace, such as SSH keys or tokens, is open to it.

Without the script:

- **The directory guard.** `clod` refuses to mount your home directory, a
  directory above it, `~/.clod` or a home's directory as the workspace, and
  checks the container's home the same way. Nothing stops `docker run`, so
  never run it with `-v ~:/workspace` or from your home directory: the agent
  could read every credential you have. The function above checks only for
  your home directory and the directories above it.
- **Builds.** `clod` rebuilds the base and variants when their files, or the
  image they are `FROM`, change, builds a variant's base first, and prunes the
  images builds replace. The bundled variants, `rebuild`, `images` and
  `new-image` go too.
- **Settings.** Homes by name (`-H`), borrowed logins (`--creds`), the
  project's `.clod.envrc` or `.envrc` passed in as variables, ports published
  on localhost from a short form (`-P`), and defaults kept with `clod default`.
- **Maintenance.** `clod update`, `clod install`, and the check that Docker is
  installed and running before anything else.
