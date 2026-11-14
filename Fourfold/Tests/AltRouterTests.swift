//  AltRouterTests.swift — ALT ferry (2026-11-14), §9.5–9.13 on the wire: the four overrides applied to notes in the alt state, the rest, the units, and no stuck notes while cycling. Drives the real Router and reads the emitted (sample, cable,
//  note, vel) stream. The test lane is a STACK (notes-layer) lane that hits EVERY step (0.5-beat gap) so each hit re-strikes cleanly — the overrides go through the same addPitch/riffResolve path as the riff, which the golden byte-identity covers.

import XCTest

final class AltRouterTests: XCTestCase {
    private struct Ev: Equatable { let sample: Int64; let cable: UInt8; let status: UInt8; let note: UInt8; let vel: UInt8 }
    private final class Rec: MIDIEmitter {
        var ev: [Ev] = []
        func emit(sampleTime: Int64, cable: UInt8, _ b0: UInt8, _ b1: UInt8, _ b2: UInt8) { ev.append(Ev(sample: sampleTime, cable: cable, status: b0 & 0xF0, note: b1, vel: b2)) }
        var ons: [Ev] { ev.filter { $0.status == 0x90 && $0.vel > 0 } }
        var offs: [Ev] { ev.filter { $0.status == 0x80 || ($0.status == 0x90 && $0.vel == 0) } }
    }
    private let tb = 120.0 / 60.0 / 48_000.0   // samples → beats

    /// A STACK lane hitting every step; `configure` sets the ALT fields. Renders `beats` of playing windows (forceColumn 0, as the mask tests do, so the grid cell keeps ticking) + a stop edge.
    private func render(beats: Double, pool: [UInt8] = [60, 62, 64, 65], _ configure: (inout EuclidLine) -> Void) -> Rec {
        var line = EuclidLine(target: 0, pulses: 8, steps: 8, noteSel: .all, rate: .r1_8, useRiff: false, litNotes: 0b0000_0001, riffOn: false, sourceMode: .midi)
        line.notesOn = true; line.notesGate = 0.5
        line.notesOutMask = 0b0001   // stack → output A
        configure(&line)
        var c = Machine(machineID: "gold", type: .euclid); c.paramsA.euclidLines = [line]
        var st = PluginState(machines: machineIDs.map { $0 == "gold" ? c : Machine(machineID: $0, type: .arp) },
                             scenes: [{ var s = SceneState.empty(); s.cells[0][Snap.euclideousRow] = Cell(machineID: "gold", buses: [.a]); return s }()])
        st.euclideousNoteSource = .midi
        var pl = st.sourcePlanResolved; pl.midiOctaves = .keep; st.euclideousSourcePlan = pl   // hold the pool where it's played (KEEP), as the Router tests do
        let box = SnapshotBuilder.build(from: st)
        let router = Router(); var diag = KernelDiag(); let e = Rec(); let np = NotePool(); for n in pool { np.noteOn(n, velocity: 100, channel: 0) }
        let tempo = 120.0, sr = 48_000.0, frames: UInt32 = 2048, windowBeats = Double(frames) * tempo / 60.0 / sr
        var beat = 0.0, ts = 0.0
        while beat < beats {
            router.process(box: box, pool: np, playing: true, beatPos: beat, tempo: tempo, sampleRate: sr, timestampSample: ts, frameCount: frames, forceColumn: 0, out: e, diag: &diag)
            beat += windowBeats; ts += Double(frames)
        }
        router.process(box: box, pool: np, playing: false, beatPos: beat, tempo: tempo, sampleRate: sr, timestampSample: ts, frameCount: frames, out: e, diag: &diag)
        return e
    }
    /// The non-ALL cables (1…4) each hit struck on, in time order — one Set of cables per distinct onset sample.
    private func hitsByCable(_ e: Rec, cablesIn: Set<UInt8> = [1, 2, 3, 4]) -> [Set<UInt8>] {
        var out: [(Int64, Set<UInt8>)] = []
        for on in e.ons.filter({ cablesIn.contains($0.cable) }).sorted(by: { $0.sample < $1.sample }) {
            if let i = out.firstIndex(where: { $0.0 == on.sample }) { out[i].1.insert(on.cable) } else { out.append((on.sample, [on.cable])) }
        }
        return out.map { $0.1 }
    }
    /// A sounding hit's duration in beats: the first off of the same pitch at/after its on (gate < 1 ⇒ no overlap, so this is unambiguous).
    private func dur(_ e: Rec, _ on: Ev, cable: UInt8 = 1) -> Double {
        guard let off = e.offs.first(where: { $0.cable == cable && $0.note == on.note && $0.sample >= on.sample }) else { return -1 }
        return Double(off.sample - on.sample) * tb
    }
    private func assertNothingLeftSounding(_ e: Rec) {
        var last: [Int: UInt8] = [:]
        for ev in e.ev where ev.status == 0x90 || ev.status == 0x80 {
            last[(Int(ev.cable) * 16) * 128 + Int(ev.note)] = (ev.status == 0x90 && ev.vel > 0) ? 0x90 : 0x80
        }
        XCTAssertFalse(last.values.contains(0x90), "a note was left sounding")
    }

