"""Draws the shooter's customisation art: characters and hats/shirts/jackets/pants/shoes.

Every item is drawn onto the body-part labels of the ten kid poses (see outfit_regions.py), in
the reference art's style: the GIF's black outlines, and shading ramps built like the GIF's own
(each material gets a light, mid and shadow tone, cooling slightly into the shadows).
Output, all in PocketHoops/GIFArt/:

- outfit_avatar_<id>.png — a character's whole body, one 44×66 cell per pose (in POSES order);
- outfit_hair_<id>.png   — hair a character wears *over* its clothes (a ponytail), same layout;
- outfit_acc_<id>.png    — an accessory: only its own pixels, same layout;
- outfits.json           — pose order, cell size and each character's skin tones.

Accessories that show skin (shorts) paint it in SKIN_KEYS placeholder colours, which the game
swaps for the current character's skin. Nothing is painted in the ball's exact red or white,
which the game recolours for the equipped ball skin.

Usage: python3 scripts/make_outfits.py [--preview out.png]
"""
import colorsys
import json
import math
import sys
from pathlib import Path

from PIL import Image, ImageDraw

sys.path.insert(0, str(Path(__file__).resolve().parent))
from outfit_regions import (ARM, ART, BALL, EMPTY, HAIRL, HAND, HEADSKIN, OUTLINE, PANTSL,  # noqa: E402
                            POSES, SHIRTL, SHOES, hexof, load_all)

W, H = 44, 66
BLACK = 0x000000
SKIN_KEYS = [0xFF00F0, 0xFF00F1, 0xFF00F2]  # light, mid, shadow skin placeholders
BALL_COLOURS = {0xD42C2C, 0xFFFFFF}

# The reference art's own ramps (light → dark), to read each pixel's shade.
ORIG = {
    "shirt": [0xE5E5E5, 0xC9C9C9, 0xB5B5B5, 0x8D8D8D],
    "pants": [0x4F84A5, 0x1C5375],
    "skin": [0xFED5B3, 0xEAAB76, 0xCA8347],
    "hair": [0x6C4A2E, 0x64452C, 0x5B3516, 0x533114, 0x3C220D, 0x211205],
}
KIND = {SHIRTL: "shirt", PANTSL: "pants", HEADSKIN: "skin", ARM: "skin", HAND: "skin", HAIRL: "hair"}

POSES_DATA = load_all()


# --------------------------------------------------------------------------------------------
# Colour helpers.

def safe(h):
    """Never the ball's exact red/white (the game recolours those for the ball skin)."""
    return h - 0x010101 if h in BALL_COLOURS else h


def rgba(h):
    return ((h >> 16) & 255, (h >> 8) & 255, h & 255, 255)


def shade(h, v=1.0, s=1.0, hue=0.0):
    r, g, b = ((h >> 16) & 255) / 255, ((h >> 8) & 255) / 255, (h & 255) / 255
    hh, ss, vv = colorsys.rgb_to_hsv(r, g, b)
    hh = (hh + hue / 360) % 1
    r, g, b = colorsys.hsv_to_rgb(hh, min(1, ss * s), max(0, min(1, vv * v)))
    return safe((int(round(r * 255)) << 16) | (int(round(g * 255)) << 8) | int(round(b * 255)))


def ramp(light, n, dark=0.62):
    """n tones from `light` down to `dark`× its brightness, a little more saturated and cooler."""
    if n == 1:
        return [safe(light)]
    return [shade(light, v=1 - (1 - dark) * i / (n - 1), s=1 + 0.2 * i / (n - 1), hue=-5 * i / (n - 1))
            for i in range(n)]


def tone(tones, lab, c):
    """The new colour for an original pixel: its step in the reference ramp, mapped onto `tones`."""
    r = ORIG[KIND[lab]]
    k = r.index(c) if c in r else 0
    return tones[min(len(tones) - 1, round(k * (len(tones) - 1) / max(1, len(r) - 1)))]


# --------------------------------------------------------------------------------------------
# Layers: one image per pose.

class Layer:
    def __init__(self, base=False):
        self.cells = [p.img.copy() if base else Image.new("RGBA", (W, H), (0, 0, 0, 0)) for p in POSES_DATA]

    def put(self, i, x, y, c):
        if 0 <= x < W and 0 <= y < H:
            self.cells[i].putpixel((x, y), rgba(c) if isinstance(c, int) else c)

    def clear(self, i, x, y):
        if 0 <= x < W and 0 <= y < H:
            self.cells[i].putpixel((x, y), (0, 0, 0, 0))

    def at(self, i, x, y):
        if 0 <= x < W and 0 <= y < H:
            a = self.cells[i].getpixel((x, y))
            return None if a[3] == 0 else hexof(a)
        return None

    def sheet(self):
        s = Image.new("RGBA", (W * len(POSES), H), (0, 0, 0, 0))
        for i, c in enumerate(self.cells):
            s.paste(c, (i * W, 0))
        return s


def pixels(p, *labs):
    return [(x, y) for y in range(H) for x in range(W) if p.label[y][x] in labs]


def orig(p, x, y):
    return p.colour(x, y) or 0


