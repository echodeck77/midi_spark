//  CCPageV2Tests.swift — CC PAGE V2 (2026-11-15) §7: the pure functions. Visibility (§4.3), hidden-means-inert (§4.4), and amendment 1 (MUTE gone; a muted output parks at LOW — the engine side is in RouterTests/PortsStressTests).

import XCTest
#if canImport(CoreGraphics)
import CoreGraphics
#endif

final class CCPageV2Tests: XCTestCase {

    // §7.1 — the shown set matches §4.3 for every mode × hold × ramp: in the fixed order, never more than seven, the §4.3 rules exactly.
    func testVisibility() {
        for mode in EmitterCCValueMode.allCases {
            for hold in [0, 25, 100] {
                for ramp in [0, 50] {
                    let shown = euclideousCCVisibleControls(mode: mode, hold: hold, ramp: ramp)
                    let effRamp = max(0, min(ramp, 100 - hold))
                    XCTAssertLessThanOrEqual(shown.count, 7, "never more than seven controls")
                    XCTAssertEqual(shown, shown.sorted { $0.rawValue < $1.rawValue }, "in the §4.2 fixed order")
                    XCTAssertEqual(Set(shown).count, shown.count, "no duplicates")
                    XCTAssertTrue(shown.contains(.high) && shown.contains(.low) && shown.contains(.hold), "HIGH/LOW/HOLD always")
                    XCTAssertEqual(shown.contains(.ramp), hold < 100, "RAMP iff hold < 100  [\(mode) hold \(hold)]")
                    XCTAssertEqual(shown.contains(.to), hold < 100 && mode != .hits, "TO iff hold<100 and not HITS  [\(mode) hold \(hold)]")
                    XCTAssertEqual(shown.contains(.curve), effRamp > 0, "CURVE iff effective ramp > 0  [\(mode) hold \(hold) ramp \(ramp)]")
                    XCTAssertEqual(shown.contains(.passes), mode == .climb, "PASSES iff CLIMB  [\(mode)]")
                }
            }
        }
    }

    // §8 acceptance boards A / B / C (MUTE gone — amendment 1).
    func testAcceptanceBoards() {
        XCTAssertEqual(euclideousCCVisibleControls(mode: .riff, hold: 25, ramp: 50), [.high, .low, .hold, .ramp, .to, .curve], "Board A: RIFF 25/50 → 6, three rows")
        XCTAssertEqual(euclideousCCVisibleControls(mode: .hits, hold: 25, ramp: 50), [.high, .low, .hold, .ramp, .curve], "Board B: HITS → no TO")
        XCTAssertEqual(euclideousCCVisibleControls(mode: .climb, hold: 100, ramp: 50), [.high, .low, .hold, .passes], "Board C: CLIMB HOLD 100 → no RAMP/TO/CURVE, shows PASSES")
    }

    // §7.2 — hidden-means-inert. A one-bar trace: in HITS, TO = NEXT and TO = REST send the SAME thing (§4.4 forces REST); a mode that DOES read TO differs, proving the test bites. PASSES off CLIMB changes nothing.
    private func hits() -> [EmitterCCTraceHit] {
        // two lanes' worth of varied events so the envelope's target actually matters (different ranks ⇒ different NEXT values)
        [EmitterCCTraceHit(beat: 0, rank: 2, lane: 0, ordinal: 0, passHits: 2, count: 1, routed: 2),
         EmitterCCTraceHit(beat: 1, rank: 7, lane: 0, ordinal: 1, passHits: 2, count: 2, routed: 2),
         EmitterCCTraceHit(beat: 2, rank: 4, lane: 0, ordinal: 2, passHits: 2, count: 1, routed: 2),
         EmitterCCTraceHit(beat: 3, rank: 8, lane: 0, ordinal: 3, passHits: 2, count: 2, routed: 2)]
    }
    private func trace(_ cc: EmitterCC) -> [CGPoint] {
        emitterCCTrace(cfg: EmitterCCCfg(cc), hits: hits(), barBeats: 4).points
    }
    func testHitsIgnoresTo() {
        var rest = EmitterCC(); rest.on = true; rest.valueMode = .hits; rest.hold = 20; rest.ramp = 60; rest.high = 120; rest.low = 10; rest.to = .rest
        var next = rest; next.to = .next
        XCTAssertEqual(trace(rest), trace(next), "HITS: TO = NEXT must equal TO = REST (§4.4 effectiveTo)")
        // the control: RIFF genuinely reads TO, so the two differ — the equality above is not a vacuous pass.
        var rRest = rest; rRest.valueMode = .riff; rRest.to = .rest
        var rNext = rRest; rNext.to = .next
        XCTAssertNotEqual(trace(rRest), trace(rNext), "RIFF: TO changes the ramp target, so the traces differ")
    }
    func testPassesInertOffClimb() {
        var a = EmitterCC(); a.on = true; a.valueMode = .hits; a.hold = 20; a.ramp = 60; a.passes = 1
        var b = a; b.passes = 16
        XCTAssertEqual(trace(a), trace(b), "PASSES changes nothing outside CLIMB")
    }

    // amendment 1 §3.3 — the model has no muteValue; an old document that stored one decodes cleanly (the key is ignored).
    func testNoMuteValueAndOldDocDecodes() throws {
        let json = Data(#"{"on":true,"ccNumber":71,"valueMode":"HITS","high":100,"low":20,"hold":25,"ramp":50,"to":"REST","curve":"EXP","passes":1,"muteValue":99}"#.utf8)
        let cc = try JSONDecoder().decode(EmitterCC.self, from: json)
        XCTAssertEqual(cc.ccNumber, 71); XCTAssertEqual(cc.low, 20); XCTAssertTrue(cc.on, "an old document's muteValue key is ignored, the rest loads")
    }
}
