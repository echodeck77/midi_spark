# PLAN — the per-parameter LFO (the ∿ "mod button" beside a param label)

A **mod button next to any relevant parameter's label**: tap it, set a WAVEFORM + a DURATION (+ a DEPTH), and that
param oscillates over time — an LFO wired straight to the setting. First targets: the ARP's **LENGTH** (gate) and
**SPEED** (rate). Paul 2026-09-14.

> **The good news:** the engine is ~80% built. The MOD processor already has a pure, beat-derived waveform kit; Span
> Automation already proves render-time scalar-param override from the beat; and MOD's `THIS CHAIN` mode already
> modulates a chain param with a waveform. This feature is mostly a **new inline authoring affordance** over those
> pieces + one small render pass — not new DSP.

---

## 1. Where this sits among the modulators (deliberate, not accidental overlap)

The app will now have four ways to move a value. This is the fourth; keep them distinct:

| surface | shape of motion | authored where | engine |
|---|---|---|---|
| **AUTO panel** (`PLAN-processor-automation-controls.md`) | a **positional** FROM→TO ramp across the part grid (where you *are*) | part-page ⟲ arm | `AutoLane` → `renderAuto`/`settingAuto` |
| **MOD cell** (`ProcessorType.mod`, `THIS CHAIN`) | a **temporal** waveform, but as a *separate chain slot* targeting a `MacroParam` | a MOD box in the chain | `applyInternalMods` → `applyModChainOffset` |
| **Macros** | a host/slider offset folded at build | MACROS tab | `applyMacros` (bakes at publish) |
| **★ Param LFO (this plan)** | a **temporal** waveform, authored **inline on the param itself** | a ∿ button on the param label | `modUnipolar` → `settingAuto` (new `applyParamLFO` pass) |

The Param LFO is the **inline, per-param, no-extra-cell** temporal modulator. It shares the AUTO panel's *curation*
(which params are worth modulating) and its *render-write path* (`settingAuto`), and it reuses the MOD processor's
*oscillator* (`modUnipolar`) and *glyphs* (`waveGlyph`/`iconSeg`). It differs from a MOD cell only in that it needs no
slot in the chain and reads as an attribute of the control.

**Coexistence:** AUTO ramp (position) + Param LFO (time) can both target the same param — sum the offsets, clamp once
(the same way macros + AUTO already compose). Flag for Paul: allow both, or make them mutually exclusive per param? (Rec: allow; sum.)

---

## 2. The model (additive-Optional, no migration)

`MachineParams` (Models.swift:179) is an all-Optional, append-only, synthesized-Codable struct — appending new Optional
fields is decode-safe and byte-identical for old docs. A machine can carry LFOs on *several* params, so use a keyed list:

```swift
// Models.swift — append-only §12.0
struct ParamLFO: Codable, Equatable {
    var target: AutoParamField          // reuse the existing 24-target enum (Snapshot.swift:284); add .rate for SPEED
    var shape: ModShape = .sine         // reuse Models.swift:52 (SINE/TRI/SQR/RAMP/S&H)
    var period: ModRate = .r2           // the DURATION — one cycle in beats (reuse ModRate)
    var free: Bool = false              // FREE = ride the global grid clock (seamless loop), like modFree/SPAN FREE
    var depth: Double = 0               // 0…1 — swing amount around the base (0 = off)
    var phase: Double = 0               // 0…1 (×360°), reuse the modPhase idea
    var quantize: Int = 0               // snap the output to N levels (reuse modQuantizeValue); 0 = smooth
}
// on MachineParams:
var paramLFOs: [ParamLFO]? = nil        // nil / [] ⇒ no LFOs, byte-identical
```

- **One LFO per target for v1** (a param has at most one entry). Enforced in the editor, not the type.
- `SnapParams` (Snapshot.swift) gets the resolved mirror `paramLFOs: [ParamLFO]` (empty default), copied by the builder
  exactly like the other resolved fields. Empty ⇒ builder emits nothing ⇒ byte-identical.

**Base-vs-motion contract:** the param's *own* control still sets the resting/**centre** value. The LFO adds a **bipolar
offset** around it: `offset = (modUnipolar(shape, phase', …) − 0.5) · 2 · depth · paramSpan(target)`. So the slider works
exactly as today when `depth == 0`, and the LFO "breathes" the value around wherever the slider sits. `paramSpan` reuses
the same span notion `macroParamSpan`/the AutoParamField lo–hi range already use.

