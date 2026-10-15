"""Original redraw mock-up for Pocket Hoops: a new cabinet, player and ball drawn from scratch.

Nothing here is traced or sampled from the reference GIF; every shape is placed by the numbers
below. This is a preview only; the app and its art pipeline are untouched.

    python3 redraw/draw_mockup.py      → redraw/mockup.png
"""
import math
from pathlib import Path

from PIL import Image, ImageDraw, ImageFont

OUT = Path(__file__).resolve().parent
T = (0, 0, 0, 0)
INK = (24, 16, 34, 255)          # outline: a deep plum, not pure black


def hexc(h, a=255):
    h = h.lstrip('#')
    return (int(h[0:2], 16), int(h[2:4], 16), int(h[4:6], 16), a)


# ---- palette ------------------------------------------------------------------------------
BG = hexc('2B1E4A')
BG_DOT = hexc('362659')
FLOOR = hexc('3B2A5E')
FLOOR_LINE = hexc('46336D')
METAL = [hexc('8C93B8'), hexc('646B95'), hexc('454B72')]          # light, mid, dark
WOOD = [hexc('E6A15C'), hexc('C9803F'), hexc('A3612B')]
MAGENTA = [hexc('FF5FA2'), hexc('E0377F'), hexc('A81E5C')]
BOARD = [hexc('F4F1E8'), hexc('D8D2C4')]
TEAL = [hexc('5EF2DE'), hexc('22C7B4'), hexc('138577')]
NET = hexc('F4F1E8')
BULB_ON = hexc('FFE45C')
BULB_OFF = hexc('8A6A2A')
SCREEN = hexc('16232E')
LED = hexc('5EF2DE')
BALL = [hexc('FFB25C'), hexc('F28C28'), hexc('C4621A')]
SEAM = hexc('5A2A10')
SKIN = [hexc('E2A47A'), hexc('C4825A'), hexc('9C6040')]
HAIR = hexc('2A1A14')
CAP = [hexc('3FA7FF'), hexc('2276D6'), hexc('16509A')]
JERSEY = [hexc('FFD84A'), hexc('F2B21E'), hexc('C98A10')]
SHORTS = [hexc('2C3E8F'), hexc('1F2C68')]
SOCK = hexc('F4F1E8')
SHOE = [hexc('FF5F5F'), hexc('C93A3A')]


class Layer:
    """A transparent pixel layer that gets its own outline before compositing."""

    def __init__(self, w, h):
        self.w, self.h = w, h
        self.px = {}

    def set(self, x, y, c):
        if 0 <= x < self.w and 0 <= y < self.h:
            self.px[(x, y)] = c

    def rect(self, x0, y0, x1, y1, c):
        for y in range(y0, y1):
            for x in range(x0, x1):
                self.set(x, y, c)

    def ellipse(self, cx, cy, rx, ry, c, ring=None):
        """Filled ellipse (centre on a pixel corner when cx/cy end in .5). `ring` = (inner rx, ry) keeps only a band."""
        for y in range(int(cy - ry) - 1, int(cy + ry) + 2):
            for x in range(int(cx - rx) - 1, int(cx + rx) + 2):
                d = ((x + .5 - cx) / rx) ** 2 + ((y + .5 - cy) / ry) ** 2
                if d <= 1:
                    if ring and ((x + .5 - cx) / ring[0]) ** 2 + ((y + .5 - cy) / ring[1]) ** 2 <= 1:
                        continue
                    self.set(x, y, c)

    def line(self, x0, y0, x1, y1, c):
        dx, dy = abs(x1 - x0), -abs(y1 - y0)
        sx, sy = (1 if x0 < x1 else -1), (1 if y0 < y1 else -1)
        err = dx + dy
        while True:
            self.set(x0, y0, c)
            if (x0, y0) == (x1, y1):
                break
            e2 = 2 * err
            if e2 >= dy:
                err += dy
                x0 += sx
            if e2 <= dx:
                err += dx
                y0 += sy

    def outline(self, c=INK):
        ring = set()
        for (x, y) in self.px:
            for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1)):
                q = (x + dx, y + dy)
                if q not in self.px and 0 <= q[0] < self.w and 0 <= q[1] < self.h:
                    ring.add(q)
        for q in ring:
            self.px[q] = c
        return self

    def onto(self, img, ox=0, oy=0):
        p = img.load()
        for (x, y), c in self.px.items():
            X, Y = x + ox, y + oy
            if 0 <= X < img.width and 0 <= Y < img.height and c[3]:
                p[X, Y] = c
        return img


# ---- the cabinet --------------------------------------------------------------------------
W, H = 96, 150


