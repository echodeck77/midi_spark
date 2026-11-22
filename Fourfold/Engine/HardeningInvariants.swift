//  HardeningInvariants.swift — ENGINE HARDENING 1 (2026-11-21), §3: pure checks over an emitted event list.
//  One event model + one checker, shared by every consumer so the rules can never drift apart:
//    - GoldenEventInvariantTests  (the checked-in event-list goldens, Scripts/fourfold-harness/golden-events/)
//    - RenderInvariantTests       (Router-level renders: block sizes, sample rates, seeks, loops)
//    - HardeningFuzzTests         (every fuzz session)
//    - KernelHostTests            (the headless Kernel host)
//
//  The rules, as the CODE defines them (verified against Router.swift / Emission.swift, 2026-11-21):
//  §3.1 BALANCE — on the wire a note-on and its off are collapsed through the engine's per-(cable,ch,note)
//       refcount, so the wire contract is: a running per-key balance never goes below zero (an off with no
//       on is an orphan), and ends at zero after the final stop window (anything else is stuck). A restrike
//       emits off-then-on at the SAME stamp in that order — balance is therefore walked in EMISSION order.
//  §3.2 ORDER — there is no sort at emission: each message carries its own absolute sample stamp and the
//       host schedules by stamp, so EMISSION order is not globally time-ordered (documented: under joins a
//       note's off can be emitted after a later same-key on). What the code does guarantee: every stamp lies
//       inside the render window that emitted it — or is the IMMEDIATE sentinel (Int64(bitPattern:
//       0xFFFFFFFF00000000), Emission.swift `renderSampleImmediate`, the flush stamp, meaning "window start,
//       now") — and window starts are non-decreasing. That is what checkOrder asserts.
//  §3.3 RANGE — data bytes ≤ 127; a note-on's velocity ≥ 1 (0x90 v0 is an off and is normalised first);
//       cable 0…4. Channels are a nibble and always valid by construction; they are still surfaced.
//  §3.10 ALL — cable 0 (ALL) carries one copy of every output's NOTE-ON (same stamp, channel, note,
//       velocity): the multiset of ons on cables 1…4 equals cable 0's. OFFS are excluded by design —
//       the ALL cable's refcount collapses them differently (two outputs holding one key = one ALL off).
//
//  Everything returns [String] violations (empty = clean) so a caller can prefix its seed/document.

import Foundation

/// One emitted MIDI message, normalised: `on` is true only for 0x9n with velocity > 0.
struct WireEvent: Equatable {
    var sample: Int64
    var cable: UInt8
    var b0: UInt8, b1: UInt8, b2: UInt8
    var status: UInt8 { b0 & 0xF0 }
    var channel: UInt8 { b0 & 0x0F }
    var isNoteOn: Bool { status == 0x90 && b2 > 0 }
    var isNoteOff: Bool { status == 0x80 || (status == 0x90 && b2 == 0) }
    static let immediateSentinel = Int64(bitPattern: 0xFFFFFFFF00000000)   // Emission.swift renderSampleImmediate
}

/// A render window an event list was produced over — lets checkOrder pin stamps to their windows and
/// lets musicalBeatStream stamp each event by its MUSICAL beat (not its sample — a seek breaks the
/// sample↔beat correspondence, so seek-exactness must compare musical beats). `beat0` is the window's
/// host beatPos at its first sample; `beatsPerSample` = tempo/60/sr for the window.
struct WireWindow {
    var start: Int64; var frames: Int64; var firstEvent: Int; var endEvent: Int
    var beat0: Double = 0; var beatsPerSample: Double = 0
}

enum HardeningInvariants {

    // MARK: §3.1 balance

    /// Walks EMISSION order. `requireEmpty`: assert end-of-list balance is zero (after a final stop+flush).
    /// Returns violations; keys are (cable, channel, note).
    static func checkBalance(_ e: [WireEvent], requireEmpty: Bool = true) -> [String] {
        var bal = [Int](repeating: 0, count: 5 * 16 * 128)
        var out: [String] = []
        func idx(_ ev: WireEvent) -> Int { Int(ev.cable) * 2048 + Int(ev.channel) * 128 + Int(ev.b1) }
        for (i, ev) in e.enumerated() {
            if ev.isNoteOn { bal[idx(ev)] += 1 }
            else if ev.isNoteOff {
                bal[idx(ev)] -= 1
                if bal[idx(ev)] < 0 {
                    out.append("ORPHAN off — event \(i) cable \(ev.cable) ch \(ev.channel + 1) note \(ev.b1) at sample \(ev.sample)")
                    bal[idx(ev)] = 0
                }
            }
        }
        if requireEmpty {
            for c in 0..<5 { for ch in 0..<16 { for n in 0..<128 where bal[c * 2048 + ch * 128 + n] != 0 {
                out.append("STUCK note — cable \(c) ch \(ch + 1) note \(n) balance \(bal[c * 2048 + ch * 128 + n]) at the end")
            } } }
        }
        return out
    }

