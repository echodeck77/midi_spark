//  PlayButtonsAmendmentTests.swift — PLAY RIFF / PLAY STACK, amendment 1 (2026-11-08): the lane card's frame function (§A1, test 1), the strip's reserved bands (§A2, test 2), the button's type (§A3, test 3), its looks (§A4, test 4)
//  and the ANSWER line (§A5). All pure functions in Derivations.swift.

import XCTest

final class PlayButtonsAmendmentTests: XCTestCase {
    private func close(_ a: CGFloat, _ b: CGFloat, _ msg: String = "", file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertEqual(Double(a), Double(b), accuracy: 0.0005, msg, file: file, line: line)
    }
    private func closeD(_ a: Double, _ b: Double, _ msg: String = "", accuracy: Double = 0.0005, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertEqual(a, b, accuracy: accuracy, msg, file: file, line: line)
    }

    /// The page sizes the project tests at (the iPads and the windowed AUM / Stage Manager sizes) — the lane card's size at each is what the frame function takes.
    private let pageSizes: [(String, CGSize)] = [("1376×1032", CGSize(width: 1376, height: 1032)), ("1366×1024", CGSize(width: 1366, height: 1024)), ("1194×834", CGSize(width: 1194, height: 834)), ("1190×726 (ref)", CGSize(width: 1190, height: 726)),
                                                  ("1180×820", CGSize(width: 1180, height: 820)), ("1133×744 (mini)", CGSize(width: 1133, height: 744)), ("1113×683", CGSize(width: 1113, height: 683)), ("1113×636", CGSize(width: 1113, height: 636)),
                                                  ("1024×768", CGSize(width: 1024, height: 768)), ("900×600 window", CGSize(width: 900, height: 600)), ("834×1210", CGSize(width: 834, height: 1210)), ("814×1102 (ref)", CGSize(width: 814, height: 1102)),
                                                  ("768×1024", CGSize(width: 768, height: 1024)), ("744×1133 (mini)", CGSize(width: 744, height: 1133)), ("700×900 window", CGSize(width: 700, height: 900)), ("600×900 window", CGSize(width: 600, height: 900)),
                                                  ("500×900 window", CGSize(width: 500, height: 900)), ("300×700 window", CGSize(width: 300, height: 700))]

    // MARK: test 1 — the frame function (§A1)

