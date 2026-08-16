# MidiSpark — Codebase Review (2026-08-16)

A whole-repo review: the **purpose** of each part, what can be **improved for clarity**, what can be
**refactored**, what **tests** are missing, and what I'd **do differently starting again**. It was produced by
reading every source file (≈19k lines of app code across 32 files + ≈8.7k lines of tests), grouped into seven
subsystems, plus the two bugs fixed in this session (a render-thread `SIGTRAP`; a stale column-lap silently gating
the BUILD audition) used as ground-truth calibration.

Line references are `file:line` and were accurate at the time of writing; treat them as signposts, not addresses.

---

## 0. TL;DR

**The engine and the pure-math layer are excellent** — broad, invariant-driven, honestly commented, and heavily
tested (RouterTests ≈251 cases, DerivationsTests ≈172, all exercising the *real* Router behind a recording
`MIDIEmitter`). This is the strongest asset in the project and the reason the audio is trustworthy.

**The debt is concentrated in three places**, and they rhyme:

1. **The UI/BUILD layer is almost entirely outside the test boundary.** `BuildPage.swift` (1,815 lines) is the
   most-churned file in the repo and has *near-zero* automated coverage; both bugs shipped this week lived exactly
   there or in code the fuzz never reaches. The fix is not "UI testing" — it's **extracting the pure decision cores**
   (the same move that made `Router` testable behind the `MIDIEmitter` seam).
2. **Retired features left scars.** A/B-morph, grid-chaining, and the drag&drop page are all removed *in spirit* but
   survive as dead Codable fields, zombie AU parameters, a threaded-but-ignored `t` morph axis through the whole
   engine, and a `dd`-named layer BUILD leans on. Every one is a comprehension tax and a couple are latent bugs.
3. **Two mega-functions and a lot of duplicated chrome.** `Router.process` (≈380 lines, 35 params) and
   `emitOneBus` (≈145 lines) carry the engine; the SwiftUI files each re-declare the same cyan/amber tokens and
   re-implement the same chips/steppers/toggles.

**Top actions, in order:** (1) extract `composeBuildScene` + the BUILD reducers into a pure `BuildModel` and test
them; (2) fix the confirmed latent bugs in §8; (3) delete the dead `t` morph axis and the vestigial-field scars;
(4) build a shared design-system + shared test-support recorder; (5) widen the fuzz to reach >16 colours.

---

## 1. Architecture at a glance

The spine is a one-way, lock-free data flow, and it is genuinely well-built:

```
UI (SwiftUI)  ──edit──▶  MidiSparkAudioUnit          (main thread)
                          • editScene / editDocument  ← the only two document writers
                          • document: PluginState
                          • scheduleRebuild()
                              └─ SnapshotBuilder.build(from: renderDoc())  → SnapshotBox (immutable)
                                    └─ SnapshotStore.publish  (main-thread only, atomic swap)
                                                     │
  ─────────────────────────────────────────────────┼──────────  render-thread boundary
                                                     ▼
                          Kernel.render  ── acquire() one atomic load ──▶ Router.process(box, …)
                                                                            └─ MIDIEmitter.emit(…)  → host cables
```

**Invariants (CLAUDE.md:110):** (1) the render thread reads only the immutable `SnapshotBox`; (2) everything is
*derived* from host beat position — no accumulated counters (a few sanctioned exceptions); (3) no allocation / locks
/ ObjC on the render path; (4) no stuck notes, ever — offs refcounted per emitted `(cable, channel, note)`;
(5) parameter addresses are stable forever. **The seam rule:** only `MidiSparkAudioUnit`/`AudioUnitViewController`/
`Kernel` import AudioToolbox; `Router`/`Derivations`/`Snapshot*`/`Models`/`Emission`/`Diag` stay Foundation-only —
which is *why* the engine compiles into the macOS unit-test target and is so well tested.

The seam, the two choke points, the copy-on-poll rule, and the `AuditionBox` silent-reference-box trick are the
load-bearing strengths. **Do not disturb them** in any refactor; everything below works within them.

---

## 2. Cross-cutting themes

These recur across subsystems and are worth reading before the per-file detail.

### 2.1 Dead-feature accretion (the single biggest legibility tax)
When a feature was removed, its *render* path was deleted but its *schema, parameters, and UI bindings* were left
behind — because `Colour`/`Cell` are simultaneously the persisted format and the working model, so nothing can be
deleted without a decode story.

