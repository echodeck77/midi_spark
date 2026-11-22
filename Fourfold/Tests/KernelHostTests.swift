//  KernelHostTests.swift — ENGINE HARDENING 1 (2026-11-21), §5.
//  A headless host for Kernel.swift. The Kernel is the render ENTRY POINT — transport & musical-context
//  derivation, incoming-MIDI parsing (the source pool, CC forwarding, all-notes-off, passthrough), the
//  free-run clock, the reel state machine, and the two stuck-note self-heal nets — and until this ferry it
//  had ZERO unit-test reach (it links AudioToolbox/CoreMIDI, so it was kept out of the macOS target). It is
//  now in the target (project.yml), driven here through its single beat seam `render(timestamp:frameCount:
//  events:)` with a synthetic AudioTimeStamp, synthetic transport/musical-context blocks, real AURenderEvent
//  MIDI in, and the MIDIEmitter out captured off `kernel.midiOut`. This is NOT a second Router driver — it
//  exercises exactly the Kernel-only code the Router tests cannot reach.
//
//  The STUCK ORACLE runs for free: Kernel.hardTrapOnStuckNote is true in DEBUG (this target is Debug), so
//  any window that leaves a voice stuck when it should be silent assertion-fails the test. These scenarios
//  therefore also assert, at every stop, that nothing is left sounding.

import XCTest
import AudioToolbox

final class KernelHostTests: XCTestCase {

    /// Drives one Kernel through its render seam with a synthetic host.
    final class KernelHarness {
        let kernel = Kernel()
        let store: SnapshotStore
        var sr = 48_000.0, tempo = 120.0, bpb: Double = 4
        var playing = true
        var sampleTime: Double = 0
        var baseSample: Double = 0
        var events: [WireEvent] = []
        var windows: [WireWindow] = []
        private var haveTransport = true, haveContext = true

        init(_ box: SnapshotBox, haveTransport: Bool = true, haveContext: Bool = true) {
            store = SnapshotStore(initial: box)
            self.haveTransport = haveTransport; self.haveContext = haveContext
            kernel.store = store
            kernel.sampleRate = sr
            kernel.midiOut = { [unowned self] t, cable, len, bytes in
                if len >= 3 { self.events.append(WireEvent(sample: Int64(t), cable: cable, b0: bytes[0], b1: bytes[1], b2: bytes[2])) }
                return noErr
            }
            kernel.transportState = haveTransport ? { [unowned self] flags, _, _, _ in
                flags?.pointee = self.playing ? .moving : []; return true
            } : nil
            kernel.musicalContext = haveContext ? { [unowned self] bpm, tsNum, tsDen, beat, off, measure in
                bpm?.pointee = self.tempo; tsNum?.pointee = self.bpb; tsDen?.pointee = 4
                let b = (self.sampleTime - self.baseSample) * self.tempo / 60.0 / self.sr
                beat?.pointee = b; off?.pointee = 0; measure?.pointee = (b / self.bpb).rounded(.down) * self.bpb
                return true
            } : nil
        }

        func publish(_ box: SnapshotBox) { store.publish(box) }

        /// One render window. `midi` = (sampleOffsetInWindow, cable 0-based, bytes) scheduled this window.
        func render(_ frames: Int, midi: [(Int, UInt8, [UInt8])] = []) {
            var ts = AudioTimeStamp(); ts.mSampleTime = sampleTime; ts.mFlags = .sampleTimeValid
            let beat0 = (sampleTime - baseSample) * tempo / 60.0 / sr
            windows.append(WireWindow(start: Int64(sampleTime), frames: Int64(frames), firstEvent: events.count,
                                      endEvent: events.count, beat0: beat0, beatsPerSample: tempo / 60.0 / sr))
            // Build the AURenderEvent MIDI linked list (stable addresses, freed after render).
            var nodes: [UnsafeMutablePointer<AURenderEvent>] = midi.map { _ in .allocate(capacity: 1) }
            defer { nodes.forEach { $0.deallocate() } }
            for (i, m) in midi.enumerated() {
                var ev = AUMIDIEvent()
                ev.eventType = .MIDI
                ev.eventSampleTime = Int64(sampleTime) + Int64(m.0)
                ev.cable = m.1
                ev.length = UInt16(m.2.count)
                withUnsafeMutableBytes(of: &ev.data) { raw in   // arity-agnostic (the SDK tuple size varies); the Kernel reads midi.data the same way
                    for (j, byte) in m.2.enumerated() where j < raw.count { raw[j] = byte }
                }
                ev.next = (i + 1 < nodes.count) ? nodes[i + 1] : nil
                nodes[i].withMemoryRebound(to: AUMIDIEvent.self, capacity: 1) { $0.pointee = ev }
            }
            let head = nodes.first.map { UnsafePointer($0) }
            withUnsafePointer(to: &ts) { tsPtr in
                kernel.render(timestamp: tsPtr, frameCount: AUAudioFrameCount(frames), events: head)
            }
            windows[windows.count - 1].endEvent = events.count
            sampleTime += Double(frames)
        }

