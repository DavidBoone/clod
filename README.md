# clod

Run Claude Code or Codex with no permission prompts, safely. `clod` starts the
agent in a throwaway Docker container that sees only the directory you run it
from and a home of its own. Inside, it works without stopping to ask: it
browses the web, runs whatever tools it needs and installs packages into its
home (npm, uv, pip in a venv), while the rest of your machine stays out of
reach.

> **What the agent can reach:** your project directory, its own home, and the
> network. Nothing else on your machine: a new home starts empty, with none of
> your keys or logins, and holds only what you give it. See
> [What the agent can reach](#what-the-agent-can-reach).

## Quick start

### 1. Get Docker running

**macOS:** [Colima](https://github.com/abiosoft/colima) is a lightweight Docker
runtime from Homebrew:

```bash
brew install colima docker
colima start --cpu 4 --memory 8
brew services start colima      # optional: start it at login
```

Docker Desktop works too. Colima shares your home folder with the containers
by default, so keep projects under it, or add other folders with
`colima start --mount /path:w`. A project outside the shared folders appears
as an empty `/workspace`, and clod warns at launch when that happens.

**Linux:** install Docker Engine with Docker's convenience script, then add
yourself to the `docker` group and log in again:

```bash
curl -fsSL https://get.docker.com | sh
sudo usermod -aG docker $USER
```

Check with `docker run --rm hello-world`. You also need git; clod itself is a
bash script and runs with the bash that macOS and Linux include.

### 2. Install clod

```bash
git clone https://github.com/DavidBoone/clod.git ~/.clod/src
~/.clod/src/clod install
```

`install` links `clod` into the first of `~/.local/bin`, `~/bin`,
`/opt/homebrew/bin` and `/usr/local/bin` that's on your `PATH` and writable,
or else creates `~/.local/bin` and prints the line that adds it to your
`PATH`. `clod install DIR` links it into a directory of your choice.

### 3. Run it

```bash
cd ~/code/some-project
clod
```

The first run builds the image, which takes a few minutes, and installs Claude
Code into the container's home. Claude Code then asks you to `/login`: open the
printed URL in your browser and paste the code back. Both happen once.

That's the whole setup. Every `clod` from here on starts in seconds with:

- your project mounted read-write at `/workspace`
- a home that persists between runs (`~/.clod/homes/default`), holding the
  login, settings, history and Claude Code itself, which updates itself
- Claude Code running with `--dangerously-skip-permissions`
- a statusline showing the home, image, model, tokens, context use, cache idle
  time and rate limits:

  ![The clod statusline: home and image, model and effort, tokens, lines changed, context use, idle time, and 5-hour and 7-day rate limits](docs/statusline.svg)
- instructions telling Claude about the container: what's mounted where and
  what persists

## Everyday use

```bash
clod                 # Claude Code
clod claude --resume # Claude Code with its own arguments
clod codex [args]    # Codex
clod bash | zsh      # a shell in the container
clod -i go           # the go image variant (see Image variants)
clod -H work         # the "work" home (see Homes and logins)
clod env             # show the home, image, login, ports, envrc and variables that would be used
clod default         # show your defaults (see Your defaults)
clod --help          # all commands and options
```

clod's options come before the command, and a command's own arguments go
after it, unchanged, options included. With no command, clod runs the default
command, Claude Code unless you change it. `--` ends clod's options and passes
the rest to the default command, so `clod -- --resume` is `clod claude
--resume`.

To update clod, `clod update` pulls its checkout in `~/.clod/src` and lists
what changed, one line per change. The next `clod` rebuilds the image if it
changed.

An image is otherwise kept as built. To refresh its system packages, Node and
whatever its variant downloads, rebuild it from scratch. When an image's files
have changed but you'd rather not wait for the build, `--skip-build` runs it
as it is:

```bash
clod update           # update clod
clod rebuild          # rebuild the image from scratch
clod --skip-build     # run the image as built
```

To reach a server the agent starts, such as a dev server on port 5173, publish
its port when you launch. Ports are written host first, container second, as
in Docker: the port on your machine, then the one inside. They're published on
your machine's localhost, and the server must listen on all interfaces
(`0.0.0.0`) inside the container:

```bash
clod -P 5173                 # localhost:5173 -> port 5173 in the container
clod -P 3000:5173            # localhost:3000 -> port 5173 in the container
clod -P 5173 -P 8080         # several
```

The container is removed when you exit; only the home and the workspace
persist.

`clod` refuses to run from your home directory or any directory above it, from
`~/.clod`, or from `~/.clod/homes` or anything under it, since the agent could
then read your credentials and every home's login. `clod --force` runs anyway.

Claude Code runs with `--dangerously-skip-permissions` unless its arguments
include `--permission-mode`, `--dangerously-skip-permissions` or
`--allow-dangerously-skip-permissions`, so `clod claude --permission-mode plan`
brings the prompts back. `clod claude -p "..." | ...` works without a terminal.

## Going further

Everything below is optional. It all lives under `~/.clod`:

```
~/.clod/
  src/                this repo
  config              your defaults for the launcher settings
  homes/<name>/       container homes
  images/<name>/      your image variants
  shared/             your shared config, mounted read-only as /etc/claude-code
```

### Git and GitHub

A new home has no git identity or GitHub login, so the agent's first commit
fails until you set them up. Do it once per home, in a shell in the container;
both persist in the home:

```bash
clod bash
git config --global user.name "Your Name"
git config --global user.email you@example.com
gh auth login            # then: gh auth setup-git, so git pushes use it
```

### Your own shared config

Claude Code reads managed settings and a managed `CLAUDE.md` from
`/etc/claude-code`, for every home. Until `~/.clod/shared` exists, clod mounts
this repo's [`shared/`](shared) there, which updates with `git pull`:

- `statusline.sh` is the statusline.
- `managed-settings.json` turns that statusline on.

To customise them, make your own copy and edit that:

```bash
clod new-shared       # copies the starter to ~/.clod/shared
```

From then on clod mounts `~/.clod/shared` in place of the starter, so keep
everything you want from it there. Updates to the repo's `shared/` reach you
only when you merge them in. Run `clod new-shared` again to compare: it lists
the starter's files that yours is missing or differs on, with the `diff`
command to see them, and `clod --force new-shared` replaces yours with the
starter, keeping yours as a backup. Put your own instructions for Claude in a
`CLAUDE.md` there, and any other
[managed settings](https://code.claude.com/docs/en/settings) in
`managed-settings.json` or `managed-settings.d/*.json`. Managed settings take
precedence over a home's own settings, so keep per-client config in the homes.

What Claude is told about the container (the mounts, what persists, the
`CLOD_*` variables) comes with the image, from [`container.md`](container.md),
so your `CLAUDE.md` only needs your own additions.

Changes to `statusline.sh` show up on its next refresh. To turn it off, remove
`statusLine` from `managed-settings.json`; homes can then set their own in
`~/.claude/settings.json`. To log each turn's cache reads and writes, create
`~/.claude/cache-turns.log` in a home (`touch`); the script appends to it
while it exists.

### Image variants

The `clod` image is a generic base: Claude Code, Codex, git, the GitHub CLI,
Python, Node 26, vim and everyday CLI tools. A variant puts a language,
compiler or browser on top. clod comes with these, in [`images/`](images):

| Variant   | Adds |
|-----------|------|
| `browser` | Chromium, fonts, and the system libraries Playwright's browsers need |
| `dotnet`  | .NET 10 SDK, from Microsoft's package repository |
| `go`      | the latest Go release, as of when the image is built |
| `lamp`    | PHP with common extensions, Composer, Apache and MariaDB |
| `python`  | uv, and the C toolchain and headers for native extensions |
| `rust`    | Rust's stable toolchain, via rustup, and the C toolchain |

```bash
clod -i go             # run the go variant
clod default image go  # run it from now on
clod images            # list the base, the bundled variants and yours
```

The first run builds `clod-go`; later runs reuse it until its `Dockerfile` or
the base image changes. To pick up a newer Go or Rust, rebuild it with
`clod -i go rebuild`. Rebuilding the base makes every variant rebuild on its
next use.

Your own variants go in `~/.clod/images/<name>/`, a directory holding a
`Dockerfile` that starts `FROM clod`, or `FROM` another variant. `clod
new-image` creates one:

```bash
clod new-image mine        # a starter Dockerfile, FROM clod
clod new-image mine go     # a copy of the go variant
clod new-image go          # your own copy of the bundled go, which then takes its place
```

For example:

```dockerfile
# ~/.clod/images/mine/Dockerfile
FROM clod-go
USER root
RUN apt-get install -y postgresql-client build-essential
USER claude
```

`build-essential` is there for npm or pip packages that compile native code on
install; most ship prebuilt binaries and don't need it.

`clod -i mine` builds `clod-go` if needed, then `clod-mine`, and
rebuilds each whenever a file in its directory or an image it is `FROM`
(in any stage) changes. A variant in `~/.clod/images` takes precedence over a bundled one of
the same name, so copying one there is how to customise it. Apt lists are kept
in the base, so variants can `apt-get install` without `apt-get update`. The
directory is the build context, so `COPY` works for files beside the
`Dockerfile`.

A variant can give Claude instructions about itself, such as where its tools
are. Put them in a Markdown file beside the `Dockerfile` and copy it into
`/etc/clod/.claude/rules/`, which Claude Code loads in every image built from
the variant:

```dockerfile
COPY CLAUDE.md /etc/clod/.claude/rules/mine.md
```

Images are never pulled at launch, so `-i` must name a variant or an image
already built locally.

### Homes and logins

Each home holds its own Claude login (`~/.claude/.credentials.json`), and that
file also stores the OAuth tokens of MCP servers logged into from the home. Use
one home per client or context to keep those apart: `/login` once in each, and
again when the login expires (about monthly).

```bash
clod -H work                    # ~/.clod/homes/work, created on first use
clod -H work-scratch --creds work  # a scratch home borrowing work's login
clod homes                      # list the homes and which have logins
```

A borrowed login's credentials file is mounted live, so token refreshes from
either home reach both. A copy would go stale at the next refresh, since
refresh tokens rotate.

Each option has a matching setting, which can come from your shell
environment, per project from an envrc (below), or as your defaults from
`~/.clod/config` (see Your defaults). An option wins over the shell, the shell
over the envrc, and the envrc over the config file:

| Setting      | Option | Default   | Meaning |
|--------------|--------|-----------|---------|
| `CLOD_HOME`  | `-H`   | `default` | Container home. A name means `~/.clod/homes/<name>`; anything with a `/` is a host path, relative to the current directory. |
| `CLOD_IMAGE` | `-i`   | `clod`    | A variant: yours in `~/.clod/images/` or a bundled one (`clod images` lists them), named `NAME` or `clod-NAME`. Or a local docker image built `FROM clod` (it needs the entrypoint, `claude` user and environment). |
| `CLOD_CREDS` | `--creds` | unset  | Borrow another home's Claude login (a home name or path, as for `CLOD_HOME`). Unset, the home keeps its own. |
| `CLOD_COMMAND` | the command | `claude` | What a bare `clod`, or `clod -- ARGS`, runs: `claude`, `codex`, `bash` or `zsh`. |
| `CLOD_PORTS` | `-P`   | unset     | Ports to publish on the host's `127.0.0.1`, comma- or space-separated: `8080` (the same on both sides), `host:container`, or `address:host:container` to publish on another address. |

In a direnv `.envrc`, `$PWD` is the `.envrc`'s directory, so
`export CLOD_HOME=$PWD/.clod-home` pins a project-local home. A home inside the
project directory is also visible under `/workspace`, login included, so
gitignore it.

### Your defaults

`clod default` shows and sets your defaults, kept in `~/.clod/config`:

```bash
clod default                    # show them all: yours, or built in
clod default image go           # CLOD_IMAGE=go
clod default command codex      # a bare clod runs Codex
clod default home work          # CLOD_HOME=work
clod default ports 5173         # CLOD_PORTS=5173
clod default image              # show one
clod default image --reset      # back to the built-in default
```

The keys are `image`, `command`, `home`, `creds` and `ports`. Values are
checked when you set them, and a home or login path is stored as an absolute
path. Your shell's settings and a project's envrc win over these defaults;
`clod env` shows what a run will actually use.

Inside the container the same variables hold what the launch resolved to:
`CLOD_HOME` is the home name (or `~/`-relative path), `CLOD_IMAGE` the image
tag (`clod`, `clod-<variant>`), and `CLOD_CREDS`, set only when a login is
borrowed, the home it came from.

### Per-project environment

`clod` looks up from the current directory for the nearest directory holding a
`.clod.envrc` or an `.envrc`, evaluates that one file on the host, and passes
the variables it sets into the container via `--env-file`. Like direnv, it stops
at the first match, so parent directories' files only count if the file pulls
them in (`source_up`). Run `clod env` to see which file is used and exactly what
would be passed.

- **`.envrc`** is used as is, through your host's direnv: it must be approved
  with `direnv allow`, and only exported variables count. Without direnv
  installed, `.envrc` is ignored.
- **`.clod.envrc`**, beside an `.envrc`, replaces it for the container. Use one
  when the `.envrc` would be wrong inside the container, or isn't approved. It
  is sourced in bash with every assignment exported, with direnv's commands
  (`source_env`, `source_up`, `dotenv`, ...) available when direnv is installed,
  and it doesn't need `direnv allow`. It's your own file, so keep it out of
  the project's repo, e.g. in `.git/info/exclude` or a global gitignore.

```sh
# .clod.envrc
source_env .envrc              # start from the project's .envrc
PGHOST=host.docker.internal    # but reach the host's Postgres from the container
```

Values are evaluated on the host but used in the container, so write them for
the container (`host.docker.internal`, not `localhost` or a host socket path).
`PATH` is never passed in. Launcher settings (`CLOD_HOME`, `CLOD_IMAGE`,
`CLOD_CREDS`, `CLOD_PORTS`, `CLOD_COMMAND`) set by the envrc aren't passed in
either; they act as defaults
for the launcher, and the same variable set in your shell wins. So a
`.clod.envrc` can pick the home and image for a project whose `.envrc` you
can't change. `--env-file` can't carry multi-line values, so variables holding
one are skipped with a warning. Changes take effect on the next `clod` launch.

The container also gets the host's timezone (`$TZ`, else `/etc/localtime`).

### Codex

Codex CLI installs from the official `@openai/codex` npm package into the home
the first time `codex` runs, and updates itself. Its login is per home.

```bash
clod codex login --device-auth  # first-time login
clod codex                      # start Codex
clod codex resume               # resume a session
```

Open the printed link in your browser and enter the code. Device code login
must be enabled in your ChatGPT security settings or by your workspace admin.
See [OpenAI's authentication documentation](https://learn.chatgpt.com/docs/auth).

Codex runs with `--dangerously-bypass-approvals-and-sandbox`, which turns off
its own sandbox and approval prompts inside the container, including for
resumed sessions.

### Linux hosts

Docker Engine on Linux keeps bind-mount ownership as is, so on a Linux host
`clod` builds the image with `claude` given your uid and gid, and files written
to the home and workspace belong to you. The image is therefore specific to the
user who built it. The launcher also maps `host.docker.internal` to the host,
which Docker Desktop and Colima provide on their own.

Rootless Docker and Podman are untested.

### Without the script

The images run with plain `docker build` and `docker run` too, for docker
options clod doesn't cover or to skip the script altogether:

```bash
docker run -it --rm -v ~/.clod/homes/default:/home/claude -v "$PWD":/workspace \
  -v ~/.clod/src/shared:/etc/claude-code:ro clod
```

[Running the image without clod](docs/without-clod.md) covers building it,
each piece of that command, a shell function to use in its place, variants,
and what you give up without the script.

## What the agent can reach

clod gives the agent a fixed reach instead of a stream of permission prompts.
Claude Code runs with `--dangerously-skip-permissions` and Codex with
`--dangerously-bypass-approvals-and-sandbox`, so within that reach they act
without asking:

- **The project directory**, read-write: the agent can change or delete any
  file in it, including any secrets the project keeps, such as a `.env` file.
- **Its home**, `~/.clod/homes/<name>` on your machine, not your own home
  directory. A new home starts empty: no SSH keys, git or GitHub credentials,
  or cloud logins. It holds only what you give it: the logins you make inside
  the container (`/login`, `! gh auth login`), files you copy in, and a login
  borrowed from another home with `--creds`. So the agent can push to git only
  if you've given that home credentials that allow it. Give each home only
  what its work needs.
- **The variables you pass in** from `.clod.envrc` or `.envrc`, tokens
  included.
- **The network**, including services on your machine through
  `host.docker.internal`.

Everything else on your machine is out of reach: your own home directory,
other projects, host processes and system files. In the container the agent
runs as an ordinary user, `claude`, so the image's system files are out of its
reach too, and anything it changes outside the home and project is discarded
on exit. `clod` refuses to use your home directory, `~/.clod` or the homes
directory as the project or as the container's home, unless run with
`--force`.

Claude Code installs on first run with
`curl -fsSL https://claude.ai/install.sh | bash`, and Codex from npm.

## License

[MIT](LICENSE)
