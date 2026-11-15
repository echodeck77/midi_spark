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

    // §7.3 — the layout: header / trace / VALUE / grid frames, four rows inside the panel, and the §1.3 trace shrink.
    func testLayout() {
        let L = euclideousCCPageLayout(box: CGSize(width: 390, height: 300))
        XCTAssertEqual(L.header.minY, 0); XCTAssertEqual(L.header.height, 30)
        XCTAssertEqual(L.trace.minY, 38, accuracy: 0.01); XCTAssertEqual(L.trace.height, 70, accuracy: 0.01)
        XCTAssertEqual(L.valueRow.minY, 116, accuracy: 0.01); XCTAssertEqual(L.valueRow.height, 26)
        XCTAssertEqual(L.pad, 12); XCTAssertEqual(L.colW, (390 - 24 - 12) / 2, accuracy: 0.01)
        // two columns: cell 0 left, cell 1 to its right, cell 2 on the next row
        XCTAssertEqual(L.gridCell(0).minX, 12, accuracy: 0.01)
        XCTAssertEqual(L.gridCell(1).minX, 12 + L.colW + 12, accuracy: 0.01)
        XCTAssertEqual(L.gridCell(2).minY, L.gridCell(0).minY + 26 + 6, accuracy: 0.01)
        XCTAssertTrue(L.fits, "four rows fit at 300 tall"); XCTAssertLessThanOrEqual(L.gridCell(6).maxY, 300, "the 7th control (row 4) is inside the panel")
        // §1.3: a shorter panel shrinks the trace to 52; shorter still flags the floor.
        XCTAssertEqual(euclideousCCPageLayout(box: CGSize(width: 390, height: 270)).trace.height, 52, accuracy: 0.01, "shrinks the trace when four rows wouldn't fit at 70")
        let tiny = euclideousCCPageLayout(box: CGSize(width: 390, height: 240))
        XCTAssertFalse(tiny.fits); XCTAssertTrue(tiny.floors.contains(EuclideousCCPageLayout.gridRowsFloor), "too short even at trace 52 ⇒ floor flagged, drawn anyway")
    }

    // §7.4 — reflow order: a control is only ever hidden by one EARLIER in the fixed order (HOLD hides RAMP/TO/CURVE; RAMP hides CURVE), so the visible list never reorders.
    func testReflowOrder() {
        // whenever a control is hidden, at least one control that is still shown and sits BEFORE it in the order is what gates it — i.e. the list stays a prefix-stable subsequence.
        for mode in EmitterCCValueMode.allCases {
            let full = euclideousCCVisibleControls(mode: mode, hold: 0, ramp: 50)   // the most-expanded set for this mode
            for hold in [0, 25, 100] {
                for ramp in [0, 50] {
                    let shown = euclideousCCVisibleControls(mode: mode, hold: hold, ramp: ramp)
                    // `shown` is always an in-order subsequence of `full` (never a reordering)
                    var fi = 0
                    for c in shown { while fi < full.count && full[fi] != c { fi += 1 }; XCTAssertLessThan(fi, full.count, "\(c) keeps its place for \(mode) hold \(hold) ramp \(ramp)"); fi += 1 }
                }
            }
        }
    }

    // amendment 1 §3.3 — the model has no muteValue; an old document that stored one decodes cleanly (the key is ignored).
    func testNoMuteValueAndOldDocDecodes() throws {
        let json = Data(#"{"on":true,"ccNumber":71,"valueMode":"HITS","high":100,"low":20,"hold":25,"ramp":50,"to":"REST","curve":"EXP","passes":1,"muteValue":99}"#.utf8)
        let cc = try JSONDecoder().decode(EmitterCC.self, from: json)
        XCTAssertEqual(cc.ccNumber, 71); XCTAssertEqual(cc.low, 20); XCTAssertTrue(cc.on, "an old document's muteValue key is ignored, the rest loads")
    }
}
