# Using clod

## The command line

```bash
clod                 # Claude Code
clod claude --resume # Claude Code with its own arguments
clod codex [args]    # Codex
clod bash | zsh      # a shell in the container
clod -i go           # the go image variant (see Image variants)
clod -H work         # the "work" home (see Homes)
clod env             # show the home, image, login, ports, envrc and variables that would be used
clod default         # show your defaults
clod --help          # all commands and options
```


A bare `clod` runs Claude Code, or whatever you've set as the default command.
To pass it arguments without naming it, put them after `--`: `clod -- --resume`
is `clod claude --resume`.

Claude Code runs with `--dangerously-skip-permissions` unless its arguments
include `--permission-mode`, `--dangerously-skip-permissions` or
`--allow-dangerously-skip-permissions`, so `clod claude --permission-mode plan`
brings the prompts back. `clod claude -p "..." | ...` works without a terminal.

`clod` refuses to run from your home directory or any directory above it, from
`~/.clod`, or from `~/.clod/homes` or anything under it, since the agent could
then read your credentials and every home's login. `clod --force` runs anyway.

See also [Image variants](images.md) and [Homes, settings and per-project
environment](configuration.md).

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
```

## Updating and rebuilding

To update clod, `clod update` pulls its checkout in `~/.clod/src` and lists
what changed, one line per change. The next `clod` rebuilds the image if it
changed; `clod build` builds it straight away instead, without starting a
container.

An image is otherwise kept as built. To refresh its system packages, Node and
whatever its variant downloads, rebuild it from scratch. When an image's files
have changed but you'd rather not wait for the build, `--skip-build` runs it
as it is:

```bash
clod update           # update clod
clod build            # build the image now, if it changed
clod rebuild          # rebuild the image from scratch
clod --skip-build     # run the image as built
```

## What lives where

Everything clod keeps is under `~/.clod`:

```
~/.clod/
  src/                clod's own checkout
  config              your defaults for the launcher settings
  homes/<name>/       container homes
  images/<name>/      your image variants
  shared/             your shared config, mounted read-only as /etc/claude-code
```
