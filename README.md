# clod

A Docker image for running Claude Code or Codex CLI in an ephemeral container,
and `clod`, a launcher script that builds it and runs it on the current
directory. Claude Code is the default.

> **The container is not a sandbox.** Both agents run with their permission
> prompts disabled, and the agent can read and write everything in the mounted home and workspace and reach the
> network. See [Security](#security).

## Requirements

- macOS with [Colima](https://github.com/abiosoft/colima) or Docker Desktop, or
  Linux with Docker Engine (rootful; rootless Docker and Podman are untested)
- Docker 23 or newer (BuildKit)
- bash 3.2 or newer (the `/bin/bash` macOS ships is fine), and `shasum` or `sha1sum`

## Usage

Clone this repo and symlink the [`clod`](clod) script onto your `PATH`:

```bash
git clone https://github.com/DavidBoone/clod.git ~/.clod/src
ln -s ~/.clod/src/clod ~/.local/bin/clod
```

To update clod, pull the repo; the next `clod` rebuilds the image if
`Dockerfile` or `entrypoint.sh` changed. Claude Code and Codex update
themselves.

```bash
git -C ~/.clod/src pull
```

Then from any project directory:

```bash
clod                 # Claude Code, with --dangerously-skip-permissions
clod --resume        # Claude Code with your own args (permission prompts stay off)
clod codex [args]    # Codex
clod bash | zsh      # a shell
clod env             # show the home, image, login, envrc and variables that would be used
clod --force ...     # any of the above, from a directory clod otherwise refuses
```

The current directory is mounted read-write as `/workspace`, so `clod` refuses
to run from your home directory or any directory above it, from `~/.clod`, or
from `~/.clod/homes` or anything under it: the agent could read your
credentials and every home's login. `~/.clod/src`, `~/.clod/images/<name>` and
`~/.clod/shared` are fine. `clod --force` runs anyway; `--force` must be the
first argument, and later arguments go to the agent unchanged.

The container's entire home directory is persisted on the host, by default in
`~/.clod/homes/default`. Claude Code and Codex install themselves there on first
run and keep their config and updates there. On the first run Claude Code asks
you to `/login`; open the printed URL in your host browser.

A fresh home skips Claude Code's first-run prompts (onboarding, folder trust,
bypass-permissions warning); the entrypoint seeds `.claude.json` and
`settings.json` when they are missing.

Claude Code runs with `--dangerously-skip-permissions` unless its arguments
include `--permission-mode`, `--dangerously-skip-permissions` or
`--allow-dangerously-skip-permissions`, so `clod --permission-mode plan` brings
the prompts back. Without a terminal (`clod -p "..." | ...`) the container runs
without a TTY.

The launcher builds the `clod` image itself from the script's directory (follow
the symlink back to this repo), and rebuilds it when `Dockerfile` or
`entrypoint.sh` change.

```
~/.clod/
  homes/<name>/       container homes
  images/<name>/      image variants
  shared/             mounted read-only as /etc/claude-code in every container
```

### Homes, images and logins

The launcher reads these from your shell environment, for a one-off
(`CLOD_HOME=work clod`) or per project via a host-side direnv `.envrc`
(`export CLOD_IMAGE=dotnet`):

| Variable     | Default                    | Meaning |
|--------------|----------------------------|---------|
| `CLOD_HOME`  | `default`                  | Container home. A name means `~/.clod/homes/<name>`; anything with a `/` is a host path, relative to the current directory. |
| `CLOD_IMAGE` | `clod`                     | A variant name from `~/.clod/images/`, or any docker image built `FROM clod` (it needs the entrypoint, `claude` user and environment). |
| `CLOD_CREDS` | unset                      | Borrow another home's Claude login (a home name or path, as for `CLOD_HOME`). Unset, the home keeps its own. |

In a direnv `.envrc`, `$PWD` is the `.envrc`'s directory, so
`export CLOD_HOME=$PWD/.clod-home` pins a project-local home. A home inside
the project directory is also visible under `/workspace`, login included, so
gitignore it.

Inside the container the same variables hold what the launch resolved to:
`CLOD_HOME` is the home name (or `~/`-relative path), `CLOD_IMAGE` the image
tag (`clod`, `clod-<variant>`), and `CLOD_CREDS`, set only when a login is
borrowed, the home it came from.

### Image variants

The `clod` image is a generic base: Claude Code, Codex, Python, Node 26,
Playwright's browser libraries and common CLI tools. Put a stack on top as a
variant, a directory holding a `Dockerfile` that starts `FROM clod`:

```dockerfile
# ~/.clod/images/dotnet/Dockerfile
FROM clod
USER root
RUN apt-get install -y dotnet-sdk-10.0
USER claude
```

`CLOD_IMAGE=dotnet clod` builds it as `clod-dotnet` on first use and rebuilds it
whenever a file in that directory or the image it is `FROM` changes. A variant
can build on another with `FROM clod-<name>`; the launcher builds the chain in
order. Apt lists are kept in the base, so variants can `apt-get install`
without `apt-get update`. The directory is the build context, so `COPY` works
for files beside the `Dockerfile`.

