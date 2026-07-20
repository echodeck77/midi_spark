# MidiSpark — Specification v2.8 (consolidated edition)

*AUv3 MIDI effect for iPadOS.*

This is the complete, self-contained specification, consolidating revisions v2.0–v2.8 into one document with the v2.7 terminology sweep applied throughout (StackArp → MidiSpark; the colour-level object is a **Colour**, never a "preset"). It supersedes and replaces the delta documents. Behavioural content is identical to the v2.4 core + v2.5 §12 + v2.6 §13 + v2.7 + v2.8 chain.

---

## 0. The governing invariants

> **Nothing happens that the grid doesn't show.**

Every routing behaviour is visible as a wire, button, or lamp; every visible wire, button, and lamp corresponds to a real behaviour. No hidden defaults, no automatic fallbacks, no emission the UI doesn't display. Any future feature that violates this invariant is redesigned or rejected.

> *Unpredictable-what-it-sounds-like is musical; unpredictable-what-the-gesture-does is not.*

Performance gestures have exactly one meaning at a time; their sonic result may legitimately depend on patch context (the pedalboard property).

> **The gesture grammar:** Tap changes state. Hold borrows time (or intensity) and always returns it. Drag sets; spring borrows.

Universal across cells, stack buttons, row buttons, panel parameter buttons, and desk faders. Every hold/spring is momentary, composes with other holds, self-cleans on release, mode switch, or transport stop, and is never persisted.

> **The naming invariant:** interface words may not claim behaviours the app doesn't have, and may not collide with words the host has already taught the user.

Enforced precedents: CHANNEL → OUT CH (implied input); SOUND/MIX → COLOUR/MORPH (implied audio); preset → Colour at the colour level (collided with host presets).

**A structural fact promoted to design intent:** because Colour edits are global, the COLOUR panel is a sixteen-channel macro desk — the grid is the *score*, the panel is the *desk*. Panel-performance features exist to serve this second way of playing: leave the grid alone and ride the colours.

## 1. Terminology & the instance model

### 1.0 The three-layer hierarchy

Every layer owns exactly one word; spec, UI, manual, and marketing use them consistently:

| Word | Layer | Definition |
|---|---|---|
| **Colour** | the treatment | Type + parameters + A/B states + morph + transpose + OUT CH. Sixteen of them in a 4×4 bank. Editing a Colour updates every placement. |
| **Cell** | the patch point | One Colour placed at one grid position, carrying that placement's wiring (▾ / buses / +SRC) and performance state (alt / bypass / mute). |
| **Preset** | the host document | The entire saved plugin state (`fullState`) — the shareable/sellable session object. **Reserved: nothing inside the app may be called a preset.** |

### 1.1 The instance model *(normative)*

1. **Every cell is a completely independent processor invocation, unconditionally.** Placing a Colour never creates a link between cells. Two cells of the same Colour — anywhere, including within one stack — are two separate processors that happen to read the same definition.
2. **Colours are definitions, not objects.** A Colour is the shared *recipe*; editing it changes what every instance computes from that moment on. Nothing else is shared: each cell owns its wiring, its A/B flag, its bypass/mute, and its input as derived by the routing rules. One violet cell may play B while another plays A.
3. **Vertical same-Colour placement is chaining or parallelism, never continuation.** Two same-Colour cells in one stack joined by ▾ form a chain in which the lower instance processes the upper instance's output — *self-chains are legal and intended* (arpeggiating an arpeggio is a technique, not an error). Unchained, they are parallel duplicates; on a shared (bus, channel) the §7 collision refcount governs the duplicates. No vertical arrangement ever merges instances.
4. **Phase modes share derivation, never state.** There is no persistent arp object handed between cells. Each cell, at each moment, independently *computes* its pattern position from its mode's formula (RETRIG: position-in-step; LEGATO: position-in-run; FREE: global beat position). LEGATO cells in a run agree about phase the way two clocks agree about the time — by computing the same answer from the same reference, not by connection. LEGATO applies **horizontally only** (same Colour + same row + contiguous columns): columns are moments, rows are chain depth.
5. **Consequence for implementers:** because cells share no state, there is nothing to construct, destroy, or migrate when cells are painted, cleared, repainted, or when Colours are edited mid-performance — only definitions and formulas. Any implementation introducing per-cell mutable processor state must justify itself against this section.

*Quotable summary:* **Colours share definition; cells share nothing; LEGATO and FREE share a formula — which looks like sharing but is just agreement.**

### 1.2 Overview & format

MidiSpark is a grid-based MIDI processor sequencer. An 8×8 grid is swept left-to-right by a transport-synced playhead. Each column ("stack") holds up to eight MIDI processors, placed by painting Colours from the palette. The active column's processors transform incoming MIDI (typically held chords) and emit the results on up to four independent MIDI output buses — separate MIDI sources in the host's routing (e.g. AUM), so one instance can drive four instruments.

**Format:** AUv3 MIDI processor (`aumi`) in a container app, four MIDI outputs via `MIDIOutputNames` = ["A","B","C","D"]. **Primary host:** AUM; correct in any AUv3 MIDI-effect host including single-output (§8). **Platform:** iPadOS.

## 2. Routing model *(frozen)*

### 2.1 The rule
Each cell has exactly three wiring controls, and they define everything:

| Control | Meaning |
|---|---|
| **▾ stack** (on/off) | A cable to the cell directly below. On + occupied cell below = that cell is fed. |
| **A B C D** (each on/off) | Emission to that MIDI output bus. **Sound leaves the plugin only through a lit letter.** |
| **▸ src / +SRC** | Input indicator/modifier (2.2). |

