#!/usr/bin/env python3
"""Generate macOS app icons and website assets for AutoSuggest.

Uses pure Python (struct + zlib) to write valid PNGs — no Pillow required.
"""

import math
import os
import struct
import zlib

# ── Palette ──────────────────────────────────────────────────────────
TEAL = (10, 147, 150)       # #0A9396
WHITE = (255, 255, 255)
CORAL = (231, 111, 81)      # #E76F51
DARK = (26, 26, 26)         # #1A1A1A
LIGHT_BG = (250, 250, 248)  # website OG background

# ── Paths ────────────────────────────────────────────────────────────
REPO = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
APPICONSET = os.path.join(
    REPO, "macos", "AutoSuggestDesktop", "Assets.xcassets",
    "AppIcon.appiconset"
)
WEBSITE = os.path.join(REPO, "website")

ICON_SIZES = [16, 32, 64, 128, 256, 512, 1024]


# ── Pure-Python PNG writer ───────────────────────────────────────────

def _make_png(width: int, height: int, pixels: list[list[tuple[int, int, int, int]]]) -> bytes:
    """Create a PNG file from RGBA pixel data."""

    def _chunk(chunk_type: bytes, data: bytes) -> bytes:
        c = chunk_type + data
        crc = struct.pack(">I", zlib.crc32(c) & 0xFFFFFFFF)
        return struct.pack(">I", len(data)) + c + crc

    sig = b"\x89PNG\r\n\x1a\n"
    ihdr = _chunk(b"IHDR", struct.pack(">IIBBBBB", width, height, 8, 6, 0, 0, 0))

    raw = bytearray()
    for row in pixels:
        raw.append(0)  # filter byte
        for r, g, b, a in row:
            raw.extend((r, g, b, a))

    compressed = zlib.compress(bytes(raw), 9)
    idat = _chunk(b"IDAT", compressed)
    iend = _chunk(b"IEND", b"")
    return sig + ihdr + idat + iend


def _blend(bg: tuple, fg: tuple, alpha: float) -> tuple:
    """Alpha-blend fg over bg."""
    return tuple(int(b * (1 - alpha) + f * alpha) for b, f in zip(bg, fg))


def _dist(x1, y1, x2, y2):
    return math.sqrt((x1 - x2) ** 2 + (y1 - y2) ** 2)


# ── Icon renderer ────────────────────────────────────────────────────

def render_icon(size: int) -> list[list[tuple[int, int, int, int]]]:
    """Render the AutoSuggest icon at a given size."""
    pixels = [[(*TEAL, 255)] * size for _ in range(size)]
    s = size  # alias

    # Corner radius (rounded rect mask)
    radius = s * 0.18
    for y in range(s):
        for x in range(s):
            # Check four corners
            corners = [
                (radius, radius),
                (s - radius - 1, radius),
                (radius, s - radius - 1),
                (s - radius - 1, s - radius - 1),
            ]
            inside = True
            for cx, cy in corners:
                if (x < radius or x > s - radius - 1) and (y < radius or y > s - radius - 1):
                    if _dist(x, y, cx, cy) > radius:
                        pixels[y][x] = (0, 0, 0, 0)
                        inside = False
                        break

    # I-beam cursor (centered-left area)
    beam_cx = s * 0.38
    beam_top = s * 0.22
    beam_bot = s * 0.78
    beam_w = max(1, s * 0.035)
    serif_w = s * 0.10
    serif_h = max(1, s * 0.035)

    for y in range(s):
        for x in range(s):
            if pixels[y][x][3] == 0:
                continue
            # Vertical bar
            if abs(x - beam_cx) <= beam_w / 2 and beam_top <= y <= beam_bot:
                pixels[y][x] = (*WHITE, 255)
            # Top serif
            if abs(y - beam_top) <= serif_h / 2 and abs(x - beam_cx) <= serif_w:
                pixels[y][x] = (*WHITE, 255)
            # Bottom serif
            if abs(y - beam_bot) <= serif_h / 2 and abs(x - beam_cx) <= serif_w:
                pixels[y][x] = (*WHITE, 255)

    # Text lines (right side)
    line_x_start = s * 0.55
    line_heights = [0.32, 0.44, 0.56, 0.68]
    line_widths = [0.30, 0.25, 0.28, 0.18]
    line_h = max(1, s * 0.030)

    for i, (ly_frac, lw_frac) in enumerate(zip(line_heights, line_widths)):
        ly = s * ly_frac
        lw = s * lw_frac
        for y in range(s):
            for x in range(s):
                if pixels[y][x][3] == 0:
                    continue
                if abs(y - ly) <= line_h / 2 and line_x_start <= x <= line_x_start + lw:
                    alpha = 0.75 if i < 2 else 0.45
                    bg = pixels[y][x][:3]
                    blended = _blend(bg, WHITE, alpha)
                    pixels[y][x] = (*blended, 255)

    # Coral sparkle (top-right area)
    sparkle_cx = s * 0.75
    sparkle_cy = s * 0.22
    sparkle_r = s * 0.06

    for y in range(s):
        for x in range(s):
            if pixels[y][x][3] == 0:
                continue
            d = _dist(x, y, sparkle_cx, sparkle_cy)
            if d <= sparkle_r:
                alpha = max(0, 1.0 - d / sparkle_r)
                bg = pixels[y][x][:3]
                blended = _blend(bg, CORAL, alpha * 0.9)
                pixels[y][x] = (*blended, 255)

    # Four-point star at sparkle center
    star_arm = s * 0.04
    star_w = max(1, s * 0.012)
    for y in range(s):
        for x in range(s):
            if pixels[y][x][3] == 0:
                continue
            dx = abs(x - sparkle_cx)
            dy = abs(y - sparkle_cy)
            if (dx <= star_w and dy <= star_arm) or (dy <= star_w and dx <= star_arm):
                pixels[y][x] = (*CORAL, 255)

    return pixels


