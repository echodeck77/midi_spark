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
        "(default)|137": (9771049027159314997, 1024, 512),
        "(default)|4096": (5648158088018603419, 1024, 512),
        "(default)|480": (5810583246765842761, 1024, 512),
        "ARPEGGIO LADDER|137": (639556068906465621, 4096, 2048),
        "ARPEGGIO LADDER|4096": (11150856385095901081, 4096, 2048),
        "ARPEGGIO LADDER|480": (15028064168758528653, 4096, 2048),
        "BACKWARDS GLANCE|137": (13528171041010172761, 1280, 640),
        "BACKWARDS GLANCE|4096": (17354752442658812381, 1280, 640),
        "BACKWARDS GLANCE|480": (8021304670992595901, 1280, 640),
        "CALL AND HOLD|137": (9870892494650926733, 832, 416),
        "CALL AND HOLD|4096": (2472279771766923291, 832, 416),
        "CALL AND HOLD|480": (2252889707138412593, 832, 416),
        "DRUNKEN WALK|137": (9895128083589906081, 1152, 576),
        "DRUNKEN WALK|4096": (3245523013462744401, 1152, 576),
        "DRUNKEN WALK|480": (6391371830639514825, 1152, 576),
        "EARLY BLOOM|137": (18110205626271483257, 528, 264),
        "EARLY BLOOM|4096": (8615989700482392329, 528, 264),
        "EARLY BLOOM|480": (14706456658884921181, 528, 264),
        "FIFTH ABOVE|137": (4623494998458432949, 1280, 640),
        "FIFTH ABOVE|4096": (1840817528121452229, 1280, 640),
        "FIFTH ABOVE|480": (5731262618919878237, 1280, 640),
        "FIVE AGAINST EIGHT|137": (11073777361779199645, 1256, 628),
        "FIVE AGAINST EIGHT|4096": (5843368118986671817, 1256, 628),
        "FIVE AGAINST EIGHT|480": (3298886382283204093, 1256, 628),
        "GAPPED GROOVE|137": (6770596324028948505, 1024, 512),
        "GAPPED GROOVE|4096": (6299600146467354687, 1024, 512),
        "GAPPED GROOVE|480": (10068800245553378065, 1024, 512),
        "HELD BREATH|137": (958338531557389289, 80, 40),
        "HELD BREATH|4096": (2523738563444112093, 80, 40),
        "HELD BREATH|480": (17853329910382017621, 80, 40),
        "KOTEKAN|137": (17093189171154422829, 2048, 1024),
        "KOTEKAN|4096": (12654581290795768917, 2048, 1024),
        "KOTEKAN|480": (8393456998199786213, 2048, 1024),
        "LONG TAIL|137": (9887125031566881457, 304, 152),
        "LONG TAIL|4096": (12346523413822706337, 304, 152),
        "LONG TAIL|480": (7091941721064415841, 304, 152),
        "MIRROR WALK|137": (16678802538838303997, 1536, 768),
        "MIRROR WALK|4096": (8285411804084503929, 1536, 768),
        "MIRROR WALK|480": (17587072312325070501, 1536, 768),
        "MIRRORED PITCH|137": (17632403971465351237, 896, 448),
        "MIRRORED PITCH|4096": (1377438825118036827, 896, 448),
        "MIRRORED PITCH|480": (7917750127668525037, 896, 448),
        "OCTAVE COLUMN|137": (18240240920005437317, 2560, 1280),
        "OCTAVE COLUMN|4096": (8906193832116539141, 2560, 1280),
        "OCTAVE COLUMN|480": (12347037978995313477, 2560, 1280),
        "PENDULUM|137": (17312059486703607369, 1024, 512),
        "PENDULUM|4096": (9836850937527104661, 1024, 512),
        "PENDULUM|480": (5674093713025947149, 1024, 512),
        "PING-PONG LEAD|137": (2577914434306549953, 1568, 784),
        "PING-PONG LEAD|4096": (2725759344816176019, 1568, 784),
        "PING-PONG LEAD|480": (6487574056831416737, 1568, 784),
        "RANDOM GARDEN|137": (17244826290908189177, 1792, 896),
        "RANDOM GARDEN|4096": (3972908956338243501, 1792, 896),
        "RANDOM GARDEN|480": (11094577514255666629, 1792, 896),
        "SCALE WALK|137": (16757816058807925525, 1280, 640),
        "SCALE WALK|4096": (11458897320647714477, 1280, 640),
        "SCALE WALK|480": (18257920096646117325, 1280, 640),
        "STRIDE WALK|137": (7243936524615466989, 1152, 576),
        "STRIDE WALK|4096": (5770628229236947, 1152, 576),
        "STRIDE WALK|480": (4941413961264373045, 1152, 576),
        "STUTTER FILL|137": (17456136801621110293, 3600, 1800),
        "STUTTER FILL|4096": (16280860711395786713, 3600, 1800),
        "STUTTER FILL|480": (17684813643519563649, 3600, 1800),
    ]

    func testEveryDocumentRendersTheSameMessageStreamAtEveryWindowSize() {
        XCTAssertEqual(EuclideousPresets.all.count, 20)
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
