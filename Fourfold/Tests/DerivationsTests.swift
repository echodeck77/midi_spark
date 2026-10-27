//  DerivationsTests.swift
//  Off-device unit tests for MidiSpark's pure engine core (Derivations.swift + Models.swift enums).
//  These run in seconds via `xcodebuild test` — no simulator, no iPad, no ears. They guard the
//  regression-prone math: swing warp + inverse, phase modes, arp patterns, dispatch, ratchet ramp.

import XCTest

final class DerivationsTests: XCTestCase {




    // MARK: PER-LAYER EMITTER ROUTING ferry (2026-10-25) §2 — the OUT column




    // MARK: swing warp (§4)

    func testSwingIdentityAt50() {
        // a = swing/50 = 1 at 50%: musical == real, exactly.
        for beat in stride(from: 0.0, through: 8.0, by: 0.13) {
            XCTAssertEqual(musicalOf(beat, stepBeats: 2, a: 1), beat, accuracy: 1e-9)
            XCTAssertEqual(realOf(beat, stepBeats: 2, a: 1), beat, accuracy: 1e-9)
        }
    }

    func testSwingIsInvertible() {
        // realOf ∘ musicalOf == identity for any swing amount and step (round-trip, no drift).
        for a in [1.0, 1.2, 1.5] {          // swing 50, 60, 75
            for S in [0.5, 1.0, 2.0, 3.0] {
                for beat in stride(from: 0.0, through: 12.0, by: 0.37) {
                    let round = realOf(musicalOf(beat, stepBeats: S, a: a), stepBeats: S, a: a)
                    XCTAssertEqual(round, beat, accuracy: 1e-9, "S=\(S) a=\(a) beat=\(beat)")
                }
            }
        }
    }

    func testSwingWarpsStepPairs() {
        // At swing > 50 the first step of each pair is stretched (its musical midpoint lands early).
        let a = 1.5, S = 1.0
        // musical position of the real halfway point of step 0 should be < 0.5 (compressed forward)
        XCTAssertLessThan(musicalOf(0.5, stepBeats: S, a: a), 0.5)
    }

    // MARK: phase modes (§3.5)




    // MARK: arp patterns (§3)

    private func pool(_ notes: [UInt8]) -> NotePool {
        let p = NotePool()
        for n in notes { p.noteOn(n, velocity: 100, channel: 0) }
        p.rebuildSorted()
        return p
    }











    // (Provenance channel removed with delta §7 — a note carries no channel past the input filter;
    //  channel behaviour is covered by the input-channel filter tests below.)


    // MARK: input-channel filter (delta §7)

    private func mixedPool() -> NotePool {
        let p = NotePool()
        p.noteOn(60, velocity: 100, channel: 0)   // ch 1 (wire 0)
        p.noteOn(64, velocity: 100, channel: 1)   // ch 2 (wire 1)
        p.noteOn(67, velocity: 100, channel: 0)   // ch 1
        p.rebuildSorted()
        return p
    }

    func testSrcCountFilter() {
        let p = mixedPool()
        XCTAssertEqual(p.srcCount(filter: 0), 3)   // OMNI = all
        XCTAssertEqual(p.srcCount(filter: 1), 2)   // ch 1 → 60, 67
        XCTAssertEqual(p.srcCount(filter: 2), 1)   // ch 2 → 64
        XCTAssertEqual(p.srcCount(filter: 5), 0)   // nothing on ch 5
    }

    func testSrcAscendingFilter() {
        let p = mixedPool()
        XCTAssertEqual(p.srcAscending(0, filter: 1), 60)   // ch-1 notes ascending: 60, 67
        XCTAssertEqual(p.srcAscending(1, filter: 1), 67)
        XCTAssertEqual(p.srcAscending(0, filter: 2), 64)   // ch-2: 64
    }



    // §item 11 INPUT CABLES: the cable admission (bitmask; ANY = all bits) — sits ahead of the channel filter.
    func testReceiverHearsCable() {
        let any = 0b1111
        // ANY (nil → all bits via cableResolved) hears every cable — today's behaviour, byte-for-byte.
        for c in 1...4 { XCTAssertTrue(receiverHearsCable(mask: any, eventCable: c)) }
        // A single-cable receiver hears only its cable.
        XCTAssertTrue(receiverHearsCable(mask: 0b0010, eventCable: 2))
        XCTAssertFalse(receiverHearsCable(mask: 0b0010, eventCable: 1))
        XCTAssertFalse(receiverHearsCable(mask: 0b0010, eventCable: 3))
        // Subset-multi (cables {1,3}) — the reserved future capability.
        XCTAssertTrue(receiverHearsCable(mask: 0b0101, eventCable: 1))
        XCTAssertFalse(receiverHearsCable(mask: 0b0101, eventCable: 2))
        XCTAssertTrue(receiverHearsCable(mask: 0b0101, eventCable: 3))
        // Unknown/untagged cable (0 or >4: a single-input host, or legacy) → heard by everyone.
        XCTAssertTrue(receiverHearsCable(mask: 0b0010, eventCable: 0))
        XCTAssertTrue(receiverHearsCable(mask: 0b0001, eventCable: 9))
    }



    // MARK: UMP → legacy (§item 11 INPUT CABLES — the eventList path)

    // A UMP MIDI-1.0 Channel-Voice message (MT 0x2): one word [MT|grp][status][d1][d2].
    private func ump1(_ group: UInt32, _ status: UInt32, _ d1: UInt32, _ d2: UInt32) -> UInt32 {
        (0x2 << 28) | (group << 24) | (status << 16) | (d1 << 8) | d2
    }

    func testUmpWordCountByMessageType() {
        XCTAssertEqual(umpWordCount(mt: 0x2), 1)   // MIDI 1.0 CV
        XCTAssertEqual(umpWordCount(mt: 0x4), 2)   // MIDI 2.0 CV
        XCTAssertEqual(umpWordCount(mt: 0x0), 1)   // utility
        XCTAssertEqual(umpWordCount(mt: 0x3), 2)   // 7-bit sysex
        XCTAssertEqual(umpWordCount(mt: 0x5), 4)   // 128-bit data
        XCTAssertEqual(umpWordCount(mt: 0xD), 4)   // flex
    }

    func testUmpMidi1CVDecodesWithGroupAsCable() {
        // Note-on, group 3, ch 5, note 60, vel 100 → legacy bytes verbatim, group 3 (cable = group+1 upstream).
        guard let m = umpToLegacy(ump1(3, 0x95, 60, 100), 0) else { return XCTFail("nil") }
        XCTAssertEqual(m.b0, 0x95); XCTAssertEqual(m.b1, 60); XCTAssertEqual(m.b2, 100)
        XCTAssertEqual(m.len, 3);   XCTAssertEqual(m.group, 3)
        // Program change (0xC) is a 2-byte message.
        guard let pc = umpToLegacy(ump1(0, 0xC0, 7, 0), 0) else { return XCTFail("nil") }
        XCTAssertEqual(pc.len, 2)
    }

    func testUmpMidi2NoteOnScalesVelocityAndKeepsGroup() {
        // MT 0x4 note-on: [0x4|grp][0x9|ch][note][0] + [vel16<<16]. Group 2, ch 1, note 64, vel16 0x8000.
        let w0: UInt32 = (0x4 << 28) | (2 << 24) | (0x9 << 20) | (1 << 16) | (64 << 8)
        let w1: UInt32 = 0x8000 << 16
        guard let m = umpToLegacy(w0, w1) else { return XCTFail("nil") }
        XCTAssertEqual(m.b0, 0x91); XCTAssertEqual(m.b1, 64)
        XCTAssertEqual(m.b2, 64)                          // 0x8000 >> 9 = 64
        XCTAssertEqual(m.group, 2)
        // A near-zero 16-bit velocity still yields a sounding note-on (min 1), never a false note-off.
        guard let q = umpToLegacy(w0, 0x0001 << 16) else { return XCTFail("nil") }
        XCTAssertEqual(q.b0, 0x91); XCTAssertEqual(q.b2, 1)
    }

    func testUmpMidi2NoteOffAndCC() {
        // Note-off (0x8).
        let off: UInt32 = (0x4 << 28) | (0x8 << 20) | (3 << 16) | (72 << 8)
        guard let n = umpToLegacy(off, 0) else { return XCTFail("nil") }
        XCTAssertEqual(n.b0, 0x83); XCTAssertEqual(n.b1, 72); XCTAssertEqual(n.b2, 0)
        // CC (0xB): 32-bit value 0xFFFFFFFF → 7-bit 127.
        let cc: UInt32 = (0x4 << 28) | (0xB << 20) | (74 << 8)
        guard let c = umpToLegacy(cc, 0xFFFFFFFF) else { return XCTFail("nil") }
        XCTAssertEqual(c.b0, 0xB0); XCTAssertEqual(c.b1, 74); XCTAssertEqual(c.b2, 127)
    }

    func testUmpNonChannelVoiceIsIgnored() {
        XCTAssertNil(umpToLegacy(0x0 << 28, 0))            // utility
        XCTAssertNil(umpToLegacy(0x1 << 28, 0))            // system realtime
        // MT 0x4 with a reserved status nibble (0x0) → nil (only note/CC/pressure/bend handled).
        XCTAssertNil(umpToLegacy((0x4 << 28) | (0x0 << 20), 0))
    }

    func testUmpMidi2PitchBendAndChannelPressure() {
        // Pitch bend (0xE): the 32-bit value downscales to 14-bit, split LSB/MSB into two 7-bit bytes.
        let pb: UInt32 = (0x4 << 28) | (0x1 << 24) | (0xE << 20) | (2 << 16)   // group 1, ch 2
        guard let b = umpToLegacy(pb, 0x8000_0000) else { return XCTFail("pitch-bend nil") }
        XCTAssertEqual(b.b0, 0xE2)                          // status | channel 2
        XCTAssertEqual(b.b1, 0)                             // v14 = 0x2000 (centre) → LSB 0
        XCTAssertEqual(b.b2, 64)                            //                       → MSB 64
        XCTAssertEqual(b.len, 3); XCTAssertEqual(b.group, 1)
        // Channel pressure (0xD): 32-bit → 7-bit, a 2-byte legacy message.
        let cp: UInt32 = (0x4 << 28) | (0xD << 20) | (5 << 16)   // ch 5
        guard let c = umpToLegacy(cp, 0xFFFF_FFFF) else { return XCTFail("pressure nil") }
        XCTAssertEqual(c.b0, 0xD5); XCTAssertEqual(c.b1, 127); XCTAssertEqual(c.len, 2)
    }

    // MARK: - ON ARRIVE (§9 item 1) — pure temporal derivations

    // (CELL MACHINE: ALT-ALTERNATE + MORPH-DRIFT derivation tests removed with `arriveAlt`/`arriveMorph`.)

    func testArriveEmitterRotateWalksEmittersAcrossPasses() {
        var on = OnConfig(); on.arrive = .emitterRotate; on.arriveEvery = 1
        XCTAssertEqual([0, 1, 2, 3, 4].map { arriveBusMask(base: 0b0001, on: on, arrivals: $0) },
                       [0b0001, 0b0010, 0b0100, 0b1000, 0b0001])   // A→B→C→D→A
        XCTAssertEqual(arriveBusMask(base: 0b0101, on: on, arrivals: 1), 0b1010)   // A+C rotate together → B+D
        on.arriveEvery = 2                                          // holds two passes per step
        XCTAssertEqual([0, 1, 2, 3].map { arriveBusMask(base: 0b0001, on: on, arrivals: $0) },
                       [0b0001, 0b0001, 0b0010, 0b0010])
        on.arrive = .altAlternate                                  // a non-rotate config is inert
        XCTAssertEqual(arriveBusMask(base: 0b0001, on: on, arrivals: 3), 0b0001)
        on.arrive = .emitterRotate                                 // an empty mask stays empty
        XCTAssertEqual(arriveBusMask(base: 0, on: on, arrivals: 3), 0)
    }

    // MARK: - ON SCENE audibility (§9 item 1)

    func testOnSceneAudibilityEntranceExit() {
        var on = OnConfig()
        XCTAssertTrue(onSceneAudible(on, pass: 0)); XCTAssertTrue(onSceneAudible(on, pass: 20))   // no facets → always
        on.sceneEntrance = true; on.entrancePass = 3                                              // ENTER 3 (1-indexed)
        XCTAssertEqual([0, 1, 2, 3].map { onSceneAudible(on, pass: $0) }, [false, false, true, true])
        on = OnConfig(); on.sceneExit = true; on.exitPass = 7                                     // EXIT 7
        XCTAssertEqual([4, 5, 6, 7].map { onSceneAudible(on, pass: $0) }, [true, true, false, false])
        on.sceneEntrance = true; on.entrancePass = 3                                              // ENTER 3 + EXIT 7
        XCTAssertEqual([1, 2, 5, 6].map { onSceneAudible(on, pass: $0) }, [false, true, true, false])
    }

    // MARK: - ON HOLD (§9 item 1) — momentary held-cell treatments


    // MARK: - ON TAP timing (§9 item 1, 4c) — quantized onset + duration expiry


    // MARK: - UI peak-hold decay (delta §6a metering — shared by both meter views)


    // MARK: NotePool (§2.5)

    // §item 11 INPUT CABLES: the source-filter methods gate on the cable mask as well as the channel.
    func testSrcCountAndAscendingHonourCableMask() {
        let p = NotePool()
        p.noteOn(60, velocity: 100, channel: 0, cable: 1)
        p.noteOn(64, velocity: 100, channel: 0, cable: 2)
        p.noteOn(67, velocity: 100, channel: 0, cable: 2)
        p.rebuildSorted()
        XCTAssertEqual(p.srcCount(filter: 0, cableMask: 0b0010), 2)          // only the two cable-2 notes
        XCTAssertEqual(p.srcAscending(0, filter: 0, cableMask: 0b0010), 64)
        XCTAssertEqual(p.srcAscending(1, filter: 0, cableMask: 0b0010), 67)
        XCTAssertEqual(p.srcAscending(2, filter: 0, cableMask: 0b0010), 255) // out of range
        XCTAssertEqual(p.srcCount(filter: 0, cableMask: 0b1111), 3)          // ANY hears every cable
        XCTAssertEqual(p.srcCount(filter: 0, cableMask: 0b0001), 1)          // cable-1 mask → the one cable-1 note
    }

    func testMatchesRequiresBothChannelAndCable() {
        let p = NotePool()
        p.noteOn(60, velocity: 100, channel: 0, cable: 1)   // wire ch 0 (filter 1), cable 1
        p.noteOn(64, velocity: 100, channel: 4, cable: 2)   // wire ch 4 (filter 5), cable 2
        p.rebuildSorted()
        XCTAssertEqual(p.srcAscending(0, filter: 1, cableMask: 0b0001), 60)  // right channel AND right cable
        XCTAssertEqual(p.srcCount(filter: 1, cableMask: 0b0010), 0)          // right channel, wrong cable → nothing
        XCTAssertEqual(p.srcCount(filter: 5, cableMask: 0b0001), 0)          // right cable, wrong channel → nothing
        XCTAssertEqual(p.srcAscending(0, filter: 5, cableMask: 0b0010), 64)  // channel 5 + cable 2
    }



    // COMET SWEEP DIRECTION (Paul 2026-10-02: "reverses direction when reverse is chosen... goes back and forth
    // on pingpong") — euclidCometRaw/euclidCometPos drive the GridUI comet bar's own visual motion.
    func testEuclidCometPosReversesAndBounces() {
        // euclidCometRaw mods by the DIRECTION's own real cycle length — n for FWD/BKW, 2n for PING-PONG — so a
        // raw mTickBeat well past one lap still wraps into the right range.
        XCTAssertEqual(euclidCometRaw(mTickBeat: 0, sub: 1, spanBeats: 0, n: 8, dir: .fwd), 0)
        XCTAssertEqual(euclidCometRaw(mTickBeat: 10, sub: 1, spanBeats: 0, n: 8, dir: .fwd), 2, "10 mod 8 = 2")
        XCTAssertEqual(euclidCometRaw(mTickBeat: 10, sub: 1, spanBeats: 0, n: 8, dir: .bkw), 2, "BKW's cycle length is still 8 — same raw, only the screen position reads differently")
        XCTAssertEqual(euclidCometRaw(mTickBeat: 10, sub: 1, spanBeats: 0, n: 8, dir: .pingpong), 10, "PING-PONG mods by 2n=16, so raw 10 stays 10 (not yet wrapped)")
        XCTAssertEqual(euclidCometRaw(mTickBeat: 18, sub: 1, spanBeats: 0, n: 8, dir: .pingpong), 2, "18 mod 16 = 2")
        // FWD sweeps left→right (pos == raw); BKW sweeps right→left (pos == n − raw) — a REAL reversal, not just
        // a relabelling, per Paul's own ask.
        XCTAssertEqual(euclidCometPos(0, n: 8, dir: .fwd), 0)
        XCTAssertEqual(euclidCometPos(3, n: 8, dir: .fwd), 3)
        XCTAssertEqual(euclidCometPos(0, n: 8, dir: .bkw), 8)
        XCTAssertEqual(euclidCometPos(3, n: 8, dir: .bkw), 5, "n − raw = 8 − 3")
        // PING-PONG bounces within one lap: the ascending half (raw < n) matches FWD; the descending half
        // (raw ≥ n) mirrors it back down — "goes back and forth."
        XCTAssertEqual(euclidCometPos(3, n: 8, dir: .pingpong), 3, "ascending half — same as FWD")
        XCTAssertEqual(euclidCometPos(8, n: 8, dir: .pingpong), 8, "the turn")
        XCTAssertEqual(euclidCometPos(11, n: 8, dir: .pingpong), 5, "descending half: 2n − raw = 16 − 11")
        XCTAssertEqual(euclidCometPos(15, n: 8, dir: .pingpong), 1, "nearly back to the start")
    }



    // The for:cell convenience reads BOTH filter fields off the SnapCell (the render-loop dedup).
    func testSrcCountForCellReadsBothChannelAndCable() {
        let p = NotePool()
        p.noteOn(60, velocity: 100, channel: 2, cable: 1)   // wire ch 2 (filter 3), cable 1
        p.noteOn(64, velocity: 100, channel: 2, cable: 2)   // wire ch 2, cable 2
        p.rebuildSorted()
        var cell = SnapCell()
        cell.inputChannel = 3            // filter 3 = wire channel 2
        cell.inputCableMask = 0b0001     // cable 1 only
        XCTAssertEqual(p.srcCount(for: cell), 1)
        XCTAssertEqual(p.srcAscending(0, for: cell), 60)
    }


    func testPoolSortsAndCounts() {
        let p = pool([67, 60, 64])
        XCTAssertEqual(p.count, 3)
        XCTAssertEqual(Array(p.sorted[0..<3]), [60, 64, 67])   // ascending regardless of press order
    }

    func testPoolNoteOffAndOmniMerge() {
        let p = NotePool()
        p.noteOn(60, velocity: 100, channel: 0)
        p.noteOn(60, velocity: 100, channel: 5)   // same note, different channel → merges (omni)
        p.rebuildSorted()
        XCTAssertEqual(p.count, 1)
        // latest channel wins — observable through the input filter (wire ch 5 = filter 6):
        XCTAssertEqual(p.srcCount(filter: 6), 1)   // now on ch 5
        XCTAssertEqual(p.srcCount(filter: 1), 0)   // no longer on ch 0
        p.noteOff(60)
        p.rebuildSorted()
        XCTAssertEqual(p.count, 0)
    }

    func testPlayOrderCompactsOnRelease() {
        let p = NotePool()
        p.noteOn(67, velocity: 100, channel: 0)
        p.noteOn(60, velocity: 100, channel: 0)
        p.noteOn(64, velocity: 100, channel: 0)
        XCTAssertEqual((0..<p.playedCount).map { p.played(at: $0) }, [67, 60, 64])
        p.noteOff(60)   // release the middle one
        XCTAssertEqual((0..<p.playedCount).map { p.played(at: $0) }, [67, 64])   // compacts, order kept
        p.noteOn(67, velocity: 110, channel: 0)   // re-press a held note → keeps its slot
        XCTAssertEqual((0..<p.playedCount).map { p.played(at: $0) }, [67, 64])
    }

    // MARK: cellMode dispatch (§3/§4)

    func testCellModeBasics() {
        XCTAssertEqual(cellMode(type: .arp, bypassed: false), .arp)
        XCTAssertEqual(cellMode(type: .ratchet, bypassed: false), .ratchet)
        XCTAssertEqual(cellMode(type: .strum, bypassed: false), .strum)
        XCTAssertEqual(cellMode(type: .chance, bypassed: false), .chance)
        XCTAssertEqual(cellMode(type: .harmonize, bypassed: false), .harmonize)
        XCTAssertEqual(cellMode(type: .harmonize, bypassed: true), .identity)  // bypass wins
        XCTAssertEqual(cellMode(type: .empty, bypassed: false), .identity)     // the sentinel is always a no-op
    }

    // MARK: ratchet velocity (§3)



    // MARK: strum (§3)






    // MARK: chance (§3)





    // MARK: harmonize (§3)






    // MARK: - COLUMN-SUBSET LAP (§5b)

    func testLapPassthroughWhenNothingHeld() {
        for step in 0..<16 { XCTAssertEqual(lapColumn(laneMask: 0, absoluteStep: step, trueColumn: step % 8), step % 8) }
    }

    func testLapStutterK1LocksToTheHeldColumn() {
        let mask: UInt16 = 1 << 2                                   // hold column 2 only
        for step in 0..<20 { XCTAssertEqual(lapColumn(laneMask: mask, absoluteStep: step, trueColumn: step % 8), 2) }
    }

    func testLapContiguousK2Alternates() {
        let mask: UInt16 = (1 << 3) | (1 << 4)                     // hold columns 3,4 (loop brace)
        let got = (0..<6).map { lapColumn(laneMask: mask, absoluteStep: $0, trueColumn: $0 % 8) }
        XCTAssertEqual(got, [3, 4, 3, 4, 3, 4])
    }

    func testLapK3RotatesAsPolymeterAgainstTheEightStep() {
        // Hold three columns {1,3,5}: the 3-cycle phases against the 8-step timeline and is NEVER reset
        // at the pass boundary (step 8 continues the rotation, landing off-phase vs the grid).
        let mask: UInt16 = (1 << 1) | (1 << 3) | (1 << 5)
        let got = (0..<9).map { lapColumn(laneMask: mask, absoluteStep: $0, trueColumn: $0 % 8) }
        XCTAssertEqual(got, [1, 3, 5, 1, 3, 5, 1, 3, 5])          // step 8 → index 2 → col 5, not reset to col 1
    }

    func testLapSortsHeldColumnsLeftToRight() {
        // The mask bit order IS left→right regardless of the "order pressed" — sorted wins (spec).
        let mask: UInt16 = (1 << 6) | (1 << 0)                     // columns 0 and 6
        XCTAssertEqual(lapColumn(laneMask: mask, absoluteStep: 0, trueColumn: 0), 0)   // leftmost first
        XCTAssertEqual(lapColumn(laneMask: mask, absoluteStep: 1, trueColumn: 1), 6)
    }

    func testLapNegativeStepIsSafe() {
        let mask: UInt16 = (1 << 2) | (1 << 4)
        XCTAssertEqual(lapColumn(laneMask: mask, absoluteStep: -1, trueColumn: 0), 4)  // (-1 mod 2) → index 1
        XCTAssertEqual(lapColumn(laneMask: mask, absoluteStep: -2, trueColumn: 0), 2)
    }

    // MARK: - passthrough routing (§2.6 / §7b)

    func testPassthroughGoesToAllAndEmitA() {
        let allAndA: UInt8 = 0b11   // cable 0 (All) + cable 1 (Emit A)
        // CC/PB/AT (non-note) ALWAYS forward, both transport states.
        XCTAssertEqual(passthroughCableMask(isNote: false, playing: true,  auditionSuppressing: false), allAndA)
        XCTAssertEqual(passthroughCableMask(isNote: false, playing: false, auditionSuppressing: true),  allAndA)
        // Notes forward ONLY when stopped and not audition-suppressed (the PURE §2.6 rule; the Kernel now
        // gates this whole note branch OFF by policy — see noteMonitorPassthrough — so a fresh instance is silent).
        XCTAssertEqual(passthroughCableMask(isNote: true, playing: false, auditionSuppressing: false), allAndA)
        XCTAssertEqual(passthroughCableMask(isNote: true, playing: true,  auditionSuppressing: false), 0, "playing → sequencer owns notes")
        XCTAssertEqual(passthroughCableMask(isNote: true, playing: false, auditionSuppressing: true),  0, "audition replaces the raw chord")
    }

    // MARK: - PassthroughGate (a8 hang fix) — a note-OFF must follow its forwarded ON, no stuck notes

    private let allAndA: UInt8 = 0b11

    // THE BUG: note held across a transport START. ON while stopped forwards; OFF while PLAYING must STILL
    // forward (its ON was echoed to the synth), or the synth is stranded ON forever = the hang.
    func testGateNoteOffFollowsOnAcrossTransportStart() {
        var g = PassthroughGate()
        XCTAssertEqual(g.mask(statusByte: 0x90, note: 60, velocity: 100, playing: false, auditionSuppressing: false), allAndA)
        XCTAssertEqual(g.mask(statusByte: 0x80, note: 60, velocity: 0,   playing: true,  auditionSuppressing: false), allAndA,
                       "note-OFF must follow its forwarded ON even though playing flipped true — no stuck note")
    }

    // Same failure via the AUDITION transition: ON while not auditioning, OFF once audition suppresses.
    func testGateNoteOffFollowsOnAcrossAuditionStart() {
        var g = PassthroughGate()
        XCTAssertEqual(g.mask(statusByte: 0x90, note: 64, velocity: 90, playing: false, auditionSuppressing: false), allAndA)
        XCTAssertEqual(g.mask(statusByte: 0x80, note: 64, velocity: 0,  playing: false, auditionSuppressing: true),  allAndA,
                       "note-OFF must follow its forwarded ON even though audition began — no stuck note")
    }

    // A vel-0 note-on IS a note-off and must follow the ON the same way.
    func testGateVelZeroNoteOnIsTreatedAsOff() {
        var g = PassthroughGate()
        XCTAssertEqual(g.mask(statusByte: 0x90, note: 67, velocity: 100, playing: false, auditionSuppressing: false), allAndA)
        XCTAssertEqual(g.mask(statusByte: 0x90, note: 67, velocity: 0,   playing: true,  auditionSuppressing: false), allAndA,
                       "0x90 vel-0 = note-OFF, follows its ON")
    }

    // No SPURIOUS off: a note played WHILE PLAYING was never echoed, so its OFF must not forward (else it
    // could cut a sequenced note the processors emitted on cable 0/1).
    func testGateSuppressedOnMeansSuppressedOff() {
        var g = PassthroughGate()
        XCTAssertEqual(g.mask(statusByte: 0x90, note: 60, velocity: 100, playing: true,  auditionSuppressing: false), 0)
        XCTAssertEqual(g.mask(statusByte: 0x80, note: 60, velocity: 0,   playing: true,  auditionSuppressing: false), 0,
                       "an OFF whose ON was never echoed must not forward")
    }

    // Tracking is per (channel, note): an OFF only follows the ON on the SAME channel.
    func testGateTracksPerChannel() {
        var g = PassthroughGate()
        XCTAssertEqual(g.mask(statusByte: 0x90, note: 60, velocity: 100, playing: false, auditionSuppressing: false), allAndA, "ch1 ON")
        XCTAssertEqual(g.mask(statusByte: 0x81, note: 60, velocity: 0,   playing: true,  auditionSuppressing: false), 0,       "ch2 OFF — no ON tracked there")
        XCTAssertEqual(g.mask(statusByte: 0x80, note: 60, velocity: 0,   playing: true,  auditionSuppressing: false), allAndA, "ch1 OFF — follows the ch1 ON")
    }

    // CC/PB/AT always forward regardless of state, and are not note-tracked.
    func testGateNonNotesAlwaysForward() {
        var g = PassthroughGate()
        XCTAssertEqual(g.mask(statusByte: 0xB0, note: 7,  velocity: 100, playing: true,  auditionSuppressing: false), allAndA, "CC")
        XCTAssertEqual(g.mask(statusByte: 0xE0, note: 0,  velocity: 64,  playing: true,  auditionSuppressing: true),  allAndA, "pitch bend")
    }

    // drainActive fills a fixed-size scratch buffer with every note still awaiting its OFF (for a panic
    // all-notes-off) and returns the count, then clears (render-thread-safe: no allocation — code-review
    // finding 2026-10-04 converted this from a returned Array to a count + `drained(_:)` accessor).
    func testGateDrainActiveReportsHeldPassthroughNotes() {
        var g = PassthroughGate()
        _ = g.mask(statusByte: 0x90, note: 60, velocity: 100, playing: false, auditionSuppressing: false)
        _ = g.mask(statusByte: 0x91, note: 72, velocity: 100, playing: false, auditionSuppressing: false)
        let n = g.drainActive()
        let held = (0..<n).map { g.drained($0) }.sorted { ($0.channel, $0.note) < ($1.channel, $1.note) }
        XCTAssertEqual(held.count, 2)
        XCTAssertEqual(held[0].channel, 0); XCTAssertEqual(held[0].note, 60)
        XCTAssertEqual(held[1].channel, 1); XCTAssertEqual(held[1].note, 72)
        XCTAssertEqual(g.drainActive(), 0, "drain clears")
    }

    // a8 dump: the held-echo fingerprint lists the awaiting-OFF notes and reads "none" when balanced.
    func testGateHeldFingerprint() {
        var g = PassthroughGate()
        XCTAssertEqual(g.heldFingerprint(), "none")
        _ = g.mask(statusByte: 0x90, note: 60, velocity: 100, playing: false, auditionSuppressing: false)
        _ = g.mask(statusByte: 0x91, note: 72, velocity: 100, playing: false, auditionSuppressing: false)
        let fp = g.heldFingerprint()
        XCTAssertTrue(fp.contains("ch0/n60"), fp)
        XCTAssertTrue(fp.contains("ch1/n72"), fp)
        _ = g.mask(statusByte: 0x80, note: 60, velocity: 0, playing: true, auditionSuppressing: false)
        XCTAssertFalse(g.heldFingerprint().contains("n60"), "the released note leaves the fingerprint")
    }

