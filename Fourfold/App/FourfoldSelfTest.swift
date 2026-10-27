//  FourfoldSelfTest.swift
//  FOURFOLD Step 3 (2026-10-23): an in-process check of the app's MIDI shell, run only with `--midi-selftest` (Scripts/fourfold-harness/app-test.sh). The iOS simulator's CoreMIDI does not reach macOS, so the app listens to ITS OWN
//  output ports from a second CoreMIDI client and sends a note to ITS OWN input, then prints what it saw to stderr:
//    OUT  — note-ons and note-offs per source (All, Emit Riff A … Emit Notes D), and how far ahead of "now" the packets' host-time stamps are (they should be a little ahead: the render runs a buffer before the sound);
//    IN   — a note sent to "Fourfold In" must reach the AU (the held-note count goes 0 → 1 → 0).

import CoreMIDI
import Foundation

final class FourfoldSelfTest {
    private var client = MIDIClientRef()
    private var inPort = MIDIPortRef(), outPort = MIDIPortRef()
    private let lock = NSLock()
    private var ons = [Int](repeating: 0, count: FourfoldPorts.cableCount), offs = [Int](repeating: 0, count: FourfoldPorts.cableCount)
    private var leadMs: [Double] = []
    private let timebase: mach_timebase_info_data_t = { var t = mach_timebase_info_data_t(); mach_timebase_info(&t); return t }()

    func run(engine: FourfoldEngine, after delay: TimeInterval = 3, listenFor: TimeInterval = 8) {
        MIDIClientCreate("Fourfold selftest" as CFString, nil, nil, &client)
        MIDIInputPortCreateWithBlock(client, "st-in" as CFString, &inPort) { [weak self] list, ref in self?.collect(list, source: Int(bitPattern: ref) - 1) }
        MIDIOutputPortCreate(client, "st-out" as CFString, &outPort)
        for i in 0..<FourfoldPorts.cableCount { MIDIPortConnectSource(inPort, engine.midi.sources[i], UnsafeMutableRawPointer(bitPattern: i + 1)) }
        let destination = engine.midi.destination
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [self] in
            let before = engine.au.kernelDiagnostics().poolCount
            send([0x90, 60, 100], to: destination)
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [self] in
                let held = engine.au.kernelDiagnostics().poolCount
                send([0x80, 60, 0], to: destination)
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [self] in
                    let after = engine.au.kernelDiagnostics().poolCount
                    log("SELFTEST IN: held notes before=\(before) while-held=\(held) after-release=\(after) (CoreMIDI messages received by the app: \(engine.midi.inputMessageCount))")
                }
            }
        }
        if CommandLine.arguments.contains("--midi-selftest-transport") {
            // STOP then PLAY again: every note-on must have its note-off, nothing may sound while stopped, and PLAY must resume.
            func snap() -> ([Int], [Int]) { lock.lock(); defer { lock.unlock() }; return (ons, offs) }
            var a = ([Int](), [Int]()), b = ([Int](), [Int]())
            DispatchQueue.main.asyncAfter(deadline: .now() + delay + 1) { engine.setPlaying(false) }
            DispatchQueue.main.asyncAfter(deadline: .now() + delay + 1.5) { a = snap() }
            DispatchQueue.main.asyncAfter(deadline: .now() + delay + 4) { b = snap(); engine.setPlaying(true) }
            DispatchQueue.main.asyncAfter(deadline: .now() + delay + 7) { [self] in
                let c = snap()
                log("SELFTEST TRANSPORT: after STOP note-ons=\(a.0) offs=\(a.1) | stopped 2.5 s later note-ons=\(b.0) (no new notes: \(a.0 == b.0), all notes closed: \(b.0 == b.1)) | after PLAY again note-ons=\(c.0) (resumed: \(c.0[0] > b.0[0]))")
            }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + delay + listenFor) { [self] in
            lock.lock(); defer { lock.unlock() }
            let lead = leadMs.sorted()
            let med = lead.isEmpty ? Double.nan : lead[lead.count / 2]
            log("SELFTEST OUT: note-ons [All,RiffA,NotesA,RiffB,NotesB,RiffC,NotesC,RiffD,NotesD]=\(ons) note-offs=\(offs); host-time lead of packets over 'now' (ms): min=\(String(format: "%.1f", lead.first ?? .nan)) median=\(String(format: "%.1f", med)) max=\(String(format: "%.1f", lead.last ?? .nan)) over \(lead.count) note-ons")
        }
    }

    /// `--hocket-test mode:main:alt` (e.g. `swap:1:3`, `pass:2:4`; outputs are cables 1…8): a second after launch, store ONE rule the way the pop-up's funnel does (`editDocument`), so the SELFTEST OUT line shows which of the nine
    /// outputs the real engine, in the real app, then sounds on.
    func hocketTest(engine: FourfoldEngine) {
        let a = CommandLine.arguments
        guard let i = a.firstIndex(of: "--hocket-test"), i + 1 < a.count else { return }
        let parts = a[i + 1].split(separator: ":", omittingEmptySubsequences: false).map(String.init)
        guard parts.count == 3 else { log("SELFTEST HOCKET: expected mode:main:alt"); return }
        var rule = HocketRule()
        rule.mode = parts[0] == "pass" ? .pass : .swap
        rule.main = parts[1].split(separator: ",").compactMap { Int($0) }
        rule.alt = parts[2].split(separator: ",").compactMap { Int($0) }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
            engine.au.editDocument { $0.hocketRules = HocketRuleSet([rule]) }
            self.log("SELFTEST HOCKET: stored \(a[i + 1]) -> rules \(engine.au.uiHocketRules().map { "\($0.mode) main=\($0.main) alt=\($0.alt) lit=\($0.isLit)" })")
        }
    }

    /// `--state-test-write`: change a document field a second after launch (the app's 3 s autosave then writes it). `--state-test-read`: print that field — run in the NEXT launch it shows whether the session came back.
    func stateTest(engine: FourfoldEngine) {
        if CommandLine.arguments.contains("--state-test-write") {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
                engine.au.editDocument { $0.euclideousKeyRoot = 7 }
                self.log("SELFTEST STATE: wrote key root 7")
            }
        }
        if CommandLine.arguments.contains("--state-test-read") {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1) { self.log("SELFTEST STATE: key root after launch = \(engine.au.uiEuclideousKeyRoot())") }
        }
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
        guard source >= 0, source < FourfoldPorts.cableCount else { return }
        let now = mach_absolute_time()
        for packet in list.unsafeSequence() {
            let n = Int(packet.pointee.length)
            withUnsafePointer(to: packet.pointee.data) { t in
                t.withMemoryRebound(to: UInt8.self, capacity: 256) { b in
                    var i = 0
                    while i + 2 < n {
                        let st = b[i] & 0xF0
                        lock.lock()
                        if st == 0x90 && b[i + 2] > 0 {
                            ons[source] += 1
                            if source == 1, packet.pointee.timeStamp != 0 {
                                let ticks = Double(Int64(bitPattern: packet.pointee.timeStamp) - Int64(bitPattern: now))
                                leadMs.append(ticks * Double(timebase.numer) / Double(timebase.denom) / 1_000_000)
                            }
                        } else if st == 0x80 || st == 0x90 { offs[source] += 1 }
                        lock.unlock()
                        i += 3
                    }
                }
            }
        }
    }

    private func log(_ s: String) { FileHandle.standardError.write((s + "\n").data(using: .utf8)!) }
}