        /// A run of identical windows.
        func run(_ windows: Int, frames: Int = 512) { for _ in 0..<windows { render(frames) } }

        /// Stop the transport and render the flush window (the edge closes every voice).
        func stopAndFlush() { playing = false; render(512) }
    }

    private func box(_ make: () -> PluginState = { PluginState.makeInit() }) -> SnapshotBox {
        HardeningCorpus.box(for: make())
    }
    /// Note-on / note-off byte helpers on cable 0 (the host input), channel 0.
    private func on(_ n: UInt8, _ v: UInt8 = 100) -> [UInt8] { [0x90, n, v] }
    private func off(_ n: UInt8) -> [UInt8] { [0x80, n, 0] }

    private func assertClean(_ h: KernelHarness, _ what: String) {
        let v = HardeningInvariants.checkBalance(h.events) + HardeningInvariants.checkRange(h.events)
        XCTAssertTrue(v.isEmpty, "\(what): \(v.prefix(4).joined(separator: " | "))")
        XCTAssertEqual(h.kernel.diag.stuckReason, 0, "\(what): kernel reports a stuck-note heal")
    }

    // MARK: §5.2 — Kernel-only scenarios

    func testPlaysAndFlushesCleanUnderAHeldChord() {
        let h = KernelHarness(box())
        h.render(512, midi: [(0, 0, on(60)), (0, 0, on(64)), (0, 0, on(67))])
        h.run(200)
        h.render(512, midi: [(0, 0, off(60)), (0, 0, off(64)), (0, 0, off(67))])
        h.stopAndFlush()
        assertClean(h, "held chord")
    }

    func testTransportEdgesCloseEveryVoice() {
        let h = KernelHarness(box())
        h.render(512, midi: [(0, 0, on(60)), (0, 0, on(64)), (0, 0, on(67))])
        h.run(40)
        h.playing = false; h.render(512)   // stop edge — must flush
        h.run(10)                           // stopped windows
        h.playing = true; h.render(512)     // start edge
        h.run(40)
        h.stopAndFlush()
        assertClean(h, "transport edges")
    }

    func testPanicClosesEverything() {
        let h = KernelHarness(box())
        h.render(512, midi: [(0, 0, on(60)), (0, 0, on(64)), (0, 0, on(67))])
        h.run(20)
        h.kernel.panic()
        h.render(512)
        h.run(5)
        h.stopAndFlush()
        assertClean(h, "panic")
        XCTAssertGreaterThan(h.kernel.diag.panics, 0, "panic did not register")
    }

    func testEuclideousAllNotesOffFlushesTheRow() {
        let h = KernelHarness(box())
        h.render(512, midi: [(0, 0, on(60)), (0, 0, on(64)), (0, 0, on(67))])
        h.run(30)
        h.kernel.euclideousAllNotesOffRequest()
        h.render(512)
        h.run(5)
        h.stopAndFlush()
        assertClean(h, "all notes off")
    }

    func testResetMidStreamFlushesAndContinuesClean() {
        let h = KernelHarness(box())
        h.render(512, midi: [(0, 0, on(60)), (0, 0, on(64)), (0, 0, on(67))])
        h.run(30)
        h.kernel.reset()
        h.render(512)
        h.run(30)
        h.stopAndFlush()
        assertClean(h, "reset mid-stream")
    }

    func testDocumentReplaceMidNoteClosesTheOldVoices() {
        let h = KernelHarness(box())
        h.render(512, midi: [(0, 0, on(60)), (0, 0, on(64)), (0, 0, on(67))])
        h.run(30)
        h.kernel.flushVoices()                       // the AU's document-replace flush
        h.publish(box { var s = PluginState.makeInit(); var ls = s.euclideousLinesResolved
            for i in 0..<4 { ls[i].riffOn = true; ls[i].steps = 5 + i }; s.euclideousLines = ls; return s })
        h.run(30)
        h.stopAndFlush()
        assertClean(h, "document replace mid-note")
    }

