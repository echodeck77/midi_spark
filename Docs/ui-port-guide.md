# UI port guide — mockup v60 → SwiftUI

The reference implementation is `Docs/midispark-preview-v60.html` (React, runs
in any browser; v60 adds the §6a emitter-toggle panel behaviour). A first grid slice EXISTS in the repo built to an earlier
generation — reconciliation, not greenfield, is the task (see the migration
doc's GUI section for sequencing). It is the *behavioural* spec for the UI: when this guide and
the HTML disagree on look/feel/timing, open the HTML and match it. When either
disagrees with the spec (v2.8 + v3.0-delta) on semantics, the spec wins.
v26–v49 are historical; v50/v51 contain a JSX bug (do not open); v52–v58 are
intermediates; v59 is canonical. v40 is the preserved abandoned fork.
MOCKUP-ONLY AFFORDANCE — DO NOT PORT: the header's AUTO/WIDE/TALL layout
toggle exists so both orientations can be previewed in a browser; the real
app derives orientation from size classes, never a user toggle.

## Design tokens

**The sixteen Colours** (order = bank order = `colourIDs` in Models.swift; these
hexes are canonical and brightness-separated on purpose — do not "harmonise" them):
gold #FFC53D · orange #FF7A1A · vermilion #FF4B33 · wine #C2244B · magenta #FF4D9E ·
blush #FFA8B8 · purple #B44DFF · violet #7A3DF0 · indigo #5566FF · azure #38A6FF ·
cyan #25E0F0 · teal #148F80 · mint #7BF2CE · green #2ECC5E · chartreuse #C6F23D ·
bronze #C9A227

**State hues** (§6.5 — hue + motion + location): white = select/isolate/step-lock ·
coral = mute · amber = bypass & EDIT accent · lime = solo · cyan = alt/apply &
PERFORM accent · dashed red = no destination. Exact values: read the `HUES`
constant in the HTML.

**Timing constants:** hold threshold ≈ 300 ms (cells, side buttons, panel
borrow) · B-state breathe cycle 1.4 s · SPRING return glide ≈ 180 ms ·
QUANT-armed blink = fast, half intensity. Dark theme: background/ink values in
the HTML's `T` constant.

## Component inventory (top → bottom of the mockup)

1. **Header:** "8×8 STATE" logotype (the DECIDED public name — display-only;
   code identity stays MidiSpark, see CLAUDE.md vocabulary), mode toggle (EDIT amber /
   PERFORM cyan), STEP rate, SWING, PASS counter, transport, momentary
   indicators. (v54 decision: STEP/SWING live HERE, not the desk. The TAP
   action selector was REMOVED at `3e816ee` with MUTE/BYP — PERFORM tap is
   ALT-flip only pending the TOUCH design pass; engine fields retained.)
2. **Playhead strip:** the master DOWN-ARROW sweeping above the grid —
   continuous through each step, swing-stretched, loop-snapped.
3. **Grid 8×8** + side buttons (stack/MUTE row on top, row column at right) +
   edit frame in the selected Colour. NO wiring layer of any kind.
   **Cell anatomy (four rows, spec v3.0-delta §4):**
   ① INPUT HEADER "FROM MIDI" / "MIDI CHn" (filtered) / "FROM ROW n"
   (dim=default, bright=patched, white flare=receiving; EDIT tap opens the
   FROM POPOVER: any occupied row except self + the IN CH filter control
   when MIDI IN is selected) ·
   ② type GLYPH · ③ PARAMS text from EFFECTIVE state ("1/16", "1/8 ×3") ·
   ④ A–D EMITTER strip (ring=on, recess=off, white flip+down-glow=firing;
   EDIT tap opens the OUT POPOVER with four A–D toggles). Plus: badges (B/M/∞/transpose at row-2/3 corners),
   LEGATO left tick, breathing ALT ring, falling MUTATION sweep on working
   cells of the live column (faint when bypassed), row-number WATERMARK on
   empty cells (perform).
4. **Desk (a PERFORMANCE surface — delta §6): three NAMED boxes** in fixed
   order COLOUR → PROCESSOR → EMITTERS; stacked vertically in the right
   third beside the grid in landscape (grid takes two-thirds), left-to-right
   thirds below the grid in portrait ("the grid is square, screens are
   not"). Scroll policy: ONLY the PROCESSOR box may scroll (content-sized to
   a ceiling); COLOUR and EMITTERS never. COLOUR = palette 4×4 + selected
   name·type readout. PROCESSOR = A/B tabs + the selected Colour's fields
   (TYPE, TRANSPOSE, PHASE, TIME/DENSITY, params — NO channel field;
   channels are bus-owned; the frame is FIXED-SIZE per orientation, sized
   for the largest type's field set — the STATIC FRAMES RULE, delta §6:
   boxes never resize or move with content; use fixed frames in SwiftUI,
   never intrinsic sizing, for all three boxes). EMITTERS = four channel
   strips (§6a revs, mode-aware in ONE static frame; the as-built
   caption-popover is superseded — see CLAUDE.md a7). BOTH modes: toggle
   pad on top (per-output mute; disabled = recessed, no flash; flashes per
   emission when live). EDIT face: a DEDICATED per-emitter CH selector
   below each toggle (visible value; no popover, no selection state).
   PERFORM face: velocity slider + green LED ladder (momentary ABSOLUTE
   override — greyed idle, spring-back, post-transform metering) + CLAIM
   radio per strip. KINSHIP LAW: toggles share the CELLS' emitter-letter
   vocabulary, scaled — the panel reads as the cells' strips, summed.
   All-cable note + shared-channel warning remain. MORPH desk:
   PARKED (own later pass); RESERVED above COLOUR: the MIDI-IN display
   (details TBD).
5. **SCENE strip:** full-width along the bottom in both orientations —
   SIXTEEN grid-idiom slots, current ringed. Release builds wire
   `SceneFactory` (Docs/factory-scenes.md); dev builds host the canned test
   sessions via the DEV LOADER (as built: portrait plugin UI only).

## Gesture map (the grammar, §0 — implement uniformly)

- Cell tap: EDIT = the unified CELL EDITOR pop-up (delta §5 rev 2: colour
  picker + input rows/IN CH + emitter toggles + CLEAR/COPY/PASTE-COLOUR/
  PASTE-ROUTING; inspector behaviour — picks persist, cell-taps retarget;
  SESSION TEMPLATE pre-fills empties, commit on first interaction; STAMP
  MODE via "COPY TO CELLS…" with banner + overwrite tint) · PERFORM+playing
  = ALT flip (richer actions return via TOUCH) · stopped+hold (BOTH modes)
  = audition (delta §5 rev 2 restored EDIT+stopped). Column keys: tap
  unassigned; HOLD = the §5b lap (SHIPPED, ColumnHoldOverlay). The whole
  pad is ONE target in BOTH modes — no sub-cell zones remain (the sub-44
  openers law retires for cells; FROM/OUT popovers dissolved into the
  editor). Drag-from-palette survives as a paint accelerator.
- Cell hold 300 ms: audition (stopped, both modes); isolate
  (perform+playing) remains provisional pending TOUCH.
- Row button: tap = SEL (edit) / row bypass (perform); hold = row ALT push.
- Panel selectors: tap sets, hold borrows (white glow), EXCEPT the PHASE selector
  (plain). Faders: drag sets; double-tap zeroes; SPRING makes release glide home.
- A completed hold always suppresses its trailing tap. Mode switch and transport
  stop clear every momentary thing.

## SwiftUI porting notes

- One observable document store on the main actor owning `PluginState`; every
  mutation calls the AU's existing `scheduleRebuild()` path. UI state that is
  NOT document state (selections, held sets, armed QUANT set, panel view) lives
  in view-local state and must never enter fullState.
- Playheads (master arrow + falling cell lines) and header/emitter flares:
  ALL are pure functions of the one derived beat fraction + emission activity
  polled from the AU — the ONE-CLOCK RULE (v3.0-delta §4) is binding; no view
  owns an animation clock. `TimelineView` reads, views render.
- The mockup's per-step CSS animations are a simulation artifact — do NOT
  port that mechanism; derive positions per frame.
- Hold detection: `LongPressGesture(minimumDuration: 0.3)` composed with tap;
  replicate the suppress-trailing-tap rule exactly.
- Multi-touch: stutter+brace and multi-fader require simultaneous gestures —
  test on hardware early; this is where SwiftUI defaults fight you.
- Layout: implement the delta §6 responsive rule (aspect-driven breakpoint,
  not device-driven). Landscape desk column has height to spare; PORTRAIT is
  the tight case — apply the height budget there, tuned on device.
- Do NOT port: Babel/React scaffolding, the mockup's fake transport clock
  (the AU is the clock), mouse-event hold emulation.

## Order of work — STATUS: steps 1–5 DONE (the reconcile shipped; see
## CLAUDE.md). Remaining UI work lives in CLAUDE.md NEXT (§5b lap visuals,
## §6a toggles, size gate). Kept for the record:

1. SURVEY the existing grid (migration doc GUI section): what it binds, which
   visual generation it implements. List before editing.
2. Rebind to the new schema (inputRow / inputChannel / busChannels) once the
   engine migration lands — the grid must never write old fields.
3. Reconcile visuals to v59/v60: four-row cell, watermarks, playheads (one-clock
   rule), header/emitter states. Acceptance 12 (rescoped): header names the
   live parent; emitter strip matches actual emission — verify vs a monitor.
4. Edit interactions: FROM/OUT popovers → then drag-and-drop + hold menu.
5. Desk: three-box responsive placement + SCENE strip (wire scene slots to
   the TestSessions loader in dev builds) → perform layers → audition
   (incl. EDIT-stopped hold, delta §5) → QUANT arming visuals. MORPH desk
   returns as its own later pass.

The §6.9 layout pass is CLOSED — delta §6 is its outcome; implement, don't
re-design.
