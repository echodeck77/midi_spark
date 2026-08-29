//  RoomsLatticeTests.swift
//  The pure geometry behind the rooms interface (Derivations.roomsLattice). The lattice must make the
//  part/select grids, the seam sliver, and the machine panel land on the SAME band lines — so its
//  invariants (exact tiling of the height, the nav fraction, the interior span) are worth pinning off
//  the SwiftUI/CGFloat path. RoomsMetrics (RoomsPage.swift) is a thin CGFloat wrapper over this.

import XCTest

final class RoomsLatticeTests: XCTestCase {

    // The column stacks: pad · ▲PLAY door (ch·nf) · gap · header row (ch) · gap · 8 interior rows (ch, gap-sep) · pad.
    // When the cell is NOT floored, those bands + gaps + pads sum EXACTLY to the input height (the lattice tiles it).
    func testLatticeTilesTheHeightExactly() {
        for h in [220.0, 400.0, 733.5, 1024.0] {
            let g = roomsLattice(height: h)
            let gap = 3.0, pad = 3.0
            let total = pad + g.navH + gap + g.ch + gap + g.interiorH + pad   // pad·nav·gap·header·gap·interior·pad
            XCTAssertEqual(total, h, accuracy: 1e-9, "the lattice bands + gaps + pads tile the content height exactly (h=\(h))")
        }
    }

    // navH is exactly half a cell (the nav-door fraction nf = 0.5) — the ▲PLAY door reads as a half-row sliver.
    func testNavBandIsHalfACell() {
        let g = roomsLattice(height: 500)
        XCTAssertEqual(g.navH, g.ch * 0.5, accuracy: 1e-9)
    }

    // The interior is 8 grid rows + 7 inter-row gaps — the 8×8 grid's body height.
    func testInteriorSpansEightRowsAndSevenGaps() {
        let g = roomsLattice(height: 640)
        XCTAssertEqual(g.interiorH, g.ch * 8 + 3.0 * 7, accuracy: 1e-9)
    }

    // interiorTop sits below: pad + the nav door + a gap + the header row + a gap. (Where the 8 interior rows begin.)
    func testInteriorTopClearsTheDoorAndHeader() {
        let g = roomsLattice(height: 480)
        XCTAssertEqual(g.interiorTop, 3.0 + g.navH + 3.0 + g.ch + 3.0, accuracy: 1e-9)
    }

    // GUARD (the GeometryReader's first zero-height layout pass): a tiny / zero / negative height must never yield a
    // non-positive or NaN row — the cell floors at 6.
    func testDegenerateHeightsFloorTheCellNotCrash() {
        for h in [-100.0, 0.0, 1.0, 20.0] {
            let g = roomsLattice(height: h)
            XCTAssertGreaterThanOrEqual(g.ch, 6, "the cell never collapses below the 6pt floor (h=\(h))")
            XCTAssertFalse(g.ch.isNaN || g.navH.isNaN || g.interiorH.isNaN, "no NaN at degenerate heights (h=\(h))")
            XCTAssertGreaterThan(g.interiorH, 0, "the interior stays positive (h=\(h))")
        }
    }

    // A larger content height yields a larger (or equal, when both are floored) cell — monotone, so the grids grow
    // with the canvas rather than jumping.
    func testCellGrowsMonotonicallyWithHeight() {
        var last = -1.0
        for h in stride(from: 100.0, through: 1200.0, by: 50.0) {
            let ch = roomsLattice(height: h).ch
            XCTAssertGreaterThanOrEqual(ch, last, "cell height is monotone in the content height (h=\(h))")
            last = ch
        }
    }

    // Deterministic: same input → same output (pure function, no hidden state).
    func testLatticeIsDeterministic() {
        XCTAssertEqual(roomsLattice(height: 512), roomsLattice(height: 512))
    }

    // MARK: - roomsStampSource (the edit-not-carried bug locus)

    private func chain(_ ts: [ProcessorType]) -> [ProcessorSlot] { ts.map { ProcessorSlot(type: $0) } }

    // THE BUG (2026-08-29): editing an audition then assigning it must carry the EDIT — the live audition (its edited
    // chain) wins over the ORIGINAL library cell. Before the fix the stamp read the library cell and dropped the edit.
    func testAuditionEditWinsOverTheOriginalLibraryCell() {
        let edited = chain([.arp, .harmonize])                   // the card was edited: a harmonizer was added
        let original = (chain([.arp]), 5)                        // the untouched library cell (with a register home)
        let hit = roomsStampSource(auditionEdited: edited, libraryCell: original, sideRow: nil)
        XCTAssertEqual(hit?.chain.map(\.type), [.arp, .harmonize], "the live audition's EDITED chain is stamped, not the original")
        XCTAssertEqual(hit?.transpose, 0, "the audition's register home is baked into the chain (transpose 0)")
    }

    // An EMPTY audition (no live gsAud edit) falls through to the browsed library cell — keeping its register home.
    func testEmptyAuditionFallsThroughToTheLibraryCell() {
        let hit = roomsStampSource(auditionEdited: [], libraryCell: (chain([.cascade]), -12), sideRow: nil)
        XCTAssertEqual(hit?.chain.map(\.type), [.cascade])
        XCTAssertEqual(hit?.transpose, -12, "the library cell's register home travels when the audition is empty")
    }

    // No audition + no library cell → the aimed side-button's part row is the source (its register home too).
    func testSideRowIsTheSourceWhenNoAuditionOrLibraryCell() {
        let hit = roomsStampSource(auditionEdited: nil, libraryCell: nil, sideRow: (chain([.euclid]), 7))
        XCTAssertEqual(hit?.chain.map(\.type), [.euclid])
        XCTAssertEqual(hit?.transpose, 7)
    }

    // Nothing active → nil (COMMIT/stamp restores rather than discarding).
    func testNoSourceReturnsNil() {
        XCTAssertNil(roomsStampSource(auditionEdited: nil, libraryCell: nil, sideRow: nil))
        XCTAssertNil(roomsStampSource(auditionEdited: [], libraryCell: nil, sideRow: nil), "an empty audition alone is not a source")
    }
}