There is no input selector. **The sender decides:** a cell's input is derived —
- If the cell above has ▾ on → this cell receives that cell's output (it is *fed*).
- Otherwise → this cell receives the **source** (the live held-note pool from plugin MIDI input).
- A fed cell with **+SRC** on receives the union of feed and source.

Consequences (all automatic, none configurable):
- The top cell of any run always hears the source.
- A cell below a chain end reverts to the source — chain ends are self-marking.
- An empty cell above means source input.
- A cell cannot refuse a feed; if ▾ is on above it, it is chained.
- A cell whose feeder is *muted* (§6.2) receives no feed and reverts to the source, exactly as if the feeder's ▾ were off. The wiring visualisation must show this truthfully (cable dark, source tap lit on the follower).

### 2.2 The ▸ control's two states
- **Unfed cell:** source input is automatic and guaranteed. ▸ displays lit-and-locked (a fact, not a choice).
- **Fed cell:** ▸ becomes the **+SRC** toggle — off (default) = feed only; on = feed + source merged.

### 2.3 Emission
- A cell emits its processed output on every enabled bus letter simultaneously (fan-out duplicates events per bus).
- ▾ and letters are independent: chain only, emit only, or both (audible tap mid-chain).
- **No fall-through:** ▾ with no occupied cell below sends the output nowhere — legal (deliberate chain-tail mute) but flagged (2.4).
- Buses are merge points: any number of cells may emit on the same bus; no interaction, no chaining through buses.

### 2.4 The no-destination state
A cell whose output goes nowhere — no letters lit AND (▾ off OR no occupied cell below) — is legal but visually flagged (dashed warning border, §5). Newly painted cells default to `{▾ off, A on, +SRC off}`, so a fresh cell is always audible; the flagged state only arises from explicit user action (including deleting a cell out from under a chain, which orphans and flags the feeder).

### 2.5 Source — the omni commitment
Plugin MIDI input is **omni, permanently**: all input channels merge into the single held-note pool (tracked via note-on/off; no latch in this version). Colours and cells carry **no input configuration of any kind** — a design commitment, not a v1 limitation. Channel-split workflows belong to **host routing across multiple MidiSpark instances**, where AUM's per-connection channel filters already do the job visibly. Rationale recorded: per-Colour input filters would reintroduce input configuration (which sender-decides eliminated), fracture the source rail's truthfulness, duplicate host functionality, and create a mysterious-silence failure mode. The source is only ever an *input* to cells; it never reaches any output bus by itself. Empty columns and columns whose cells emit nothing are rests.

### 2.6 Transpose and OUT CH (Colour-level)
- **Transpose:** −24…+24 semitones per Colour, applied at processor output; chains accumulate; post-transpose clamp to 0–127 with note-on/off pairing preserved. Not B-able, not morphable.
- **OUT CH:** per Colour, `INHERIT | 1–16`, stamped on that Colour's *emissions* on every bus (never an input filter — the label and palette badge →n make the direction unmissable). Retained for single-output-host degradation, hardware multitimbral rigs, and scale (4 buses × 16 channels). CC/PB/AT pass through unstamped on original channels, **bus A only**.

## 3. Processor types & states

Colour-level, common to all: `outChannel`, `transpose`. Switching type preserves these; type params reset to defaults including a designed default B-state.

