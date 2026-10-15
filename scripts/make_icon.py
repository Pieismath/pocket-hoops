"""Draws the app icon: the arcade machine from the reference GIF, rendered the way the game renders it.

The icon is the top of the machine seen from above, the sign, the board and rim and a ball on the
lane, cut off above the PLAYER strip. Every pixel comes from the game's own art:

- the machine, rim and ball are the sprites in PocketHoops/GIFArt/, in their own colours;
- each is upscaled with the game's Scale2x (the rim with GIFArt.rimCanvas), ported below, so edges
  round off exactly as they do in game;
- the shooter's square is a little squatter, leaving the lane room for the ball: DROP_ROWS leaves out
  rows that repeat the row above, so every step of the rails, glass and board lines is kept;
- "SCORE!" is in PixelFont's 3×5 LCD font, read from PixelFont.swift, with the sign's drop shadow.

Simplified for the home screen (180 px): the sign's letters are full-pixel 3×5, not the game's
half-size 5×7 ones, which blur into a smear. They're lit in the Gold Rush cabinet's LED yellow.

An art pixel is 12 px (a Scale2x texel is 6), so the 1024 px icon is pixel-exact. Xcode makes the
smaller sizes from it.

Usage: python3 scripts/make_icon.py [--preview out.png]
"""
import json
import math
import re
import subprocess
import sys
import tempfile
from pathlib import Path

from PIL import Image, ImageDraw

ROOT = Path(__file__).resolve().parent.parent
ART = ROOT / "PocketHoops/GIFArt"
FONT = ROOT / "PocketHoops/Art/PixelFont.swift"
OUT = ROOT / "PocketHoops/Assets.xcassets/AppIcon.appiconset/icon-1024.png"

SIZE = 1024
TEXEL = 6               # icon pixels per Scale2x texel
ART_PX = 2 * TEXEL      # icon pixels per art pixel
TOP = 4                 # art pixels of background above the sign

CLEAR = (0, 0, 0, 0)


def rgba(h):
    return ((h >> 16) & 255, (h >> 8) & 255, h & 255, 255)


BACKGROUND = rgba(0x24ACE5)     # the Classic cabinet's background
SIGN_TEXT = rgba(0xF5C542)      # the Gold Rush cabinet's LED
SIGN_SHADOW = rgba(0x23424A)    # GameScene's sign label shadow

# GIF art rows (y down) left out of the machine, from the sides of the shooter's square. Each one
# repeats the row above it.
DROP_ROWS = {25, 30, 31}
SIGN_AT = (88, 9)       # "SCORE!": centred on the sign, filling its LCD (rows 9–13)
LANE_BALL = (93, 70)    # top-left of the ball on the lane: centred on the rim, near the bottom edge


def load(name):
    """A sprite as rows of RGBA tuples."""
    im = Image.open(ART / f"{name}.png").convert("RGBA")
    p = im.load()
    return [[p[x, y] if p[x, y][3] else CLEAR for x in range(im.width)] for y in range(im.height)]


def scale2x(g):
    """PixelCanvas.scale2x (EPX), with y down: rounds off diagonal staircases, keeps every colour."""
    h, w = len(g), len(g[0])
    at = lambda x, y: g[min(max(y, 0), h - 1)][min(max(x, 0), w - 1)]
    out = [[CLEAR] * (2 * w) for _ in range(2 * h)]
    for y in range(h):
        for x in range(w):
            p, a, b, c, d = at(x, y), at(x, y - 1), at(x + 1, y), at(x - 1, y), at(x, y + 1)
            out[2 * y][2 * x] = a if c == a and c != d and a != b else p
            out[2 * y][2 * x + 1] = b if a == b and a != c and b != d else p
            out[2 * y + 1][2 * x] = c if d == c and d != b and c != a else p
            out[2 * y + 1][2 * x + 1] = d if b == d and b != a and d != c else p
    return out


RIM_COLOURS = {rgba(0xFF1414), rgba(0xFF7373), rgba(0x000000)}


