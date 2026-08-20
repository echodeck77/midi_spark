# MidiSpark — PENDING TASKS (forward checklist)

_The canonical "what's left" list. CLAUDE.md's "Current status" is the backward log (what LANDED, with commit
refs); THIS file is forward-looking (what's open). Keep them from overlapping: when a task lands, tick it here
AND add its commit line to CLAUDE.md status. Terse by design — detail lives in the spec (`midispark-spec-v3.0-
delta.md`, esp. §10) and the `Docs/design-*.md` ferries. Last synced: 2026-08-18._

## ★ FERRY 2026-08-20 — REDESIGN FIXES + reel fixes + banking (much LANDED unattended 2026-08-20)
- **REDESIGN FIXES** (`Docs/AcceptanceCriteria/AcceptanceCriteria-redesign-fixes.md`): §3 QUIET LEFT BOX DONE (`871d94d`
  — neutral chrome frame, hue accent only when the chain audition sounds, thin hue spine on the left edge). §1 CHAIN
  PANEL DONE (`6a43129` — ghost-dashed empties + a flow line drawing ORDER with turn marks; the flow-line GEOMETRY is a
  first pass, device eye owed to tune). **§2 THE RACK TWO VERBS — ANSWERED, folded into THE CONFIG SHEETS**: the design
  confirmed RACK 1–4 = 4 rack CONFIGS (the SETUPS radio lives on the RACK SHEET). It's now part of the config-sheets
  reframe (below), Paul-walked — not a standalone fix. Membership stays a MARK on the strip; the radio + matrix live on
  the sheet. Needs the 4-config engine model (saved configs + per-config membership + a live selector) first.
- **PASS BROWSER v1 fixes** (`…-pass-browser-v1-fixes.md`): §1 DONE (`34b91cd` — SAVE PASS n · collapse empty lanes ·
  neutral selection wash). DEFERRED: "tap the roll to select the pass under the finger" needs the roll to become a
  MULTI-PASS session timeline (the shipped v1 roll is single-pass) — a larger change; §4 dim-future-slots optional.
- **PAUL'S FOUR + THE CARRIAGE + TIMELINE PAIR** (same doc §2–§4, roadmap, Paul walks): BANK-AND-FOLLOW (overwrite-row
  switches the edit target — the ladder as a typewriter carriage `[◀][chips][BANK ▶]`, forward deals / backward visits);
  SUB-PASS + TRACK-FILTERED saves (drag a roll region / toggle lane labels); PASS RANGES (drag pass chips → SAVE PASSES
  3–6); DEEP HISTORY (the 32-ring stands + an opt-in SESSION TAPE file); REVERT-TO-HERE (per-pass state snapshots, restore
  as one forward event — "revert the revert"); PASS LABELS (per-pass changelog badges). = the reel as **TAPE·SNAPSHOTS·LOG**.
- **THE BANKING WORKFLOW** (`…-banking-workflow.md`): STAMP TELL DONE (`4f4b34a`); THE CARRIAGE `[◀][chips][BANK ▶]` DONE
  (`5ae1037` — BANK ▶ deals to the next row + follows, ◀ visits the previous fossil, both disable at the ends);
  occupied=filled / empty=hollow editor chip states DONE (`0c94064`). STILL OPEN (device eye): the EDITING-vs-tap-to-
  overwrite live-mark refinement + HOLD-chip = preview that row's machine.

## ★ HOUSEKEEPING FLAGS — surveyed + verified 2026-08-19, DEFERRED (need a focused tested pass, not unattended)
- **Render-path allocations (invariant 3):** (1) ~~`srcNotes` local array in the 4 driver emitters~~ DONE (2026-08-19,
  `ac7eb2b`) — a reused `srcNoteBuf`/`srcNoteCount` + `srcNoteBuf[0..<srcNoteCount]` slice view; byte-identical.
  (2) ~~`euclidPattern`/`burstFractions`/`tuttiSliceRanks` array returns in the hot loop~~ DONE (2026-08-20, `a87e492`)
  — `*Into(&buf,…)` no-alloc variants in Derivations (array versions wrap them for the tests); Router reused buffers,
  separate tutti A/B for the `[TUTTI→TUTTI]` nest; byte-identical. (3) STILL OPEN: `process()`
  uniform-vs-multi-clock block is ~duplicated (transition + tick loops) — an `emitColumnTransition` extraction would
  dedup; same item as codebase-review §12 "split Router.process".
- **UI dead-code (grep-clean, FLAGGED not removed — the EDIT/verb surface may be intentional WIP like BuildPage):**
  `AudioUnitViewController` `toggleHold`/`onVerbEngaged`/`clearSelectionUndo`/`selectionMixed`/`sceneName`; `EditPage`
  `setEditMode`/`commitSession`/`revertSession`/`editGridLongPress`/`editGridLongEnd`/`midiSectionHeader`/
  `chainSectionHeader`; latent AU API (`setPreviewOverlay`/`clearPreviewOverlay`, `addMacroEmitterTargets`/
  `removeMacroEmitterTargets`, `setCellChain`, `listLibraryCells`, `factoryLibraryCells`, `loadFactoryScene`,
  `uiEffColumn`). Confirm each surface isn't held-for-rebuild before a sweep. (`Router.hasDuplicateVoices` +
  `MacroParam` decode zombies are RESERVED — keep.)
- **DONE this pass (`main`):** fixed the composeScene bug (a default-rate deployed part silently lost its short LENGTH,
  + staging-row clock could be clobbered by the piece) with a `clockClaimed` tracker + 4 composeScene tests; removed 2
  render-path allocations (`emitColumnHolds` per-call array, `applyStage` harmonize interval array); +1 rowLen-clamp
  test; removed the accidental `continuousRange` orphan.