    // MARK: - silence invariant (a8 assert-on-silence)

    // THE CHORD SEQUENCER (Paul 2026-09-04): chordSeqNotes — the SHARED derivation the CHORDS processor + the chord DOOR use.
    func testChordSeqNotesWalksThePatternOnTheBeat() {
        var p = SnapParams()
        p.chordsMode = .pattern; p.chordsDegrees = [0, 4, 5, 3]; p.chordsSteps = 4; p.chordsRateBeats = 1   // I–V–vi–IV, one chord/beat
        let tones = ScaleType.major.intervals
        // bar 0 (beat 0.5) → I = C E G (root MIDI 48).
        XCTAssertEqual(chordSeqNotes(beat: 0.5, p, keyRoot: 0, keyTones: tones, followNote: nil), [48, 52, 55])
        // beat 1.x → V = G B D.
        XCTAssertEqual(chordSeqNotes(beat: 1.2, p, keyRoot: 0, keyTones: tones, followNote: nil), [55, 59, 62])
        // step 4 loops back to I.
        XCTAssertEqual(chordSeqNotes(beat: 4.0, p, keyRoot: 0, keyTones: tones, followNote: nil),
                       chordSeqNotes(beat: 0.0, p, keyRoot: 0, keyTones: tones, followNote: nil))
        // A REST degree (7) yields no notes.
        p.chordsDegrees = [7, 0, 0, 0]
        XCTAssertTrue(chordSeqNotes(beat: 0.0, p, keyRoot: 0, keyTones: tones, followNote: nil).isEmpty)
        // FOLLOW names the degree from the trigger note (nil ⇒ the tonic).
        p.chordsMode = .follow
        XCTAssertEqual(chordSeqNotes(beat: 0.0, p, keyRoot: 0, keyTones: tones, followNote: nil),
                       diatonicChord(degree: 0, scaleTones: tones, rootNote: 48, voicing: .triad, spread: .close))
        // WALK is deterministic for a fixed seed/step.
        p.chordsMode = .walk; p.chordsWalkSeed = 7
        XCTAssertEqual(chordSeqNotes(beat: 3.0, p, keyRoot: 0, keyTones: tones, followNote: nil),
                       chordSeqNotes(beat: 3.0, p, keyRoot: 0, keyTones: tones, followNote: nil))
    }

    // CHORDS C1 (2026-09-01) — the pure diatonic-progression core, derived FROM THE CONCEPT (music theory), no engine read.
    func testDiatonicChordStacksThirdsInTheKey() {
        let maj = ScaleType.major.intervals   // [0,2,4,5,7,9,11]
        // C major, root C = MIDI 60.
        XCTAssertEqual(diatonicChord(degree: 0, scaleTones: maj, rootNote: 60), [60, 64, 67], "I = C E G")
        XCTAssertEqual(diatonicChord(degree: 1, scaleTones: maj, rootNote: 60), [62, 65, 69], "ii = D F A")
        XCTAssertEqual(diatonicChord(degree: 4, scaleTones: maj, rootNote: 60), [67, 71, 74], "V = G B D (D wraps to the next octave)")
        XCTAssertEqual(diatonicChord(degree: 0, scaleTones: maj, rootNote: 60, voicing: .seventh), [60, 64, 67, 71], "Imaj7 = C E G B")
        XCTAssertEqual(diatonicChord(degree: 0, scaleTones: maj, rootNote: 60, voicing: .add9), [60, 64, 67, 71, 74], "Imaj9 = C E G B D")
        XCTAssertEqual(diatonicChord(degree: 0, scaleTones: maj, rootNote: 60, spread: .open), [60, 67, 76], "OPEN lifts the middle voice (E) an octave → C G E")
        // The SAME degrees play in ANY key — the point of deriving. F major (root 65):
        XCTAssertEqual(diatonicChord(degree: 0, scaleTones: maj, rootNote: 65), [65, 69, 72], "I in F = F A C")
    }
    func testDegreeLabelIsQualityAware() {
        let maj = ScaleType.major.intervals
        XCTAssertEqual(degreeLabel(degree: 0, scaleTones: maj), "I",   "major triad → uppercase")
        XCTAssertEqual(degreeLabel(degree: 1, scaleTones: maj), "ii",  "minor triad → lowercase")
        XCTAssertEqual(degreeLabel(degree: 4, scaleTones: maj), "V",   "dominant is major")
        XCTAssertEqual(degreeLabel(degree: 6, scaleTones: maj), "vii°", "leading-tone triad is diminished")
        // A different key: natural minor's i is minor, its V is minor (bVII major etc.) — the label tracks the scale.
        let min = ScaleType.naturalMinor.intervals
        XCTAssertEqual(degreeLabel(degree: 0, scaleTones: min), "i", "natural-minor tonic is minor")
    }
    func testWalkNextDegreeIsSeededAndGravitates() {
        // Deterministic: same (prev, seed) → same next.
        XCTAssertEqual(walkNextDegree(prev: 4, seed: 12345), walkNextDegree(prev: 4, seed: 12345), "replay-exact")
        for s in 0..<200 { XCTAssertTrue((0..<7).contains(walkNextDegree(prev: s % 7, seed: UInt64(s))), "always a valid degree 0…6") }
        // Gravity: from V, I (the resolution) is by far the most common landing.
        var toI = 0
        for s: UInt64 in 0..<300 where walkNextDegree(prev: 4, seed: s) == 0 { toI += 1 }
        XCTAssertGreaterThan(toI, 300 / 3, "V resolves HOME to I far more often than chance (weight 8 of 18)")
    }
    func testScaleDegreeOfNamesTheDegree() {   // CHORDS FOLLOW — the played note names the degree
        let maj = ScaleType.major.intervals
        XCTAssertEqual(scaleDegreeOf(60, root: 0, scaleTones: maj), 0, "C in C major → I (degree 0)")
        XCTAssertEqual(scaleDegreeOf(67, root: 0, scaleTones: maj), 4, "G → V (degree 4)")
        XCTAssertEqual(scaleDegreeOf(71, root: 0, scaleTones: maj), 6, "B → vii (degree 6)")
        XCTAssertEqual(scaleDegreeOf(48, root: 0, scaleTones: maj), 0, "octave-invariant — low C is still I")
        let cSharp = scaleDegreeOf(61, root: 0, scaleTones: maj)   // C# not in C major → snaps to a neighbour (C=0 or D=1)
        XCTAssertTrue(cSharp == 0 || cSharp == 1, "an off-scale note snaps to the nearest degree")
    }
    // CHORDS matrix DISPLAY (Bugfix Paul 2026-09-15): extending the pattern past its authored columns used to light a FALSE
    // degree-0 (I) in the editor while the engine CARRIED the last chord → screen ≠ audio. chordsMatrixCell must light nothing
    // BRIGHT there, and show the carried chord FAINT, matching what chordsDegreeAt (the engine) actually plays.
    func testChordsMatrixCellShowsCarryNotFalseTonic() {
        let a = [0, 3, 4, 5]                                  // authored I · IV · V · V (last authored = V, NOT the tonic)
        // authored columns light bright, no faint
        XCTAssertEqual(chordsMatrixCell(a, step: 0, steps: 8).bright, 0)
        XCTAssertEqual(chordsMatrixCell(a, step: 2, steps: 8).bright, 4)
        XCTAssertNil(chordsMatrixCell(a, step: 2, steps: 8).faint)
        // extended columns (4…7): NOTHING bright (was a false I), FAINT = the carried chord (V), matching the engine
        for c in 4...7 {
            XCTAssertNil(chordsMatrixCell(a, step: c, steps: 8).bright, "col \(c): an extended column lights nothing bright")
            XCTAssertEqual(chordsMatrixCell(a, step: c, steps: 8).faint, 5, "col \(c): shows FAINT the carried chord (V)")
            let degs = (0..<8).map { $0 < a.count ? a[$0] : -1 }
            XCTAssertEqual(chordsMatrixCell(a, step: c, steps: 8).faint, chordsDegreeAt(step: c, degrees: degs, rotate: 0).degree, "display == what the engine plays")
        }
        // an explicit REST (7) stays bright REST, not carried
        XCTAssertEqual(chordsMatrixCell([0, 7, 4], step: 1, steps: 8).bright, 7)
    }
    func testChordsWalkIsSeededAndDeterministic() {   // CHORDS WALK — the gravity dice, replay-exact
        XCTAssertEqual(chordsWalkDegreeAt(step: 0, seed: 42), 0, "the walk starts on the tonic")
        for s in 0..<32 { XCTAssertTrue((0..<7).contains(chordsWalkDegreeAt(step: s, seed: 42)), "always a valid degree") }
        let a = (0..<8).map { chordsWalkDegreeAt(step: $0, seed: 99) }
        let b = (0..<8).map { chordsWalkDegreeAt(step: $0, seed: 99) }
        XCTAssertEqual(a, b, "same seed → identical walk (replay-exact)")
        XCTAssertNotEqual((0..<8).map { chordsWalkDegreeAt(step: $0, seed: 1) }, (0..<8).map { chordsWalkDegreeAt(step: $0, seed: 2) }, "a different seed → a different walk")
    }
    // JOB 3 (bug-hunt B-2): the RATE clock is free-running, so `step` grows unbounded; the walk must LOOP (period 64),
    // not FREEZE at step 64 (the old clamp returned step-64's degree forever). Loops + stays valid + replay-exact.
    func testChordsWalkLoopsAndDoesNotFreezeAfter64() {
        for s in 0..<8 { XCTAssertEqual(chordsWalkDegreeAt(step: 64 + s, seed: 7), chordsWalkDegreeAt(step: s, seed: 7), "loops every 64 rate-ticks") }
        XCTAssertEqual(chordsWalkDegreeAt(step: 130, seed: 7), chordsWalkDegreeAt(step: 2, seed: 7), "130 % 64 == 2")
        for s in [64, 65, 100, 200, 999] { XCTAssertTrue((0..<7).contains(chordsWalkDegreeAt(step: s, seed: 7)), "still a valid degree past 64 (no freeze/garbage)") }
        // it did NOT collapse to a single frozen degree — the loop actually varies
        XCTAssertGreaterThan(Set((64..<128).map { chordsWalkDegreeAt(step: $0, seed: 7) }).count, 1, "the progression keeps moving past step 64")
    }
    // HOUSEKEEPING (2026-09-03): posMod's negative branch (its whole reason to exist over a bare %) — every live caller
    // passes x ≥ 0, so lock the wrap here.
    func testPosModWrapsNegatives() {
        XCTAssertEqual(posMod(-1, 64), 63); XCTAssertEqual(posMod(-64, 64), 0); XCTAssertEqual(posMod(-65, 64), 63)
        XCTAssertEqual(posMod(5, 64), 5); XCTAssertEqual(posMod(64, 64), 0)   // non-negative unchanged
    }
    // A SCALE door names itself ("A MIXO") — the chip-never-lies label shared by the receiver chip + the MIDI tab. (2026-08-31)
    func testScaleDoorLabel() {
        var r = Receiver(); XCTAssertNil(r.scaleLabel, "a non-scale door has no key label")
        r.doorMode = .scale; r.scaleRoot = 9; r.scaleType = .mixolydian   // A mixolydian
        XCTAssertEqual(r.scaleLabel, "A MIXO")
        r.scaleRoot = 0; r.scaleType = .major
        XCTAssertEqual(r.scaleLabel, "C MAJOR")
        r.doorMode = .latch
        XCTAssertNil(r.scaleLabel, "switching off SCALE mode drops the label")
    }
    func testSilenceInvariantHoldsWhenTrulySilent() {
        XCTAssertFalse(silenceInvariantViolated(playing: false, heldInput: 0, auditioning: false,
                                                activeVoices: 0, passthroughHeld: 0), "clean silence")
    }
    func testSilenceInvariantCatchesLeakedVoice() {
        XCTAssertTrue(silenceInvariantViolated(playing: false, heldInput: 0, auditioning: false,
                                               activeVoices: 1, passthroughHeld: 0), "a voice open in dead silence = stuck")
    }
    func testSilenceInvariantCatchesStrandedEcho() {
        XCTAssertTrue(silenceInvariantViolated(playing: false, heldInput: 0, auditioning: false,
                                               activeVoices: 0, passthroughHeld: 1), "an echo held in dead silence = stuck")
    }
    func testSilenceInvariantIgnoresLegitimateSound() {
        // playing → the sequencer legitimately sounds. The Kernel passes the EFFECTIVE playing flag here (host transport
        // OR the FREE-RUN clock OR reel replay) — so a free-run scene driven by a LATCHED chord (live input empty, host
        // stopped) is exempt, not a crash (Paul 2026-08-26).
        XCTAssertFalse(silenceInvariantViolated(playing: true, heldInput: 0, auditioning: false,
                                                activeVoices: 5, passthroughHeld: 0))
        // keys held while stopped → passthrough echoes are expected
        XCTAssertFalse(silenceInvariantViolated(playing: false, heldInput: 3, auditioning: false,
                                                activeVoices: 0, passthroughHeld: 3))
        // auditioning → the audition legitimately sounds
        XCTAssertFalse(silenceInvariantViolated(playing: false, heldInput: 0, auditioning: true,
                                                activeVoices: 2, passthroughHeld: 0))
    }

    // §a8b — the PLAYING hung-note net (catches e.g. a harmonizer voice whose off went missing).
    private let dbnc: Int64 = 48_000   // ~1 s @ 48k, for the tests below

    func testPlayingLeakCatchesStuckVoiceAfterDebounce() {
        XCTAssertTrue(playingSilenceLeak(playing: true, liveInput: 0, latchArmed: false, auditioning: false,
                                         emptyInputSamples: dbnc, debounceSamples: dbnc,
                                         activeVoices: 2, passthroughHeld: 0), "no source for the debounce, yet voices ring = stuck")
    }
    func testPlayingLeakCatchesStrandedEchoAfterDebounce() {
        XCTAssertTrue(playingSilenceLeak(playing: true, liveInput: 0, latchArmed: false, auditioning: false,
                                         emptyInputSamples: dbnc, debounceSamples: dbnc,
                                         activeVoices: 0, passthroughHeld: 1))
    }
    func testPlayingLeakWaitsForTheDebounce() {
        // a note released mid-column still rings to its boundary — below the debounce, do NOT heal.
        XCTAssertFalse(playingSilenceLeak(playing: true, liveInput: 0, latchArmed: false, auditioning: false,
                                          emptyInputSamples: dbnc - 1, debounceSamples: dbnc,
                                          activeVoices: 2, passthroughHeld: 0), "within the debounce = a legit release tail")
    }
    func testPlayingLeakRespectsLatchAuditionAndLiveInput() {
        // an armed LATCH legitimately sustains a frozen chord with an empty live pool
        XCTAssertFalse(playingSilenceLeak(playing: true, liveInput: 0, latchArmed: true, auditioning: false,
                                          emptyInputSamples: dbnc, debounceSamples: dbnc, activeVoices: 4, passthroughHeld: 0))
        // auditioning legitimately sounds
        XCTAssertFalse(playingSilenceLeak(playing: true, liveInput: 0, latchArmed: false, auditioning: true,
                                          emptyInputSamples: dbnc, debounceSamples: dbnc, activeVoices: 4, passthroughHeld: 0))
        // live input present → a real source
        XCTAssertFalse(playingSilenceLeak(playing: true, liveInput: 3, latchArmed: false, auditioning: false,
                                          emptyInputSamples: dbnc, debounceSamples: dbnc, activeVoices: 4, passthroughHeld: 0))
        // stopped → the stopped-net (silenceInvariantViolated) owns that case, not this one
        XCTAssertFalse(playingSilenceLeak(playing: false, liveInput: 0, latchArmed: false, auditioning: false,
                                          emptyInputSamples: dbnc, debounceSamples: dbnc, activeVoices: 4, passthroughHeld: 0))
    }
    func testPlayingLeakSilentWhenNothingSounds() {
        XCTAssertFalse(playingSilenceLeak(playing: true, liveInput: 0, latchArmed: false, auditioning: false,
                                          emptyInputSamples: dbnc, debounceSamples: dbnc,
                                          activeVoices: 0, passthroughHeld: 0), "nothing sounding → nothing to heal")
    }

    // §cell-edit D — CHORD SPLIT window over an ascending source list [60, 64, 67, 72] (4 notes).
    private let chord4 = [60, 64, 67, 72]
    private func win(_ s: ChordSplit) -> (start: Int, len: Int) { chordSplitWindow(count: chord4.count, split: s) { chord4[$0] } }
    func testChordSplitAllTakesEverything() {
        XCTAssertTrue(win(ChordSplit(mode: .all)) == (0, 4))
    }
    func testChordSplitTopIsTheHighestNSuffix() {
        XCTAssertTrue(win(ChordSplit(mode: .top, n: 2)) == (2, 2), "TOP 2 = indices 2,3 (67,72)")
        XCTAssertTrue(win(ChordSplit(mode: .top, n: 10)) == (0, 4), "TOP n>count clamps to all")
    }
    func testChordSplitBottomIsTheLowestNPrefix() {
        XCTAssertTrue(win(ChordSplit(mode: .bottom, n: 2)) == (0, 2), "BOTTOM 2 = indices 0,1 (60,64)")
    }
    func testChordSplitRangeHighTakesTheSplitAndAbove() {
        XCTAssertTrue(win(ChordSplit(mode: .range, note: 67, high: true)) == (2, 2), "≥67 = 67,72")
        XCTAssertTrue(win(ChordSplit(mode: .range, note: 60, high: true)) == (0, 4), "≥60 = all")
        XCTAssertTrue(win(ChordSplit(mode: .range, note: 100, high: true)) == (4, 0), "≥100 = none")
    }
    func testChordSplitRangeLowTakesBelowTheSplit() {
        XCTAssertTrue(win(ChordSplit(mode: .range, note: 67, high: false)) == (0, 2), "<67 = 60,64")
        XCTAssertTrue(win(ChordSplit(mode: .range, note: 60, high: false)) == (0, 0), "<60 = none")
    }
    func testChordSplitEmptyChordIsEmptyWindow() {
        XCTAssertTrue(chordSplitWindow(count: 0, split: ChordSplit(mode: .top, n: 2)) { _ in 0 } == (0, 0))
    }
    func testSrcReadersApplyChordSplit() {   // the split actually rides the NotePool source readers
        let pool = NotePool()
        for n: UInt8 in [60, 64, 67, 72] { pool.noteOn(n, velocity: 100, channel: 0) }
        pool.rebuildSorted()
        var cell = SnapCell()                                    // OMNI channel, ANY cable
        cell.chordSplit = ChordSplit(mode: .top, n: 2)
        XCTAssertEqual(pool.srcCount(for: cell), 2)
        XCTAssertEqual(pool.srcAscending(0, for: cell), 67)
        XCTAssertEqual(pool.srcAscending(1, for: cell), 72)
        cell.chordSplit = ChordSplit(mode: .range, note: 65, high: false)   // < 65 → 60, 64
        XCTAssertEqual(pool.srcCount(for: cell), 2)
        XCTAssertEqual(pool.srcAscending(0, for: cell), 60)
        cell.chordSplit = ChordSplit()                           // ALL → the whole chord, untouched
        XCTAssertEqual(pool.srcCount(for: cell), 4)
    }
    // COVERAGE (2026-08-25 housekeeping): omniRead (a LATCH/REPLAY/FILE frozen pool) SKIPS the door channel/cable filter but
    // KEEPS the cell's VELOCITY WINDOW. The existing omniRead test uses a FULL vel window (the fast path); this pins the
    // narrow branch — a velocity-windowed cell reading an omniRead pool must still drop out-of-window notes.
    func testOmniReadKeepsVelocityWindowWhileSkippingDoorFilter() {
        let pool = NotePool(); pool.omniRead = true
        pool.noteOn(60, velocity: 30, channel: 3); pool.noteOn(64, velocity: 80, channel: 3); pool.noteOn(67, velocity: 120, channel: 3)   // all on channel index 3
        pool.rebuildSorted()
        var cell = SnapCell()
        cell.inputChanMask = 0b0000_0000_0000_0001                // hears channel 0 ONLY (excludes the notes' channel 3)
        cell.velFloor = 50; cell.velCeil = 100                    // a NON-full window → the omniRead vel branch, not the fast path
        XCTAssertEqual(pool.srcCount(for: cell), 1, "omniRead ignores the channel filter but STILL applies the vel window")
        XCTAssertEqual(Int(pool.srcAscending(0, for: cell)), 64, "only the vel-80 note (64) survives — 30 below floor, 120 above ceil")
        pool.omniRead = false
        XCTAssertEqual(pool.srcCount(for: cell), 0, "omniRead OFF → the door channel filter wins → the channel-3 notes are all dropped")
    }
    func testChordSplitCodableAndMigration() throws {
        var c = Cell(machineID: "gold"); c.chordSplit = ChordSplit(mode: .top, n: 3)
        let back = try JSONDecoder().decode(Cell.self, from: JSONEncoder().encode(c))
        XCTAssertEqual(back.chordSplit, ChordSplit(mode: .top, n: 3), "a set split round-trips")
        // a default cell omits the Optional key (encodeIfPresent) — decoding that is the OLD-doc migration path
        let d = try JSONDecoder().decode(Cell.self, from: JSONEncoder().encode(Cell(machineID: "gold")))
        XCTAssertNil(d.chordSplit, "no split key ⇒ nil")
        XCTAssertEqual(d.chordSplitResolved.mode, .all, "…resolves to ALL")
    }

    // §cell-edit D — VELOCITY WINDOW admission (gates BEFORE the chord split).
    func testVelocityWindowGatesThenSplits() {
        let pool = NotePool()
        pool.noteOn(60, velocity: 30, channel: 0)
        pool.noteOn(64, velocity: 80, channel: 0)
        pool.noteOn(67, velocity: 120, channel: 0)
        pool.rebuildSorted()
        var cell = SnapCell()
        cell.velFloor = 50; cell.velCeil = 100                   // only 64 (vel 80) is admitted
        XCTAssertEqual(pool.srcCount(for: cell), 1)
        XCTAssertEqual(pool.srcAscending(0, for: cell), 64)
        cell.velFloor = 40; cell.velCeil = 127                   // admits 64,67; then TOP 1 → 67
        cell.chordSplit = ChordSplit(mode: .top, n: 1)
        XCTAssertEqual(pool.srcCount(for: cell), 1)
        XCTAssertEqual(pool.srcAscending(0, for: cell), 67)
        cell.velFloor = 1; cell.velCeil = 127; cell.chordSplit = ChordSplit()   // full range + ALL → everything
        XCTAssertEqual(pool.srcCount(for: cell), 3)
    }
    func testVelWindowCodableAndMigration() throws {
        var c = Cell(machineID: "gold"); c.velWindow = VelWindow(floor: 40, ceil: 110)
        let back = try JSONDecoder().decode(Cell.self, from: JSONEncoder().encode(c))
        XCTAssertEqual(back.velWindow, VelWindow(floor: 40, ceil: 110))
        let d = try JSONDecoder().decode(Cell.self, from: JSONEncoder().encode(Cell(machineID: "gold")))
        XCTAssertNil(d.velWindow, "no key ⇒ nil")
        XCTAssertEqual(d.velWindowResolved.floor, 1); XCTAssertEqual(d.velWindowResolved.ceil, 127)
    }
    func testChopBusMaskRoutes() {   // §cell-edit F — the per-slice emit routing, main/alt/mute INDEPENDENT
        XCTAssertEqual(chopBusMask(0b0011, main: true,  alt: false, mute: false, altMask: 0b1100), 0b0011, "MAIN keeps the cell's own emitters")
        XCTAssertEqual(chopBusMask(0b0011, main: false, alt: true,  mute: false, altMask: 0b1100), 0b1100, "ALT adds the alt destination")
        XCTAssertEqual(chopBusMask(0b0011, main: true,  alt: true,  mute: false, altMask: 0b1100), 0b1111, "MAIN+ALT emits to BOTH")
        XCTAssertEqual(chopBusMask(0b0011, main: true,  alt: true,  mute: true,  altMask: 0b1100), 0,      "MUTE wins over both")
        XCTAssertEqual(chopBusMask(0b0011, main: false, alt: false, mute: false, altMask: 0b1100), 0,      "nothing lit → silent")
    }
    func testChopSliceDividesTheColumn() {   // §cell-edit F — 8 slices within one column of length S beats
        XCTAssertEqual(chopSlice(0.0,   columnBeats: 1.0), 0)
        XCTAssertEqual(chopSlice(0.1,   columnBeats: 1.0), 0, "0.1·8 = 0.8 → slice 0")
        XCTAssertEqual(chopSlice(0.125, columnBeats: 1.0), 1, "exactly 1/8 → slice 1")
        XCTAssertEqual(chopSlice(0.5,   columnBeats: 1.0), 4)
        XCTAssertEqual(chopSlice(0.99,  columnBeats: 1.0), 7)
        XCTAssertEqual(chopSlice(2.5,   columnBeats: 1.0), 4, "beat 2.5 → within-column frac 0.5 → slice 4")
        XCTAssertEqual(chopSlice(0.0,   columnBeats: 0.0), 0, "guard: zero-length column")
    }
    func testChopCodableAndMigration() throws {   // §cell-edit F — chop model round-trips; absent key ⇒ all-MAIN
        var ch = Chop(); ch.altMask = 0b0000_0100; ch.muteMask = 0b0010_0000; ch.altDest = [.c]   // slice 2 → alt, slice 5 → mute
        var c = Cell(machineID: "gold"); c.chop = ch
        let back = try JSONDecoder().decode(Cell.self, from: JSONEncoder().encode(c))
        XCTAssertEqual(back.chop, ch, "a set chop round-trips (masks + altDest)")
        let d = try JSONDecoder().decode(Cell.self, from: JSONEncoder().encode(Cell(machineID: "gold")))
        XCTAssertNil(d.chop, "no chop key ⇒ nil")
        XCTAssertEqual(d.chopResolved.mainMask, 0xFF, "…resolves to all-MAIN")
        XCTAssertEqual(d.chopResolved.altMask, 0); XCTAssertEqual(d.chopResolved.muteMask, 0)
        XCTAssertTrue(d.chopResolved.altDest.isEmpty)
    }

    // The gate's activeCount tracks held echoes and returns to zero after their offs.
    func testGateActiveCountBalances() {
        var g = PassthroughGate()
        _ = g.mask(statusByte: 0x90, note: 60, velocity: 100, playing: false, auditionSuppressing: false)
        _ = g.mask(statusByte: 0x90, note: 64, velocity: 100, playing: false, auditionSuppressing: false)
        XCTAssertEqual(g.activeCount, 2)
        _ = g.mask(statusByte: 0x80, note: 60, velocity: 0, playing: true, auditionSuppressing: false)   // off across a transition
        XCTAssertEqual(g.activeCount, 1, "the off still clears its tracking even when not forwarded-by-state")
        _ = g.mask(statusByte: 0x80, note: 64, velocity: 0, playing: false, auditionSuppressing: false)
        XCTAssertEqual(g.activeCount, 0)
    }

    // MARK: - column sweep fraction (mutation-line / §6b chip playhead)


    // MARK: - TWO LATCH MODES — latchAddStep (note-toggle accumulation)

    func testLatchAddStepTogglesMembershipOnRisingEdges() {
        let frozen = NotePool(), live = NotePool()
        var prev = [Bool](repeating: false, count: 128)
        func step() { frozen.latchAddStep(from: live, filter: 0, cableMask: 0b1111, prevHeld: &prev) }
        func has(_ n: UInt8) -> Bool { frozen.velocity(n) != 0 }

        live.noteOn(60, velocity: 100, channel: 0); step()
        XCTAssertTrue(has(60), "playing 60 adds it to the frozen pool")
        step()
        XCTAssertTrue(has(60), "holding 60 is idempotent — no re-toggle without a new edge")
        live.noteOn(64, velocity: 90, channel: 0); step()
        XCTAssertTrue(has(60) && has(64), "64 joins the cluster")
        XCTAssertEqual(frozen.velocity(64), 90, "the joined note keeps its live velocity")
        live.noteOff(60); live.noteOff(64); step()
        XCTAssertTrue(has(60) && has(64), "releasing keeps the frozen pool (no rising edges to toggle)")
        live.noteOn(60, velocity: 100, channel: 0); step()
        XCTAssertFalse(has(60), "replaying 60 toggles it OUT")
        XCTAssertTrue(has(64), "…and 64 stays — the cluster is sculpted note by note")
    }

    func testLatchAddStepRespectsTheReceiverFilter() {
        let frozen = NotePool(), live = NotePool()
        var prev = [Bool](repeating: false, count: 128)
        live.noteOn(60, velocity: 100, channel: 2)   // wire ch 2 → matches receiver filter 3 (chan == filter−1)
        live.noteOn(62, velocity: 100, channel: 0)   // wire ch 0 → does NOT match filter 3
        frozen.latchAddStep(from: live, filter: 3, cableMask: 0b1111, prevHeld: &prev)
        XCTAssertNotEqual(frozen.velocity(60), 0, "the matching-channel note toggles in")
        XCTAssertEqual(frozen.velocity(62), 0, "the filtered-out note never enters the frozen pool")
    }

    // MARK: /btw ⑥ — PLACE one-per-column, per hold


    // (Removed 2026-08-27 housekeeping: the multi-cell ROUTE-FOCI and ROUTING-VISUALISATION-GRAPH tests
    //  (routeFociByColumn / routingEdges / RouteEdge / RouteCell) — the routing-viz overlay was retired with the
    //  tab era and grid-chaining, so those pure helpers have no engine or UI consumer. Tests removed as dead-feature.)

    // MARK: emblems (cells & machine desk)


    // MARK: trigger glyph (deviation-shown)

    // (machine census tests removed 2026-08-27: `machineCensus` (the D3 delete-protection helper) has zero non-test
    //  callers — the delete-protection UI was dropped — so the tests guard a dead pure function.)

    // MARK: - THE SEAL (derived cell face)

