# Pocket Hoops

A pixel-art arcade basketball game for iPhone. You see the whole machine from above, exactly like
the reference GIF (`art/reference.gif`): the glass score sign, the backboard and rim, the ramp, the
`PLAYER: I II` panel with its ball rack, and the kid standing in front of it. **Swipe up to shoot.**

SwiftUI menus + SpriteKit game, no third-party dependencies. The art is the reference GIF itself:
`scripts/extract_gif_art.py` cuts every sprite out of it (see *Art pipeline*); score, clock and
messages are drawn live on top. Every sound is synthesised at launch.

## Run it

```bash
xcodegen generate          # only needed after adding/removing files
open PocketHoops.xcodeproj
```

- **Simulator:** pick an iPhone and press Run.
- **Your iPhone:** Xcode › target *PocketHoops* › Signing & Capabilities › pick your Team
  (a free Apple ID works; the app then lasts 7 days before re-installing).

## Art pipeline

```bash
python3 scripts/extract_gif_art.py art/reference.gif   # needs Pillow
```

The GIF is 800×600 but drawn in 4×4 art pixels, so each frame is reduced to its native 200×150
art. The script then writes, 1 PNG pixel = 1 art pixel, into `PocketHoops/GIFArt/`:

- `machine.png` — the cabinet with the kid, ball, rack balls and sign text removed (every frame's
  per-pixel majority colour, then the kid's area rebuilt), and the rim lifted off the backboard.
- `panel.png`, `lip.png` — the front panel above/below the rack; rack balls are drawn between them,
  so only their middles show, like the jumble in the GIF's tray.
- `rim_back_*`, `rim_front_*` — the rim and net, at rest and mid-swish (GIF frame 18); a ball in
  the hoop is drawn between them.
- `ball_0…4.png` (rotation frames), `ball_squash.png` (rim bounce), `kid_*.png` (the kid's ten
  poses; the ones holding the ball include it), `sparkle_0…3.png` (the make celebration).
- `layout.json` — where everything sits; `GIFLayout` reads it.

In game the scene's unit is one art pixel, shown as a whole number of device pixels (15 on an
iPhone 17 Pro Max). Each sprite is upscaled 2× with Scale2x (EPX) when it's loaded — that only
rounds off diagonal staircases, keeping straight edges and every colour as drawn — so the art is
the GIF's, just a touch less chunky. The rim is one ring split into two layers (behind and in front
of a ball in the hoop), so its pixels are upscaled as one piece and then split again (`GIFArt.rimCanvas`).
Upscaled apart, each layer rounded its corners off at the seam and the board showed through. The strip's "PLAYER:" and all live text use a clean 5×7 font
at half-pixel resolution (the GIF's own lettering is 3 px tall). Themes and ball skins are palette
swaps of these sprites (Classic / Arcade Red are the GIF as is).

```bash
python3 scripts/make_outfits.py [--preview out.png]    # characters + accessories
```

`scripts/outfit_regions.py` labels every pixel of the kid's ten poses (hair, head, arms, hands,
shirt, pants, shoes, ball). `make_outfits.py` then draws each character and accessory onto those
parts with the GIF's black outlines and shading ramps, and writes `outfit_avatar_*.png`,
`outfit_acc_*.png`, `outfit_hair_*.png` (hair worn over clothes) and `outfits.json` into
`PocketHoops/GIFArt/`. At load time the game stacks the layers: character → pants → shoes → shirt →
jacket → over-clothes hair → hat. It then applies Scale2x and the ball skin, as for every sprite. To
add an item, give it a drawing function in the script and an entry in `Wardrobe.swift`, then re-run
the script and `xcodegen generate`.

## How to play

- Touch near the kid and he steps sideways with your finger (he crouches while you hold);
  **flick up** to shoot — he jumps, releases, follows through, then reaches into the rack for the
  next ball, using the GIF's own frames.
- Flick **speed** = distance, measured from the stroke's peak (fingers slow down before lifting).
  The game learns how hard *you* usually flick (`FlickCalibration`), so your normal flick drops in
  (about 0.7–1.25× your usual goes in); noticeably softer hits the front rim or falls short, and
  clearly too hard (1.3× and up) flies over the rim, bangs off the backboard high up and rebounds
  back out over the lane into the tray. However hard you flick, the ball always goes *over* the rim.
  Flick **direction** = aim.
- 3 in a row puts you **ON FIRE**: double points until you miss (watch the lamps on the strip).
- Swish = +1 bonus. The last 10 seconds of every stage are a **3-point frenzy**.

## Modes

