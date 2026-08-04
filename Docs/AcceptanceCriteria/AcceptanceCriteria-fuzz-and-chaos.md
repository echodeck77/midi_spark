# AcceptanceCriteria / PLAN — ENGINE FUZZ HARNESS + ON-DEVICE CHAOS MODE
_From the design ferry (design-ferry-fuzz-and-chaos, 2026-08-04; direction ratified by Paul, pre-TestFlight
hardening). This is Code's PLAN grounded in the codebase + the answers to the ferry's OPEN FOR CODE items._
_Status: **BUILT 2026-08-04.** Layer 1 (fuzz harness) is complete + green (412 tests); Layer 2 (chaos mode) is
built, `#if DEBUG`-gated, and compile-verified — DEVICE run owed. Additive test infrastructure; blocks nothing._

## BUILT — what landed
- **Layer 1 — `Tests/FuzzTests.swift`** (5 tests, ~18 s): `mulberry32` seed → random doc + a spell-driven pool
  (**held → short → silence**, per the user) with pathological orderings, driving `Router.process` + the recording
  double. Asserts: **I5** (in-range), **I1/I2** (no key left sounding after flush — via LAST-event-per-key, NOT a
  net count), **I8/I10** (`Router.quiescent`), **I6** (determinism — same seed ⇒ byte-identical stream, 200 seeds),
  **I12** (SnapshotBuilder totality, 4000 docs), **I13** (NotePool robustness, 3000 seqs). Failing seeds pin into
  `testPinnedRegressionSeeds`. Router gained `quiescent` (+ `hasDuplicateVoices`, unused pending an adoption-aware I3).
- **Layer 2 — `AUExtension/ChaosDriver.swift`** (`#if DEBUG` — whole file): a seeded, jittered, MAIN-thread loop that
  drives ~24 AU control handlers (claim/duck/alt, receiver channel/range/bypass/latch/mute, masters, ladder, panic…)
  while the engine renders live. Seed shown on the dev overlay + written to a per-session dump (`chaos-0x<seed>.log`).
  Chaos v1 = minimal dump. TWO MIDI SOURCES (user 2026-08-04):
  - **SIMULATED** (`▶ SIM MIDI`) — chaos injects its OWN seeded spell-MIDI (held → short → silence), so a soak is
    self-contained (no controller). Injection: `Kernel.chaosEnqueue` (main) → drained at the top of `render()` into
    the SAME `handleIncoming` path host MIDI uses (a debug-only `OSAllocatedUnfairLock` — a deliberate, #if DEBUG,
    never-shipped exception to no-locks-on-render). AU hook `chaosInjectMIDI`.
  - **LIVE** (`▶ LIVE MIDI`) — MIDI from the host (AUM + a real latched chord); chaos fuzzes only controls.
  - **THE OUTPUT ORACLE** (user 2026-08-04) — a live watchdog reading the diag each loop, highlighted on the overlay
    + written to the log:
    - **STUCK** (precise): transport stopped + no notes held, yet notes still sounding → a hung note.
    - **SILENT** — now **precise about the structural cause** via `diag.routedPath` (a render-side scan: does any
      occupied, audible cell ADMIT a held note AND route to an ENABLED emitter?). Silence with **no routed path** is
      **EXPECTED** (nothing routes) and NOT flagged; silence **with** a routed path is **SUSPICIOUS** and flagged.
    - **The MIDI-CHAIN DUMP on silence** (user 2026-08-04): when the suspicious streak crosses threshold, the RENDER
      side (safe access to box+pool) builds a full chain dump — held notes · per-receiver filter/range · every audible
      cell's (receiver · admits · buses · enabled-emitter · → PATH) · a VERDICT line — stashed via a lock and
      appended to `chaos-0x<seed>.log` by the driver. So the log now says WHY it's silent, not just "silent".
    - The dump can't be 100%-certain a suspicious silence is a bug (a closed passgate / chance / arp-tick legitimately
      gates a routed path), but it rules out the expected-silence cases and hands a precise routing snapshot to dig from.
- **The harness caught its OWN invariant-check bugs first pass** (validating the approach): the net-count I1/I2 was
  wrong (refcount folds many ons into one off → last-event-per-key is correct), and the naive I3 flagged legitimate
  refcount collisions — both corrected. `quiescent` never failed → the engine is genuinely clean under the fuzz.
