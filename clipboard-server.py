#!/usr/bin/env python3
"""Serves the host clipboard's image to a clod container, for Ctrl+V in Claude Code.

clod starts this on the host for a run with --clipboard, as

    clipboard-server.py ADDRESS PID TOKEN

It listens on ADDRESS (127.0.0.1 on macOS, Docker's bridge gateway on Linux)
on a free port, prints that port, and serves GET /TOKEN: 200 with the image on
the clipboard as PNG, or 204 when there is none. It reads the clipboard only
when asked, and only ever an image. It exits when process PID (clod, then the
docker run clod becomes) is gone.

CLOD_CLIPBOARD_COMMAND, if set, is a shell command that prints the clipboard's
image as PNG, in place of pngpaste or osascript (macOS), or wl-paste or xclip
(Linux).
"""

import http.server
import os
import shutil
import subprocess
import sys
import tempfile
import threading
import time

PNG = b"\x89PNG\r\n\x1a\n"

# Writes the clipboard's image to argv[0] as PNG: its PNG if it has one, else
# its TIFF (what most apps copy) converted.
JXA = """
ObjC.import('AppKit');
function run(argv) {
    var pb = $.NSPasteboard.generalPasteboard;
    var data = pb.dataForType('public.png');
    if (data.isNil()) {
        var tiff = pb.dataForType('public.tiff');
        if (tiff.isNil()) return 'none';
        var rep = $.NSBitmapImageRep.imageRepWithData(tiff);
        if (rep.isNil()) return 'none';
        data = rep.representationUsingTypeProperties(4, $({}));  // 4: PNG
    }
    data.writeToFileAtomically(argv[0], true);
    return 'ok';
}
"""


def run(cmd, **kw):
    try:
        return subprocess.run(cmd, stdin=subprocess.DEVNULL, stdout=subprocess.PIPE,
                              stderr=subprocess.DEVNULL, timeout=10, **kw).stdout
    except (OSError, subprocess.SubprocessError):
        return b""


def clipboard_png():
    """The clipboard's image as PNG bytes, or None."""
    command = os.environ.get("CLOD_CLIPBOARD_COMMAND")
    if command:
        data = run(command, shell=True)
    elif sys.platform == "darwin":
        if shutil.which("pngpaste"):
            data = run(["pngpaste", "-"])
        else:
            with tempfile.TemporaryDirectory() as tmp:
                path = os.path.join(tmp, "clip.png")
                run(["osascript", "-l", "JavaScript", "-e", JXA, path])
                try:
                    with open(path, "rb") as f:
                        data = f.read()
                except OSError:
                    data = b""
    elif os.environ.get("WAYLAND_DISPLAY"):
        types = run(["wl-paste", "--list-types"]).split()
        data = run(["wl-paste", "--type", "image/png"]) if b"image/png" in types else b""
    else:
        targets = run(["xclip", "-selection", "clipboard", "-t", "TARGETS", "-o"]).split()
        data = (run(["xclip", "-selection", "clipboard", "-t", "image/png", "-o"])
                if b"image/png" in targets else b"")
    return data if data.startswith(PNG) else None


class Handler(http.server.BaseHTTPRequestHandler):
    def do_GET(self):
        if self.path != "/" + self.server.token:
            self.send_error(404)
            return
        data = clipboard_png()
        if data is None:
            self.send_response(204)
            self.end_headers()
            return
        self.send_response(200)
        self.send_header("Content-Type", "image/png")
        self.send_header("Content-Length", str(len(data)))
        self.end_headers()
        self.wfile.write(data)

    def log_message(self, *args):
        pass


def watch(pid):
    while True:
        time.sleep(2)
        try:
            os.kill(pid, 0)
        except ProcessLookupError:
            os._exit(0)
        except PermissionError:
            pass


def main():
    address, pid, token = sys.argv[1], int(sys.argv[2]), sys.argv[3]
    try:
        server = http.server.ThreadingHTTPServer((address, 0), Handler)
    except OSError as e:
        print(f"error can't listen on {address}: {e.strerror}", flush=True)
        sys.exit(1)
    server.token = token
    print(server.server_address[1], flush=True)
    # Nothing else reads this process's output: clod has exec'd docker run,
    # which owns the terminal.
    devnull = os.open(os.devnull, os.O_RDWR)
    for fd in 0, 1, 2:
        os.dup2(devnull, fd)
    threading.Thread(target=watch, args=(pid,), daemon=True).start()
    server.serve_forever()


if __name__ == "__main__":
    main()
