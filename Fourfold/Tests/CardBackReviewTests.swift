//  CardBackReviewTests.swift — CARD BACKS adversarial review (2026-10-28, reviewer's sweeps adapted after the fixes). Pure sweeps over every view size the page lays out un-scaled (760×480 … 1376×1032 landscape, 480×760 … 1032×1376 portrait):
//  the back's geometry never overlaps itself or leaves the card EXCEPT where the layout's own floor list says so, the jack letter stays inside its cell, the XY pad's touch maths survives every pad height, and every header group stays inside its container.

import XCTest

final class CardBackReviewTests: XCTestCase {
    private func sizes() -> [CGSize] {
        var out: [CGSize] = []
        for w in stride(from: 760, through: 1376, by: 8) { for h in stride(from: 480, through: 1032, by: 8) where CGFloat(w) > CGFloat(h) { out.append(CGSize(width: w, height: h)) } }
        for w in stride(from: 480, through: 1032, by: 8) { for h in stride(from: 760, through: 1376, by: 8) where CGFloat(h) >= CGFloat(w) { out.append(CGSize(width: w, height: h)) } }
        return out.filter { !euclideousScaleToFit($0).scaled }
    }
    private func fmt(_ s: CGSize) -> String { "\(Int(s.width))x\(Int(s.height))" }

    /// The label pill fits inside the roll; the invitation pill (slid clear of the label) and its touch target never cover the label's — wherever the roll is at least `euclideousCardInvitationRollWidthFloor()` wide, which is exactly when the
    /// layout reports no "roll width" floor. Below it the overlap is allowed but must be REPORTED (a floor entry), and the invitation still stays inside the roll.
    func testTheInvitationClearsTheLabelWherePossibleAndTheFloorListSaysWhereItCannot() {
        var overlapsAtOrAboveFloor: [String] = [], overlapsBelowFloorUnreported: [String] = [], outsideRoll: [String] = [], belowFloor = 0
        for s in sizes() {
            let L = euclideousCardBackLayout(card: euclideousPageLayout(size: s).box)
            let reported = L.floors.contains { $0.name.hasPrefix("roll width") }
            for part in [EuclideousCardPart.riff, .notes] {
                let f = L.part(part)
                let roll = CGRect(x: 0, y: 0, width: f.roll.width, height: f.roll.height)
                let lab = euclideousCardLabelFrames(roll: roll, part: part)
                for kind in [EuclideousCardInvitation.addHits, part == .riff ? .turnOnRiff : .turnOnNotes] {
                    let inv = euclideousCardInvitationFrames(roll: roll, kind, avoiding: lab.pill)
                    let overlap = inv.pill.intersects(lab.pill) || inv.target.intersects(lab.target)
                    if inv.pill.minX < roll.minX - 1e-9 || inv.pill.maxX > roll.maxX + 1e-9 { if !reported { outsideRoll.append("\(fmt(s)) \(part) \(kind.label)") } }
                    if overlap && !reported { overlapsAtOrAboveFloor.append("\(fmt(s)) roll \(Int(roll.width))x\(Int(roll.height)) \(part) \(kind.label)") }
                    if overlap && reported { belowFloor += 1 }
                    if !overlap && reported && roll.width >= euclideousCardInvitationRollWidthFloor() { overlapsBelowFloorUnreported.append(fmt(s)) }
                }
            }
        }
        XCTAssertTrue(overlapsAtOrAboveFloor.isEmpty, "the invitation covers the label with no floor reported: \(overlapsAtOrAboveFloor.prefix(4))")
        XCTAssertTrue(outsideRoll.isEmpty, "the invitation leaves the roll with no floor reported: \(outsideRoll.prefix(4))")
        XCTAssertTrue(overlapsBelowFloorUnreported.isEmpty, "a floor is reported at a size wide enough: \(overlapsBelowFloorUnreported.prefix(3))")
        print("CARDBACKREVIEW invitation overlaps at floor-reported sizes: \(belowFloor)")
    }
    func testAnInvitationSlidesRightOfTheLabelAndStaysInTheRoll() {
        let roll = CGRect(x: 0, y: 0, width: 200, height: 57)
        let lab = euclideousCardLabelFrames(roll: roll, part: .notes)
        let centred = euclideousCardInvitationFrames(roll: roll, .turnOnNotes)
        XCTAssertTrue(centred.pill.intersects(lab.pill), "centred, it would cover the label at 200 pt")
        let slid = euclideousCardInvitationFrames(roll: roll, .turnOnNotes, avoiding: lab.pill)
        XCTAssertFalse(slid.pill.intersects(lab.pill)); XCTAssertGreaterThanOrEqual(slid.pill.minX, lab.pill.maxX + EuclideousCardInvitationMetrics.labelGap - 1e-9)
        XCTAssertLessThanOrEqual(slid.pill.maxX, roll.maxX - EuclideousCardLabelMetrics.inset + 1e-9)
        let wide = CGRect(x: 0, y: 0, width: 256, height: 57)
        XCTAssertEqual(euclideousCardInvitationFrames(roll: wide, .addHits, avoiding: euclideousCardLabelFrames(roll: wide, part: .riff).pill).pill,
                       euclideousCardInvitationFrames(roll: wide, .addHits).pill, "a roll with room keeps the invitation centred")
    }

