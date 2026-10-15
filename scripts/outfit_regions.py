"""Body-part labelling for the kid sprites (GIFArt/kid_<pose>.png).

The reference art draws each part of the shooter in its own colours, so every pixel of every
pose can be labelled: hair, head skin (ears/neck), arm (split into sleeve length and hand),
shirt, pants, shoes, the ball being held, outline. make_outfits.py draws hats, clothes and
characters onto those labels, so every item fits all ten poses.
"""
import json
from collections import deque
from pathlib import Path

from PIL import Image

ART = Path(__file__).resolve().parent.parent / "PocketHoops" / "GIFArt"
POSES = ["reach", "lift", "hold", "crouch", "jump", "follow1", "follow2", "follow3", "idle", "ready"]

HAIR = {0x3C220D, 0x5B3516, 0x211205, 0x6C4A2E, 0x533114, 0x64452C}
SKIN = {0xFED5B3, 0xEAAB76, 0xCA8347}
SHIRT = {0xC9C9C9, 0xB5B5B5, 0x8D8D8D, 0xE5E5E5}
PANTS = {0x4F84A5, 0x1C5375}
BALLRED, BALLWHITE, SHOEDARK = 0xD42C2C, 0xFFFFFF, 0xBD2828
BLACK = 0x000000

EMPTY, OUTLINE, HAIRL, HEADSKIN, ARM, HAND, SHIRTL, PANTSL, SHOES, BALL = range(10)
NAMES = ["empty", "outline", "hair", "headskin", "arm", "hand", "shirt", "pants", "shoes", "ball"]


def hexof(px):
    return (px[0] << 16) | (px[1] << 8) | px[2]


class Pose:
    def __init__(self, name):
        self.name = name
        self.img = Image.open(ART / f"kid_{name}.png").convert("RGBA")
        self.w, self.h = self.img.size
        self.px = self.img.load()
        layout = json.loads((ART / "layout.json").read_text())
        self.ballbox = (layout["kidBall"].get(name) or {}).get("ball")
        self.label = [[EMPTY] * self.w for _ in range(self.h)]
        self.armdist = {}
        self._label()

    def colour(self, x, y):
        p = self.px[x, y]
        return None if p[3] == 0 else hexof(p)

    def inball(self, x, y):
        b = self.ballbox
        return b is not None and b[0] <= x < b[2] and b[1] <= y < b[3]

    def cells(self, lab):
        return [(x, y) for y in range(self.h) for x in range(self.w) if self.label[y][x] == lab]

    def bbox(self, lab):
        cs = self.cells(lab)
        if not cs:
            return None
        xs = [c[0] for c in cs]; ys = [c[1] for c in cs]
        return min(xs), min(ys), max(xs), max(ys)

    def _label(self):
        L = self.label
        for y in range(self.h):
            for x in range(self.w):
                c = self.colour(x, y)
                if c is None:
                    continue
                if c in HAIR: L[y][x] = HAIRL
                elif c in SKIN: L[y][x] = ARM  # split into head skin / arm / hand below
                elif c in SHIRT: L[y][x] = SHIRTL
                elif c in PANTS: L[y][x] = PANTSL
                elif c in (BALLRED, BALLWHITE, SHOEDARK):
                    L[y][x] = BALL if self.inball(x, y) and c != SHOEDARK else SHOES
                elif c == BLACK: L[y][x] = OUTLINE
        # The ball's own outline: black pixels in the ball box touching ball colour.
        if self.ballbox:
            for y in range(self.h):
                for x in range(self.w):
                    if L[y][x] == OUTLINE and self.inball(x, y) and any(
                            L[y + dy][x + dx] == BALL for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1))
                            if 0 <= x + dx < self.w and 0 <= y + dy < self.h):
                        L[y][x] = BALL
        # Head skin: ears and neck — skin inside the head's columns, from the hair down to the shirt.
        hx0, hy0, hx1, hy1 = self.bbox(HAIRL)
        shirt = self.bbox(SHIRTL)
        top_of_shirt = shirt[1] if shirt else hy1 + 2
        for y in range(hy0, top_of_shirt + 1):
            for x in range(hx0 - 1, hx1 + 2):
                if 0 <= x < self.w and L[y][x] == ARM and self._near_hair(x, y):
                    L[y][x] = HEADSKIN
        # Arms: distance (through skin) from the shoulder, where the arm meets the shirt.
        seeds = [(x, y) for (x, y) in self.cells(ARM) if self._near(x, y, SHIRTL, 2)]
        dist = {s: 0 for s in seeds}
        q = deque(seeds)
        while q:
            x, y = q.popleft()
            for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1), (1, 1), (-1, -1), (1, -1), (-1, 1)):
                n = (x + dx, y + dy)
                if 0 <= n[0] < self.w and 0 <= n[1] < self.h and L[n[1]][n[0]] == ARM and n not in dist:
                    dist[n] = dist[(x, y)] + 1
                    q.append(n)
        # Skin not reached from a shoulder (e.g. an arm drawn apart from the body) counts as arm too.
        far = max(dist.values()) if dist else 0
        for c in self.cells(ARM):
            dist.setdefault(c, far)
        self.armdist = dist
        # Hands: the last few pixels of each arm.
        for (x, y), d in dist.items():
            if d >= far - 2 and far >= 4:
                L[y][x] = HAND

    def _near_hair(self, x, y):
        return self._near(x, y, HAIRL, 2) or self._near(x, y, HEADSKIN, 1)

    def _near(self, x, y, lab, r):
        for dy in range(-r, r + 1):
            for dx in range(-r, r + 1):
                nx, ny = x + dx, y + dy
                if 0 <= nx < self.w and 0 <= ny < self.h and self.label[ny][nx] == lab:
                    return True
        return False


def load_all():
    return [Pose(p) for p in POSES]


if __name__ == "__main__":
    import sys
    out = Path(sys.argv[1]) if len(sys.argv) > 1 else Path("regions.png")
    cols = {EMPTY: (60, 160, 220, 255), OUTLINE: (0, 0, 0, 255), HAIRL: (120, 70, 20, 255), HEADSKIN: (255, 170, 0, 255),
            ARM: (255, 120, 200, 255), HAND: (255, 255, 0, 255), SHIRTL: (180, 180, 180, 255), PANTSL: (40, 90, 200, 255),
            SHOES: (0, 220, 120, 255), BALL: (230, 30, 30, 255)}
    poses = load_all()
    k = 6
    sheet = Image.new("RGBA", (len(poses) * (44 * k + 6), 66 * k), (255, 255, 255, 255))
    for i, p in enumerate(poses):
        im = Image.new("RGBA", (p.w, p.h))
        for y in range(p.h):
            for x in range(p.w):
                im.putpixel((x, y), cols[p.label[y][x]])
        sheet.paste(im.resize((p.w * k, p.h * k), Image.NEAREST), (i * (44 * k + 6), 0))
    sheet.save(out)
    print("wrote", out)
