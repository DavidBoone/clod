# Using clod

## The command line

```bash
clod                 # Claude Code
clod claude --resume # Claude Code with its own arguments
clod codex [args]    # Codex
clod bash | zsh      # a shell in the container
clod -i go           # the go image variant (see Image variants)
clod -H work         # the "work" home (see Homes)
clod -w ~/src/app    # that directory as /workspace (see Another workspace)
clod -w vol:play     # a workspace kept in a Docker volume
clod -s              # an empty, throwaway /workspace (see A scratch workspace)
clod env             # show the home, workspace, image, ports, .envrc and variables that would be used
clod default         # show your defaults
clod image           # list the images (see Image variants)
clod home            # list the homes (see Homes)
clod workspace       # list the volume workspaces
clod --help          # all commands and options
```

Commands that manage something are a noun and a verb: `clod image build`,
`clod home rm`. The noun on its own lists them, except `shared`, which needs
`new` or `diff`.

A bare `clod` runs Claude Code, or whatever you've set as the default command.
To pass it arguments without naming it, put them after `--`: `clod -- --resume`
is `clod claude --resume`.

Claude Code runs with `--dangerously-skip-permissions` unless its arguments
include `--permission-mode`, `--dangerously-skip-permissions` or
`--allow-dangerously-skip-permissions`, so `clod claude --permission-mode plan`
brings the prompts back. `clod claude -p "..." | ...` works without a terminal.

`clod` refuses to mount your home directory or any directory above it,
`~/.clod`, or `~/.clod/homes` or anything under it as the workspace, since the
agent could then read your credentials and every home's login. `clod --force`
runs anyway.

See also [Image variants](images.md) and [Homes, settings and per-project
environment](configuration.md).

## Another workspace

`clod -w PATH` (`--workspace`) mounts that directory as `/workspace` instead of
the current one, from wherever you run it; the `.envrc` is looked up from it.
It must exist.

`clod -w vol:NAME` uses the Docker volume `clod-workspace-NAME` instead: it
lives on Docker's own disk, not in a folder on your machine, and is kept
between runs, for a repository cloned just for the agent, say. Docker creates it
on first use, owned by the container's user. No `.envrc` is read, and clod runs
from anywhere. To get files out, push them somewhere or copy them into the home.

```bash
clod workspace                  # list the volume workspaces, and which are in use
clod workspace rm play          # delete clod-workspace-play, after asking
clod --force workspace rm play  # delete it without asking
```

`clod workspace rm` takes `NAME` or `vol:NAME`. In a terminal it lists what
it will delete and asks first; without one, it needs `--force`. Docker won't
remove a volume a container uses.

`-w` is an option only, with no setting in the environment, an `.envrc` or your
defaults.

## A scratch workspace

`clod --scratch` (`-s`) runs with an empty `/workspace` instead of the current
directory: a Docker volume that's removed with the container, for a question,
an experiment or a repository cloned just to look at. Only the home persists,
so copy out anything worth keeping, or push it somewhere. No `.envrc` is read,
since the current directory isn't the project, and clod runs from anywhere,
your home directory included. With `--docker`, the agent's containers can't
bind-mount a scratch workspace, which has no path on the Docker host.

Claude Code keys its history and memory by the workspace path, which is
`/workspace` in every clod run, so a scratch session shares them with the
home's other sessions: `clod -s claude --resume` lists them all. `-s` doesn't
combine with `-w`.

## Install and tab completion

`clod install` links `clod` into the first of `~/.local/bin`, `~/bin`,
`/opt/homebrew/bin` and `/usr/local/bin` that's on your `PATH` and writable,
or else creates `~/.local/bin` and prints the line that adds it to your
`PATH`. `clod install DIR` links it into a directory of your choice.

For tab completion in bash or zsh, add this to your `~/.bashrc` or `~/.zshrc`:

```bash
eval "$(clod completion)"
```

## Git and GitHub

A new home has no git identity or GitHub login, so the agent's first commit
fails until you set them up. Do it once per home, in a shell in the container;
both persist in the home:

```bash
clod bash
git config --global user.name "Your Name"
git config --global user.email you@example.com
gh auth login            # then: gh auth setup-git, so git pushes use it
```

Whatever you log into here, the agent can use: give each home only what its
work needs.

## Codex

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

## Publishing ports

To reach a server the agent starts, such as a dev server on port 5173, publish
its port when you launch. Ports are written host first, container second, as
in Docker: the port on your machine, then the one inside. They're published on
your machine's localhost, and the server must listen on all interfaces
(`0.0.0.0`) inside the container:

```bash
clod -P 5173                 # localhost:5173 -> port 5173 in the container
clod -P 3000:5173            # localhost:3000 -> port 5173 in the container
clod -P 5173 -P 8080         # several
clod -P ''                   # none, even if the .envrc or config sets some
```

## Updating and rebuilding

To update clod, `clod update` pulls its checkout in `~/.clod/src` and lists
what changed, one line per change. The next `clod` rebuilds the image if it
changed; `clod image build` builds it straight away instead, without starting
a container. An update that changes the base image leaves every variant you've
built stale; `clod image prune` removes the stale images to free their space,
and each builds again on its next run.

An image is otherwise kept as built. To refresh its system packages, Node and
whatever its variant downloads, rebuild it from scratch. When an image's files
have changed but you'd rather not wait for the build, `--skip-build` runs it
as it is:

```bash
clod update                 # update clod
clod image build            # build the image now, if it changed
clod image build go rust    # build those images now, if they changed
clod image rebuild          # rebuild the image from scratch
clod --skip-build           # run the image as built
clod image prune            # remove the stale images
```

## What lives where

Everything clod keeps is under `~/.clod`:

```
~/.clod/
  src/                clod's own checkout
  config              your defaults for the launcher settings
  homes/<name>/       container homes (volume homes are Docker volumes, clod-home-<name>)
  images/<name>/      your image variants
  shared/             your shared config, mounted read-only as /etc/claude-code
```
