# Browser

This image has Chromium at `/usr/bin/chromium`, with fonts for Latin, CJK and emoji text.

- Screenshot: `chromium --headless --screenshot=out.png --window-size=W,H URL`. Without `--window-size` the viewport is a small 780×493, so set the size the task calls for. It already runs without its sandbox. The "Failed to connect to the bus" and D-Bus errors it logs are expected in a container and harmless. A failed load shows as "Page load failed" with no output file, and the exit status is 0 either way, so check that the file exists.
- Playwright: launch it with `executable_path="/usr/bin/chromium"` (Python) or `executablePath: "/usr/bin/chromium"` (Node) instead of installing a browser. That suits scripts. A test suite (pytest-playwright, `@playwright/test`) that expects the browser of its pinned Playwright version needs that browser installed, which belongs in the image rather than the home: suggest the user add to their variant, as root, `ENV PLAYWRIGHT_BROWSERS_PATH=/opt/ms-playwright` and `RUN npx --yes playwright@<version> install chromium`, with the version the project pins.
