# PLAN — incoming ferry 2026-09-01 (macro-automation · CHORDS)

Grounded implementation plan for the two docs merged this intake:
`Docs/INSTRUCTIONS-macro-automation.md` (RATIFIED) and `Docs/SPEC-chords-stage.md` (CHORDS ratified;
its three MODES + voicing await Paul's ratifying word — §2 degree matrix is canon). File:line anchors
are current as of this date; re-grep before editing. Read this before building either.

---

## §A — THE MACRO AUTOMATION SYSTEM (the bigger lift)

### What ALREADY exists (the offset engine survives; the old UI was retired)
- **Model** — `Macro { name·value·fixed·targets[] }` (`Models.swift:935`), `MacroTarget { col·row·slot·param·delta }`
  (`Models.swift:914` — note the target already carries a **cell** col/row), `MacroEmitterTarget` (emitter params),
  `MacroKind { slider, button, timeline }` (`Models.swift:909`). `PluginState.macrosResolved` = 24 macros
  (`Models.swift:1209`); `macroKind(i)` banks **0–7 = slider · 8–15 = button · 16–23 = timeline** (`Models.swift:1211`).
- **The fold** — `applyMacros(p, mods, values)` (`Snapshot.swift:436`) = `clamp(base + Σ vₖ·deltaₖ)`, folded per cell in
  `SnapshotBuilder` (targets → per-cell `MacroMod`, grouped by col/row/slot). `SnapshotBox.macroValues` = 24 live values.
- **AU + params** — `addMacroTargets`/`removeMacroTargets`/`setMacroValue`/`setMacroName`/`setMacroFixed`
  (`MidiSparkAudioUnit.swift:860+`, currently zero-ref reserved surface) + the host-automatable param bank `400+i`.
- **Pure authoring registry** — `MacroAuthoring.swift` (`MacroControlKind`, `MacroControlParam/Group`, `macroSparseDelta`,
  `macroApply`, `macroSlotBindings`, `processorValues`/`applyProcessorValues`), unit-tested (`MacroAuthoringTests`).
- **GONE** — `MacroPanel.swift`/`MacroAuthoringView.swift`/`MacroBindPopup` (old-UI sweep). The 4-tab band is a NEW surface.

### What's NEW in the ratified spec (the delta to build)
1. **Two species, sixteen macros.** Keep 8 SLIDER (0–7) + 8 TOGGLE (8–15, the `button` kind); **retire the 8 timelines
   (16–23)** — spec is "16 named movements." A TOGGLE gangs several params into one named MOVE (OFF=base · ON=the bound
   offset); its ON value is set at BIND time. Model: mostly there (`MacroTarget` gangs params already; `Macro.value` is the
   slider ride / toggle 0|1). Add a per-macro **ON-value** for toggles if the offset alone isn't enough (likely the delta IS
   the ON value → `value` 0|1 suffices; confirm at build).
2. **Per-CELL and per-SPAN application — the real new ENGINE bit.** Today a macro has ONE global value (`macroValues[i]`)
   applied everywhere its targets land. PUNCH/SPAN need the macro's *value* to vary **per cell** (PUNCH draws a per-cell
   value/state; SPAN draws a sweep across an extent). Plan: a per-cell macro-value store (a `[macroIndex] → per-cell grid`,
   like `buildStagingCells` but Double/Bool), resolved in the fold as **per-cell value ?? the global PLAY value**. Two clean
   options — (a) fold into `SnapCell` a resolved `macroValueOverride[16]` the builder fills from the grid (render reads the
   box, invariant 1), or (b) keep macro values global + let PUNCH/SPAN write the per-cell *targets'* delta scale. (a) is
   cleaner + matches the state-matrix pattern; **flag as §K1**. Boundary-deferred + drawn=config already hold (the box is
   published on the boundary; the drawn grid is deterministic).
3. **LAYOUT (Paul 2026-09-01):** the whole macro section is **the bottom HALF of the PART grid** — the part grid's INTERIOR
   (the 8×8 cells) is reduced **50% in height**, and the freed bottom half becomes the 4-tab macro band. The **ferry buttons
   (top row), the ▲▼ row cursor, and the STOP button stay at their CURRENT size** (only the interior 8×8 shrinks). So the PART
   page becomes: [ferry row · ▲▼ · STOP — unchanged] → [part 8×8 at 50% height] → [macro band: the collapsible 4 tabs]. Hook in
   `roomsPartGrid` (`BuildPage.swift:1901`) — split its interior height ~50/50 (part cells vs the band); the band only shows on
   `roomsRoom == .part`. The SELECT/PLAY grids are untouched.
