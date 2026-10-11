# Image variants

The `clod` image is a generic base: Claude Code, Codex, git, the GitHub CLI,
Python, Node 26, vim and everyday CLI tools. A variant puts a language,
compiler or browser on top. clod comes with these, in [`images/`](../images):

| Variant   | Adds |
|-----------|------|
| `browser` | Chromium, fonts, and the system libraries Playwright's browsers need |
| `docker`  | the Docker CLI, with buildx and compose, for use with `--docker` |
| `dotnet`  | .NET 10 SDK, from Microsoft's package repository |
| `go`      | the latest Go release, as of when the image is built |
| `lamp`    | PHP with common extensions, Composer, Apache and MariaDB |
| `python`  | uv, and the C toolchain and headers for native extensions |
| `rust`    | Rust's stable toolchain, via rustup, and the C toolchain |
| `sudo`    | passwordless `sudo`, for installing packages mid-session (gone when the container exits) |

```bash
clod -i go               # run the go variant
clod default image go    # run it from now on
clod image               # list the base, the bundled variants and yours, and which are stale
clod image show go+sudo  # how an image is built: the images it's FROM, and their Dockerfiles
clod image clean go      # remove the built image; the next clod -i go builds it again
clod image prune         # remove the stale images, which their next run rebuilds anyway
```

The first run builds the image (`clod-go`, to Docker); later runs reuse it
until its `Dockerfile` or the base image changes. To pick up a newer Go or Rust, rebuild it with
`clod image rebuild go`. Rebuilding the base makes every variant rebuild on its
next use.

Variants combine with `+`: `clod -i browser+dotnet` builds `browser`, then the
`dotnet` variant on top of it. They build in the order given, which matters
only when two variants change the same files. A combination rebuilds, and is
set as a default, like any variant:

```bash
clod -i browser+dotnet          # .NET with a browser, for testing a web app
clod default image go+sudo      # Go, with passwordless sudo
```

`-i +NAME` puts `NAME` on top of the image the run would use without `-i`,
the one `CLOD_IMAGE` (shell, `.envrc` or `clod default image`) or
`CLOD_DEVCONTAINER=auto` picks: with `CLOD_IMAGE=go`, `clod -i +sudo` runs
`go+sudo`. It is an error when that image already has `NAME`. Only `-i` takes
a leading `+`; `CLOD_IMAGE` can't.

Every variant after the first must take its base as an argument; the bundled
ones all do, starting with:

```dockerfile
ARG BASE=clod
FROM $BASE
```

Your own variants go in `~/.clod/images/<name>/`, a directory holding a
`Dockerfile` built `FROM clod`, or `FROM` another variant. Built `FROM $BASE`,
as above, it combines with the others. `clod image new` creates one:

```bash
clod image new mine          # a starter Dockerfile, FROM $BASE
clod image new mine go       # a copy of the go variant
clod image new mine go+sudo  # a starter Dockerfile, built on go+sudo
clod image new go            # your own copy of the bundled go, which then takes its place
clod image diff go           # how yours differs from the bundled go, after either changes
clod image edit mine         # open its Dockerfile in $VISUAL, $EDITOR or vi
clod image edit mine CLAUDE.md  # or another file beside it, created if need be
clod image edit mine --build    # then build it, to see a mistake now
```

`clod image edit` with no name edits the variant `-i` or `CLOD_IMAGE` selects.
A file beside the `Dockerfile` reaches the image only if the `Dockerfile`
copies it in, as `COPY CLAUDE.md /etc/clod/.claude/rules/mine.md` does.
It edits only your own variants: a bundled one needs `clod image new NAME`
first, and a combination is edited one variant at a time. The next run picks up
the change and rebuilds.

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

A variant can be `FROM` a combination by its Docker name, which joins the
variants with dots: `browser+dotnet` is `FROM clod-browser.dotnet`. clod builds
the combination first, and rebuilds yours when any variant in it changes. That
keeps your own additions on top of bundled variants without copying their
install steps.

