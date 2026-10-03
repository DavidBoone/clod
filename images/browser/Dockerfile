# The system libraries Playwright's Chromium needs. Browsers themselves install
# into the home with `npx playwright install chromium`.
FROM clod
USER root
RUN npx --yes playwright install-deps chromium && rm -rf /root/.npm
USER claude
