# MidiSpark spec v3.0-delta — routing model + visual language revision

STATUS: AUTHORITATIVE. This delta supersedes the listed sections of
`midispark-spec-v2.8.md`. Where this document is silent, v2.8 stands unchanged
(colours/cells/presets, processors, morph/ALT, swing, QUANT, performance layers,
engine snapshot architecture, collision policy, parameters, MORPH desk).
Reference implementation of the UI: `Docs/midispark-preview-v60.html`
(v50/v51 contain a JSX bug — do not use; v52 fixed base → v54 three-box
layout → v56 scene strip → v57 column keys → v58 static frames → v59
sixteen-slot strip → v60 emitter toggles (§6a) = canonical).
The abandoned alternative (linear chains + module boxes) is preserved as
`midispark-preview-v40.html` for the record; do not implement it.

## 1. The routing model (supersedes §1.1.3, §2.1–2.5)

**Receiver-picked references replace the ▾ stack cable.**

- Each cell owns exactly one input setting: `inputRow` — either MIDI IN
  (null) or the index of ANY OTHER ROW in the same column. Downward
  references and reference cycles are LEGAL.
- **Cycles are silent by construction, not by policing.** Input is
  single-select, so every member of a cycle points inside the cycle — MIDI
  IN can never be a member, nothing can ever enter, so a closed cycle emits
  nothing, forever. No runtime safeguard is needed; a "dead loop" INDICATOR
  is deferred to a later design pass (log as UI backlog, do not invent).
- **Evaluation stays a single 0→7 pass** with persistent sounding state (the
  voice table): an upward reference reads its parent's current sets as
  usual; a DOWNWARD reference reads the referenced cell's sounding voices as
  they stand (effectively the previous derivation — a unit delay, the same
  resolution audio feedback loops use). No topological sort, no recursion,
  no special cases.
- Multiple cells may reference the same parent: **fan-out is legal and is a
  headline feature** (one engine, several parallel treatments). The column is
  a reference GRAPH rooted at MIDI IN entries; acyclic patches behave as
  trees, cyclic sub-graphs are legal-and-silent as above.
- REMOVED from the model entirely: `stack` (▾), `srcMix`, +SRC. There is no
  input union anywhere; a cell hears exactly one thing. The old "+SRC"
  musical role (feed AND source) is expressed as a sibling: a second cell
  referencing the same parent, or referencing MIDI IN, on the same bus.
- Input derivation (per render, never stored):
  - `parentOf(cell)` = inputRow if that row is occupied and ≠ self; else null.
  - Input pool = parent's sounding set, sampled at this cell's tick times;
    if parentOf is null → the source pool FILTERED by the cell's
    `inputChannel` (0 = OMNI, the default; 1–16 = only notes arriving on that
    channel). The filter applies only at the source boundary — referenced
    parents' sounding sets are never filtered, and past the front door notes
    carry NO channel at all (see §7: INHERIT is removed from the model). 
  - **Reroute rule (generalises v2.8 §2.1):** if the referenced parent is
    muted OR its slot is empty, the cell reverts to MIDI IN for the duration.
    Configuration (`inputRow`) is untouched; this is live derivation only.
- Outputs are unchanged in kind but reduced in number: buses A–D only.
  Transpose stamping: unchanged from v2.8 §2.6. **Per-Colour OUT CH is
  REMOVED** — channel is a property of the WIRE, not the treatment; see §7.
- **No-destination warning becomes reference-aware:** a cell warns when it has
  no buses AND no other cell references it (`isTapped == false`). Note this
  is non-local (editing a child can create/clear a parent's warning); that is
  accepted.
- Sender-decides (v2.8 §2.1) is REPEALED for the feed. The receiver owns its
  one input reference; there is nothing for the sender to decide except its
  own buses.

## 2. Schema (supersedes the cell portion of §9)

```json
cell: { "presetID": int, "inputRow": int|null, "inputChannel": 0|1..16, "buses": [0..4 of "A".."D"], "alt": bool }
document additionally: busChannels[4] (1..16 each) · busEnabled[4] (bool, default true — §6a)
```
`stack` and `srcMix` are gone. Migration from v2.x documents: fed cell
(above.stack was true) → inputRow = row−1; srcMix has no equivalent (drop it;
log a warning). Colour schema: `outChannel` REMOVED (drop with a log — see
§7 note on migration); TRANSPOSE and all treatment params unchanged.
Document gains `busChannels[4]` (there is no outputMode — see §7b).

## 3. Engine notes (amends router-design.md; engine architecture unchanged)

- The pools model already supports reference graphs at zero cost: cells sample
  any referenced row's sounding voices; evaluation stays rows 0→7 against
  persistent voice state (§1 unit-delay rule for downward references).
- LEGATO phase (§3.5) is a COLUMN-run concept and is unaffected.
- Collision/refcount, voices, phase formulas, swing, morph resolution: all
  unchanged.
- Snapshot precomputation gains: per-cell resolvedParent (after occupancy
  check) and isTapped, so the render thread does no scanning.

## 4. Visual language — PERFORM (supersedes §5)

The perform grid is a **readable table that plays**. Reference: v59 preview.

- **Cell = four rows** (top→bottom):
  1. INPUT HEADER — text: `FROM MIDI` (dim white = the default), `MIDI CHn`
     (input-channel filter active, §7) or `FROM ROW n` (full white = an
     explicit patch). Flares solid white while
     actually receiving on the live column. n is 1-based display.
  2. GLYPH — the type, drawn (unchanged glyph vocabulary).
  3. PARAMS — text, params only, no type name: e.g. `1/16`, `1/8 ×3`,
     `1/16 2OCT`. Rendered from EFFECTIVE state → morph/ALT rewrite it live.
  4. EMITTERS — A B C D strip: ON = dark key, bright ring, white letter;
     OFF = deep recess, legible ghost letter; FIRING = white flip + downward
     glow. Display-only in perform.
- **Empty cells carry a row-number watermark** (large, ~8% white) — the
  coordinate system that makes `FROM ROW n` traceable at a glance.
- **Playheads (one-clock rule is BINDING):** every playhead is a pure function
  of the single derived beat fraction; no element owns an animation clock.
  - Master: a glowing white DOWN-ARROW above the grid sweeping left→right
    continuously through each step (stretches with swing; snaps at loop).
  - Per-cell: ONE falling horizontal line per working cell in the active
    column (the MUTATION line — "this machine is running"); faint and
    glowless when bypassed (identity); absent when muted. The former
    across-line (input sweep) is REMOVED — the header states the input.
- Badges (B, M, ∞, transpose), breathing ALT ring, isolate/mute/bypass hue
  language: unchanged from v2.8 §6.5.
- REMOVED from perform: all wiring lines/rails/lanes (since v27), MIDI IN
  chip/lamp, per-cell ▸ input indicators, module boxes, side bus chips.

## 5. EDIT additions (amends §6.2)

- Tapping a cell's INPUT HEADER opens a POPOVER hovering above the cell:
  `MIDI IN` + one button per OCCUPIED row other than the cell's own (any-row
  references, §1). With MIDI IN selected, the IN CH filter control appears
  (§7). Direct selection; self-reference is unexpressible; tap-away
  dismisses. (Supersedes header cycling; resolves the tap-target and O(n)
  concerns.)
