#!/usr/bin/env python3
"""Renders terminal text with 16-colour ANSI escapes, 256-colour greys as
backgrounds and OSC 8 links (from stdin) as an SVG terminal panel (to stdout),
for pictures in the docs.

Each run of text is placed at its column and drawn with textLength, so viewers
fit it to the grid whatever monospace font they have; glyph widths vary between
fonts."""
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
OSC8 = re.compile(r"\x1b\]8;[^\x07\x1b]*(?:\x07|\x1b\\)")


def grey(n):
    """The colour of 256-colour greyscale index n (232 to 255)."""
    v = 8 + (n - 232) * 10
    return f"#{v:02x}{v:02x}{v:02x}"


def spans(line):
    """Yields (text, fill, bold, dim, underline, background) runs for one line."""
    fill, bold, dim, under, back = FG, False, False, False, None
    for part in re.split(r"(\x1b\[[0-9;]*m)", OSC8.sub("", line)):
        m = re.fullmatch(r"\x1b\[([0-9;]*)m", part)
        if not m:
            if part:
                yield part, fill, bold, dim, under, back
            continue
        codes = [int(c) for c in (m.group(1) or "0").split(";")]
        while codes:
            code = codes.pop(0)
            if code == 0:
                fill, bold, dim, under, back = FG, False, False, False, None
            elif code == 1:
                bold = True
            elif code == 2:
                dim = True
            elif code == 4:
                under = True
            elif code == 49:
                back = None
            elif code in (38, 48) and codes[:1] == [5]:
                n = codes[1]
                codes = codes[2:]
                if code == 48 and n >= 232:
                    back = grey(n)
            elif code in COLORS:
                fill = COLORS[code]


def main():
    lines = sys.stdin.read().rstrip("\n").split("\n")
    rows = [list(spans(l)) for l in lines]
    cols = max(sum(len(r[0]) for r in row) for row in rows)
    width = round(cols * CHAR_W + 2 * PAD)
    height = len(lines) * LINE_H + 2 * PAD - (LINE_H - FONT_SIZE)
    out = [
        f'<svg xmlns="http://www.w3.org/2000/svg" width="{width}" height="{height}" '
        f'viewBox="0 0 {width} {height}">',
        f'<rect width="{width}" height="{height}" rx="8" fill="{BG}"/>',
    ]
    font = ('font-family="ui-monospace, SFMono-Regular, Menlo, Consolas, monospace" '
            f'font-size="{FONT_SIZE}" xml:space="preserve"')
    for i, row in enumerate(rows):
        y = PAD + FONT_SIZE + i * LINE_H - 3
        col = 0
        for text, fill, bold, dim, under, back in row:
            x = round(PAD + col * CHAR_W, 1)
            length = round(len(text) * CHAR_W, 1)
            if back:
                out.append(f'<rect x="{x}" y="{y - FONT_SIZE + 1}" width="{length}" '
                           f'height="{FONT_SIZE + 4}" fill="{back}"/>')
            if text.strip():
                out.append(
                    f'<text x="{x}" y="{y}" textLength="{length}" '
                    f'lengthAdjust="spacingAndGlyphs" {font} fill="{fill}"'
                    + (' font-weight="bold"' if bold else "")
                    + (' opacity="0.5"' if dim else "")
                    + (' text-decoration="underline"' if under else "")
                    + f">{html.escape(text)}</text>")
            col += len(text)
    out.append("</svg>")
    print("\n".join(out))


if __name__ == "__main__":
    main()
