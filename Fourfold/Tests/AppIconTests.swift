//  AppIconTests.swift — the Canon icon must reach a HOST, not only the home screen (2026-11-01).
//  The standalone app's icon worked while AUM showed the wrong one: the extension carried no icon of its own, and the container's old bundle id (`com.paulbarrett.Fourfold`, no icon) can still sit next to the new one. These are cheap tripwires over
//  the project definition and the master image, so the icon cannot quietly vanish from either target again (project.yml says the same of the app's own line: "explicit so it cannot vanish").

import XCTest
import ImageIO

final class AppIconTests: XCTestCase {
    private var repo: URL { URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent() }

    /// The text of one top-level target in project.yml (from `  Name:` to the next two-space-indented key).
    private func target(_ name: String) throws -> String {
        let yml = try String(contentsOf: repo.appendingPathComponent("project.yml"), encoding: .utf8)
        let lines = yml.components(separatedBy: "\n")
        guard let start = lines.firstIndex(of: "  \(name):") else { XCTFail("no target \(name)"); return "" }
        var out: [String] = []
        for l in lines[(start + 1)...] {
            if l.hasPrefix("  ") && !l.hasPrefix("   ") && !l.hasPrefix("  #") && l.contains(":") { break }
            out.append(l)
        }
        return out.joined(separator: "\n")
    }

    func testBothTheAppAndTheExtensionCarryTheCanonAppIcon() throws {
        for name in ["Fourfold", "FourfoldAU"] {
            let t = try target(name)
            XCTAssertTrue(t.contains("ASSETCATALOG_COMPILER_APPICON_NAME: AppIcon"), "\(name) must name the AppIcon set")
        }
        // 2026-11-19: the extension carries its OWN full classic size set (AUAssets.xcassets) — the on-device AU ICON
        // PROBE showed the system registers NO icon for the component from the app's single-1024 "universal" set.
        XCTAssertTrue(try target("FourfoldAU").contains("Fourfold/AU/AUAssets.xcassets"), "the extension compiles its own full-size icon catalog")
        XCTAssertFalse(try target("FourfoldAU").contains("\n    info:"), "the extension's Info.plist stays hand-maintained (an `info:` block would drop its aumi AudioComponents)")
    }

    /// The extension's set is a FULL classic ladder generated from the same 1024 master — every entry's file exists at its exact pixel size.
    func testTheExtensionsIconSetIsAFullSizeLadderFromTheMaster() throws {
        let set = repo.appendingPathComponent("Fourfold/AU/AUAssets.xcassets/AppIcon.appiconset")
        let json = try JSONSerialization.jsonObject(with: Data(contentsOf: set.appendingPathComponent("Contents.json"))) as? [String: Any]
        let images = json?["images"] as? [[String: Any]] ?? []
        XCTAssertGreaterThanOrEqual(images.count, 18, "iPhone + iPad + marketing entries")
        for e in images {
            let file = try XCTUnwrap(e["filename"] as? String)
            let size = try XCTUnwrap(e["size"] as? String).components(separatedBy: "x")
            let scale = Double((e["scale"] as? String ?? "1x").dropLast()) ?? 1
            let px = Int((Double(size[0]) ?? 0) * scale)
            let src = try XCTUnwrap(CGImageSourceCreateWithURL(set.appendingPathComponent(file) as CFURL, nil), "\(file) missing")
            let img = try XCTUnwrap(CGImageSourceCreateImageAtIndex(src, 0, nil))
            XCTAssertEqual(img.width, px, "\(file) must be \(px)px for \(e["size"] ?? "?")@\(scale)x")
            XCTAssertEqual(img.width, img.height, "\(file) square")
        }
    }

    func testTheMasterIconIsA1024SquareWithNoAlpha() throws {
        let set = repo.appendingPathComponent("Fourfold/App/Assets.xcassets/AppIcon.appiconset")
        let json = try JSONSerialization.jsonObject(with: Data(contentsOf: set.appendingPathComponent("Contents.json"))) as? [String: Any]
        let images = json?["images"] as? [[String: Any]] ?? []
        XCTAssertEqual(images.count, 1, "a single-size set")
        XCTAssertEqual(images.first?["size"] as? String, "1024x1024")
        let file = try XCTUnwrap(images.first?["filename"] as? String)
        let src = try XCTUnwrap(CGImageSourceCreateWithURL(set.appendingPathComponent(file) as CFURL, nil))
        let img = try XCTUnwrap(CGImageSourceCreateImageAtIndex(src, 0, nil))
        XCTAssertEqual(img.width, 1024); XCTAssertEqual(img.height, 1024)
        XCTAssertTrue([CGImageAlphaInfo.none, .noneSkipFirst, .noneSkipLast].contains(img.alphaInfo), "an icon with an alpha channel draws black corners in a host that masks it itself (and the App Store refuses it)")
    }

    func testTheExtensionsHandMaintainedPlistDoesNotOverrideTheIcon() throws {
        let plist = try String(contentsOf: repo.appendingPathComponent("Fourfold/AU/Info.plist"), encoding: .utf8)
        XCTAssertFalse(plist.contains("CFBundleIcons"), "the build merges CFBundleIcons from the asset catalog; a hand-written one would fight it")
        XCTAssertTrue(plist.contains("<string>Frfd</string>") && plist.contains("<string>OutM</string>"), "the component identity the icon belongs to: aumi / Frfd / OutM")
    }
}
