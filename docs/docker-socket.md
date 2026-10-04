# Letting the agent run containers

> [!CAUTION]
> `--docker` hands the agent your Docker daemon, and with it the whole Docker
> host. The container stops being a boundary: anything you could do as root
> on that host, the agent can do too.

To build and run containers, the agent needs two things: the Docker CLI, which
the `docker` variant has, and your Docker's socket, which `--docker` mounts.
`--docker` adds only the socket, so use the two together:

```bash
clod -i docker --docker      # the docker CLI, and the socket to drive it
```

## What it gives away

Whoever controls the Docker socket controls the Docker host: they can start a
container that mounts any folder on it, as root. With `--docker`, the agent's
reach grows from the project and its home to that whole host:

- **On Linux**, the Docker host is your machine. The agent can read and change
  any file on it, including your home directory, SSH keys and cloud
  credentials, other projects, every clod home's login, and system files.
- **On macOS**, the Docker host is Colima's or Docker Desktop's VM. The VM
  mounts your home folder read-write, so the agent can reach everything under
  `~`: your keys and credentials, other projects and every clod home's login.
- **Everywhere**, it can stop, change or remove any of your containers, images
  and volumes, including ones unrelated to clod.

Use `--docker` only for work you'd let run on your machine unconfined, and run
it with a home that holds no more than that work needs.

`--docker` is an option only, with no setting in the environment, an `.envrc` or
your defaults, so a project can't turn it on: it applies only when you type it.

## How the agent's containers behave

The containers the agent starts run beside clod's, on your Docker, and outlive
it. Their bind mounts take paths on your machine, so the container gets the
project's path as `$CLOD_HOST_WORKSPACE`. A volume workspace (`-w vol:NAME`)
has no such path; the agent's containers mount the volume
`clod-workspace-NAME` by name instead. A scratch workspace can't be mounted at
all. The agent reaches their published
ports at `host.docker.internal`. The `docker` variant tells Claude all this.

`--docker` works with any image that has the Docker CLI, such as a combination
like `-i go+docker`; with one that doesn't, clod warns at launch. It fails if
Docker isn't running on this machine (or its VM).