## ★ FERRY-CAPTURED, NOT A BUILD ORDER (2026-08-19 — Paul steers; his device steps outrank the docs)
- **THE CONFIG SHEETS** (`Docs/AcceptanceCriteria/AcceptanceCriteria-config-sheets.md`, 2026-08-20 — big reframe, Paul
  walks). The legacy MIDI IN/OUT tabs RETIRE; config lives at the thing via three SHEETS opened by HOLDING a console
  subject (TAP = act · HOLD = sheet): DOOR SHEET (tap an in-strip name), WIRE SHEET (out-strip), RACK SHEET (rack chip).
  The DOOR gains a MODE RADIO **LATCH · HOLD · REPLAY · KEYS · FILE**: LATCH (toggle-in pool) · HOLD (chord-detect) ·
  REPLAY (the DOOR LOOP as a mode — input ring, PASSES 1·2·4·8 loop as living input) · KEYS (on-screen) · FILE (a loaded
  .mid loops as living input; "a FILE IS A CABLE" — CH/BLOCK/OCT/vel all apply; beat-locked f(file,beat), replay-safe).
  Console strips wear a dynamic MODE BADGE (label + tap-act: LATCH clear · RPLY·n re-catch · FILE play/pause). The RACK
  SHEET carries the SETUPS radio (RACK 1–4) + membership matrix + treatment stack — resolves the §2 two-verbs. Reconcile
  REPLAY/FILE with the door-loop ferry (siblings: remembered vs loaded input).
  **ENGINE MODEL — staged:** STAGE 1 the 4 RACK CONFIGS **DONE** (2026-08-20, `0933cf2` — rackConfigs/rackActiveConfig +
  resolvers, builder reads the active config, AU edits it, byte-identical, +3 tests). STAGE 2 the DOOR MODE enum **DONE**
  (2026-08-20 — `DoorMode {latch·hold·keys·replay·file}` + `Receiver.doorMode` + `doorModeResolved`; the latch resolvers
  honour it when set, else fall through to the legacy latchAdd/latchPiano EXACTLY → byte-identical; AU `setDoorMode`/
  `uiDoorMode` sync the legacy fields; REPLAY/FILE resolve to a HOLD-like fallback until stages 3/4; +3 tests, 803 green).
  **DOOR RANGE (Paul 2026-08-20): the door sheet must ALSO expose the note RANGE — the model ALREADY has `rangeLo`/
  `rangeHi` (+`rangeLoResolved`/`rangeHiResolved`), so it's a UI-surface item, not new engine.** STILL OPEN (each needs a
  device checkpoint — the latch/kernel is delicate + verified): STAGE 3
  REPLAY = the door input ring recording (a NEW engine feature, the door-loop v1); STAGE 4 FILE = .mid playback as living
  input ("a file is a cable"); STAGE 5 the UI — the three SHEETS + console mode badges (tap=act / hold=sheet). Stages 3/4
  are large new engine features; do them with the user + device.
- **THE MELODY/CHORD SUITE** (`Docs/AcceptanceCriteria/AcceptanceCriteria-melody-suite-UNRATIFIED.md`, UNRATIFIED —
  CAPTURE ONLY, do NOT build). RIFF (capture+remap) · TRIGGER (chords play the melody's rhythm; STAB|CLOCK) · HARMONIZE
  SOLI mode (dynamic block harmony from a door's pool) · PEDAL (hold the bar/cell's first note; FOLD-to-home register) ·
  a shortlist (gap-intelligence, contour extraction, canon rail, self-accumulation). Interface rule: receiver door chips
  (THIS·R1–R4) live IN the processor panel. Held UNRATIFIED at Paul's word.
- **THE DOOR LOOP family** (`Docs/design-door-loop-2026-08-19.md`, ratified-for-the-channel). A latch that remembers
  RHYTHM: record a door's RAW INPUT for N bars, cycle it back as the living input (determinism free — looped input
  events ARE input events). Riders: RETRO-CAPTURE by default (the CATCH ring, double-tap keeps the last N bars);
  OVERDUB = the latch's ADD/CHORD modes extended in time; PLAYBACK IS RE-ASKING (RATE/TRANSPOSE/QUANTIZE-on-playback
  transform the loop — a legal moving frame for RIFF FOLLOWING). THE PROGRESSION REEL: record the whole song's harmony
  once, scenes address SECTIONS of it. LINEAGE: this is the PURE-SOURCE recorder birthstone; the shipped ReelDeck is its
  output-side twin — rhyme the machinery (ring/bars/freeze). Paul will walk the implementation directly.
- **BURST · PATTERN + CARRY** (`Docs/AcceptanceCriteria/AcceptanceCriteria-burst-pattern-carry.md`, captured-not-ratified).
  BURST gains the family MODE radio ONCE|COIN|PATTERN; PATTERN = the 8-slice pick-then-paint row with a new **CARRY**
  state (the roll STRETCHES across the burst step + its contiguous carries — span-stretch of strikes+curve, not a
  gate-ring). SPAN CELL|ROW reuses the shipped EUCLID precedent (NB: BURST's SPAN field already landed in the SPAN
  rollout — this adds the PATTERN mode + CARRY on top). Follows LENGTH's trailing-note laws.

