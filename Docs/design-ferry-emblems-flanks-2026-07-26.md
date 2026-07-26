# DESIGN FERRY — LIVING EMBLEMS + FLANK TENANCY (from design-side Claude, 2026-07-26)

Two accumulator items held for the next build wave. Preserved from `PENDING-FERRY.md`. Mockup for item 1:
`Docs/midispark-emblems.html`.

## 1. THE LIVING EMBLEMS — prominent processor icons
(user: "more prominent, something fun") Each type = a bold EMBLEM drawn from its musical action, ANIMATED by
the derivation clock — icons that PERFORM their type:
- ARP = the climb (dots light in pattern order at rate) · RTC = the stutter comb (one bar split to teeth,
  burst-firing) · PASS = the gate (pulses approach; scheduled pass the opening, off-schedule break on the
  fence) · STRM = the fan (stroke cascade; spread = strum time) · CHNC = the dice field (dots flicker
  unpredictably; density = probability) · HARM = the bloom (one note grows its stack) · OFF = the dashed
  empty (B picker only).
- PLACEMENT: the picker popover rows animate on a shared beat (the zoo — open the picker and every type
  demonstrates itself); panel TITLES get the emblem at ~28pt (static, or alive only for the sounding Colour —
  budget call at build); the item-10 disclosure ladder may later put mini-emblems on cells.
- PARAMETRIC where cheap (step/tooth count, density track the actual settings — item 10's law); tinted in the
  Colour's hue.
- BUDGET LAW: animate only what's visible (picker open / active title); Canvas glyphs off the existing
  derivation clock, no timers.
- Extends cleanly: MOD = a wave morphing sine→steps · RECORD = a pulsing dot · EXTERNAL = a plug. The emblem
  system is the roster's face. (Ties into the processor-type-header redesign — delta §6d — where the title
  carries the mini-glyph and the picker rows are the zoo.)

## 2. FLANK TENANCY — the three empty boxes (the placeholder flanks in the §6d layout)
- **TOP-LEFT = CONTROLS ("how time runs," beside the receivers):** STEP rate · SWING · **HOLD (big — it's a
  mode; modes get corners)**. The header slims to logo · EDIT/PERFORM · undo/redo.
- **TOP-RIGHT = VISUALIZATION — the picture IS the button:** a compact ambient visualizer (miniature
  flow/activity, governed by the OFF/SUBTLE/SHOWCASE intensity setting); **TAP IT = open full FLOW** (the
  header FLOW button dies; the door is a living thumbnail). DIAG keeps the slot as the DEV face
  (toggle/dev-build overlay).
- **BOTTOM-RIGHT = MASTER (item 14's corner, beside the emitters):** master FADER (momentary-absolute over
  the sum; HOLD-latchable — the whisper-drop) · master MUTE · the sum METER · **REVERT** (item 7: tap =
  at-wrap, double-tap = now) · the CHARACTER fader's reserved seat. The big-consequential-buttons corner.
- Same tenants both orientations wherever the flanks render. Corner semantics: time by the inputs · the sum
  by the outputs · the eye opposite the clock · signal falling through the middle.

## 3. THE MASTER PANEL (bottom-right corner — completes the console)
Anatomy mirrors the strips (kinship): the SUM METER behind a **master velocity FADER** (momentary-
absolute over all output; spring; §5c HOLD latches — the whisper-drop) beside a feature column:
- **MUTE** — tap = global emission kill (PERSISTED). **LONG-PRESS = PANIC**: all-notes-off + voice-
  table flush, logged by the hang kit (tap = dignified, hold = fire axe).
- **REVERT** — item 7's snapshot restore (tap = at-the-wrap · double-tap = now). SEAT RESERVED until
  the snapshot machinery builds.
- **KEY − / +** — master transpose PROMOTED to a built-in: semitones, clamp ±12, PERSISTED PER-SCENE
  (the key is structure), value shown when ≠0.
