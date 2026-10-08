//  DerivationsTests.swift
//  Off-device unit tests for MidiSpark's pure engine core (Derivations.swift + Models.swift enums).
//  These run in seconds via `xcodebuild test` — no simulator, no iPad, no ears. They guard the
//  regression-prone math: swing warp + inverse, phase modes, arp patterns, dispatch, ratchet ramp.

import XCTest

final class DerivationsTests: XCTestCase {

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

    func testRetrigRestartsEachColumn() {
        // RETRIG: index resets to 0 at each column (step) start.
        let arp = 0.25, S = 2.0, cyc = 16.0
        // column 0 start (beat 0) and column 1 start (beat 2) both → phase 0
        XCTAssertEqual(phaseIndex(tick: 0, mTickBeat: 0, arpBeats: arp, S: S, cycleBeats: cyc,
                                  phase: .retrig, runStartColumn: -1), 0)
        let tickAtCol1 = Int64(2.0 / arp)   // 8
        XCTAssertEqual(phaseIndex(tick: tickAtCol1, mTickBeat: 2.0, arpBeats: arp, S: S, cycleBeats: cyc,
                                  phase: .retrig, runStartColumn: -1), 0)
    }

    func testFreeIsAbsolute() {
        // FREE: phase index == absolute tick, never resets.
        XCTAssertEqual(phaseIndex(tick: 37, mTickBeat: 9.25, arpBeats: 0.25, S: 2, cycleBeats: 16,
                                  phase: .free, runStartColumn: -1), 37)
    }

    func testLegatoCountsFromRunStart() {
        // LEGATO run starting at column 4: at column 5 the index continues (doesn't reset).
        let arp = 0.5, S = 2.0, cyc = 16.0, runStart: Int8 = 4
        // column 4 start = beat 8 → phase 0; column 5 start = beat 10 → phase 4 (4 ticks of 0.5 in)
        XCTAssertEqual(phaseIndex(tick: Int64(8.0 / arp), mTickBeat: 8.0, arpBeats: arp, S: S,
                                  cycleBeats: cyc, phase: .legato, runStartColumn: runStart), 0)
        XCTAssertEqual(phaseIndex(tick: Int64(10.0 / arp), mTickBeat: 10.0, arpBeats: arp, S: S,
                                  cycleBeats: cyc, phase: .legato, runStartColumn: runStart), 4)
    }

    // MARK: arp patterns (§3)

    private func pool(_ notes: [UInt8]) -> NotePool {
        let p = NotePool()
        for n in notes { p.noteOn(n, velocity: 100, channel: 0) }
        p.rebuildSorted()
        return p
    }

    private func sequence(pattern: ArpPattern, octaves: Int, notes: [UInt8], length: Int) -> [Int] {
        let p = pool(notes)
        let pi = UInt8(ArpPattern.allCases.firstIndex(of: pattern)!)
        return (0..<length).map { arpPickSource(phaseIndex: Int64($0), octaves: octaves,
                                                pattern: pi, pool: p) }
    }

    func testPatternUp() {
        XCTAssertEqual(sequence(pattern: .up, octaves: 1, notes: [60, 64, 67], length: 6),
                       [60, 64, 67, 60, 64, 67])
    }

    func testPatternDown() {
        XCTAssertEqual(sequence(pattern: .down, octaves: 1, notes: [60, 64, 67], length: 6),
                       [67, 64, 60, 67, 64, 60])
    }

    func testPatternUpDownNoRepeatedEnds() {
        // C E G with UP-DN: C E G E | C E G E …  (top and bottom each hit once per period)
        XCTAssertEqual(sequence(pattern: .upDown, octaves: 1, notes: [60, 64, 67], length: 8),
                       [60, 64, 67, 64, 60, 64, 67, 64])
    }

    func testPatternUpOctaves() {
        // 2 octaves: base then +12 across the span.
        XCTAssertEqual(sequence(pattern: .up, octaves: 2, notes: [60, 64], length: 4),
                       [60, 64, 72, 76])
    }

    func testPatternAsPlayed() {
        // Pressed 67, 60, 64 (not ascending) → AS-PLAYED follows PRESS order, not pitch…
        XCTAssertEqual(sequence(pattern: .asPlayed, octaves: 1, notes: [67, 60, 64], length: 6),
                       [67, 60, 64, 67, 60, 64])
        // …while UP on the same pool sorts to pitch order.
        XCTAssertEqual(sequence(pattern: .up, octaves: 1, notes: [67, 60, 64], length: 3),
                       [60, 64, 67])
    }

    func testPatternAltLo() {
        // ALT LO (Paul 2026-09-13): the lowest note pedals, alternating with each higher note ascending — 1,2,1,3,1,4…
        XCTAssertEqual(sequence(pattern: .altLo, octaves: 1, notes: [60, 64, 67, 71], length: 8),
                       [60, 64, 60, 67, 60, 71, 60, 64])
    }

    func testPatternAltHi() {
        // ALT HI: the mirror — the highest note pedals, alternating with each lower note descending.
        XCTAssertEqual(sequence(pattern: .altHi, octaves: 1, notes: [60, 64, 67, 71], length: 8),
                       [71, 67, 71, 64, 71, 60, 71, 67])
    }

    func testRandomAnchorExcludesTheAnchorFromThePool() {
        // Paul 2026-09-13: the anchored note sounds only at the cycle wrap (asc==0); the shuffle never repeats it.
        let p = pool([60, 64, 67, 71])   // span 4, octaves 1
        let rnd = UInt8(ArpPattern.allCases.firstIndex(of: .random)!)
        for pi in 0..<40 {
            let lo = arpPick(phaseIndex: Int64(pi), octaves: 1, pattern: rnd, pool: p, randomAnchor: 1).note
            if pi % 4 == 0 { XCTAssertEqual(lo, 60, "LO opens each cycle on the low anchor") }
            else { XCTAssertNotEqual(lo, 60, "the low anchor never repeats inside the shuffled pool") }
            let hi = arpPick(phaseIndex: Int64(pi), octaves: 1, pattern: rnd, pool: p, randomAnchor: 2).note
            if pi % 4 == 0 { XCTAssertEqual(hi, 71, "HI opens each cycle on the high anchor") }
            else { XCTAssertNotEqual(hi, 71, "the high anchor never repeats inside the shuffled pool") }
        }
    }

    func testRandomIsLoopConsistent() {
        // Same tick → same note every pass. Compare pass 0 with pass 1 (span apart).
        let p = pool([60, 62, 64, 65, 67])
        let pi = UInt8(ArpPattern.allCases.firstIndex(of: .random)!)
        let span = Int64(p.count)   // octaves 1
        for t in 0..<span {
            let a = arpPickSource(phaseIndex: t, octaves: 1, pattern: pi, pool: p)
            let b = arpPickSource(phaseIndex: t, octaves: 1, pattern: pi, pool: p)
            XCTAssertEqual(a, b, "RANDOM must be a pure function of the tick")
        }
        // and it should actually shuffle (not equal UP for this pool/length)
        let rnd = (0..<8).map { arpPickSource(phaseIndex: Int64($0), octaves: 1, pattern: pi, pool: p) }
        let up = sequence(pattern: .up, octaves: 1, notes: [60, 62, 64, 65, 67], length: 8)
        XCTAssertNotEqual(rnd, up)
    }

    // (Provenance channel removed with delta §7 — a note carries no channel past the input filter;
    //  channel behaviour is covered by the input-channel filter tests below.)

    func testEmptyPoolReturnsMinusOne() {
        let up = UInt8(ArpPattern.allCases.firstIndex(of: .up)!)
        XCTAssertEqual(arpPickSource(phaseIndex: 0, octaves: 1, pattern: up, pool: NotePool()), -1)
    }

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

    func testArpPickSourceHonoursFilter() {
        let p = mixedPool()
        let up = UInt8(ArpPattern.allCases.firstIndex(of: .up)!)
        // filter ch 1: the arp cycles only 60 and 67
        XCTAssertEqual(arpPickSource(phaseIndex: 0, octaves: 1, pattern: up, pool: p, filter: 1), 60)
        XCTAssertEqual(arpPickSource(phaseIndex: 1, octaves: 1, pattern: up, pool: p, filter: 1), 67)
        XCTAssertEqual(arpPickSource(phaseIndex: 2, octaves: 1, pattern: up, pool: p, filter: 1), 60)  // wraps (span 2)
        // filter ch 5: empty → −1
        XCTAssertEqual(arpPickSource(phaseIndex: 0, octaves: 1, pattern: up, pool: p, filter: 5), -1)
        // OMNI default unchanged from pre-filter behaviour
        XCTAssertEqual(arpPickSource(phaseIndex: 0, octaves: 1, pattern: up, pool: p), 60)
    }