## ★★ PER-PART CLOCK — Stages A/B/C/D LANDED (2026-08-19; commits in CLAUDE.md status). OPEN follow-ups:
- ~~**Stage D — length < 8 UI.**~~ DONE — the corner control now carries a LOOP LENGTH section (1…8) editing the part's
  `buildPartLen`; staging + play grids dim columns past the loop (per-row by each row's part length); playheads already
  wrap at length. `testPerRowLengthLoopsShorterThanTheBar` proves a short row loops shorter. (Paul's "promote only
  LOOPED columns → parts shorter than 8" — the render + UI now support any length; the promote-picks-looped-columns
  behaviour itself is a separate future step.)
- ~~**echo / mod / glide per-row clock (v1 limitation).**~~ DONE (2026-08-19) — each fires on its ROW's own clock in the
  multi-clock path; MOD/GLIDE leave-disposition is now per-slot (per-row + a global slot), uniform path byte-identical.
  Remaining sub-limit: MOD SPAN=ROW's period still uses the scene bar, not the row's (minor).
- **DEVICE ear/eye owed:** two parts at different rates in one play grid (hear the drift, incl. echo/mod/glide now
  retimed per part); the per-row playheads drift out of phase; the RATE/LENGTH corner control; the reel colour roll.

## ★ THE REEL-TO-REEL — STEP 1 LANDED (Paul 2026-08-18)
The 1-pass output-tape (RECORD → REPLACE live output, LOOP; second touch resumes). Built at the Kernel seam: `ReelDeck`
+ `ReelTap` (Foundation-only, in Emission.swift, unit-tested); the tap records every emitted event with its pass-relative
beat; on ARM the just-finished pass becomes the loop and REPLACES live from the next pass boundary; a second touch
resumes live. Flushes on the transitions (allNotesOff entering replay · CC120/123 leaving) → no stuck notes. Reel-to-reel
glyph bottom-left of the BUILD page (amber armed · green replaying). Rulings applied: REPLACE the output · loop 1 pass ·
second touch resumes. macOS 762 green (4 ReelDeck tests), iOS builds. **DEVICE EAR OWED** (render path — unheard here).
- [x] **STEP 2 — EXPORT LANDED (Paul 2026-08-18)**: LONG-PRESS the reel glyph → the recorded pass exported as SMF files
  (`MidiFile.swift`, pure + unit-tested): `MidiSpark-All.mid` = the A–D SUM (each emitter on its stamp channel, cable-0
  All duplicates dropped) + a per-emitter stem (`-A/-B/-C/-D`) for each cable that has events. Files written to the temp
  dir + presented in a share sheet (`ReelShareSheet`). The deck now keeps the last COMPLETED pass every boundary (not
  only on arm), so export works after any pass. macOS 766 green (+4 MidiFileTests). **DEVICE test owed** (the share
  sheet from an AUv3 extension is the risk).
  - Delivery = SHARE SHEET, chosen (Paul 2026-08-18, "simple version for now"). The robust App Group + Files-sharing
    route (extension → shared container → container app copies to its Files-visible Documents via
    UIFileSharingEnabled / LSSupportsOpeningDocumentsInPlace) is DEFERRED — revisit if the share sheet won't present in
    a host, or once the standalone app lands.
- [x] **STEP 3 — THE PASS BROWSER pop-up LANDED (Paul 2026-08-19)**: the reel glyph now TAPS OPEN an 8×8 pop-up. TOP 4
  rows = the last 32 passes (`ReelDeck` gained a 32-slot history RING: flat `hist` buffer, `passNumbers()` oldest→newest
  so the newest lands bottom-right, `selectPass`/`selectedPassNo` pin, `selectedRoll()` note-pairing); each populated cell
  shows its 1-based pass number, tap = SELECT + REPLAY NOW (replace live output), tapping the replaying one stops → live.
  BOTTOM 4 rows = the selected pass drawn as A/B/C/D piano-roll lanes (Canvas, pitch shared-scaled, x by pass length,
  opacity by velocity). SAVE = export the selected pass via the share sheet (STEP 2 path). Engine: `reelSelectRequest`/
  `reelStopRequest` consumed on the render thread (select → replaying + allNotesOff; stop → off + blanket-off + clear pin);
  ring fills continuously while live (recording was already always-on), promote pins-aware. macOS 771 green (+5 ReelDeck
  ring tests), iOS builds. **DEVICE EAR/EYE OWED.** Answers of record (Paul 2026-08-19): tap opens pop-up (retires
  tap-replay/long-press-export) · pass tap = select+play now · Save = selected pass → share.
  - v1 notes: bottom-right = the most-recent COMPLETED pass (the in-progress pass isn't replayable); ring per-pass cap
    8192 events (dense-pass overflow drops, as the record cap already does); selecting a pass while STOPPED pins it for
    SAVE but only sounds once the transport runs.
  - **FREEZE-WHILE-BROWSING (Paul 2026-08-19)**: the history tape stops writing whenever the browser is open OR a pass is
    replaying (`reelBrowsing` set by the pop-up's onAppear/onDisappear · `reelFrozen = reelBrowsing || replaying`), so the
    pass list is a stable snapshot; recording resumes on the NEXT FULL pass on exit (only a pass recorded start→finish,
    uninterrupted, is filed — `reelRecordFromStart`). Kernel-only (not unit-tested; device-verified path).
  - **ROLL PLAYHEAD (Paul 2026-08-19)**: while a pass replays, a white playhead sweeps the piano-roll lanes (TimelineView,
    beat-extrapolated one-clock) and each note LIGHTS (full hue + glow + thicker) as the head crosses it.
  - **ROLL GRID (Paul 2026-08-19)**: each lane now draws 8 CELL dividers + OCTAVE dividers (pitch framed to whole
    octaves) with the C labelled on BOTH the left + right axis, under the notes.
  - **FULL-SCREEN + RECORDING GLYPH (Paul 2026-08-19)**: the pop-up now fills the screen (opaque backdrop, 8 equal rows
    fill the height). The reel glyph reads as RECORDING — red tape + a pulsing red dot while the tape captures live
    (`d.playing && !replaying`); green while a pass replays; dim stopped.
  - **ROLL DIVIDERS v2 (Paul 2026-08-19)**: kept octave + cell dividers; REMOVED the C-axis text labels; added a divider
    line between the four output lanes.
- v1 caveats to revisit: the pass boundary is detected at the render-block START (a few ms of slop); a brief gap on STOP
  (CC123 → the grid re-emits at the next column); the glyph is BUILD-page-only (could go global); doesn't yet snapshot
  tempo/scene changes mid-record.

## ★★ RANDOMIZE = AN ENSEMBLE (grid-roll rework) — v1 LANDED (2026-08-19; commit in CLAUDE.md status)
**BUILT:** `Dice.rollEnsemble` → 8 archetypes (pad · bass · stab · arp · groove · texture · sparkle · wild), each
register-separated via `Colour.transpose` (threaded through the ephemeral-colour path) + inherent density; grid RANDOMIZE
sorts by complexity + lays them onto the 8 rows; rung-per-column is now `buildAssignArcRungs` (a sparse→peak→breath→land
ARC, not random); the flood CAP is judged at a 6-note chord (`Dice.peakAt6`), character at 3. macOS 773 green (+2). DEVICE
EAR OWED. Follow-ups still open from the contract below: true events/beat density BANDS (v1 uses inherent archetype
density + the complexity sort, not an explicit per-row budget); richer call-and-response (v1 = arc + jitter); SCALE-LOCK
(its own KEY-door session). The full ratified contract, kept for the follow-ups:
Ferry `REPLY-density-audit-answered` (design-side, absorbed 2026-08-19) answered my note-density audit and set the
PRIORITY: **THE ROLL FIRST — ahead of the note-sweep plumbing AND the display/label reconcile queue.** Rationale: the
roll is the front door's first impression; every STAGE press sells or kills the instrument, and chrome can't rescue
un-musical music. Order of work: **roll rework → display layer + reconcile (small, queued) → the feed + sweep.** My lean
was endorsed AS WRITTEN: reuse `buildByRole` + archetype/register assignment + a sparse-biased density target; **NO new
engine.** The contract:
- **AN ENSEMBLE, not 8 rolls.** The player brings the chord; the roll hands back A BAND — contrasting archetypes across
  the 8: pad · bass pulse · chord stab · arp lead · texture · sparkle · groove · wild-card. "Musical" = CONTRAST; the
  current "wall of activity" IS the failure mode.
- **Density = a SPARSE-BIASED pyramid.** Most rows sparse→medium, ONE dense, the FLOOR row GENUINELY sparse (a two-note
  pulse must be possible). Assign each row a DENSITY BUDGET BAND (events/beat) + a REGISTER HOME (oct offset / split
  range) BEFORE rolling → simple→complex true BY CONSTRUCTION; the complexity sort then sorts something real.
- **Role model + rate coherence.** Adopt `buildByRole` for the grid roll (slow root under faster figures), replacing
  `rollSimple`'s random-rate stacks.
- **Rung-per-column = AN ARC, not random.** Sparse open → build through the middle → one breath/drop column → land;
  call-and-response between adjacent registers as seasoning. Pure-chaos stays reachable as a dice DEPTH, never the
  default (SURPRISE-FIRST governs flavour, not structure).
- **Onset BUDGET** (events/beat) alongside the concurrency cap = the budget bands above. Probe fix: judge the flood CAP
  at a 6-note worst-case chord, judge CHARACTER at 3 — cheap, closes the under-prediction.
- SCALE-LOCK (the KEY door) = a real PROCESSOR, its OWN design session — NOT a randomize tweak. Parked.
- Sweep-feed connection (for later): the `ReelTap` already records per-note EMITTED events at the Kernel seam — the live
  per-cell feed the note-sweep renderer needs is that tap's COUSIN, not a from-scratch job. Start there when sweep's turn comes.

## ★ SOON — PatternSpan (SPAN: CELL | ROW) rollout to the pattern processors (Paul 2026-08-18)
EUCLID SPAN landed (`e7e0043`, on `main`; commit line in CLAUDE.md status). `PatternSpan { cell, row }` + `euclidSpan`
are in place. ROW stretches a processor's N-step timeline across the whole 8-column BAR (a cross-column phrase) —
this is the arp/weave PHASE=FREE axis generalised, NOT note-sustain legato. The `iterateTicks` column gate already
scopes each cell to its own column, so per processor the work is small + uniform: engine = ONE line (the tick-grid
denominator `S` → `cycleBeats`), model = an additive-Optional field (nil ⇒ CELL, old docs safe), UI = a SPAN CELL|ROW
seg on the face, + a row-fills-a-row test (`testEuclidSpanRowSpreadsPulsesAcrossTheBar` is the template). Roll onto
(every processor rated ★★ or higher, in priority order):
- [x] **LENGTH** ★★★ — DONE (2026-08-19, `c01a9fb`): the 8-slice gate spans the bar (standalone + composed paths).
- [x] **MOD** ★★★ — DONE (2026-08-19, `c01a9fb`): ROW = one LFO/STEPS cycle per bar; CELL = the modRate period (default,
  unchanged). The CC-stage `SPAN CELL|PHRASE|FREE` sketch resolved as CELL(=rate)|ROW(=bar); no FREE variant added.
- [x] **TUTTI (PATTERN)** ★★ — DONE (2026-08-19): ROW = the 8 slices span the bar (else the RATE stride).
- [x] **RATCHET (PATTERN)** ★★ — DONE (2026-08-19): ROW = the per-slice counts span the bar (else the RATE stride).
- [x] **BURST** ★★ — DONE (2026-08-19): ROW = the accel/decel roll unfolds across the whole bar.
- [x] **CASCADE** ★★ — DONE (2026-08-19): ROW = the reveal spreads evenly across the bar.
All six: additive-Optional model fields (old docs = CELL), snapshot + builder + `SPAN CELL|ROW` face seg, a row-vs-cell
RouterTest each, + the fuzz flips ROW on ~half of span-capable procs (no-stuck-notes across every edge).
(CHANCE was ★ — deferred. ARP/WEAVE already have PHASE; DRONE/ECHO/GLIDE already flow across boundaries.)
**DEVICE ear owed on EUCLID + LENGTH/MOD/TUTTI/RATCHET/BURST/CASCADE ROW.**

## ★ DONE (2026-08-05/06) — MACROS (phase 2 track)
Specs: `AcceptanceCriteria-macro-panel.md` · `-macro-ab-authoring.md` · `-overlay-rule-macro-lanes.md`. `feat/macros`
MERGED to `main` 2026-08-05; the canonical MACRO AUTHORING FLOW landed 2026-08-06. Commit refs in CLAUDE.md status.
- [x] M0 state model · M1 offset term (base ⊕ Σ value×delta, folded at build; seals stable) + tests · M2 the 8
  slider macros as automatable AU params · M3 the MACROS tab panel (BTN|SLD|TML; sliders drive values + padlock) ·
  **M4 A/B authoring** (the [AB] popup on the Edit page's CHAIN header → live B demonstration → bind delta to a
  SLIDER macro; base restored to A on close). **MACROS ARE USABLE END-TO-END.**
- [x] BUTTON bank completed end-to-end (values via a direct document setter for 8–23; [AB] popup SLD|BTN selector).
- [x] OUTPUT group done end-to-end: the offset extended to the per-emitter role amounts (LEAK/DUCK/CURVE/POCKET,
  MacroEmitterTarget, folded in the builder) + the [AB] popup's CHAIN|OUTPUT selector + OUTPUT authoring.

## Open within macros (forward)
- [ ] INPUT group — the source shaping. **Underspecified**: the panel spec lists INPUT as a group but doesn't name
  its continuous targets. Candidates: the velocity window (floor/ceil) · the note range (lo/hi). Needs a pick before
  building (SnapCell-field fold + an INPUT group in the popup).
- [ ] TIMELINE bank (lane editor + per-column STEP|SMOOTH|BYPASS + the render-time per-column path, which replaces
  M1's bake-at-build for lanes) · BUTTON/TIMELINE binding + mover-eligibility live-dim · the A↔B morph-audition
  slider · the CC rail · the perform-surface panel in the GRID top band (part of the phase-2 GRID redesign) ·
  announce/ghost-thumb tells.

## ★ DONE (2026-08-05) — LAYOUT v2 tab shell (phase 1)
Spec of record: **`Docs/AcceptanceCriteria/layout-v2-tabs.md`**; plan `~/.claude/plans/resilient-imagining-truffle.md`.
On `main`, iOS builds, 428 green; commit refs in CLAUDE.md status; **device pass owed**.
- [x] Part 0 — retire SELECT · Parts 1-2 — six-tab bar + body switch (`AppTab`) · Part 3 — clock→header ·
  Part 4 — RECEIVERS tab (`ReceiverConfigView`) · Part 5 — EMITTERS tab (rack out of the grid).
- [ ] **Phase 2+ (deferred, captured):** GRID top-band 8 macro sliders+buttons · SINGLE|MULTI toggle · HOLD
  localisation per slider group · the MACROS + AUTOMATION engines/pages · global FREEZE/STUTTER gestures ·
  MIDI-OUT channels moved into the emitters tab. (These are engine/authoring work — needs Paul to prioritise.)

## ★ DONE (user, 2026-07-29) — /btw authoring UX + AcceptanceCriteria wave
Spec of record: **`Docs/AcceptanceCriteria/verbs-behaviour.md`**. All LANDED off-device (device pass owed) —
commit refs in CLAUDE.md "Current status":
- [x] **/btw ⑥** one-per-column per-hold · **④** retro-repaint · **⑤** per-cell + row selectors (already built) ·
  **STROKES** · **MIXED-SET law** · palette-live-during-holds (via ④).
- [x] **AcceptanceCriteria additions**: SELECT empty-tap no-op · **DELETE = SEVER** (children cut to MIDI-IN) ·
  **DESK RE-POINT** hard rule · **multi-cell routing (per-column)** + **SRC/DEST pulsing candidate look** ·
  placed/selected cells always WHITE · PLACE nearest-above nudge · **sticky routing** · **verbs do NOT latch**.
- [x] Refactor + tests: routing logic → pure `Derivations` helpers (`routeFociByColumn`, `placedCellRouting`) +
  `deleteCell` dedup (`181bf7c`).

## A. Blocked on the user (need a decision before building)
- [~] **Accent-colour dedup (refactor B1)** — MIGRATION IN PROGRESS. A `DesignKit.swift` token layer LANDED
  2026-08-16 (`enum UI`: cyan/amber/red/green/editHue/ink, values unchanged, migrated across ~10 files). BUT it's
  PARTIAL: the cyan literal still appears ~18×, amber ~16×, `editHue` is defined twice, and `FlowView.swift` still
  hardcodes a divergent receiver-hue array. **REMAINING OPEN DECISIONS:** `FlowView.swift`'s cyan is
  `Color(red:0.145,g:0.878,b:0.941)` — a real ~0.005 near-miss of the canonical `0.15/0.88/0.94`, still unruled
  (unify to canonical, or keep FlowView's tuned-for-dark-canvas value); and the same call on FlowView's divergent
  lighter receiver-hue array vs `receiverHues`.
- [ ] **midiNoteName convention** — the shared `midiNoteName` is 0-based (note 60 = "C5"); `RackMatrix.noteName` is
  `n/12−1` (note 60 = "C4"), so FENCE labels read an octave below the receiver RANGE labels. `midiNoteName`'s doc
  says it exists "so naming can't drift". Pick the canonical convention (C4=60 is the common MIDI one) → unify (a
  visible label shift, hence a ruling).
- [ ] **HOLD latch re-home** — §5c latch UI slot is vacant; CONTROLS-corner restoration recommended, awaiting the nod.
- [ ] **SCOPE ops home** — chips-during-SELECT-hold vs deferred (design device-nod).
- [x] **DELETE-sever fallback in the null era** (user ruled NULL, 2026-07-30) — severed children now fall to NULL
  input (inputRow nil AND inputReceiver nil, own emitters kept) instead of a phantom R1 re-point. Done in
  `deleteCellSever`; test updated. Reply to design-side owed (bundle with the file-read ack).

## B. ✅ DEVICE-VERIFIED (user device pass, 2026-07-30 — "happy with things as they stand")
The whole accumulated GUI + engine stack was run on device and ACCEPTED. Cleared from the owed list:
- [x] **Adoption ear-check** · **Strips** (session faces · LATCH · DUCK · SPACE-FILL · receiver marks · emitter buttons · verbs-as-pills) · **COPY·PASTE** · **preset enlarge + UNDO/REDO** · **white selected ring**.
- [x] **AcceptanceCriteria wave (2026-07-29)** — /btw ④⑥ · STROKES · MIXED-SET · DELETE-sever · multi-cell routing · candidate body-pulse · desk re-point.
- [x] **Routing view + visualisation (2026-07-30)** — IN/OUT labels · candidate-hides-content · the routing overlay (curved flows + comets · cell→cell arrow · band dots · clip-over-uncrossed · lane separation · lit-through-selected).
- [x] **Cells & colour desk overhaul (2026-07-30)** — cell face (emblem · digest · dots · compass tint · trigger glyph · white selection) · desk title-as-picker + popover · Colour NAMES · SPARSE palette · census protection. _(Placeholder SF-Symbol emblems still stand in for real artwork — the drawing job is a separate asset task, not a bug.)_
- [x] **Fresh-cell + naming + furniture (2026-07-30)** — fully-null new cells · full processor names · grid down-chevrons (watermark + column keys) · dual-side row rails · DELETE-sever→NULL.

## C. Buildable now (next increments)
- [ ] **MOSAIC §2 — THE CREST** (design ferry 2026-08-06, spec `AcceptanceCriteria-mosaic-face.md` §2; mosaic
  device-approved "looks amazing"). The largest rect gains 1–2 HASH-CHOSEN inscribed shapes (▲▽◆●, tone-on-tone,
  twins share) that light on the FIRST INSTANCE of the HIGHEST note per COLUMN ENTRY (peak brightness + timed fade)
  — two layers: rank breathes below, crown flashes above. Pure `mosaicCrest(hash:)` (testable) + a drawMosaic layer
  + a per-cell PEAK-NOTE feed (small engine plumbing, like the mosaic phase-2 per-note feed; v1 approximation
  available). PLAN drafted (see the spec §2 CODE NOTE + the chat).
- [ ] **THE WINDOW — the pre|post note graphic** (design ferry 2026-08-06, spec `AcceptanceCriteria-the-window-
  graphic.md`). ONE parameterized piano-roll component (NOW divider · held input bars left · derived-future rects
  scrolling in + firing at the line; brightness=velocity). LIVE (derive-ahead ~2 beats, pure) + CANNED modes; sizes
  S/M/L; sites = processor boxes · macro page MAIN/ALT · library · manual · receivers. §2 THE EYE = a header-bar
  inspect toggle → cell-tap opens the window popup. Needs a pure `scheduleAhead(...)` derive-ahead + the `NoteWindow`
  view. Larger feature; §3 LONG WINDOW / RACK VARIANT flagged futures.
- [x] **MACRO AUTHORING FLOW (canonical)** (Paul + design 2026-08-06, spec `AcceptanceCriteria-macro-authoring.md`;
  **LANDED 2026-08-06 — `MacroBindPopup` removed**) — a GENERIC control-group authoring page (MAIN/ALT instances →
  TEST slider+button → ADD-TO-MACRO assignment view), hosted by a control-group registry so processors · receivers ·
  emitters · rack all reuse it. Sparse relative deltas (the M1 offset model — already built); host-adaptive
  transactions (staged vs live); mover eligibility (discrete→buttons only); ALT persists per group; first-assign sets
  spring/toggle then locks it. KEPT the offset engine (M1) + AU params (M2) + MACROS tab (M3). **Residue still open:**
  the receiver / emitter / rack authoring domains (only the processor domain shipped) + the discrete-param binding
  path (only the 7 foldable continuous keys reach the engine). A future MACRO MAIN TAB (management surface) is
  separate + later.
- [x] **CONTROLLER ROUTING v1** (design ruling 2026-08-06, spec `AcceptanceCriteria-controller-routing.md`;
  **LANDED 2026-08-10 — `Receiver.controllerMask` exists**) — per-door cog mask CONTROLLERS→[A·B·C·D] (default
  all-live); forward matching CC/PB/AT/PC to each selected emitter RE-STAMPED to its channel; supersedes the
  hardwired `passthroughCableMask`. **CC123/120 = pool/latch FLUSH + forward** (all-notes-off must release us).
  **UMP legacy parity where cheap** (system/SysEx pass). BEND-ownership rule reserved for the future per-emitter
  bend stage. Model seam: `Receiver.controllerMask: UInt8?` (nil ⇒ 0b1111).
- [x] **MPE toggle + auto-detect RETIRED** (design ruling 2026-08-06, on `main`) — the RECEIVERS-tab MPE toggle
  (`ReceiverConfigView.mpeRow`) + the write-only auto-detect (`mpeSeenAt`) are gone (manual-honesty law: the UI
  stopped promising what nothing reads). `Receiver.mpeMerge` stays Codable + `setReceiverMpeMerge`/`mpeLikely`
  reserved for the two-lane expression era.
- [x] **THE "STRIPS DONE" WAVE** — emitter hold-while-sounding feed built + **device-verified 2026-07-30**
  (steady cargo-tinted `SoundMark` ticks + fade-on-release; `Router.snapshotEmitterSounding`; test
  `testEmitterSoundingReportsHeldNoteOnItsBusThenClearsOnRelease`). ④ polish-laws accepted at current values on
  the device pass. _(Latent: the release-fade keys on (vel, colour) not the wire note — same-vel chords could
  mis-pair a fade; not seen on device, revisit only if it surfaces.)_
- [x] **Full strip EDIT-face sweep** — DONE (off-device): the strips' EDIT faces were dead in the live path
  (nothing passed `editing:true`) and their config already lives on the cog (`CogPage.swift`). Retired
  `OutputsView.channelStepper` + `ReceiversView.editFeatures` and the `editing` param on both, plus the orphaned
  callbacks/helpers. Strips are single-face forever. _(Separate future: `GridView.editing` — the grid's own
  cell-editor mode — is untouched.)_ Device-verify: the strips look/behave unchanged (perform face only).
- [~] **CELL EDIT** (spec `Docs/AcceptanceCriteria/AcceptanceCriteria-cell-edit.md`; user-chosen phased build).
  **⚠ BANNER (2026-08-13): the PROCESSORS / cell-edit page was RETIRED — BUILD supersedes it; `editSpikePage` is now
  unreachable dead code.** So the whole block below is HISTORICAL: the crash bug is MOOT (the page can't be reached),
  and every open sub-item here needs TRIAGE — folded-into-BUILD, wanted-elsewhere, or dropped. Detail kept for the
  record; do not treat the `[ ]`/`[~]` marks below as live forward work until triaged.
  Decisions locked: start with the station skeleton; **triggers stay Colour-side** (no per-cell schema change).
  **LAYOUT (evolving): design-side revised B to a full-page takeover (2026-07-31); the USER then overrode that —
  the page REPLACES THE GRID in its slot (via `gridBlock`, like FLOW) while receivers/emitters/strips/desk/arr-bar
  stay visible + reachable. Spec B on file still says full-takeover — ferry the user's grid-slot override to
  design-side.** Content/model/engine/tests unaffected by all this layout churn.
  **~~OPEN BUG~~ MOOT (page RETIRED 2026-08-13, unreachable): crash on tapping the TRIGGERS section (device, first
  Cell-Edit device run). No logic error on that path (collapsed rows are plain text) → suspected a SwiftUI
  transition/nesting crash; the grid-slot move may have cleared it. No longer reachable, so no retest needed.**
  - [x] **Phase 1 — station skeleton + full-page rework** (off-device): EDIT = a 6th TOGGLE (out of the `Verb`
    enum); tap re-points + suppresses the trigger fire. **Re-architected to the full-page takeover**: `cellEditPage`
    replaces the whole grid layout when a cell is pointed; pinned breadcrumb (scene · column · 8-dot minimap ·
    DONE); persistent LOOP+TEST strip (placeholders; test pad shows the glyph, H6); ONE vertical accordion
    (IDENTITY · INPUT · TRIGGERS · OUTPUT · sound-desk, B4). Retired the `primarySlot`/`deskSwapBar`/`deskShowsColour`
    in-place swap. Device-verify: takeover push/return (DONE + re-tap EDIT), breadcrumb minimap, one-open accordion.
  - [x] **Phase 2a — triggers accordion** (Colour-side, off-device): a one-open accordion editing `Colour.on`
    via `editOn`→`editBrushColour` (undoable); reused `OnConfig` wholesale — no schema change. **Curated to the
    WIRED actions only** (user, this version): TAP none/alt/mute/solo · HOLD none/alt/oct · ARRIVE none/alt-
    alternate/morph-drift/emitter-rotate; the inert placeholders (fill/replay/freeze/slice-cycle/morph-scrub/dice)
    + the LEAVE & SCENE rows are hidden (enum cases kept for a future TOUCH-box design pass). Device-verify:
    pickers offer only the wired actions, each fires in perform, edits ride to the cell-face glyph.
  - [ ] **Phase 2b — REDIRECT + retrigger style** (NET-NEW model+engine): the REDIRECT TAP/HOLD action + ALT-DEST
    A–D toggles (new `OnConfig` field + admission-time engine effect); the TAP CUT|LAYER retrigger field.
  - [~] **Utilities §I**: [x] Apply-input-to-scope (twins / all-colour, reuse `applyToScope` + live counts) +
    Reset-input (off-device). [ ] Copy/Paste CONFIG (a cell input+triggers clipboard, `ProcClip` pattern) — deferred.
  - [x] **Phase 3 — input editing** (COMPLETE, off-device): source · octave/transpose · chord-split · velocity window.
    - [x] **3a source picker** (off-device): NONE · MIDI-IN R1–R4 · FROM ROW n value-chip, editing the existing
      `inputRow`/`inputReceiver` (reuse `routeInReceiver`/`routeInRow`/`routeInSourcesAbove`). No schema change.
    - [x] **3b chord-split** (NET-NEW, off-device): ALL · TOP n · BOTTOM n · KEY RANGE. `Cell.chordSplit?`
      (migration-safe) → `SnapCell`; pure `chordSplitWindow` applied inside the `srcCount(for:)`/`srcAscending(for:)`
      readers (contiguous window, ALL fast-path); station INPUT SPLIT control (per-cell). Tests: window (all
      modes+edges) · readers apply it · Codable/migration. _(Follow-up: preview/audition STRUM use a raw filter,
      so the split doesn't reach those two paths yet.)_
    - [x] **3c velocity window** (NET-NEW, off-device): `Cell.velWindow?` (migration-safe) → `SnapCell`;
      velocity-aware base readers composed as velocity-admit THEN chord-split (full-range fast-path); station
      VEL ≥ / VEL ≤ steppers. Tests: gating + composition + Codable/migration.
    - [x] **3d input octave + transpose** (off-device, REUSE not net-new): per spec "existing steppers,
      unchanged" — surfaces the per-Colour `transpose` (−24…+24 st, already engine-wide) as a SHIFT row (octave
      ±12 + semitone ±1) via `setBrushTranspose`. Colour-side like triggers; no schema/engine change. _(If a true
      per-CELL input transpose is wanted later, that's the net-new ~5-site version — deferred.)_
  - [~] **Phase 4 — output/chop** (spec F REVISED 2026-07-31):
    - [x] **UI + model** (off-device): MAIN dest A–D (LIVE, edits cell.buses) · the 8×2 chop grid (MAIN+redirect
      dot / MUTE) · shared ALT A–D. New `Cell.chop` (Chop = 8 slots + alt set, migration-safe; Codable test).
      Grid/alt edits persist but are labelled "routing engine pending".
    - [~] **chop routing ENGINE** (SEMANTIC confirmed by user: 8 slices divide the CELL'S OWN column, a per-cell
      output gate — not pass columns):
      - [x] **TICK cells** (off-device): `chopSlice(mBeat, columnBeats:)` → each ARP tick / RATCHET repeat routes
        MAIN/ALT/MUTE by its slice within the column (`chopBusMask`); MUTE-slice = silent. Tests cover both pure
        fns. (Reverted the earlier wrong pass-column indexing.)
      - [ ] **HOLD cells** (identity/passgate/chance/harmonize) — the trance-GATE: sub-articulate the sustained
        chord into 8 slices (note-off at MUTE edges, ALT redirect), interacting with legato/harmonize/adoption.
        The bigger piece.
      - [ ] **STRUM + row-fed MIRROR** chop (thread the onset slice in).
    - Open call F (emitter-picker vs spatial ROUTE-OUT) — both surfaced now (two doors); leave as-is unless the
      user rules to collapse them.
  - [ ] **Phase 5 — LOOP**: single-column loop ≈ one-bit `laneMask` via existing `lapColumn` (very low engine
    risk); UI toggle + wiring. Resolve open call G3 (LOOP-starts-playback-when-stopped).
  - [ ] **Phase 6 — test pad**: real-path stopped-time trigger fire (self-driven clock + silence-invariant
    exemption + scope). Hardest engine piece.
- [x] **Trigger-glyph cell face** (§3) — built in the cells-and-colour-desk overhaul (emblem · trigger glyph · digest · dots · compass tint) and device-verified 2026-07-30.
- [x] **Touch completions** — palette LIVE during holds · **STROKES** · **MIXED-SET law** — ALL DONE (2026-07-29; see the DONE block above).
- [ ] **Live preset previews** · **SCROLL+TEACH** (both deferred-flagged).
- [ ] **Tag `v0.7-gui`** (user tags manually).
- [ ] **CAPTURED via ferry 2026-08-07 (specs of record, NOT built — design-side Claude, Paul's asks):**
  - [x] **GLIDE processor** (`AcceptanceCriteria-glide-processor.md`; **LANDED 2026-08-10 — `ProcessorType.glide` +
    `GlidePriority` exist**) — notes→pitchbend: first note = anchor, each next = a bend ramp (mono sliding voice);
    RANGE handshake; out-of-range RE-ANCHOR (steps glide, leaps articulate) or CLAMP; params TIME/RANGE/PRIORITY.
    Shares BEND's expression scheduler + channel-ownership plumbing.
  - [ ] **WEAVE driver** (`AcceptanceCriteria-weave-driver.md`) — a rank-clocked polyrhythm DRIVER (arp/rtc/strum
    family; last-driver rule): each pool member ticks on its own rank-derived clock. MODE = LADDER / HARMONIC★ /
    DRAWN; params BASE/GATE/SPAN. Two chips: TAPE (rate×2 → +12) · DUR-BY-INTERVAL (leap → length). Pure per-rank.
  - [ ] **EDIT-TIME DERIVATION SERVICES** (`AcceptanceCriteria-edit-time-derivation.md`) — one facility
    `deriveInput(toSlot:against:span:)` (the dice's audition machinery, exposed offline) → four services: FITTED
    DEFAULTS (a newborn stage seeds from its input) · PICKER PREVIEWS (choose a type by result) · DEGENERACY
    WARNINGS (flag near-silence/wrap before commit) · ADAPTIVE RANGES + derived slot summaries.

## D. Parked futures — log only, NO build (re-explain from `design-ferry-completions-phase-cc-2026-07-28.md`)
- [ ] FEEDBACK EDGES (unit-delay) · THE PIN · MASTER+TEXTURE multi-playhead · **THE CC RAIL** · **THE TWO-LANE INSTRUMENT** (+ cross-lane valves) · MORPH desk (16 faders) · EXTERNAL processor type + standalone-app milestone.
- [ ] **MULTI-INPUT / fan-in — THE G1 RULING** (design-Claude, 2026-07-30; captured here because the ferry note is
  transient). Shipping subset = **multi-RECEIVER-in** only (merge the four doors); keep the single row-parent so
  chains stay trees (no DAG, cycles impossible). At a union point: the pool is a **refcounted SET** (a note lives
  while ANY source holds it; entry dies at count 0; dedup by wire note-number after per-source transforms).
  **Velocity** = the latest strike UPDATES the pool entry but NEVER re-strikes a sounding hold-voice (applies to
  the next articulation). **Voice identity stays source-blind**: note + emitter + Colour-and-face, refcounted at
  the union. Full multi-row-parent remains the parked birthstone (schema-as-set already insures it).

## E. Architecture debt (opportunistic, all accepted)
- [ ] §6a CLAIM L3 residual (short-note All `on,off,on,off`) · `TODO(spec §7)` param route (writes doc then rebuilds) · `Cell.stack`/`srcMix` kept load-bearing for the v2→v3 migration.
- [ ] **HARMONIZER hung-note ROOT CAUSE** (user-reported device bug, 2026-07-31) — the §a8b playing-time net now
  auto-clears it within ~1 s (safety net, committed), but the underlying leak is NOT fixed. HARMONIZE emits
  root + up to 3 interval voices per source note with column-boundary offs (Router `emitHarmony`); a missed/late
  off leaves a stuck wire note. Suspect the close-vs-reemit ordering at a column boundary or a refcount imbalance
  amplified by harmonize's fan-out (4× voices vs identity's 1×). Repro on device, then trace `emitHarmony` →
  `emitArtic`/`openVoice` refcount across a column transition + a live interval change while a chord sustains.

## F. Codebase-review carry-over (§12, 2026-08-16)
The currently-open medium/large work captured in `Docs/codebase-review-2026-08-16.md §12` (and CLAUDE.md status) that
this file otherwise omits — one line each, see the review for detail:
- [ ] **BuildModel / ColourRegistry extraction + BUILD selection unification** — pull BUILD's model out of the view.
- [ ] **Colour-owned routing** (the "four steers ①") — lift buses/receiver/chop off `Cell` onto `Colour`.
- [ ] **Split `Router.process`** — the ~35-arg monolith.
- [ ] **Persisted-DTO / working-model split** — separate the on-disk document from the live working model.
- [ ] **Total macro model** — discrete-delta bake (bug M1: discrete-param macros don't fold yet).
- [ ] **RACK engine tests** — fence / mono / pocket / conversation / curve are untested.
- [ ] **Unassigned-BUILD-part persistence follow-ups** — the deployed play-grid isn't persisted yet, and "exactly
  one unassigned part" isn't a hard invariant.

---
_Done this thread (moved off the list): /btw ①②③ · adoption · strips session-faces/LATCH/DUCK/SPACE-FILL/receiver-marks · verbs reverted to pills · CONTROLS single-face · §10 spec fold. **2026-07-29 wave:** /btw ④⑤⑥ · STROKES · MIXED-SET · DELETE-sever · multi-cell routing + SRC/DEST look · desk re-point · sticky routing · verbs-no-latch · routing refactor+tests. See CLAUDE.md status for commit refs._
