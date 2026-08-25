# ✅ IDEA 24 TOUCH-TO-DIFF — LANDED 2026-08-25 (`535cae5`; iOS builds, UI-only; DEVICE eye owed). While a control is
# edited, the OUT strip + Stage Eye output lane show a live before/after: the edit clock is stamped at the single
# `buildApplyChain` choke point (gesture start + last change, cleared ~0.6s after quiet); notes born at/after the gesture
# start (the NEW behaviour) draw bright + white-ringed, earlier ones dim to a ghost, the box glows the hue. Only the
# OUTPUT diffs. Shared `buildRollCanvas`. TRUTH-STRIPS TRACK (§1 · §4 · 24) IS NOW FEATURE-COMPLETE (all device-eye owed).
#
# ✅ DEVICE-FEEDBACK PASS — 2026-08-25 (`7c1e5f7`; iOS builds, UI-only; DEVICE eye owed). Three fixes from Paul's look:
# (1) IN no longer flashes "nothing held" on every note-off — a per-door grace holds the state for a full PASS (8 steps
# playing · ~0.8s else, computed in the poll); during the grace the strip shows the last-held silhouette DIMMED, the
# teach text only after a genuinely empty pass (panel + eye INPUT lane). (2) OUT names its driver + dims when it isn't
# this cell: chain audition → "this chain"; PLAY THIS PART → "this cell — live" only when the edited rung is active under
# the playhead, else "part — not this cell" (dimmed). (3) The eye MECHANISM lane draws a real ARP note-WALK contour
# (UP/DOWN/UP-DN/RANDOM shapes + current step lit) instead of the generic 8 boxes; EUCLID keeps its pulses, other types
# the position lane (bespoke per-type mechanism art = the v2 rollout, now started with ARP).
#
# ✅ §4 STAGE EYE — v1 LANDED 2026-08-25 (`ff8a350`; iOS builds, UI-only; DEVICE eye owed). Tapping a truth strip opens a
# full-page 3-lane overlay (`buildStageEyeView`): INPUT roll (new `buildEyeInRoll`, onset-diffed off the door's held set)
# · MECHANISM (the machine live + a position light on the live column — EUCLID draws its pulse pattern via `euclidPattern`,
# others an 8-step lane) · OUTPUT roll (reuses `buildOutRoll`). v1 = the DRIFT model (rolls scroll, NOW = right edge).
# DEFERRED to v2: the fully column-aligned SWEEP (output tagged by emitting step) · bespoke per-type mechanism art ·
# embedding the real hero widget read-only. Idea 24 (touch→OUT diff) still open, builds on §1.
#
# ✅ §1 IN/OUT TRUTH STRIPS — v1 LANDED 2026-08-25 (`98bec19`; iOS builds, UI-only; DEVICE eye owed). The processor
# editor (BuildPage `buildProcessorPanel`) gains a slim IN | OUT band above the controls. IN = a C1–C7 keyboard
# silhouette lit by the held notes at the colour's input door (`recvHeldNotes[door]`, now polled while the editor is
# open); EMPTY-STATE TEACHES "nothing held — LATCH or play at INPUT A" (the cure). OUT = a live mini-roll of emitted
# note-ons drifting ~2.5s (new `buildOutRoll` from the read-and-clear `pollCellNotes`). v1: OUT aggregates the whole
# board (during a chain audition, part stopped, = the chain). DEFERRED: §4 STAGE EYE (tap-to-expand) + idea 24 touch-diff.
#
# ⚠ §2 AUDITION FALLBACK — was LANDED 2026-08-23, then REMOVED 2026-08-23 (Paul: a synthetic chord from nowhere "should
# never be part of the user experience"). The reference-chord path (`refPool`/`refChordDoor`/`referenceSet`) is GONE.
# So the "hear something anyway" half is retired; the §1 truth strips are now the sole cure — the SEE-IT half.
#
# INSTRUCTIONS → Code — THE IN/OUT TRUTH STRIPS (Paul, 2026-08-22:
# the TUTTI confusion, cured by visibility — ratified fix set)

## The root, named
The stage was fine; the INPUT was empty; NOTHING SAID SO. Silence
without explanation reads as breakage. The fix is truth, not
machinery.

## 1. EVERY STAGE PANEL GAINS TWO SMALL TRUTHS
- **IN — the held-note strip** (the receiver architecture's
  ratified keyboard silhouette, reused at panel scale): what this
  stage receives, live. **THE EMPTY STATE TEACHES**: when no pool
  is held, the strip shows words, not blankness —
  **"nothing held — LATCH or play at INPUT A"** (the door named,
  the cure pointed at; the §7 teach-in-place law).
- **OUT — the mini-roll window** (the window family, size S):
  what leaves the stage — the change visible. Tap either =
  the LARGER view (the window ladder; Paul's "fuller page
  piano-roll" = size L, both streams side by side).

## 2. THE AUDITION FALLBACK, REAFFIRMED (gotcha 2's ruling)
PLAY THIS MIDI CHAIN with an empty pool falls back to the
REFERENCE CHORD with a tell ("no input — reference chord") —
the button never appears broken. If unshipped, ship with this
set; the strips + the fallback together close the confusion from
both ends (see it, and hear something anyway).

## 3. Declined, with reasons (Paul's other candidates)
- **A HOLD processor / per-stage hold chips**: the DOOR owns
  holding (one concept, one home); a chain-duplicate splits it —
  and neither helps the confused user DISCOVER the cure (the
  person who didn't latch wouldn't add a hold stage either).
  The strips teach; duplicated holding wouldn't.

## §4 — THE STAGE EYE: the three-strata page (Paul, 2026-08-22 —
## captured with enthusiasm)
- **Every stage panel gains the EYE** — one grammar app-wide:
  the eye opens THE SPACIOUS VERSION of what you're looking at
  (grids → spacious grids; a stage → this page).
- **The page, three strata on ONE SHARED TIME AXIS**:
  - TOP — **the INPUT roll** (what arrives, live).
  - MIDDLE — **the MECHANISM** — v1 = the stage's own hero
    widget, embedded live + read-only with a position light
    (EUCLID's dots · TUTTI's slices · MOD's wave · RTC's counts —
    already drawn; zero new art). v2 = bespoke mechanism drawings
    where a card earns one.
  - BOTTOM — **the OUTPUT roll** (what leaves).
  The playhead sweeps all three: cause → machine → effect,
  readable vertically. EUCLID becomes self-explaining — Paul's
  own example, and the storefront thumbnails' living form.
- The truth strips (§1) remain the panel-scale summary; the eye
  is their L size. Empty-input teaching carries through (the top
  roll says "nothing held — LATCH at INPUT A" in the big view
  too).
- This page IS the manual's illustrations, live — every stage's
  doc figure = a capture of its eye view.