| Mode | Rules |
| --- | --- |
| Arcade | 40 s. Reach 80 by the buzzer for Stage 2 (+20 s, moving hoop), 300 in all by the next buzzer for Stage 3 (+15 s, faster). |
| Daily | Same twist for everyone each day (moving hoop, crosswind, tiny/big rim, moon/heavy gravity). Builds a day streak. |
| Sudden Death | 3 lives, no clock. The hoop starts moving and speeds up every 5 baskets. |
| 2 Player | Pass-and-play: 30 s each, highest score wins. The results show a card per player with their own score and stats. |
| Practice | No clock; the aim coach tells you "flick harder / softer / aim left / right". |

**Tickets** come out after every game (plus daily-mission rewards, a first-daily bonus and a small +2
for a new best) and are spent at the **Prize Counter**: 1 ticket per 6.2 points in Arcade, 4.1 in the
Daily, 8.3 in 2-Player (best score), 1 per basket in Sudden Death and 1 per 10.3 baskets in Practice
(`PlayerProgress.pointsPerTicket`). **Missions** rotate daily; career stats live there too.

## Prize Counter

Three tabs: **BALLS**, **CABINETS** and **PLAYER** (characters, hats, shirts, jackets, pants, shoes).
Every item costs tickets *and* has a progress requirement taken from the lifetime stats: games played,
baskets made, best single-game score (Arcade or Daily), swishes, or most baskets in a row. Cheap items
need little or nothing; rare items need a lot of play. A locked item shows what it needs and how far
you've got ("MAKE 250 BASKETS: 112/250"). BUY is only enabled once every requirement is met *and* you
have the tickets. Tap any item, locked or not, to preview it; characters and clothes are tried on the
animated shooter. Owned items can be equipped or taken off for free, and purchases and what's worn are
saved.

One item is worn per category. A character replaces the whole shooter. Your accessories stay equipped
when you switch characters, and a character that can't wear something just doesn't show it: Robo,
Bruno Bear and Legend are costumes that wear nothing, and Zorp's antennae leave no room for a hat.

To change a price or a requirement, edit the lists in `Art/Wardrobe.swift` (characters and accessories)
and `Art/Catalog.swift` (balls and cabinets), for example `.needs(.baskets(400))` or
`.needs(.games(40), .score(150))`.

## World leaderboard

The 🏆 button under the settings button on the menu, and the **LEADERBOARD** button on Arcade
results, open the world board. It shows everyone's best Arcade score, highest first, with each
player's name and the character they play as. Equal scores share a rank. Your own row stays pinned
at the bottom however far down you are ("#61 JASON 15"). Joining is opt-in: nothing is sent until you
pick a name (up to 10 of A–Z, 0–9 and spaces). After that, a new Arcade best goes up by itself, and
so does your current look. The last board loaded is kept on the phone, so it shows at once and
while offline.

The scores live in a small Supabase database: one table, and two SQL functions the app calls over
Supabase's REST API. You need your own Supabase project (the free plan is enough):

1. Create a project at supabase.com. Then either paste
   `supabase/migrations/20260927120000_world_leaderboard.sql` into its SQL Editor and run it, or use
   `supabase init`, `supabase link --project-ref <ref>` and `supabase db push`.
2. In project.yml, set `BOARD_URL` to `https://<project-ref>.supabase.co/rest/v1` and `BOARD_KEY` to
   the project's anon (or publishable) key, from Project Settings › API.
3. Run `xcodegen generate` and build.

While either value is empty, the board says it isn't switched on yet and nothing is sent anywhere.
Worth knowing:
- The key is public by design, so a determined player could post a fake score. The database only
  turns away impossible ones (over 3,000) and bad names.
- Names aren't filtered for rude words. Before an App Store release you'd want a way to report or
  remove them. You can already delete a row in the Supabase dashboard.
- Free Supabase projects pause after a week with no traffic; unpausing is one click.
- Apple's Game Center would handle names, cheating and hosting for you, but it needs the paid
  Apple Developer Program.

To try it without a Supabase account, run a local copy: `supabase init` once, then `supabase start`,
which applies the migration and prints a local anon key. Launch a Debug build in the simulator with
`-boardURL http://localhost:54321/rest/v1 -boardKey <that key>`.

## Code map

- `Game/Physics.swift` — fixed-step 3D ball sim: sloped ramp, rim torus, backboard, glass walls, net, ball–ball.
  The cabinet is enclosed (ceiling net), launch speed is clamped, fast balls are sub-stepped so
  nothing tunnels, and any lost/invalid/wedged ball is sent back to the rack — a ball never vanishes.
  The net is a solid cone to any ball that didn't come down through the ring, so nothing can slip
  under the rim. Rim/board friction acts per impact (a resting ball rolls out of the rim–board gap).
  A ball only leaves play once it has rolled off the ramp or come down into the tray, never mid-air.