    /// Equal insets on all four sides; PLAY RIFF on the content box's leading edge and PLAY STACK on its trailing edge; g between each button and the strip and from the top row to the body; the buttons exactly as tall as the strip; with a badge
    /// the strip ends g before it and the badge sits g before PLAY STACK. At the two references and at every page layout, with and without a lock badge. (The portrait reference's card is also the card in a portrait AUM window: a window under
    /// 814 wide renders the page at the reference and scales it, so the card — and every frame here — is the same 387 × 301.67.)
    func testTheFramesAtEveryLayout() {
        var cards: [(String, CGSize)] = [("landscape ref card", CGSize(width: 380.67, height: 301)), ("portrait ref card (also the portrait AUM window's)", CGSize(width: 387, height: 301.67))]
        for (name, size) in pageSizes { cards.append((name, euclideousPageLayout(size: size).laneBox)) }
        var table: [String] = []
        func f(_ v: CGFloat) -> String { String(format: "%.2f", Double(v)) }
        for (name, card) in cards {
            for badge in [false, true] {
                let m = "\(name) badge \(badge)"
                let F = euclideousLaneCardFrames(card: card, withBadge: badge)
                let g = EuclideousLaneCardMetrics.columnGap
                close(g, 4, "g is the tab bodies' column gap, sp4")
                // equal inset on all four sides of the content box
                close(F.content.minX, 10, m); close(F.content.minY, 10, m); close(card.width - F.content.maxX, 10, m); close(card.height - F.content.maxY, 10, m)
                // the buttons sit on the content box's edges — the tab bodies' outer edges
                close(F.lead.minX, F.content.minX, m); close(F.trail.maxX, F.content.maxX, m); close(F.body.minX, F.content.minX, m); close(F.body.maxX, F.content.maxX, m)
                XCTAssertEqual(F.lead.width, 44); XCTAssertEqual(F.trail.width, 44)
                // g either side of the strip; with a badge, g between the strip and the badge and g between the badge and PLAY STACK
                close(F.strip.minX - F.lead.maxX, g, m)
                if let b = F.badge {
                    // (a card too narrow to leave the strip its 1 pt floor — the 300×700 window's 130 pt card with a badge — overlaps by arithmetic; the page floors flag that layout)
                    if F.strip.width > 1 { close(b.minX - F.strip.maxX, g, "\(m): the strip ends g before the badge") }
                    close(F.trail.minX - b.maxX, g, "\(m): the badge sits g before PLAY STACK")
                    close(b.width, 34); close(b.height, 34); close(b.midY, F.strip.midY, "the badge is centred on the row")
                    close(F.badgeTouch?.height ?? 0, F.T, "the badge's touch target is the row's full height")
                } else {
                    close(F.trail.minX - F.strip.maxX, g, m)
                }
                // both buttons and the strip are T tall, T the strip's full height with every band reserved, and share the row's top and bottom
                close(F.T, EuclideousStripMetrics.stripH, m); close(F.T, 44, m)
                for r in [F.lead, F.strip, F.trail] { close(r.height, F.T, m); close(r.minY, F.topRow.minY, m); close(r.maxY, F.topRow.maxY, m) }
                // g under the row, and the body runs to the content box's bottom
                close(F.body.minY - F.topRow.maxY, g, m); close(F.body.maxY, F.content.maxY, m)
                close(F.body.height, EuclideousLaneCardMetrics.contentAreaH(cardHeight: card.height), "\(m): the tab body's height is contentAreaH")
                XCTAssertGreaterThan(F.strip.width, 0)
                // the strip's width is the one `EuclideousLockBadge` and the lane box compute
                close(F.strip.width, EuclideousLockBadge.cometStripWidth(innerWidth: card.width - 20, withBadge: badge), m)
            }
            let a = euclideousLaneCardFrames(card: card, withBadge: false), b = euclideousLaneCardFrames(card: card, withBadge: true)
            let oldContentH = card.height - 72, newContentH = EuclideousLaneCardMetrics.contentAreaH(cardHeight: card.height)
            table.append("PLAYAMEND-LAYOUT \(name): card \(f(card.width))×\(f(card.height)) inset 10 g \(f(a.g)) T \(f(a.T)) buttons 44/44 strip \(f(a.strip.width)) (badge \(f(b.strip.width))) | body top \(f(a.body.minY)) (was 62) h \(f(newContentH)) (was \(f(oldContentH))) | RHYTHM upper \(f(newContentH - 84)) (was \(f(oldContentH - 84)))")
        }
        print(table.joined(separator: "\n"))
    }
    /// The two references, exactly: strip 264.67 / 226.67 (landscape) and 271 / 233 (portrait); the body starts at y 58; the RHYTHM upper zone is 149 / 149.67 (was 145 / 145.67) and the 192 pt floor does not trip.
    func testTheReferenceNumbers() {
        let land = CGSize(width: 380.67, height: 301), port = CGSize(width: 387, height: 301.67)
        close(euclideousLaneCardFrames(card: land, withBadge: false).strip.width, 264.67); close(euclideousLaneCardFrames(card: land, withBadge: true).strip.width, 226.67)
        close(euclideousLaneCardFrames(card: port, withBadge: false).strip.width, 271); close(euclideousLaneCardFrames(card: port, withBadge: true).strip.width, 233)
        close(EuclideousLaneCardMetrics.bodyTop, 58); close(EuclideousLaneCardMetrics.chromeH, 68)
        close(EuclideousLaneCardMetrics.contentAreaH(cardHeight: land.height) - 80 - 4, 149); close(EuclideousLaneCardMetrics.contentAreaH(cardHeight: port.height) - 80 - 4, 149.67)
        XCTAssertGreaterThan(EuclideousLaneCardMetrics.contentAreaH(cardHeight: land.height), EuclideousLaneCardMetrics.rhythmZonesFloor, "RHYTHM's 192 pt floor holds with room to spare")
        // the badge: x unchanged (g was already 4 before PLAY STACK), 34 × 34 centred on the row
        close(EuclideousLockBadge.frame(cardWidth: 380.67).minX, 288.67, "badge x = 380.67 − 10 − 44 − 4 − 34")
        close(EuclideousLockBadge.frame(cardWidth: 387).minX, 295)
    }

