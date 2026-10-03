#!/usr/bin/env python3
"""Renders terminal text with 16-colour ANSI escapes (from stdin) as an SVG
terminal panel (to stdout), for pictures in the README.

Each line is drawn with textLength, so viewers fit it to the panel's width
whatever monospace font they have; glyph widths vary between fonts."""
import html
import re
import sys

# VS Code's dark terminal palette, indexed by SGR code.
COLORS = {
    30: "#000000", 31: "#cd3131", 32: "#0dbc79", 33: "#e5e510",
    34: "#2472c8", 35: "#bc3fbc", 36: "#11a8cd", 37: "#e5e5e5",
    90: "#666666", 91: "#f14c4c", 92: "#23d18b", 93: "#f5f543",
    94: "#3b8eea", 95: "#d670d6", 96: "#29b8db", 97: "#e5e5e5",
}
FG, BG = "#cccccc", "#1e1e1e"
FONT_SIZE, CHAR_W, LINE_H, PAD = 14, 8.4, 22, 18


def spans(line):
    """Yields (text, fill, bold, dim) runs for one line."""
    fill, bold, dim = FG, False, False
    for part in re.split(r"(\x1b\[[0-9;]*m)", line):
        m = re.fullmatch(r"\x1b\[([0-9;]*)m", part)
        if not m:
            if part:
                yield part, fill, bold, dim
            continue
        for code in (int(c) for c in (m.group(1) or "0").split(";")):
            if code == 0:
                fill, bold, dim = FG, False, False
            elif code == 1:
                bold = True
            elif code == 2:
                dim = True
            elif code in COLORS:
                fill = COLORS[code]


def main():
    lines = sys.stdin.read().rstrip("\n").split("\n")
    plain = [re.sub(r"\x1b\[[0-9;]*m", "", l) for l in lines]
    width = round(max(len(l) for l in plain) * CHAR_W + 2 * PAD)
    height = len(lines) * LINE_H + 2 * PAD - (LINE_H - FONT_SIZE)
    out = [
        f'<svg xmlns="http://www.w3.org/2000/svg" width="{width}" height="{height}" '
        f'viewBox="0 0 {width} {height}">',
        f'<rect width="{width}" height="{height}" rx="8" fill="{BG}"/>',
    ]
    font = ('font-family="ui-monospace, SFMono-Regular, Menlo, Consolas, monospace" '
            f'font-size="{FONT_SIZE}" xml:space="preserve"')
    for i, line in enumerate(lines):
        y = PAD + FONT_SIZE + i * LINE_H - 3
        runs = "".join(
            f'<tspan fill="{fill}"'
            + (' font-weight="bold"' if bold else "")
            + (' opacity="0.5"' if dim else "")
            + f">{html.escape(text)}</tspan>"
            for text, fill, bold, dim in spans(line)
        )
        length = round(len(plain[i]) * CHAR_W)
        out.append(f'<text x="{PAD}" y="{y}" textLength="{length}" '
                   f'lengthAdjust="spacingAndGlyphs" {font}>{runs}</text>')
    out.append("</svg>")
    print("\n".join(out))


if __name__ == "__main__":
    main()