`clod -i mine` builds `go` if needed, then `mine`, and
rebuilds each whenever a file in its directory or an image it is `FROM`
(in any stage) changes. A variant in `~/.clod/images` takes precedence over a bundled one of
the same name, so copying one there is how to customise it. Apt lists are kept
in the base, so variants can `apt-get install` without `apt-get update`, and
packages install without their docs, man pages or translations
(the base is `debian:trixie-slim`; see [The base](#the-base) to keep them). The
directory is the build context, so `COPY` works for files beside the
`Dockerfile`.

A variant can give Claude instructions about itself, such as where its tools
are. Put them in a Markdown file beside the `Dockerfile` and copy it into
`/etc/clod/.claude/rules/`, which Claude Code loads in every image built from
the variant:

```dockerfile
COPY CLAUDE.md /etc/clod/.claude/rules/mine.md
```

Node is in the base for the agents' own tooling: Codex installs with npm, and
many MCP servers run with `npx`. Claude Code doesn't need it. The base gets Node
26 from NodeSource's repository, and a project that needs another major gets it
from a variant that edits that repository and reinstalls:

```dockerfile
USER root
RUN sed -i 's/node_[0-9]*\.x/node_22.x/' /etc/apt/sources.list.d/nodesource.sources \
    && apt-get update && apt-get install -y --allow-downgrades nodejs
USER claude
```

Images are never pulled at launch, so `-i` must name a variant or an image
already built locally.

## The base

`CLOD_BASE` picks the Debian image the base is built on, from the same
`Dockerfile`:

```bash
clod default base full    # debian:trixie, built as clod:full
clod default base slim    # debian:trixie-slim, built as clod (the default)
```

`slim` installs packages without their docs, man pages or translations; `full`
keeps them (the `man` command itself isn't installed). The two are separate
images, `clod` and `clod:full`, so switching between them builds each only
once. `clod image` lists both, `clod env` shows which a
run uses, and `-i clod` names whichever `CLOD_BASE` picks. Variants whose
`ARG BASE` defaults to `clod`, the bundled ones and those `clod image new`
starts, are built on it, keeping their names (`clod-go`), so switching rebuilds
them on their next run; a variant built on another variant gets it through
that one. A variant whose `Dockerfile` says `FROM clod` stays on the slim base,
and one whose `ARG BASE` defaults to another image stays on that.
`CLOD_BASE` doesn't apply to a devcontainer, which is its own base.

## Devcontainers

A project with a [devcontainer](https://containers.dev) can run in it: clod
builds the devcontainer with the [devcontainer
CLI](https://github.com/devcontainers/cli), then the base image's layer on top,
so the agent gets the project's toolchain and clod's container alike. It needs
the CLI on your machine (`npm install -g @devcontainers/cli`); nothing else
does.

```bash
clod -i devcontainer               # .devcontainer/devcontainer.json, or .devcontainer.json
clod -i devcontainer:python        # .devcontainer/python/devcontainer.json
clod -i devcontainer+sudo          # a variant on top, as in any combination
clod -i devcontainer:app/          # app/'s, from the folder above it
clod default devcontainer auto     # run a project's devcontainer whenever it has one
```

`devcontainer` means the workspace's, found in the directory clod mounts as
`/workspace` (`-w`), not above it. To run one from somewhere else, such as a
folder holding several projects, name it by its path, relative to the current
directory: anything with a `/` (or starting with `.` or `~`) is a path, to a
project (`devcontainer:app/`), a config folder
(`devcontainer:app/.devcontainer/python`) or a config file. `/workspace` is
still the directory clod runs in, and the image is the one `clod -i
devcontainer` builds in the project. In an `.envrc`, `export
CLOD_IMAGE=devcontainer:$PWD/app` pins it. It goes first in a combination,
and a variant can't be built `FROM` it, since it differs from one project to
the next: make your variant `FROM $BASE` and combine them. `clod env` mentions
a devcontainer the run doesn't use. With `auto`, a run uses the devcontainer
unless `-i`, `CLOD_IMAGE` in your shell or the project's `.envrc` chooses an
image; one in `~/.clod/config` doesn't count, so `clod default image go` still
applies elsewhere. Without the CLI, `auto` says so and runs the image it
otherwise would.

clod uses the devcontainer for its image and nothing else. The CLI's `build`
handles `image`, `build` (a Dockerfile), `dockerComposeFile` (the service's
image only; the other services don't run) and `features`, from registries your
`docker login` reaches. clod never runs `devcontainer up`, so a run is a clod
run as usual: `initializeCommand` (which would run on your machine), the
lifecycle commands (`postCreateCommand` and the rest), `mounts`, `runArgs`,
`forwardPorts` and `customizations` are all left unused. Publish ports with
`-P` or `CLOD_PORTS`, and set run-time variables in the `.envrc`. Nothing in a
project's `devcontainer.json` can widen what the container reaches.

The layer on top needs a Debian or Ubuntu image (`apt-get`). Three things carry
over from the devcontainer:

- **Its user**: `remoteUser` (or `containerUser`) takes `claude`'s uid and gid,
  its files with it, so `claude` can use and update the tools installed in its
  home, such as nvm's Node in `/home/vscode`. The container still runs as
  `claude`, with its home at `/home/claude`.
- **Its `containerEnv`**: each variable the image and the run don't already
  set. The image's own `ENV`, `PATH` included, is kept.
- **Its apt repositories**: where it already lists GitHub's (as the
  `github-cli` feature does), NodeSource's Node 26 or the git-core PPA, the
  base's layer installs `gh`, Node or git from that entry instead of adding
  its own. On Ubuntu, git comes from the PPA's build for that release; on a
  release the PPA lacks, git is the base's own.

The image is `clod-devcontainer-HASH` to Docker, `HASH` being of the config
file's path, so each project's is its own; `clod image` lists them by their
config file. It rebuilds when a file beside the config changes (in
`.devcontainer/`, or the `.devcontainer/NAME` folder), or the base's
`Dockerfile` does. A file it names from elsewhere, such as `"dockerfile":
"../Dockerfile"`, isn't checked: `clod image rebuild devcontainer` rebuilds it
without the cache, picking up a change to one. `clod image clean devcontainer`
removes this project's, and `clod image prune` removes those whose project has
changed or gone.

## Removing images

`clod image rm NAME...` undoes `clod image new`: it deletes your variant
`~/.clod/images/NAME` and the images clod built from it, combinations that
include it too. In a terminal it lists what it will delete and asks first;
without one it needs `--force`. A bundled variant can't be deleted, but if
yours has the same name, the bundled one takes its place again.

`clod image clean NAME...` removes only images clod built, named as for `-i`
(`go`, `go+sudo`, `clod`), keeping their variants; with no names, it removes
the image `-i` or `CLOD_IMAGE` selects. The next run builds them again.
`clod image prune` removes every image clod built that is stale, along
with the untagged images builds left behind; an image whose variant you've
deleted by hand isn't stale, so it stays. Docker won't remove an image a
container uses, including a stopped one, so `clod image` marks those `in use`,
`prune` keeps them, and `rm` and `clean` refuse them; `docker ps -a` lists the
containers. `clod image` lists every image clod built, including those whose
variant you've deleted by hand, marked `(no Dockerfile)`. Removing an image
that others are built on frees its space only once they're gone too; they
rebuild on their next run.

```bash
clod image rm mine          # delete the variant mine and its images (asks first)
clod image clean go         # remove the built go image; the variant stays
clod image clean            # remove the image -i or CLOD_IMAGE selects
```

Docker's build cache isn't removed with the images. `docker system df` shows
how much space it takes, and `docker builder prune` clears it, for everything
built on that Docker, not only clod's images.
