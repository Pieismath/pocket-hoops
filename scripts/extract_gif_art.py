#!/usr/bin/env python3
"""Cut the game's sprites out of the reference GIF.

    python3 scripts/extract_gif_art.py [art/reference.gif]

The GIF is 800x600 but drawn in 4x4-pixel art pixels, so each frame is reduced to its native
200x150 art first (majority colour per block; the blocks are uniform). Everything is then cropped
from those native frames and written 1 PNG pixel = 1 art pixel into PocketHoops/GIFArt/; the game
scales them with nearest-neighbour filtering.

Coordinates below are native GIF art pixels, y down. The machine canvas (MX0, MY0, MW x MH) is the
frame the game positions everything in; `GIFLayout.swift` mirrors these numbers.
"""
import json
import os
import sys
from collections import Counter

from PIL import Image, ImageDraw, ImageSequence

SRC = sys.argv[1] if len(sys.argv) > 1 else 'art/reference.gif'
OUT = 'PocketHoops/GIFArt'
SCALE = 4

# Machine canvas inside the 200x150 art (covers the cabinet, the kid and the coin box).
MX0, MY0, MW, MH = 60, 0, 80, 142
# Sparkles live on both sides of the machine.
SX0, SW = 36, 128

HEX = lambda c: '%02X%02X%02X' % c
RGB = lambda h: (int(h[0:2], 16), int(h[2:4], 16), int(h[4:6], 16))

BG = RGB('24ACE5')
LANE = RGB('1463AD')        # lane, board, panel blue
LIGHT = RGB('227BCF')
DARK = RGB('0C4E8C')
DARKER = RGB('083662')
BLACK = RGB('000000')
WHITE = RGB('FFFFFF')
RED = RGB('D42C2C')         # ball red, strip red, sneaker red
BRIGHT_RED = RGB('FF1414')  # rim / side rails
PINK = RGB('FF7373')        # rim highlight / frame
ORANGE = RGB('FF7D14')      # lit player lamp
SCREEN = RGB('5C949F')      # sign LCD
TEXT = RGB('BBB38A')        # sign text
TEXT_ON_GLARE = RGB('DDD9C5')
GLARE = RGB('AECACF')
SPARKLE = {RGB('B79200'), RGB('F1C103')}

KID = {RGB(h) for h in ('3C220D', '5B3516', '533114', '6C4A2E', '64452C', '211205',   # hair
                        'FED5B3', 'EAAB76', 'CA8347',                                 # skin
                        'C9C9C9', 'B5B5B5', 'E5E5E5', '8D8D8D',                       # tee
                        '4F84A5', '1C5375')}                                          # jeans
HAIR = {RGB(h) for h in ('3C220D', '5B3516', '533114', '6C4A2E', '64452C', '211205')}
BALL = {RED, WHITE, BLACK, PINK, BRIGHT_RED, RGB('BD2828')}

# Rim geometry (continuous coordinates): centre and outer radii of the red ring.
RIM_C = (100.0, 49.0)
RIM_OUTER = (10.5, 8.0)
RIM_BOX = (86, 37, 114, 64)          # x0, y0, x1, y1 (exclusive) of the rim + net region
TROUGH = (76, 109, 123, 118)         # interior of the ball rack
PANEL_ROWS = (96, 109)               # front panel above the rack (occludes rack balls' tops)
LIP_ROWS = (118, 142)                # lip, base and coin box (occludes rack balls' bottoms)
LAMPS = [(107, 102), (116, 102)]     # top-left of the two 3x3 player lamps on the strip
PLAYER_TEXT = (80, 101, 104, 106)    # x0, y0, x1, y1 (exclusive): the strip's 3-px "PLAYER:" lettering


def native_frames(path):
    im = Image.open(path)
    frames = []
    for fr in ImageSequence.Iterator(im):
        rgb = fr.convert('RGB')
        px = rgb.load()
        w, h = rgb.size[0] // SCALE, rgb.size[1] // SCALE
        n = Image.new('RGB', (w, h))
        npx = n.load()
        for y in range(h):
            for x in range(w):
                block = Counter(px[x * SCALE + i, y * SCALE + j] for i in range(SCALE) for j in range(SCALE))
                npx[x, y] = block.most_common(1)[0][0]
        frames.append(n)
    # GIF quantisation leaves near-duplicate colours; fold each into the most common close colour.
    counts = Counter()
    for f in frames:
        counts.update(f.getdata() if not hasattr(f, 'get_flattened_data') else f.get_flattened_data())
    reps, canon = [], {}
    for c, _ in counts.most_common():
        best = next((r for r in reps if sum((a - b) ** 2 for a, b in zip(c, r)) <= 12), None)
        if best is None:
            reps.append(c)
            best = c
        canon[c] = best
    for f in frames:
        p = f.load()
        for y in range(f.size[1]):
            for x in range(f.size[0]):
                p[x, y] = canon[p[x, y]]
    return frames