def repaint(layer, i, p, labs, tones, pattern=None):
    """Repaint body parts keeping the reference shading; `pattern(x, y, colour)` may override."""
    for (x, y) in pixels(p, *labs):
        c = tone(tones, p.label[y][x], orig(p, x, y))
        if pattern:
            c = pattern(x, y, c) or c
        layer.put(i, x, y, safe(c))


def outline(layer, i, p, only_new=True):
    """Black outline around what the layer added outside the kid's silhouette."""
    cell = layer.cells[i]
    adds = []
    for y in range(H):
        for x in range(W):
            if cell.getpixel((x, y))[3]:
                continue
            if only_new and p.label[y][x] != EMPTY:
                continue
            for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1)):
                nx, ny = x + dx, y + dy
                if 0 <= nx < W and 0 <= ny < H and cell.getpixel((nx, ny))[3] and hexof(cell.getpixel((nx, ny))) != BLACK \
                        and p.label[ny][nx] == EMPTY:
                    adds.append((x, y))
                    break
    for (x, y) in adds:
        layer.put(i, x, y, BLACK)


def keep_ball(layer, i, p, restore=False):
    """Nothing covers the ball being held (a body layer puts the original ball back)."""
    for (x, y) in pixels(p, BALL):
        if restore:
            layer.put(i, x, y, p.img.getpixel((x, y)))
        else:
            layer.clear(i, x, y)


def head(p):
    return p.bbox(HAIRL)


def centre_x(p):
    hx0, _, hx1, _ = head(p)
    return (hx0 + hx1) // 2


TINY = {
    "1": [".#.", "##.", ".#.", ".#.", "###"], "2": ["###", "..#", "###", "#..", "###"],
    "3": ["###", "..#", "###", "..#", "###"], "7": ["###", "..#", ".#.", ".#.", ".#."],
    "P": ["##.", "#.#", "##.", "#..", "#.."], "*": [".#.", "###", ".#.", "#.#", "..."],
}


def back_print(layer, i, p, text, colour, top=1):
    """A 3×5 print centred on the back of the shirt — the whole text if it fits in this pose,
    else just its last character, else nothing (a pose where the ball hides the back)."""
    b = p.bbox(SHIRTL)
    if not b:
        return
    x0, y0, x1, y1 = b
    for t in (text, text[-1:]):
        wt = 4 * len(t) - 1
        sx = (x0 + x1 + 1) // 2 - wt // 2
        sy = y0 + top
        cells = [(sx + 4 * n + c, sy + r) for n, ch in enumerate(t) for r, line in enumerate(TINY[ch])
                 for c, v in enumerate(line) if v == "#"]
        if all(0 <= x < W and 0 <= y < H and p.label[y][x] == SHIRTL for (x, y) in cells):
            for (x, y) in cells:
                layer.put(i, x, y, colour)
            return


# --------------------------------------------------------------------------------------------
# Characters.

SKINS = {
    "kid": [0xFED5B3, 0xEAAB76, 0xCA8347],
    "tan": [0xF3C497, 0xD8A06A, 0xB07743],
    "brown": [0xCF9463, 0xAB7042, 0x80502C],
    "deep": [0x9A6440, 0x77492C, 0x55321C],
    "alien": [0xA9EC72, 0x6BC24F, 0x3F8E38],
    "metal": [0xE2E8EE, 0xAEB9C4, 0x77838F],
    "fur": [0xC0874E, 0x9A6634, 0x6E4520],
    "gold": [0xFFE784, 0xEBB838, 0xB9821B],
}


class Avatar:
    def __init__(self, ident, skin, wears=("hat", "shirt", "jacket", "pants", "shoes")):
        self.id = ident
        self.skin = SKINS[skin]
        self.wears = list(wears)
        self.body = Layer(base=True)
        self.over = None

    def each(self):
        return enumerate(POSES_DATA)


def paint_skin(av):
    for i, p in av.each():
        repaint(av.body, i, p, [HEADSKIN, ARM, HAND], av.skin)


def paint_clothes(av, shirt=None, pants=None, shoes_=None, shirt_pattern=None):
    for i, p in av.each():
        if shirt:
            repaint(av.body, i, p, [SHIRTL], shirt, shirt_pattern(i, p) if shirt_pattern else None)
        if pants:
            repaint(av.body, i, p, [PANTSL], pants)
        if shoes_:
            paint_shoes(av.body, i, p, *shoes_)


def paint_shoes(layer, i, p, main, sole, trim=None):
    m = ramp(main, 2, dark=0.78)
    for (x, y) in pixels(p, SHOES):
        c = orig(p, x, y)
        if c == 0xFFFFFF:
            layer.put(i, x, y, safe(sole))
        elif c == 0xBD2828:
            layer.put(i, x, y, safe(trim or m[1]))
        else:
            layer.put(i, x, y, safe(m[0]))


def hair_colour(av, light, dark=0.3):
    t = ramp(light, 6, dark=dark)
    for i, p in av.each():
        repaint(av.body, i, p, [HAIRL], t)
    return t


def fade(av, top_light, stubble):
    """Short on top; the sides and back faded down to skin with a little stubble."""
    t = hair_colour(av, top_light, dark=0.35)
    for i, p in av.each():
        hx0, hy0, hx1, hy1 = head(p)
        for (x, y) in pixels(p, HAIRL):
            if y >= hy1 - 3 or ((x <= hx0 + 1 or x >= hx1 - 1) and y >= hy1 - 6):
                low = y >= hy1 - 1
                dot = (x * 3 + y * 2) % (4 if y < hy1 - 2 else 5) == 0
                av.body.put(i, x, y, stubble if dot else (av.skin[2] if low else av.skin[1]))
    return t


