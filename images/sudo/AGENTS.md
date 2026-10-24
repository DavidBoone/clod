# Sudo

The `claude` user has passwordless `sudo`, so `sudo apt-get update && sudo apt-get install -y PACKAGE` works. The apt lists date from the image's build; without the update, a package superseded since then fails to download.

- Anything installed or changed outside `/home/claude` and `/workspace` is gone when the container exits. If a package will be needed again, tell the user so they can add it to a variant's `Dockerfile`.
- Files created with `sudo` in `/workspace` are owned by root on a Linux host; don't leave them there.
