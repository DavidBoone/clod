# Docker

This image has the Docker CLI with the buildx and compose plugins. When clod ran with `--docker`, `/var/run/docker.sock` is the host's Docker socket and `docker` works; without it there is no socket, so `docker` commands fail.

- The daemon is the host's (on macOS, the Linux VM of Colima or Docker Desktop), not this container's. Containers, images, volumes and networks you create are siblings of this container and outlive it: clean up what you start (`docker run --rm`, `docker compose down`) and leave alone what you didn't.
- Bind mounts take paths on the Docker host, not in this container. The project at `/workspace` is at `$CLOD_HOST_WORKSPACE` there, so mount `"$CLOD_HOST_WORKSPACE/some/dir"`, not `/workspace/some/dir`. Other paths in this container, such as `/home/claude` or `/tmp`, can't be mounted, and neither can `/workspace` when `$CLOD_HOST_WORKSPACE` is unset (a scratch workspace).
- `localhost` here is this container, not the Docker host. Publish a sibling container's ports (`-p 8080:80`) and reach them at `host.docker.internal:8080`.
- `docker build` sends its context from this container, so building from `/workspace` works as usual.