- Tapping the EMITTER STRIP opens the matching OUT popover: four A–D
  toggles. One popover open at a time.
- COLOUR ASSIGNMENT is drag-and-drop: drag a palette chip onto a cell's
  BODY (the middle sections). The mockup stands this in with
  select-chip-then-tap-body; the SwiftUI build implements true drag.
  Clearing/copying cells: body HOLD opens a cell menu (CLEAR / COPY) — the
  hold-layer slot freed by drag replacing paint-tap. (Menu is not in the
  mockup; implement at step 5.)
- AUDITION integration: the §6 audition layer (perform + stopped) is
  unchanged and remains the primary listening surface. Additionally, in
  EDIT + stopped, the same hold-to-preview applies on the cell BODY when no
  drag is in progress: hold ≈300ms auditions the cell (its true routing and
  buses); holding a column's top MUTE/stack button auditions the whole
  column. Popovers keep a live audition running — selecting an input or
  toggling a bus while holding is the intended patch-and-listen loop.

## 6. Desk (closes the §6.9 layout-pass task)

**The desk is a PERFORMANCE surface, not edit chrome** — palette-select +
live parameter tweaking while restructuring on the pads is a first-class
workflow. It is therefore always visible, in both modes, with no scrolling.

**Placement rule: the grid is square, screens are not — the desk lives in
the leftover rectangle.** Landscape: a fixed-width column at the RIGHT of
the grid, full grid height (generous). Portrait: a compact band BELOW the
grid (the tight case; the height budget applies here). The breakpoint is
aspect-driven, not device-driven.

