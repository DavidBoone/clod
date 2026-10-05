# Homes, settings and per-project environment

## Homes and logins

Each home holds its own Claude login (`~/.claude/.credentials.json`), and that
file also stores the OAuth tokens of MCP servers logged into from the home. Use
one home per client or context to keep those apart: `/login` once in each, and
again when the login expires (about monthly).

```bash
clod -H work                    # use ~/.clod/homes/work
clod home                       # list the homes and which have logins
clod home new work              # create a home without running anything
```

A directory home is a folder under `~/.clod/homes`, or the path `-H` names.
A run whose home doesn't exist asks, in a terminal, before creating it, so a
mistyped name doesn't start an empty home; without a terminal it fails, and
`clod home new` creates the home first.

### Volume homes

`clod -H vol:NAME` uses the Docker volume `clod-home-NAME` as the home instead
of a directory on your machine. The volume lives on Docker's own disk (on
macOS, inside the Colima or Docker Desktop VM), so it avoids the shared-folder
file system: installs and caches in the home are faster, and `chown` and
`chmod` work as on any Linux disk. A new volume home starts as a copy of the
image's `/home/claude`.

Its files aren't visible from the host; `clod -H vol:NAME bash` gets you a
shell in it. `clod home` lists volume homes but shows `?` for their logins.
`colima delete` and `docker system prune --volumes` delete volume homes.

### Deleting homes

```bash
clod home rm work               # delete ~/.clod/homes/work, login included, after asking
clod home rm vol:work           # delete the volume clod-home-work, after asking
clod --force home rm work       # delete it without asking
```

In a terminal, `clod home rm` lists what it will delete and asks first;
without one, it needs `--force`. It takes names and `vol:NAME`, not paths: a
home at a path is a folder you delete yourself. It won't delete a home a
container uses, even a stopped one (`docker ps -a` lists them).

### Copying and moving homes

`clod home cp` copies a home, login included, to a new one, and `clod home mv`
moves it. Either side can be a name, a path or `vol:NAME`, so a directory home
can become a volume home or the other way round:

```bash
clod home cp work vol:work      # copy ~/.clod/homes/work into the volume clod-home-work
clod home mv vol:work work2     # move the volume into ~/.clod/homes/work2
clod home mv work old-work      # rename a directory home
```

The copy runs in a container of the `clod` image, as `claude`, so its files
are `claude`'s (yours, for a directory). `mv` deletes the source only once the
copy is complete; a directory moved to a directory is renamed. Both refuse a
destination that exists, a source or destination a container uses, even a
stopped one, and `/`, your home folder, a folder above it, `~/.clod` and
`~/.clod/homes`.

## Settings

Each option has a matching setting. A setting can come from your shell
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
| `CLOD_PORTS_BUSY` | none | `skip` | What a run does with a `CLOD_PORTS` host port another running container publishes: `skip` leaves it out, `next` publishes the next free host port, `error` stops. A taken port given with `-P` always stops the run (see [Publishing ports](usage.md#publishing-ports)). |

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
clod default ports-busy next    # CLOD_PORTS_BUSY=next
clod default image              # show one
clod default image --reset      # back to the built-in default
```

The keys are `image`, `command`, `home`, `ports` and `ports-busy`. Values are checked when
you set them, and a home path is stored as an absolute path. Your shell's
settings and a project's `.envrc` win over these defaults; `clod env` shows
what a run will actually use.

Inside the container the same variables hold what the launch resolved to:
`CLOD_HOME` is the home name (or `~/`-relative path, or `vol:NAME`),
`CLOD_WORKSPACE` the workspace's path on the host (`~/`-relative) or
`vol:NAME`, and `CLOD_IMAGE` the image as `-i` names it (`clod`, `go`, `go+sudo`).

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

The container also gets the host's timezone (`$TZ`, else `/etc/localtime`). When
clod runs in a terminal, it passes in the terminal's `TERM_PROGRAM`,
`TERM_PROGRAM_VERSION`, `LC_TERMINAL`, `LC_TERMINAL_VERSION` and `COLORTERM`, where
they're set, so programs inside can tell what the terminal supports, such as links.
`TERM` stays Docker's `xterm`.