- `Game/Rack.swift` — the ball rack: returning balls drop in from the return chute and roll (with
  spin) down to the pile the kid reaches into.
- `Game/Aim.swift` — flick → launch velocity (comfort zone, aim assist). Over-hits get flatter but
  never flatter than `clearingAngle` (the arc that still clears the front of the rim), and past the
  make window they get long fast so they rebound out. Tuned by `AimTests` — re-run after any change.
- `Game/Flick.swift` — reads a swipe (peak speed, direction of the fast part) and calibrates the
  player's normal flick speed.
- `Game/Projection.swift` — maps the 3D court onto the GIF's pixels (scale factors measured off the
  art — including the rim's depth, so a ball that looks centred in the drawn rim *is* centred).
- `Game/GameRules.swift` — modes, clock/stages/lives, scoring, fire, daily seed.
- `Game/GameScene.swift` — SpriteKit scene: rendering, the kid, HUD, input, attract mode (menu background).
  `rimLayer(of:court:)` draws each ball on the side of the rim it's really on (through the hoop,
  in front of the ring, or behind it), so a ball rolling off the rim never looks like it went through.
- `Art/` — `GIFArt` (loads/recolours the GIF sprites, composites outfits onto the kid), `Catalog`
  (skins/themes as palette swaps, with prices and requirements), `Wardrobe` (characters, accessories,
  `Outfit`), `PixelFont` (menu font + the sign's 3×5 LCD font), `PixelCanvas`.
- `Meta/Progress.swift` — save data, lifetime stats, tickets, bests, missions, purchases and what's
  equipped (UserDefaults; older saves load with everything they owned).
- `Meta/Unlocks.swift` — the requirement model (`.games`, `.baskets`, `.score`, `.swishes`, `.streak`)
  and the "112/250" progress text.
- `Meta/WorldBoard.swift` — the world leaderboard: name rules, the Supabase/PostgREST client and the
  cached board. `supabase/migrations/` holds its table and functions.
- `UI/` — menu, game wrapper, results, prize counter (preview + try-on), missions/stats, leaderboard.

## Debug launch arguments (Debug builds only)

`-play arcade|daily|streak|versus|practice` jump into a mode · `-screen prizes|missions|leaderboard` ·
`-autoplay YES` the game shoots for itself · `-forceTheme <id>` / `-forceSkin <id>` /
`-forceOutfit <character>,<item>,…` (e.g. `jenn,beanie,hoodie`) preview a look without touching the
save · `-rich YES` top up to 2,000 tickets · `-boardURL <url> -boardKey <key>` point the world
leaderboard at a test server.

## Tests

```bash
xcodebuild test -project PocketHoops.xcodeproj -scheme PocketHoops \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro'
```

53 tests, including: wild flicks at any speed/angle never lose the ball or pass through the board,
rim, glass or ceiling; hard flicks (1.1×–50× the player's normal flick, any angle, hoop anywhere)
never go under the rim or into it; the net stops balls that didn't go through the ring; a ball
knocked through the ring still counts; rebounds aren't removed mid-air; a ball can't stick behind
the rim, or sink into it when squeezed into the rim/board/glass corner; balls are layered on the side
of the rim they're really on; corrupted balls are recovered to the rack; rack balls drop in, roll down and
settle without overlapping; the flick make-window is forgiving but bounded; tickets pay about half
what they used to in every mode (daily bonus and missions too); every GIF sprite loads
for every theme/skin/pose; skins/themes only swap colours; every character and accessory draws in
every pose; old saves load with everything they owned; requirements gate buying and show progress;
owned items re-equip for free; the shop catalog matches the art (cheap items need little, rare ones
need real play); each 2-player results card has only that player's shots (a shot that drops after
the final buzzer counts for P2); the rim is solid all the way round in every colourway, with only its
seams changed by the fix; the leaderboard sends what its SQL functions expect, reads their
reply, sends nothing before you join, keeps the last board for offline, and every line of it fits an
iPhone SE; names and looks only use what the font and the database accept; plus scoring, stages,
lives, 2-player, daily, tickets/missions and font coverage.

The app icon is drawn by `scripts/make_icon.py` (needs Pillow) from the game's own sprites, Scale2x and
3×5 LCD font, so it matches the art in game. Re-run it after `extract_gif_art.py`;
`--preview out.png` shows it at home-screen sizes.
