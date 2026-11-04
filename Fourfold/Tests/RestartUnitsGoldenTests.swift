//  RestartUnitsGoldenTests.swift — RESTART UNITS ferry (2026-11-04), test 1: the riff ranks the REAL engine plays hit by hit under today's restart chains, captured BEFORE the schedule replaced the closed forms.
//  After the ferry every string below must still match exactly (the unit-less settings it covers — BAR rhythm chains, own-PASS melody chains — are the ones "that existed before"). One lane, a held 8-note pool, rank r = pool[r − 1], so a note-on's pitch names the
//  riff column it read; a string is "beat-in-sixteenths:column" per note-on of the lane's own output, in time order.

import XCTest

private final class GoldenEmitter: MIDIEmitter {
    struct Ev: Equatable { let sample: Int64; let cable: UInt8; let status: UInt8; let note: UInt8 }
    private(set) var events: [Ev] = []
    func emit(sampleTime: Int64, cable: UInt8, _ b0: UInt8, _ b1: UInt8, _ b2: UInt8) { events.append(Ev(sample: sampleTime, cable: cable, status: b0 & 0xF0, note: b1)) }
}

final class RestartUnitsGoldenTests: XCTestCase {
    private let pool: [UInt8] = [48, 50, 52, 53, 55, 57, 59, 60]
    private let beat: Double = 24_000   // samples in a beat at 120 BPM / 48 kHz

    /// One lane: `hits` of `steps` at `rate`, walking the 8-column riff, with the given chains (links in bars for RHYTHM, passes for MELODY; [] = FREE).
    private func lane(hits: Int, steps: Int, rate: ArpRate = .r1_8, dir: EuclidDir = .fwd, rhythm: [UInt8] = [], melody: [UInt8] = [], advanceStep: Bool = false,
                      riffDir: RiffDir = .forward, every: Int = 1, length: Int? = nil, stride: Int = 1) -> EuclidLine {
        var l = EuclidLine(target: 0, pulses: hits, steps: steps)
        l.gate = 0.5; l.velocityAbsolute = 90; l.rate = rate; l.useRiff = true; l.riffOn = true; l.sourceMode = .midi; l.notesOn = true; l.litNotes = 0
        l.direction = dir; l.riffAdvanceStep = advanceStep; l.riffDir = riffDir; l.riffAdvanceEvery = every; l.riffLength = length; l.riffStride = stride
        euclideousPinRestartChains(&l, .from(rhythm), .from(melody))
        return l
    }
    private func ranks(_ l: EuclidLine, beats: Double, tempo: Double = 120, frames: UInt32 = 2048) -> String {
        var c = Machine(machineID: "gold", type: .euclid)
        c.paramsA.euclideousRiff = EuclideousRiff(steps: 8, ranks: [1, 2, 3, 4, 5, 6, 7, 8])
        c.paramsA.euclidLines = [l]
        var sc = SceneState.empty(); sc.stepRate = .r1_8
        sc.cells[0][Snap.euclideousRow] = Cell(machineID: "gold", buses: [.a, .b, .c, .d])
        var st = PluginState(machines: machineIDs.map { $0 == "gold" ? c : Machine(machineID: $0, type: .arp) }, scenes: [sc])
        st.euclideousNoteSource = .midi
        st.euclideousSameNoteGuard = false
        let box = SnapshotBuilder.build(from: st)
        let e = GoldenEmitter(); let router = Router(); var diag = KernelDiag()
        let sr = 48_000.0
        let p = NotePool(); for n in pool { p.noteOn(n, velocity: 100, channel: 0) }
        var ts = 0.0
        func beatNow() -> Double { ts * tempo / 60.0 / sr }
        while beatNow() < beats {
            router.process(box: box, pool: p, playing: true, beatPos: beatNow(), tempo: tempo, sampleRate: sr, timestampSample: ts, frameCount: frames, forceColumn: 0, out: e, diag: &diag)
            ts += Double(frames)
        }
        router.process(box: box, pool: p, playing: false, beatPos: beatNow(), tempo: tempo, sampleRate: sr, timestampSample: ts, frameCount: frames, out: e, diag: &diag)
        return e.events.filter { $0.cable == 1 && $0.status == 0x90 }.map { ev -> String in
            let col = pool.firstIndex(of: ev.note).map { $0 + 1 } ?? 0
            return "\(Int((Double(ev.sample) / beat * 16).rounded())):\(col)"
        }.joined(separator: " ")
    }
    private func check(_ name: String, _ l: EuclidLine, beats: Double, _ expected: String, file: StaticString = #filePath, line: UInt = #line) {
        let got = ranks(l, beats: beats)
        XCTAssertEqual(got, expected, name, file: file, line: line)
    }

