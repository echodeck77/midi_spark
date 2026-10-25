//  FourfoldSoak.swift
//  A long, randomised stress run of the REAL standalone app (2026-10-24), started with `--soak <seconds>` (Scripts/fourfold-harness/soak.sh). It exercises what offline unit tests cannot: real threads, the real audio pump, wall-clock timing.
//  It plays the app like a very restless user — MIDI notes in, PLAY / STOP, tempo, factory presets, HOLD / LATCH, note source, lane edits, solo, ALL NOTES OFF — while a second CoreMIDI client listens to all five output ports and
//  tracks, per (port, channel, note), whether a synth listening there would have that key ON or OFF. The invariants it checks, at every STOP and at the end:
//    · after the stop every key is OFF — no stuck note (a re-strike of an already-sounding key is counted but is not a failure; a synth just retriggers it);
//    · nothing starts sounding while the transport is stopped.
//  It prints `SOAK ...` lines to stderr; the last is `SOAK RESULT: PASS` or `SOAK RESULT: FAIL`.

import CoreMIDI
import Foundation

final class FourfoldSoak {
    private var client = MIDIClientRef(), inPort = MIDIPortRef(), outPort = MIDIPortRef()
    private let lock = NSLock()
    private static let ports = 5, channels = 16, notes = 128
    private var sounding = [Bool](repeating: false, count: ports * channels * notes)   // what a synth listening to that port would be doing: the key is ON or OFF
    private var onTime = [UInt64](repeating: 0, count: ports * channels * notes)
    private var totalOns = 0, totalOffs = 0, unmatchedOffs = 0, doubleOns = 0, blanketOffs = 0
    private var maxHoldMs = 0.0
    private var faultEvery = 0   // `--soak-fault N`: pretend every Nth note-off never arrived — a CONTROL: the run must then report a stuck note, proving the checker can fail
    private let timebase: mach_timebase_info_data_t = { var t = mach_timebase_info_data_t(); mach_timebase_info(&t); return t }()

    // driver state (main queue only)
    private var rng: UInt64 = 0xF0F0_F0F0
    private var held: [(chan: UInt8, note: UInt8)] = []
    private var playing = true
    private var stops = 0, checks = 0, failures = 0
    private var onsAtLastStop = -1
    private var counts: [String: Int] = [:]
    private var replayStartEvents = -1          // the session tape's size when the current replay began (-1 = none running)
    private var replays = 0, replaysTapeGrew = 0

    private func next() -> UInt64 { rng &+= 0x9E37_79B9_7F4A_7C15; var z = rng; z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9; z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB; return z ^ (z >> 31) }
    private func rand(_ r: ClosedRange<Int>) -> Int { r.lowerBound + Int(next() % UInt64(r.upperBound - r.lowerBound + 1)) }
    private func randD(_ lo: Double, _ hi: Double) -> Double { lo + Double(next() % 10_000) / 10_000 * (hi - lo) }