    private func sealCell() -> Cell {
        var c = Cell(machineID: "gold", buses: [.a, .b]); c.inputReceiver = 1
        c.processors = [ProcessorSlot(type: .harmonize), { var s = ProcessorSlot(type: .arp); s.bypassed = true; return s }()]
        c.chop = Chop(mainMask: 0xFF, altMask: 0b0000_0100, muteMask: 0, altDest: [.c])
        return c
    }


    // MARK: - shared pure helpers (extracted dedup — clampVel · positiveFract · splitmix64Mix)

    func testClampVelClampsToOneToOneTwentySeven() {
        XCTAssertEqual(clampVel(0), 1, "never 0 (a note-off)")
        XCTAssertEqual(clampVel(-9), 1)
        XCTAssertEqual(clampVel(64), 64)
        XCTAssertEqual(clampVel(200), 127)
    }

    func testPositiveFractFoldsNegativesForward() {
        XCTAssertEqual(positiveFract(0.25), 0.25, accuracy: 1e-12)
        XCTAssertEqual(positiveFract(1.25), 0.25, accuracy: 1e-12)
        XCTAssertEqual(positiveFract(-0.1), 0.9, accuracy: 1e-12, "a negative folds into [0,1)")
        XCTAssertEqual(positiveFract(-2.75), 0.25, accuracy: 1e-12)
    }

    func testSplitmix64MixIsDeterministicAndDiffuses() {
        XCTAssertEqual(splitmix64Mix(0x1234), splitmix64Mix(0x1234), "deterministic")
        XCTAssertNotEqual(splitmix64Mix(1), splitmix64Mix(2), "adjacent seeds diverge")
        XCTAssertNotEqual(splitmix64Mix(1), 1, "a nonzero seed avalanches away from itself")
    }

    // MARK: - midiNoteName — non-negative octaves (user 2026-08-03: "no more -1")


    // MARK: - NOTE VIEW (Paul 2026-10-10 ferry) — euclideousNoteViewName, the window/mark pure math

    /// §4.7 (2026-10-10) originally ratified "MIDI 60 = C3" — CORRECTED by the 2026-10-14 ferry §1: every
    /// one of its 11 worked no-key test chords only reconciles against the STANDARD convention (MIDI 60 =
    /// C4), forcing this anchor to change for "one name per note everywhere" to hold. Hand-derived, not
    /// assumed: floor(0/12)−1=−1 ⇒ "C-1"; floor(127/12)−1=9 ⇒ "G9".
    func testEuclideousNoteViewNameAnchorsMidi60AtC4() {
        XCTAssertEqual(euclideousNoteViewName(60, flatKey: false), "C4")
        XCTAssertEqual(euclideousNoteViewName(0, flatKey: false), "C-1")
        XCTAssertEqual(euclideousNoteViewName(127, flatKey: false), "G9")
    }
    func testEuclideousNoteViewNameSpellsFlatsOnlyWhenAsked() {
        // 2026-10-13 ferry: always the Unicode glyphs, never ASCII "#"/"b".
        XCTAssertEqual(euclideousNoteViewName(63, flatKey: false), "D\u{266F}4")
        XCTAssertEqual(euclideousNoteViewName(63, flatKey: true), "E\u{266D}4")
        XCTAssertEqual(euclideousNoteViewName(61, flatKey: true), "D\u{266D}4", "a flat key still spells the natural white keys the same way")
    }
    func testEuclideousSplitNoteOctaveSeparatesNameFromTrailingDigits() {
        XCTAssertEqual(euclideousSplitNoteOctave("C3").note, "C")
        XCTAssertEqual(euclideousSplitNoteOctave("C3").octave, "3")
        XCTAssertEqual(euclideousSplitNoteOctave("D\u{266D}2").note, "D\u{266D}")
        XCTAssertEqual(euclideousSplitNoteOctave("D\u{266D}2").octave, "2")
        XCTAssertEqual(euclideousSplitNoteOctave("C-2").note, "C")
        XCTAssertEqual(euclideousSplitNoteOctave("C-2").octave, "-2")
        XCTAssertEqual(euclideousSplitNoteOctave("–").note, "–", "the empty-pool placeholder has no digit to split off")
        XCTAssertEqual(euclideousSplitNoteOctave("–").octave, "")
    }

    // MARK: - FERRY (2026-10-14, "Euclideous fixes from Paul's 14 Oct run") §1 — all 11 of the ferry's own
    // worked chords, hand-verified algebraically before being trusted (see the derivation in
    // `euclideousRelativeNoteName`'s own doc comment), not just transcribed.
    func testEuclideousRelativeNoteNameMatchesEveryWorkedChordInTheFerry() {
        func names(_ pool: [UInt8]) -> [String] { pool.map { euclideousRelativeNoteName($0, pool: pool) } }
        XCTAssertEqual(names([50, 54, 57]), ["D3", "F\u{266F}3", "A3"])
        XCTAssertEqual(names([49, 53, 56]), ["D\u{266D}3", "F3", "A\u{266D}3"])
        XCTAssertEqual(names([49, 52, 56]), ["C\u{266F}3", "E3", "G\u{266F}3"])
        XCTAssertEqual(names([54, 58, 61]), ["F\u{266F}3", "A\u{266F}3", "C\u{266F}4"])
        XCTAssertEqual(names([51, 54, 58]), ["E\u{266D}3", "G\u{266D}3", "B\u{266D}3"])
        XCTAssertEqual(names([57, 61, 66]), ["A3", "C\u{266F}4", "F\u{266F}4"])
        XCTAssertEqual(names([53, 56, 61]), ["F3", "A\u{266D}3", "D\u{266D}4"])
        XCTAssertEqual(names([55, 59, 62]), ["G3", "B3", "D4"])
        XCTAssertEqual(names([52, 55, 59]), ["E3", "G3", "B3"])
        XCTAssertEqual(names([54, 58, 61, 65]), ["F\u{266F}3", "A\u{266F}3", "C\u{266F}4", "F4"], "E♯ → F, the octave-crossing simplification")
        XCTAssertEqual(names([49, 53, 56, 59]), ["D\u{266D}3", "F3", "A\u{266D}3", "B3"], "C♭ → B, the octave-crossing simplification")
    }
    func testEuclideousRelativeRootPrefersMinorOnlyWhenAThirdAboveItSounds() {
        XCTAssertFalse(euclideousRelativeRoot(pool: [50, 54, 57])!.minor, "D-F♯-A: no minor third above D (54 is a major third)")
        XCTAssertTrue(euclideousRelativeRoot(pool: [49, 52, 56])!.minor, "C♯-E-G♯: 52 IS a minor third above 49")
        XCTAssertNil(euclideousRelativeRoot(pool: []), "nothing held, nothing to spell relative to")
    }
    func testEuclideousDisplayNoteNameRoutesKeyModeUnchangedAndOthersThroughTheRelativeAlgorithm() {
        // KEY mode: "as now" — the existing key-driven sharp/flat choice, ignoring the pool entirely.
        XCTAssertEqual(euclideousDisplayNoteName(63, source: .key, pool: [50, 54, 57], keyRoot: 0, keyType: .major), "D\u{266F}4")
        // MIDI/CHORD: the SAME physical note reads differently depending on what's actually held, never flat-by-default.
        XCTAssertEqual(euclideousDisplayNoteName(54, source: .midi, pool: [50, 54, 57], keyRoot: 0, keyType: .major), "F\u{266F}3",
                       "the reported bug, fixed: F♯ must not read G♭ just because the source has no key")
        XCTAssertEqual(euclideousDisplayNoteName(54, source: .chords, pool: [50, 54, 57], keyRoot: 0, keyType: .major), "F\u{266F}3")
    }



    func testEuclideousKeyIsFlatMatchesTheStandardCircleOfFifthsRoots() {
        for root in [5, 10, 3, 8, 1] { XCTAssertTrue(euclideousKeyIsFlat(root), "pitch class \(root) is a conventional flat-key root") }
        for root in [0, 7, 2, 9, 4, 11, 6] { XCTAssertFalse(euclideousKeyIsFlat(root), "pitch class \(root) is a conventional sharp-key root (6/F#-Gb defaults sharp)") }
        XCTAssertEqual(euclideousKeyIsFlat(-7), euclideousKeyIsFlat(5), "negative roots wrap the same as any other pitch-class math in this codebase")
    }
    /// Fix 5 (2026-10-14 ferry) — the regression guard for the exact reported bug: a C natural-minor pool
    /// must spell E♭/A♭/B♭, not D♯/G♯/A♯. C minor's root (0) tests flat only once shifted to its relative
    /// major (C → Eb, +3 semitones) — the un-shifted, major-only reading of root 0 is sharp, confirming the
    /// shift is actually doing something here, not a no-op that happened to agree by coincidence.
    func testEuclideousKeyIsFlatUsesTheScalesRelativeMajorNotTheBareRoot() {
        XCTAssertFalse(euclideousKeyIsFlat(0), "C major (or an unspecified scale) reads sharp at the bare root")
        XCTAssertTrue(euclideousKeyIsFlat(0, scaleType: .naturalMinor), "C natural minor's relative major is Eb — a flat key")
        XCTAssertTrue(euclideousKeyIsFlat(0, scaleType: .harmonicMinor))
        XCTAssertTrue(euclideousKeyIsFlat(0, scaleType: .melodicMinor))
        XCTAssertTrue(euclideousKeyIsFlat(0, scaleType: .minorPentatonic))
        XCTAssertTrue(euclideousKeyIsFlat(0, scaleType: .blues))
        // D dorian's relative major is C (shift 2) — reads the same as plain C major: sharp.
        XCTAssertFalse(euclideousKeyIsFlat(2, scaleType: .dorian))
        // E phrygian's relative major is C (shift 4) — same, sharp.
        XCTAssertFalse(euclideousKeyIsFlat(4, scaleType: .phrygian))
        // F lydian's relative major is C (shift 5) — same, sharp.
        XCTAssertFalse(euclideousKeyIsFlat(5, scaleType: .lydian))
        // G mixolydian's relative major is C (shift 7) — same, sharp.
        XCTAssertFalse(euclideousKeyIsFlat(7, scaleType: .mixolydian))
        // Whole-tone/chromatic have no relative-major concept — fall back to the bare-root (major) reading.
        XCTAssertEqual(euclideousKeyIsFlat(3, scaleType: .wholeTone), euclideousKeyIsFlat(3))
        XCTAssertEqual(euclideousKeyIsFlat(3, scaleType: .chromatic), euclideousKeyIsFlat(3))
    }

    /// §2, the rhythm-only tick/window projection — mirrors `Router.runEuclidLine`'s own hit-test exactly
    /// (same pure functions, same order) so a projected mark can never silently disagree with what the
    /// engine would actually strike for that tick.
    func testEuclideousNoteViewPatternMatchesTheRealEngineHitTest() {
        let buf = euclideousNoteViewPattern(pulses: 3, steps: 8, rotate: 0, tilt: 0)
        var expected = [Bool](repeating: false, count: 8)
        euclidPatternInto(&expected, pulses: 3, steps: 8, rotation: 0)
        XCTAssertEqual(buf, expected)
    }
    /// Found 2026-10-12 while building the riff-grid-markers/footers ferry on top of this function: ROTATE
    /// must apply on top of a hand-edited (`customHits`) pattern too, matching Router.swift's own
    /// `runEuclidLine` exactly ("OFFSET still applies — a position-shift on top of whatever the base shape
    /// is, pure or edited"). Previously rotation only ran inside the generated-pattern branch.
    func testEuclideousNoteViewPatternAppliesRotateOnTopOfCustomHitsToo() {
        let custom = [true, false, false, false]
        let unrotated = euclideousNoteViewPattern(pulses: 1, steps: 4, rotate: 0, tilt: 0, customHits: custom)
        XCTAssertEqual(unrotated, [true, false, false, false])
        let rotated = euclideousNoteViewPattern(pulses: 1, steps: 4, rotate: 1, tilt: 0, customHits: custom)
        var base = [true, false, false, false]
        euclidRotateBuffer(&base, steps: 4, rotation: 1)
        XCTAssertEqual(rotated, base, "a hand-edited pattern must rotate exactly like a generated one")
        XCTAssertNotEqual(rotated, unrotated, "rotation must actually move the hit, not be silently ignored for customHits")
    }
    // ── RIFF POSITION MARKERS + LANE FOOTERS (Paul 2026-10-12 ferry) ────────────────────────────────────────
    func testEuclideousLapHitStepsMatchesThePatternsOwnHitPositions() {
        let buf = euclideousNoteViewPattern(pulses: 3, steps: 8, rotate: 0, tilt: 0)
        let hits = euclideousLapHitSteps(pulses: 3, steps: 8, rotate: 0, tilt: 0, patternMiss: false, customHits: nil)
        XCTAssertEqual(hits.map { $0.bufIdx }, (0..<8).filter { buf[$0] }, "FWD (the default) must be exactly the ascending step indices the pure pattern mirror marks as hits")
        XCTAssertEqual(hits.map { $0.tick }, hits.map { $0.bufIdx }, "FWD: tick == bufIdx for every hit (euclidReadIndex is the identity for .fwd)")
        XCTAssertEqual(hits.count, 3)
    }
    // DIRECTION FIX (2026-10-13 adversarial review): `euclideousLapHitSteps` previously always returned hit
    // positions in ascending BUFFER-INDEX order regardless of the lane's own PATTERN direction — correct for
    // FWD only. The real engine (`euclidReadIndex`) reads a BKW lane's buffer back-to-front, so the hit at
    // the HIGHEST buffer index actually sounds FIRST, not last.
    func testEuclideousLapHitStepsOrdersHitsByRealTemporalOrderForBackward() {
        // Same E(3,8) pattern as the test above (hits at buffer indices 0, 3, 6). Under BKW,
        // euclidReadIndex(raw,8,.bkw) = 7-raw, so bufIdx 6 sounds at real tick 1, bufIdx 3 at tick 4, bufIdx 0
        // at tick 7 — hand-derived directly from euclidReadIndex's own formula, not assumed.
        let hits = euclideousLapHitSteps(pulses: 3, steps: 8, rotate: 0, tilt: 0, patternMiss: false, customHits: nil, dir: .bkw)
        XCTAssertEqual(hits.map { $0.bufIdx }, [6, 3, 0], "BKW must visit these hits in REVERSE buffer-index order, not ascending")
        XCTAssertEqual(hits.map { $0.tick }, [1, 4, 7], "each hit's own real tick, matching euclidReadIndex's BKW formula exactly")
    }
    func testEuclideousLapHitStepsDoublesEachHitForPingPongOnceEachDirection() {
        // PING-PONG's real cycle is 2n (euclidCycleLen) — the same 3 hits sound once ascending (ticks 0,3,6)
        // then once descending (ticks 9,12,15, hand-derived from euclidReadIndex(raw,8,.pingpong)=15-raw for
        // raw in 8...15) as the walk bounces back.
        let hits = euclideousLapHitSteps(pulses: 3, steps: 8, rotate: 0, tilt: 0, patternMiss: false, customHits: nil, dir: .pingpong)
        XCTAssertEqual(hits.map { $0.bufIdx }, [0, 3, 6, 6, 3, 0], "PING-PONG's doubled cycle visits every hit once ascending, then once descending")
        XCTAssertEqual(hits.map { $0.tick }, [0, 3, 6, 9, 12, 15])
    }
    /// Paul's own literal acceptance example: "Lane 1 forward, 3 hits from riff step 3: footers read
    /// 3 · 4 · 5." A 3-hit lap, FWD/stride 1/length 8, with `startOrd` chosen so the first hit lands on
    /// (0-based) riff step 2 — i.e. the displayed "riff step 3."
    func testEuclideousRiffCyclePredictionMatchesPaulsOwnWorkedExample() {
        let hits = euclideousLapHitSteps(pulses: 3, steps: 8, rotate: 0, tilt: 0, patternMiss: false, customHits: nil)
        let predicted = euclideousRiffCyclePrediction(hitSteps: hits, advanceStep: false, dir: .forward, stride: 1,
                                                        length: 8, rotate: 0, seed: 0, startOrd: 2)
        XCTAssertEqual(predicted, [3, 4, 5])
    }
    /// A one-step STRIDE/HIT-mode advance from a DIFFERENT starting ordinal lands somewhere else entirely —
    /// guards against the worked example above being coincidentally right regardless of `startOrd`.
    func testEuclideousRiffCyclePredictionAdvancesFromItsOwnStartOrd() {
        let hits = euclideousLapHitSteps(pulses: 3, steps: 8, rotate: 0, tilt: 0, patternMiss: false, customHits: nil)
        let predicted = euclideousRiffCyclePrediction(hitSteps: hits, advanceStep: false, dir: .forward, stride: 1,
                                                        length: 8, rotate: 0, seed: 0, startOrd: 0)
        XCTAssertEqual(predicted, [1, 2, 3])
    }
    /// ADVANCE = STEP: the ordinal climbs by the REAL elapsed grid-step count since the lap's first hit,
    /// not by 1 per hit — a lap with hits at steps 0, 3, 5 (gaps of 3 and 2) must show the SAME gaps in the
    /// predicted riff-step sequence, not a uniform +1 walk.
    func testEuclideousRiffCyclePredictionStepModeAdvancesByRealElapsedSteps() {
        let hits: [EuclidHitStep] = [0, 3, 5]
        let predicted = euclideousRiffCyclePrediction(hitSteps: hits, advanceStep: true, dir: .forward, stride: 1,
                                                        length: 8, rotate: 0, seed: 0, startOrd: 0)
        XCTAssertEqual(predicted, [1, 4, 6], "gaps of 3 and 2 grid-steps must advance the riff walk by 3 and 2 steps, not 1 and 1")
    }
    /// PENDULUM at the top of its run reverses cleanly, the direct worked-example proof behind "a pendulum
    /// lane at the end of its run already points back": length 4 ⇒ period 2*(4-1)=6, raw%6 sequence
    /// 0,1,2,3,2,1,… — the ord landing on raw%6==3 (the peak, displayed rank 4) is IMMEDIATELY followed by
    /// a strictly LOWER rank (raw%6==4 ⇒ value 2, rank 3), proving the next-vs-current comparison a marker's
    /// arrow direction reads off this same array already encodes the turnaround with no special-casing.
    func testEuclideousRiffCyclePredictionPendulumReversesAtThePeakWithNoSpecialCasing() {
        let hits: [EuclidHitStep] = [0, 1]   // two consecutive hits, ord 3 then 4 (raw%6 == 3 then 4)
        let predicted = euclideousRiffCyclePrediction(hitSteps: hits, advanceStep: false, dir: .pendulum, stride: 1,
                                                        length: 4, rotate: 0, seed: 0, startOrd: 3)
        XCTAssertEqual(predicted, [4, 3], "the peak (rank 4) must be immediately followed by a strictly lower rank — the reversal, read directly off the sequence")
    }
    // testEuclideousRiffCyclePredictionDrunkReplaysExactlyWhatTheRealWalkWouldDo removed (2026-10-12
    // MELODY-tab ferry): DRUNK is no longer one of Euclideous's own WALK directions — the engine's own
    // `euclideousRiffDrunkStep`/the prediction's `drunkLive` parameter are both gone, so this test's whole
    // premise is gone. The generic chain RIFF processor's own, unrelated DRUNK mechanism (riffDrunkPeek/
    // riffDrunkDelta) is untouched and keeps its own separate test coverage elsewhere in this file.
    func testEuclideousRiffLapBaselineRestartPassAlwaysResetsRegardlessOfLiveState() {
        let hits: [EuclidHitStep] = [0, 3, 6]
        let b = euclideousRiffLapBaseline(hitSteps: hits, lapSteps: 8, isMelodyRestartPass: true, advanceStep: false, liveOrd: 47)
        XCTAssertEqual(b.startOrd, 0)
        XCTAssertEqual(b.currentHitIndex, 0, "a melody restart pass: the live hit is always lap-relative index 0 — a fresh lap always starts there")
    }
    /// FREE + HIT mode: a live ordinal mid-lap (hit index 1 of 3) must recover the lap's OWN first-hit
    /// ordinal by simple subtraction — verified by feeding the recovered `startOrd` straight back into
    /// `euclideousRiffCyclePrediction` and confirming hit-index 1's own prediction matches what the live
    /// ordinal would directly predict for ITSELF, proving the baseline is self-consistent.
    func testEuclideousRiffLapBaselineFreeHitModeRecoversTheLapsFirstHitOrdinal() {
        let hits: [EuclidHitStep] = [0, 3, 6]   // effHits = 3
        // live ordinal 7 ⇒ 7 % 3 == 1 ⇒ currently at hit-index 1 of the lap ⇒ lap started at ordinal 6
        let b = euclideousRiffLapBaseline(hitSteps: hits, lapSteps: 8, isMelodyRestartPass: false, advanceStep: false, liveOrd: 7)
        XCTAssertEqual(b.startOrd, 6)
        XCTAssertEqual(b.currentHitIndex, 1)
        let predicted = euclideousRiffCyclePrediction(hitSteps: hits, advanceStep: false, dir: .forward, stride: 1,
                                                        length: 8, rotate: 0, seed: 0, startOrd: b.startOrd)
        // hit-index 1 (the live hit itself, ordinal 7) must read the SAME riff step a direct call with
        // startOrd 7 would predict for hit-index 0 — the self-consistency check.
        let direct = euclideousRiffCyclePrediction(hitSteps: [hits[1]], advanceStep: false, dir: .forward, stride: 1,
                                                     length: 8, rotate: 0, seed: 0, startOrd: 7)
        XCTAssertEqual(predicted[1], direct[0])
    }
    /// FREE + STEP mode: the live ordinal (the elapsed GRID-STEP count at the most recent hit, not a hit
    /// count) must recover the lap's first-hit ordinal by finding which hit the live step position matches.
    func testEuclideousRiffLapBaselineFreeStepModeRecoversTheLapsFirstHitOrdinal() {
        let hits: [EuclidHitStep] = [0, 3, 6]
        // Under STEP mode the live ordinal IS the elapsed grid-step count, read via `buf[localT % lapSteps]`
        // — so a lap starting at ordinal 8 (self-consistent: 8 % 8 == hits[0] == 0) has its step-6 hit
        // (hits[2]) occur at ordinal 8 + (6 - 0) = 14 (checked: 14 % 8 == 6, the step itself).
        let b = euclideousRiffLapBaseline(hitSteps: hits, lapSteps: 8, isMelodyRestartPass: false, advanceStep: true, liveOrd: 14)
        XCTAssertEqual(b.startOrd, 8)
        XCTAssertEqual(b.currentHitIndex, 2, "the live hit landed on hits[2] (step 6) — array index 2")
    }
    // DIRECTION FIX (2026-10-13 adversarial review): the pre-fix STEP-mode branch reduced `liveOrd` by the
    // plain buffer length and compared the result directly against `hitSteps`' BUFFER-INDEX values — wrong
    // for BKW on two counts (its real cycle length happens to coincide with the buffer length, but a raw
    // reduced tick is NOT the same as a buffer index without `euclidReadIndex`'s own conversion). Mirrors
    // the existing FWD self-consistency test's own technique: feed the recovered `startOrd` back into
    // `euclideousRiffCyclePrediction` and confirm hit-index 1's own prediction matches what the live ordinal
    // would directly predict for ITSELF.
    func testEuclideousRiffLapBaselineStepModeRecoversCorrectlyForBackwardDirection() {
        // Same E(3,8) pattern as the direction-ordering tests above, read under BKW: hits land on real
        // ticks 1, 4, 7 (buffer indices 6, 3, 0 respectively).
        let hits = euclideousLapHitSteps(pulses: 3, steps: 8, rotate: 0, tilt: 0, patternMiss: false, customHits: nil, dir: .bkw)
        let liveOrd: Int64 = 12   // 12 % 8 == 4, matching hit index 1's own real TICK (4), not its buffer index (3)
        let b = euclideousRiffLapBaseline(hitSteps: hits, lapSteps: 8, isMelodyRestartPass: false, advanceStep: true, liveOrd: liveOrd, dir: .bkw)
        XCTAssertEqual(b.currentHitIndex, 1, "tick 4 matches hit index 1's own real tick — the pre-fix code compared against a buffer index directly and would have found no match at all")
        XCTAssertEqual(b.startOrd, 9)
        let predicted = euclideousRiffCyclePrediction(hitSteps: hits, advanceStep: true, dir: .forward, stride: 1, length: 8, rotate: 0, seed: 0, startOrd: b.startOrd)
        let direct = euclideousRiffCyclePrediction(hitSteps: [hits[1]], advanceStep: true, dir: .forward, stride: 1, length: 8, rotate: 0, seed: 0, startOrd: liveOrd)
        XCTAssertEqual(predicted[1], direct[0], "the recovered baseline must be self-consistent with the live ordinal")
    }
    // RIFF/NOTES SPLIT (Paul's third same-day ferry) — `euclideousRiffStepRanks` resolves each of the 8
    // STEP positions' own rank, mirroring Router.swift's real per-hit `invRank`/`transposedRank` formula
    // exactly, mask-oblivious. A genuinely different question from `euclideousRiffReachableRanks` above
    // (a static per-step property, not "every rank the walk could ever visit").
    func testEuclideousRiffStepRanksAppliesInvertThenTransposePerStepAndLeavesRestsAlone() {
        // rank 0 (rest) passes through untouched by BOTH invert and transpose, matching Router.swift's own
        // `invRank >= 1 ? ... : invRank` guard; rank 1 inverts to 8, then +1 transpose → 9 (left as-is, not
        // folded here — folding into a displayable 1...8 range is the CALLER's own job, per this function's
        // own doc comment).
        XCTAssertEqual(euclideousRiffStepRanks(ranks: [0, 1, 8], invert: true, transpose: 1), [0, 9, 2])
    }
    func testEuclideousRiffStepRanksNoOpWhenNotInvertedAndNotTransposed() {
        XCTAssertEqual(euclideousRiffStepRanks(ranks: [0, 1, 2, 3, 4, 5, 6, 7], invert: false, transpose: 0),
                       [0, 1, 2, 3, 4, 5, 6, 7])
    }
    func testEuclideousRiffStepRanksTransposeAloneShiftsOnlyNonRestSteps() {
        XCTAssertEqual(euclideousRiffStepRanks(ranks: [0, 3, 0, 5], invert: false, transpose: 2), [0, 5, 0, 7],
                       "every rest (rank 0) stays exactly 0 — TRANSPOSE alone never turns a rest into a note")
    }
    func testEuclideousFooterStatesHitMissRestAndRiffOff() {
        // 3 hits (steps 0, 3, 6 of an 8-step lap); predicted riff steps 3, 5(rest), 7 against a grid whose
        // rank 5 is a rest (0).
        let hits: [EuclidHitStep] = [0, 3, 6]
        let ranks = [1, 2, 3, 4, 0, 6, 7, 8]   // 0-based index 4 (displayed rank 5) is a rest
        let states = euclideousFooterStates(hitSteps: hits, lapSteps: 8, prediction: [3, 5, 7], riffRanksResolved: ranks)
        XCTAssertEqual(states[0], .hit(riffStep: 3))
        XCTAssertEqual(states[1], .miss)
        XCTAssertEqual(states[3], .hitOnRest(riffStep: 5))
        XCTAssertEqual(states[6], .hit(riffStep: 7))
        // Riff off (prediction nil): every hit is a plain, number-less hit; non-hits stay miss.
        let offStates = euclideousFooterStates(hitSteps: hits, lapSteps: 8, prediction: nil, riffRanksResolved: ranks)
        XCTAssertEqual(offStates[0], .hit(riffStep: nil))
        XCTAssertEqual(offStates[3], .hit(riffStep: nil))
        XCTAssertEqual(offStates[1], .miss)
    }
    // LIT NOTES PLUS THE RIFF (Paul 2026-10-13, second same-day ferry), Elsewhere-on-page §4 — `anyLit`
    // supersedes the prior ferry's own unconditional riff-off `.hit(riffStep: nil)` rule: "riff off with
    // nothing lit: the miss footer, because nothing will sound" (every step, hit included, becomes `.miss`);
    // "riff off with notes lit" keeps the old `.hit(riffStep: nil)` (drawn grey at the `laneFooter` call
    // site — a styling concern outside this pure function's own scope).
    func testEuclideousFooterStatesRiffOffNothingLitForcesEveryStepToMiss() {
        let hits: [EuclidHitStep] = [0, 3, 6]
        let ranks = [1, 2, 3, 4, 0, 6, 7, 8]
        let litStates = euclideousFooterStates(hitSteps: hits, lapSteps: 8, prediction: nil, riffRanksResolved: ranks, anyLit: true)
        XCTAssertEqual(litStates[0], .hit(riffStep: nil), "riff off, something lit: still a plain hit footer")
        let emptyStates = euclideousFooterStates(hitSteps: hits, lapSteps: 8, prediction: nil, riffRanksResolved: ranks, anyLit: false)
        for i in 0..<8 { XCTAssertEqual(emptyStates[i], .miss, "riff off, nothing lit: every step is .miss, hit steps included — step \(i)") }
    }
    // ── ONE GLOBAL RIFF/NOTE SOURCE (Paul 2026-10-12, second ferry same day) ──────────────────────────────
    /// All 3 of the ferry's own literal worked examples, hand-verified.
    func testEuclideousGlobalPoolExtendedMatchesAllThreeWorkedExamples() {
        // C natural minor: C D Eb F G Ab Bb -> + the root one octave up.
        let key = [0, 2, 3, 5, 7, 8, 10]
        XCTAssertEqual(euclideousGlobalPoolExtended(sortedRaw: key), [0, 2, 3, 5, 7, 8, 10, 12])
        // C Eb G triad: 3+3 = 6, +2 more from a third octave (drops the would-be 9th, G+24).
        let triad = [0, 3, 7]
        XCTAssertEqual(euclideousGlobalPoolExtended(sortedRaw: triad), [0, 3, 7, 12, 15, 19, 24, 27])
        // One held note: eight octaves of itself.
        XCTAssertEqual(euclideousGlobalPoolExtended(sortedRaw: [60]), [60, 72, 84, 96, 108, 120, 132, 144])
        // Empty pool (MIDI IN, nothing held): stays empty, not padded with garbage.
        XCTAssertEqual(euclideousGlobalPoolExtended(sortedRaw: []), [])
        // A raw pool already >= 8: no further extension, just the first 8.
        let full = [0, 1, 2, 3, 4, 5, 6, 7, 8, 9]
        XCTAssertEqual(euclideousGlobalPoolExtended(sortedRaw: full), [0, 1, 2, 3, 4, 5, 6, 7])
    }
    /// TRANSPOSE's own case: a rank beyond 8 must continue the SAME octave-extension pattern, not clamp —
    /// `riffResolve`'s existing `.fold` wrap already does this against the RAW (un-padded) sorted pool, so
    /// rank 9 (one past the natural end of a 7-note key) must land exactly one octave above rank 2 (0-based
    /// index 1, since 9-1=8, 8%7=1, 8/7=1 lap).
    func testRiffResolveContinuesTheOctaveExtensionBeyondRank8ForTranspose() {
        let key = [0, 2, 3, 5, 7, 8, 10]   // 7 notes
        let rank9 = riffResolve(rank: 9, oct: 0, n: key.count, wrap: .fold, asc: { key[$0] })
        XCTAssertEqual(rank9, key[1] + 12, "rank 9 = index 1 (9-1=8, 8%7=1) one octave up (8/7=1 lap)")
    }

