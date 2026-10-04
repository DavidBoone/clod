# clod

Run Claude Code or Codex with no permission prompts, safely. `clod` starts the
agent in a throwaway Docker container that sees only the directory you run it
from and a home of its own. Inside, it works without stopping to ask: it
browses the web, runs whatever tools it needs and installs packages into its
home, while the rest of your machine stays out of reach.

## Quick start

> [!NOTE]
> clod needs a working Docker: `docker run --rm hello-world`
> should succeed. If it doesn't yet, [Getting Docker running](docs/docker.md)
> covers Colima, Docker Desktop and Docker Engine.

### Install

```bash
git clone https://github.com/DavidBoone/clod.git ~/.clod/src
~/.clod/src/clod install
```

`install` links `clod` into a directory on your `PATH`, such as `~/.local/bin`.
For tab completion, add `eval "$(clod completion)"` to your `~/.zshrc` or
`~/.bashrc`.

### Run it

```bash
cd ~/code/some-project
clod
```

The first run builds the image, which takes a few minutes, and installs Claude
Code into the container's home. Claude Code then asks you to `/login`: open the
printed URL in your browser and paste the code back. Both happen once; every
`clod` after that starts in seconds.

## How it works

Each `clod` starts a fresh container from three pieces:

- **Your project.** The directory you run `clod` from is mounted read-write at
  `/workspace`. The agent works on your real files, not a copy.
- **A home.** `~/.clod/homes/default` is mounted as the container's home. It
  persists between runs and holds the login, settings, history and Claude Code
  itself, which updates itself. It is not your own home directory: it starts
  empty, with none of your keys or logins, and holds only what you give it.
  `clod -H work` uses another home, with its own login.
- **An image.** The `clod` image has Claude Code, Codex, git, the GitHub CLI,
  Python, Node and everyday CLI tools. Variants add a language or stack on
  top: `clod -i go`.

When you exit, the container is removed. Only the project and the home remain.

That container is the boundary. Claude Code runs with
`--dangerously-skip-permissions` (Codex with its equivalent), so instead of
asking you about each command, the agent can do anything inside it. What it
can reach is short and easy to check:

- your project, which it can change or delete, so keep it in git
- its own home, and whatever logins you make there
- variables you pass in from the project's envrc
- the network, including services on your machine via `host.docker.internal`

Your own home directory, other projects, SSH keys, cloud logins and the rest of
your machine are outside the container. [What the agent can
reach](docs/security.md) goes through this in full.

## More

Everything below is optional; plain `clod` is all most work needs.

- [Using clod](docs/usage.md): the command line, Codex, shells, publishing
  ports, git and GitHub logins, updating and rebuilding
- [Image variants](docs/images.md): the bundled Go, Rust, Python, .NET, LAMP,
  browser and Docker images, combining them, and writing your own
- [Homes, settings and per-project environment](docs/configuration.md): one
  home per client, borrowing a login, defaults, and `.envrc` variables
- [Shared config and the statusline](docs/shared-config.md): managed settings
  and instructions for every home
- [Letting the agent run containers](docs/docker-socket.md): `--docker`, and
  what it gives away
- [What the agent can reach](docs/security.md): the boundary in detail
- [Getting Docker running](docs/docker.md): macOS and Linux setup, and Linux
  host notes
- [Running the image without clod](docs/without-clod.md): plain `docker build`
  and `docker run`

## License

[MIT](LICENSE)
