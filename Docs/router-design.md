# Router design — build-order step 3 [STATUS: IMPLEMENTED under the OLD model]

> This document guided the router as BUILT (chain model). Routing semantics are
> now superseded by spec v3.0-delta + Docs/migration-tree-routing.md — for the
> migration, this doc remains the reference for everything the migration's
> guard-rail says not to touch (voices, refcount policy, PHASE formulas,
> per-render flow). Sections marked HISTORICAL describe the old model.

Engineering plan for replacing the hardcoded demo arp with the grid-driven engine.
Contract: spec §2 (routing), §7 (engine), §1.1 (instance model). This doc is the *how*;
the spec is the *what*. Where they disagree, the spec wins and this doc gets fixed.

## Scope

IN: derivation of each cell's input (HISTORICAL: sender-decides; now
receiver-picked references per delta §1), evaluation top→bottom, per-cell ARP
invocation with PHASE modes, identity behaviour for not-yet-implemented
types, bus emission with transpose (channel handling now per delta §7), the (bus, channel, note)
collision refcount, column-transition note handling, effective-column override
(lock fields — engine support now, UI later).

OUT (step 4+): RATCHET/PASSGATE/STRUM/CHANCE/HARMONIZE real behaviour, swing-warped
subdivision *interactions* beyond what the bridge already does, QUANT pending-set,
event budget thinning (stub the hook, don't implement).

## The processing model (the subtle decision, made explicit)

Chains do NOT pass event streams; they pass **time-varying pools**.

- Every cell exposes, at any moment within the active step, a **sounding set**:
  the notes it is currently emitting (for ARP: usually one note; for identity
  types: its whole input pool, articulated at step entry).
- A referencing cell's input pool = its PARENT's *sounding set*, sampled at
  each of its own tick times. The parent is named by the cell's `inputRow`
  (null = the source; otherwise ANY other row — see spec v3.0-delta §1;
  downward references and cycles are legal). Fan-out (several cells
  referencing one parent) is legal and free. This is what makes ARP→ARP "arpeggiate the
  arpeggio" work: the downstream arp cycles whatever its parent is sounding
  when the downstream tick fires.
- Everything is derived per tick from (beat position, snapshot, source pool).
  No cell owns cross-render state except its entry in the voice table.

Pool entries carry `(note, velocity)`. Channel exists ONLY in the raw source
pool, where per-cell input filters read it (delta §7); it is dropped at every
cell's front door and never threads through the graph. (HISTORICAL: the
INHERIT design that required channel-through-the-chain is deleted.)

## Per-render flow

1. `acquire()` snapshot; clear param overrides if generation changed (existing).
2. Derive transport, beat, tempo (existing). Derive `trueColumn`, `pass`.
3. Effective column: `lockLo/lockHi` from snapshot (both −1 today) → `effColumn`.
   Implement the override now; it's three lines and step 6 turns it on.
4. **Column transition** (`effColumn != prevEffColumn` or transport edge):
   close ALL voices at the boundary sample time (truncate policy), then treat the
   new column as fresh. Locks and relocations are the same transition (§7: no
   special cases).
5. For the active column, evaluate rows 0→7 (top→bottom, so feeders precede fed):
   a. Skip empty cells. Muted cells produce nothing and are invisible as
      parents (children revert to source — automatic via the derivation).
   b. Input pool: `p = resolvedParent(cell)` (snapshot-precomputed: inputRow
      if occupied, else null; render-side additionally treats a MUTED parent
      as null). input = p != null ? soundingSet(p) : sourcePool. There is no
      union; +SRC/srcMix no longer exist. Bypassed cells: identity — their
      sounding set IS their input pool (articulated at step entry), and they
      remain valid parents.
   c. Compute the cell's tick times in this render window from its effective
      params (morph/master/overrides — reuse the bridge helpers) and its PHASE
      formula (below). At each tick: pick note(s), apply the Colour's transpose
      (clamp 0–127, skip out-of-range, pairing preserved), emit.
