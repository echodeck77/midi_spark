//  HardeningCorpus.swift (macOS test target) — ENGINE HARDENING 1 (2026-11-21).
//  The document corpus the §3 invariants and the §4 fuzz run over IN THE NORMAL SUITE, plus the shared
//  render driver. The corpus is the release default + every factory preset + authored per-feature
//  documents (mirroring the harness's GOLDEN HARDENING group but built here so the pure checks run
//  without the simulator). Documents are built with MIDI IN OCTAVES KEEP so a held chord stays where it
//  is played (the default IGNORE fold has its own tests); that matches the RouterTests/HocketGolden setup.

import Foundation

/// A corpus entry: a name and a builder (fresh each call — never shared mutable state).
struct CorpusDoc { let name: String; let make: () -> PluginState }

enum HardeningCorpus {

    /// Build the published SnapshotBox for a document exactly as the app does (FourfoldCompose chain),
    /// with OCTAVES KEEP. Mirrors HocketGoldenTests.box(for:) and the harness's publishDocument().
    /// `sameNoteGuard: false` disables the window-length-dependent same-pitch off-shortening (its own
    /// SameNoteGuardTests cover it) — the block-size / sample-rate INVARIANCE checks pass false so they
    /// measure the engine's own event placement, not the guard's deliberate per-window behaviour.
    static func box(for s0: PluginState, sameNoteGuard: Bool = true) -> SnapshotBox {
        var st = s0
        if !sameNoteGuard { st.euclideousSameNoteGuard = false }
        var plan = st.sourcePlanResolved; plan.midiOctaves = .keep; st.euclideousSourcePlan = plan
        if !st.machines.contains(where: { $0.machineID == FourfoldCompose.machineID }) {
            st.machines.append(Machine(machineID: FourfoldCompose.machineID, type: .euclid))
        }
        let input = FourfoldCompose.Input(lines: st.euclideousLinesResolved, riff: st.euclideousRiffResolved,
                                          riffs: st.riffsResolved, activeRiff: st.activeRiffResolved,
                                          soloMask: st.euclideousSoloMaskResolved,
                                          locks: st.euclideousLocksResolved, lockRevs: 0)
        st.scenes = [FourfoldCompose.scene(input)]
        return SnapshotBuilder.build(from: st)
    }

    /// Default + every factory preset. These are the always-available, always-current documents.
    static var presets: [CorpusDoc] {
        [CorpusDoc(name: "(default)") { PluginState.makeInit() }]
        + EuclideousPresets.all.map { p in CorpusDoc(name: p.name, make: p.make) }
    }

    /// Authored per-feature documents — each isolates one area of the coverage map so an invariant
    /// failure points at a feature. Built on top of a fresh init; only literal, deterministic edits.
    static var authored: [CorpusDoc] {
        func lanes(_ s: inout PluginState, _ f: (inout EuclidLine, Int) -> Void) {
            var ls = s.euclideousLinesResolved; for i in 0..<ls.count { f(&ls[i], i) }; s.euclideousLines = ls
        }
        var out: [CorpusDoc] = []
        func doc(_ name: String, _ edit: @escaping (inout PluginState) -> Void) {
            out.append(CorpusDoc(name: name) { var s = PluginState.makeInit(); edit(&s); return s })
        }

        doc("EUCLID directions") { s in
            let dirs: [EuclidDir] = [.fwd, .bkw, .pingpong, .fwd]
            lanes(&s) { l, i in l.enabled = true; l.riffOn = true; l.pulses = [5, 7, 3, 16][i]; l.steps = [8, 16, 5, 16][i]
                l.rotate = i; l.direction = dirs[i]; if i == 3 { l.patternMiss = true } }
        }
        doc("RIFF walks") { s in
            let rd: [RiffDir] = [.forward, .reverse, .pingpong, .forward]
            let rest: [EuclidRiffOnRest] = [.skip, .tie, .repeatLast, .skip]
            lanes(&s) { l, i in l.enabled = true; l.riffOn = true; l.riffStride = [1, 3, 2, 1][i]
                l.riffLength = [8, 5, 4, 8][i]; l.riffRotate = i; l.riffDir = rd[i]
                l.riffOnRest = rest[i]; l.riffAdvanceEvery = [1, 2, 1, 1][i] }
        }
        doc("STACK lit") { s in
            lanes(&s) { l, i in l.enabled = true; l.notesOn = true; l.riffOn = (i % 2 == 0)
                l.notesLitOrder = [[0, 2, 4], [1, 3], [0, 7, 8], [2, 5, 9]][i].map { UInt8($0) } }
        }
        doc("INPUTS lanes apart") { s in
            s.euclideousKeyType = .dorian
            lanes(&s) { l, i in l.enabled = true; l.riffOn = true
                l.poolSrcMask = [0b00001, 0b00010, 0b10000, 0b01100][i]   // MIDI / CHORD1 / CHORD2 / PICK+KEY
                l.midiMode = [nil, .replace, .root, nil][i] }
        }
        doc("MIX routing") { s in
            s.busChannels = [16, 1, 9, 2]
            s.euclideousPartSoloMask = 0b000011   // lane 1 both parts latched solo
            lanes(&s) { l, i in l.enabled = true; l.riffOn = true; l.notesOn = true
                l.riffOutMask = [0b0011, 0b0000, 0b0100, 0b1000][i]   // two outs / none / shared C / D
                l.notesOutMask = [0b0001, 0b0100, 0b0100, 0b1000][i] }
        }
        doc("empty riff nothing lit") { s in
            s.riffs = [EuclideousRiff.empty]
            lanes(&s) { l, _ in l.enabled = true; l.riffOn = true; l.notesOn = true; l.notesLitOrder = [] }
        }
        doc("no outputs") { s in lanes(&s) { l, _ in l.enabled = true; l.riffOn = true; l.riffOutMask = 0; l.notesOutMask = 0 } }
        doc("one step zero hits hits==steps") { s in
            lanes(&s) { l, i in l.enabled = true; l.riffOn = true
                l.steps = [1, 8, 5, 16][i]; l.pulses = [1, 0, 5, 16][i] } }
        doc("all on output A") { s in
            s.busChannels = [1, 1, 1, 1]
            lanes(&s) { l, _ in l.enabled = true; l.riffOn = true; l.riffOutMask = 0b0001; l.notesOutMask = 0b0001 } }

        return out
    }

