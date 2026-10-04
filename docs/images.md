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
clod image rm go         # remove the built image; the next clod -i go builds it again
clod image prune         # remove the stale images, which their next run rebuilds anyway
```

The first run builds `clod-go`; later runs reuse it until its `Dockerfile` or
the base image changes. To pick up a newer Go or Rust, rebuild it with
`clod image rebuild go`. Rebuilding the base makes every variant rebuild on its
next use.

Variants combine with `+`: `clod -i browser+dotnet` builds `clod-browser`, then
the `dotnet` variant on top of it as `clod-browser.dotnet`. They build in the
order given, which matters only when two variants change the same files. A
combination rebuilds, and is set as a default, like any variant:

```bash
clod -i browser+dotnet          # .NET with a browser, for testing a web app
clod default image go+sudo      # Go, with passwordless sudo
```

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
clod image new mine go+sudo  # a starter Dockerfile, FROM clod-go.sudo
clod image new go            # your own copy of the bundled go, which then takes its place
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

A variant can be `FROM` a combination by its tag, as in `FROM clod-browser.dotnet`:
clod builds the combination first, and rebuilds yours when any variant in it
changes. That keeps your own additions on top of bundled variants without
copying their install steps.

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

## Removing images

`clod image rm NAME...` removes images clod built, named as for `-i`
(`go`, `go+sudo`, `clod`); with no names, it removes the image `-i` or
`CLOD_IMAGE` selects. A variant's files stay, so its next run builds it
again. `clod image prune` removes every image clod built that is stale, along
with the untagged images builds left behind; an image whose variant you've
deleted isn't stale, so it stays. Docker won't remove an image a container
uses, including a stopped one, so `clod image` marks those `in use`, `prune`
keeps them, and `rm` refuses them; `docker ps -a` lists the containers. `clod image` lists every image clod built,
including those whose variant you've deleted, marked `(no Dockerfile)`. Removing an image that
others are built on frees its space only once they're gone too; they rebuild
on their next run.

Docker's build cache isn't removed with the images. `docker system df` shows
how much space it takes, and `docker builder prune` clears it, for everything
built on that Docker, not only clod's images.
