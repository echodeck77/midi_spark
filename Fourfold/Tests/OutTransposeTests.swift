//  OutTransposeTests.swift
//  CARD BACKS v2 (2026-10-28): a part's OUT-TRANSPOSE — the pure scale-step mover (ferry §13.12) and the two EuclidLine fields' persistence (§13.2). The engine path (Router) is in RouterTests' "OUT-TRANSPOSE" extension,
//  which needs that file's private fixtures.

import XCTest

final class OutTransposeTests: XCTestCase {
    private func mask(_ root: Int, _ type: ScaleType) -> UInt16 { euclideousKeyPitchClassMask(root: root, intervals: type.intervals) }
    private func mv(_ note: Int, _ steps: Int, _ m: UInt16) -> Int { euclideousScaleStepMove(note: note, steps: steps, pcMask: m) }

    // §13.12 — the ferry's own list. Note numbers: C4 = 60, so E4 64, F♯4 66, G4 67, D4 62, B4 71, C5 72, B3 59, E5 76, D3 50.
    func testTheFerrysScaleStepList() {
        let eMinor = mask(4, .naturalMinor)
        XCTAssertEqual(mv(64, 1, eMinor), 66, "E4 +1 → F♯4")
        XCTAssertEqual(mv(64, 2, eMinor), 67, "E4 +2 → G4")
        XCTAssertEqual(mv(64, -1, eMinor), 62, "E4 −1 → D4")
        XCTAssertEqual(mv(71, 1, eMinor), 72, "B4 +1 → C5 (the steps wrap into the next octave)")
        XCTAssertEqual(mv(60, -1, eMinor), 59, "C4 −1 → B3")
        XCTAssertEqual(mv(66, -2, eMinor), 62, "F♯4 −2 → D4")
        XCTAssertEqual(mv(64, 7, eMinor), 76, "E4 +7 → E5: a seven-note scale, so 7 steps is one octave")
        XCTAssertEqual(mv(62, -7, eMinor), 50, "D4 −7 → D3")
        XCTAssertEqual(mv(60, 5, mask(0, .majorPentatonic)), 72, "C major pentatonic: C4 +5 → C5 (five notes, five steps an octave)")
        XCTAssertEqual(mv(65, 1, eMinor), 67, "F4 is outside E minor: it moves as the scale note below it (E4) does — E4 +1 = F♯4 — and keeps its semitone: G4")
    }
    func testNothingMovesAtZeroStepsOrWithoutAScaleAndTheResultIsPinnedToTheMidiRange() {
        let c = mask(0, .major)
        XCTAssertEqual(mv(200, 0, c), 200, "zero steps hands the note back untouched — not even pinned")
        XCTAssertEqual(mv(60, 3, 0), 60, "an empty scale moves nothing")
        XCTAssertEqual(mv(127, 1, c), 127, "pinned at the top")
        XCTAssertEqual(mv(0, -1, c), 0, "pinned at the bottom")
        XCTAssertEqual(mv(125, 7, c), 127); XCTAssertEqual(mv(3, -7, c), 0)
    }
    /// A note below its octave's LOWEST scale degree (C in D major) anchors to the top degree of the octave below, and keeps its offset.
    func testANoteBelowItsOctavesLowestDegreeAnchorsToTheOctaveBelow() {
        let dMajor = mask(2, .major)                  // C♯ D E F♯ G A B — C (pc 0) sits under every degree
        XCTAssertEqual(mv(60, 1, dMajor), 62, "C4 +1: B3 +1 step = C♯4, plus C's one-semitone offset above B → D4")
        XCTAssertEqual(mv(60, -1, dMajor), 58, "C4 −1: A3 plus the offset → B♭3")
        XCTAssertEqual(mv(60, 7, dMajor), 72, "an octave of steps is an octave of semitones, offset kept")
        XCTAssertEqual(mv(60, -7, dMajor), 48)
    }
    /// Against LISTEN's mover (`euclideousListenMoveByInterval`) wherever that one is right: in-range, and the note has a scale degree at or below its pitch class. (For a note below its octave's lowest degree LISTEN's
    /// mover lands an octave high — C4 +0 in D major gives C5 — which is why the out-transpose has its own, allocation-free function.)
    func testItAgreesWithListensMoverEverywhereThatOneIsRight() {
        var checked = 0
        for type in ScaleType.allCases {
            for root in 0..<12 {
                let m = mask(root, type)
                let pcs = type.intervals.map { (($0 + root) % 12 + 12) % 12 }.sorted()
                for note in 24...100 {
                    let pc = note % 12
                    guard pcs.contains(where: { $0 <= pc }) else { continue }
                    for steps in -7...7 {
                        let ref = euclideousListenMoveByInterval(note: note, interval: steps, octave: 0, keyRoot: root, scaleIntervals: type.intervals)
                        XCTAssertEqual(mv(note, steps, m), ref, "\(type) root \(root) note \(note) steps \(steps)")
                        checked += 1
                    }
                }
            }
        }
        XCTAssertGreaterThan(checked, 50_000)
    }
    /// For every scale, root and note: k steps for a k-note scale is exactly an octave (offset kept), in either direction, and an in-scale note comes back after +n then −n.
    func testAFullScaleOfStepsIsAnOctaveAndInScaleNotesComeBack() {
        for type in ScaleType.allCases {
            for root in 0..<12 {
                let m = mask(root, type), k = m.nonzeroBitCount
                for note in 36...90 {
                    XCTAssertEqual(mv(note, k, m), note + 12, "\(type) root \(root) note \(note)")
                    XCTAssertEqual(mv(note, -k, m), note - 12)
                    if m & (1 << UInt16(note % 12)) != 0 { for n in 1...7 { XCTAssertEqual(mv(mv(note, n, m), -n, m), note, "in-scale \(note) +\(n) −\(n)") } }
                }
            }
        }
    }

