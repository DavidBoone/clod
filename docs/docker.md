# Getting Docker running

clod needs Docker on macOS or Linux, plus git. clod itself is a bash script
and runs with the bash that macOS and Linux include. When Docker works,
`docker run --rm hello-world` prints a greeting.

## macOS

[Colima](https://github.com/abiosoft/colima) is a lightweight Docker runtime
from Homebrew:

```bash
brew install colima docker
colima start --cpu 4 --memory 8
brew services start colima      # optional: start it at login
```

Docker Desktop works too.

Colima shares your home folder with the containers by default, so keep
projects under it, or add other folders with `colima start --mount /path:w`. clod
won't start with a workspace or home outside the shared folders: Docker reports
`bind source path does not exist` for it, since its VM can't see the folder.

Colima's shared folders, which hold the home and workspace, don't allow every
ownership and permission change: `chown`, and sometimes `chmod`, fail with
`Permission denied`. Databases trip over this, so keep a database's data
directory in the container's own filesystem rather than in the workspace, and
for one that should persist, use a [volume home](configuration.md#volume-homes)
(`clod -H vol:NAME`), which is on the VM's own disk.

## Linux

Install Docker Engine with Docker's convenience script, then add yourself to
the `docker` group and log in again:

```bash
curl -fsSL https://get.docker.com | sh
sudo usermod -aG docker $USER
```

Docker Engine on Linux keeps bind-mount ownership as is, so on a Linux host
`clod` builds the image with `claude` given your uid and gid, and files written
to the home and workspace belong to you. The image is therefore specific to the
user who built it. The launcher also maps `host.docker.internal` to the host,
which Docker Desktop and Colima provide on their own.

Rootless Docker and Podman are untested.