def afro(av, light):
    t = ramp(light, 4, dark=0.45)
    for i, p in av.each():
        hx0, hy0, hx1, hy1 = head(p)
        cx, cy = (hx0 + hx1) / 2, (hy0 + hy1) / 2 - 1.0
        rx, ry = (hx1 - hx0) / 2 + 2.4, (hy1 - hy0) / 2 + 2.2
        for y in range(H):
            for x in range(W):
                lab = p.label[y][x]
                if lab not in (HAIRL, EMPTY, OUTLINE) or y > hy1 - 2:
                    continue
                if lab == OUTLINE and y > cy + 2:
                    continue
                d = ((x - cx) / rx) ** 2 + ((y - cy) / ry) ** 2
                if d <= 1:
                    k = 0 if y < cy - ry * 0.45 else (1 if y < cy + ry * 0.2 else 2)
                    if (x * 7 + y * 3) % 5 == 0:
                        k = min(3, k + 1)  # curls
                    av.body.put(i, x, y, t[k])
        outline(av.body, i, p)
        keep_ball(av.body, i, p, restore=True)
    return t


def ponytail(av, tones, tie):
    """A high ponytail hanging down the back, over whatever top is worn."""
    av.over = Layer()
    for i, p in av.each():
        hx0, hy0, hx1, hy1 = head(p)
        cx = centre_x(p)
        top, bot = hy1 - 2, hy1 + 7
        for y in range(top, bot + 1):
            half = 1 if y < bot - 1 else 0
            for x in range(cx - half, cx + half + 2):
                if p.label[y][x] in (BALL,):
                    continue
                k = 1 if x == cx - half else (2 if x == cx + half + 1 else 0)
                if y >= bot - 2:
                    k = min(3, k + 1)
                av.over.put(i, x, y, tones[k])
        for x in range(cx - 1, cx + 3):
            av.over.put(i, x, top, tie)
        # Outline the tail where it hangs over the back.
        cell = av.over.cells[i]
        adds = []
        for y in range(top, bot + 2):
            for x in range(cx - 3, cx + 5):
                if cell.getpixel((x, y))[3]:
                    continue
                if any(cell.getpixel((x + dx, y + dy))[3] for dx, dy in ((1, 0), (-1, 0), (0, -1))
                       if 0 <= x + dx < W and 0 <= y + dy < H) and p.label[y][x] != HAIRL:
                    adds.append((x, y))
        for (x, y) in adds:
            av.over.put(i, x, y, BLACK)
        keep_ball(av.over, i, p)