    // MARK: §3.2 order

    /// Every stamp inside its window — inclusive of the window's end boundary (an event stamped at exactly
    /// `start + frames` is the engine's boundary convention: its ABSOLUTE sample is still correct, and the
    /// host schedules by absolute sample, so it is not a timing error — determinism and sample-rate
    /// invariance confirm the sample is right). A stamp strictly past the boundary, or before the start
    /// (and not the immediate sentinel), is a real violation. Window starts must be non-decreasing when the
    /// transport does not jump; a seek is allowed (checkOrder is not run on seek scripts).
    static func checkOrder(_ e: [WireEvent], windows: [WireWindow], allowSeek: Bool = false) -> [String] {
        var out: [String] = []
        var prevStart = Int64.min
        for w in windows {
            if !allowSeek, w.start < prevStart { out.append("WINDOW start moved backwards: \(w.start) after \(prevStart)") }
            prevStart = w.start
            for i in w.firstEvent..<w.endEvent {
                let s = e[i].sample
                if s == WireEvent.immediateSentinel { continue }
                if s < w.start || s > w.start + w.frames {
                    out.append("STAMP outside its window — event \(i) sample \(s) not in [\(w.start), \(w.start + w.frames)] cable \(e[i].cable) note \(e[i].b1)")
                }
            }
        }
        return out
    }

    /// Count events stamped at exactly the exclusive window end (offset == frameCount in a real AU). Not a
    /// violation (see checkOrder) but a host-compatibility fact worth watching — a strict host might clamp
    /// or defer offset == frameCount. Device-owed to confirm no host drops/doubles them.
    static func boundaryStampedCount(_ e: [WireEvent], windows: [WireWindow]) -> Int {
        var n = 0
        for w in windows { for i in w.firstEvent..<w.endEvent where e[i].sample == w.start + w.frames { n += 1 } }
        return n
    }

    // MARK: §3.3 range

    static func checkRange(_ e: [WireEvent]) -> [String] {
        var out: [String] = []
        for (i, ev) in e.enumerated() {
            if ev.cable > 4 { out.append("CABLE out of range — event \(i) cable \(ev.cable)") }
            if ev.b1 > 127 || ev.b2 > 127 { out.append("DATA byte > 127 — event \(i) \(ev.b0) \(ev.b1) \(ev.b2)") }
            if ev.isNoteOn && ev.b2 < 1 { out.append("NOTE-ON velocity 0 slipped normalisation — event \(i)") }   // unreachable by construction; kept as the §3.3 statement
            if ev.status == 0xB0 && ev.b1 > 127 { out.append("CC number > 127 — event \(i)") }
        }
        return out
    }

    // MARK: §3.10 ALL = union of A–D (note-ons)

    static func checkAllUnion(_ e: [WireEvent]) -> [String] {
        var outputs: [String: Int] = [:], all: [String: Int] = [:]
        for ev in e where ev.isNoteOn {
            let key = "\(ev.sample)/\(ev.channel)/\(ev.b1)/\(ev.b2)"
            if ev.cable == 0 { all[key, default: 0] += 1 } else { outputs[key, default: 0] += 1 }
        }
        var out: [String] = []
        for (k, n) in outputs where all[k, default: 0] != n { out.append("ALL union broken — on \(k): outputs \(n)× vs ALL \(all[k, default: 0])×") }
        for (k, n) in all where outputs[k, default: 0] == 0 { out.append("ALL union broken — ALL-only on \(k) (\(n)×) with no output copy") }
        return out
    }

    // MARK: §3.5/3.6 stream comparison

    /// Canonical form for cross-block-size / cross-sample-rate comparison: stable-sorted by stamp
    /// (ties keep emission order — a restrike's off-then-on at one stamp stays ordered), sentinel
    /// stamps resolved to their window start first via `windows`. Two renders of the same script are
    /// equivalent iff their canonical streams are equal element-for-element.
    static func canonical(_ e: [WireEvent], windows: [WireWindow]) -> [WireEvent] {
        var resolved = e
        for w in windows {
            for i in w.firstEvent..<w.endEvent where resolved[i].sample == WireEvent.immediateSentinel {
                resolved[i].sample = w.start
            }
        }
        return resolved.enumerated().sorted { a, b in
            a.element.sample != b.element.sample ? a.element.sample < b.element.sample : a.offset < b.offset
        }.map(\.element)
    }

    /// First difference between two canonical streams, as a readable line (nil = identical).
    static func firstDifference(_ a: [WireEvent], _ b: [WireEvent]) -> String? {
        for i in 0..<min(a.count, b.count) where a[i] != b[i] {
            return "event \(i): \(describe(a[i])) vs \(describe(b[i]))"
        }
        if a.count != b.count { return "length \(a.count) vs \(b.count) (first \(min(a.count, b.count)) equal)" }
        return nil
    }