def background():
    img = Image.new('RGBA', (W, H), BG)
    p = img.load()
    for y in range(H):
        for x in range(W):
            if (x * 7 + y * 3) % 23 == 0 and y < 118:
                p[x, y] = BG_DOT
            if y >= 118:
                p[x, y] = FLOOR if (y - 118) % 6 else FLOOR_LINE
    return img


def cabinet():
    L = Layer(W, H)
    cx = 48
    # Side cages: straight metal rails that splay out toward the player (no glass bubbles).
    for y in range(22, 106):
        t = (y - 22) / 84
        half = int(26 + 12 * t)
        for side in (-1, 1):
            x_outer = cx + side * half
            for k in range(4):
                x = x_outer - side * k
                L.set(x, y, METAL[0] if k == 1 else METAL[1] if k < 3 else METAL[2])
            # cage bars every 6 rows
            if (y - 22) % 6 == 0:
                for k in range(4, 9):
                    L.set(x_outer - side * k, y, METAL[2])
    # Lane: wooden planks, widening toward the front.
    for y in range(50, 100):
        t = (y - 22) / 84
        half = int(26 + 12 * t) - 4
        for x in range(cx - half, cx + half):
            plank = (x - (cx - half)) * 5 // max(1, 2 * half)
            shade = WOOD[1] if plank % 2 else WOOD[0]
            if (y + plank * 3) % 11 == 0:
                shade = WOOD[2]
            L.set(x, y, shade)
    # Backboard wall (behind the hoop).
    L.rect(cx - 22, 22, cx + 22, 50, METAL[2])
    # Front panel with player lamps.
    L.rect(cx - 39, 100, cx + 39, 111, MAGENTA[1])
    L.rect(cx - 39, 100, cx + 39, 101, MAGENTA[0])
    L.rect(cx - 39, 110, cx + 39, 111, MAGENTA[2])
    for i, lx in enumerate((cx + 14, cx + 24)):
        L.ellipse(lx + .5, 105.5, 2.6, 2.6, BULB_ON if i == 0 else BULB_OFF)
    # P1 / P2 marks as little dots-and-bars (no lettering copied from anywhere).
    for i, lx in enumerate((cx + 10, cx + 20)):
        for k in range(i + 1):
            L.rect(lx + k * 2, 103, lx + k * 2 + 1, 108, MAGENTA[2])
    # Ball tray and base.
    L.rect(cx - 37, 111, cx + 37, 120, METAL[2])
    L.rect(cx - 37, 111, cx + 37, 112, INK)
    L.rect(cx - 39, 120, cx + 39, 127, MAGENTA[2])
    L.rect(cx - 39, 120, cx + 39, 121, MAGENTA[1])
    return L.outline()


def marquee():
    L = Layer(W, H)
    cx = 48
    # An arched marquee with a bulb border (instead of a flat glass sign).
    for y in range(3, 22):
        for x in range(cx - 30, cx + 30):
            dx = (x + .5 - cx) / 30
            top = 3 + int(7 * dx * dx)
            if y >= top:
                L.set(x, y, MAGENTA[1] if y > top + 1 else MAGENTA[0])
    L.rect(cx - 18, 10, cx + 18, 19, SCREEN)
    # bulbs along the arch
    for i in range(-6, 7):
        x = cx + i * 4
        dx = (x + .5 - cx) / 30
        y = 3 + int(7 * dx * dx) + 1
        L.set(x, y, BULB_ON if i % 2 == 0 else BULB_OFF)
    # LED digits "0042" in a home-made 3x5 font
    digits = {'0': ['###', '#.#', '#.#', '#.#', '###'], '4': ['#.#', '#.#', '###', '..#', '..#'],
              '2': ['###', '..#', '###', '#..', '###']}
    for i, ch in enumerate('0042'):
        for r, row in enumerate(digits[ch]):
            for c, v in enumerate(row):
                if v == '#':
                    L.set(cx - 9 + i * 5 + c, 12 + r, LED)
    return L.outline()


def backboard():
    L = Layer(W, H)
    cx = 48
    L.rect(cx - 17, 24, cx + 17, 46, BOARD[0])
    L.rect(cx - 17, 44, cx + 17, 46, BOARD[1])
    # A teal target square and a little star stamp (our own logo).
    for x in range(cx - 7, cx + 7):
        L.set(x, 33, TEAL[2])
        L.set(x, 42, TEAL[2])
    for y in range(33, 43):
        L.set(cx - 7, y, TEAL[2])
        L.set(cx + 6, y, TEAL[2])
    star = ['..#..', '.###.', '#####', '.#.#.']
    for r, row in enumerate(star):
        for c, v in enumerate(row):
            if v == '#':
                L.set(cx - 3 + c, 27 + r, MAGENTA[1])
    return L.outline()