    // §9.5 — OUT (HIT 3/1, alt set {C, D}): every 4th hit leaves on C and D, the others on A.
    func testOutRoutesAltHitsElsewhere() {
        let e = render(beats: 4) {
            $0.altUnit = .hit; $0.altMainCount = 3; $0.altAltCount = 1
            $0.altNotes = EuclideousAltPart(outOn: true, out: 0b1100)   // C + D
        }
        let hits = hitsByCable(e)
        XCTAssertGreaterThanOrEqual(hits.count, 8)
        for i in 0..<8 {
            if i % 4 == 3 { XCTAssertEqual(hits[i], [3, 4], "hit \(i) (ord%4==3) is alt → C and D") }
            else { XCTAssertEqual(hits[i], [1], "hit \(i) is main → A") }
        }
        assertNothingLeftSounding(e)
    }

    // §9.6 — a rest: alt OUT on with an empty set ⇒ every alt hit sends nothing (no output, no ALL); the next (main) hit plays. HIT 1/1 silences every other hit, so the sounding hits are 1.0 beat apart (not 0.5).
    func testEmptyAltOutIsARest() {
        let e = render(beats: 4) {
            $0.altUnit = .hit; $0.altMainCount = 1; $0.altAltCount = 1
            $0.altNotes = EuclideousAltPart(outOn: true, out: 0)   // a rest
        }
        let c1 = e.ons.filter { $0.cable == 1 }.map { $0.sample }.sorted()
        XCTAssertGreaterThanOrEqual(c1.count, 3)
        for i in 1..<c1.count { XCTAssertEqual(Double(c1[i] - c1[i - 1]) * tb, 1.0, accuracy: 0.05, "the sounding hits are 1.0 beat apart (every other hit rested)") }
        XCTAssertEqual(e.ons.filter { $0.cable == 0 }.count, c1.count, "a rest sends nothing on ALL either (ALL count == the sounding count)")
        assertNothingLeftSounding(e)
    }