    /// The whole normal-suite corpus (presets + authored). The §4 fuzz adds random documents on top.
    static var all: [CorpusDoc] { presets + authored }

    // MARK: - render driver

    /// Chunk `totalSamples` into render windows. `fixed` = constant block; `varying` = a seeded sequence
    /// drawn from the given sizes (so a run can vary block size call to call, §3.5).
    enum BlockPlan {
        case fixed(Int)
        case varying(sizes: [Int], seed: UInt64)
        func sizes(total: Int) -> [Int] {
            switch self {
            case .fixed(let n):
                var out: [Int] = []; var r = total; while r > 0 { let s = min(n, r); out.append(s); r -= s }; return out
            case .varying(let sizes, let seed):
                var out: [Int] = []; var r = total; var x = seed == 0 ? 0x9E3779B97F4A7C15 : seed
                while r > 0 {
                    x ^= x << 13; x ^= x >> 7; x ^= x << 17
                    let s = min(sizes[Int(x % UInt64(sizes.count))], r); out.append(s); r -= s
                }
                return out
            }
        }
    }

    /// Render a document playing CONTINUOUSLY from sample 0 for `beats` musical beats, then one stop
    /// window (flush). beatPos at each window = cumulativeSample × tempo / 60 / sr — so the musical
    /// trajectory is identical whatever the block plan: the §3.5/§3.6 comparison axis. Fresh Router.
    static func renderContinuous(_ doc: PluginState, beats: Double, sr: Double = 48_000, tempo: Double = 120,
                                 block: BlockPlan = .fixed(480), hold: [UInt8] = [60, 64, 67],
                                 sameNoteGuard: Bool = true) -> WireRecorder {
        let b = box(for: doc, sameNoteGuard: sameNoteGuard)
        let pool = NotePool(); for n in hold { pool.noteOn(n, velocity: 100, channel: 0) }
        let router = Router(); var diag = KernelDiag(); let rec = WireRecorder()
        let totalSamples = Int((beats * 60.0 / tempo * sr).rounded())
        let bps = tempo / 60.0 / sr
        var cum = 0
        for n in block.sizes(total: totalSamples) {
            let beat = Double(cum) * bps
            rec.beginWindow(start: Int64(cum), frames: Int64(n), beat0: beat, beatsPerSample: bps)
            router.process(box: b, pool: pool, playing: true, beatPos: beat, tempo: tempo, sampleRate: sr,
                           timestampSample: Double(cum), frameCount: UInt32(n), out: rec, diag: &diag)
            rec.endWindow()
            cum += n
        }
        let beat = Double(cum) * bps
        rec.beginWindow(start: Int64(cum), frames: 512, beat0: beat, beatsPerSample: bps)
        router.process(box: b, pool: pool, playing: false, beatPos: beat, tempo: tempo, sampleRate: sr,
                       timestampSample: Double(cum), frameCount: 512, out: rec, diag: &diag)
        rec.endWindow()
        return rec
    }

    /// Canonical stream in BEAT space (sample → beat), for comparing renders at different sample rates
    /// (§3.6): a note at the same musical beat lands at a different sample at 44.1 vs 96 kHz. Beats are
    /// rounded to the nearest 1/1e6 so float noise within ±1 sample collapses.
    static func beatStream(_ rec: WireRecorder, sr: Double, tempo: Double = 120) -> [String] {
        let canon = HardeningInvariants.canonical(rec.events, windows: rec.windows)
        return canon.map { e in
            let beat = (Double(e.sample) * tempo / 60.0 / sr * 1_000.0).rounded() / 1_000.0   // 1/1000-beat ≈ well under one sample
            return "\(beat)|\(e.cable)|\(e.b0)|\(e.b1)|\(e.b2)"
        }
    }
}