- **[INS]** — the master-insert Colour chip, reserved seat (item 14 future); a FULL-glide insert Colour
  reveals the CHARACTER fader beneath the panel (host-automatable via the insert's 200+i).
NO SOLO on master. Fader = weather; MUTE/KEY/INS = structure. Populates in waves:
fader+meter+MUTE+PANIC+KEY now; REVERT with snapshots; INS/CHARACTER with the wire work.

## 4. METER SEMANTICS REDESIGN (amends the receiver/emitter/master meter specs)
The VU-style bottom-fill lied — velocity is a VALUE, not a fullness.
- **METERING (passive) = FLOATING VELOCITY MARKS:** each note-on draws a mark AT its velocity height;
  it HOLDS while the note sounds (a chord shows its velocity fingerprint, steady while ringing) and
  FADES on release (~250ms). Multiple notes = independent marks (cap ~6 per strip). Shows spread,
  dynamics, held-vs-decaying — none of which the fill could say.
- **OVERRIDE (touching) = the FILL, correctly:** bottom-to-finger while touching (there it IS a level);
  the modes agree at the boundary (under override all marks sit at the finger height — the fill is
  their union). Spring on release; HOLD-latch keeps fill + held tick per §5c.
- **EMITTER MARKS TINT IN THE SOURCE CELL'S COLOUR** (the emission path already knows the cell): the
  mixer shows WHO struck and HOW HARD in one glance. Receiver marks = the strip's identity hue (input
  has no Colour). Master = same semantics over the sum, denser, capped.
- Language: they're VELOCITY MARKS now, not ladders — update the spec text where "LED ladder" appears.
  ⚠ AFFECTS THE SHIPPED STRIPS: the receiver/emitter sliders currently use the bottom-fill LED ladder;
  this redesign replaces that with floating velocity marks (a UI refinement, engine feed unchanged).

## 5. WAYFINDING — INPUT → GRID → OUTPUT → MASTER cues (RATIFIED 2026-07-26)
Three layers (sequence with the meter/visual pass; the spine may ride earlier):
- **THE SPINE (static):** a quiet 2pt low-opacity rail along the signal path's edge with CHEVRONS at the panel
  seams (INPUT ▾ grid ▾ OUTPUT ▾ MASTER). LAW AMENDMENT: the no-static-wiring law banned per-note patch
  cables; the spine is ANATOMY, not wiring — the one sanctioned static flow cue (same class as panel titles).
- **LIVING PULSES:** the spine carries traffic — input arrivals drop INPUT→keys, emissions fall grid→OUTPUT,
  the sum trickles OUTPUT→MASTER. Derived from the existing meter feeds; governed by OFF/SUBTLE/SHOWCASE; the
  flow layer's THIRD renderer (same engine as the theater + the thumbnail). Idle quiet; playing breathes.
- **THE FIRST-LIGHT SWEEP:** once per launch (or first note after load), ONE ~600ms teaching pulse runs the
  whole path — INPUT glow → grid sweep → OUTPUT → MASTER — then silence. Onboarding in one breath.
- Hue continuity (receiver tints + Colour-tinted marks + the pending cell input-attribution tint) is the
  fourth, already-ratified layer.

## 6. DESIGN FINDING — SUPPRESSION MUST BE VISIBLE (the withheld tell)
Claim/suppression is currently invisible: the flow layer shows notes travelling, nothing shows them dying.
Spec: a SUPPRESSED note renders as a HOLLOW / struck-through mark on the emitter meter (and a hollow
comet-fizzle in FLOW), with a small CLAIM-hue tick = "generated but withheld, and by whom." "The suppression
that can't be seen is the suppression that files bug reports."

## Screenshot-review flags (2026-07-26, console-built frame) — for alignment
(a) LIVE·SOLO foot: if LIVE = the mute button labelled by its ON-state, the muted state must fail LOUDLY
(dim strip + label → MUTED, not merely unlit) — user to rule. (b) Compact cell face must keep row-fed INPUT
ATTRIBUTION (a slim top-edge source-hue tint or ⇐n). (c) Verify the live-column highlight survived the layout
rebuild. (d) Emitter mini-meters still the old ladder — the velocity-marks redesign remains queued on top.