    /// First difference allowing a ±`tol`-sample stamp jitter (same message bytes, same order). Block-size
    /// invariance holds to within one sample (float rounding in beat→sample), which §3.6 explicitly permits;
    /// a difference in bytes/order, or a stamp off by more than `tol`, is a real violation.
    static func firstDifferenceTolerant(_ a: [WireEvent], _ b: [WireEvent], tol: Int64 = 1) -> String? {
        if a.count != b.count { return "length \(a.count) vs \(b.count)" }
        for i in 0..<a.count {
            let x = a[i], y = b[i]
            if x.cable != y.cable || x.b0 != y.b0 || x.b1 != y.b1 || x.b2 != y.b2 || abs(x.sample - y.sample) > tol {
                return "event \(i): \(describe(x)) vs \(describe(y))"
            }
        }
        return nil
    }

    /// The NOTE-ONS in musical-beat window [from, to), each as "beat|cable|note|vel" (beat rounded to
    /// 1/1000), SORTED — a multiset that is order- and sample-rate- and block-size-independent. This is the
    /// invariance measure for §3.5/§3.6/§3.7: "the same notes sound at the same musical moments." Note-offs
    /// are excluded (refcount-collapsed + end-of-render-tail-sensitive; the balance/stuck checks cover them),
    /// as is the final-stop flush (its beats fall at/after `to`). Immediate-sentinel ons stamp at beat0.
    static func noteOnBeatKeys(_ e: [WireEvent], windows: [WireWindow], from: Double, to: Double) -> [String] {
        var out: [String] = []
        for w in windows {
            for i in w.firstEvent..<w.endEvent {
                let ev = e[i]
                guard ev.isNoteOn else { continue }
                let beat = ev.sample == WireEvent.immediateSentinel ? w.beat0
                    : w.beat0 + Double(ev.sample - w.start) * w.beatsPerSample
                let r = (beat * 1_000).rounded() / 1_000
                if r >= from && r < to { out.append("\(r)|\(ev.cable)|\(ev.b1)|\(ev.b2)") }
            }
        }
        return out.sorted()
    }

    /// Each event stamped by its MUSICAL beat (window.beat0 + (sample − window.start)·beatsPerSample),
    /// rounded to 1/1000 beat, as "beat|cable|b0|b1|b2". Use this — not a sample-derived beat — whenever a
    /// seek or loop has broken the sample↔beat correspondence. The immediate sentinel is stamped at beat0.
    static func musicalBeatStream(_ e: [WireEvent], windows: [WireWindow]) -> [String] {
        var out: [String] = []
        out.reserveCapacity(e.count)
        for w in windows {
            for i in w.firstEvent..<w.endEvent {
                let ev = e[i]
                let beat = ev.sample == WireEvent.immediateSentinel ? w.beat0
                    : w.beat0 + Double(ev.sample - w.start) * w.beatsPerSample
                let r = (beat * 1_000).rounded() / 1_000
                out.append("\(r)|\(ev.cable)|\(ev.b0)|\(ev.b1)|\(ev.b2)")
            }
        }
        return out
    }

    static func describe(_ ev: WireEvent) -> String {
        let cables = ["ALL", "A", "B", "C", "D"]
        let kind = ev.isNoteOn ? "on" : ev.isNoteOff ? "off" : String(format: "x%02X", ev.status)
        return "[\(ev.sample) \(cables[Int(min(ev.cable, 4))]) ch\(ev.channel + 1) \(kind) \(ev.b1) v\(ev.b2)]"
    }

    /// All of §3.1 + §3.3 + §3.10 in one call (the per-case fuzz bundle; §3.2 needs windows).
    static func checkAll(_ e: [WireEvent], requireEmpty: Bool = true) -> [String] {
        checkBalance(e, requireEmpty: requireEmpty) + checkRange(e) + checkAllUnion(e)
    }
}

/// An emitter that records WireEvents and window boundaries — the §3 harness-side collector.
final class WireRecorder: MIDIEmitter {
    var events: [WireEvent] = []
    var windows: [WireWindow] = []
    private var openWindow: (start: Int64, frames: Int64, first: Int, beat0: Double, bps: Double)?
    func emit(sampleTime: Int64, cable: UInt8, _ b0: UInt8, _ b1: UInt8, _ b2: UInt8) {
        events.append(WireEvent(sample: sampleTime, cable: cable, b0: b0, b1: b1, b2: b2))
    }
    /// Bracket every Router.process call with begin/end so checkOrder/musicalBeatStream know the windows.
    /// Pass beat0 (the window's host beatPos) and beatsPerSample (tempo/60/sr) for musical-beat stamping.
    func beginWindow(start: Int64, frames: Int64, beat0: Double = 0, beatsPerSample: Double = 0) {
        openWindow = (start, frames, events.count, beat0, beatsPerSample)
    }
    func endWindow() {
        if let w = openWindow {
            windows.append(WireWindow(start: w.start, frames: w.frames, firstEvent: w.first, endEvent: events.count,
                                      beat0: w.beat0, beatsPerSample: w.bps))
        }
        openWindow = nil
    }
}
