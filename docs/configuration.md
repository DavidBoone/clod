# Homes, settings and per-project environment

## Homes and logins

Each home holds its own Claude login (`~/.claude/.credentials.json`), and that
file also stores the OAuth tokens of MCP servers logged into from the home. Use
one home per client or context to keep those apart: `/login` once in each, and
again when the login expires (about monthly).

```bash
clod -H work                    # ~/.clod/homes/work, created on first use
clod home                       # list the homes and which have logins
```

A directory home is a folder under `~/.clod/homes`; deleting the folder
deletes the home and its login.

### Volume homes

`clod -H vol:NAME` uses the Docker volume `clod-home-NAME` as the home instead
of a directory on your machine. The volume lives on Docker's own disk (on
macOS, inside the Colima or Docker Desktop VM), so it avoids the shared-folder
file system: installs and caches in the home are faster, and `chown` and
`chmod` work as on any Linux disk. Docker creates the volume on first use,
starting it with the image's `/home/claude`.

Its files aren't visible from the host; `clod -H vol:NAME bash` gets you a
shell in it. `clod home` lists volume homes but shows `?` for their logins.

```bash
clod home rm vol:work           # delete clod-home-work, login included, after asking
clod --force home rm vol:work   # delete it without asking
```

In a terminal, `clod home rm` lists what it will delete and asks first;
without one, it needs `--force`. It deletes only volume homes, and Docker
won't remove one a container uses. `colima delete` and
`docker system prune --volumes` delete volume homes too.

## Settings

Each option has a matching setting, which can come from your shell
environment, per project from an `.envrc` (see [Per-project
environment](#per-project-environment)), or as your defaults from
`~/.clod/config` (see [Your defaults](#your-defaults)). An option wins over
the shell, the shell over the `.envrc`, and the `.envrc` over the config file.
A setting given empty still wins and means its default, so `clod -P ''` or
`CLOD_PORTS='' clod` publishes no ports even when the `.envrc` lists some:

| Setting      | Option | Default   | Meaning |
|--------------|--------|-----------|---------|
| `CLOD_HOME`  | `-H`   | `default` | Container home. A name means `~/.clod/homes/<name>`; anything with a `/` is a host path, relative to the current directory; `vol:NAME` is the Docker volume `clod-home-NAME` (see [Volume homes](#volume-homes)). |
| `CLOD_IMAGE` | `-i`   | `clod`    | A variant: yours in `~/.clod/images/` or a bundled one (`clod image` lists them), named `NAME` or `clod-NAME`, or variants combined as `A+B`. Or a local docker image built `FROM clod` (it needs the entrypoint, `claude` user and environment). |
| `CLOD_COMMAND` | the command | `claude` | What a bare `clod`, or `clod -- ARGS`, runs: `claude`, `codex`, `bash` or `zsh`. |
| `CLOD_PORTS` | `-P`   | unset     | Ports to publish on the host's `127.0.0.1`, comma- or space-separated: `8080` (the same on both sides), `host:container`, or `address:host:container` to publish on another address. |

In an `.envrc`, `$PWD` is the `.envrc`'s directory, so
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

The keys are `image`, `command`, `home` and `ports`. Values are checked when
you set them, and a home path is stored as an absolute path. Your shell's
settings and a project's `.envrc` win over these defaults; `clod env` shows
what a run will actually use.

Inside the container the same variables hold what the launch resolved to:
`CLOD_HOME` is the home name (or `~/`-relative path, or `vol:NAME`),
`CLOD_WORKSPACE` the workspace's path on the host (`~/`-relative) or
`vol:NAME`, and `CLOD_IMAGE` the image tag (`clod`, `clod-<variant>`, `clod-<a>.<b>`).

## Per-project environment

`clod` looks up from the workspace directory (the current directory, or the
one `-w` names) for the nearest `.envrc`, loads it
on the host through your direnv, and passes the variables it exports into the
container via `--env-file`. Only exported variables count: `FOO=bar` without
`export` isn't passed in. The file must be approved with `direnv allow`; without
direnv installed it is ignored. Like direnv, `clod` stops at the first match, so
parent directories' files only count if the file pulls them in (`source_up`).
Run `clod env` to see which file is used and exactly what would be passed.
`clod --scratch` reads none (see [A scratch
workspace](usage.md#a-scratch-workspace)), nor does a volume workspace (`-w vol:NAME`).

Values are evaluated on the host but used in the container, so write them for
the container (`host.docker.internal`, not `localhost` or a host socket path).
`PATH` is never passed in. Launcher settings (`CLOD_HOME`, `CLOD_IMAGE`,
`CLOD_PORTS`, `CLOD_COMMAND`) set by the `.envrc` aren't passed in either; they act
as defaults for the launcher, and the same variable set in your shell wins.
`--env-file` can't carry multi-line values, so variables holding one are skipped
with a warning. Changes take effect on the next `clod` launch.

The container also gets the host's timezone (`$TZ`, else `/etc/localtime`).