    func testReelRecordThenReplayThenStopIsClean() {
        // Record a pass, stage it for replay, replay, stop — exercises the Kernel reel state machine.
        let h = KernelHarness(box())
        h.render(512, midi: [(0, 0, on(60)), (0, 0, on(64)), (0, 0, on(67))])
        h.run(400)                                   // record several passes
        // Stage the most recent pass for replay the way the AU browser does, then let it replay and stop.
        h.kernel.reelSetBrowsing(true)
        h.run(50)
        h.kernel.reelStopReplay()
        h.render(512)
        h.kernel.reelSetBrowsing(false)
        h.run(20)
        h.stopAndFlush()
        assertClean(h, "reel record/replay/stop")
    }

    func testFreeRunWhileStoppedThenRealStopIsClean() {
        // KEEP-PLAYING default: the engine free-runs while the host is stopped. A real stop must still flush.
        let h = KernelHarness(box())
        h.playing = false
        h.render(512, midi: [(0, 0, on(60)), (0, 0, on(64)), (0, 0, on(67))])
        h.run(80)                                    // free-running while host-stopped
        h.render(512, midi: [(0, 0, off(60)), (0, 0, off(64)), (0, 0, off(67))])
        h.run(10)
        assertClean(h, "free-run while stopped")
    }

    // MARK: §5 raw-MIDI edge cases (the Kernel parses MIDI; the Router cannot see these)

    func testNoteOffWithNoNoteOnIsHarmless() {
        let h = KernelHarness(box())
        h.render(512, midi: [(0, 0, off(60)), (10, 0, off(64))])
        h.run(20)
        h.stopAndFlush()
        assertClean(h, "note-off without note-on")
    }

    func testRepeatedNoteOnThenOneOffIsBalanced() {
        let h = KernelHarness(box())
        h.render(512, midi: [(0, 0, on(60)), (20, 0, on(60)), (40, 0, on(60))])
        h.run(40)
        h.render(512, midi: [(0, 0, off(60))])
        h.stopAndFlush()
        assertClean(h, "repeated note-on")
    }

    func testOneHundredHeldNotesReleaseClean() {
        let h = KernelHarness(box())
        h.render(512, midi: (0..<100).map { (0, UInt8(0), on(UInt8(20 + $0 % 100))) })
        h.run(60)
        h.render(512, midi: (0..<100).map { (0, UInt8(0), off(UInt8(20 + $0 % 100))) })
        h.stopAndFlush()
        assertClean(h, "100 held notes")
    }

    func testSustainPedalAndAllControllersAreForwardedNotStuck() {
        let h = KernelHarness(box())
        h.render(512, midi: [(0, 0, on(60)), (0, 0, [0xB0, 64, 127])])   // CC64 sustain down
        h.run(30)
        h.render(512, midi: [(0, 0, off(60)), (0, 0, [0xB0, 64, 0])])    // release + pedal up
        h.run(10)
        h.stopAndFlush()
        assertClean(h, "sustain + controllers")
    }

    func testCC120AndCC123DoNotStrandNotes() {
        let h = KernelHarness(box())
        h.render(512, midi: [(0, 0, on(60)), (0, 0, on(64))])
        h.run(20)
        h.render(512, midi: [(0, 0, [0xB0, 123, 0])])   // all-notes-off
        h.run(5)
        h.render(512, midi: [(0, 0, [0xB0, 120, 0])])   // all-sound-off
        h.run(5)
        h.stopAndFlush()
        assertClean(h, "CC120/CC123")
    }

    func testNotesArrivingWhileStoppedThenPlay() {
        let h = KernelHarness(box())
        h.playing = false
        h.render(512, midi: [(0, 0, on(60)), (0, 0, on(64))])   // notes while stopped
        h.run(10)
        h.playing = true; h.run(40)
        h.render(512, midi: [(0, 0, off(60)), (0, 0, off(64))])
        h.stopAndFlush()
        assertClean(h, "notes while stopped")
    }

    // MARK: §5 host that supplies no transport / no musical context

    func testHostWithNoMusicalContextDoesNotCrashOrStrand() {
        let h = KernelHarness(box(), haveContext: false)
        h.render(512, midi: [(0, 0, on(60)), (0, 0, on(64)), (0, 0, on(67))])
        h.run(80)
        h.stopAndFlush()
        assertClean(h, "no musical context")
    }

