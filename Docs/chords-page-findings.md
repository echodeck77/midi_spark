# CHORDS PAGE ferry — §0 findings (the map that was made before the build)

Ratified by Paul 2026-11-04 (the "Fourfold Chords" canvas). **STATUS: LANDED (`605f4c2`) — engine + page UI.**
This was written while the ferry was BLOCKED on RESTART UNITS (which hadn't landed its schedule yet); it is kept
as the read-only map (progressions model, the playing-column formula + its readers, the lane-cards block frame,
the overlay rule, the model-wiring path, the 8×8 boundary) and the record of the contradictions resolved on the
way (§E below). All paths relative to repo root; Fourfold product only unless noted. Verified in source.
See `Docs/euclideous-status-log.md`'s CHORDS PAGE entry for what was built, and `Docs/pending-tasks.md` for the
documented follow-ups (lane-strip DELAY, full VoiceOver, RIFF-on-FREE-lane, chords-page UI tests).

## A. The CHORDS page as built (inside the SOURCES panel)

- **Opens** via a `@State` flag, NOT a NavigationView push: `EuclideousPage.swift:1466 sourcesChordsPage`
  (the SOURCES panel `sourcesPopupOpen :1464` draws `sourcesChordsPageCard` when true, else `sourcesPanelCard`;
  body switch `:1661-1682`, animated `.move` transitions). The CHORDS row's content well navigates IN:
  `EuclideousPage.swift:2588 .onTapGesture { sourcesEditor = .none; sourcesChordsPage = true }`. Back/tap-catcher
  set it false (`:1665`, `:2877`). Inputs `:787-790` (`chordSets`, `activeChordSet`, `onEditChordSet`, `onSwitchChordSet`).
- **Frame (current):** a CENTRED POPUP CARD, not the lane block. `sourcesChordsPageCard` `EuclideousPage.swift:2824-2856`:
  `maxW = min(640, size.width-32)`; contentBox `(maxW-40) × ((size.height-60)-40)`; `.padding(20)`; surface
  `cornerRadius 8` fill `#1B1D23`, border `#3A3E47` 1pt. Inner layout `euclideousChordsPopupLayout(box:steps:)`
  `Derivations.swift:1335-1371`; metrics `EuclideousChordsPopupMetrics` `:1313-1331` (titleRowH 22, tabRowH 20,
  stepsRateRowH 26, playheadBarH 3, poolStripH 32, rowGap 4, dividerGap 10, gridRowCount 18, dividerAfterRow 11,
  rowFloor 20, cellFloor 14, labelW 36).
- **Title row** `sourcesChordsTitleRow EuclideousPage.swift:2864-2889`: back `chevron.left` 10 bold `#AAB0BA` +
  `"SOURCES"` 10 heavy mono tracking 0.06 `#AAB0BA`, 44-tall hit → `sourcesChordsPage=false` (`:2873-2877`); a
  **PIP** (not a switch) `sourcePip :2880` (10×10 r3, `EuclideousSourceColour.chords.fill` when playing — the
  CHORDS on/off TOGGLE is the SOURCES-row control `sourceLabelSwitch :2422-2434`, 84×44); label `"CHORDS"` 16
  heavy mono `white 0.9`, `" · "` 14 `white 0.4`, then **the live chord NAME** 14 heavy mono `#F2F4F7`
  (`chordsNameAndIsRest :2904-2918`, "REST" on a rest). srcChords lilac `Derivations.swift:4216 0xB9A8FF`.
- **Progression tabs** `chordsTabRow EuclideousPage.swift:2924-2949`: exactly **two** (`ForEach 0..<min(2,count)`),
  each `"\(i+1)"` 9 heavy + `chordsTabIcon` (22×12 Canvas `:2952-2963`, `euclideousChordsTabIconRow Derivations.swift:1395`)
  + steps count 8 heavy; r6, selected `#DFE3EA` ink `#0D0F14`. Tap `onSwitchChordSet(i) :2943`; long-press (0.5 s)
  COPY/PASTE/CLEAR `chordsTabMenuCard :2964-2993`.
- **STEPS / RATE** `chordsStepsRateRow EuclideousPage.swift:2995-3024`: STEPS stepper `chordsStepStepper :3019-3024`
  (26×26 r6 fill white 0.08, `−`/`+` 14) clamp 1…16 → `$0.chordsSteps`; RATE = `ForEach(StepRate.allCases)` 34×24
  r5 chips → `$0.chordsRate`. RATE values `Models.swift:1972-1977`: `"2/1"=8, "1/1"=4, "1/2"=2, "1/2."=3, "1/4"=1, "1/8"=0.5` beats.
- **18-row grid** `chordsGrid EuclideousPage.swift:3030-3069`, cell `chordsCell :3070-3114`: label col `labelW 36`
  `euclideousChordsRowLabel Derivations.swift:1401-1414` (0–6 diatonic, 7–10 borrowed, 11 REST, divider, 12–17
  `7/9/6/ADD9/SUS2/SUS4`); row→degree `euclideousChordsRowDegree :1375-1382`. Lit fill srcChords `#B9A8FF`
  (lit REST `#5C626C`), r4; cols beyond STEPS at opacity 0.42/0.30 but editable (chords-grid §3.5). Degree tap =
  unconditional write; colour tap = light/clear.
- **Playhead:** `chordsPlayingColumn EuclideousPage.swift:2896-2900` → `euclideousChordsPlayingColumn Derivations.swift:705`.
  WASH = the tinted playing column drawn inside the grid `:3034-3040` (white 0.06 rect, `playingCol` only while playing).
  BAR = `chordsPlayheadBar :3118-3130` (r1.5 `#DFE3EA` h `playheadBarH 3`), placed `:2849-2850`, nothing stopped.
- **POOL block** `sourcesPoolBlockV2 EuclideousPage.swift:2768-2788` (placed `:2853`): label 84 wide + 8 `poolChip`
  (36 tall, source colour) + "+n". **Finger-down COL preview** `:2827-2841`: `chordsHeldColumn` (held cell
  `:3062-3064`) → `euclideousColumnPreviewPool Derivations.swift:4285`, label `"COL n"`, passed as `preview:`.

## B. Progressions model — how many, and how two play at once

- **Exactly TWO** progressions. `euclideousChordSets: [MachineParams]? Models.swift:3498`, `activeChordSet: Int? :3499`;
  `euclideousChordSetsResolved :3502-3507` always returns 2 (`[euclideousChordsResolved, MachineParams()]` when nil);
  `activeChordSetResolved :3508` = 0|1. **`activeChordSet` is ONLY the edit tab now** (`:3500-3501`), NOT what plays.
  One write path `setEuclideousChordSet(idx, params) :3511`. Legacy single grid `euclideousChords :3488` decode-only;
  `normalizeChordSetsAtLoad` migrates an old 4-set doc → 2 (`PresetStore.swift:31`, `FourfoldAudioUnit.swift:737`).
- **A lane picks its grid** via `poolSrcMask: UInt8? Models.swift:755` (bits: 0 MIDI IN · **1 CHORD 1** · 2 PICK ·
  3 KEY · **4 CHORD 2**; consts `:1316-1319`; default nil → `0b01111` = CHORD 1 on, CHORD 2 off, via `poolSrcMaskResolved :768`).
  `euclideousLaneChordGrid(mask) Derivations.swift:10383` → `0` (CHORD 1) or `1` (CHORD 2). Router reads it at
  `Router.swift:2825` (canon) and `:2857` (live lane sources) → `chordRateBeats(grid)` + `chordSeqNotesInto(…, grid:)`.
- **⚠ A lane can NEVER have both grids on.** `setPoolSrc Models.swift:779-787` clears the other chord bit (`:784`),
  and `euclideousPoolSrcNormalized :1321-1325` drops CHORD 2 if both set (`:1323`, also on decode `:1194`). So the
  lane-strip §5.7 "Both on → both names joined by ' · '" state is **unreachable** with the current (shared) setter.
  See §E CONTRADICTIONS.
- **SOURCES row UI (shared state for §5.7):** `poolSourcesRow EuclideousPage.swift:6068-6094`; labels
  `["MIDI IN","CHORD 1","PICK","KEY","CHORD 2"] :6073` in display order `euclideousPoolSourceOrder [0,1,4,2,3]`
  (`Derivations.swift:10646`); lit `line.poolSrcOn(b) :6077`; tap `edit(idx){ $0.setPoolSrc(b, !$0.poolSrcOn(b)) } :6086`.

## C. The playing-column formula and every reader

- **ONE formula:** `euclideousChordsPlayingColumn(beat m, rateBeats) = floor(m/r)` (`r<=0 → 4`) `Derivations.swift:705-708`.
  Returns the RAW unbounded step; STEPS-mod + ROTATE are applied DOWNSTREAM.
- **Readers of the raw step → resolved column:**
  - Engine resolve `chordSeqNotes Derivations.swift:720` (`:727`) and render-thread `chordSeqNotesInto :815` (`:827`),
    which pass `step` into `chordsDegreeAt(step:count:rotate:element:) :1907` → `((step+rotate)%n+n)%n` (n = STEPS) +
    CARRY; colour source via `chordsSourceStepAt :1930`.
  - Router window resolve `Router.swift:2733` (`Int((m/chordRateBeats(grid)).rounded(.down))`, **no ε**),
    `chordRateBeats(grid) :2720` picks per-grid rate; canon/delay reads via `euclideousCanonChordRead Derivations.swift:10299`
    (`floor((m−d+1e-9)/rate)`, has +1e-9) and `euclideousCanonStepBeat :10314` (step middle).
  - Display playhead `chordsPlayingColumn EuclideousPage.swift:2896` (does its own `((col+rotate)%steps+steps)%steps`).
  - Chord NAME `chordsNameAndIsRest EuclideousPage.swift:2904` (reads the AUTHORED column, rotate 0).
  - The SOURCES-row chord name and the POOL NOW row read the **lane pool status feed** (`writeLanePoolStatus`
    `Router.swift:3001/3350` → `EuclideousLanePoolStatus AnswerTab.swift:287-305` → `AnswerLiveModel AnswerLive.swift:7-15`
    → `PoolNowChipsView`), i.e. the already-resolved, already-delayed pool — NOT a second column computation.
- **§3.1 target:** the new `chordColumn(progression, beat, schedule, barBeats)` must REPLACE the raw-step formula at
  all of the above and return the resolved column; §5.7's lane strip reuses the pool-status feed (never recompute).

## D. Lane-cards block frame, tab strip, overlay rule

- **Block frame = union of the four cards** = `page.lanes[0].union(page.lanes[3])` (`EuclideousPage.swift:1824`;
  same size as the MIX panel, `euclideousMixRowsPanelSize MixPanel.swift:107 = (stripWidth, 2·laneBox.h + 8)`).
  `euclideousPageLayout Derivations.swift:4902`; metrics `:4621-4635` (margin 16, gap 8, header-A top 64, header-B top 111).
  - **Landscape 1190×726 (header .a):** union **769.33 × 610** at **x 16, y 100**.
  - **Portrait 814×1102 (header .b):** union **782 × 611.33** at **x 16, y 147**.
  - **⚠ FERRY FRAME IS WRONG:** the ferry's "756 × 606 block / 724 × 574 content" does not match code (769.33×610;
    content after §4.4's 16-padding = 737.33 × 578). All §5 pt positions are keyed to the wrong reference — must be
    re-derived against 769.33 (source wins). See §E.
- **Tab strip** `Derivations.swift:4923` at x 16, y = top (64/111), width = block width, height **28**
  (`EuclideousLaneStripMetrics.height LaneViewStrip.swift:53`); segments RHYTHM·RIFF·NOTES·POOL·ANSWER·MIX
  (`EuclideousPage.swift:670`). Cards start `28+8` below (`laneTop Derivations.swift:4926`).
- **One-overlay rule:** mutually-exclusive `@State` bools + "which-item" Int?/enum flags, cleared by
  `closeAllOtherOverlays() EuclideousPage.swift:2275-2279` (keyPopupOpen, chordsPopupOpen, resetPopupLane,
  swingPopupOpen, riffTabMenuLane, chordsTabMenuIndex, sourcesPopupOpen, hocketPopupOpen). Covers presets (`:2171`),
  settings (`:2184`), hocket (`:2223`), SOURCES (`:2089`), key, swing, reel. The new page joins this family.
- **No per-card "NOW chord" row** exists; the per-lane current chord is only the POOL tab NOW row (§C feed).
- **Framing:** `EuclideousStackBreak EuclideousPage.swift:678` + `.offset(x: lanes[0].minX, y: lanes[0].minY)` is the
  pattern (exactly how `mixPanel :3380` / `mixPanelShows :3362` frames the MIX panel to the block).

## E. CONTRADICTIONS / discrepancies to resolve (ferry vs code)

1. **Lane strip "both grids on" is unreachable.** §5.7 shows two independent "1"/"2" buttons and a "Both on" display,
   but the shared `setPoolSrc` makes CHORD 1 / CHORD 2 mutually exclusive (§B). Either the buttons stay exclusive
   (matching POOL; "both on" never shows) or the model changes — but §6 keeps the POOL tab/setter UNCHANGED.
   **Needs Paul.**
2. **Block frame 769.33×610, not 756×606** (§D). Source wins; §5 positions re-derived against 769.33 / 782. Report only.
3. **Title "key short name" vs live chord.** §5.1 wants `"CHORDS · <key short name> (Cm)"`; today the title shows the
   LIVE chord name (`chordsNameAndIsRest`). Build the spec (key short name) and confirm a key-short-name source exists.
4. **New TIME formula adds +ε** (`floor((beat−r+ε)/rate)`) that today's live path lacks (`Router.swift:2733` has no ε;
   canon path has +1e-9). §3.4/test 1 require byte-identity with today under TIME+restart-off — must prove +ε moves no
   boundary in the golden (factory presets, 32 bars) and the per-window resolve.