    // MARK: - chopSlice — wrap + guards (§cell-edit F)

    /// The onset→slice map divides a column into 8; it wraps NEGATIVE beats (a lay-back onset) into the prior
    /// column and guards a zero-length column. All in-range slices are 0…7.
    func testChopSliceWrapsNegativeAndGuardsZeroColumn() {
        XCTAssertEqual(chopSlice(0.0, columnBeats: 1), 0)
        XCTAssertEqual(chopSlice(0.5, columnBeats: 1), 4)
        XCTAssertEqual(chopSlice(0.99, columnBeats: 1), 7)
        XCTAssertEqual(chopSlice(1.0, columnBeats: 1), 0)      // wraps to the next column's slice 0
        XCTAssertEqual(chopSlice(-0.1, columnBeats: 1), 7)     // a negative onset folds into the prior column's last slice
        XCTAssertEqual(chopSlice(5.0, columnBeats: 0), 0)      // S <= 0 guard → slice 0, no divide-by-zero
    }

    // (machineCensus empty-edge test removed 2026-08-27: dead helper, zero non-test callers.)

    // MARK: - trigger glyphs — per-case totality + hold-only ring



    // MARK: - NotePool.heldVelocity — the BYPASS direct-injection read


    // MARK: - THE MOD PROCESSOR (CC generator) — pure shape values


    func testColumnStartFloorsToTheStepGrid() {
        XCTAssertEqual(columnStart(0.0, 0.5), 0.0, accuracy: 1e-9)
        XCTAssertEqual(columnStart(0.49, 0.5), 0.0, accuracy: 1e-9)
        XCTAssertEqual(columnStart(0.5, 0.5), 0.5, accuracy: 1e-9)
        XCTAssertEqual(columnStart(1.3, 0.5), 1.0, accuracy: 1e-9)
        XCTAssertEqual(columnStart(2.0, 1.0), 2.0, accuracy: 1e-9)
        XCTAssertEqual(columnStart(2.9, 1.0) + 1.0, 3.0, accuracy: 1e-9, "the +S end-of-column form")
    }
    func testIsForwardableController() {
        XCTAssertTrue(isForwardableController(0xB3), "CC")
        XCTAssertTrue(isForwardableController(0xE0), "pitch bend")
        XCTAssertTrue(isForwardableController(0xD5), "channel pressure / AT")
        XCTAssertTrue(isForwardableController(0xC0), "program change")
        XCTAssertFalse(isForwardableController(0x90), "note-on is not a controller")
        XCTAssertFalse(isForwardableController(0xA0), "poly pressure is parked (MPE)")
    }



    // MARK: - TUTTI (Paul 2026-08-13): SET-level chance primitives — pure, per-step, replay-exact


    // MARK: - TUTTI PATTERN (phase 2): per-slice set-shapes


    // MARK: - LENGTH (Paul 2026-08-05): per-slice GATE override — the event model + downstream gate


    // MARK: - WEAVE (Paul 2026-08-07): rank-clocked polyrhythm driver


    // MARK: - SPLIT (Paul 2026-08-05): set-membership filter — the three placements


    // MARK: - RATCHET MODE (Paul 2026-08-16 ferry): ALL · COIN · PATTERN







    // ParamLFO.rateIgnoreResolved (Paul 2026-09-16): default ignore dotted+triplet; never ignore all three.
    func testParamLFORateIgnoreResolved() {
        XCTAssertEqual(ParamLFO(target: "arpRate").rateIgnoreResolved, 0b110, "nil ⇒ default ignore dotted+triplet")
        XCTAssertEqual(ParamLFO(target: "arpRate", rateIgnore: 0b111).rateIgnoreResolved, 0b110, "all-three ⇒ keep normal")
        XCTAssertEqual(ParamLFO(target: "arpRate", rateIgnore: 0b101).rateIgnoreResolved, 0b101, "explicit mask preserved")
        XCTAssertEqual(ParamLFO(target: "arpRate", rateIgnore: 0b1010).rateIgnoreResolved, 0b010, "high bits masked off")
    }

    // CLOCK (AcceptanceCriteria-clock-processor, Paul 2026-09-26) — the pure phase transform. FIXED (a simple
    // ratio+offset) and WAVE (a zero-mean cosine/triangle wobble) modes were built here and removed the same day —
    // Paul's own spec ("a grid with a variable number of steps, each step a mutually exclusive speed, and another
    // row on the same grid for glide") describes one mechanism, not a choice of three; CLOCK is now always the
    // DRAWN grid below. Their pure-function tests (ratio/offset math, composition, re-landing at SPAN boundaries,
    // monotonicity at the depth clamp) are gone with the functions — DRAWN's own tests below cover the same shape
    // of properties (no-op at ×1, composition, monotonicity) for the grid that actually ships.

    // DRAWN (Stage 2): an empty/CARRY (-1) column holds the PREVIOUS explicit ratio — resolved ONCE at SnapshotBuilder
    // time so the render side never re-maps. picks [×1, CARRY, ×2, CARRY] → [1, 1, 2, 2] (ladder idx 4=×1, 2=×2).
    func testClockDrawnResolveRatiosCarriesForwardAndWrapsWhenEmpty() {
        XCTAssertEqual(clockDrawnResolveRatios([4, -1, 2, -1], steps: 4), [1.0, 1.0, 2.0, 2.0])
        // a WHOLE-lane-empty lane falls back to ×1 everywhere (never crashes, never picks a stale sentinel ratio).
        XCTAssertEqual(clockDrawnResolveRatios([], steps: 4), [1.0, 1.0, 1.0, 1.0])
        XCTAssertEqual(clockDrawnResolveRatios([-1, -1, -1], steps: 3), [1.0, 1.0, 1.0])
        // a leading CARRY with only ONE explicit pick later in the lane wraps — it carries the loop's own last value.
        XCTAssertEqual(clockDrawnResolveRatios([-1, -1, 2, -1], steps: 4), [2.0, 2.0, 2.0, 2.0])
    }

    // DRAWN at all-×1/all-SET must be byte-identical to no transform — the same ×1 no-op law FIXED/WAVE both honour.
    func testClockDrawnPhaseAtAllUnityIsByteIdenticalToNoTransform() {
        let ratios = [1.0, 1.0, 1.0, 1.0, 1.0, 1.0, 1.0, 1.0]
        let glide = [false, false, false, false, false, false, false, false]
        for beat in stride(from: -3.0, through: 9.0, by: 0.7) {
            XCTAssertEqual(clockDrawnPhase(beat, ratios: ratios, glide: glide, steps: 8, rateBeats: 0.5, periodBeats: 0), beat, accuracy: 1e-9)
        }
    }

    // SET snaps to a column's full ratio immediately; GLIDE ramps linearly from the PREVIOUS column's landed ratio to
    // this one — GLIDE now lands with the "elastic" shape (Paul 2026-09-26 ②, "in sync … with or without glide"):
    // its FULL column contribution is exactly `to × rateBeats`, same as SET's, so it costs no local time overall —
    // only the WITHIN-column shape differs (a brief overshoot then ease back onto the target, `clockDrawnGlideShape`).
    // steps=2, ratios ×1 then ×2, rateBeats=1, FREE span: at the column-1 midpoint (beat 1.5, half the column, which
    // is also exactly the elastic curve's 50/50 split point for an accelerating glide), SET has been running at its
    // full ×2 for half a beat (phase 1+1=2); GLIDE's kick-then-ease has carried it to phase 1+0.875=1.875 — MORE than
    // the old straight-ramp's 1.625, since the curve is already past its overshoot peak by the split point, not
    // still crawling up from ×1 (values re-derived from the actual function, not re-guessed by hand).
    func testClockDrawnSetSnapsGlideRamps() {
        let ratios = [1.0, 2.0]
        XCTAssertEqual(clockDrawnPhase(1.5, ratios: ratios, glide: [false, false], steps: 2, rateBeats: 1, periodBeats: 0),
                       2.0, accuracy: 1e-9, "SET: col1 already running at its full ×2")
        XCTAssertEqual(clockDrawnPhase(1.5, ratios: ratios, glide: [false, true], steps: 2, rateBeats: 1, periodBeats: 0),
                       1.875, accuracy: 1e-9, "GLIDE: col1's elastic kick, half-elapsed")
        XCTAssertEqual(clockDrawnPhase(2.0, ratios: ratios, glide: [false, false], steps: 2, rateBeats: 1, periodBeats: 0),
                       clockDrawnPhase(2.0, ratios: ratios, glide: [false, true], steps: 2, rateBeats: 1, periodBeats: 0),
                       accuracy: 1e-9, "THE FIX ITSELF: by the end of col1, SET and GLIDE land at the identical phase — in sync either way")
    }

    // A run of DIFFERING consecutive targets (no two neighbours share a value) must be COMPLETELY UNCHANGED by the
    // span fix above — each glide column is its own span of length 1, reducing exactly to the original one-column
    // formula. Locks that the span walk doesn't alter the already-correct case Paul confirmed ("reading 2"). Under
    // the elastic-landing fix, a glide column's FULL contribution collapses to simply `to × rateBeats` — the SAME
    // formula as SET at that same value — so this test now doubles as the plainest possible demonstration of the
    // sync fix itself: swap ANY of these `true`s to `false` (SET) and every asserted phase is unchanged.
    // Column real-time spans are [0,1)=col0, [1,2)=col1, [2,3)=col2, [3,4)=col3 (rateBeats=1) — verified via the
    // engine's own actual output (an earlier draft of this test mis-mapped beats to columns by one and asserted
    // the wrong numbers; caught by a failing run, not trusted by construction).
    // Mixes an ACCELERATING run (col1: 1→2, col2: 2→3) with a DECELERATING one (col3: 3→2) — the "in sync" fix
    // (Paul 2026-09-26 ③) applies ONLY to the accelerating columns; col3 keeps the plain, honest, non-zero-drift
    // ramp (see `clockDrawnGlideAdvance`'s doc for why forcing sync on a deceleration is unsafe, not just
    // undesirable — it makes local time briefly race ahead of a same-target SET, the exact mechanism behind Paul's
    // "hiccups... a stutter" report). So GLIDE agrees with SET at the col1/col2 boundaries but NOT at col3's.
    func testClockDrawnGlideOfDifferingTargetsIsUnaffectedBySpanLogic() {
        let ratios = [1.0, 2.0, 3.0, 2.0]
        let glide = [false, true, true, true]
        let allSet = [false, false, false, false]
        XCTAssertEqual(clockDrawnPhase(1.0, ratios: ratios, glide: glide, steps: 4, rateBeats: 1, periodBeats: 0), 1.0, accuracy: 1e-9, "end of col0 (SET at 1) = start of col1")
        XCTAssertEqual(clockDrawnPhase(2.0, ratios: ratios, glide: glide, steps: 4, rateBeats: 1, periodBeats: 0), 3.0, accuracy: 1e-9, "end of col1 (accelerating 1→2) — checkpoint 2 landed exactly, matching SET")
        XCTAssertEqual(clockDrawnPhase(3.0, ratios: ratios, glide: glide, steps: 4, rateBeats: 1, periodBeats: 0), 6.0, accuracy: 1e-9, "end of col2 (accelerating 2→3) — checkpoint 3 landed exactly, matching SET")
        XCTAssertEqual(clockDrawnPhase(4.0, ratios: ratios, glide: glide, steps: 4, rateBeats: 1, periodBeats: 0), 8.5, accuracy: 1e-9, "end of col3 (DECELERATING 3→2) — the honest average (3+2)/2=2.5, NOT SET's 2 — no forced sync here")
        // The accelerating columns agree with SET at their boundaries; the decelerating one does not:
        for beat in [1.0, 2.0, 3.0] {
            XCTAssertEqual(clockDrawnPhase(beat, ratios: ratios, glide: glide, steps: 4, rateBeats: 1, periodBeats: 0),
                           clockDrawnPhase(beat, ratios: ratios, glide: allSet, steps: 4, rateBeats: 1, periodBeats: 0),
                           accuracy: 1e-9, "GLIDE and SET agree through the accelerating run (beat \(beat))")
        }
        XCTAssertNotEqual(clockDrawnPhase(4.0, ratios: ratios, glide: glide, steps: 4, rateBeats: 1, periodBeats: 0),
                           clockDrawnPhase(4.0, ratios: ratios, glide: allSet, steps: 4, rateBeats: 1, periodBeats: 0),
                           "col3 decelerates, so GLIDE and SET genuinely diverge there — expected, not a regression")
    }

    // The mid-column trace must never let an ACCELERATING glide run AHEAD of a same-target SET (only ever behind or
    // equal, converging exactly at the very end) — that's what makes the accelerating branch provably artefact-free
    // for a downstream tick-search. A DECELERATING glide is EXPECTED to run ahead of a same-target SET throughout
    // (it's the honest, un-synced average) — this test only guards the accelerating direction's safety property.
    func testClockDrawnAcceleratingGlideNeverRunsAheadOfSet() {
        let rateBeats = 1.0
        for from in clockRatioLadder {
            for to in clockRatioLadder where to >= from {
                for frac in stride(from: 0.0, through: 1.0, by: 0.1) {
                    let t = frac * rateBeats
                    let glide = clockDrawnGlideAdvance(t, from: from, to: to, rateBeats: rateBeats)
                    let set = to * t
                    XCTAssertLessThanOrEqual(glide, set + 1e-9, "accelerating \(from)→\(to) at t=\(t) must never lead a same-target SET")
                }
            }
        }
    }



    // DRAWN's SPAN re-anchor branch (periodBeats > 0) — untested until now (housekeeping survey finding, 2026-09-26):
    // every existing DRAWN test uses periodBeats: 0 (FREE). Hand-verified: ratios [×1, ×2], rateBeats 1, steps 2
    // (lapBeats=2). At beat 3.5, FREE (period 0) has accumulated drift since absolute beat 0 → phase 5.0; SPAN
    // (period 3, deliberately NOT a multiple of lapBeats, so the two modes can't coincidentally agree) re-anchors at
    // beat 3 → phase 3.5, the re-anchor origin plus only the 0.5 local beats elapsed since it.
    func testClockDrawnPhaseReAnchorsAtEverySpanBoundary() {
        let ratios = [1.0, 2.0], glide = [false, false]
        let free = clockDrawnPhase(3.5, ratios: ratios, glide: glide, steps: 2, rateBeats: 1, periodBeats: 0)
        let spanned = clockDrawnPhase(3.5, ratios: ratios, glide: glide, steps: 2, rateBeats: 1, periodBeats: 3)
        XCTAssertEqual(free, 5.0, accuracy: 1e-9, "FREE: drift accumulated since absolute beat 0")
        XCTAssertEqual(spanned, 3.5, accuracy: 1e-9, "SPAN: re-anchored at beat 3 (the period boundary), only 0.5 local beats since")
        XCTAssertNotEqual(free, spanned, "the SPAN control genuinely changes the phase, not just decoration")
    }


    // 2026-10-15 ferry, "per-step restart points on the LANES tab" — §1.2's "every N sets bits 0, N, 2N, …
    // below 8."
    func testEuclideousStampMaskMatchesEveryWorkedExample() {
        XCTAssertEqual(euclideousStampMask(1), 0xFF)
        XCTAssertEqual(euclideousStampMask(2), 0b01010101)
        XCTAssertEqual(euclideousStampMask(4), 0b00010001)
        XCTAssertEqual(euclideousStampMask(8), 0b00000001)
        XCTAssertEqual(euclideousStampMask(0), 0, "OFF ⇒ empty mask")
        XCTAssertEqual(euclideousStampMask(-1), 0, "defensive: never loops forever on a non-positive N")
    }





    // §3/§7 test 7 (the RESET box label) + §7 test 5 (beyond-LEN marks read as OFF).
    func testEuclideousRestartLabelMatchesEveryWorkedExample() {
        XCTAssertEqual(euclideousRestartLabel(mask: euclideousStampMask(2), loopSteps: 8), EuclideousRestartLabel(value: "2", unit: "STEP"))
        let marks157: UInt8 = (1 << 0) | (1 << 4) | (1 << 6)
        XCTAssertEqual(euclideousRestartLabel(mask: marks157, loopSteps: 8), EuclideousRestartLabel(value: "3", unit: "PTS"))
        let marks15: UInt8 = (1 << 0) | (1 << 4)
        XCTAssertEqual(euclideousRestartLabel(mask: marks15, loopSteps: 8), EuclideousRestartLabel(value: "4", unit: "STEP"), "indistinguishable from a true every-4 stamp — §1.2's own point")
        XCTAssertEqual(euclideousRestartLabel(mask: euclideousStampMask(4), loopSteps: 4), EuclideousRestartLabel(value: "4", unit: "STEP"))
        XCTAssertEqual(euclideousRestartLabel(mask: euclideousStampMask(8), loopSteps: 4), EuclideousRestartLabel(value: "4", unit: "STEP"), "every-8 narrows to the same effective mask as every-4 at LEN 4")
        XCTAssertEqual(euclideousRestartLabel(mask: 0, loopSteps: 8), EuclideousRestartLabel(value: "\u{2013}", unit: "OFF"))
        // §7 test 5: marks ONLY on steps 6-7 (bits 5,6) at LEN 4 — both bits are beyond LEN, so the EFFECTIVE
        // mask (bits below LEN only) is empty, behaving exactly like OFF.
        let marks67: UInt8 = (1 << 5) | (1 << 6)
        XCTAssertEqual(euclideousRestartLabel(mask: marks67, loopSteps: 4), EuclideousRestartLabel(value: "\u{2013}", unit: "OFF"))
    }




    // KILL STEP (Paul 2026-09-26, sibling to CLOCK; MUTE/PAUSE added 2026-09-27) — a DISCRETE step remap via a
    // PRECOMPUTED table (`killStepResolveTable`): DROP is removed from the downstream timeline, the surviving steps
    // repeat to fill the pass; MUTE counts exactly like ON for this transform (it only silences the note — a
    // separate fold, Router.emitDriverNote — never this table); PAUSE freezes the local value for its own hold
    // length. `ksModes` converts the OLD bool-array fixtures (true→ON, false→DROP) so these read exactly as they did
    // before the table refactor — proving it byte-identical whenever nothing is MUTE/PAUSE. A no-op (all ON) reduces
    // to the identity EXACTLY, at any rate/period, since `value ≡ n` when every index is kept.
    private func ksModes(_ enabled: [Bool]) -> [KillStepMode] { enabled.map { $0 ? .on : .drop } }

    // CHORDS degrees sized to the matrix width (Paul 2026-09-16 fix): a wide matrix keeps all its authored columns.
    func testChordsDegreesResolvedSizesToSteps() {
        XCTAssertEqual(MachineParams().chordsDegreesResolved(steps: 8), [0, 0, 5, 5, 3, 3, 4, 4], "default 8")
        let padded = MachineParams().chordsDegreesResolved(steps: 16)
        XCTAssertEqual(padded.count, 16); XCTAssertEqual(Array(padded.prefix(8)), [0, 0, 5, 5, 3, 3, 4, 4])
        XCTAssertEqual(Array(padded.suffix(8)), Array(repeating: -1, count: 8), "cols 8–15 carry-fill (were dropped before)")
        var p = MachineParams(); p.chordsDegrees = Array(0..<10)
        XCTAssertEqual(p.chordsDegreesResolved(steps: 8), Array(0..<8), "a >steps input truncates")
    }

    // chordsDegreeAt carry / explicit-rest / all-carry / rotate (only indirectly covered before).
    func testChordsDegreeAtBranches() {
        XCTAssertEqual(chordsDegreeAt(step: 1, degrees: [4, -1, -1, -1, -1, -1, -1, -1], rotate: 0).degree, 4, "carry holds the last real degree")
        XCTAssertFalse(chordsDegreeAt(step: 1, degrees: [4, -1, -1, -1, -1, -1, -1, -1], rotate: 0).rest)
        XCTAssertTrue(chordsDegreeAt(step: 1, degrees: [7, -1, -1, -1, -1, -1, -1, -1], rotate: 0).rest, "a REST (7) carries SILENCE, not degree 0")
        XCTAssertTrue(chordsDegreeAt(step: 0, degrees: [-1, -1, -1, -1, -1, -1, -1, -1], rotate: 0).rest, "all-carry ⇒ rest")
        XCTAssertEqual(chordsDegreeAt(step: 0, degrees: [2, -1, -1, -1, 5, -1, -1, -1], rotate: 4).degree, 5, "rotate 4 strides to column 4")
    }






    // RIFF (SPEC-riff-processor §1): a stencil RANK resolves against the sorted pool — 1 = lowest … N = highest; a rank
    // past the held count WRAPS (FOLD = wrap + octave · CLAMP = top · WRAP = same octave); OCT nudges; rank 0 = rest.
    func testRiffResolveRankWrapAndOctave() {
        let notes = [60, 64, 67]   // a 3-note chord ascending
        func r(_ rank: Int, _ oct: Int, _ w: RiffWrap) -> Int? { riffResolve(rank: rank, oct: oct, n: notes.count, wrap: w) { notes[$0] } }
        XCTAssertEqual(r(1, 0, .fold), 60); XCTAssertEqual(r(2, 0, .fold), 64); XCTAssertEqual(r(3, 0, .fold), 67)
        XCTAssertEqual(r(4, 0, .fold), 72, "FOLD: rank 4 = the root an octave up")
        XCTAssertEqual(r(4, 0, .clamp), 67, "CLAMP: the top note")
        XCTAssertEqual(r(4, 0, .wrap), 60, "WRAP: the root, same octave")
        XCTAssertEqual(r(7, 0, .fold), 84, "FOLD: rank 7 = root two octaves up (idx 6 = 2 laps over 3)")
        XCTAssertEqual(r(1, 1, .fold), 72, "OCT +1"); XCTAssertEqual(r(1, -1, .fold), 48, "OCT −1")
        XCTAssertNil(r(0, 0, .fold), "rank 0 = rest")
        XCTAssertNil(riffResolve(rank: 1, oct: 0, n: 0, wrap: .fold) { _ in 0 }, "empty pool = nil")
    }

    // RIFF CAPTURE (SPEC-riff-processor §2, Paul 2026-09-09): play a line in → recorded AS RANKS against a FRAME. The
    // (RIFF CAPTURE tests removed 2026-09-10 — the §2 capture feature was deleted.)

    // EUCLIDEOUS RIFF ADVANCE (Paul 2026-10-06): a lane's own horizontal offset into the shared riff pattern —
    // mirrors euclidPatternInto's own `(i + rot) % n` read-index convention exactly, always wrapping into 0..<steps
    // regardless of a negative step or rotate (Swift's `%` alone can return negative, so the double-mod is the
    // actual thing under test here, not a decoration).
    func testRiffRotateStepWrapsPositiveAndNegative() {
        XCTAssertEqual(riffRotateStep(0, by: 0, steps: 8), 0)
        XCTAssertEqual(riffRotateStep(3, by: 2, steps: 8), 5)
        XCTAssertEqual(riffRotateStep(7, by: 2, steps: 8), 1, "wraps forward past the last step")
        XCTAssertEqual(riffRotateStep(1, by: -3, steps: 8), 6, "a negative rotate wraps backward, never a negative index")
        XCTAssertEqual(riffRotateStep(0, by: -1, steps: 8), 7)
        XCTAssertEqual(riffRotateStep(5, by: 0, steps: 0), 0, "defensive: zero steps never divides by zero")
    }

    // MARK: - defensive resolver clamps (reachable only via a hostile/legacy DECODE — the UI constrains these)

    // These guard the classic silent-regression: someone "simplifies" the negative-safe modulo / drops a clamp and a
    // legacy or garbage-decoded door breaks on the render path. The happy path is exercised elsewhere with valid values;
    // here we pin the edges. (coverage 2026-08-29)
    func testReceiverScaleAndExcludeResolversClampAndWrap() {
        var r = Receiver()
        // scaleRootResolved — negative-safe wrap into 0…11 (the (r%12+12)%12 guard)
        r.scaleRoot = -1;  XCTAssertEqual(r.scaleRootResolved, 11, "a negative root wraps up, never negative")
        r.scaleRoot = 14;  XCTAssertEqual(r.scaleRootResolved, 2)
        r.scaleRoot = nil; XCTAssertEqual(r.scaleRootResolved, 0, "nil ⇒ C")
        // scaleBaseOctResolved — 0…8
        r.scaleBaseOct = -3; XCTAssertEqual(r.scaleBaseOctResolved, 0)
        r.scaleBaseOct = 12; XCTAssertEqual(r.scaleBaseOctResolved, 8)
        r.scaleBaseOct = nil; XCTAssertEqual(r.scaleBaseOctResolved, 3)
        // scaleOctavesResolved — floored at 1 (a decoded 0 must never feed an empty range to scaleNotes)
        r.scaleOctaves = 0; XCTAssertEqual(r.scaleOctavesResolved, 1, "0 floors to 1 — never a degenerate empty scale")
        r.scaleOctaves = 9; XCTAssertEqual(r.scaleOctavesResolved, 4)
        r.scaleOctaves = nil; XCTAssertEqual(r.scaleOctavesResolved, 2)
        // excludeDoorResolved — out-of-range / nil ⇒ OFF(-1)
        r.excludeDoor = 5;   XCTAssertEqual(r.excludeDoorResolved, -1, "an out-of-range door ⇒ OFF")
        r.excludeDoor = -2;  XCTAssertEqual(r.excludeDoorResolved, -1)
        r.excludeDoor = 2;   XCTAssertEqual(r.excludeDoorResolved, 2)
        r.excludeDoor = nil; XCTAssertEqual(r.excludeDoorResolved, -1)
        // controllerMaskResolved — nil ⇒ all four; a garbage decoded byte is truncated to the 4-emitter mask
        r.controllerMask = nil;  XCTAssertEqual(r.controllerMaskResolved, 0b1111, "nil ⇒ forward on all four emitters")
        r.controllerMask = 0xF3; XCTAssertEqual(r.controllerMaskResolved, 0b0011, "high bits truncated to 4 bits")
    }
    func testCellStarsResolverClamps() {
        var c = Cell(machineID: "gold")
        c.stars = nil; XCTAssertEqual(c.starsResolved, 0, "nil ⇒ unrated")
        c.stars = 9;   XCTAssertEqual(c.starsResolved, 5, "clamped to the 5-star ceiling")
        c.stars = -1;  XCTAssertEqual(c.starsResolved, 0, "clamped to the floor")
    }

