# SPEC — Euclideous page rework

**Status:** RATIFIED by Paul, 2026-10-07 (including the mockup). Received via the `_dear_claude_code/`
design channel as `FERRY-euclideous-page-rework.md`; archived here as the durable spec, matching this
project's convention for ratified feature specs. Mask effect controls are explicitly deferred (§4).
Companion mockup: `Docs/euclideous-rework-mockup-2026-10-07.html` (the exact ratified layout — reuse
existing components wherever a mockup detail duplicates something the app already has).

## How to read this

- **§2 — Rulings.** Things Paul said he wants. Build these.
- **§3 — The ratified mockup.** Paul ratified the mockup, so its layout and details are part of the spec.
  Where a mockup detail duplicates something that already exists in the app, use the existing component,
  not an approximation.
- **§4 — Deferred or open.** Not decided. Do not invent an answer. Leave a clearly marked stub and raise
  it when reporting back.

Anything not mentioned here stays exactly as it is in the current build.

## 1. Context: the page as built before this rework

Euclideous is a standalone instrument page with 4 independent Euclidean lanes. Each lane strikes notes
from the currently held chord in a K-of-N pattern, or, with riff on, walks one shared hand-drawn step
sequence (the riff), advancing one riff step per hit.

The page had:

- **Header:** title; a RIFF pill that opens the riff editor as a popup (step count 1–32 with +/−); IN
  A/B/C/D; ON/OFF; close.
- **Each lane:** PLAY/STOP and the step box / comet bar (pinch changes N); three XY pads (HITS/OFFS,
  VEL/GATE, NOTE/OCT, the last relabelling to RIFF H/V when riff is on); a direction row (< / >< / >);
  HIT | MISS | RATE; a riff row (OFF / FWD / REV / PENDULUM / PING-PONG / RANDOM / DRUNK); beacons and
  OUT A/B/C/D.

## 2. Rulings (build these)

### 2.1 Riff editor on the main page
- The riff editor lives on the main page, not in a popup.
- The riff is hardcoded to 8 steps. Remove the step-count control.
- The header RIFF pill and the popup are removed.
- The riff control is reduced in size, to give the space to the lane boxes.
- Saved riffs longer than 8 steps: Paul's ruling is not to worry about them. No migration work required.

### 2.2 Reset span
- Add a reset span control.
- It is **global**: one control for the whole page.

### 2.3 Main output toggles
- Add main output toggles for the four emitters (A, B, C, D) on the page.

### 2.4 Note source: key or MIDI in
- Add a key picker. One key, global to the page.
- Add two KEY | MIDI switches: one for the riff, one for the lanes' own note picking.
- **MIDI in comes from receivers 1 and 4, behind the scenes, for now.** There is no input selector on
  the page.

### 2.5 Remove the MIDI IN selectors
- Remove the IN A/B/C/D selectors from the page.

### 2.6 Lane tabs
- Each lane gets its own row of tabs, placed under the XY pad section: **PATTERN**, **RIFF**, **MASK**.
- The tab row is per lane: each lane switches independently.
- The tabs switch the section below them between pattern settings, riff settings and mask settings.
- Each tab opens two lines' worth of controls.

### 2.7 Euclid mask per lane
- Each lane gets a Euclid mask.
- The mask has the same lane control (step box / comet bar), play button and count control as the lane
  itself.
- **Mask rotation is a gesture on the mask's grid itself.** No separate rotation control.
- The user will select what the mask does (Paul's working list: ratchet, mute, pause, repeat, oct,
  velocity, "etc."), but **the mask's controls are deferred** — see §4.

### 2.8 Lane boxes, toggles, beacons
- Lane boxes are square, using the space reclaimed from the riff.
- The emitter toggles are smaller.
- **Remove the hit/miss beacons.**

## 3. The ratified mockup

Layout, top to bottom, iPad portrait:

1. **Header row 1:** title · reset span · MAIN OUT A B C D · ON · close.
2. **Header row 2:** KEY (− / key-and-scale chip / +) · LANES KEY | MIDI switch.
3. **Lanes:** 2×2 grid of square boxes filling the width.
4. **Riff panel:** full width, underneath the lanes.

Each lane box, top to bottom:

1. Play/stop · step box / comet bar · step count shown as a number.
2. The three XY pads, unchanged in function, **each showing its current value on its face** (not just in
   a transient drag HUD).
3. Tab row: PATTERN | RIFF | MASK. The RIFF and MASK tabs carry a small dot that fills in the lane colour
   when that feature is on for the lane, so it is visible from another tab.
4. Two lines of tab content:
   - **PATTERN:** line 1, direction (< / >< / >). Line 2, HIT | MISS and RATE. HIT | MISS keeps today's
     tap-to-swap behaviour. The empty rate is labelled FOLLOW instead of "—".
   - **RIFF:** the seven existing options (OFF, FWD, REV, PENDULUM, PING-PONG, RANDOM, DRUNK) laid out
     over two lines (a 4-column grid), with short labels (PEND, PING, RAND).
   - **MASK:** line 1, the mask's own play button, step bar and count. Line 2 was drawn with an effect
     picker, effect amount and hit count − / +; line 2's contents are deferred (§4).
5. OUT A B C D for the lane, at the smaller size.

Other details:

- **Reset span:** a chip opening a picker of OFF / 1 / 2 / 4 / 8 / 16 bars.
- **Main out and lane out together:** main out is a master gate over the lane routing. A lane chip
  routed to an emitter whose main toggle is off is drawn dashed/hollow.
- **A lane with no output routed** shows a NO OUTPUT label.
- **Riff panel:** a single row of eight tall cells, one per step, each showing its note and a bar whose
  height is the pitch, with the per-lane position dots above the columns. Its header carries the riff's
  SOURCE KEY | MIDI switch. With KEY selected, cells are labelled with scale note names.
- **Toggle sizes:** lane OUT 30pt, MAIN OUT 36pt. Both are under the usual 44pt touch size; check on
  device.
- The mockup was drawn about 35pt taller than the plugin area in Paul's screenshots, so sizes need
  fitting on device.

## 4. Deferred or open — do not invent

**Deferred by Paul (to be discussed later):**

1. **Mask controls.** The effect list, what each effect does, the amount control, hit count, how the
   mask lines up against the lane, and whether a lane can hold more than one mask. Build the MASK tab's
   line 1 (play, step bar with gesture rotation, count) and leave line 2 as a marked stub. The mask must
   not change the lane's output until its effects are ruled.

**Open (not yet discussed or answered):**

2. **Reset span:** what exactly resets (pattern position, riff position, or both), and what RANDOM /
   DRUNK do at a reset.
3. **Key picker:** which roots and scales it offers, and whether it reuses the existing SCALE door /
   FOUNT machinery and KEY±.
4. **KEY mode pool:** how the key's notes map to ranks and octaves for lanes and for the riff.
5. **Default sources** for a fresh page (KEY or MIDI for each switch).
6. **Riff editing gesture** in the single-row control, and how many pitch ranks it must reach.
7. **Main out off:** whether notes already sounding are cut immediately.
8. **Per-lane RATE popup, pinch-for-N, lane selection highlight:** not discussed. Unchanged.

## 5. Acknowledgment sent

Replied via `_dear_claude/` with: what was built from §2/§3; where an existing component replaced a
mockup detail; and each §4 item hit, with the question for Paul. See that file (or its git history once
acknowledged/deleted) for the exact reply.