def mode_plate(frames):
    w, h = frames[0].size
    plate = Image.new('RGB', (w, h))
    pp = plate.load()
    pxs = [f.load() for f in frames]
    for y in range(h):
        for x in range(w):
            pp[x, y] = Counter(p[x, y] for p in pxs).most_common(1)[0][0]
    return plate


def neighbours8(x, y):
    return [(x + dx, y + dy) for dx in (-1, 0, 1) for dy in (-1, 0, 1) if dx or dy]


def kid_mask(img, with_ball, ball_ellipse=None):
    """Pixels of the shooter (and the ball in their hands) in one frame.

    `ball_ellipse` (cx, cy, rx, ry) overrides ball detection for a pose where the ball's colours
    coincide with the strip and rack behind it too much to separate automatically."""
    p = img.load()
    core = set()
    for y in range(76, 142):
        for x in range(78, 122):
            c = p[x, y]
            if c in KID:
                core.add((x, y))
            elif y >= 131 and 84 <= x <= 106 and c != BG:
                core.add((x, y))  # legs and sneakers below the cabinet
    ball = set()
    if with_ball and ball_ellipse:
        cx, cy, rx, ry = ball_ellipse
        ball = {(x, y) for y in range(int(cy - ry) - 1, int(cy + ry) + 2)
                for x in range(int(cx - rx) - 1, int(cx + rx) + 2)
                if ((x + 0.5 - cx) / rx) ** 2 + ((y + 0.5 - cy) / ry) ** 2 <= 1 and p[x, y] in BALL}
    elif with_ball:
        # The ball in the kid's hands: ball colours that differ from the empty machine, above the tee,
        # grouped into connected blobs; only blobs touching the kid count (not a ball on the lane).
        # Seed from the ball's red/white only: black outlines would glue the ball to the arms.
        cand = {(x, y) for y in range(76, 129) for x in range(78, 122)
                if p[x, y] in BALL and p[x, y] != BLACK and p[x, y] != PLATE_PX[x, y]}
        hair_x = [x for (x, y) in core if p[x, y] in HAIR]
        head_lo, head_hi = (min(hair_x) - 4, max(hair_x) + 4) if hair_x else (0, 999)
        seen = set()
        for start in sorted(cand):
            if start in seen:
                continue
            blob, stack = set(), [start]
            while stack:
                q = stack.pop()
                if q in seen or q not in cand:
                    continue
                seen.add(q)
                blob.add(q)
                stack.extend(neighbours8(*q))
            touches = any(abs(x - kx) <= 2 and abs(y - ky) <= 2 for (x, y) in blob for (kx, ky) in core
                          if p[kx, ky] in KID)
            # Mid-jump the arms are spread and the ball floats above the head without touching.
            cx = sum(x for x, _ in blob) / len(blob)
            above_head = len(blob) >= 15 and head_lo <= cx <= head_hi
            if (touches and len(blob) >= 6) or above_head:
                ball |= blob
        # Its black outline (where it differs from the machine) marks the ball's true edge.
        edge = {q for (x, y) in ball for q in neighbours8(x, y)
                if q not in ball and 0 <= q[0] < 200 and 0 <= q[1] < 150
                and p[q] == BLACK and PLATE_PX[q] != BLACK}
        # The ball is convex: fill each row between its leftmost and rightmost pixel, so parts that
        # happen to match the machine behind it (red over the red strip) stay part of the ball.
        rows = {}
        for (x, y) in ball | edge:
            lo, hi = rows.get(y, (x, x))
            rows[y] = (min(lo, x), max(hi, x))
        for y, (lo, hi) in rows.items():
            for x in range(lo, hi + 1):
                if p[x, y] in BALL and (x, y) not in core:
                    ball.add((x, y))
    solid = core | ball
    outline = set()
    for (x, y) in solid:
        for q in neighbours8(x, y):
            if q not in solid and 0 <= q[0] < 200 and 0 <= q[1] < 150 and p[q] == BLACK:
                outline.add(q)
    return solid | outline, ball


