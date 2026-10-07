FROM debian:trixie-slim

# Generic base for running Claude Code and Codex, with everyday CLI tools.
# Languages, compilers and browsers go in variants built FROM clod (see docs/images.md). Layers are ordered rarely-changed
# first. Apt lists are kept so variants can `apt-get install` without
# re-running update. The slim base installs packages without their docs, man
# pages (there's no man) or translations (/etc/dpkg/dpkg.cfg.d/docker), which
# would be over 100 MB; variants inherit that.

# Base system
RUN apt-get update && apt-get upgrade -y \
    && apt-get install -y \
       curl wget ca-certificates \
       git \
       locales

# Culture (the clod launcher passes the host's TZ)
RUN echo "en_US.UTF-8 UTF-8" > /etc/locale.gen \
    && locale-gen en_US.UTF-8 \
    && update-locale LANG=en_US.UTF-8
ENV LC_ALL=en_US.UTF-8
ENV LANG=en_US.UTF-8

# Language runtimes for agent tooling (MCP servers, scripts, npm-installed CLIs).
# Pillow converts pictures for the show-image plugin.
# Node comes from NodeSource; its nodejs package includes npm. The GitHub CLI
# comes from GitHub's own repository, installed with the CLI tools below.
RUN mkdir -p /etc/apt/keyrings \
    && curl -fsSL https://deb.nodesource.com/gpgkey/nodesource-repo.gpg.key \
       -o /etc/apt/keyrings/nodesource.asc \
    && printf '%s\n' 'Types: deb' 'URIs: https://deb.nodesource.com/node_26.x' \
       'Suites: nodistro' 'Components: main' 'Signed-By: /etc/apt/keyrings/nodesource.asc' \
       > /etc/apt/sources.list.d/nodesource.sources \
    && curl -fsSL https://cli.github.com/packages/githubcli-archive-keyring.gpg \
       -o /etc/apt/keyrings/githubcli.gpg \
    && printf '%s\n' 'Types: deb' 'URIs: https://cli.github.com/packages' \
       'Suites: stable' 'Components: main' 'Signed-By: /etc/apt/keyrings/githubcli.gpg' \
       > /etc/apt/sources.list.d/githubcli.sources \
    && apt-get update \
    && apt-get install -y \
       python3 python3-venv python3-pil \
       nodejs

# CLI tools
RUN apt-get install -y \
       gh vim zsh direnv less tree file jq bc gettext-base make \
       ripgrep fd-find \
       binutils bsdextrautils strace lsof \
       psmisc procps rsync zip unzip xz-utils \
       openssh-client dnsutils netcat-openbsd iputils-ping socat iproute2 \
       sqlite3 tini \
    && ln -s /usr/bin/fdfind /usr/local/bin/fd

# Bind mounts can report owners git doesn't trust (macOS file sharing), and
# the container has no other users to guard against.
RUN git config --system --add safe.directory '*'

# Create claude user. On a Linux host the launcher passes the host user's ids,
# since bind mounts there keep host ownership; -l avoids sparse lastlog bloat
# with large uids.
ARG CLOD_UID=1000
ARG CLOD_GID=1000
RUN groupadd -o -g $CLOD_GID claude \
    && useradd -l -m -o -u $CLOD_UID -g claude -s /bin/bash claude

# clod --scratch mounts an empty volume here, which takes this directory's owner.
RUN mkdir /workspace && chown claude:claude /workspace

# The clod launcher mounts its checkout's entrypoint.sh, container.md and
# clipboard.sh over these copies, so changes to them need no build; the copies
# serve runs without clod. A separate chmod rather than COPY --chmod, which
# needs BuildKit; Homebrew's docker on macOS has no buildx, so it builds with
# the classic builder.
COPY entrypoint.sh /usr/local/bin/clod-entrypoint
RUN chmod 755 /usr/local/bin/clod-entrypoint

# xclip and wl-paste that fetch the host clipboard's image for Claude Code's
# Ctrl+V, with clod --clipboard (or run an installed xclip or wl-paste).
COPY clipboard.sh /usr/local/bin/clod-clipboard
RUN chmod 755 /usr/local/bin/clod-clipboard \
    && ln -s clod-clipboard /usr/local/bin/xclip \
    && ln -s clod-clipboard /usr/local/bin/wl-paste

# Tells Claude about the container; the entrypoint loads /etc/clod.
COPY container.md /etc/clod/.claude/rules/clod.md

# Claude Code plugins the entrypoint loads with --plugin-dir: show-image draws
# pictures inline in kitty and Ghostty. The launcher mounts its checkout's
# copy over this one, as it does the files above.
COPY plugins/show-image /etc/clod/plugins/show-image

USER claude
ENV PATH="$PATH:/home/claude/.local/bin"
ENV NPM_CONFIG_PREFIX=/home/claude/.local
ENV CLAUDE_CONFIG_DIR=/home/claude/.claude
ENV CODEX_HOME=/home/claude/.codex
# Docker leaves USER and TMPDIR unset, which scripts don't expect: $TMPDIR/x,
# written on macOS where it's always set, would be /x. vim and less are the
# editor and pager.
ENV USER=claude TMPDIR=/tmp EDITOR=vim PAGER=less

WORKDIR /workspace
# tini is PID 1, so orphaned processes (browsers a test run leaves behind) are
# reaped instead of piling up as zombies. sh runs the entrypoint, since the
# one clod mounts keeps its mode from the checkout, which needn't be executable.
ENTRYPOINT ["tini", "--", "sh", "/usr/local/bin/clod-entrypoint"]
CMD []