    func testReceiverHearsOmniAndChannel() {
        // delta §9 item 11: OMNI (0) hears every channel; a filter hears only its own (wire ch = filter−1).
        XCTAssertTrue(receiverHears(filter: 0, channel: 0))
        XCTAssertTrue(receiverHears(filter: 0, channel: 9))
        XCTAssertTrue(receiverHears(filter: 3, channel: 2))    // filter 3 = wire channel 2
        XCTAssertFalse(receiverHears(filter: 3, channel: 5))
        XCTAssertFalse(receiverHears(filter: 1, channel: 1))   // filter 1 = wire channel 0, not 1
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

    func testThruAudiblePassthroughGate() {
        let any = 0b1111
        // Un-muted THRU on OMNI/ANY forwards a non-note event (today's default R1 behaviour).
        XCTAssertTrue(thruAudible(isNote: false, isSystem: false, filter: 0, cableMask: any, eventCable: 1, channel: 5))
        // A non-note event on the WRONG channel is blocked; a note soundcheck ignores channel (mute-gated only).
        XCTAssertFalse(thruAudible(isNote: false, isSystem: false, filter: 3, cableMask: any, eventCable: 1, channel: 5))  // filter 3 = wire ch 2
        XCTAssertTrue(thruAudible(isNote: true, isSystem: false, filter: 3, cableMask: any, eventCable: 1, channel: 5))    // note ignores channel
        // A non-note event on the wrong CABLE is blocked.
        XCTAssertFalse(thruAudible(isNote: false, isSystem: false, filter: 0, cableMask: 0b0010, eventCable: 1, channel: 5))
        // A MUTED THRU (filter ≥ mutedSourceFilter) blocks EVERYTHING — non-note AND the note soundcheck.
        XCTAssertFalse(thruAudible(isNote: false, isSystem: false, filter: Snap.mutedSourceFilter, cableMask: any, eventCable: 1, channel: 5))
        XCTAssertFalse(thruAudible(isNote: true, isSystem: false, filter: Snap.mutedSourceFilter, cableMask: any, eventCable: 1, channel: 5))
    }

    /// SYSTEM messages (clock/start/stop/SysEx/active-sensing) are channel-LESS — a non-OMNI THRU filter must NOT
    /// drop them (audit B1). Their status low-nibble is a sub-type, not a channel; only mute + cable gate them.
    func testThruAudibleNeverChannelFiltersSystemMessages() {
        let any = 0b1111
        // A clock byte (0xF8 → low nibble 8, would look like "channel 8") on a THRU set to filter 3 STILL passes.
        XCTAssertTrue(thruAudible(isNote: false, isSystem: true, filter: 3, cableMask: any, eventCable: 1, channel: 8))
        XCTAssertTrue(thruAudible(isNote: false, isSystem: true, filter: 5, cableMask: any, eventCable: 1, channel: 0))  // SysEx 0xF0
        // Mute still blocks system; a wrong CABLE still blocks (a legitimate port distinction).
        XCTAssertFalse(thruAudible(isNote: false, isSystem: true, filter: Snap.mutedSourceFilter, cableMask: any, eventCable: 1, channel: 8))
        XCTAssertFalse(thruAudible(isNote: false, isSystem: true, filter: 0, cableMask: 0b0010, eventCable: 1, channel: 8))
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

    func testHoldAltAndOctave() {
        var on = OnConfig(); on.hold = .alt
        XCTAssertFalse(holdAlt(base: false, on: on, held: false))          // not held → inert
        XCTAssertTrue(holdAlt(base: false, on: on, held: true))            // held + ALT → flips
        XCTAssertFalse(holdAlt(base: true, on: on, held: true))
        on.hold = .oct
        XCTAssertFalse(holdAlt(base: false, on: on, held: true))           // a non-alt hold doesn't flip alt
        on.octUp = true;  XCTAssertEqual(holdOctaveShift(on: on, held: true), 12)   // OCT up
        on.octUp = false; XCTAssertEqual(holdOctaveShift(on: on, held: true), -12)  // OCT down
        XCTAssertEqual(holdOctaveShift(on: on, held: false), 0)            // not held → no shift
        on.hold = .freeze; XCTAssertEqual(holdOctaveShift(on: on, held: true), 0)   // a non-oct hold → no shift
    }

    // MARK: - ON TAP timing (§9 item 1, 4c) — quantized onset + duration expiry

    func testMpeLikelyNeedsTwoOrMoreChannels() {
        XCTAssertFalse(mpeLikely(channelMask: 0), "silence is not MPE")
        XCTAssertFalse(mpeLikely(channelMask: 1 << 0), "a chord all on ch 1 is a normal controller")
        XCTAssertFalse(mpeLikely(channelMask: 1 << 5), "one channel, however high, is not MPE")
        XCTAssertTrue(mpeLikely(channelMask: (1 << 1) | (1 << 2)), "notes on ch 2 + ch 3 = per-note channels = MPE")
        XCTAssertTrue(mpeLikely(channelMask: 0xFFFE), "the whole lower zone spread = MPE")
    }

    // MARK: - UI peak-hold decay (delta §6a metering — shared by both meter views)

    func testPeakHoldLevelDecaysLinearly() {
        let t0 = Date(timeIntervalSinceReferenceDate: 1000)
        XCTAssertEqual(peakHoldLevel(peak: 1.0, since: t0, now: t0, hold: 0.15), 1.0, accuracy: 1e-9)               // at the peak
        XCTAssertEqual(peakHoldLevel(peak: 1.0, since: t0, now: t0.addingTimeInterval(0.075), hold: 0.15), 0.5, accuracy: 1e-6) // half-way
        XCTAssertEqual(peakHoldLevel(peak: 1.0, since: t0, now: t0.addingTimeInterval(0.30), hold: 0.15), 0.0, accuracy: 1e-9)  // clamped ≥ 0
        XCTAssertEqual(peakHoldLevel(peak: 1.0, since: t0, now: t0, hold: 0), 0.0, accuracy: 1e-9)                 // no divide-by-zero
    }

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

    // HOLD note-identity (Paul 2026-08-31): admittedMask must expose the held NOTE SET (filtered) so HOLD can tell a same-size
    // chord SWAP from a stable chord — a difference the note COUNT hides.
    func testAdmittedMaskExposesTheNoteSetByIdentity() {
        let a = NotePool()                                                  // notes < 64 → all in the LO word
        for n: UInt8 in [48, 52, 55] { a.noteOn(n, velocity: 100, channel: 0, cable: 1) }
        a.rebuildSorted()
        let (alo, _) = a.admittedMask(chanMask: 0xFFFF, cableMask: 0b1111)
        XCTAssertEqual(alo, (UInt64(1) << 48) | (UInt64(1) << 52) | (UInt64(1) << 55))
        // A SAME-SIZE swap (48,52,55 → 50,53,57): same count, DIFFERENT set → the masks differ (count alone would miss it).
        let b = NotePool()
        for n: UInt8 in [50, 53, 57] { b.noteOn(n, velocity: 100, channel: 0, cable: 1) }
        b.rebuildSorted()
        let (blo, _) = b.admittedMask(chanMask: 0xFFFF, cableMask: 0b1111)
        XCTAssertNotEqual(alo, blo)
        XCTAssertNotEqual(alo & ~blo, 0)   // notes removed (48,52,55 not in b)
        XCTAssertNotEqual(blo & ~alo, 0)   // notes added   (50,53,57 not in a)
        // A note ≥ 64 lands in the HI word.
        let h = NotePool(); h.noteOn(72, velocity: 100, channel: 0, cable: 1); h.rebuildSorted()
        let (hlo, hhi) = h.admittedMask(chanMask: 0xFFFF, cableMask: 0b1111)
        XCTAssertEqual(hlo, 0); XCTAssertEqual(hhi, UInt64(1) << (72 - 64))
        // The CHANNEL/CABLE filter is honoured — a note on an excluded cable is absent.
        let c = NotePool(); c.noteOn(40, velocity: 100, channel: 0, cable: 2); c.rebuildSorted()
        XCTAssertEqual(c.admittedMask(chanMask: 0xFFFF, cableMask: 0b0001).0, 0)          // cable 2 excluded by a cable-1 mask
        XCTAssertEqual(c.admittedMask(chanMask: 0xFFFF, cableMask: 0b0010).0, UInt64(1) << 40)
    }

    func testHoldCaptureDecisionReplacesNewChords() {
        let A: UInt64 = 0b111, B: UInt64 = 0b111000     // two disjoint 3-note chords (lo word)
        // Fresh arm (releasing=true): the first press REPLACES.
        XCTAssertEqual(holdCaptureDecision(prevLo: 0, prevHi: 0, curLo: A, curHi: 0, releasing: true).action, .replace)
        // Same chord still forming (add, no release) → UNION (staggered onset builds up).
        XCTAssertEqual(holdCaptureDecision(prevLo: 0b1, prevHi: 0, curLo: 0b11, curHi: 0, releasing: false).action, .union)
        // A → B via SILENCE: A released (keep, releasing set), then B struck → REPLACE.
        let rel = holdCaptureDecision(prevLo: A, prevHi: 0, curLo: 0, curHi: 0, releasing: false)
        XCTAssertEqual(rel.action, .keep); XCTAssertTrue(rel.releasing)
        XCTAssertEqual(holdCaptureDecision(prevLo: 0, prevHi: 0, curLo: B, curHi: 0, releasing: rel.releasing).action, .replace)
        // A → B as a SAME-RENDER swap (release + add together, same 3-note COUNT) → REPLACE (count alone would miss this).
        XCTAssertEqual(holdCaptureDecision(prevLo: A, prevHi: 0, curLo: B, curHi: 0, releasing: false).action, .replace)
        // TWO different notes replacing the last chord (Paul's exact report) → REPLACE.
        XCTAssertEqual(holdCaptureDecision(prevLo: A, prevHi: 0, curLo: 0b11000, curHi: 0, releasing: false).action, .replace)
        // A pure release (no add) → KEEP the frozen chord, arm releasing.
        let pr = holdCaptureDecision(prevLo: A, prevHi: 0, curLo: 0b1, curHi: 0, releasing: false)
        XCTAssertEqual(pr.action, .keep); XCTAssertTrue(pr.releasing)
        // A note-for-note RESTRIKE of the SAME chord (no net add/remove) → KEEP (the held chord survives).
        XCTAssertEqual(holdCaptureDecision(prevLo: A, prevHi: 0, curLo: A, curHi: 0, releasing: false).action, .keep)
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
    func testEuclidTiltPatternIsANoOpAtZero() {
        var buf = euclidPattern(pulses: 3, steps: 8)
        let before = buf
        euclidTiltPattern(&buf, pulses: 3, steps: 8, tilt: 0)
        XCTAssertEqual(buf, before, "tilt=0 must be byte-identical to not calling this at all")
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
    // EUCLIDEOUS INVERT (Paul 2026-10-05) — the explicit acceptance case the plan's own validation pass called
    // out as the one most likely to silently regress: a FRESH, hit-only lane (missNoteSel == nil, the engine's
    // "MISS feature off" sentinel) inverted must go SILENT on the hit side and SOUND on the miss side — not
    // leave the hit side audible via the legacy target/pick fallback (`noteSelResolved` resolves a bare
    // `noteSel == nil` to `.all`, NOT silence, which is why a naive field-swap would be wrong here).
    func testEuclideousInvertSilencesAFreshHitOnlyLane() {
        let fresh = EuclidLine(target: 0, pulses: 4, steps: 8, noteSel: .low, gate: 0.6, octave: 1, velocity: 0.8)
        XCTAssertNil(fresh.missNoteSel, "sanity: a fresh lane has never touched MISS")
        let inverted = euclideousInvertLine(fresh)
        XCTAssertEqual(inverted.velocityResolved, 0, "the HIT side must go silent — not fall through to the legacy ALL default")
        XCTAssertEqual(inverted.missNoteSel, .low, "the MISS side now carries what used to be the HIT side's own pick")
        XCTAssertEqual(inverted.missVelocityResolved, 0.8, accuracy: 1e-9, "...and its velocity")
        XCTAssertEqual(inverted.missGateResolved, 0.6, accuracy: 1e-9)
        XCTAssertEqual(inverted.missOctaveResolved, 1)
    }
    // Inverting TWICE must be a no-op in every OBSERVABLE (resolved) respect — the engine gates MISS purely on
    // `missVelocity > 0` (Router.swift's own guard), so `missNoteSel` staying non-nil after the round trip
    // (rather than returning to its original nil) is an accepted, harmless, purely-cosmetic difference.
    func testEuclideousInvertTwiceRestoresTheOriginalResolvedState() {
        let fresh = EuclidLine(target: 0, pulses: 4, steps: 8, noteSel: .low, gate: 0.6, octave: 1, velocity: 0.8)
        let twice = euclideousInvertLine(euclideousInvertLine(fresh))
        XCTAssertEqual(twice.noteSelResolved, fresh.noteSelResolved)
        XCTAssertEqual(twice.velocityResolved, fresh.velocityResolved, accuracy: 1e-9)
        XCTAssertEqual(twice.gateResolved, fresh.gateResolved, accuracy: 1e-9)
        XCTAssertEqual(twice.octaveResolved, fresh.octaveResolved)
        XCTAssertEqual(twice.missVelocityResolved, 0, "the MISS side is silent again too — the round trip is a genuine no-op, not just hit-side-identical")
    }
    // A lane with BOTH sides already configured (not Euclideous's own fresh-lane default) swaps symmetrically —
    // no special-casing needed once ensureMissDefaults's invariant already holds.
    func testEuclideousInvertSwapsBothFullyConfiguredSides() {
        var line = EuclidLine(target: 0, pulses: 4, steps: 8, noteSel: .high, gate: 0.9, octave: -1, velocity: 1.2)
        line.missNoteSel = .low; line.missVelocity = 0.4; line.missGate = 0.5; line.missOctave = 2
        let inverted = euclideousInvertLine(line)
        XCTAssertEqual(inverted.noteSelResolved, .low); XCTAssertEqual(inverted.velocityResolved, 0.4, accuracy: 1e-9)
        XCTAssertEqual(inverted.gateResolved, 0.5, accuracy: 1e-9); XCTAssertEqual(inverted.octaveResolved, 2)
        XCTAssertEqual(inverted.missNoteSel, .high); XCTAssertEqual(inverted.missVelocityResolved, 1.2, accuracy: 1e-9)
        XCTAssertEqual(inverted.missGateResolved, 0.9, accuracy: 1e-9); XCTAssertEqual(inverted.missOctaveResolved, -1)
    }
    func testEuclideousStepNoteSelCyclesAndWraps() {
        XCTAssertEqual(euclideousStepNoteSel(.all, by: 1), .n1)
        XCTAssertEqual(euclideousStepNoteSel(.all, by: -1), euclideousNoteSelCycle.last)
        XCTAssertFalse(euclideousNoteSelCycle.contains(.riff), ".riff must never appear in the cycle — Euclideous's cell has no preceding slot, so it would silently go silent")
        XCTAssertFalse(euclideousNoteSelCycle.contains(.arp), "same for .arp")
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
    func testBurstFractionsCountFirstZeroAndCurve() {
        XCTAssertEqual(burstFractions(count: 4, curve: 0), [0, 0.25, 0.5, 0.75], "even spacing at curve 0")
        XCTAssertEqual(burstFractions(count: 4, curve: 0).first, 0, "first strike at step entry")
        let accel = burstFractions(count: 5, curve: 1)
        XCTAssertGreaterThan(accel[1] - accel[0], accel[4] - accel[3], "ACCEL: gaps shrink over the roll")
        let decel = burstFractions(count: 5, curve: -1)
        XCTAssertLessThan(decel[1] - decel[0], decel[4] - decel[3], "DECEL: gaps grow over the roll")
    }

    // BURST PATTERN + CARRY (Paul 2026-08-19): a burst's SPAN = 1 + its contiguous CARRY run; COIN is seeded per step.
    func testBurstCarryRunRotateAndCoin() {
        let pat: [BurstSlice] = [.burst, .carry, .carry, .rest, .burst, .rest, .rest, .rest]
        XCTAssertEqual(burstCarryRun(pat, at: 0, rotate: 0), 3, "B·C·C → span 3 slices")
        XCTAssertEqual(burstCarryRun(pat, at: 1, rotate: 0), 0, "a CARRY slice launches nothing (consumed by the burst)")
        XCTAssertEqual(burstCarryRun(pat, at: 3, rotate: 0), 0, "REST launches nothing")
        XCTAssertEqual(burstCarryRun(pat, at: 4, rotate: 0), 1, "a lone BURST → span 1")
        XCTAssertEqual(burstSliceAt(pat, 1, rotate: 1), .burst, "ROTATE 1 slides the figure: slice 1 reads slice 0")
        XCTAssertTrue(burstCoinFires(step: 0, chance: 1), "chance 1 always fires")
        XCTAssertFalse(burstCoinFires(step: 0, chance: 0), "chance 0 never fires")
        XCTAssertEqual(burstCoinFires(step: 5, chance: 0.5), burstCoinFires(step: 5, chance: 0.5), "deterministic per step")
    }
    // rtcCoinSize's zero/empty-weight FALLBACK (its own comment says "guarded anyway"): with no positive weight
    // there's nothing to pick, so it returns the first size. The existing tests always pass a non-zero weight.
    func testRtcCoinSizeFallsBackWhenWeightsAreZeroOrEmpty() {
        XCTAssertEqual(rtcCoinSize(step: 7, weights: [0, 0, 0, 0, 0]), rtcCoinSizes[0], "all-zero weights → the first size (no divide-by-zero)")
        XCTAssertEqual(rtcCoinSize(step: 3, weights: []), rtcCoinSizes[0], "empty weights → the first size")
    }
    // weaveRate's DRAWN/EUCLID fallback (those modes drive their own emitter clock) + the negative-rank clamp +
    // the 0.03125 floor — none exercised by the ladder/harmonic tests.
    func testWeaveRateDrawnEuclidAndNegativeRank() {
        XCTAssertEqual(weaveRate(mode: .drawn, baseBeats: 0.5, rank: 3), 0.5, accuracy: 1e-9, "DRAWN falls back to baseBeats")
        XCTAssertEqual(weaveRate(mode: .euclid, baseBeats: 0.25, rank: 7), 0.25, accuracy: 1e-9, "EUCLID too")
        XCTAssertEqual(weaveRate(mode: .ladder, baseBeats: 1.0, rank: -5), 1.0, accuracy: 1e-9, "a negative rank clamps to 0 → base ÷ 2^0")
        XCTAssertEqual(weaveRate(mode: .ladder, baseBeats: 0.03, rank: 10), 0.03125, accuracy: 1e-9, "a deep ladder rank hits the 1/32-beat floor")
    }
    func testAsPlayedHonoursCableMask() {
        let p = NotePool()
        p.noteOn(67, velocity: 100, channel: 0, cable: 2)   // press order: 67 …
        p.noteOn(60, velocity: 100, channel: 0, cable: 1)   //              60 (different cable) …
        p.noteOn(64, velocity: 100, channel: 0, cable: 2)   //              64
        p.rebuildSorted()
        XCTAssertEqual(p.srcPlayed(0, filter: 0, cableMask: 0b0010), 67)     // press-order through cable 2 skips 60
        XCTAssertEqual(p.srcPlayed(1, filter: 0, cableMask: 0b0010), 64)
        XCTAssertEqual(p.srcPlayed(2, filter: 0, cableMask: 0b0010), 255)
    }

    // The RANGE-windowed AS-PLAYED reader (Derivations srcPlayed(noteLo:noteHi:)): press order preserved, notes
    // outside [lo,hi] skipped — an AS-PLAYED arp on a range-narrowed receiver.
    func testAsPlayedRangeWindowSkipsOutOfWindowNotesInPressOrder() {
        let p = NotePool()
        p.noteOn(67, velocity: 100, channel: 0, cable: 0)   // press order: 67 …
        p.noteOn(60, velocity: 100, channel: 0, cable: 0)   //              60 (below the window) …
        p.noteOn(72, velocity: 100, channel: 0, cable: 0)   //              72
        p.rebuildSorted()
        // window [62,127] excludes 60; press order kept → 67 then 72
        XCTAssertEqual(p.srcPlayed(0, filter: 0, cableMask: 0b1111, noteLo: 62, noteHi: 127), 67)
        XCTAssertEqual(p.srcPlayed(1, filter: 0, cableMask: 0b1111, noteLo: 62, noteHi: 127), 72)
        XCTAssertEqual(p.srcPlayed(2, filter: 0, cableMask: 0b1111, noteLo: 62, noteHi: 127), 255)
        // a tighter high bound [62,70] now also excludes 72 → only 67 remains
        XCTAssertEqual(p.srcPlayed(0, filter: 0, cableMask: 0b1111, noteLo: 62, noteHi: 70), 67)
        XCTAssertEqual(p.srcPlayed(1, filter: 0, cableMask: 0b1111, noteLo: 62, noteHi: 70), 255)
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

    // mergeFiltered (KEYS/REPLAY/FILE live-along, Paul 2026-08-23): live notes on the door's ENABLED channels layer
    // ONTO a frozen pool WITHOUT clearing it, channel-preserving; a disabled channel is dropped; a duplicate pitch
    // stays one entry (last-writer). Contrast captureFiltered, which resets first.
    func testMergeFilteredLayersLiveOntoFrozenAndRespectsChannel() {
        let frozen = NotePool()                                   // the "loop/clip/keyboard" pick
        frozen.noteOn(60, velocity: 90, channel: 0)              // C on wire ch 1 (filter/channel 0)
        frozen.rebuildSorted()
        let live = NotePool()
        live.noteOn(67, velocity: 100, channel: 0)              // G on ch 1 (door hears it)
        live.noteOn(72, velocity: 100, channel: 2)              // C on ch 3 (door does NOT hear it)
        live.noteOn(60, velocity: 111, channel: 0)             // duplicate of a frozen pitch
        live.rebuildSorted()
        // door mask = channel 1 only (bit 0). Merge live IN — frozen note kept, ch-1 live added, ch-3 live dropped.
        frozen.mergeFiltered(from: live, chanMask: 0x0001, cableMask: 0b1111)
        XCTAssertEqual(frozen.count, 2)                         // 60 (dup collapsed) + 67; 72 excluded by channel
        XCTAssertEqual(frozen.srcCount(chanMask: 0xFFFF), 2)
        XCTAssertEqual(frozen.velocity(67), 100)               // the live G is present
        XCTAssertEqual(frozen.velocity(72), 0)                 // the ch-3 note was NOT admitted
        XCTAssertEqual(frozen.velocity(60), 111)               // duplicate → last-writer (live), still one entry
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

    func testRatchetVelocityFlatWhenRampZero() {
        for i in 0..<4 {
            XCTAssertEqual(ratchetVelocity(base: 96, ramp: 0, index: i, count: 4), 96)
        }
    }

    func testRatchetVelocityCrescendo() {
        // ramp 1: first hit softest, last hit == base, monotonically increasing.
        let vels = (0..<4).map { ratchetVelocity(base: 96, ramp: 1, index: $0, count: 4) }
        XCTAssertLessThan(vels[0], vels[3])
        for i in 1..<4 { XCTAssertGreaterThanOrEqual(vels[i], vels[i - 1]) }
        XCTAssertEqual(vels[3], 96)          // last reaches base
        XCTAssertGreaterThanOrEqual(vels[0], 1)  // never a note-off velocity
    }

    // MARK: strum (§3)

    func testStrumOffsetEndpointsAndMonotonic() {
        let spread = 0.4, K = 5
        XCTAssertEqual(strumOffset(index: 0, count: K, spread: spread, curve: 0), 0, accuracy: 1e-9)
        XCTAssertEqual(strumOffset(index: K - 1, count: K, spread: spread, curve: 0), spread, accuracy: 1e-9)
        var prev = -1.0
        for j in 0..<K {
            let off = strumOffset(index: j, count: K, spread: spread, curve: 0)
            XCTAssertGreaterThan(off, prev); prev = off      // strictly increasing
        }
        // curve 0 is linear
        XCTAssertEqual(strumOffset(index: 2, count: K, spread: spread, curve: 0), spread * 0.5, accuracy: 1e-9)
    }

    func testStrumOffsetSingleNote() {
        XCTAssertEqual(strumOffset(index: 0, count: 1, spread: 0.4, curve: 0), 0)   // nothing to spread
    }

    func testStrumSpreadNormalizeVsPerNoteWidth() {
        let spread = 0.3
        // NORMALIZE (default): a 3-note and a 6-note rake span the SAME total width (`spread`).
        let last3n = strumOffset(index: 2, count: 3, spread: spread, curve: 0, normalize: true)
        let last6n = strumOffset(index: 5, count: 6, spread: spread, curve: 0, normalize: true)
        XCTAssertEqual(last3n, spread, accuracy: 1e-9)
        XCTAssertEqual(last6n, spread, accuracy: 1e-9)
        // PER-NOTE: the gap between onsets is fixed (a 4-note rake matches `spread`), so the width WIDENS
        // with the pool — the 6-note rake is strictly wider than the 3-note one.
        let last3p = strumOffset(index: 2, count: 3, spread: spread, curve: 0, normalize: false)
        let last6p = strumOffset(index: 5, count: 6, spread: spread, curve: 0, normalize: false)
        XCTAssertGreaterThan(last6p, last3p)
        XCTAssertEqual(last3p, (spread / 3.0) * 2.0, accuracy: 1e-9)   // 3 notes → 2 gaps
        XCTAssertEqual(last6p, (spread / 3.0) * 5.0, accuracy: 1e-9)   // 6 notes → 5 gaps (a 4-note rake == spread)
    }

    func testStrumCurveBunchesEnds() {
        // curve>0: early notes bunched (midpoint offset < linear half); curve<0: opposite.
        let mid = { (c: Double) in strumOffset(index: 2, count: 5, spread: 1.0, curve: c) }
        XCTAssertLessThan(mid(1), mid(0))       // positive curve pulls the midpoint earlier
        XCTAssertGreaterThan(mid(-1), mid(0))
    }

    func testStrumVelocityTilt() {
        XCTAssertEqual(strumVelocity(index: 0, count: 4, tilt: 0, base: 96), 96)   // flat
        let up = (0..<4).map { strumVelocity(index: $0, count: 4, tilt: 1, base: 96) }
        XCTAssertLessThan(up[0], up[3])                                            // crescendo
        let down = (0..<4).map { strumVelocity(index: $0, count: 4, tilt: -1, base: 96) }
        XCTAssertGreaterThan(down[0], down[3])                                     // decrescendo
    }

    // MARK: chance (§3)

    func testChanceExtremes() {
        XCTAssertTrue(chancePasses(beat: 3.25, note: 60, probability: 1))    // 100% always passes
        XCTAssertFalse(chancePasses(beat: 3.25, note: 60, probability: 0))   // 0% never passes
    }

    func testChanceIsDeterministic() {
        // Pure function of (beat, note) → loop-consistent (same position, same fate).
        for beat in stride(from: 0.0, through: 8.0, by: 0.25) {
            for note in [48, 60, 72] {
                XCTAssertEqual(chancePasses(beat: beat, note: note, probability: 0.5),
                               chancePasses(beat: beat, note: note, probability: 0.5))
            }
        }
    }

    func testChanceRoughlyHalfAtFifty() {
        var pass = 0, total = 0
        for t in 0..<300 {
            for note in [55, 60, 65] {
                if chancePasses(beat: Double(t) * 0.25, note: note, probability: 0.5) { pass += 1 }
                total += 1
            }
        }
        let frac = Double(pass) / Double(total)
        XCTAssertGreaterThan(frac, 0.42); XCTAssertLessThan(frac, 0.58)   // ~50%, not degenerate
    }

    func testStrumDirection() {
        XCTAssertEqual(strumSortedIndex(position: 0, count: 4, direction: .up, pass: 0), 0)   // low first
        XCTAssertEqual(strumSortedIndex(position: 0, count: 4, direction: .down, pass: 0), 3) // high first
        // ALTERNATE: up on even passes, down on odd
        XCTAssertEqual(strumSortedIndex(position: 0, count: 4, direction: .alternate, pass: 0), 0)
        XCTAssertEqual(strumSortedIndex(position: 0, count: 4, direction: .alternate, pass: 1), 3)
        XCTAssertEqual(strumSortedIndex(position: 0, count: 4, direction: .alternate, pass: 2), 0)
    }

    // MARK: harmonize (§3)

    private func harmonize(_ base: Int, _ intervals: (Int8, Int8, Int8),
                           vel: UInt8 = 96, scale: Double = 0.8) -> (notes: [Int], vels: [UInt8]) {
        var notes = [Int](repeating: 0, count: 4), vels = [UInt8](repeating: 0, count: 4)
        let n = harmonizeVoices(base: base, intervals: intervals, into: &notes,
                                vel: vel, velScale: scale, vels: &vels)
        return (Array(notes[0..<n]), Array(vels[0..<n]))
    }

    func testHarmonizeMajorTriad() {
        // C (60) + [4, 7, 0] → C E G. Root first, then the two non-zero intervals; a 0 voice is off.
        XCTAssertEqual(harmonize(60, (4, 7, 0)).notes, [60, 64, 67])
    }

    func testHarmonizeRootFullAddedScaled() {
        let (notes, vels) = harmonize(60, (7, 0, 0), vel: 100, scale: 0.5)
        XCTAssertEqual(notes, [60, 67])
        XCTAssertEqual(vels[0], 100)   // root full
        XCTAssertEqual(vels[1], 50)    // added voice scaled
    }

    func testHarmonizeNoIntervalsIsIdentity() {
        XCTAssertEqual(harmonize(60, (0, 0, 0)).notes, [60])   // all off → just the root
    }

    func testHarmonizeDeDupesAndClampsRange() {
        // A +12 that lands on a held-elsewhere pitch would refcount; within one call, a unison de-dups.
        XCTAssertEqual(harmonize(60, (0, 12, 12)).notes, [60, 72])   // duplicate +12 collapses
        // out-of-range voices are dropped, root kept
        XCTAssertEqual(harmonize(120, (24, 0, 0)).notes, [120])      // 120+24=144 > 127 → dropped
        XCTAssertEqual(harmonize(5, (-24, 0, 0)).notes, [5])         // 5-24 < 0 → dropped
    }

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

    // THE SCALE DOOR (ratified §1) — the derived KEYS pool from root+scale+range.
    func testScaleNotesRealizesRootScaleAndRange() {
        // C major, 2 octaves from C3 (MIDI 48) = 7 degrees × 2 = 14 notes, ascending, starting at C3.
        let cMaj = scaleNotes(root: 0, type: .major, baseOct: 3, octaves: 2)
        XCTAssertEqual(cMaj.count, 14)
        XCTAssertEqual(cMaj.first, 48)                                   // C3
        XCTAssertEqual(cMaj.prefix(8).map { $0 }, [48, 50, 52, 53, 55, 57, 59, 60])   // C D E F G A B C
        XCTAssertEqual(cMaj, cMaj.sorted())                             // ascending, distinct
        // ROOT shifts the whole set: D major starts on D3 (50) and every note is a pitch class of {D,E,F#,G,A,B,C#}.
        let dMaj = scaleNotes(root: 2, type: .major, baseOct: 3, octaves: 1)
        XCTAssertEqual(dMaj.first, 50)
        let dClasses = Set([2, 4, 6, 7, 9, 11, 1])                      // D E F# G A B C#
        XCTAssertTrue(dMaj.allSatisfy { dClasses.contains($0 % 12) })
        // Pentatonic = 5 per octave; chromatic = 12; whole-tone = 6.
        XCTAssertEqual(scaleNotes(root: 0, type: .majorPentatonic, baseOct: 3, octaves: 2).count, 10)
        XCTAssertEqual(scaleNotes(root: 0, type: .chromatic, baseOct: 3, octaves: 1).count, 12)
        XCTAssertEqual(scaleNotes(root: 0, type: .wholeTone, baseOct: 3, octaves: 1).count, 6)
        // Range clamps: an octaves/baseOct that would run past 127 drops the out-of-MIDI notes (never emits > 127).
        XCTAssertTrue(scaleNotes(root: 0, type: .chromatic, baseOct: 8, octaves: 4).allSatisfy { $0 >= 0 && $0 <= 127 })
        // Clamped inputs: octaves 0 → 1, baseOct 99 → 8 (never traps, always ≥ 1 octave).
        XCTAssertFalse(scaleNotes(root: 0, type: .major, baseOct: 99, octaves: 0).isEmpty)
    }
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
    // AVOID/LOCK (unified 2026-08-31): the declared-key reference mask + the keyFilterNote directions it drives.
    func testScalePitchClassMaskAndKeyFilterDirections() {
        let cMaj = scalePitchClassMask(root: 0, scale: .major)   // C D E F G A B = classes 0,2,4,5,7,9,11
        XCTAssertEqual((cMaj >> 0) & 1, 1, "C is in C major"); XCTAssertEqual((cMaj >> 1) & 1, 0, "C# is not")
        XCTAssertEqual((cMaj >> 4) & 1, 1, "E is in"); XCTAssertEqual((cMaj >> 6) & 1, 0, "F# is not")
        XCTAssertEqual(scalePitchClassMask(root: 2, scale: .major) >> 1 & 1, 1, "D major DOES contain C# (root shifts)")
        // LOCK (only) + REMOVE (block): an out-of-key note drops; in-key passes.
        XCTAssertEqual(keyFilterNote(61, refMask: cMaj, only: true, snap: false), nil, "C#5 out of C major → dropped (LOCK/REMOVE)")
        XCTAssertEqual(keyFilterNote(60, refMask: cMaj, only: true, snap: false), 60, "C5 in key → kept")
        // LOCK + MOVE (snap): C# snaps to the nearest in-key (down ties → C).
        XCTAssertEqual(keyFilterNote(61, refMask: cMaj, only: true, snap: true), 60, "C# snaps to the nearest in-key note (C)")
        // AVOID (minus) + REMOVE: a note whose class IS in the reference drops (dodge the clash).
        XCTAssertEqual(keyFilterNote(60, refMask: scalePitchClassMask(root: 0, scale: .chromatic) & 0b1, only: false, snap: false), nil, "AVOID: a C is removed when C is the clash class")
    }
    // ECHO IN-KEY (Paul 2026-09-29): nextInKeyNote ALWAYS advances to a genuinely different note — unlike
    // keyFilterNote's snap-to-nearest-OR-STAY, an already-in-key note must still move.
    func testNextInKeyNoteAlwaysAdvancesCrossOctaveAndReportsNoLegalMove() {
        let cMaj = scalePitchClassMask(root: 0, scale: .major)   // C D E F G A B = classes 0,2,4,5,7,9,11
        // STRICT ADVANCE: 60 (C) is already in cMaj — keyFilterNote would return 60 unchanged; nextInKeyNote must not.
        XCTAssertEqual(nextInKeyNote(60, refMask: cMaj, dir: 1), 62, "C is already in-key, but the walk still advances — to D, not back to itself")
        XCTAssertEqual(nextInKeyNote(60, refMask: cMaj, dir: -1), 59, "same strict-advance rule going down — to B, not back to C")
        // CROSS-OCTAVE: a one-pitch-class mask (only E) starting AT an E must skip a full octave to reach the next one.
        let onlyE: UInt16 = 1 << 4
        XCTAssertEqual(nextInKeyNote(16, refMask: onlyE, dir: 1), 28, "the only legal note 12 semitones up is the next E, crossing the octave boundary")
        // NO LEGAL MOVE, two different causes, same nil result:
        XCTAssertNil(nextInKeyNote(60, refMask: 0, dir: 1), "an empty reference mask has nothing to walk to")
        XCTAssertNil(nextInKeyNote(60, refMask: cMaj, dir: 0), "dir == 0 means no movement, mirroring echoPitch == 0 in flat mode")
        let onlyC: UInt16 = 1 << 0
        XCTAssertNil(nextInKeyNote(121, refMask: onlyC, dir: 1), "the next C above 121 would be 132 — out of MIDI range, so the walk exhausts and reports no move (a DIFFERENT cause than the empty-mask case, same nil result)")
    }
    // AVOID's "CLASHES" (2026-08-31): the reference mask widens to its ±1 (ic1) / ±2 (ic2) neighbours, so a note a
    // semitone from the reference is dodged too (not just the exact doubling). A SPARSE reference is where it matters.
    func testWidenClashMask() {
        let justC: UInt16 = 1 << 0                                   // only C
        XCTAssertEqual(widenClashMask(justC, semis: 0), justC, "SAME leaves it exact")
        let ic1 = widenClashMask(justC, semis: 1)                    // C + B + C#
        XCTAssertEqual(ic1 & 1, 1); XCTAssertEqual((ic1 >> 11) & 1, 1, "B (below C) clashes"); XCTAssertEqual((ic1 >> 1) & 1, 1, "C# (above C) clashes")
        XCTAssertEqual((ic1 >> 4) & 1, 0, "E does NOT clash with C at ic1")
        let ic2 = widenClashMask(justC, semis: 2)                    // + A# and D
        XCTAssertEqual((ic2 >> 10) & 1, 1, "A# (2 below) at ic2"); XCTAssertEqual((ic2 >> 2) & 1, 1, "D (2 above) at ic2")
        // A note a semitone from the reference: SAME keeps it, CLASH drops it (AVOID = only:false).
        XCTAssertEqual(keyFilterNote(61, refMask: justC, only: false, snap: false), 61, "SAME: C# is not C → kept")
        XCTAssertEqual(keyFilterNote(61, refMask: widenClashMask(justC, semis: 1), only: false, snap: false), nil, "CLASH: C# rubs against C → removed")
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
    // THE KEY FILTER (ratified §3) — MINUS/ONLY × BLOCK/SNAP, pitch-class.
    func testKeyFilterMinusOnlyBlockSnap() {
        let cMajor: UInt16 = 0b101010110101   // C D E F G A B = {0,2,4,5,7,9,11}
        // ONLY + BLOCK: keep in-set, drop out-of-set.
        XCTAssertEqual(keyFilterNote(60, refMask: cMajor, only: true, snap: false), 60, "C is in C major")
        XCTAssertNil(keyFilterNote(61, refMask: cMajor, only: true, snap: false), "C# blocked (out of key)")
        // ONLY + SNAP: out-of-set → nearest in-set (down ties first).
        XCTAssertEqual(keyFilterNote(61, refMask: cMajor, only: true, snap: true), 60, "C# snaps down to C")
        XCTAssertEqual(keyFilterNote(66, refMask: cMajor, only: true, snap: true), 65, "F# snaps to F")
        // MINUS + BLOCK: drop in-set (the complement), keep out-of-set.
        XCTAssertNil(keyFilterNote(60, refMask: cMajor, only: false, snap: false), "C is excluded")
        XCTAssertEqual(keyFilterNote(61, refMask: cMajor, only: false, snap: false), 61, "C# survives the complement")
        // MINUS + SNAP: in-set → nearest NOT-in-set.
        XCTAssertEqual(keyFilterNote(60, refMask: cMajor, only: false, snap: true), 61, "C nudges to the nearest non-scale note")
        // OCTAVE-INDEPENDENT: C in any octave behaves identically.
        XCTAssertEqual(keyFilterNote(72, refMask: cMajor, only: true, snap: false), 72, "C5 in key")
        XCTAssertNil(keyFilterNote(72, refMask: cMajor, only: false, snap: false), "C5 excluded like C4")
        // EMPTY reference: ONLY admits nothing, MINUS excludes nothing.
        XCTAssertNil(keyFilterNote(60, refMask: 0, only: true, snap: true), "ONLY with no reference = silence")
        XCTAssertEqual(keyFilterNote(60, refMask: 0, only: false, snap: false), 60, "MINUS with no reference = pass")
        // ALL 12 classes referenced: MINUS+SNAP has nowhere legal to land → nil (never an out-of-range escape).
        XCTAssertNil(keyFilterNote(60, refMask: 0xFFF, only: false, snap: true), "every class excluded → MINUS snap finds nothing → nil")
        XCTAssertEqual(keyFilterNote(60, refMask: 0xFFF, only: true, snap: false), 60, "every class in the set → ONLY keeps everything")
        // RANGE boundary: a snap near 0/127 must stay in 0…127 and never wrap.
        for n in [0, 1, 126, 127] { if let r = keyFilterNote(n, refMask: cMajor, only: true, snap: true) { XCTAssertTrue((0...127).contains(r), "snap of \(n) stays in range: \(r)") } }
        for n in [0, 1, 126, 127] { if let r = keyFilterNote(n, refMask: cMajor, only: false, snap: true) { XCTAssertTrue((0...127).contains(r), "MINUS snap of \(n) stays in range: \(r)") } }
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

    func testPlaceHoldFirstInColumnAllowed() {
        XCTAssertEqual(placeHoldDecision(placedColumns: [], retoggle: false, col: 2), .allowed)
    }
    func testPlaceHoldSecondInSameColumnBlocked() {
        XCTAssertEqual(placeHoldDecision(placedColumns: [2], retoggle: false, col: 2), .blockedColumnUsed)
    }
    func testPlaceHoldOtherColumnStillFree() {
        XCTAssertEqual(placeHoldDecision(placedColumns: [2], retoggle: false, col: 3), .allowed)
    }
    func testPlaceHoldRetoggleAlwaysAllowed() {
        XCTAssertEqual(placeHoldDecision(placedColumns: [2], retoggle: true, col: 2), .allowed)
    }
    func testPlaceHoldRowFillIsOnePerColumn() {
        var placed = Set<Int>()
        for c in 0..<8 {
            XCTAssertEqual(placeHoldDecision(placedColumns: placed, retoggle: false, col: c), .allowed)
            placed.insert(c)
        }
        XCTAssertEqual(placeHoldDecision(placedColumns: placed, retoggle: false, col: 4), .blockedColumnUsed)
    }

    // (Removed 2026-08-27 housekeeping: the multi-cell ROUTE-FOCI and ROUTING-VISUALISATION-GRAPH tests
    //  (routeFociByColumn / routingEdges / RouteEdge / RouteCell) — the routing-viz overlay was retired with the
    //  tab era and grid-chaining, so those pure helpers have no engine or UI consumer. Tests removed as dead-feature.)

    // MARK: emblems (cells & machine desk)

    func testEmblemForEveryTypeIsDistinctAndNonEmpty() {
        for t in ProcessorType.allCases { XCTAssertFalse(emblemSymbol(t).isEmpty, "\(t) needs an emblem") }
        XCTAssertEqual(Set(ProcessorType.allCases.map(emblemSymbol)).count, ProcessorType.allCases.count, "one distinct glyph per type")
    }

    // MARK: trigger glyph (deviation-shown)

    // (testTriggerMarkDefaultIsNil + testTriggerMarkTapPlusHoldRings removed 2026-08-27: redundant — both branches are
    //  re-asserted by the newer combined testTriggerMarkTapRingAndHoldOnly + testTriggerGlyphTotality below.)
    func testTriggerMarkTapSetsGlyphNoRing() {
        var on = OnConfig(); on.tap = .replay
        let m = triggerMark(on)
        XCTAssertEqual(m?.glyph, "arrow.clockwise"); XCTAssertEqual(m?.ring, false)
    }
    func testTriggerMarkHoldOnlyIsRinged() {
        var on = OnConfig(); on.hold = .freeze
        let m = triggerMark(on)
        XCTAssertEqual(m?.glyph, "snowflake"); XCTAssertEqual(m?.ring, true)
    }
    // (machine census tests removed 2026-08-27: `machineCensus` (the D3 delete-protection helper) has zero non-test
    //  callers — the delete-protection UI was dropped — so the tests guard a dead pure function.)

    // MARK: - THE SEAL (derived cell face)

    private func sealCell() -> Cell {
        var c = Cell(machineID: "gold", buses: [.a, .b]); c.inputReceiver = 1
        c.processors = [ProcessorSlot(type: .harmonize), { var s = ProcessorSlot(type: .arp); s.bypassed = true; return s }()]
        c.chop = Chop(mainMask: 0xFF, altMask: 0b0000_0100, muteMask: 0, altDest: [.c])
        return c
    }
    func testSealHashIsStableAndConfigSensitive() {
        let a = sealCell()
        XCTAssertEqual(sealHash(a, machines: []), sealHash(sealCell(), machines: []), "same config ⇒ same hash (document-visible truth)")
        var chainChanged = a; chainChanged.processors?[0].params.harmIntervals = [7, 0, 0]
        XCTAssertNotEqual(sealHash(a, machines: []), sealHash(chainChanged, machines: []), "a chain-param change ⇒ different seal")
        var inputChanged = a; inputChanged.inputReceiver = 2
        XCTAssertNotEqual(sealHash(a, machines: []), sealHash(inputChanged, machines: []), "an input change ⇒ different seal")
        var outputChanged = a; outputChanged.buses = [.a]
        XCTAssertNotEqual(sealHash(a, machines: []), sealHash(outputChanged, machines: []), "an emitter change ⇒ different seal")
        var chopChanged = a; chopChanged.chop?.muteMask = 0b0001_0000
        XCTAssertNotEqual(sealHash(a, machines: []), sealHash(chopChanged, machines: []), "a chop-mask change ⇒ different seal")
    }
    // BUG (design ferry 2026-08-05): "identical chain + different OUTPUTS must draw DIFFERENT seals." The hash
    // ALREADY covers the full behavioural contract — this locks every twin-equality field the seal must track
    // (output emitter mask · chop ALT-destination "alt set" · input source · source-shaping), so twins + seals can
    // never silently diverge on what "identical" means. (Machine/mute/position stay excluded — tested separately.)
    func testSealHashCoversTheFullTwinContract() {
        let a = sealCell()
        var altDest = a; altDest.chop?.altDest = [.d]                        // OUTPUT: the chop ALT-destination set
        XCTAssertNotEqual(sealHash(a, machines: []), sealHash(altDest, machines: []), "the chop ALT destination is part of the output contract")
        var altMask = a; altMask.chop?.altMask = 0b0000_1000                 // OUTPUT: the chop ALT slice mask
        XCTAssertNotEqual(sealHash(a, machines: []), sealHash(altMask, machines: []), "the chop ALT mask is part of the output contract")
        var inRow = a; inRow.inputRow = 3                                    // SOURCE: input row reference
        XCTAssertNotEqual(sealHash(a, machines: []), sealHash(inRow, machines: []), "the input row is part of the source contract")
        var split = a; split.chordSplit = { var cs = ChordSplit(); cs.n = 3; return cs }()   // SOURCE: chord split
        XCTAssertNotEqual(sealHash(a, machines: []), sealHash(split, machines: []), "the chord split is part of the source contract")
        var vw = a; vw.velWindow = VelWindow(floor: 40, ceil: 100)          // SOURCE: velocity window
        XCTAssertNotEqual(sealHash(a, machines: []), sealHash(vw, machines: []), "the velocity window is part of the source contract")
    }

    // An AUTHORED passthrough (processors == []) resolves to [] and must NOT share a face with a cell drawn from the
    // machine's A face (processors == nil). Guards the resolvedCellChain branch at Derivations:905 — the "seal cannot
    // be dressed" contract would break if [] fell through to the machine's machine.
    func testExplicitEmptyChainResolvesEmptyAndSealsDistinctFromAFaceCell() {
        let machines = [Machine(machineID: "gold", type: .arp)]
        var authored = Cell(machineID: "gold", buses: [.a]); authored.processors = []       // explicit passthrough
        let aFace = Cell(machineID: "gold", buses: [.a])                                      // processors == nil → the machine's .arp
        XCTAssertTrue(resolvedCellChain(authored, machines: machines).isEmpty, "an explicit [] override stays empty")
        XCTAssertEqual(resolvedCellChain(aFace, machines: machines).first?.type, .arp, "nil falls through to the A face")
        XCTAssertNotEqual(sealHash(authored, machines: machines), sealHash(aFace, machines: machines),
                          "an authored passthrough must not wear a full-processor cell's face")
    }
    // DEVICE REPORT (Paul, 2026-08-05): cell→A and cell→B (same COUNT of emitters, DIFFERENT which one) drew the
    // SAME seal, while A+B vs A differed. Pin that different SINGLE emitters ⇒ a different hash AND a different DRAWN
    // seal (geometry), for all of A/B/C/D — the count-invariant case the earlier tests missed.
    func testSealDistinguishesWhichSingleEmitter() {
        func cell(_ b: Bus) -> Cell { var c = Cell(machineID: "gold", buses: [b]); c.processors = []; return c }
        let hA = sealHash(cell(.a), machines: []), hB = sealHash(cell(.b), machines: [])
        XCTAssertNotEqual(hA, hB, "A vs B (same count, different emitter) ⇒ different seal HASH")
        XCTAssertNotEqual(sealGeometry(hA), sealGeometry(hB), "A vs B ⇒ different DRAWN seal (geometry), not just hash")
        let hs = [Bus.a, .b, .c, .d].map { sealHash(cell($0), machines: []) }
        XCTAssertEqual(Set(hs).count, 4, "A/B/C/D each ⇒ a distinct seal hash")
        let geos = hs.map { sealGeometry($0) }
        for i in 0..<4 { for j in (i + 1)..<4 {
            XCTAssertNotEqual(geos[i], geos[j], "single emitters \(i) vs \(j) ⇒ visibly distinct seals")
        } }
    }
    func testSealHashExcludesMachineNameMutePosition() {
        let a = sealCell()
        var recoloured = a; recoloured.machineID = "cyan"
        XCTAssertEqual(sealHash(a, machines: []), sealHash(recoloured, machines: []), "machine is the hue block, NOT the seal — same seal")
        var muted = a; muted.muted = true; muted.alt = true; muted.bypassed = true   // transient perform state
        XCTAssertEqual(sealHash(a, machines: []), sealHash(muted, machines: []), "mute/alt/bypassed are chrome — a muted twin still twins")
    }
    func testSealHashBusOrderInvariant() {
        var a = Cell(machineID: "gold", buses: [.a, .c]); a.processors = []
        var b = Cell(machineID: "cyan", buses: [.c, .a]); b.processors = []   // same set, different machine + order
        XCTAssertEqual(sealHash(a, machines: []), sealHash(b, machines: []), "the emitter SET is unordered — config-twins share the seal")
    }
    // The startup/preset "every cell is the same shape" bug: a cell with NIL processors derives its machine from
    // its MACHINE (template/A face), so the seal must hash the RESOLVED chain — different machines ⇒ different seals.
    func testSealHashResolvesTheMachineChainForTemplateCells() {
        var gold = Machine(machineID: "gold", type: .arp); gold.paramsA.pattern = .up; gold.paramsA.rate = .r1_16
        var cyan = Machine(machineID: "cyan", type: .arp); cyan.paramsA.pattern = .upDown; cyan.paramsA.rate = .r1_8
        let cs = [gold, cyan]
        let goldCell = Cell(machineID: "gold", buses: [.a])   // NIL processors → uses gold's A face
        let cyanCell = Cell(machineID: "cyan", buses: [.a])   // NIL processors → uses cyan's A face
        XCTAssertNotEqual(sealHash(goldCell, machines: cs), sealHash(cyanCell, machines: cs),
                          "template/A-face cells reflect their machine's machine → different machines ⇒ different seals")
        XCTAssertEqual(sealHash(goldCell, machines: cs), sealHash(Cell(machineID: "gold", buses: [.a]), machines: cs),
                       "same machine, no override ⇒ same seal (twins)")
        var override = Cell(machineID: "gold", buses: [.a]); override.processors = [ProcessorSlot(type: .ratchet)]
        XCTAssertNotEqual(sealHash(goldCell, machines: cs), sealHash(override, machines: cs), "a per-cell OVERRIDE changes the seal")
    }
    // GEOMETRY: same hash ⇒ identical geometry (twins share the seal); the route obeys the §2 grammar.
    func testSealGeometryIsDeterministicAndTwinShared() {
        let h = sealHash(sealCell(), machines: [])
        XCTAssertEqual(sealGeometry(h), sealGeometry(h), "same hash ⇒ identical seal")
        XCTAssertEqual(sealGeometry(sealHash(sealCell(), machines: [])), sealGeometry(h), "recomputed config ⇒ identical seal")
    }
    func testSealGeometryObeysLatticeGrammar() {
        for raw in stride(from: UInt32(0), to: 4096, by: 7) {
            let g = sealGeometry(raw)
            XCTAssertGreaterThanOrEqual(g.nodes.count, 2, "at least a start + one move")
            XCTAssertLessThanOrEqual(g.nodes.count, 5, "≤4 moves ⇒ ≤5 nodes")
            XCTAssertEqual(g.arcAtNode.count, g.nodes.count, "one corner flag per node")
            XCTAssertFalse(g.arcAtNode.first ?? true, "the start terminal is never a corner")
            XCTAssertFalse(g.arcAtNode.last ?? true, "the end terminal is never a corner")
            for n in g.nodes {   // every node on the 3×3 lattice
                XCTAssertTrue(n.x >= 0 && n.x <= 2 && n.y >= 0 && n.y <= 2, "node in bounds")
            }
            for i in 1..<g.nodes.count {   // orthogonal unit steps only, no immediate backtrack
                let d = g.nodes[i] - g.nodes[i - 1]
                XCTAssertEqual(abs(d.x) + abs(d.y), 1, "each move is one orthogonal step")
                if i >= 2 { XCTAssertFalse(d == -(g.nodes[i - 1] - g.nodes[i - 2]), "no immediate backtrack") }
            }
            let xr = (g.nodes.map { $0.x }.max() ?? 0) - (g.nodes.map { $0.x }.min() ?? 0)
            XCTAssertGreaterThanOrEqual(xr, 1, "the route spans across horizontally (edge start + forced entry) → fills the length")
            if g.coilNode >= 0 { XCTAssertTrue(g.coilNode >= 1 && g.coilNode <= g.nodes.count - 2, "coil straddles a mid node") }
        }
    }
    func testSealCoilOnlyWhenHashDivisibleByFour() {
        // The coil gate is hash % 4 == 0 (and needs interior nodes) — no coil otherwise.
        for raw in stride(from: UInt32(1), to: 400, by: 1) where raw % 4 != 0 {
            XCTAssertEqual(sealGeometry(raw).coilNode, -1, "hash%4≠0 ⇒ never a coil")
        }
    }
    func testSealCoilPositiveBranchLandsOnAMidNode() {
        // The POSITIVE branch: some gated hash DOES produce a coil, and it straddles a mid-route node (1…len-2).
        var produced = false
        for raw in stride(from: UInt32(0), to: 4096, by: 4) {   // hash%4==0 candidates
            let g = sealGeometry(raw)
            guard g.coilNode >= 0 else { continue }
            produced = true
            XCTAssertGreaterThan(g.nodes.count, 2, "a coil implies interior nodes exist")
            XCTAssertTrue(g.coilNode >= 1 && g.coilNode <= g.nodes.count - 2, "the coil straddles a mid-route node")
        }
        XCTAssertTrue(produced, "the coil POSITIVE branch is exercised (a coil IS produced for some gated hash)")
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

    /// Note → name uses a 0-based octave (note 0 = C0 … 127 = G10). Locked so a future "C4=60" convention
    /// change (RackMatrix uses a different one, deliberately) can't silently drift THIS shared helper.
    func testMidiNoteNameUsesNonNegativeOctaves() {
        XCTAssertEqual(midiNoteName(0), "C0")
        XCTAssertEqual(midiNoteName(60), "C5")       // NOT C4 — this helper is 0-based on purpose
        XCTAssertEqual(midiNoteName(61), "C#5")
        XCTAssertEqual(midiNoteName(69), "A5")
        XCTAssertEqual(midiNoteName(127), "G10")
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

    /// Every ON-TAP / ON-HOLD case yields a glyph EXCEPT `.none` (which is nil) — totality, so a new case
    /// can't silently render blank (mirrors the emblemSymbol totality lock).
    func testTriggerGlyphTotality() {
        for t in OnTap.allCases {
            let g = triggerTapGlyph(t)
            XCTAssertEqual(g == nil, t == .none, "only .none has no tap glyph")
            if t != .none { XCTAssertFalse(g!.isEmpty) }
        }
        for h in OnHold.allCases {
            let g = triggerHoldGlyph(h)
            XCTAssertEqual(g == nil, h == .none, "only .none has no hold glyph")
            if h != .none { XCTAssertFalse(g!.isEmpty) }
        }
    }

    /// The single cell-face mark: a tap glyph is ringed only if a hold is ALSO set; a HOLD-ONLY config shows the
    /// HOLD glyph, always ringed; both default → no mark.
    func testTriggerMarkTapRingAndHoldOnly() {
        XCTAssertNil(triggerMark(OnConfig()))                                   // unassigned → no mark
        let tapOnly = triggerMark(OnConfig(tap: .mute))
        XCTAssertEqual(tapOnly?.glyph, "speaker.slash.fill"); XCTAssertEqual(tapOnly?.ring, false)
        let tapAndHold = triggerMark(OnConfig(tap: .mute, hold: .oct))
        XCTAssertEqual(tapAndHold?.glyph, "speaker.slash.fill"); XCTAssertEqual(tapAndHold?.ring, true)   // hold rings the tap glyph
        let holdOnly = triggerMark(OnConfig(hold: .oct))
        XCTAssertEqual(holdOnly?.glyph, "arrow.up.arrow.down"); XCTAssertEqual(holdOnly?.ring, true)      // hold-only → hold glyph, ringed
    }

    // MARK: - NotePool.heldVelocity — the BYPASS direct-injection read

    /// heldVelocity returns the held velocity (0 when not held) — the read the bypass injection pass keys on.
    func testHeldVelocityReadsPoolVelocity() {
        let p = NotePool()
        p.noteOn(60, velocity: 111, channel: 0)
        XCTAssertEqual(p.heldVelocity(60), 111)
        XCTAssertEqual(p.heldVelocity(64), 0, "an un-held note reads 0")
        p.noteOff(60)
        XCTAssertEqual(p.heldVelocity(60), 0, "released → 0")
    }

    // MARK: - THE MOD PROCESSOR (CC generator) — pure shape values

    func testModTriangleAndSquare() {
        XCTAssertEqual(modUnipolar(.triangle, phase: 0,    column: 0, cc: 1, cycleIndex: 0), 0,   accuracy: 1e-9)
        XCTAssertEqual(modUnipolar(.triangle, phase: 0.5,  column: 0, cc: 1, cycleIndex: 0), 1,   accuracy: 1e-9)
        XCTAssertEqual(modUnipolar(.triangle, phase: 0.25, column: 0, cc: 1, cycleIndex: 0), 0.5, accuracy: 1e-9)
        XCTAssertEqual(modUnipolar(.square, phase: 0.1, column: 0, cc: 1, cycleIndex: 0), 1, "first half HIGH")
        XCTAssertEqual(modUnipolar(.square, phase: 0.9, column: 0, cc: 1, cycleIndex: 0), 0, "second half LOW")
    }
    func testModFollowUnipolar() {
        XCTAssertEqual(modFollowUnipolar(.count, count: 0, meanNote: 0, meanVel: 0), 0, accuracy: 1e-9)
        XCTAssertEqual(modFollowUnipolar(.count, count: 4, meanNote: 60, meanVel: 100), 0.5, accuracy: 1e-9)
        XCTAssertEqual(modFollowUnipolar(.count, count: 8, meanNote: 60, meanVel: 100), 1.0, accuracy: 1e-9)
        XCTAssertEqual(modFollowUnipolar(.register, count: 1, meanNote: 60, meanVel: 100), (60.0 - 24) / 72, accuracy: 1e-9)
        XCTAssertEqual(modFollowUnipolar(.register, count: 0, meanNote: 60, meanVel: 100), 0, "no notes → 0")
        XCTAssertEqual(modFollowUnipolar(.vel, count: 1, meanNote: 60, meanVel: 127), 1.0, accuracy: 1e-9)
    }
    func testModStepsPattern() {
        let steps = [0, 127, 0, 127, 0, 127, 0, 127]
        XCTAssertEqual(modStepsUnipolar(steps, phase: 0.01,  smooth: false), 0, accuracy: 1e-9, "step 0 low")
        XCTAssertEqual(modStepsUnipolar(steps, phase: 0.13,  smooth: false), 1, accuracy: 1e-9, "step 1 high")
        XCTAssertEqual(modStepsUnipolar(steps, phase: 0.0625, smooth: true), 0.5, accuracy: 0.05, "SMOOTH interpolates between steps")
    }
    // columnStart floors a beat to the step grid (the shared spelling of the Router's column-start idiom).
    func testRollLaneForPitchMapsC2ToC6IntoUnitRangeClamped() {
        XCTAssertEqual(rollLaneForPitch(36), 0.0, accuracy: 1e-9, "C2 → bottom")
        XCTAssertEqual(rollLaneForPitch(84), 1.0, accuracy: 1e-9, "C6 → top")
        XCTAssertEqual(rollLaneForPitch(60), 0.5, accuracy: 1e-9, "C4 → middle")
        XCTAssertEqual(rollLaneForPitch(24), 0.0, accuracy: 1e-9, "below C2 clamps to 0")
        XCTAssertEqual(rollLaneForPitch(120), 1.0, accuracy: 1e-9, "above C6 clamps to 1")
    }

    func testColumnStartFloorsToTheStepGrid() {
        XCTAssertEqual(columnStart(0.0, 0.5), 0.0, accuracy: 1e-9)
        XCTAssertEqual(columnStart(0.49, 0.5), 0.0, accuracy: 1e-9)
        XCTAssertEqual(columnStart(0.5, 0.5), 0.5, accuracy: 1e-9)
        XCTAssertEqual(columnStart(1.3, 0.5), 1.0, accuracy: 1e-9)
        XCTAssertEqual(columnStart(2.0, 1.0), 2.0, accuracy: 1e-9)
        XCTAssertEqual(columnStart(2.9, 1.0) + 1.0, 3.0, accuracy: 1e-9, "the +S end-of-column form")
    }
    // .density is the v1 pool-fullness proxy (count/8, clamped) — documents the interim so a true event-rate change shows as a test edit.
    func testModFollowDensityProxy() {
        XCTAssertEqual(modFollowUnipolar(.density, count: 4, meanNote: 60, meanVel: 100), 0.5, accuracy: 1e-9)
        XCTAssertEqual(modFollowUnipolar(.density, count: 8, meanNote: 60, meanVel: 100), 1.0, accuracy: 1e-9)
        XCTAssertEqual(modFollowUnipolar(.density, count: 16, meanNote: 60, meanVel: 100), 1.0, accuracy: 1e-9, "clamped at 1")
    }
    // modStepsUnipolar generalises to N steps (8/16/32 by SPAN, Paul 2026-08-20): empty → 0; a 16-step ROW×2 sequence
    // addresses breakpoints the old 8-cap couldn't reach; SMOOTH wraps the last step → the first via (i+1)%N.
    func testModStepsUnipolarNStepsAndWrap() {
        XCTAssertEqual(modStepsUnipolar([], phase: 0.5, smooth: false), 0, accuracy: 1e-9, "empty → 0")
        var s16 = [Int](repeating: 0, count: 16); s16[9] = 127
        XCTAssertEqual(modStepsUnipolar(s16, phase: 9.5 / 16, smooth: false), 1, accuracy: 1e-9, "16-step: breakpoint 9 is reachable")
        XCTAssertEqual(modStepsUnipolar(s16, phase: 3.0 / 16, smooth: false), 0, accuracy: 1e-9, "16-step: breakpoint 3 is low")
        let steps = [0, 0, 0, 0, 0, 0, 0, 127]
        XCTAssertEqual(modStepsUnipolar(steps, phase: 0.9375, smooth: true), 0.5, accuracy: 0.02, "SMOOTH wraps step 7 → step 0 (8-step)")
    }
    // §2 INTERNAL TARGET (Paul 2026-08-20): applyModChainOffset adds to the base param + clamps to its range; the span
    // scales a full MIN..MAX MOD sweep to the param's whole range.
    func testApplyModChainOffsetAddsAndClamps() {
        var p = SnapParams(); p.gate = 0.5; p.curve = 0; p.spread = 0.9
        XCTAssertEqual(applyModChainOffset(p, param: .gate, offset: 0.3).gate, 0.8, accuracy: 1e-9, "adds to base")
        XCTAssertEqual(applyModChainOffset(p, param: .gate, offset: 5).gate, 1.0, accuracy: 1e-9, "clamps to the param max")
        XCTAssertEqual(applyModChainOffset(p, param: .curve, offset: -3).curve, -1.0, accuracy: 1e-9, "curve clamps to −1")
        XCTAssertEqual(applyModChainOffset(p, param: .spread, offset: 0.5).spread, 1.0, accuracy: 1e-9, "spread clamps to 1")
        XCTAssertEqual(applyModChainOffset(p, param: .gate, offset: 0).gate, 0.5, accuracy: 1e-9, "zero offset = no change")
        XCTAssertEqual(macroParamSpan(.curve), 2.0, "−1…1")
        XCTAssertEqual(macroParamSpan(.modMin), 127.0, "0…127")
        XCTAssertEqual(macroParamSpan(.gate), 1.0, "0…1")
    }
    // ccDefault — the resting value a MOD target reverts to when abandoned (so a sweep past CC7 doesn't leave volume down).
    func testCcDefaultRestingValues() {
        XCTAssertEqual(ccDefault(7), 127, "volume → full")
        XCTAssertEqual(ccDefault(11), 127, "expression → full")
        XCTAssertEqual(ccDefault(74), 127, "cutoff → full")
        XCTAssertEqual(ccDefault(10), 64, "pan → centre")
        XCTAssertEqual(ccDefault(8), 64, "balance → centre")
        XCTAssertEqual(ccDefault(1), 0, "everything else → off")
        XCTAssertEqual(ccDefault(64), 0, "sustain → off")
    }
    // chancePassesPool: a SINGLE-note pool skips the tilt branch (count > 1) — no divide-by-(count−1) — and equals plain chancePasses.
    func testChancePassesPoolSingleNoteNoTrap() {
        for tilt in [-1.0, 0.0, 0.9] {
            for beat in stride(from: 0.0, through: 1.0, by: 0.25) {
                XCTAssertEqual(chancePassesPool(beat: beat, note: 60, rank: 0, count: 1, probability: 0.5, tilt: tilt, constantDensity: false),
                               chancePasses(beat: beat, note: 60, probability: 0.5),
                               "count 1: tilt is a no-op; equals plain chancePasses")
            }
        }
    }
    func testModStrikeEnvelope() {
        XCTAssertEqual(modStrikeUnipolar(t: 0,    attack: 0.5, release: 1.0), 0,   accuracy: 1e-9)
        XCTAssertEqual(modStrikeUnipolar(t: 0.25, attack: 0.5, release: 1.0), 0.5, accuracy: 1e-9, "rising")
        XCTAssertEqual(modStrikeUnipolar(t: 0.5,  attack: 0.5, release: 1.0), 1.0, accuracy: 1e-9, "peak")
        XCTAssertEqual(modStrikeUnipolar(t: 1.0,  attack: 0.5, release: 1.0), 0.5, accuracy: 1e-9, "falling")
        XCTAssertEqual(modStrikeUnipolar(t: 2.0,  attack: 0.5, release: 1.0), 0,   accuracy: 1e-9, "rests at 0")
    }
    func testGlideBend14() {
        XCTAssertEqual(glideBend14(semitones: 0, range: 2), 8192, "0 st = centre")
        XCTAssertEqual(glideBend14(semitones: 2, range: 2), 16383, "+range = full up")
        XCTAssertEqual(glideBend14(semitones: -2, range: 2), 1, "−range = full down")
        XCTAssertEqual(glideBend14(semitones: 4, range: 2), 16383, "beyond range clamps to full")
    }
    func testGlideNeedsReanchor() {
        XCTAssertFalse(glideNeedsReanchor(target: 62, anchor: 60, range: 2), "2 st within ±2 → glide")
        XCTAssertTrue(glideNeedsReanchor(target: 65, anchor: 60, range: 2), "5 st beyond ±2 → re-anchor")
    }
    func testControllerForwardMask() {
        // Only doors that HEAR the controller contribute; the emitter mask is their union.
        XCTAssertEqual(controllerForwardMask(hearing: [true, false, false, false], masks: [0b0001, 0b1111, 0b1111, 0b1111]), 0b0001, "one door → emitter A")
        XCTAssertEqual(controllerForwardMask(hearing: [true, true, false, false], masks: [0b0001, 0b0010, 0b1111, 0b1111]), 0b0011, "two doors OR their masks")
        XCTAssertEqual(controllerForwardMask(hearing: [false, false, false, false], masks: [0b1111, 0b1111, 0b1111, 0b1111]), 0, "no door hears it → nothing forwards")
    }
    func testIsForwardableController() {
        XCTAssertTrue(isForwardableController(0xB3), "CC")
        XCTAssertTrue(isForwardableController(0xE0), "pitch bend")
        XCTAssertTrue(isForwardableController(0xD5), "channel pressure / AT")
        XCTAssertTrue(isForwardableController(0xC0), "program change")
        XCTAssertFalse(isForwardableController(0x90), "note-on is not a controller")
        XCTAssertFalse(isForwardableController(0xA0), "poly pressure is parked (MPE)")
    }
    func testCCNamedDozen() {
        XCTAssertEqual(ccName(74), "CUTOFF")
        XCTAssertEqual(ccName(1),  "MOD WHEEL")
        XCTAssertEqual(ccName(11), "EXPRESSION")
        XCTAssertNil(ccName(3), "an unnamed CC → nil")
    }
    // QUANTIZE (design-cc-stage §14①, Paul 2026-09-09): snap the 0…127 output to N evenly-spaced levels.
    func testModQuantizeSnapsToLevels() {
        XCTAssertEqual(modQuantizeValue(60, levels: 0), 60, "off (0) = identity")
        XCTAssertEqual(modQuantizeValue(60, levels: 1), 60, "1 level = identity")
        XCTAssertEqual(modQuantizeValue(60, levels: 2), 0, "2 levels: 60 (< midpoint) snaps to 0")
        XCTAssertEqual(modQuantizeValue(70, levels: 2), 127, "2 levels: 70 (> midpoint) snaps to 127")
        XCTAssertEqual(modQuantizeValue(0, levels: 4), 0)
        XCTAssertEqual(modQuantizeValue(127, levels: 4), 127, "the top level is always 127")
        XCTAssertEqual(modQuantizeValue(42, levels: 4), 42, "4 levels: points at 0 · 42 · 85 · 127")
        // every quantized output is one of the level values
        let levels = 5, allowed = Set((0..<levels).map { Int((Double($0) / Double(levels - 1) * 127).rounded()) })
        for v in 0...127 { XCTAssertTrue(allowed.contains(modQuantizeValue(v, levels: levels)), "\(v) snapped outside the level set") }
    }
    func testModSampleHoldIsHeldAndReplaySafe() {
        let a1 = modUnipolar(.sampleHold, phase: 0.1, column: 2, cc: 74, cycleIndex: 5)
        let a2 = modUnipolar(.sampleHold, phase: 0.9, column: 2, cc: 74, cycleIndex: 5)
        XCTAssertEqual(a1, a2, "S&H HOLDS across the cycle (phase-independent)")
        XCTAssertEqual(a1, modUnipolar(.sampleHold, phase: 0.4, column: 2, cc: 74, cycleIndex: 5), "replay-safe: same (column,cc,cycle) → same value")
        let next = modUnipolar(.sampleHold, phase: 0.1, column: 2, cc: 74, cycleIndex: 6)
        XCTAssertNotEqual(a1, next, "S&H picks a NEW value on the next cycle")
    }

    // CHANCE WEIGHT (tilt): the rank-weight term is only ever proven statistically via the Router. Lock its DIRECTION
    // and full-scale magnitude at the pure boundary — at ±1 tilt with count 2 it forces the top/bottom deterministically
    // (p reaches 1/0, which chancePasses short-circuits, so the hash is bypassed). (coverage 2026-08-15)
    func testChancePassesPoolTiltForcesTopAndBottom() {
        for beat in [0.0, 0.25, 0.5, 0.75, 1.0] {
            // +1 tilt favours the TOP (rank 1 of 2 always passes; rank 0 never does)
            XCTAssertTrue(chancePassesPool(beat: beat, note: 60, rank: 1, count: 2, probability: 0.5, tilt: 1.0, constantDensity: false), "+tilt: top note passes @\(beat)")
            XCTAssertFalse(chancePassesPool(beat: beat, note: 60, rank: 0, count: 2, probability: 0.5, tilt: 1.0, constantDensity: false), "+tilt: bottom note drops @\(beat)")
            // −1 tilt favours the BOTTOM — the direction flips exactly
            XCTAssertFalse(chancePassesPool(beat: beat, note: 60, rank: 1, count: 2, probability: 0.5, tilt: -1.0, constantDensity: false), "−tilt: top note drops @\(beat)")
            XCTAssertTrue(chancePassesPool(beat: beat, note: 60, rank: 0, count: 2, probability: 0.5, tilt: -1.0, constantDensity: false), "−tilt: bottom note passes @\(beat)")
        }
    }

    // GLIDE bend: the max(1, range) divide-guard for range ≤ 0 (SnapshotBuilder clamps glideRange ≥ 1, so this is
    // defensive) — range 0 must behave like range 1, never divide by zero. (coverage 2026-08-15)
    func testGlideBend14GuardsNonPositiveRange() {
        XCTAssertEqual(glideBend14(semitones: 0, range: 0), 8192, "centre")
        XCTAssertEqual(glideBend14(semitones: 1, range: 0), 16383, "frac clamps to +1 → full up")
        XCTAssertEqual(glideBend14(semitones: -5, range: 0), 1, "frac clamps to −1 → full down")
    }

    // MARK: - TUTTI (Paul 2026-08-13): SET-level chance primitives — pure, per-step, replay-exact

    func testTuttiBalanceEdges() {
        for s in 0..<50 {
            XCTAssertFalse(tuttiIsTutti(step: s, balance: 0), "balance 0 → always SOLO")
            XCTAssertTrue(tuttiIsTutti(step: s, balance: 1), "balance 1 → always TUTTI")
        }
    }
    func testTuttiRollDeterministic() {   // same step → same fate every call (loop the host → the same steps re-roll identically)
        let a = (0..<64).map { tuttiIsTutti(step: $0, balance: 0.5) }
        let b = (0..<64).map { tuttiIsTutti(step: $0, balance: 0.5) }
        XCTAssertEqual(a, b, "the per-step roll is a pure function of the step index")
    }
    func testTuttiBalanceRoughDistribution() {
        let half = Double((0..<2000).filter { tuttiIsTutti(step: $0, balance: 0.5) }.count) / 2000
        XCTAssert(half > 0.4 && half < 0.6, "balance 0.5 → ~half the steps TUTTI (got \(half))")
        let low = Double((0..<2000).filter { tuttiIsTutti(step: $0, balance: 0.2) }.count) / 2000
        XCTAssert(low < 0.32, "balance 0.2 → mostly SOLO (got \(low))")
    }
    func testTuttiSoloPickLowHigh() {
        XCTAssertEqual(tuttiSoloRank(step: 7, count: 4, pick: .low), 0, "LOW = bottom rank")
        XCTAssertEqual(tuttiSoloRank(step: 7, count: 4, pick: .high), 3, "HIGH = top rank")
        for pick in TuttiPick.allCases { XCTAssertEqual(tuttiSoloRank(step: 3, count: 1, pick: pick), 0, "a singleton is degenerate → rank 0") }
    }
    func testTuttiSoloCycleWalks() {
        XCTAssertEqual((0..<9).map { tuttiSoloRank(step: $0, count: 3, pick: .cycle) },
                       [0,1,2,0,1,2,0,1,2], "CYCLE walks the solo one rank per step, wrapping")
    }
    func testTuttiSoloRandomInRangeAndVaries() {
        var seen = Set<Int>()
        for s in 0..<200 {
            let r = tuttiSoloRank(step: s, count: 5, pick: .random)
            XCTAssert(r >= 0 && r < 5, "RANDOM rank in [0,count)")
            seen.insert(r)
        }
        XCTAssert(seen.count >= 3, "RANDOM visits multiple ranks (got \(seen.count) distinct)")
    }
    func testTuttiMacroParamsRoundTrip() {   // the euclid lesson: advertised params must survive the get→set round-trip
        var slot = ProcessorSlot(type: .tutti)
        slot.params.tuttiMode = .pattern; slot.params.tuttiBalance = 0.8; slot.params.tuttiPick = .cycle
        let back = applyProcessorValues(processorValues(slot), to: ProcessorSlot(type: .tutti))
        XCTAssertEqual(back.params.tuttiMode, .pattern)
        XCTAssertEqual(back.params.tuttiBalance ?? 0, 0.8, accuracy: 1e-9)
        XCTAssertEqual(back.params.tuttiPick, .cycle)
    }
    func testTuttiEngineSoloEmitsOneTuttiEmitsAll() {   // through the REAL Router (the offline probe holds C-E-G)
        var solo = ProcessorSlot(type: .tutti); solo.params.tuttiMode = .coin; solo.params.tuttiBalance = 0; solo.params.tuttiPick = .low
        let soloNotes = Set(Dice.runRecorder([solo]).ons.filter { $0.cable == 1 }.map { $0.note })
        var full = ProcessorSlot(type: .tutti); full.params.tuttiMode = .coin; full.params.tuttiBalance = 1
        let fullNotes = Set(Dice.runRecorder([full]).ons.filter { $0.cable == 1 }.map { $0.note })
        XCTAssertEqual(soloNotes.count, 1, "balance 0 → SOLO → exactly one note sounds (got \(soloNotes.sorted()))")
        XCTAssertEqual(fullNotes.count, 3, "balance 1 → TUTTI → the whole held C-E-G sounds (got \(fullNotes.sorted()))")
        XCTAssertTrue(soloNotes.isSubset(of: fullNotes), "the SOLO note is one of the held set")
    }

    // MARK: - TUTTI PATTERN (phase 2): per-slice set-shapes

    func testTuttiSliceRanksShapes() {
        XCTAssertEqual(tuttiSliceRanks(.all, count: 3).ranks, [0, 1, 2])
        XCTAssertEqual(tuttiSliceRanks(.low, count: 3).ranks, [0])
        XCTAssertEqual(tuttiSliceRanks(.high, count: 3).ranks, [2])
        XCTAssertEqual(tuttiSliceRanks(.top2, count: 3).ranks, [1, 2])
        XCTAssertEqual(tuttiSliceRanks(.bot2, count: 3).ranks, [0, 1])
        XCTAssertEqual(tuttiSliceRanks(.top2, count: 1).ranks, [0], "a singleton is degenerate → rank 0")
        XCTAssertEqual(tuttiSliceRanks(.rest, count: 3).ranks, [], "REST → silence")
        XCTAssertEqual(tuttiSliceRanks(.lowOct, count: 3).octave, 12, "LOW+8 shifts up an octave")
        XCTAssertEqual(tuttiSliceRanks(.allDownOct, count: 3).octave, -12, "ALL−8 shifts down an octave")
        XCTAssertEqual(tuttiSliceRanks(.all, count: 0).ranks, [], "empty set → nothing")
    }
    func testTuttiSliceOfWalksGlobally() {
        XCTAssertEqual(tuttiSliceOf(0.0, sliceBeats: 0.5), 0)
        XCTAssertEqual(tuttiSliceOf(0.5, sliceBeats: 0.5), 1)
        XCTAssertEqual(tuttiSliceOf(1.25, sliceBeats: 0.5), 2)
        XCTAssertEqual(tuttiSliceOf(4.0, sliceBeats: 0.5), 8, "keeps counting (wraps to the 8-array via %8 downstream)")
        XCTAssertEqual(tuttiSliceOf(1.0, sliceBeats: 0), 0, "guards sliceBeats > 0")
    }
    func testTuttiPatternShapesEmitExpectedNotes() {   // through the REAL Router (all 8 slices = one state → shape-independent of the clock)
        func notes(_ state: TuttiSlice) -> Set<UInt8> {
            var s = ProcessorSlot(type: .tutti); s.params.tuttiMode = .pattern
            s.params.tuttiSlices = Array(repeating: state, count: 8); s.params.tuttiRate = .r1_8
            return Set(Dice.runRecorder([s]).ons.filter { $0.cable == 1 }.map { $0.note })
        }
        XCTAssertEqual(notes(.all).count, 3, "ALL → the whole held C-E-G")
        XCTAssertEqual(notes(.high).count, 1, "HIGH → one note")
        XCTAssertEqual(notes(.low).count, 1, "LOW → one note")
        XCTAssertEqual(notes(.top2).count, 2, "TOP2 → two notes")
        XCTAssertEqual(notes(.rest), [], "REST → silence")
        if let l = notes(.low).first, let lo = notes(.lowOct).first {
            XCTAssertEqual(Int(lo) - Int(l), 12, "LOW+8 sounds an octave above LOW")
        } else { XCTFail("LOW / LOW+8 should each sound one note") }
    }

    // MARK: - LENGTH (Paul 2026-08-05): per-slice GATE override — the event model + downstream gate

    func testLengthAllPassIsOneSustain() {
        let e = lengthColumnEvents(slices: Array(repeating: .pass, count: 8), rotate: 0, shortFrac: 0.4, longFrac: 0.7, colStart: 0, S: 4)
        XCTAssertEqual(e.count, 1, "all-PASS = one sustained note")
        XCTAssertEqual(e[0].on, 0, accuracy: 1e-9)
        XCTAssertEqual(e[0].off, 4, accuracy: 1e-9, "sustains to the step end")
    }
    func testLengthAllMuteIsSilent() {
        XCTAssertTrue(lengthColumnEvents(slices: Array(repeating: .mute, count: 8), rotate: 0, shortFrac: 0.4, longFrac: 0.7, colStart: 0, S: 4).isEmpty)
    }
    func testLengthAllShortIsEightStabs() {
        let e = lengthColumnEvents(slices: Array(repeating: .short, count: 8), rotate: 0, shortFrac: 0.5, longFrac: 0.7, colStart: 0, S: 8)   // sliceLen = 1
        XCTAssertEqual(e.count, 8, "8 staccato strikes")
        XCTAssertEqual(e[0].on, 0, accuracy: 1e-9); XCTAssertEqual(e[0].off, 0.5, accuracy: 1e-9, "SHORT gate = 0.5 of a 1-beat slice")
        XCTAssertEqual(e[1].on, 1, accuracy: 1e-9)
    }
    func testLengthLongTiesThroughPassCutByMute() {
        // LONG at 0 (rings to step end), PASS 1–2 (tie), MUTE 3 (cut), PASS 4–7 (resume, sustain to end)
        let s: [LenState] = [.long, .pass, .pass, .mute, .pass, .pass, .pass, .pass]
        let e = lengthColumnEvents(slices: s, rotate: 0, shortFrac: 0.4, longFrac: 1.0, colStart: 0, S: 8)
        XCTAssertEqual(e.count, 2)
        XCTAssertEqual(e[0].on, 0, accuracy: 1e-9); XCTAssertEqual(e[0].off, 3, accuracy: 1e-9, "LONG rings through PASS, cut at the MUTE (slice 3)")
        XCTAssertEqual(e[1].on, 4, accuracy: 1e-9); XCTAssertEqual(e[1].off, 8, accuracy: 1e-9, "PASS resumes after the rest, sustains to end")
    }
    func testLengthGateForDownstream() {
        XCTAssertEqual(lengthGateFor(.mute, onset: 0, shortFrac: 0.4, longFrac: 0.7, S: 8), .drop)
        XCTAssertEqual(lengthGateFor(.pass, onset: 0, shortFrac: 0.4, longFrac: 0.7, S: 8), .keep)
        if case .overrideOff(let o) = lengthGateFor(.short, onset: 0, shortFrac: 0.5, longFrac: 0.7, S: 8) {
            XCTAssertEqual(o, 0.5, accuracy: 1e-9, "SHORT downstream off = onset + 0.5·sliceLen(=1)")
        } else { XCTFail("SHORT should override the off") }
    }
    func testLengthEngineMuteSilentAndShortReArticulates() {   // through the REAL Router (the probe holds C-E-G)
        func ons(_ slices: [LenState]) -> Int {
            var s = ProcessorSlot(type: .length); s.params.lenSlices = slices; s.params.lenShort = 0.4; s.params.lenLong = 0.7
            return Dice.runRecorder([s]).ons.filter { $0.cable == 1 }.count
        }
        XCTAssertEqual(ons(Array(repeating: .mute, count: 8)), 0, "all-MUTE → silence")
        let pass = ons(Array(repeating: .pass, count: 8)), short = ons(Array(repeating: .short, count: 8))
        XCTAssertGreaterThan(pass, 0, "all-PASS → the chord sounds")
        XCTAssertGreaterThan(short, pass, "all-SHORT re-strikes every slice → more note-ons than the tied PASS sustain")
    }

    // MARK: - WEAVE (Paul 2026-08-07): rank-clocked polyrhythm driver

    func testWeaveRateLadderHalvesPerRank() {
        XCTAssertEqual(weaveRate(mode: .ladder, baseBeats: 1.0, rank: 0), 1.0, accuracy: 1e-9)
        XCTAssertEqual(weaveRate(mode: .ladder, baseBeats: 1.0, rank: 1), 0.5, accuracy: 1e-9)
        XCTAssertEqual(weaveRate(mode: .ladder, baseBeats: 1.0, rank: 2), 0.25, accuracy: 1e-9)
    }
    func testWeaveRateHarmonicDividesByRankPlusOne() {
        XCTAssertEqual(weaveRate(mode: .harmonic, baseBeats: 1.2, rank: 0), 1.2, accuracy: 1e-9)
        XCTAssertEqual(weaveRate(mode: .harmonic, baseBeats: 1.2, rank: 1), 0.6, accuracy: 1e-9)
        XCTAssertEqual(weaveRate(mode: .harmonic, baseBeats: 1.2, rank: 2), 0.4, accuracy: 1e-9)
    }
    func testWeaveRateFloorClamped() {
        XCTAssertGreaterThanOrEqual(weaveRate(mode: .ladder, baseBeats: 1.0, rank: 20), 0.03125, "a deep rank can't tick per-sample")
    }
    func testWeaveEngineBassSlowerThanTop() {   // through the REAL Router (the probe holds C-E-G ascending)
        var w = ProcessorSlot(type: .weave); w.params.weaveMode = .ladder; w.params.weaveBaseStep = .r1_4; w.params.weaveSpan = 4
        var byNote: [UInt8: Int] = [:]
        for o in Dice.runRecorder([w]).ons.filter({ $0.cable == 1 }) { byNote[o.note, default: 0] += 1 }
        let notes = byNote.keys.sorted()   // ascending pitch = ascending rank
        XCTAssertEqual(notes.count, 3, "all three held notes weave (got \(notes))")
        if notes.count == 3 {
            XCTAssertLessThan(byNote[notes[0]]!, byNote[notes[2]]!, "the bass (rank 0) ticks slower than the top (rank 2)")
        }
    }
    private func weaveOnsByNote(_ w: ProcessorSlot) -> [UInt8: Int] {
        var byNote: [UInt8: Int] = [:]
        for o in Dice.runRecorder([w]).ons.filter({ $0.cable == 1 }) { byNote[o.note, default: 0] += 1 }
        return byNote
    }
    func testWeaveDrawnRankFollowsItsSlot() {   // phase 2: each rank's own authored rate
        var w = ProcessorSlot(type: .weave); w.params.weaveMode = .drawn; w.params.weaveSpan = 4
        w.params.weaveDrawn = [.r1_1, .r1_8, .r1_8, .r1_8, .r1_8, .r1_8, .r1_8, .r1_8]   // rank 0 slow (4 beats), rank 1 fast (0.5)
        let byNote = weaveOnsByNote(w); let notes = byNote.keys.sorted()
        XCTAssertEqual(notes.count, 3)
        if notes.count == 3 { XCTAssertLessThan(byNote[notes[0]]!, byNote[notes[1]]!, "DRAWN: the bass slot (slow) ticks fewer than rank 1 (fast)") }
    }
    func testWeaveEuclidBassSparserThanTop() {   // phase 2: rank r fills 2r+1 pulses → bass sparse, top dense
        var w = ProcessorSlot(type: .weave); w.params.weaveMode = .euclid; w.params.weaveEuclidSteps = 8; w.params.weaveSpan = 4
        let byNote = weaveOnsByNote(w); let notes = byNote.keys.sorted()
        XCTAssertEqual(notes.count, 3)
        if notes.count == 3 { XCTAssertLessThan(byNote[notes[0]]!, byNote[notes[2]]!, "EUCLID: bass fills fewer pulses than the top") }
    }
    func testWeaveSlowerBaseTicksLess() {   // phase 2: the slower StepRate range
        func ons(_ base: StepRate) -> Int {
            var w = ProcessorSlot(type: .weave); w.params.weaveMode = .ladder; w.params.weaveBaseStep = base; w.params.weaveSpan = 1
            return Dice.runRecorder([w]).ons.filter { $0.cable == 1 }.count
        }
        XCTAssertLessThan(ons(.r2_1), ons(.r1_8), "a 2-bar bass clock ticks far fewer than a 1/8 clock")
    }
    func testWeaveAllPhasesSound() {   // phase 2: RETRIG · FREE · LEGATO all produce output (fuzz proves no stuck notes)
        for ph in ArpPhase.allCases {
            var w = ProcessorSlot(type: .weave); w.params.weaveMode = .ladder; w.params.weavePhase = ph
            XCTAssertGreaterThan(Dice.runRecorder([w]).ons.filter { $0.cable == 1 }.count, 0, "\(ph) weave sounds")
        }
    }

    // MARK: - SPLIT (Paul 2026-08-05): set-membership filter — the three placements

    func testSplitStandaloneKeepsSubset() {   // a held chord filtered to its subset (through the real Router)
        func notes(_ set: ChordSplit) -> Set<UInt8> {
            var s = ProcessorSlot(type: .split); s.params.splitSet = set
            return Set(Dice.runRecorder([s]).ons.filter { $0.cable == 1 }.map { $0.note })
        }
        XCTAssertEqual(notes(ChordSplit(mode: .all)).count, 3, "ALL keeps the whole chord")
        XCTAssertEqual(notes(ChordSplit(mode: .top, n: 1)).count, 1, "TOP 1 keeps one note")
        XCTAssertEqual(notes(ChordSplit(mode: .top, n: 2)).count, 2, "TOP 2 keeps two")
        XCTAssertEqual(notes(ChordSplit(mode: .bottom, n: 1)).count, 1, "BOTTOM 1 keeps one note")
        if let t = notes(ChordSplit(mode: .top, n: 1)).first, let b = notes(ChordSplit(mode: .bottom, n: 1)).first {
            XCTAssertGreaterThan(t, b, "TOP 1 sits above BOTTOM 1")
        }
    }
    func testSplitVelWindowFiltersByVelocity() {
        var lo = ProcessorSlot(type: .split); lo.params.splitVel = VelWindow(floor: 1, ceil: 50)
        XCTAssertEqual(Dice.runRecorder([lo]).ons.filter { $0.cable == 1 }.count, 0, "vel window [1,50] blocks the vel-100 chord")
        var hi = ProcessorSlot(type: .split); hi.params.splitVel = VelWindow(floor: 90, ceil: 127)
        XCTAssertGreaterThan(Dice.runRecorder([hi]).ons.filter { $0.cable == 1 }.count, 0, "vel window [90,127] passes it")
    }
    func testSplitRePoolBeforeArp() {   // [SPLIT TOP 1 → ARP]: the arp only walks the top note (pedal)
        var sp = ProcessorSlot(type: .split); sp.params.splitSet = ChordSplit(mode: .top, n: 1)
        let notes = Set(Dice.runRecorder([sp, ProcessorSlot(type: .arp)]).ons.filter { $0.cable == 1 }.map { $0.note })
        XCTAssertEqual(notes.count, 1, "the arp pedals the single top note")
    }
    func testSplitPunchHolesAfterArp() {   // [ARP → SPLIT TOP 1]: the arp walks all; only top-note visits sound
        let arp = ProcessorSlot(type: .arp)
        var sp = ProcessorSlot(type: .split); sp.params.splitSet = ChordSplit(mode: .top, n: 1)
        let full = Dice.runRecorder([arp]).ons.filter { $0.cable == 1 }.count
        let holed = Dice.runRecorder([arp, sp]).ons.filter { $0.cable == 1 }
        XCTAssertLessThan(holed.count, full, "downstream SPLIT punches holes — fewer notes than the bare arp")
        XCTAssertEqual(Set(holed.map { $0.note }).count, 1, "only the top note survives the holes")
    }

    // MARK: - RATCHET MODE (Paul 2026-08-16 ferry): ALL · COIN · PATTERN

    func testRtcCoinEdgesAndDeterminism() {
        for s in 0..<40 {
            XCTAssertFalse(rtcCoinRatchets(step: s, chance: 0), "chance 0 → always plain")
            XCTAssertTrue(rtcCoinRatchets(step: s, chance: 1), "chance 1 → always ratchet")
            let c = rtcCoinCount(step: s, lo: 2, hi: 4); XCTAssert(c >= 2 && c <= 4, "count in [lo,hi]")
        }
        XCTAssertEqual((0..<40).map { rtcCoinRatchets(step: $0, chance: 0.5) }, (0..<40).map { rtcCoinRatchets(step: $0, chance: 0.5) }, "seeded/replay-exact")
        XCTAssertEqual(rtcCoinCount(step: 7, lo: 3, hi: 3), 3, "lo==hi → fixed count")
    }
    func testRtcCoinChanceScalesDensity() {   // through the real Router
        func rtc(_ chance: Double) -> ProcessorSlot {
            var s = ProcessorSlot(type: .ratchet); s.params.rtcMode = .coin; s.params.rtcChance = chance; s.params.rtcCountLo = 4; s.params.rtcCountHi = 4; return s
        }
        let plain = Accept.onsA([rtc(0)]).count, burst = Accept.onsA([rtc(1)]).count
        XCTAssertGreaterThan(burst, plain, "COIN chance=1 (all bursts) emits more than chance=0 (all plain)")
        XCTAssertGreaterThan(plain, 0, "chance=0 still sounds — a plain hit each step")
        XCTAssertEqual(Accept.notesA([rtc(1)]), [60, 64, 67], "the whole chord bursts")
    }
    // RATCHET PATTERN v3 (Paul 2026-09-06, RIFF-shaped): a SELF-CLOCKED ratchet — fires the chord at its OWN RATE, no per-slice
    // matrix. A faster RATE = more strikes (its own clock drives the density); the whole chord sounds each strike.
    // STANDALONE RATCHET PATTERN = PASS-THROUGH, not a self-clocked generator (Paul 2026-09-08, supersedes the old
    // "faster rate = more strikes" self-clock model). A single-slot ratchet-pattern PASSES the input through: count 1 =
    // sustain (RATE-INDEPENDENT — the definitive fix for "a stab plays for each step"), 2…8 = ratchet (adds strikes).
    func testRtcPatternStandaloneIsPassThrough() {
        func pat(_ counts: [Int], _ rate: ArpRate) -> ProcessorSlot {
            var s = ProcessorSlot(type: .ratchet); s.params.rtcMode = .pattern; s.params.rtcRate = rate
            s.params.rtcSteps = counts.count; s.params.rtcSlices = counts; s.params.ramp = 0; return s
        }
        let passFast = Accept.onsA([pat(Array(repeating: 1, count: 8), .r1_16)]).count
        let passSlow = Accept.onsA([pat(Array(repeating: 1, count: 8), .r1_4)]).count
        let ratFast  = Accept.onsA([pat(Array(repeating: 3, count: 8), .r1_16)]).count
        XCTAssertGreaterThan(passFast, 0, "pass-through sounds the held chord")
        XCTAssertEqual(passFast, passSlow, "PASS-THROUGH is RATE-INDEPENDENT — it passes the input, never generates per step")
        XCTAssertGreaterThan(ratFast, passFast, "ratchet columns (×3) add strikes over pass-through")
        XCTAssertEqual(Accept.notesA([pat(Array(repeating: 1, count: 8), .r1_16)]), [60, 64, 67], "the whole chord passes through")
    }

    // ARP OCT DIRECTION — the PATTERN orders WITHIN a lap; OCT DIRECTION orders the LAPS. REDEFINED (Paul 2026-09-30):
    // symmetric with UP now — both directions open lap 0 AT the held register; UP ascends from there, DOWN descends
    // below it (was "DOWN opens at the TOP octave and comes down TO the held keys, never below" — a deliberate
    // behaviour change, confirmed fine since Paul is the sole user).
    func testArpOctDirectionInvertsTheLaps() {
        let p = NotePool(); for n: UInt8 in [60, 64, 67] { p.noteOn(n, velocity: 100, channel: 0) }; p.rebuildSorted()
        let count = 3, octaves = 2   // UP pattern = index 0
        XCTAssertEqual(arpPick(phaseIndex: 0, octaves: octaves, pattern: 0, pool: p).note, 60, "UP: lap 0 opens on the lowest note")
        XCTAssertEqual(arpPick(phaseIndex: Int64(count), octaves: octaves, pattern: 0, pool: p).note, 72, "UP: lap 1 = the lowest note an octave up")
        // OCT DOWN: both directions open AT the held register; DOWN's lap 1 descends BELOW it, not up to it.
        XCTAssertEqual(arpPick(phaseIndex: 0, octaves: octaves, pattern: 0, pool: p, octDown: true).note, 60, "DOWN: lap 0 opens at the held register, same as UP")
        XCTAssertEqual(arpPick(phaseIndex: Int64(count), octaves: octaves, pattern: 0, pool: p, octDown: true).note, 48, "DOWN: lap 1 descends a full octave BELOW the held register")
    }

    // ARP OCTAVE CONTROL — the exact octave-spanning sequence (Paul 2026-09-15: "make sure the octave control is right").
    // OCTAVES multiplies the pool by 12·lap; the pitch SET must be the chord repeated at each octave, ordered by PATTERN.
    func testArpOctaveSpanFullSequence() {
        let p = NotePool(); for n: UInt8 in [60, 64, 67] { p.noteOn(n, velocity: 100, channel: 0) }; p.rebuildSorted()
        func seq(_ octaves: Int, _ n: Int, octDown: Bool = false, pattern: UInt8 = 0) -> [Int] {
            (0..<n).map { arpPick(phaseIndex: Int64($0), octaves: octaves, pattern: pattern, pool: p, octDown: octDown).note }
        }
        // OCTAVES = N raises the chord to exactly N octave levels (+0, +12, … +12·(N−1)) — one lap per octave, N−1 raises.
        XCTAssertEqual(seq(1, 3), [60, 64, 67], "OCTAVES 1 = the chord, 0 raises (1 octave level)")
        XCTAssertEqual(seq(2, 6), [60, 64, 67, 72, 76, 79], "OCTAVES 2 = 1 raise (levels +0, +12)")
        XCTAssertEqual(seq(3, 9), [60, 64, 67, 72, 76, 79, 84, 88, 91], "OCTAVES 3 = 2 raises (+0, +12, +24)")
        XCTAssertEqual(seq(4, 12), [60, 64, 67, 72, 76, 79, 84, 88, 91, 96, 100, 103], "OCTAVES 4 = 3 raises (+0, +12, +24, +36) — the control's max")
        // exactly N distinct octave levels — never N+1 or N−1
        XCTAssertEqual(Set(seq(4, 12).map { ($0 - 60) / 12 }).count, 4, "OCTAVES 4 produces exactly 4 octave levels, no more")
        XCTAssertEqual(Set(seq(3, 9).map { ($0 - 60) / 12 }).count, 3, "OCTAVES 3 produces exactly 3 octave levels")
        XCTAssertEqual(seq(2, 6, octDown: true), [60, 64, 67, 48, 52, 55], "OCT DIR DOWN: lap 0 at the held register, lap 1 a full octave below it")
        XCTAssertEqual(seq(2, 6, pattern: 1), [79, 76, 72, 67, 64, 60], "DOWN pattern descends the whole 2-octave span")
        XCTAssertEqual(seq(2, 12), seq(2, 6) + seq(2, 6), "the span loops cleanly (phase 6 == phase 0)")
    }

    // ARP RANDOM ANCHOR (Paul 2026-08-22): PATTERN=RANDOM opens each cycle (a full pool×oct traversal) on the anchor note.
    func testArpRandomAnchorOpensOnLowOrHigh() {
        let p = NotePool(); for n: UInt8 in [60, 64, 67] { p.noteOn(n, velocity: 100, channel: 0) }; p.rebuildSorted()
        let octaves = 2, span = 6   // RANDOM pattern = index 3; span = 3 notes × 2 octaves
        for k in 0..<3 {   // LOW anchor: every wrap (phaseIndex = k·span) opens on the lowest note
            XCTAssertEqual(arpPick(phaseIndex: Int64(k * span), octaves: octaves, pattern: 3, pool: p, randomAnchor: 1).note, 60, "LOW anchor at wrap \(k)")
        }
        XCTAssertEqual(arpPick(phaseIndex: 0, octaves: octaves, pattern: 3, pool: p, randomAnchor: 2).note, 79, "HIGH anchor = top note of the top octave (67+12)")
    }

    // RANDOM ONCE (Paul 2026-09-16): a FIXED shuffle off a persisted seed — the SAME order every cycle (unlike RANDOM,
    // which re-hashes the absolute tick), and different seeds shuffle differently.
    func testArpRandomOnceIsCycleStableAndSeedDependent() {
        let p = NotePool(); for n: UInt8 in [60, 64, 67] { p.noteOn(n, velocity: 100, channel: 0) }; p.rebuildSorted()
        let octaves = 2, span = 6; let pat: UInt8 = 7   // RANDOM ONCE = ArpPattern index 7 (appended)
        let seed: UInt64 = 0xABCD_EF12
        for k in 0..<span {   // the order repeats identically each cycle (position depends on phaseIndex % span, not the cycle)
            let a = arpPick(phaseIndex: Int64(k), octaves: octaves, pattern: pat, pool: p, seed: seed).note
            let b = arpPick(phaseIndex: Int64(k + span), octaves: octaves, pattern: pat, pool: p, seed: seed).note
            XCTAssertEqual(a, b, "RANDOM ONCE repeats identically each cycle (step \(k))")
        }
        let s1 = (0..<span).map { arpPick(phaseIndex: Int64($0), octaves: octaves, pattern: pat, pool: p, seed: 0x1111).note }
        let s2 = (0..<span).map { arpPick(phaseIndex: Int64($0), octaves: octaves, pattern: pat, pool: p, seed: 0x2222).note }
        XCTAssertNotEqual(s1, s2, "different seeds shuffle to a different order")
        let valid: Set<Int> = [60, 64, 67, 72, 76, 79]   // the 3-note pool across 2 octaves
        for n in s1 { XCTAssertTrue(valid.contains(n), "picked note \(n) is a real pool member") }
    }

    // LFO RATE IGNORE (Paul 2026-09-16): the sweep only visits KEPT families; FROM/TO snap to the nearest kept rung.
    // The ladder is TEMPO-SORTED (Paul 2026-09-26 fix), not declaration-block order — a dotted/triplet rate musically
    // interleaves BETWEEN two adjacent normal rates, so it must occupy a ladder POSITION between them, not off in its
    // own block (else a normal→normal sweep — the common case — never crosses it even when "included").
    func testArpRateIgnoreLadderAndSnap() {
        XCTAssertEqual(arpRateAllowedLadder(ignore: 0), [6, 0, 7, 12, 1, 8, 13, 2, 9, 14, 3, 10, 15, 4, 11, 16, 5, 17],
                       "ignore nothing → the full ladder, TEMPO-sorted slow→fast (dotted/triplet interleave with normal)")
        XCTAssertEqual(arpRateAllowedLadder(ignore: 0b110), Array(0..<6), "default (ignore dotted+trip) → normal only (already tempo-order)")
        XCTAssertEqual(arpRateAllowedLadder(ignore: 0b010), [0, 12, 1, 13, 2, 14, 3, 15, 4, 16, 5, 17],
                       "ignore dotted → normal + triplet, tempo-interleaved (was the stale Array(0..<6)+Array(12..<18) block order)")
        XCTAssertEqual(arpRateAllowedLadder(ignore: 0b111), Array(0..<6), "all-ignore → keep normal (never empty)")
        let ladder = arpRateAllowedLadder(ignore: 0b110)   // [0…5] — a single family sorts identically either way
        XCTAssertEqual(nearestLadderPos(ladder, 2), 2, "kept index maps to its own position")
        XCTAssertEqual(nearestLadderPos(ladder, 14), 5, "an ignored (triplet) endpoint snaps to the nearest kept rung")
    }
    // THE BUG (Paul 2026-09-26): "the LFO jumps right past dotted/triplet even when I include them." A sweep between
    // TWO NORMAL rates (the common case — FROM defaults to the arp's own base rate) with all families included must
    // now visit any dotted/triplet rate that musically falls between them — e.g. 1/8 (0.5 beats) → 1/4 (1.0 beats)
    // passes through 1/4T (0.667) and 1/8D (0.75) in between. Before the tempo-sort fix, both endpoints sat in the
    // same contiguous ladder block (positions 2…3 of [0..5]) and the interleaved families were never reached.
    func testArpRateLFOSweepBetweenNormalRatesCrossesIncludedDottedAndTriplet() {
        let ladder = arpRateAllowedLadder(ignore: 0)   // everything included
        let r1_8 = ArpRate.allCases.firstIndex(of: .r1_8)!, r1_4 = ArpRate.allCases.firstIndex(of: .r1_4)!
        let r1_4t = ArpRate.allCases.firstIndex(of: .r1_4t)!, r1_8d = ArpRate.allCases.firstIndex(of: .r1_8d)!
        let fp = nearestLadderPos(ladder, r1_8), tp = nearestLadderPos(ladder, r1_4)
        let lo = min(fp, tp), hi = max(fp, tp)
        let crossed = Set(ladder[lo...hi])
        XCTAssertTrue(crossed.contains(r1_4t), "sweeping 1/8→1/4 must pass through 1/4T (0.667 beats lies between 0.5 and 1.0)")
        XCTAssertTrue(crossed.contains(r1_8d), "sweeping 1/8→1/4 must pass through 1/8D (0.75 beats lies between 0.5 and 1.0)")
    }

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

    // GLIDE SPANS (Paul 2026-09-26, caught against a worked example): three consecutive GLIDE columns that all
    // target the SAME ratio must ramp smoothly across ALL THREE, not reach the target after the first and flatline
    // for the other two (the bug in the original "ramp from my immediate predecessor" reading — a segment whose
    // two ends are numerically equal has no slope to inherit). `clockDrawnGlideEndpoints` (the per-column checkpoint
    // sequence, UNCHANGED by the elastic-landing fix) still climbs spanFrom=1 → target=7 in three even slices
    // (col1: 1→3, col2: 3→5, col3: 5→7) — but each column's own FULL contribution is now its own checkpoint's `to`
    // value exactly (1, 3, 5, 7 for col0..col3), not the old straight-ramp's average of its endpoints, so the
    // cumulative phase at each boundary is the running sum of THOSE checkpoints (values pulled from the actual
    // function's own output, per this session's rule of never trusting a hand-derivation of this math unchecked).
    func testClockDrawnGlideSpanRampsAcrossTheWholeRunNotJustTheFirstColumn() {
        let ratios = [1.0, 7.0, 7.0, 7.0]
        let glide = [false, true, true, true]
        XCTAssertEqual(clockDrawnPhase(1.0, ratios: ratios, glide: glide, steps: 4, rateBeats: 1, periodBeats: 0), 1.0, accuracy: 1e-9, "end of col0 (SET at 1) = start of the span")
        XCTAssertEqual(clockDrawnPhase(1.5, ratios: ratios, glide: glide, steps: 4, rateBeats: 1, periodBeats: 0), 2.25, accuracy: 1e-9, "col1's own slice (1→3) at its midpoint")
        XCTAssertEqual(clockDrawnPhase(2.0, ratios: ratios, glide: glide, steps: 4, rateBeats: 1, periodBeats: 0), 4.0, accuracy: 1e-9, "end of col1 — its own checkpoint (3) landed exactly, cumulative with col0's 1")
        XCTAssertEqual(clockDrawnPhase(3.0, ratios: ratios, glide: glide, steps: 4, rateBeats: 1, periodBeats: 0), 9.0, accuracy: 1e-9, "end of col2 — cumulative checkpoints 1 + 3 + 5 = 9")
        XCTAssertEqual(clockDrawnPhase(4.0, ratios: ratios, glide: glide, steps: 4, rateBeats: 1, periodBeats: 0), 16.0, accuracy: 1e-9, "end of col3 (one full lap) — cumulative checkpoints 1 + 3 + 5 + 7 = 16")
        XCTAssertEqual(clockDrawnDriftPerLap(ratios, glide: glide, steps: 4, rateBeats: 1), 12.0, accuracy: 1e-9, "drift = lapAdvance(16) − steps×rateBeats(4) — the SAME 12 a SET lane at [1,3,5,7] would report (see the next test)")
        // Confirms the drift is a property of the CHECKPOINT VALUES only, never of glide-vs-SET on the same targets:
        XCTAssertEqual(clockDrawnDriftPerLap(ratios, glide: glide, steps: 4, rateBeats: 1),
                       clockDrawnDriftPerLap([1, 3, 5, 7], glide: [false, false, false, false], steps: 4, rateBeats: 1),
                       accuracy: 1e-9, "GLIDE-ing into a checkpoint sequence drifts identically to SET-ting those same checkpoints outright")
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

    // THE FIX ITSELF, swept across the WHOLE ratio ladder (Paul 2026-09-26 ②→③: "when it lands on a target, whether
    // it got there with or without glide, it should be in sync" — then, once tried, "hiccups... a stutter" on a
    // decelerating run). ACCELERATING pairs (to ≥ from) get the full sync guarantee: a GLIDE column's full
    // contribution matches a same-target SET exactly, and the elastic peak never needs to go negative (proven safe
    // for ANY split fraction when to ≥ from — see the doc comment). DECELERATING pairs (to < from) deliberately do
    // NOT get this guarantee — forcing it there requires local time to race ahead of the same-target SET mid-column
    // (confirmed with a throwaway script: up to 16% ahead for a simple ×2→×1 column), which is the actual mechanism
    // behind the reported stutter — so they keep the plain, honest, straight-ramp average instead.
    func testClockDrawnGlideFullColumnAlwaysMatchesSetAtTheSameTarget() {
        let rateBeats = 0.5
        for from in clockRatioLadder {
            for to in clockRatioLadder {
                let atEnd = clockDrawnGlideAdvance(rateBeats, from: from, to: to, rateBeats: rateBeats)
                let expected = to >= from ? to * rateBeats : (from + to) / 2 * rateBeats
                XCTAssertEqual(atEnd, expected, accuracy: 1e-9,
                               to >= from ? "ACCELERATING \(from)→\(to): must land exactly where SET at \(to) would"
                                          : "DECELERATING \(from)→\(to): must keep the honest straight-ramp average, not force sync")
                // and the closed-form inverse must recover the full span exactly, either way
                let back = clockDrawnGlideAdvanceInverse(expected, from: from, to: to, rateBeats: rateBeats)
                XCTAssertEqual(back, rateBeats, accuracy: 1e-6, "inverting the full contribution must land exactly at the column's end")
            }
        }
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

    // The drift readout must match what the phase function ACTUALLY does over one full lap. An ACCELERATING glide
    // column's full contribution equals `to × rateBeats` — identical to SET at that same value — so using GLIDE
    // instead of SET on the SAME accelerating checkpoint can no longer change the reported drift at all. A
    // DECELERATING glide still can (unchanged from before this whole "in sync" feature existed).
    func testClockDrawnDriftPerLapMatchesThePhaseFunctionsOwnLapAdvance() {
        let ratios = [1.0, 2.0]
        XCTAssertEqual(clockDrawnDriftPerLap(ratios, glide: [false, false], steps: 2, rateBeats: 1), 1.0, accuracy: 1e-9)
        XCTAssertEqual(clockDrawnDriftPerLap(ratios, glide: [false, true], steps: 2, rateBeats: 1), 1.0, accuracy: 1e-9, "GLIDE-ing into ×2 drifts exactly as much as SET-ting it — no glide-specific penalty")
        XCTAssertEqual(clockDrawnDriftPerLap([1, 1, 1, 1], glide: [false, false, false, false], steps: 4, rateBeats: 0.5), 0, accuracy: 1e-9)
    }

    // REPLAY-EXACTNESS: `clockDrawnPhase` factors elapsed time into `fullLaps × lapAdvance + (partial lap)` rather than
    // summing lap-by-lap, so it stays exact — and O(steps), not O(laps) — no matter how many laps have already gone by.
    // 50 laps later, the SAME within-lap offset must land exactly 50×lapAdvance further on, to floating-point precision.
    func testClockDrawnPhaseStaysExactAcrossManyLaps() {
        let ratios = [1.0, 2.0, 0.5, 1.5]
        let glide = [false, true, false, true]
        let steps = 4, rateBeats = 0.5
        let lapAdvance = clockDrawnDriftPerLap(ratios, glide: glide, steps: steps, rateBeats: rateBeats) + Double(steps) * rateBeats
        let within = 0.3
        let early = clockDrawnPhase(within, ratios: ratios, glide: glide, steps: steps, rateBeats: rateBeats, periodBeats: 0)
        let lapBeats = Double(steps) * rateBeats
        let late = clockDrawnPhase(within + 50 * lapBeats, ratios: ratios, glide: glide, steps: steps, rateBeats: rateBeats, periodBeats: 0)
        XCTAssertEqual(late - early, 50 * lapAdvance, accuracy: 1e-7)
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

    // Driver retiming (Paul 2026-09-26, final spec — "a grid with a variable number of steps, each step a
    // mutually exclusive speed, and another row on the same grid for glide"): clockDrawnPhaseInverse must exactly
    // undo clockDrawnPhase across a spread of ratio/glide patterns, origins, and laps — this is the primitive a
    // retimed driver (Router.driverClockBeat/Inverse) uses to convert a LOCAL tick it found on THIS grid back to
    // the REAL beat it must schedule at. Any drift here would misplace note-on/off sample positions. Covers
    // all-SET, all-GLIDE (including extreme ratios, where the quadratic coefficient is large), mixed SET/GLIDE,
    // and a degenerate single-step lane.
    func testClockDrawnPhaseInverseRoundTrips() {
        let cases: [(ratios: [Double], glide: [Bool], steps: Int, rateBeats: Double)] = [
            ([1, 1, 1, 1], [false, false, false, false], 4, 0.5),
            ([1, 2, 0.5, 1.5], [false, false, false, false], 4, 0.5),
            ([1, 2, 0.5, 1.5], [false, true, false, true], 4, 0.5),
            ([4, 0.25, 3, 1], [true, true, true, true], 4, 0.25),
            ([1], [false], 1, 1),
            ([1, 5, 5, 5, 2], [false, true, true, true, false], 5, 0.5),   // a 3-column GLIDE SPAN (Paul 2026-09-26) — the inverse must resolve the same span endpoints the forward transform used
        ]
        for c in cases {
            for origin in [0.0, 2.7, -1.4] {
                for beat in stride(from: origin - 3.0, through: origin + 9.0, by: 0.37) {
                    let local = clockDrawnPhase(beat, ratios: c.ratios, glide: c.glide, steps: c.steps,
                                                rateBeats: c.rateBeats, periodBeats: 0, originOverride: origin)
                    let back = clockDrawnPhaseInverse(local, originBeat: origin, ratios: c.ratios, glide: c.glide,
                                                       steps: c.steps, rateBeats: c.rateBeats)
                    XCTAssertEqual(back, beat, accuracy: 1e-6,
                                   "ratios \(c.ratios) glide \(c.glide) origin \(origin) beat \(beat)")
                }
            }
        }
    }

    // KILL STEP (Paul 2026-09-26, sibling to CLOCK; MUTE/PAUSE added 2026-09-27) — a DISCRETE step remap via a
    // PRECOMPUTED table (`killStepResolveTable`): DROP is removed from the downstream timeline, the surviving steps
    // repeat to fill the pass; MUTE counts exactly like ON for this transform (it only silences the note — a
    // separate fold, Router.emitDriverNote — never this table); PAUSE freezes the local value for its own hold
    // length. `ksModes` converts the OLD bool-array fixtures (true→ON, false→DROP) so these read exactly as they did
    // before the table refactor — proving it byte-identical whenever nothing is MUTE/PAUSE. A no-op (all ON) reduces
    // to the identity EXACTLY, at any rate/period, since `value ≡ n` when every index is kept.
    private func ksModes(_ enabled: [Bool]) -> [KillStepMode] { enabled.map { $0 ? .on : .drop } }
    func testKillStepPhaseIsExactIdentityWhenAllStepsEnabled() {
        let t = killStepResolveTable(ksModes(Array(repeating: true, count: 8)), pauseLen: 1)
        for rate in [0.25, 0.5, 1.0, 2.0] {
            for origin in [0.0, 1.3, -2.7] {
                for beat in stride(from: origin - 5, through: origin + 12, by: 0.41) {
                    XCTAssertEqual(killStepPhase(beat, columnMap: t.columnMap, columnsPerLap: t.columnsPerLap, steps: 8, rateBeats: rate, periodBeats: 0, originOverride: origin),
                                   beat, accuracy: 1e-9, "rate \(rate) origin \(origin) beat \(beat)")
                }
            }
        }
    }
    // The user's own worked example: 4 of 8 steps enabled — real columns 0…7 (one rate-tick each) should read as
    // 0,1,2,3,0,1,2,3 mod the row's own 8-step width ("the first half plays twice"), and the raw returned value
    // must climb by a full lap (8) each time it wraps, since the shared tick-search machinery needs a monotonic
    // local beat to walk forward through.
    func testKillStepPhasePlaysTheFirstHalfTwiceOverOnePass() {
        let t = killStepResolveTable(ksModes([true, true, true, true, false, false, false, false]), pauseLen: 1)
        let got = (0..<8).map { n in killStepPhase(Double(n), columnMap: t.columnMap, columnsPerLap: t.columnsPerLap, steps: 8, rateBeats: 1, periodBeats: 0, originOverride: 0) }
        XCTAssertEqual(got, [0, 1, 2, 3, 8, 9, 10, 11], "columns 0…3 repeat (offset by a full lap of 8) instead of ever reaching 4…7")
    }
    // 3 of 8 enabled: the enabled set doesn't divide the 8-column bar evenly, so the 3-cycle rotates against it
    // ("overriding the clock") instead of realigning every pass.
    func testKillStepPhaseRotatesAnUnevenCountAgainstTheBar() {
        let t = killStepResolveTable(ksModes([true, true, true, false, false, false, false, false]), pauseLen: 1)
        let got = (0..<8).map { n in killStepPhase(Double(n), columnMap: t.columnMap, columnsPerLap: t.columnsPerLap, steps: 8, rateBeats: 1, periodBeats: 0, originOverride: 0) }
        XCTAssertEqual(got, [0, 1, 2, 8, 9, 10, 16, 17], "a 3-enabled-of-8 row drifts a full lap ahead every 3 real columns, never landing back on the bar's own 8-count")
    }
    // An all-disabled row is never silent/undefined — it falls back to all-enabled, matching
    // `clockDrawnResolveRatios`'s empty-lane convention (a true no-op, identical to testKillStepPhaseIsExact…).
    func testKillStepPhaseAllDisabledFallsBackToAllEnabled() {
        let t = killStepResolveTable(ksModes(Array(repeating: false, count: 8)), pauseLen: 1)
        for beat in stride(from: -3.0, through: 9.0, by: 0.7) {
            XCTAssertEqual(killStepPhase(beat, columnMap: t.columnMap, columnsPerLap: t.columnsPerLap, steps: 8, rateBeats: 1, periodBeats: 0, originOverride: 0),
                           beat, accuracy: 1e-9, "beat \(beat)")
        }
    }
    // Every output KILL STEP's forward transform can produce is, BY CONSTRUCTION, a real occurrence (never a gap —
    // gaps only arise from an EXTERNAL local beat the transform never produced, e.g. a downstream driver ticking at
    // its own unrelated rate) — so sweeping `beat` continuously and round-tripping forward→inverse must be exact
    // everywhere, not just at column-aligned points (mirrors `testClockDrawnPhaseInverseRoundTrips`'s sweep style).
    func testKillStepPhaseInverseRoundTripsAcrossAContinuousSweep() {
        let cases: [(enabled: [Bool], steps: Int, rateBeats: Double)] = [
            (Array(repeating: true, count: 8), 8, 0.5),
            ([true, true, true, true, false, false, false, false], 8, 0.5),
            ([true, true, true, false, false, false, false, false], 8, 0.25),
            ([true, false, true, false, false], 5, 0.5),          // uneven steps, k∤steps
            (Array(repeating: false, count: 6), 6, 1.0),          // all-disabled fallback
            ([true], 1, 1.0),
        ]
        for c in cases {
            let t = killStepResolveTable(ksModes(c.enabled), pauseLen: 1)
            for origin in [0.0, 2.7, -1.4] {
                for beat in stride(from: origin - 3.0, through: origin + 9.0, by: 0.37) {
                    let local = killStepPhase(beat, columnMap: t.columnMap, columnsPerLap: t.columnsPerLap, steps: c.steps, rateBeats: c.rateBeats, periodBeats: 0, originOverride: origin)
                    let back = killStepPhaseInverse(local, originBeat: origin, columnMap: t.columnMap, columnsPerLap: t.columnsPerLap, firstSlot: t.firstSlot, steps: c.steps, rateBeats: c.rateBeats)
                    XCTAssertEqual(back, beat, accuracy: 1e-6, "enabled \(c.enabled) origin \(origin) beat \(beat)")
                }
            }
        }
    }
    // A local beat that DOESN'T correspond to any real occurrence (it falls inside a disabled column's span — a
    // "gap") has documented, non-crashing behaviour: snap FORWARD to the start of the next enabled repeat. Hand-
    // verified: enabled {0,1,2,3} of 8 at rate 1 from origin 0 — local beat 5.3 sits inside the disabled span
    // [4,8); the next enabled repeat starts at the next lap's column 0, real beat 4 — so the inverse is 4.3, and
    // (confirmed, not just asserted) forward-mapping THAT real beat lands on a genuine, differently-valued local
    // beat (8.3, the very next repeat) rather than reproducing the original gap probe — this is not a round trip.
    func testKillStepPhaseInverseSnapsForwardPastAGap() {
        let t = killStepResolveTable(ksModes([true, true, true, true, false, false, false, false]), pauseLen: 1)
        let back = killStepPhaseInverse(5.3, originBeat: 0, columnMap: t.columnMap, columnsPerLap: t.columnsPerLap, firstSlot: t.firstSlot, steps: 8, rateBeats: 1)
        XCTAssertEqual(back, 4.3, accuracy: 1e-9, "snaps forward to the start of the next enabled repeat (real column 0 of the second lap)")
        let reforward = killStepPhase(back, columnMap: t.columnMap, columnsPerLap: t.columnsPerLap, steps: 8, rateBeats: 1, periodBeats: 0, originOverride: 0)
        XCTAssertEqual(reforward, 8.3, accuracy: 1e-9, "the snapped-to real beat maps forward to a genuine repeat, not back to the gap")
    }
    // NEW (Paul 2026-09-27): MUTE counts exactly like ON for this TRANSFORM — a row of [ON,MUTE,ON,MUTE,DROP×4]
    // must be timing-IDENTICAL to testKillStepPhasePlaysTheFirstHalfTwiceOverOnePass's plain ON/DROP row (MUTE's
    // only effect — silencing the note — lives entirely in Router.emitDriverNote's fold, never in this table).
    func testKillStepPhaseMuteCountsLikeOnForTiming() {
        let t = killStepResolveTable([.on, .mute, .on, .mute, .drop, .drop, .drop, .drop], pauseLen: 1)
        let got = (0..<8).map { n in killStepPhase(Double(n), columnMap: t.columnMap, columnsPerLap: t.columnsPerLap, steps: 8, rateBeats: 1, periodBeats: 0, originOverride: 0) }
        XCTAssertEqual(got, [0, 1, 2, 3, 8, 9, 10, 11], "MUTE steps advance the local value exactly like ON — same shape as an equivalent ON/DROP row")
    }
    // NEW: PAUSE freezes the local value across its own hold — real columns [pauseCol, pauseCol+1+pauseLen) must
    // read the IDENTICAL local value (a true freeze, no drift within the hold), then jump forward by exactly one
    // step once it ends. Hand-traced against `killStepResolveTable`'s own algorithm, not guessed.
    func testKillStepPhasePauseFreezesForItsHoldLength() {
        let t = killStepResolveTable([.on, .pause, .on, .on], pauseLen: 2)   // step 1 pauses; table = [0,1,1,1,2,3], columnsPerLap 6
        let got = (0..<6).map { n in killStepPhase(Double(n), columnMap: t.columnMap, columnsPerLap: t.columnsPerLap, steps: 4, rateBeats: 1, periodBeats: 0, originOverride: 0) }
        XCTAssertEqual(got, [0, 1, 1, 1, 2, 3], "step 1's PAUSE holds the SAME local value across 3 real columns (1 + pauseLen 2), then resumes")
    }
    // Inverse round-trip must also hold with MUTE in the mix — MUTE is injective just like ON (each real column still
    // maps to a DISTINCT local value), so the same "exact everywhere" guarantee applies. (PAUSE is deliberately
    // EXCLUDED here — see the two tests below for why a blind round-trip sweep is the wrong test for it.)
    func testKillStepPhaseInverseRoundTripsWithMuteInTheMix() {
        let t = killStepResolveTable([.on, .mute, .on, .mute, .drop, .drop, .drop, .drop], pauseLen: 1)
        for origin in [0.0, 1.9] {
            for beat in stride(from: origin - 3.0, through: origin + 9.0, by: 0.31) {
                let local = killStepPhase(beat, columnMap: t.columnMap, columnsPerLap: t.columnsPerLap, steps: 8, rateBeats: 0.5, periodBeats: 0, originOverride: origin)
                let back = killStepPhaseInverse(local, originBeat: origin, columnMap: t.columnMap, columnsPerLap: t.columnsPerLap, firstSlot: t.firstSlot, steps: 8, rateBeats: 0.5)
                XCTAssertEqual(back, beat, accuracy: 1e-6, "origin \(origin) beat \(beat)")
            }
        }
    }
    // CAUGHT BY THE TEST SUITE, not hand-derived (this session's own standing rule — trace, don't re-guess): a first
    // draft asserted the SAME blind round-trip sweep for PAUSE and failed ~64 times. Root cause, traced: PAUSE makes
    // the forward map NON-INJECTIVE by design — every real column across the whole hold maps to the SAME frozen local
    // value (that IS the freeze) — so a beat landing on the 2nd/3rd real column of a hold can only invert back to the
    // hold's FIRST column (same "snap to a real occurrence" policy `testKillStepPhaseInverseSnapsForwardPastAGap`
    // already documents for DROP gaps — this is that same policy, hand-verified explicitly instead of swept blindly).
    func testKillStepPhaseInverseOfAPausedValuePicksTheFirstOccurrence() {
        let t = killStepResolveTable([.on, .pause, .on, .on], pauseLen: 2)   // step 1 pauses; table [0,1,1,1,2,3], columnsPerLap 6
        for frac in [0.0, 0.2, 0.7] {   // any within-column offset — the inverse still snaps the COLUMN, offset carries through
            let back = killStepPhaseInverse(1.0 + frac, originBeat: 0, columnMap: t.columnMap, columnsPerLap: t.columnsPerLap, firstSlot: t.firstSlot, steps: 4, rateBeats: 1)
            XCTAssertEqual(back, 1.0 + frac, accuracy: 1e-9, "value 1's FIRST real occurrence is real column 1 — frac \(frac)")
        }
    }
    // The other half of the same fact, checked forward: real columns 1, 2, AND 3 (the whole hold: 1 + pauseLen 2)
    // must all map to the SAME local value — a true freeze, not an approximation.
    func testKillStepPhaseAllColumnsOfAHoldMapToTheSameValue() {
        let t = killStepResolveTable([.on, .pause, .on, .on], pauseLen: 2)
        let values = [1.0, 2.0, 3.0].map { n in killStepPhase(n, columnMap: t.columnMap, columnsPerLap: t.columnsPerLap, steps: 4, rateBeats: 1, periodBeats: 0, originOverride: 0) }
        XCTAssertEqual(Set(values).count, 1, "real columns 1,2,3 (the whole 3-column hold) must read the IDENTICAL local value \(values)")
    }

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

    // span ladder ×8 reach + rtcCoinCount determinism/bounds-swap (untested edges).
    func testSpanLadder64AndRtcCoinCountEdges() {
        XCTAssertEqual(spanLadderBeats(64, S: 0.5, row: 4.0), 32.0, "×8 = 8 rows")
        XCTAssertEqual(rtcCoinCount(step: 5, lo: 2, hi: 6), rtcCoinCount(step: 5, lo: 2, hi: 6), "replay-exact (deterministic per step)")
        let swapped = rtcCoinCount(step: 5, lo: 6, hi: 2)
        XCTAssertTrue((2...6).contains(swapped), "inverted lo>hi is order-guarded → in-range, no trap")
    }

    // KEYS EXCLUDE (Paul 2026-08-22): the complement door subtracts these pitch classes from its typed set.
    func testPitchClassMaskCollectsHeldPitchClassesUnderFilters() {
        let p = NotePool()
        p.noteOn(60, velocity: 100, channel: 0)  // C
        p.noteOn(64, velocity: 100, channel: 0)  // E
        p.noteOn(79, velocity: 100, channel: 0)  // G, an octave up — folds to the same class as 67
        p.rebuildSorted()
        XCTAssertEqual(p.pitchClassMask(chanMask: 0xFFFF, cableMask: 0b1111, noteLo: 0, noteHi: 127),
                       (1 << 0) | (1 << 4) | (1 << 7), "C, E, G pitch classes set (79 folds to G)")
        XCTAssertEqual(p.pitchClassMask(chanMask: 1 << 1, cableMask: 0b1111, noteLo: 0, noteHi: 127), 0, "channel 2 hears nothing (all notes on channel 1)")
        XCTAssertEqual(p.pitchClassMask(chanMask: 0xFFFF, cableMask: 0b1111, noteLo: 62, noteHi: 66), (1 << 4), "only E is in the 62–66 window")
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
        XCTAssertEqual(spanLadderLabel(16), "×2"); XCTAssertEqual(spanLadderLabel(32), "×4"); XCTAssertEqual(spanLadderLabel(3), "3")
    }

    // GLIDE SYNTH mode (Paul 2026-08-22): glide TIME (beats) → CC5 portamento value (0…127), linear ·24 with clamps.
    func testGlideSynthCCTimeMapsBeatsToPortamentoValue() {
        XCTAssertEqual(glideSynthCCTime(0), 0, "instant = 0")
        XCTAssertEqual(glideSynthCCTime(0.25), 6, "0.25 beat → 6")
        XCTAssertEqual(glideSynthCCTime(0.5), 12, "0.5 beat → 12")
        XCTAssertEqual(glideSynthCCTime(10), 127, "long glide clamps at the ceiling")
        XCTAssertGreaterThanOrEqual(glideSynthCCTime(1.0), glideSynthCCTime(0.5), "monotonic non-decreasing")
    }

    // COIN — SIZE WEIGHTS (Paul 2026-08-26 ①): a seeded weighted pick over 2·3·4·6·8; all weight on one size → always it;
    // equal weights → every size appears; deterministic per step.
    func testRtcCoinSizePicksByWeight() {
        XCTAssertTrue((0..<64).allSatisfy { rtcCoinSize(step: $0, weights: [1, 0, 0, 0, 0]) == 2 }, "all weight on size 2 → always 2")
        XCTAssertTrue((0..<64).allSatisfy { rtcCoinSize(step: $0, weights: [0, 0, 0, 0, 1]) == 8 }, "all weight on size 8 → always 8")
        XCTAssertEqual(Set((0..<200).map { rtcCoinSize(step: $0, weights: [1, 1, 1, 1, 1]) }), [2, 3, 4, 6, 8], "equal weights → every size appears")
        XCTAssertEqual(rtcCoinSize(step: 5, weights: [1, 2, 3, 0, 0]), rtcCoinSize(step: 5, weights: [1, 2, 3, 0, 0]), "deterministic")
    }
    // COIN — FIRE GATE (Paul 2026-08-26 ②③④): fast path == rtcCoinRatchets; GAP spaces fires; QUOTA caps per row; velocity scales odds.
    func testRtcCoinFiresGapQuotaAndVelocity() {
        for s in 0..<64 { XCTAssertEqual(rtcCoinFires(step: s, chance: 0.5, gap: 0, quota: 0, velFactor: 1), rtcCoinRatchets(step: s, chance: 0.5), "fast path byte-identical") }
        // GAP 2, chance 1 (every raw step fires) → fires ≥3 steps apart within a row
        var last = -100
        for s in 0..<8 where rtcCoinFires(step: s, chance: 1.0, gap: 2, quota: 0, velFactor: 1) { XCTAssertGreaterThan(s - last, 2, "gap keeps fires >2 apart"); last = s }
        // QUOTA 3, chance 1 → exactly 3 fires per 8-step row
        XCTAssertEqual((0..<8).filter { rtcCoinFires(step: $0, chance: 1.0, gap: 0, quota: 3, velFactor: 1) }.count, 3, "quota caps fires per row")
        // VELOCITY: factor 0 → never fires; lower factor → fewer fires
        XCTAssertFalse((0..<64).contains { rtcCoinFires(step: $0, chance: 0.5, gap: 0, quota: 0, velFactor: 0) }, "silent chord never fires")
        let hi = (0..<300).filter { rtcCoinFires(step: $0, chance: 0.5, gap: 0, quota: 0, velFactor: 1.0) }.count
        let lo = (0..<300).filter { rtcCoinFires(step: $0, chance: 0.5, gap: 0, quota: 0, velFactor: 0.3) }.count
        XCTAssertLessThan(lo, hi, "lower velocity → fewer fires")
    }
    // COVERAGE (2026-08-25 housekeeping): the per-ROW reset (a SECOND row gets a FRESH quota — pins that rowStart advances
    // to 8, not stuck at 0) + gap∧quota TOGETHER + a negative-step origin (reachable under a fuzz seek-backward, must not trap).
    func testRtcCoinFiresPerRowResetCombinedAndNegativeStep() {
        XCTAssertEqual((8..<16).filter { rtcCoinFires(step: $0, chance: 1.0, gap: 0, quota: 2, velFactor: 1) }.count, 2,
                       "row 2 gets its own fresh quota of 2 (the per-row budget resets — rowStart advanced to 8)")
        var last = -100, total = 0                                     // gap 1 ∧ quota 3 together, one row
        for s in 0..<8 where rtcCoinFires(step: s, chance: 1.0, gap: 1, quota: 3, velFactor: 1) { XCTAssertGreaterThan(s - last, 1, "gap holds"); last = s; total += 1 }
        XCTAssertLessThanOrEqual(total, 3, "quota caps the combined row")
        _ = rtcCoinFires(step: -1, chance: 0.5, gap: 1, quota: 2, velFactor: 1)   // negative origin must not trap
    }
    // COVERAGE: the arp EUCLID MASK Bjorklund helpers by EXACT value — the Router test only asserts relative facts (an
    // off-by-one in the WAIT cross-lap term or the TIE span would slip past it). Values computed from the mask formula.
    func testEuclidMaskHelpersExactValues() {
        XCTAssertEqual((0..<8).map { euclidMaskHit($0, k: 4, n: 8, rotate: 0) }, [true, false, true, false, true, false, true, false], "4-of-8 = every other step")
        XCTAssertTrue(euclidMaskHit(3, k: 8, n: 8, rotate: 0), "K == N ⇒ every step a hit (mask OFF)")
        XCTAssertEqual((0...10).map { euclidMaskHitsBefore($0, k: 4, n: 8, rotate: 0) }, [0, 1, 1, 2, 2, 3, 3, 4, 4, 5, 5], "WAIT walk index; step 8→4 & 10→5 pin the cross-lap laps*K term")
        XCTAssertEqual([0, 3, 6].map { euclidMaskTieRun($0, k: 3, n: 8, rotate: 0) }, [2, 2, 1], "tie gaps at the 3-of-8 hits {0,3,6}; the 1 wraps into the next lap")
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
    // arpPatternAt (the cached-cases reader that replaced ArpPattern.allCases on the render path) indexes exactly like
    // allCases and clamps an out-of-range index to UP — byte-identical to the old inline guard. (efficiency 2026-08-29)
    func testArpPatternAtMatchesAllCasesAndClampsToUp() {
        for (i, c) in ArpPattern.allCases.enumerated() { XCTAssertEqual(arpPatternAt(i), c, "index \(i) matches allCases") }
        XCTAssertEqual(arpPatternAt(ArpPattern.allCases.count), .up, "an out-of-range index clamps to UP")
        XCTAssertEqual(arpPatternAt(-1), .up, "a negative index clamps to UP")
    }
    // VELOCITY (Paul 2026-09-07): the per-step lane resolver — override clamps to a legal note velocity 1…127 (never a
    // vel-0 note-on = a note-off), a PASSTHROUGH step returns nil, the column wraps the drawn length, empty pass = no passthrough.
    func testVelLaneStepOverridesClampsAndPassesThrough() {
        let lane = [30, 0, 200, 90]
        let pass = [0, 0, 0, 1]
        XCTAssertEqual(velLaneStep(lane: lane, pass: pass, steps: 4, col: 0), 30)
        XCTAssertEqual(velLaneStep(lane: lane, pass: pass, steps: 4, col: 1), 1, "0 in the lane clamps to 1 — never a vel-0 note-on")
        XCTAssertEqual(velLaneStep(lane: lane, pass: pass, steps: 4, col: 2), 127, "clamps to the 127 ceiling")
        XCTAssertNil(velLaneStep(lane: lane, pass: pass, steps: 4, col: 3), "a passthrough step returns nil (leave the note's own velocity)")
        XCTAssertEqual(velLaneStep(lane: lane, pass: pass, steps: 4, col: 5), 1, "col wraps the drawn length (5 mod 4 = 1)")
        XCTAssertEqual(velLaneStep(lane: lane, pass: [], steps: 4, col: 3), 90, "empty pass = no passthrough")
        XCTAssertNil(velLaneStep(lane: lane, pass: pass, steps: 0, col: 0), "zero steps = nil")
    }
}
