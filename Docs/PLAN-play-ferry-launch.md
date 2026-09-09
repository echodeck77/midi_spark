# PLAN — Play-ferry launch settings (name · colour · launch behaviour · choke)

**Status:** APPROVED in concept by Paul (2026-09-09). Not started. Own branch off
`main` when scheduled (coordinate with the other instance per the two-instance rule).

## What & why

The below-grid card (`roomsProcessorCardAt`, `BuildPage.swift:1714`) is dead space
when the selected part's cell has no processor — today just an icon + one line
(`roomsCardPlaceholder`, `:1734`). Repurpose it as a **launch-settings panel for the
selected part's PLAY FERRY**: identity + how the ferry fires when performed. This turns
the 8 part-ferries into a clip-launcher performance layer.

## Decisions locked (Paul, 2026-09-09)

- **Scope = per FERRY/PART** (a ferry *is* a `BuildPart`), stored on `BuildPart` — NOT
  shared via the underlying machine. Sidesteps "renaming affects every cell."
- **Panel = the empty-machine card**, shown for the selected part until a processor is
  chosen; the processor editor then takes the space. (Empty-state, not always-available.)
- **Controls:** name · colour (hue) · tap action · tap timing · spring/latch · choke group.
- **Choke:** one group number per ferry.
- **One-shot start-time decoupling = YES, in scope.** Fire from the part's top on tap,
  still at host tempo (NOT tempo-decoupled). Delivered via a per-ferry **launch anchor**
  (the beat a ferry was launched on); the ferry then derives its column as
  `f(beat − anchor)` so it plays from column 0. This is the REPLAY-loop anchor pattern
  (`Kernel.swift:322-327`, `replayAnchor`), and stays inside invariant 2 ("derived from
  beat position" — the anchor is a stored reference, the sanctioned-exception class).

## The launch model

Two orthogonal axes + timing + choke (TOGGLE == the LATCH side of spring/latch — not a
separate mode):

| Field | Options | Meaning | Default |
|---|---|---|---|
| **Playback** | ONE-SHOT · LOOP | stop at part end, or repeat | LOOP (today) |
| **Trigger** | SPRING · LATCH | hold-to-play (gate) · tap-on/tap-off | LATCH (today) |
| **Start** | SYNC · INSTANT · STEP · BEAT · PASS | SYNC = stay locked to transport (today's behaviour, **no anchor**); the rest = launch **from the part's top** at that boundary (INSTANT = the tap moment = off-grid) | SYNC (see open decision 1) |
| **Choke** | OFF · 1–8 | ferries sharing a non-OFF group are mutually exclusive: launching one stops the others in that group | OFF |

`SYNC` is simply "anchor disabled for this row" — so the anchor mechanism serves both
the transport-locked backing-part case and the from-top clip-launch case with one lever.

## Model changes — `BuildPart` (`BuildModel.swift:9-30`)

Add (all additive-Optional so old saves decode; **must extend the decode-tolerant
`init(from:)` at `BuildModel.swift:157-176`** with `decodeIfPresent` for each — this is
the CR-8 data-loss guard):

```swift
var ferryName: String?          // per-ferry label (nil ⇒ unnamed)
var ferryHue: UInt32?           // display-hue override (nil ⇒ position playHexes[col])
var launchPlayback: FerryPlayback?   // .oneShot | .loop   (nil ⇒ .loop)
var launchTrigger:  FerryTrigger?    // .spring  | .latch  (nil ⇒ .latch)
var launchStart:    FerryStart?      // .sync/.instant/.step/.beat/.pass (nil ⇒ .sync)
var chokeGroup: Int?            // 0/nil = OFF, 1…8
```
New enums in `BuildModel.swift` (Foundation-only, Codable, so they're unit-testable):
`FerryPlayback`, `FerryTrigger`, `FerryStart`. (Consider reusing `OnTapWhen`
`{now,step,pass,lap}` + its `tapOnsetBeat` helper `Derivations.swift:1507` for the
boundary math rather than a fresh enum — see open decision 3.)

These auto-persist: they ride `BuildPart` → `BuildPlayGridData.parts`
(`BuildModel.swift:100`) → `PluginState.buildPlayGrid` (`Models.swift:1455`), captured/
restored by `buildCapturePlayGrid` / `buildRestorePlayGrid`
(`BuildPage.swift:4292-4329`). **No new persistence plumbing.**

The **launch anchor is NOT persisted** — it's runtime. New `@State var launchAnchor:
[Double]` (size `Snap.rows` = 16) in `AudioUnitViewController.swift` alongside
`buildPlayColOn` (`:221`).

## Engine — the launch anchor (the one real engine change)

The per-ferry playing flag is `buildPlayColOn: [Bool]` (`AudioUnitViewController.swift:221`).
Ferries render on engine rows: the active on-bench ferry via the staging rows 0-7
(`composeSceneMeta` stagingPlaying block, `BuildSceneLogic.swift:219-236`); background
on-ferries via the play layer rows `8+c` (`BuildSceneLogic.swift:176-203`,
`Snap.playLayerRowBase = 8`).

Column-from-beat derivation (multi-clock per-row path):
**`Router.swift:2531-2549`** — per row `r`, `mNr = musicalOf(beatPos, stepBeats: Sr, …)`
at **`:2534`**. The anchor injects here:

1. Thread a per-engine-row `rowLaunchAnchor: [Double]` onto `SnapshotBox` (published from
   `launchAnchor` via `BuildSceneLogic.Input` → `SnapshotBuilder`).
2. At `Router.swift:2534` use `beatPos − rowLaunchAnchor[r]` in `musicalOf(...)`. Then
   `posR`, `absStepR`, `passR` all derive from the phased beat → the row plays from
   column 0 at the anchor. `SYNC` = anchor 0 (no shift, byte-identical to today).
3. **Force the multi-clock path when any anchor is set** (mirror how per-part `rate`
   forces it), so an anchored ferry never falls through the uniform fast path
   (`:2463-2473`) which has no per-row offset.
4. Capture the anchor in the SAME beat space as playback: host `beatPos` when playing,
   else `freeRunBeat` (`Kernel.swift:207-214`) when free-running.

Stamp/quantize the anchor in **`buildToggleFerryPlay`** (`BuildPage.swift:1882-1894`):
on `willOn`, `launchAnchor[row] = tapOnsetBeat(currentBeat, launchStart, stepBeats)`
(reusing `Derivations.swift:1507`); `SYNC` → leave 0. `row` = 0-7 for the active
on-bench ferry (the whole staging part shares one anchor), or `8+t` for a background ferry.

**One-shot** (`launchPlayback == .oneShot`): the row must not loop. Thread a per-row
`rowOneShot: [Bool]` to `SnapshotBox`; in the tick emit, once `absStepR ≥ Lr` (one pass
past the anchor) emit nothing. Also clear `buildPlayColOn[t]` in the ~4 Hz poll
(`AudioUnitViewController.swift:835`) at `beat ≥ anchor + Lr·stepBeats` so the button
reflects "stopped." (`tapExpiryBeat`, `Derivations.swift:1518`, gives the expiry.)

**Spring** (`launchTrigger == .spring`): momentary — the ferry plays only while its button
is held. Change `roomsPlayFerry`'s play button (`BuildPage.swift:1789-1834`) to a
press/release gesture (the ROW-8 held-mover idiom: `DragGesture(minimumDistance:0)` →
on = press, off = release) when the ferry is SPRING; LATCH keeps the tap-toggle.

**Choke** (`chokeGroup`): none exists today (all 8 play independently,
`BuildSceneLogic.swift:176-177`). In `buildToggleFerryPlay` on launch, for every other
ferry with the same non-OFF `chokeGroup`, clear `buildPlayColOn[other]` +
`buildClearFerryPlayback(other)` (`BuildPage.swift:1897`). Pure decision → extract
`BuildSceneLogic.chokeVictims(group:, parts:, on:)` for unit testing.

## UI — the panel

Extend `roomsProcessorCardAt` (`BuildPage.swift:1714-1731`): when `buildEditSlot == nil`
(no processor being edited) and a part/ferry is selected (`buildActiveFerry != nil`),
render a new `roomsFerryLaunchPanel(ferry:)` in place of / above `roomsCardPlaceholder`
(`:1729`), editing `buildFerryParts[buildActiveFerry!]`. Contents:
- **Name** — the first `TextField` in the build surface (none exists today). Writes
  `ferryName`.
- **Colour** — a hue swatch row (the 16 palette hues + the position default) writing
  `ferryHue`; the ferry row (`roomsPlayFerry`) + selector read it (fall back to
  `playHexes[col]`).
- **Playback** ONE-SHOT · LOOP · **Trigger** SPRING · LATCH · **Start** SYNC/INSTANT/
  STEP/BEAT/PASS · **Choke** OFF · 1–8 — segmented rows (reuse `seg`/`iconSeg`).

## Phasing (each shippable + verifiable on its own)

- **Phase 1 — DONE (commit 84c89a5):** the 6 BuildPart fields + decode-tolerant init +
  enums; roomsFerryLaunchPanel (name · colour · launch selectors, store-only); ferry row
  honours ferryName/ferryHue. iOS builds, macOS +1 round-trip test.
- **Phase 2a — DONE (commit e7bc36f):** the launch ANCHOR (start decoupling). SnapshotBox
  rowLaunchAnchor + the Router injection (anchored beat passed consistently to every
  per-row emitter so phase shifts while sample offsets stay in the raw window) + the
  multi-clock force + the armed-until-start guard; pure ferryLaunchAnchor + full threading
  + stamp in buildToggleFerryPlay + ferry→engine-row mapping in buildPublishScene. macOS
  +1 RouterTest (armed-until-start + eventual play), fuzz green, byte-identical when no anchor.
- **Phase 2b — TODO:** one-shot STOP (record launchBeat — already stored — clear buildPlayColOn
  at pass expiry in the 4 Hz poll) + the SPRING momentary gesture (press/release on the ferry
  play button). Both device-feel owed. Also: bulk play-all should stamp per-ferry anchors
  (currently plays SYNC).
- **Original Phase 1 — identity + panel + persistence (UI/model only, no engine).** Add the 6
  `BuildPart` fields + decode-tolerant init + enums; build `roomsFerryLaunchPanel`
  (name + colour + the four launch selectors, storing only); ferry row/selector render
  `ferryName`/`ferryHue`. Nothing changes playback yet. macOS round-trip test for the new
  fields; device eye for the panel.
- **Phase 2 — launch engine (anchor + start-quant + one-shot + spring/latch).** The
  `SnapshotBox` per-row `rowLaunchAnchor` + `rowOneShot`, the `Router.swift:2534`
  injection + multi-clock forcing, `buildToggleFerryPlay` anchor stamping, the one-shot
  stop, the spring press/release gesture. RouterTests: anchored row plays from col 0;
  SYNC == byte-identical to today; one-shot stops after one pass, no stuck notes; free-run
  anchor. Device ear.
- **Phase 3 — choke groups.** `chokeVictims` + the cutoff in `buildToggleFerryPlay`.
  Unit test + device.

## Decisions resolved (Paul, 2026-09-09)

1. **Default Start = `SYNC`** — ferries stay transport-locked (byte-identical to today);
   from-top launch is opt-in per ferry.
2. **Launch behaviour applies to the ACTIVE on-bench ferry too** (staging rows 0-7), not
   just background play-layer ferries — the anchor array is per engine row and covers both.
3. **Fresh `FerryStart` enum** (`{sync, instant, step, beat, pass}`), borrowing the
   boundary math from `tapOnsetBeat` (`Derivations.swift:1507`) rather than reusing
   `OnTapWhen`.

## Verification & git

- macOS suite green (new decode-tolerance + anchor/choke/one-shot pure tests); iOS build
  green. Phase 2/3 device ear owed (Kernel/Router aren't unit-run on device).
- Own branch → commit → merge to `main` → push, per the two-instance workflow.