- **Determinism CONFIRMED** on the engine (I6 green) — locks in the "no Date/RNG on the render path" invariant.

## The SEED LAW (both layers)
Deterministic PRNG seeded per run; seed + build number replays the exact sequence. **Reuse the existing
`mulberry32`** (already in the pure test target, powering `SealRNG`) — proven, reproducible, no new dependency.
Fuzz: seed printed on failure → the failing seed is PINNED as a named regression test (the LEGATO pattern). Chaos:
seed on-screen + written to the App Group with the event stream.

## LAYER 1 — ENGINE FUZZ HARNESS  (first · ~1 Code-day · CI-forever)
A new test file/target `FuzzTests` in the macOS test target (the pure, Foundation-only set:
Derivations/Models/Snapshot/SnapshotBuilder/Router/NotePool/PresetStore). It drives the **Router** (via
`process()` + the `RecordingEmitter` double) and the **document→box** layer (SnapshotBuilder) — the same seam the
407 existing tests use.

### What the harness generates (mapped to real inputs)
- **note storms** → a fuzzed `NotePool` sequence: off-before-on, double-on, hanging-on at stop, empty/1/full-128,
  vel {0,1,127}. (NotePool + `captureFiltered`/`latchAddStep` are pure → also fuzz them directly.)
- **config mid-pass** → rebuild the `SnapshotBox` (new generation) between windows: treatment/face/trigger swaps,
  chain edits, receiver channel/range/enable/bypass, emitter roles.
- **scene swaps / re-cue** → `sceneFlush` + generation change at/across pass boundaries.
- **LATCH / KEYS(+) ** → `latchMask` toggles + a fuzzed frozen `latchedPools` while notes sound.
- **DELETE chain-head / PLACE graft** → document-level slot delete/insert (inherit-on-delete), rebuild.
- **CLAIM/DUCK/ALT flips** → box masks (`claimMask`/`flattenMask`/`altMask` + params) mid-coalition.
- **KEY±** → `masterKey` during held chords. **fader-kill** → `velKillMask`/`masterKill` boundaries.
- Length-jittered, thousands per run; occasional bursts + idles.

