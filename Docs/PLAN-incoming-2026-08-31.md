# PLAN — the 2026-08-31 ferry intake (detailed, no-surprises)

_Code-side implementation plan for the five docs received 2026-08-31, grounded against the current code by three
read-only mapping passes (every file:line below verified). Each feature: what EXISTS · what's NEW · MODEL/ENGINE/UI ·
TESTS · RISKS · EFFORT. Design authority = the merged/added specs; this is the build map. Nothing here is built yet.
**§K lists the decisions Paul must settle before the risky pieces — the "no surprises" gate.**_

## §0 — INTAKE + CLASSIFICATION

**Docs filed:** `INSTRUCTIONS-interface-redesign.md` (MERGED, clean superset +§8/§8b/§9) · `AcceptanceCriteria-scale-door.md`
(MERGED, +§6/§7/§7b) · `INSTRUCTIONS-room-palettes.md` (ADDED) · `OPEN-listening-set.md` (ADDED) · `SPEC-macro-lanes.md`
(ADDED). Both merges were pure append-only supersets of my held copies — no reverts.

**RATIFIED (scale-door §7, 2026-08-29) → buildable:** ▲▼ TRACK-MOVE + GHOSTS (§F) · GRID 8|16 (§E) · MACRO LANES (§D) ·
AVOID (§B) · the SCALE-AWARE IN STRIP (§C). CHORDS/the DYNAMIC REFERENCE (scale-door §4) is **already built** (`d1dc0fc`).

**Already built (verified this pass — do NOT rebuild):**
- THE BAZAAR IS MUTED (select cells → muted greys) — `buildGridSelCell` greyUnlessSel, BuildPage.swift:4602.
- SCALE DOORS NAME THEMSELVES — DONE on the machine-column receiver chip (`buildReceiverSelectChip`, BuildPage.swift:2300
  computes "A MIXO" from `doorModeResolved==.scale`). The ONLY leftover is the MIDI-config **tab bar** (`buildMidiTabBar`
  :186 still shows the plain letter) → §A is now a 1-line follow-up, not a feature.
- THE ROOM PALETTE SIGNATURES — `roomsField` (per-room near-black PLAY vs charcoal, :1466), `roomsDoorBar`/`roomsDoorInk`
  (rainbow/amber/indigo/red door signatures, :1449/:1459), the room tokens `roomsAmber/Indigo/RedSig/RainbowHues`
  (:63-69), the ▲PLAY sliver already INDIGO (cyan retired). §G is now SMALL (below).

