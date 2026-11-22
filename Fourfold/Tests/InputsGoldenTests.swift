//  InputsGoldenTests.swift — INPUTS + HARMONY ferry (2026-11-06) §10 test 1: golden renders captured BEFORE any change. The default document and every factory preset, through the FOURFOLD chain (`FourfoldCompose`, the path the AU publishes),
//  32 bars at 120 BPM in 480-frame windows, under the page's MIDI mode ADD, REPLACE and ROOT (which become each lane's fallback mode, ferry 1.1) and four hold scenarios — nothing held; a held C-major triad with OCTAVES KEEP; the same with
//  OCTAVES IGNORE; the triad held for 8 bars then released (ROOT latches its transpose) — hashing every message in emission order (sample, cable, status+channel, note, velocity). With FREEZE 0, SUSTAIN off and SLIP 0 (every
//  factory document: none sets any) the stream must stay bit-identical after the ferry: a changed hash here is a bug, not a re-baseline. CAPTURED on origin/main 4cb3c12, before the ferry.

import XCTest

private final class InputsGoldenEmitter: MIDIEmitter {
    var h: UInt64 = 0xcbf29ce484222325
    var events = 0, ons = 0
    private func mix(_ v: UInt64) { h = (h ^ v) &* 0x100000001b3 }
    func emit(sampleTime: Int64, cable: UInt8, _ b0: UInt8, _ b1: UInt8, _ b2: UInt8) {
        mix(UInt64(bitPattern: sampleTime)); mix(UInt64(cable)); mix(UInt64(b0)); mix(UInt64(b1)); mix(UInt64(b2))
        events += 1
        if b0 & 0xF0 == 0x90 && b2 > 0 { ons += 1 }
    }
}

final class InputsGoldenTests: XCTestCase {
    enum Hold: String, CaseIterable { case none = "nothing held", keep = "held, KEEP", ignore = "held, IGNORE", released = "held 8 bars then released" }

    private func box(for s0: PluginState, mode: MidiMode, octaves: MidiOctaves) -> SnapshotBox {
        var st = s0
        st.euclideousSameNoteGuard = false   // the pre-guard stream, as the other goldens pin
        var plan = st.sourcePlanResolved; plan.midiMode = mode; plan.midiOctaves = octaves; st.euclideousSourcePlan = plan
        st.machines.append(Machine(machineID: FourfoldCompose.machineID, type: .euclid))
        let input = FourfoldCompose.Input(lines: st.euclideousLinesResolved, riff: st.euclideousRiffResolved, riffs: st.riffsResolved,
                                          activeRiff: st.activeRiffResolved, soloMask: st.euclideousSoloMaskResolved,
                                          locks: st.euclideousLocksResolved, lockRevs: 0)
        st.scenes = [FourfoldCompose.scene(input)]
        return SnapshotBuilder.build(from: st)
    }

    private func render(_ s: PluginState, mode: MidiMode, hold: Hold) -> (hash: UInt64, events: Int, ons: Int) {
        let b = box(for: s, mode: mode, octaves: hold == .ignore ? .ignore : .keep)
        let pool = NotePool()
        let notes: [UInt8] = [60, 64, 67]
        if hold != .none { for n in notes { pool.noteOn(n, velocity: 100, channel: 0) } }
        let router = Router(); var diag = KernelDiag(); let e = InputsGoldenEmitter()
        let sr = 48_000.0, tempo = 120.0, frames: UInt32 = 480
        let totalFrames = Int(32 * 4 * 60.0 / tempo * sr)
        var done = 0, beat = 0.0, ts = 0.0, released = false
        while done < totalFrames {
            if hold == .released, !released, beat >= 32 { for n in notes { pool.noteOff(n) }; released = true }
            let n = UInt32(min(Int(frames), totalFrames - done))
            router.process(box: b, pool: pool, playing: true, beatPos: beat, tempo: tempo, sampleRate: sr, timestampSample: ts, frameCount: n, out: e, diag: &diag)
            done += Int(n); beat += Double(n) * tempo / 60.0 / sr; ts += Double(n)
        }
        router.process(box: b, pool: pool, playing: false, beatPos: beat, tempo: tempo, sampleRate: sr, timestampSample: ts, frameCount: 512, out: e, diag: &diag)
        return (e.h, e.events, e.ons)
    }