5. **pool DELAY ∘ advance (§3.7).** The delay path (`euclideousCanonChordRead`) computes its own `floor((m−d)/rate)`; with
   LOOP/RIFF advance the step is an event count, so the delayed read must also go through `chordColumn` at the delayed
   beat. Integration point for the build.

## F. Model-wiring path to mirror (§2.6) — the 7 new fields

- `MachineParams Models.swift:2076` uses **SYNTHESIZED Codable** (no CodingKeys/encode/init in 2076-2245) → new
  Optional fields auto-travel (`encodeIfPresent`/`decodeIfPresent`: nil omitted → old docs byte-identical, §2.4).
  Add the 7 fields next to the other `chords*` fields (`Models.swift:2168-2213`) + `*Resolved` helpers.
- **Snapshot:** add the 7 to grid 1 (`SnapParams` beside `chordsSteps`/`chordsRateBeats`, `Snapshot.swift:358-369`)
  AND grid 2 (`ChordGridSnap :376`). **SnapshotBuilder fresh-literal:** set them for both grids at
  `SnapshotBuilder.swift:177-190` (grid 1 `sc.procs[0].*`, grid 2 `ChordGridSnap(...)`).
- **Undo / resync / probe:** they ride `euclideousChordSets` automatically (whole-`MachineParams` compare): undo
  restore `FourfoldRootView.swift:738-739`, apply `:757`; resync `:962` (`if echd != euclideousChordSets`); probe
  hashes `FourfoldUndoProbe.swift:42,53`. Nothing new needed beyond the MachineParams fields + the snapshot spots.

