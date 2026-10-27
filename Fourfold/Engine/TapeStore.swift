//  TapeStore.swift — REEL PHASE 1d (Docs/reel-redesign-plan.md): the session tape's file.
//  A file of checksummed BLOCKS, one per chunk of records, appended as the tape seals them. It does two jobs: it lets the tape keep only its newest ~8 MiB in memory (older chunks are read back from here on demand), and — in
//  the standalone app, where one session owns one file — it lets the session survive a relaunch. Main thread only. Foundation only (so the unit tests reach it), and deliberately no file-attribute calls: reading a file's
//  dates or the disk's free space would need a required-reason entry in both privacy manifests, and nothing here needs either (the file's length comes from `seekToEnd`, a session's age is not used).
//
//  Layout (little-endian):  FILE HEADER 16 B = "FFTAPE\0\1" · chunkEvents u32 · 0 u32.   then BLOCK* — HEADER 24 B = 0xB10C7A9E u32 · count u32 · minTick u32 · maxTick u32 · checksum u32 · 0 u32, then count × 8 B records.
//  The checksum (FNV-1a, 32 bit) covers count, minTick, maxTick and the records. Blocks are full chunks except possibly the LAST, which may be a partial "tail" the tape rewrites in place every few seconds and replaces with a full block
//  when its chunk fills; a crash mid-write leaves a block that fails its checksum, and loading keeps everything before it and cuts the file there.

import Foundation

final class TapeStore {
    struct Block { var offset: UInt64; var count: Int; var minTick: UInt32; var maxTick: UInt32 }

    // Version 2 (THE NINE PORTS, 2026-10-27): the cable field now means ALL + eight ports (it used to mean ALL + outputs A–D), so a version-1 file is reset on load instead of being re-read with its passes on the wrong ports.
    static let fileMagic: [UInt8] = [0x46, 0x46, 0x54, 0x41, 0x50, 0x45, 0x00, 0x02]
    static let blockMagic: UInt32 = 0xB10C_7A9E
    static let fileHeaderBytes: UInt64 = 16, blockHeaderBytes: UInt64 = 24

    let url: URL
    let chunkEvents: Int
    let deleteOnClose: Bool
    private var handle: FileHandle?
    private(set) var blocks: [Block] = []            // the good blocks, in file order (a live tail is not among them)
    private(set) var tailOffset: UInt64 = TapeStore.fileHeaderBytes
    private(set) var ioErrors = 0
    var isUsable: Bool { handle != nil }

    /// Opens (creating if need be) the file at `url` and, when `exclusive`, takes an advisory lock on it that lives as long as this object (and goes with the process if it dies) — so two instances can never write the same file, and
    /// `removeStale` can tell a dead process's leftovers from a live one's. Nil if it cannot be opened for writing or someone else holds the lock. Call `load` next to bring back what is in it.
    init?(url: URL, chunkEvents: Int, deleteOnClose: Bool = false, exclusive: Bool = true) {
        self.url = url; self.chunkEvents = chunkEvents; self.deleteOnClose = deleteOnClose
        let fm = FileManager.default
        try? fm.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        if !fm.fileExists(atPath: url.path), !fm.createFile(atPath: url.path, contents: nil) { return nil }
        guard let h = try? FileHandle(forUpdating: url) else { return nil }
        if exclusive, flock(h.fileDescriptor, LOCK_EX | LOCK_NB) != 0 { try? h.close(); return nil }
        handle = h
    }
    /// Delete every file in `directory` named `prefix…` that no live process holds (the leftovers of an extension that was killed).
    static func removeStale(in directory: URL, prefix: String) {
        guard let names = try? FileManager.default.contentsOfDirectory(atPath: directory.path) else { return }
        for n in names where n.hasPrefix(prefix) {
            let u = directory.appendingPathComponent(n)
            guard let h = try? FileHandle(forUpdating: u) else { continue }
            let free = flock(h.fileDescriptor, LOCK_EX | LOCK_NB) == 0
            try? h.close()
            if free { try? FileManager.default.removeItem(at: u) }
        }
    }
    deinit { close() }

    func close() {
        try? handle?.close(); handle = nil
        if deleteOnClose { try? FileManager.default.removeItem(at: url) }
    }
    private func fail() { ioErrors += 1; try? handle?.close(); handle = nil }

    private static func u32(_ d: Data, _ at: Int) -> UInt32 {
        let i = d.startIndex + at
        return UInt32(d[i]) | UInt32(d[i + 1]) << 8 | UInt32(d[i + 2]) << 16 | UInt32(d[i + 3]) << 24
    }
    private static func put(_ d: inout Data, _ v: UInt32) { d.append(UInt8(v & 0xFF)); d.append(UInt8((v >> 8) & 0xFF)); d.append(UInt8((v >> 16) & 0xFF)); d.append(UInt8((v >> 24) & 0xFF)) }
    private static func checksum(count: Int, minTick: UInt32, maxTick: UInt32, payload: UnsafeRawBufferPointer) -> UInt32 {
        var h: UInt32 = 0x811C_9DC5
        func mix(_ b: UInt8) { h = (h ^ UInt32(b)) &* 0x0100_0193 }
        for v in [UInt32(count), minTick, maxTick] { mix(UInt8(v & 0xFF)); mix(UInt8((v >> 8) & 0xFF)); mix(UInt8((v >> 16) & 0xFF)); mix(UInt8((v >> 24) & 0xFF)) }
        for b in payload { mix(b) }
        return h
    }

