//  EmitterTokenTests.swift — EMITTER TOKEN ferry (2026-11-07): the pure token layer (`EmitterToken.swift`). Test 1 = geometry at 22 / 28 / 36 (§1); test 2 = the looks (§2) + the two state selectors (§3.4 / §2.3).
//  Mutation-checked where it counts: the look cases are asserted by exact ink, so a changed colour fails here.

import XCTest

final class EmitterTokenTests: XCTestCase {
    private func close(_ a: CGFloat, _ b: CGFloat, _ msg: String = "", file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertEqual(a, b, accuracy: 0.0005, msg, file: file, line: line)
    }

    // MARK: test 1 — geometry (§1.1–1.3)

    func testGeometryAt22() {
        let g = euclideousEmitterTokenGeom(.d22)
        close(g.diameter, 22); close(g.ringWidth, 2); close(g.ringRadius, 10, "D/2 − w/2"); close(g.letterSize, 8)
        close(g.gap, 4); close(g.gapAngle, 4.0 / 10.0, "g ÷ ringRadius")
        close(g.keySide, 2.5); close(g.keyRadius, 0.5)
        close(g.keyRect.minY, 3, "top 1 pt below the inner edge (w + 1)")
        close(g.keyRect.midX, 11, "centred horizontally (D/2)")
        close(g.keyRect.width, 2.5); close(g.keyRect.height, 2.5)
    }
    func testGeometryAt28() {
        let g = euclideousEmitterTokenGeom(.d28)
        close(g.diameter, 28); close(g.ringWidth, 2); close(g.ringRadius, 13); close(g.letterSize, 11)
        close(g.gap, 5); close(g.gapAngle, 5.0 / 13.0)
        close(g.keySide, 3); close(g.keyRect.minY, 3); close(g.keyRect.midX, 14)
    }
    func testGeometryAt36() {
        let g = euclideousEmitterTokenGeom(.d36)
        close(g.diameter, 36); close(g.ringWidth, 3); close(g.ringRadius, 16.5, "D/2 − w/2 = 18 − 1.5"); close(g.letterSize, 14)
        close(g.gap, 6); close(g.gapAngle, 6.0 / 16.5)
        close(g.keySide, 3.5); close(g.keyRect.minY, 4, "w + 1 = 3 + 1"); close(g.keyRect.midX, 18)
    }
    func testTheGapIsCentredOnTwelveOClockAndTheKeySitsInIt() {
        for s in [EuclideousEmitterTokenSize.d22, .d28, .d36] {
            let g = euclideousEmitterTokenGeom(s)
            // the key is centred horizontally in the box (the gap's centre line) and above the centre (in the gap at the top)
            close(g.keyRect.midX, g.diameter / 2)
            XCTAssertLessThan(g.keyRect.maxY, g.center.y, "the key sits in the top gap, above the centre")
        }
    }

    // MARK: test 2 — looks (§2.1 emitter, §2.3 routing) and that a dashed ring keeps the gap

