# Passwordless sudo for claude, so the agent can install packages or change
# system files while it runs. Changes outside the home and workspace are lost
# when the container exits; put anything wanted every run in a variant's
# Dockerfile instead. Combine it with another variant: clod -i go+sudo.
ARG BASE=clod
FROM $BASE
USER root
RUN apt-get install -y sudo \
    && echo 'claude ALL=(ALL) NOPASSWD:ALL' > /etc/sudoers.d/claude \
    && chmod 440 /etc/sudoers.d/claude
COPY CLAUDE.md /etc/clod/.claude/rules/sudo.md
USER claude