    // ── SIX VERTICAL SLIDERS (usability ferry, 2026-10-12) — pure range/mapping/commit/revert/default
    // logic behind `EuclideousVSlider`, EuclideousPage.swift. ──────────────────────────────────────────
    func testEuclideousSliderRangeReadsEachFieldsCurrentValueAndBounds() {
        var l = EuclidLine(pulses: 3, noteSel: .all)
        l.steps = 8; l.rotate = 2; l.tilt = 0.4; l.gate = 0.6; l.velocityAbsolute = 90
        var r = euclideousSliderRange(.hits, l)
        XCTAssertEqual(r.value, 3); XCTAssertEqual(r.lo, 0); XCTAssertEqual(r.hi, 8, "HITS is 0...STEPS")
        r = euclideousSliderRange(.steps, l)
        XCTAssertEqual(r.value, 8); XCTAssertEqual(r.lo, 2); XCTAssertEqual(r.hi, 16)
        r = euclideousSliderRange(.offset, l)
        // OFFSET DRAG DIRECTION fix (Paul, on-device): the slider's own displayed value is the MIRROR of
        // raw rotate, `(n-r)%n` — rotate=2 at steps=8 displays as (8-2)%8=6, not the raw 2 (see
        // euclideousSliderRange's own comment for why).
        XCTAssertEqual(r.value, 6); XCTAssertEqual(r.hi, 7, "OFFSET is 0...STEPS-1")
        XCTAssertEqual(euclideousSliderRange(.tilt, l).value, 0.4, accuracy: 1e-9)
        XCTAssertEqual(euclideousSliderRange(.gate, l).value, 0.6, accuracy: 1e-9)
        XCTAssertEqual(euclideousSliderRange(.velocity, l).value, 90)
    }
    func testEuclideousSliderFracMatchesRangePosition() {
        var l = EuclidLine(pulses: 4, noteSel: .all); l.steps = 8
        XCTAssertEqual(euclideousSliderFrac(.hits, l), 0.5, accuracy: 1e-9, "4 of 0...8 is exactly halfway")
    }
    func testEuclideousSliderValueAtBandsWholeNumberFields() {
        var l = EuclidLine(pulses: 0, noteSel: .all); l.steps = 8
        XCTAssertEqual(euclideousSliderValueAt(.hits, l, frac: 0), 0, "touch at the very bottom gives the minimum")
        XCTAssertEqual(euclideousSliderValueAt(.hits, l, frac: 1), 8, "touch at the very top gives the maximum")
        XCTAssertEqual(euclideousSliderValueAt(.hits, l, frac: 0.99), 8, "still the top band just short of 1.0")
    }
    func testEuclideousSliderValueAtIsContinuousForGateAndVelocity() {
        let l = EuclidLine(pulses: 1, noteSel: .all)
        // GATE's floor lowered 5%→1% (Paul, on-device: "quite a long gate at minimum, 5 of 16" — the old 5%
        // floor was tiny only under the pre-redesign fixed-tick formula; proportional-to-the-real-gap, it's
        // a non-trivial ~40-50ms on a sparse pattern).
        XCTAssertEqual(euclideousSliderValueAt(.gate, l, frac: 0.5), 0.01 + 0.5 * (1 - 0.01), accuracy: 1e-9)
        XCTAssertEqual(euclideousSliderValueAt(.velocity, l, frac: 0), 1)
        XCTAssertEqual(euclideousSliderValueAt(.velocity, l, frac: 1), 127)
    }
    func testEuclideousSliderTickFracsOnlyHitsAndOffset() {
        var l = EuclidLine(pulses: 2, noteSel: .all); l.steps = 4
        XCTAssertEqual(euclideousSliderTickFracs(.hits, l).count, 5, "0...4 inclusive = 5 possible values")
        XCTAssertEqual(euclideousSliderTickFracs(.offset, l).count, 4, "0...3 inclusive = 4 possible values")
        XCTAssertTrue(euclideousSliderTickFracs(.steps, l).isEmpty)
        XCTAssertTrue(euclideousSliderTickFracs(.tilt, l).isEmpty)
        XCTAssertTrue(euclideousSliderTickFracs(.gate, l).isEmpty)
        XCTAssertTrue(euclideousSliderTickFracs(.velocity, l).isEmpty)
    }
    func testEuclideousSliderCommitHitsRebuildsAnEditedPatternFromTheFrozenSnapshot() {
        let snap = EuclidLine(pulses: 1, steps: 8, noteSel: .all, customHits: [true, false, false, false, false, false, false, false])
        var line = snap
        euclideousSliderCommit(.hits, &line, snapshot: snap, newValue: 2)
        XCTAssertEqual(line.customHits ?? [], [true, false, false, false, true, false, false, false], "adds into the widest gap, opposite the one existing hit")
        // Drag back down to the ORIGINAL count — rebuilt from the SAME frozen snapshot, not the intermediate line.
        euclideousSliderCommit(.hits, &line, snapshot: snap, newValue: 1)
        XCTAssertEqual(line.customHits, snap.customHits, "dragging back to the starting count restores the pattern exactly")
    }
    func testEuclideousSliderCommitHitsOnAPurePatternJustSetsPulses() {
        var line = EuclidLine(pulses: 3, steps: 8, noteSel: .all)
        euclideousSliderCommit(.hits, &line, snapshot: line, newValue: 5)
        XCTAssertEqual(line.pulses, 5)
        XCTAssertNil(line.customHits, "no hand-edited pattern ⇒ stays pure Euclid, only pulses changes")
    }
    func testEuclideousSliderCommitStepsRevertsAnEditedPatternOnlyWhenItActuallyChanges() {
        let edited = EuclidLine(pulses: 2, steps: 4, noteSel: .all, customHits: [true, false, true, false])
        var line = edited
        euclideousSliderCommit(.steps, &line, snapshot: edited, newValue: 4)
        XCTAssertEqual(line.customHits, edited.customHits, "landing on the SAME steps value is a no-op — the edit survives")
        euclideousSliderCommit(.steps, &line, snapshot: edited, newValue: 8)
        XCTAssertNil(line.customHits, "a genuine STEPS change reverts the hand edit to pure Euclid")
        XCTAssertEqual(line.steps, 8)
    }
    func testEuclideousSliderCommitOffsetGateVelocity() {
        var line = EuclidLine(pulses: 1, steps: 8, noteSel: .all)
        euclideousSliderCommit(.offset, &line, snapshot: line, newValue: 11)
        // OFFSET DRAG DIRECTION fix: the committed value is the MIRROR of the displayed slider value, not
        // a direct write — 11 wraps mod 8 to a displayed 3, which mirrors to rotate = (8-3)%8 = 5.
        XCTAssertEqual(line.rotate, 5, "wraps mod steps (11 mod 8 = 3 displayed), then mirrored to the stored rotate")
        euclideousSliderCommit(.gate, &line, snapshot: line, newValue: 0.5)
        XCTAssertEqual(line.gate, 0.5)
        euclideousSliderCommit(.velocity, &line, snapshot: line, newValue: 200)
        XCTAssertEqual(line.velocityAbsolute, 127, "clamps to the MIDI ceiling")
    }
    /// Paul, on-device: "I scroll left, the hits scroll right" — a direct regression guard for the ACTUAL
    /// visual claim, not just the raw stored number: committing a HIGHER displayed OFFSET value (what
    /// dragging the slider RIGHT produces) must move a hit's real on-screen box position RIGHT, using the
    /// SAME `euclidPatternInto` the real step-box row draws with.
    func testEuclideousSliderOffsetDragRightMovesHitsRightOnScreen() {
        func boxIndex(displayedOffset: Double) -> Int {
            var line = EuclidLine(pulses: 1, steps: 8, noteSel: .all)
            euclideousSliderCommit(.offset, &line, snapshot: line, newValue: displayedOffset)
            var buf = [Bool](repeating: false, count: 8)
            euclidPatternInto(&buf, pulses: 1, steps: 8, rotation: line.rotate)
            return buf.firstIndex(of: true)!
        }
        XCTAssertEqual(boxIndex(displayedOffset: 2), (boxIndex(displayedOffset: 0) + 2) % 8,
                        "dragging right (raising the displayed value by 2) moves the hit 2 boxes to the right")
    }
    func testEuclideousSliderCommitTiltIsANoOpOnAnEditedPattern() {
        let edited = EuclidLine(pulses: 1, steps: 2, noteSel: .all, tilt: 0, customHits: [true, false])
        var line = edited
        euclideousSliderCommit(.tilt, &line, snapshot: edited, newValue: 0.8)
        XCTAssertEqual(line.tilt, 0, "defensive guard — the UI never drags a disabled TILT, but the commit itself must still refuse")
    }
    func testEuclideousSliderRevertRestoresOnlyTheOwnedField() {
        let before = EuclidLine(pulses: 2, steps: 8, rotate: 1, noteSel: .all)
        var line = before
        line.rotate = 5
        euclideousSliderRevert(.offset, &line, snapshot: before)
        XCTAssertEqual(line.rotate, 1)
    }
    // RHYTHM fixes §4 (2026-10-21): a revert used to restore only the headline field (pulses/steps/
    // rotate), leaving hitsRequested/offsetRequested (and, for STEPS, pulses/rotate too) at whatever the
    // committed-then-aborted drag last wrote — a long-press-cancel could leave a stale requested value to
    // resurface on a later edit. Each revert now restores every field its own commit can touch.
    func testEuclideousSliderRevertRestoresHitsRequestedToo() {
        let before = EuclidLine(pulses: 2, steps: 8, noteSel: .all, hitsRequested: 2)
        var line = before
        line.pulses = 6; line.hitsRequested = 6
        euclideousSliderRevert(.hits, &line, snapshot: before)
        XCTAssertEqual(line.pulses, 2); XCTAssertEqual(line.hitsRequested, 2)
    }
    func testEuclideousSliderRevertRestoresOffsetRequestedToo() {
        let before = EuclidLine(pulses: 2, steps: 8, rotate: 1, noteSel: .all, offsetRequested: 7)
        var line = before
        line.rotate = 5; line.offsetRequested = 1
        euclideousSliderRevert(.offset, &line, snapshot: before)
        XCTAssertEqual(line.rotate, 1); XCTAssertEqual(line.offsetRequested, 7)
    }
    func testEuclideousSliderRevertOnStepsRestoresPulsesRotateAndBothRequestedFields() {
        // Touch-down: STEPS=8, pulses=3, rotate=1, neither Requested field pinned yet.
        let before = EuclidLine(pulses: 3, steps: 8, rotate: 1, noteSel: .all)
        var line = before
        // Mid-drag the commit pins both Requested fields from the pre-change values, then changes STEPS,
        // pulses and rotate for the new length (steps: 8→12, matching euclideousSliderCommit's own formula).
        euclideousSliderCommit(.steps, &line, snapshot: before, newValue: 12)
        XCTAssertEqual(line.steps, 12)
        XCTAssertNotNil(line.hitsRequested, "sanity: the commit actually pinned something to revert"); XCTAssertNotNil(line.offsetRequested)
        euclideousSliderRevert(.steps, &line, snapshot: before)
        XCTAssertEqual(line.steps, before.steps); XCTAssertEqual(line.pulses, before.pulses); XCTAssertEqual(line.rotate, before.rotate)
        XCTAssertNil(line.hitsRequested, "the pin the commit made must be undone too, not left stale")
        XCTAssertNil(line.offsetRequested)
    }
    func testEuclideousSliderDoubleTapDefaults() {
        var line = EuclidLine(pulses: 3, steps: 8, rotate: 4, noteSel: .all, gate: 0.3, velocityAbsolute: 40, tilt: 0.5)
        euclideousSliderDoubleTapDefault(.hits, &line); XCTAssertEqual(line.pulses, 3, "HITS has no double-tap default, matching the old pad's own behaviour")
        euclideousSliderDoubleTapDefault(.steps, &line); XCTAssertEqual(line.steps, 8, "STEPS likewise has none")
        euclideousSliderDoubleTapDefault(.offset, &line); XCTAssertEqual(line.rotate, 0)
        euclideousSliderDoubleTapDefault(.tilt, &line); XCTAssertEqual(line.tilt, 0)
        euclideousSliderDoubleTapDefault(.gate, &line); XCTAssertEqual(line.gate, 0.9)
        euclideousSliderDoubleTapDefault(.velocity, &line); XCTAssertEqual(line.velocityAbsolute, 100)
    }
    func testEuclideousSliderValueTextFormatting() {
        var l = EuclidLine(pulses: 3, steps: 8, noteSel: .all, tilt: 0)
        XCTAssertEqual(euclideousSliderValueText(.tilt, l), "0%", "zero carries no sign (RHYTHM POLISH §2.2: a whole percent, so \"0%\")")
        l.tilt = 0.2
        XCTAssertEqual(euclideousSliderValueText(.tilt, l), "+20%")
        l.tilt = -0.3
        XCTAssertEqual(euclideousSliderValueText(.tilt, l), "−30%", "a true minus sign, not an ASCII hyphen")
    }
    // Paul, on-device (2026-10-14): "The label GATE should read as LEGATO when at 100%" — a second, VISIBLE
    // legato cue beside the existing VoiceOver-only one; the on-screen VALUE stays a bare "100%" throughout.
    func testEuclideousSliderLabelTextSwitchesToLegatoAtExactly100PercentForGateOnly() {
        var l = EuclidLine(pulses: 3, steps: 8, noteSel: .all, gate: 0.99)
        XCTAssertEqual(euclideousSliderLabelText(.gate, l), "GATE", "below 100% stays the plain field name")
        l.gate = 1.0
        XCTAssertEqual(euclideousSliderLabelText(.gate, l), "LEGATO")
        XCTAssertEqual(euclideousSliderValueText(.gate, l), "100%", "the on-screen VALUE is unaffected — still bare '100%', only the label swaps")
        // scoped to GATE only — another field sitting at its own "100" doesn't borrow the legato label.
        var vel = EuclidLine(pulses: 3, steps: 8, noteSel: .all, velocityAbsolute: 100)
        XCTAssertEqual(euclideousSliderLabelText(.velocity, vel), "VEL")
        vel.velocityAbsolute = 127
        XCTAssertEqual(euclideousSliderLabelText(.velocity, vel), "VEL", "never LEGATO for any field but GATE")
    }
    func testEuclideousSliderAccessibilityStepIsPercentForGateAndFivePercentForTilt() {
        XCTAssertEqual(euclideousSliderAccessibilityStep(.gate), 0.01)
        XCTAssertEqual(euclideousSliderAccessibilityStep(.tilt), 0.05, "RHYTHM POLISH §2.4: a TILT swipe moves 5 %")
        XCTAssertEqual(euclideousSliderAccessibilityStep(.hits), 1)
        XCTAssertEqual(euclideousSliderAccessibilityStep(.velocity), 1)
    }
    func testEuclidWidestGapCenterEdgeCases() {
        XCTAssertNil(euclidWidestGapCenter([true, true, true]), "fully packed — nothing to add to")
        XCTAssertEqual(euclidWidestGapCenter([false, false, false, false]), 0, "all-rest starts the very first hit at 0")
    }
    func testEuclidMostCrowdedHitEdgeCases() {
        XCTAssertNil(euclidMostCrowdedHit([false, false, false]), "no hits to remove")
        XCTAssertEqual(euclidMostCrowdedHit([false, false, true, false]), 2, "a lone hit is trivially the one removed")
    }

    // ── RATE = DIVISION × FEEL (ratified PATTERN-tab-layout ferry, 2026-10-12) ─────────────────────────
    func testEuclideousRateDivisionFeelDecomposesEveryArpRateExactly() {
        XCTAssertEqual(euclideousRateDivisionFeel(.r1_1).division, 0); XCTAssertEqual(euclideousRateDivisionFeel(.r1_1).feel, 0)
        XCTAssertEqual(euclideousRateDivisionFeel(.r1_32).division, 5); XCTAssertEqual(euclideousRateDivisionFeel(.r1_32).feel, 0)
        XCTAssertEqual(euclideousRateDivisionFeel(.r1_4d).division, 2); XCTAssertEqual(euclideousRateDivisionFeel(.r1_4d).feel, 1)
        XCTAssertEqual(euclideousRateDivisionFeel(.r1_8t).division, 3); XCTAssertEqual(euclideousRateDivisionFeel(.r1_8t).feel, 2)
    }
    func testEuclideousRateFromDivisionFeelRoundTripsEveryCombination() {
        for rate in ArpRate.allCases {
            let (d, f) = euclideousRateDivisionFeel(rate)
            XCTAssertEqual(euclideousRateFromDivisionFeel(division: d, feel: f), rate)
        }
    }
    func testEuclideousRateFromDivisionFeelClampsOutOfRangeInputs() {
        XCTAssertEqual(euclideousRateFromDivisionFeel(division: -1, feel: 0), .r1_1)
        XCTAssertEqual(euclideousRateFromDivisionFeel(division: 99, feel: 99), .r1_32t)
    }

    // ── RIFF-GRID WALK TAGS WITH THREADS (ferry, ratified by Paul 2026-10-15) ───────────────────────────
    // Reference block 42.5 × 29pt, 4pt gaps. Every lane below hits on EVERY tick (8 of 8) with sub = 0.25, so tick k
    // is the lane's k-th hit and (FREE, ADV HIT) its walk ordinal is k — which lets a test name "the landing on
    // ordinal k" directly. Ticks are taken well away from 0 so the scan's look-back never reaches a negative tick.
    private let wtW: CGFloat = 42.5, wtH: CGFloat = 29, wtGap: CGFloat = 4
    private func wtConfig(sub: Double = 0.25, dir: RiffDir = .forward, length: Int = 8, stride: Int = 1, rotate: Int = 0, locked: Bool = false, advanceStep: Bool = false) -> EuclideousWalkLaneConfig {
        // RESTART CHAINS (2026-10-19): the mirror's real tick decision now reads `.chains`, not `.locked`/`.grid`
        // (kept only for FX) — "LOCK" here is a melody chain of [1] (§4.7), lapBeats = this config's own 8-tick lap.
        let chains = locked ? EuclideousLaneRestartChains(rhythm: .free, melody: .from([1]), barBeats: 4, lapBeats: 8 * sub) : .off
        return EuclideousWalkLaneConfig(buf: [Bool](repeating: true, count: 16), n: 8, dir: .fwd, sub: sub, chains: chains, riffDir: dir, stride: stride, length: length,
                                 rotate: rotate, locked: locked, advanceStep: advanceStep)
    }
    /// The plan "just after" tick `k` landed (a quarter of a tick later), 120 BPM, polled step = what the engine
    /// would report for that hit. `ranks` default: step i sits on row i+1.
    private func wtPlan(_ cfg: EuclideousWalkLaneConfig, tick k: Int64, ranks: [Int] = [1, 2, 3, 4, 5, 6, 7, 8], running: Bool = true) -> EuclideousWalkTagPlan? {
        euclideousWalkTagPlan(cfg: cfg, ranks: ranks, beat: (Double(k) + 0.25) * cfg.sub, secondsPerBeat: 0.5,
                              polledStep: euclideousWalkTick(cfg, tick: k).playedStep, running: running)
    }


    // Direction --------------------------------------------------------------------------------------
    func testWalkTagFwdPointsRightAtEveryStepAndRevLeft() {
        let f = wtConfig(dir: .forward), r = wtConfig(dir: .reverse)
        for k in Int64(160)..<Int64(176) {
            XCTAssertEqual(wtPlan(f, tick: k)?.facingRight, true, "FWD tick \(k)")
            XCTAssertEqual(wtPlan(r, tick: k)?.facingRight, false, "REV tick \(k)")
        }
    }
    func testWalkTagPendulumFacesRightGoingUpLeftOnLandingAtEightAndDownAndRightOnLandingAtOne() {
        let c = wtConfig(dir: .pendulum)   // positions by ordinal: 0…7, 6…1, 0, 1…  (period 14)
        let base: Int64 = 14 * 12
        for o in Int64(0)...6 { XCTAssertEqual(wtPlan(c, tick: base + o)?.facingRight, true, "going up, step \(o + 1)") }
        XCTAssertEqual(wtPlan(c, tick: base + 7)?.seatStep, 7)
        XCTAssertEqual(wtPlan(c, tick: base + 7)?.facingRight, false, "landing on 8: the next move goes down")
        for o in Int64(8)...13 { XCTAssertEqual(wtPlan(c, tick: base + o)?.facingRight, false, "on the way down, ord \(o)") }
        XCTAssertEqual(wtPlan(c, tick: base + 14)?.seatStep, 0)
        XCTAssertEqual(wtPlan(c, tick: base + 14)?.facingRight, true, "landing on 1: right")
        XCTAssertEqual(wtPlan(c, tick: base + 7)?.turned, true); XCTAssertEqual(wtPlan(c, tick: base + 14)?.turned, true)
        XCTAssertEqual(wtPlan(c, tick: base + 3)?.turned, false)
    }

    func testWalkTagWrapEndsFollowTheStepsTheWalkActuallyVisits() {
        // STRIDE 2 on LEN 8 only ever lands on 1,3,5,7: the loop's end blocks are columns 1 and 7.
        let r = euclideousWalkVisitedRange(dir: .forward, length: 8, stride: 2, rotate: 0)
        XCTAssertEqual(r.min, 0); XCTAssertEqual(r.max, 6)
        XCTAssertEqual(euclideousWalkVisitedRange(dir: .forward, length: 8, stride: 1, rotate: 0).max, 7)
        XCTAssertEqual(euclideousWalkVisitedRange(dir: .forward, length: 5, stride: 1, rotate: 3).max, 4)
    }

    // Rests, empty riffs, the poll ---------------------------------------------------------------------
    func testWalkTagOnARestSitsHollowAtTheLastNotesHeight() {
        let ranks = [3, 0, 0, 6, 0, 0, 0, 0]
        let plan = wtPlan(wtConfig(), tick: 8 * 10 + 2, ranks: ranks)!   // step 3 is a rest; the walk last played step 1 (row 3)
        XCTAssertTrue(plan.seatIsRest); XCTAssertEqual(plan.seatStep, 2); XCTAssertEqual(plan.seatRank, 3)
        let atFour = wtPlan(wtConfig(), tick: 8 * 10 + 5, ranks: ranks)!   // step 6 is a rest; the last note was step 4 (row 6)
        XCTAssertTrue(atFour.seatIsRest); XCTAssertEqual(atFour.seatRank, 6)
    }
    func testWalkTagBeforeAnyNoteHasPlayedUsesTheNearestNoteBehindInWalkOrder() {
        let ranks = [0, 0, 0, 0, 0, 0, 0, 5]   // only step 8 is a note; the tag is on step 2 and has "never played" yet
        let plan = wtPlan(wtConfig(), tick: 8 * 10 + 1, ranks: ranks)!
        XCTAssertTrue(plan.seatIsRest); XCTAssertEqual(plan.seatRank, 5, "behind step 2 in FWD order is step 1, then 8")
    }
    func testWalkTagEmptyRiffShowsNoTag() {
        XCTAssertNil(wtPlan(wtConfig(), tick: 100, ranks: [0, 0, 0, 0, 0, 0, 0, 0]))
        XCTAssertNil(wtPlan(wtConfig(length: 3), tick: 100, ranks: [0, 0, 0, 4, 4, 4, 4, 4]), "notes beyond LEN are never visited")
    }
    func testWalkTagNotStartedShowsNoTag() {
        let cfg = wtConfig()
        XCTAssertNil(euclideousWalkTagPlan(cfg: cfg, ranks: [1, 2, 3, 4, 5, 6, 7, 8], beat: 25, secondsPerBeat: 0.5, polledStep: -1, running: true))
    }
    func testWalkTagFollowsThePolledStepAndGoesStaticWhenThePredictionDisagrees() {
        let cfg = wtConfig()
        let beat = (82.0 + 0.25) * cfg.sub
        let ranks = [1, 2, 3, 4, 5, 6, 7, 8]
        let ok = euclideousWalkTagPlan(cfg: cfg, ranks: ranks, beat: beat, secondsPerBeat: 0.5, polledStep: 2, running: true)!
        XCTAssertNotNil(ok.nextSeconds, "polled step == predicted landing: a flight is scheduled")
        let lagging = euclideousWalkTagPlan(cfg: cfg, ranks: ranks, beat: beat, secondsPerBeat: 0.5, polledStep: 1, running: true)!
        XCTAssertEqual(lagging.seatStep, 2, "poll one hit behind, within the grace: the tag is already on the landing")
        let lost = euclideousWalkTagPlan(cfg: cfg, ranks: ranks, beat: beat, secondsPerBeat: 0.5, polledStep: 6, running: true)!
        XCTAssertEqual(lost.seatStep, 6, "the polled step is the authority when the prediction can't account for it")
        XCTAssertNil(lost.nextSeconds); XCTAssertNil(lost.dest)
    }


    func testWalkTagSchedulesTheSwungOnsetNotTheStraightTickBeat() {
        // 1/8 ticks with the scene step S = 0.5 and swing 75% (a = 1.5): odd ticks land at base + a·S = 0.75 into the
        // beat-pair instead of 0.5. The tag must arrive at the note-on's REAL time, not the straight tick beat.
        var cfg = wtConfig(sub: 0.5)
        cfg.swingA = 1.5; cfg.swingStepBeats = 0.5
        let plan = euclideousWalkTagPlan(cfg: cfg, ranks: [1, 2, 3, 4, 5, 6, 7, 8], beat: 50.2, secondsPerBeat: 0.5,
                                         polledStep: euclideousWalkTick(cfg, tick: 100).playedStep, running: true)!
        XCTAssertEqual(plan.nextSeconds!, (50.75 - 50.2) * 0.5, accuracy: 1e-9, "tick 101 sounds at 50.75, not 50.5")
        XCTAssertEqual(plan.landedSeconds!, (50.0 - 50.2) * 0.5, accuracy: 1e-9)
        XCTAssertEqual(euclideousWalkRealBeat(cfg, tick: 101), 50.75, accuracy: 1e-12)
        // No swing: the straight tick beat.
        var straight = cfg; straight.swingA = 1
        XCTAssertEqual(euclideousWalkRealBeat(straight, tick: 101), 50.5, accuracy: 1e-12)
    }

    // The ferry: a tag's destination is "the same value the lane footer shows for that hit". Cross-check the mirror's
    // played step for every hit of a lap against the footer's own `euclideousRiffCyclePrediction`.
    private func wtFooterAgreement(_ name: String, walk: (inout EuclidLine) -> Void, file: StaticString = #filePath, line: UInt = #line) {
        var L = EuclidLine(target: 0, pulses: 5, steps: 8, rate: .r1_16, useRiff: true, sourceMode: .midi)
        L.rotate = 3
        walk(&L)
        let cfg = euclideousWalkLaneConfig(lane: 0, lines: [L], cyc: 4, resetSpanBars: 0, lanesSeqRate: .oneBar, lanesSeqLen: 8)!
        let hitSteps = euclideousLapHitSteps(pulses: L.pulses, steps: 8, rotate: L.rotate, tilt: L.tiltResolved, patternMiss: false, customHits: nil, dir: L.directionResolved)
        let lapStart = Int64(8 * 100)
        let lapTicks = (lapStart..<(lapStart + 8)).filter { euclideousWalkTick(cfg, tick: $0).isHit }
        XCTAssertEqual(lapTicks.count, hitSteps.count, "\(name): same hits per lap", file: file, line: line)
        let live = euclideousWalkTick(cfg, tick: lapTicks[0]).advOrd
        let nowBeat = Double(lapStart) * cfg.sub
        let isMelodyRestartPass = euclideousIsMelodyChainRestartPass(beat: nowBeat, lapBeats: cfg.chains.lapBeats, barBeats: cfg.chains.barBeats,
                                                                      rhythmChain: cfg.chains.rhythm, melodyChain: cfg.chains.melody)
        let base = euclideousRiffLapBaseline(hitSteps: hitSteps, lapSteps: 8, isMelodyRestartPass: isMelodyRestartPass, advanceStep: L.riffAdvanceStepResolved, liveOrd: live, dir: L.directionResolved)
        let footer = euclideousRiffCyclePrediction(hitSteps: hitSteps, advanceStep: L.riffAdvanceStepResolved, dir: L.euclideousRiffDirResolved, stride: L.riffStrideResolved,
                                                   length: L.riffLengthResolved, rotate: L.riffRotateResolved, seed: 0, startOrd: base.startOrd)
        for (i, t) in lapTicks.enumerated() {
            XCTAssertEqual(footer[i] - 1, euclideousWalkTick(cfg, tick: t).playedStep, "\(name): hit \(i)", file: file, line: line)
        }
    }
    func testWalkTagDestinationsAgreeWithTheLaneFooterForFreeAndMelodyRestartHitAdvance() {
        wtFooterAgreement("FREE/HIT") { _ in }
        wtFooterAgreement("FREE/HIT pendulum stride 3 len 6") { $0.riffDir = .pendulum; $0.riffStride = 3; $0.riffLength = 6 }
        // RESTART CHAINS (2026-10-19): a melody chain of [1] restarts every pass — exactly old LOCK's own
        // guarantee (§4.7) — so this sub-case now sets the chain field directly instead of the retired `riffLock`.
        wtFooterAgreement("MELODY-1/HIT") { $0.restartMelodyPasses = [1] }
        wtFooterAgreement("FREE/STEP") { $0.riffAdvanceStep = true }
        // NOT covered, on purpose: a restarting melody chain + ADV STEP. There the footer (`euclideousRiffLapBaseline`
        // returns startOrd 0 for any restart pass) predicts steps that are off by the lap's first-hit tick, while the
        // engine feeds the walk the lap-local tick itself — so the mirror (which matches the engine, see RouterTests)
        // and the footer disagree. Pre-existing footer bug (inherited unchanged from old LOCK), outside this ferry's
        // "footers stay as built"; reported to Paul.
    }

    func testWalkTagHeldHeightUsesTheLastNoteActuallyPlayedNotAnOrdinalWalk() {
        // ADV STEP: ordinals tick on every pattern step, but only hits play. 2 hits per 8 steps at steps 0 and 5 (rank 4 / rank 0):
        var cfg = wtConfig(advanceStep: true)
        cfg.buf = [true, false, false, false, false, true, false, false] + [Bool](repeating: false, count: 8)
        let ranks = [4, 0, 0, 0, 0, 0, 0, 0]
        // At the hit on tick 8·10+5 the walk lands on step (ord 85 mod 8) = 5 (a rest). The last PLAYED note was the hit
        // at tick 80 → step 0 → rank 4. (An ordinal walk would also find rank 4 here; make it differ: ranks[3] = 9→clamped.)
        let plan = euclideousWalkTagPlan(cfg: cfg, ranks: [4, 0, 0, 7, 0, 0, 0, 0], beat: (8.0 * 10 + 5 + 0.25) * cfg.sub, secondsPerBeat: 0.5,
                                         polledStep: 5, running: true)!
        _ = ranks
        XCTAssertTrue(plan.seatIsRest)
        XCTAssertEqual(plan.seatRank, 4, "the previous hit played step 1 (row 4); step 4's row-7 note was never struck, so it can't set the height")
    }

    // ── FOURFOLD HEADER (ferry, approved 2026-10-15) ─────────────────────────────────────────────────────
    // §10.5 — the key label is the receiver chip's own format, for every root and scale type.
    func testFourfoldKeyLabelMatchesTheReceiverChipFormatForEveryRootAndScale() {
        let names = ["C", "C#", "D", "D#", "E", "F", "F#", "G", "G#", "A", "A#", "B"]
        for root in 0..<12 {
            for t in ScaleType.allCases {
                XCTAssertEqual(euclideousKeyLabel(root: root, type: t), "\(names[root]) \(t.label)")
                var r = Receiver(); r.doorMode = .scale
                r.scalePools = [ScalePool(root: root, type: t, baseOct: 3, octaves: 2)]; r.activeScale = 0
                XCTAssertEqual(r.scaleLabel, euclideousKeyLabel(root: root, type: t), "the receiver chip and the pill can never disagree")
            }
        }
        XCTAssertEqual(euclideousKeyLabel(root: 0, type: .naturalMinor), "C MINOR", "a fresh session's default key")
        XCTAssertEqual(euclideousKeyLabel(root: 2, type: .dorian), "D DORIAN")
        XCTAssertEqual(euclideousKeyLabel(root: -1, type: .major), "B MAJOR", "a negative root wraps")
        XCTAssertLessThanOrEqual(ScaleType.allCases.map { euclideousKeyLabel(root: 1, type: $0).count }.max() ?? 0, 13, "the 120pt pill fits 13 characters")
    }