def rim_back():
    L = Layer(W, H)
    L.ellipse(48, 50.5, 10, 5, TEAL[1], ring=(7.4, 3.2))
    L.ellipse(48, 50.5, 10, 5, TEAL[0], ring=(9, 4.2))
    # keep only the far half for the back layer
    L.px = {k: v for k, v in L.px.items() if k[1] <= 50}
    return L


def rim_front():
    L = Layer(W, H)
    L.ellipse(48, 50.5, 10, 5, TEAL[1], ring=(7.4, 3.2))
    for (x, y) in list(L.px):
        if y >= 53:
            L.px[(x, y)] = TEAL[2]
    L.px = {k: v for k, v in L.px.items() if k[1] > 50}
    # Net: diamond mesh hanging under the ring.
    for y in range(53, 61):
        half = 7 - (y - 53) // 2
        for x in range(48 - half, 48 + half):
            if (x + y) % 3 == 0 or (x - y) % 3 == 0:
                L.set(x, y, NET)
    return L


def ball_sprite(r=4.5, spin=0.0):
    L = Layer(12, 12)
    c = 6
    ca, sa = math.cos(spin), math.sin(spin)
    for y in range(12):
        for x in range(12):
            dx, dy = x + .5 - c, y + .5 - c
            d = (dx * dx + dy * dy) ** .5
            if d > r:
                continue
            u, v = dx * ca + dy * sa, -dx * sa + dy * ca      # ball-space coordinates
            col = BALL[0] if (dx + dy) < -2.5 else BALL[2] if d > r - 1.2 and dx + dy > 1 else BALL[1]
            if abs(u) < .5 or abs(v + .08 * u * u) < .5:      # a cross of seams, one gently curved
                col = SEAM
            L.set(x, y, col)
    return L.outline()


# ---- the player, seen from behind --------------------------------------------------------
PW, PH = 30, 44


def player(pose):
    """pose: idle | crouch | shoot | follow."""
    L = Layer(PW, PH)
    cx = 15
    lift = {'idle': 0, 'crouch': 2, 'shoot': -3, 'follow': -2}[pose]
    y0 = 6 + lift
    # legs + shorts + socks + shoes
    knee = 1 if pose == 'crouch' else 0
    for side in (-1, 1):
        lx = cx + side * 3 - (1 if side < 0 else 0)
        L.rect(lx - 1, y0 + 26, lx + 2, y0 + 33 - knee, SKIN[1])
        L.rect(lx - 1, y0 + 31 - knee, lx + 2, y0 + 34 - knee, SOCK)
        L.rect(lx - 2, y0 + 34 - knee, lx + 3, y0 + 36 - knee, SHOE[0])
        L.rect(lx - 2, y0 + 35 - knee, lx + 3, y0 + 36 - knee, SHOE[1])
    L.rect(cx - 6, y0 + 21, cx + 6, y0 + 28, SHORTS[0])
    L.rect(cx - 6, y0 + 26, cx + 6, y0 + 28, SHORTS[1])
    L.rect(cx - 1, y0 + 23, cx + 1, y0 + 28, SHORTS[1])
    # torso: yellow jersey with a big "7" on the back
    L.rect(cx - 6, y0 + 10, cx + 6, y0 + 22, JERSEY[1])
    L.rect(cx - 6, y0 + 10, cx - 4, y0 + 22, JERSEY[2])
    L.rect(cx + 4, y0 + 10, cx + 6, y0 + 22, JERSEY[0])
    seven = ['####', '...#', '..#.', '.#..', '.#..']
    for r, row in enumerate(seven):
        for c, v in enumerate(row):
            if v == '#':
                L.set(cx - 2 + c, y0 + 13 + r, SHORTS[0])
    # arms
    if pose in ('idle', 'crouch'):
        for side in (-1, 1):
            ax = cx + side * 7 - (1 if side < 0 else 0)
            L.rect(ax - 1, y0 + 11, ax + 2, y0 + 20, SKIN[1])
            L.rect(ax - 1, y0 + 11, ax + 2, y0 + 13, JERSEY[1])
    else:
        # elbows out, hands up under the ball
        top = y0 - 3 if pose == 'follow' else y0 - 1
        for side in (-1, 1):
            sh, el, ha = (cx + side * 6, y0 + 12), (cx + side * 9, y0 + 5), (cx + side * 4, top)
            for w in (0, 1):
                L.line(sh[0] - side * w, sh[1], el[0] - side * w, el[1], SKIN[1])
                L.line(el[0] - side * w, el[1], ha[0] - side * w, ha[1], SKIN[1] if w else SKIN[0])
            L.rect(sh[0] - 1, y0 + 10, sh[0] + 1, y0 + 13, JERSEY[1])
    # head from behind: dark hair, ears, and a small backwards cap on top
    L.ellipse(cx, y0 + 5.5, 4.6, 5, HAIR)
    L.set(cx - 5, y0 + 6, SKIN[1]); L.set(cx + 4, y0 + 6, SKIN[1])        # ears
    L.rect(cx - 2, y0 + 9, cx + 2, y0 + 11, SKIN[2])                       # neck
    L.ellipse(cx, y0 + 2.6, 4.4, 2.6, CAP[1])
    L.rect(cx - 3, y0 + 1, cx + 2, y0 + 2, CAP[0])
    L.rect(cx - 2, y0 + 4, cx + 2, y0 + 6, CAP[2])                         # brim, pointing back at us
    return L.outline()