    private var documents: [(name: String, make: () -> PluginState)] {
        [("(default)", { PluginState.makeInit() })] + EuclideousPresets.all.map { ($0.name, $0.make) }
    }

    /// "document|scenario|mode" → (hash, events, note-ons).
    private let golden: [String: (UInt64, Int, Int)] = [
        // DEFAULT DOC RE-BASELINED (Paul 2026-11-18): the fresh default is now MIDI IN + CHORDS grid 1 (was KEY)
        // and the default riff is a plain ascending run (was the arch R1) — so the "(default)" stream legitimately
        // moves. The 20 factory presets set `sourceMode = .key` + pin the arch riff, so THEY stay bit-identical
        // (unchanged below). These 12 entries are re-captured from the CAPTURE output of this very test:
        // RE-PINNED 2026-11-22 for the 22-preset roster (preset redesign b22ef71/c2788bf/943a7e3), engine unchanged:
        // rebuilt ARPEGGIO LADDER / KOTEKAN / PING-PONG LEAD / SCALE WALK re-captured, the new presets added, retired names dropped.
        "(default)|held 8 bars then released|ADD": (13886482855600816069, 1024, 512),
        "(default)|held 8 bars then released|REPLACE": (16247500885243126169, 1024, 512),
        "(default)|held 8 bars then released|ROOT": (6423042572934091401, 1024, 512),
        "(default)|held, IGNORE|ADD": (15882602144144395745, 1024, 512),
        "(default)|held, IGNORE|REPLACE": (16054217090826119369, 1024, 512),
        "(default)|held, IGNORE|ROOT": (6423042572934091401, 1024, 512),
        "(default)|held, KEEP|ADD": (9764849573068998081, 1024, 512),
        "(default)|held, KEEP|REPLACE": (14765769720292496329, 1024, 512),
        "(default)|held, KEEP|ROOT": (6423042572934091401, 1024, 512),
        "(default)|nothing held|ADD": (3088691733876276321, 1024, 512),
        "(default)|nothing held|REPLACE": (3088691733876276321, 1024, 512),
        "(default)|nothing held|ROOT": (3088691733876276321, 1024, 512),
        "ARPEGGIO LADDER|held 8 bars then released|ADD": (11785268549209022237, 4224, 2112),
        "ARPEGGIO LADDER|held 8 bars then released|REPLACE": (970111525610690877, 4224, 2112),
        "ARPEGGIO LADDER|held 8 bars then released|ROOT": (196587126652674349, 4224, 2112),
        "ARPEGGIO LADDER|held, IGNORE|ADD": (3941822156449626165, 4224, 2112),
        "ARPEGGIO LADDER|held, IGNORE|REPLACE": (9185001147652828037, 4224, 2112),
        "ARPEGGIO LADDER|held, IGNORE|ROOT": (196587126652674349, 4224, 2112),
        "ARPEGGIO LADDER|held, KEEP|ADD": (1456475393325068317, 4224, 2112),
        "ARPEGGIO LADDER|held, KEEP|REPLACE": (4792459938184270317, 4224, 2112),
        "ARPEGGIO LADDER|held, KEEP|ROOT": (196587126652674349, 4224, 2112),
        "ARPEGGIO LADDER|nothing held|ADD": (3667199860181741173, 4224, 2112),
        "ARPEGGIO LADDER|nothing held|REPLACE": (3667199860181741173, 4224, 2112),
        "ARPEGGIO LADDER|nothing held|ROOT": (3667199860181741173, 4224, 2112),
        "CANON|held 8 bars then released|ADD": (6686853661769679153, 4224, 2112),
        "CANON|held 8 bars then released|REPLACE": (13456884810464366161, 4224, 2112),
        "CANON|held 8 bars then released|ROOT": (4818488743330651861, 4224, 2112),
        "CANON|held, IGNORE|ADD": (5853651790367360477, 4224, 2112),
        "CANON|held, IGNORE|REPLACE": (16886617068199865805, 4224, 2112),
        "CANON|held, IGNORE|ROOT": (4818488743330651861, 4224, 2112),
        "CANON|held, KEEP|ADD": (2994992185585289941, 4224, 2112),
        "CANON|held, KEEP|REPLACE": (4750749998986929301, 4224, 2112),
        "CANON|held, KEEP|ROOT": (4818488743330651861, 4224, 2112),
        "CANON|nothing held|ADD": (6542105107048839165, 4224, 2112),
        "CANON|nothing held|REPLACE": (6542105107048839165, 4224, 2112),
        "CANON|nothing held|ROOT": (6542105107048839165, 4224, 2112),
        "CHORD ARP|held 8 bars then released|ADD": (8569676701886109841, 2192, 1096),
        "CHORD ARP|held 8 bars then released|REPLACE": (2765956286852829137, 2192, 1096),
        "CHORD ARP|held 8 bars then released|ROOT": (9005081896554361777, 2192, 1096),
        "CHORD ARP|held, IGNORE|ADD": (14359497988970845233, 2192, 1096),
        "CHORD ARP|held, IGNORE|REPLACE": (863515726410458233, 2192, 1096),
        "CHORD ARP|held, IGNORE|ROOT": (9005081896554361777, 2192, 1096),
        "CHORD ARP|held, KEEP|ADD": (14977422553995596025, 2192, 1096),
        "CHORD ARP|held, KEEP|REPLACE": (6143544996080954001, 2192, 1096),
        "CHORD ARP|held, KEEP|ROOT": (9005081896554361777, 2192, 1096),
        "CHORD ARP|nothing held|ADD": (14799962524448981713, 2192, 1096),
        "CHORD ARP|nothing held|REPLACE": (14799962524448981713, 2192, 1096),
        "CHORD ARP|nothing held|ROOT": (14799962524448981713, 2192, 1096),
        "COLOUR CHORDS|held 8 bars then released|ADD": (6881859938260457141, 2192, 1096),
        "COLOUR CHORDS|held 8 bars then released|REPLACE": (322413894748571117, 2192, 1096),
        "COLOUR CHORDS|held 8 bars then released|ROOT": (807229448351039889, 2192, 1096),
        "COLOUR CHORDS|held, IGNORE|ADD": (414499169032290921, 2192, 1096),
        "COLOUR CHORDS|held, IGNORE|REPLACE": (863515726410458233, 2192, 1096),
        "COLOUR CHORDS|held, IGNORE|ROOT": (807229448351039889, 2192, 1096),
        "COLOUR CHORDS|held, KEEP|ADD": (13016664432059064073, 2192, 1096),
        "COLOUR CHORDS|held, KEEP|REPLACE": (6143544996080954001, 2192, 1096),
        "COLOUR CHORDS|held, KEEP|ROOT": (807229448351039889, 2192, 1096),
        "COLOUR CHORDS|nothing held|ADD": (362489304178557745, 2192, 1096),
        "COLOUR CHORDS|nothing held|REPLACE": (362489304178557745, 2192, 1096),
        "COLOUR CHORDS|nothing held|ROOT": (362489304178557745, 2192, 1096),
        "FILL RUN|held 8 bars then released|ADD": (17910871635713839501, 784, 392),
        "FILL RUN|held 8 bars then released|REPLACE": (13153365111380217701, 784, 392),
        "FILL RUN|held 8 bars then released|ROOT": (16845419770824549117, 784, 392),
        "FILL RUN|held, IGNORE|ADD": (5766841075321548881, 784, 392),
        "FILL RUN|held, IGNORE|REPLACE": (5981603387621044145, 784, 392),
        "FILL RUN|held, IGNORE|ROOT": (16845419770824549117, 784, 392),
        "FILL RUN|held, KEEP|ADD": (7600803326047582861, 784, 392),
        "FILL RUN|held, KEEP|REPLACE": (11489655337373590049, 784, 392),
        "FILL RUN|held, KEEP|ROOT": (16845419770824549117, 784, 392),
        "FILL RUN|nothing held|ADD": (17454797241920985109, 784, 392),
        "FILL RUN|nothing held|REPLACE": (17454797241920985109, 784, 392),
        "FILL RUN|nothing held|ROOT": (17454797241920985109, 784, 392),
        "FIVE ON EIGHT|held 8 bars then released|ADD": (4988304194724767357, 1384, 692),
        "FIVE ON EIGHT|held 8 bars then released|REPLACE": (13423520230866053853, 1384, 692),
        "FIVE ON EIGHT|held 8 bars then released|ROOT": (7953598392964885285, 1384, 692),
        "FIVE ON EIGHT|held, IGNORE|ADD": (18410004983667041997, 1384, 692),
        "FIVE ON EIGHT|held, IGNORE|REPLACE": (2983453128688142413, 1384, 692),
        "FIVE ON EIGHT|held, IGNORE|ROOT": (7953598392964885285, 1384, 692),
        "FIVE ON EIGHT|held, KEEP|ADD": (6723191658501550741, 1384, 692),
        "FIVE ON EIGHT|held, KEEP|REPLACE": (8733540108084414477, 1384, 692),
        "FIVE ON EIGHT|held, KEEP|ROOT": (7953598392964885285, 1384, 692),
        "FIVE ON EIGHT|nothing held|ADD": (12266552422148341013, 1384, 692),
        "FIVE ON EIGHT|nothing held|REPLACE": (12266552422148341013, 1384, 692),
        "FIVE ON EIGHT|nothing held|ROOT": (12266552422148341013, 1384, 692),
        "HELD CHORDS|held 8 bars then released|ADD": (15516326005145999933, 224, 112),
        "HELD CHORDS|held 8 bars then released|REPLACE": (9304237655244457589, 224, 112),
        "HELD CHORDS|held 8 bars then released|ROOT": (2308408438246008425, 224, 112),
        "HELD CHORDS|held, IGNORE|ADD": (4363140916521556809, 224, 112),
        "HELD CHORDS|held, IGNORE|REPLACE": (4362939998097415177, 224, 112),
        "HELD CHORDS|held, IGNORE|ROOT": (2308408438246008425, 224, 112),
        "HELD CHORDS|held, KEEP|ADD": (6724066512012528609, 224, 112),
        "HELD CHORDS|held, KEEP|REPLACE": (5573189958816538265, 224, 112),
        "HELD CHORDS|held, KEEP|ROOT": (2308408438246008425, 224, 112),
        "HELD CHORDS|nothing held|ADD": (14005270360717959337, 224, 112),
        "HELD CHORDS|nothing held|REPLACE": (14005270360717959337, 224, 112),
        "HELD CHORDS|nothing held|ROOT": (14005270360717959337, 224, 112),
        "HELD RIFF|held 8 bars then released|ADD": (5911105194397989845, 272, 136),
        "HELD RIFF|held 8 bars then released|REPLACE": (17639139303913017677, 272, 136),
        "HELD RIFF|held 8 bars then released|ROOT": (2470922633512218837, 272, 136),
        "HELD RIFF|held, IGNORE|ADD": (10129183842808159241, 272, 136),
        "HELD RIFF|held, IGNORE|REPLACE": (1438399048427991593, 272, 136),
        "HELD RIFF|held, IGNORE|ROOT": (2470922633512218837, 272, 136),
        "HELD RIFF|held, KEEP|ADD": (3329269685785199701, 272, 136),
        "HELD RIFF|held, KEEP|REPLACE": (4670059260938762089, 272, 136),
        "HELD RIFF|held, KEEP|ROOT": (2470922633512218837, 272, 136),
        "HELD RIFF|nothing held|ADD": (3718996159391064789, 272, 136),
        "HELD RIFF|nothing held|REPLACE": (3718996159391064789, 272, 136),
        "HELD RIFF|nothing held|ROOT": (3718996159391064789, 272, 136),
        "KOTEKAN|held 8 bars then released|ADD": (7260285330865234181, 1152, 576),
        "KOTEKAN|held 8 bars then released|REPLACE": (12594448463142953485, 1152, 576),
        "KOTEKAN|held 8 bars then released|ROOT": (18329211212906948813, 1152, 576),
        "KOTEKAN|held, IGNORE|ADD": (11510995460759840661, 1152, 576),
        "KOTEKAN|held, IGNORE|REPLACE": (11510995460759840661, 1152, 576),
        "KOTEKAN|held, IGNORE|ROOT": (18329211212906948813, 1152, 576),
        "KOTEKAN|held, KEEP|ADD": (12554336867270298805, 1152, 576),
        "KOTEKAN|held, KEEP|REPLACE": (507160487156137245, 1152, 576),
        "KOTEKAN|held, KEEP|ROOT": (18329211212906948813, 1152, 576),
        "KOTEKAN|nothing held|ADD": (11677624884587161765, 1152, 576),
        "KOTEKAN|nothing held|REPLACE": (11677624884587161765, 1152, 576),
        "KOTEKAN|nothing held|ROOT": (11677624884587161765, 1152, 576),
        "MIRROR LINE|held 8 bars then released|ADD": (17978151830058096037, 1664, 832),
        "MIRROR LINE|held 8 bars then released|REPLACE": (17407677836523200713, 1664, 832),
        "MIRROR LINE|held 8 bars then released|ROOT": (14688643769873399733, 1664, 832),
        "MIRROR LINE|held, IGNORE|ADD": (9078454501275464517, 1664, 832),
        "MIRROR LINE|held, IGNORE|REPLACE": (3186357182070482813, 1664, 832),
        "MIRROR LINE|held, IGNORE|ROOT": (14688643769873399733, 1664, 832),
        "MIRROR LINE|held, KEEP|ADD": (1657946498435770701, 1664, 832),
        "MIRROR LINE|held, KEEP|REPLACE": (8515865058513584085, 1664, 832),
        "MIRROR LINE|held, KEEP|ROOT": (14688643769873399733, 1664, 832),
        "MIRROR LINE|nothing held|ADD": (16804258591809150717, 1664, 832),
        "MIRROR LINE|nothing held|REPLACE": (16804258591809150717, 1664, 832),
        "MIRROR LINE|nothing held|ROOT": (16804258591809150717, 1664, 832),
        "PARALLEL FIFTH|held 8 bars then released|ADD": (14749822614190519301, 1664, 832),
        "PARALLEL FIFTH|held 8 bars then released|REPLACE": (9044443239558363229, 1664, 832),
        "PARALLEL FIFTH|held 8 bars then released|ROOT": (8333864261814863597, 1664, 832),
        "PARALLEL FIFTH|held, IGNORE|ADD": (16112192265072885445, 1664, 832),
        "PARALLEL FIFTH|held, IGNORE|REPLACE": (4655375062116763605, 1664, 832),
        "PARALLEL FIFTH|held, IGNORE|ROOT": (8333864261814863597, 1664, 832),
        "PARALLEL FIFTH|held, KEEP|ADD": (4388078783516373445, 1664, 832),
        "PARALLEL FIFTH|held, KEEP|REPLACE": (8510710147847990709, 1664, 832),
        "PARALLEL FIFTH|held, KEEP|ROOT": (8333864261814863597, 1664, 832),
        "PARALLEL FIFTH|nothing held|ADD": (18131399656932173453, 1664, 832),
        "PARALLEL FIFTH|nothing held|REPLACE": (18131399656932173453, 1664, 832),
        "PARALLEL FIFTH|nothing held|ROOT": (18131399656932173453, 1664, 832),
        "PING-PONG LEAD|held 8 bars then released|ADD": (7126747730350192637, 1936, 968),
        "PING-PONG LEAD|held 8 bars then released|REPLACE": (13622000921780319593, 1936, 968),
        "PING-PONG LEAD|held 8 bars then released|ROOT": (5876373097366338785, 1936, 968),
        "PING-PONG LEAD|held, IGNORE|ADD": (8045503935641591913, 1936, 968),
        "PING-PONG LEAD|held, IGNORE|REPLACE": (4310938844297892425, 1936, 968),
        "PING-PONG LEAD|held, IGNORE|ROOT": (5876373097366338785, 1936, 968),
        "PING-PONG LEAD|held, KEEP|ADD": (14588992646264036505, 1936, 968),
        "PING-PONG LEAD|held, KEEP|REPLACE": (3761946787363262561, 1936, 968),
        "PING-PONG LEAD|held, KEEP|ROOT": (5876373097366338785, 1936, 968),
        "PING-PONG LEAD|nothing held|ADD": (17851936196610042665, 1936, 968),
        "PING-PONG LEAD|nothing held|REPLACE": (17851936196610042665, 1936, 968),
        "PING-PONG LEAD|nothing held|ROOT": (17851936196610042665, 1936, 968),
        "REHARMONIZE|held 8 bars then released|ADD": (2765956286852829137, 2192, 1096),
        "REHARMONIZE|held 8 bars then released|REPLACE": (2765956286852829137, 2192, 1096),
        "REHARMONIZE|held 8 bars then released|ROOT": (2765956286852829137, 2192, 1096),
        "REHARMONIZE|held, IGNORE|ADD": (863515726410458233, 2192, 1096),
        "REHARMONIZE|held, IGNORE|REPLACE": (863515726410458233, 2192, 1096),
        "REHARMONIZE|held, IGNORE|ROOT": (863515726410458233, 2192, 1096),
        "REHARMONIZE|held, KEEP|ADD": (6143544996080954001, 2192, 1096),
        "REHARMONIZE|held, KEEP|REPLACE": (6143544996080954001, 2192, 1096),
        "REHARMONIZE|held, KEEP|ROOT": (6143544996080954001, 2192, 1096),
        "REHARMONIZE|nothing held|ADD": (14799962524448981713, 2192, 1096),
        "REHARMONIZE|nothing held|REPLACE": (14799962524448981713, 2192, 1096),
        "REHARMONIZE|nothing held|ROOT": (14799962524448981713, 2192, 1096),
        "RESTART SHIFT|held 8 bars then released|ADD": (18094258695412759457, 784, 392),
        "RESTART SHIFT|held 8 bars then released|REPLACE": (11674606101898343393, 784, 392),
        "RESTART SHIFT|held 8 bars then released|ROOT": (7965254427430467357, 784, 392),
        "RESTART SHIFT|held, IGNORE|ADD": (14572621671452856113, 784, 392),
        "RESTART SHIFT|held, IGNORE|REPLACE": (15823904613063767201, 784, 392),
        "RESTART SHIFT|held, IGNORE|ROOT": (7965254427430467357, 784, 392),
        "RESTART SHIFT|held, KEEP|ADD": (749512692874661889, 784, 392),
        "RESTART SHIFT|held, KEEP|REPLACE": (8622043216525681745, 784, 392),
        "RESTART SHIFT|held, KEEP|ROOT": (7965254427430467357, 784, 392),
        "RESTART SHIFT|nothing held|ADD": (15879580637635629357, 784, 392),
        "RESTART SHIFT|nothing held|REPLACE": (15879580637635629357, 784, 392),
        "RESTART SHIFT|nothing held|ROOT": (15879580637635629357, 784, 392),
        "REVERSE READ|held 8 bars then released|ADD": (15702610754904609833, 1408, 704),
        "REVERSE READ|held 8 bars then released|REPLACE": (1508111425330973233, 1408, 704),
        "REVERSE READ|held 8 bars then released|ROOT": (6223262387384607577, 1408, 704),
        "REVERSE READ|held, IGNORE|ADD": (15475967878528930413, 1408, 704),
        "REVERSE READ|held, IGNORE|REPLACE": (1650674348904842013, 1408, 704),
        "REVERSE READ|held, IGNORE|ROOT": (6223262387384607577, 1408, 704),
        "REVERSE READ|held, KEEP|ADD": (17876756778590520933, 1408, 704),
        "REVERSE READ|held, KEEP|REPLACE": (969846507600122237, 1408, 704),
        "REVERSE READ|held, KEEP|ROOT": (6223262387384607577, 1408, 704),
        "REVERSE READ|nothing held|ADD": (14814448089234233, 1408, 704),
        "REVERSE READ|nothing held|REPLACE": (14814448089234233, 1408, 704),
        "REVERSE READ|nothing held|ROOT": (14814448089234233, 1408, 704),
        "RIFF LEAD|held 8 bars then released|ADD": (5675521815583732173, 912, 456),
        "RIFF LEAD|held 8 bars then released|REPLACE": (10336878574834945761, 912, 456),
        "RIFF LEAD|held 8 bars then released|ROOT": (15506391085099526753, 912, 456),
        "RIFF LEAD|held, IGNORE|ADD": (1569027654502571761, 912, 456),
        "RIFF LEAD|held, IGNORE|REPLACE": (14594824882562193465, 912, 456),
        "RIFF LEAD|held, IGNORE|ROOT": (15506391085099526753, 912, 456),
        "RIFF LEAD|held, KEEP|ADD": (14574777511664772337, 912, 456),
        "RIFF LEAD|held, KEEP|REPLACE": (6572636253697120985, 912, 456),
        "RIFF LEAD|held, KEEP|ROOT": (15506391085099526753, 912, 456),
        "RIFF LEAD|nothing held|ADD": (14340731506396270889, 912, 456),
        "RIFF LEAD|nothing held|REPLACE": (14340731506396270889, 912, 456),
        "RIFF LEAD|nothing held|ROOT": (14340731506396270889, 912, 456),
        "ROOT FOLLOW|held 8 bars then released|ADD": (7855015658380686217, 912, 456),
        "ROOT FOLLOW|held 8 bars then released|REPLACE": (7855015658380686217, 912, 456),
        "ROOT FOLLOW|held 8 bars then released|ROOT": (7855015658380686217, 912, 456),
        "ROOT FOLLOW|held, IGNORE|ADD": (7855015658380686217, 912, 456),
        "ROOT FOLLOW|held, IGNORE|REPLACE": (7855015658380686217, 912, 456),
        "ROOT FOLLOW|held, IGNORE|ROOT": (7855015658380686217, 912, 456),
        "ROOT FOLLOW|held, KEEP|ADD": (7855015658380686217, 912, 456),
        "ROOT FOLLOW|held, KEEP|REPLACE": (7855015658380686217, 912, 456),
        "ROOT FOLLOW|held, KEEP|ROOT": (7855015658380686217, 912, 456),
        "ROOT FOLLOW|nothing held|ADD": (4213865869534528225, 912, 456),
        "ROOT FOLLOW|nothing held|REPLACE": (4213865869534528225, 912, 456),
        "ROOT FOLLOW|nothing held|ROOT": (4213865869534528225, 912, 456),
        "SCALE WALK|held 8 bars then released|ADD": (1473503753343964045, 1280, 640),
        "SCALE WALK|held 8 bars then released|REPLACE": (9709356356491056753, 1280, 640),
        "SCALE WALK|held 8 bars then released|ROOT": (14175605780850842149, 1280, 640),
        "SCALE WALK|held, IGNORE|ADD": (14960842875588575261, 1280, 640),
        "SCALE WALK|held, IGNORE|REPLACE": (1949929254304634589, 1280, 640),
        "SCALE WALK|held, IGNORE|ROOT": (14175605780850842149, 1280, 640),
        "SCALE WALK|held, KEEP|ADD": (17331130688756751261, 1280, 640),
        "SCALE WALK|held, KEEP|REPLACE": (15347594671931884189, 1280, 640),
        "SCALE WALK|held, KEEP|ROOT": (14175605780850842149, 1280, 640),
        "SCALE WALK|nothing held|ADD": (13003696579247174421, 1280, 640),
        "SCALE WALK|nothing held|REPLACE": (13003696579247174421, 1280, 640),
        "SCALE WALK|nothing held|ROOT": (13003696579247174421, 1280, 640),
        "STACK ARP|held 8 bars then released|ADD": (8151354610658015941, 2192, 1096),
        "STACK ARP|held 8 bars then released|REPLACE": (14929529159041302689, 2192, 1096),
        "STACK ARP|held 8 bars then released|ROOT": (8661819047514738017, 2192, 1096),
        "STACK ARP|held, IGNORE|ADD": (13313116605277555425, 2192, 1096),
        "STACK ARP|held, IGNORE|REPLACE": (18203609932509320297, 2192, 1096),
        "STACK ARP|held, IGNORE|ROOT": (8661819047514738017, 2192, 1096),
        "STACK ARP|held, KEEP|ADD": (4796412544670910769, 2192, 1096),
        "STACK ARP|held, KEEP|REPLACE": (12660172207823203801, 2192, 1096),
        "STACK ARP|held, KEEP|ROOT": (8661819047514738017, 2192, 1096),
        "STACK ARP|nothing held|ADD": (15647105964934497505, 2192, 1096),
        "STACK ARP|nothing held|REPLACE": (15647105964934497505, 2192, 1096),
        "STACK ARP|nothing held|ROOT": (15647105964934497505, 2192, 1096),
        "STRIDE HARMONY|held 8 bars then released|ADD": (2952716127466205429, 1664, 832),
        "STRIDE HARMONY|held 8 bars then released|REPLACE": (5528959804719142981, 1664, 832),
        "STRIDE HARMONY|held 8 bars then released|ROOT": (4909506432151090085, 1664, 832),
        "STRIDE HARMONY|held, IGNORE|ADD": (4449241194887251957, 1664, 832),
        "STRIDE HARMONY|held, IGNORE|REPLACE": (569162349164902925, 1664, 832),
        "STRIDE HARMONY|held, IGNORE|ROOT": (4909506432151090085, 1664, 832),
        "STRIDE HARMONY|held, KEEP|ADD": (185442804631487337, 1664, 832),
        "STRIDE HARMONY|held, KEEP|REPLACE": (1679183936457926813, 1664, 832),
        "STRIDE HARMONY|held, KEEP|ROOT": (4909506432151090085, 1664, 832),
        "STRIDE HARMONY|nothing held|ADD": (7481092235451454629, 1664, 832),
        "STRIDE HARMONY|nothing held|REPLACE": (7481092235451454629, 1664, 832),
        "STRIDE HARMONY|nothing held|ROOT": (7481092235451454629, 1664, 832),
        "STUTTER WALK|held 8 bars then released|ADD": (18312329635945512761, 2960, 1480),
        "STUTTER WALK|held 8 bars then released|REPLACE": (14976961420185224893, 2960, 1480),
        "STUTTER WALK|held 8 bars then released|ROOT": (1417537047419171093, 2960, 1480),
        "STUTTER WALK|held, IGNORE|ADD": (9439185385487032397, 2960, 1480),
        "STUTTER WALK|held, IGNORE|REPLACE": (18348979523648558061, 2960, 1480),
        "STUTTER WALK|held, IGNORE|ROOT": (1417537047419171093, 2960, 1480),
        "STUTTER WALK|held, KEEP|ADD": (8456567949600151181, 2960, 1480),
        "STUTTER WALK|held, KEEP|REPLACE": (15681088184628939621, 2960, 1480),
        "STUTTER WALK|held, KEEP|ROOT": (1417537047419171093, 2960, 1480),
        "STUTTER WALK|nothing held|ADD": (2051402597079705741, 2960, 1480),
        "STUTTER WALK|nothing held|REPLACE": (2051402597079705741, 2960, 1480),
        "STUTTER WALK|nothing held|ROOT": (2051402597079705741, 2960, 1480),
        "TILT PHRASE|held 8 bars then released|ADD": (1891392896141676685, 784, 392),
        "TILT PHRASE|held 8 bars then released|REPLACE": (16248788132144350533, 784, 392),
        "TILT PHRASE|held 8 bars then released|ROOT": (11634387123181653693, 784, 392),
        "TILT PHRASE|held, IGNORE|ADD": (2344131327195032805, 784, 392),
        "TILT PHRASE|held, IGNORE|REPLACE": (2119126595681250341, 784, 392),
        "TILT PHRASE|held, IGNORE|ROOT": (11634387123181653693, 784, 392),
        "TILT PHRASE|held, KEEP|ADD": (16303455148216414629, 784, 392),
        "TILT PHRASE|held, KEEP|REPLACE": (7967056199606632301, 784, 392),
        "TILT PHRASE|held, KEEP|ROOT": (11634387123181653693, 784, 392),
        "TILT PHRASE|nothing held|ADD": (14081351541262851421, 784, 392),
        "TILT PHRASE|nothing held|REPLACE": (14081351541262851421, 784, 392),
        "TILT PHRASE|nothing held|ROOT": (14081351541262851421, 784, 392),
    ]

