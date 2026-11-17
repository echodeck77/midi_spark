//  StylePassTests.swift — STYLE PASS 1 (2026-11-17) §7 tests 1 + 9: the tokens resolve from ONE definition (a source scan,
//  the UndoAuditTests tripwire pattern) and the text colours meet 4.5:1 on their surfaces. Tests 2-8/10 ride their slices.

import XCTest
import CoreGraphics

final class StylePassTests: XCTestCase {

    // MARK: §7 test 1 — one definition per token; no second copy of the ownable values anywhere in the app

    /// The repo's Fourfold/ dir, from this file's own path (the UndoAuditTests tripwire pattern).
    private func fourfoldDir() -> URL {
        URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
    }
    private func swiftSources(under sub: String) throws -> [(name: String, text: String)] {
        let dir = fourfoldDir().appendingPathComponent(sub)
        let files = try FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)
            .filter { $0.pathExtension == "swift" }
        return try files.map { ($0.lastPathComponent, try String(contentsOf: $0, encoding: .utf8)) }
    }

    func testTokenValues() {
        XCTAssertEqual(FourfoldStyle.card, 0x17191E)
        XCTAssertEqual(FourfoldStyle.control, 0x23262D)
        XCTAssertEqual(FourfoldStyle.controlPressed, 0x2E323A)
        XCTAssertEqual(FourfoldStyle.selectedFill, 0xDFE3EA)
        XCTAssertEqual(FourfoldStyle.selectedInk, 0x0D0F14)
        XCTAssertEqual(FourfoldStyle.value, 0xF2F4F7)
        XCTAssertEqual(FourfoldStyle.label, 0xB4BAC4)
        XCTAssertEqual(FourfoldStyle.key, 0x959BA6)
        XCTAssertEqual(FourfoldStyle.disabled, 0x4A4E57)
        XCTAssertEqual(FourfoldStyle.hairline, FourfoldStyle.control, "§1.4: the hairline IS the control tone")
        XCTAssertEqual(FourfoldStyle.hairlineWidth, 1)
        XCTAssertEqual(FourfoldStyle.tapeDot, 0xF0475B)
        XCTAssertEqual(FourfoldStyle.tapeDotSize, 5)
        XCTAssertEqual(FourfoldStyle.iconStroke, 1.6)
    }

    /// §7 test 1's scan: the three surface values the tokens OWN appear in no other file (a stray literal is a second
    /// copy — §1.5). #DFE3EA/#0D0F14 are not blind-scanned (they legitimately hold NON-selected roles: the neutral
    /// emitter ring, MIX's active fill — findings §12.8); their selected-role holders are repointed and test 2 covers
    /// the selected look itself.
    func testNoSecondCopyOfTheOwnedSurfaceValues() throws {
        let owned = ["0x17191E", "0x17191e", "0x23262D", "0x23262d", "0x2E323A", "0x2e323a"]
        for sub in ["UI", "Engine", "Shared", "App"] {
            for f in try swiftSources(under: sub) where f.name != "StyleTokens.swift" {
                for v in owned {
                    XCTAssertFalse(f.text.contains(v), "\(f.name) holds \(v) — read FourfoldStyle instead (§1.5)")
                }
            }
        }
    }

    // MARK: §7 test 9 — contrast (WCAG relative luminance)

    private func luminance(_ hex: UInt32) -> Double {
        func lin(_ c: Double) -> Double { c <= 0.03928 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4) }
        let r = lin(Double((hex >> 16) & 0xFF) / 255)
        let g = lin(Double((hex >> 8) & 0xFF) / 255)
        let b = lin(Double(hex & 0xFF) / 255)
        return 0.2126 * r + 0.7152 * g + 0.0722 * b
    }
    private func contrast(_ a: UInt32, _ b: UInt32) -> Double {
        let (x, y) = (luminance(a), luminance(b))
        return (max(x, y) + 0.05) / (min(x, y) + 0.05)
    }

    func testTextContrastOnTheSurfaces() {
        XCTAssertGreaterThanOrEqual(contrast(FourfoldStyle.key, FourfoldStyle.card), 4.5, "key on card")
        XCTAssertGreaterThanOrEqual(contrast(FourfoldStyle.key, FourfoldStyle.control), 4.5, "key on control")
        XCTAssertGreaterThanOrEqual(contrast(FourfoldStyle.label, FourfoldStyle.card), 4.5, "label on card")
        XCTAssertGreaterThanOrEqual(contrast(FourfoldStyle.label, FourfoldStyle.control), 4.5, "label on control")
        XCTAssertGreaterThanOrEqual(contrast(FourfoldStyle.selectedInk, FourfoldStyle.selectedFill), 4.5, "ink on selected")
    }
}
