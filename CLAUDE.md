# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Overview

A Docker image for running Claude Code or Codex in ephemeral containers, plus the `clod` launcher (zsh). Supported hosts: macOS (Colima or Docker Desktop) and Linux (rootful Docker Engine). No compose, no persistent containers - just `docker run` with `--rm`.

## Build & Run

```bash
clod          # launcher script; builds images as needed and wraps docker run
```

`Dockerfile` is the generic base image (`clod`). Personal or per-stack tooling goes in variants: `~/.clod/images/<name>/Dockerfile` built `FROM clod`, selected with `CLOD_IMAGE=<name>` and auto-built as `clod-<name>` when its files or the base change. The launcher builds the base from its own (symlink-resolved) directory when `Dockerfile` or `entrypoint.sh` change.

The `clod` launcher mounts a home from `~/.clod/homes/<name>` (or any host path) at `/home/claude` and `.` at `/workspace`. Each home keeps its own Claude login (MCP OAuth tokens live in the same file); `CLOD_CREDS=<home>` mounts another home's credentials file live to borrow its login. `~/.clod/shared` is mounted read-only at `/etc/claude-code` (managed settings and CLAUDE.md for every home). `shared/` in this repo is a starter for it: a `CLAUDE.md` describing the container, and a statusline with the managed settings enabling it. `CLOD_HOME`, `CLOD_IMAGE` and `CLOD_CREDS` come from the host shell environment; container variables come from the nearest `.clod.envrc` or, failing that, direnv-allowed `.envrc` up the tree (only that one file; `.clod.envrc` wins in the same directory). Launcher settings set by that file are defaults for the shell's, never container variables. Claude Code and Codex install themselves into the home on first run and self-update. The launcher refuses to mount `$HOME`, a directory above it, `~/.clod` or anything under `~/.clod/homes` as the workspace unless the first argument is `--force`, which it strips.

On a Linux host, where bind mounts keep host ownership, the launcher builds the base image with `--build-arg CLOD_UID/CLOD_GID` set to the host user's ids (folded into the build hash) so `claude` owns its files, and maps `host.docker.internal` to the host gateway. On macOS the VM's file sharing handles ownership, so `claude` keeps uid 1000.

## Security

The container is a convenience boundary, not a sandbox against a hostile agent:

- Claude Code runs with `--dangerously-skip-permissions` unless its arguments choose a permission mode, and Codex with `--dangerously-bypass-approvals-and-sandbox`
- `claude` has passwordless sudo inside the container
- The workspace and the whole home are mounted read-write, so anything in the home (SSH keys, tokens, credentials) is visible to the agent
- The container has normal outbound network access and can reach host services via `host.docker.internal`
- Claude Code installs via `curl https://claude.ai/install.sh | bash` on first run
- `--rm` discards everything outside the home and workspace mounts after each run
