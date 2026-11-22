//  HocketGoldenTests.swift — HOCKET ferry (2026-10-27) §12 test 1: golden renders captured BEFORE any engine change.
//  With no hocket rule lit, every output (ALL included) must stay byte-identical. RE-BASELINED 2026-10-28 (CARD BACKS: five outputs — each lane's two parts leave on its own output — instead of nine ports; the pins before were the nine-output stream). `RouterTests.testEveryFactoryPreset…32Bar` already pins the 20 presets' note stream over 32 bars at one window size
//  through the older cell-based scene; this suite renders the default document and every factory preset through the FOURFOLD chain (`FourfoldCompose`, the path the AU publishes) at three host window sizes
//  (480 = the harness's, 137 = an odd size that splits every tick, 4096 = a big one), hashing every message in emission order (sample, cable, status+channel, note, velocity).
//  CAPTURED on origin/main 9f1b08d (nine ports + adversarial review), immediately before the HOCKET engine work; re-captured on the CARD BACKS engine. A changed hash here with no rule lit is a bug, not a re-baseline.

import XCTest

private final class GoldenEmitter: MIDIEmitter {
    var h: UInt64 = 0xcbf29ce484222325
    var events = 0, ons = 0
    private func mix(_ v: UInt64) { h = (h ^ v) &* 0x100000001b3 }
    func emit(sampleTime: Int64, cable: UInt8, _ b0: UInt8, _ b1: UInt8, _ b2: UInt8) {
        mix(UInt64(bitPattern: sampleTime)); mix(UInt64(cable)); mix(UInt64(b0)); mix(UInt64(b1)); mix(UInt64(b2))
        events += 1
        if b0 & 0xF0 == 0x90 && b2 > 0 { ons += 1 }
    }
}

final class HocketGoldenTests: XCTestCase {

    /// The document as the app publishes it: the lines resolved, composed into the Euclideous cell's chain, built into a snapshot.
    private func box(for s0: PluginState) -> SnapshotBox {
        var st = s0
        st.euclideousSameNoteGuard = false   // these goldens pin the PRE-same-note-guard stream (2026-10-31); the guard (default ON) moves same-pitch offs earlier and has its own SameNoteGuardTests — exclude its orthogonal effect here
        var plan = st.sourcePlanResolved; plan.midiOctaves = .keep; st.euclideousSourcePlan = plan   // …and the pre-OCTAVES stream (2026-11-01): the held chord stays where it is played. Default IGNORE folds it (the harness golden lists that change); KEEP must be what these pins captured
        st.machines.append(Machine(machineID: FourfoldCompose.machineID, type: .euclid))
        let input = FourfoldCompose.Input(lines: st.euclideousLinesResolved, riff: st.euclideousRiffResolved, riffs: st.riffsResolved,
                                          activeRiff: st.activeRiffResolved, soloMask: st.euclideousSoloMaskResolved,
                                          locks: st.euclideousLocksResolved, lockRevs: 0)
        st.scenes = [FourfoldCompose.scene(input)]
        return SnapshotBuilder.build(from: st)
    }