HEADER contents (v54 decision — supersedes the earlier STEP/SWING
relocation): "8×8 STATE" logotype (candidate branding; display only) ·
EDIT/PERFORM · TAP selector · STEP rate · SWING · PASS · transport ·
momentary indicators. Desk contents: palette 4×4 · the selected Colour's
parameter
fields · A/B tabs. (MORPH desk: parked — returns as its own design pass.)
Desk boxes are three NAMED panels — COLOUR, PROCESSOR, EMITTERS — in that
order in both orientations; only PROCESSOR may scroll (content-sized up to a
ceiling); emitter select buttons are grid-pad-scale squares carrying their
channel readouts. **STATIC FRAMES RULE (binding):** desk boxes have FIXED positions and sizes
per orientation — they NEVER resize or move in response to content or
selection (switching a Colour's TYPE must not move the EMITTERS pads a
single point). The PROCESSOR frame is sized for the LARGEST field set;
smaller types leave calm space; only content that exceeds the frame scrolls
WITHIN it. The mockup's content-driven sizing is a simulation artifact.
A **SCENE strip** runs full-width along the BOTTOM in both
orientations: SIXTEEN slots, current highlighted — factory content per
Docs/factory-scenes.md (dev builds may host the canned test sessions here
until SceneFactory lands). RESERVED, details TBD:
a MIDI-IN display ABOVE the COLOUR box. BACKLOG (log, don't invent):
collapsible/scalable desk sections for tucking away unused panels.
Final dimension tuning happens on device.

### 5b. PERFORM v2 — the COLUMN-SUBSET LAP (supersedes v2.8 §6.2 stutter +
### loop brace; this is the revised hold-layer spec)

**Gesture:** in PERFORM, HOLD one or more COLUMN KEYS. While held, the lap
consists of exactly the held columns; on full release, playback is back at
the true position instantly. (Column-key TAP is currently UNASSIGNED — tap-to-mute was removed at
`3e816ee` pending the revised perform spec, so the hold gesture has the
keys to itself; mute's return route is the TOUCH design pass.)

**The rule (pure derivation — the whole feature is one line):**
`effColumn = S[absoluteStep mod k]` where S = held columns sorted
left-to-right, k = |S|, absoluteStep = the derived global step counter. The
TRUE timeline never stops and never remaps; only column selection is warped.
Release ⇒ effColumn = trueColumn — nothing snaps because nothing drifted.
[Considered and REJECTED: order-of-press ordering for S — expressive but
unpredictable under sweaty fingers; sorted wins.]

- **Subsumes the old family:** k=1 = stutter; contiguous S = loop brace
  (the two-finger brace gesture is REMOVED); non-contiguous S = new.
- **INTENDED polymeter:** when k does not divide 8, the lap rotates against
  the pass (hold 3 columns: the 3-cycle phases around the 8-step timeline).
  This is a feature, not an artifact — do not "correct" it by resetting the
  mapping at pass boundaries.
- Time itself is unwarped: PASS count, PASSGATE, per-pass behaviours, and
  swing all follow the TRUE timeline. A held-but-muted column contributes
  its silence honestly. Fingers joining/leaving mid-hold recompute S live.
- **State:** the held set is EPHEMERAL engine-visible state (audition's
  category — never persisted, cleared on transport stop and on mode switch
  to EDIT).
- **Engine shape:** replaces the `lockLo/lockHi` contiguous-range stub with
  a held-column BITMASK + the mapping above; transitions in/out of/within a
  hold close/reopen notes per invariant 4 (a column change is a column
  change, whatever caused it).
- **Visuals:** held keys show the LOOP state (v57 key vocabulary); the
  playhead arrow follows the EFFECTIVE column (one-clock rule — it is a pure
  function of effColumn). A ghost indicator of the true position is
  DEFERRED to a later visual pass (log, don't invent).
- Relationship to the parked per-Colour tap/hold item (§9): column-key holds
  are ARRANGEMENT-level time-warps; the per-Colour behaviours are
  VOICE-level. They compose; neither replaces the other.

### 6b. COLOUR-chip activity playheads (DEFINITE requirement, 2026-07)

Palette chips indicate when their Colour is WORKING on the grid, using the
established mutation-line effect at chip scale:
- A chip sweeps a **horizontal line TOP→BOTTOM** while ≥1 instance of its
  Colour is working in the live column (mirror the cell mutation-line
  condition, including the faint-when-only-bypassed nuance; multiple
  instances = ONE sweep, never stacked).
- If the sounding instance(s) are in their **ALT face**, the sweep runs
  **LEFT→RIGHT** (a vertical line sweeping horizontally) — orientation
  encodes the face. Mixed main+alt instances in the same column: MAIN wins
  (top→bottom); left→right means alt-only.
- Model-agnostic: "alt face" = B-state today, the partner Colour under the
  colour-pair model (item 5) — the rule survives ratification either way.
- ONE-CLOCK RULE binding as everywhere: the sweep is a pure function of the
  derived beat fraction; chips own no animation clocks.

### 6a. The EMITTERS panel — behaviour per mode (supersedes panel-as-selector)

The four grid-pad-scale pads ARE the emitters (letter + CH readout + firing
flash when notes leave).

- **PERFORM: pad body = TOGGLE.** Enables/disables that emitter's output
  entirely — the per-output performance mute. Disabled = recessed/dark, CH
  dimmed, no firing flash. CH is display-only in PERFORM.
- **EDIT: the toggle is RETAINED on the pad body** (body = toggle in both
  modes — an invariant; one muscle memory). The channel becomes editable:
  the pad's CH caption is an OPENER (sub-44 law) for the CHANNEL POPOVER
  (1–16, one-popover grammar, tap-away dismisses). [Considered and REJECTED:
  a persistent selector row — it would force EDIT taps to mean select-not-
  toggle, breaking the cross-mode body invariant.]
- **Disable semantics (each clause follows an existing law):** disabling X
  immediately closes X's sounding notes (invariant 4), on X's own cable AND
  X's contribution to All — **All = the sum of ENABLED emitters.** Shared-
  channel merges survive correctly: notes co-owned by an enabled emitter
  keep sounding on All; the emitted-tuple refcount reaches zero only when
  all owners are gone. Re-enable resumes from the NEXT articulation — never
  retroactive re-sounding of mid-flight notes.
- **Cells are untouched:** a disabled emitter's cells still derive; children
  still hear parents. The gate lives at the emission boundary EXCLUSIVELY
  (seam rule 3). Bus-disable is not cell-mute.
- **State:** document-level `busEnabled[4]`, default all true, persisted
  (scenes/Presets); loader defaults old documents to all-true. Factory
  scenes ship all-enabled.
- The AU always declares five outputs; disable is emission-gating, never a
  declaration change. The shared-channel merge note remains a gentle
  warning, both modes. Static frames: toggling and the popover never resize
  the panel.
- **MIDI-activity metering (DEFINITE requirement, 2026-07):**
  (a) In PERFORM, each CELL's emitter letters flash on that cell's emission
  events per bus (ratifies the v59 "white flip + down-glow = firing"
  language as required behaviour, per-event).
  (b) The EMITTER PANEL pads meter activity **with VELOCITY**: flash/glow
  intensity tracks emitted velocity, plus a thin per-pad level bar
  (peak-hold with ~150ms decay). Purpose: live feedback for the future
  per-emitter velocity faders (§9 item 4) — the meter shows POST-transform
  velocity, always. Disabled emitters (toggled off) never meter.
  Engineering: activity metering is EVENT-driven, not beat-derived — it
  rides the existing emission-activity poll (extend the feed with
  per-emitter peak-velocity-since-last-poll + event count; UI owns only the
  decay envelope). The one-clock rule governs playheads, not meters; meters
  are the sanctioned event-driven visual class.

**Sizing across devices and host windows:** all UI dimensions and type sizes
are TOKENS derived from the resolved cell size, with a legibility floor —
no hardcoded literals survive the port. Screens (1024×768 floor → 13") need
only the tokens. The AUv3 HOST WINDOW is the real variable: define a minimum
design size, below which the canvas scales UNIFORMLY; for small-but-usable
views apply the DEGRADATION LADDER: (1) full UI → (2) type tiers shrink to
floor → (3) cell captions drop (colour + glyph + strips only) → (4) desk
collapses to a summonable drawer, grid-only. Rung 4 shares its mechanism
with the tuck-away-sections backlog item — build once. Static-frames rule
applies WITHIN each rung; rung changes are size-driven, never content-driven.

## 7. Channels: filter in, stamp out (supersedes v2.8 §2.6 and all INHERIT semantics)

**The whole channel story in one sentence: channel is FILTERED at the front
door and STAMPED at each exit; in between, notes have no channel.**

- IN: a cell whose input is MIDI IN has an `inputChannel` filter — OMNI
  (default) or a single channel 1–16. Shown in the FROM popover only when
  MIDI IN is selected; the header reads `MIDI CHn` when filtered. This is the
  multi-controller feature: different keyboards on different channels can
  drive different cells/columns.
- DISCARD: past the filter, origin channel is dropped. INHERIT no longer
  exists anywhere. Pool entries and sounding sets carry (note, velocity)
  only — the engine sheds the origin-channel threading entirely; channel
  survives only inside the raw source pool, where the per-cell filter reads it.
- OUT: each bus stamps its own channel: `busChannels[4]`, defaults [1,2,3,4],
  each 1–16 (there is no INHERIT option to offer). Applies in both modes.

## 7b. Outputs: ALL + A–D (no modes — supersedes the MULTI/SINGLE design)

There is no reliable way for an AUv3 to ask its host how many MIDI cables it
reads (unsupported cables are silently discarded, not refused), so a mode
switch would be manual forever. Instead, the Fugue Machine pattern: publish
every answer at once.

- The AU declares FIVE MIDI outputs, labels AS BUILT: `["All", "Emit A",
  "Emit B", "Emit C", "Emit D"]` (cables 0–4). Static, all modes of host served simultaneously:
  - **ALL (cable 0):** every emitter's notes, distinguished by their stamped
    channels. A single-cable host reads this and simply works — channels are
    the routing. Also useful everywhere: record-everything, or drive one
    multitimbral synth.
  - **A–D (cables 1–4):** each emitter's own stream, channel-stamped the
    same. Multi-out hosts (AUM) patch these individually.
- Every note is emitted twice (its own cable + ALL); the collision refcount
  keys on the EMITTED tuple (cable, channel, note), so the duplicate is just
  two independent entries and off-pairing stays correct — including when two
  emitters share a channel and therefore merge on ALL (the existing
  shared-channel machinery covers it).
- `outputMode` DOES NOT EXIST. The document setting is gone; the OUTPUTS
  panel shows the fixed cable identities and each emitter's channel. A
  gentle note appears when two emitters share a channel (their streams merge
  on ALL); legal, flagged, never blocked.
- User vocabulary note: Fugue Machine calls its equivalents "playheads"; our
  term is EMITTERS. The panel may subtitle ALL as "everything, by channel".

## 8. Acceptance items (amends §11)

- Item 12 (wiring truthfulness) RESCOPED: truth = each cell's header names its
  live-configured parent; reroutes visibly flare FROM MIDI while active;
  emitter strip matches actual bus emission (verify against a MIDI monitor).
- ADD item 29: fan-out — two cells referencing one parent emit independently
  processed streams derived from the same sounding set (test T9).
- ADD item 30: reroute — muting a referenced parent reverts children to
  MIDI IN within one derivation, restoring on unmute, with no stuck notes.
- ADD item 34: the column-subset lap (§5b) — arbitrary held sets map per the
  formula; release is seamless (true position, zero drift); k∤8 polymeter
  rotates as specified; PASSGATE follows true time throughout; zero stuck
  notes across hold enter/leave/membership changes (new T-intent).
- ADD item 33: emitter toggles (§6a) — disable = instant silence of that
  cable AND removal from All with correct off-pairing incl. shared-channel
  merges; cells keep deriving; re-enable resumes at next articulation; zero
  stuck notes under toggle-hammering (new T-intent, test-procedures).
- ADD item 32: cycles are silent, backward taps work (test T11).
- ADD item 31: the ALL cable — carries every emitter's stream
  channel-distinguished, correctly off-paired even when two emitters share a
  channel; individual cables carry their own streams simultaneously (T10).
- AMEND item covering OUT CH (old T6): channels are now filter-in/stamp-out
  (§7) — per-cell input filters select what a MIDI-IN cell hears; per-bus
  stamps set what every note leaves on; no origin channel survives (test T6,
  re-expressed).
- Items concerning ▾/+SRC semantics (old T2/T3/T5 phrasing) are re-expressed
  in test-procedures.md; the musical intents survive, the mechanism changed.

## 9. Out of scope / unresolved (do not invent)

- Launchpad mapping of graph references: TBD (v2.8 §10 assumed chains).
- Emitter flare in perform when strip legibility fails at small sizes: the
  fallback design (bottom-edge glint) exists in chat history; only if needed.
- Cross-column references: FORBIDDEN, now and later. Reference graphs are per-column.
- The dead-loop (cycle) indicator: DEFERRED — visual design later; engine
  needs nothing.
- RECORDED, UNDESIGNED (2026-07 — the user will expand these in a future
  design pass; log, do NOT design, implement, or let them shape other work):
  1. **TOUCH (per-Colour touch behaviours) — DESIGN SKETCH ON RECORD
     (2026-07; converging, not yet spec).** Desk order becomes COLOUR →
     TOUCH → PROCESSOR → EMITTERS. The TOUCH box is COMPACT: three rows
     (TAP · HOLD · COL-HOLD) showing the selected Colour's assignments
     (DOUBLE-TAP considered and REJECTED 2026-07: the disambiguation delay
     taxes single-tap on an instrument) — each row an OPENER (sub-44 law) for a popover with THREE
     pickers, the 3-AXIS GRAMMAR: **WHAT** (behaviour) × **WHEN** (NOW /
     NEXT STEP / NEXT PASS / NEXT LAP — pass≠lap under §5b holds, deliberately)
     × **HOW LONG** (while-held / until-tapped-again / one pass / one lap).
     "Play one pass" = UNMUTE · next-pass · one-pass — durations are an axis,
     not behaviours. COL-HOLD slot = "while my column is held in the §5b
     lap" (a Colour can auto-ALT under stutter) — NOT a new column-key
     gesture; keys keep tap=mute, hold=lap. Candidate behaviours (ship ~10):
     State ALT/BYP/MUTE-UNMUTE · Structure SOLO-EMITTERS/ISOLATE/FILL ·
     Time SLICE-CYCLE/FREEZE/REVERSE/HALF-DOUBLE · Sound OCT±12/ACCENT/
     GATE/COMMIT-STARVE · Material REPLAY (v1 = live replay, SHIPPED
     decision)/DICE. LAWS already decided: unassigned slots inherit a GLOBAL DEFAULT action
     (currently ALT — the header TAP selector and MUTE/BYP were removed at
     `3e816ee`; TOUCH is the intended vehicle for reintroducing the richer
     action set, engine fields retained); armed
     (quantized-pending) behaviours show the v2.8 QUANT blink. Open: final
     behaviour shortlist; portrait four-box fit.
  2. **Recorded input bar / per-cell capture — DESIGN SKETCH ON RECORD
     (2026-07, refined; still a future item).** DECIDED: TOUCH v1 SHIPS with
     live-replay only (audition's in-time sibling, fully derived). The v2
     direction is PER-CELL CAPTURE, user-refined to resolve the earlier
     objections: every time the playhead passes an active cell, record its
     INPUT — "the pool as sampled at the cell's tick times during its most
     recent activation" (referenced cells therefore capture the TRANSFORMED
     stream, correctly). CLEARED ON TRANSPORT STOP — the memory is of THIS
     run (persistence dilemma dissolved; staleness ≤ ~one pass while
     playing, patchwork dissolved). Replay runs the capture through CURRENT
     params. Memory: bounded static ~64–256KB total (≤32 ticks × 16 notes ×
     64 cells, preallocated) — negligible. Ownership: router writes at
     derivation, reads at replay — render-thread single-writer, no atomics.
     COSTS THAT REMAIN when implemented: a two-sentence invariant-2
     amendment (third sanctioned accumulator: fixed-size, single-writer,
     cleared on stop); CHANCE-upstream captures replay that pass's exact
     dice (feature, document it). The SHARED bar idea demotes to a display
     candidate for the reserved MIDI-IN slot. Do not implement ahead of the
     TOUCH-box design pass.
  3. **Row solo** — soloing at row granularity (relationship to column
     mute/solo and the perform layer unspecified).
  4. **EMITTER performance layer — DESIGN SKETCH ON RECORD (2026-07; future
     version).** Every feature here is a transform AT THE EMISSION BOUNDARY
     (seam rule 3) — no engine-upstream changes, ever:
     - **Velocity faders per emitter** (the mixer; do FIRST): pure scale at
       emission, new stable param addresses (400+bus per invariant 5) ⇒
       host-automatable free. New note-ons only (MIDI can't re-velocity);
       fader-zero floors at vel 1 — suppression stays §6a's job. Best-effort
       on velocity-deaf synths (same category as BLEND).
     - **Note exclusivity with emitter priority** (OFF by default): a pitch
       sounding on a higher-priority emitter is SUPPRESSED on lower ones —
       and the generative reading is the point: lower-priority emitters are
       SPILLOVER channels (the lead claims, the pad gets the residue; with
       CHANCE upstream, B receives the gamble's rejects). Suppress, never
       defer (no retroactive sounding — §6a doctrine). First inter-emitter
       coupling: needs a priority-order control + a withheld-note tell in
       the UI. 
     - **HOCKET mode**: grouped emitters distribute successive notes
       round-robin (rotation index DERIVED from tick derivation, no state) —
       one arp shattered across synths; the 808 State homage made technical.
     - Also logged: velocity-SPLIT routing (soft/hard note ranges per
       emitter), live emitter SWAP (A↔B permutation), TOUCH slots on the
       emitter pads themselves (hold = momentary solo-emitters first).
     Do not implement ahead of a spec pass; the boundary placement is the
     binding constraint.
  5. **COLOUR-PAIR MORPH MODEL — DESIGN SKETCH ON RECORD (2026-07, rev 2;
     supersedes the per-Colour A/B model AND the parked morph-desk direction
     if ratified).** Pairing is PER-COLOUR: beside the palette sits a small
     **ALT box** — empty = this Colour has no second self; tap it to target,
     then pick/drag any Colour in (the partner swatch lives there
     persistently). Cells keep only their alt FLAG; what they flip TO is the
     Colour's pairing. Per-Colour A/B states, A/B tabs, and B-over-A resolve
     are DELETED — Colours are single treatments; the second personality is
     the PARTNER.
     - **Morph is CAPABILITY-TIERED:** FULL (same type — all params glide,
       §3.2 stepped quantize) · SWAP (nothing shared — clean flip, NO fader:
       the fader never lies) · PARTIAL (future, gated on LISTENING TESTS
       per pair): shared CHANNELS glide (TIME: arp/ratchet rate, strum
       spread · DENSITY: ratchet count, chance %, arp octaves · LENGTH:
       gate · TRANSPOSE always, semitone-quantized) while type identity
       flips at midpoint, arriving in-groove. Candidate PARTIAL pairs by
       expected grace: ARP↔RATCHET (showcase), PASSGATE↔CHANCE
       (structure↔dice), STRUM↔ARP, HARMONIZE↔* (marginal). SHIP FULL+SWAP
       FIRST; a fader that sounds broken at 0.3 poisons the ones that work.
     - **RESCUED by colour-level pairing:** morph position is per-Colour →
       param addresses 200+i STAY LIVE (automation surface intact; only the
       address *meaning* updates: morph toward the partner); the 16-strip
       MORPH DESK is structurally viable again (16 Colour-morphs = 16
       strips — un-parks WITH this model); migration softens (old B-state ≈
       partner Colour; scenes 14/16 re-author near-mechanically; loader
       maps empty-alt + log).
     - **UI:** cell ring = the Colour's partner hue (see what it becomes);
       compatible pairs show the MORPH slider in the desk (colour-level →
       it lives with the Colour, not in cell popovers); cell BODY blends
       the two hexes at morph position (interpolation shown, not
       indicated). **Audition-before-commit is FREE**: audition runs on
       effective params, morph is in the resolve — hold-to-audition at 0.4
       hears 0.4.
     - **MORPH-SCRUB joins the TOUCH menu** (HOLD slot): hold a cell + drag
       vertically = scrub its COLOUR's morph (one finger bends every cell
       of that Colour); release springs home or latches (the SPRING
       semantic as a per-assignment option).
     - Schema: Colour gains altColour(0..15|none) + morph(0..1); cell keeps
       alt flag only. NOT ratified — awaiting the user's call after a UI
       mockup (the ratification test: does a grid of ringed pairs READ?).
  6. **FUTURE PROCESSORS — CHANCE family extensions (2026-07; sketches, one
     AMBIGUITY awaiting the user's call).** All are pure derived-dice
     processors (tick/pass → slice index → seeded deterministic roll, the
     existing CHANCE discipline) — engine cost is a cellMode case each; the
     design cost is UI.
     - **NOTE-CHANCE** (chance by musical note). Two candidate forms, decide
       at the design pass: (a) per-POOL-POSITION as BASE + TILT (probability
       a function of sorted chord position; two params; bottom-heavy = bass
       certain, top sparkles — the v1 lean) or (b) per-PITCH-CLASS (12
       weights; scale-tone weighting, maximal control, heavy panel).
     - **STEP-MASK — CONFIRMED as the request (user, 2026-07-23):** the
       cell's active step divides into 4|8 slices, each with probability
       0–100, rolled per tick by slice (seeded deterministic dice). At 0/100
       extremes = a drawable trance-gate/rhythm mask inside the step
       (user's example: 0,0,0,0,100,100,100,100 → only the second half of
       the step sounds); between = probabilistic groove. UI: 4/8 draggable
       mini-bars — the instrument's first DRAWABLE control; introduce the
       species once, reuse it.
     - PASS-MASK (probabilities per pass-slot; generalizes PASSGATE):
       INCIDENTAL suggestion that emerged from the ambiguity — unrequested;
       logged only, cut at leisure.
     - **PICK (requested 2026-07-23) — the voice-splitting primitive:**
       filters the input pool to ONE note. Params collapse to TWO controls:
       FROM {BOTTOM|TOP} + N {1..8} ("lowest"=bottom-1, "highest"=top-1,
       "3rd from top"=top-3 — no special cases). Chord-hold family: sustains
       its selection through the step, reconciles LIVE as held keys change
       (audition-chord-hold machinery); engine = sort pool, index — pure
       one-liner, cheapest processor on the roster. HEADLINE USE: sibling
       PICK cells fan-out one chord engine into monophonic PARTS across
       emitters (voice splitting); also bass extract (bottom-1 → B), sub
       doubler (+ T−12 Colour), topline extract, PICK→RATCHET ratcheted
       bass, PICK→ARP rhythmic pedal. Complements emitter-HOCKET (register-
       stable assignment vs round-robin-in-time). OPEN micro-question:
       out-of-range (N > pool size) = STRICT (silence — voice-splitting
       honest; chord SIZE becomes a performance control: add a 4th note,
       the 4th instrument enters) vs CLAMP (nearest — bass never drops).
       Lean STRICT; decide by ear at the design pass.
     - **CURATED WIDER ROSTER (2026-07-23, rev 2 — merged brainstorms; all
       pure/derived unless noted; champions ★):**
       Pitch/voicing — ★TRANSPOSE-SEQ (per-pass/step transpose pattern: one
       chord becomes a PROGRESSION — the pass dimension's best friend; does
       scene 4 in one cell) · ★ROTATE/INVERT (cycle inversions per
       tick/step/pass — harmony-in-motion, the roster's biggest gap) ·
       VOICING/SPREAD (open/close, drop-2/3) · MIRROR (invert around axis;
       ideal ALT partner). **SCALE — TWO POSITIONS ON RECORD, user to
       adjudicate:** PRO: wrong-note-proofs pitch-ADDING processors
       (HARMONIZE's +7 can leave the key; SCALE after it legitimizes) —
       coherent as a CORRECTIVE. CON: as a general input-override it fights
       the constitution (the held chord IS the truth). Possible resolution:
       scope it explicitly as post-pitch-adder correction.
       Time/feel — BURST (one-shot accel/decel roll at step entry; the
       CURVE distinguishes it from RATCHET) · DRONE (sample pool at entry,
       sustain to boundary — the pad-maker) · CASCADE (pool membership
       revealed incrementally across the step; STRUM's additive cousin) ·
       SHIFT (tick-offset articulation) · HUMANIZE (seeded jitter,
       replay-safe — the deterministic human). EUCLID = a K-of-N GENERATOR
       BUTTON inside STEP-MASK, not a type (both brainstorms converged).
       Dynamics — VELOCITY-CURVE/RAMP (shape across the step; pairs with
       §6a metering) · VELOCITY-MAP (in→out transfer) · ACCENT = STEP-MASK's
       drawable bars writing VELOCITY (one widget species, two modes —
       design them together).
       **PITCH BEND — four coherent roles (2026-07-23; the mismatch is
       real: PB is channel-wide + continuous, the engine is per-note +
       discrete — it never goes "through" a processor):**
       (1) PASSTHROUGH = the player's hand (v1; = the CLAUDE.md OPEN
       DECISION on channel-wide message mirroring). (2) CONTROL SOURCE:
       incoming wheel → morphMaster / a Colour's morph / velocity faders —
       cheapest big win; a sprung pitch wheel IS morph-scrub with hardware
       spring physics. Kernel/param territory, not a processor. (3)
       **GENERATED bend — a BEND processor**: emits bend curves DERIVED
       from beat (one-clock-pure, replay-safe): vibrato (ensemble vibrato
       on chords is legitimate — channel-wide moves all notes together) ·
       dive · rise · seeded drift. LAW: uniform gestures fine; per-note-
       different bends impossible without MPE (far door, standalone
       scope). Killer chain: **PICK → GLIDE** — on a monophonic stream,
       render slides as note+bend-ramp = acid slide lines on ANY synth
       incl. poly (complements the tail-rule overlap-slide: that one asks
       the synth to glide, this one performs it; assumes bend range, ±2
       default, a range setting solves). (4) WILDCARD: received PB as a
       SELECTOR (wheel = ribbon over the held pool) — performance toy,
       logged as such.
       DOCTRINE-FIGHTERS, flagged: MONO/last-note needs event-order memory
       (capture-state class; the only impure idea — last or never). OUT OF
       SCOPE: CC/LFO generators (Kernel/standalone territory, not
       processors).
     - **THE TAIL RULE — design brief (2026-07-23; the cross-step
       amendment, answered ONCE for all customers incl. EXTERNAL tails).**
       Voices MAY outlive their column. Customers, in value order:
       (1) GATE >100% ⇒ inter-step overlap ⇒ SLIDE/LEGATO on mono synths
       (303-style glide is impossible under strict truncation — plausibly
       outranks ECHO for the AUM audience); (2) overlapping pads/washes
       (DRONE at 150–200%); (3) gestures longer than a step (slow STRUM
       spread, BURST deceleration, HUMANIZE's late final tick no longer
       clipped at the edge); (4) performance RING-OUTS (lap release /
       column mute may ring remaining gate instead of chopping — same
       machinery, different trigger; chop-vs-ring becomes a choice);
       (5) ECHO repeats across steps.
       MACHINERY (mostly exists): tails keep their birth cell's
       colour/buses/stamps (voice table already per-cell; the change is
       "don't force-close at column exit"); collisions with later columns
       are ordinary emitted-tuple refcount cases; BOUNDS = the fixed voice
       table (steal-oldest) + a TTL so nothing rings forever; closures
       that ALWAYS apply: transport stop, §6a disable, scene switch.
       **THE FORK the amendment must decide (not inherit by accident):
       are tails REFERENCEABLE** (in the sounding set — children can
       process the echo: ratchet chews repeats, CHANCE gambles on ghosts)
       **or emission-only ghosts** (simpler, no downstream surprises)?
       Decide by ear at the design pass; either answer is fine, an
       accidental answer is not.
  7. **MPE / MIDI 2.0 posture (decided 2026-07-23).**
     - MIDI 2.0 TRANSPORT (UMP / MIDIEventList): hygiene, do SOON — verify
       the Kernel accepts both legacy and eventList input and emits via the
       eventList block (the original scaffold TODO'd this; confirm status),
       translating to MIDI 1.0 semantics internally. Not a feature; a
       compatibility floor that hosts are trending toward requiring.
     - MIDI 2.0 SEMANTICS (16-bit velocity, 32-bit CC, per-note
       controllers): NOT NOW — negligible ecosystem consumption; pools stay
       7-bit; revisit when target synths consume it.
     - **MPE INPUT — a trap is armed:** per-cell channel filters read
       channels as separate controllers; an MPE controller sprays one
       performance across ch2–16 and would be misread as fifteen keyboards.
       NEAR-TERM insurance: an MPE-INPUT MERGE mode (detect-or-toggle,
       fold member channels into one source, strip per-note expression).
       One toggle, one class of confused-user reports prevented.
     - MPE FULL (expression through the engine; MPE OUTPUT): far-future —
       output-side it is the third wave of pitch continuity (dissolves the
       BEND processor's channel-wide limit: per-note vibrato, poly slides)
       AFTER tail-rule slide and PICK→GLIDE prove themselves. FORECLOSURE
       CHECK DONE: nothing blocks it — MPE output = dynamic channel
       allocation at the emission boundary; refcount keys on emitted
       tuples; Emission.swift isolation means it lands later as a
       per-emitter mode at one seam.
  9. **RECORD processor (in-grid MIDI clip capture) — USER'S DESIGN, rev 2
     (2026-07-23; supersedes the rev-1 sketch's arming model; file import
     explicitly NOT wanted — clips persist in the document like presets).**
     - **THE GRID IS THE RECORD BUTTON.** RECORD is a processor type. Paint
       a cell of that Colour; it starts ARMED. Its input channel (the
       SHIPPED per-cell filter, e.g. ⇐MIDI ch2) is the record SOURCE — the
       performer holds the main chord on ch1 and plays the part on ch2.
       While armed, notes on the source channel are captured tick-timed
       DURING the cell's active window as the playhead crosses; at window
       exit the cell flips ARMED → PLAY automatically (one-pass punch-in).
       Doctrine note (user's correction, accepted): multi-channel input
       already made the instrument multi-performer — recorded playback is
       a third hand, not a constitutional break.
     - **Clips live ON THE COLOUR like its params** → document/fullState
       persistence (save/load survives; NO file I/O). Painting the Colour
       to many cells = looper behaviour with ORCHESTRATION DECIDED IN
       ADVANCE by placement.
     - Capture infra: render-side bounded buffer during the window; ONE
       main-thread document commit at WINDOW EXIT (a defined moment);
       shared with item 2's capture infra — build once.
     - **LENGTH is a Colour PARAM (1–8 steps; user 2026-07-23):** the
       window opens at the cell's column entry and spans LENGTH steps
       regardless of what occupies those columns (leaving them free for
       other cells — including other recorders). Supersedes the
       run-painting lean.
     - **RECORD MODE: ONE-SHOT vs OVERDUB (always-listening; user
       2026-07-23).** OVERDUB never flips to play-only: every pass the
       window plays back AND captures, each window-exit committing that
       pass's additions as a discrete batch ⇒ UNDO-LAST-LAYER is nearly
       free (pop the last batch). Capacity policy when the bounded clip
       buffer fills: lean STOP-ADDING (predictable); steal-oldest ("the
       forgetting looper") logged as a deliberate variant, not a default.
     - **OVERLAPPING WINDOWS: YES — capture is READ-ONLY FAN-OUT** (any
       number of open windows transcribe the same source simultaneously,
       own window-relative timestamps). RULE: overlapping recorders must
       be DIFFERENT Record Colours; ONE open window per Colour at a time
       (first crossing wins; other placements of that Colour play back).
       Musical bonus on record: a long window + a short window over the
       same take = sampled-fragment orchestration / automatic canon (the
       same performance quoted at offsets).
     - **UNLOCKS (2026-07-23 — consequences, not new machinery):**
       (1) **RESAMPLING**: a RECORD cell with ⇐Rn records ANOTHER CELL'S
       OUTPUT (capture records what the cell hears; do NOT restrict
       RECORD's input to MIDI-only — the feature is one absent restriction).
       ⇒ the dice types become PRINTABLE ("print the take": CHANCE's
       perfect pass becomes a clip; mute the chain, the keeper plays);
       chains bounce to phrases; and with the colour-pair model, a
       generative Colour ALT-paired with its own printed RECORD Colour =
       TAP flips a part between GENERATIVE and COMMITTED, live.
       (2) Factory scenes may ship riffs (SceneFactory authors clips in
       code — no file I/O involved).
       (3) TAKES: the overdub batch structure supports a small pop-able
       layer stack beyond single undo — growth, not v1.
       (4) RULE: record windows follow the TRUE timeline, never the §5b
       lap's effective column (recording during a stutter captures real
       bar-time — PASSGATE's side of the line).
       (5) CONSOLIDATION: parked item 2 (recorded input bar / TOUCH-replay
       capture) = a CONFIGURATION of this machinery (always-listening,
       length-8, EPHEMERAL) — one infrastructure, two lifecycles; design
       and build ONCE when the pass opens.
     - **OPEN QUESTIONS (remaining):** re-arm/clear UX — REC + CLEAR on
       the Colour panel; the ARMED cell state needs a visual (record-red
       ring; the one new cell state this adds); OVERDUB's undo depth
       (one layer or a small stack).
     - Playback: v1 = ABS (a captured performance plays as performed;
       input dormant in play mode). ROOT-FOLLOW / DEGREE-FOLLOW demote to
       optional per-Colour PLAYBACK MODES later (the riff-machine case).
       PHASE applies to playback: RETRIG one-shot per column · LEGATO
       across runs · FREE = the clip loops against absolute beat, cells
       are windows onto it. Clip-vs-window length: truncate at exit
       (tail-rule customer later).
     - Graph citizenship stands: RECORD cells feed processors (RATCHET
       chews the phrase, CHANCE gambles on it, PICK extracts its bass);
       colour-pair morph gives clip↔clip ALT pairs.
  8. **HARDWARE GRID SURFACES (Launchpad / Push) — plan on record
     (2026-07-23; supersedes v2.8 §10's TBD, which worried about the
     routing model — irrelevant: the surface speaks only the perform
     layer, which is model-agnostic).**
     - **GATING SPIKE (do first, an afternoon):** direct CoreMIDI from the
       AU EXTENSION on-device — attach a Launchpad, echo presses, light
       pads. Direct-attach is the architecture (bidirectional, no host
       routing, no wasted emitter, presses never pollute the source pool);
       allowed on iOS and shipped by other AUv3 sequencers, but verify on
       OUR extension. Fallback if it fails: controller-channel convention
       via host routing (uglier) and/or standalone-first.
     - BUILD: (1) device-profile layer, **Launchpad X/Mk3 FIRST** (SysEx
       RGB shows the ACTUAL sixteen Colour hexes); (2) state→LED renderer =
       grid snapshot + live-column lift + firing flashes — the §6a
       activity-metering feed REUSED; (3) input translator calls the SAME
       functions GUI touches call (tap = TAP/TOUCH, hold = HOLD slot;
       **top-row buttons = column keys — §5b's multi-hold lap was born for
       physical buttons**; side buttons = scene slots, 8 paged to 16);
       (4) settings: enable + auto-detect by device name.
     - SCOPE: **PERFORM-only v1** (EDIT stays on glass; painting needs the
       palette). Push = later pads-only profile (the display needs a USB
       bulk driver — never on iPad; encoders→selected-Colour params =
       unlabeled stretch goal, honestly capped).
     - SEQUENCE: after multi-scene + perform v2 land (the lap is the
       hardware showcase); standalone helps but is NOT a prerequisite if
       the spike passes.
- EXTERNAL processor type (hosted 3rd-party MIDI AUv3s): decided direction,
  standalone-only by platform law, fully deferred — see
  Docs/standalone-plan.md. Do not design or implement ahead of it; DO honour
  the router contract it states (articulate-in / track-voices-out, never
  assume processor purity).