## G. The RESTART UNITS schedule (§3.6 dependency) — NOT on main

- No "schedule" / riff-completion / loop-with-cumulative-counts API exists on main (the only `EuclideousRestartUnit`
  hits are the old LANES-GRID 4STP/PASS/2PASS). The pre-ferry closed forms the schedule will repackage
  (per `5ef838e`): `euclideousRhythmChainOrigin/NextRhythmRestart/PassIndex/PassStart`, `euclideousMelodyChainOrigin/
  IsMelodyChainRestartPass/NextMelodyRestart`, `euclideousFXWalkPeriod` (riff cycle), `euclideousChainHitsBefore`.
- §1.2 loop = rhythm restart if the rhythm chain is active, else pass; §1.3 riff completion = RESTART UNITS 2.7 (both
  kinds). §3.6: read cumulative counts + binary search, no render-thread alloc; if the schedule doesn't expose riff
  completions / loops with cumulative counts, ADD them there (RESTART UNITS §4.1 owns it) and report. **To verify once
  it lands:** the schedule's riff-completion + loop event APIs and their cumulative-count accessors.

## H. 8×8 State CHORDS processor + chord door (must not change, §2.5 / test 9)

- The forked `AUExtension/` copy reads only 11 `chords*` fields via `applyChords AUExtension/SnapshotBuilder.swift:12`
  (processor `AUExtension/Router.swift:7532`, door `AUExtension/Kernel.swift:350`, both → `chordSeqNotes
  AUExtension/Derivations.swift:1235`). None of the 7 new field names exist in AUExtension. **Fourfold is a fork**, so
  adding fields to Fourfold's `MachineParams` cannot reach AUExtension at all; Fourfold has no chord processor/door
  (trimmed). §2.5 satisfied by the fork boundary; test 9 runs unchanged in the 8×8 target.
