# INSTRUCTIONS → Code — THE INTERFACE REDESIGN (Paul, 2026-08-28)
# ⚠ STALENESS BANNER (2026-09-04): MUCH OF THIS HAS SHIPPED. The ROOMS surface
# (SELECT / PART / PLAY grids + the reel-to-reel pass browser) is now the SOLE
# interface (the old tab/PERFORM-EDIT/cell-editor surfaces are retired). This doc
# is kept as the ORIGINAL redesign shape + the remaining unbuilt increments — it is
# NOT a status record. For what actually shipped vs what's still open, the CLAUDE.md
# status log + Docs/pending-tasks.md are the source of truth; where this prose says
# "not built" it is very likely already built.
# STATUS: PARTLY BUILT; remaining increments TO BE IMPLEMENTED WITH PAUL'S GUIDANCE
# (the door-loop pattern: this is the shape; he walks the build; device steps
# outrank prose).
# ★ THE STANDING ORDER: USE EXISTING COMPONENTS WHEREVER
# POSSIBLE — real components, NOT approximations. §6 names the
# expected reuses; deviations need Paul's word.

## §1 — THE GEOGRAPHY (buttons only; nothing drags)
Three rooms + the tape, one grid in view at a time:
- **SELECT GRID** (the shop) · **PART GRID** (the workshop) ·
  **PLAY GRID** (the stage) · **THE REEL** (the tape).
- Navigation = TAPS on thin door-buttons (no pane-drags, ever —
  musical drags own the surfaces). SELECT and PART each wear a
  **thin top door-button sweeping up to the PLAY grid**. The
  play grid's **bottom row = the provenance doors home** (§4).
- **RECORD stays cornered** (bottom-left) in every room.
- The **CHAIN EDITOR is a summoned overlay** — expands over the
  grid for editing; **tap the uncovered grid = it RECEDES** (the
  sheet grammar; the existing ≤600pt docked editor IS this
  component, re-housed).
- **THE FOOTER STACK**: a persistent footer, tapping outward:
  footer → THE MIXER STRIP (the existing I/O console) → MIDI
  CONFIG (the existing sheets). Grid-tap recedes the stack.
  **THE DECK (ROW 8's verbs + config-hub jumps) is PARKED — its
  eventual home is the footer.** Until it lands, row-8 features
  stay where built; nothing is deleted.

## §2 — THE SHARED HEADER (one component, four surfaces)
**Eight cells, the same objects everywhere**: the SELECT grid's
top row · the PART grid's top row · the REEL page's header · and
the PLAY grid's track-heads. They are ONE component with room-
dependent sources:
- **TAP = play/stop that track** (the mute-toggle; mirrored
  state everywhere).
- **LONG-PRESS = ASSIGN to that track**: from SELECT = whatever
  the seat is playing (the live chain) · from PARTS = flatten
  that part · **from THE REEL = the current selection (one pass
  or several, one emitter or several — the existing pass-range +
  lane-toggle selection) becomes a RECORDED track.**
- **DELETE = the armed-DELETE ceremony only** (a remote that can
  destroy from another room is never a bare tap).

## §3 — THE PLAY GRID (the stage)
- **EIGHT VERTICAL TRACKS, all equal** (no in-grid action deck).
  Tracks run top-to-bottom; the header cells are their heads.
- Track types by the PROVENANCE LAW: LIVE (assigned from the
  seat) · FLATTENED (from parts) · RECORDED (from the reel).
  Notes carry their recorded wires (replay honours addresses);
  decompose per the two verbs (FLIP LIVE · UNPACK) as filed in
  OPEN-play-grid-lanes.md.
- **The track cells' interior rendering: RESERVED** — plain for
  now (the variation-slots future is deliberately unblocked);
  Paul rules if a rising mini-roll comes sooner.

## §4 — THE SEAMS
- **SELECT ↔ PARTS: the SIDE BUTTONS** (the shared exclusive
  column): multiple mutually-exclusive assignments dealt from
  the select grid; the same buttons RECALL those parts for
  editing on the part grid. One component, two rooms.
- **THE STAGE ↔ HOME: the bottom provenance row**: each track's
  bottom cell = its way home, wearing the track's HUE + a
  provenance mark (**shop · bench · reel** — three marks). Tap =
  navigate to the source room with SELECTION TRAVELLING (land on
  the source cell/machine/pass).

## §5 — THE VOICE LAWS
- **THE SILENCE LAW (room-scoped voices)**: tracks are room-
  independent (the performance persists everywhere). Auditions
  (the seat, the candidate) are ROOM-SCOPED: **entering the PLAY
  grid stops the workroom voices** — the stage owns the sound
  when you stand on it. Feel-edge for Paul's glass: returning to
  a workroom, the seat stays SILENT until re-tapped (lean; no
  auto-resume).
- The stack-and-seat model stands as filed (§8 of the lanes
  doc): many in the stack (the tracks), one in the seat, the
  seat to the last exclusive tap.

## §6 — ★ THE EXISTING-COMPONENTS MANDATE (the expected reuses)
- The docked chain editor → the summoned overlay (re-housed, not
  rebuilt).
- The I/O console strips → the footer's mixer layer, verbatim.
- The MIDI/RACK sheets → the footer's config layer, verbatim.
- The pass browser's selection machinery (ranges · lane
  toggles · the wash) → the reel's assign payload.
