# clod

Run Claude Code or Codex with no permission prompts, safely. `clod` starts the
agent in a throwaway Docker container that sees only the directory you run it
from and a home of its own. Inside, it's unrestricted: it browses the web,
installs packages and runs whatever tools it needs without stopping to ask,
while the rest of your machine stays out of reach.

> **What the agent can reach:** your project directory, its own home with
> whatever logins and keys you give it, and the network. Nothing else on your
> machine. See [What the agent can reach](#what-the-agent-can-reach).

## Quick start

### 1. Get Docker running

**macOS:** [Colima](https://github.com/abiosoft/colima) is a lightweight Docker
runtime from Homebrew:

```bash
brew install colima docker
colima start --cpu 4 --memory 8
brew services start colima      # optional: start it at login
```

Docker Desktop works too.

**Linux:** install Docker Engine with Docker's convenience script, then add
yourself to the `docker` group and log in again:

```bash
curl -fsSL https://get.docker.com | sh
sudo usermod -aG docker $USER
```

Check with `docker run --rm hello-world`. You also need git.

### 2. Install clod

```bash
git clone https://github.com/DavidBoone/clod.git ~/.clod/src
mkdir -p ~/.local/bin
ln -s ~/.clod/src/clod ~/.local/bin/clod
```

`~/.local/bin` must be on your `PATH`. On macOS it isn't by default; add
`export PATH="$HOME/.local/bin:$PATH"` to `~/.zshrc` and open a new terminal.

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
  ```
  ⌂ default@clod  ✦ Opus ⚡high  ↑48.2k ↓12.1k  +120/-35  ◔ ▰▰▰▱▱ 42%  ⏱ 3:07  5h ▰▱▱▱▱ 12%/40%
  ```
- instructions telling Claude about the container: what's mounted where and
  what persists

## Everyday use

```bash
clod                 # Claude Code
clod --resume        # Claude Code with your own args (permission prompts stay off)
clod codex [args]    # Codex
clod bash | zsh      # a shell in the container
clod env             # show the home, image, login, envrc and variables that would be used
```

To update clod, pull the repo. The next `clod` rebuilds the image if it
changed.

```bash
git -C ~/.clod/src pull
```

The container is removed when you exit; only the home and the workspace
persist.

`clod` refuses to run from your home directory or any directory above it, from
`~/.clod`, or from `~/.clod/homes` or anything under it, since the agent could
then read your credentials and every home's login. `clod --force` runs anyway;
`--force` must be the first argument, and later arguments go to the agent
unchanged.

Claude Code runs with `--dangerously-skip-permissions` unless its arguments
include `--permission-mode`, `--dangerously-skip-permissions` or
`--allow-dangerously-skip-permissions`, so `clod --permission-mode plan` brings
the prompts back. `clod -p "..." | ...` works without a terminal.

## Going further

Everything below is optional. It all lives under `~/.clod`:

```
~/.clod/
  src/                this repo
  homes/<name>/       container homes
  images/<name>/      your image variants
  shared/             your shared config, mounted read-only as /etc/claude-code
```

### Your own shared config

Claude Code reads managed settings and a managed `CLAUDE.md` from
`/etc/claude-code`, for every home. Until `~/.clod/shared` exists, clod mounts
this repo's [`shared/`](shared) there, which updates with `git pull`:

- `CLAUDE.md` tells Claude about the clod container.
- `statusline.sh` is the statusline.
- `managed-settings.json` turns that statusline on.

To customise them, copy them out and edit your copy:

```bash
cp -R ~/.clod/src/shared ~/.clod/shared
```

From then on clod mounts `~/.clod/shared`, and updates to the repo's `shared/`
reach you only when you merge them in (`diff -r ~/.clod/src/shared
~/.clod/shared`). Add your own instructions to its `CLAUDE.md`, and any other
[managed settings](https://code.claude.com/docs/en/settings) to
`managed-settings.json` or `managed-settings.d/*.json`. Managed settings take
precedence over a home's own settings, so keep per-client config in the homes.

Changes to `statusline.sh` show up on its next refresh. To turn it off, remove
`statusLine` from `managed-settings.json`; homes can then set their own in
`~/.claude/settings.json`. The script logs each turn's cache reads and writes
to `~/.claude/cache-turns.log`.

### Image variants

The `clod` image is a generic base: Claude Code, Codex, git, the GitHub CLI,
Python, Node 26, vim and everyday CLI tools. A variant puts a language,
compiler or browser on top. clod comes with these, in [`images/`](images):

| Variant   | Adds |
|-----------|------|
| `browser` | the system libraries Playwright's Chromium needs |
| `dotnet`  | .NET 10 SDK, from Microsoft's package repository |
| `go`      | the latest Go release, as of when the image is built |
| `lamp`    | PHP with common extensions, Composer, Apache and MariaDB |
| `python`  | uv, and the C toolchain and headers for native extensions |
| `rust`    | Rust's stable toolchain, via rustup, and the C toolchain |

```bash
CLOD_IMAGE=go clod
```

The first run builds `clod-go`; later runs reuse it until its `Dockerfile` or
the base image changes. To pick up a newer Go or Rust, remove the image
(`docker rmi clod-go`) and the next run rebuilds it.

Your own variants go in `~/.clod/images/<name>/`, a directory holding a
`Dockerfile` that starts `FROM clod`, or `FROM` another variant:

```dockerfile
# ~/.clod/images/mine/Dockerfile
FROM clod-go
USER root
RUN apt-get install -y postgresql-client build-essential
USER claude
```

`build-essential` is there for npm or pip packages that compile native code on
install; most ship prebuilt binaries and don't need it.

`CLOD_IMAGE=mine clod` builds `clod-go` if needed, then `clod-mine`, and
rebuilds each whenever a file in its directory or the image it is `FROM`
changes. A variant in `~/.clod/images` takes precedence over a bundled one of
the same name, so copying one there is how to customise it. Apt lists are kept
in the base, so variants can `apt-get install` without `apt-get update`. The
directory is the build context, so `COPY` works for files beside the
`Dockerfile`.

Images are never pulled at launch, so `CLOD_IMAGE` must name a variant or an
image already built locally.

### Homes and logins

Each home holds its own Claude login (`~/.claude/.credentials.json`), and that
file also stores the OAuth tokens of MCP servers logged into from the home. Use
one home per client or context to keep those apart: `/login` once in each, and
again when the login expires (about monthly).

```bash
CLOD_HOME=work clod                          # ~/.clod/homes/work
CLOD_HOME=work-scratch CLOD_CREDS=work clod  # a scratch home borrowing work's login
```

A borrowed login's credentials file is mounted live, so token refreshes from
either home reach both. A copy would go stale at the next refresh, since
refresh tokens rotate.

The launcher reads these settings from your shell environment, for a one-off
as above, or per project from an envrc (below):

| Variable     | Default   | Meaning |
|--------------|-----------|---------|
| `CLOD_HOME`  | `default` | Container home. A name means `~/.clod/homes/<name>`; anything with a `/` is a host path, relative to the current directory. |
| `CLOD_IMAGE` | `clod`    | A variant name from `~/.clod/images/`, or a local docker image built `FROM clod` (it needs the entrypoint, `claude` user and environment). |
| `CLOD_CREDS` | unset     | Borrow another home's Claude login (a home name or path, as for `CLOD_HOME`). Unset, the home keeps its own. |

In a direnv `.envrc`, `$PWD` is the `.envrc`'s directory, so
`export CLOD_HOME=$PWD/.clod-home` pins a project-local home. A home inside the
project directory is also visible under `/workspace`, login included, so
gitignore it.

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
`CLOD_CREDS`) set by the envrc aren't passed in either; they act as defaults
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

### Plain docker run

Without the script, e.g. to expose a port for a dev server:

```bash
docker run -it --rm -p 5206:5206 -v ~/.clod/homes/default:/home/claude -v .:/workspace clod
```

On Linux, add `--add-host=host.docker.internal:host-gateway` to reach host
services.

## Requirements

- macOS with Colima or Docker Desktop, or Linux with Docker Engine
- Docker 23 or newer (BuildKit)
- bash 3.2 or newer, and `shasum` or `sha1sum`, which macOS and Linux include

## What the agent can reach

clod gives the agent a fixed reach instead of a stream of permission prompts.
Claude Code runs with `--dangerously-skip-permissions` and Codex with
`--dangerously-bypass-approvals-and-sandbox`, so within that reach they act
without asking:

- **The project directory**, read-write: the agent can change or delete any
  file in it, and commit and push with whatever git credentials the home
  holds.
- **Its home**: the Claude and Codex logins, MCP tokens, and anything else you
  put there, such as SSH keys or API tokens. Give each home only what its work
  needs.
- **The network**, including services on your machine through
  `host.docker.internal`.

Everything else on your machine is out of reach: your own home directory,
other projects, host processes and system files. The container's system is
discarded on exit, so whatever the agent installs or breaks there goes with
it. `clod` refuses to mount your home directory, `~/.clod` or the homes as the
project, unless run with `--force`.

Claude Code installs on first run with
`curl -fsSL https://claude.ai/install.sh | bash`, and Codex from npm.

## License

[MIT](LICENSE)