## 3. The engine (reuse; ~one new function)

A new pure-ish render pass modelled on `applyRenderAuto` (Router.swift:1500), applied at the **same two sites** it is
(`emitTickRow` Router.swift:1521 and `emitColumnHolds` Router.swift:1702), gated `!box … isEmpty`:

```
for lfo in cell.procs[slot].paramLFOs:
    periodBeats = lfo.free ? gridWidthBeats : lfo.period.beats
    phase = fract((musicalBeat / periodBeats) + lfo.phase)          // beat-derived → replay-safe (invariant 2)
    u = modUnipolar(lfo.shape, phase, column, seed, cycleIndex)      // reuse Derivations.swift:76
    if lfo.quantize > 0 { u = quantized(u, lfo.quantize) }           // reuse modQuantizeValue idea
    let base = cell.procs[slot].<field for target>
    let v = clamp(base + (u - 0.5) * 2 * lfo.depth * span(target))
    cell.procs[slot] = cell.procs[slot].settingAuto(lfo.target, v)   // reuse Snapshot.swift:307 (value-copy, clamps, render-safe)
```

- **Invariant 2 (derived, never accumulated):** the phase is a pure function of the beat — no oscillator state. ✅
- **Invariant 3 (no render alloc):** `settingAuto` is a value-copy, `modUnipolar` is `@inline(__always)`; no heap. ✅
- **Invariant 4 (no stuck notes):** the LFO only *reshapes a scalar the emitter already reads* (gate/rate); it opens/
  closes no voices, so it can't strand a note. ✅ (Same safety class as AUTO/macros.)
- **Sampling granularity:** block-start, exactly like SMOOTH span-auto (`applyRenderAuto`) and `applyInternalMods` — the
  value is constant across a render window, updated per block. Deterministic per host schedule; **not** strictly
  block-size-invariant (the established, accepted convention for continuous modulation here). Smooth enough for gate at
  audio-block rate. *Per-note* evaluation (each arp note its own gate) is a flagged refinement, not v1.

## 4. The UI — the ∿ button + its editor

**The affordance (hooks into the existing label row).** `field(label, keypath)` (GridUI.swift:1488) and `heroField`
(GridUI.swift:1515) render the param label above its control. Add a variant that appends a small ∿ button to the label
row for **modulatable** params:

```
LENGTH 60%   ∿          ← ∿ sits right after the label; idle = dim hollow waveform; active = accent-filled + live shape
[========slider========]  ← a faint DEPTH band shades the swept travel on the param's own track
```

- **Idle:** a dim hollow `waveGlyph`-style ∿ — an invitation, receding like other defaults.
- **Active:** fills accent + shows the chosen waveform, with a faint moving phase dot so the label *visibly breathes*
  even before opening (reuse the `waveGlyph` Canvas at GridUI.swift:1709).
- **Tap → editor; long-press → clear the LFO** (spring-off), matching the house gesture grammar.

