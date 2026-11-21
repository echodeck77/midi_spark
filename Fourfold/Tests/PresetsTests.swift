//  PresetsTests.swift — PRESETS REDESIGN (Paul 2026-11-21): the new factory presets are wired right and not silent.

import XCTest

final class PresetsTests: XCTestCase {
    /// Mirror the load path a factory preset goes through (the AU's factory-apply runs these before the snapshot).
    private func loaded(_ make: () -> PluginState) -> PluginState {
        var s = make()
        s.normalizeSourcesAtLoad()
        return s
    }

    /// Pins the source wiring: after load, every active chord lane reads exactly MIDI IN + CHORDS 1 (mask 0b00011) — so it plays
    /// the authored progression standalone AND reharmonizes from played MIDI for free, with KEY/PICK off (no scale muddying).
    func testTier1LanesReadMidiAndChordsOnly() {
        let midiChords: UInt8 = euclideousPoolSrcChords1 | 0b00001   // 0b00011
        for (name, make) in EuclideousPresets.all {
            for (i, l) in loaded(make).euclideousLinesResolved.enumerated() where l.enabledResolved {
                XCTAssertEqual(l.poolSrcMaskResolved, midiChords, "\(name) L\(i): reads MIDI + CHORDS 1 only")
            }
        }
    }

    func testTier1AreWiredAndNotSilent() {
        for (name, make) in EuclideousPresets.all {
            let s = loaded(make)
            let lines = s.euclideousLinesResolved
            let active = lines.filter { $0.enabledResolved && ($0.pulses > 0 || $0.patternMissResolved) }
            XCTAssertGreaterThanOrEqual(active.count, 2, "\(name): ≥2 lanes will strike")
            for l in active { XCTAssertNotEqual(l.poolSrcMaskResolved, 0, "\(name): an active lane has a source (not a NO-INPUT lane)") }
            XCTAssertNotNil(s.euclideousChords, "\(name): authors a chord progression")
            XCTAssertTrue(lines.contains { $0.enabledResolved && $0.poolChordsOn }, "\(name): an active lane reads the chords")
        }
    }

    func testTier1RoundTrips() throws {
        for (name, make) in EuclideousPresets.all {
            let s = make()
            let back = try JSONDecoder().decode(PluginState.self, from: JSONEncoder().encode(s))
            XCTAssertEqual(back.euclideousChords?.chordsDegrees, s.euclideousChords?.chordsDegrees, "\(name) round-trips its progression")
        }
    }
}
