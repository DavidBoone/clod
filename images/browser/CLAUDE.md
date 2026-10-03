# Browser

This image has Chromium at `/usr/bin/chromium`, with fonts for Latin, CJK and emoji text.

- Screenshot: `chromium --headless --screenshot=out.png --window-size=1280,800 URL`. It already runs without its sandbox. The "Failed to connect to the bus" and D-Bus errors it logs are expected in a container and harmless. A failed load shows as "Page load failed" with no output file, and the exit status is 0 either way, so check that the file exists.
- Playwright: launch it with `executable_path="/usr/bin/chromium"` (Python) or `executablePath: "/usr/bin/chromium"` (Node) instead of installing a browser.
