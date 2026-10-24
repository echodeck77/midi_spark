# Standalone app — plan (ACTIVE — Fourfold)

**Product name: Fourfold** (Paul, 2026-10-23). "FourStep" in older docs (and in CLAUDE.md) is the same product's earlier working name.

STATUS: this is no longer a deferred milestone (2026-10-14). Euclideous ships as **Fourfold**, a standalone AUv3 *and* a standalone app, built as SEPARATE Xcode targets that
start by sharing the engine sources with MidiSpark/8x8 State and then take their own trimmed copy of the engine (see "Plan of record"). The three seam rules below are LOAD-BEARING,
not aspirational: a second host is being built on top of them.

## PLAN OF RECORD (2026-10-23)

### Decisions (made)
- **Name / ids.** Company **Outlier MIDI** (Paul, 2026-10-24). App `com.outliermidi.Fourfold`, extension `com.outliermidi.Fourfold.AU` (was `com.paulbarrett.Fourfold[.AU]` until 2026-10-24; MidiSpark keeps `com.paulbarrett.MidiSpark[.AU]`). The reverse-domain `outliermidi` is a default, not a confirmed domain; the signing team (`DEVELOPMENT_TEAM` in project.yml) is unchanged — check it is the team that owns Outlier MIDI before the first TestFlight.
  AU component: type `aumi`, subtype `Frfd`, manufacturer `OutM` (Outlier MIDI; was `MSPK` until 2026-10-24, changed while no session could exist), AUM listing name "Outlier MIDI: Fourfold". **ONE-WAY DOOR** — AUM keys saved sessions on (type, subtype, manufacturer); never change `Frfd` once anyone has saved a session.
  MidiSpark's `MSpk`/`MSPK` are untouched. MIDI port names "All", "Out A"…"Out D" (the page already says MAIN OUT); exported files `Fourfold-*.mid`.
- **The one link back to 8x8 State goes:** the settings sheet's WORKBENCH footer (`EuclideousSettingsSheet.swift`, wired through `EuclideousPage.onClose`). 8x8 State keeps its own Fourfold overlay until Paul says otherwise.
- **Engine: share first, then copy-and-trim.** Trimming the shared engine in place would change 8x8 State (the product Paul runs in AUM today), so: Fourfold starts on the SAME `AUExtension/` engine files (target membership); once the LISTEN rebuild has landed and the
  Fourfold-only scene composer exists, the engine is COPIED into Fourfold's own folder and trimmed there. 8x8 State keeps the original, frozen (it is on hold). From then on engine fixes go to one side only — acceptable while 8x8 is on hold.
- **Host glue: copy-and-prune, not shared.** The Fourfold half of `DiagView` (AudioUnitViewController.swift: the 39 euclideous + 19 reel `@State`, the ~220-line `EuclideousPage(...)` callback block, the 30 Hz poll, undo, lane lock, presets) is ported into a new `FourfoldRootView`.
  `DiagView` is not touched.