4. **The four tabs** (the part-page macro band, collapsible):
   - **BIND** — the chain list, stages self-named (reuse `buildProcLabel`); tap a control → assign to a macro (species+slot;
     toggles set ON here). Reuses `MacroAuthoring` (`macroSparseDelta`/`macroSlotBindings`) + AU `addMacroTargets`. ADD BINDING;
     bindings listed per macro.
   - **PLAY** — 8 pads (toggles) + 8 faders (sliders), hand-ridden → `setMacroValue` (or the tree param 400+i). Grid untouched.
     Reuse the `FineSlider` + haptics.
   - **PUNCH** — arm a macro chip (glow=mode) → tap CELLS → per-cell value/state (needs §A2 store). Tap chip = out. CLEAR (one
     undo). e-brush legal (reuse `EBrushButton`).
   - **SPAN** — arm a macro → the ladder chip (1…16·×2·×4, reuse `spanLadderField`) → apply across the extent (slider spans =
     drawn sweeps; ×-spans = multi-pass breathing). Same glow/exit/CLEAR.
5. **Overrides survive mutate/randomize** (the roll changes the base, not the macro layer) + persistence (the per-cell store
   travels with the document, like `BuildPlayGridData`).

### Increments (each build+test)
- **M1 (model tidy):** formalize 16-macro/2-species (retire timeline in the UI; keep the enum case decode-safe); +tests.
- **M2 (per-cell value store, engine):** the `SnapCell.macroValueOverride` fold + builder fill + a Router/builder test
  (a PUNCH-drawn per-cell value shifts one cell's param, not its neighbours). Byte-identical when unset. **This is the load-
  bearing increment** — do it first + test hard.
- **M3 (BIND + PLAY tabs):** the band shell + BIND (tap-to-assign, gang, ON-value) + PLAY (pads+faders). UI, device-owed.
- **M4 (PUNCH):** arm→tap-cells→draw per-cell (reads M2), CLEAR, e-brush.
- **M5 (SPAN):** arm→ladder→sweep/×-pass (reads M2 + spanLadder), CLEAR.
- **M6 (persistence + mutate/randomize survival).**

### Risks
- The per-cell value store (M2) is the only real engine change; everything else is UI over the existing offset fold. Keep the
  render reading ONLY the box (invariant 1). · Boundary-deferral is free (publish on the boundary). · Watch the 24→16 bank
  change against saved docs (timeline macros in old docs must decode harmlessly — keep the enum case).

---

## §B — CHORDS (the diatonic-progression stage) — build AFTER Paul ratifies the modes

### The thesis (cheap by construction)
A diatonic chord = **rank arithmetic on the scale pool**: degree n = pool-steps {n, n+2, n+4} (stacked thirds; quality falls
out of the key). No chord stored — progressions are DERIVED. Requires a scale-class pool upstream (the SCALE door, or KEYS).

### What it REUSES (little new engine)
- **Scale pool** — `scaleNotes(root,type,baseOct,octaves)` (`Derivations.swift:604`) + `scalePitchClassMask(root,scale)`
  (`Derivations.swift:656`) + `ScaleType` + `DoorMode.scale`. The degree indexes into this pool.
- **Pedal machinery (FOLLOW)** — `lastReferenceMask` / the §4 CARRY PIN (`Kernel.swift:466`, reset on transport start
  `:824`), first-note-per-window, SEED SOUNDING|STRIKE, the register FOLD — exactly what AVOID's door-live reference uses;
  `doorLivePitchClassMask(r)` (`Router.swift:174`) reads another door's live notes. FOLLOW = the source door's note NAMES the
  degree (its rank in the scale).
- **State matrix (PATTERN)** — `stateMatrixRadio(...)` (`GridUI.swift:403/585/718`) → the §2 DEGREE MATRIX: **8 rows = I–VII +
  REST**, radio-per-column, **empty column = CARRY the previous chord**, quality-aware self-updating headers (I·ii·iii°… from
  the declared key), ROTATE ◀n▶ + SPAN (reuse `spanLadderField`) + e-brush.
- **Set-shaper integration** — CHORDS is a HARMONY transform (per-WINDOW, one degree → a chord SET), NOT a tick driver. Wire
  it like `harmonize`/`split`: `applyStage` (upstream fold) + `emitColumnHolds` (hold path). NO new driver dispatch
  (`isDriverType` `Router.swift:3366` unchanged). Downstream composes: `[CHORDS→STRUM]` raked · `[CHORDS→ARP]` arpeggiated ·
  `[CHORDS→drone]` the pad bed that follows the bass finger.

### What's NEW
1. **`ProcessorType.chords`** (append-only) + `cellMode` + emblem/desc/typeParams + a storefront card (HARMONY group).
2. **Pure core (Foundation-only, unit-tested):** `diatonicChord(degree:pool:voicing:)` — {n,n+2,n+4} pool-steps, +7th/+add9
   (one more third), CLOSE|OPEN (octave-lift the middle), INVERT-toward-previous (nearest inversion — voice-leading by
   construction). Plus `walkNextDegree(seed:prev:weights:)` — the gravity dice (tonic pulls home · dominant resolves ·
   subdominant wanders). Both pure → tested from the concept.
3. **MODE** FOLLOW|PATTERN|WALK · **VOICING** TRIAD|7TH|ADD9 · **SPREAD** CLOSE|OPEN · **INVERT** toward-previous ·
   **WINDOW** CELL|ROW|BAR (the span family). Additive-Optional SnapParams; nil ⇒ a sensible default so a fresh CHORDS plays.

### Increments
- **C1 (pure core + tests):** `diatonicChord` + `walkNextDegree` + the quality-aware degree label — no engine wiring; the
  music theory is locked first (the AVOID/oracle pattern).
- **C2 (PATTERN mode):** the state-matrix degree panel + `applyStage`/hold integration reading the SCALE-door pool → a drawn
  progression plays in any key. +RouterTest (the same matrix plays Cm vs F correctly).
- **C3 (FOLLOW mode):** the door-note → degree read via the pedal machinery (kin to AVOID's door-live ref) + CARRY. +test.
- **C4 (WALK mode):** the seeded gravity walk (replay-exact, like the ratchet-coin seed). +test.
- **C5 (voicing/window polish + downstream composition checks).**

### Risks
- FOLLOW inherits AVOID's L1 later-row caveat (read a door's live notes SO FAR this render → put CHORDS on a later row than
  the source). · The quality-aware headers are UI theory (self-updating from the key) — keep the pure label fn tested. ·
  WALK must be seeded/replay-exact (no accumulated RNG across renders — derive from the window/step index).

---

## §J — SEQUENCING
1. **Macro-automation M1→M2 first** (the per-cell value store is the one real engine change; land + test it before any tab UI).
2. Then M3→M6 (the four tabs), device-verified per tab — **NO PLAY tab as a play-page thing** (K1 ruling: macros never touch the
   PLAY page). The band's four tabs (BIND · PLAY-ride · PUNCH · SPAN) all live on the PART page; "PLAY" here = the hand-ride
   surface INSIDE the part-page band, not the PLAY grid/room.
3. **CHORDS is RATIFIED (all three modes) — buildable.** C1 (pure core + tests) first, then C2 PATTERN · C3 FOLLOW · C4 WALK.

## §K — DECISIONS — ✅ ALL RESOLVED (Paul 2026-09-01)
- **K1 — RESOLVED: macros are a PART-PAGE-only feature; NOT on the play page.** The per-cell amount grid (option **a**, my
  recommendation — a per-cell value resolved into the cell, fed by PUNCH/SPAN, falling back to the ride amount) stands, **scoped
  to the PART grid (rows 0–7)**. No macro store/UI/application reaches the PLAY grid (rows 8–15) or the SELECT grid. The amount
  grid lives per-part (on `BuildPart` / the part model), not spread across every SnapCell.
- **K2 — CONFIRMED: a toggle is a binary gate on the bound offset.** ON = base+offset · OFF = base; `Macro.value` ∈ {0,1}
  suffices; no separate ON magnitude. One mechanism serves both species (a toggle is a slider pinned to {0,1}).
- **K3 — RESOLVED: RETIRE the 8 timeline macros.** The bank is 16 (8 slider + 8 toggle). Keep `MacroKind.timeline` decode-safe
  for old docs (no real doc holds timeline data — the species was never built), drop it from the bank/UI.
- **K4 — RATIFIED: all three CHORDS modes** (FOLLOW · PATTERN · WALK) + voicing (TRIAD|7TH|ADD9 · CLOSE|OPEN · invert-toward-
  previous). Build order C1→C2(PATTERN)→C3(FOLLOW)→C4(WALK).
