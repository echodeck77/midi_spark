# UI port guide — mockup v26 → SwiftUI (build-order step 5)

The reference implementation is `docs/midispark-preview-v26.html` (React, runs in
any browser). It is the *behavioural* spec for the UI: when this guide and the
HTML disagree on look/feel/timing, open the HTML and match it. When either
disagrees with the spec on semantics, the spec wins.

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

1. **Header:** transport, STEP rate selector, SWING slider+readout, mode toggle
   (EDIT amber / PERFORM cyan), TAP action selector (perform), pass counter,
   momentary indicators (ISOLATE / STUTTER / LOOP n–m / ROW ALT).
2. **Grid 8×8** + side buttons (stack row on top, row column at right) + the
   wiring visualisation layer (source rails/taps, chain cables + chevrons, out
   rails, four bus lanes + lamps) + edit frame in the selected Colour.
   Cell anatomy: colour fill, type glyph rendering the ACTIVE state, badges
   (B top-left, M top-right, ∞ bottom-left, transpose bottom-right), LEGATO
   left-edge link tick, breathing ring (full B), static morph ring (opacity =
   effective morph), edit-mode spatial buttons (▸ left, A–D right, ▾ below).
3. **Bottom panel** with COLOUR ⇄ MORPH toggle:
   COLOUR view = palette (4×4 chips, type + →n badges, selection ring) + editor
   (TYPE, OUT CH, TRANSPOSE, PHASE, TIME/DENSITY ÷2×2, A/B tabs, params with
   HoldSeg selectors, MORPH fader).
   MORPH view = 16 strips (cap/fader/readout/type/B-dot) + divider + MASTER,
   SPRING toggle, hint line.

## Gesture map (the grammar, §0 — implement uniformly)

- Cell tap: EDIT = paint/clear/repaint · PERFORM+playing = TAP action ·
  PERFORM+stopped = audition hold semantics.
- Cell hold 300 ms: isolate (perform+playing) / preview (audition).
- Stack button: tap = SEL (edit) / mute, solo with S (perform) / APPLY (audition);
  hold = stutter, two+ = loop brace (perform+playing only).
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
- The wiring layer wants `Canvas`/`TimelineView` (event-driven animation only:
  current flows when MIDI flows — drive from a lightweight "activity" feed off
  the diag/emission counters, not a timer pretending).
- Playhead/pass for display: derive from the same host-beat maths as the engine
  (poll the AU at 30–60 Hz for beat position); never run a UI timer clock.
- Hold detection: `LongPressGesture(minimumDuration: 0.3)` composed with tap;
  replicate the suppress-trailing-tap rule exactly.
- Multi-touch: stutter+brace and multi-fader require simultaneous gestures —
  test on hardware early; this is where SwiftUI defaults fight you.
- Layout: iPad landscape first (mockup geometry); MORPH desk is ~17×44 pt strips
  wide — portrait needs the active-colours-only collapse noted in the spec's
  layout-pass task.
- Do NOT port: Babel/React scaffolding, the mockup's fake transport clock
  (the AU is the clock), mouse-event hold emulation.

## Order of work

1. Read-only grid bound to the document (cells, badges, playhead) — proves the
   binding against the running engine.
2. Edit mode (paint + spatial wiring buttons) — replaces TestSessions as the
   authoring path; re-run T1–T8 authored by hand.
3. Wiring visualisation (truthfulness against the MIDI monitor = acceptance 12).
4. Perform tap layer → hold layer → panel (COLOUR view, after the layout pass) →
   audition → MORPH desk → QUANT arming visuals.

**Pending design task (spec 6.9):** the COLOUR-panel layout pass happens BEFORE
porting the panel. Design conversations belong in the chat/design venue with the
mockup; port the outcome.
