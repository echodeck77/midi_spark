//  FourfoldTransportTests.swift
//  FOURFOLD Step 3 (2026-10-23): the standalone app's internal transport — beat from the render timeline, continuous across tempo changes, restart-from-zero, and the host-time stamp CoreMIDI gets.

import XCTest

final class FourfoldTransportTests: XCTestCase {
    private let sr = 48_000.0

    func testStoppedTransportHoldsBeatZeroAndReportsNoNextBeatOffset() {
        var c = FourfoldTransportClock(sampleRate: sr)
        c.sync(desiredPlaying: false, desiredTempo: 120, at: 5_000)
        XCTAssertFalse(c.playing)
        XCTAssertEqual(c.beat(at: 99_999), 0)
        XCTAssertEqual(c.samplesToNextBeat(at: 99_999), 0)
    }
    func testPlayStartsFromBeatZeroAtTheBufferItIsAppliedAndAdvancesAtTheTempo() {
        var c = FourfoldTransportClock(sampleRate: sr)
        c.sync(desiredPlaying: true, desiredTempo: 120, at: 1_000)
        XCTAssertTrue(c.playing)
        XCTAssertEqual(c.beat(at: 1_000), 0, accuracy: 1e-12)
        XCTAssertEqual(c.beat(at: 1_000 + 48_000), 2.0, accuracy: 1e-9, "one second at 120 BPM is two beats")
        XCTAssertEqual(c.beat(at: 1_000 + 24_000), 1.0, accuracy: 1e-9)
    }
    func testTheBeatIsContinuousAcrossATempoChange() {
        var c = FourfoldTransportClock(sampleRate: sr)
        c.sync(desiredPlaying: true, desiredTempo: 120, at: 0)
        let t1 = 48_000.0                                  // 2 beats in
        XCTAssertEqual(c.beat(at: t1), 2.0, accuracy: 1e-9)
        c.sync(desiredPlaying: true, desiredTempo: 60, at: t1)
        XCTAssertEqual(c.tempo, 60)
        XCTAssertEqual(c.beat(at: t1), 2.0, accuracy: 1e-9, "no jump at the change")
        XCTAssertEqual(c.beat(at: t1 + 48_000), 3.0, accuracy: 1e-9, "one more second at 60 BPM is one beat")
    }
    func testStopFreezesTheBeatAndPlayAgainRestartsFromTheTop() {
        var c = FourfoldTransportClock(sampleRate: sr)
        c.sync(desiredPlaying: true, desiredTempo: 120, at: 0)
        c.sync(desiredPlaying: false, desiredTempo: 120, at: 36_000)   // 1.5 beats in
        XCTAssertEqual(c.beat(at: 36_000), 1.5, accuracy: 1e-9)
        XCTAssertEqual(c.beat(at: 500_000), 1.5, accuracy: 1e-9, "frozen while stopped")
        c.sync(desiredPlaying: true, desiredTempo: 120, at: 500_000)
        XCTAssertEqual(c.beat(at: 500_000), 0, accuracy: 1e-12, "a start edge begins at beat 0")
    }
    func testSyncIsLevelTriggeredSoRepeatedCallsChangeNothing() {
        var c = FourfoldTransportClock(sampleRate: sr)
        c.sync(desiredPlaying: true, desiredTempo: 100, at: 0)
        let once = c
        for k in 1...50 { c.sync(desiredPlaying: true, desiredTempo: 100, at: Double(k) * 512) }
        XCTAssertEqual(c, once, "the same desired state, applied every buffer, is a no-op")
    }
    func testTempoIsClampedAndANonFiniteTempoFallsBackToDefault() {
        XCTAssertEqual(FourfoldTransportClock.clamped(5), 30); XCTAssertEqual(FourfoldTransportClock.clamped(900), 300)
        XCTAssertEqual(FourfoldTransportClock.clamped(.nan), 120); XCTAssertEqual(FourfoldTransportClock.clamped(.infinity), 120)
        var c = FourfoldTransportClock(sampleRate: sr)
        c.sync(desiredPlaying: false, desiredTempo: 10_000, at: 0)
        XCTAssertEqual(c.tempo, 300)
    }
    func testSamplesToNextBeat() {
        var c = FourfoldTransportClock(sampleRate: sr)
        c.sync(desiredPlaying: true, desiredTempo: 120, at: 0)          // a beat is 24 000 samples
        XCTAssertEqual(c.samplesToNextBeat(at: 0), 24_000)
        XCTAssertEqual(c.samplesToNextBeat(at: 6_000), 18_000)           // beat 0.25 → 0.75 of a beat left
        XCTAssertEqual(c.samplesToNextBeat(at: 24_000), 24_000, "exactly on a beat: a whole beat to the next")
    }
    func testARestartedTimelineCarriesTheBeatOverInsteadOfJumping() {
        var c = FourfoldTransportClock(sampleRate: 48_000)
        c.sync(desiredPlaying: true, desiredTempo: 120, at: 0)
        c.timelineWillRestart(lastSampleTime: 72_000, newSampleRate: 44_100)    // 3 beats in; the engine restarts at another rate
        XCTAssertEqual(c.sampleRate, 44_100)
        c.sync(desiredPlaying: true, desiredTempo: 120, at: 100)                 // the new timeline's first buffer
        XCTAssertEqual(c.beat(at: 100), 3.0, accuracy: 1e-9)
        XCTAssertEqual(c.beat(at: 100 + 44_100), 5.0, accuracy: 1e-9, "one second at the NEW rate is two beats")
    }
    func testHostTimeStampsAnEventWithItsOffsetFromTheBufferStart() {
        // 1:1 timebase (numer == denom): ticks are nanoseconds. An event 480 samples (10 ms at 48 kHz) into the buffer lands 10 ms after the buffer's host time.
        let h = fourfoldHostTime(eventSample: 10_480, baseSample: 10_000, baseHost: 5_000_000_000, sampleRate: 48_000, numer: 1, denom: 1)
        XCTAssertEqual(h, 5_010_000_000, accuracy: 2)
        // Apple-silicon style timebase 125/3: ticks = nanos × 3/125.
        let h2 = fourfoldHostTime(eventSample: 10_480, baseSample: 10_000, baseHost: 1_000_000, sampleRate: 48_000, numer: 125, denom: 3)
        XCTAssertEqual(h2, 1_000_000 + UInt64(10_000_000.0 * 3.0 / 125.0), accuracy: 2)
    }
    func testHostTimeFallsBackToTheBufferStartForPastImmediateAndAbsurdlyFarEvents() {
        let base: UInt64 = 777
        XCTAssertEqual(fourfoldHostTime(eventSample: 9_000, baseSample: 10_000, baseHost: base, sampleRate: 48_000, numer: 1, denom: 1), base, "before the buffer")
        XCTAssertEqual(fourfoldHostTime(eventSample: 10_000, baseSample: 10_000, baseHost: base, sampleRate: 48_000, numer: 1, denom: 1), base)
        XCTAssertEqual(fourfoldHostTime(eventSample: Int64(bitPattern: 0xFFFF_FFFF_0000_0000), baseSample: 10_000, baseHost: base, sampleRate: 48_000, numer: 1, denom: 1), base, "AUEventSampleTimeImmediate")
        XCTAssertEqual(fourfoldHostTime(eventSample: 10_000 + 48_000 * 10, baseSample: 10_000, baseHost: base, sampleRate: 48_000, numer: 1, denom: 1), base, "10 s ahead is not a real event time")
        XCTAssertEqual(fourfoldHostTime(eventSample: 20_000, baseSample: 10_000, baseHost: base, sampleRate: 0, numer: 1, denom: 1), base, "no sample rate")
    }
}

private func XCTAssertEqual(_ a: UInt64, _ b: UInt64, accuracy: UInt64, file: StaticString = #filePath, line: UInt = #line) {
    XCTAssertLessThanOrEqual(a > b ? a - b : b - a, accuracy, "\(a) vs \(b)", file: file, line: line)
}