def to_rgba(img, box, keep):
    """Crop `box` of `img`, keeping only pixels in `keep` (None = everything not background)."""
    x0, y0, x1, y1 = box
    out = Image.new('RGBA', (x1 - x0, y1 - y0), (0, 0, 0, 0))
    p = img.load()
    o = out.load()
    for y in range(y0, y1):
        for x in range(x0, x1):
            c = p[x, y]
            if (keep is None and c != BG) or (keep is not None and (x, y) in keep):
                o[x - x0, y - y0] = c + (255,)
    return out


def machine_layer(img, rows=None, cols=None, only=None):
    """A machine-canvas-sized layer from `img` (optionally limited to rows/cols or a pixel set)."""
    out = Image.new('RGBA', (MW, MH), (0, 0, 0, 0))
    p = img.load()
    o = out.load()
    for y in range(MY0, MY0 + MH):
        if rows and not (rows[0] <= y < rows[1]):
            continue
        for x in range(MX0, MX0 + MW):
            if cols and not (cols[0] <= x < cols[1]):
                continue
            if only is not None and (x, y) not in only:
                continue
            c = p[x, y]
            if c != BG:
                o[x - MX0, y - MY0] = c + (255,)
    return out


def rim_split(img):
    """(back, front) pixel sets of the rim + net region of a frame."""
    p = img.load()
    x0, y0, x1, y1 = RIM_BOX
    back, front = set(), set()
    for y in range(y0, y1):
        for x in range(x0, x1):
            c = p[x, y]
            if c == LANE:
                continue
            u = (x + 0.5 - RIM_C[0]) / RIM_OUTER[0]
            v = (y + 0.5 - RIM_C[1]) / RIM_OUTER[1]
            r = (u * u + v * v) ** 0.5
            below = y + 0.5 > RIM_C[1]
            ring = r >= 0.72 and r <= 1.08 and c in (BRIGHT_RED, PINK, RED, BLACK)
            skirt = y >= 58 and c == WHITE and 88 <= x <= 111
            if (ring and below) or skirt:
                front.add((x, y))
            elif y < 57 or (y >= 58 and c == WHITE):
                back.add((x, y))
    return back, front


