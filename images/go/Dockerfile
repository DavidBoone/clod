# The latest Go release from go.dev, as of when the image is built. Modules and
# installed tools go to ~/go in the home.
FROM clod
USER root
RUN version=$(curl -fsSL 'https://go.dev/VERSION?m=text' | head -1) \
    && curl -fsSL "https://go.dev/dl/$version.linux-$(dpkg --print-architecture).tar.gz" \
       | tar -C /usr/local -xz
USER claude
ENV PATH="/usr/local/go/bin:/home/claude/go/bin:$PATH"
