# Development tooling on top of the base: compilers and build tools, pip, the
# GitHub CLI, vim, and the system libraries Playwright's Chromium needs.
FROM clod
USER root
RUN apt-get install -y \
       build-essential python3-pip \
       gh vim
RUN npx --yes playwright install-deps chromium && rm -rf /root/.npm
USER claude