# ---- presentation ------------------------------------------------------------------------
def scene(theme_shift=None):
    img = background()
    cabinet().onto(img)
    marquee().onto(img)
    backboard().onto(img)
    rb = rim_back()
    rf = rim_front()
    rb_outlined = Layer(W, H)
    rb_outlined.px = dict(rb.px)
    rb_outlined.outline().onto(img)
    # a ball dropping through the hoop, between the rim layers
    ball_sprite(spin=0.6).onto(img, 42, 47)
    rfo = Layer(W, H)
    rfo.px = dict(rf.px)
    rfo.outline().onto(img)
    # rack balls
    for i, x in enumerate(range(18, 80, 10)):
        ball_sprite(spin=i * .7).onto(img, x - 6, 108)
    # the player, shooting
    player('shoot').onto(img, 33, 104)
    ball_sprite(spin=1.4).onto(img, 42, 102)
    return img


def scale(img, k):
    return img.resize((img.width * k, img.height * k), Image.NEAREST)


def main():
    font = ImageFont.truetype('/System/Library/Fonts/Supplemental/Arial Bold.ttf', 22)
    small = ImageFont.truetype('/System/Library/Fonts/Supplemental/Arial.ttf', 16)
    main_scene = scale(scene(), 5)

    poses = [player(p) for p in ('idle', 'crouch', 'shoot', 'follow')]
    strip = Image.new('RGBA', (PW * 4 + 18, PH + 8), BG)
    for i, L in enumerate(poses):
        L.onto(strip, 4 + i * (PW + 4), 4)
        if i >= 2:
            ball_sprite(spin=i).onto(strip, 4 + i * (PW + 4) + 9, (-1 if i == 2 else -3))
    strip = scale(strip, 5)

    balls = Image.new('RGBA', (12 * 5 + 12, 16), BG)
    for i in range(5):
        ball_sprite(spin=i * math.pi / 5).onto(balls, 2 + i * 14, 2)
    balls = scale(balls, 6)

    pad = 30
    Wd = main_scene.width + pad * 3 + max(strip.width, balls.width)
    Hd = main_scene.height + pad * 2 + 40
    sheet = Image.new('RGBA', (Wd, Hd), hexc('120C20'))
    d = ImageDraw.Draw(sheet)
    d.text((pad, 10), 'NEW CABINET (drawn from scratch)', font=font, fill=(255, 228, 92))
    sheet.paste(main_scene, (pad, 44))
    rx = main_scene.width + pad * 2
    d.text((rx, 10), 'PLAYER: idle, crouch, shoot, follow-through', font=font, fill=(255, 228, 92))
    sheet.paste(strip, (rx, 44))
    d.text((rx, 44 + strip.height + 24), 'BALL (spins through 5 frames)', font=font, fill=(255, 228, 92))
    sheet.paste(balls, (rx, 44 + strip.height + 58))
    notes = ['Preview only: nothing in the app has changed.',
             'Different from the GIF on purpose: arched bulb marquee instead of a glass sign,',
             'straight metal cage sides instead of glass bubbles, wooden lane, teal rim,',
             'orange basketball, and a new player (backwards cap, yellow #7 jersey, shorts).']
    for i, n in enumerate(notes):
        d.text((rx, 44 + strip.height + 58 + balls.height + 30 + i * 24), n, font=small, fill=(220, 214, 240))
    sheet.save(OUT / 'mockup.png')
    scale(scene(), 1).save(OUT / 'mockup_native.png')
    print('wrote', OUT / 'mockup.png', sheet.size)


if __name__ == '__main__':
    main()