Images are never pulled at launch, so `CLOD_IMAGE` must name a variant or an
image already built locally.

### Logins

Each home holds its own Claude login (`~/.claude/.credentials.json`), and that
file also stores the OAuth tokens of MCP servers logged into from the home. Use
one home per client or context to keep those apart: `/login` once in each, and
again when the login expires (about monthly).

For a scratch home, borrow an existing login instead of logging in again:

```bash
CLOD_HOME=work-scratch CLOD_CREDS=work clod
```

The owner's credentials file is mounted live, so token refreshes from either
home reach both. A copy would not work: refresh tokens rotate, so a copied
login goes stale at the next refresh.

### Shared config

`~/.clod/shared/` is mounted read-only at `/etc/claude-code`, where Claude Code
reads managed settings (`managed-settings.json`, `managed-settings.d/*.json`)
and a managed `CLAUDE.md`. Use it for config every home should have.

```
~/.clod/shared/
  managed-settings.json   settings for every home
  statusline.sh           the statusline those settings run
  CLAUDE.md               instructions for every home
```

The repo's [`shared/`](shared) folder is a starter set of these files:

- `CLAUDE.md` tells Claude about the clod container: what's mounted where and
  what persists.
- `statusline.sh` is a statusline (below).
- `managed-settings.json` turns that statusline on for every home.

Copy them into your shared config on the host, from this repo (`-n` keeps any
files you already have):

```bash
mkdir -p ~/.clod/shared && cp -n shared/* ~/.clod/shared/
```

The copies are yours to customize, and later changes in this repo don't reach
them.

#### Statusline

The starter statusline shows the clod home, borrowed login and
image, then model and effort, tokens in and out, lines changed, context use,
idle time against the prompt cache's one-hour lifetime, 5-hour and 7-day rate
limits, and a warning when a turn missed the prompt cache:

```
⌂ work@clod-dotnet  ✦ Opus ⚡high  ↑48.2k ↓12.1k  +120/-35  ◔ ▰▰▰▱▱ 42%  ⏱ 3:07  5h ▰▱▱▱▱ 12%/40%
```

Changes to `~/.clod/shared/statusline.sh` show up on the next refresh. To turn it
off, remove `statusLine` from `managed-settings.json`. To let homes choose their
own statusline instead, leave it out of managed settings and set `statusLine` in
a home's `~/.claude/settings.json`. The script needs `jq` (in the image) and
logs each turn's cache reads and writes to `~/.claude/cache-turns.log`.

Managed settings take precedence over a home's own settings, so keep
per-client config in the homes.

### Linux hosts

Docker Engine on Linux keeps bind-mount ownership as is, so on a Linux host
`clod` builds the image with `claude` given your uid and gid, and files written
to the home and workspace belong to you. The image is therefore specific to the
user who built it. The launcher also maps `host.docker.internal` to the host,
which Docker Desktop and Colima provide on their own.

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
can't change.
`--env-file` can't carry multi-line values, so variables holding one are
skipped with a warning. Changes take effect on the next `clod` launch.

The container also gets the host's timezone (`$TZ`, else `/etc/localtime`).

### Plain docker run

Without the script, e.g. to expose a port for a dev server:

```bash
docker run -it --rm -p 5206:5206 -v ~/.clod/homes/default:/home/claude -v .:/workspace clod
```

On Linux, add `--add-host=host.docker.internal:host-gateway` to reach host
services.

## Codex

Codex CLI is installed from the official `@openai/codex` npm package into
`~/.local` the first time `codex` runs, so it can update itself.

```bash
clod codex login --device-auth  # First-time login
clod codex                      # Start Codex
clod codex resume               # Resume a session
```

Open the printed link in your host browser and enter the code. Device code login
must be enabled in your ChatGPT security settings or by your workspace admin.
No callback port is needed. See [OpenAI's authentication documentation](https://learn.chatgpt.com/docs/auth).

Arguments after `codex` are passed directly to Codex.
Codex runs with `--dangerously-bypass-approvals-and-sandbox`, disabling its internal
sandbox and approval prompts inside the Docker container, including resumed sessions.
It can modify everything writable inside the container, including bind mounts.

Both agents share the home. Codex login is per home. The workspace and home mounts persist
after `--rm`; other container changes do not.

## Security

The container keeps the agents off your host filesystem outside the mounts, but
it is a convenience boundary, not a sandbox against a misbehaving agent:

- Claude Code runs with `--dangerously-skip-permissions` (unless you choose a
  permission mode) and Codex with `--dangerously-bypass-approvals-and-sandbox`.
- The workspace and the whole home are mounted read-write. `clod` refuses
  workspaces that would expose your host home or the clod homes unless run
  with `--force`. Anything you keep in a home, such as SSH keys or API
  tokens, is available to the agent.
- The container has normal outbound network access and can reach services on
  the host through `host.docker.internal`.
- Claude Code is installed on first run with
  `curl -fsSL https://claude.ai/install.sh | bash`, and Codex from npm.

## License

[MIT](LICENSE)