    /// A note ALREADY outside 0…127 is handed back untouched (the engine drops such a pitch; pinning it would make it sound — adversarial review 2026-10-28); an in-range note the shift pushes outside is pinned.
    func testANoteOutsideTheMidiRangeIsHandedBackUntouched() {
        let c = mask(0, .major)
        for n in [-1, -40, 128, 150, 10_000, -10_000] { for s in [-7, -1, 1, 7] { XCTAssertEqual(mv(n, s, c), n, "note \(n) steps \(s)") } }
        XCTAssertEqual(mv(127, 1, c), 127); XCTAssertEqual(mv(0, -1, c), 0)
    }
    /// Brute force against an independent oracle (sorted pitch-class array, written separately): every scale × root × note −40…160 × steps −14…14 — 909,324 cases, covering the `below == 0` branch the agreement test skips.
    func testItAgreesWithAnIndependentOracleEverywhere() {
        func oracle(_ note: Int, _ steps: Int, _ pcs: [Int]) -> Int {
            guard steps != 0, !pcs.isEmpty, note >= 0, note <= 127 else { return note }
            let m = pcs.count, pc = ((note % 12) + 12) % 12
            var octave = (note - pc) / 12, degree = -1
            for i in 0..<m where pcs[i] <= pc { degree = i }
            let offset: Int
            if degree >= 0 { offset = pc - pcs[degree] } else { degree = m - 1; offset = pc - (pcs[m - 1] - 12); octave -= 1 }
            let base = degree + steps, wrapped = ((base % m) + m) % m, laps = (base - wrapped) / m
            return max(0, min(127, (octave + laps) * 12 + pcs[wrapped] + offset))
        }
        var checked = 0
        for type in ScaleType.allCases { for root in 0..<12 {
            let m = mask(root, type), pcs = Array(Set(type.intervals.map { (($0 + root) % 12 + 12) % 12 })).sorted()
            for note in -40...160 { for steps in -14...14 {
                let got = mv(note, steps, m), want = oracle(note, steps, pcs)
                if got != want { XCTFail("\(type) root \(root) note \(note) steps \(steps): got \(got), oracle \(want)"); return }
                checked += 1
            } }
        } }
        XCTAssertGreaterThan(checked, 900_000)
    }

    // MARK: persistence (§13.2)