    /// 32 bars at 120 BPM under a held C-major triad, then the stop edge, at `frames` frames a window.
    private func render(_ s: PluginState, frames: UInt32) -> (hash: UInt64, events: Int, ons: Int) {
        let b = box(for: s)
        let pool = NotePool()
        for n in [60, 64, 67] { pool.noteOn(UInt8(n), velocity: 100, channel: 0) }
        let router = Router(); var diag = KernelDiag(); let e = GoldenEmitter()
        let sr = 48_000.0, tempo = 120.0
        let totalFrames = Int(32 * 4 * 60.0 / tempo * sr)
        var done = 0, beat = 0.0, ts = 0.0
        while done < totalFrames {
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

    /// Document × window size → (hash, events, note-ons).
    private let golden: [String: (UInt64, Int, Int)] = [
        // DEFAULT DOC RE-BASELINED (Paul 2026-11-18): fresh default is now MIDI IN + CHORDS grid 1 (was KEY) and
        // an ascending-run default riff (was arch R1), so the "(default)" no-rule stream moves. The 20 presets pin
        // their own source (.key) + arch riff and stay bit-identical. Re-captured from this test's CAPTURE output:
        // RE-PINNED 2026-11-22 for the 22-preset roster (preset redesign b22ef71/c2788bf/943a7e3), engine unchanged:
        // rebuilt ARPEGGIO LADDER / KOTEKAN / PING-PONG LEAD / SCALE WALK re-captured, the new presets added, retired names dropped.
        "(default)|137": (15887760000328875437, 1024, 512),
        "(default)|4096": (11477244096088047971, 1024, 512),
        "(default)|480": (9764849573068998081, 1024, 512),
        "ARPEGGIO LADDER|137": (17657388443478623813, 4224, 2112),
        "ARPEGGIO LADDER|4096": (4738276623961440901, 4224, 2112),
        "ARPEGGIO LADDER|480": (1456475393325068317, 4224, 2112),
        "CANON|137": (17767569999598222909, 4224, 2112),
        "CANON|4096": (13227290062597958437, 4224, 2112),
        "CANON|480": (2994992185585289941, 4224, 2112),
        "CHORD ARP|137": (14645162686368002649, 2192, 1096),
        "CHORD ARP|4096": (16789986518445999683, 2192, 1096),
        "CHORD ARP|480": (14977422553995596025, 2192, 1096),
        "COLOUR CHORDS|137": (8975215637397045857, 2192, 1096),
        "COLOUR CHORDS|4096": (3024954626435689707, 2192, 1096),
        "COLOUR CHORDS|480": (13016664432059064073, 2192, 1096),
        "FILL RUN|137": (11470785484563188869, 784, 392),
        "FILL RUN|4096": (5038986187153994847, 784, 392),
        "FILL RUN|480": (7600803326047582861, 784, 392),
        "FIVE ON EIGHT|137": (8990147967711778245, 1384, 692),
        "FIVE ON EIGHT|4096": (4235517662917245381, 1384, 692),
        "FIVE ON EIGHT|480": (6723191658501550741, 1384, 692),
        "HELD CHORDS|137": (17540492972905499953, 224, 112),
        "HELD CHORDS|4096": (11520337330386763913, 224, 112),
        "HELD CHORDS|480": (6724066512012528609, 224, 112),
        "HELD RIFF|137": (4237966546097847193, 272, 136),
        "HELD RIFF|4096": (7337844509498361369, 272, 136),
        "HELD RIFF|480": (3329269685785199701, 272, 136),
        "KOTEKAN|137": (14216389821207625561, 1152, 576),
        "KOTEKAN|4096": (4512461606339167777, 1152, 576),
        "KOTEKAN|480": (12554336867270298805, 1152, 576),
        "MIRROR LINE|137": (11109418630365295973, 1664, 832),
        "MIRROR LINE|4096": (11554762975206570173, 1664, 832),
        "MIRROR LINE|480": (1657946498435770701, 1664, 832),
        "PARALLEL FIFTH|137": (3727211401208180117, 1664, 832),
        "PARALLEL FIFTH|4096": (14671030119691444893, 1664, 832),
        "PARALLEL FIFTH|480": (4388078783516373445, 1664, 832),
        "PING-PONG LEAD|137": (9668295227789025753, 1936, 968),
        "PING-PONG LEAD|4096": (12486385440630688243, 1936, 968),
        "PING-PONG LEAD|480": (14588992646264036505, 1936, 968),
        "REHARMONIZE|137": (5458233563590941097, 2192, 1096),
        "REHARMONIZE|4096": (9870232041326711979, 2192, 1096),
        "REHARMONIZE|480": (6143544996080954001, 2192, 1096),
        "RESTART SHIFT|137": (5520708910866625857, 784, 392),
        "RESTART SHIFT|4096": (18365853401266330293, 784, 392),
        "RESTART SHIFT|480": (749512692874661889, 784, 392),
        "REVERSE READ|137": (12285295760118995309, 1408, 704),
        "REVERSE READ|4096": (2281948389515106605, 1408, 704),
        "REVERSE READ|480": (17876756778590520933, 1408, 704),
        "RIFF LEAD|137": (14174364193247794181, 912, 456),
        "RIFF LEAD|4096": (4791739875329415779, 912, 456),
        "RIFF LEAD|480": (14574777511664772337, 912, 456),
        "ROOT FOLLOW|137": (3315405732584808357, 912, 456),
        "ROOT FOLLOW|4096": (11369309106310040827, 912, 456),
        "ROOT FOLLOW|480": (7855015658380686217, 912, 456),
        "SCALE WALK|137": (11495201425285962525, 1280, 640),
        "SCALE WALK|4096": (7211234921938487773, 1280, 640),
        "SCALE WALK|480": (17331130688756751261, 1280, 640),
        "STACK ARP|137": (3448010786320125057, 2192, 1096),
        "STACK ARP|4096": (2058931202106160299, 2192, 1096),
        "STACK ARP|480": (4796412544670910769, 2192, 1096),
        "STRIDE HARMONY|137": (18389480029155148489, 1664, 832),
        "STRIDE HARMONY|4096": (11965729402655703037, 1664, 832),
        "STRIDE HARMONY|480": (185442804631487337, 1664, 832),
        "STUTTER WALK|137": (8923241907694461321, 2960, 1480),
        "STUTTER WALK|4096": (3897162671679741107, 2960, 1480),
        "STUTTER WALK|480": (8456567949600151181, 2960, 1480),
        "TILT PHRASE|137": (12911812411610280593, 784, 392),
        "TILT PHRASE|4096": (17359131820740628987, 784, 392),
        "TILT PHRASE|480": (16303455148216414629, 784, 392),
    ]

    func testEveryDocumentRendersTheSameMessageStreamAtEveryWindowSize() {
        XCTAssertEqual(EuclideousPresets.all.count, 22)
        for (name, make) in documents {
            for frames in [UInt32(480), 137, 4096] {
                let key = "\(name)|\(frames)"
                let got = render(make(), frames: frames)
                guard let want = golden[key] else { XCTFail("CAPTURE \"\(key)\": (\(got.hash), \(got.events), \(got.ons)),"); continue }
                XCTAssertEqual(got.events, want.1, "\(key): message count")
                XCTAssertEqual(got.ons, want.2, "\(key): note-on count")
                XCTAssertEqual(got.hash, want.0, "\(key): the message stream (sample, cable, status+channel, note, velocity) must be bit-identical with no hocket rule lit")
            }
        }
    }
}