    // §9.7 — VEL and GATE: alt hits take the alt velocity and a shorter gate; main hits keep their values.
    func testVelAndGateReplaceMainOnAltHits() {
        let e = render(beats: 4) {
            $0.notesVelocity = 90; $0.notesGate = 0.5
            $0.altUnit = .hit; $0.altMainCount = 1; $0.altAltCount = 1
            $0.altNotes = EuclideousAltPart(velOn: true, vel: 120, gateOn: true, gate: 40)
        }
        let ons = e.ons.filter { $0.cable == 1 }.sorted { $0.sample < $1.sample }
        XCTAssertGreaterThanOrEqual(ons.count, 6)
        for (i, on) in ons.enumerated() { XCTAssertEqual(Int(on.vel), i % 2 == 0 ? 90 : 120, "hit \(i): main 90 / alt 120") }
        XCTAssertEqual(dur(e, ons[0]), 0.50 * 0.5, accuracy: 0.03, "main gate 50% × the 0.5-beat gap")
        XCTAssertEqual(dur(e, ons[1]), 0.40 * 0.5, accuracy: 0.03, "alt gate 40% × the 0.5-beat gap")
        assertNothingLeftSounding(e)
    }

    // §9.8 — OCT: main +0, alt +1 ⇒ alt notes sound 12 semitones above the main ones.
    func testOctReplacesTheMainOctave() {
        let p = render(beats: 4, pool: [60]) {   // one pool note ⇒ OCT is the only pitch change
            $0.altUnit = .hit; $0.altMainCount = 1; $0.altAltCount = 1
            $0.altNotes = EuclideousAltPart(octOn: true, oct: 1)
        }.ons.filter { $0.cable == 1 }.sorted { $0.sample < $1.sample }.map(\.note)
        XCTAssertGreaterThanOrEqual(p.count, 4)
        for i in 0..<p.count { XCTAssertEqual(Int(p[i]), i % 2 == 0 ? 60 : 72, "hit \(i): main 60 / alt +1 octave = 72") }
    }

    // §9.9 / §3.2 — a pill that's off leaves the setting at its main value (the stored alt value is inert until the pill is on).
    func testPillOffSoundsAsMain() {
        func vels(_ on: Bool) -> [UInt8] {
            render(beats: 4) {
                $0.notesVelocity = 90; $0.altUnit = .hit; $0.altMainCount = 1; $0.altAltCount = 1
                $0.altNotes = EuclideousAltPart(velOn: on, vel: 120)   // value stored either way; only the pill differs
            }.ons.filter { $0.cable == 1 }.sorted { $0.sample < $1.sample }.map(\.vel)
        }
        XCTAssertTrue(vels(false).allSatisfy { $0 == 90 }, "pill off ⇒ every hit the main 90, the stored 120 inert")
        XCTAssertTrue(vels(true).enumerated().allSatisfy { $0.1 == ($0.0 % 2 == 0 ? 90 : 120) }, "pill on ⇒ alt hits take 120")
    }

    // §9.11 — units: STEP 2/2 makes step indices 2,3,6,7,… alt. A hit on every step ⇒ hit i sits on step i, so hit i is alt iff (i mod 4) >= 2.
    func testStepUnit() {
        let e = render(beats: 4) {
            $0.altUnit = .step; $0.altMainCount = 2; $0.altAltCount = 2
            $0.altNotes = EuclideousAltPart(outOn: true, out: 0b0100)   // C
        }
        let hits = hitsByCable(e)
        XCTAssertGreaterThanOrEqual(hits.count, 8)
        for i in 0..<8 { XCTAssertEqual(hits[i], (i % 4) >= 2 ? [3] : [1], "hit \(i) on step \(i): \((i % 4) >= 2 ? "alt→C" : "main→A")") }
    }

    // §9.12 — mid-note safety: cycling every ALT setting while notes sound (GATE 100, held legato — the worst case) leaves nothing stuck.
    func testNoStuckNotesWhileCyclingAlt() {
        for unit in EuclideousAltUnit.allCases {
            let e = render(beats: 8) {
                $0.notesGate = 1.0   // held legato
                $0.altUnit = unit; $0.altMainCount = 1; $0.altAltCount = 1
                $0.altNotes = EuclideousAltPart(outOn: true, out: 0, octOn: true, oct: 2, velOn: true, vel: 50, gateOn: true, gate: 30)
            }
            assertNothingLeftSounding(e)
        }
    }
}