def render_og_image(width: int, height: int) -> list[list[tuple[int, int, int, int]]]:
    """Render an OG image (1200x630) with branding."""
    pixels = [[(*LIGHT_BG, 255)] * width for _ in range(height)]

    # Centered icon area
    icon_size = 200
    icon = render_icon(icon_size)
    ox = (width - icon_size) // 2
    oy = (height - icon_size) // 2 - 60

    for iy in range(icon_size):
        for ix in range(icon_size):
            px = icon[iy][ix]
            if px[3] > 0:
                pixels[oy + iy][ox + ix] = px

    # Simple text bar below icon
    bar_y = oy + icon_size + 30
    bar_h = 6
    bar_w = 300
    bar_x = (width - bar_w) // 2
    for y in range(bar_y, min(bar_y + bar_h, height)):
        for x in range(bar_x, min(bar_x + bar_w, width)):
            pixels[y][x] = (*TEAL, 255)

    return pixels


# ── Main ─────────────────────────────────────────────────────────────

def main():
    os.makedirs(APPICONSET, exist_ok=True)
    os.makedirs(WEBSITE, exist_ok=True)

    # Generate app icons
    print("Generating app icons...")
    for size in ICON_SIZES:
        icon = render_icon(size)
        png = _make_png(size, size, icon)
        path = os.path.join(APPICONSET, f"icon_{size}x{size}.png")
        with open(path, "wb") as f:
            f.write(png)
        print(f"  {path} ({size}x{size})")

    # Contents.json for appiconset
    images = []
    size_map = {
        16: [("16x16", "1x"), ("16x16", "2x")],
        32: [("16x16", "2x"), ("32x32", "1x")],
        64: [("32x32", "2x")],
        128: [("128x128", "1x")],
        256: [("128x128", "2x"), ("256x256", "1x")],
        512: [("256x256", "2x"), ("512x512", "1x")],
        1024: [("512x512", "2x")],
    }
    seen = set()
    for px_size in ICON_SIZES:
        for size_str, scale in size_map.get(px_size, []):
            key = (size_str, scale)
            if key in seen:
                continue
            seen.add(key)
            images.append({
                "filename": f"icon_{px_size}x{px_size}.png",
                "idiom": "mac",
                "scale": scale,
                "size": size_str,
            })

    import json
    contents = {"images": images, "info": {"author": "xcode", "version": 1}}
    contents_path = os.path.join(APPICONSET, "Contents.json")
    with open(contents_path, "w") as f:
        json.dump(contents, f, indent=2)
    print(f"  {contents_path}")

    # Website assets
    print("Generating website assets...")

    # favicon.png (32x32)
    favicon = render_icon(32)
    with open(os.path.join(WEBSITE, "favicon.png"), "wb") as f:
        f.write(_make_png(32, 32, favicon))
    print(f"  website/favicon.png")

    # apple-touch-icon.png (180x180)
    touch = render_icon(180)
    with open(os.path.join(WEBSITE, "apple-touch-icon.png"), "wb") as f:
        f.write(_make_png(180, 180, touch))
    print(f"  website/apple-touch-icon.png")

    # og-image.png (1200x630)
    og = render_og_image(1200, 630)
    with open(os.path.join(WEBSITE, "og-image.png"), "wb") as f:
        f.write(_make_png(1200, 630, og))
    print(f"  website/og-image.png")

    print("Done!")


if __name__ == "__main__":
    main()