    func testHostWithNoTransportStateDoesNotCrashOrStrand() {
        let h = KernelHarness(box(), haveTransport: false)
        h.render(512, midi: [(0, 0, on(60)), (0, 0, on(64)), (0, 0, on(67))])
        h.run(80)
        h.stopAndFlush()
        assertClean(h, "no transport state")
    }

    // MARK: §5.3 Thread Sanitizer structure (run under -enableThreadSanitizer YES)

    /// Renders on this thread while a second thread publishes snapshots and a third polls the UI feeds at
    /// 30 Hz — the real three-thread shape. Under TSan (SANITIZE build) any data race is reported and fails.
    /// Without TSan it is a smoke test that the concurrency does not crash or strand notes.
    func testConcurrentRenderPublishAndPoll() {
        let h = KernelHarness(box())
        let stop = NSLock(); var stopped = false
        func isStopped() -> Bool { stop.lock(); defer { stop.unlock() }; return stopped }
        let publisher = Thread {
            var n: UInt64 = 1
            while !isStopped() {
                var s = PluginState.makeInit(); var ls = s.euclideousLinesResolved
                for i in 0..<4 { ls[i].steps = Int(2 + n % 14); ls[i].riffOn = true }
                s.euclideousLines = ls
                h.publish(HardeningCorpus.box(for: s)); n &+= 1
                usleep(300)
            }
        }
        let poller = Thread {
            while !isStopped() { _ = h.kernel.diag; usleep(33_000) }   // 30 Hz UI poll
        }
        publisher.start(); poller.start()
        h.render(512, midi: [(0, 0, on(60)), (0, 0, on(64)), (0, 0, on(67))])
        h.run(600)
        stop.lock(); stopped = true; stop.unlock()
        usleep(5000)
        h.render(512, midi: [(0, 0, off(60)), (0, 0, off(64)), (0, 0, off(67))])
        h.stopAndFlush()
        assertClean(h, "concurrent render/publish/poll")
    }

    // MARK: §5.5 headless soak (deep tier) — fast, no simulator

    func testHeadlessSoak() throws {
        try XCTSkipUnless(ProcessInfo.processInfo.environment["HARDENING_DEEP"] == "1", "headless soak runs with HARDENING_DEEP=1")
        let h = KernelHarness(box())
        var g: UInt64 = 0xDEADBEEF
        func rnd(_ n: Int) -> Int { g = g &* 6364136223846793005 &+ 1442695040888963407; return Int((g >> 33) % UInt64(n)) }
        var held: Set<UInt8> = []
        // ~1 hour of musical time at 512/48k ≈ 337,500 windows; cap to a few musical minutes per run here —
        // the full 8-hour soak is Scripts/fourfold-harness/soak.sh on the real app. This catches Kernel-path
        // regressions fast under the stuck-note trap.
        let windowCount = 40_000
        for w in 0..<windowCount {
            var midi: [(Int, UInt8, [UInt8])] = []
            if rnd(5) == 0 { let n = UInt8(24 + rnd(72)); held.insert(n); midi.append((rnd(400), 0, on(n))) }
            if rnd(5) == 0, let n = held.randomElement() { held.remove(n); midi.append((rnd(400), 0, off(n))) }
            if rnd(40) == 0 { h.playing.toggle() }
            if rnd(60) == 0 { h.tempo = Double(40 + rnd(400)) }
            if rnd(80) == 0 { h.kernel.panic(); held.removeAll() }
            if rnd(50) == 0 { var s = PluginState.makeInit(); var ls = s.euclideousLinesResolved
                for i in 0..<4 { ls[i].steps = 2 + rnd(14); ls[i].pulses = rnd(16); ls[i].riffOn = rnd(2) == 0 }
                s.euclideousLines = ls; h.kernel.flushVoices(); h.publish(HardeningCorpus.box(for: s)) }
            h.render(512, midi: midi)
            if w % 4000 == 0 { h.events.removeAll(keepingCapacity: true); h.windows.removeAll(keepingCapacity: true) }   // keep memory flat
        }
        h.playing = false
        for n in held { h.render(512, midi: [(0, 0, off(n))]) }
        h.stopAndFlush()
        XCTAssertEqual(h.kernel.diag.stuckReason, 0, "headless soak left a stuck-note heal flagged")
    }
}