    // MARK: test 2 — the strip reserves the same bands on every lane (§A2)

    /// The strip's cell rows and key rows are fixed rectangles: the cells y 0 h 27, a 3 pt gap, the note keys y 30 h 14 — their sum is the card's top row T. They take no input but the columns' x and width, so no lane, tab, setting or
    /// moment of playback can move or resize them, and a lane with nothing drawn shows empty bands.
    func testTheStripReservesTheSameBandsEverywhere() {
        let xs: [CGFloat] = (0..<16).map { CGFloat($0) * 20 }
        for n in [2, 5, 8, 12, 16] {
            let frames = euclideousStripLayout(xs: Array(xs.prefix(n)), columnW: 18)
            XCTAssertEqual(frames.count, n)
            for fr in frames {
                close(fr.column.minY, 0); close(fr.column.height, 27)
                close(fr.key.minY, 30); close(fr.key.height, 14); close(fr.key.maxY, EuclideousLaneCardMetrics.cometRowH, "the key row ends at T")
            }
        }
        close(EuclideousStripMetrics.stripH, EuclideousLaneCardMetrics.cometRowH, "cells 27 + gap 3 + note keys 14 = the top row")
        // the four lanes' frames are one function of the card — identical for any lane, with or without a badge on the others
        let card = CGSize(width: 380.67, height: 301)
        let lanes = (0..<4).map { _ in euclideousLaneCardFrames(card: card, withBadge: false) }
        for l in lanes { XCTAssertEqual(l, lanes[0]) }
        // eight bars of playback: the frame function has no time input at all; the same call returns the same strip
        var seen = Set<CGFloat>()
        for _ in 0..<8 { seen.insert(euclideousLaneCardFrames(card: card, withBadge: false).strip.height) }
        XCTAssertEqual(seen, [44])
    }

    // MARK: test 3 — the type (§A3)

    /// COMPACT+STRIP STYLE §4.2 (2026-11-26): the type is FIXED now (the h-derived amendment-1 formula is retired — the strip's
    /// buttons are the same size at the card's 44 and the Compact panel's 50). PLAY 7 pt / 0.12 em; RIFF 10 pt / 0.08 em, STACK
    /// 9 pt / 0.05 em; the lamp from PLAY's size (7.5 × 7); lamp gap 4; line gap 3; the stopped triangle 1.1 pt.
    func testTheTypeSizes() {
        for h: CGFloat in [44, 50, 78] {
            let riff = euclideousPartPlayType(height: h, isNotes: false), stack = euclideousPartPlayType(height: h, isNotes: true)
            close(riff.playSize, 7); close(stack.playSize, 7)
            close(riff.nameSize, 10, "RIFF 10 pt"); close(stack.nameSize, 9, "STACK 9 pt")
            closeD(Double(riff.nameTracking), 0.08 * 10); closeD(Double(stack.nameTracking), 0.05 * 9)
            closeD(Double(riff.playTracking), 0.12 * 7); closeD(Double(riff.playLineH), 1.1 * 7); closeD(Double(riff.nameLineH), 1.06 * 10)
            close(riff.lampGap, 4); close(riff.lineGap, 3); close(riff.lampStroke, 1.1, "§4.2 stopped triangle"); close(riff.lampH, 7.5); close(riff.lampW, 7)
            XCTAssertGreaterThan(riff.nameSize, riff.playSize, "the part name is the largest text on the button (h \(h))")
        }
    }
    /// A3.2's size at every layout: the button is 44 tall everywhere (the top row is T = 44 at every card size), so every layout takes the h 44 sizes. And the name's width in the 44-wide tile (A3.4): "STACK" at 9.5 pt needs ≈ 31 pt; at h 78 the
    /// same 44-wide tile would need ≈ 55 (it would truncate) — reported by this estimate, a monospaced advance of 0.6 em plus the tracking.
    func testTheTypeAtEveryLayoutAndTheNameWidth() {
        for (_, size) in pageSizes {
            let card = euclideousPageLayout(size: size).laneBox
            let F = euclideousLaneCardFrames(card: card, withBadge: false)
            XCTAssertEqual(euclideousPartPlayType(height: F.lead.height, isNotes: false), euclideousPartPlayType(height: 44, isNotes: false), "§4.2 fixed, same at every layout")
        }
        func stackWidth(_ t: EuclideousPartPlayType) -> Double { 5 * Double(0.6 * t.nameSize + t.nameTracking) }
        XCTAssertLessThan(stackWidth(euclideousPartPlayType(height: 44, isNotes: true)), 42, "STACK (9 pt) fits the 44 pt tile")
        print("PLAYAMEND-TYPE STACK needs ≈ \(String(format: "%.1f", stackWidth(euclideousPartPlayType(height: 44, isNotes: true)))) pt (§4.2 fixed 9 pt)")
    }

