"""Generate Media/glow.tga: a white square glow ring for the 5-stack highlight.

The texture is 128x128. The icon covers the centre 64x64 (transparent);
around it is a crisp border line and a soft glow with rounded corners.
The addon tints it with SetVertexColor, so it is pure white + alpha.

Run:  python tools/make_glow.py
"""
import math
import os
import struct

SIZE = 128          # texture size (power of two)
INNER = 32          # half-size of the transparent icon area
BORDER = 3          # crisp border width (texture px)
GLOW = SIZE // 2 - INNER  # glow reaches the texture edge
GLOW_STRENGTH = 0.85

out = os.path.join(os.path.dirname(__file__), "..", "MaelstromTracker", "Media", "glow.tga")
os.makedirs(os.path.dirname(out), exist_ok=True)

c = (SIZE - 1) / 2
pixels = bytearray()
for y in range(SIZE):
    for x in range(SIZE):
        # Distance from the inner square (0 inside), Euclidean -> round corners.
        dx = max(abs(x - c) - INNER, 0)
        dy = max(abs(y - c) - INNER, 0)
        d = math.hypot(dx, dy)
        if abs(x - c) <= INNER and abs(y - c) <= INNER:
            a = 0.0
        elif d <= BORDER:
            a = 1.0
        else:
            t = min((d - BORDER) / (GLOW - BORDER), 1.0)
            a = GLOW_STRENGTH * (1 - t) ** 2
        pixels += bytes((255, 255, 255, round(a * 255)))  # BGRA

# Uncompressed 32-bit TGA, top-left origin (descriptor 0x28).
header = struct.pack("<BBBHHBHHHHBB", 0, 0, 2, 0, 0, 0, 0, 0, SIZE, SIZE, 32, 0x28)
with open(out, "wb") as fh:
    fh.write(header + pixels)
print("wrote", os.path.abspath(out))
