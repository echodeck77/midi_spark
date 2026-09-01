# MidiSpark — PENDING TASKS (forward checklist)

_The canonical "what's left" list. CLAUDE.md's "Current status" is the backward log (what LANDED, with commit
refs); THIS file is forward-looking (what's open). Keep them from overlapping: when a task lands, tick it here
AND add its commit line to CLAUDE.md status. Terse by design — detail lives in the spec (`midispark-spec-v3.0-
delta.md`, esp. §10) and the `Docs/design-*.md` ferries. Last synced: 2026-09-01._

## ★ HOUSEKEEPING FLAGS — 2026-09-01 (surveyed + verified)
- **✅ DONE — BIG DEAD-CODE CASCADE (`7b9d160`, ~820 lines):** removed the orphaned `GridView` (0 instantiations) + its
  subtree + the GridView-only seal render island + GridGeometry + accentCyan/cellBg/cellEdge (GridUI −604); the `flowDiagram`
  render subtree + the DIN-icon cluster (EditPage −211); the dead `DDZonePref`/`ddZone` (DragDropPage). `GridPos` was EXTRACTED
  to a standalone top-level struct (still used by EditSelection + colour-scope helpers). Per-symbol verified — the survey's
  cascade list was imprecise (cellChain is live via the AU; DragDropPage is mostly the live shared colour cluster). iOS builds.
  (Left: `armLadderRung` (VC) + its ladder-cluster callees — a separate small cluster.)
- **✅ DONE — BUG-HUNT Finding 4 (`9047463`):** MONO voice-steal now calls `forgetGlideAnchorAtSlot` when it closes a glide
  anchor (re-centre bend + clear the GlideVoice) so a reused slot can't be wrong-closed; +1 RouterTest (glide+MONO+steal path).
- **✅ DONE — PER-ROW ENGINE TEST GAPS (2026-09-01, +4 RouterTests):** (1) fixed the FALSE-POSITIVE lap test
  (`testPerRowLapLoopsEachRowsOwnColumns` — now a 16-entry `rowLane` + a discriminating "a col-off-the-lap cell stays SILENT"
  assertion the old uniform-sweep path would have failed). (2) `testPlayLayerRowsRunOnTheirOwnClockWithoutLeak` (a cell in
  engine rows 8–15 renders on its own clock — first coverage). (3) `testOnlyRowLegatoDroneSurvivesAFastNeighbourRow` (a slow
  legato drone strikes ONCE per note, adopted, while a fast neighbour row transitions — the onlyRow scoping). (4)
  `testPerRowGlideAndModFireOnTheRowsOwnClock` (fast row's glide re-anchors more; both rows' MOD emit independently). The
  clock-mode-switch #5 was already covered by the 2026-09-01 glide/mod-switch fix's test.
- **DOCS — "needs-Paul" removals (agent-flagged, left to avoid dangling refs):** cited spent plans (PLAN-presentation-redesign,
  implementation-plan-btw-authoring, implementation-plan-cells-and-colour-desk, AcceptanceCriteria-emitter-page-pass1) + the
  dedupe pairs (scenes-v2-multigrids ⟷ AC-scenes-v2; INSTRUCTIONS-room-palettes ⟷ AC-room-palettes; OPEN-listening-set ⟷
  design-listening-set) + "surface-retired" banners on the ~15 retired-era AcceptanceCriteria/design-ferry docs + the ~12
  landed SPEC-/FERRY- headers. All keep-as-history unless Paul says delete.
- **AUTO-RUN (`618eac5`) — DEVICE EAR:** cog → DEV → "▶ AUTO-RUN" should play a musical chord loop by itself (free-run) and
  leave nothing stuck over a long soak; the os_log `autorun` heartbeat + STUCK oracle report in Console.app.

## DEVICE-OWED (2026-09-01) — Tide & Ember colour scheme + housekeeping + reveal + unification inc.1 (landed `6537159`…`121c997`)
- **EYE — the colour REVEAL (`1a1fc1f`):** committing a SELECT draft (ferry → part side-button / play column) now BLOOMS the
  destination's real machine colour (a saturated wash easing out ~0.6s, settling to the cell) — was a white flash. Verify the
  bloom reads as "it became this colour" on the mostly-dark part/play cells.
- **EYE — MachineBinding inc.1 (`121c997`):** the play button + machine hue now derive from one resolver (behaviour-preserving —
  should look identical). Confirm no regression in the machine box/play-button state as you select select-cells / ferries / parts.
- **EYE** — the **Tide & Ember** scheme + **Even Dusk** play palette on device: do the 8 play columns now read as DISTINCT
  (the whole point — the old dusk set blurred)? Cool receivers / warm emitters / sea-blue PLAY door / ember PART door /
  warm→cool SELECT strip. Plus the SELECT-grid CHEQUER, the solid-block ▲▼ ferry cursor, and the alternating-bright-grey
  machine feedback on each new SELECT pick.
- **EAR** — the CC120/123 fix: with a HOLD/LATCH armed, a source app spamming all-notes-off (chord release / between phrases)
  must NOT cut the held chord at the SYNTH now (previously survived internally but was silenced downstream). Verify a legato/
  drone HOLD keeps sounding through a source's CC123, and that a real panic (nothing armed) still passes through.
- **OPEN colour follow-ups (Paul's call, from the colour study artifact — NOT built):** ① a muted "opposite-of-a-rainbow"
  SELECT nav (Graphite/Slate/Blueprint/Paper) — a one-line `roomsRainbowHues` swap; ② the disposable-sketchpad SELECT
  material + the colour-blooms-on-commit "reveal"; ③ raise the cell hue WASH/frame opacity so the play hue reads more boldly
  (independent of palette); ④ warm-shift the 16 machine `colourHexes` (left a full spectrum — only if Paul wants it).


## ★★★ FERRY INTAKE 2026-09-01 — macro-automation (RATIFIED) + CHORDS §2 (canon) — PLAN: `Docs/PLAN-incoming-2026-09-01.md`
Two docs read + merged from `_dear_claude_code/` (inbox cleared): **`INSTRUCTIONS-macro-automation.md`** (NEW, RATIFIED — the
one automation currency; 16 macros in TWO SPECIES = 8 TOGGLE + 8 SLIDER; four collapsible tabs on the part page: BIND · PLAY ·
PUNCH · SPAN; base⊕offset, boundary-deferred, drawn=config; overrides survive mutate/randomize). **SUPERSEDES `SPEC-macro-lanes.md`**
(now tombstoned — the grid-as-canvas + ×-spans cover the band's whole job; the wave-chip = a possible uncommissioned SPAN fill).
And **`SPEC-chords-stage.md`** grew a **§2 DEGREE MATRIX (canon)** — 8 rows (I–VII + REST) · radio-per-column · empty column =
CARRY the previous chord · quality-aware self-updating headers (I·ii·iii°…) from the declared key · VOICING/WINDOW/ROTATE chips.
CHORDS itself is RATIFIED (derive diatonic progressions from a key: FOLLOW·PATTERN·WALK modes; no chord stored — rank arithmetic
on the scale pool); the STATUS note says the three MODES + voicing await Paul's ratifying word before build, §2 is canon.
- **Read the grounded plan `Docs/PLAN-incoming-2026-09-01.md` before building either.** Macro-automation is the bigger lift
  (four tabs + the toggle/slider species + per-cell/per-span application). CHORDS reuses the SCALE-door pool + the state-matrix
  + pedal machinery (kin to AVOID/§2 the degree matrix).
- **✅ §K RESOLVED (Paul 2026-09-01):** K1 — macros are **PART-PAGE-ONLY** (never the play page); the per-cell amount grid
  (option a) is scoped to the part grid, lives per-part. K2 — a toggle is a binary gate on the bound offset (value ∈ {0,1}).
  K3 — RETIRE the 8 timeline macros (bank = 16: 8 slider + 8 toggle; enum case kept decode-safe). K4 — **all three CHORDS
  modes RATIFIED** (FOLLOW·PATTERN·WALK + voicing). **LAYOUT:** the macro band = the bottom HALF of the PART grid (interior 8×8
  −50% height; ferry row · ▲▼ · STOP unchanged). **BUILD ORDER:** CHORDS C1 (pure core) → C2 PATTERN → C3 FOLLOW → C4 WALK;
  macro M1→M2 (the part-scoped amount grid) → M3–M6 (the 4 tabs).
- **✅ CHORDS — DONE / FEATURE-COMPLETE (2026-09-01, `64ed992`+`df5289c`+`2fd8d98`; 995 green, iOS builds; DEVICE ear owed).**
  C1 pure core → C2 PATTERN → C3 FOLLOW → C4 WALK → C5 lone/tail emission + voicing/downstream. All three modes + VOICING/SPREAD
  + the quality-aware degree matrix ship; wired via applyStage (upstream fold) + emitColumnHolds (lone/tail hold, no stuck
  notes). **DEVICE-FIX PASS (2026-09-01, `a038a68`; Paul "doesn't respond / one chord"):** default → FOLLOW (responsive: play →
  chord) + C2b#1 DONE (CHORDS reads the key from a receiver door in SCALE mode). **REMAINING C2b (flagged, NOT blockers):**
  ① INVERT-toward-previous (the pure `voiceLeadTowardPrevious` exists + is tested, but wiring it needs a per-cell last-chord
  memory across windows); ② WINDOW CELL|ROW|BAR (the span family — CELL only today); ③ the editor still shows the card KEY
  picker even when a SCALE door governs (inert — a "(key from door)" caption is a device-owed UI nicety).
- **✅ MACRO-AUTOMATION M1+M2 — DONE (2026-09-01, `2aa17ed`+`f157ef8`; 999 green, iOS builds; engine-only). M1** = the 16-macro/
  two-species bank (8 slider + 8 toggle; timelines retired §K3, decode-safe). **M2** = the per-cell value store
  (`MacroCellValue` + `PluginState.macroCellValues`; builder-side fold `override ?? global`; no render change; persistence free).
  **NEXT = M3–M6 (the 4-tab band UI, PART-PAGE-ONLY, DEVICE-OWED):** M3 the band shell + layout split (part-grid interior −50%,
  the freed bottom half = the collapsible band; ferry/▲▼/STOP unchanged — `roomsPartGrid`) + BIND (tap-to-assign, reuse
  `MacroAuthoring`) + PLAY (8 pads + 8 faders → `setMacroValue`); M4 PUNCH (arm→tap cells→draw per-cell, writes `macroCellValues`);
  M5 SPAN (arm→ladder→sweep/×-pass); M6 mutate/randomize survival + rooms-@State ↔ document sync. Held for Paul's device eye —
  a large blind UI surface with layout-interpretation room; the engine it drives is proven + tested.

## ★★★ FERRY INTAKE 2026-08-31 — the ratified batch (DETAILED PLAN: `Docs/PLAN-incoming-2026-08-31.md`)
Five docs merged/added (interface-redesign +§8/§8b/§9 · scale-door +§6/§7/§7b · room-palettes · listening-set · macro-lanes).
`Docs/PLAN-incoming-2026-08-31.md` is the grounded, file:line implementation plan — read it before building any of these.
- **RATIFIED, buildable (sequence + risk in the plan §J). PROGRESS 2026-08-31 (unattended):**
  - ✅ **§A MIDI-tab scale label** — DONE (`Receiver.scaleLabel` shared helper; the tab shows "A MIXO" for a SCALE door; +test).
  - ✅ **§5 play-grid undo** — DONE (the 10 play arrays added to BuildSnapshot; ferry/flatten now record undo).
  - ✅ **§E GRID 8|16 stage 1** — DONE (Voice.cellIndex Int8→Int16, byte-identical, full suite green). STAGE 2 (the
    cols=16 flip + mask/cellSounding/Snap.cols widening) is device-verified, Paul-present — see plan §E.
  - ✅ **§B AVOID / LOCK (UNIFIED)** — DONE (`7c60dac`) + **CLASHES axis & LIVE-DOOR reference** (`6477fbb`). Paul unified
    "avoid clashes" + "lock to key" into ONE processor: a per-note pitch filter (keyFilterNote as a chain stage) —
    REFERENCE (KEY·DOOR·WIRE·ALL SOUNDING) × MODE (LOCK|AVOID) × ACTION (REMOVE|MOVE), placeable anywhere (position-
    independent; no SKIP — §K1 resolved). Subsumes the separate §H LOCK-TO-KEY. Full surface + self-naming (LOCK A MIXO /
    AVOID CLASHES) + storefront cards + fuzz. **CLASHES (`6477fbb`):** WHAT = SAME | CLASH | CLASH+ widens the reference
    set to its ±1/±2 pitch-class neighbours (widenClashMask) in AVOID mode (LOCK keeps the exact key) — so it dodges the
    dissonant semitones, not just the notes. **LIVE-DOOR (`6477fbb`):** a DOOR-referenced AVOID now reads what ANOTHER
    receiver is playing THIS render (latched/SCALE pool if present, else the live THRU input via doorLivePitchClassMask) —
    Paul's "listen to a different receiver" scenario, +test. Also fixed: standalone/single-slot [AVOID] + [X→AVOID] were
    silently emitting nothing (emitColumnHolds guard + isHoldTailChain lacked `.avoid`). WIRE/SOUNDING keep the L1 later-
    row caveat. **EDITOR REWORK (`b810558`, UI-only, DEVICE eye owed):** removed the KEY picker; REFERENCE → "LISTEN TO" =
    INPUT (▸A–D) | EVERYTHING (WIRE dropped from the UI); plain labels (AVOID|LOCK · ALSO DODGE NOTHING/CLASHES/MORE · IF
    BLOCKED DROP/MOVE) + an illustration PIANO (two live C1–C7 keyboards: the reference notes + clash halo · YOUR OUTPUT).
    Engine keeps every enum case (decode/test safety). DEVICE ear owed.
  - ✅ **§F PLAY-FERRY ROW CURSOR** — DONE (`7c60dac`; Paul's #4 clarification, NOT the abstract track-swap): a ▲▼ picks
    which grid ROW the play-ferry buttons target (`buildPlayFerryRow`). The ghost-previews/track-swap of redesign §9 remain
    a separate incremental-redesign item. DEVICE eye owed.
  - ⏸ **§G AVOID — OUTPUT/EMITTER references (RATIFIED 2026-08-31)** — extend the LISTEN-TO axis from input-domain only
    (INPUT ▸A–D · EVERYTHING IN = other receivers, excl. own) to ALSO output-domain: **OUTPUT ▸A–D** (what one emitter is
    actually PLAYING, post-arp/harmony/generators) + **EVERYTHING OUT** (all emitter output EXCEPT this chain's OWN
    emitters). Point: avoid the real MIX, not just raw held chords — a bass dodging a busy lead arp catches every arp note.
    Same PITCH-CLASS model (octave-agnostic — a ref C blocks every C). **Self-exclusion is mandatory** (else self-thin/
    flicker): v1 = exclude by BUS (read `soundingPitchClassMask` for emitters ∉ cell.busMask — simple, correct; also skips
    other chains on that bus); v2 = exclude by VOICE ownership (colourIndex/cellIndex — precise, keeps other chains on the
    same bus). **Engine ~mostly there:** `.wire` = one emitter (`soundingPitchClassMask(bus:)`), `bus:nil` = all — add
    "all except own buses"; the enum already has `.wire`. **COSTS to design around:** (1) L1 ORDERING — an output ref reads
    the live voice table (emitted-so-far this render), so the avoider must sit on a LATER grid row than its source, else it
    reads last render's output (~1 block lag); mutual refs ping-pong at 1-block latency. (2) MOVING TARGET — an emitter's
    output changes note-by-note; DROP = holes open/close musically, but a LEGATO hold could drop+re-strike (click) as the
    source crosses its class. (3) PIANO — the pianos predict from input doors (recvHeldNotes); an output ref needs a NEW
    per-emitter output feed to stay honest, else the OUTPUT-ref piano is degraded. UI = a LISTEN-TO domain toggle
    INPUTS|OUTPUTS × (one A–D | EVERYTHING). Effort: small engine + a UI axis + (for the honest piano) an emitter-output feed.
  - ⏸ **§C scale-aware IN strip** — the §6 SCALE-door IN readout + the "arm AVOID CLASHES from the strip" chip (thin UI over
    §B now that AVOID exists). Buildable next.
  - ⛔ **§D MACRO LANES — SUPERSEDED (2026-09-01)** by the ratified `INSTRUCTIONS-macro-automation.md` (the 4-tab band; see
    the 2026-09-01 intake + `PLAN-incoming-2026-09-01.md`). The old below-grid-lane framing is retired.
- **ALREADY BUILT (verified — do NOT rebuild):** the bazaar-muted select cells · scale-doors-name-themselves (on the
  receiver chip; only the MIDI-config tab bar is left = §A) · the room palette signatures (roomsField near-black PLAY,
  roomsDoorBar rainbow/amber/indigo/red, ▲PLAY indigo) · CHORDS/the dynamic reference.
- **⛔ DECISIONS PAUL MUST SETTLE before the risky pieces (plan §K):** ~~(1) AVOID SKIP downstream~~ ✅ RESOLVED (Paul: no
  SKIP at all — AVOID is a per-note pitch FILTER, REMOVE|MOVE, position-independent before/after an arp) · (2) macro-lane render path (build-side table vs render-side eval)
  + part-local scope (never write the global Macro.value) · (3) GRID 8|16 = always-16 allocation + active-width, per-doc? ·
  (4) ▲▼ axis/glyph (tracks are COLUMNS — swap c↔c±1? ▲▼ vs ◀▶) · (5) OK to add the 10 play arrays to BuildSnapshot (play
  grid has NO undo today).
- **CAPTURED, NOT ratified (HOLD):** LOCK TO KEY stage (scale-door §7 — ≈ AVOID with only:true at chain END) · the rest of
  the LISTENING SET (SHADOW/FEEL-THIEF/IMITATE/…) · the full rooms/tracks/provenance/footer redesign (build with Paul).

## ★ HOUSEKEEPING SWEEP — 2026-08-30 (dead code · 30-bug hunt · tests · refactors, unattended)
- **✅ DEAD CODE DONE:** 24 grep-verified zero-ref orphans deleted (`Housekeeping: delete 24 grep-clean dead orphans`) —
  22 BuildPage leaf helpers (buildBandNumber/BandRange/BlankSlot/CastMemberAt/ColourTabs/ColumnHasSelection/
  FirstFreePaletteSlot/FooterBoxBtn/Lighten/MidiOutInfo/MSBtn/RowButtonIcon/SetPartLen/SetSource/Step/TargetMark/
  colSelCellPart/row8Live + vars CurrentDeployed/PerformPopulated/ShowColourBox/StagingPopulated) + `clearReceiverLatch`
  + `buildPlacedOrig` (dead write-only PLACE-verb state). KEPT (reserved/conformance/WIP, do NOT delete): the macro-
  authoring + colour-chain + mark-feed + Row 8 AU APIs, the EditSelection undo cluster (markBorn/recordUndo/wasBorn/
  asSet/syncAnchor), `roomsPlayHeader` (active rooms surface), makeUIViewController/updateUIViewController.
- **✅ BUGS DONE (this pass):** K1 presets now carry the BUILD workspace · K2 load paths drop stale pending · K3 empty-
  scenes guards · P1 chain-audition fallback sweeps (not pins) · R1 master-MUTE closes sustained notes · R3 no-machine wire
  honors emitter enable/solo · Rooms1 play-rung tap re-publishes · Rooms2 pass-aware transport · Rooms4 ragged-restore guards.
  The 2026-08-24 pre-surveyed bug list (below, §"Wrong audio / correctness"…) was RE-VERIFIED — nearly all already fixed by
  unticked CR-6/9/10/11/15/16/17/18 passes; only [7]'s gate-stack half remained (= R2, flagged).
- **⚠ FLAGGED, NOT fixed (need a dedicated tested + device pass):**
  - **R2 — GLIDE gate stack — ✅ DONE (2026-08-30):** routed glide through the emitOneBus output pipeline via two helpers
    (`glideOutNote` = OCT + master KEY + FENCE · `glideBusAvailable` = emitter ENABLE + output-SOLO), applied at every open
    site in emitColumnGlide + emitGlideDriven; an unavailable bus phrase-ends the voice. Byte-identical when KEY/OCT/FENCE
    unset (330 RouterTests unchanged); +2 tests + fuzz. DEVICE ear owed (glide in key; disabled-emitter silence).
    **STILL DEFERRED:** CLAIM + CONVERSATION for glide — their discrete note-ghost / per-onset-stance models don't map onto
    a continuous mono bend (a design question, not a mechanical fix); the STEP-mode intermediate zipper notes aren't
    re-FENCEd (transient; endpoints are). This closes the open half of old finding [7].
  - **Rooms3 — a flattened play PASS's per-step I/O chips edit-but-are-ignored** (the engine uses playColStepRecv/Emit; the
    chips write only the column default). Overlaps the ⛔ PAUL-TO-DEFINE pass-editing model below — settle that first.
  - Minor (low): glide stamps a stale currentCellIndex (cosmetic SEAL/reel tag); flood governor undercounts BROADCAST.
- **`buildGCColours` (ephemeral-colour GC) was removed with the old UI** — the rooms UI never called it, so no behaviour change,
  BUT ephemeral colours (minted on ferry/flatten/audition) no longer GC. If a long rooms session shows colour bloat, add a
  rooms-side colour-GC (the old one keyed off the old-UI liveset; a rooms one would key off buildStagingCells + buildPlayCells +
  buildColourReg + the selection).

## ⛔ PAUL TO DEFINE — design decisions BLOCKING further build (2026-08-30, rooms multi-step passes)
- **★★★ HIGH — RE-ENTERING A PART ROOM AFTER IT'S BEEN FERRIED.** When a part has been flattened onto a play column
  (`roomsFlattenPartToPlay`), the flatten stops the part audition — but re-entering the PART room re-arms it
  (`roomsSyncVoice(.part)` sets `buildStagingPlaying = true`), so the part can play on rows 0–7 WHILE the flattened pass plays
  the same sequence on the play layer → DOUBLING/phasing. Need Paul's ruling: on re-entry should the part (a) stay silent
  because it's "moved to play", (b) play as normal (accept the double), or (c) something else (e.g. the pass mutes while you're
  in the part room)? Blocks a clean re-entry rule. Flagged in CLAUDE.md status (multi-step-play-passes entry).
- **★★ PRIORITY — EDITING CELLS ON THE PART GRID + FERRIES.** How editing works across the part grid, the select→part
  ferries, and (now) a flattened multi-step PLAY pass is under-defined. Current v1: a play pass's machine edit hits only the
  representative (first-step) colour — pass editing isn't a defined operation. Need Paul to define the model: what does
  "edit this ferry/pass" mean (edit one step? the whole pass? re-flatten?), and how the part-grid ↔ ferry ↔ pass edits
  relate. Blocks a coherent edit UX for the rooms surface.

## ★★★ ACTIVE THREAD — THE UNIVERSAL SPAN MODEL + STANDARD PANEL ANATOMY (2026-08-27)
- **✅ SPAN = re-anchor period, decoupled from an ABSOLUTE RATE (grain). DONE for the free-running generators:**
  - **RIFF + EUCLID** → FREE·1·2·3·4·6·8·×2·×4 re-anchor with an absolute GRID grain (`a94f4a8`; Paul "go absolute").
  - **FREE on TUTTI + RATCHET** (`5fa2451`, UI-only) — fixes the "shows 1 but free-runs" mislabel; adds a FREE chip.
  - **Cascade/burst/length LEFT on CELL|ROW** — their ROW is a real windowed reveal / bar roll / bar gate (not "just slower").
- **✅ STRIKE PER SPAN v1 — DONE on the DRONE** (`1c029ac`, spec `AcceptanceCriteria-strike-per-span.md` ratified): STRIKE
  HOLD|PER SPAN chip + RE-STRIKE EVERY ladder; re-articulate at each span origin, legato-hold between. One gate on the
  emitColumnHolds adopt decision. +2 tests + fuzz. DEVICE ear owed.
- **OPEN — STRIKE PER SPAN on the span-ladder DRIVER cards** (euclid/riff/ratchet/tutti-pattern/burst/cascade): each is
  tick-driven, not a hold, so each needs its own adopt/reconcile bolted on (bigger, riskier). Spec calls them "legal but not
  the point." HARMONIZE/TUTTI-COIN holds are the easy same-path follow-ups. Flagged in `_dear_paul/strike-per-span-drone-*`.
- **STANDARD PANEL ANATOMY §1 (spec `AcceptanceCriteria-standard-panel-anatomy.md`) — IN PROGRESS:**
  - ✅ **FOOTER** (`c01e966`+`5aedb06`+`e3ed45f`): `frameRow` = compact horizontal GRID·ROTATE·SPAN (Paul chose horizontal;
    gridMenu/spanMenu tap-menus + ◀n▶ rotate) + `pairsWell` line. On RATCHET + TUTTI PATTERN (the reference pair).
  - ✅ **HEADER OCT** (`ce0954d`): per-slot `stageOct` ±3 (stage's own voice); engine on all paths + `applyStage` post-shift; +2 tests.
  - ✅ **HEADER SOURCE** (`c5fffce`): per-slot `stageSource` CHAIN|MIDI IN|BOTH; v1 = the composeChainSet fold; +1 test.
  - ✅ **FOOTER SWEEP** (`b273afb`): the frame row + pairs-well now on RATCHET · TUTTI · EUCLID · RIFF · BURST(PATTERN).
    Footer redesigned per Paul's device iterations (`e3054e7`…`b273afb`): compact chips in one `FS` knobs block; GRID left /
    ROTATE centre / SPAN right; left-aligned labels above; GRID 2-row, SPAN 2-row (FREE·×2·×4 / 1–8); pairs-well under
    ROTATE; no "FRAME" word (rule kept). CASCADE excluded (a reveal). Per-card: EUCLID hides ROTATE in LINES; RIFF no ROTATE;
    BURST GRID gated by SLICES=RATE. Still open: OPTIONS chips in the footer (deferred).
  - ⏳ **CHROME** — reposition the IN truth-strip UNDER the header + the OUT roll to the FLOOR (currently one IN|OUT band below the body).
  - ⏳ **SOURCE downstream** (the [ARP→HARMONIZE(MIDI IN)] headline) — needs the door threaded into emitDriverNote (cascades
    through emit helpers) + the hold-tail source + **a FEEL ruling from Paul** (per-tick door read vs a sustained parallel voice).

## ★★★ THE INTERFACE REDESIGN — captured 2026-08-28 (`Docs/INSTRUCTIONS-interface-redesign.md`, ferry). BIG, build with Paul.
The whole surface geography, to be built INCREMENTALLY under Paul's guidance (door-loop pattern; device steps outrank prose).
Headline shape: **three rooms + the tape, one grid in view** — SELECT (shop) · PART (workshop) · PLAY (stage) · REEL (tape);
navigation = TAPS on thin door-buttons (no pane drags). **★ STANDING ORDER (§6): reuse REAL existing components, never
approximations** — docked chain editor → summoned overlay; I/O console → footer mixer layer; MIDI/RACK sheets → footer config
layer; pass-browser selection → reel assign payload; multi-row/stack machinery → the tracks; stateMatrix/slider-lane/nudge-pair
unchanged. **Anything that would be approximated: STOP + ask Paul.** Key laws: shared 8-cell HEADER (tap=play/stop track ·
long-press=assign) · PLAY grid = 8 equal vertical TRACKS, NO chain panels (§3b) · bottom band = 10 provenance doors
(SELECT · 8 per-track · PART; corners=general, middle=specific, doors follow the LIT slot §4c) · slot-column model (tap=take,
hold=FLIP LIVE|UNPACK §3c) · room-scoped audition silence (§5). Composes with `design-play-grid-lanes-OPEN.md` (the tracks/
stack model) + the just-landed panel-anatomy footer/header (the chain editor is the re-housed overlay). NOTHING built yet.

## ★★ DESIGN INBOX 2026-08-22 BATCH — 8 RATIFIED SPECS, filed to `Docs/` 2026-08-24 (sequencing = Paul's word). NONE built yet.
Read + filed: `INSTRUCTIONS-state-matrix.md`, `SPEC-arp-additions.md`, `SPEC-euclid-variations.md`, `SPEC-exclude-complement.md`,
`SPEC-glide-modes.md`, `SPEC-grid-selector.md`, `SPEC-motif-processor.md`, `SPEC-riff-processor.md` (all in `Docs/`). Reply in
`_dear_claude/REPLY-2026-08-24-eight-specs-filed.md`. **Recommended build order (mine — Paul picks):**
1. **✅ QUICK ENGINE WINS — DONE (2026-08-24, `3b096dd` + next):** ARP OCT-DIRECTION + RANDOM-ANCHOR · EUCLID PICK +
   INVERT · GLIDE SYNTH + STEP modes + on-screen text · KEYS EXCLUDE complement door. All additive-Optional chips,
   +10 tests, macOS green incl. fuzz, iOS builds. DEVICE ear/eye owed. v1 flags: GLIDE driven-path stays BEND (mono-
   driver commission); STEP run-window = glideTime (rate chip later); KEYS EXCLUDE Kernel subtraction device-owed.
2. **THE FOUNDATION (big cross-cutting UI):** STATE MATRIX + SLIDER LANE + SPAN LADDER (`INSTRUCTIONS-state-matrix §1-3`).
   - **✅ STATE MATRIX — DONE (2026-08-24, `bc40be2`):** the `stateMatrixRadio` widget (rows = states · cols = 8 steps ·
     radio-per-column · instant, no brush). Converted LENGTH · RATCHET PATTERN · TUTTI PATTERN (8×8) · BURST PATTERN.
     UI-only, reads the same slice arrays. DEVICE eye owed.
   - **SLIDER LANE (§2): the component ALREADY EXISTS** as `modStepBars` (tap-set + drag-draw, variable step count) at its
     origin STEP MOD. No new consumer to wire until VELOCITY/CHANCE/TIMING PATTERN land (Tier 3/5). Optional: rename it
     `sliderLane` + reuse when the first new consumer is built.
   - **SPAN LADDER (§3) — Paul RULED: RATE × ladder (both)** (RATE = slice width · SPAN = loop period in columns). Staged:
     - **✅ STAGE 1 — DONE (2026-08-24, next commit):** the 3 WIDTH procs (EUCLID · BURST · LENGTH) — dial 1·2·3·4·6·8·×2·×4,
       `spanLadderBeats`, byte-identical CELL=1/ROW=8, polymeter for odd N. +1 test, fuzz-hammered. DEVICE ear owed.
     - **STAGE 2a — DONE (2026-08-24, next commit): TUTTI PATTERN** — the RATE×ladder model proof. RATE = slice width;
       `tuttiSpanN` (opt-in, nil ⇒ legacy byte-identical) sets the loop period; the 8-slice walk re-anchors every N cols.
       +1 test, fuzz-hammered. **DEVICE EAR OWED before rolling further.**
     - **STAGE 2b — DONE (2026-08-24): RATCHET PATTERN + CASCADE** — same RATE×ladder (opt-in, byte-identical legacy).
       RATCHET: RATE = slice width, SPAN N = loop period. CASCADE: RATE = reveal spacing, SPAN N = reveal window. +2 tests,
       fuzz-hammered. **MOD EXCLUDED by design** — its rate IS the LFO/shape period (no width×period split; STEP MOD already
       has `modStepSpan`). SPAN LADDER now on 6/7 span procs. Whole rate-proc feel DEVICE-EAR OWED. **TIER 2 ENGINE DONE.**
- **RATIFIED UI DELTAS filed 2026-08-25 (from the ferry channel; engine-untouched, render+interaction only):**
  - **`Docs/FERRY-rotate-control-ratified.md`** — the numbered ROTATE row RETIRES everywhere: a **◀ n ▶** nudge pair
    (tap = slide one step, wrapping; offset shown small between) + **drag the lane/matrix itself** to rotate. Applies to
    CHANCE/RATCHET/BURST/TUTTI/LENGTH rotate (currently 8-chip 0–7 segs) + euclid lines (per-line ◀▶). Clean self-contained
    render pass; do after DEST unless prioritised.
  - **`Docs/FERRY-complement-extensions-ratified.md`** — KEYS EXCLUDE (already BUILT this session) grows: chip → **FREE |
    MINUS[door] | ONLY[door]** (ONLY = palette ∩ door = scale-lock), LATCH-mode generalisation, truth-strip carving, an
    exclude-lag hysteresis. All additive on the shipped MINUS door (ONLY = ∩ vs − one-line flip).
  - **TAP processor is now RATIFIED** (`AcceptanceCriteria-tap-processor.md`) — build when sequenced. Storefront
    increment-2: per-panel sub-header = YES · type-swap-through-catalog = YES (design-answered, captured).
  - **DESIGN REQUEST answered** (inventory delivered) → **PRESENTATION REDESIGN RATIFIED + PLANNED (2026-08-25):** the
    design side returned `Docs/SPEC-presentation-pass-ratified.md` (6 hierarchy rules + per-card remap) +
    `Docs/FERRY-presentation-ideas-ratified.md` (32 ideas; Paul's high-value wave 21·23·16·15·8). My implementation plan =
    **`Docs/PLAN-presentation-redesign.md`** — ALL render-only (engine + params untouched; device-eye is the judge).
    Sequence: **✅ A** `numPair` keystone (`0bf0fdd`) → **✅ B** hero law + options cluster (`1f46a94`) → **✅ C** section
    long cards (`49366c3`) → **D wave (partial):** ✅ 8 self-drawing chips + ✅ 15 playhead-sweeps-matrix (`d45e409`) · ✅ 23
    hold-bypass A/B (`321e885`). **DEFERRED (each has a wrinkle):** **16 SPAN BRACKET** — the ladder's ×2/×4 values don't
    fit an 8-column bracket cleanly (needs a design for the multi-bar case). **21 DEFAULTS-RECEDE** — needs per-control
    "is-at-default" plumbing across ~50 controls (a large mechanical pass; the options-chips already show deviation).
    → **✅ E** two-column (= width-Pass-2, `e773fa5`) — `row2` pairs the short couples. → **F (batch 1, `bb378b2`):** ✅ 30
    CC picker (MOD CC → numPair with named-CC format) · ✅ 4/22 double-tap-to-zero (bipolarSlider: FAVOUR·VOL TILT·SHAPE·
    ECHO NUDGE) · ✅ 9 teach-lines (CHANCE·NUDGE mode) · ✅ 18 lane-readout-at-the-finger. **A–F landed.** F REMAINING (each
    needs infrastructure, do on request): 3 detents+haptics · 5 fine-mode (custom slider) · 7 touch-preview (window render) ·
    10 long-press-chip-explain (per-enum text) · 12 tap-value big-picker overlay · 14 hold-to-accelerate · 17 result-ghosting ·
    19 pinch-lane · 20 lane-header-mute · 24 touch→OUT-strip diff (needs truth strips) · 25 conditional-animate-in ·
    26 long-press=bind-macro (macro flow) · 27 sticky-hero · 28 section-anchor-chips · 31 keypad-overlay · 32 hero-glyph
    thumbnails. **✅ 21 DEFAULTS-RECEDE — DONE (`90c105e`):** keypath-`field` overload vs one static `ColourParams()`
    snapshot dims ~45 at-default fields (no per-render alloc, one Equatable compare — Paul's low-cost constraint met).
    **16 span-bracket = LEFT AS-IS** (Paul's call — the ×2/×4 multi-bar look isn't worth reworking now).
    **F INFRASTRUCTURE (started 2026-08-25):** ✅ **12+31 VALUE OVERLAY (`8a78175`)** — tap a numPair's number → a grid
    picker (small ranges) / keypad (CC 0–127) for exact entry, self-contained on NumPair. ✅ **5 FINE-MODE SLIDER
    (`e233b8c`)** — a custom FineSlider replaces SwiftUI's Slider at all 29 sites (+ bipolar + morph); coarse = absolute,
    PULL AWAY from the bar (>44pt) → latches FINE ×10 relative scrub (thumb grows, "FINE ×10" pip). Drop-in via
    `slider(_:in:)`. Device-eye owed on the pull-away feel + threshold. ✅ **3 DETENTS + HAPTICS (`1e30344`)** — every
    slider fires a soft SELECTION haptic on notch crossings (20/range coarse · 100 fine); optional `detents` (musical
    values) add gravity-snap + a firmer bump + track pips. Wired glideTime/glideRange octaves/mod attack+release. Device-
    ear owed on the haptic feel. **THE CONTROLS-POLISH WAVE (numeric grammar + fader) is now COHESIVE + done.**
    **REMAINING TRACKS (each a distinct build):**
    (b) LONG-PRESS EXPLANATIONS (10) — DEFERRED by Paul (2026-08-25, "ignore for now"). ✅ **§1 TRUTH STRIPS v1
    (`98bec19`)** — IN silhouette (held @ door) + empty-state teach + OUT mini-roll on the processor editor. ✅ **§4 STAGE
    EYE v1 (`ff8a350`)** — tap a strip → a full-page 3-lane input·mechanism·output view (DRIFT model; EUCLID draws its
    pulses, others an 8-step position lane). ✅ **IDEA 24 TOUCH-TO-DIFF (`535cae5`)** — while editing, the OUT strip + eye
    output lane show a live before/after: NEW notes (born after the gesture, stamped at the `buildApplyChain` choke point)
    bright + ringed, the BEFORE dim, box glows. **The truth-strips track (§1 · §4 · 24) is now FEATURE-COMPLETE** — all
    device-eye owed. LEFT (v2, deferred): §4 column-aligned SWEEP (needs the engine to tag output notes by emitting step) ·
    bespoke per-type mechanism art · embed the real hero widget read-only. (d) MACRO-BIND (26) — HELD by Paul (downstream);
    (e) LAYOUT — sticky-hero (27) · section-anchor chips (28) · conditional-animate-in (25) · hero-glyph thumbnails (32);
    (f) LANE gestures — pinch-scale (19) · header-mute (20) · result-ghosting (17);
    (g) hold-to-accelerate (14, low value now — scrub+overlay cover it).
3. **NEW FEATURES ON THE SUBSTRATE:** ✅ **THE E-BRUSH — DONE (2026-08-25, `a17efe0`):** `EBrushButton` (ε + K/rotate
   popover) wired into the SHARED widgets — `sliderLane` (CHANCE·STEP MOD·TIMING), `stateMatrixRadio` (RATCHET·BURST·
   TUTTI·LENGTH), the MUTE matrix — so euclidean fills land on every grid; UI-only. ✅ **EUCLID LINES MODEL — DONE
   (2026-08-25, `85d715a`):** `EuclidLine`{target·K·N·rotate·invert} + `euclidLines: [EuclidLine]?` (nil ⇒ single euclid,
   byte-identical); engine `runEuclidLine` loop (per-line N = polyrhythm; note-target via strikeChord onlyIndex); UI = the
   LINES STACK + ADD LINE. +1 test, fuzz. Both were `SPEC-euclid-variations §10/§5`. STILL OPEN: per-line PICK + a per-line
   die (v1b). ✅ **TAP — DONE (2026-08-25, `2621dd3`):** the mid-chain SEND — `ProcessorType.tap` (note-transparent, cellMode
   `.identity`); a fold-loop special case in `emitDriverNote` mirrors each note to the TAP wire (LEVEL scale · TO THIS/A/B/C/D ·
   MUTE) via emitArtic, then passes `cur` through; +1 test, fuzz (`AcceptanceCriteria-tap-processor`). STILL OPEN: TAP hold-path.
   ✅ **ROTATE RETIRE — DONE (2026-08-25):** part 1 (◀ n ▶ nudge pair) already shipped in the presentation pass; part 2 = the
   `RotateOnDrag` modifier — horizontal drag on the pattern MATRIX rotates by direct manipulation (~26px/step, wrap, taps
   still set), wired to RATCHET·BURST·TUTTI·LENGTH. The ◀▶ pair stays as the visible hint + precise control. sliderLane cases
   (CHANCE·STEP MOD·TIMING) keep the ◀▶ pair only (drag conflicts with the vertical draw gesture — flagged); DEST matrix has
   no rest/rotate. UI-only, device-eye owed. ·
   **✅ RIFF STAGE 1 — DONE (2026-08-26): the rank-stencil ENGINE + editor** (`ProcessorType.riff`, a DRIVER; pure
   `riffResolve`/`riffNote` — rank→sorted-pool note, WRAP fold/clamp/wrap, oct, rest; `emitRiffRow` on the arp tick
   lifecycle, composes as a chain driver; the RANK MATRIX editor + STEPS/RATE/WRAP; MELODY card; +2 tests + fuzz). RIFF
   **remaining stages (open):** the OCT/ACCENT/TIE/SLIDE modifier lanes (§5) + the GLIDE-SYNTH slide interlock · CAPTURE
   (§2, arm + play-in, records as ranks — input-driven, device-owed) · the FOLLOWING frame (§4, rank-vs-chord-at-its-
   moment) · then MOTIF (plays the riff library — `SPEC-motif-processor`, depends on RIFF).
4. **GRID SELECTOR §2/§3** (`SPEC-grid-selector`) — **ACTIVATED 2026-08-26** (ferry `FERRY-select-grid-activated` = Paul's
   go-signal; sequencing still his word). Enhances the ALREADY-BUILT grid selector: EXCLUSIVE ON|OFF toggle + layered
   audition (QUANTIZE already ships), PART-BUTTONS-as-COMMIT (retire COMMIT; tap cell→tap part N deals it), LAYERED DEALS
   (EXCLUSIVE-OFF + N lit + part → the part's rows, one undo), right-column BROWSE-CONTEXT I/O (audition-only; deal uses the
   part's own I/O), the PREGEN CORPUS (bulk background gen → instant DEAL + preset mining; profile the live-roll first).
   Riders NOT ratified: HOLD part = preview · OCCUPIED/EMPTY part-button states. **Plan: `Docs/PLAN-grid-selector-and-
   ratchet-coin.md`**. **✅ §3.1 PREGEN CORPUS — DONE (2026-08-26, Paul):** `Dice.rollCorpus` (quality `rollEnsemble` passes,
   cheap STRUCTURAL dedup — not the render-heavy sig — seeded/deterministic) + `buildGridSelBuildCorpus` (INCREMENTAL 64/
   batch → 256 target, background utility thread, non-blocking); DEAL now SAMPLES 64 instantly (RE-DEAL bumps the seed),
   fresh-64 fallback until batch 1 lands. +1 DiceTest (8.6s; was 95s before dropping the double-render). v1: in-memory
   (persist-to-disk + preset-mining curation = follow-ups). **STILL OPEN (device-owed interaction increments): EXCLUSIVE
   ON|OFF + layering audition · PART-BUTTONS-as-COMMIT (retire COMMIT) · LAYERED DEALS · right-column BROWSE-CONTEXT I/O**
   — these touch BUILD's delicate device-verified part-deploy/audition model + are feel-heavy (recommend a device pass).
   **↳ ✅ RATCHET COIN — SHAPING THE DICE — DONE (2026-08-26, Paul ordered it):** all four seeded additive-Optional COIN
   additions — ① SIZE WEIGHTS slider-lane over 2·3·4·6·8 (`rtcSizeWeights` + `rtcCoinSize`; replaces SIZE LO/HI, empty ⇒
   LO/HI byte-identical) · ② REFIRE GAP 0–4 · ③ QUOTA FREE|~2|~3|~4 · ④ ODDS FROM FIXED|VELOCITY. ②③ = the bounded
   deterministic `rtcCoinFires` per-row SCAN (gap spaces, quota caps; "derived never accumulated", v1 resets per row);
   ④ = `coinVelFactor` (pool peak vel). +3 tests, fuzz-hammered, iOS builds. v1: gap/quota reset per 8-step row.
5. **THE MATRIX/LANE CANDIDATES (ratified §5):** **✅ CHANCE PATTERN + ✅ TIMING LANE — DONE (2026-08-25).** CHANCE =
   the odds SLIDER LANE (SINGLE|PATTERN, step-aware `effectiveProbability`). TIMING = NUDGE FIXED|LANE (per-column ±8/16
   pocket; step = cell column). Together they delivered the SLIDER LANE species fully: `modStepBars`→shared `sliderLane`
   with unipolar + CENTRE(bipolar) modes, now 3 consumers (STEP MOD · CHANCE · TIMING). **✅ DEST MATRIX — DONE
   (2026-08-25):** a new routing-class `ProcessorType.dest` — the 8-slice per-onset EMITTER hocket via `chopMask`; UI =
   the STATE MATRIX (A–D × 8, radio). +1 test, fuzz-hammered. **✅ MUTE MATRIX — DONE (2026-08-25):** a new routing-class
   `ProcessorType.muteMatrix` — an A/B/C/D × 8 MULTI-SELECT grid; each GRID COLUMN removes the muted emitters (indexed by
   `columnStart(m,S)/S mod 8` like CHANCE PATTERN — the `9a00e69` "MUTE does nothing" fix; was chopSlice = inert for holds;
   composes on top of DEST/CHOP in `chopMask`; last-MUTE-wins; empties → note dropped, no stuck note). Additive-Optional `muteSlices`
   (nil ⇒ nothing muted, byte-identical). +1 RouterTest, fuzz-hammered. **The §5 matrix/lane family is now COMPLETE**
   (STATE MATRIX · SLIDER LANE · SPAN LADDER · CHANCE PATTERN · TIMING LANE · DEST MATRIX · MUTE MATRIX). ARRANGEMENT
   MATRIX = NOT ratified.
6. **SLIDER LANE / WIDTH:** the `sliderLane` shared component now has 2 consumers (STEP MOD · CHANCE). Processor-editor
   WIDTH PASS 1 landed (compact segs + ≤600pt panel); **PASS 2 = two-column packing** of short fields (device-eye owed).

## ★ DESIGN INBOX 2026-08-22/23 — FILED + QUEUED (4 ferries read + filed to `Docs/`; sequencing = Paul's word)
- **⟳ ROW 8 — LARGELY BUILT 2026-08-24 (overnight autonomous; see CLAUDE.md status). DONE: the type MODEL + factory deck +
  per-scene toggle capture; the FREEZE + HALFTIME engines (live, tested, fuzzed); REDIRECT + SWAP (wire re-stamp, tested,
  fuzzed); the perform STRIP + the EDIT PAGE (author every type); SETUP/MACRO/KILL wired to the existing engine. OPEN
  (deferred, each substantial): BROADCAST (a per-note fan-out — voice/refcount+governor design), PART (scene-independent
  part playback), INPUT (door mode-act — reuse latch/replay engage), CC-PUNCH/PC-SEND (need an on-demand CC/PC emission
  path), the HUB (retire the 2 bottom config buttons + the SETUP "edit setups →" jump + the INPUT cell type), and the
  HELD-mover spring press-gesture (v1 toggles via row8On). Device eye/ear owed on all of it.**
- **⟳ SCENES V2 — v1 SWITCHER BUILT 2026-08-24 (in-memory). DONE: BuildSceneSnapshot + a chip strip on the play column;
  capture/restore/add (arrangement per-scene, parts/colours shared). OPEN: PERSIST scenes with the document; PASS-QUANTIZED
  switch (arm/blink/next-pass + a hard sceneFlush) — v1 is an instant republish; drag-swap + cog-trash delete; the §2
  user-defined grid makeup (band count/heights) + factory form templates. Device owed.**
- **ROW 8 (the "fifth row") — RATIFIED WHOLE, BUILD-READY** (`Docs/row8-spec.md`; supersedes the scenes-v2 doc's §3–6
  fifth-row sections). The bottom row becomes **8 TYPED performance cells** `{TYPE · payload · MOVER (HELD|TOGGLE|ONE-SHOT)}`.
  Type catalog: SEQUENCE · PART (play a part from a pad, scene-independent) · SETUP (rack-config radio) · MACRO · FREEZE ·
  STUTTER · BROADCAST · SWAP · REDIRECT · HALFTIME · CC-PUNCH/PC-SEND · INPUT (door mode-act) · KILL. Factory "danger gradient"
  deck (STUTTER·FREEZE·HALFTIME · `[+]` · REDIRECT·SWAP·KILL·BROADCAST). CONFIG lives on a dedicated **ROW 8 EDIT PAGE**
  (the compact grid goes PERFORM-ONLY for row 8); ROW 8 is the **HUB** — the two bottom config buttons (MIDI/RACK CONFIG)
  RETIRE, INPUT/SETUP cells jump to their sheets, ALL latch control runs through ROW 8. §5: NO factory reset. ENGINE ask
  (the one genuinely new op): **REDIRECT** (stream re-stamp A→B while held) + its refcount handback; most other actions
  reuse specced machinery (MACRO/TRIGGER/FREEZE/STUTTER/CC/PC). STATE split: authoring = DOCUMENT, pressing = RUNTIME
  (scene-captured toggle states). A BIG feature → its own STAGED effort (type model → the edit page → each action's engine).
  Sequence the build with Paul before starting.
- **SCENES V2 — MULTI PLAY GRIDS** (`Docs/scenes-v2-multigrids.md`). A SCENE = one play-grid ARRANGEMENT (the deployed
  instances per band); PARTS/colours/receivers/master are SHARED above the scenes. REFERENCE-not-move across scenes (a part
  deploys many ways); **scene CHIPS** (8, pass-quantized switch · re-cue · drag-swap, never overwrite). M/S = LIVE mixer
  (NOT scene state); rung-actives/mutes/FREE-picks/rates = per scene. §2 USER-DEFINED GRID MAKEUP (band count/heights/types
  in the 8-row budget) = **DOCUMENT-LEVEL**, "captured, NOT commissioned" (v2). This retires the always-length-1 `scenes[]`
  gap (the flagship-unbuilt hole in CLAUDE.md status). Large model change (per-scene arrangement state + chip grammar +
  instance mapping) — design captured, build on Paul's word.
- **MICROTONAL LADDER** (`Docs/microtonal-ladder.md`). Tuning-agnostic by construction (we emit note numbers). **TIER 0 =
  CLAIM IT** (manual + one marketing line "we send the notes; your synth's tuning decides the pitches" + a GLIDE-caveat
  support note) — DOCS-only, do now / at launch. **TIER 1 = ★ ONE "NOTES PER OCTAVE" cog setting** (default 12) read by
  CLAIM's mod-12, OCTAVE/OCT±/FOLD's ±N, and the KEYS-door key count → EDO-native (19/24/31-EDO…); small, safe (12 = today),
  future-proofs OCTAVE/PEDAL — **AWAITING PAUL'S WORD**. Tiers 2 (MTS-ESP client for display) + 3 (scala import · ratio-
  HARMONIZE · per-scene tunings) parked with the KEY-door session.
- **STANDALONE APP** (`Docs/standalone-app-analysis.md`; complements the DEFERRED `Docs/standalone-plan.md` + its 3 seam
  rules, already enforced). ~2 Code-weeks, ENGINE UNCHANGED: (1) AVAudioEngine driver + internal transport (~2–3d, also
  unlocks BACKGROUND) · (2) CoreMIDI OUT (4 virtual sources A–D) + IN (~2–3d; Network/BT MIDI free) · (3) Ableton Link
  (~1–2d) · (4) app chrome — transport bar/port pickers (~2–3d) · (5) polish + device pass (~2–3d). WHY NOW: the beta pool
  explodes (no host needed), XCUITest becomes possible, the standalone IS the store page. Recommendation: schedule the
  spike AFTER the current queue settles; phase ① driver+transport+OUT (playable alone) → ② IN → ③ Link → ④ chrome.

## ★ CODE-REVIEW FINDINGS 2026-08-23 — ✅ ALL 18 FIXED (overnight autonomous batch + CR-8 closed later; see CLAUDE.md
## status). **[9]/CR-8 (PluginState non-Optional post-v2 fields) is DONE** — `activeScene`/`morphMaster`/`busChannels`
## are now additive-Optional with `*Resolved` helpers (Models.swift ~1029; test testPreV2DocMissingBusChannelsActiveScene
## MorphDecodes). **2026-08-29:** the SAME class on `Cell.inputChannel` (v3.0 non-Optional → a formatVersion-2 doc's
## cells threw at decode, BEFORE migration could run → whole-session data-loss) is closed with a decode-tolerant Cell
## init(from:) (the Macro/BuildPart pattern; fields stay non-Optional so encode is byte-identical; +3 tests). Commits:
## e1f6925 (CR-1/12/16/17) · 67bd53c (CR-2/3/4/5/6/7/9/10/11/13) · 9e72626 (CR-14/15 + the 7 EXTRAS). The historical
## finding text is kept below for the record.
## **RE-VERIFIED 2026-08-30 (housekeeping sweep):** every item below re-checked against current code — ALL closed by the
## CR passes above EXCEPT [7]'s emitOneBus-gate-stack half (GLIDE), now flagged as R2 in the top housekeeping section.
## New data-loss fixes this pass extend the same class: K1 (presets now carry the BUILD workspace) + K2 (load paths drop
## stale pending) — see the top section. The list below is HISTORICAL; do not re-chase without re-verifying first.
##
## (original sweep header:) 6-reviewer adversarial sweep — Router · Kernel · Derivations/Builder · Models/Emission · BuildPage · VC/AU; each finding VERIFIED against the code. Fix in small individually-verifiable commits (macOS suite + iOS build after each); the render-engine ones are byte-identical-sensitive — lean on RouterTests + fuzz.

### Crashes & races (do FIRST)
- **[1] Nested `[[UInt8]]` receiver-sounding feed = live render↔main race (the known SIGTRAP class).** `Kernel.swift:389,398,428`
  (`recvHeldVel`/`recvHeldNote`, written per-element on render, polled every tick at `AudioUnitViewController.swift:784/789`
  via `MidiSparkAudioUnit.swift:434`). The scalar-mask fix was applied to the DOT but NOT these — same pattern the
  `soundVel`/`markVel`/`withheldVel` feeds were FLATTENED to avoid. TWO reviewers found it independently. FIX: flatten to
  `4×W` value arrays (+`recvHeldCount`), like the emitter feeds.
- **[2] `Int8(colourIndex)` traps at ≥128 colours.** `SnapshotBuilder.swift:54` — `colourIndex` is a document-order index but
  `SnapCell.colourIndex` is `Int8`; with the 16-cap gone (unlimited ephemeral colours) a big BUILD session crosses 128 →
  overflow trap on publish. FIX: widen `SnapCell.colourIndex` to `Int16`/`Int` (or clamp with a documented ceiling).
- **[3] Colour param observer/provider/resync index `document.colours` unguarded < 16.** `MidiSparkAudioUnit.swift:1067,1083,1271`
  — sibling setters bounds-check; these don't. Latent (builders make 16), but a decoded/hand-crafted <16-colour preset +
  host automating `morph_15`/`transpose_15` traps. FIX: `< document.colours.count` guards.

### Stuck notes
- **[4] GLIDE bookkeeping not flushed on the emitter-disable + preview edges.** `Router.swift:1951` (bus disable via `closeBus`)
  and `2022` (preview via `allNotesOff`) close the immortal glide anchor but omit the `flushGlide()` the transport/panic/
  scene/latch edges pair with (warning at 2006). Kill a glide via the fader → stale `glideVoices.slot` → the reused slot
  later emits a spurious note-off on an unrelated note + the glide goes silent. FIX: add `flushGlide()` at both edges.
- **[5] ReelDeck `cap`(16384) vs `histCap`(8192) asymmetry drops note-offs on re-selection.** `Emission.swift:38,48,62,66,88` —
  the auto-loop keeps 16384 but the archived ring slot keeps 8192, and `replay()` re-emits verbatim with no synthetic offs.
  A dense pass replays fine immediately but, re-selected from the browser, is truncated → stuck notes (looks intermittent).
  FIX: unify the caps, or have `replay()` close notes still open at loop end.
- **[6] Uniform vs multi-clock paths keep separate column-edge trackers that desync on a live clock-mode switch.**
  `Router.swift:2101–2136` — `prevEffColumnRow[]` only re-inits when `prevEffColumn == -1` (a flush); enabling a per-row rate
  live is NOT a flush → a stale row tracker can skip a row's transition reconcile → phantom sustained drone. Low-probability.
  FIX: reset `prevEffColumnRow[]`/`modLastColumn`/`glideLastColumn` on the uniform↔multi-clock transition.

### Wrong audio / correctness
- **[7] GLIDE emits note-ons via raw `openVoice`, bypassing the whole `emitOneBus` gate stack.** `Router.swift:2422+` — no
  `busEnabledMask`/`soloEmitterMask`/CLAIM/FENCE/master-KEY/OCTAVE/flood reads in the glide path (MOD, its sibling, checks
  them). A disabled/soloed-out emitter still plays its glide line; master transpose/fence never applies to glide. FIX: route
  glide through the same gates (or replicate the enable/solo/key/fence checks).
- **[8] BURST "HITS 12"/"HITS 16" both render as 8.** `SnapshotBuilder.swift:291` clamps shared `count` to `2…8`, but BURST
  writes up to 16 and the engine expects it (`Router.swift:2700` `min(16,…)` is dead). FIX: `clamp(v, 2, 16)` (RATCHET
  unaffected — `effectiveRepeats` re-snaps ≤8).
- **[9] Master MUTE / master-kill doesn't silence BYPASS voices.** `Router.swift:461` `reconcileBypass` has no `masterMute`
  guard while grid/MOD/GLIDE all do → a bypassed door plays new notes straight through master mute. FIX: gate on
  `masterMute` (or confirm monitor-through-mute is intended).
- **[10] Parameter tree never resynced on the REAL load paths.** `MidiSparkAudioUnit.swift:1168` (factory), `1187` (preset),
  `1309` (fullState) skip the `syncParameterTreeToDocument()` that `loadTestSession` (1108) calls → after a restore the host
  shows the previous doc's stepRate/transpose/morph/macro + the next knob nudge fights the new doc. FIX: call it (suppress-
  rebuild wrapped) in all three.
- **[11] MONO steal runs BEFORE the flood governor → silent emitter.** `Router.swift:1173–1195` — MONO closes the holder (1185)
  then the governor can `return -1` (1193), dropping the note it stole for → the emitter goes silent for the rest of the beat.
  FIX: move the governor check ahead of the MONO steal.
- **[20] REPLAY discontinuity forward-jump threshold is a fixed `> 1.0` beat.** `Kernel.swift:662` — doesn't scale with
  `renderWindowBeats` (the comment even says a normal block advances by ~that), so at high tempo × large buffer a normal
  block trips `clearHistory()` every block → "LAST N" captures nothing. FIX: `> max(1.0, k * renderWindowBeats)`.

### Persistence / data-loss
- **[12] ✅ DONE (PluginState + Cell).** Non-Optional post-v1 fields broke decode of old documents → whole session silently
  lost (Swift ignores the `=` default on decode → `keyNotFound`, swallowed by `try?`, so the doc reverts and the migration
  never runs). PluginState's `activeScene`/`morphMaster`/`busChannels` are now additive-Optional with `*Resolved`. **2026-08-29:**
  `Cell.inputChannel` (added at v3.0) was the same trap for a formatVersion-2 doc — closed with a decode-tolerant `Cell`
  init(from:) (decodeIfPresent every field; fields stay non-Optional so encode is byte-identical). +tests both.
- **[13] `rackConfigsResolved` discards saved rack setups unless length == 4.** `Models.swift:833` — siblings PAD; this drops
  a length-3/5 array to the legacy default → all four user rack configs lost. FIX: pad/truncate to 4.
- **[14] `fullState.set` never resets `pendingBuildUnassigned`.** `MidiSparkAudioUnit.swift:1305/1311` — a host that saves right
  after loading session B re-persists session A's BUILD part (or nil) over B's. FIX: set `pendingBuildUnassigned =
  doc.buildUnassigned` in `fullState.set`.

### UI / state
- **[15] Processor-editor CANCEL reverts the WRONG colour after an in-editor colour switch.** `BuildPage.swift:3641/3648` —
  snapshot captured once in `.onAppear`; the editor has no backdrop (left column stays tappable), so switching the selected
  colour mid-edit leaves the snapshot on the original → CANCEL reverts X and strands Y's edits. FIX: re-snapshot on
  `ddSelectedColourID` change (`.onChange`), or revert the current target.
- ~~**[16] A door's running REPLAY loop is stranded when its mode is switched**~~ FIXED 2026-08-23 (folded into the THRU/SET-button
  rewrite): `buildReceiverLatchButton` now computes `engaged = replayOn || latchOn` and the tap stops whichever arm is live,
  so a mode switch can't strand a running loop.
- **[17] RANGE-picker keyboard hard-codes `width: 660`, overflowing narrow sheets.** `BuildPage.swift:375` — sheet is
  `min(720, width-32)`; on a < ~712 pt AUM pane the top octaves render off-screen → high MIN/MAX bounds untappable. FIX:
  derive the keyboard width from the available sheet width.

### Perf / invariant-3
- **[18] Per-event heap allocation on the render thread in `handleIncoming`.** `Kernel.swift:913` `var hearing =
  [false,false,false,false]` per forwardable CC/PB/AT (same class as the fixed "M1" alloc). FIX: reused member scratch, or
  fold the OR inline without the array.
- **[19] The 4 Hz poll isn't gated on `uiAppeared`** (the 30 Hz `meterTimer` at `AudioUnitViewController.swift:717` is;
  the poll at `723` isn't) → drains render→main feeds every 250 ms while the view is hidden (wasted work + widens finding-1's
  race window). FIX: add the `uiAppeared` guard (keep `buildPersistTick` running if needed).

### EXTRAS — lower value, fold into a cleanup pass
- **Inverted per-cell velocity window mutes a cell** — no `floor ≤ ceil` guard (`SnapshotBuilder.swift:88`; SPLIT's `splitVel`
  and the RACK FENCE both guard theirs). Reachable only via decoded/library cells (the per-cell UI was removed). FIX: order
  the bounds in `resolve`.
- **`rangeLo/HiResolved` has the same missing `lo ≤ hi`** (`Models.swift:536`) → an inverted decoded window silently kills the
  door. FIX: `hi = max(lo, hi)` in the resolver.
- **ARP ignores the cell's `chordSplit`** while HOLD/STRUM/RATCHET honor it (`Derivations.swift:942`). May be intended like the
  vel-window omission — DECIDE, then either honor it or document the asymmetry.
- **`bypassDestResolved` doc-comment says "ALL four" but the code intentionally defaults to emitter A** (`Models.swift:547-548`,
  "user 2026-08-05"). Stale COMMENT — fix the comment (code is correct).
- **`receiverNote` is dead write-only state + `nudgeReceiverNote` is missing** (`AudioUnitViewController.swift:260,526`; the AU
  `setInputSemitone` has no live caller). Either wire the ±semitone nudge or delete the dead state.
- **Reel-replay logs a spurious "playing silence leak" self-heal** from a stale `diag.activeVoiceCount` (`Kernel.swift:768/818` —
  `router.process` is skipped during replay so the count never updates). Diagnostic noise only (bumps `diag.panics`). FIX:
  zero `activeVoiceCount` on entering replay, or exempt the replay state from the silence-leak net.
- **`buildDeployCurrentPart` lacks the `>= 0` guard its siblings have** (`BuildPage.swift:2028`) — latent `[-1]` crash,
  currently unreachable. FIX: guard `buildCurrentPart >= 0` for symmetry.


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

## ★ AUDIO CRACKLE IN AUM (Paul reported 2026-08-21 — UI actions glitch the host audio; may be partly AUM/other apps)
- **Render (audio) thread is real-time-safe** — verified: pre-allocated scratch buffers (Router), lock-free `store.acquire()`,
  no locks/dispatch/ObjC/allocation on the audio thread for normal use. So the plugin isn't inherently glitching the graph.
- **Cause = main-thread CPU pressure** starving the audio thread on a loaded host: (a) presenting a SwiftUI Menu (e.g. the
  RATE selector) re-evaluates the HEAVY BuildPage body — the "opened the rate selector, it crackled" case; (b) every doc
  edit ran `SnapshotBuilder.build` synchronously on main — repeated spikes during interaction.
- **DONE (`3a0fb30`):** coalesced `scheduleRebuild` → one build per runloop (was N synchronous builds per gesture).
- **STILL OPEN (device-verify + bigger):** reduce the BuildPage body's re-evaluation cost (the menu-open spike) — a
  SwiftUI-perf pass (Equatable views / smaller diffed subtrees / fewer poll-driven @State re-renders). Also: the new 30fps
  `meterTimer` adds some main-thread load (trade against the velocity-indicator latency fix if needed). And a KNOWN niche
  invariant-3 spot: MOD §2 `applyInternalMods` COW-allocates when a cell uses an INTERNAL-target MOD (unused today; fix
  if that feature sees use). Device factors outside us: AUM's audio buffer size + whatever else is running.

## ★★★ HOUSEKEEPING — TOP PRIORITY (Paul 2026-08-31): UNIFY THE MACHINE↔CELL PLAYBACK/SELECTION MODEL
- **PROGRESS 2026-09-01 — INCREMENT 1 LANDED (`121c997`, behaviour-preserving + tested):** the pure `BuildSceneLogic.machineBinding(...)`
  → `MachineBinding { kind: .none|.selectAudition|.partRow|.playFerry(c), isGrey, playing }` (primitive inputs so it's in the
  test target; +testMachineBindingResolvesFerryAuditionAndGrey). `buildMachineBinding(room)` gathers the four axes; `buildMachineHue`
  AND the play button (`roomsVerticalPlay` active/hue/tap) now DERIVE from it → the machine's play state == the represented cell's
  by construction. **INCREMENT 2 (OPEN, device-owed):** route the remaining PER-CELL indicators through the same binding —
  `roomsSideChip` (D3), `roomsPlayFerry`/`roomsPlayCell` `on`, `buildGridSelCell` roll (D1's extra `!buildChainLiveChord.isEmpty`
  term) — and reconcile D5's second "grey" (the cell selGrey vs the machine grey). This CHANGES on-screen state → verify on device.
- **The problem (Paul's device report):** the machine (box + play button) is meant to ALWAYS represent exactly one cell —
  a select-grid cell (light grey), a part cell, or a ferry (its colour) — and its play/stop must drive THAT cell, with the
  cell reflecting the play state (and vice-versa). Today there's a disconnect: the machine can be playing while no cell shows
  it, and edits/selection can diverge from what plays.
- **Root cause (mapped 2026-08-31 by an Explore agent — see the session transcript):** playback truth is split across
  FOUR independent axes, reconciled only inside individual tap handlers (`buildGridSelAudition`, `buildSelectPlayColumn`,
  `roomsAssignPlayColumn`), so any state change touching one axis without the others desyncs:
  1. `buildVoiceOwner` (`.none|.chain|.part`) — the shared EXCLUSIVE audition voice (ddSolo/buildStagingPlaying are mirrors).
  2. `buildPlayColOn[8]` — the PERSISTENT per-column ferry layer (sounds on every page, independent of selection).
  3. `buildSelID` → `ddSelectedColourID` — MACHINE identity (which cell the box/chain/play button represent).
  4. `buildGridSelSel` — the SELECT-grid cell highlight.
  Machine hue greys iff `buildSelID == buildGridSelAudID` (gsAud); the play button's `active` is `buildDisplayVoice==voice`
  OR `buildPlayColOn[buildSelectedPlayCol]`; the select cell's "playing" adds `!buildChainLiveChord.isEmpty`; the ferry's is
  `buildPlayColOn[t] && buildPlaySel[t]==buildPlayFerryRow` — five different derivations of one conceptual binding.
- **The disconnects (agent's D1–D6):** D1 machine `active` ≠ select-cell roll-scroll (extra live-chord term); D2 a ferry keeps
  playing while the machine represents gsAud and reads STOPPED; D3 selecting a ferry kills the chain audition; **D4 (partly
  fixed 2026-08-31, `e01e77d`)** entering SELECT auto-played an orphan colour with no visible cell — now gated on
  `buildGridSelSel != nil`; D5 two independent "grey" conditions; D6 five "playing" derivations off different @State.
- **The task:** collapse to ONE source of truth. Sketch: a single `MachineBinding { kind: .selectCell(i) | .partRow(n) |
  .ferry(c) | .none, playing: Bool }` (or equivalent), from which the machine identity/hue, the play button state+action, and
  EVERY cell's highlight/playing indicator all DERIVE — so they cannot diverge. Keep the persistent ferry layer (`buildPlayColOn`)
  but make the machine's play button + the represented cell read the SAME state. Do it TEST-GUARDED (extract the pure
  binding→state resolution into a Foundation-only function with unit tests, the BuildSceneLogic pattern) — this is UI-model
  logic that's currently untestable and device-verify-only. Was going to rush it blind; Paul said do it LATER, carefully.

## ★ HOUSEKEEPING FLAGS — surveyed + verified 2026-08-19, DEFERRED (need a focused tested pass, not unattended)
- **Render-path allocations (invariant 3):** (1) ~~`srcNotes` local array in the 4 driver emitters~~ DONE (2026-08-19,
  `ac7eb2b`) — a reused `srcNoteBuf`/`srcNoteCount` + `srcNoteBuf[0..<srcNoteCount]` slice view; byte-identical.
  (2) ~~`euclidPattern`/`burstFractions`/`tuttiSliceRanks` array returns in the hot loop~~ DONE (2026-08-20, `a87e492`)
  — `*Into(&buf,…)` no-alloc variants in Derivations (array versions wrap them for the tests); Router reused buffers,
  separate tutti A/B for the `[TUTTI→TUTTI]` nest; byte-identical. (3) ~~`process()` uniform-vs-multi-clock transition
  block ~duplicated~~ DONE (2026-08-21, `c338eda` — `emitColumnTransition(effCol:prevEdge:onlyRow:…)`; onlyRow nil =
  global clock, r = per-row; byte-identical, proven by the acceptance oracle + fuzz determinism). The TICK loops
  (`emitTickRow`) were already shared; only the trivial MOD/GLIDE per-row loop stays inline. Closes codebase-review §12.
- **TAB SECTION RETIRED (2026-08-21, `96a484d`→`7b01ade`) — BUILD is the sole surface; GRID/MIDI IN/MIDI OUT-tab/
  MACROS/AUTOMATION + the tab bar deleted (~2.4k lines); MIDI OUT `RackMatrix` kept as a BUILD overlay.** **EDIT/verb/
  proc-editor CLUSTER also deleted (2026-08-21, `7b01ade`, ~980 lines):** with BUILD sole, `editArmed` is permanently
  false + `heldVerb` permanently nil, so the whole grid-EDIT / verb / flow-diagram-proc-editor machinery was dead (kept
  alive only by flowDiagram's interactive buttons, which BUILD renders display-only + edits via its own
  `buildProcessorEditor`). Removed the chain-edit/macro-authoring/pop-up/output-split/selection machinery from EditPage,
  the verb + selection-undo cluster + 22 dead @State + Verb enum from the VC, dd* residue, and the whole
  `MacroAuthoringView.swift`. KEPT (BUILD-reached): `flowDiagram` + its display subtree, `cellChain`, `editPointedCell`,
  the dd* colour cluster + `EditSelection`/`sel` (BUILD scopes via `ddScopeToColour`), `syncSingleModeActivation`,
  `refreshTapMasks`, `setHold`. STILL LEFT (low-value, not chased): a few write-only mark @State (`emitMarks`/`recvMarks`/
  `emitHeld`/`emitRelease`/`recvRelease`/`recvLiveHeld`) + their poll writes; `GridView` + its renderers + `GridMacroSlider/
  Button` (BUILD uses `GridView.GridPos` + shares the components — the grid component itself is still referenced). Total
  tab-retirement sweep: ~3.4k lines. DEVICE eye owed on the whole BUILD surface (esp. the flow diagram still renders, and
  RackMatrix via EDIT TREATMENTS).
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
  `rangeHi` (+`rangeLoResolved`/`rangeHiResolved`), so it's a UI-surface item, not new engine.** **DONE (2026-08-21,
  `f497bea`/`e87c55c` — the MIDI INPUTS sheet's door section: 16-channel multi-select buttons + ALL/NONE, OCT ±, a
  RANGE row → a 6-octave keyboard MIN/MAX picker, the mode radio, and a LIVE INPUT|[MODE] test-in-place engage pair.
  Rides the MULTI-CHANNEL engine `fae473a`.)** STILL OPEN (each needs a
  device checkpoint — the latch/kernel is delicate + verified): STAGE 3
  REPLAY = the door input ring recording (a NEW engine feature, the door-loop v1); STAGE 4 FILE = .mid playback as living
  input ("a file is a cable"). STAGE 3 REPLAY **DONE** (2026-08-20, `6ad8e34` — DoorRing input ring, self-arm, capture at
  N-pass boundaries, pool from the loop; byte-identical, +tests; device-ear owed). **BUGFIX (`5b8b0d6`, Paul reported
  "REPLAY works sometimes, other times not"):** `capture` now seeds beat-0 note-ons for notes HELD across the catch
  window start (their on was before the window → previously dropped → silent). OPEN follow-ups (device-verify): a note
  still held at the catch END drones (on, no off in the window); a host that LOOPS transport makes the ring's absolute
  beats discontinuous. STAGE 4 FILE engine foundation **DONE**
  (2026-08-20, `aafdc97` — `MidiFile.decode` SMF parser + `DoorRing.loadLoop`; round-trips; 811 green). Interim UI:
  door MODE row on BUILD (`c80b7bc`/`115ce17`) — but §5/§6 below RELOCATE it.
  **⚠ DESIGN REVISION (config-sheets §4–§9, 2026-08-20) — answers "where does MIDI I/O live? it isn't per-build":**
  (§5 LAYER MODEL) the **console = the raw-input layer** (door CONFIG is global/infrastructure, correct as-is); the
  **compact grids = performance** (chrome-quiet, no config furniture); the **EYE opens a SPACIOUS VIEW = the detail layer**
  where per-row door info + row I/O pickers live (the eye is a VIEW-ZOOM, not inspection — the earlier "eyes never set"
  law is WITHDRAWN). (§4) door OWNERSHIP is per-row (which door a row hears); the door CONFIG stays global — the two
  grains separated. (§6) **TWO STACKED BUTTONS bottom of the page: `[MIDI CONFIG]` / `[RACK CONFIG]`** (left of the
  receiver strips, right of the record/reel button) → the MIDI sheet (4 INPUTS + 4 OUTPUTS) / the rack sheet. (§7) the
  sheets are the TEACHING surface — every mode carries its plain-English description in place (reuse the friendly-labels
  copy); `[RACK CONFIG]` bears the active setup ("OUT CHAIN · 2"). **⇒ my interim door-MODE row on the BUILD grid should
  MOVE into the MIDI CONFIG sheet (spacious view); the compact grid keeps at most a per-row door-tint edge (visibility
  only). Don't polish the BUILD-grid version.**
  **§9 NAMES RATIFIED (user-facing text ONLY — code identifiers NEVER rename, standing law):** "door" → **MIDI INPUT**
  (sheet "MIDI INPUTS"; per-row badge "INPUT: A"; radio "INPUT MODE"); "rack" → **OUTPUT CHAIN** (sheet header; button
  "OUT CHAIN · 2"; strip button "CHAIN"; the 4 configs → **SETUP 1–4**). So `DoorMode`/`rackConfigs`/`setDoorMode` etc.
  stay as-is in code; only the LABELS change when the sheets are built.
  STAGE 5 the UI: MIDI CONFIG sheet **DONE** (2026-08-20/21 — spacious MIDI INPUTS sheet: 16-ch multi-select, range
  keyboard, mode radio, LIVE INPUT|[MODE] test-in-place; `f497bea`/`e87c55c`). RACK CONFIG sheet **v1 DONE** (2026-08-21,
  `33965c6`; deep treatment stack inline **DONE** 2026-08-21, `427fc4d` — the OUTPUT CHAIN sheet is now one self-contained
  surface: SETUPS radio RACK 1–4 · a compact ON BOARD membership row (A·B·C·D chips, lit=in path / dim=RAW) · the full
  RackMatrix treatment editor INLINE (`RackMatrix.embedded` mode drops its header/scroll/panel; OWNS/KEY/TURNS/MONO/
  FENCE/CURVE/POCKET/CONVERSATION edited in place); the read-only summary + EDIT TREATMENTS jump + the separate overlay
  are gone). ~~PER-ROW INPUT·MODE INDICATORS~~ BUILT then DROPPED at Paul's word (2026-08-21, `969f745`→revert `436279d`
  — the staging-row-button door-tint stripe + "A·L" badge; Paul hadn't checked the placement first and pulled it). The
  full per-row I/O PICKER (the spacious "eye" view) remains the intended home for per-row door info — NOT the compact
  grid; don't re-add compact per-row badges without Paul's steer.
  The ~~RECORD button move to the top-right banner~~ TRIED + REVERTED (2026-08-21, `43ba611`→revert — Paul prefers the
  reel/RECORD glyph in the bottom-left cluster where it was; don't re-move it). DEVICE eye owed on the inline matrix (it now
  lays out in a ~640pt sheet, not the old full width). **§9 LABEL RENAME DONE** (2026-08-21, `c566054` — SETUPS radio +
  the 4 play-grid buttons "RACK n"→"SETUP n" (the buttons now WIRED to setRackConfig, active lit); dropped "door" wording;
  the "RACK CONFIG" button keeps Paul's override). **FILE STORAGE RECONCILE DONE** (2026-08-21, `89d2432` — the imported
  clip persists on Receiver.fileClip (Codable, capped 8192) through the document round-trip + rebuilds into the box + the
  Kernel reloads the DoorRing; +`testFileClipSurvivesDocumentRoundTripAndRebuilds`. Follow-up if heavy: store raw .mid
  bytes + decode-on-load instead of decoded notes).
- **MOD · SPAN + INTERNAL TARGETS** (`Docs/AcceptanceCriteria/AcceptanceCriteria-mod-span-target.md`, 2026-08-20 — MOD
  grows two axes, NOT a new processor): **§1 STEPS SPAN DONE** (2026-08-21, `8334342` — PERIOD|ROW|ROW×2|ROW×4 = 8/16/32
  breakpoints across 1/2/4 bars; `ModStepSpan` enum, box carries N breakpoints, `modStepsUnipolar` generalised to N,
  Router derives the STEPS period from it, 4-way SPAN seg + N-bar step editor; old cell|row modSpan migrates, byte-
  identical; +3 tests). **§2 TARGET → THIS CHAIN DONE** (2026-08-21, `8896219`, Paul-approved v1 mapping): `ModTarget
  {cc,chain}` + `modChainParam`; render-time BOUNDARY-DEFERRED — `applyInternalMods` copies the SnapCell at the top of
  `emitTickRow`/`emitColumnHolds`, samples each internal MOD once at the column start, re-ranges by MIN/MAX (MIN>MAX
  inverts), scales by the param's span (`macroParamSpan`), adds to every slot's param (`applyModChainOffset`, clamped
  like macros — composes on one lane); no render-path alloc; emitColumnMod skips CC + reset for internal; UI SEND = CC |
  THIS CHAIN + a param menu. Byte-identical when target=CC (oracle + fuzz green). +3 tests. Mapping of record: `offset =
  (min/127 + u·(max−min)/127) × param-span`, added to base + clamped. v1 boundaries (device-tune): STRIKE sampled at
  t=0 (≈0); ON EXIT HOLD nominal (the param only applies while the cell renders its column). Partially lands the CC-RAIL
  birthstone's mapped-values half. **DEVICE ear owed on the feel + mapping.** MOD · SPAN + INTERNAL TARGETS = COMPLETE.
- **THE MELODY/CHORD SUITE** (`Docs/AcceptanceCriteria/AcceptanceCriteria-melody-suite-UNRATIFIED.md`, UNRATIFIED —
  CAPTURE ONLY, do NOT build). RIFF (capture+remap) · TRIGGER (chords play the melody's rhythm; STAB|CLOCK) · HARMONIZE
  SOLI mode (dynamic block harmony from a door's pool) · PEDAL (hold the bar/cell's first note; FOLD-to-home register) ·
  a shortlist (gap-intelligence, contour extraction, canon rail, self-accumulation). Interface rule: receiver door chips
  (THIS·R1–R4) live IN the processor panel. Held UNRATIFIED at Paul's word.
- **THE DOOR LOOP family** (`Docs/design-door-loop-2026-08-19.md`, ratified-for-the-channel). **CORE SHIPPED** = the
  REPLAY door mode + `DoorRing` (config-sheets stage 3, `6ad8e34`): record a door's raw input, cycle it back as living
  input; RETRO-CAPTURE (the CATCH ring / LAST N; 1·2·4·8 bars); per-door independence. **CHANNEL-PRESERVATION FIX
  (2026-08-22, `a3373ad`): a channel-filtered door replayed SILENT — `DoorRing` dropped the note channel and the Kernel
  re-stamped OMNI→ch1, so channel-N cells rejected the loop; now records+replays the original channel (device
  re-verify owed). A HEALTH-panel diagnostic (`RPLY ENG · LOOP · RPOOL`) was added to bisect it.** Device-ear owed. **RIDERS
  DEFERRED TO A FUTURE VERSION (Paul, 2026-08-21):** (1) OVERDUB = ADD accumulates across passes vs CHORD replace
  (DoorRing accumulate mode); (2) PLAYBACK IS RE-ASKING = RATE (half/double-time) · TRANSPOSE · QUANTIZE-on-playback
  transforms inside `notesSoundingAt(phase)` + per-door controls; (3) THE PROGRESSION REEL = one long harmony take,
  scenes address SECTIONS (scene→beat-window model + longer ring — the big architectural one). Paul walks each directly
  (device steps outrank the doc); interlocks with the UNRATIFIED melody suite (RIFF FOLLOWING) but neither blocks.
- **BURST · PATTERN + CARRY DONE** (2026-08-21, `44ed611`; `AcceptanceCriteria-burst-pattern-carry.md`). BURST gained
  the MODE radio ONCE|COIN|PATTERN (byte-identical default ONCE): COIN = seeded chance-of-burst per step
  (`burstCoinFires`); PATTERN = the 8-slice pick-then-paint B/C/R row, CARRY = span-stretch (the roll's strikes+curve
  redistribute across the burst slice + its contiguous CARRY run, `burstCarryRun`; CELL = S/8 slices in the column, ROW
  = the 8 columns; ROTATE). Shared `layBurst` (no render-path alloc); fuzz randomises mode/slices/rotate (no stuck
  notes); +3 tests; oracle confirms ONCE byte-identical. **RATE axis deferred** (the fixed 8-slice = SPAN geometry
  covers v1 — `burstRate`/`burstRateBeats` fields exist, unused). **DEVICE ear owed** on the carry feel.

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
- **REEL DEFERRALS — design answers (ferry `REPLY-reel-scope-answers`, 2026-08-26; scope pre-agreed, build when convenient):**
  - **#3 boundary handoff + roll-follows-reel** — device-paced is right; the switchover is BOUNDARY-deferred and the roll's
    source flips ATOMICALLY with playback (never half-live/half-reel). Build with Paul on device.
  - **#5 REVISIT (per-pass state restore)** — the snapshot = the FULL DOCUMENT STATE, captured at each pass boundary into
    the ring beside the emissions. ⚠ MEASURE the real size first (32 × KB-class); if fullState is heavy on device,
    delta-chain from the previous snapshot (fallback PRE-APPROVED — no second design pass). RESTORE = load the snapshot as
    ONE FORWARD EVENT (one undo step; the tape rolls through; history never rewrites). Nothing else restores (transport/host
    untouched). [increment 1 already landed a live-switch restore of the play-grid arrangement; this is the full-state v2.]
  - **#6 the acts log (per-pass change badges)** — stamp every UNDOABLE ACT with the pass index current AT COMMIT (acts only —
    never navigation/selection/view; undo/redo ARE acts). Entry = {passIndex · short label ("ARP RATE" · "BANK→3" · "+RTC") ·
    the act's machine HUE, or nil for scene-level}. Keep the FULL per-pass bucket (a detail line will want it); the pass CHIP
    renders the FIRST entry tinted by its hue (neutral ink when nil). Empty bucket = unlabelled chip. Build when convenient.

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
- [x] ~~**MOSAIC §2 — THE CREST**~~ — DROPPED 2026-08-23 (Paul): the whole MOSAIC cell face was removed (it was dead on
  the main grid since the piano-roll face won 2026-08-19). The crest follow-up is moot; the piano-roll face is the cell
  visualisation now. `AcceptanceCriteria-mosaic-face.md` deleted.
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

- [ ] **RATIFIED 2026-08-22 (Paul's word) — `Docs/processor-pairings.md` §7 ① and ② are BUILD ORDERS (IN PROGRESS):**
  - [x] **① GLIDE AFTER A MONO DRIVER — v2** (`processor-pairings.md` §7 ①) — **LANDED 2026-08-22, macOS 827 green,
    iOS builds; DEVICE ear owed.** `[driver→GLIDE]` — the driver's notes feed GLIDE's mono voice (steps bend over
    `glideTime`, leaps past RANGE re-anchor/clamp, column-exit/key-release ends the phrase). `emitDriverNote` records +
    suppresses the driver note (keyed by `currentCellIndex`); a post-tick `emitGlideDriven` pass drains the targets into
    the shared `glideVoices` (flushGlide/phrase-end/no-stuck-notes cover it). Generic across ALL drivers, not just
    ARP/CASCADE. +2 RouterTests. Multi-emitter fan-out stays a SEPARATE deferred v2 item.
  - [x] **② ECHO MID-CHAIN** (`processor-pairings.md` §7 ②) — **DRIVER-PATH LANDED 2026-08-22, macOS green, iOS
    builds; DEVICE ear owed.** The ferry's "existing birthstone stands ready" was WRONG — no ROUTE chip existed; built
    from scratch. NEW `EchoRoute { direct, chain }` (append-only, `.direct` default = byte-identical). CHAIN: each echo
    repeat is re-folded through the stages AFTER the ECHO slot at ITS OWN beat (`refoldEchoRepeat` in `drainEchoTails`,
    which now takes `box`; the `EchoTail` carries `route`/`cellIdx`/`echoSlot`). `emitDriverNote` registers CHAIN tails
    from the pre-post-echo set. `[ARP→ECHO→LENGTH]` = repeats choked/tied by the slice they land in · `[ECHO→SPLIT]` =
    thinned by register/velocity · `[ECHO→HARMONIZE]` dressed per repeat. +1 RouterTest. ROUTE chip in the echo box.
    **NON-DRIVER HOLD PATH LANDED 2026-08-23** (macOS green incl. fuzz, iOS builds): hold-tail `[ECHO→HARMONIZE/SPLIT]`
    `chainEchoParams` block made ROUTE-aware; `[ECHO→LENGTH]` (registered ZERO echoes — swallowed) now registers via
    `registerLengthChainEcho` (from `emitEchoColumn`) + an `echoMuteDry` guard. +3 tests + fuzz echo-CHAIN randomizer.
    An adversarial-review workflow caught 2 bugs (FREE+MUTE silence regression → free-timeBeats fix; SPAN=ROW dry/echo
    divergence → refold honors lenSpan). v1: hold-tail block stays synced-only; MUTE not honored for hold-tail echo.
  - [ ] **③ PASSES v2 — the per-lap switchboard** — STILL CAPTURED, NOT ratified. Do not build until Paul's word.

- [x] **THE UTILITY SET — OCTAVE·TRANSPOSE·CHANNEL·NUDGE — LANDED 2026-08-22** (`AcceptanceCriteria-utility-set.md`;
  ferry-ratified). New UTILITY catalog group; 4 simple per-chain transforms. OCTAVE/TRANSPOSE = pitch-shift set
  transforms; CHANNEL/NUDGE = note-transparent emit overrides (byte-identical when unset). +6 RouterTests; macOS green
  incl. fuzz; iOS builds. DEVICE eye/ear owed. **Echo tails now INHERIT the cell's channel/nudge (2026-08-23 review
  sweep) — [CHANNEL→ECHO] echoes on the cell's channel; the earlier "wire defaults" v1 limit is resolved.**
- [ ] **RATIFIED 2026-08-22, UI-HEAVY — captured, DEVICE-owed (built off-device is not meaningful; need Paul's eyes):**
  - [~] **THE GRID SELECTOR** (`AcceptanceCriteria-grid-selector.md`) — **v1 LANDED 2026-08-23** (iOS builds; UI-only,
    device eye/ear owed). Full-page 8×8, each cell = a complete MIDI chain; the active cell shows a piano-roll of its
    output (hue tiles otherwise); QUANTIZE defaults to INSTANT; tap = live audition vs
    current input (mutually-exclusive, QUANTIZE STEP|INSTANT); COMMIT overwrites the arrival row's chain (one undo) /
    CANCEL restores the pre-open voice; RIGHT column = read-only chain; the reel records it. Banks v1: **DEALT** (64
    seeded, off-thread + RE-DEAL) + **MY LIBRARY** (saved+factory by section). Built understand→implement→review (a
    4-lens adversarial review caught + fixed 7 bugs). **DEFERRED / for Paul:** FACTORY as its own curated 64-bank (the
    content deliverable); §2 EXCLUSIVE-OFF layering (audition BANDS); stopped-transport audition is silent (inherent,
    a hint shows); the working name pending the no-metaphors pass.
  - [x] **THE IN/OUT TRUTH STRIPS + THE STAGE EYE — LANDED 2026-08-25** (`AcceptanceCriteria-in-out-truth-strips.md`;
    §1 truth strips `98bec19`, §4 stage eye `ff8a350`, idea-24 touch-to-diff `535cae5`). The track is FEATURE-COMPLETE
    (all device-eye owed); v2 sweep items remain (§4 column-aligned sweep · bespoke per-type mechanism art · embed the
    real hero read-only).
    - [–] **§2 AUDITION FALLBACK — REMOVED 2026-08-23** (NOT landed). The reference-chord fallback was deleted entirely
      (Paul: "should never be part of the user experience"); no `refPool`/`refChordDoor`/`setChainReference` in the code.
      The truth strips are now the SOLE cure (the see-it half). Superseded, not shipped.
- [x] **TAP processor — LANDED 2026-08-25** (`2621dd3`, `AcceptanceCriteria-tap-processor.md`, ratified). The mid-chain
  SEND: `ProcessorType.tap` mirrors each passing note to a chosen wire (LEVEL · TO THIS/A/B/C/D · MUTE the dry) then
  passes `cur` through unchanged. +1 test + fuzz. (This was "NOT RATIFIED" — now built; see §3.)

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
- [~] **HARMONIZER hung-note ROOT CAUSE** (user-reported device bug, 2026-07-31) — the §a8b playing-time net auto-clears
  it within ~1 s (safety net, committed). **INVESTIGATED 2026-08-23 (adversarial 4-lens hunt + repro tests):** the
  NORMAL-PLAYBACK harmonize path is CLEAN — all four leak modes (fan-out collision vs refcount · drainDue-vs-strike
  boundary ordering · live interval change without flush · on/off wire divergence via fence/octave/masterKey) were
  traced to safe with line citations, and a repro test (collision {60,67}+7 + mid-sustain interval change) shows the
  sounding set stays refcount-balanced with nothing stuck. The reported transient hung-note was **NOT reproducible
  off-device** → it is device-timing-specific (render-block/note-tracker), still owed a device repro to pin.
  **The hunt DID find + FIX a separate real bug** (`adoptLegatoBus` over-un-marking under a SELF-COLLIDING harmonize
  auditioned via PLAY: THIS CELL — a per-window immortal-voice/refcount leak that machine-guns toward the voice cap;
  62 re-strikes over 94 windows → <6 after the fix, adopt one own+All pair per call). +2 RouterTests. Root-cause work
  is thus advanced but the ORIGINAL device symptom remains open (needs the device repro).

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
