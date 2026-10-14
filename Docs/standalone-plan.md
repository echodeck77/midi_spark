# Standalone app — plan (ACTIVE as of 2026-10-14 — FourStep)

STATUS CHANGED 2026-10-14: this is no longer a deferred milestone. Paul's
decision: Euclideous ships as **FourStep**, a standalone AUv3 *and* standalone
app, built as a SEPARATE Xcode target sharing the engine sources with
MidiSpark/8x8 State (not a reskin of the existing target, not a fork of the
engine — see CLAUDE.md's "Scope" section for how the two products relate).
The three seam rules below are now LOAD-BEARING, not aspirational — every
change to Router/Kernel/Emission should be checked against them, because a
second host is being built on top of them, not hypothesised about.

## FourStep target — decisions needed before creating it (none of these exist
## yet; this is the checklist for when the target is actually scaffolded)

- **Bundle ID.** `com.paulbarrett.FourStep[.AU]` is the default-by-convention
  choice (same prefix as MidiSpark) unless Paul wants a distinct developer/
  company identity for this release. Paul's call.
- **`aumi` component subtype + manufacturer code.** MidiSpark's are `MSpk`/
  `MSPK` and CLAUDE.md is emphatic those never change because saved AUM
  sessions key on them — the same will be true the moment anyone saves a
  FourStep session, so this is a ONE-WAY DOOR to get right before shipping,
  not something to default quietly. Needs an explicit 4-char subtype (e.g.
  `4Stp`/`FStp` — not yet chosen) and a decision on whether the manufacturer
  code stays `MSPK` (same developer) or changes too.
- **App identity.** Display name, icon, `CFBundleDisplayName` — independent of
  MidiSpark's "8x8 State" branding; FourStep is its own product listing.
- **Source sharing, per the rejected-alternative principle above (one engine
  artifact, not two integration paths):** the new `FourStep`/`FourStepAU`
  targets should point at the SAME `AUExtension/*.swift` engine files
  (Router/Kernel/Derivations/Models/Snapshot*/Emission) via target membership,
  exactly like MidiSparkAU does today — not a copy, not a framework (still
  rejected, see "Explicitly not now" below). Open question, not yet decided:
  does the FourStep AU target need `BuildPage.swift`/`RoomsPage.swift`/
  `GridUI.swift`/`RackMatrix.swift` at all? Those are pure 8×8-grid-workbench
  UI, structurally irrelevant to Euclideous (which only ever composes
  `Snap.euclideousRow`) — likely excludable from that target's source list to
  keep it lean, but this hasn't been audited or decided.
- **The standalone APP side's own work (described below, still fully
  unbuilt):** internal transport, CoreMIDI shell, silent render pump. Was
  "later, when the milestone opens" — the milestone is now open.

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
