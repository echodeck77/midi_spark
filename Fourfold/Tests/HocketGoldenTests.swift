//  HocketGoldenTests.swift — HOCKET ferry (2026-10-27) §12 test 1: golden renders captured BEFORE any engine change.
//  With no hocket rule lit, every output (ALL included) must stay byte-identical to the nine-output build. `RouterTests.testEveryFactoryPreset…32Bar` already pins the 20 presets' note stream over 32 bars at one window size
//  through the older cell-based scene; this suite renders the default document and every factory preset through the FOURFOLD chain (`FourfoldCompose`, the path the AU publishes) at three host window sizes
//  (480 = the harness's, 137 = an odd size that splits every tick, 4096 = a big one), hashing every message in emission order (sample, cable, status+channel, note, velocity).
//  CAPTURED on origin/main 9f1b08d (nine ports + adversarial review), immediately before the HOCKET engine work. A changed hash here with no rule lit is a bug, not a re-baseline.

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
        "(default)|137": (8702447007768151285, 1024, 512),
        "(default)|4096": (11971050443652770891, 1024, 512),
        "(default)|480": (12822894880197170969, 1024, 512),
        "ARPEGGIO LADDER|137": (11758451056136123749, 4096, 2048),
        "ARPEGGIO LADDER|4096": (12979039643332042341, 4096, 2048),
        "ARPEGGIO LADDER|480": (8443923179276891829, 4096, 2048),
        "BACKWARDS GLANCE|137": (3355204274169050581, 1280, 640),
        "BACKWARDS GLANCE|4096": (3598075339797116429, 1280, 640),
        "BACKWARDS GLANCE|480": (4959009255195445737, 1280, 640),
        "CALL AND HOLD|137": (16420146169718856689, 832, 416),
        "CALL AND HOLD|4096": (2303380991387249335, 832, 416),
        "CALL AND HOLD|480": (5900694110415499517, 832, 416),
        "DRUNKEN WALK|137": (18187133699378698281, 1152, 576),
        "DRUNKEN WALK|4096": (1345133826788475417, 1152, 576),
        "DRUNKEN WALK|480": (7216651925512303809, 1152, 576),
        "EARLY BLOOM|137": (14174561674979100249, 528, 264),
        "EARLY BLOOM|4096": (2886004440444112169, 528, 264),
        "EARLY BLOOM|480": (7534506432746697649, 528, 264),
        "FIFTH ABOVE|137": (15829703212009022725, 1280, 640),
        "FIFTH ABOVE|4096": (8721279716450900949, 1280, 640),
        "FIFTH ABOVE|480": (1071249428654766701, 1280, 640),
        "FIVE AGAINST EIGHT|137": (9214951473819907161, 1256, 628),
        "FIVE AGAINST EIGHT|4096": (13874401514866422249, 1256, 628),
        "FIVE AGAINST EIGHT|480": (5192951657606942737, 1256, 628),
        "GAPPED GROOVE|137": (13633950113072317733, 1024, 512),
        "GAPPED GROOVE|4096": (9072552867480626875, 1024, 512),
        "GAPPED GROOVE|480": (15616499426908642253, 1024, 512),
        "HELD BREATH|137": (7014078461236697809, 80, 40),
        "HELD BREATH|4096": (9583067495939002057, 80, 40),
        "HELD BREATH|480": (11276356089657271721, 80, 40),
        "KOTEKAN|137": (11643162465113528089, 2048, 1024),
        "KOTEKAN|4096": (8574564788428032073, 2048, 1024),
        "KOTEKAN|480": (14847332556576897741, 2048, 1024),
        "LONG TAIL|137": (4056109885892952197, 304, 152),
        "LONG TAIL|4096": (10779488171617219237, 304, 152),
        "LONG TAIL|480": (12726653543108599557, 304, 152),
        "MIRROR WALK|137": (12509872393807644749, 1536, 768),
        "MIRROR WALK|4096": (11785849296355823061, 1536, 768),
        "MIRROR WALK|480": (1434114968251555669, 1536, 768),
        "MIRRORED PITCH|137": (7270615169982032797, 896, 448),
        "MIRRORED PITCH|4096": (7004125086724935631, 896, 448),
        "MIRRORED PITCH|480": (10675103124169759489, 896, 448),
        "OCTAVE COLUMN|137": (15966472154406688917, 2560, 1280),
        "OCTAVE COLUMN|4096": (15189869471319693541, 2560, 1280),
        "OCTAVE COLUMN|480": (15044251898649586613, 2560, 1280),
        "PENDULUM|137": (15193643397553757569, 1024, 512),
        "PENDULUM|4096": (13369202848078611145, 1024, 512),
        "PENDULUM|480": (13978142480813298105, 1024, 512),
        "PING-PONG LEAD|137": (6159724057780786381, 1568, 784),
        "PING-PONG LEAD|4096": (1335072476785370115, 1568, 784),
        "PING-PONG LEAD|480": (15706094841188464117, 1568, 784),
        "RANDOM GARDEN|137": (16496082468614327713, 1792, 896),
        "RANDOM GARDEN|4096": (5893806084197031161, 1792, 896),
        "RANDOM GARDEN|480": (5086941178428206189, 1792, 896),
        "SCALE WALK|137": (17222168686445172425, 1280, 640),
        "SCALE WALK|4096": (16541380089263351241, 1280, 640),
        "SCALE WALK|480": (781286112088414181, 1280, 640),
        "STRIDE WALK|137": (15879189672078173137, 1152, 576),
        "STRIDE WALK|4096": (18302828974534149531, 1152, 576),
        "STRIDE WALK|480": (2050108392723480497, 1152, 576),
        "STUTTER FILL|137": (7983994194342192273, 3600, 1800),
        "STUTTER FILL|4096": (1005682618865978889, 3600, 1800),
        "STUTTER FILL|480": (12421101962336768749, 3600, 1800),
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