    func testTheTwoFieldsDefaultToZeroClampAndRoundTrip() throws {
        let fresh = EuclidLine()
        XCTAssertNil(fresh.riffOutTranspose); XCTAssertNil(fresh.notesOutTranspose)
        XCTAssertEqual(fresh.riffOutTransposeResolved, 0); XCTAssertEqual(fresh.notesOutTransposeResolved, 0)
        var l = EuclidLine(pulses: 3, steps: 8)
        l.riffOutTranspose = 40; l.notesOutTranspose = -40
        XCTAssertEqual(l.riffOutTransposeResolved, 7, "a stored 40 reads as 7"); XCTAssertEqual(l.notesOutTransposeResolved, -7)
        l.riffOutTranspose = -3; l.notesOutTranspose = 5
        let back = try JSONDecoder().decode(EuclidLine.self, from: JSONEncoder().encode(l))
        XCTAssertEqual(back.riffOutTranspose, -3); XCTAssertEqual(back.notesOutTranspose, 5); XCTAssertEqual(back, l)
        let dirty = try JSONDecoder().decode(EuclidLine.self, from: Data(#"{"target":0,"pulses":5,"steps":8,"rotate":0,"invert":false,"riffOutTranspose":99,"notesOutTranspose":-99}"#.utf8))
        XCTAssertEqual(dirty.riffOutTranspose, 7, "clamped at decode"); XCTAssertEqual(dirty.notesOutTranspose, -7)
        let wrongType = try JSONDecoder().decode(EuclidLine.self, from: Data(#"{"target":0,"pulses":5,"steps":8,"rotate":0,"invert":false,"riffOutTranspose":"up"}"#.utf8))
        XCTAssertNil(wrongType.riffOutTranspose, "a wrong-typed value reads as missing, never a whole-session reset")
        let old = try JSONDecoder().decode(EuclidLine.self, from: Data(#"{"target":0,"pulses":5,"steps":8,"rotate":0,"invert":false}"#.utf8))
        XCTAssertNil(old.riffOutTranspose); XCTAssertNil(old.notesOutTranspose); XCTAssertEqual(old.riffOutTransposeResolved, 0)
        XCTAssertNotEqual(l, { var o = l; o.notesOutTranspose = 4; return o }(), "a different out-transpose is a different line, so a pad drag is an undo step")
    }
    /// SnapshotBuilder rebuilds each lane as a FRESH literal: a field it forgets silently resets every render.
    func testTheSnapshotBuilderKeepsBothFields() throws {
        var l = EuclidLine(pulses: 3, steps: 8)
        l.riffOutTranspose = -3; l.notesOutTranspose = 5
        func rebuilt(_ line: EuclidLine) throws -> EuclidLine {
            var c = Machine(machineID: "gold", type: .euclid)
            c.paramsA.euclidLines = [line]
            var sc = SceneState.empty(); sc.cells[0][Snap.euclideousRow] = Cell(machineID: "gold", buses: [.a])
            let built = SnapshotBuilder.build(from: PluginState(machines: [c], scenes: [sc]))
            return try XCTUnwrap(built.machines.first { $0.a.euclidLines.count == 4 }?.a.euclidLines.first)
        }
        let r = try rebuilt(l)
        XCTAssertEqual(r.riffOutTranspose, -3); XCTAssertEqual(r.notesOutTranspose, 5)
        l.riffOutTranspose = 9; l.notesOutTranspose = -9
        let c = try rebuilt(l)
        XCTAssertEqual(c.riffOutTranspose, 7, "the rebuild's own bound matches the resolver's"); XCTAssertEqual(c.notesOutTranspose, -7)
        XCTAssertNil(try rebuilt(EuclidLine(pulses: 3, steps: 8)).riffOutTranspose, "nil stays nil — a lane that never set it is not given a value")
    }
    /// The KEY pill's scale reaches the render thread as a root + root-relative intervals; the mask is exactly its pitch classes.
    func testTheKeyMask() {
        XCTAssertEqual(euclideousKeyPitchClassMask(root: 0, intervals: ScaleType.major.intervals), 0b1010_1011_0101)   // C D E F G A B
        XCTAssertEqual(euclideousKeyPitchClassMask(root: 4, intervals: ScaleType.naturalMinor.intervals), euclideousKeyPitchClassMask(root: 7, intervals: ScaleType.major.intervals), "E minor and G major share their notes")
        XCTAssertEqual(euclideousKeyPitchClassMask(root: -1, intervals: [0]), 1 << 11, "a negative root wraps")
        XCTAssertEqual(euclideousKeyPitchClassMask(root: 0, intervals: []), 0)
    }
}