    // MARK: test 4 — the looks (§A4)

    func testTheTileNeverChangesAndTheOffLooksAreTheRatifiedGreys() {
        let on = euclideousPartPlayLook(on: true), off = euclideousPartPlayLook(on: false)
        // The shared `euclideousPartPlayLook` is UNCHANGED (the FILL-tab tiles read it); COMPACT+STRIP STYLE §4.2 restyles the
        // strip's buttons in the view only (fill #25272C/lane100@14 %, no outline, radius 7, fixed 1.1 pt stopped triangle).
        XCTAssertEqual(EuclideousPartPlayLook.tileStrokeHex, 0x5B606A); XCTAssertEqual(EuclideousPartPlayLook.tilePressedFillHex, 0x2B2D33)
        close(EuclideousPartPlayLook.tileRadius, 7, "§4.2 the strip play tile's radius (was 9)")
        // on: lamp lane100 filled (+ a lane stroke), PLAY + name both #F2F4F7 (§1.3); the triangle rests at 55 % (§1.4)
        XCTAssertTrue(on.lampFilled); XCTAssertTrue(on.lampUsesLane); XCTAssertEqual(on.playHex, 0xF2F4F7); XCTAssertEqual(on.nameHex, 0xF2F4F7)
        close(EuclideousPartPlayLook.lampRestOpacity, 0.55, "§1.4 resting triangle opacity")
        // off: lamp unfilled with a #C9CDD4 outline, PLAY + name both #C9CDD4 — reads as available, not disabled (§1.3/§1.4)
        XCTAssertFalse(off.lampFilled); XCTAssertFalse(off.lampUsesLane); XCTAssertEqual(off.lampStrokeHex, 0xC9CDD4); XCTAssertEqual(off.playHex, 0xC9CDD4); XCTAssertEqual(off.nameHex, 0xC9CDD4)
        XCTAssertEqual(Double(euclideousPartPlayType(height: 78, isNotes: false).lampStroke), 1.1, accuracy: 0.0005, "§4.2 the stopped triangle is 1.1 pt")
    }

    // MARK: §A5 — the ANSWER line

    func testTheAnswerLineIsATwoPointLineAlongTheBottomOfTheNoteBand() {
        let r = euclideousStripAnswerLineFrame(stripWidth: 264.67)
        close(r.minX, 0); close(r.width, 264.67, "the strip's full width"); close(r.height, 2); close(r.maxY, EuclideousLaneCardMetrics.cometRowH, "along the bottom: it ends where the strip does")
        close(r.minY, EuclideousStripMetrics.trackH + EuclideousStripMetrics.rowGap + EuclideousStripMetrics.keyRowH - 2, "inside the note-key band (y 30…44)")
        XCTAssertGreaterThanOrEqual(r.minY, EuclideousStripMetrics.trackH + EuclideousStripMetrics.rowGap)
        closeD(EuclideousStripMetrics.answerLineAlpha, 0.7); close(EuclideousStripMetrics.answerLineRadius, 1)
        close(euclideousLaneCardFrames(card: CGSize(width: 380.67, height: 301), withBadge: false).strip.height, 44, "it doesn't change the strip's height")
    }
}
