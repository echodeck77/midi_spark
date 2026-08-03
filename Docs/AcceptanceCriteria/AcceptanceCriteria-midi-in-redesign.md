# AcceptanceCriteria — MIDI-IN REDESIGN (working latch · KEYS|CHORD · ENABLE · BYPASS · RANGE)
_From the design side (INSTRUCTIONS-midi-in-redesign, 2026-08-03). The user's full input-side ruling set + one bug._

## 0. BUG REPORT FIRST (prerequisite)
**The current on-strip LATCH doesn't seem to do anything** (user, on device). DIAGNOSE before building — the
features below assume a working latch underneath.

## 1. THE STRIP (per door, top → bottom)
- **LATCH — BIG.** Strip sizing law: everything small EXCEPT LATCH (easy to hit in the heat of the moment). Lit
  when armed.
- **KEYS | CHORD** — a small toggle directly under LATCH (the mode, moved OUT of the cog per the split law):
  - **KEYS (DEFAULT):** each key played is ADDED to the latch pool; playing it again REMOVES it (per-note toggle).
  - **CHORD:** on chord detection, the pool CLEARS and REPLACES.
  - **Mode-switching NEVER clears the pool** — the latch persists across the toggle; only LATCH OFF releases.
- **ENABLE/DISABLE** — small per-door toggle: DISABLED = the door STOPS LISTENING (incoming MIDI ignored) while its
  latched pool + sounding state PERSIST. Workflow: latch a chord on R1, disable R1, move to R2 and play fresh —
  "close the door, keep the room." Distinct from LIVE (which mutes OUTPUT); this gates INPUT. Default: enabled.
- **BYPASS** — small toggle: the door's stream (post its shaping — octave, velocity, range) routes DIRECTLY to
  emitters, skipping the grid. Destination = the door's bypass mask (cog §2), default ALL four. PIN: v1 bypass is a
  direct injection (no role gating — the word is "directly"); flag if role interplay is ever wanted.
- Existing tenants (OCT±, fader, LIVE·SOLO, THRU pip) stay, sized small per the law.

## 2. THE COG (per-door line gains/loses)
- **GAINS: RANGE** — bottom note + top note (two small note chips), default ALL. The door admits only notes in
  range (the lens gains a window; UPSTREAM of latch and everything else).
- **GAINS: BYPASS DESTINATIONS** — a per-door multiselect (A–D), default all — where §1's BYPASS routes.
- **LOSES: the latch-type chip** — the mode now lives on the strip as KEYS | CHORD. Remove from the cog.
- With cables retired (prior instruction), the cog line reads: **hue·label · CH chip · RANGE chips · BYPASS dests · MPE.**

## 3. Defaults, restated
KEYS · CH OMNI · RANGE all · ENABLED · BYPASS off (dests all) · LATCH off. A fresh door is a wide-open, honest lens.
