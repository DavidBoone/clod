# Browser

This image has Chromium at `/usr/bin/chromium`, with fonts for Latin, CJK and emoji text.

- Screenshot: `chromium --headless --screenshot=out.png --window-size=1280,800 URL`
- Playwright: launch it with `executable_path="/usr/bin/chromium"` (Python) or `executablePath: "/usr/bin/chromium"` (Node) instead of installing a browser.