def rim_canvas(name):
    """GIFArt.rimCanvas: one rim layer, upscaled; where the seam with the other layer changes a ring
    pixel's look, it takes the look of the whole ring upscaled in one piece."""
    back = name.startswith("rim_back_")
    partner = name.replace("rim_back_", "rim_front_") if back else name.replace("rim_front_", "rim_back_")
    mine, other = load(name), load(partner)
    behind, over = (mine, other) if back else (other, mine)
    whole = [[f if f[3] else b for b, f in zip(rb, rf)] for rb, rf in zip(behind, over)]
    out, ring = scale2x(mine), scale2x(whole)
    for y, row in enumerate(out):
        for x, alone in enumerate(row):
            own, together = mine[y // 2][x // 2], ring[y][x]
            if own not in RIM_COLOURS or alone == together:
                continue
            if together in RIM_COLOURS:
                row[x] = together
            elif alone[3] == 0:
                row[x] = own
    return out


def lettering(text, colour, shadow):
    """`text` in PixelFont's 3×5 glyphs, one font pixel per art pixel, with PixelFont's drop shadow
    one texel down-right (the size of the shadow on the game's half-scale labels)."""
    source = re.search(r"static let tinyGlyphs.*?= \[(.*?)\n    \]", FONT.read_text(), re.S).group(1)
    glyphs = {k: re.findall(r'"([.#]+)"', v) for k, v in re.findall(r'"(.)": \[([^\]]*)\]', source)}
    g = [[CLEAR] * ((len(text) * 4 - 1) * 2 + 1) for _ in range(5 * 2 + 1)]
    for c, d in ((shadow, 1), (colour, 0)):
        for i, ch in enumerate(text.upper()):
            for row, line in enumerate(glyphs[ch]):
                for col, v in enumerate(line):
                    if v == "#":
                        for t in range(4):
                            g[row * 2 + t // 2 + d][(i * 4 + col) * 2 + t % 2 + d] = c
    return g


class Canvas:
    """The icon on the texel grid. Sprites are placed in art pixels (halves allowed)."""

    def __init__(self, x0, y0, n):
        self.x0, self.y0, self.n = x0, y0, n
        self.px = [[BACKGROUND] * n for _ in range(n)]

    def put(self, g, ax, ay):
        """Draws texel image `g` with its top-left at art pixel (ax, ay)."""
        tx, ty = round((ax - self.x0) * 2), round((ay - self.y0) * 2)
        for y, line in enumerate(g):
            for x, c in enumerate(line):
                if c[3] and 0 <= ty + y < self.n and 0 <= tx + x < self.n:
                    self.px[ty + y][tx + x] = c


def draw():
    layout = json.loads((ART / "layout.json").read_text())
    mx, my = layout["machineCanvas"][:2]
    rim_x, rim_y = layout["rimBox"][:2]

    machine = load("machine")
    for r in DROP_ROWS:
        assert machine[r - my] == machine[r - my - 1], f"machine.png row {r} no longer repeats row {r - 1}"
    cy = lambda y: y - sum(1 for r in DROP_ROWS if r < y)    # GIF row -> row of the shortened machine

    # The machine's centre line (x = 100) runs down the middle of the icon.
    x0, y0 = 100 - SIZE / ART_PX / 2, cy(2) - TOP
    cv = Canvas(math.floor(x0 * 2) / 2, math.floor(y0 * 2) / 2, SIZE // TEXEL + 4)

    # Back to front, in the game's z order.
    cv.put(scale2x([row for y, row in enumerate(machine) if y + my not in DROP_ROWS]), mx, my)
    cv.put(rim_canvas("rim_back_rest"), rim_x, cy(rim_y))
    cv.put(lettering("SCORE!", SIGN_TEXT, SIGN_SHADOW), SIGN_AT[0], cy(SIGN_AT[1]))
    cv.put(rim_canvas("rim_front_rest"), rim_x, cy(rim_y))
    cv.put(scale2x(load("ball_0")), LANE_BALL[0], cy(LANE_BALL[1]))

    im = Image.new("RGB", (cv.n, cv.n))
    im.putdata([c[:3] for line in cv.px for c in line])
    im = im.resize((cv.n * TEXEL, cv.n * TEXEL), Image.NEAREST)
    ox, oy = round((x0 - cv.x0) * ART_PX), round((y0 - cv.y0) * ART_PX)
    return im.crop((ox, oy, ox + SIZE, oy + SIZE))


def shrink(icon, s):
    """The icon at s px, resized the way Xcode does it (sips gives actool's pixels exactly)."""
    with tempfile.TemporaryDirectory() as d:
        src, dst = Path(d, "in.png"), Path(d, "out.png")
        icon.save(src)
        try:
            subprocess.run(["sips", "-z", str(s), str(s), str(src), "--out", str(dst)], capture_output=True, check=True)
            return Image.open(dst).convert("RGB")
        except (OSError, subprocess.CalledProcessError):
            return icon.resize((s, s), Image.LANCZOS)


def preview(icon, path):
    """The icon with the home-screen mask at 512 px, 180 px blown up ×3, and the sizes iOS shows."""
    sizes = [180, 120, 87, 80, 60, 40]
    pad, bg = 24, (242, 242, 247)

    def masked(s):
        mask = Image.new("L", (s * 4, s * 4), 0)
        ImageDraw.Draw(mask).rounded_rectangle((0, 0, s * 4 - 1, s * 4 - 1), radius=s * 4 * 0.2237, fill=255)
        tile = Image.new("RGB", (s, s), bg)
        tile.paste(shrink(icon, s), (0, 0), mask.resize((s, s), Image.LANCZOS))
        return tile

    sheet = Image.new("RGB", (512 + 540 + sum(sizes) + pad * (len(sizes) + 3), 540 + 2 * pad), bg)
    sheet.paste(masked(512), (pad, pad))
    sheet.paste(masked(180).resize((540, 540), Image.NEAREST), (512 + 2 * pad, pad))
    x = 512 + 540 + 3 * pad
    for s in sizes:
        sheet.paste(masked(s), (x, pad))
        x += s + pad
    sheet.save(path)


if __name__ == "__main__":
    icon = draw()
    icon.save(OUT)
    print("wrote", OUT.relative_to(ROOT))
    if "--preview" in sys.argv:
        preview(icon, Path(sys.argv[sys.argv.index("--preview") + 1]))
