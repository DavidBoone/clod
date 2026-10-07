"""Prints a picture file's first frame as a base64 PNG of at most MAX_BYTES.

Usage: python3 convert.py PATH MAX_SIDE MAX_BYTES
"""
import base64
import io
import sys

try:
    from PIL import Image, ImageOps
except ImportError:
    sys.exit("Pillow (python3-pil) is not installed")

path, max_side, max_bytes = sys.argv[1], int(sys.argv[2]), int(sys.argv[3])
try:
    with Image.open(path) as image:
        image.seek(0)
        image = ImageOps.exif_transpose(image)
        if image.mode not in ("1", "L", "LA", "P", "RGB", "RGBA"):
            image = image.convert("RGBA" if "A" in image.getbands() else "RGB")
        side = max_side
        while True:
            image.thumbnail((side, side))
            out = io.BytesIO()
            image.save(out, "PNG")
            if out.tell() <= max_bytes or side < 64:
                break
            side = side * 3 // 4
except (OSError, ValueError, Image.DecompressionBombError) as err:
    sys.exit(str(err))
if out.tell() > max_bytes:
    sys.exit("too large to show")
sys.stdout.write(base64.b64encode(out.getvalue()).decode())
