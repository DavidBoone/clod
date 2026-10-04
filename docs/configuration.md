# Homes, settings and per-project environment

## Homes and logins

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

## Settings

Each option has a matching setting, which can come from your shell
environment, per project from an envrc (see [Per-project
environment](#per-project-environment)), or as your defaults from
`~/.clod/config` (see [Your defaults](#your-defaults)). An option wins over
the shell, the shell over the envrc, and the envrc over the config file:

| Setting      | Option | Default   | Meaning |
|--------------|--------|-----------|---------|
| `CLOD_HOME`  | `-H`   | `default` | Container home. A name means `~/.clod/homes/<name>`; anything with a `/` is a host path, relative to the current directory. |
| `CLOD_IMAGE` | `-i`   | `clod`    | A variant: yours in `~/.clod/images/` or a bundled one (`clod images` lists them), named `NAME` or `clod-NAME`, or variants combined as `A+B`. Or a local docker image built `FROM clod` (it needs the entrypoint, `claude` user and environment). |
| `CLOD_CREDS` | `--creds` | unset  | Borrow another home's Claude login (a home name or path, as for `CLOD_HOME`). Unset, the home keeps its own. |
| `CLOD_COMMAND` | the command | `claude` | What a bare `clod`, or `clod -- ARGS`, runs: `claude`, `codex`, `bash` or `zsh`. |
| `CLOD_PORTS` | `-P`   | unset     | Ports to publish on the host's `127.0.0.1`, comma- or space-separated: `8080` (the same on both sides), `host:container`, or `address:host:container` to publish on another address. |

In a direnv `.envrc`, `$PWD` is the `.envrc`'s directory, so
`export CLOD_HOME=$PWD/.clod-home` pins a project-local home. A home inside the
project directory is also visible under `/workspace`, login included, so
gitignore it.

## Your defaults

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
tag (`clod`, `clod-<variant>`, `clod-<a>.<b>`), and `CLOD_CREDS`, set only when a login is
borrowed, the home it came from.

## Per-project environment

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