- **Documents.** A new product starts clean: no migration of old sessions into Fourfold (sessions saved from Fourfold inside 8x8 State will not open in it unless an import is added later — Paul's call, not planned).

### Evidence behind the engine decision (measured 2026-10-23, coverage run of the Euclideous test list + 87 tests from three files that list was missing)
- Router: 3,143 of 7,494 runnable lines (42%) are never run by Fourfold's tests — ≈2,150 of them in whole functions only the 8x8 processors use (`emitDriverNote`, weave/tutti/strum/ratchet/length rows, column holds/recorder/glide, the superseded preview/audition code), ≈1,000 inside partly-used functions (the `process()` front end, `emitTickRow`, `emitOneBus`, and the six non-euclid generators in `emitGeneratorRow`).
- Derivations 22% unrun (≈1,190 lines are 8x8: seal/emblem, clock-drawn phase, length columns…), Models 28% (8x8 factory scenes, migrations), Snapshot 24%, Emission 23% (DoorRing, PartRoll).
- The big, hard code — `emitGeneratorRow`'s `.euclid` case (`runEuclidLine`, ≈2,500 lines) — IS Fourfold and is 90–100% exercised. Most of the engine's complexity is Fourfold's own, not unused features. Fourfold also carries >300 comments marking retired / legacy / decode-only code of its own.
- NOT planned: replacing the 8x8 grid scaffolding (one pinned row, receiver 4, the scene/snapshot shape) with a Fourfold-native engine front end — a rewrite, 2+ weeks, high risk.
- Unrun ≠ deletable until proven unreachable: the Fourfold-only composer (Step 1) guarantees only a `.euclid` cell can exist, which is what makes deleting the other processors provably safe. ≈150 lines INSIDE the Fourfold engine are unrun by any test (echo follower, rank inversion, `missNotesPool`…) — leave them alone.
- Probe (compile-only, scratchpad): the Fourfold UI + engine + settings + presets compile with the 8x8 UI/host files (≈13.7k of 58.4k lines) excluded and four helpers shimmed.

### Steps (each ends green: iOS build, the Fourfold test list, and the existing 8x8 targets unchanged)
1. **Targets + composer** — DONE 2026-10-23 (branch `feature/fourfold-targets`; see the status log) — (a) Move the four helpers the Fourfold files need out of `GridUI.swift` (`Color(hex:)`, `EuclidDragHUDInfo`, `machineHueOverride`, `machineHexes`) into a small shared file; split the 8x8 `CellBrowser` out of `PresetBrowser.swift`; fence the cell-library API (`LibEntry`) and the `TestSessions` loader in `MidiSparkAudioUnit` so Fourfold need not compile them.
   (b) `FourfoldCompose` (pure, Foundation-only): the ≈15 lines of `composeSceneMeta` that place the Euclideous cell, plus the chain; a test proves its scene equals `composeSceneMeta`'s for the same input. (c) `project.yml`: `Fourfold` (app) + `FourfoldAU` (extension, hand-maintained Info.plist with `Frfd`/`MSPK`) sharing `AUExtension/` minus an exclude list; a placeholder view. Exit: both build; the 8x8 targets still build; suite green.
2. **FourfoldRootView + AU on device** — DONE 2026-10-23 (branch `feature/fourfold-root`; simulator-verified with `Scripts/fourfold-harness`, device passes owed; see the status log) — Port the host glue; WORKBENCH link removed; the reel as a standalone view (not another `extension DiagView`; carry the REEL LINK changes: "output" wording, pass length line, no RESTORE SETUP); presets; branding. Exit: Fourfold runs in AUM from the new extension.
3. **App shell** — DONE 2026-10-23 (branch `feature/fourfold-app`; simulator-verified with `Scripts/fourfold-harness/app-test.sh`, device passes owed; see the status log; the app builds the AU DIRECTLY in-process, so no private component description or spike was needed) — Internal transport (mach time → beat), silent render pump, CoreMIDI in/out (five virtual sources All/A–D), document save/restore, background audio, icon/launch. The app compiles the same sources and registers the AU under a private component description (in-process) — still ONE integration path (the AU class), not the rejected "drive the Kernel directly". Starts with a one-day device spike to confirm in-process hosting. Exit: plays and sends MIDI with no host.
4. **Engine copy-and-trim** — IN PROGRESS 2026-10-24 (branch `feature/fourfold-engine`; (A) (B) (E) and most of (C) DONE: engine copy 26.3k → 20.6k lines, `FourfoldTests` 1,070 green, golden identical; left: Models.swift's 8x8 document types, Derivations' 8x8-flavoured helpers, (D); see the status log) (after the LISTEN rebuild lands; can run alongside Step 3). Copy the engine into `Fourfold/Engine/`, point the Fourfold targets at the copy, then trim in small green steps: (A) dead/superseded code (audition/preview); (B) the non-euclid processors in Router and their Derivations helpers; (C) 8x8 Models/Snapshot/Emission pieces (MachineParams fields, factory scenes, migrations, DoorRing/PartRoll); (D) Fourfold's own retired/decode-only layers (new product ⇒ no old sessions); (E) a `FourfoldTests` target holding only Fourfold's tests (membership by file, no classifier). Each step: the golden 32-bar preset renders, stress and fuzz tests stay green; compare the coverage list before/after.
5. **Release hygiene.** Docs renamed FourStep→Fourfold, in-app manual, TestFlight.

### Not changed by this plan
- `MidiSpark`/`MidiSparkAU`/`MidiSparkTests` and the 8x8 State UI. The existing aumi codes. `Scripts/classify_euclideous_tests.py` stays as the fast-run selector until Step 4(E) replaces it.


## The approach, decided: the app becomes MidiSpark's SECOND HOST

The standalone app hosts the SAME AUv3 extension (in-process where possible),
supplying what AUM supplies today:
- **Internal transport** providing `musicalContextBlock` / `transportStateBlock`:
  tempo + play/stop, beat position DERIVED from mach time (start-anchor +
  tempo → beat; the derived-never-accumulated doctrine, second beat source —
  "the AU is the clock" generalises to "the HOST's beat is the clock, and
  standalone-mode we are the host").
- **CoreMIDI shell**: inputs (hardware/virtual) → the AU's MIDI-event input;
  `midiOutputEventBlock` → FIVE named virtual MIDI sources, mapping the cable
  model one-to-one: "8x8 State ALL", "… A" … "… D".
- **A silent render pump** (minimal output unit) to pull the AU's render.

REJECTED alternative, on the record: linking the engine sources directly into
the app. It looks simpler but creates a second way of driving the Kernel —
two integration paths = behavioural drift, the disease this architecture
exists to prevent. One engine artifact; the app is just another host.

Later carrots that live here (not before): Ableton Link, background audio
session, files/document browser for Presets.

## The three seam rules (ENFORCED DURING THE MIGRATION — they are the entire
## "early support" cost, and they are nearly free while everything is open)

1. **Import hygiene (as built, post-v0.6).** `MidiSparkAudioUnit.swift`,
   `AudioUnitViewController.swift`, and `Kernel.swift` may import
   AudioToolbox — Kernel IS the render boundary (host transport/context
   blocks + render-event types; it hosts the `LiveMIDIEmitter` adapter and
   sheds the import only when the standalone swap replaces those host reads
   per rule 2). Router/Derivations/Snapshot*/Models/Emission/Diag/
   TestSessions and EVERYTHING in GridUI stay Foundation/SwiftUI-only —
   Router was made Foundation-only against the `MIDIEmitter` protocol
   (`Emission.swift`, which REALISES rule 3) and now unit-tests off-device
   (`RouterTests.swift`).
2. **The beat seam has ONE name.** The kernel consumes a single derived
   transport/context value built in one function from the host blocks. Keep
   it that way and keep it named: standalone swaps the SOURCE of that one
   value, nothing else. Do not let host-block reads smear into new code
   during the migration.
3. **The emission boundary stays the only place that knows the medium.** The
   (bus) → (cable, channel) mapping lands there in the outputs commit;
   standalone later adds (cable) → (virtual source) at the SAME boundary.
   Nothing upstream of emission may ever mention cables.

## Roadmap resident: EXTERNAL processors (hosted 3rd-party MIDI AUv3s)

DECIDED DIRECTION, DEFERRED WORK. A future Colour type EXTERNAL hosts a
3rd-party MIDI AUv3 as its treatment. Key facts, so nothing else is designed
in a way that blocks it:

- **Standalone-only by platform law**: app extensions cannot host other app
  extensions, so EXTERNAL Colours run ONLY in the standalone app. Inside a
  host (AUM), an EXTERNAL Colour degrades to IDENTITY with a visible warning,
  and documents round-trip losslessly. This makes the standalone app the
  platform for a headline feature, not just a port.
- **Integration model (already fits)**: an EXTERNAL cell articulates its
  input pool INTO the plugin at column entry and the router tracks the
  plugin's OUTPUT events into the cell's sounding voices — the same voice
  table as every other cell. Children sample those voices exactly as the
  graph model's persistent-state evaluation already specifies (the cycles
  decision built this interface). Truncate-at-boundary applies to external
  output at column exit, consistent with §7.
- **Router contract (STANDING — observe during the migration)**: the router's
  relationship to any cell is "articulate input in, track sounding voices
  out" — NEVER "call a pure function". Five of six current processors happen
  to be pure; the dispatch and data flow must not assume purity.
- **PHASE modes for EXTERNAL = HOSTING POLICIES (designed 2026-07; best-effort
  by nature).** We control each instance's musical context and its input:
  - FREE: report the TRUE beat (identity) — the plugin free-runs; zero work.
  - RETRIG: at column entry, relocate the instance's VIRTUAL beat to 0 (reads
    to the plugin as an ordinary host loop-point) AND re-articulate the input
    (off/on — restarts key-synced pattern state).
  - LEGATO: hold input across the run, virtual clock continuous from the
    run's start — the SAME runStartColumn derivation as internal LEGATO.
  Best-effort: sample-time free-runners ignore the virtual clock (RETRIG
  degrades toward FREE); plugins with their own sync settings may fight ours.
  Never promise more; surface a small ⓘ in the UI eventually.
- **Instance boundary = the PHRASE boundary (decides the old economics
  question): instantiate PER RUN**, not per cell (breaks LEGATO at column
  swaps — opaque state can't be transplanted) and not per Colour (same-column
  sibling runs collide). All cells of a contiguous run share one instance;
  phase mode is the within-run boundary policy. Runs are already
  snapshot-precomputed. Instantiation is slow/async: (re)build instances at
  EDIT time via the snapshot-rebuild pipeline, NEVER on the render path.
- **Remaining logged design questions (do not solve early)**: plugin
  fullState blob stored on the Colour; A/B for external = two plugin states?
  (morphing an opaque plugin: almost certainly never — resist); latency
  reporting; UI for plugin pick + view hosting.
- Audio plugins/effects: FAR-FUTURE note only — our AU is `aumi` with no
  audio path; only the standalone pump could ever grow an audio graph.
  Nothing is designed for this and nothing should be.

## Explicitly not now

No app-side transport UI, no CoreMIDI code, no pump, no framework-target
restructuring (target membership sharing suffices; a MidiSparkCore framework
is project surgery with zero present benefit — revisit when the milestone
opens). No standalone testing is expected until then.