    /// The jack letter stays inside its cell wherever the cell meets the floor (46 pt); below it the floor list says so.
    func testTheJackLetterFitsItsCellAtOrAboveTheFloor() {
        var bad: [String] = [], unreported: [String] = []
        for s in sizes() {
            let L = euclideousCardBackLayout(card: euclideousPageLayout(size: s).box)
            let cell = L.riff.jackCells[0], letter = L.riff.jackLetters[0]
            let overflow = letter.minX + EuclideousCardBackMetrics.letterAdvance > cell.maxX + 1e-9
            let reported = L.floors.contains { $0.name == "jack cell width" }
            if overflow && !reported { bad.append("\(fmt(s)) cell \(cell.width)") }
            if reported && cell.width >= EuclideousCardBackMetrics.floorJackCellWidth { unreported.append(fmt(s)) }
        }
        XCTAssertTrue(bad.isEmpty, "the letter overflows with no floor reported: \(bad.prefix(4))"); XCTAssertTrue(unreported.isEmpty)
    }
    func testTightCellsPullTheLightSocketAndLetterIn() {
        let wide = euclideousCardBackLayout(card: CGSize(width: 376, height: 316)).riff
        let tight = euclideousCardBackLayout(card: CGSize(width: 316, height: 316)).riff     // a 196 pt panel → 49 pt cells: wide enough for the floor, tight for the letter
        XCTAssertGreaterThanOrEqual(wide.jackCells[0].width, EuclideousCardBackMetrics.tightBelow); XCTAssertLessThan(tight.jackCells[0].width, EuclideousCardBackMetrics.tightBelow)
        XCTAssertEqual(wide.jackSockets[0].minX - wide.jackCells[0].minX, 18); XCTAssertEqual(tight.jackSockets[0].minX - tight.jackCells[0].minX, 13)
        XCTAssertLessThanOrEqual(tight.jackLetters[0].minX + EuclideousCardBackMetrics.letterAdvance, tight.jackCells[0].maxX + 1e-9)
        XCTAssertGreaterThan(tight.jackSockets[0].minX, tight.jackLights[0].maxX, "the light does not touch the socket")
    }

    /// `euclideousCardXYValues` used to divide by `pad.height − 14` and trap in `Int(…)` at a pad exactly 14 pt tall (it happens at real page heights). Every pad height from 0 to 200 and every touch point gives in-range values.
    func testTheXYPadTouchMathSurvivesEveryPadHeightAndWidth() {
        for h in stride(from: 0.0, through: 200.0, by: 0.5) {
            for w in [0.0, 14.0, 28.0, 92.0] {
                let pad = CGRect(x: 0, y: 0, width: w, height: h)
                for p in [CGPoint(x: -50, y: -50), CGPoint(x: 0, y: 0), CGPoint(x: w / 2, y: h / 2), CGPoint(x: w, y: h), CGPoint(x: 500, y: 500)] {
                    let v = euclideousCardXYValues(at: p, in: pad)
                    XCTAssertTrue((1...99).contains(Int((v.gate * 100).rounded())) && (1...127).contains(v.velocity), "pad \(w)x\(h) touch \(p): \(v)")
                }
            }
        }
    }

    /// Every header group stays inside its container at every width the page lays out un-scaled (portrait from 480 wide → container 448; landscape from 760), in whichever layout (A, B, C, or the three-row D) is chosen.
    func testEveryHeaderGroupStaysInsideTheContainerAtEveryUnscaledWidth() {
        var overflow: [String] = [], kinds = Set<String>()
        for view in stride(from: 480, through: 1376, by: 4) {
            for landscape in [false, true] {
                let size = landscape ? CGSize(width: CGFloat(view), height: 480 + CGFloat(view) / 4) : CGSize(width: CGFloat(view), height: 1100)
                if euclideousScaleToFit(size).scaled || landscape != (size.width > size.height) { continue }
                let p = euclideousPageLayout(size: size)
                let cw = size.width - 32
                let l = euclideousHeaderLayout(containerW: cw, isLandscape: p.isLandscape, riffLeadingX: p.riffLeadingX)
                kinds.insert("\(l.kind)")
                XCTAssertEqual(p.headerKind, l.kind, "the page and the header agree on the layout at \(view)")
                XCTAssertLessThanOrEqual(l.cardSwitch.row, l.rowCount - 1); XCTAssertLessThanOrEqual(l.notes.row, l.rowCount - 1)
                for (n, g) in [("brand", l.brand), ("notes", l.notes), ("utilities", l.utilities), ("cardSwitch", l.cardSwitch)] where g.x + g.width > cw + 1e-6 {
                    overflow.append("\(landscape ? "landscape" : "portrait") view \(view) (container \(Int(cw))): \(n) ends at \(Int(g.x + g.width)) (kind \(l.kind), row \(g.row))")
                }
            }
        }
        XCTAssertTrue(overflow.isEmpty, "a header group runs past the container: \(overflow.prefix(4))")
        XCTAssertEqual(kinds, ["a", "b", "c", "d"], "every layout is exercised")
    }
    func testLayoutDHasThreeRowsAndItsOwnTop() {
        let narrow = euclideousHeaderLayout(containerW: 480, isLandscape: false, riffLeadingX: 0)
        XCTAssertEqual(narrow.kind, .d); XCTAssertEqual(narrow.rowCount, 3); XCTAssertTrue(narrow.compact)
        XCTAssertEqual(narrow.height, 44 * 3 + 4 * 2)
        XCTAssertEqual([narrow.brand.row, narrow.utilities.row, narrow.cardSwitch.row, narrow.notes.row], [0, 0, 1, 2])
        XCTAssertEqual(EuclideousPageMetrics.top(.d), 159); XCTAssertEqual(EuclideousPageMetrics.top(.c), 111)
        XCTAssertEqual(euclideousHeaderKind(containerW: 549.9, isLandscape: false), .d); XCTAssertEqual(euclideousHeaderKind(containerW: 550, isLandscape: false), .c)
        XCTAssertEqual(euclideousHeaderKind(containerW: 587.88, isLandscape: false), .b)
    }
}
