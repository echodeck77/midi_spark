# Standalone app — plan (DEFERRED milestone; seams enforced NOW)

STATUS: no standalone work is scheduled and none should be started. This
document exists so that (a) the migration doesn't accidentally make standalone
expensive, and (b) when the milestone opens, the approach is already decided.

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

1. **Import hygiene.** Only `MidiSparkAudioUnit.swift`, `AudioUnitViewController.swift`,
   and `Kernel.swift` may import AudioToolbox / AU-specific frameworks. Router,
   Derivations, Snapshot*, Models, Emission, Diag, TestSessions, and EVERYTHING in
   GridUI stay Foundation/SwiftUI-only. (GridUI will be shared by both targets; an
   AU import there is a future build error.)
   - **Kernel is the render boundary, and keeps AudioToolbox on purpose**: it reads
     the host transport/musical-context blocks and the `AURenderEvent`/`AudioTimeStamp`
     render types. Rule 2 is exactly what lets standalone swap the SOURCE of those
     reads later; only then does Kernel shed the import. Kernel also hosts
     `LiveMIDIEmitter` — the one adapter onto `AUMIDIOutputEventBlock`.
   - **Router is now clean** (was a violation through v0.6). It emits through the
     Foundation-only `MIDIEmitter` protocol (`Emission.swift`) and names sample times
     as plain `Int64`; the AU integer typedefs it used (`AUEventSampleTime`=Int64,
     `AUAudioFrameCount`=UInt32, `AUParameterAddress`=UInt64) were only aliases. Payoff:
     the entire render engine — tick generation, graph derivation, the 5-cable refcount
     — now compiles into the macOS unit-test target (`RouterTests.swift`, a recording
     `MIDIEmitter` double asserts no-stuck-notes / §7b two-cable / channel stamp).
   During the migration survey, list any current violations; fix them in the
   commit that touches the offending file anyway.
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
- **Logged design questions (do not solve early)**: instance-per-Colour vs
  per-cell (economics vs same-Colour-same-column collisions); plugin
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