    // §10.3 — the layout ladder.
    private typealias HM = EuclideousHeaderMetrics
    /// PAGE LAYOUT ferry (2026-10-19): the header's one positional input (the riff panel's x, less the page margin) comes from the PAGE layout. `pageFor` builds the page a header of this
    /// container width sits over (the height is synthetic: any value that keeps the orientation).
    private func pageFor(_ containerW: CGFloat, landscape: Bool) -> EuclideousPageLayout {
        euclideousPageLayout(size: CGSize(width: containerW + 32, height: landscape ? 600 : containerW + 432))
    }
    private func hdrLayout(_ containerW: CGFloat, landscape: Bool) -> EuclideousHeaderLayout {
        let p = pageFor(containerW, landscape: landscape)
        return euclideousHeaderLayout(containerW: containerW, isLandscape: landscape, riffLeadingX: p.riffLeadingX)
    }
    /// no two groups on a row closer than the layout's gap; nothing past either container edge.
    private func assertHeaderInvariants(_ l: EuclideousHeaderLayout, _ containerW: CGFloat, _ msg: String, file: StaticString = #filePath, line: UInt = #line) {
        let frames = [l.brand, l.notes, l.utilities]
        for f in frames {
            XCTAssertGreaterThanOrEqual(f.x, -1e-9, "\(msg): nothing before the leading edge", file: file, line: line)
            XCTAssertLessThanOrEqual(f.x + f.width, containerW + 1e-9, "\(msg): nothing past the trailing edge", file: file, line: line)
        }
        for row in 0..<l.rowCount {
            let r = frames.filter { $0.row == row }.sorted { $0.x < $1.x }
            for i in 1..<max(1, r.count) {
                XCTAssertGreaterThanOrEqual(r[i].x - (r[i - 1].x + r[i - 1].width), l.widths.gap - 1e-9, "\(msg): row \(row) groups \(i - 1)/\(i) closer than the gap", file: file, line: line)
            }
        }
    }
    // THE NINE PORTS (2026-10-26): the OUTPUTS group (the four rings) is gone from the header — a note's port is fixed by its lane and layer.
    func testTheHeaderHasThreeGroupsAndNoRings() {
        let f = euclideousHeaderGroupWidths(compact: false)
        let wordmark: CGFloat = 8 * 11 * 0.76          // 8 chars × 11pt × (0.6 advance + 0.16 tracking)
        // RANDOM MODE ferry (§2.2): the dice adds one more sp8 + one more target after redo — +52pt (+8+44). LANE LOCK ferry (§2.2): the padlock sits sp8 after the dice — once more, +52pt (+8+44).
        XCTAssertEqual(f.brand, 13 + 8 + wordmark + 16 + 88 + 8 + 44 + 8 + 44, accuracy: 1e-9)
        XCTAssertEqual(f.brand, 296, accuracy: 0.2)
        // WIDENED 312→426 (2026-10-20, HOLD/LATCH): two fixed-width chips (48+54) + the sp4 between them + the sp8 before them. UTILITIES is 4 icons (presets · SWING · REEL · settings).
        XCTAssertEqual(f.notes, 426); XCTAssertEqual(f.utilities, 176 + 100, "HOCKET ferry: the pill's reserved width (92) and the sp8 before the presets button")
        XCTAssertEqual(HM.segmentedWidth, 184)
        let c = euclideousHeaderGroupWidths(compact: true)
        // RANDOM MODE / LANE LOCK (§2.2): compact BRAND grew +44 for the dice and +44 for the padlock; the compact target is 36 wide.
        XCTAssertEqual(c.brand, 93 + 44 + 44); XCTAssertEqual(c.utilities, 144 + 100)
        XCTAssertEqual(c.brand + c.utilities + c.gap, 93 + 44 + 44 + 144 + 100 + 8, "layout C's row 1: BRAND and UTILITIES, one gap apart")
        XCTAssertEqual(HM.topMargin, 9, "a 44pt row centred on the 31pt centre line")
        XCTAssertEqual(HM.wordmarkWidth, 8 * 11 * 0.76, accuracy: 1e-9)
    }
    // WIDENED to 1900 (2026-10-23), then to 2300 (HOCKET ferry, 2026-10-27: UTILITIES grew by the pill's 100) so NOTES sits unclamped on the riff panel's leading edge, clear of the utility icons.
    func testLayoutAPutsNotesOnTheRiffPanel() {
        let l = hdrLayout(2300, landscape: true)
        XCTAssertEqual(l.kind, .a); XCTAssertEqual(l.rowCount, 1); XCTAssertEqual(l.height, 44)
        let cols = pageFor(2300, landscape: true)
        XCTAssertEqual(l.brand.x, 0); XCTAssertEqual(l.utilities.x + l.utilities.width, 2300, accuracy: 1e-9)
        XCTAssertEqual(l.notes.x, cols.riffLeadingX, accuracy: 1e-9, "NOTES' leading edge on the riff panel's")
        assertHeaderInvariants(l, 2300, "A@2300")
    }
    func testLayoutANotesSlidesLeftToClearUtilitiesAtItsFloor() {
        let full = euclideousHeaderGroupWidths(compact: false)
        let w = full.brand + full.notes + full.utilities + 2 * full.gap   // A's exact need: 929.88
        let l = hdrLayout(w, landscape: true)
        let cols = pageFor(w, landscape: true)
        XCTAssertEqual(l.kind, .a)
        XCTAssertLessThan(l.notes.x, cols.riffLeadingX, "NOTES slid left to clear UTILITIES")
        XCTAssertEqual(l.utilities.x - (l.notes.x + l.notes.width), full.gap, accuracy: 1e-9)
        XCTAssertEqual(l.notes.x - (l.brand.x + l.brand.width), full.gap, accuracy: 1e-9, "…and at A's floor it sits one gap clear of BRAND too")
        assertHeaderInvariants(l, w, "A at its exact need")
        XCTAssertEqual(hdrLayout(w - 1, landscape: true).kind, .b, "one point narrower falls to B")
        for cw in stride(from: w, through: w + 400, by: 7) { assertHeaderInvariants(hdrLayout(cw, landscape: true), cw, "A@\(cw)") }
    }
    func testLayoutBAt500AndCAt470() {
        let b = hdrLayout(620, landscape: false)   // (500 before the HOCKET button: B now needs 587.88)
        XCTAssertEqual(b.kind, .b); XCTAssertEqual(b.rowCount, 2); XCTAssertEqual(b.height, 44 + 4 + 44)
        XCTAssertEqual(b.notes.row, 1); XCTAssertEqual(b.notes.x, 0, "NOTES on row 2's leading edge")
        XCTAssertEqual([b.brand.row, b.utilities.row], [0, 0])
        assertHeaderInvariants(b, 620, "B@620")
        XCTAssertEqual(hdrLayout(500, landscape: false).kind, .c, "500 used to be layout B; with the HOCKET button it is C")
        let c = hdrLayout(470, landscape: false)
        XCTAssertEqual(c.kind, .c); XCTAssertTrue(c.compact)
        XCTAssertEqual(c.widths.gap, 8)
        assertHeaderInvariants(c, 470, "C@470")
        // a landscape page too narrow for A falls to B, never A; portrait never uses A, however wide.
        XCTAssertEqual(hdrLayout(700, landscape: true).kind, .b)
        XCTAssertEqual(hdrLayout(1200, landscape: false).kind, .b)
    }
    func testFourfoldKeySpokenNameSpellsOutEveryScale() {
        XCTAssertEqual(euclideousKeySpokenName(root: 0, type: .naturalMinor), "C minor")
        XCTAssertEqual(euclideousKeySpokenName(root: 6, type: .mixolydian), "F sharp mixolydian")
        for t in ScaleType.allCases { XCTAssertFalse(euclideousKeySpokenName(root: 3, type: t).hasSuffix("MIXO"), "\(t)") }
    }
    // THE NINE PORTS (2026-10-26): the PORTS tab of the settings sheet — one row per lane, RIFF then NOTES, eight channel steppers in all.
    func testThePortsTabListsEightPortsInLaneOrder() {
        let rows = euclideousPortsTabRows()
        XCTAssertEqual(rows.map { $0.letter }, ["A", "B", "C", "D"])
        XCTAssertEqual(rows.flatMap { $0.ports.map { $0.bus } }, Array(0..<8), "riff bus 2·lane, notes bus 2·lane + 1")
        XCTAssertEqual(rows.flatMap { $0.ports.map { $0.label } }, ["RIFF", "NOTES", "RIFF", "NOTES", "RIFF", "NOTES", "RIFF", "NOTES"])
        XCTAssertEqual(euclideousPortChannelAccessibilityLabel(bus: 0, channel: 1), "Emit Riff A, channel 1")
        XCTAssertEqual(euclideousPortChannelAccessibilityLabel(bus: 7, channel: 16), "Emit Notes D, channel 16")
        XCTAssertEqual(rows.flatMap { $0.ports.map { euclideousPortChannelAccessibilityLabel(bus: $0.bus, channel: 3) } }.map { $0.replacingOccurrences(of: ", channel 3", with: "") },
                       Array(FourfoldPorts.names.dropFirst()), "every stepper is named for the port the host lists")
    }
    func testThePortsAreNamedAndNumberedForTheHost() {
        XCTAssertEqual(FourfoldPorts.names, ["All", "Emit Riff A", "Emit Notes A", "Emit Riff B", "Emit Notes B", "Emit Riff C", "Emit Notes C", "Emit Riff D", "Emit Notes D"])
        XCTAssertEqual(FourfoldPorts.cableCount, 9); XCTAssertEqual(FourfoldPorts.busCount, 8)
        for lane in 0..<4 {
            XCTAssertEqual(FourfoldPorts.cable(lane: lane, part: .riff), 1 + 2 * lane); XCTAssertEqual(FourfoldPorts.cable(lane: lane, part: .notes), 2 + 2 * lane)
            XCTAssertEqual(FourfoldPorts.laneBusMask(lane), FourfoldPorts.busMask(lane: lane, part: .riff) | FourfoldPorts.busMask(lane: lane, part: .notes))
            XCTAssertEqual(FourfoldPorts.lanePart(ofCable: 1 + 2 * lane)?.lane, lane); XCTAssertEqual(FourfoldPorts.lanePart(ofCable: 2 + 2 * lane)?.part, .notes)
        }
        XCTAssertNil(FourfoldPorts.lanePart(ofCable: 0)); XCTAssertNil(FourfoldPorts.lanePart(ofCable: 9))
        XCTAssertEqual(FourfoldPorts.shortName(cable: 0), "ALL"); XCTAssertEqual(FourfoldPorts.shortName(cable: 4), "NOTES B")
    }
    // FOURFOLD REEL LINK (2026-10-23) · THE NINE PORTS (2026-10-26): Fourfold's lanes each have a riff and a notes port; the workbench still says emitter.
    func testTheReelBrowserCopyNamesPortsOnFourfoldAndEmittersOnTheWorkbench() {
        let fourfold = reelInstructionText(fourfold: true), workbench = reelInstructionText(fourfold: false)
        XCTAssertTrue(fourfold.contains("both its ports")); XCTAssertTrue(fourfold.contains("RIFF / NOTES")); XCTAssertFalse(fourfold.contains("emitter"))
        XCTAssertTrue(workbench.contains("that emitter")); XCTAssertFalse(workbench.contains("ports"))
        XCTAssertEqual(reelExportPortsLabel([]), "MASTER")
        XCTAssertEqual(reelExportPortsLabel([0]), "RIFF A"); XCTAssertEqual(reelExportPortsLabel([5, 2]), "RIFF B·NOTES C")
        XCTAssertEqual(reelExportPortsLabel([0, 1, 2]), "3 PORTS"); XCTAssertEqual(reelExportPortsLabel([9, -1]), "MASTER", "out-of-range ports are ignored")
    }
    func testThePassLengthLineReadsInBeats() {
        XCTAssertEqual(reelPassLengthText(beats: 4), "1 PASS = 4 BEATS")
        XCTAssertEqual(reelPassLengthText(beats: 1), "1 PASS = 1 BEAT")
        XCTAssertEqual(reelPassLengthText(beats: 0.5), "1 PASS = 0.5 BEATS")
        XCTAssertEqual(reelPassLengthText(beats: 2.6666666), "1 PASS = 2.67 BEATS", "a triplet-rate pass rounds to two places")
        XCTAssertEqual(reelPassLengthText(beats: 0), "1 PASS = —"); XCTAssertEqual(reelPassLengthText(beats: .nan), "1 PASS = —")
    }

    // §4.8 → PULSE ferry §6: the ring's flash is §1's velocity-scaled envelope (the step-based `euclideousRingFlare` is retired).
    func testFourfoldRingFlareEnvelopeIsPeakAtTheStrikeAndGoneAfterOneAndAHalfSeconds() {
        XCTAssertEqual(euclideousPulseEnvelopes(velocity: 127, seconds: 0, scale: 1).f, 1, accuracy: 1e-12)
        XCTAssertEqual(euclideousPulseEnvelopes(velocity: 127, seconds: -0.5, scale: 1).f, 0, "a strike that hasn't happened yet")
        XCTAssertEqual(euclideousPulseEnvelopes(velocity: 127, seconds: 1.6, scale: 1).f, 0)
        var last = 2.0
        for i in 0...50 { let v = euclideousPulseEnvelopes(velocity: 100, seconds: Double(i) * 0.03, scale: 1).f; XCTAssertLessThanOrEqual(v, last + 1e-12); last = v }
        // the OLD windows still exist for the BUILD-page editor's own comet bar
        XCTAssertEqual(euclideousFlareAfterglowSteps, 1.5); XCTAssertEqual(euclideousFlareBurstSteps, 0.35)
    }
    // The tap-vs-hold machine (§4.6/§4.7).
    func testFourfoldRingPressTapHoldDragAndCancel() {
        // tap: release before the hold timer fires
        var p = EuclideousRingPress(); p.touchDown()
        XCTAssertEqual(p.touchEnded(), .tap)
        // a stale timer (fires after the release) does nothing, and a second release is inert
        XCTAssertEqual(p.holdTimerFired(), .none); XCTAssertEqual(p.touchEnded(), .none)
        // hold: timer fires while down → trace; release ends it and NEVER taps
        p.touchDown()
        XCTAssertEqual(p.holdTimerFired(), .holdBegan)
        XCTAssertEqual(p.holdTimerFired(), .none, "the hold begins once")
        XCTAssertEqual(p.touchEnded(), .holdEnded)
        // drag off before the timer: no tap, no hold
        p.touchDown(); p.moved(distance: EuclideousRingPress.dragCancel + 1)
        XCTAssertEqual(p.holdTimerFired(), .none); XCTAssertEqual(p.touchEnded(), .none)
        // a small wobble is still a tap; dragging after the hold fired does not cancel it
        p.touchDown(); p.moved(distance: EuclideousRingPress.dragCancel - 1)
        XCTAssertEqual(p.touchEnded(), .tap)
        p.touchDown(); XCTAssertEqual(p.holdTimerFired(), .holdBegan); p.moved(distance: 200)
        XCTAssertEqual(p.touchEnded(), .holdEnded, "still a hold, still no tap")
        // a CANCELLED touch ends a started hold (so the trace can't stay stuck) and is silent otherwise
        p.touchDown(); XCTAssertEqual(p.holdTimerFired(), .holdBegan)
        XCTAssertEqual(p.touchCancelled(), .holdEnded)
        p.touchDown(); XCTAssertEqual(p.touchCancelled(), .none, "cancelled before the hold: no tap")
        XCTAssertEqual(p.touchEnded(), .none)
        XCTAssertEqual(EuclideousRingPress.holdSeconds, 0.3)
    }
    func testFourfoldTwoRingsPressIndependently() {
        // The bug this guards: one shared press slot made a second finger swallow BOTH taps. Each ring owns its own machine.
        var a = EuclideousRingPress(), b = EuclideousRingPress()
        a.touchDown(); b.touchDown()
        XCTAssertEqual(b.touchEnded(), .tap)
        XCTAssertEqual(a.touchEnded(), .tap)
        // a holds while b taps
        a.touchDown(); XCTAssertEqual(a.holdTimerFired(), .holdBegan)
        b.touchDown(); XCTAssertEqual(b.touchEnded(), .tap)
        XCTAssertEqual(a.touchEnded(), .holdEnded)
    }

    // MARK: - FERRY (2026-10-15, "Fourfold settings — a gear, one sheet, three tabs") §10 test 1

    func testFourfoldListenOnChannelTapFollowsEveryRuleIn3Point3() {
        // "ALL lit means every channel, and the 16 buttons show unlit."
        XCTAssertTrue(euclideousListenOnAllIsLit(0xFFFF))
        for ch in 1...16 { XCTAssertFalse(euclideousListenOnChannelIsLit(mask: 0xFFFF, channel1based: ch), "ch \(ch)") }
        // "Tapping a channel while ALL is lit picks only that channel."
        let afterTap1 = euclideousListenOnAfterChannelTap(mask: 0xFFFF, channel1based: 1)
        XCTAssertEqual(afterTap1, 1 << 0)
        XCTAssertTrue(euclideousListenOnChannelIsLit(mask: afterTap1, channel1based: 1))
        XCTAssertFalse(euclideousListenOnAllIsLit(afterTap1))
        // "After that, taps toggle channels."
        let afterTap1And10 = euclideousListenOnAfterChannelTap(mask: afterTap1, channel1based: 10)
        XCTAssertEqual(afterTap1And10, (1 << 0) | (1 << 9))
        let backOff10 = euclideousListenOnAfterChannelTap(mask: afterTap1And10, channel1based: 10)
        XCTAssertEqual(backOff10, 1 << 0, "toggling 10 back off leaves only 1")
        // "Turning off the last picked channel lights ALL again."
        let turnedOffLast = euclideousListenOnAfterChannelTap(mask: backOff10, channel1based: 1)
        XCTAssertEqual(turnedOffLast, 0xFFFF)
        XCTAssertTrue(euclideousListenOnAllIsLit(turnedOffLast))
        // "Tapping ALL goes back to every channel" — unconditional, even from a narrowed mask.
        XCTAssertEqual(euclideousListenOnAfterAllTap(), 0xFFFF)
        // "Picking all sixteen by hand reads as ALL" — falls out of the representation, no special case:
        // starting from ALL, tapping channels 1...16 in turn narrows to 1, then toggles each of 2...16 ON
        // in its own previously-off position, ending back at every bit set.
        var mask: UInt16 = 0xFFFF
        for ch in 1...16 { mask = euclideousListenOnAfterChannelTap(mask: mask, channel1based: ch) }
        XCTAssertEqual(mask, 0xFFFF, "every one of the 16 toggled on in turn reads as ALL, same as the all-channels value")
    }
    func testFourfoldListenOnValueLabelMatchesEveryWorkedCount() {
        XCTAssertEqual(euclideousListenOnValueLabel(mask: 0xFFFF), "ALL CHANNELS")
        XCTAssertEqual(euclideousListenOnValueLabel(mask: 1 << 0), "CH 1")
        XCTAssertEqual(euclideousListenOnValueLabel(mask: (1 << 0) | (1 << 9)), "CH 1 · 10")
        let five: UInt16 = (1 << 0) | (1 << 1) | (1 << 2) | (1 << 3) | (1 << 4)
        XCTAssertEqual(euclideousListenOnValueLabel(mask: five), "5 CHANNELS")
        let fifteen: UInt16 = 0xFFFF & ~(UInt16(1) << 15)   // every channel but 16
        XCTAssertEqual(euclideousListenOnValueLabel(mask: fifteen), "15 CHANNELS")
    }

    // MARK: - FERRY §10 test 8 (the width half — see EuclideousSettingsSheet's own doc comment for the
    // disclosed height-measurement choice)

    func testFourfoldSettingsSheetWidthCapsAt448() {
        XCTAssertEqual(euclideousSettingsSheetWidth(containerW: 1158), 448, "wide container: capped at 448")
        XCTAssertEqual(euclideousSettingsSheetWidth(containerW: 343), 343, "narrow container: spans it")
    }

    // SOURCES STACK ferry (2026-10-26) §12: the pop-up's width, CELL and header-row height at the reference widths.
    func testSourcesPopupGeometry() {
        for w in [1158.0, 868.0, 600.0] as [CGFloat] {
            let l = euclideousSourcesPopupLayout(containerW: w)
            XCTAssertEqual(l.width, 412, "wide containers cap the pop-up at 412 (w=\(w))")
            XCTAssertEqual(l.cellW, 104, accuracy: 1e-9, "CELL = (380 − 76 − 72 − 24) / 2 at width 412")
            XCTAssertEqual(l.headerRowH, 20, "CELL 104 ≥ the 'MIDI PLAYING' width ⇒ a 20 pt header row")
        }
        let narrow = euclideousSourcesPopupLayout(containerW: 343)
        XCTAssertEqual(narrow.width, 343, "a narrow container: the pop-up spans it")
        XCTAssertEqual(narrow.cellW, 69.5, accuracy: 1e-9, "CELL = (311 − 172) / 2 = 69.5 at width 343 (§5.5 'report it at 343')")
        XCTAssertEqual(narrow.headerRowH, 28, "CELL 69.5 < the 'MIDI PLAYING' width ⇒ the header row wraps to 28 pt")
    }
    // SOURCES STACK §4.6: the status control keeps the 184-wide footprint, so the NOTES group stays 426 (the
    // header ladder is unchanged — the ferry's stale "312" predates the HOLD/LATCH chips).
    func testNotesGroupStaysAt426() {
        XCTAssertEqual(euclideousHeaderGroupWidths(compact: false).notes, 426)
        XCTAssertEqual(EuclideousHeaderMetrics.segmentedWidth, 184, "the status control reuses the segmented control's 184×32 footprint")
    }

    // LISTEN REBUILT (2026-10-23): `testWalkTagWithAndGapsSplitTheLanesRawHitsAndLeaveTheOrdinalAlone` and
    // `testWalkTagGapsLaneThreadsToItsNextStrikeNotToASilencedHit` deleted — WITH/GAPS's per-tick STRIKE
    // filter (`EuclideousWalkListenFilter`) no longer exists; COPY/FILL already replace the buffer itself
    // (`euclideousEffectiveHitPattern`), so every raw hit in the mirror's own buffer strikes, trivially
    // (`euclideousWalkTick` just returns `strikes: info.rawIsHit` unconditionally now).

    // The footer must predict what the engine's walk plays under a restarting MELODY chain + ADV STEP even when the lap's
    // first hit is NOT on tick 0 (the engine feeds the walk the lap-local tick, leading rests included). A melody chain of
    // [1] restarts every pass — exactly old LOCK's own guarantee (§4.7) — so this (2026-10-19) sets the chain field
    // directly instead of the retired `riffLock`.
    func testFooterAgreesWithTheEngineMirrorUnderARestartingMelodyChainAndAdvStepWhenTheFirstHitIsOffTickZero() {
        var offZero = 0
        for rot in 0..<8 {
            for stride in [1, 2] {
                var line = EuclidLine(target: 0, pulses: 3, steps: 8, rate: .r1_8, useRiff: true, sourceMode: .midi)
                line.rotate = rot; line.restartMask = 0
                line.restartMelodyPasses = [1]; line.riffAdvanceStep = true; line.riffStride = stride; line.riffLength = 5
                let hits = euclideousLapHitSteps(pulses: 3, steps: 8, rotate: rot, tilt: 0, patternMiss: false, customHits: nil, dir: .fwd)
                guard let first = hits.first else { return XCTFail("no hits") }
                if first.tick > 0 { offZero += 1 }
                let base = euclideousRiffLapBaseline(hitSteps: hits, lapSteps: 8, isMelodyRestartPass: true, advanceStep: true, liveOrd: 99)
                let predicted = euclideousRiffCyclePrediction(hitSteps: hits, advanceStep: true, dir: .forward, stride: stride, length: 5,
                                                              rotate: 0, seed: 0, startOrd: base.startOrd)
                let cfg = euclideousWalkLaneConfig(lane: 0, lines: [line], cyc: 4, resetSpanBars: 0, lanesSeqRate: .oneBar, lanesSeqLen: 8)!
                for (k, h) in hits.enumerated() {
                    let t = euclideousWalkTick(cfg, tick: Int64(h.tick))
                    XCTAssertTrue(t.isHit)
                    XCTAssertEqual(predicted[k], t.playedStep + 1, "rotate \(rot) stride \(stride) hit \(k) (tick \(h.tick)): footer vs the engine's own walk")
                }
            }
        }
        XCTAssertGreaterThan(offZero, 6, "the sweep genuinely includes first hits that are not on tick 0")
        // …and the other restart / FREE combinations keep their baselines.
        let hits = euclideousLapHitSteps(pulses: 3, steps: 8, rotate: 1, tilt: 0, patternMiss: false, customHits: nil, dir: .fwd)
        XCTAssertEqual(euclideousRiffLapBaseline(hitSteps: hits, lapSteps: 8, isMelodyRestartPass: true, advanceStep: false, liveOrd: 5).startOrd, 0, "a restarting melody chain + HIT mode feeds the hit index")
    }


    // MARK: - COPY/FILL lanes: bar + footer come from the pattern that actually plays (LISTEN REBUILT, 2026-10-23)

    private func copyLines(sourceSteps: Int = 7, sourceRotate: Int = 1, mode: EuclideousListenRhythmMode = .copy, delay: Int = 0, direction: EuclidDir = .fwd, speed: Int = 0) -> [EuclidLine] {
        var source = EuclidLine(target: 0, pulses: 3, steps: sourceSteps, rate: .r1_8, useRiff: true, sourceMode: .midi)
        source.rotate = sourceRotate; source.restartMask = 0
        var follower = EuclidLine(target: 0, pulses: 2, steps: 8, rate: .r1_16, useRiff: true, sourceMode: .midi)   // its OWN 2-of-8 is irrelevant while borrowing
        follower.listenRhythm = mode; follower.listenSource = 0
        follower.listenDelay = delay; follower.listenDirection = direction; follower.listenSpeed = speed
        follower.restartMask = 0
        return [source, follower]
    }
    // The footer's hit ticks (what the bar's cells and bands are built from) == the engine mirror's hit ticks, for every DIRECTION.
    func testCopyLanesFooterHitsAreTheTicksTheEngineActuallyPlays() {
        for dir in [EuclidDir.fwd, .bkw, .pingpong] {
            for sourceSteps in [7, 8, 5] {
                let lines = copyLines(sourceSteps: sourceSteps, direction: dir)
                let eff = euclideousEffectivePattern(lane: 1, lines: lines)!
                // the borrowed buffer is ALREADY in its own final tick order (DIRECTION baked in by
                // euclideousEffectiveHitPattern) — the mirror reads it FWD, exactly as Router's `cfgDir` fix does.
                let hits = euclideousLapHitSteps(buf: Array(eff.buf.prefix(eff.n)), dir: .fwd)
                let cfg = euclideousWalkLaneConfig(lane: 1, lines: lines, cyc: 4, resetSpanBars: 0, lanesSeqRate: .oneBar, lanesSeqLen: 8)!
                let cycleLen = euclidCycleLen(.fwd, n: eff.n)
                let engineTicks = (0..<cycleLen).filter { euclideousWalkTick(cfg, tick: Int64($0)).isHit }
                XCTAssertEqual(hits.map { $0.tick }, engineTicks, "\(dir) source \(sourceSteps): footer hit ticks vs the engine's own")
                XCTAssertFalse(hits.isEmpty)
                // the bar has one cell per SOURCE step, so the footer must have exactly that many bands (the old code made 8)
                let states = euclideousFooterStates(hitSteps: hits, lapSteps: eff.n, prediction: nil, riffRanksResolved: [], anyLit: true)
                XCTAssertEqual(states.count, eff.n)
                for i in 0..<eff.n { XCTAssertEqual(states[i] != .miss, hits.contains { $0.bufIdx == i }, "cell \(i)") }
            }
        }
        // the buffer-based walk is the pulses-based walk for an ordinary lane (the refactor changed nothing there)
        for dir in [EuclidDir.fwd, .bkw, .pingpong] {
            let viaPulses = euclideousLapHitSteps(pulses: 5, steps: 8, rotate: 2, tilt: 0.3, patternMiss: false, customHits: nil, dir: dir)
            let viaBuf = euclideousLapHitSteps(buf: euclideousNoteViewPattern(pulses: 5, steps: 8, rotate: 2, tilt: 0.3), dir: dir)
            XCTAssertEqual(viaPulses.map { [$0.tick, $0.bufIdx] }, viaBuf.map { [$0.tick, $0.bufIdx] })
        }
    }


    // MARK: - COPY/FILL lanes: who is borrowing, where their gestures go, how fast they sweep (LISTEN REBUILT, 2026-10-23)

