//  LaneSoloTests.swift
//  LANE SOLO ferry (2026-10-21): the pure layer (`euclideousLaneMayStrike` / `…IsDimmed`, the press machine, tap vs hold, the look and the words) and the persistence of the latched mask (§8 tests 2, 7, 8).
//  The Router half (tests 1, 3-6, 9) lives in RouterTests.

import XCTest

final class LaneSoloTests: XCTestCase {
    // MARK: §8.2 — the truth table
    func testLaneMayStrikeTruthTable() {
        for lane in 0..<4 {
            for solo in UInt8(0)...15 {
                for muteAudible in [true, false] {
                    for enabled in [true, false] {
                        let silencedBySolo = solo != 0 && (solo >> UInt8(lane)) & 1 == 0
                        let want = enabled && muteAudible && !silencedBySolo
                        XCTAssertEqual(euclideousLaneMayStrike(lane: lane, soloMask: solo, muteAudible: muteAudible, enabled: enabled), want,
                                       "lane \(lane) solo \(solo) muteAudible \(muteAudible) enabled \(enabled)")
                    }
                }
            }
        }
    }
    func testSoloMaskZeroIsInertAndASoloedLaneIsNeverSilencedBySolo() {
        for lane in 0..<4 { XCTAssertFalse(euclideousSoloSilences(lane: lane, soloMask: 0)) }
        XCTAssertFalse(euclideousSoloSilences(lane: 1, soloMask: 0b0010)); XCTAssertTrue(euclideousSoloSilences(lane: 0, soloMask: 0b0010))
        XCTAssertFalse(euclideousSoloSilences(lane: 0, soloMask: 0b1001)); XCTAssertFalse(euclideousSoloSilences(lane: 3, soloMask: 0b1001))
        XCTAssertTrue(euclideousSoloSilences(lane: 1, soloMask: 0b1001)); XCTAssertTrue(euclideousSoloSilences(lane: 2, soloMask: 0b1001))
        XCTAssertFalse(euclideousSoloSilences(lane: 7, soloMask: 0b0001), "a lane index outside 0…3 is never silenced by solo")
        XCTAssertEqual(euclideousSoloSilencedLanes(soloMask: 0b0101), [false, true, false, true])
    }
    func testTheEffectiveMaskIsLatchedOrHeldInFourBits() {
        XCTAssertEqual(euclideousSoloEffective(latched: 0b0001, held: 0b0100), 0b0101)
        XCTAssertEqual(euclideousSoloEffective(latched: 0, held: 0), 0)
        XCTAssertEqual(euclideousSoloEffective(latched: 0xF1, held: 0x10), 0b0001, "only the four lane bits count")
    }
    /// The displays' question is the engine's with the play state taken out: a dimmed lane is exactly a lane that could not strike if it were playing — and one dim, however many reasons.
    func testTheDisplayDimEqualsTheEnginesAnswerWithTheStopStateRemoved() {
        for lane in 0..<4 { for solo in UInt8(0)...15 { for muteAudible in [true, false] {
            let dim = euclideousLaneIsDimmed(lane: lane, soloMask: solo, muteAudible: muteAudible)
            XCTAssertEqual(dim, !euclideousLaneMayStrike(lane: lane, soloMask: solo, muteAudible: muteAudible, enabled: true))
            XCTAssertEqual(dim, euclideousSoloSilences(lane: lane, soloMask: solo) || !muteAudible, "one flag: muted OR solo-silenced, never a product")
        } } }
        XCTAssertEqual(EuclideousLaneDimStyle.opacity, 0.42); XCTAssertEqual(EuclideousLaneDimStyle.easeSeconds, 0.15)
    }

    // MARK: §8.8 — tap versus hold
    func testTapVersusHoldAtDurations0And299And300Milliseconds() {
        for (before, secs, after, why) in [(false, 0.0, true, "off + tap → on"), (true, 0.0, false, "on + tap → off"), (false, 0.299, true, "off + 299 ms is still a tap"), (true, 0.299, false, "on + 299 ms is a tap"),
                                            (false, 0.300, false, "off + hold → off"), (true, 0.300, true, "on + hold → on"), (false, 2.5, false, "a long hold on an unlatched lane"), (true, 2.5, true, "a long hold on a latched lane")] {
            XCTAssertEqual(euclideousSoloLatchAfter(latchedBefore: before, pressSeconds: secs), after, why)
        }
        XCTAssertEqual(EuclideousRingPress.holdSeconds, 0.3, "the header rings' threshold, shared")
    }
    func testThePressMachineDecidesByDurationAndCountsASlideOffAndACancel() {
        var p = EuclideousSoloPress()
        XCTAssertEqual(p.touchEnded(at: 1), .none, "a lift with no touch is nothing")
        p.touchDown(at: 10)
        XCTAssertTrue(p.down); XCTAssertFalse(p.showsHeldLook, "the held look waits for 300 ms")
        XCTAssertEqual(p.touchEnded(at: 10.1), .ended(latchToggles: true), "a short touch is a tap — wherever the finger lifts (a slide-off is not a cancel)")
        XCTAssertFalse(p.down)
        p.touchDown(at: 20); p.holdTimerFired()
        XCTAssertTrue(p.showsHeldLook, "from 300 ms until release")
        XCTAssertEqual(p.touchEnded(at: 20.31), .ended(latchToggles: false), "a hold never toggles")
        XCTAssertFalse(p.showsHeldLook)
        p.touchDown(at: 30)   // the timer never ran (a stalled main thread): the clock still says hold
        XCTAssertEqual(p.touchEnded(at: 30.3), .ended(latchToggles: false))
        p.touchDown(at: 40)
        XCTAssertEqual(p.touchEnded(at: 40.299), .ended(latchToggles: true))
        p.touchDown(at: 50); XCTAssertEqual(p.touchCancelled(), .ended(latchToggles: false), "a cancelled touch ends as a hold would — it never toggles")
        XCTAssertEqual(p.touchCancelled(), .none)
        p.holdTimerFired(); XCTAssertFalse(p.showsHeldLook, "a timer firing with no touch down does nothing")
    }
    func testTwoButtonsAreTwoIndependentMachines() {
        var a = EuclideousSoloPress(), b = EuclideousSoloPress()
        a.touchDown(at: 0); b.touchDown(at: 0.05)
        b.holdTimerFired()
        XCTAssertFalse(a.showsHeldLook); XCTAssertTrue(b.showsHeldLook)
        XCTAssertEqual(a.touchEnded(at: 0.2), .ended(latchToggles: true)); XCTAssertEqual(b.touchEnded(at: 0.9), .ended(latchToggles: false))
    }

