# Alternatives to clod

clod is one of many ways to let a coding agent work without permission
prompts. They differ mainly in three things: how strong the boundary is, whether
they limit the network, and whether they keep credentials out of the agent's
reach. If clod's trade-offs don't suit you, one of these may.

This page describes each from its own documentation as of October 2026. They
change quickly, so check before relying on a detail.

## At a glance

|                            | Boundary            | Hosts                                   | Agents                                    | Network                         | Credentials                                          |
| -------------------------- | ------------------- | --------------------------------------- | ----------------------------------------- | ------------------------------- | ---------------------------------------------------- |
| **clod**                   | container           | macOS (Colima, Docker Desktop), Linux   | Claude Code, Codex                        | open                            | in the home, readable by the agent                   |
| **Docker Sandboxes**       | microVM             | macOS (Apple silicon), Windows 11       | Claude Code, Codex, Gemini, Copilot, more | open, balanced or locked down   | kept on the host; a proxy adds them to requests      |
| **Anthropic devcontainer** | container           | wherever devcontainers run              | Claude Code                               | allowlist (iptables)            | in the container                                     |
| **Claude Code `/sandbox`** | OS sandbox, no container | macOS, Linux, WSL2                 | Claude Code                               | allowlist (proxy)               | the agent runs as you, on your machine               |
| **ClaudeBox**              | container           | macOS, Linux                            | Claude Code                               | allowlist per project           | per-project state in the container                   |
| **agent-sandbox**          | container and proxy | wherever Docker runs                    | Claude Code, Codex                        | allowlist (mitmproxy)           | kept on the host; the proxy adds them to requests    |

## Docker Sandboxes

[Docker Sandboxes](https://docs.docker.com/ai/sandboxes/) (`sbx`, or
`docker sandbox run claude`) runs each agent in a microVM with its own kernel
and its own Docker engine. That is a stronger boundary than a container, and
the agent can build and run containers without being given your Docker, which
is what clod's `--docker` does. A host-side proxy enforces the network policy
and keeps API keys and GitHub tokens out of the sandbox: the agent sees a
placeholder, and the proxy swaps in the real value from your keychain on the
way out. SSH is forwarded from your agent, so private keys stay on the host.
Custom templates play the part of clod's image variants.

Choose it when you want the strongest isolation, or the agent needs to run
containers. At the time of writing it doesn't run on Linux, and users report
noticeable overhead on large projects.

## Anthropic's reference devcontainer

The [Claude Code devcontainer](https://code.claude.com/docs/en/devcontainer)
is a `Dockerfile`, a `devcontainer.json` and a firewall script that allows only
the hosts Claude Code needs. VS Code, or any tool that reads devcontainers,
builds and opens it.

Choose it when you work in VS Code, want the setup checked into each
repository, or want the network locked down without running anything else.

## Claude Code's built-in sandbox

`/sandbox` in Claude Code runs each shell command under the operating
system's sandbox: Seatbelt on macOS, bubblewrap on Linux. Writes are limited
to the project, and network access goes through an allowlist proxy. There is
no container, so there is nothing to build, and the agent uses your own tools
and environment. That is also the catch: it runs as you, on your machine. Codex
has a similar sandbox of its own.

Choose it when you want fewer prompts with no Docker at all, and you're
comfortable with the agent working in your real environment.

## ClaudeBox

[ClaudeBox](https://github.com/RchGrav/claudebox) is the closest to clod: a
launcher script around Docker, with more than fifteen ready-made language
profiles, a separate image and saved state for each project, and a firewall
allowlist per project.

Choose it when you want many ready-made stacks and per-project network rules,
and you use only Claude Code.

## agent-sandbox

[agent-sandbox](https://github.com/mattolson/agent-sandbox) runs the agent's
container behind a mitmproxy container. Rules decide which hosts it may reach,
and which secrets, kept in files on the host, are added to which requests. Its
docs point out the limit of this: the agent can still use a secret for
anything the rules allow while it runs. So scope tokens narrowly, to specific
repositories, whatever tool you use.

Choose it when you need tokens, such as a GitHub token for pushing, that the
agent can use but never read.

## Where clod differs

- **Homes.** Named homes, each with its own login and settings, which you
  can list, copy, move and remove. One home per client or account keeps their
  logins apart.
- **Image variants that combine.** `clod -i go+docker` builds one on top of
  the other, and clod rebuilds a variant when its files or its base change.
- **Shared configuration.** Managed settings and instructions in
  `~/.clod/shared` apply to every home.
- **Per-project variables** from a direnv `.envrc`.
- **Claude Code and Codex** in the same image.
- **Plain Docker.** A bash script and `docker run --rm`, on Colima, Docker
  Desktop or Linux, with no VM of its own, no proxy and no daemon.

What it leaves out, on purpose:

- **Limiting the network.** clod's container has the network your machine has.
  If you want limits, apply them outside clod: at your router or firewall, or
  through a proxy you point the container at with `HTTPS_PROXY` in the
  `.envrc`.
- **Keeping credentials from the agent.** Anything in the home or the `.envrc`
  is readable by the agent. Give each home only what its work needs, and prefer
  tokens limited to specific repositories, with an expiry.

See [What the agent can reach](security.md) for clod's boundary in detail.
