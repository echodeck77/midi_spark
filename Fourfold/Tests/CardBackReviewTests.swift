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
                for kind in [EuclideousCardInvitation.addHits] {   // the only invitation the roll offers (CARD BACKS v2)
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

    /// CARD BACKS v2: at every size the page lays out un-scaled the two pads and the roll panel sit side by side inside the row without overlapping; the pads give way (72 → 44) BEFORE the roll panel drops under 176; the jack targets are
    /// bottom-aligned with the row, as wide as their cell, and never run past it; a socket fits its cell wherever the cell is as wide as the socket.
    func testThePadsGiveWayBeforeTheRollAndNothingOverlapsAtAnyLayout() {
        var bad: [String] = [], padsShrunk = 0, rollUnder = 0
        for s in sizes() {
            let L = euclideousCardBackLayout(card: euclideousPageLayout(size: s).box)
            for f in [L.riff, L.notes] {
                if !(f.velGate.maxX < f.pitch.minX && f.pitch.maxX < f.rollPanel.minX && f.rollPanel.maxX <= f.row.maxX + 1e-9) { bad.append("\(fmt(s)) row order") }
                if f.velGate.width < 44 - 1e-9 || abs(f.velGate.width - f.pitch.width) > 1e-9 { bad.append("\(fmt(s)) pads \(f.velGate.width) / \(f.pitch.width)") }
                if f.velGate.width < 72 - 1e-9 { padsShrunk += 1; if f.velGate.width > 44 + 1e-9 && abs(f.rollPanel.width - 176) > 1e-6 { bad.append("\(fmt(s)) pads give way but the panel is \(f.rollPanel.width), not 176") } }
                if f.rollPanel.width < 176 - 1e-6 { rollUnder += 1; if f.velGate.width > 44 + 1e-9 { bad.append("\(fmt(s)) the roll panel narrowed below 176 with the pads still above their floor") } }
                for i in 0..<4 {
                    let c = f.jackCells[i], t = f.jackTargets[i], k = f.jackSockets[i]
                    if abs(t.maxY - f.row.maxY) > 1e-9 || abs(t.height - 44) > 1e-9 || abs(t.minX - c.minX) > 1e-9 || abs(t.width - c.width) > 1e-9 { bad.append("\(fmt(s)) target \(i) \(t)") }
                    if c.width >= 22 && (k.minX < c.minX - 1e-9 || k.maxX > c.maxX + 1e-9) { bad.append("\(fmt(s)) socket \(i) outside its cell") }
                    if abs(k.midX - c.midX) > 1e-9 || abs(k.midY - c.midY) > 1e-9 { bad.append("\(fmt(s)) socket \(i) not centred") }
                }
                // the label's 32-tall target (from the roll's top-left) and the jack targets (the bottom 44 of the row) only meet where the row is shorter than 76
                let lab = euclideousCardLabelFrames(roll: CGRect(origin: .zero, size: f.roll.size), part: .riff).target.offsetBy(dx: f.roll.minX, dy: f.roll.minY)
                if f.row.height >= 76 && lab.intersects(f.jackTargets[0]) { bad.append("\(fmt(s)) the label's target meets a jack's at rowH \(f.row.height)") }
            }
        }
        XCTAssertTrue(bad.isEmpty, "\(bad.prefix(5))")
        print("CARDBACKREVIEW sizes with the pads shrunk: \(padsShrunk), with the roll panel under 176: \(rollUnder)")
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

    /// Every header group stays inside its container at every width the page lays out un-scaled (portrait from 480 wide → container 448; landscape from 760), in whichever layout (A, B or C) is chosen. (TAB STRIP 2026-10-29: the three-row D is retired.)
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
                XCTAssertLessThanOrEqual(l.notes.row, l.rowCount - 1)
                for (n, g) in [("brand", l.brand), ("notes", l.notes), ("utilities", l.utilities)] where g.x + g.width > cw + 1e-6 {
                    overflow.append("\(landscape ? "landscape" : "portrait") view \(view) (container \(Int(cw))): \(n) ends at \(Int(g.x + g.width)) (kind \(l.kind), row \(g.row))")
                }
            }
        }
        XCTAssertTrue(overflow.isEmpty, "a header group runs past the container: \(overflow.prefix(4))")
        XCTAssertEqual(kinds, ["a", "b", "c"], "every layout the ladder chooses is exercised")
    }
    /// TAB STRIP (2026-10-29): the three-row D existed to give the PATTERN | MIX switch its own row; the ladder never chooses it now (its layout code and top stay, unreachable).
    func testTheLadderNeverChoosesTheRetiredThreeRowLayout() {
        let narrow = euclideousHeaderLayout(containerW: 400, isLandscape: false, riffLeadingX: 0)
        XCTAssertEqual(narrow.kind, .c); XCTAssertEqual(narrow.rowCount, 2); XCTAssertTrue(narrow.compact)
        XCTAssertEqual([narrow.brand.row, narrow.utilities.row, narrow.notes.row], [0, 0, 1])
        XCTAssertEqual(EuclideousPageMetrics.top(.d), 159); XCTAssertEqual(EuclideousPageMetrics.top(.c), 111)
        XCTAssertEqual(euclideousHeaderKind(containerW: 483.8, isLandscape: false), .c); XCTAssertEqual(euclideousHeaderKind(containerW: 483.88, isLandscape: false), .b)
    }
}
