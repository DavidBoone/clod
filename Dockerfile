FROM debian:trixie

# Generic base for running Claude Code and Codex, with everyday CLI tools.
# Languages, compilers and browsers go in variants built FROM clod (see docs/images.md). Layers are ordered rarely-changed
# first. Apt lists are kept so variants can `apt-get install` without
# re-running update.

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
# Node comes from NodeSource; its nodejs package includes npm.
RUN mkdir -p /etc/apt/keyrings \
    && curl -fsSL https://deb.nodesource.com/gpgkey/nodesource-repo.gpg.key \
       -o /etc/apt/keyrings/nodesource.asc \
    && printf '%s\n' 'Types: deb' 'URIs: https://deb.nodesource.com/node_26.x' \
       'Suites: nodistro' 'Components: main' 'Signed-By: /etc/apt/keyrings/nodesource.asc' \
       > /etc/apt/sources.list.d/nodesource.sources \
    && apt-get update \
    && apt-get install -y \
       python3 python3-venv \
       nodejs

# CLI tools
RUN apt-get install -y \
       gh vim zsh direnv less tree file jq bc gettext-base make \
       ripgrep fd-find \
       binutils bsdextrautils strace lsof \
       psmisc procps rsync zip unzip xz-utils \
       openssh-client dnsutils netcat-openbsd iputils-ping socat iproute2 \
       sqlite3 \
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

# A separate chmod rather than COPY --chmod, which needs BuildKit; Homebrew's
# docker on macOS has no buildx, so it builds with the classic builder.
COPY entrypoint.sh /usr/local/bin/clod-entrypoint
RUN chmod 755 /usr/local/bin/clod-entrypoint

# Tells Claude about the container; the entrypoint loads /etc/clod.
COPY container.md /etc/clod/.claude/rules/clod.md

USER claude
ENV PATH="$PATH:/home/claude/.local/bin"
ENV NPM_CONFIG_PREFIX=/home/claude/.local
ENV CLAUDE_CONFIG_DIR=/home/claude/.claude
ENV CODEX_HOME=/home/claude/.codex

WORKDIR /workspace
ENTRYPOINT ["clod-entrypoint"]
CMD []
