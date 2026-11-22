//  HardeningGolden.swift
//  ENGINE HARDENING 1 (2026-11-21) — §2 GOLDEN RENDERS.
//
//  Two things live here:
//  1. EVENT-LIST goldens: every golden document (all groups, old and new) now also writes one
//     readable text file per document — every MIDI message the AU sent, as
//     `<sample>\t<cable>\t<ch>\t<kind>\t<data>` — into the app container's Documents/golden-events/.
//     run.sh copies them to build/fourfold-harness/golden-events/ and (with --capture) into
//     Scripts/fourfold-harness/golden-events/, the checked-in baseline. A diff of those files reads
//     as music (which document, which note, at which sample), where the GOLDEN hash lines only say
//     "something moved". `--octaves-keep` runs hash lines only (the corpus isn't stored twice).
//  2. The GOLDEN HARDENING group: one authored document per feature area of the coverage map
//     (Docs/fourfold-coverage-map.md) plus combination documents, appended AFTER `GOLDEN INPUTS ALL`
//     so every pre-existing line stays untouched. UNLIKE the older groups, every HARDENING document
//     starts from a FULL `au.reset()` (the Kernel's deferred performReset) + a fresh init, so its
//     hash does NOT depend on its position in the list — new documents may be inserted anywhere in
//     the HARDENING list without re-deriving its neighbours (the group ALL line still folds in order).
//     A document may carry a `drive` closure (window index, host) for deterministic mid-run live-word
//     scripts (scrub ribbons, part solo, reel) — the same pattern the alloc audit uses.
//
//  The corpus itself is HardeningCorpus.swift. Re-derive goldens: sh Scripts/fourfold-harness/run.sh --golden
//  then diff; adopt a new baseline with --golden --capture (copies hash file + event lists into Scripts/).

import Foundation

/// One HARDENING golden document: name, the document edit, and an optional per-window drive
/// (render index 0..<6400, the host) for live-word scripts. The drive runs BEFORE that window's render.
typealias HardeningDoc = (name: String, edit: (inout PluginState) -> Void, drive: ((Int, Host) -> Void)?)

extension Host {
    /// Start collecting raw messages for the document that is about to render (called beside the hash reset).
    func beginEventCapture() {
        captured.removeAll(keepingCapacity: true)
        if captured.capacity < 300_000 { captured.reserveCapacity(300_000) }
        capturing = !CommandLine.arguments.contains("--octaves-keep")
    }

    /// Write the captured messages as one readable text file (the event-list golden) and stop capturing.
    /// Lines: `<sample>\t<cable name>\t<ch>\t<kind>\t<data>`, sample relative to the document's base;
    /// a message stamped with the immediate sentinel (−(1<<32), the engine's flush stamp) prints `imm`
    /// in the sample column and belongs, by the engine's definition, to the window it was emitted in.
    func writeEventGolden(_ group: String, _ name: String) {
        defer { capturing = false; captured.removeAll(keepingCapacity: true) }
        guard capturing else { return }
        let cables = ["ALL", "A", "B", "C", "D"]
        let names = ["C", "C#", "D", "D#", "E", "F", "F#", "G", "G#", "A", "A#", "B"]
        func noteName(_ n: UInt8) -> String { "\(names[Int(n) % 12])\(Int(n) / 12 - 1)(\(n))" }
        var out = "# GOLDEN \(group.isEmpty ? "" : group + " ")\(name)\n# events=\(captured.count)  columns: sample cable ch kind data\n"
        out.reserveCapacity(captured.count * 28 + 128)
        let sentinel = Int64(bitPattern: 0xFFFFFFFF00000000)   // AUEventSampleTimeImmediate
        for e in captured {
            let rel = e.t == sentinel ? "imm" : String(e.t - Int64(baseSample))
            let ch = (e.b0 & 0x0F) + 1
            let st = e.b0 & 0xF0
            let kind: String, data: String
            switch st {
            case 0x90 where e.b2 > 0: kind = "on";  data = "\(noteName(e.b1)) v\(e.b2)"
            case 0x80, 0x90:          kind = "off"; data = noteName(e.b1)
            case 0xB0:                kind = "cc";  data = "cc\(e.b1)=\(e.b2)"
            case 0xE0:                kind = "pb";  data = "\(Int(e.b2) << 7 | Int(e.b1))"
            case 0xA0:                kind = "at";  data = "\(noteName(e.b1)) p\(e.b2)"
            case 0xC0:                kind = "pc";  data = "\(e.b1)"
            default:                  kind = String(format: "x%02X", e.b0); data = "\(e.b1) \(e.b2)"
            }
            out += "\(rel)\t\(cables[Int(e.cable)])\t\(ch)\t\(kind)\t\(data)\n"
        }
        let dir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("golden-events", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let slug = (group.isEmpty ? "" : group.lowercased() + "-") + name.lowercased()
            .map { $0.isLetter || $0.isNumber ? $0 : "-" }.reduce(into: "") { s, c in
                if c != "-" || s.last != "-" { s.append(c) } }
        try? out.write(to: dir.appendingPathComponent("\(slug).txt"), atomically: true, encoding: .utf8)
    }

    /// §2's new group. Every document starts from a full Kernel reset + fresh init (position-independent,
    /// see the header); 32 bars at 120 BPM under a held C-major chord unless the document's drive says otherwise.
    func goldenHardening() {
        let docs = hardeningCorpus()
        timer?.invalidate()
        var all: UInt64 = 0xcbf29ce484222325, total = 0
        func step(_ i: Int) {
            if i == docs.count {
                fputs("GOLDEN HARDENING ALL: documents=\(docs.count) events=\(total) hash=\(String(all, radix: 16))\n", stderr)
                exit(0)
            }
            let doc = docs[i]
            playing = false; for _ in 0..<8 { render(480) }
            au.reset()                                   // deferred performReset — consumed by the next render
            au.resetToFreshInit(); au.editDocument(doc.edit)
            publishDocument()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { [self] in
                for _ in 0..<8 { render(480) }           // consumes the reset, settles the snapshot
                hash = 0xcbf29ce484222325; eventCount = 0; baseSample = sampleTime; beginEventCapture()
                if CommandLine.arguments.contains("--dump") { dumpName = "HARDENING: " + doc.name }
                hold([60, 64, 67]); playing = true
                for r in 0..<6400 { doc.drive?(r, self); render(480) }
                playing = false; for _ in 0..<8 { render(480) }
                release([60, 64, 67])
                writeEventGolden("HARDENING", doc.name)
                fputs("GOLDEN HARDENING \(doc.name): events=\(eventCount) hash=\(String(hash, radix: 16))\n", stderr)
                all = (all ^ hash) &* 0x100000001b3; total += eventCount
                DispatchQueue.main.async { step(i + 1) }
            }
        }
        step(0)
    }
}