### Invariants (assert INVARIANTS, not outputs) — mapped to what the engine exposes
From the emitted stream (`RecordingEmitter`) unless noted:
- **I1** on/off pairing, no orphans post-`allNotesOff`/panic — generalise `assertNothingLeftSounding` (net sounding
  per (cable,ch,note) == 0 after flush; note the collision refcount makes on,on,off legal, so it's a NET check).
- **I2** nothing sounds after stop + settle — same post-flush net check after a `playing:false` window + `drainDue`.
- **I3** no duplicate live voices for the same note+emitter+Colour-and-face — needs a small engine hook (below).
- **I4** cycle bounds — grid-chaining is RETIRED (cells are always MIDI-IN, `resolvedParent = -1`), so inter-cell
  cascades can't occur; within-cell fan-out (harmonize×4/strum/arp) is per-window bounded → assert no window emits
  > voice-capacity events.
- **I5** MIDI in range — every emitted note/vel ∈ 0…127, status ∈ {0x80,0x90}, cable 0…4, chan 0…15. Trivial.
- **I6** determinism — run each sequence TWICE, diff the streams byte-for-byte. **Confirmed holds by design**
  (CHANCE = hash of (position,note); random-arp = tick hash; no `Date()`/RNG on the path). Cheapest high-value check.
- **I7** inherit-on-delete — document/builder level: delete chain-head slots on random cells, rebuild, assert the
  box is well-formed (no orphan slots, `resolvedReceiver ∈ [-1,3]`, 64 cells).
- **I8** config-mutation never throws + post-pass consistency — swap the box mid-sequence; assert no trap + the
  QUIESCENCE self-check (below). NOTE: "deadlock" is not applicable to the single-threaded pure Router — it's a
  Kernel-store/threading concern → Layer 2.
- **I9** withheld/claimed accounting balances — source notes routed == emitted + withheld (via `drainWithheld`);
  none lost untracked. Trickiest; may want a small per-window counter.

### Engine-specific invariants Code adds (answering "extend from engine internals")
- **I10** refcount never underflows (closeVoice guards) and post-flush ALL `refcount == 0` (no leak).
- **I11** voice-capacity respected — `openVoice` drops at 128 without overflow/corruption (stress full pools).
- **I12** `SnapshotBuilder.build(from:)` TOTALITY — ANY random document never traps; yields 64 cells, masks in
  range, `resolvedReceiver ∈ [-1,3]`. **Highest payoff, cheapest** (no process loop; the builder is pure).
- **I13** `NotePool` robustness — random on/off orderings + `captureFiltered`/`latchAddStep` with random
  filters/ranges never trap; `srcCount`/`srcAscending` indices stay in bounds.
- **I14** bounds-safe scene access (`SceneState.cellAt/setCell/inBounds`) — random col/row never traps.

### Small shipping-code hooks Layer 1 needs (cheap, debug-guarded)
- **`Router.quiescent`** (I8/I10): after `allNotesOff`, `distinctSounding == 0 && activeVoiceCount() == 0 &&
  refcount.allSatisfy { $0 == 0 }`. A one-line self-report the harness asserts.
- **`Router.assertNoDuplicateVoices()`** (I3): no two ACTIVE non-silent voices share (note,chan,cable,colourIndex,
  alt). Debug-only.
These are the ONLY shipping-code touches; everything else is new test code.

## LAYER 2 — ON-DEVICE CHAOS MODE  (later · as TestFlight nears · debug-only)
Compile-flag gated (`#if DEBUG && CHAOS`) — impossible to ship enabled. A `ChaosDriver` that calls the SAME VC
handlers real touches call (`triggerTap`, `doVerb`, `armLadderRung`, `toggleReceiverLatch`, `setClaim`,
`nudgeMasterKey`, scene ops, cog edits, faders, MUTE/PANIC) on a seeded loop with jittered ms gaps (bursts +
multi-second idles), a speed multiplier, hosted in AUM with a latched chord so voices stay live. This catches the
render↔main races + UI/engine desync the pure harness cannot (e.g. the header-dot poll crash class fixed 2026-08-03).
Session record = seed + build + event stream → pairs any `.ips` with its input history.

## Answers to OPEN FOR CODE
1. **Invariants** — extended with I10–I14 above; I8 self-consistency = `Router.quiescent`; I3 = `assertNoDuplicateVoices`.
   Both are cheap internal self-reports. Determinism (I6) is CONFIRMED by construction.
2. **Ring-buffer logger** — recommend chaos v1 ships with the **minimal event-stream dump** to the App Group (seed +
   build + timestamped events). It already satisfies the SEED LAW + the incident format; the full ring-buffer logger
   is a fast-follow once the event vocabulary stabilises. Don't gate chaos v1 on it.
3. **CI budget** — the pure harness is very fast (407 tests ≈ 2 s; the Router runs thousands of windows in ms).
   Recommend: **~2–5k length-jittered sequences in the standard `xcodebuild test` run** (adds ~10–30 s, incl. the
   I6 double-run), plus a **separate nightly-soak scheme** (time-boxed ~15–30 min, 100k+ sequences) that pins
   failing seeds. Failing seeds are committed as pinned tests, never discarded.

## What FIGHTS the codebase (flags)
- **The KERNEL is outside the pure test target** (imports AudioToolbox): the incoming-MIDI/UMP decode, the
  passthrough gate, the latch ORCHESTRATION timing, and the render↔main `SnapshotBox` store are NOT Layer-1-fuzzable.
  Their pure PIECES are (NotePool capture, SnapshotBuilder, frozen-pool emission). Recommendation: accept that the
  Kernel's orchestration + threading is inherently **Layer 2** territory; OR extract a thin Foundation-only
  `KernelCore` for the latch/pool orchestration if we want it fuzzable pre-device (a bigger, optional refactor).
- **I8 "deadlock"** — not reachable in the single-threaded pure Router (no locks). It's a Kernel-store race concern →
  Layer 2.

## Sequencing / effort
Layer 1 now (~1 Code-day: `FuzzTests` + mulberry32 seeding + generators + the invariant asserts + seed-print/pin
helper + the two debug self-checks). Layer 2 as TestFlight nears. Neither blocks the open queue.
