# The Docker CLI with the buildx and compose plugins, from Docker's Debian
# package repository. There is no daemon: run with clod --docker, the CLI
# drives the host's Docker through its socket.
ARG BASE=clod
FROM $BASE
USER root
RUN curl -fsSL https://download.docker.com/linux/debian/gpg -o /etc/apt/keyrings/docker.asc \
    && printf '%s\n' 'Types: deb' 'URIs: https://download.docker.com/linux/debian' \
       "Suites: $(. /etc/os-release && echo "$VERSION_CODENAME")" 'Components: stable' \
       'Signed-By: /etc/apt/keyrings/docker.asc' \
       > /etc/apt/sources.list.d/docker.sources \
    && apt-get update \
    && apt-get install -y docker-ce-cli docker-buildx-plugin docker-compose-plugin
COPY CLAUDE.md /etc/clod/.claude/rules/docker.md
USER claude