**The editor (a popover, reusing the MOD editor's controls).** There's precedent for mounting a processor editor in a
popover (the chord door mounts the CHORDS `ProcessorBox`). Mount a trimmed MOD-style editor:

- **WAVE** — `iconSeg` + `waveGlyph` (SINE · TRI · SQR · RAMP · S&H). Already built.
- **DURATION** — `seg(ModRate)` for the period, plus a **FREE** end (ride the grid, seamless loop).
- **DEPTH** — a fader; drawn as the shaded band on the param's own slider so the travel is visible.
- **PHASE** (0–360°) and **QUANTIZE** (snap to N levels) — both lifted straight from the MOD editor.

Because it hangs off `field`/`heroField`, giving *any* future param a mod button is a one-line flag — ARP is just where
we light it up first.

## 5. Which params get a ∿ (reuse the AUTO panel's curation)

The `PLAN-processor-automation-controls.md` ⟲ curation is exactly the right "worth modulating?" answer — reuse it, so a
param that's ⟲-armable is also ∿-moddable:

- **★ Continuous → always** — for the ARP: **LENGTH (gate)**. (Codebase-wide: SPREAD, CURVE, TILT, CHANCE, MOD MIN/MAX,
  SHORT/LONG, glide RANGE, …) `gate` is already an `AutoParamField` *and* a `MacroParam`, clamped 0.05…1 — reuse directly.
- **◐ Stepped → where stepping is musical** — ARP **OCTAVES**; also REPEATS, HITS, ROTATE, VOICES, euclid K. The LFO
  output quantizes to the integer steps (as `settingAuto` already casts `octaves`/`count` via `UInt8(ci(...))`).
- **◐ Rate (SPEED) → the one enum worth it** — a slow→fast rate wobble/ramp is musical (the AUTO doc arms it too). But
  `rate` is an `ArpRate` **enum**, absent from `AutoParamField`/`MacroParam` — see the fork below.
- **✕ Skip** — PATTERN, FLOW (phase), OCT DIR: too few discrete states; a waveform just chatters them. (If ever wanted,
  that's a "cycle every N bars" control, not an LFO.)

## 6. The one real fork — scalar (LENGTH) vs enum (SPEED)

- **LENGTH (gate)** is a clean scalar already wired end-to-end (`AutoParamField.gate` + `settingAuto` clamp 0.05…1). Ship
  it first with zero new target plumbing.
- **SPEED (rate)** needs: (a) a new `AutoParamField.rate` case; (b) `settingAuto` teaching to map a ramped `Double` →
  nearest `ArpRate` index (the same cast pattern `octaves`/`count` use); (c) a **DEPTH-as-a-band-of-rate-steps** model
  (the LFO sweeps between a lo and hi rate). **Caveat (flag):** modulating the arp's own clock changes its tick period
  mid-phrase — phase continuity across a rate change is a real feel question (accel/decel vs sudden flip). Keep SPEED as
  **stage 2**, LENGTH proves the mechanism first.

## 7. Build sequence (each stage device-verifiable)

1. **Model + engine (LENGTH only).** Add `ParamLFO` + `MachineParams.paramLFOs` + `SnapParams` mirror + builder copy;
   add `applyParamLFO` at the two `applyRenderAuto` sites; wire `.gate`. **Off-device tests:** LFO reshapes gate per beat,
   depth 0 == byte-identical, sine/square differ, replay-exact (same beat → same value), no stuck notes (fuzz a `.gate`
   LFO under held notes / transport edges).
2. **The ∿ affordance + editor (LENGTH).** `field`/`heroField` mod-button variant; the popover (WAVE/DURATION/DEPTH/
   PHASE/QUANTIZE) reusing `waveGlyph`/`iconSeg`; depth band on the slider. Device-eye: the button look, the live phase
   dot, the popover legibility.
3. **SPEED (rate).** `AutoParamField.rate` + `settingAuto` index-cast + the rate-band depth model; resolve the phase-
   continuity feel on device.
4. **Roll out to the rest of the ⟲ set** (OCTAVES, then other processors' continuous params) — one flag per `field`.

## 8. Open decisions (Paul)

1. **AUTO + LFO on the same param** — allow both (sum offsets, clamp once) or mutually exclusive? *(Rec: allow, sum.)*
2. **DEPTH semantics** — bipolar swing around the slider's base (this plan) vs. an absolute MIN↔MAX window (reuse
   `modMap`). *(Rec: bipolar-around-base — keeps the param usable unchanged when depth 0.)*
3. **Host automation** — expose LFO params on AU addresses (free range ≥ 500) for host recording, or editor-only for v1?
   *(Rec: editor-only v1; addresses are cheap to add later.)*
4. **SPEED phase continuity** — accept a rate that jumps at block boundaries, or constrain to smooth ramps only? (stage 2.)
5. **Per-note vs block-granular** — v1 samples per render block (matches every existing modulator). Ever want per-arp-
   note gate variation? (refinement, not v1.)

## 9. Risks / flags

- **Stale-base branch:** this plan lives on `worktree-arp-newchord-vertical`, which is behind `origin/main` (~41 commits);
  rebase before building so the `field`/MOD/span-auto line numbers above are current.
- **Not block-size-invariant** by design (block-start sampling) — the accepted convention, but note it in the spec so it
  isn't later mistaken for a bug.
- **Naming:** "mod button" is the working name; the glyph is ∿. Confirm the on-screen label/word (MOD? LFO? MOVE?).
