# MidiSpark spec v3.0-delta — routing model + visual language revision

STATUS: AUTHORITATIVE. This delta supersedes the listed sections of
`midispark-spec-v2.8.md`. Where this document is silent, v2.8 stands unchanged
(colours/cells/presets, processors, morph/ALT, swing, QUANT, performance layers,
engine snapshot architecture, collision policy, parameters, MORPH desk).
Reference implementation of the UI: `Docs/midispark-preview-v56.html`
(v50/v51 contain a JSX bug — do not use; v52 fixed base → v53 responsive desk
→ v54 three-box layout → v55 big emitters → v56 scene strip = canonical).
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

The perform grid is a **readable table that plays**. Reference: v56 preview.

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
channel readouts. A **SCENE strip** runs full-width along the BOTTOM in both
orientations: 8 slots, current highlighted (dev builds host the canned test
sessions in these slots until scenes are implemented). RESERVED, details TBD:
a MIDI-IN display ABOVE the COLOUR box. BACKLOG (log, don't invent):
collapsible/scalable desk sections for tucking away unused panels.
Final dimension tuning happens on device.

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

- The AU declares FIVE MIDI outputs: `["MidiSpark ALL", "MidiSpark A", "B",
  "C", "D"]` (cables 0–4). Static, all modes of host served simultaneously:
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
- EXTERNAL processor type (hosted 3rd-party MIDI AUv3s): decided direction,
  standalone-only by platform law, fully deferred — see
  Docs/standalone-plan.md. Do not design or implement ahead of it; DO honour
  the router contract it states (articulate-in / track-voices-out, never
  assume processor purity).
