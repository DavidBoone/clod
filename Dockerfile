FROM debian:trixie

# Generic base for running Claude Code and Codex. Personal stacks go in image
# variants built FROM clod (see README). Layers are ordered rarely-changed
# first. Apt lists are kept so variants can `apt-get install` without
# re-running update.

# Base system
RUN apt-get update && apt-get upgrade -y \
    && apt-get install -y \
       curl wget ca-certificates \
       git build-essential \
       sudo locales

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
       python3 python3-pip python3-venv \
       nodejs

# Browser system libraries for Playwright's Chromium
RUN npx --yes playwright install-deps chromium && rm -rf /root/.npm

# CLI tools
RUN apt-get install -y \
       gh vim zsh direnv less tree file jq \
       ripgrep fd-find \
       psmisc procps rsync zip unzip \
       openssh-client dnsutils netcat-openbsd iputils-ping socat \
       sqlite3

# Bind mounts can report owners git doesn't trust (macOS file sharing), and
# the container has no other users to guard against.
RUN git config --system --add safe.directory '*'

# Create claude user. On a Linux host the launcher passes the host user's ids,
# since bind mounts there keep host ownership; -l avoids sparse lastlog bloat
# with large uids.
ARG CLOD_UID=1000
ARG CLOD_GID=1000
RUN groupadd -o -g $CLOD_GID claude \
    && useradd -l -m -o -u $CLOD_UID -g claude -s /bin/bash claude \
    && echo 'claude ALL=(ALL) NOPASSWD:ALL' > /etc/sudoers.d/claude \
    && chmod 0440 /etc/sudoers.d/claude

USER claude
ENV PATH="$PATH:/home/claude/.local/bin"
ENV NPM_CONFIG_PREFIX=/home/claude/.local
ENV CLAUDE_CONFIG_DIR=/home/claude/.claude
ENV CODEX_HOME=/home/claude/.codex

COPY --chmod=755 entrypoint.sh /usr/local/bin/clod-entrypoint

WORKDIR /workspace
ENTRYPOINT ["clod-entrypoint"]
CMD []
