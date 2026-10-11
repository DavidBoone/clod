# Generic base for running Claude Code and Codex, with everyday CLI tools.
# Languages, compilers and browsers go in variants built FROM clod (see
# docs/images.md). BASE can instead name another Debian or Ubuntu image, such
# as one with a project's toolchain, to add clod's layer to: its PATH and other
# ENV are kept, and a user it has at claude's uid keeps its files. Layers are
# ordered rarely-changed first. Apt lists are kept so variants can `apt-get
# install` without re-running update. The slim base installs packages without
# their docs, man pages (there's no man) or translations
# (/etc/dpkg/dpkg.cfg.d/docker), which would be over 100 MB; variants inherit
# that.

ARG BASE=debian:trixie-slim
FROM $BASE

# Another BASE may end as a user of its own; installing needs root.
USER root

# Base system
RUN command -v apt-get >/dev/null \
       || { echo "clod's image needs a Debian or Ubuntu base, with apt-get" >&2; exit 1; } \
    && apt-get update && apt-get upgrade -y \
    && apt-get install -y \
       curl wget ca-certificates \
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
# comes from GitHub's own repository, installed with the CLI tools below. Git
# comes from the git-core PPA, for relative worktree paths (git 2.48), which
# keep a worktree's links valid on the host as well as at /workspace: an
# Ubuntu base uses its own release's build, Debian trixie Ubuntu 24.04's (its
# dependencies are all in trixie), and a release the PPA lacks keeps its own
# git. A repository the base already lists (a devcontainer's github-cli
# feature adds GitHub's) is left as it is, since apt refuses one listed twice
# with different keys.
RUN has_source() { grep -rqsF "$1" /etc/apt/sources.list /etc/apt/sources.list.d; } \
    && mkdir -p /etc/apt/keyrings \
    && . /etc/os-release \
    && case "$ID:${VERSION_CODENAME:-}" in \
         ubuntu:?*) git_suite=$VERSION_CODENAME ;; \
         debian:trixie) git_suite=noble ;; \
         *) git_suite= ;; \
       esac \
    && git_ppa=https://ppa.launchpadcontent.net/git-core/ppa/ubuntu \
    && if [ -n "$git_suite" ] && ! has_source launchpadcontent.net/git-core \
          && ! has_source launchpad.net/git-core \
          && curl -fsSI "$git_ppa/dists/$git_suite/Release" >/dev/null; then \
         curl -fsSL 'https://keyserver.ubuntu.com/pks/lookup?op=get&search=0xF911AB184317630C59970973E363C90F8F1B6217' \
           -o /etc/apt/keyrings/git-core.asc \
         && printf '%s\n' 'Types: deb' "URIs: $git_ppa" \
           "Suites: $git_suite" 'Components: main' 'Signed-By: /etc/apt/keyrings/git-core.asc' \
           > /etc/apt/sources.list.d/git-core.sources; \
       fi \
    && if ! has_source deb.nodesource.com/node_26.x; then \
         curl -fsSL https://deb.nodesource.com/gpgkey/nodesource-repo.gpg.key \
           -o /etc/apt/keyrings/nodesource.asc \
         && printf '%s\n' 'Types: deb' 'URIs: https://deb.nodesource.com/node_26.x' \
           'Suites: nodistro' 'Components: main' 'Signed-By: /etc/apt/keyrings/nodesource.asc' \
           > /etc/apt/sources.list.d/nodesource.sources; \
       fi \
    && if ! has_source cli.github.com/packages; then \
         curl -fsSL https://cli.github.com/packages/githubcli-archive-keyring.gpg \
           -o /etc/apt/keyrings/githubcli.gpg \
         && printf '%s\n' 'Types: deb' 'URIs: https://cli.github.com/packages' \
           'Suites: stable' 'Components: main' 'Signed-By: /etc/apt/keyrings/githubcli.gpg' \
           > /etc/apt/sources.list.d/githubcli.sources; \
       fi \
    && apt-get update \
    && apt-get install -y \
       git \
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
# with large uids. A user or group a base already has at those ids keeps its
# name and files, and claude's entries move ahead of its, so the ids resolve
# to claude (whoami, ssh's home).
ARG CLOD_UID=1000
ARG CLOD_GID=1000

# On a devcontainer's image, clod passes in its devcontainer.metadata label.
# The user its tools run as (remoteUser, else containerUser) moves to claude's
# ids, files included, so claude can use and update what it installed. Its
# containerEnv, which the devcontainer CLI leaves in the label unless it
# builds features, goes in a file the entrypoint sets them from.
ARG DEVCONTAINER_METADATA=
RUN [ -n "$DEVCONTAINER_METADATA" ] || exit 0; \
    user=$(python3 -c 'import json, os, re; \
m = json.loads(os.environ["DEVCONTAINER_METADATA"]); \
m = [x for x in (m if isinstance(m, list) else [m]) if isinstance(x, dict)]; \
env = {}; [env.update(x.get("containerEnv") or {}) for x in m]; \
os.makedirs("/usr/local/share/clod", exist_ok=True); \
open("/usr/local/share/clod/devcontainer.env", "w").write("".join("%s=%s\n" % (k, v) for k, v in env.items() \
  if re.match(r"[A-Za-z_][A-Za-z0-9_]*$", k) and "\n" not in str(v))); \
u = [x["remoteUser"] for x in m if x.get("remoteUser")] or [x["containerUser"] for x in m if x.get("containerUser")]; \
print(u[-1] if u else "")') \
    && if [ -n "$user" ] && [ "$user" != root ] && [ "$CLOD_UID" != 0 ] && uid=$(id -u "$user" 2>/dev/null); then \
         gid=$(id -g "$user") group=$(id -gn "$user"); \
         if [ "$uid" != "$CLOD_UID" ]; then \
           find / -xdev -uid "$uid" -exec chown -h "$CLOD_UID" {} + && usermod -o -u "$CLOD_UID" "$user"; \
         fi \
         && if [ "$gid" != "$CLOD_GID" ]; then \
           find / -xdev -gid "$gid" -exec chgrp -h "$CLOD_GID" {} + && groupmod -o -g "$CLOD_GID" "$group"; \
         fi; \
       fi

RUN groupadd -o -g $CLOD_GID claude \
    && useradd -l -m -o -u $CLOD_UID -g claude -s /bin/bash claude \
    && for f in /etc/passwd:$CLOD_UID /etc/group:$CLOD_GID; do \
         [ "${f#*:}" = 0 ] && continue; \
         awk -F: -v id=${f#*:} 'NR == FNR { if ($1 == "claude") c = $0; next } \
           $1 == "claude" { if (!done) print; done = 1; next } \
           $3 == id && !done { print c; done = 1 } { print }' ${f%:*} ${f%:*} > /tmp/ids \
         && cat /tmp/ids > ${f%:*}; \
       done \
    && rm /tmp/ids

# clod --scratch mounts an empty volume here, which takes this directory's owner.
RUN mkdir -p /workspace && chown claude:claude /workspace

# The clod launcher mounts its checkout's entrypoint.sh, container.md and
# clipboard.sh over these copies, so changes to them need no build; the copies
# serve runs without clod. A separate chmod rather than COPY --chmod, which
# needs BuildKit; Homebrew's docker on macOS has no buildx, so it builds with
# the classic builder.
# The entrypoint installs missing agents into new or existing mounted homes.
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