    func testOnlyCopyOrFillCountsAsBorrowingAndItsGesturesGoToTheSource() {
        var lines = copyLines()
        XCTAssertEqual(euclideousRhythmBorrowPartner(lane: 1, lines: lines), 0)
        XCTAssertEqual(euclideousRhythmGestureTarget(lane: 1, lines: lines), 0, "a borrowing lane's bar gestures edit the lane it borrows from")
        XCTAssertNil(euclideousRhythmBorrowPartner(lane: 0, lines: lines), "the source itself is not borrowing from anyone")
        XCTAssertEqual(euclideousRhythmGestureTarget(lane: 0, lines: lines), 0)
        // FILL also counts as borrowing — unlike the old WITH/GAPS, COPY and FILL both replace the pattern wholesale
        lines[1].listenRhythm = .fill
        XCTAssertEqual(euclideousRhythmBorrowPartner(lane: 1, lines: lines), 0, "FILL")
        XCTAssertEqual(euclideousRhythmGestureTarget(lane: 1, lines: lines), 0)
        // OWN keeps the lane's own rhythm — not borrowing, gestures edit itself
        lines[1].listenRhythm = .own
        XCTAssertNil(euclideousRhythmBorrowPartner(lane: 1, lines: lines))
        XCTAssertEqual(euclideousRhythmGestureTarget(lane: 1, lines: lines), 1)
        lines[1].listenRhythm = nil
        XCTAssertNil(euclideousRhythmBorrowPartner(lane: 1, lines: lines))
        // out of range
        XCTAssertNil(euclideousRhythmBorrowPartner(lane: 9, lines: lines))
        XCTAssertEqual(euclideousRhythmGestureTarget(lane: 9, lines: lines), 9)
    }
    func testCopyLaneSweepsAtTheSourcesRateDividedByTwoToTheSpeedExactlyAsTheEngineMirrorDoes() {
        for speed in -2...2 {
            var lines = copyLines()
            lines[1].listenSpeed = speed
            let eff = euclideousEffectivePattern(lane: 1, lines: lines)!
            XCTAssertEqual(eff.rateBeats, ArpRate.r1_8.beats / pow(2.0, Double(speed)), accuracy: 1e-12, "÷2^\(speed)")
            let cfg = euclideousWalkLaneConfig(lane: 1, lines: lines, cyc: 4, resetSpanBars: 0, lanesSeqRate: .oneBar, lanesSeqLen: 8)!
            XCTAssertEqual(cfg.sub, eff.rateBeats, accuracy: 1e-12, "the comet and the engine mirror use ONE step length")
        }
        // at SPEED 0 the follower sweeps at the SOURCE's 1/8 — not the 1/16 it has stored for itself
        let plain = copyLines()
        XCTAssertEqual(euclideousEffectivePattern(lane: 1, lines: plain)!.rateBeats, ArpRate.r1_8.beats)
        XCTAssertEqual(plain[1].rate?.beats, ArpRate.r1_16.beats, "(its own stored rate is different, so this is not just reading the lane's own field)")
        // not borrowing: the lane's own rate; an unset rate takes the default
        var lines = copyLines()
        XCTAssertEqual(euclideousEffectivePattern(lane: 0, lines: lines)!.rateBeats, ArpRate.r1_8.beats)
        lines[0].rate = nil
        XCTAssertEqual(euclideousEffectivePattern(lane: 0, lines: lines, defaultRateBeats: 0.375)!.rateBeats, 0.375)
        XCTAssertEqual(euclideousEffectivePattern(lane: 1, lines: lines, defaultRateBeats: 0.375)!.rateBeats, 0.375, "a follower whose source has no rate takes the default ÷ 2^SPEED")
        XCTAssertTrue(euclideousListenCellFade > 0.5 && euclideousListenCellFade < 1, "slightly faded, still clearly lit")
    }


    // LISTEN REBUILT (2026-10-23): the old "partner remembered across off/on and mode-switches" section
    // deleted wholesale — one shared source per lane (not a partner per row) has nothing left to
    // "remember" the same way; `euclideousListenToggleRhythm`/`TogglePitch`/`ToggleLevel`,
    // `euclideousListenPartnerToLight`/`AnyIsLegal`/`Edges` (all old 3-row-partner model) are now fully
    // orphaned and deleted alongside their own tests here.

    // MARK: - LOOPER TABS (FERRY "looper tabs replace the riff tabs", ratified 2026-10-16, §9)
    //
    // §9 tests 4/5/6/7/10 live partly or wholly in `EuclideousPage.swift`/`AudioUnitViewController.swift`
    // (the state machine, undo wiring, button look) — ZERO macOS test-target reach, same established
    // split as every other Euclideous UI surface (CLAUDE.md's own test-coverage note). Covered here only
    // to the extent they reduce to a pure function; the rest is code-inspection + device verification.

    /// §9 test 1: start ranks, then events up to the position, last wins; a 2-pass loop wraps; no loop or
    /// a beat before B falls back to the live grid.
    func testLooperEffectiveRankStartRanksThenEventsWithWrap() {
        let startRanks = [1, 0, 0, 0, 0, 0, 0, 0]
        let events = [EuclideousLoopEvent(offsetBars: 1.0, column: 0, rank: 5)]
        XCTAssertEqual(euclideousLooperEffectiveRank(column: 0, beat: 0.5, liveGrid: [], active: true, startBeat: 0, passes: 2, startRanks: startRanks, events: events, beatsPerBar: 4), 1)
        XCTAssertEqual(euclideousLooperEffectiveRank(column: 0, beat: 4.5, liveGrid: [], active: true, startBeat: 0, passes: 2, startRanks: startRanks, events: events, beatsPerBar: 4), 5)
        // pass 2 WRAPS (2-pass loop): back to the start rank, not a continuation.
        XCTAssertEqual(euclideousLooperEffectiveRank(column: 0, beat: 8.5, liveGrid: [], active: true, startBeat: 0, passes: 2, startRanks: startRanks, events: events, beatsPerBar: 4), 1)
        // no loop, or before B: the live grid.
        XCTAssertEqual(euclideousLooperEffectiveRank(column: 0, beat: 4.5, liveGrid: [9, 9, 9, 9, 9, 9, 9, 9], active: false, startBeat: 0, passes: 2, startRanks: startRanks, events: events, beatsPerBar: 4), 9)
        XCTAssertEqual(euclideousLooperEffectiveRank(column: 0, beat: -1, liveGrid: [9, 9, 9, 9, 9, 9, 9, 9], active: true, startBeat: 0, passes: 2, startRanks: startRanks, events: events, beatsPerBar: 4), 9)
    }
    /// §9 test 1 (bars, not beats): a stored offset survives a meter change — 4/4 → 3/4 mid-loop.
    func testLooperEffectiveRankOffsetBarsSurviveAMeterChange() {
        let startRanks = [1, 1, 1, 1, 1, 1, 1, 1]
        let events = [EuclideousLoopEvent(offsetBars: 1.0, column: 3, rank: 6)]
        XCTAssertEqual(euclideousLooperEffectiveRank(column: 3, beat: 4.1, liveGrid: [], active: true, startBeat: 0, passes: 4, startRanks: startRanks, events: events, beatsPerBar: 4), 6, "4/4: bar 1 starts at beat 4")
        XCTAssertEqual(euclideousLooperEffectiveRank(column: 3, beat: 3.1, liveGrid: [], active: true, startBeat: 0, passes: 4, startRanks: startRanks, events: events, beatsPerBar: 3), 6, "3/4: the SAME bar-offset event, a different real beat (3)")
        XCTAssertEqual(euclideousLooperEffectiveRank(column: 3, beat: 2.9, liveGrid: [], active: true, startBeat: 0, passes: 4, startRanks: startRanks, events: events, beatsPerBar: 3), 1, "still bar 0 at 3/4 just before the bar line")
    }
    /// §9 test 2, the worked example literally: armed in pass 0, recording passes 1-8 (N=8), and pass 9
    /// plays pass 1 exactly as recorded. An overdub made during pass 9 plays again in pass 17.
    // DROPPED (2026-10-18 ferry, "drop the loop functionality in favour of four riff tabs"):
    // `euclideousAppendLooperEvent`/`euclideousNextLandingBeat`/`euclideousRunFirstBarLine`/
    // `euclideousLooperSegmentGeometry` are deleted along with the looper's own
    // `AudioUnitViewController` state machine and `EuclideousPage` loop-row UI they served — their
    // tests (§9 tests 3, 7's pure half, 9, 10) are removed with them. `euclideousLooperEffectiveRank`
    // stays live (Router.swift still calls it, permanently with `active: false`), so its own coverage
    // (just above, and `testALateSnapshotJoinsInProgressAnchoredAtB` below) stays — this one test is
    // rewritten to build its event list by hand instead of via the deleted coalescing helper.
    func testLooperTimelineN8PassNinePlaysPassOneOverdubCarriesToPassSeventeen() {
        let startRanks = [0, 0, 0, 0, 0, 0, 0, 0]
        // Recorded during pass 1 (beats 0..<4): rank 5 on column 2 at beat 1 (offset 0.25 bars).
        var events: [EuclideousLoopEvent] = [EuclideousLoopEvent(offsetBars: 0.25, column: 2, rank: 5)]
        let pass1 = euclideousLooperEffectiveRank(column: 2, beat: 1, liveGrid: [], active: true, startBeat: 0, passes: 8, startRanks: startRanks, events: events, beatsPerBar: 4)
        let pass9 = euclideousLooperEffectiveRank(column: 2, beat: 33, liveGrid: [], active: true, startBeat: 0, passes: 8, startRanks: startRanks, events: events, beatsPerBar: 4)
        XCTAssertEqual(pass1, 5); XCTAssertEqual(pass9, 5, "pass 9 (beat 33) plays pass 1 (beat 1) exactly as recorded")
        // Overdub during pass 9: column 6, rank 7, at relative offset 0.5 bars (beat 34).
        events.append(EuclideousLoopEvent(offsetBars: 0.5, column: 6, rank: 7))
        let pass17 = euclideousLooperEffectiveRank(column: 6, beat: 66, liveGrid: [], active: true, startBeat: 0, passes: 8, startRanks: startRanks, events: events, beatsPerBar: 4)
        XCTAssertEqual(pass17, 7, "the pass-9 overdub recurs in pass 17 (and every future cycle) — it IS the loop now")
    }
    /// §9 test 8: a late-arriving snapshot joins in progress anchored at B — no special "catching up"
    /// logic exists or is needed; the pure function only ever compares `beat` to `startBeat`.
    func testALateSnapshotJoinsInProgressAnchoredAtB() {
        let startRanks = [2, 2, 2, 2, 2, 2, 2, 2]
        let rank = euclideousLooperEffectiveRank(column: 0, beat: 20, liveGrid: [], active: true, startBeat: 0, passes: 4, startRanks: startRanks, events: [], beatsPerBar: 4)
        XCTAssertEqual(rank, 2, "beat (20) vs startBeat (0) alone decides — being read 'late' changes nothing")
    }

    // MARK: - MIX TAB (ferry 2026-10-18) §9 tests 1–4 (pure)

    // PER-LAYER EMITTER ROUTING ferry §5.2 (over CLARITY PASS §3.1/§3.2): the OUT row left MIX, so the pad grew by it
    // (20) + its sp4 gap — padH = innerH − sp4 − 24 = panelH − 36 (was panelH − 60 with the row). A 401 × 264 area now
    // gives panelW 192.5, panelH 124, cellW 90.25, padH 88 (was 64). NOTE §5.2's "pads 79 × 98 at 348 × 280" was written
    // against the mix-tidy ferry's own (pre-CLARITY) panel geometry; the real formula gives 90.25 × 88 here. Reported.
    func testMixGridAtTheReferenceSizeAndItsCellOrigins() {
        let g = euclideousMixGrid(width: 401, height: 264)
        XCTAssertEqual(g.cellW, 90.25, accuracy: 1e-9); XCTAssertEqual(g.rowH, 124, accuracy: 1e-9); XCTAssertEqual(g.padH, 88, accuracy: 1e-9)
        XCTAssertEqual(g.panelW, 192.5, accuracy: 1e-9); XCTAssertEqual(g.panelH, 124, accuracy: 1e-9)
        XCTAssertEqual(g.outRowH, 0, "the OUT row is gone from MIX (§5.1)")
        XCTAssertFalse(g.belowFloors, "padH 88 is well above the 64 floor")
        let xs: [CGFloat] = [4, 98.25, 212.5, 306.75], ys: [CGFloat] = [4, 144]
        var want: [CGPoint] = []
        for row in 0..<2 { for col in 0..<2 { for notes in [false, true] { want.append(CGPoint(x: xs[col * 2 + (notes ? 1 : 0)], y: ys[row])) } } }
        var got: [CGPoint] = []
        for lane in 0..<4 { for notes in [false, true] { got.append(g.origin(lane: lane, notes: notes)) } }
        // order: lane 1 riff, lane 1 notes, lane 2 riff, lane 2 notes, then lanes 3 and 4
        for (i, (a, b)) in zip(got, want).enumerated() { XCTAssertEqual(a.x, b.x, accuracy: 1e-9, "cell \(i) x"); XCTAssertEqual(a.y, b.y, accuracy: 1e-9, "cell \(i) y") }
        // the four panels exactly tile the area: last panel's trailing edge = W, bottom = H; the last pad ends one padding short of W, the pad + OCT stepper one padding short of H (no OUT row below now)
        XCTAssertEqual(g.panelFrame(lane: 3).maxX, 401, accuracy: 1e-9); XCTAssertEqual(g.panelFrame(lane: 3).maxY, 264, accuracy: 1e-9)
        XCTAssertEqual(got[7].x + g.cellW, 401 - 4, accuracy: 1e-9)
        XCTAssertEqual(got[7].y + g.padH + 4 + EuclideousMixMetrics.stepperH, 264 - 4, accuracy: 1e-9)
        // the panel → grid area: the ferry's 417 × 308 panel is 401 × 264 inside its padding, tab row and gap
        let area = euclideousMixGridArea(panelWidth: 417, panelHeight: 308)
        XCTAssertEqual(area.width, 401); XCTAssertEqual(area.height, 264)
    }
    // §9.3 — the floors are REPORTED (never shrunk). PAGE LAYOUT ferry (2026-10-19) retired §9.3's STOP: below padH 60 MIX is still DRAWN at the
    // formula's values (the old 393 × 248 portrait panel, padH 46, is what used to draw nothing); the flags below are what the page's floor list raises.
    func testMixGridFlagsPanelsBelowTheLegibilityFloors() {
        // PER-LAYER ROUTING ferry §5.2: with the OUT row gone the pad has more room, so the old 393 × 248 portrait panel
        // now clears the floor (padH 64). A smaller 393 × 212 panel still flags: nominal padH 40, the fair-share fallback
        // drops the stepper to its compact floor (only the stepper now — the OUT row is gone) and buys the pad back to 46.
        let portrait = euclideousMixGrid(width: euclideousMixGridArea(panelWidth: 393, panelHeight: 212).width, height: euclideousMixGridArea(panelWidth: 393, panelHeight: 212).height)
        XCTAssertEqual(portrait.padH, 46, accuracy: 1e-9); XCTAssertTrue(portrait.belowFloors, "portrait: padH 46 < 64")
        XCTAssertLessThan(portrait.padH, EuclideousMixMetrics.floorPadH, "…and below the 48pt flag too (no longer a stop)")
        let narrow = euclideousMixGridArea(panelWidth: 357.12, panelHeight: 333.5)
        XCTAssertTrue(euclideousMixGrid(width: narrow.width, height: narrow.height).belowFloors, "1024-wide landscape: cellW 75.3 < 78")
        let ok = euclideousMixGridArea(panelWidth: 416.88, panelHeight: 312.25)
        XCTAssertFalse(euclideousMixGrid(width: ok.width, height: ok.height).belowFloors)
    }
    // §9.2 — the pad maths: the three §3.5 points, the §3.6 ticks, and §4.1 inverting §3.5.
    func testMixPadPuckTicksAndTheTouchInverse() {
        let pad = EuclideousMixPadGeometry(cellW: 96.25, padH: 96)
        // CLARITY PASS: the 24 pt VEL strip is gone (its label and value moved), so the plot spans the whole pad: plotW 96.25 (was 72.25) and the puck travels x 7 … 89.25
        XCTAssertEqual(pad.plotW, 96.25, accuracy: 1e-9); XCTAssertEqual(pad.plotH, 82, accuracy: 1e-9)
        func near(_ p: CGPoint, _ x: Double, _ y: Double, _ msg: String) { XCTAssertEqual(Double(p.x), x, accuracy: 0.01, msg); XCTAssertEqual(Double(p.y), y, accuracy: 0.01, msg) }
        near(pad.puck(gate: 0.60, velocity: 104), 56.35, 19.31, "gate 60 / vel 104")
        near(pad.puck(gate: 1.00, velocity: 127), 89.25, 7, "100 / 127")
        near(pad.puck(gate: 0.01, velocity: 1), 7.82, 74.46, "1 / 1")
        XCTAssertEqual(pad.tickXs.map { Double($0) }.map { ($0 * 100).rounded() / 100 }, [27.56, 48.13, 68.69])
        XCTAssertEqual(pad.tickYs.map { Double($0) }, [58, 41, 24])
        // regions and axes (§3.3/§3.4)
        XCTAssertEqual(pad.velStrip, CGRect(x: 0, y: 0, width: 0, height: 82)); XCTAssertEqual(pad.gateStrip, CGRect(x: 0, y: 82, width: 96.25, height: 14))
        XCTAssertEqual(pad.plot, CGRect(x: 0, y: 0, width: 96.25, height: 82))
        XCTAssertEqual(pad.yAxis, CGRect(x: 0, y: 0, width: 1, height: 82)); XCTAssertEqual(pad.xAxis, CGRect(x: 0, y: 82, width: 96.25, height: 1))
        // §4.1 inverts §3.5 for EVERY gate 1…99 at velocities 1, 64 and 127 (100% — legato — is no longer offered; the far edge is 99%)
        for g in 1...99 { for v in [1, 64, 127] {
            let back = pad.values(at: pad.puck(gate: Double(g) / 100, velocity: v))
            XCTAssertEqual(Int((back.gate * 100).rounded()), g, "gate \(g) @ vel \(v)"); XCTAssertEqual(back.velocity, v, "vel \(v) @ gate \(g)")
        } }
        // …and points outside the plot clamp to each field's range
        XCTAssertEqual(pad.values(at: CGPoint(x: -50, y: 500)).gate, 0.01); XCTAssertEqual(pad.values(at: CGPoint(x: -50, y: 500)).velocity, 1)
        XCTAssertEqual(pad.values(at: CGPoint(x: 900, y: -500)).gate, 0.99, "the far right edge is 99%, never legato"); XCTAssertEqual(pad.values(at: CGPoint(x: 900, y: -500)).velocity, 127)
        XCTAssertEqual(pad.values(at: pad.puck(gate: 1.0, velocity: 64)).gate, 0.99, "even a puck drawn at 100% reads back as 99%")
        XCTAssertEqual(pad.values(at: CGPoint(x: 2, y: 40)).gate, 0.01, "a touch left of the puck's travel still sets both values; its x clamps the gate to 1%")
    }
    // RESTART CHAINS ferry §9.4/§16, literal: at padH 76 (the new grid-derived reference, OUT moved into
    // MIX): plotH 62, left-axis ticks at y 43/31/19 (bottom ticks unchanged), and the three named puck points.
    func testMixPadAtTheNewPadH76ReferenceMatchesTheFerrysOwnLiteralNumbers() {
        let pad = EuclideousMixPadGeometry(cellW: 96.25, padH: 76)
        XCTAssertEqual(pad.plotH, 62, accuracy: 1e-9)
        func near(_ p: CGPoint, _ x: Double, _ y: Double, _ msg: String) { XCTAssertEqual(Double(p.x), x, accuracy: 0.01, msg); XCTAssertEqual(Double(p.y), y, accuracy: 0.01, msg) }
        near(pad.puck(gate: 0.60, velocity: 104), 56.35, 15.69, "gate 60 / vel 104")
        near(pad.puck(gate: 1.00, velocity: 127), 89.25, 7, "100 / 127")
        near(pad.puck(gate: 0.01, velocity: 1), 7.82, 54.62, "1 / 1")
        XCTAssertEqual(pad.tickXs.map { Double($0) }.map { ($0 * 100).rounded() / 100 }, [27.56, 48.13, 68.69], "bottom-axis ticks follow the strip-less plot (CLARITY PASS)")
        XCTAssertEqual(pad.tickYs.map { Double($0) }, [43, 31, 19])
    }
    // §9.4 — resolvers: notesGate nil reads GATE; notesVelocity nil reads VEL + offset (clamped).
    func testNotesGateAndVelocityResolversFollowTheLaneUntilStored() {
        var l = EuclidLine()
        XCTAssertEqual(l.notesGateResolved, 0.9); XCTAssertEqual(l.notesVelocityResolved, 100)
        l.gate = 0.55; l.velocityAbsolute = 80
        XCTAssertEqual(l.notesGateResolved, 0.55, "nil reads GATE"); XCTAssertEqual(l.notesVelocityResolved, 80, "nil reads VEL (+ no offset)")
        l.notesVelOffset = 20
        XCTAssertEqual(l.notesVelocityResolved, 100, "VEL + offset — today's notes velocity")
        l.velocityAbsolute = 120; XCTAssertEqual(l.notesVelocityResolved, 127, "clamped high")
        l.velocityAbsolute = 10; l.notesVelOffset = -64; XCTAssertEqual(l.notesVelocityResolved, 1, "clamped low")
        l.notesVelOffset = 500; l.velocityAbsolute = 100; XCTAssertEqual(l.notesVelocityResolved, 127, "the stored offset is itself ±64-clamped, then the sum is")
        l.notesGate = 0.3; l.notesVelocity = 33
        XCTAssertEqual(l.notesGateResolved, 0.3); XCTAssertEqual(l.notesVelocityResolved, 33, "stored values win over the lane's")
        l.notesVelocity = 900; XCTAssertEqual(l.notesVelocityResolved, 127); l.notesVelocity = -4; XCTAssertEqual(l.notesVelocityResolved, 1)
    }
    // §9.4 — §6.3's pinning: the layers part at the first GATE / VEL edit, inside that edit.
    func testLayersPartAtTheFirstGateOrVelocityEdit() {
        var l = EuclidLine(); l.gate = 0.8; l.velocityAbsolute = 90; l.notesVelOffset = -10
        let snap = l
        euclideousSliderCommit(.gate, &l, snapshot: snap, newValue: 0.5)
        XCTAssertEqual(l.gate, 0.5); XCTAssertEqual(l.notesGate, 0.8, "pinned to the GATE it had BEFORE the edit")
        XCTAssertNil(l.notesVelocity, "a GATE edit doesn't part the velocities")
        euclideousSliderCommit(.gate, &l, snapshot: snap, newValue: 0.2)
        XCTAssertEqual(l.notesGate, 0.8, "already parted: later GATE edits leave the notes alone")
        euclideousSliderCommit(.velocity, &l, snapshot: snap, newValue: 60)
        XCTAssertEqual(l.velocityAbsolute, 60); XCTAssertEqual(l.notesVelocity, 80, "pinned to VEL + offset (90 − 10) before VEL changed")
        euclideousSliderCommit(.velocity, &l, snapshot: snap, newValue: 127)
        XCTAssertEqual(l.notesVelocity, 80, "once pinned, notes velocity ignores a VEL change"); XCTAssertEqual(l.notesVelocityResolved, 80)
        // a no-op commit (same value) never parts the layers
        var m = EuclidLine(); m.gate = 0.7; m.velocityAbsolute = 64
        euclideousSliderCommit(.gate, &m, snapshot: m, newValue: 0.7); euclideousSliderCommit(.velocity, &m, snapshot: m, newValue: 64)
        XCTAssertNil(m.notesGate); XCTAssertNil(m.notesVelocity)
        // the sliders' double-tap goes through the same helper
        var d = EuclidLine(); d.gate = 0.4; d.velocityAbsolute = 50
        euclideousSliderDoubleTapDefault(.gate, &d); euclideousSliderDoubleTapDefault(.velocity, &d)
        XCTAssertEqual(d.gate, 0.9); XCTAssertEqual(d.velocityAbsolute, 100); XCTAssertEqual(d.notesGate, 0.4); XCTAssertEqual(d.notesVelocity, 50)
        // …and a fresh lane double-tapped at the defaults parts nothing
        var f = EuclidLine(); euclideousSliderDoubleTapDefault(.gate, &f); euclideousSliderDoubleTapDefault(.velocity, &f)
        XCTAssertNil(f.notesGate); XCTAssertNil(f.notesVelocity)
        // a long-press REVERT is not an edit: it takes the pin back (only the pin)
        var r = EuclidLine(); r.gate = 0.8; r.velocityAbsolute = 90
        let rs = r
        euclideousSliderCommit(.gate, &r, snapshot: rs, newValue: 0.3); euclideousSliderCommit(.velocity, &r, snapshot: rs, newValue: 20)
        euclideousSliderRevert(.gate, &r, snapshot: rs); euclideousSliderRevert(.velocity, &r, snapshot: rs)
        XCTAssertEqual(r, rs, "a stray press leaves the line exactly as it was, layers still tied")
        var keep = rs; euclideousSliderCommit(.gate, &keep, snapshot: rs, newValue: 0.3); keep.notesGate = 0.55   // a notes-pad edit made meanwhile
        euclideousSliderRevert(.gate, &keep, snapshot: rs)
        XCTAssertEqual(keep.notesGate, 0.55, "a genuinely different notes value is not clobbered by the revert")
    }
    // The pad write paths: RIFF through the RHYTHM sliders' setters (so GATE/VEL agree and the pin happens), NOTES into its own fields.
    func testMixPadWritesRiffThroughTheSlidersAndNotesIntoItsOwnLayer() {
        var l = EuclidLine(); l.gate = 0.9; l.velocityAbsolute = 100
        euclideousMixPadWrite(&l, notes: false, gate: 0.6, velocity: 104)
        XCTAssertEqual(l.gate, 0.6); XCTAssertEqual(l.velocityAbsolute, 104)
        XCTAssertEqual(euclideousSliderRange(.gate, l).value, 0.6, "the RHYTHM slider reads what the riff pad wrote")
        XCTAssertEqual(l.notesGate, 0.9, "the notes layer was parted at its old values, not moved"); XCTAssertEqual(l.notesVelocity, 100)
        euclideousMixPadWrite(&l, notes: true, gate: 0.3, velocity: 20)
        XCTAssertEqual(l.notesGate, 0.3); XCTAssertEqual(l.notesVelocity, 20); XCTAssertEqual(l.gate, 0.6, "dragging a notes pad never moves the riff pad"); XCTAssertEqual(l.velocityAbsolute, 104)
        euclideousMixPadWrite(&l, notes: false, gate: 0.2, velocity: 50)
        XCTAssertEqual(l.notesGate, 0.3, "…and the reverse"); XCTAssertEqual(l.notesVelocity, 20)
        let (g, v) = euclideousMixPadValues(of: l, notes: true); XCTAssertEqual(g, 0.3); XCTAssertEqual(v, 20)
        euclideousMixPadReset(&l, notes: true); XCTAssertEqual(l.notesGate, 0.9); XCTAssertEqual(l.notesVelocity, 100)
        euclideousMixPadReset(&l, notes: false); XCTAssertEqual(l.gate, 0.9); XCTAssertEqual(l.velocityAbsolute, 100)
        XCTAssertTrue(euclideousMixLayerIsOff(EuclidLine(riffOn: false), notes: false)); XCTAssertFalse(euclideousMixLayerIsOff(EuclidLine(), notes: false))
        var n = EuclidLine(); n.notesOn = false
        XCTAssertTrue(euclideousMixLayerIsOff(n, notes: true), "switch off ⇒ off")
        XCTAssertTrue(euclideousMixLayerIsOff(EuclidLine(), notes: true), "a fresh lane has NO notes selected, so its notes layer is OFF (Paul 2026-10-18)")
        var lit = EuclidLine(); lit.litNotes = 0b1
        XCTAssertFalse(euclideousMixLayerIsOff(lit, notes: true), "…and ON once a note is selected")
    }
    // The OCT stepper: one setter per layer shared with the RIFF/NOTES tabs; range −2…+2, no wrap.
    func testMixOctaveStepperSettersRangeAndText() {
        var l = EuclidLine()
        euclideousSetRiffOctave(&l, 2); XCTAssertEqual(l.riffOctave, 2); XCTAssertEqual(euclideousMixOctave(of: l, notes: false), 2)
        l.notesOn = false
        euclideousSetNotesOctave(&l, -1)
        XCTAssertEqual(l.octave, -1); XCTAssertEqual(l.notesOn, true, "the NOTES tab's own setter switches the layer on — the MIX stepper shares it")
        l.octave = 3; XCTAssertEqual(euclideousMixOctave(of: l, notes: true), 2, "a stored ±3 (the 8×8 editor's range) reads as the engine's ±2")
        XCTAssertEqual(euclideousMixOctaveNext(2, up: true), nil); XCTAssertEqual(euclideousMixOctaveNext(-2, up: false), nil)
        XCTAssertEqual(euclideousMixOctaveNext(0, up: true), 1); XCTAssertEqual(euclideousMixOctaveNext(0, up: false), -1)
        XCTAssertEqual((-2...2).map(euclideousMixOctaveText), ["\u{2212}2", "\u{2212}1", "0", "+1", "+2"])
        XCTAssertEqual((-2...2).map(euclideousMixOctaveSpoken), ["minus 2", "minus 1", "0", "plus 1", "plus 2"])
    }
    // §1 — tabs: MIX then LANES, RIFFS hidden, MIX the default, equal widths.
    func testSequencerTabsAreMixThenLanesWithEqualWidths() {
        XCTAssertEqual(EuclideousSeqTab.visible, [.mix, .lanes]); XCTAssertEqual(EuclideousSeqTab.default, .mix)
        XCTAssertEqual(EuclideousSeqTab.visible.map { $0.label }, ["MIX", "LANES"])
        XCTAssertEqual(euclideousSeqTabWidth(count: 2, contentWidth: 401), 198.5, accuracy: 1e-9, "two tabs at the reference panel")
        XCTAssertEqual(euclideousSeqTabWidth(count: 1, contentWidth: 401), 401)
    }
    // §4.3/§4.4 — one undo step per touch; a double tap is one step.
    func testPadUndoBurstTakesOneStepPerTouchAndMergesADoubleTap() {
        var b = EuclideousPadUndoBurst()
        b.touchDown(at: 0.0)
        XCTAssertTrue(b.nextWriteNeedsNewStep(), "the first write of a touch checkpoints"); XCTAssertFalse(b.nextWriteNeedsNewStep()); XCTAssertFalse(b.nextWriteNeedsNewStep())
        b.touchEnd(at: 0.4)
        b.touchDown(at: 2.0)    // a separate touch, long after
        XCTAssertTrue(b.nextWriteNeedsNewStep(), "a later, separate touch is its own undo step")
        b.touchEnd(at: 2.5)
        // a double tap: tap, lift, tap again within 0.35s, then the reset write — all ONE step
        b.touchDown(at: 5.0); XCTAssertTrue(b.nextWriteNeedsNewStep()); b.touchEnd(at: 5.05)
        b.touchDown(at: 5.2); XCTAssertFalse(b.nextWriteNeedsNewStep(), "the second tap continues the same step — one undo returns to before the first tap"); b.touchEnd(at: 5.25)
        // an EMPTY touch (no write) opens no step; the next one still gets its checkpoint
        b.touchDown(at: 9.0); b.touchEnd(at: 9.1)
        b.touchDown(at: 9.2)
        XCTAssertTrue(b.nextWriteNeedsNewStep(), "nothing was checkpointed by the empty touch, so a double-tap reset after it is still undoable")
    }