    // MARK: §2.3 / §7 — the look and the words
    func testTheLookIsOffLatchedOrHeldAndHeldWins() {
        XCTAssertEqual(euclideousSoloButtonLook(latched: false, heldLook: false), .off)
        XCTAssertEqual(euclideousSoloButtonLook(latched: true, heldLook: false), .latched)
        XCTAssertEqual(euclideousSoloButtonLook(latched: false, heldLook: true), .held)
        XCTAssertEqual(euclideousSoloButtonLook(latched: true, heldLook: true), .held, "held, whether or not it was latched")
    }
    func testTheWords() {
        XCTAssertEqual(euclideousSoloAccessibilityLabel(lane: 0), "Solo lane 1"); XCTAssertEqual(euclideousSoloAccessibilityLabel(lane: 3), "Solo lane 4")
        XCTAssertEqual(euclideousSoloAccessibilityValue(latched: true), "on"); XCTAssertEqual(euclideousSoloAccessibilityValue(latched: false), "off")
        XCTAssertEqual(euclideousSoloAccessibilityHint, "Tap to latch; hold to solo while held")
        XCTAssertEqual(euclideousAppendSilencedBySolo("on step 5", silenced: true), "on step 5, silenced by solo")
        XCTAssertEqual(euclideousAppendSilencedBySolo("on step 5", silenced: false), "on step 5")
        XCTAssertEqual(euclideousAppendSilencedBySolo("", silenced: true), "silenced by solo")
    }

    // MARK: §8.7 — persistence
    func testTheLatchedMaskRoundTripsAndAPreFeatureDocumentResolvesToNoSolo() throws {
        var st = PluginState(machines: [], scenes: [])
        XCTAssertNil(st.euclideousSoloMask); XCTAssertEqual(st.euclideousSoloMaskResolved, 0, "a new document stores no solo")
        st.euclideousSoloMask = 0b0101
        let data = try JSONEncoder().encode(st)
        let back = try JSONDecoder().decode(PluginState.self, from: data)
        XCTAssertEqual(back.euclideousSoloMask, 0b0101); XCTAssertEqual(back.euclideousSoloMaskResolved, 0b0101)
        // a document written before the feature (no key at all)
        var obj = try JSONSerialization.jsonObject(with: JSONEncoder().encode(PluginState(machines: [], scenes: []))) as! [String: Any]
        obj.removeValue(forKey: "euclideousSoloMask")
        let old = try JSONDecoder().decode(PluginState.self, from: JSONSerialization.data(withJSONObject: obj))
        XCTAssertNil(old.euclideousSoloMask); XCTAssertEqual(old.euclideousSoloMaskResolved, 0, "a pre-feature document sounds as before")
        var wild = PluginState(machines: [], scenes: []); wild.euclideousSoloMask = 0xFF
        XCTAssertEqual(wild.euclideousSoloMaskResolved, 0x0F, "four lane bits")
    }
    func testTheHeldMaskIsNeverSavedAndLaneDataCarriesNoSolo() throws {
        var st = PluginState(machines: [], scenes: []); st.euclideousSoloMask = 0b0010
        let json = String(decoding: try JSONEncoder().encode(st), as: UTF8.self).lowercased()
        XCTAssertFalse(json.contains("soloheld") || json.contains("solo_held") || json.contains("heldsolo"), "the held solo is UI state only")
        for c in Mirror(reflecting: st).children { XCTAssertFalse((c.label ?? "").lowercased().contains("held") && (c.label ?? "").lowercased().contains("solo"), c.label ?? "?") }
        // solo travels where the main-out mask travels and nowhere else: not in a lane's data (so a lane copy, were there one, couldn't carry it)
        for c in Mirror(reflecting: EuclidLine()).children { XCTAssertFalse((c.label ?? "").lowercased().contains("solo"), "EuclidLine.\(c.label ?? "?")") }
    }
    func testTheMaskReachesSnapParamsThroughTheBuilderInFourBits() {
        var m = Machine(machineID: "gold", type: .euclid)
        m.paramsA.soloMask = 0xFF
        let sc = SceneState.empty()
        let built = SnapshotBuilder.build(from: PluginState(machines: [m], scenes: [sc]))
        XCTAssertEqual(built.machines.first { $0.a.euclidLines.count == 4 }?.a.soloMask ?? 0, 0x0F)
        var none = Machine(machineID: "gold", type: .euclid); none.paramsA.soloMask = nil
        XCTAssertEqual(SnapshotBuilder.build(from: PluginState(machines: [none], scenes: [sc])).machines.first { $0.a.euclidLines.count == 4 }?.a.soloMask ?? 0, 0, "nil ⇒ no solo")
    }
}