- **A/B morph:** `Colour.morph` is render-dead but still AU parameter #200+i, UI-slider-bound (`GridUI.swift:1272`),
  and persisted — a fully-wired, host-automatable knob that does nothing. `morphMaster` (#300) likewise. `paramsB`/
  `typeB` are written by migration but never read by the builder. `morphByType` (`Models.swift:169`) is *truly* dead
  (unreferenced anywhere). And the removed morph axis is still **threaded as `t: Double` through the entire engine** —
  every emit function declares `let t = 0.0` and passes it to `effective*` helpers that ignore it (`Router.swift`
  passim; `Snapshot.swift:294-342` are now identity wrappers with a dead parameter).
- **Grid-chaining:** `Cell.inputRow` is commented "inert decode-only" but **still feeds cell identity** via
  `SealKey` (`Derivations.swift:1125`) and the flow diagram — the comment is one wrong deletion away from silently
  invalidating every seal hash (see §8-B2).
- **Drag&drop page:** removed, but BUILD still calls into its `dd*` cluster, and `ddSolo` (named for the retired
  "PLAY: THIS CELL") is now the BUILD "chain is the voice" flag.

**The clean rule this violates:** kill a feature's render, parameter surface, UI binding, and schema in one move,
leaving only a `reserved` marker for the address number.

### 2.2 The extract-pure-core opportunity (the highest-value theme)
`Router` is testable because it was pulled behind a Foundation-only seam. The *same move* is available and unmade for
the UI layer. Several agents independently converged on the same candidates:
- `composeBuildScene` from `buildPublishScene` (BUILD) — the product's core, untested.
- `buildGCColours` liveness union (BUILD/AU) — session-only + untested = silent data loss.
- `renderDoc()` merge (AU), the RACK toggle/clamp logic (AU), the poll decay reducers (AU).
- `flowCells`/`isRooted` (FlowView), `EditSelection` (EditPage), the macro authoring reducer (MacroAuthoringView).

### 2.3 Duplicated chrome and tokens (SwiftUI)
The cyan `Color(red:0.15,0.88,0.94)` literal appears **18×**, the amber **16×**; `editHue` is defined twice; a
`PillToggle`/`Stepper`/`ChannelMenu`/`LabeledControl` is re-implemented 4–6 times across EditPage/RackMatrix/
ReceiverConfigView/CogPage/ArrangementBar/MacroPanel/GridMacroBand. `FlowView` even hardcodes a *different* receiver
hue array than the shared `receiverHues`. A single `Tokens` palette + ~6 shared primitives would remove ~30% of the
chrome in this layer.

### 2.4 "Derived, never accumulated" is now enforced by vigilance, not structure
Invariant 2's sanctioned exceptions were three (note tracker, param override, echo tails). The render thread now also
persistently accumulates `altMomentIndex`, `strumProgress`, `prevForcedStep`, the MOD/glide state, flood budget, and a
raft of edge-latches. Most are legitimate, but one (`altMomentIndex`) is a genuine violation (§8-A1), and a future
edit that adds a counter has no tripwire. A typed `RenderMemory` value would make the boundary visible.

### 2.5 Two-copies-of-truth in the UI state
Repeatedly, a working `@State` mirror and a stored authority coexist and can diverge: BUILD's `buildStagingSel` vs
`buildParts[i].stagingSel` (§8-C2), the document mirrored into `@State` in three places (AU §R2), the selected colour
held as both `buildSelID` and `ddColourSel`. Each is a lost-update or desync waiting to happen.

---

## 3. Subsystem: Engine render core
`Router.swift` (2795) · `Kernel.swift` (722) · `Derivations.swift` (1355) · `Emission.swift` (24) · `Diag.swift` (44)

**Purpose.** `Emission` is the 5-arg `MIDIEmitter` seam that keeps the engine Foundation-only. `Diag` is the
`inout` value struct carrying UI-facing counters. `Derivations` is the pure, stateless beat-math (swing warp, arp
phase/pattern, chance/strum/ratchet/harmonize/euclid/burst math, `NotePool`, the silence-invariant predicates, plus
UI-derivation helpers — seal/mosaic/glyphs). `Kernel` is the AudioToolbox boundary owning the *input* side (transport
derivation, incoming MIDI, latch pools, param-event route, the a8 stuck-note self-heal nets). `Router` is the render
engine proper: the voice tracker, per-processor emit functions, the §5b column-lap, echo tails, flood governor, the
emitter roles (claim/duck/alt/turns) and the RACK (curve/fence/mono/pocket/conversation), MOD, GLIDE, chain
composition, and the audition/preview paths.

**Clarity.** The dead `t` morph axis (S1) is the biggest tax. `process()` is a ~380-line monolith with a **35-param
signature** (`Router.swift:1402`) containing *two near-identical dispatch switches* (1728 vs 1757). `emitOneBus`
(942-1087) is a 15-gate sequential gauntlet whose correctness is pure ordering. Enormous stored-state surface
(~40 props in Router, a comparable wall of packed-mask setters in Kernel). Dead params linger: `emitArpRow`/
`emitRatchetRow` take an unused `box:`; preview threads a retired `inputRow`/`vr`. Feel-tuning magic numbers
(humanize `0.15`/`45.0`, shift `0.4`, fence-fold `<11`, ratchet `0.6`) are undocumented literals.

**Refactor.** *Safe, high value:* delete the `t` axis (mechanical, behaviour cannot change — R1); introduce a
`PerformInputs` struct for `process()`'s 35 args (R2); **extract one `cellAudible(col,row,cell)` predicate** used in
place of the guard that's copy-pasted with subtle variations in *five* emit paths (R3 — also closes §8-A3); collapse
the two dispatch switches (R4); a `WindowTiming` struct to kill the `(windowStart,beatPos,beatsPerSample,S,a)` param
noise threaded everywhere (R5). *Risky (hot path, stage behind tests):* group `emitOneBus` into
`resolveOutputPitch`/`velocityPipeline` phases (R6); dedupe the chain-fold loop (R7).

**Tests.** The processor/voice/claim/chain/audition surface is *very* well covered. The gaps cluster in the newer
hot-path treatments: **the whole RACK is essentially untested** — no engine test for FENCE (drop-leaves-no-stuck /
clamp-fold pairing), MONO (steal by priority), POCKET (shift preserves duration + off pairs), CONVERSATION (stance
gating), CURVE (monotonic remap). ALT/TURNS turn-taking and FLATTEN ducking are untested. Echo is thin (only the
pitch-clamp test). No loop/seek *replay-consistency* test (would catch §8-A1). The `FuzzTests.randomDoc` doesn't
stress the rack/roles/echo parameter space.

**Fragility / bugs.** See §8: A1 (ALT accumulated, not derived — invariant-2 violation), A2 (the sanctioned-exception
set has grown informally), A3 (five divergent cell-audible guards), A4 (voice-table own/All can open asymmetrically →
note missing on All), A5 (MONO-steal-then-flood-drop silent hole), plus cross-file guards that agree only by prose
(`Kernel.auditionCellSounds` ↔ `Router.auditionRender`).

**Start-again.** Table-drive processor dispatch (one `{isTickDriver,isHold,composeTransform,tickEmitter}` descriptor
per type, enum-indexed — adding a processor today touches ~6 sites). Extract the output stage (roles + rack) into an
ordered, individually-testable pipeline instead of the interleaved `emitOneBus` gauntlet — that interleaving is *why*
the rack is untested. Index the voice tracker (per-bus free list, per-pitch-class claim bitmap, per-bus holder
pointer) so claim/mono/flatten/conversation stop being O(128) scans on the hottest path. Gather the mutable
render-memory into one typed `RenderMemory` so invariant 2 is a type boundary, not a convention. Give `process()` a
real shape: `refreshState → handleEdges → deriveColumn → emitColumn → emitTicks`. *This is careful, battle-hardened
code* — the scars (deferred-reset race fix, ARC-safe flat metering buffers, fenced-note-shared-with-adoption) are all
healed correctly; the debt is the dead `t` axis, the two mega-functions, and the untested rack.

---

## 4. Subsystem: Model + Snapshot layer
`Models.swift` (1256) · `Snapshot.swift` (341) · `SnapshotBuilder.swift` (322) · `SnapshotStore.swift` (35) · `Dice.swift` (327)

**Purpose.** `Models` is the persisted document schema (the vocabulary enums, `Colour`/`Cell`/`SceneState`/
`PluginState`, all Codable, the effective-read resolvers with clamps, the factory presets, and the v2→v5 migrations).
`Snapshot` is the immutable render-facing mirror (`Snap` geometry, the flat pre-clamped `SnapCell`/`SnapParams`/
`SnapColour`, the `SnapshotBox`, `applyMacros`). `SnapshotBuilder` is the single pure resolver document→box (colour-
by-ID, 3-tier chain resolution, passthrough collapse, ladder dormancy, macro fold, receiver filter, every clamp).
`SnapshotStore` is the lock-free atomic publish/acquire with a 3-deep keep-alive. `Dice` is the offline chain
generator/evaluator that runs the *real* Router against a held chord to compute a note "signature".

**Clarity.** **The vestigial-field burden is the top issue** — every reader must track "live / decode-only / zombie"
per field. A consolidated table belongs in the code; the agent enumerated: `morphByType` (truly dead), `morph`/
`morphMaster` (zombie: persisted + automatable + inert), `paramsB`/`typeB` (migration-written, render-dead),
`transposeB`/`altColour`/`stack`/`srcMix` (decode-only), `inputRow` (**mislabelled "inert" — identity-live**),
`resolvedParent`/`inputCableMask` (constant). The `effective*(t:)` family (Snapshot.swift:294-342) is now a dozen
identity wrappers with a dead parameter. `resolve(_:type:fallback:)` carries a permanently-nil `fallback`. `PluginState`
is a 140-line wall of `Mask/Amount` + `Resolved` pairs (the RACK family, 599-701). Magic `64` slot keyspace vs the
real 8-slot cap. Stale comments contradict the actual stable addresses (Snapshot.swift:137 "#35" vs the real #300).

**Refactor.** *Very safe:* delete `morphByType` (genuinely unreferenced); dedupe the factory/preset epilogue
(5 lines ×4, `Models.swift:878-1120`). *Low:* collapse the `effective*` identity wrappers + drop `resolve`'s dead
`fallback`. *Medium (Codable migration):* extract a nested `EmitterRack` value type from `PluginState`'s ~25 rack
pairs. *Leave mostly as-is:* the `resolve` clamp block is verbose but is the *only* render-side sanitization and each
clamp is individually test-assertable — group with `// MARK:` rather than table-driving away the special cases.

**Tests.** Migration/round-trip/clamp coverage is strong. Gaps: the **passthrough-collapse** branches (explicit `[]`
vs all-bypassed-non-empty vs nil — the 2026-08-05 device bug, Builder:63-81) have no direct assertion; the
**canonical-vs-doc-order colour divergence** (§8-B1) has no guard test *and would likely fail today*; short
colours-array default masking; the muted-vs-disabled receiver asymmetry; `SnapshotStore` has zero tests (a basic
publish/acquire + keep-3-alive lifetime test would guard what everything trusts).

**Fragility / bugs.** §8-B1 (the canonical-first colour lookup is a latent silent-wrong-colour bug), §8-B2 (the
`inputRow` "inert" comment is a trap over seal identity), §8-B3 (zombie automatable params), and the structural
per-cell-routing twin-divergence class the model doesn't guard.

**Start-again.** **Commit to colour-owned routing from day one** — model `Colour` as the complete machine `{id, chain,
input, output, params}` and `Cell` as only `{colourID, position, perform, overrides?}`. That single change kills the
twin-divergence class, removes the fan-out sync, and makes half the vestigial fields never exist. **Separate the
persisted schema (an append-only DTO) from the working model** so retired features get read-and-dropped at the decode
boundary instead of haunting the domain type forever — this is the root cause of theme 2.1. One resolver, no
per-field wrappers. A linear versioned migration pipeline with explicit per-field lifecycle (`live`/`decode-only`/
`retired@vN`) so "is this dead?" is answered by the type, not by grep.

---

## 5. Subsystem: AU boundary + app shell
`MidiSparkAudioUnit.swift` (1252) · `AudioUnitViewController.swift` (1697) · `ChaosDriver.swift` (292) · `App/*`

**Purpose.** `MidiSparkAudioUnit` is the whole app↔engine boundary: the render seam (document → scheduleRebuild →
build → publish), the two mutation choke points (`editScene`/`editDocument`), the ~200 `setX`/`uiX`/`pollX` methods,
the 35-slot parameter tree + KVO, `fullState` encode/decode, the preset/undo/edit-session machinery, and the
ephemeral render overlays merged in `renderDoc()`. `AudioUnitViewController` hosts `DiagView`, the SwiftUI god-object:
**166 `@State` properties**, the 4 Hz poll, the tab bridge, the body, and all GRID/EDIT/LADDER interaction.
`ChaosDriver` (#if DEBUG) is the *only* thing exercising the AU handlers under render↔main pressure. The App shell is
a deliberate stub (standalone host deferred).

**Clarity.** The **4 Hz poll is a 140-line everything-bucket** (`:976`) doing diag dedup + ~20 scalar mirrors + six
multiset-diff decay blocks + tap refresh + transport cleanup — every line load-bearing for the gesture-stability
rule. **166 `@State` on one struct, ungrouped.** The **RACK setter forest** (`:443-662`, ~220 lines) is ~15
near-identical mask+amount pairs, then mirrored *again* in `refreshFromDocument` and a *third* time in the poll. The
**extension-DiagView split hurts navigability**: BUILD `@State` lives in the VC, BUILD logic in `BuildPage.swift`, the
hooks that call it in a third place. Dead surface: `routeInCandidates`/`wireRouteCandidate` stubs, `selectionMixed`
hardwired false, brush-desk remnants.

**Refactor.** *Low risk:* data-drive the RACK family into a role table + 2 generic helpers (and the logic becomes
pure/testable); extract the poll's six decay blocks into pure `MeterReducer` functions. *Medium (gesture-sensitive):*
have the AU vend one `UIDocSnapshot` value so the document is mirrored *once*, not in three places. *Medium-high (wait
for BUILD to stabilize):* lift BUILD state into a `BuildModel`; make ephemeral BUILD state a first-class AU overlay so
`renderDoc`, the colour GC, and the persist boundary have one owner.

**Tests.** None of this compiles into the macOS target. Highest-value pure extractions: `buildGCColours` live-set
union (**do this first** — silent data loss), `renderDoc()` merge, `buildPublishScene` assembly, the RACK toggle/clamp
logic, the poll decay reducers, `buildNewColour`/`buildSimilarHue`. `tapOverlayMasks` already shows the right pattern
(pure, in Derivations, tested).

**Fragility / bugs.** *Good news, verified:* **no poll returns a stored buffer by reference** — the render↔main crash
class is genuinely closed (scalar masks, `Array(slice)` copies, the header-dot mask unpacked fresh). *Watch items:*
**ephemeral BUILD state is session-only** — a deployed piece referencing `"b<n>"` colours is *not* serialized and
vanishes on teardown (§8-C4, needs a design decision); `buildGCColours` is the most fragile live logic (hand-unioned
liveset, untested); the exclusive-access discipline (`withChainCells` reads `document` before `editScene` to dodge a
crash) is correct but *manual*; `editColour`/`setColourType` record undo not gated by `sessionBaseline` (double-record
edge); host automation mid-edit-session bypasses the baseline; `reset()` on the control thread is the known
reset/render race (memory-flagged, fix belongs in Kernel).

**Start-again.** Split the AU into `extension` files per concern (`+RackEmitters`, `+ColourChain`, `+SceneEdits`,
`+PresetIO`, `+ParamTree`), expressed as an `EditAPI` protocol (enables test fakes *and* is the seam the standalone
host will need). Retire the 166-`@State` god-struct for 3–4 focused models (`PerformModel`, `MeterModel`,
`BuildModel`, the EDIT set). One AU-vended `docView` instead of three mirror sites. Make the ephemeral overlay one
explicit AU-owned layer. **Keep the seam, the choke points, the copy-on-poll rule, and `AuditionBox` exactly as they
are.**

---

## 6. Subsystem: BUILD page + grid rendering
`BuildPage.swift` (1815) · `GridUI.swift` (1856) · `DragDropPage.swift` (104) · `BuildSelfTest.swift` (207)

**Purpose.** `BuildPage` (an `extension DiagView`) is the primary workshop: PALETTE (per-part I/O + the cast),
STAGING/parts grid (one colour per row, one selected rung per column, + the STAGE-THE-GRID variation generator),
PLAY/perform grid (the valve deploy/restore + rung/mute selection), and the machinery footer (the selected colour's
chain editor). Everything funnels through **`buildPublishScene()`** (`:321`) which assembles a `SceneState` in three
passes (piece → part → chain) and hands it to the engine. `GridUI` is shared rendering + the global hue resolver
`colourColor` (reading the `colourHueOverride` global). `DragDropPage` is the retired page reduced to the shared `dd*`
colour cluster BUILD still calls. `BuildSelfTest` is the new in-app MIDI self-test suite.

**Clarity.** `buildPublishScene` is *the whole product* and is a dense, untested 43-line imperative — **where both
shipped bugs lived**. The **vocabulary is inconsistent**: the centre grid is "staging"/"part"/`BuildPart`; the right
grid is "perform" in code but "THE PIECE" in comments with no `buildPiece*` symbol; "row" and "rung" are used
interchangeably; `buildColourMachine` (all slots) vs `buildColourChain` (audible only) are easy to confuse. **Triple
selection representation** (`buildSelID` String, `ddColourSel` Int, computed `ddSelectedColourID`) dual-written by
hand in four places. **Vestigial `dd` coupling**: `buildSelectID` calls `ddScopeToColour` which does wasted work in
the *real document scene*; `ddSolo` (a drag&drop name) means "chain is the voice." The band form `[3,2,1,1,1]` is a
magic literal copied 4× (plus a divergent `[3,2,1,1]`). The `AnyView` metadata-overflow wrapping is load-bearing but
defeats SwiftUI diffing/identity and constrains every edit.

**Refactor.** **R1 (highest value, low risk): extract a pure `buildScene(from:) -> SceneState`** — pull the body of
`buildPublishScene` into a Foundation function over a plain input struct; the shell keeps only `clearColourSolo`/
`setLane(0)`/`setBuildStagingScene`. This makes the most important, most-churned, currently-untestable function
testable at a stroke. **R2: a `ColourRegistry` type** owning `buildColourReg` + `colourHueOverride` + minting + GC +
machine/hue resolution (dedupes three minting sites, makes GC a testable pure function, removes the global-var read).
**R3: unify the parts/play-grid selection** (three incompatible shapes today). **R4: absorb/remove the `dd` layer**
from BUILD (scoped — EditPage/PROCESSORS still consume `dd*`).

**Tests.** BUILD has **no automated tests** except `BuildSelfTest`, and that tests the *engine* given a hand-built
scene — never BUILD's own state→scene mapping. Extract-and-cover, in priority: `buildScene` (a `setLane(0)`-on-publish
assertion **would have caught the lap bug**); `buildReconcileStagingSel` (must *preserve* an explicit −1 deselect —
§8-C1); `buildStampRow` relocation/`rowUnder` revert; `buildCopySelectedRow`/`buildDeployBand` mapping;
`buildPerformActiveRung`; `buildStageTheGrid` invariants (every variation audible, fills to 8, lighter-above/darker-
below); `buildGCColours` liveness (incl. the `p.selID` gap — §8-C3).

**Fragility / bugs.** §8-C1 (`buildReconcileStagingSel` resurrects explicit deselects — **confirmed**), §8-C2
(multi-rung play-grid selection lost on part save — **confirmed**), §8-C3 (GC omits `p.selID`), §8-C4 (ephemeral piece
not persisted), plus the deploy/restore clears are hand-rolled in 3 near-duplicate loops (factor `clearPerformRange`),
and the loop-keys are an interactive-looking dead placeholder (now force-reset to 0 every publish).

**Start-again.** Separate the three fused concerns: **a pure `BuildModel` value type** (no `@State` working-copy
mirror — the current part is always `parts[currentPart]`, killing the save/restore hazard §8-C2); **a `ColourRegistry`
type**; **a pure `scene(from: BuildModel) -> SceneState`** as the *only* engine bridge (the natural home for the lane
reset and mute/rung rules); **one `Selection { colourID; perColumnRung: [Int?] }`** where `nil` means silent (kills
the overloaded −1, fixing §8-C1); **delete the `dd` dependency** from BUILD. The pattern to break is "one 1,800-line
view extension that is simultaneously the state store, the engine bridge, and the renderer, mutating shared globals
and a retired page's flags."

---

## 7. Subsystem: Edit / processor / routing / chrome UI
`EditPage.swift` (788) · `FlowView.swift` (577) · `RackMatrix.swift` (426) · `ReceiverConfigView.swift` (294) · `CogPage.swift` (148) · `ArrangementBar.swift` (359) · `ProcessorBox` (in `GridUI.swift:1216`)

**Purpose.** `EditPage` is the PROCESSORS tab: the transactional edit session, the mode rail (ADD/EDIT/MOVE/MUTE/
CLEAR), the chain-stack editor, the flow-diagram host, the three pop-ups, the OUTPUT/CHOP editor, the cell library.
`FlowView` is the *watch-only* MIDI-flow theater (a genuinely pure derived graph feeding five Canvas renderers — the
cleanest file in the set). `RackMatrix` is the per-emitter treatment matrix (stateless, prop-driven). `ReceiverConfig`
is the MIDI-IN tab. `CogPage` is settings. `ArrangementBar` is the header/tab-bar/scene-strip/help/dev-loader trigger.
`ProcessorBox` (dual-purpose: colour-desk face + chain-slot editor) lives in GridUI.

**Clarity.** **Dead colour-scoped branch in EditPage** (`editColourScoped` hardwired `false`, `:246`, `:736`) — every
`if editColourScoped` block is unreachable vestige from the drag&drop era, actively misleading (~15 lines). **The
`flowDiagram` is a wall of magic geometry** (`:393-436`) whose constants *hand-encode `receiverBox`'s internal
layout* — change the box and the dotted thread silently desyncs (the most fragile layout in the subsystem). Design
tokens + primitives duplicated per file (§2.3). `flattenMask`/`flattenAmount` are the storage names for the UI's
KEY/DUCK — a persistent name/label mismatch. Stale comments reference the removed drag&drop page as live.

**Refactor.** **A shared design-system** (tokens + `PillToggle`/`Stepper`/`LabeledControl`/`ChannelMenu`/
`EmitterMaskChips`/`Rotary`) — low risk, high payoff, collapses §2.3. **Extract flow-diagram geometry to a pure
`FlowDiagramLayout`** computed from the *actual* receiverBox metrics (fixes the desync, makes it unit-testable).
**Clarify the edit-session state machine** — there are effectively *three* overlapping undo/transaction mechanisms
(the global `UndoStack`, the `sessionBaseline`, and `EditSelection`'s own history) plus `clearedStash`/`adoptStash`,
all writing `document`; collapse into one `EditTransaction` with nested checkpoints. Split `renderFlow` (140 lines).

**Tests.** Extract and cover: **`FlowView.flowCells`/`flowTicks`/`isRooted`** (`:30-80`, pure, *zero tests*, encodes
real cycle/fallback logic that mirrors the engine — a divergence is a lying picture); **`EditSelection`** (a pure
value type blocked only by `GridPos`); the **rack readout string builder**; the **edit-session document transform**
(cancel-restores-baseline / apply-iff-changed / nested-begin-idempotent). Note `FlowView.clock()` reimplements
`columnStart` — it should call the shared Derivations helper (one-clock rule).

**Fragility / bugs.** The exclusive-access trap (worked around, unguarded); `sessionDirty` does whole-document
equality per redraw (perf cliff now that the doc is unbounded); the flow diagram's "bypassed passgate ≡ empty"
sentinel can desync display from document; `slotBox` round-trips slot params through a synthetic `Colour` and silently
drops any non-`paramsA` field ProcessorBox touches; nested pop-up baselines compose correctly *only because* they're
always time-ordered.

**Start-again.** One design-system layer; separate flow geometry (pure) from rendering (view) with a single
`RoutingGraph` shared by both flow diagrams (they currently share nothing and even disagree on receiver hues); one
`EditTransaction` model; move the resolution sentinel into a `Cell.displayChain` vs `renderChain` method. **FlowView,
RackMatrix, CogPage, ArrangementBar are in good shape** — the debt is concentrated in EditPage and the absence of
shared primitives.

---

## 8. Subsystem: Macros / presets / scenes / misc UI
`MacroAuthoring.swift` (281) · `MacroAuthoringView.swift` (372) · `MacroPanel.swift` (241) · `PresetStore.swift` (122) · `PresetBrowser.swift` (211) · `SceneFactory.swift` (281) · `TestSessions.swift` (314) · `ManualView.swift` (133) · `GridMacroBand.swift` (73)

**Purpose.** `MacroAuthoring` is the pure macro model + authoring math (in the test target). `MacroAuthoringView` is
the A/B authoring pop-up. `MacroPanel` is the MACROS tab (three banks). `PresetStore`/`CellLibraryStore` persist whole
documents / per-cell files. `PresetBrowser` is the browser sheets. `SceneFactory` is the 16 factory scenes.
`TestSessions` is the T1–T17 canned engine rigs. `ManualView` is the in-app "?" reader. `GridMacroBand` is the
grid-top macro band.

**Clarity.** **The discrete-param macro preview lies vs the engine** — the authoring audition sweeps pattern/rate/
bypass, but `applyMacros` folds only the 9 *continuous* `MacroParam`s, so a bound discrete delta is stored-but-inert
and the preview is a fidelity fiction (nothing in the UI signals the boundary). **Manual anchors have drifted** —
`#id`, `#tab-bar` used in code have no `{#…}` in the doc → the manual silently opens at the top. The whole timeline
bank is reserved-but-inert dead surface (a third of the "24 macro slots" headline). `TestSessions`' header comments
describe a codebase that no longer exists. Three copies of `subscript(safe:)`; per-file hex colours (§2.3).

**Refactor.** `CellLibraryStore` ≈ `PresetStore` (near-total duplication → one generic `NamedFileStore<T:Codable>`,
low risk). Shared macro widget primitives (`MacroButton`≈`GridMacroButton`, `MacroFader`≈`GridMacroSlider` — byte-
identical gesture logic). Extract the authoring reducer (`bind`/`unbind`/`reflect`/`lockMacro`) out of the View.
**Move `TestSessions` into `Tests/`** as the fixture provider it already is (its own docstring calls it a test rig)
and delete the now-orphaned `loadTestSession`/`load`/`selected` chain — it's genuinely valuable as engine-coverage
fixtures (T5 mute-reroute, T7 collision, T11 cycle-silence encode invariants no unit test asserts end-to-end).

**Tests.** `MacroAuthoringTests`/`PresetStoreTests`/`SceneFactoryTests` are strong. Add: `macroApply` negative-delta +
lo-clamp + downward sweeps; **an explicit assertion that a bound discrete delta does *not* survive into `applyMacros`**
(pin the boundary); preset name-collision (`sanitize("My/Rig")==sanitize("MyRig")`); a >16-ephemeral-colour preset
round-trip; **`SceneFactory` colourID-validity + bus-channel invariants** (every cell's `colourID` canonical, every
scene's `busChannels.count==4 ∈ 1…16`); a manual anchor⇔doc consistency check.

**Fragility / bugs.** The orphaned `TestSessions` loader chain (confirmed dead); the drifted manual anchors (silent
no-op); preset sanitize collisions overwrite silently with no confirm; `SceneFactory.load(_:)` is unguarded (traps on
bad index). *Good:* `applyMacros` sum-then-clamp-once is correct; scenes 9 & 11 match the revised doc; the two
doc-divergences are honestly annotated in-code.

**Start-again.** **Make the macro boundary total, not partial** — at snapshot-publish time, bake *every* authored delta
(discrete included) into the resolved `SnapParams` by re-running the same `macroApply` math the preview uses; the
render thread stays offset-free, discrete params modulate for real, and the preview stops lying. One file-store
abstraction; fixtures (TestSessions) out of the app target. **Make the manual anchor registry an `enum` checked
against the doc** so a drift is a caught error, not a silent scroll-to-top. *The pure core here (MacroAuthoring,
PresetStore, SceneFactory) is clean and well-tested — the strongest UI-adjacent code in the repo.*

---

## 9. Subsystem: The test suite
`Tests/*.swift` — ≈616 test functions, 8,760 lines

**Purpose & coverage.** RouterTests (251), DerivationsTests (172), MigrationTests (85), EffectiveParams (32),
SnapshotBuilder (24), MacroAuthoring (15), Dice (10), Fuzz (8), Preset (8), ColourTypeSwitch (5), SceneFactory (5),
BuildSelfTestMeta (1). **The engine and pure-math coverage is exemplary** — a `RecordingEmitter` captures the exact
wire, `assertNothingLeftSounding` expresses the no-stuck contract, tests drive the *real* Router/SnapshotBuilder (not
mocks). **Where it's thin or absent:** BuildPage (near-zero — the most-churned file), the AU boundary (only the
render-param route + the ephemeral-append are reached), all SwiftUI (device-only), the ephemeral-colour lifecycle,
selection logic, deploy/restore.

**Clarity.** RouterTests is a **4,327-line monolith** (251 tests, one class, ~13 fixture builders, ~11 run-harness
variants) — split by the existing MARK seams. **Four near-identical `MIDIEmitter` doubles** each re-implement the same
no-stuck check (`RecordingEmitter`, `FuzzEmitter`, `SelfTestRecorder`, `DiceRecorder`). The `windowBeats` idiom is
hand-inlined in ~8 harnesses.

**The big gaps (ranked).** **(a) BUILD-page pure cores** — extract & test `composeBuildScene` (the single biggest
untested surface, and where the lap bug lived), `bandGeometry`, the workshop-voice reducer, `liveColourSet`,
`buildComplexity`/`stageTheGrid`, orphan-part reuse. **(b) AU-boundary logic** — the colour-index→override-slot clamp
(the SIGTRAP root), the *tree-setValue* param route (only the render-side is tested, though invariant 6 needs both).
**(c) Coverage reach, not a missing processor** — `FuzzTests.randomDoc` caps colour IDs at six (`:59`), so the
ephemeral index-≥16 path — the exact class that once made the suite *vacuous* and produced this session's SIGTRAP — is
**never fuzzed**. **(d) Invariant property tests**: block-size-invariance for *all* processors (not just echo),
byte-identical output across a no-op republish, per-processor replay-safety.

**This session's two bugs vs the suite.** The **SIGTRAP** (colour index ≥33 overflowing the fixed override table) was
*not catchable* (no test/fuzz placed a cell with index ≥16) and is **now well-locked** by three new tests. The **stale
column-lap** gating the BUILD audition was *not catchable and is still not locked* — the fix lives in `buildPublishScene`
(not compiled into the test target) and `BuildSelfTest.render` always passes `laneMask: 0`. **Lock it** by extracting
`composeBuildScene` and asserting the scene never depends on a non-zero lane.

**Fragility.** The perpetual blind spot at the last-two-bugs' address (the 6-colour fuzz cap); `testPinnedRegressionSeeds`
is currently an inert green no-op (three empty lists); the entire BuildPage is device-only; the `-derivedDataPath` /
clock-skew caveat means a green run *without* the pinned path can be a stale bundle (runner discipline, not suite
quality). *Not over-mocked — a genuine strength.*

**Start-again.** Make BUILD testable by **extraction, not UI testing** (a Foundation `BuildModel` with pure
transitions; the SwiftUI becomes a thin projection). Formalize the fuzz into a **property harness** over
`(doc, chord, transport-schedule)` with generators that reach the *whole* document space (>16 colours, deep chains,
all receiver modes). **Golden-MIDI-signature regression** — promote `Dice.signature` to committed golden files for a
curated scene set and diff every run (catches behavioural *drift*, not just invariant breakage). Split RouterTests;
one shared test-support recorder; a data-driven per-processor property table.

---

## 10. Confirmed & latent bugs (consolidated)

Ranked by a blend of severity and confidence. "Confirmed" = a concrete failing path was identified; "Latent" = correct
today but one edit / rare input away.

| # | Sev | Where | Issue |
|---|-----|-------|-------|
| **C1** | **High (confirmed)** | `BuildPage.swift:505` `buildReconcileStagingSel` | The `−1` deselect sentinel is overloaded with "invalid/unchosen", so the reconcile *resurrects* a deliberately-silenced column. Triggered by an edit-mode place/delete or STAGE-THE-GRID after the user silenced a column. Fix: only fall back a *positive* pick at an empty cell; preserve explicit `−1`. |
| **C2** | **Med (confirmed)** | `BuildPage.swift:768` `buildTogglePerformRung` | Multi-rung play-grid rung selection is written to `buildParts[part].stagingSel`, but when `part == buildCurrentPart` the live authority is `buildStagingSel`, and the next `buildSavePart` (`:541`) overwrites it — silently discarding the toggle. Root cause: two copies of truth. |
| **C3** | Med | `BuildPage.swift:430` `buildGCColours` | The GC liveness union omits each part's `p.selID`. If a stored selection ever falls outside its cast, GC frees the colour and `buildLoadPart` selects a dead id. Add `p.selID` to the live set. |
| **B1** | **High (latent)** | `SnapshotBuilder.swift:51` | `colourIDs.firstIndex(of:) ?? colourIndexByID[…]` prefers the *canonical* 0–15 index over the doc-order map. Correct only while `doc.colours[i].colourID == colourIDs[i]`. Any colour reorder/removal → a canonical-ID cell reads the *wrong* SnapColour (wrong machine/transpose). Silent. Fix: use `colourIndexByID` alone (correct-by-construction). |
| **A1** | Med (latent) | `Router.swift:161,906,1517` | ALT turn-taking (`altMomentIndex`) is *accumulated* and reset only on the transport edge, never on seek/loop — so which emitter holds a turn is **not** a pure function of beat position (invariant 2 violation). Loop the host and the passage hands out turns differently. Not in the sanctioned-exception list. |
| **B2** | Low (trap) | `Models.swift:329` / `SnapshotBuilder.swift:93` | `Cell.inputRow` is commented "inert decode-only" but feeds cell identity via `SealKey` (`Derivations.swift:1125`). Acting on the comment and deleting it silently invalidates every seal hash. Fix the comment to "render-inert, identity-live." |
| **A4** | Low (latent) | `Router.swift:1080` `emitOneBus` | The own-cable and All-cable voices open independently; at 128-voice exhaustion `own` can get the last slot and `all` not → the note is missing on the All cable (silent divergence, not a stuck note). Reserve own+All atomically or add a diag counter. |
| **A5** | Low (rare) | `Router.swift:1050` `emitOneBus` | MONO steal closes the previous holder *before* the flood-cap check; if the new note is then flood-dropped, the emitter is dead until the next beat resets the budget. Order the cap before the steal. |
| **C4** | Med (design) | `MidiSparkAudioUnit.swift:1201` | Ephemeral BUILD state (`buildColourReg`, the parts, the grids, `"b<n>"` colours) is `@State`/side-field, **never serialized**. A host autosave/preset captures only committed colours — a partially-built piece, *including a deployed play grid referencing ephemeral colours*, vanishes on teardown. Confirm the "provisional until committed" intent or persist it. |
| **M1** | Med (UX) | `Snapshot.swift:247` vs `MacroAuthoringView.swift:257` | The macro authoring preview sweeps discrete params (pattern/rate/bypass) that `applyMacros` never folds — the audition misrepresents playback. Either bake discrete deltas at publish (see §8 start-again) or signal the boundary in the UI. |
| **M2** | Low | `ManualView.swift:104` | `helpAnchor("#id")` / `"#tab-bar"` have no matching `{#…}` in the manual doc → silent scroll-to-top. Make anchors an `enum` checked against the doc. |
| **M3** | Low | `PresetStore.swift:14,44` | `sanitize` is many-to-one and `save` is unguarded → `"My/Rig"` and `"MyRig"` clobber; same-name save overwrites with no confirm. Dedup or confirm-overwrite in the store. |
| **U1** | Low | `MidiSparkAudioUnit.swift:711,721` | `editColour`/`setColourType` record undo *not* gated by `sessionBaseline`, so a colour edit during an open edit session records an extra nested undo step the session model doesn't expect. |

---

## 11. If I were starting again — the synthesis

Keeping the parts that are genuinely excellent (the immutable-SnapshotBox seam, the two choke points, the copy-on-poll
rule, `AuditionBox`, the Foundation-only engine seam, the invariant-driven engine tests), here is what I'd change at
the design level:

1. **Separate the persisted schema from the working model.** A thin append-only `PersistedV_n` DTO decoded into a
   clean working `Colour`/`Cell`/`PluginState` that carries *only live fields*. Retired features get read-and-dropped
   at the boundary. This single decision prevents the dead-Codable accretion (§2.1) that causes most of this review's
   clarity findings and two of its bugs (B1, B2).

2. **Colour owns its machine; Cell owns only placement + performance + a sparse override.** `Colour = {chain, input,
   output, params}`; `Cell = {colourID, position, perform, overrides?}`. Kills the twin-divergence class and the
   per-cell routing fan-out, and makes half the model vanish. (CLAUDE.md's "four steers" already ratifies this.)

3. **Push the whole UI's decision logic behind a Foundation seam, exactly as `Router` is.** A `BuildModel` value type
   with pure transitions (`composeScene`, `workshopVoiceReducer`, `bandGeometry`, `liveColourSet`), an `EditTransaction`
   model, a `RoutingGraph` shared by both flow diagrams. The SwiftUI layer becomes a thin projection. This is the
   change that would have made both of this week's bugs catchable in CI.

4. **A typed `RenderMemory` for the engine's sanctioned mutable state**, so "derived vs accumulated" is a type
   boundary a reviewer can see (fixing A1/A2 structurally), and table-driven processor dispatch + an extracted,
   testable output pipeline (fixing the untested rack).

5. **One design-system layer** (tokens + ~6 primitives) so the SwiftUI files stop re-declaring the same chrome.

6. **A total macro model** — bake every authored delta at publish, discrete included, sharing the preview's math.

7. **A property-based fuzz harness with full-space generators + golden-MIDI-signature diffs**, so behavioural drift
   and whole bug classes are caught, not just the invariants.

The through-line: *the engine got the "pull the pure core behind a seam and test the real thing" treatment and is
superb; the UI and the model never did.* Almost every finding here is a consequence of that one asymmetry — and
almost every high-value action is an instance of correcting it.

---

## 12. Prioritized action list

**Do now (low risk, high value):**
1. Fix the confirmed BUILD bugs **C1, C2, C3** (§10) and add regression tests.
2. Correct the `inputRow` "inert" comment (**B2**) and switch `SnapshotBuilder:51` to `colourIndexByID` alone (**B1**).
3. Extract **`composeBuildScene`** (pure) from `buildPublishScene`; assert the scene never depends on a non-zero lane
   (locks the lap bug) + the mute/rung/least-occupied-row rules.
4. Delete the dead `t` morph axis through the engine (mechanical, behaviour-preserving) and the truly-dead
   `morphByType`; extract the `cellAudible` predicate (§3-R3).
5. Widen `FuzzTests.randomDoc` past 16 colours (closes the perpetual blind spot); add a comment to the inert
   `testPinnedRegressionSeeds`.

**Do soon (low risk, medium value):**
6. A shared **design-system** (tokens + primitives) + a shared **test-support recorder** (one `MIDIRecorder`).
7. Extract & test `buildGCColours` liveness, the RACK toggle/clamp logic, `flowCells`/`isRooted`, `EditSelection`.
8. Add the missing engine tests for the **RACK** (fence/mono/pocket/conversation/curve) and ALT/TURNS.
9. Move `TestSessions` into `Tests/` and delete the orphaned loader chain; fix the manual anchors (**M2**) and preset
   collisions (**M3**).

**Do when BUILD stabilizes (medium risk, structural):**
10. Introduce the `BuildModel` + `ColourRegistry`; unify the selection model; delete BUILD's `dd` dependency.
11. Data-drive the AU RACK setter forest; vend one `docView`; extract the poll decay reducers.
12. Collapse the three edit-session mechanisms into one `EditTransaction`.
13. Split `Router.process` (`PerformInputs` struct, unified dispatch) and `RouterTests` (by MARK seam).

**Larger bets (design-level):**
14. The persisted-DTO / working-model split; colour-owned routing; the total macro model; the property-fuzz +
    golden-signature harness.

---

*Generated 2026-08-16 from a full read of every source and test file. The engine is in excellent shape; the highest
leverage is making the UI/BUILD layer testable by extraction — the same move that made the engine trustworthy.*