    func run(engine: FourfoldEngine, seconds: Double, seed: UInt64?, faultEvery: Int = 0) {
        if let seed { rng = seed }
        self.faultEvery = faultEvery
        log("SOAK START: \(Int(seconds)) s, seed \(rng), \(engine.au.factoryPresetNames().count) factory presets")
        MIDIClientCreate("Fourfold soak" as CFString, nil, nil, &client)
        MIDIInputPortCreateWithBlock(client, "soak-in" as CFString, &inPort) { [weak self] list, ref in self?.collect(list, source: Int(bitPattern: ref) - 1) }
        MIDIOutputPortCreate(client, "soak-out" as CFString, &outPort)
        for i in 0..<5 { MIDIPortConnectSource(inPort, engine.midi.sources[i], UnsafeMutableRawPointer(bitPattern: i + 1)) }
        let destination = engine.midi.destination
        let presets = engine.au.factoryPresetNames()
        engine.setPlaying(true); playing = true
        let start = Date()

        // every action: (name, next due, min/max seconds between runs, what it does). One 40 ms tick runs whichever are due.
        struct Act { var name: String; var due: Date; var lo: Double; var hi: Double; var fire: () -> Void }
        var acts: [Act] = []
        func add(_ name: String, _ lo: Double, _ hi: Double, _ fire: @escaping () -> Void) { acts.append(Act(name: name, due: start.addingTimeInterval(randD(lo, hi)), lo: lo, hi: hi, fire: fire)) }

        add("note-on", 0.05, 0.35) { [self] in
            guard held.count < 10 else { return }
            let chan = UInt8(rand(0...3)), note = UInt8(rand(36...84)), vel = UInt8(rand(30...120))
            send([0x90 | chan, note, vel], to: destination); held.append((chan, note))
            if rand(0...4) == 0 { for iv in [4, 7] where Int(note) + iv < 100 { send([0x90 | chan, note + UInt8(iv), vel], to: destination); held.append((chan, note + UInt8(iv))) } }   // a chord
        }
        add("note-off", 0.05, 0.4) { [self] in
            guard !held.isEmpty else { return }
            let i = rand(0...(held.count - 1)); let h = held.remove(at: i); send([0x80 | h.chan, h.note, 0], to: destination)
        }
        add("release-all", 8, 20) { [self] in for h in held { send([0x80 | h.chan, h.note, 0], to: destination) }; held.removeAll() }
        add("transport", 2.5, 12) { [self] in
            if playing {
                playing = false; engine.setPlaying(false); stops += 1
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { [self] in check("stop edge #\(stops)"); lock.lock(); onsAtLastStop = totalOns; lock.unlock() }
            } else {
                lock.lock(); let sounded = onsAtLastStop >= 0 && totalOns != onsAtLastStop; let n = totalOns - onsAtLastStop; lock.unlock()
                if sounded { failures += 1; log("SOAK FAIL: \(n) note-on(s) arrived while the transport was STOPPED (stop edge #\(stops))") }
                playing = true; engine.setPlaying(true); onsAtLastStop = -1
            }
        }
        add("tempo", 4, 9) { engine.setTempo(Double(self.rand(60...200))) }
        add("preset", 9, 16) { engine.au.loadFactoryPreset(named: presets[self.rand(0...(presets.count - 1))]) }
        add("hold-latch", 6, 14) { [self] in
            let m: EuclideousHoldLatchMode? = [nil, .hold, .latch][rand(0...2)]
            engine.au.editDocument { $0.euclideousHoldLatchMode = m }
        }
        add("note-source", 8, 18) { [self] in
            let s: EuclideousLaneSource = [.midi, .midi, .chords, .key][rand(0...3)]
            engine.au.editDocument { $0.euclideousNoteSource = s }
        }
        add("lane-edit", 3, 8) { [self] in
            let i = rand(0...3), steps = rand(2...16), pulses = rand(0...steps), rot = rand(0...15)
            engine.au.editDocument { var ls = $0.euclideousLinesResolved; guard i < ls.count else { return }; ls[i].steps = steps; ls[i].pulses = pulses; ls[i].rotate = rot; $0.euclideousLines = ls }
        }
        add("solo", 5, 12) { [self] in engine.au.setEuclideousSoloLive([0, 0, 1, 2, 4, 8, 3][rand(0...6)]) }
        add("all-notes-off", 12, 30) { engine.au.euclideousAllNotesOff() }
        // REEL PHASE 1c: start replaying a random recorded pass, or hand back to live. The engine must keep running underneath (the session tape keeps growing), and a stop / hand-back must leave no key on.
        add("reel", 5, 11) { [self] in
            let au = engine.au
            if replayStartEvents >= 0, au.uiReelState() != 2 {                     // a replay ended (hand-back, or the transport stopped): did the tape keep growing?
                replays += 1; if au.tapeStats().events > replayStartEvents { replaysTapeGrew += 1 }
                replayStartEvents = -1
            }
            if au.uiReelState() == 2 {
                au.reelStopReplay()
            } else if playing {
                let nums = au.reelPassNumbers().filter { $0 >= 0 }
                guard !nums.isEmpty else { return }
                replayStartEvents = au.tapeStats().events
                au.reelSelectPass(nums[rand(0...(nums.count - 1))])
            }
        }

        let timer = DispatchSource.makeTimerSource(queue: .main)
        var lastProgress = start
        timer.schedule(deadline: .now() + 0.5, repeating: .milliseconds(40))
        timer.setEventHandler { [self] in
            let now = Date()
            if now.timeIntervalSince(start) >= seconds { timer.cancel(); finish(engine: engine, destination: destination); return }
            for i in acts.indices where now >= acts[i].due {
                acts[i].fire(); counts[acts[i].name, default: 0] += 1
                acts[i].due = now.addingTimeInterval(randD(acts[i].lo, acts[i].hi))
            }
            if now.timeIntervalSince(lastProgress) >= 30 {
                lastProgress = now; lock.lock(); let o = totalOns, f = totalOffs; lock.unlock()
                log("SOAK t=\(Int(now.timeIntervalSince(start))) s  note-ons=\(o) note-offs=\(f) stops=\(stops) checks=\(checks) failures=\(failures)")
            }
        }
        timer.resume(); soakTimer = timer
    }
    private var soakTimer: DispatchSourceTimer?