**CAPTURED, NOT ratified (do NOT build without Paul's word):** LOCK TO KEY (§H) · the rest of the LISTENING SET beyond
AVOID (SHADOW/FEEL-THIEF/IMITATE/…) · the full rooms/tracks/provenance/footer INTERFACE REDESIGN (§I, Paul-walked).

---

## §A — MIDI-tab scale label (tiny leftover)
`buildMidiTabBar` (BuildPage.swift:179-197) still renders `["A","B","C","D"][i]` at :186. Lift the exact "A MIXO" string
already computed at :2300 (`receivers[i].doorModeResolved==.scale ? "\(names[scaleRootResolved]) \(scaleTypeResolved.label)"`).
NEW: one shared `scaleDoorLabel(_ rec)->String?` (so the chip + tab + any future site agree) + a test. EFFORT: minutes.

---

## §B — THE AVOID PROCESSOR (ratified · engine · listening §4)

Shape: SOURCE = DOOR▾ | WIRE▾ | ALL SOUNDING · WHAT = SAME NOTE | CLASHES(ic1; ic2 stricter) · ACTION = SKIP (re-pick next
pool candidate, density kept — default) | SHIFT (nearest safe tone) | REST. Pure, per-candidate, pre-emission; politeness
not counterpoint. **Reuses the KEY-FILTER law; is a set-FILTER like SPLIT (not a driver, not identity/emit-side).**

**EXISTS (verified):**
- `keyFilterNote(note, refMask, only, snap)` — Derivations.swift:628-641 = the SHIFT (snap→nearest legal) / REST (nil) core.
- `NotePool.pitchClassMaskAll()` (Derivations.swift:356) + `pitchClassMask(chanMask:cableMask:noteLo:noteHi:)` (:363) — for
  a DOOR source (`latchedPools[door].pitchClassMaskAll()`; live via `effectivePool`).
- `emitterSounding(bus)` (Router.swift:157) + the CONVERSATION/HOCKET wire-listen pattern (`convLead` :155, read :1211;
  hocket :3145-3174) — the model for WIRE/ALL-SOUNDING; the row-order tie rule (`for row in 0..<Snap.rows`) IS the settled
  "later chain defers."
- The SPLIT hook precedent: upstream `applyStage` (Router.swift:3458, `case .split` :3517-3525); downstream `emitDriverNote`
  (:3592, LENGTH/SPLIT-downstream :3639-3676); hold path `emitColumnHolds` (:1522).

**NEW — engine:**
- A voice-table pitch-class scan `soundingPitchClassMask(bus: Int?)` (nil = ALL) — `pitchClassMaskAll` lives only on
  NotePool, so ALL SOUNDING / WIRE genuinely need this new scan (trivial, patterned on `emitterSounding` :157).
- `avoidRefMask` = the avoided classes (ALL-SOUNDING voice scan · DOOR pool mask · WIRE bus scan), widened by WHAT
  (SAME = the class; IC1 = ±1; IC2 = ±2 pitch classes). Pure + tested.
- The per-candidate decision, split by chain position (the SPLIT precedent): **upstream `[AVOID→ARP]`** = re-pool (drop
  notes whose class ∈ refMask → the driver walks survivors = SKIP, density kept) via a NEW `case .avoid` in `applyStage`;
  **downstream `[ARP→AVOID]`** = per-emitted-note REST(drop)/SHIFT(`keyFilterNote snap`) in `emitDriverNote` before
  `emitChop`; **hold path** = filter in `emitColumnHolds`.

**NEW — model + surface (~14 sites, mirror HOCKET, all verified):** `ProcessorType.avoid` (Models.swift:9, after :33) ·
`ColourParams.avoidSource/avoidWhat/avoidAction` + enums (Models.swift ~:344 hocket block) · `SnapParams` mirror
(Snapshot.swift ~:234) · builder copy (SnapshotBuilder.swift ~:395) · **`CellMode.avoid`** (Derivations.swift:1182 +
mapping :1403, like `.split` — NOT `.identity`) · `emblemSymbol` (:1576, "hand.raised") · `typeDescription` (GridUI:848) ·
`typeParams` editor (GridUI:1493, SOURCE/WHAT/ACTION segs) · `buildCatalog` card in DYNAMICS/CONTROL (BuildPage:4303) ·
`buildProcLabel` self-name (:4335) · `macroParamsForProcessor` note-transparent list (MacroAuthoring:214) · fuzz roster
(FuzzTests:69) + randomizer (:94) · Dice `fWord` only, NOT the drivers set (:502/:515) · NOT `isDriverType` (:3210).

**TESTS:** pure `avoidRefMask` (ALL/IC1/IC2) · `[AVOID→ARP]` walks only the complement · `[ARP→AVOID]` REST drops vs SHIFT
remaps vs SKIP keeps count · determinism · fuzz for no-stuck-notes across upstream/downstream/hold placements (like SPLIT).

**RISK:** ⚠ **SKIP has no clean DOWNSTREAM meaning** — downstream a note is already chosen; "re-pick the next candidate"
would need to re-enter the driver's picker (`arpPick`), which `emitDriverNote` can't. So downstream SKIP collapses to REST.
The clean resolution is the SPLIT law (re-pool before / punch-holes after) → **SKIP is an UPSTREAM behaviour; downstream is
REST|SHIFT only.** This must be settled (see §K1). Otherwise: bounded re-pick (whole-pool-avoided → REST, no loop); the L1
row-order caveat (put the avoider on a later row than its source, same as HOCKET). **EFFORT:** 1 focused session after §K1.

---

## §C — THE SCALE-AWARE IN STRIP + self-naming AVOID CLASHES stage (ratified · thin UI over §B)

Scale-door §6/§7/§7b: a SCALE-door chain's IN strip shows "A MIXOLYDIAN — the full palette" + a `PLAY: ALL NOTES | AVOID
CLASHES` chip + a `change key →` jump-link; arming AVOID CLASHES **materializes a slot-resident AVOID stage** (ALL SOUNDING
· SKIP), self-named "AVOID CLASHES" (§7b: the strip chip = the switch, ALL-SOUNDING only; the A–D/WIRE source pick lives in
the stage's panel).

**EXISTS:** `buildTruthStrips` IN|OUT band (BuildPage.swift:3894-3926; IN reads the door at :3895, the scale-label logic at
:2300 to reuse); chain write `buildApplyChain` (:4197) + `buildChainAddCard` (:4351). **So §C = insert/remove a preset
`.avoid(ALL,SKIP)` slot + a scale-aware readout — a THIN UI layer, NO new engine.** It cannot land before §B.

**NEW:** the IN-strip scale branch (BuildPage.swift ~:3903, when `door.doorModeResolved==.scale`) + the arm/disarm chip
that adds/removes the AVOID slot. **TESTS:** a pure "arm → chain contains one AVOID(ALL,SKIP) slot." **EFFORT:** short, after §B.

---

## §D — THE MACRO LANES (ratified · the render-time path is the real work)

`SPEC-macro-lanes.md`: a collapsible per-PART strip below the part grid; ≤4 lanes; each = TARGET macro 1–8 · CURVE
(slider-lane widget OR WAVE chip SINE/TRI/RAMP/SQUARE+rate) · SPAN 16/×2/×4 multi-pass sweeps; boundary-deferred; saved
with the part. PART-scoped (vs MOD's chain-scoped step/lanes).

**EXISTS + THE GAP (verified):** the offset engine folds `applyMacros(sc.procs[k], mods, values: macroVals)` at BUILD
(SnapshotBuilder.swift:112-118), where `macroVals` = the RAW MANUAL value (:37) — **a publish-time BAKE**. `box.macroValues`
is carried (Snapshot.swift:311) but **NEVER read by Router/Kernel**. `laneValue` (Derivations.swift:216) has **ZERO
callers**. The MOD WAVE math (`modUnipolar`, :74) is reusable for a WAVE curve. **So the whole per-column macro sweep is
unbuilt.** A single-lap (SPAN=1) lane could bake per-column at publish (each column is its own SnapCell), but **multi-pass
×2/×4 differs per lap and is unknowable at publish → the headline "LFO over four laps" REQUIRES a new render-time
modulation path** (Router reads a per-column/per-lap macro value and folds the offset there, not at build).

**NEW:**
- MODEL: a NEW `MacroLane` struct on `BuildPart` (BuildModel.swift:9; add to memberwise + the decode-tolerant init :103-122;
  persist via `BuildUnassignedData` :34 → `buildCaptureUnassigned` :3078 / `buildRestoreUnassigned` :3102, riding the rate/
  length precedent :3085). Fields: target macro 0–7 · curve (DRAWN slider-values | WAVE shape+rate) · span 1|2|4. (Do NOT
  overload the old `Macro.lane*` fields — they're the retired TIMELINE shape, no WAVE, no 16/×2/×4.)
- ENGINE: the render-time per-column macro value. Two options (§K2): (a) build a per-COLUMN macro-value table in
  SnapshotBuilder and move the `applyMacros` fold into the render column loop; (b) carry the lane/WAVE spec on the box and
  evaluate `laneValue`/`modUnipolar` in the render loop. Either way alloc-free (fixed scratch), derived-not-accumulated.
- SCOPE (§K2): lanes are part-scoped but macros are DOCUMENT-global (PluginState.macros). A lane must drive a PART-LOCAL
  render-time macro override scoped to that part's ROWS — never write `Macro.value` (else two parts on the same macro fight).
  The builder already keys targets by `(col*Snap.rows+row)*64+slot`, so a part = a row-set — the scoping fits.
- UI: a collapsible band below the part grid (RoomsPage.swift:239 `roomsPart` / after BuildPage.swift:1801). **The
  `sliderLane`/`stateMatrixRadio` widgets are PRIVATE to `ProcessorBox` (GridUI.swift:1624/:1593)** → the reuse mandate
  requires EXTRACTING them to a shared standalone view (parameterize the `accent`/`liveStep` context) — a NEW refactor, not
  a duplicate. Reuse the SPAN ladder (`spanLadderField`) + the e-brush (`EBrushButton`).

**TESTS:** per-column lane value (DRAWN via `laneValue`; WAVE via `modUnipolar` at the column beat; SPAN ×2/×4 across laps)
· the offset folds per column · round-trip persistence with the part. **RISK:** medium-large (render-time path on the hot
loop). Works at grid-8; richer at grid-16. **EFFORT:** 1–2 sessions after §K2.

---

## §E — THE GRID 8|16 SETTING (ratified · ⚠ gated by an index-width refactor)

A document part-grid WIDTH: 8 or 16 columns. **THE HARD CONSTRAINT (verified):** cells key by `col*Snap.rows+row`
(Snap.rows=16). At 8 cols the max index = `7*16+15 = 127` = exactly `Int8.max`; **at 16 cols = `15*16+15 = 255`.** Precise
ceilings that OVERFLOW at 16:
- `Voice.cellIndex: Int8` (Router.swift:54) traps at `Int8(currentCellIndex)` (:790) → **widen Int8→Int16** (the
  `SnapCell.colourIndex` CR-13a precedent).
- `cellSounding` = 2×UInt64 = 128 bits (Router.swift:240, packed :864-869 with literal `<64`/`-64`) → **256 cells need
  4×UInt64** + de-hardcode the literals.
- tap/solo/tapAlt masks pack `col*8+row` in ONE UInt64 (Router.swift:418-433; Kernel:70-85; AU :283/:325/:351): 8 cols max
  `7*8+7=63` fits; **16 cols max `15*8+7=127 > 63` → widen to 128-bit** + widen `setSoloCellMask`/`setAudition` signatures.
- feed arrays sized `Snap.cells`=128 (VC :376-390) → 256 (auto via `cells=cols*rows`, but audit hardcoded `<64`/`128`).
- `Snap.cols` is a `static let` used at ~50 sites → **recommend ALWAYS-16 allocation (Snap.cols=16) + a per-document
  "active width" governing only loop-length + the UI column count** (option a) — far safer than threading a runtime width
  through Builder/Router/Kernel. `iterateTicks(columns:)` (:1926) is already parameterized (a good hook).
- NEW: `PluginState.gridCols` (additive-Optional) · a 1..16 loop-length control (the old 1..8 one was removed; only the
  RATE menu survives) · the part-grid UI ForEach column loops (BuildPage :1790/:1796). Play-layer stays dimensionally
  disjoint (16×16=256) but blows the same ceilings.

**Playbook:** this is the SAME class as the 64→128 row widening done 2026-08-30 — follow it (widen the index space →
add the setting → the UI). **RISK:** HIGH (render hot path + persistence). **EFFORT:** 2–3 sessions, staged. Do LAST of the
ratified batch, after §K3.

**REFINED ANALYSIS (2026-08-31, Paul approved the refactor):** the widening is INSEPARABLE from the cols=16 flip — at
active-width 8 nothing overflows (index ≤127, masks ≤63), so widening the masks/cellSounding is only EXERCISED when cols
8–15 actually render. That flip changes what the render produces (16 columns), which needs Paul's DEVICE to verify. So the
staged plan is:
- **STAGE 1 (DONE unattended, byte-identical, verifiable off-device):** `Voice.cellIndex` Int8 → Int16 (Router.swift:54/790)
  — removes the single flagged latent ceiling ("16 is this field's limit"), a no-op at cols=8, full suite green.
- **STAGE 2 (Paul-present, device-verified — the flip + its widenings):** `cellSounding` 2→4 UInt64 (de-hardcode `<64`/
  `-64` at Router:864-869) · the tap/solo/tapAlt/audition masks UInt64 → 128-bit (Router:418-433, Kernel:70-85, AU
  :283/:325/:351, widen `setSoloCellMask`/`setAudition`) · the `Snap.cols` static-let → the always-16-allocation +
  per-document active-width (option a) · the feed arrays 128→256 (audit `<64`/`128` literals) · the UI `ForEach(0..<8)`
  column loops · a 1..16 loop-length control. Each byte-identical at active-width 8; the cols=16 rendering is the device check.

---

## §F — ▲▼ TRACK-MOVE + GHOST PREVIEWS (ratified · UI · redesign §9)

FOCUS-FOLLOWS-TOUCH · a ▲▼ pair SWAPS the focused track with its neighbour (swap, never shift; one undo each) · GHOSTS:
landing on a previously-EMPTY column seeds dim/dashed MUTATION GHOSTS of the moved content (tap=commit, else evaporate;
occupied→occupied spawns none; deterministic).

**EXISTS:** the focus concept partly (`buildSelectedPlayCol` :1920, `buildSelectPlayColumn` :1911, a `focused` frame in
`roomsPlayFerry` :1505); the seeded mutation `BuildSceneLogic.mutateChain` (:244, deterministic, distinct, audible) +
`buildNewTabColour` (:3155) to commit a ghost; ghost-render pieces (`buildChainDragGhost` :2473, dashed "+" grammar :2519,
`buildGridSelStampSweep` :4698, `buildGridSelDriftFace` :4636).

**NEW + TWO SERIOUS GOTCHAS:**
- ⚠ **A "track" = a play COLUMN whose state spans TEN parallel `@State` arrays** (AudioUnitViewController.swift:208-223:
  buildPlayCells, buildPlaySel, buildPlayColOn, buildPlayColRecv, buildPlayColEmit, buildPlayColLen, buildPlayColSteps,
  buildPlayColRate, buildPlayColStepRecv, buildPlayColStepEmit). A swap MUST `.swapAt(a,b)` **all ten together** — a NEW
  `buildSwapPlayColumns(a,b)` (miss one → silent desync). Then `buildPublishScene()` + one undo.
- ⚠ **UNDO DOES NOT COVER THE PLAY GRID** — `BuildSnapshot` (BuildPage.swift:75) / `buildCaptureSnapshot` (:2731) /
  `buildApplySnapshot` (:2755) touch NONE of the buildPlay* arrays. §9's per-press undo needs **ten new snapshot fields**
  across struct+capture+apply (in-pattern fix; see §K5). (Play-grid persistence via `BuildPlayGridData` is orthogonal.)
- ⚠ **SPEC AXIS/GLYPH AMBIGUITY** — §9 says "▲▼" + "Track 3 → row 6", but tracks are COLUMNS (horizontal). The doc is
  "captured, awaiting his word." Assume adjacent-COLUMN swap (c↔c±1) with a confirm (§K4).
- GHOSTS: no commit-on-tap precedent — NEW `@State` (a `[col:[slot:chain]]` ghost map) + dim/dashed render + evaporate-on-
  next-action; depends on the slot-column model (the redesign's future) → v1 may be a single ghost or deferred.
- FOCUS: extend the subtle frame to `roomsPlayCell`/`roomsPlayBottom` via `buildSelectPlayColumn`.

**RISK:** medium (the atomic ten-array swap + the missing play-grid undo). **EFFORT:** swap+focus = 1 session (incl. the
undo fields); ghosts = follow-up gated on the slot model. Part of the incremental redesign — walk with Paul.

---

## §G — ROOM PALETTES / WAYFINDING (ratified · MOSTLY DONE — small remainder)

The signatures + per-room field + door bars + muted select cells + scale-key chip are **already built** (§0). Remaining NEW:
- **Per-room CHROME accent tint (§8b):** chrome washes/handles/lit-state still use `buildCyan` (e.g. `roomsPartRightRail`
  :1841, `roomsSelectPage` :1653). Add a `roomsRoomAccent(_ room)->Color` token (AMBER on PART · INDIGO on PLAY ·
  neutral-white on SELECT · RED on REEL) and thread it through the per-room chrome. NEW token, mechanical thread.
- **The §4b TEN-button provenance bottom band** `[SELECT][8 provenance doors][PARTS]` — NOT built (today: 8 transport
  buttons `roomsPlayBottom` :1997 + two `navDoor`s in a separate HStack RoomsPage:262). Its corner doors (rainbow/amber) +
  per-track provenance-mark home doors (following the lit slot, §4c) are NEW — this is genuinely part of the interface
  redesign (§I), build with Paul.
- Optional: the scale-key on `buildMidiTabBar` (§A).

**RISK:** low (colour; device-screenshot-per-room is the acceptance test). **EFFORT:** the accent token = short; the bottom
band = a redesign slice with Paul.

---

## §H — LOCK TO KEY — ✅ SUBSUMED into §B (2026-08-31)
Paul unified LOCK TO KEY with AVOID: LOCK is just AVOID's `MODE = lock` (`keyFilterNote only:true`) with a KEY reference,
placeable anywhere (incl. the chain END). Built as part of §B (`7c60dac`) — the "LOCK TO KEY" storefront card = AVOID(kind:
key, mode: lock, action: move). No separate processor. (Historical sketch below.)

## §H(old) — LOCK TO KEY (the pre-unification sketch, kept for the record)
Scale-door §7/§7b: an END-of-chain force-to-key output filter (declared/referenced key + REJECTS BLOCK|SNAP, seated at the
chain END; self-named "LOCK: A MIXO"). Mechanically it is **AVOID with `keyFilterNote(only:true, snap:)`** at the chain tail
(the LENGTH-override pattern at Router.swift:3666-3676 shows "last stage overrides the note"). A shared `.avoid`/`.lock`
filter core could serve both. **HOLD** until Paul ratifies.

---

## §I — THE INTERFACE REDESIGN (umbrella — build INCREMENTALLY with Paul)
§1–§8 (rooms/tracks/provenance/footer stack/shared header/seams/voice laws). Large surface-geography change; device steps
outrank prose; ★ reuse existing components (never approximate — if you'd approximate, STOP and ask Paul). §F (▲▼/ghosts),
§G (the accent token + the §4b bottom band) are its first concrete ratified slices; the rest lands as Paul walks it.

---

## §J — RECOMMENDED SEQUENCING
1. **§A** MIDI-tab scale label — minutes.
2. **§B AVOID** (after §K1) — self-contained engine; unblocks §C.
3. **§C** scale-aware IN strip — thin UI over §B; ship together.
4. **§G accent token** — independent UI slice.
5. **§F swap+focus+undo-fields** (after §K4/§K5) — ghosts deferred to the slot model.
6. **§D MACRO LANES** (after §K2) — extract the widgets, add the render-time path, the MacroLane model + UI.
7. **§E GRID 8|16** (after §K3) — LAST; stage the index-width widening first (the 64→128 playbook).
8. **§H LOCK TO KEY** — HOLD (not ratified).
Cross-cutting: render reads only SnapshotBox · derived-never-accumulated · no alloc/locks on the render path · no stuck
notes · NEW param addresses only · additive-Optional + decode-tolerant models · tests off-device first, device owed on UI.

---

## §K — DECISIONS PAUL MUST SETTLE (the "no surprises" gate)
1. **AVOID SKIP downstream (§B).** SKIP ("re-pick next candidate, density kept") only has clean meaning UPSTREAM (re-pool).
   Proposed: SKIP = upstream behaviour; downstream `[ARP→AVOID]` offers REST|SHIFT only (the SPLIT law). Confirm, or specify
   what downstream-SKIP should do.
2. **Macro-lane render path + scope (§D).** (a) build a per-column macro table + fold in the render loop, or (b) carry the
   lane/WAVE spec on the box and evaluate in the render loop? AND: confirm lanes drive a PART-LOCAL render-time override
   (scoped to the part's rows), never the document-global `Macro.value`.
3. **Grid 8|16 allocation (§E).** Confirm ALWAYS-16 allocation (Snap.cols=16 always; an "active width" governs loop-length
   + UI) rather than a runtime width threaded through the engine. And confirm this is a per-DOCUMENT setting.
4. **▲▼ axis/glyph (§F).** Tracks are columns (horizontal) — is the move an adjacent-column swap? Glyph ▲▼ vs ◀▶? ("row 6"
   wording vs the column model.)
5. **Play-grid undo (§F).** OK to add the ten play arrays to `BuildSnapshot` (so play-grid edits — swaps, and future
   ferries — become undoable in-pattern)? (Today the play grid has NO undo coverage — a pre-existing gap this surfaces.)
