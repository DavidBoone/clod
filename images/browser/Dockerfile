# Chromium from Debian, fonts for Latin, CJK and emoji text, and the system
# libraries Playwright's own browsers need. Chromium runs without its sandbox,
# which needs kernel features Docker doesn't allow; the container is the
# boundary instead.
FROM clod
USER root
RUN apt-get install -y chromium fonts-liberation fonts-noto-cjk fonts-noto-color-emoji \
    && echo 'export CHROMIUM_FLAGS="$CHROMIUM_FLAGS --no-sandbox"' > /etc/chromium.d/clod
RUN npx --yes playwright install-deps chromium && rm -rf /root/.npm
COPY CLAUDE.md /etc/clod/.claude/rules/browser.md
USER claude