def main():
    global PLATE_PX
    os.makedirs(OUT, exist_ok=True)
    frames = native_frames(SRC)
    plate = mode_plate(frames)
    PLATE_PX = plate.load()

    # ---------- clean machine ----------
    base = plate.copy()
    b = base.load()
    # Sign: wipe the scrolling text off the LCD (the game draws the live score there).
    for y in range(9, 14):
        for x in range(84, 114):
            if b[x, y] == TEXT:
                b[x, y] = SCREEN
            elif b[x, y] == TEXT_ON_GLARE:
                b[x, y] = GLARE
    # The strip's 3-pixel-tall "PLAYER:" is unreadable when scaled; the game redraws it live in a
    # cleaner font, so leave plain red here ("I", "II" and the lamps stay as drawn).
    for y in range(PLAYER_TEXT[1], PLAYER_TEXT[3]):
        for x in range(PLAYER_TEXT[0], PLAYER_TEXT[2]):
            b[x, y] = RED
    # Player lamps off (the game lights the active player's lamp).
    for lx, ly in LAMPS:
        for y in range(ly, ly + 3):
            for x in range(lx, lx + 3):
                b[x, y] = BLACK
    # Remove the kid, rebuilding what was behind them from the same row further left.
    kid, _ = kid_mask(plate, with_ball=False)
    for (x, y) in kid:
        if y >= 131:
            b[x, y] = BG
        elif TROUGH[1] <= y < TROUGH[3] and TROUGH[0] <= x < TROUGH[2]:
            pass  # the whole trough is repainted below
        else:
            b[x, y] = PLATE_PX[84, y] if (84, y) not in kid else PLATE_PX[80, y]
    # Empty the rack (the game rolls its own balls in it).
    for y in range(TROUGH[1], TROUGH[3]):
        for x in range(TROUGH[0], TROUGH[2]):
            b[x, y] = DARKER if y == TROUGH[1] else (DARK if y == TROUGH[1] + 1 else LANE)
    # Lift the rim + net off the board so it can slide along it (moving-hoop stages).
    rim_back, rim_front = rim_split(base)
    board_only = base.copy()
    bo = board_only.load()
    x0, y0, x1, y1 = RIM_BOX
    for y in range(y0, y1):
        for x in range(x0, x1):
            if y == 57:
                bo[x, y] = WHITE          # the board's bottom edge
            elif y == 59:
                bo[x, y] = BLACK          # where the board meets the lane
            else:
                bo[x, y] = LANE

    machine_layer(board_only).save(f'{OUT}/machine.png')
    machine_layer(base, rows=PANEL_ROWS).save(f'{OUT}/panel.png')
    machine_layer(base, rows=LIP_ROWS).save(f'{OUT}/lip.png')

    # ---------- rim + net, at rest and mid-swish ----------
    rim_imgs = {'rest': base, 'swish': frames[18]}
    for name, img in rim_imgs.items():
        back, front = rim_split(img) if name == 'swish' else (rim_back, rim_front)
        if name == 'swish':
            back = {q for q in back if q[1] < 62}   # frame 18's ball is below the net
            front = {q for q in front if q[1] < 62}
        to_rgba(img, RIM_BOX, back).save(f'{OUT}/rim_back_{name}.png')
        to_rgba(img, RIM_BOX, front).save(f'{OUT}/rim_front_{name}.png')

    # ---------- ball ----------
    ball_frames = [(0, 85, 79), (19, 93, 69), (5, 92, 75), (20, 89, 69), (6, 92, 59)]
    for k, (fi, bx, by) in enumerate(ball_frames):
        p = frames[fi].load()
        keep = set()
        for y in range(by, by + 14):
            for x in range(bx, bx + 14):
                if ((x + 0.5 - bx - 7) ** 2 + (y + 0.5 - by - 7) ** 2) ** 0.5 <= 7.05 and p[x, y] in BALL:
                    keep.add((x, y))
        to_rgba(frames[fi], (bx, by, bx + 14, by + 14), keep).save(f'{OUT}/ball_{k}.png')
    # Squashed ball (bouncing on the rim).
    p = frames[8].load()
    keep = set()
    for y in range(25, 37):
        for x in range(92, 108):
            if ((x + 0.5 - 100) / 8.1) ** 2 + ((y + 0.5 - 31) / 6.1) ** 2 <= 1 and p[x, y] in BALL:
                keep.add((x, y))
    to_rgba(frames[8], (92, 25, 108, 37), keep).save(f'{OUT}/ball_squash.png')

    # ---------- the kid ----------
    # Frame 1's ball sits over the red strip and the rack; its extent was read off the frame by hand.
    ellipses = {'lift': (99.0, 107.0, 7.3, 6.3)}
    poses = {'reach': (0, False), 'lift': (1, True), 'hold': (2, True), 'crouch': (3, True),
             'jump': (4, True), 'follow1': (5, False), 'follow2': (6, False), 'follow3': (7, False),
             'idle': (9, False), 'ready': (19, False)}
    KX0, KY0, KX1, KY1 = 78, 76, 122, 142
    kid_meta = {}
    for name, (fi, holding) in poses.items():
        mask, ballpx = kid_mask(frames[fi], with_ball=holding, ball_ellipse=ellipses.get(name))
        to_rgba(frames[fi], (KX0, KY0, KX1, KY1), mask).save(f'{OUT}/kid_{name}.png')
        if ballpx:
            xs = [x for x, _ in ballpx]
            ys = [y for _, y in ballpx]
            kid_meta[name] = {'ball': [min(xs) - KX0, min(ys) - KY0, max(xs) - KX0 + 1, max(ys) - KY0 + 1]}

    # ---------- sparkles (score celebration) ----------
    for k, fi in enumerate((17, 18, 19, 20)):
        p = frames[fi].load()
        keep = {(x, y) for y in range(150) for x in range(SX0, SX0 + SW) if p[x, y] in SPARKLE
                and not (67 <= x <= 132)}
        to_rgba(frames[fi], (SX0, 0, SX0 + SW, 150), keep).save(f'{OUT}/sparkle_{k}.png')

    meta = {
        'machineCanvas': [MX0, MY0, MW, MH], 'rimCentre': RIM_C, 'rimBox': RIM_BOX, 'trough': TROUGH,
        'panelRows': PANEL_ROWS, 'lipRows': LIP_ROWS, 'lamps': LAMPS, 'playerText': PLAYER_TEXT, 'kidCanvas': [KX0, KY0, KX1, KY1],
        'kidBall': kid_meta, 'sparkleCanvas': [SX0, 0, SW, 150],
        'palette': sorted({HEX(c) for f in frames for c in f.getdata()}),
    }
    with open(f'{OUT}/layout.json', 'w') as fh:
        json.dump(meta, fh, indent=1)
    print('wrote', sorted(os.listdir(OUT)))


if __name__ == '__main__':
    main()