    private func finish(engine: FourfoldEngine, destination: MIDIEndpointRef) {
        for h in held { send([0x80 | h.chan, h.note, 0], to: destination) }; held.removeAll()
        playing = false; engine.setPlaying(false)
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) { [self] in
            check("final stop")
            lock.lock(); let o = totalOns, f = totalOffs, u = unmatchedOffs, d = doubleOns, mh = maxHoldMs; lock.unlock()
            log("SOAK TOTALS: note-ons=\(o) note-offs=\(f) re-strikes-of-a-sounding-key=\(d) unmatched-offs=\(u) stops=\(stops) balance-checks=\(checks) longest note=\(Int(mh)) ms")
            let tape = engine.au.tapeStats()
            log("SOAK TAPE: events=\(tape.events) dropped=\(tape.dropped) passes=\(tape.passes) whole=\(tape.completePasses) resident=\(tape.residentBytes / 1024) KiB evicted chunks=\(tape.evictedChunks) file errors=\(tape.storeErrors); replays=\(replays) (tape kept growing in \(replaysTapeGrew)); all-notes-off CCs=\(blanketOffs)")
            if tape.storeErrors > 0 { failures += 1; log("SOAK FAIL: the tape's file reported \(tape.storeErrors) error(s)") }
            if tape.dropped > 0 { failures += 1; log("SOAK FAIL: the session tape dropped \(tape.dropped) record(s) — the render thread ran out of chunks") }
            if replays >= 3, replaysTapeGrew == 0 { failures += 1; log("SOAK FAIL: the session tape did not grow during any of \(replays) replays — the engine froze under replay") }
            log("SOAK ACTIONS: " + counts.sorted { $0.key < $1.key }.map { "\($0.key)=\($0.value)" }.joined(separator: " "))
            let unmatchedBad = u > 0; if unmatchedBad { log("SOAK NOTE: \(u) note-off(s) arrived with no matching note-on (harmless to a synth, but worth knowing)") }
            log(failures == 0 && o > 0 ? "SOAK RESULT: PASS" : "SOAK RESULT: FAIL (failures=\(failures), note-ons=\(o))")
        }
    }

    /// Every (port, channel, note) must be balanced; report any that are not.
    private func check(_ label: String) {
        lock.lock(); defer { lock.unlock() }
        checks += 1
        var stuck: [String] = []
        for p in 0..<Self.ports { for c in 0..<Self.channels { for n in 0..<Self.notes where sounding[(p * Self.channels + c) * Self.notes + n] {
            stuck.append("\(["All", "A", "B", "C", "D"][p]) ch\(c + 1) note \(n)")
        } } }
        if !stuck.isEmpty { failures += 1; log("SOAK FAIL @ \(label): \(stuck.count) note(s) still ON after the stop: " + stuck.prefix(8).joined(separator: "; ")) }
    }

    private func send(_ bytes: [UInt8], to destination: MIDIEndpointRef) {
        var buf = [UInt8](repeating: 0, count: 256)
        buf.withUnsafeMutableBytes { raw in
            let list = raw.baseAddress!.assumingMemoryBound(to: MIDIPacketList.self)
            let p = MIDIPacketListInit(list)
            _ = MIDIPacketListAdd(list, 256, p, 0, bytes.count, bytes)
            MIDISend(outPort, destination, list)
        }
    }

    private func collect(_ list: UnsafePointer<MIDIPacketList>, source: Int) {
        guard source >= 0, source < Self.ports else { return }
        let now = mach_absolute_time()
        for packet in list.unsafeSequence() {
            let n = Int(packet.pointee.length)
            withUnsafePointer(to: packet.pointee.data) { t in
                t.withMemoryRebound(to: UInt8.self, capacity: 256) { b in
                    var i = 0
                    while i < n {
                        let status = b[i]
                        guard status >= 0x80 else { i += 1; continue }
                        let kind = status & 0xF0
                        let len = (kind == 0xC0 || kind == 0xD0) ? 2 : (status >= 0xF0 ? 1 : 3)
                        if i + len > n { break }
                        if kind == 0xB0, len == 3, b[i + 1] == 120 || b[i + 1] == 123 {   // All Sound Off / All Notes Off: a synth drops every key on that channel (the reel sends these when a replay ends)
                            lock.lock()
                            let base = (source * Self.channels + Int(status & 0x0F)) * Self.notes
                            for k in 0..<Self.notes { sounding[base + k] = false }
                            blanketOffs += 1
                            lock.unlock()
                        }
                        if kind == 0x80 || kind == 0x90, len == 3 {
                            let key = (source * Self.channels + Int(status & 0x0F)) * Self.notes + Int(b[i + 1] & 0x7F)
                            lock.lock()
                            if kind == 0x90 && b[i + 2] > 0 {
                                if sounding[key] { doubleOns += 1 }   // a re-strike of a key that is already on (a synth just retriggers it)
                                sounding[key] = true; totalOns += 1; onTime[key] = now
                            } else {
                                totalOffs += 1
                                if faultEvery > 0 && totalOffs % faultEvery == 0 { /* fault injection: this off is 'lost' */ }
                                else if sounding[key] {
                                    sounding[key] = false
                                    if onTime[key] != 0 { maxHoldMs = max(maxHoldMs, Double(now &- onTime[key]) * Double(timebase.numer) / Double(timebase.denom) / 1_000_000) }
                                } else { unmatchedOffs += 1 }
                            }
                            lock.unlock()
                        }
                        i += len
                    }
                }
            }
        }
    }

    private func log(_ s: String) { FileHandle.standardError.write((s + "\n").data(using: .utf8)!) }
}
