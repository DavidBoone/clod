# uv, and the C toolchain and Python headers for packages that build native
# extensions. Python versions uv installs and its cache go to the home.
ARG BASE=clod
FROM $BASE
USER root
RUN apt-get install -y build-essential python3-dev
RUN curl -LsSf https://astral.sh/uv/install.sh | env UV_INSTALL_DIR=/usr/local/bin UV_NO_MODIFY_PATH=1 sh
USER claude
# The cache (home) and a project's venv (workspace) are separate mounts, so uv
# can't hardlink between them.
ENV UV_LINK_MODE=copy