    func testEmitterLive() {
        let p = euclideousEmitterTokenPaint(.live, size: .d36)
        XCTAssertEqual(p.disc, .hex(0x2A2D34, 1))
        XCTAssertEqual(p.ring, .hex(0xDFE3EA, 1))
        XCTAssertEqual(p.key, .hex(0xDFE3EA, 1))
        XCTAssertEqual(p.letter, .hex(0xF2F4F7, 1))
        close(p.ringWidth, 3); XCTAssertFalse(p.dashed); XCTAssertEqual(p.flare, 0)
    }
    func testEmitterUnused() {
        let p = euclideousEmitterTokenPaint(.unused, size: .d28)
        XCTAssertEqual(p.disc, .hex(0x2A2D34, 1))
        XCTAssertEqual(p.ring, .hex(0x3A3E47, 1))
        XCTAssertEqual(p.key, .hex(0x3A3E47, 1))
        XCTAssertEqual(p.letter, .hex(0x8A909A, 1))
        XCTAssertFalse(p.dashed)
    }
    func testEmitterMutedNoDiscDashedAndNeverPlays() {
        let p = euclideousEmitterTokenPaint(.muted, size: .d36)
        XCTAssertEqual(p.disc, .none, "no disc — the surface shows through")
        XCTAssertEqual(p.ring, .hex(0x5C626C, 1)); close(p.ringWidth, 2, "muted ring is 2 pt whatever the size")
        XCTAssertTrue(p.dashed, "a dashed ring keeps the gap")
        XCTAssertEqual(p.key, .hex(0x5C626C, 1))
        XCTAssertEqual(p.letter, .hex(0x5C626C, 1))
        XCTAssertEqual(p.flare, 0, "muted never plays")
    }
    func testEmitterPlayingIsTheLiveBasePlusAFlare() {
        let p = euclideousEmitterTokenPaint(.playing(0.5), size: .d36)
        XCTAssertEqual(p.ring, .hex(0xDFE3EA, 1), "base ring stays white; the lane ring is the flare overlay")
        XCTAssertEqual(p.disc, .hex(0x2A2D34, 1))
        XCTAssertEqual(p.flare, 0.5)
    }
    func testRoutingRouted() {
        let p = euclideousEmitterTokenPaint(.routed, size: .d22)
        XCTAssertEqual(p.disc, .lane(0.2), "source EuclideousPartOutDiscArt fills lane @ 20 % (ferry said 18 %)")
        XCTAssertEqual(p.ring, .lane(1))
        XCTAssertEqual(p.key, .lane(1))
        XCTAssertEqual(p.letter, .hex(0xF2F4F7, 1))
        XCTAssertFalse(p.dashed)
    }
    func testRoutingNotRouted() {
        let p = euclideousEmitterTokenPaint(.notRouted, size: .d22)
        XCTAssertEqual(p.disc, .none)
        XCTAssertEqual(p.ring, .hex(0x3A3E47, 1), "source off-ring is #3A3E47 (ferry said #4A4E57)")
        XCTAssertEqual(p.key, .hex(0x3A3E47, 1))
        XCTAssertEqual(p.letter, .hex(0x8A909A, 1))
    }
    func testRoutingRoutedButOutputMuted() {
        let p = euclideousEmitterTokenPaint(.routedMuted, size: .d28)
        XCTAssertEqual(p.disc, .none)
        XCTAssertEqual(p.ring, .lane(0.45)); XCTAssertTrue(p.dashed)
        XCTAssertEqual(p.key, .lane(0.45))
        XCTAssertEqual(p.letter, .hex(0x8A909A, 1))
    }

    // MARK: the state selectors (§3.4, §2.3)

    func testEmitterStateSelector() {
        XCTAssertEqual(euclideousEmitterTokenEmitterState(muted: true, activity: 0.9, anyRouted: true), .muted, "muted wins and never plays")
        XCTAssertEqual(euclideousEmitterTokenEmitterState(muted: false, activity: 0.3, anyRouted: true), .playing(0.3))
        XCTAssertEqual(euclideousEmitterTokenEmitterState(muted: false, activity: 0, anyRouted: true), .live)
        XCTAssertEqual(euclideousEmitterTokenEmitterState(muted: false, activity: 0, anyRouted: false), .unused)
    }
    func testRoutingStateSelector() {
        XCTAssertEqual(euclideousEmitterTokenRoutingState(routed: false, outputMuted: true), .notRouted, "a not-routed circle ignores the output's mute")
        XCTAssertEqual(euclideousEmitterTokenRoutingState(routed: true, outputMuted: false), .routed)
        XCTAssertEqual(euclideousEmitterTokenRoutingState(routed: true, outputMuted: true), .routedMuted)
    }

    // MARK: test 5 — §5.1: the MIX tap full-toggles the mute; the hold uses the shared 300 ms threshold

    func testTheMixTapFullToggle() {
        XCTAssertEqual(euclideousOutputMuteFullToggle(0xFFFF), 0x0000, "fully sounding → fully muted")
        XCTAssertEqual(euclideousOutputMuteFullToggle(0x0000), 0xFFFF, "fully muted → fully sounding")
        XCTAssertEqual(euclideousOutputMuteFullToggle(0b1010_1010_1010_1010), 0xFFFF, "a partial MUTE-tab pattern unmutes to fully sounding")
        var m = EuclideousOutputMute(cells16: 0b0000_1111_0000_1111, passes: 3)
        XCTAssertTrue(m.hasMute)
        m = m.toggledFull(); XCTAssertEqual(m.cells16, 0xFFFF); XCTAssertEqual(m.passes, 3, "the pass ladder is untouched"); XCTAssertFalse(m.hasMute)
        m = m.toggledFull(); XCTAssertEqual(m.cells16, 0x0000, "a second tap mutes it fully"); XCTAssertTrue(m.hasMute)
    }
    func testTheHoldThresholdIsTheSharedValue() {
        XCTAssertEqual(EuclideousRingPress.holdSeconds, 0.3, "the MIX emitter hold reuses the project's 300 ms hold convention")
    }
}
