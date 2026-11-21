//  PresetsTests.swift — PRESETS REDESIGN (Paul 2026-11-21): the new factory presets are wired right and not silent.

import XCTest

final class PresetsTests: XCTestCase {
    /// Mirror the load path a factory preset goes through (the AU's factory-apply runs these before the snapshot).
    private func loaded(_ make: () -> PluginState) -> PluginState {
        var s = make()
        s.normalizeSourcesAtLoad()
        return s
    }

    /// Every preset: ≥1 lane that will strike, and NO active lane is a NO-INPUT lane (every active lane has a source) — so
    /// nothing is silently broken. (Musical quality is device-owed; this only guards against a mis-wired / empty preset.)
    func testEveryPresetIsWiredAndNotSilent() {
        for (name, make) in EuclideousPresets.all {
            let active = loaded(make).euclideousLinesResolved.filter { $0.enabledResolved && ($0.pulses > 0 || $0.patternMissResolved) }
            XCTAssertGreaterThanOrEqual(active.count, 1, "\(name): at least one lane will strike")
            for (i, l) in active.enumerated() { XCTAssertNotEqual(l.poolSrcMaskResolved, 0, "\(name) active lane \(i): has a source (not NO-INPUT)") }
        }
    }

    /// The chord-driven presets (those that author a progression and use CHORDS, not the two KEY-based ones) really read the chords after load.
    func testChordDrivenPresetsReadTheirChords() {
        let keyBased: Set = ["PARALLEL FIFTH", "SCALE WALK"]
        for (name, make) in EuclideousPresets.all where !keyBased.contains(name) {
            let s = loaded(make)
            XCTAssertNotNil(s.euclideousChords, "\(name): authors a chord progression")
            XCTAssertTrue(s.euclideousLinesResolved.contains { $0.enabledResolved && $0.poolChordsOn }, "\(name): an active lane reads the chords")
        }
    }

    func testEveryPresetRoundTrips() throws {
        for (name, make) in EuclideousPresets.all {
            let s = make()
            let back = try JSONDecoder().decode(PluginState.self, from: JSONEncoder().encode(s))
            XCTAssertEqual(back.euclideousLines?.count, s.euclideousLines?.count, "\(name) lanes round-trip")
            XCTAssertEqual(back.euclideousChords?.chordsDegrees, s.euclideousChords?.chordsDegrees, "\(name) progression round-trips")
            XCTAssertEqual(back.riffPoly, s.riffPoly, "\(name) poly flag round-trips")
        }
    }
}
