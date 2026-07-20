# Router design — build-order step 3

Engineering plan for replacing the hardcoded demo arp with the grid-driven engine.
Contract: spec §2 (routing), §7 (engine), §1.1 (instance model). This doc is the *how*;
the spec is the *what*. Where they disagree, the spec wins and this doc gets fixed.

## Scope

IN: derivation of each cell's input (sender decides), chain evaluation top→bottom,
per-cell ARP invocation with PHASE modes, identity behaviour for not-yet-implemented
types, bus emission with OUT CH stamping and transpose, the (bus, channel, note)
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
- A fed cell's input pool = its feeder's *sounding set*, sampled at each of the
  fed cell's own tick times (+ the source pool if +SRC). This is what makes
  ARP→ARP "arpeggiate the arpeggio" (§1.1.3) work: the downstream arp cycles
  whatever the upstream arp is sounding when the downstream tick fires.
- Everything is derived per tick from (beat position, snapshot, source pool).
  No cell owns cross-render state except its entry in the voice table.

Pool entries carry `(note: UInt8, velocity: UInt8, channel: UInt8)` — channel is
required because OUT CH = INHERIT stamps the *original* channel (§2.6). The
kernel's source pool must be upgraded from velocities-by-note to entries.

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
   a. Skip empty cells. Muted cells produce nothing and feed nothing (follower
      derives source — automatic, because the follower checks feeder-muted).
   b. Input pool: `fed = row>0 && cellAbove.stack && cellAbove occupied &&
      !cellAbove.muted`; input = fed ? feederSoundingSet : sourcePool;
      if `srcMix` union with sourcePool. Bypassed cells: identity — their
      sounding set IS their input pool (articulated at step entry), and they
      feed it onward.
   c. Compute the cell's tick times in this render window from its effective
      params (morph/master/overrides — reuse the bridge helpers) and its PHASE
      formula (below). At each tick: pick note(s), apply the Colour's transpose
      (clamp 0–127, skip out-of-range, pairing preserved), emit.
6. Emission: for each lit bus bit, `channel = outChannel == 0 ? entry.channel
   : outChannel - 1`; note-on through the refcount (below) at the tick's
   unwarped sample time; register the voice.

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

Fixed-size, allocated at `allocateRenderResources`:

```
struct Voice { active, cellIndex, note, channel, busMask }   // e.g. 128 slots
refcount: UInt8[4][16][128]                                   // bus × channel × note = 8 KB
```

- Note-on: ALWAYS emit on each lit bus (re-articulation is policy); increment
  refcount per (bus, channel, note); record the voice with its owning cell.
- Note-off (gate end, next tick, column transition, mute, reset): per bus,
  decrement; **emit the wire off only when the count hits zero**. Free the voice.
- No restoration strike (clause 3). Transport stop / `reset()`: close every
  active voice AND zero the refcount table (belt and braces: also flush any
  nonzero refcount entries with an off — a leak here is a stuck note).
- Invariant check (debug builds): after a full close, table must be all-zero.

## Testability requirement (do this FIRST)

There is no grid UI until step 5, so the router cannot be exercised without
canned documents. Before router work:
- Add `TestSessions.swift`: ~8 named `PluginState` builders (T1–T8, defined in
  docs/test-procedures.md).
- Add a row of buttons to the diagnostic view that loads each via the normal
  document path (`document = T_n; scheduleRebuild()`), so the human can switch
  test patches on-device without Xcode.
This also incidentally tests fullState-shaped mutation end-to-end.

## File plan & commits (small, verifiable increments)

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