    func testEveryDocumentRendersTheSameStreamUnderEveryModeAndHold() {
        XCTAssertEqual(EuclideousPresets.all.count, 22)
        for (name, make) in documents {
            for hold in Hold.allCases {
                for mode in MidiMode.allCases {
                    let key = "\(name)|\(hold.rawValue)|\(mode.rawValue)"
                    // the document as the app now opens it (lanes carry their own sources, the four switches read true)…
                    var migrated = make(); migrated.migrateLegacyRoutingIfNeeded(); migrated.normalizeSourcesAtLoad()
                    let got = render(migrated, mode: mode, hold: hold)
                    guard let want = golden[key] else { XCTFail("CAPTURE \"\(key)\": (\(got.hash), \(got.events), \(got.ons)),"); continue }
                    XCTAssertEqual(got.events, want.1, "\(key): message count")
                    XCTAssertEqual(got.ons, want.2, "\(key): note-on count")
                    XCTAssertEqual(got.hash, want.0, "\(key): the message stream must be bit-identical (FREEZE 0, SUSTAIN off, SLIP 0)")
                    // …and the un-migrated one (a path that never normalised: the engine still ANDs the switches), on the held KEEP scenario
                    if hold == .keep {
                        let raw = render(make(), mode: mode, hold: hold)
                        XCTAssertEqual(raw.hash, want.0, "\(key): the un-migrated document plays the same")
                    }
                }
            }
        }
    }
}