    // 7 steps of 1/8: a pass is 3.5 beats; eight passes = 28 beats. 4 hits per pass.
    func testMelodyChain1PinsTheRanksInEveryDirection() {
        for (name, dir, expected) in goldenMelody1 { check("melody [1], \(name)", lane(hits: 4, steps: 7, dir: dir, melody: [1]), beats: 28, expected) }
    }
    func testRhythm1WithMelody2PinsTheRanksInEveryDirection() {
        for (name, dir, expected) in goldenRhythm1Melody2 { check("rhythm [1] + melody [2], \(name)", lane(hits: 4, steps: 7, dir: dir, rhythm: [1], melody: [2]), beats: 28, expected) }
    }
    func testAChainOfSeveralLinksOnBothPins() {
        check("rhythm [2,1] + melody [3], 5 steps, 3 hits", lane(hits: 3, steps: 5, rhythm: [2, 1], melody: [3]), beats: 24, goldenTwoLinks)
    }
    func testADottedRateWhoseBarLineFallsInsideAStepPins() {
        check("dotted 1/8 (0.75), 7 steps, rhythm [1] + melody [2]", lane(hits: 4, steps: 7, rate: .r1_8d, rhythm: [1], melody: [2]), beats: 32, goldenDotted)
    }
    func testAdvanceStepPins() {
        check("ADV STEP, 7 steps, rhythm [1] + melody [2]", lane(hits: 4, steps: 7, rhythm: [1], melody: [2], advanceStep: true), beats: 28, goldenAdvStep)
    }
    func testATripletRateWithEveryAndAPendulumRiffPins() {
        check("1/8T, 6 steps, rhythm [2], melody [1], riff PING-PONG EVERY 2", lane(hits: 4, steps: 6, rate: .r1_8t, rhythm: [2], melody: [1], riffDir: .pendulum, every: 2), beats: 24, goldenTriplet)
    }
}

// Captured from the engine as it stood before the ferry (2026-11-04). Do not edit: a difference here is a sound change.
private let goldenMelody1: [(String, EuclidDir, String)] = [
    ("FWD", .fwd, "0:1 16:2 32:3 48:4 56:1 72:2 88:3 104:4 112:1 128:2 144:3 160:4 168:1 184:2 200:3 216:4 224:1 240:2 256:3 272:4 280:1 296:2 312:3 328:4 336:1 352:2 368:3 384:4 392:1 408:2 424:3 440:4 448:1"),
    ("BKW", .bkw, "0:1 16:2 32:3 48:4 56:1 72:2 88:3 104:4 112:1 128:2 144:3 160:4 168:1 184:2 200:3 216:4 224:1 240:2 256:3 272:4 280:1 296:2 312:3 328:4 336:1 352:2 368:3 384:4 392:1 408:2 424:3 440:4 448:1"),
    ("PING-PONG", .pingpong, "0:1 16:2 32:3 48:4 56:5 72:6 88:7 104:8 112:1 128:2 144:3 160:4 168:5 184:6 200:7 216:8 224:1 240:2 256:3 272:4 280:5 296:6 312:7 328:8 336:1 352:2 368:3 384:4 392:5 408:6 424:7 440:8 448:1")]
private let goldenRhythm1Melody2: [(String, EuclidDir, String)] = [
    ("FWD", .fwd, "0:1 16:2 32:3 48:4 56:5 64:1 80:2 96:3 112:4 120:5 128:1 144:2 160:3 176:4 184:5 192:1 208:2 224:3 240:4 248:5 256:1 272:2 288:3 304:4 312:5 320:1 336:2 352:3 368:4 376:5 384:1 400:2 416:3 432:4 440:5 448:1"),
    ("BKW", .bkw, "0:1 16:2 32:3 48:4 56:5 64:1 80:2 96:3 112:4 120:5 128:1 144:2 160:3 176:4 184:5 192:1 208:2 224:3 240:4 248:5 256:1 272:2 288:3 304:4 312:5 320:1 336:2 352:3 368:4 376:5 384:1 400:2 416:3 432:4 440:5 448:1"),
    ("PING-PONG", .pingpong, "0:1 16:2 32:3 48:4 56:5 64:6 80:7 96:8 112:1 120:2 128:1 144:2 160:3 176:4 184:5 192:6 208:7 224:8 240:1 248:2 256:1 272:2 288:3 304:4 312:5 320:6 336:7 352:8 368:1 376:2 384:1 400:2 416:3 432:4 440:5 448:6")]
private let goldenTwoLinks = "0:1 16:2 32:3 40:4 56:5 72:6 80:7 96:8 112:1 120:1 128:2 144:3 160:4 168:5 184:6 192:1 208:2 224:3 232:4 248:5 264:6 272:7 288:8 304:1 312:1 320:2 336:3 352:4 360:5 376:6 384:1"
private let goldenDotted = "0:1 24:2 48:3 84:5 108:6 144:2 168:3 192:4 216:5 240:7 276:2 300:3 336:4 360:6 384:1 408:2 432:3 468:5 492:6"
private let goldenAdvStep = "0:1 16:3 32:5 48:7 56:8 64:1 80:3 96:5 112:7 120:8 128:1 144:3 160:5 176:7 184:8 192:1 208:3 224:5 240:7 248:8 256:1 272:3 288:5 304:7 312:8 320:1 336:3 352:5 368:7 376:8 384:1 400:3 416:5 432:7 440:8 448:1"
private let goldenTriplet = "0:1 11:1 16:2 27:2 32:1 43:1 48:2 59:2 64:1 75:1 80:2 91:2 96:1 107:1 112:2 123:2 128:1 139:1 144:2 155:2 160:1 171:1 176:2 187:2 192:1 203:1 208:2 219:2 224:1 235:1 240:2 251:2 256:1 267:1 272:2 283:2 288:1 299:1 304:2 315:2 320:1 331:1 336:2 347:2 352:1 363:1 368:2 379:2 384:1"
