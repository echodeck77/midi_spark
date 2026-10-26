//  FourfoldMIDI.swift
//  FOURFOLD Step 3 (2026-10-23): the standalone app's CoreMIDI shell — the medium-specific end of the emission boundary (seam rule 3). OUT: nine virtual sources, one per AU cable (All, Emit Riff A, Emit Notes A … Emit Notes D), so the wires are visible
//  ports in every other app. IN: an input port connected to every other source on the system (hardware, Bluetooth, network, other apps) plus a virtual destination "Fourfold In"; complete channel-voice messages go to `onInput`.
//  Stable unique ids, so another app can remember a connection to "Fourfold Emit Riff A" across launches.

import CoreMIDI
import Foundation

final class FourfoldMIDI {
    static let sourceNames = FourfoldPorts.names.map { "Fourfold " + $0 }
    private static let uniqueIDBase: Int32 = 0x4652_4644   // "FRFD"; +0…8 the sources, +10 the destination

    private var client = MIDIClientRef()
    private(set) var sources = [MIDIEndpointRef](repeating: 0, count: FourfoldPorts.cableCount)
    private(set) var destination = MIDIEndpointRef()
    private var inputPort = MIDIPortRef()
    private var connected = Set<MIDIEndpointRef>()
    /// One packet-list scratch buffer; `send` is only ever called from the AU's render thread, so it is not shared.
    private let listBuffer = UnsafeMutableRawPointer.allocate(byteCount: 1024, alignment: 8)

    /// Called on CoreMIDI's thread with one complete channel-voice message (pointer, length). Set before any input arrives.
    var onInput: ((UnsafePointer<UInt8>, Int) -> Void)?
    private(set) var inputMessageCount = 0

    init() {
        MIDIClientCreateWithBlock("Fourfold" as CFString, &client) { [weak self] note in
            let id = note.pointee.messageID
            if id == .msgSetupChanged || id == .msgObjectAdded || id == .msgObjectRemoved { DispatchQueue.main.async { self?.connectAllSources() } }
        }
        for i in 0..<FourfoldPorts.cableCount {
            MIDISourceCreate(client, Self.sourceNames[i] as CFString, &sources[i])
            MIDIObjectSetIntegerProperty(sources[i], kMIDIPropertyUniqueID, Self.uniqueIDBase &+ Int32(i))
        }
        MIDIDestinationCreateWithBlock(client, "Fourfold In" as CFString, &destination) { [weak self] list, _ in self?.receive(list) }
        MIDIObjectSetIntegerProperty(destination, kMIDIPropertyUniqueID, Self.uniqueIDBase &+ 10)
        MIDIInputPortCreateWithBlock(client, "Fourfold Input" as CFString, &inputPort) { [weak self] list, _ in self?.receive(list) }
        connectAllSources()
    }

    deinit {
        MIDIClientDispose(client)     // disposes the endpoints and ports it owns
        listBuffer.deallocate()
    }

    /// Listen to every source on the system except our own (which would feed the output back in).
    func connectAllSources() {
        var present = Set<MIDIEndpointRef>()
        for i in 0..<MIDIGetNumberOfSources() {
            let src = MIDIGetSource(i)
            if sources.contains(src) { continue }
            present.insert(src)
            if !connected.contains(src) { MIDIPortConnectSource(inputPort, src, nil); connected.insert(src) }
        }
        connected.formIntersection(present)
    }
    var connectedSourceCount: Int { connected.count }

    /// OUT (render thread): one message on cable 0…8 (All, Riff A, Notes A … Notes D), stamped with the host time it should sound at.
    func send(cable: Int, bytes: UnsafePointer<UInt8>, length: Int, hostTime: UInt64) {
        guard cable >= 0, cable < FourfoldPorts.cableCount, length > 0, length <= 256 else { return }
        let list = listBuffer.assumingMemoryBound(to: MIDIPacketList.self)
        let pkt = MIDIPacketListInit(list)
        _ = MIDIPacketListAdd(list, 1024, pkt, hostTime, length, bytes)   // one packet of at most 256 bytes always fits the 1024-byte list
        MIDIReceived(sources[cable], list)
    }

    /// IN (CoreMIDI thread): split each packet into complete channel-voice messages. System realtime (clock, start, stop…) and SysEx are ignored for now; stray data bytes (running status) are skipped.
    private func receive(_ list: UnsafePointer<MIDIPacketList>) {
        guard let onInput else { return }
        for packet in list.unsafeSequence() {
            let total = Int(packet.pointee.length)
            withUnsafePointer(to: packet.pointee.data) { tuple in
                tuple.withMemoryRebound(to: UInt8.self, capacity: 256) { b in
                    var i = 0
                    while i < total {
                        let status = b[i]
                        if status >= 0xF8 { i += 1; continue }                                           // realtime
                        if status == 0xF0 { while i < total && b[i] != 0xF7 { i += 1 }; i += 1; continue } // SysEx
                        if status >= 0xF0 { i += (status == 0xF2 ? 3 : (status == 0xF1 || status == 0xF3 ? 2 : 1)); continue }
                        guard status >= 0x80 else { i += 1; continue }                                   // a data byte with no status
                        let len = (status & 0xF0 == 0xC0 || status & 0xF0 == 0xD0) ? 2 : 3
                        if i + len <= total { inputMessageCount &+= 1; onInput(b + i, len) }
                        i += len
                    }
                }
            }
        }
    }
}