    /// Start the file over: empty, with a fresh header.
    func reset() {
        guard let h = handle else { return }
        do {
            try h.truncate(atOffset: 0)
            try h.seek(toOffset: 0)
            var head = Data(TapeStore.fileMagic); TapeStore.put(&head, UInt32(chunkEvents)); TapeStore.put(&head, 0)
            try h.write(contentsOf: head)
            blocks = []; tailOffset = TapeStore.fileHeaderBytes
        } catch { fail() }
    }

    /// Read back what the file holds: `visit(blockIndex, block, records)` for each good block in order (the pointer is valid only during the call). A file with the wrong header is started over; a bad or torn block ends the
    /// list and the file is cut there.
    func load(_ visit: (Int, Block, UnsafePointer<TapeEvent>) -> Void) {
        guard let h = handle else { return }
        blocks = []; tailOffset = TapeStore.fileHeaderBytes
        let scratch = UnsafeMutablePointer<TapeEvent>.allocate(capacity: chunkEvents)
        defer { scratch.deallocate() }
        do {
            try h.seek(toOffset: 0)
            let head = try h.read(upToCount: Int(TapeStore.fileHeaderBytes)) ?? Data()
            guard head.count == Int(TapeStore.fileHeaderBytes), Array(head.prefix(8)) == TapeStore.fileMagic, Int(TapeStore.u32(head, 8)) == chunkEvents else { reset(); return }
            var offset = TapeStore.fileHeaderBytes
            while true {
                try h.seek(toOffset: offset)
                guard let hd = try h.read(upToCount: Int(TapeStore.blockHeaderBytes)), hd.count == Int(TapeStore.blockHeaderBytes), TapeStore.u32(hd, 0) == TapeStore.blockMagic else { break }
                let count = Int(TapeStore.u32(hd, 4)), mn = TapeStore.u32(hd, 8), mx = TapeStore.u32(hd, 12), sum = TapeStore.u32(hd, 16)
                guard count > 0, count <= chunkEvents, let payload = try h.read(upToCount: count * MemoryLayout<TapeEvent>.stride), payload.count == count * MemoryLayout<TapeEvent>.stride else { break }
                let ok = payload.withUnsafeBytes { raw -> Bool in
                    guard TapeStore.checksum(count: count, minTick: mn, maxTick: mx, payload: raw) == sum else { return false }
                    UnsafeMutableRawPointer(scratch).copyMemory(from: raw.baseAddress!, byteCount: raw.count)
                    return true
                }
                guard ok else { break }
                let b = Block(offset: offset, count: count, minTick: mn, maxTick: mx)
                blocks.append(b)
                visit(blocks.count - 1, b, UnsafePointer(scratch))
                offset += TapeStore.blockHeaderBytes + UInt64(payload.count)
            }
            tailOffset = offset
            try h.truncate(atOffset: offset)
        } catch { fail() }
    }

    /// Read block `index`'s records into `out` (room for `chunkEvents`). False on any trouble.
    func read(block index: Int, into out: UnsafeMutablePointer<TapeEvent>) -> Bool {
        guard let h = handle, index >= 0, index < blocks.count else { return false }
        let b = blocks[index]
        do {
            try h.seek(toOffset: b.offset + TapeStore.blockHeaderBytes)
            let n = b.count * MemoryLayout<TapeEvent>.stride
            guard let payload = try h.read(upToCount: n), payload.count == n else { return false }
            payload.withUnsafeBytes { UnsafeMutableRawPointer(out).copyMemory(from: $0.baseAddress!, byteCount: n) }
            return true
        } catch { fail(); return false }
    }

    private func blockData(_ p: UnsafePointer<TapeEvent>, _ count: Int, _ mn: UInt32, _ mx: UInt32) -> Data {
        let raw = UnsafeRawBufferPointer(start: p, count: count * MemoryLayout<TapeEvent>.stride)
        var d = Data(); d.reserveCapacity(Int(TapeStore.blockHeaderBytes) + raw.count)
        TapeStore.put(&d, TapeStore.blockMagic); TapeStore.put(&d, UInt32(count)); TapeStore.put(&d, mn); TapeStore.put(&d, mx)
        TapeStore.put(&d, TapeStore.checksum(count: count, minTick: mn, maxTick: mx, payload: raw)); TapeStore.put(&d, 0)
        d.append(contentsOf: raw)
        return d
    }
    /// File one finished chunk as the next block (over a tail written earlier for the same chunk). Returns its block index, or nil if the file can no longer be written.
    func appendBlock(from p: UnsafePointer<TapeEvent>, count: Int, minTick: UInt32, maxTick: UInt32) -> Int? {
        guard let h = handle else { return nil }
        let d = blockData(p, count, minTick, maxTick)
        do {
            try h.seek(toOffset: tailOffset)
            try h.write(contentsOf: d)
            blocks.append(Block(offset: tailOffset, count: count, minTick: minTick, maxTick: maxTick))
            tailOffset += UInt64(d.count)
            return blocks.count - 1
        } catch { fail(); return nil }
    }
    /// Write the chunk still being filled as a partial block at the end of the file, without closing it: the next `writeTail` or `appendBlock` overwrites it.
    @discardableResult
    func writeTail(from p: UnsafePointer<TapeEvent>, count: Int, minTick: UInt32, maxTick: UInt32) -> Bool {
        guard let h = handle else { return false }
        let d = blockData(p, count, minTick, maxTick)
        do { try h.seek(toOffset: tailOffset); try h.write(contentsOf: d); return true } catch { fail(); return false }
    }
    /// The file's length in bytes (via the file handle, not file attributes).
    func lengthBytes() -> UInt64 { guard let h = handle else { return 0 }; return (try? h.seekToEnd()) ?? 0 }
}
