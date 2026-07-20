# Snapshot Bridge — build-order step 2 (spec §7)

## What changed
- `AUExtension/Snapshot.swift` (new): SnapshotBox (flat, immutable), effective-param
  helpers (§3.2 quantized morph interp, §13.5 MASTER formula), SnapshotStore
  (atomic publish/acquire; publish is MAIN THREAD ONLY; last 3 boxes kept alive).
- `AUExtension/SnapshotBuilder.swift` (new): document → box. Resolves sparse paramsB
  over paramsA, enum→index mapping, and LEGATO runStartColumn per row (§7 v2.4).
- `AUExtension/Kernel.swift` (rewritten): reads the snapshot every render. The demo
  arp's rate/gate/octaves come from colour "gold" via morph(+MASTER); swing is a
  beat-space warp (real ⇄ musical) so derivation stays accumulation-free (§4).
- `AUExtension/MidiSparkAudioUnit.swift`: owns the store; parameter writes and
  fullState loads publish fresh snapshots (coalesced when off-main).
- `project.yml`: adds the apple/swift-atomics SPM package (fetched on first
  `xcodegen generate` + Xcode resolve; needs network once).

## Re-generate & build
```bash
xcodegen generate     # picks up the package + new files
open MidiSpark.xcodeproj
```
Xcode will resolve swift-atomics on first open. Build both targets as before.

## Hear the bridge working (the point of step 2)
In AUM, with a chord held and transport running:
1. Automate/adjust **Morph Gold** (parameter) 0→1: the arp's rate LADDER-STEPS
   (1/16 → 1/32 territory) and gate shifts — quantized, never gliding (§3.2).
2. Adjust **Morph Master**: same effect across the patch (formula §13.5).
3. Adjust **Swing** 50→66: the arp limps at the STEP level; subdivisions divide the
   warped step evenly. At exactly 50 the maths is identity — timing must be
   bit-identical to pre-swing (acceptance 23's future check, provable now).
4. Sync torture as before: tempo changes, loops, relocation — still drift-free.

## Invariants this step establishes (do not regress)
- Render thread reads ONLY SnapshotBox. It never touches PluginState.
- Boxes are immutable after construction. All resolution happens in the builder.
- publish() on main only; acquire() is one atomic load, no locks, no allocation.
- Step 3 (the router) consumes cells[]/busMask/runStartColumn from here — the
  bridge already carries everything the router needs.