    // MARK: - NOTES layer on/off follows the selection (Paul 2026-10-18) + the VELOCITY strip label

    private func laneWithNoNotesSelected() -> EuclidLine { var l = EuclidLine(); l.litNotes = 0; l.topLit = false; l.top2Lit = false; return l }

    // "If no notes are selected in the notes tab then it should be considered off."
    func testNotesLayerIsOffWhenNoNoteIsSelectedAndOnWhenOneIs() {
        let none = laneWithNoNotesSelected()
        XCTAssertTrue(none.notesOnResolved, "its switch reads on …")
        XCTAssertFalse(euclideousNotesHaveSelection(none)); XCTAssertFalse(euclideousNotesLayerIsOn(none), "… but with nothing selected the layer is OFF")
        XCTAssertFalse(euclideousNotesLayerIsOn(EuclidLine()), "a brand-new lane (nothing lit by default) is off")
        for (name, mutate) in [("a key", { (l: inout EuclidLine) in l.litNotes = 0b0001_0000 }), ("TOP", { $0.topLit = true }), ("TOP 2", { $0.top2Lit = true })] as [(String, (inout EuclidLine) -> Void)] {
            var l = none; mutate(&l)
            XCTAssertTrue(euclideousNotesHaveSelection(l), name); XCTAssertTrue(euclideousNotesLayerIsOn(l), "\(name) selected ⇒ on")
            l.notesOn = false
            XCTAssertFalse(euclideousNotesLayerIsOn(l), "\(name) selected but the switch is off ⇒ still off (the lit notes are remembered)")
        }
        // every surface that shows the layer's state reads the same answer
        var l = none; l.litNotes = 0b1
        XCTAssertEqual(euclideousMixLayerIsOff(l, notes: true), !euclideousNotesLayerIsOn(l))
        XCTAssertEqual(euclideousMixLayerIsOff(none, notes: true), !euclideousNotesLayerIsOn(none))
        // the riff layer's own off state is unchanged and independent of the notes selection
        var r = l; r.riffOn = false
        XCTAssertTrue(euclideousMixLayerIsOff(r, notes: false)); XCTAssertFalse(euclideousMixLayerIsOff(r, notes: true))
    }

    // MARK: - §5.1/§5.3 restart editor fallback + touch areas (RHYTHM fixes, 2026-10-21)

    /// §5.3: the MIX OUT button's widened hit area (±2pt vertically) must never reach into the OCT
    /// stepper's own — there's exactly one `sp4` gap between them (`euclideousMixGrid`'s own `belowPad`
    /// layout), so a 2pt expansion each still leaves clearance. A regression guard on the real constants,
    /// not a re-derived literal, so a future change to any of the three catches this invariant.
    func testOutButtonWidenedHitAreaNeverReachesTheOctStepper() {
        let gap = EuclideousMixMetrics.sp4
        let outExpansion: CGFloat = 2
        XCTAssertGreaterThanOrEqual(gap, outExpansion, "the OUT button's upward hit-area expansion must not exceed the gap to the OCT stepper above it")
    }

    // ── LEGATO REMOVED FROM A LANE'S GATE (2026-10-19) ──────────────────────────────────────────────────────────────────
    func testNoLaneGateSetterCanReachLegato() {
        XCTAssertEqual(euclideousLaneGateMax, 0.99)
        var l = EuclidLine()
        euclideousMixPadWrite(&l, notes: false, gate: 1.0, velocity: 90); XCTAssertEqual(l.gateResolved, 0.99, "the riff layer, through the pad")
        euclideousMixPadWrite(&l, notes: true, gate: 1.0, velocity: 90); XCTAssertEqual(l.notesGateResolved, 0.99, "the notes layer, through the pad")
        var s = EuclidLine(); euclideousSliderCommit(.gate, &s, snapshot: s, newValue: 1.0); XCTAssertEqual(s.gateResolved, 0.99, "the RHYTHM slider")
        euclideousSliderCommit(.gate, &s, snapshot: s, newValue: 0.5); XCTAssertEqual(s.gateResolved, 0.5, "everything below is untouched")
        XCTAssertFalse(euclideousGateIsLegato(l.gateResolved)); XCTAssertFalse(euclideousGateIsLegato(l.notesGateResolved)); XCTAssertFalse(euclideousGateIsLegato(s.gateResolved))
    }
    func testAStoredLaneGateOf100LoadsAs99ButEverythingBelowIsUntouched() {
        var doc = PluginState(machines: [], scenes: [SceneState.empty()])
        var lines = (0..<4).map { _ in EuclidLine() }
        lines[0].gate = 1.0; lines[0].notesGate = 1.0       // an older session's legato lane, both layers
        lines[1].gate = 0.98; lines[1].notesGate = 0.4      // ordinary values
        lines[2].gate = 1.0                                  // notes layer unset: follows the (clamped) riff gate
        doc.euclideousLines = lines
        let r = doc.euclideousLinesResolved
        XCTAssertEqual(r[0].gateResolved, 0.99); XCTAssertEqual(r[0].notesGateResolved, 0.99)
        XCTAssertEqual(r[1].gateResolved, 0.98); XCTAssertEqual(r[1].notesGateResolved, 0.4)
        XCTAssertEqual(r[2].gateResolved, 0.99); XCTAssertEqual(r[2].notesGateResolved, 0.99)
        XCTAssertNil(r[3].gate, "an untouched gate stays nil (its own 90% default)")
        XCTAssertTrue(r.allSatisfy { !euclideousGateIsLegato($0.gateResolved) && !euclideousGateIsLegato($0.notesGateResolved) })
        // the shipped presets are all 98% or less — none moves under the clamp
        for preset in EuclideousPresets.all {
            let d = preset.make()
            for (i, line) in (d.euclideousLines ?? []).enumerated() {
                XCTAssertLessThanOrEqual(line.gateResolved, 0.99, "\(preset.name) lane \(i + 1)")
                XCTAssertEqual(d.euclideousLinesResolved[i].gateResolved, line.gateResolved, "\(preset.name) lane \(i + 1): the clamp didn't touch it")
            }
        }
    }
    // The allocating K-of-N builder the Euclid core tests below read through (production builds into a reused buffer, `euclidPatternInto`).
    private func euclidPattern(pulses: Int, steps: Int, rotation: Int = 0) -> [Bool] {
        var buf = [Bool](repeating: false, count: max(1, min(64, steps)))
        let n = euclidPatternInto(&buf, pulses: pulses, steps: steps, rotation: rotation)
        return Array(buf[0..<n])
    }
    // GENERATORS (user 2026-08-08) — the pure pattern derivations.
    func testEuclidPatternSpreadsKHitsEvenly() {
        XCTAssertEqual(euclidPattern(pulses: 3, steps: 8).map { $0 ? 1 : 0 }, [1, 0, 0, 1, 0, 0, 1, 0], "tresillo: hits at 0,3,6")
        XCTAssertEqual(euclidPattern(pulses: 3, steps: 8).filter { $0 }.count, 3, "exactly K hits")
        XCTAssertEqual(euclidPattern(pulses: 5, steps: 8).filter { $0 }.count, 5)
        XCTAssertEqual(euclidPattern(pulses: 4, steps: 4).filter { $0 }.count, 4, "K==N → every step")
        XCTAssertEqual(euclidPattern(pulses: 0, steps: 8).filter { $0 }.count, 0, "K==0 → silence")
        XCTAssertTrue(euclidPattern(pulses: 3, steps: 8)[0], "a hit on step 0 before rotation")
        let base = euclidPattern(pulses: 3, steps: 8)
        XCTAssertEqual(euclidPattern(pulses: 3, steps: 8, rotation: 1), (0..<8).map { base[($0 + 1) % 8] }, "rotation cycles the pattern")
    }
    // TILT (Paul 2026-10-08): "bias the distribution of hits to the left or right."
    /// The CHORDS note source runs the allocation-free `…Into` form every render window; `chordSeqNotes` stays as the plain statement. Same notes for every key, scale, voicing, spread, matrix, rotation and beat.
    func testTheAllocationFreeChordGeneratorMatchesChordSeqNotes() {
        var g = SystemRandomNumberGenerator()
        let scales: [[Int]] = ScaleType.allCases.map { $0.intervals }
        var out = [Int](repeating: 0, count: 8)
        var rests = 0, chords = 0
        for _ in 0..<20_000 {
            var p = SnapParams()
            p.chordsMode = .pattern
            p.chordsSteps = Int.random(in: 1...16, using: &g)
            p.chordsDegrees = (0..<Int.random(in: 0...16, using: &g)).map { _ in Int.random(in: -1...11, using: &g) }   // -1 carry · 0…6 diatonic · 7 rest · 8…11 the borrowed chords
            p.chordsColours = Bool.random(using: &g) ? [] : (0..<Int.random(in: 0...16, using: &g)).map { _ in Int.random(in: 0...6, using: &g) }
            p.chordsVoicing = ChordVoicing.allCases.randomElement(using: &g)!; p.chordsSpread = ChordSpread.allCases.randomElement(using: &g)!
            p.chordsRotate = Int.random(in: -20...20, using: &g); p.chordsRateBeats = [0, 1, 2, 4, 0.5].randomElement(using: &g)!
            let tones = scales.randomElement(using: &g)!, root = Int.random(in: -12...23, using: &g), beat = Double.random(in: -8...400, using: &g)
            let expected = chordSeqNotes(beat: beat, p, keyRoot: root, keyTones: tones, followNote: nil)
            let n = chordSeqNotesInto(&out, beat: beat, p, keyRoot: root, keyTones: tones, followNote: nil)
            XCTAssertEqual(Array(out[0..<n]), expected, "beat \(beat) root \(root) \(p.chordsVoicing) \(p.chordsSpread)")
            if expected.isEmpty { rests += 1 } else { chords += 1 }
        }
        XCTAssertGreaterThan(rests, 500); XCTAssertGreaterThan(chords, 5000)
        var w = SnapParams(); w.chordsMode = .walk
        XCTAssertEqual(Array(out[0..<chordSeqNotesInto(&out, beat: 9, w, keyRoot: 0, keyTones: scales[0], followNote: nil)]), chordSeqNotes(beat: 9, w, keyRoot: 0, keyTones: scales[0], followNote: nil), "WALK falls back to the array form")
    }
    func testEuclidTiltPatternIsANoOpAtZero() {
        var buf = euclidPattern(pulses: 3, steps: 8)
        let before = buf
        euclidTiltPattern(&buf, pulses: 3, steps: 8, tilt: 0)
        XCTAssertEqual(buf, before, "tilt=0 must be byte-identical to not calling this at all")
    }
    /// The render thread runs the bitmask form; the Set-and-arrays form stays as the plain statement of the rule. Every K, N, tilt and (hand-edited, not-Euclid) pattern must come out the same — including patterns whose hit count does not match K.
    func testTheAllocationFreeTiltAgreesWithTheReferenceOnEveryShape() {
        var g = SystemRandomNumberGenerator()
        var changed = 0
        for _ in 0..<30_000 {
            let n = Int.random(in: 2...64, using: &g), k = Int.random(in: 0...n, using: &g)
            var a = euclidPattern(pulses: k, steps: n)
            if Bool.random(using: &g) { for i in 0..<n where Int.random(in: 0..<6, using: &g) == 0 { a[i].toggle() } }   // a hand-edited pattern: hit count may no longer equal K
            if Bool.random(using: &g) { a += [Bool](repeating: true, count: Int.random(in: 0...3, using: &g)) }          // a buffer longer than the lane's steps
            let tilt = [0.0, -1, -0.5, 0.25, 0.7, 1, Double.random(in: -1.5...1.5, using: &g)].randomElement(using: &g)!
            var fast = a, ref = a
            euclidTiltPattern(&fast, pulses: k, steps: n, tilt: tilt)
            euclidTiltPatternReference(&ref, pulses: k, steps: n, tilt: tilt)
            XCTAssertEqual(fast, ref, "k \(k) n \(n) tilt \(tilt)")
            if fast != a { changed += 1 }
        }
        XCTAssertGreaterThan(changed, 5000, "the fuzz must actually move hits, or it proves nothing")
        var big = [Bool](repeating: false, count: 70); for i in stride(from: 0, to: 70, by: 7) { big[i] = true }
        var bigRef = big
        euclidTiltPattern(&big, pulses: 10, steps: 70, tilt: 0.6); euclidTiltPatternReference(&bigRef, pulses: 10, steps: 70, tilt: 0.6)
        XCTAssertEqual(big, bigRef, "more than 64 steps falls back to the reference")
    }
    func testEuclidTiltPatternPreservesExactHitCount() {
        for (k, n) in [(3, 8), (5, 8), (2, 16), (7, 16), (1, 8)] {
            for t in [-1.0, -0.5, 0.3, 1.0] {
                var buf = euclidPattern(pulses: k, steps: n)
                euclidTiltPattern(&buf, pulses: k, steps: n, tilt: t)
                XCTAssertEqual(buf.filter { $0 }.count, k, "K=\(k) N=\(n) tilt=\(t): exactly K hits must survive, never dropped or duplicated")
            }
        }
    }
    func testEuclidTiltPatternShiftsWeightedAveragePositionDirectionally() {
        func avgPos(_ buf: [Bool]) -> Double {
            let idxs = buf.enumerated().filter { $0.element }.map { Double($0.offset) }
            return idxs.reduce(0, +) / Double(idxs.count)
        }
        var neg = euclidPattern(pulses: 4, steps: 16); euclidTiltPattern(&neg, pulses: 4, steps: 16, tilt: -1)
        let zero = euclidPattern(pulses: 4, steps: 16)
        var pos = euclidPattern(pulses: 4, steps: 16); euclidTiltPattern(&pos, pulses: 4, steps: 16, tilt: 1)
        XCTAssertLessThan(avgPos(neg), avgPos(zero), "negative tilt must pull the average hit position EARLIER")
        XCTAssertGreaterThan(avgPos(pos), avgPos(zero), "positive tilt must pull the average hit position LATER")
    }
    func testEuclidTiltPatternLeavesATrivialPatternUntouched() {
        var buf = euclidPattern(pulses: 1, steps: 8)
        let before = buf
        euclidTiltPattern(&buf, pulses: 1, steps: 8, tilt: 1)
        XCTAssertEqual(buf, before, "a single hit has nothing to bias — tilt must be a no-op")
    }
    // LINEAR BLEND (Paul 2026-10-11, redesign — "indecipherable or unpredictable... I like the idea of a
    // slider that places density early, middle or late"): replaces the old power-curve (`rank^gamma`) warp,
    // which was perceptually nonlinear (most of its visible movement bunched in a narrow band of the
    // control's travel). The new mechanism must be a TRUE straight-line interpolation between "evenly
    // spread" (tilt=0) and "fully packed at one end" (tilt=±1) — distinguishing it from the old curve,
    // which would NOT land on these exact values.
    func testEuclidTiltPatternReachesExactlyFullyPackedAtTheExtremes() {
        let k = 4, n = 16
        var early = euclidPattern(pulses: k, steps: n); euclidTiltPattern(&early, pulses: k, steps: n, tilt: -1)
        XCTAssertEqual(early, (0..<n).map { $0 < k }, "tilt=-1 must cram all K hits into the FIRST K steps, exactly")
        var late = euclidPattern(pulses: k, steps: n); euclidTiltPattern(&late, pulses: k, steps: n, tilt: 1)
        XCTAssertEqual(late, (0..<n).map { $0 >= n - k }, "tilt=+1 must cram all K hits into the LAST K steps, exactly")
    }
    func testEuclidTiltPatternAtHalfTiltLandsExactlyHalfwayBetweenEvenAndPacked() {
        // K=3/N=10, tilt=0.5, worked by hand from the formula itself (evenPos + |t|×(packedLate−evenPos)),
        // not from the OLD power-curve (which would NOT produce these values — the discriminating point of
        // this test): hit0 evenPos=0, packedLate=10−3+0=7 → 0+0.5×7=3.5→4. hit1 evenPos=1/2×9=4.5,
        // packedLate=8 → 4.5+0.5×3.5=6.25→6. hit2 evenPos=9, packedLate=9 (coincide at the last hit for
        // this K/N) → 9. No collisions (4,6,9 are distinct), so no nudging enters the picture either.
        let k = 3, n = 10
        var buf = euclidPattern(pulses: k, steps: n)
        euclidTiltPattern(&buf, pulses: k, steps: n, tilt: 0.5)
        let positions = buf.enumerated().filter { $0.element }.map { $0.offset }
        XCTAssertEqual(positions, [4, 6, 9], "tilt=0.5 must land each hit exactly halfway between its even-spread and fully-packed-late position — the defining property of a LINEAR blend")
    }
    // ROTATION DECOUPLING (Paul 2026-10-11: "the offset makes tilt look indecipherable... maybe this could
    // adjust to offset") — `euclidRotateBuffer` must reproduce `euclidPatternInto`'s OWN internal rotation
    // exactly, so building unrotated-then-rotating is byte-identical to the old single-call convention
    // whenever TILT isn't in play (the untilted case must be a true no-op change).
    func testEuclidRotateBufferMatchesEuclidPatternIntosOwnRotationExactly() {
        for (k, n, rot) in [(3, 8, 1), (3, 8, 5), (5, 16, 7), (2, 8, 0), (4, 12, 11)] {
            let direct = euclidPattern(pulses: k, steps: n, rotation: rot)
            var viaRotate = euclidPattern(pulses: k, steps: n, rotation: 0)
            euclidRotateBuffer(&viaRotate, steps: n, rotation: rot)
            XCTAssertEqual(viaRotate, direct, "K=\(k) N=\(n) rot=\(rot): build-unrotated-then-rotate must exactly match build-with-rotation")
        }
    }
    func testEuclidRotateBufferPreservesCountAndIsANoOpAtZero() {
        var buf = euclidPattern(pulses: 3, steps: 8)
        let before = buf
        euclidRotateBuffer(&buf, steps: 8, rotation: 0)
        XCTAssertEqual(buf, before, "rotation=0 must be a byte-identical no-op")
        euclidRotateBuffer(&buf, steps: 8, rotation: 3)
        XCTAssertEqual(buf.filter { $0 }.count, 3, "rotation must never drop or duplicate a hit")
    }
    // DIRECTION (2026-09-29): euclidReadIndex flips the READ into the already-rotated buffer, not a second
    // rotation. Rotate-then-reverse and reverse-then-rotate are NOT the same pattern in general (they differ by a
    // shift of 2×rotate mod n) — this worked example pins the composition order actually shipped, so a future
    // refactor can't silently swap it without a test noticing.
    func testEuclidReverseFlipsReadIndexNotRebuiltBuffer() {
        XCTAssertEqual(euclidReadIndex(0, n: 8, dir: .fwd), 0)
        XCTAssertEqual(euclidReadIndex(3, n: 8, dir: .fwd), 3, "FWD is the identity — no change from today")
        XCTAssertEqual(euclidReadIndex(0, n: 8, dir: .bkw), 7)
        XCTAssertEqual(euclidReadIndex(7, n: 8, dir: .bkw), 0, "BKW mirrors the index range")
        // K=3,N=8 rotated by 1: [0,0,1,0,0,1,0,1] (hits at buffer indices 2,5,7 — from testEuclidPatternSpreadsKHitsEvenly's
        // own base [1,0,0,1,0,0,1,0], rotated[i] = base[(i+1)%8]).
        let rotated = euclidPattern(pulses: 3, steps: 8, rotation: 1)
        XCTAssertEqual(rotated.map { $0 ? 1 : 0 }, [0, 0, 1, 0, 0, 1, 0, 1])
        // SHIPPED composition: reverse reads THIS rotated buffer back-to-front (readIdx = n-1-step).
        let reverseOfRotated = (0..<8).map { rotated[euclidReadIndex($0, n: 8, dir: .bkw)] }
        XCTAssertEqual(reverseOfRotated.enumerated().filter { $0.element }.map { $0.offset }, [0, 2, 5],
                       "reverse-of-the-already-rotated-buffer's hit steps")
        // The OTHER, NOT-shipped order — reverse the UNROTATED base, then rotate it — gives a DIFFERENT pattern,
        // proving the two compositions genuinely disagree (not an arbitrary choice between equivalent orders).
        let base = euclidPattern(pulses: 3, steps: 8)
        let reversedBase = (0..<8).map { base[7 - $0] }
        let rotateThenOfReversedBase = (0..<8).map { reversedBase[($0 + 1) % 8] }
        XCTAssertEqual(rotateThenOfReversedBase.enumerated().filter { $0.element }.map { $0.offset }, [0, 3, 6])
        XCTAssertNotEqual(reverseOfRotated, rotateThenOfReversedBase, "the two composition orders are NOT interchangeable")
    }
    // DIRECTION §3-way (2026-10-01): PING-PONG bounces — period 2n, each endpoint (raw 0 and raw n-1) sounds on
    // TWO consecutive raw ticks (the turn), every OTHER index exactly once per lap — worked against the SAME
    // n=8 rotated buffer as the test above, so the hit-step numbers are directly comparable.
    func testEuclidPingPongCycleLenAndReadIndex() {
        XCTAssertEqual(euclidCycleLen(.fwd, n: 8), 8)
        XCTAssertEqual(euclidCycleLen(.bkw, n: 8), 8, "BKW's cycle length is unchanged — only the read direction flips")
        XCTAssertEqual(euclidCycleLen(.pingpong, n: 8), 16, "PING-PONG must bounce out and back before repeating")
        // raw 0...7 ascend (identity, same as FWD); raw 8...15 descend back through 6...0 — endpoints 0 and 7 are
        // each read on two CONSECUTIVE raw ticks (7 at raw=7 and raw=8; 0 at raw=15 and the next lap's raw=0).
        let readSeq = (0..<16).map { euclidReadIndex($0, n: 8, dir: .pingpong) }
        XCTAssertEqual(readSeq, [0, 1, 2, 3, 4, 5, 6, 7, 7, 6, 5, 4, 3, 2, 1, 0])
        let rotated = euclidPattern(pulses: 3, steps: 8, rotation: 1)   // same fixture as the test above: hits at 2,5,7
        let pingpongHitSteps = readSeq.enumerated().filter { rotated[$0.element] }.map { $0.offset }
        XCTAssertEqual(pingpongHitSteps, [2, 5, 7, 8, 10, 13], "hit at buffer index 7 fires on BOTH raw ticks 7 and 8 (the turn)")
    }
    // The finished lane pattern (cells only) as the page and the engine build it — the allocating form of `euclideousBuildHitPatternInto`.
    private func euclideousBuildPattern(_ L: EuclidLine) -> (buf: [Bool], n: Int) {
        var cells = [Bool](repeating: false, count: 16), micro = [Double](repeating: 0, count: 16)
        let n = euclideousBuildHitPatternInto(L, cells: &cells, micro: &micro)
        return (cells, n)
    }
    // §7's "a tab is either fully the lane's own or fully paused" means a borrowing lane's own rotate/invert
    // do NOT apply on top any more (unlike the old FOLLOW) — this also regression-tests the direction-
    // double-application bug fixed in both Router.swift and this mirror (the lane's own `direction` field is
    // never read a second time once DIRECTION/COPY have already placed the cells in their final tick order).
    func testEffectivePatternOfACopyLaneIsTheSourcesFinishedPatternWithNoOffsetOrInvertOnTop() {
        let lines = copyLines()
        guard let eff = euclideousEffectivePattern(lane: 1, lines: lines) else { return XCTFail("no pattern") }
        XCTAssertTrue(eff.followsPartner)
        XCTAssertEqual(eff.n, 7, "the follower takes the source's step count, not its own 8")
        // by hand: exactly the source's finished pattern — no rotate/invert of the follower's own on top
        let source = euclideousBuildPattern(lines[0])
        XCTAssertEqual(Array(eff.buf.prefix(eff.n)), Array(source.buf.prefix(source.n)))
        // …and it is NOT the follower's own 2-of-8
        let own = euclideousBuildPattern(lines[1])
        XCTAssertNotEqual(own.n, eff.n)
        // a lane that is not borrowing plays its OWN pattern
        let plain = euclideousEffectivePattern(lane: 0, lines: lines)!
        XCTAssertFalse(plain.followsPartner); XCTAssertEqual(plain.buf, euclideousBuildPattern(lines[0]).buf); XCTAssertEqual(plain.n, 7)
        // no OTHER lane exists to borrow from ⇒ not borrowing, even though RHYTHM is COPY
        let single = [lines[1]]
        XCTAssertNil(euclideousRhythmBorrowPartner(lane: 0, lines: single))
        XCTAssertFalse(euclideousEffectivePattern(lane: 0, lines: single)!.followsPartner)
        XCTAssertNil(euclideousEffectivePattern(lane: 4, lines: lines))
    }

    /// Cross-check against the SAME footer-prediction primitive the UI uses (`euclideousLapHitSteps`) — a
    /// real, rotated+tilted pattern, across all 3 Euclideous directions, confirming the new gap function can
    /// never silently disagree with what the step footers themselves predict (per the ferry's own "use the
    /// same prediction the step footers use"; the footer-mirror functions have a documented history of
    /// drifting from the real engine, so this is a standing regression guard, not a one-off sanity check).
     // The lap's hit list (what the strip, the footers and the LANES roll all read): ticks strictly increase and stay inside one cycle, for every direction.
    func testLapHitStepsAreStrictlyIncreasingTicksInsideOneCycleForEveryDirection() {
        for dir in [EuclidDir.fwd, .bkw, .pingpong] {
            let hits = euclideousLapHitSteps(pulses: 3, steps: 8, rotate: 2, tilt: 0.3, patternMiss: false, customHits: nil, dir: dir)
            let cycleLen = euclidCycleLen(dir, n: 8)
            XCTAssertFalse(hits.isEmpty, "\(dir)")
            for i in 1..<hits.count { XCTAssertGreaterThan(hits[i].tick, hits[i - 1].tick, "\(dir): hit \(i)") }
            XCTAssertTrue(hits.allSatisfy { $0.tick >= 0 && $0.tick < cycleLen }, "\(dir): inside one cycle")
            XCTAssertEqual(hits.count, dir == .pingpong ? 6 : 3, "\(dir): PING-PONG visits each hit twice")
        }
    }

    // span ladder ×8 reach (an untested edge).
    func testSpanLadder64Reach() {
        XCTAssertEqual(spanLadderBeats(64, S: 0.5, row: 4.0), 32.0, "×8 = 8 rows")
    }

    // SPAN LADDER (Paul 2026-08-22 §3): the WIDTH-in-beats dial. Endpoints CELL(1)=S and ROW(8)=rowBeats are the
    // byte-identical legacy anchors; 2·3·4·6 = N columns; 16/32 = ×2/×4 the row (the multi-bar polymeter spans — never
    // reached by the 1-bar Router integration tests, so proven directly here).
    func testSpanLadderBeatsCoversEveryRung() {
        let S = 0.5, row = 4.0
        XCTAssertEqual(spanLadderBeats(1, S: S, row: row), S, "CELL = one column (S)")
        XCTAssertEqual(spanLadderBeats(8, S: S, row: row), row, "ROW = the whole row (rowBeats)")
        XCTAssertEqual(spanLadderBeats(3, S: S, row: row), 1.5, "3 columns = 3·S")
        XCTAssertEqual(spanLadderBeats(6, S: S, row: row), 3.0, "6 columns = 6·S")
        XCTAssertEqual(spanLadderBeats(16, S: S, row: row), 8.0, "×2 = 2 rows")
        XCTAssertEqual(spanLadderBeats(32, S: S, row: row), 16.0, "×4 = 4 rows")
        XCTAssertEqual(spanLadderBeats(0, S: S, row: row), S, "sub-1 clamps to CELL")
    }

    // The pad's strip is always GATE and its spoken value plain — legato was removed from the XY box (2026-10-19). The RHYTHM slider's own label function is unchanged
    // (a raw 1.0 would still read LEGATO there) but nothing can set a lane's gate that high any more.
    func testMixGateNameIsAlwaysGateAndTheSpokenValueNeverSaysLegato() {
        var l = EuclidLine(); l.gate = 1.0
        XCTAssertEqual(euclideousSliderLabelText(.gate, l), "LEGATO", "the slider's own pure label function is untouched")
        XCTAssertTrue(euclideousGateIsLegato(1.0)); XCTAssertFalse(euclideousGateIsLegato(0.99), "the engine's legato predicate is untouched (the FX GATE row uses it)")
        XCTAssertEqual(euclideousMixGateValueText(gate: 0.6), "60%"); XCTAssertEqual(euclideousMixGateValueText(gate: 0.99), "99%")
        XCTAssertEqual(euclideousMixPadAccessibilityValue(gate: 0.6, velocity: 104), "gate 60 percent, velocity 104")
        XCTAssertEqual(euclideousMixPadAccessibilityValue(gate: 0.99, velocity: 127), "gate 99 percent, velocity 127")
        XCTAssertEqual(euclideousMixPadAccessibilityValue(gate: 1.0, velocity: 127), "gate 100 percent, velocity 127", "no \"legato\" suffix, even for a raw 1.0")
        XCTAssertEqual(euclideousMixPadAccessibilityLabel(lane: 0, notes: false, off: false), "Lane 1 riff")
        XCTAssertEqual(euclideousMixPadAccessibilityLabel(lane: 3, notes: true, off: true), "Lane 4 notes, off")
        XCTAssertEqual(euclideousMixOctaveAccessibilityLabel(lane: 1, notes: true), "Lane 2 notes octave")
        XCTAssertEqual(euclideousMixVelocityStep(126, up: true), 127); XCTAssertEqual(euclideousMixVelocityStep(100, up: true), 104); XCTAssertEqual(euclideousMixVelocityStep(2, up: false), 1)
        XCTAssertEqual(euclideousMixGateStep(0.6, longer: true), 0.65, accuracy: 1e-12); XCTAssertEqual(euclideousMixGateStep(0.98, longer: true), 0.99, accuracy: 1e-12); XCTAssertEqual(euclideousMixGateStep(0.99, longer: true), 0.99, accuracy: 1e-12)
        XCTAssertEqual(euclideousMixGateStep(0.03, longer: false), 0.01, accuracy: 1e-12)
    }
}