6. Emission: for each lit bus, stamp `busChannels[bus]` and emit TWICE — on
   the bus's own cable (bus+1) and on the ALL cable (0) — through the
   refcount (below) at the tick's unwarped sample time; register the voice.
   (Delta §7/§7b; lands with the outputs commit.)

## PHASE formulas (§3.5) — all pure functions

Let `sub` = subdivisions of the (warped-domain) musical beat at the cell's
effective rate; `m` = musical beat (post swing warp, existing helpers).
- RETRIG: `phaseIndex = floor((m − stepStart(m)) / rateBeats)`
- LEGATO: `runStart = cells[idx].runStartColumn` (snapshot-precomputed);
  `phaseIndex = floor((m − columnStartBeat(runStart)) / rateBeats)`
- FREE: `phaseIndex = floor(m / rateBeats) mod patternLength` — use integer
  math on a rational tick count, not accumulated floats (§7).
Pattern note selection: index into the sorted input pool per pattern
(UP for step 3; other patterns are cheap once the plumbing exists), octave span
as in the bridge. Chord changes: continue by index (never reset).

## Voices & the collision refcount (§7 policy, clauses 1–4)

Note evaluation order needs NO topological sort even with downward references
and cycles (legal per delta §1): evaluate rows 0→7 against PERSISTENT
sounding state (the voice table). Upward refs read this-pass values; downward
refs read the referenced cell's voices as they stand — a unit delay, exactly
how audio feedback loops resolve. Cycles receive no external entry (single
input ⇒ closed loop) and therefore stay silent without any special handling.

Fixed-size, allocated at `allocateRenderResources`:

```
struct Voice { active, cellIndex, note, channel, busMask }   // e.g. 128 slots
refcount: UInt8[5][16][128]                                   // cable × channel × note = 10 KB (ALL + A–D)
```

- Note-on: ALWAYS emit on each lit bus (re-articulation is policy); increment
  refcount per (bus, channel, note); record the voice with its owning cell.
- Note-off (gate end, next tick, column transition, mute, reset): per bus,
  decrement; **emit the wire off only when the count hits zero**. Free the voice.
- No restoration strike (clause 3). Transport stop / `reset()`: close every
  active voice AND zero the refcount table (belt and braces: also flush any
  nonzero refcount entries with an off — a leak here is a stuck note).
- Invariant check (debug builds): after a full close, table must be all-zero.

## Testability requirement

TestSessions remain the CANONICAL engine-test harness even now a grid UI
exists: canned documents are exact and repeatable; hand-authored patches are
not. Keep both paths working. As originally specified:
- Add `TestSessions.swift`: ~8 named `PluginState` builders (T1–T8, defined in
  Docs/test-procedures.md).
- Add a row of buttons to the diagnostic view that loads each via the normal
  document path (`document = T_n; scheduleRebuild()`), so the human can switch
  test patches on-device without Xcode.
This also incidentally tests fullState-shaped mutation end-to-end.

## File plan & commits [HISTORICAL — completed as built under the old model;
the migration doc sequences all further changes]

1. `TestSessions.swift` + diag buttons. Human check: T1 behaves like today.
2. Pool upgrade (entries with channel) + INHERIT stamping. Check: T6.
3. `Router.swift`: column transitions + single-cell ARP via router path
   (delete demo-arp code from Kernel; Kernel keeps transport/pool/dispatch and
   calls Router). Check: T1 identical to before.
4. Chains + identity types + srcMix + muted-feeder reroute. Check: T2, T3, T5.
5. Buses/fan-out + refcount. Check: T4, T7 (the collision test, on a monitor).
6. PHASE formulas. Check: T8.
Tag `v0.3-router` when T1–T8 pass.

## Diagnostics to add for this step

Extend KernelDiag: active voice count, refcount-nonzero count, effColumn, pass,
last emission (bus, ch, note), per-render emitted-event count. The diag panel is
the human's window; keep it current with every engine capability.