| Type | A-state parameters | B-state overridable |
|---|---|---|
| **ARP** | pattern UP/DOWN/UP-DN/RANDOM/AS-PLAYED · rate 1/4…1/32 incl. triplets · octaves 1–4 · gate 5–100% · **phase** (3.5) | rate, octaves |
| **RATCHET** | repeats 2/3/4/6/8 · velocity ramp 0–100% | repeats |
| **PASSGATE** | 4 pass toggles; closed = no output; click-safe; all-open in audition | pass mask |
| **STRUM** | direction UP/DOWN/ALTERNATE · spread 10 ms–1 beat · curve ±100 · velocity tilt ±100 | spread |
| **CHANCE** | probability 0–100% per note-on (off follows its on's fate) | probability |
| **HARMONIZE** | up to 3 voices, each −24…+24 st, velocity scale 10–100% | voice intervals |

### 3.1 A/B states
Every Colour carries a designed **B-state**: a small set of overrides (table above) authored via the A/B tab pair; the B tab exposes only the overridable parameters; unlisted parameters always come from A. Factory Colours ship with musically useful B-states. **Which state plays is per cell** — the Colour defines what B *is*; each cell stores which state it's *in*; a held row ALT push (6.2b) additionally forces B row-wide momentarily: effective state = `cell.alt OR rowPushed(row)`. State flips are parameter swaps under the note-tracker rules (no retriggers, no stuck notes).

### 3.2 Morph — the A→B fader
Each Colour has a **morph** position `0…1` (default 0). For every cell of that Colour **not** flipped/pushed to B, effective parameters interpolate from A toward B by the morph amount; flipped/pushed cells remain pinned at full B.

Interpolation rules:
- **Continuous fields** (gate, spread, probability, velocity scales): linear.
- **Stepped fields** (rate, octaves, repeats, harmonize intervals): interpolate the index/value and **quantize to the nearest legal step** — a morphed rate audibly steps through the ladder; it must not glide.
- **Masks** (passgate): switch A→B at morph = 0.5.
- Effective values must always land on legal parameter values.

Morph **is** the per-Colour macro AUParameter (§8): sixteen automatable, MIDI-learnable faders. Morph is persisted state — a *parameter*, not a hold.

### 3.3 Relative transforms — ×2 / ÷2
One-tap, per-Colour, always-musical big levers in the COLOUR panel:
- **ARP — TIME:** rate doubles/halves along its own ladder, straight (1/4↔1/8↔1/16↔1/32) or triplet (1/8T↔1/16T), never crossing between ladders, clamped at the ends.
- **RATCHET — DENSITY:** repeats map 2↔4↔8 and 3↔6 (÷2 floors: 3→2), clamped.
They edit the A-state (the same field morph/B read from), so they compose with everything.

### 3.4 Hold-to-borrow parameters
The panel's stepped selectors (pattern, rate, octaves, repeats — and their B-tab counterparts) obey the grammar: **tap sets; hold engages the touched value only while held**, reverting on release (white-glow indication). A held rate is a fill; a held octave is a lift. Pure UI (stored prior value + revert); the engine sees two ordinary parameter changes, click-free by the next-scheduled-event rule. Never persisted.

### 3.5 ARP PHASE — RETRIG | LEGATO | FREE
Per-Colour, ARP-only mode selecting how the arp's **pattern position (phase)** is derived. It governs phase *index* only — note lifetimes remain step-bounded under the tail policy and gate; what carries across boundaries is *where in the pattern the next note comes from*, never a sounding note.

| Mode | Phase derivation | Musical meaning |
|---|---|---|
| **RETRIG** *(default)* | Position within the current step. | Every placement a self-contained stamp starting at pattern position zero. The painting metaphor at its purest. |
| **LEGATO** | Position within the current run (subdivisions since the run's first step, along the effective playhead). | A contiguous horizontal run of the same Colour is one phrase; the pattern continues across internal boundaries and restarts after any gap. **Phrase length becomes paintable.** |
| **FREE** | Global true beat position, mod pattern length. | The pattern runs invisibly underneath; cells gate it audible. Re-entry lands wherever the pattern would be; non-dividing lengths drift polymetrically by design. |

Rules:
- **Run identity (LEGATO):** same Colour + same **row** + contiguous **columns**. Wiring is irrelevant to run identity (§1.1). A **muted** cell silences its slice but does *not* break contiguity (the phrase resumes at the correct index); **bypassed** likewise (identity processor, phase advances). Only emptiness or a different Colour breaks a run — performance actions must not silently re-segment authored phrases.
- **Chord changes:** the arp continues **by index** into the new pool, never resetting phase, in any mode.
- **Scope:** ARP only (per-step restart is natural for the other types; recorded as considered-and-rejected).
- **Not B-able, not morphable, not hold-borrowable** (a borrowed structural mode produces meaningless discontinuities; deliberate).
- **Audition:** hold-preview zeroes phase regardless of mode.
- **Performance interactions (normative):** stutter × RETRIG = machine-perfect repeats; stutter × LEGATO = consistent repeat at the pinned run offset; stutter × FREE **evolves while held** (FREE derives from *true* position) — sanctioned unpredictability, must not be "fixed". Loop brace applies each formula per effective column.
- **§0 compliance:** RETRIG unmarked; LEGATO continuation cells show a left-edge link tick; FREE cells carry a persistent **∞ badge**.

## 4. Transport, playhead, passes, swing

- Global step rate `2/1, 1/1, 1/2, 1/2., 1/4, 1/8`; default `1/2`.
- **Derived, never accumulated:** `column = floor(beatPos/stepBeats) mod 8`; `pass = floor(beatPos/(stepBeats×8)) mod 4`. Correct across loops, jumps, tempo changes, multiple instances. Pass counter (1–4) shown in header; consumed by PASSGATE, QUANT (6.8), and future PASS RAMP (12.12).
- **Performance overrides** (stutter/brace, 6.2b) replace the *effective* column while true position keeps deriving underneath; release restores exact true position with zero drift — guaranteed by construction, required behaviour. **During any override the pass counter continues deriving from true position** (a stuttered column keeps evolving through its passgates — normative).
- **Global swing**, 50% (straight) to 75%, default 50: a **phase warp on the derived beat position** (beat → warped beat → column), MPC-style pairwise at the **global step level only** — subdivisions (arp notes, ratchets) divide their step's *warped* duration evenly; there is deliberately no subdivision swing. Identity at exactly 50. Composes with stutter/brace. Automatable; persisted in the scene.
- Transport stopped → audition (6.4). Transport running → sequencing.
- All PHASE formulas (3.5) are derivations from these same references and inherit every guarantee. Swing warps the beat before all phase derivation.

## 5. Grid & wiring visualisation

The live circuit (from v2.0): MIDI IN chip + top bus, per-stack source rails and taps, Colour chain cables with chevrons, out rails with lane junction nodes, four bottom lanes with pulsing lamps; wires lit with animated current only while MIDI traverses them; truthful extents at all times.

**Motion-as-state rule:** colour encodes *identity*, motion encodes *non-default state*, position encodes *function*:
- **B-state cell:** colour fill + breathing white inner ring (~1.4 s) + **B** badge; glyphs always render the active state.
- **Morph ring:** unflipped cells of a Colour with effective morph > 0 show a *static* white inner ring whose opacity tracks the amount (breathing reserved for full B; the grid displays how far toward B each Colour sits — including under MASTER, 13.5).
- **Muted cell:** drained faint tint + coral **M** badge; chain cable dark; follower's source tap lit (the reroute displayed).
- **Bypassed cell:** dim outline, ghosted glyph. Mute and bypass are deliberately static — drained things look inert; armed things breathe.
- **Isolated cell (held):** white outline + glow; all others fade; ISOLATE header indicator.
- **Stutter/loop:** locked stack buttons light white (LOCK/LOOP), header shows STUTTER or LOOP n–m, playhead highlight follows the *effective* column.
- During a row ALT push the whole row breathes. Borrowed parameter buttons glow white while held. QUANT-armed targets blink fast at half intensity (armed ≠ in-B).
- Badges: B top-left · M top-right · ∞ bottom-left · transpose bottom-right; LEGATO link tick on the left edge.
- The only other motions are playhead flash, wire current, lane lamps — all event-driven. Continuous animation stays scarce and meaningful.

## 6. Modes & interaction

Two UI modes × transport state = four contexts. Mode switches clear selections, modifiers, isolate, and all held stutters/braces/pushes.

|  | Transport running | Transport stopped |
|---|---|---|
| **PERFORM** (default) | sequencing + performance controls | **audition** |
| **EDIT** | live patching | silent patching |

### 6.1 Edit mode
Spatial wiring buttons on each occupied cell: **▸** left edge (lit-locked when unfed / +SRC toggle when fed), **A B C D** stacked on the right edge, **▾** centred below. Gutters widen in edit; the same geometry renders the live wire taps in perform — editing teaches performing. Cell taps: empty = paint (default routing), same Colour = clear, other Colour = repaint preserving wiring. Side buttons = SELECT (white); stack COPY/PASTE/CLEAR (full patch copy incl. wiring); row FILL/CLEAR. **The edit frame around the grid renders in the currently selected Colour.**

### 6.2 Perform mode (transport running)

**(a) Tap layer.** **Tap action** is a global setting (header selector, colour-coded per 6.5, switchable mid-performance, default ALT):

| Action | Tap on a cell does | Character |
|---|---|---|
| **ALT** (cyan) | Flip between the Colour's A and B states. | Maximally predictable; the build/drop mechanic; 64 designed variation switches. |
| **BYP** (amber) | Toggle bypass: identity processor — wiring intact, transformation skipped. | Context-dependent by design (pedalboard property). |
| **MUTE** (coral) | Toggle cell mute: emits nothing, feeds nothing; chained followers revert to source (§2.1). | "This branch dies"; per-cell granularity stack-mute lacks. |

**Hold a cell (≈300 ms) = ISOLATE**, always: only that cell sounds anywhere (playhead keeps running). Release restores; release-outside and mode-switch also release. Momentary; overrides bypass for the held cell.

Row buttons = **row bypass** (amber). Stack buttons = **stack mute** (coral); with **S modifier** (lime) = **stack solo** (solo overrides mute; no row solo). All transitions send immediate note-offs and are click-safe.

**(b) Hold layer** — side buttons gain momentary holds (≈300 ms; a completed hold suppresses its trailing tap):

| Gesture | Action | Behaviour |
|---|---|---|
| **Hold one stack button** | **STEP LOCK (stutter)** | Effective playhead pins to that column; the step repeats at the step rate; passgates keep evolving (§4). Release → snap to true position. |
| **Hold two+ stack buttons** | **LOOP BRACE** | Effective playhead cycles the contiguous range between lowest and highest held. Release to one hold = stutter; release all = true position. |
| **Hold a row button** | **ROW ALT PUSH** | Every cell in the row forced to B while held; release restores per-cell flags. |

Holds compose freely (stutter + push = locked, intensified repeat) and with the tap layer. Never persisted; released by mode switch or transport stop.

### 6.3 Perform-state persistence
Cell alt/bypass/mute, row bypass, stack mute/solo, tap action, QUANT persist in `fullState`. Isolate, stutter, brace, pushes, borrows: momentary — never persisted.

### 6.4 Audition mode (perform + stopped)
Raw passthrough soundcheck; hold a cell → that processor alone against the live source (phase zeroed, input forced to source, its letters active, the cell's *active* A/B state); stack buttons = APPLY latches; internal phase clock at host tempo; transport start auto-releases; passgates all-open; row buttons disabled. Side-button holds have no audition meaning in this version.

### 6.5 Interaction colour vocabulary
Disambiguation is **hue + motion + location** (necessary at sixteen Colours): state hues on buttons/badges/frames, Colour hues on cells/wires, continuous motion = "alternate armed".
white = select, isolate & step lock · coral = mute/silence · amber = bypass & edit mode · lime = solo · cyan = alt/apply & perform mode · dashed red = output goes nowhere · fast blink = QUANT-armed.

### 6.6 Onboarding
Factory session sounds immediately and demonstrates an ALT flip; hint overlay on an empty grid.

### 6.7 Palette
**Sixteen Colours in a 4×4 bank**, factory-fixed hues in v1 (user-editable hues recorded as a possible later setting), chosen for perceptual separation across **hue AND lightness/saturation** (sixteen equal-brightness hues produce near-twins; brightness spacing also survives coarse hardware LEDs, §10). Chips show type (abbreviated) and →n OUT CH badge; selecting a chip drives the edit frame colour. Palette caption: "COLOURS — the treatment".

### 6.8 QUANT — boundary-quantized actions
Global setting `OFF | STEP | PASS` (default OFF), persisted in the scene, shown in the transport header.

**Governs discrete state changes only:** perform-mode cell taps (ALT/BYP/MUTE), stack mute/solo and row bypass toggles, and **SPRING release commits** on the MORPH desk (the fader still moves freely — a dragged fader is never quantized; with QUANT active the release's return commits at the boundary).

**Never governs the hold layer:** stutter, brace, row push, isolate remain immediate at engage and release (normative: holds are *borrowed time*; latency on a momentary gesture reads as breakage; QUANT is a state-timing rule and holds don't change state). Plain fader drags remain immediate.

**Armed state (§0):** between gesture and boundary the pending action blinks fast at half intensity of its target treatment (blinking = "committed, not yet applied"). A second tap cancels. On the boundary all armed actions apply atomically, click-safe via the existing transition machinery.

**Boundaries derive from TRUE position** (STEP = next true step edge; PASS = next true pass edge) — armed actions land correctly during a stutter or brace, firing when the *song* crosses the boundary. Transport stop clears pending actions.

### 6.9 COLOUR panel
Contains: TYPE · OUT CH · TRANSPOSE · PHASE (ARP) · TIME ÷2/×2 (ARP) / DENSITY (RATCHET) · type parameters with A/B tabs · the MORPH fader (with % readout, always visible, accented in the Colour). Selectors are hold-borrowable per 3.4 (PHASE excepted). **Recorded pre-build task:** one deliberate layout pass (grouping, not accretion) before implementation, without changing any semantics.

## 7. Engine

Sample-accurate `MIDIOutputEventBlock` with cable index (0–3 = A–D). No allocation, locks, or ObjC dispatch on the render thread. UI ↔ engine via an atomically-swapped flat snapshot; the render thread reads only the snapshot.

- **Tails:** truncate-at-boundary; a per-event ring-out policy flag is *reserved* (activated by ECHO, 12.4).
- **Event budget:** post-fan-out ceiling with lowest-velocity thinning.
- **Snapshot carries:** both parameter blocks (A and B) per Colour + per-cell alt bits (an ALT flip is a one-bit change); per-Colour `morph` + global `morphMaster` (effective per cell = A merged toward B by `(alt|push ? 1 : effectiveMorph)` with 3.2 quantization, computed render-side); global `swing` (applied in the beat→column derivation before any lock override; subdivision scheduling divides the warped step); `lockLo`/`lockHi` (−1 inactive; equal = stutter; range = brace) + `rowPush` 8-bit mask (effective column and effective alt derived render-side; engaging/releasing is a snapshot swap, nothing more); per-ARP-Colour `phase` mode + per-cell `runStartColumn` (precomputed by the UI-thread builder; render never scans the grid; any run-membership edit rebuilds affected values in the next snapshot); QUANT pending-set (action, target, boundary — applied when the true-position derivation crosses the boundary; derived, never timer-based; cleared on transport stop).
- **Note tracker invariant: no stuck notes under any action, on any bus.** Covers: ALT flips mid-note (sounding notes finish under originating parameters; new state from the next scheduled event — no retrigger); cell mute (close the cell's sounding notes and the old chain-fed notes downstream before events derive from the new input); isolate (engine-side a cell-scoped solo flag, reusing mute/solo machinery); lock engage/range-change/release (ordinary playhead transitions — no special cases permitted); row-push transitions (ALT rule); run boundaries are *not* note events (phase modes move indices, not lifetimes).
- **Same-note collision policy** (normative): for multiple sounding instances of one (bus, channel, note) — sustained chord + same-pitch arp, or transpose-induced pitch collisions —
  1. **Note-ons always emit** (re-articulation is audible truth; velocity-arpeggiating a held chord is a supported technique).
  2. **Note-offs are reference-counted** per (bus, channel, note): emitted only when the *last* instance releases. No dropouts, ever.
  3. **No restoration strike.** The surviving note continues at the last strike's velocity; the drift self-heals at the next step boundary via truncate-and-re-articulate, accepted by design (a restoration note-on would inject unauthored accents). Future note: a MIDI 2.0 / per-note-controller output mode could express true level restoration; out of scope now.
  4. The refcount lives in the tracker keyed by (bus, channel, note) with per-instance ownership retained; all close-on-transition rules operate on *instances*, the wire-level off gated by the refcount.
- **FREE phase** uses integer/rational beat math robust to hours-long sessions, never accumulated floats.
- Host parameter changes arrive by **two routes** — tree setValue (observer → document → snapshot) and render-side parameter events — and both must work; the implementation reconciles them (render-side overrides cleared by each new snapshot generation).

## 8. Host integration & degradation

- Four MIDI outputs declared (AUM: four routable sources). Single-output hosts: buses collapse onto output 0; OUT CH stamps remain the separation mechanism.
- **AUParameters — 35, addresses STABLE forever:** `0` stepRate · `1` swing · `100+i` transpose per Colour · `200+i` morph per Colour (the macro; no other macro exists) · `300` MORPH MASTER (§13.5 — reserved *and functional* from v1 even before the desk UI ships; retrofitting parameters breaks automation compatibility, retrofitting UI doesn't). Add new addresses; never renumber or reuse.
- Not AUParameters (deliberate): tap action, cell states, borrows, holds, QUANT (automating a timing mode invites races).
- CC/PB/AT pass through on bus A only. Honour musical context, transport state, host bypass, `reset`. Instances independent.

## 9. State & persistence

```
Colour {                        // ×16
  colourID; type
  outChannel  : 0=INHERIT | 1–16
  transpose   : −24…+24
  morph       : 0.0–1.0
  paramsA     : full type params (incl. phase for ARP)
  paramsB     : sparse overrides (unlisted = inherit from A)
}

Cell { colourID; stack; buses : Set{A..D}; srcMix; alt; bypassed; muted }

SceneState {
  cells[8][8]; rowBypass[8]; stackMute[8]; stackSolo[8]
  stepRate; swing : 50–75; tapAction : ALT|BYP|MUTE; quant : OFF|STEP|PASS
}

PluginState {
  formatVersion = 2
  colours[16]
  scenes[] : SceneState          // length 1; scenes remain the flagship next feature
  activeScene : Int (0)
  morphMaster : 0.0–1.0          // parameter 300
}
// "preset" appears nowhere below the host boundary — by design.
// Older states load: field renames mapped; missing fields default
// (morph 0, swing 50, quant OFF, phase RETRIG; 6-Colour states map to bank slots 1–6).
```

Scene design intent (recorded, not implemented): whole-grid snapshots incl. wiring and performance state; switching quantized to pass boundary; Colours global; Launchpad right strip as launchers.

## 10. Launchpad integration

Launchpad X / Mini MK3 / Pro MK3, Programmer mode, direct CoreMIDI client — an alternative UI on the same document model; graceful absence; hot-plug. Pads = grid (perform: tap action; **pad hold = isolate**); top row = stack buttons (**holds = stutter / loop brace** — hardware multi-touch makes the brace *more* playable than glass); right column = row buttons (**hold = row ALT push**); corner holds = mode switch and S. Wiring edits remain screen-only.
LEDs: B-state cells pulse-brighten; muted cells low-brightness with coral beat-blink; isolate dims all others; locked stack pads bright white; braced range white with the effective column sweeping inside; pushed rows pulse cyan; QUANT-armed pads blink fast at half intensity; FREE cells may add a slow shimmer if the ∞ badge needs a hardware equivalent. Sixteen Colours map to nearest LED palette entries; near-hue pairs must be verified distinguishable and nudged to different indices if they merge. Morph riding belongs to MIDI-learned fader banks (or the future virtual-fader page, 13.6), not the Launchpad grid.

## 11. Acceptance checklist

1. Loads in AUM declaring four MIDI outputs; empty grid + running transport = silence; stopped = raw passthrough; factory session sounds immediately and demonstrates an ALT flip.
2. Playhead locked to host through loops, tempo changes, relocation; multiple instances agree; pass counter correct.
3. Single ARP cell with letter A: correct sample-stable arpeggio at every step rate, on bus A only.
4. **Routing:** ▾ chains feed correctly; chain ends revert followers to source; +SRC merges; mid-chain letter taps audible; ▾-to-nowhere silent and flagged; deleting a receiver flags the orphan; no stuck notes in any of these.
5. **Buses:** multi-letter fan-out correct; different OUT CHs and buses drive four host destinations from one instance; note-offs match note-ons per bus and channel including mid-note wiring edits; CC passthrough on bus A only.
6. PASSGATE exact per-pass behaviour, click-free, all-open in audition.
7. **Tap layer:** selector switches cleanly mid-performance; ALT flips without retriggers or stuck notes; BYP correct at every chain position; MUTE reroutes followers with truthful visuals; hold-isolate engages/releases cleanly (incl. release-outside, mode switch) and never leaks notes.
8. Bypass (cell/row), stack mute, solo, S-flow: correct semantics and visuals, click-safe.
9. Edit mode: paint/clear/repaint-preserving-wiring; spatial buttons edit the correct cell; ▸ locked/unlocked correct; stack copy/paste carries wiring; row fill/clear; mode switch never fires performance actions and releases everything momentary.
10. Audition: hold isolates with zeroed phase, forced source, active A/B state, the cell's letters; APPLY latches merge; transport start auto-releases.
11. Transpose accumulates and clamps safely; save/reload restores Colours (both states + morph), cells, performance states, tap action, step rate, swing, QUANT exactly; older-format states load with correct defaults and bank-slot mapping.
12. Wiring visualisation truthful at all times, including under mute-reroute and isolate; no-destination flagged; lanes/lamps light only when fed (spot-checked per bus against a MIDI monitor).
13. Single-output host: all buses on output 0, channel separation intact, no crashes.
14. Launchpad: paint, perform (tap action + holds), audition from hardware with correct LEDs; hot-plug and absence handled.
15. **Stutter:** hold pins the effective playhead within one step boundary; the step repeats correctly incl. ratchets/arps re-running per pass; **passgates continue evolving during the lock**; release restores true position exactly (verified after long holds spanning tempo changes and loop wraps); no stuck notes at engage or release.
16. **Loop brace:** two+ holds cycle the bounded range in order; adding/removing holds adjusts live; collapse-to-stutter and full release per spec; true position untouched throughout.
17. **Row ALT push:** all cells take B from the next scheduled event while held, with row-wide breathing; release restores per-cell flags; no retriggers; composes with an active stutter and with individually flipped cells.
18. **Grammar hygiene:** a completed hold never fires its tap action (stack, row, or cell); mode switch and transport stop release every hold; nothing hold-related appears in saved state.
19. **Palette:** all sixteen Colours distinguishable on the target iPad at arm's length and on Launchpad LEDs; edit frame tracks the selected Colour.
20. 30-minute soak: deep chains, multi-bus fan-out, continuous ALT/MUTE/isolate plus sustained stutter/brace/push activity, event budget engaged — no memory growth, no real-time violations, no stuck notes on any bus.
21. **Morph:** riding a fader steps unflipped cells through quantized intermediate states (rate ladder-steps, never glides; all effective values legal); flipped/pushed cells stay at full B; morph ring opacity tracks the effective amount; automates via its AUParameter and MIDI-learns in AUM; mid-note changes never retrigger or strand notes.
22. **Panel grammar:** hold-borrow engages while held, reverts exactly on release (verified after rapid multi-borrows), suppresses its trailing tap, never persists; ×2/÷2 obey their ladders and clamps for every starting value incl. triplets and ratchet 3↔6.
23. **Swing:** 50% bit-identical to pre-swing timing; swung positions match the warp formula at several settings (MIDI-monitor timestamps); subdivisions divide the warped step evenly; survives save/reload; composes with stutter and brace; true-position guarantee holds under swing + lock combined.
24. **Collision policy:** sustained PASS chord + same-pitch ARP on a shared (bus, channel): every strike re-articulates at its own velocity, **zero dropouts**, exactly one note-off after the final holder releases (MIDI monitor); same for a transpose-induced collision; refcount correct against truncation, mutes, and locks.
25. **PHASE modes:** RETRIG — identical output from the same arp in different stacks and across passes (monitor diff). LEGATO — an 8-note pattern over a 2-step run completes exactly once, no repeated/skipped indices; gaps restart at 0; run identity ignores wiring; muting/bypassing mid-run doesn't re-segment phase; repainting splits from the next snapshot. FREE — coprime pattern lengths catch different slices exactly as the mod formula predicts; re-entry lands at the derived index; identical across loop wraps, relocations, tempo changes; a second instance agrees; ∞ badge present. Interactions: stutter×RETRIG bit-identical; stutter×LEGATO repeats the locked offset; stutter×FREE evolves and re-syncs on release; chord changes continue by index; no stuck notes at run starts/ends or mode edits.
26. **QUANT:** with STEP and PASS — taps and toggles arm visibly, apply exactly on the true-position boundary (MIDI-monitor timing), cancel on second tap, clear on transport stop; SPRING releases commit at the boundary while drags stay continuous; holds remain immediate in all modes; armed actions land correctly across a stutter, a brace, and a host loop wrap; boundary application produces no clicks or stuck notes.
27. **Naming audit:** no UI string, manual text, or store copy uses "preset" below the host layer, "sound" for a Colour, or "mix" for the desk; COLOUR/MORPH toggle, palette caption, and desk title match §1.
28. **Instance independence:** two same-Colour cells chained by ▾ — the lower audibly processes the upper's output (ARP→ARP verified against the single-cell case); unchained same-Colour duplicates on a shared (bus, channel) behave under the refcount with no dropouts or stuck notes; flipping one instance to B leaves siblings in A; editing a Colour mid-performance updates all instances from the next scheduled event with no divergence; same-Colour cells in one stack never phase-link in any PHASE mode (LEGATO verified horizontal-only).

## 12. Future processor roster *(design commitment)*

### 12.0 Constraints every future processor must satisfy *(binding)*
1. **§0 readability:** a cell glyph rendering its configuration, plus an honesty badge if behaviour isn't grid-derivable (as FREE's ∞).
2. **Derived, never accumulated.** Cross-step *state* is forbidden; cross-step *scheduling* only under the ring-out policy (12.4).
3. **One narrow B-override set** (1–2 params), morph-interpolable per 3.2.
4. **Defined audition behaviour, Launchpad LED treatment, and note-tracker analysis** (new tracker cases require explicit spec text).
5. **Event-budget accounting** if it multiplies events.
6. **Notes only.** Generated CC/modulation output is out of scope (12.10).

Type IDs are append-only; the TYPE selector, snapshot param blocks, and glyph system must accommodate roster growth without schema breaks.

### 12.1 SCALE — pitch quantize *(high)*
Snaps passing notes to a key/scale (root × scale table; nearest/up/down). Retro-upgrades the whole roster — RANDOM arps, stacked transposes, HARMONIZE chains become guaranteed-musical downstream. Same-pitch snaps are collisions §7 already handles. B: scale. Glyph: keyboard strip with in-scale pips.

### 12.2 RANGE — pitch slice *(high)*
Passes LOWEST n / HIGHEST n / a zone. Completes the one-chord orchestra: RANGE(lowest 1) → arp on bus A is a bass extractor; zone splits give keyboard-split behaviour per placement. Pool-relative, derived per event, stateless. B: the selection. Glyph: bracket over a pitch strip.

### 12.3 WINDOW — time slice *(high)*
Audible only during start+width fractions of the step (quantized to quarters, optionally eighths). WINDOW(75%, 25%) = only the last quarter sounds — the temporal complement to PASSGATE. Fed streams: onsets in the window pass; source input articulates at window start, ends at window end (click-safe edges). Windows subdivide the *swung* step. B: window position/width (downbeat ↔ offbeat stab). Glyph: a step-bar with the lit segment.

### 12.4 ECHO — tempo-synced repeats *(medium-high; the ring-out activator)*
Synced repeats, n, velocity decay, optional per-repeat transpose. **The processor the reserved ring-out tail policy exists for:** repeats are scheduled at emission time (derived; chains stay acyclic), tagged ring-out, exempt from truncation, still cell-owned and refcounted. Biggest event multiplier — budget mandatory. Pinned decision: tails die with the owning cell's mute. B: repeat count or time. Glyph: diminishing ticks.

### 12.5 CHORD — voicing generator *(medium)*
Each note → a voicing (triads/7ths/sus/spread; diatonic degrees with 12.1's table). HARMONIZE gains a scale-aware mode in the same work package. Event multiplier (×voices). B: voicing. Glyph: stacked pips.

### 12.6 EUCLID — euclidean gate *(medium)*
k pulses over n subdivisions, rotatable; passes only pulse-landing events; source articulates on pulses. E(3,8) on a chord = instant tresillo. Stateless. B: k. Glyph: the pulse row itself.

### 12.7 VELOCITY — dynamics shaper *(medium-low)*
Curve/compress/expand; accent patterns per subdivision; bounded humanize via a **seeded per-position hash**, never accumulated RNG (a rule CHANCE should also adopt when revisited). B: accent pattern or curve amount.

### 12.8 LATCH — source capture *(medium-low; conditionally approved)*
Captures the pool at step entry and processes the capture after keys release — as a *placement*, so latched and live cells coexist. §0 risk: sound-after-hands-leave must be badged, and the capture is a derived snapshot keyed to step entry. If testing shows confusion, prefer a global source-latch toggle and drop the processor form.

### 12.9 INVERT/ROTATE — pool transform *(low)*
Inversion or note-order rotation, optionally advancing per pass. Low urgency (transpose+SCALE approximates much of it).

### 12.10 Considered and rejected *(recorded so they stay rejected)*
- **Time-quantize** of live input: the engine is grid-driven; belongs to hosts/recorders.
- **CC/LFO generators:** violates notes-only; modulation is the host's and synth's domain. Out of scope, not deferred.
- **Per-cell swing:** global only.
- **Note-probability as a new type:** that is **CHANCE**; per-event/per-pass variants are CHANCE panel extensions.
- **Phase modes for non-ARP types.**

### 12.11 Implementation waves
Wave 1 (musicality): SCALE + RANGE + WINDOW. Wave 2 (space): ECHO + CHORD (+ scale-aware HARMONIZE). Wave 3 (finesse): EUCLID, VELOCITY, then LATCH/INVERT as testing warrants. Scenes remain the flagship feature alongside all waves.

### 12.12 PASS RAMP — auto-morph per pass *(candidate; medium)*
Per-Colour: morph auto-advances across the four passes (e.g. 0→33→66→100; small curve/direction set; wrap or hold). Pure derivation (f(pass)), composes with MASTER; desk display rules pinned at implementation. *Architectural note:* with QUANT and RAMP, the **pass is a first-class clock with three consumers** — extensions should feed existing clocks rather than invent new ones.

## 13. The MORPH desk *(future feature; design committed)*

### 13.1 Premise
Morph is already the per-Colour macro AUParameter. The desk is a **pure view**: sixteen fader strips bound to existing parameters, plus MASTER. No engine changes; automation and MIDI-learn reach the desk's parameters whether its UI exists or not. v1 must merely keep parameter IDs stable and build the bottom panel as a swappable view.

### 13.2 Placement
**Not a third mode.** A **COLOUR ⇄ MORPH** toggle on the bottom panel swaps the Colour editor for the desk; the grid remains fully live above in either mode.

### 13.3 The strip
Per Colour: colour cap · type label · morph fader (0–100, readout) · **B-indicator** (lit when any cell of that Colour is at full B via flip or push — the desk admits when a fader isn't the whole story). Unplaced Colours render dimmed but operable. **Deliberately absent:** per-Colour mute/solo/level — those constructs don't exist in the model, and the desk shows only what is real. Double-tap a fader = return to 0.

### 13.4 SPRING
> Drag changes state. **SPRING borrows:** with the desk-wide toggle engaged, fader moves are momentary — release glides back to the stored position (short fixed glide; click-free). 
The fader-shaped sibling of hold-to-borrow, completing the grammar across every control class. UI preference; never persisted; never affects host-written automation. Multi-touch (several faders at once) is required behaviour. Interacts with QUANT per 6.8 (release commits defer; drags never quantize).

### 13.5 MASTER
A seventeenth strip pushing all Colours toward B proportionally:
`effective_i = morph_i + (1 − morph_i) × master`
— preserving the faders' *mix* while lifting the whole patch toward its designed intensity. MASTER is AUParameter **300 ("MORPH MASTER")**, automatable, default 0, persisted. Applied render-side where effective params are computed; cell morph rings display the *effective* amount. Flip rule unchanged. **v1 obligation: parameter 300 reserved and engine-functional now**, even though the desk UI ships later.

### 13.6 Hardware
Launchpad X/Mini native pad-column fader mode → a future MIX page maps eight virtual Colour faders onto the already-specified controller. External fader banks work today via MIDI-learn on the morph parameters.

### 13.7 Acceptance sketch (for the implementing revision)
Desk faders, cell morph rings, and host automation views agree at all times; SPRING releases restore the stored value exactly and write no state; MASTER formula verified at boundary values against per-cell effective params; multi-touch on ≥3 strips; dimmed-but-operable unused Colours; B-indicators track flips/pushes live; parameter 300 automates with the desk closed.

---
*End of specification v2.8 (consolidated). Frozen: §§0–2 (invariants, terminology, instance model, routing incl. omni input), the tap and hold layers, the gesture grammar, panel-performance semantics (morph, borrow, ×2/÷2, swing), the collision policy, PHASE semantics, QUANT semantics, the naming hierarchy. §12.0's constraints bind all future processors. One pending pre-build task: the COLOUR-panel layout pass (6.9). Deviations require a spec revision first — especially anything touching §0.*