- The multi-row/stack machinery (persistence · mute-taps ·
  freeze-at-park I/O) → the tracks, as filed.
- stateMatrix / slider-lane / nudge-pair species → unchanged,
  everywhere they live.
- The two-depth grammar (tap/hold), armed-DELETE, the hue
  system, provenance marks from the badge vocabulary.
Anything that would be approximated instead of reused: STOP and
ask Paul first.

## §7 — Open, named (small)
Seat-resume feel on room-return (§5's lean) · the deck's footer
arrival (parked) · track-cell interiors (§3, reserved) · the
naming pass (SELECT/PART/PLAY = working titles; no-metaphors
christens later) · the door-buttons possibly carrying miniature
state (track mutes / part hues) — spice, Paul's call.
— design-side Claude

## §4b — THE BOTTOM BAND (Paul, 2026-08-28 — amends §4's play-
## grid bottom row)
The play grid's bottom band = **TEN buttons**:
**[SELECT door] [8 per-track provenance doors] [PARTS door]**
- **The corners = the GENERAL doors**: bottom-left → the SELECT
  grid in its unassigned/browsing state · bottom-right → the
  PART grid likewise. The rooms reachable regardless of what's
  assigned — "these need to live somewhere."
- **The middle eight = the SPECIFIC doors** (as §4): each
  assigned track's way home — select-cell, part-machine, or
  REEL PASS per its provenance mark, selection travelling.
  Unassigned tracks' doors render empty/dim.
- **The symmetry, noted**: the third room's general door already
  exists — **RECORD's corner IS the reel's entrance.** Record
  RE-CORNERS to clear the bottom band (lean: TOP-LEFT; Paul's
  glass picks the corner — "always in a corner" stands).

## §3b — NO CHAIN PANELS ON THE STAGE (Paul, 2026-08-28)
The MIDI-chain control panels (left/right) belong to the SELECT
and PART grids only. **The PLAY grid renders none** — full-width
tracks, the header, the bottom band, the footer stack. Chain
surgery is workroom business (reach it via the provenance doors
or UNPACK); the summoned chain overlay is workroom furniture and
never appears on the stage.

## §3c — THE SLOT'S HOLD (from Paul's r3c5 walkthrough,
## 2026-08-28 — captured, awaiting his word)
With the slot-column model: **tap a slot = it becomes the
track's playing take** (radio-per-column, boundary-deferred).
**HOLD a slot = its verb menu: FLIP LIVE | UNPACK** (the two
decompose verbs, given a local handle; delete stays armed-only).
The edit path becomes: tap c5 · hold → UNPACK · edit in the
workshop · long-press header 3 to re-assign. Without this hold,
every edit detours through the reel — the ruling exists to kill
that trek. Grammar note: the HEADER's hold = assign; the SLOT's
hold = the verbs — different objects, no collision.

## §4c — THE DOORS FOLLOW THE LIT SLOTS (Paul's confirm,
## 2026-08-28)
Yes: each track's provenance door reflects **the LIT SLOT** —
hue, mark, and destination follow the playing take (switch takes,
the door re-faces). The bottom band = a live provenance readout
of the stage: eight marks saying what kind of thing each track
is currently playing. Empty tracks' doors stay dim.
Two opens this exposes (leans, Paul's word):
- **Slots may MIX provenance within a track** (c2 a flatten, c5
  a reel pass — legal; the door tracks the lit one).
- **A fresh assign lands in the NEXT EMPTY slot** (lean; full
  column = replace the lit slot, with the flash tell).

## §8 — THE ROOM PALETTES (Paul, 2026-08-28 — leans for his
## glass; colour is device territory)
**The law first**: MACHINE HUES ARE SACRED and room-independent
(identity = the thread). Rooms differentiate by AMBIENT (field ·
chrome · empty cells), never by re-tinting content.
- **SELECT = THE BAZAAR**: crazy multicolour, made MEANINGFUL —
  each cell wears its own chain's colours (the corpus's
  diversity visible; RE-DEAL reshuffles the palette). Dense,
  riotous, alive.
- **PART = THE WORKSHOP LADDER**: the shipped row-gradient
  stands — staggered, distinctive, warm, ordered.
- **PLAY = THE DARK STAGE**: near-black field, minimal chrome;
  tracks GLOW in their identity hues — dark house, lit
  performers. Maximally distinct from both workrooms.
- Grace note: DOOR-BUTTONS tinted by their DESTINATION's ambient
  — the map colours itself.

## §8b — §8's SACRED-HUES LAW SUPERSEDED (Paul, 2026-08-28)
**Colours are NOT sacred.** Users should never be hung up on
what colour a machine is. Colour's PRIMARY job is WAYFINDING:
1. **The three grids are IMMEDIATELY DISTINCTIVE** — room-first
   colour (the three ambients of §8 survive as servants of this:
   bazaar · ladder · dark stage).
2. **DOOR-BUTTONS wear their DESTINATION'S scheme** — top and
   side buttons visibly point elsewhere by colour; the §8 grace
   note promoted to the rule.
3. Machine hues DEMOTE to local, per-room roles — they may
   colour content within a room's scheme but carry no cross-room
   identity burden a user must track.
Engine note: per-note COLOUR ATTRIBUTION (revert/decompose
machinery) is internal and unaffected — attribution is
plumbing, not paint.

## §9 — MOVING TRACKS FROM THE SHOP (Paul, 2026-08-29 —
## captured with leans, awaiting his word)
- **FOCUS-FOLLOWS-TOUCH**: tapping a header (play/stop as law)
  also makes that track CURRENT (a subtle focus frame).
- **THE ▲▼ PAIR** (seated by the header row): each press SWAPS
  the focused track with its neighbour — swap, never shift (no
  cascades; each press its own undo). Track 3 → row 6 = tap 3,
  ▼▼▼, done — without leaving the select grid.
- **GHOST PREVIEWS ON FRESH ARRIVAL** (Paul's shortcut, gated):
  landing on a column that was EMPTY fills its open slots with
  SEEDED MUTATION GHOSTS of the moved content — dim/dashed,
  clearly previews. TAP A GHOST = it commits as a real take;
  otherwise they EVAPORATE on the next action. Swaps between
  occupied tracks spawn nothing (ghosts greet fresh ground
  only — invitation without clutter). Deterministic (seeded).