def antennae(av, colour, bulb):
    for i, p in av.each():
        hx0, hy0, hx1, hy1 = head(p)
        cx = centre_x(p)
        for side in (-1, 1):
            bx = cx + side * 3 + (1 if side > 0 else 0)
            for k in range(1, 5):
                x = bx + side * (k // 2)
                av.body.put(i, x, hy0 - k, colour)
            tip = (bx + side * 2, hy0 - 5)
            for dx in (0, 1):
                for dy in (0, -1):
                    av.body.put(i, tip[0] + dx - (1 if side < 0 else 0), tip[1] + dy, bulb)
        outline(av.body, i, p)
        keep_ball(av.body, i, p, restore=True)


def bear_ears(av, fur, inner):
    for i, p in av.each():
        hx0, hy0, hx1, hy1 = head(p)
        for ex in (hx0 + 1, hx1 - 2):
            for dy in range(-2, 1):
                for dx in range(0, 3):
                    if (dx, dy) in ((0, -2), (2, -2)):
                        continue
                    av.body.put(i, ex + dx, hy0 + dy, fur)
            av.body.put(i, ex + 1, hy0 - 1, inner)
        outline(av.body, i, p)
        keep_ball(av.body, i, p, restore=True)


def robot_head(av, metal):
    t = metal
    for i, p in av.each():
        hx0, hy0, hx1, hy1 = head(p)
        cx = centre_x(p)
        for (x, y) in pixels(p, HAIRL):
            k = 0 if y < hy0 + 3 else (1 if y < hy1 - 2 else 2)
            if x == cx or x == cx + 1:
                k = 2 if y > hy0 else k  # panel seam
            av.body.put(i, x, y, t[k])
        for (rx, ry) in ((hx0 + 2, hy0 + 3), (hx1 - 2, hy0 + 3), (hx0 + 2, hy1 - 3), (hx1 - 2, hy1 - 3)):
            if p.label[ry][rx] == HAIRL:
                av.body.put(i, rx, ry, 0x4D5661)
        for k in range(1, 4):
            av.body.put(i, cx, hy0 - k, 0x8792A0)
        for dx in (-1, 0, 1):
            av.body.put(i, cx + dx, hy0 - 4, 0xF03C3C)
        av.body.put(i, cx, hy0 - 5, 0xF03C3C)
        outline(av.body, i, p)
        keep_ball(av.body, i, p, restore=True)


def statue(av):
    """Gold all over (keeping the ball)."""
    gold = SKINS["gold"]
    t6 = ramp(gold[0], 6, dark=0.5)
    for i, p in av.each():
        repaint(av.body, i, p, [HAIRL], t6)
        repaint(av.body, i, p, [SHIRTL], ramp(0xFFE27A, 4, dark=0.62))
        repaint(av.body, i, p, [PANTSL], [0xE8B530, 0xA87318])
        paint_shoes(av.body, i, p, 0xF2C544, 0xFFF3C0, 0xA87318)
        # A gleam across the head.
        hx0, hy0, hx1, hy1 = head(p)
        for (x, y) in pixels(p, HAIRL):
            if x - hx0 == y - hy0 + 2 or x - hx0 == y - hy0 + 3:
                av.body.put(i, x, y, 0xFFF6C8)


def build_avatars():
    out = []
    kid = Avatar("kid", "kid")
    out.append(kid)

    dre = Avatar("dre", "deep")
    paint_skin(dre)
    fade(dre, 0x3B3B42, 0x2A2A30)
    paint_clothes(dre, shirt=ramp(0xF7C83A, 4, dark=0.66), pants=[0x3A3E4C, 0x1F222C], shoes_=(0xF4F4F8, 0xC9CDD8, 0x9AA0AE))
    out.append(dre)

    maya = Avatar("maya", "tan")  # shown in the game as Jenn
    paint_skin(maya)
    mt = hair_colour(maya, 0x4A2E1E, dark=0.35)
    ponytail(maya, [mt[0], mt[2], mt[4], mt[5]], 0xFF5FA8)
    paint_clothes(maya, shirt=ramp(0x3FD1C4, 4, dark=0.62), pants=[0x5A5F74, 0x33374A], shoes_=(0x9B6BFF, 0xF1ECFF))
    out.append(maya)

    rio = Avatar("rio", "brown")
    paint_skin(rio)
    afro(rio, 0x3E2C22)
    paint_clothes(rio, shirt=ramp(0xFF8A3D, 4, dark=0.64), pants=[0x3F6FB0, 0x1D3F72], shoes_=(0x2E2E38, 0xE9E9EF))
    out.append(rio)

    zorp = Avatar("zorp", "alien", wears=("shirt", "jacket", "pants", "shoes"))
    paint_skin(zorp)
    for i, p in zorp.each():  # bald, green, with freckle-spots
        repaint(zorp.body, i, p, [HAIRL], [0xA9EC72, 0xA9EC72, 0x8BD863, 0x6BC24F, 0x55AA45, 0x3F8E38])
        hx0, hy0, hx1, hy1 = head(p)
        for (sx, sy) in ((hx0 + 3, hy0 + 3), (hx1 - 4, hy0 + 5), (hx0 + 6, hy0 + 7)):
            if p.label[sy][sx] == HAIRL:
                zorp.body.put(i, sx, sy, 0x3F8E38)
    antennae(zorp, 0x3F8E38, 0xFF5FD2)
    paint_clothes(zorp, shirt=ramp(0x9D6BFF, 4, dark=0.6), pants=[0xB8C0CC, 0x7D8795], shoes_=(0x5AF0C8, 0xE8FFF8))
    out.append(zorp)

    robo = Avatar("robo", "metal", wears=())
    paint_skin(robo)
    robot_head(robo, [0xDDE4EB, 0xA9B4C0, 0x76838F])
    paint_clothes(robo, shirt=[0xC4CDD6, 0xA6B1BD, 0x8D99A6, 0x66727F], pants=[0x5E6875, 0x3C444F],
                  shoes_=(0x4A525D, 0x8C96A2, 0x2E343C),
                  shirt_pattern=lambda i, p: (lambda x, y, c: 0x4D5661 if x == centre_x(p) else None))
    for i, p in robo.each():  # a glowing core on the back
        b = p.bbox(SHIRTL)
        if b:
            cx, cy = (b[0] + b[2] + 1) // 2, b[1] + 2
            for dx, dy in ((0, 0), (1, 0), (0, 1), (1, 1)):
                if p.label[cy + dy][cx + dx - 1] == SHIRTL:
                    robo.body.put(i, cx + dx - 1, cy + dy, 0x5AF0FF)
    out.append(robo)

    bruno = Avatar("bruno", "fur", wears=())
    paint_skin(bruno)
    ft = ramp(0xC0874E, 6, dark=0.5)
    for i, p in bruno.each():
        repaint(bruno.body, i, p, [HAIRL], ft)
    bear_ears(bruno, ft[1], 0xF2A6A0)
    paint_clothes(bruno, shirt=ramp(0x2F7DE0, 4, dark=0.6), pants=[ft[2], ft[4]], shoes_=(ft[3], ft[1], ft[5]))
    for i, p in bruno.each():
        back_print(bruno.body, i, p, "1", 0xFFF1C2)
    out.append(bruno)

    legend = Avatar("legend", "gold", wears=())
    paint_skin(legend)
    statue(legend)
    out.append(legend)
    return out


# --------------------------------------------------------------------------------------------
# Accessories.

def cover_hair(layer, i, p, rows, colour_at):
    """Paint the top `rows` rows of the hair (a hat's crown); colour_at(x, y, row, col) → colour."""
    hx0, hy0, hx1, hy1 = head(p)
    for (x, y) in pixels(p, HAIRL):
        r = y - hy0
        if r < rows:
            layer.put(i, x, y, colour_at(x, y, r, x - hx0))


def hat_edge(layer, i, p, row, colour):
    hx0, hy0, hx1, hy1 = head(p)
    for (x, y) in pixels(p, HAIRL):
        if y - hy0 == row:
            layer.put(i, x, y, colour)


def sweatband(layer, i, p):
    hx0, hy0, hx1, hy1 = head(p)
    for (x, y) in pixels(p, HAIRL, HEADSKIN):
        r = y - hy0
        if r in (5, 6) and hx0 - 1 <= x <= hx1 + 1:
            layer.put(i, x, y, 0xF4F4F8 if r == 5 else 0xC9CFDC)
    for (x, y) in pixels(p, HAIRL):
        if y - hy0 == 5 and (x - hx0) % 4 == 1:
            layer.put(i, x, y, 0xE5383B)


def beanie(tones, band, pom):
    def f(layer, i, p):
        hx0, hy0, hx1, hy1 = head(p)
        cover_hair(layer, i, p, 7, lambda x, y, r, c: band[0 if c % 2 else 1] if r >= 5 else
                   tones[min(2, r // 2) + (1 if c % 2 else 0)])
        cx = centre_x(p)
        for (x, y) in ((cx, hy0 - 2), (cx + 1, hy0 - 2), (cx - 1, hy0 - 1), (cx, hy0 - 1), (cx + 1, hy0 - 1),
                       (cx + 2, hy0 - 1), (cx, hy0), (cx + 1, hy0)):
            if 0 <= y and p.label[y][x] in (EMPTY, OUTLINE, HAIRL):
                layer.put(i, x, y, pom[0] if y < hy0 - 1 else pom[1])
        outline(layer, i, p)
    return f


def bandana(main, dots, knot):
    def f(layer, i, p):
        hx0, hy0, hx1, hy1 = head(p)
        cx = centre_x(p)
        cover_hair(layer, i, p, 6, lambda x, y, r, c: dots if (x + 2 * y) % 5 == 0 and r < 5 else
                   (main[0] if r < 3 else main[1]))
        for x in range(cx - 1, cx + 3):
            layer.put(i, x, hy0 + 5, knot)
        for k in range(1, 4):  # two tails
            for tx in (cx - (k + 1) // 2, cx + 1 + (k + 1) // 2):
                if p.label[hy0 + 5 + k][tx] in (HAIRL, HEADSKIN):
                    layer.put(i, tx, hy0 + 5 + k, main[1] if k < 3 else knot)
    return f


def cap(crown, brim, button):
    """A cap seen from behind and above: the crown, and the peak sticking out ahead of the head."""
    def f(layer, i, p):
        hx0, hy0, hx1, hy1 = head(p)
        cx = centre_x(p)
        cover_hair(layer, i, p, 6, lambda x, y, r, c: crown[0] if r < 2 else (crown[1] if r < 5 else crown[2]))
        # Adjuster opening at the back, above the strap.
        for x in range(cx - 1, cx + 2):
            if p.label[hy0 + 4][x] == HAIRL:
                layer.clear(i, x, hy0 + 4)
            layer.put(i, x, hy0 + 5, crown[2])
        layer.put(i, cx, hy0, button)
        # The peak, ahead of the head (up the screen).
        w = (hx1 - hx0) // 2 - 1
        for dy, half in ((-1, w), (-2, w - 1), (-3, w - 3)):
            for x in range(cx - half, cx + half + 2):
                y = hy0 + dy
                if y >= 0 and p.label[y][x] in (EMPTY, OUTLINE):
                    layer.put(i, x, y, brim[0] if dy < -1 else brim[1])
        outline(layer, i, p)
    return f


def headphones(band, cup, pad):
    def f(layer, i, p):
        hx0, hy0, hx1, hy1 = head(p)
        cx = (hx0 + hx1) / 2
        rx = (hx1 - hx0) / 2
        ear = hy0 + 7
        for x in range(hx0, hx1 + 1):
            t = (x - cx) / rx
            y = int(round(hy0 + 1 + (ear - hy0 - 1) * (t * t) ** 1.3))
            for yy in (y, y + 1):
                if p.label[yy][x] in (HAIRL, HEADSKIN):
                    layer.put(i, x, yy, band)
        for side in (-1, 1):
            x0 = hx0 - 1 if side < 0 else hx1
            for dx in range(2):
                for dy in range(-1, 3):
                    x, y = x0 + dx, ear + dy
                    if p.label[y][x] in (EMPTY, OUTLINE, HAIRL, HEADSKIN, ARM):
                        layer.put(i, x, y, cup if dy in (-1, 2) or dx == (0 if side < 0 else 1) else pad)
        outline(layer, i, p)
    return f


def crown(gold, jewel_a, jewel_b):
    def f(layer, i, p):
        hx0, hy0, hx1, hy1 = head(p)
        cx = centre_x(p)
        for (x, y) in pixels(p, HAIRL):
            r = y - hy0
            if r in (3, 4) and hx0 + 1 <= x <= hx1 - 1:
                layer.put(i, x, y, gold[0] if r == 3 else gold[1])
        for sx in (hx0 + 2, cx, hx1 - 3):
            for y in range(hy0 - 2, hy0 + 3):
                for x in (sx, sx + 1):
                    if y >= 0 and (y >= hy0 or x == sx + (1 if sx < cx else 0) or sx == cx):
                        if p.label[y][x] in (EMPTY, OUTLINE, HAIRL):
                            layer.put(i, x, y, gold[0] if x == sx else gold[1])
        for (x, jc) in ((hx0 + 3, jewel_a), (cx, jewel_b), (hx1 - 3, jewel_a)):
            if p.label[hy0 + 3][x] == HAIRL:
                layer.put(i, x, hy0 + 3, jc)
        outline(layer, i, p)
    return f


def solid_top(tones, pattern=None, print_=None):
    def f(layer, i, p):
        repaint(layer, i, p, [SHIRTL], tones, pattern(p) if pattern else None)
        if print_:
            back_print(layer, i, p, *print_)
    return f


def stripes(a, b):
    ta, tb = ramp(a, 4, dark=0.7), ramp(b, 4, dark=0.7)
    return lambda p: (lambda x, y, c: None)


def striped_top(a, b):
    ta, tb = ramp(a, 4, dark=0.72), ramp(b, 4, dark=0.72)

    def f(layer, i, p):
        for (x, y) in pixels(p, SHIRTL):
            k = ORIG["shirt"].index(orig(p, x, y)) if orig(p, x, y) in ORIG["shirt"] else 1
            layer.put(i, x, y, (ta if y % 2 == 0 else tb)[k])
    return f


def tiedye():
    def f(layer, i, p):
        b = p.bbox(SHIRTL)
        cx, cy = (b[0] + b[2]) / 2, (b[1] + b[3]) / 2
        for (x, y) in pixels(p, SHIRTL):
            k = ORIG["shirt"].index(orig(p, x, y)) if orig(p, x, y) in ORIG["shirt"] else 1
            ang = math.atan2(y - cy, x - cx) + math.hypot(x - cx, y - cy) * 0.55
            hue = (ang / (2 * math.pi)) % 1
            r, g, bb = colorsys.hsv_to_rgb(hue, 0.55, 1.0 - 0.1 * k)
            layer.put(i, x, y, safe((int(r * 255) << 16) | (int(g * 255) << 8) | int(bb * 255)))
    return f


def jersey(body, trim, number, number_colour):
    tb = ramp(body, 4, dark=0.62)

    def f(layer, i, p):
        repaint(layer, i, p, [SHIRTL], tb)
        # Trim round the armholes and neck: shirt pixels touching skin.
        for (x, y) in pixels(p, SHIRTL):
            if any(p.label[y + dy][x + dx] in (ARM, HEADSKIN) for dx, dy in ((1, 0), (-1, 0), (0, -1))):
                layer.put(i, x, y, trim)
        back_print(layer, i, p, number, number_colour, top=1)
    return f


def sleeves(layer, i, p, tones, cuff=None, stripe=None):
    """Long sleeves: the arms down to the hands. `stripe` runs along the outer edge."""
    far = {}
    for (x, y), d in p.armdist.items():
        pass
    for (x, y) in pixels(p, ARM):
        c = tone(tones, ARM, orig(p, x, y))
        if stripe is not None:
            side = 1 if x > centre_x(p) else -1
            if p.label[y][x + side] in (OUTLINE, EMPTY):
                c = stripe
        if cuff is not None and any(p.label[y + dy][x + dx] == HAND for dx, dy in
                                    ((1, 0), (-1, 0), (0, 1), (0, -1)) if 0 <= x + dx < W and 0 <= y + dy < H):
            c = cuff
        layer.put(i, x, y, safe(c))


def jacket(body, sleeve=None, cuff=None, stripe=None, hood=None, quilt=None, collar=None, hem=None,
           emblem=None, emblem_colour=None, star=None):
    tb = ramp(body, 4, dark=0.62)
    ts = ramp(sleeve or body, 4, dark=0.62)

    def f(layer, i, p):
        b = p.bbox(SHIRTL)
        repaint(layer, i, p, [SHIRTL], tb)
        sleeves(layer, i, p, ts, cuff=cuff, stripe=stripe)
        if quilt is not None:
            for (x, y) in pixels(p, SHIRTL):
                if (y - b[1]) % 3 == 2:
                    layer.put(i, x, y, quilt)
            for (x, y) in pixels(p, ARM):
                if p.armdist.get((x, y), 0) % 3 == 2:
                    layer.put(i, x, y, quilt)
        if collar is not None:
            for (x, y) in pixels(p, SHIRTL):
                if y == b[1]:
                    layer.put(i, x, y, collar)
        if hem is not None:
            for (x, y) in pixels(p, SHIRTL):
                if y == b[3]:
                    layer.put(i, x, y, hem)
        if hood is not None:
            # The hood lies down on the upper back: a rounded flap, outlined, with its dark opening
            # tucked under the head.
            hx0, hy0, hx1, hy1 = head(p)
            cx = (hx0 + hx1 + 1) / 2
            cy = b[1] + 0.5
            inside = set()
            for y in range(hy1 - 1, b[1] + 5):
                for x in range(int(cx) - 7, int(cx) + 8):
                    if 0 <= x < W and p.label[y][x] in (HEADSKIN, SHIRTL, ARM, OUTLINE) and \
                            ((x + 0.5 - cx) / 5.2) ** 2 + ((y + 0.5 - cy) / 3.6) ** 2 <= 1 and y > hy1 - 1:
                        inside.add((x, y))
            for (x, y) in inside:
                edge = any((x + dx, y + dy) not in inside for dx, dy in ((1, 0), (-1, 0), (0, 1)))
                if edge:
                    layer.put(i, x, y, BLACK)
                elif (x, y - 1) not in inside or y <= hy1:
                    layer.put(i, x, y, hood[2])
                else:
                    layer.put(i, x, y, hood[0] if y < cy + 1 else hood[1])
        if emblem:
            back_print(layer, i, p, emblem, emblem_colour, top=1)
        if star:
            back_print(layer, i, p, "*", star, top=1)
        keep_ball(layer, i, p)
    return f


def pants(tones, pattern=None):
    def f(layer, i, p):
        repaint(layer, i, p, [PANTSL], tones, pattern(p) if pattern else None)
    return f


def track_pants(body, stripe):
    tb = [body, shade(body, 0.62)]

    def f(layer, i, p):
        repaint(layer, i, p, [PANTSL], tb)
        for (x, y) in pixels(p, PANTSL):
            side = 1 if x > centre_x(p) else -1
            if p.label[y][x + side] in (OUTLINE, EMPTY):
                layer.put(i, x, y, stripe)
    return f


def shorts(colour):
    t = [colour, shade(colour, 0.66)]

    def f(layer, i, p):
        b = p.bbox(PANTSL)
        for (x, y) in pixels(p, PANTSL):
            if y - b[1] < 2:
                layer.put(i, x, y, t[0] if orig(p, x, y) == 0x4F84A5 else t[1])
            else:
                layer.put(i, x, y, SKIN_KEYS[0] if orig(p, x, y) == 0x4F84A5 else SKIN_KEYS[2])
    return f


def camo():
    cols = [0x6E7A3C, 0x4A552A, 0x8C7A4A, 0x2F3620]

    def f(layer, i, p):
        for (x, y) in pixels(p, PANTSL):
            n = (x * 73 + y * 151 + (x // 2) * (y // 2) * 17) % 11
            layer.put(i, x, y, cols[0] if n < 4 else (cols[1] if n < 7 else (cols[2] if n < 9 else cols[3])))
    return f


def galaxy():
    def f(layer, i, p):
        for (x, y) in pixels(p, PANTSL):
            dark = orig(p, x, y) != 0x4F84A5
            c = 0x2A1850 if dark else 0x46288A
            if (x * 5 + y * 11) % 13 == 0:
                c = 0xF7E8FF
            elif (x * 7 + y * 3) % 17 == 0:
                c = 0xFF7AD9
            layer.put(i, x, y, c)
    return f


def kicks(main, sole, trim=None):
    def f(layer, i, p):
        paint_shoes(layer, i, p, main, sole, trim)
    return f


ACCESSORIES = {
    # Hats
    "sweatband": sweatband,
    "beanie": beanie([0xE85B5B, 0xD24545, 0xB73636, 0x9E2B2B], [0xF4EBDD, 0xD9CDB9], [0xF4EBDD, 0xD9CDB9]),
    "bandana": bandana([0x2F6FE0, 0x1F4FAE], 0xF1F4FF, 0x163A82),
    "cap": cap([0x3A3A46, 0x2C2C36, 0x1E1E26], [0xF2C33A, 0xC99A1E], 0xF2C33A),
    "headphones": headphones(0x2B2B33, 0xE5383B, 0x3A3A44),
    "crown": crown([0xFFD84A, 0xD9A21E], 0xE5383B, 0x3FA7FF),
    # Shirts
    "redtee": solid_top(ramp(0xEF4B4B, 4, dark=0.62)),
    "blacktee": solid_top([0x55555F, 0x44444D, 0x393941, 0x26262C]),
    "striped": striped_top(0xF2F2F6, 0x2E4E9E),
    "jersey": jersey(0x7A4BD6, 0xFFC83A, "23", 0xFFC83A),
    "tiedye": tiedye(),
    "goldjersey": jersey(0xF2C544, 0x1E1E26, "1", 0x1E1E26),
    # Jackets
    "hoodie": jacket(0x6F86A8, hood=(0x8EA4C6, 0x6F86A8, 0x33405A)),
    "track": jacket(0xE0383C, stripe=0xF2F2F6, cuff=0xF2F2F6, collar=0xF2F2F6),
    "bomber": jacket(0x6B7A3C, collar=0xF08A2E, hem=0x4A552A, cuff=0x4A552A),
    "puffer": jacket(0xFF8A2E, quilt=0xC75F16),
    "varsity": jacket(0x243B77, sleeve=0xEDE3C8, cuff=0xFFC83A, hem=0xFFC83A, emblem="P", emblem_colour=0xFFC83A),
    "mvp": jacket(0x24242C, sleeve=0x24242C, stripe=0xFFC83A, collar=0xFFC83A, hem=0xFFC83A, star=0xFFC83A),
    # Pants
    "blackjeans": pants([0x4B4F5E, 0x282A33]),
    "shorts": shorts(0xE5383B),
    "trackpants": track_pants(0x243B77, 0xF2F2F6),
    "camo": camo(),
    "galaxy": galaxy(),
    # Shoes
    "whites": kicks(0xF2F3F7, 0xC9CDD8, 0xAAB0BE),
    "blackkicks": kicks(0x2E2E38, 0xEDEDF2, 0x1E1E26),
    "retros": kicks(0x2F74D8, 0xF2F3F7, 0x1F4FAE),
    "neon": kicks(0x7CFF4F, 0xFF6FD8, 0x3FC43A),
    "lava": kicks(0x2A2A30, 0xFF7A1E, 0xE5383B),
    "goldkicks": kicks(0xF2C544, 0xFFF3C0, 0xA87318),
}


def build_accessories():
    out = {}
    for ident, draw in ACCESSORIES.items():
        layer = Layer()
        for i, p in enumerate(POSES_DATA):
            draw(layer, i, p)
            keep_ball(layer, i, p)
        out[ident] = layer
    return out


# --------------------------------------------------------------------------------------------
# Preview (what the game composes): character body, then pants, shoes, shirt, jacket, the
# character's over-clothes hair, hat.

ORDER = ["pants", "shoes", "shirt", "jacket", "hairover", "hat"]
CATEGORY = {}
for _k in ("sweatband", "beanie", "bandana", "cap", "headphones", "crown"):
    CATEGORY[_k] = "hat"
for _k in ("redtee", "blacktee", "striped", "jersey", "tiedye", "goldjersey"):
    CATEGORY[_k] = "shirt"
for _k in ("hoodie", "track", "bomber", "puffer", "varsity", "mvp"):
    CATEGORY[_k] = "jacket"
for _k in ("blackjeans", "shorts", "trackpants", "camo", "galaxy"):
    CATEGORY[_k] = "pants"
for _k in ("whites", "blackkicks", "retros", "neon", "lava", "goldkicks"):
    CATEGORY[_k] = "shoes"


def compose(av, acc, items, i):
    img = av.body.cells[i].copy()
    by = {CATEGORY[k]: k for k in items if CATEGORY[k] in av.wears}
    for cat in ORDER:
        if cat == "hairover":
            if av.over:
                img.alpha_composite(av.over.cells[i])
            continue
        if cat in by:
            layer = acc[by[cat]].cells[i].copy()
            px = layer.load()
            for y in range(H):
                for x in range(W):
                    if px[x, y][3] and hexof(px[x, y]) in SKIN_KEYS:
                        px[x, y] = rgba(av.skin[SKIN_KEYS.index(hexof(px[x, y]))])
            img.alpha_composite(layer)
    return img


def make_preview(avatars, acc, out, poses=(8, 2, 4, 5)):
    k = 4
    looks = [("kid", []), ("kid", ["beanie", "redtee", "blackjeans", "whites"]),
             ("kid", ["cap", "jersey", "shorts", "retros"]), ("kid", ["headphones", "hoodie", "trackpants", "neon"]),
             ("kid", ["bandana", "striped", "camo", "blackkicks"]), ("kid", ["sweatband", "track", "galaxy", "lava"]),
             ("kid", ["crown", "mvp", "goldkicks", "galaxy"]), ("kid", ["tiedye", "bomber"]), ("kid", ["puffer", "goldjersey"]),
             ("kid", ["varsity", "blacktee"]), ("dre", []), ("dre", ["cap", "varsity"]), ("maya", []),
             ("maya", ["beanie", "hoodie", "shorts"]), ("rio", []), ("rio", ["headphones", "jersey"]), ("zorp", []),
             ("zorp", ["track", "camo"]), ("robo", []), ("bruno", []), ("legend", [])]
    byid = {a.id: a for a in avatars}
    cw, ch = W * k, H * k
    sheet = Image.new("RGBA", (len(poses) * cw, len(looks) * ch), (41, 168, 224, 255))
    d = ImageDraw.Draw(sheet)
    for r, (aid, items) in enumerate(looks):
        for c, pi in enumerate(poses):
            img = compose(byid[aid], acc, items, pi).resize((cw, ch), Image.NEAREST)
            sheet.alpha_composite(img, (c * cw, r * ch))
        d.text((2, r * ch + 2), aid + " " + " ".join(items), fill=(0, 0, 0))
    sheet.save(out)
    print("preview", out, sheet.size)


def run(preview=None):
    avatars = build_avatars()
    accessories = build_accessories()
    manifest = {"poses": POSES, "cell": [W, H], "skinKeys": ["#%06X" % k for k in SKIN_KEYS], "avatars": {}}
    for av in avatars:
        if av.id != "kid":
            av.body.sheet().save(ART / f"outfit_avatar_{av.id}.png")
        if av.over:
            av.over.sheet().save(ART / f"outfit_hair_{av.id}.png")
        manifest["avatars"][av.id] = {"skin": ["#%06X" % s for s in av.skin], "hairOver": av.over is not None,
                                      "wears": av.wears}
    for ident, layer in accessories.items():
        layer.sheet().save(ART / f"outfit_acc_{ident}.png")
    manifest["accessories"] = {k: CATEGORY[k] for k in accessories}
    (ART / "outfits.json").write_text(json.dumps(manifest, indent=1))
    print(f"wrote {len(avatars) - 1} characters and {len(accessories)} accessories")
    if preview:
        make_preview(avatars, accessories, preview)


if __name__ == "__main__":
    run(Path(sys.argv[sys.argv.index("--preview") + 1]) if "--preview" in sys.argv else None)
