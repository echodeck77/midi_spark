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
    // EUCLIDEOUS INVERT (euclideousInvertLine) RETIRED 2026-10-10 — the dual-voice field-swap it exercised
    // (testEuclideousInvertSilencesAFreshHitOnlyLane / …InvertTwiceRestoresTheOriginalResolvedState /
    // …InvertSwapsBothFullyConfiguredSides, all deleted) has no successor to test here: Euclideous's own
    // MISS is now the engine-level `patternMiss` pattern-invert (Router.swift's `runEuclidLine`), covered by
    // RouterTests, not a pure Derivations-level field transform.
    func testEuclideousStepNoteSelCyclesAndWraps() {
        XCTAssertEqual(euclideousStepNoteSel(.all, by: 1), .n1)
        XCTAssertEqual(euclideousStepNoteSel(.all, by: -1), euclideousNoteSelCycle.last)
        XCTAssertFalse(euclideousNoteSelCycle.contains(.riff), ".riff must never appear in the cycle — Euclideous's cell has no preceding slot, so it would silently go silent")
        XCTAssertFalse(euclideousNoteSelCycle.contains(.arp), "same for .arp")
        // MELODY POP-UP (Paul 2026-10-10 ferry §2.1): "remove RANDOM from the NOTE choices... everywhere
        // it still appears" — the case itself stays decode-safe (an old doc with .random saved still
        // resolves and plays correctly), only the offered list shrinks.
        XCTAssertFalse(euclideousNoteSelCycle.contains(.random), "RANDOM must no longer be offered in the NOTE cycle")
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

    // MARK: - FERRY §2 — the riff-grid arrow's own pure per-lane step, no delay built into the math itself
    // (the TIMING half — whether the view calls this promptly — has no test-target reach; see the
    // production comment on `riffMarker`'s own declaration in EuclideousPage.swift).
    func testEuclideousRiffMarkerStepTracksTheCurrentPositionWithNoLagOfItsOwn() {
        let resolved = [1, 2, 0, 3, 4, 0, 5, 6]   // rank 0 = a grid rest at columns 2 and 5
        // A real rank at the live position: jump there immediately, regardless of where the marker was.
        XCTAssertEqual(euclideousRiffMarkerStep(current: (7, 6), riffOn: true, riffPosition: 0, resolved: resolved, wipeEvent: nil)!.col, 0)
        XCTAssertEqual(euclideousRiffMarkerStep(current: nil, riffOn: true, riffPosition: 3, resolved: resolved, wipeEvent: nil)!.col, 3)
        // Riff off: always nil, regardless of the old marker or the live position.
        XCTAssertNil(euclideousRiffMarkerStep(current: (0, 1), riffOn: false, riffPosition: 1, resolved: resolved, wipeEvent: nil))
        // A rest with NO matching fresh event: hold the previous marker exactly (rests stay out of scope).
        let held = euclideousRiffMarkerStep(current: (1, 2), riffOn: true, riffPosition: 2, resolved: resolved, wipeEvent: nil)
        XCTAssertEqual(held?.col, 1); XCTAssertEqual(held?.row, 2)
        // A rest with a matching FILL event: jump to where sound was actually produced.
        let ev = Router.EuclideousNoteViewEventSnapshot(onsetBeat: 0, durationBeat: 0, kind: 0, notes: [], column: 2, rank: 4)
        let filled = euclideousRiffMarkerStep(current: (1, 2), riffOn: true, riffPosition: 2, resolved: resolved, wipeEvent: ev)
        XCTAssertEqual(filled?.col, 2); XCTAssertEqual(filled?.row, 4)
        // Out-of-range position: hold, don't crash.
        XCTAssertEqual(euclideousRiffMarkerStep(current: (3, 5), riffOn: true, riffPosition: -1, resolved: resolved, wipeEvent: nil)?.col, 3)
    }

    // MARK: - FERRY §4 — the lane-output chip's 3-way style, all 4 combinations
    func testEuclideousLaneOutChipStyleCoversAllFourCombinations() {
        XCTAssertEqual(euclideousLaneOutChipStyle(routed: true, mainOn: true), .filled)
        XCTAssertEqual(euclideousLaneOutChipStyle(routed: true, mainOn: false), .hollowDashed)
        XCTAssertEqual(euclideousLaneOutChipStyle(routed: false, mainOn: true), .plain)
        XCTAssertEqual(euclideousLaneOutChipStyle(routed: false, mainOn: false), .plain)
    }

    // MARK: - FERRY §5 — the hit-flash style, the 4 literal cases plus the reasoned `.miss` extension
    func testEuclideousHitFlashStyleMatchesAllFourLiteralCasesPlusTheMissExtension() {
        XCTAssertEqual(euclideousHitFlashStyle(footerState: .hit(riffStep: 3), onRest: .skip), .solid, "a hit on a note is always solid")
        XCTAssertEqual(euclideousHitFlashStyle(footerState: .hitOnRest(riffStep: 2), onRest: .fill), .solid, "FILL substitutes a real note")
        XCTAssertEqual(euclideousHitFlashStyle(footerState: .hitOnRest(riffStep: 2), onRest: .skip), .outline, "SKIP plays nothing new")
        XCTAssertEqual(euclideousHitFlashStyle(footerState: .hitOnRest(riffStep: 2), onRest: .tie), .outline, "TIE plays nothing new — the held note carries on")
        XCTAssertEqual(euclideousHitFlashStyle(footerState: .miss, onRest: .skip), .outline, "nothing can ever sound here either — the reasoned extension")
        XCTAssertEqual(euclideousHitFlashStyle(footerState: nil, onRest: .skip), .solid, "no footer info at all (the regular BUILD-page editor) ⇒ unchanged default")
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
    func testEuclideousNoteViewIsHitWrapsAndReAnchorsOnSpanBoundaries() {
        let buf = euclideousNoteViewPattern(pulses: 1, steps: 4, rotate: 0, tilt: 0)   // a hit on step 0 only
        // FREE (spanBeats 0): hits recur every 4 beats at sub=1 forever.
        XCTAssertTrue(euclideousNoteViewIsHit(buf: buf, tickBeat: 0, sub: 1, spanBeats: 0, dir: .fwd))
        XCTAssertFalse(euclideousNoteViewIsHit(buf: buf, tickBeat: 1, sub: 1, spanBeats: 0, dir: .fwd))
        XCTAssertTrue(euclideousNoteViewIsHit(buf: buf, tickBeat: 8, sub: 1, spanBeats: 0, dir: .fwd))
        // A 2-beat SPAN re-anchors the pattern's own step-0 every 2 beats — tick beat 2 (a span boundary)
        // must ALSO read as a hit, even though it's "step 2" under the free-run reading above.
        XCTAssertTrue(euclideousNoteViewIsHit(buf: buf, tickBeat: 2, sub: 1, spanBeats: 2, dir: .fwd), "a span re-anchor must make beat 2 (the span's own step 0) a hit again")
    }
    // ── GATE FOLLOWS THE RHYTHM (Paul 2026-10-13 ferry) ─────────────────────────────────────────────────────
    func testEuclideousNextHitGapBeatsFindsTheRealNextHit() {
        // E(3,8), hits at buffer indices 0, 3, 6 (same known pattern the lap-hit-steps tests below use).
        let buf = euclideousNoteViewPattern(pulses: 3, steps: 8, rotate: 0, tilt: 0)
        XCTAssertEqual(euclideousNextHitGapBeats(buf: buf, n: 8, dir: .fwd, sub: 1, spanBeats: 0, fromBeat: 0, cap: 32), 3)
        XCTAssertEqual(euclideousNextHitGapBeats(buf: buf, n: 8, dir: .fwd, sub: 1, spanBeats: 0, fromBeat: 3, cap: 32), 3)
        XCTAssertEqual(euclideousNextHitGapBeats(buf: buf, n: 8, dir: .fwd, sub: 1, spanBeats: 0, fromBeat: 6, cap: 32), 2, "wraps across the end of the cycle to step 0 of the next lap")
    }
    func testEuclideousNextHitGapBeatsIncludesAResetThatFallsBeforeTheNextHit() {
        // Same E(3,8) pattern — free-run, the next hit from beat 0 is beat 3 (confirmed above). A 2-beat
        // RESET SPAN re-anchors step 0 at beat 2, which IS itself a hit — so the real next hit becomes
        // beat 2, not beat 3, "include a reset if one falls before it."
        let buf = euclideousNoteViewPattern(pulses: 3, steps: 8, rotate: 0, tilt: 0)
        XCTAssertEqual(euclideousNextHitGapBeats(buf: buf, n: 8, dir: .fwd, sub: 1, spanBeats: 2, fromBeat: 0, cap: 32), 2)
    }
    func testEuclideousNextHitGapBeatsFallsBackToTheCapOnAnAllRestPattern() {
        let buf = [Bool](repeating: false, count: 8)
        XCTAssertEqual(euclideousNextHitGapBeats(buf: buf, n: 8, dir: .fwd, sub: 1, spanBeats: 0, fromBeat: 0, cap: 16), 16)
    }
    /// Deliberately builds `buf` as a LARGER, PADDED array (24 slots, only the first 8 meaningful) — the
    /// direct regression guard for the real bug this function's own doc comment names: Router's real
    /// `euclidBuf` is a fixed, OVERSIZED scratch array, and relying on `buf.count` for the modulus (instead
    /// of the explicit `n`) silently wraps the cycle at the WRONG length.
    func testEuclideousNextHitGapBeatsIgnoresTrailingScratchBufferPadding() {
        var buf = euclideousNoteViewPattern(pulses: 3, steps: 8, rotate: 0, tilt: 0)
        buf += [Bool](repeating: false, count: 16)   // pad to 24 — buf.count would wrongly suggest a 24-step cycle
        XCTAssertEqual(euclideousNextHitGapBeats(buf: buf, n: 8, dir: .fwd, sub: 1, spanBeats: 0, fromBeat: 6, cap: 32), 2,
                       "must wrap at the real step count (8), not the padded buffer's own larger size (24)")
    }
    /// Cross-check against the SAME footer-prediction primitive the UI uses (`euclideousLapHitSteps`) — a
    /// real, rotated+tilted pattern, across all 3 Euclideous directions, confirming the new gap function can
    /// never silently disagree with what the step footers themselves predict (per the ferry's own "use the
    /// same prediction the step footers use"; the footer-mirror functions have a documented history of
    /// drifting from the real engine, so this is a standing regression guard, not a one-off sanity check).
    func testEuclideousNextHitGapBeatsAgreesWithTheFooterPredictionAcrossAllDirections() {
        let sub = 0.5
        for dir: EuclidDir in [.fwd, .bkw, .pingpong] {
            let buf = euclideousNoteViewPattern(pulses: 3, steps: 8, rotate: 2, tilt: 0.3)
            let hits = euclideousLapHitSteps(pulses: 3, steps: 8, rotate: 2, tilt: 0.3, patternMiss: false, customHits: nil, dir: dir)
            let cycleLen = euclidCycleLen(dir, n: buf.count)
            XCTAssertFalse(hits.isEmpty)
            for i in 0..<hits.count {
                let thisTick = hits[i].tick
                let nextTick = i + 1 < hits.count ? hits[i + 1].tick : hits[0].tick + cycleLen
                let expectedGap = Double(nextTick - thisTick) * sub
                let got = euclideousNextHitGapBeats(buf: buf, n: 8, dir: dir, sub: sub, spanBeats: 0, fromBeat: Double(thisTick) * sub, cap: cycleLen * 4)
                XCTAssertEqual(got, expectedGap, accuracy: 1e-9, "dir \(dir), hit \(i): tick \(thisTick) → next \(nextTick)")
            }
        }
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
    // MELODY TAB (Paul 2026-10-13 ferry) — the Acceptance checklist's own worked example: "ranks 1-5, TRANS
    // +2 → marks under ranks 3-7." A plain FORWARD walk over LENGTH 5 with identity ranks [1,2,3,4,5]
    // reaches walk positions 0...4 (ranks 1...5); +2 TRANSPOSE shifts every one of those to 3...7 — exactly
    // the ferry's own literal example, not re-derived from scratch.
    func testEuclideousRiffReachableRanksMatchesTheFerrysLiteralWorkedExample() {
        let reachable = euclideousRiffReachableRanks(dir: .forward, length: 5, stride: 1, rotate: 0,
                                                       ranks: [1, 2, 3, 4, 5], invert: false, transpose: 2)
        XCTAssertEqual(reachable, [3, 4, 5, 6, 7])
    }
    func testEuclideousRiffReachableRanksEmptyWhenEveryStepIsARest() {
        let reachable = euclideousRiffReachableRanks(dir: .forward, length: 4, stride: 1, rotate: 0,
                                                       ranks: [0, 0, 0, 0], invert: false, transpose: 0)
        XCTAssertTrue(reachable.isEmpty, "every step a rest ⇒ no note button is ever reachable")
    }
    func testEuclideousRiffReachableRanksAppliesInvertBeforeTranspose() {
        // Mirrors Router.swift's own order exactly: INVERT (9-r) first, THEN transpose. rank 1 → invert → 8
        // → +1 transpose → 9, out of range (dropped); rank 8 → invert → 1 → +1 → 2, kept.
        let reachable = euclideousRiffReachableRanks(dir: .forward, length: 2, stride: 1, rotate: 0,
                                                       ranks: [1, 8], invert: true, transpose: 1)
        XCTAssertEqual(reachable, [2], "rank 1 inverts to 8, +1 transpose runs off the top of the board (dropped) — only rank 8's own inverted+transposed result (2) survives")
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
    // LIT NOTES PLUS THE RIFF (Paul 2026-10-13, second same-day ferry), Elsewhere-on-page §1 — `euclideous
    // SilenceReason`'s "EMPTY RIFF" check now reads `riffOnResolved` (the genuinely live source of truth),
    // not the stale `useRiffResolved` (which still derives from the OLD, now-unread melodyMode/legacy
    // useRiff chain and can silently disagree once a lane's riff is toggled through the new MELODY tab) —
    // and a brand-new "NO NOTES" state fires when neither layer has anything to produce a note from.
    func testEuclideousSilenceReasonEmptyRiffReadsRiffOnNotStaleUseRiffResolved() {
        var line = EuclidLine(pulses: 4, steps: 8)
        line.enabled = true; line.emitterMask = 0b0001
        line.useRiff = false        // STALE legacy field — would read "riff off" if EMPTY RIFF mistakenly used it
        line.riffOn = true          // the GENUINE, live source of truth — riff is actually on
        XCTAssertEqual(euclideousSilenceReason(line: line, mainOutMask: 0b1111, riffAllRest: true), "EMPTY RIFF",
                       "must read riffOnResolved (true), not the disagreeing legacy useRiffResolved (false)")
    }
    func testEuclideousSilenceReasonNoNotesWhenNothingLitAndRiffOff() {
        var line = EuclidLine(pulses: 4, steps: 8)
        line.enabled = true; line.emitterMask = 0b0001
        line.riffOn = false; line.litNotes = 0; line.topLit = false; line.top2Lit = false
        XCTAssertEqual(euclideousSilenceReason(line: line, mainOutMask: 0b1111, riffAllRest: false), "NO NOTES")
        line.litNotes = 0b0000_0001   // lighting one note clears the silence
        XCTAssertNil(euclideousSilenceReason(line: line, mainOutMask: 0b1111, riffAllRest: false))
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
    func testEuclideousNoteViewMarkXReachesThePlayheadExactlyAtAgeZeroAndIsRemovedPastIt() {
        // Flipped 2026-10-11 (Paul: "right-to-left is what you expect on any piano roll") — the playhead
        // is now the LEFT edge (x=0), entry is the RIGHT edge (x=trackW).
        let trackW: CGFloat = 100
        XCTAssertEqual(euclideousNoteViewMarkX(tickBeat: 4, nowBeat: 4, windowBeats: 4, trackW: trackW), 0, "age 0 (playing exactly now) must land AT the playhead, the track's LEFT edge")
        XCTAssertEqual(euclideousNoteViewMarkX(tickBeat: 8, nowBeat: 4, windowBeats: 4, trackW: trackW), trackW, "age == windowBeats (just entered) must land at the far RIGHT edge")
        XCTAssertNil(euclideousNoteViewMarkX(tickBeat: 3, nowBeat: 4, windowBeats: 4, trackW: trackW), "§3.3: a mark that has already passed the playhead (age < 0) must be removed, not drawn past the edge")
        XCTAssertNil(euclideousNoteViewMarkX(tickBeat: 20, nowBeat: 4, windowBeats: 4, trackW: trackW), "a tick far beyond the look-ahead window isn't visible yet either")
    }
    func testEuclideousNoteViewWindowBarsShrinksOnlyWhenStepsWouldCrowd() {
        // A slow lane (sub=1 beat) at a generously wide track never needs to shrink below the full 2 bars.
        XCTAssertEqual(euclideousNoteViewWindowBars(fastestSub: 1, cyc: 4, trackW: 400), 2.0)
        // A very fast lane (sub well under a beat) on a narrow track must shrink — first to 1 bar, then ½.
        let narrow = euclideousNoteViewWindowBars(fastestSub: 0.03125, cyc: 4, trackW: 60)
        XCTAssertLessThan(narrow, 2.0, "a fast-enough lane on a narrow track must shrink the window below the 2-bar default")
        XCTAssertTrue([1.0, 0.5].contains(narrow), "only 1 or ½ bar are legal reduced values — never anything in between")
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

    // A SELF-AUDIT against the sequencer-panel ferry's own raw text (2026-10-14) found the first build's
    // per-lane reset re-anchored purely from absolute beat 0 (`columnStart(beat, resetSteps*stepBeats)`),
    // ignoring the LANES sequencer's own LEN entirely — §5's literal wording ("the count restarts when the
    // sequence loops, so the marks stay fixed") requires re-anchoring at the sequencer's own lap boundary
    // instead. stepBeats=1 for simplicity (step index == beat); resetSteps=3, loopSteps=5 — DELIBERATELY not
    // a divisor of the loop, so the two formulas can't coincidentally agree (exactly the gap that made this
    // invisible at the shipped default, LEN=8 with every reset option a divisor of 8).
    func testEuclideousLoopedResetOriginRealignsAtTheLoopBoundaryUnlikeThePlainUnboundedFormula() {
        // Within lap 1 (absStep 0..4): restarts at local step 0 and local step 3 (0%3==0, 3%3==0).
        XCTAssertEqual(euclideousLoopedResetOrigin(beat: 0, stepBeats: 1, resetSteps: 3, loopSteps: 5), 0)
        XCTAssertEqual(euclideousLoopedResetOrigin(beat: 2, stepBeats: 1, resetSteps: 3, loopSteps: 5), 0)
        XCTAssertEqual(euclideousLoopedResetOrigin(beat: 3, stepBeats: 1, resetSteps: 3, loopSteps: 5), 3)
        XCTAssertEqual(euclideousLoopedResetOrigin(beat: 4, stepBeats: 1, resetSteps: 3, loopSteps: 5), 3)
        // Lap 2 begins at absStep 5 — a NEW lap always restarts fresh at ITS OWN local step 0, even though
        // the plain unbounded formula (`columnStart`, resetSteps=3 from beat 0) would still be mid-cycle
        // (floor(5/3)*3 = 3, not 5) — this is the concrete divergence the fix exists to close.
        XCTAssertEqual(euclideousLoopedResetOrigin(beat: 5, stepBeats: 1, resetSteps: 3, loopSteps: 5), 5)
        XCTAssertEqual(columnStart(5, 3), 3, "the OLD unbounded formula disagrees here — the actual bug")
        XCTAssertEqual(euclideousLoopedResetOrigin(beat: 7, stepBeats: 1, resetSteps: 3, loopSteps: 5), 5)
        XCTAssertEqual(euclideousLoopedResetOrigin(beat: 8, stepBeats: 1, resetSteps: 3, loopSteps: 5), 8)
        // loopSteps <= 0 degenerates to the exact original unbounded behaviour (every OTHER reset path —
        // the legacy bars-count/span-ladder ones — has no LEN concept and must stay byte-identical).
        XCTAssertEqual(euclideousLoopedResetOrigin(beat: 5, stepBeats: 1, resetSteps: 3, loopSteps: 0), columnStart(5, 3))
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

    // §7 test 1 (equivalence sweep): for every N in {1,2,4,8} and every LEN 1...8, the masked function must
    // return EXACTLY what the old resetSteps-based function returns for resetSteps=N — at a NON-INTEGER
    // stepBeats (0.75, so a naive float-precision slip can't hide), over three full laps.
    func testEuclideousMaskedResetOriginEquivalenceSweepAtNonIntegerStepBeatsOverThreeLaps() {
        let stepBeats = 0.75
        for n in [1, 2, 4, 8] {
            let mask = euclideousStampMask(n)
            for len in 1...8 {
                let lapBeats = Double(len) * stepBeats
                var beat = 0.0
                while beat < lapBeats * 3 {
                    let old = euclideousLoopedResetOrigin(beat: beat, stepBeats: stepBeats, resetSteps: n, loopSteps: len)
                    let new = euclideousMaskedResetOrigin(beat: beat, stepBeats: stepBeats, mask: mask, loopSteps: len)
                    XCTAssertEqual(new, old, accuracy: 1e-9, "N=\(n) LEN=\(len) beat=\(beat)")
                    beat += stepBeats / 4
                }
            }
        }
    }

    // §7 test 2: a hand-placed mask on steps 1, 5, 7 (bits 0, 4, 6) at LEN 8.
    func testEuclideousMaskedResetOriginOnSteps157AtLen8() {
        let mask: UInt8 = (1 << 0) | (1 << 4) | (1 << 6)
        let sb = 1.0
        for beat in [0.0, 1, 2, 3] { XCTAssertEqual(euclideousMaskedResetOrigin(beat: beat, stepBeats: sb, mask: mask, loopSteps: 8), 0, "beat \(beat)") }
        for beat in [4.0, 5] { XCTAssertEqual(euclideousMaskedResetOrigin(beat: beat, stepBeats: sb, mask: mask, loopSteps: 8), 4, "beat \(beat)") }
        for beat in [6.0, 7] { XCTAssertEqual(euclideousMaskedResetOrigin(beat: beat, stepBeats: sb, mask: mask, loopSteps: 8), 6, "beat \(beat)") }
        // the next lap restarts at its own step 1 (local beat 8 = lap 2's step 0)
        XCTAssertEqual(euclideousMaskedResetOrigin(beat: 8, stepBeats: sb, mask: mask, loopSteps: 8), 8)
    }

    // §7 test 3: a mask on step 5 ONLY (bit 4), LEN 8 — steps 1-4 of lap k take step 5 of lap k-1 as their
    // origin (no restart at the lap boundary, since there's no mark on step 0/local step 0). Includes lap 0,
    // where this is a NEGATIVE origin (no previous lap exists yet) — deterministic, no crash.
    func testEuclideousMaskedResetOriginOnStep5OnlyAtLen8IncludesNegativeLap0Origin() {
        let mask: UInt8 = 1 << 4
        let sb = 1.0
        // Lap 0 (absStep 0...3): no mark has been reached yet this lap, so the origin falls back to the
        // PREVIOUS (imaginary) lap's own step 5 — one full lap (8 beats) before THIS lap's start (0), plus
        // the mark's own offset (4): 0 - 8 + 4 = -4.
        XCTAssertEqual(euclideousMaskedResetOrigin(beat: 0, stepBeats: sb, mask: mask, loopSteps: 8), -4)
        XCTAssertEqual(euclideousMaskedResetOrigin(beat: 3, stepBeats: sb, mask: mask, loopSteps: 8), -4)
        // Lap 0's own step 5 (beat 4) — now the mark IS at or before local step, origin becomes 4
        XCTAssertEqual(euclideousMaskedResetOrigin(beat: 4, stepBeats: sb, mask: mask, loopSteps: 8), 4)
        XCTAssertEqual(euclideousMaskedResetOrigin(beat: 7, stepBeats: sb, mask: mask, loopSteps: 8), 4)
        // Lap 1 (absStep 8...11, before its own step 5 at absStep 12): origin is LAP 0's step 5 (beat 4), not lap 1's own start (beat 8)
        XCTAssertEqual(euclideousMaskedResetOrigin(beat: 8, stepBeats: sb, mask: mask, loopSteps: 8), 4, "no restart at the lap boundary — still running from the previous lap's mark")
        XCTAssertEqual(euclideousMaskedResetOrigin(beat: 11, stepBeats: sb, mask: mask, loopSteps: 8), 4)
        XCTAssertEqual(euclideousMaskedResetOrigin(beat: 12, stepBeats: sb, mask: mask, loopSteps: 8), 12)
    }

    // §7 test 4: OFF (empty mask) — origin is 0 for every beat.
    func testEuclideousMaskedResetOriginOffIsAlwaysZero() {
        for beat in [0.0, 1, 5, 100, -5] {
            XCTAssertEqual(euclideousMaskedResetOrigin(beat: beat, stepBeats: 1, mask: 0, loopSteps: 8), 0)
        }
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

    func testEuclideousRestartAccessibleLabelPhrasesAllThreeCases() {
        XCTAssertEqual(euclideousRestartAccessibleLabel(mask: 0, loopSteps: 8), "off")
        XCTAssertEqual(euclideousRestartAccessibleLabel(mask: euclideousStampMask(4), loopSteps: 8), "every 4 steps")
        let marks157: UInt8 = (1 << 0) | (1 << 4) | (1 << 6)
        XCTAssertEqual(euclideousRestartAccessibleLabel(mask: marks157, loopSteps: 8), "3 custom points")
    }

    // §4.4's one-thumb hit-test: a touch inside the RESET box itself, in a column gap, or past the last
    // column misses (nil); a touch inside any of the 8 cells lands on that exact step.
    func testEuclideousRestartStepHitTestMatchesTheGridsOwnGeometry() {
        let labelW: CGFloat = 40, gap: CGFloat = 4, cellW: CGFloat = 30
        XCTAssertNil(euclideousRestartStepHitTest(localX: 20, labelW: labelW, gap: gap, cellW: cellW, columns: 8), "still inside the box")
        for step in 0..<8 {
            let cellStartX = labelW + gap + CGFloat(step) * (cellW + gap)
            XCTAssertEqual(euclideousRestartStepHitTest(localX: cellStartX + 1, labelW: labelW, gap: gap, cellW: cellW, columns: 8), step)
            XCTAssertEqual(euclideousRestartStepHitTest(localX: cellStartX + cellW - 1, labelW: labelW, gap: gap, cellW: cellW, columns: 8), step)
        }
        let gapX = labelW + gap + CGFloat(2) * (cellW + gap) - gap / 2
        XCTAssertNil(euclideousRestartStepHitTest(localX: gapX, labelW: labelW, gap: gap, cellW: cellW, columns: 8), "inside the gap between step 2 and step 3")
        let pastLastX = labelW + gap + CGFloat(8) * (cellW + gap)
        XCTAssertNil(euclideousRestartStepHitTest(localX: pastLastX, labelW: labelW, gap: gap, cellW: cellW, columns: 8), "past the last column")
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
    // RIFF-CELL WIPES / RESET PROGRESS (Paul 2026-10-10 ferry "riff-cell wipes, reset progress on lane
    // cards") — the two pure helpers behind the lane-card fill + header countdown. Built on the SAME
    // `columnStart` Router.swift itself uses to find the real reset boundary, so these can never visually
    // disagree with when the engine actually resets.
    func testEuclideousResetProgressSweepsZeroToOneWithinAWindow() {
        let spanBeats = 8.0
        XCTAssertEqual(euclideousResetProgress(liveBeat: 16.0, spanBeats: spanBeats), 0, accuracy: 1e-9, "0 right at a window start")
        XCTAssertEqual(euclideousResetProgress(liveBeat: 20.0, spanBeats: spanBeats), 0.5, accuracy: 1e-9, "~0.5 at the midpoint")
        XCTAssertEqual(euclideousResetProgress(liveBeat: 23.99, spanBeats: spanBeats), 23.99 / 8.0 - 2, accuracy: 1e-6, "approaching 1 just before the boundary")
        XCTAssertEqual(euclideousResetProgress(liveBeat: 24.0, spanBeats: spanBeats), 0, accuracy: 1e-9, "wraps back to ~0 just past the boundary, not past 1")
    }
    func testEuclideousResetProgressIsInertWhenSpanIsOff() {
        XCTAssertEqual(euclideousResetProgress(liveBeat: 100, spanBeats: 0), 0, "RESET SPAN off ⇒ 0, the caller's own job to hide the fill entirely")
    }
    func testEuclideousResetBarsRemainingCountsDownAndSnapsBack() {
        let cyc = 4.0   // one bar, 4 beats
        let spanBeats = 16.0   // 4-bar window
        XCTAssertEqual(euclideousResetBarsRemaining(liveBeat: 0, spanBeats: spanBeats, cyc: cyc, resetSpanBars: 4), 4, "reads the full count right at a window start")
        XCTAssertEqual(euclideousResetBarsRemaining(liveBeat: 4, spanBeats: spanBeats, cyc: cyc, resetSpanBars: 4), 3)
        XCTAssertEqual(euclideousResetBarsRemaining(liveBeat: 8, spanBeats: spanBeats, cyc: cyc, resetSpanBars: 4), 2)
        XCTAssertEqual(euclideousResetBarsRemaining(liveBeat: 12, spanBeats: spanBeats, cyc: cyc, resetSpanBars: 4), 1)
        XCTAssertEqual(euclideousResetBarsRemaining(liveBeat: 15.9, spanBeats: spanBeats, cyc: cyc, resetSpanBars: 4), 1, "never reads 0, even a hair before the boundary")
        XCTAssertEqual(euclideousResetBarsRemaining(liveBeat: 16, spanBeats: spanBeats, cyc: cyc, resetSpanBars: 4), 4, "snaps back to the full count across the boundary")
    }
    func testEuclideousResetBarsRemainingIsInertWhenOff() {
        XCTAssertEqual(euclideousResetBarsRemaining(liveBeat: 10, spanBeats: 0, cyc: 4, resetSpanBars: 0), 0)
        XCTAssertEqual(euclideousResetBarsRemaining(liveBeat: 10, spanBeats: 16, cyc: 0, resetSpanBars: 4), 0, "a zero bar length guards against division by zero")
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
    func testEuclideousTiltDetentFracSnapsNearCentreOnly() {
        XCTAssertEqual(euclideousTiltDetentFrac(0.5), 0.5)
        XCTAssertEqual(euclideousTiltDetentFrac(0.54), 0.5, "within ±6%")
        XCTAssertEqual(euclideousTiltDetentFrac(0.46), 0.5, "within ±6%, below centre too")
        XCTAssertEqual(euclideousTiltDetentFrac(0.57), 0.57, accuracy: 1e-9, "past the 6% band, passes through unchanged")
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
        XCTAssertEqual(euclideousSliderValueText(.tilt, l), "0", "zero carries no sign")
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
    func testEuclideousSliderAccessibilityStepIsPercentForGateAndTiltOnly() {
        XCTAssertEqual(euclideousSliderAccessibilityStep(.gate), 0.01)
        XCTAssertEqual(euclideousSliderAccessibilityStep(.tilt), 0.01)
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
    private func wtGeo(_ plan: EuclideousWalkTagPlan, lane: Int = 0) -> EuclideousThreadGeometry? {
        euclideousThreadGeometry(lane: lane, plan: plan, cellW: wtW, cellH: wtH, gap: wtGap)
    }
    private func wtSeat(_ lane: Int, col: Int, rank: Int) -> CGPoint {
        euclideousTagSeatCentre(lane: lane, col: col, rank: rank, cellW: wtW, cellH: wtH, gap: wtGap)
    }

    // Geometry ---------------------------------------------------------------------------------------
    func testWalkTagRectsMatchTheFerryTableAtTheReferenceBlock() {
        XCTAssertEqual(euclideousTagRect(lane: 0, blockW: 42.5, blockH: 29), CGRect(x: 2, y: 2.5, width: 18, height: 11))
        XCTAssertEqual(euclideousTagRect(lane: 1, blockW: 42.5, blockH: 29), CGRect(x: 22.5, y: 2.5, width: 18, height: 11))
        XCTAssertEqual(euclideousTagRect(lane: 2, blockW: 42.5, blockH: 29), CGRect(x: 2, y: 15.5, width: 18, height: 11))
        XCTAssertEqual(euclideousTagRect(lane: 3, blockW: 42.5, blockH: 29), CGRect(x: 22.5, y: 15.5, width: 18, height: 11))
        for lane in 0..<4 {
            let r = euclideousTagRect(lane: lane, blockW: 42.5, blockH: 29)
            let c = euclideousTagCentre(lane: lane, blockW: 42.5, blockH: 29)
            XCTAssertEqual(c.x, r.origin.x + 9, accuracy: 1e-9); XCTAssertEqual(c.y, r.origin.y + 5.5, accuracy: 1e-9)
        }
    }
    func testWalkTagScalesDownOnlyBelowTheReferenceBlock() {
        XCTAssertEqual(euclideousTagScale(blockW: 42.5, blockH: 29), 1)
        XCTAssertEqual(euclideousTagScale(blockW: 80, blockH: 60), 1, "a bigger block never enlarges the tag")
        let r = euclideousTagRect(lane: 3, blockW: 21.25, blockH: 14.5)
        XCTAssertEqual(r.width, 9, accuracy: 1e-9); XCTAssertLessThanOrEqual(r.maxX, 21.25); XCTAssertLessThanOrEqual(r.maxY, 14.5)
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
    func testWalkTagPingRepeatsTheEndStepAndTurnsOnTheSecondLanding() {
        let c = wtConfig(dir: .pingpong)   // positions by ordinal: 0…7, 7…0, 0, 1…  (period 16): the end steps repeat
        let base: Int64 = 16 * 9
        XCTAssertEqual(wtPlan(c, tick: base + 7)?.seatStep, 7); XCTAssertEqual(wtPlan(c, tick: base + 8)?.seatStep, 7)
        XCTAssertEqual(wtPlan(c, tick: base + 7)?.facingRight, true, "first landing at 8: the next move is zero-length, so it keeps pointing right")
        XCTAssertEqual(wtPlan(c, tick: base + 7)?.turned, false)
        XCTAssertEqual(wtPlan(c, tick: base + 8)?.facingRight, false, "second landing at 8: the next move goes back")
        XCTAssertEqual(wtPlan(c, tick: base + 8)?.turned, true, "…so the turn happens on this landing, not the first")
        XCTAssertNil(wtGeo(wtPlan(c, tick: base + 7)!), "the repeated end step is a zero-length move: no thread")
        XCTAssertEqual(wtPlan(c, tick: base + 15)?.facingRight, false, "first landing at 1 keeps pointing left")
        XCTAssertEqual(wtPlan(c, tick: base + 16)?.facingRight, true, "second landing at 1 turns right")
    }

    // Thread -----------------------------------------------------------------------------------------
    func testWalkTagThreadIsOneLineBetweenSeatCentresWithASolidDot() {
        let plan = wtPlan(wtConfig(), tick: 82)!   // FWD at step 3, next advance plays step 4
        XCTAssertEqual(plan.seatStep, 2); XCTAssertEqual(plan.dest?.step, 3)
        let g = wtGeo(plan)!
        XCTAssertEqual(g.segments, [EuclideousThreadSegment(from: wtSeat(0, col: 2, rank: 3), to: wtSeat(0, col: 3, rank: 4))])
        XCTAssertEqual(g.dot, wtSeat(0, col: 3, rank: 4)); XCTAssertFalse(g.hollowDot); XCTAssertFalse(g.isWrap)
    }
    func testWalkTagThreadToARestIsAHollowDotAtTheCurrentNotesHeight() {
        let ranks = [1, 2, 3, 4, 5, 6, 7, 0]   // step 8 is a rest
        let plan = wtPlan(wtConfig(), tick: 8 * 10 + 6, ranks: ranks)!   // at step 7 (row 7); the next advance lands on the rest
        let g = wtGeo(plan)!
        XCTAssertTrue(g.hollowDot)
        XCTAssertEqual(g.dot, wtSeat(0, col: 7, rank: 7), "column 8, at the current note's height")
        XCTAssertEqual(plan.dest, EuclideousTagDest(step: 7, rank: 7, isRest: true))
    }
    func testWalkTagFwdAtTheLastStepWrapsOutPastColumnEightAndInFromColumnOne() {
        let plan = wtPlan(wtConfig(), tick: 8 * 10 + 7)!   // FWD LEN 8 at step 8
        XCTAssertTrue(plan.isWrap)
        let g = wtGeo(plan)!
        let from = wtSeat(0, col: 7, rank: 8), to = wtSeat(0, col: 0, rank: 1)
        XCTAssertEqual(g.segments.count, 2)
        XCTAssertEqual(g.segments[0], EuclideousThreadSegment(from: from, to: CGPoint(x: 7 * (wtW + wtGap) + wtW + 2, y: from.y)))
        XCTAssertEqual(g.segments[1], EuclideousThreadSegment(from: CGPoint(x: -2, y: to.y), to: to))
        XCTAssertEqual(g.dot, to)
    }
    func testWalkTagRevAtStepOneWrapsOutBeforeColumnOneAndInFromPastColumnEight() {
        let plan = wtPlan(wtConfig(dir: .reverse), tick: 8 * 10 + 7)!   // REV: ordinal 7 → position 0 → step 1
        XCTAssertEqual(plan.seatStep, 0); XCTAssertEqual(plan.dest?.step, 7); XCTAssertTrue(plan.isWrap)
        let g = wtGeo(plan)!
        let from = wtSeat(0, col: 0, rank: 1), to = wtSeat(0, col: 7, rank: 8)
        XCTAssertEqual(g.segments[0], EuclideousThreadSegment(from: from, to: CGPoint(x: -2, y: from.y)))
        XCTAssertEqual(g.segments[1], EuclideousThreadSegment(from: CGPoint(x: 7 * (wtW + wtGap) + wtW + 2, y: to.y), to: to))
    }
    func testWalkTagFwdLenFiveAtStepFiveWrapsAtColumnFiveNotEight() {
        let plan = wtPlan(wtConfig(length: 5), tick: 5 * 20 + 4)!
        XCTAssertEqual(plan.seatStep, 4); XCTAssertTrue(plan.isWrap)
        let g = wtGeo(plan)!
        XCTAssertEqual(g.segments[0].to.x, 4 * (wtW + wtGap) + wtW + 2, accuracy: 1e-9)
        XCTAssertEqual(g.segments[1].from.x, -2, accuracy: 1e-9)
    }
    func testWalkTagWrapEndsFollowTheStepsTheWalkActuallyVisits() {
        // STRIDE 2 on LEN 8 only ever lands on 1,3,5,7: the loop's end blocks are columns 1 and 7.
        let r = euclideousWalkVisitedRange(dir: .forward, length: 8, stride: 2, rotate: 0)
        XCTAssertEqual(r.min, 0); XCTAssertEqual(r.max, 6)
        XCTAssertEqual(euclideousWalkVisitedRange(dir: .forward, length: 8, stride: 1, rotate: 0).max, 7)
        XCTAssertEqual(euclideousWalkVisitedRange(dir: .forward, length: 5, stride: 1, rotate: 3).max, 4)
    }
    func testWalkTagLockRestartIsOneStraightThreadNotAWrap() {
        // LOCK restarts the ordinal at every lap of the lane's own 8-tick pattern: the last hit's successor is
        // ordinal 0 again. With LEN 5 the walk sits on step 3 (ordinal 7 mod 5) and restarts at step 1.
        let c = wtConfig(length: 5, locked: true)
        let plan = wtPlan(c, tick: 8 * 10 + 7)!
        XCTAssertTrue(plan.isReset); XCTAssertFalse(plan.isWrap, "a restart is never drawn as a wrap")
        XCTAssertEqual(plan.facingRight, true, "…and the tag keeps pointing its walk direction")
        XCTAssertEqual(wtGeo(plan)?.segments.count, 1)
        XCTAssertEqual(wtGeo(plan)?.segments.first?.to, wtSeat(0, col: plan.dest!.step, rank: plan.dest!.rank))
    }
    func testWalkTagZeroLengthMoveHasNoThreadAndNoDot() {
        let plan = wtPlan(wtConfig(length: 1), tick: 100)!   // a one-step walk: the destination is the current seat
        XCTAssertEqual(plan.dest?.step, plan.seatStep)
        XCTAssertNil(wtGeo(plan))
        XCTAssertNil(euclideousTagDrawing(lane: 0, plan: plan, cellW: wtW, cellH: wtH, gap: wtGap).thread)
    }
    func testWalkTagTransportStoppedShowsTheTagWithNoThread() {
        let plan = wtPlan(wtConfig(), tick: 82, running: false)!
        XCTAssertNil(plan.nextSeconds); XCTAssertNil(plan.dest)
        let d = euclideousTagDrawing(lane: 0, plan: plan, cellW: wtW, cellH: wtH, gap: wtGap)
        XCTAssertNil(d.thread)
        XCTAssertEqual(d.centre, wtSeat(0, col: 2, rank: 3))
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

    // Timing (a fake clock: previous advance P, next advance H, all in seconds) --------------------------
    func testWalkTagFlightDurationIsEightyMsOrHalfTheIntervalIfShorter() {
        XCTAssertEqual(euclideousTagFlightDuration(previousAdvance: 10.00, nextAdvance: 10.25), 0.080, accuracy: 1e-12)
        XCTAssertEqual(euclideousTagFlightDuration(previousAdvance: 10.00, nextAdvance: 10.10), 0.050, accuracy: 1e-12)
        XCTAssertEqual(euclideousTagFlightDuration(previousAdvance: nil, nextAdvance: 10.10), 0.080, accuracy: 1e-12)
    }
    func testWalkTagDepartsBeforeTheHitAndArrivesOnIt() {
        // H − P = 0.25s → departs H − 0.080s, arrives H.
        let P = 10.0, H = 10.25
        XCTAssertEqual(euclideousTagPhase(now: H - 0.0801, previousAdvance: P, nextAdvance: H), .seated)
        guard case .inFlight(let rawStart) = euclideousTagPhase(now: H - 0.080, previousAdvance: P, nextAdvance: H) else { return XCTFail("departure") }
        XCTAssertEqual(rawStart, 0, accuracy: 1e-9)
        guard case .inFlight(let rawMid) = euclideousTagPhase(now: H - 0.040, previousAdvance: P, nextAdvance: H) else { return XCTFail("mid flight") }
        XCTAssertEqual(rawMid, 0.5, accuracy: 1e-9)
        XCTAssertEqual(euclideousTagPhase(now: H, previousAdvance: P, nextAdvance: H), .landed, "arrives exactly at the advance")
        // H − P = 0.10s → departs H − 0.050s.
        XCTAssertEqual(euclideousTagPhase(now: 10.0499, previousAdvance: 10.0, nextAdvance: 10.10), .seated)
        guard case .inFlight = euclideousTagPhase(now: 10.0501, previousAdvance: 10.0, nextAdvance: 10.10) else { return XCTFail("short-interval departure") }
    }
    func testWalkTagThreadIsVisibleFromTheAdvanceUntilDepartureHiddenInFlightAndBackFromTheNextOne() {
        let cfg = wtConfig()
        // A real plan, stepped through its flight with the clock: P = tick 82, H = tick 83 (0.125s apart at 120 BPM,
        // sub 0.25 ⇒ 0.125s/tick), so the flight is the last 0.0625s.
        func drawing(atTickFraction f: Double) -> EuclideousTagDrawing {
            let beat = (82.0 + f) * cfg.sub
            let plan = euclideousWalkTagPlan(cfg: cfg, ranks: [1, 2, 3, 4, 5, 6, 7, 8], beat: beat, secondsPerBeat: 0.5, polledStep: 2, running: true)!
            return euclideousTagDrawing(lane: 0, plan: plan, cellW: wtW, cellH: wtH, gap: wtGap)
        }
        XCTAssertNotNil(drawing(atTickFraction: 0.0).thread, "visible from the advance")
        XCTAssertNotNil(drawing(atTickFraction: 0.4).thread, "…until departure")
        XCTAssertNil(drawing(atTickFraction: 0.75).thread, "hidden in flight")
        XCTAssertNotEqual(drawing(atTickFraction: 0.75).centre, wtSeat(0, col: 2, rank: 3), "the tag has left its seat")
        let landed = euclideousWalkTagPlan(cfg: cfg, ranks: [1, 2, 3, 4, 5, 6, 7, 8], beat: (83.0 + 0.1) * cfg.sub, secondsPerBeat: 0.5, polledStep: 3, running: true)!
        XCTAssertEqual(landed.seatStep, 3)
        XCTAssertNotNil(euclideousTagDrawing(lane: 0, plan: landed, cellW: wtW, cellH: wtH, gap: wtGap).thread, "the next thread is visible from the next advance")
    }
    func testWalkTagArrivesOnTheDestinationSeatAndHollowSwitchesOnArrivalNotDuringTheMove() {
        let cfg = wtConfig()
        let ranks = [1, 2, 3, 4, 5, 6, 7, 0]
        func drawing(tick: Int64, f: Double, polled: Int) -> EuclideousTagDrawing {
            let plan = euclideousWalkTagPlan(cfg: cfg, ranks: ranks, beat: (Double(tick) + f) * cfg.sub, secondsPerBeat: 0.5, polledStep: polled, running: true)!
            return euclideousTagDrawing(lane: 0, plan: plan, cellW: wtW, cellH: wtH, gap: wtGap)
        }
        let flight = drawing(tick: 8 * 10 + 6, f: 0.9, polled: 6)          // approaching the rest on step 8
        XCTAssertFalse(flight.hollow, "still the note's filled tag while it travels")
        let arrived = drawing(tick: 8 * 10 + 7, f: 0.0, polled: 7)
        XCTAssertTrue(arrived.hollow, "hollow once it has landed on the rest")
        XCTAssertEqual(arrived.centre.x, wtSeat(0, col: 7, rank: 7).x, accuracy: 1e-6)
        XCTAssertEqual(arrived.centre.y, wtSeat(0, col: 7, rank: 7).y, accuracy: 1e-6)
    }
    func testWalkTagEaseIsAnEaseOutThroughTheEndpoints() {
        XCTAssertEqual(euclideousTagEase(0), 0); XCTAssertEqual(euclideousTagEase(1), 1)
        XCTAssertGreaterThan(euclideousTagEase(0.25), 0.25, "ease-out is ahead of linear early on")
        var last = -1.0
        for i in 0...20 { let v = euclideousTagEase(Double(i) / 20); XCTAssertGreaterThanOrEqual(v, last); last = v }
    }
    func testWalkTagWrapFlightFadesOutAlongTheExitPieceAndBackInAlongTheEntryPiece() {
        let plan = wtPlan(wtConfig(), tick: 8 * 10 + 7)!
        let g = wtGeo(plan)!
        let start = euclideousTagFlightPose(g, raw: 0), mid = euclideousTagFlightPose(g, raw: 0.5), end = euclideousTagFlightPose(g, raw: 1)
        XCTAssertEqual(start.opacity, 1, accuracy: 1e-9); XCTAssertEqual(start.centre, g.segments[0].from)
        XCTAssertEqual(mid.opacity, 0, accuracy: 1e-9, "fully faded by half the duration")
        XCTAssertEqual(end.opacity, 1, accuracy: 1e-9); XCTAssertEqual(end.centre.x, g.dot.x, accuracy: 1e-6); XCTAssertEqual(end.centre.y, g.dot.y, accuracy: 1e-6)
        let early = euclideousTagFlightPose(g, raw: 0.4), late = euclideousTagFlightPose(g, raw: 0.6)
        XCTAssertEqual(early.centre.y, g.segments[0].from.y, accuracy: 1e-9, "the exit piece is horizontal at the tag's own height")
        XCTAssertEqual(late.centre.y, g.segments[1].to.y, accuracy: 1e-9, "the entry piece is horizontal at the destination's height")
    }
    func testWalkTagTurnFlipsAboutItsCentreStartingTwentyMsAfterArrival() {
        let cfg = wtConfig(sub: 1.0, dir: .pendulum)   // a quarter-note tick (0.5s at 120 BPM): room for the 120ms flip before the next departure
        let base: Int64 = 14 * 12
        func drawing(secondsAfterLanding t: Double) -> EuclideousTagDrawing {
            let beat = (Double(base + 7) * cfg.sub) + t / 0.5
            let plan = euclideousWalkTagPlan(cfg: cfg, ranks: [1, 2, 3, 4, 5, 6, 7, 8], beat: beat, secondsPerBeat: 0.5, polledStep: 7, running: true)!
            return euclideousTagDrawing(lane: 0, plan: plan, cellW: wtW, cellH: wtH, gap: wtGap)
        }
        XCTAssertEqual(drawing(secondsAfterLanding: 0.005).scaleX, 1, accuracy: 1e-9)
        XCTAssertTrue(drawing(secondsAfterLanding: 0.005).pointsRight, "still facing the way it arrived for the first 20ms")
        XCTAssertEqual(drawing(secondsAfterLanding: 0.070).scaleX, 0, accuracy: 1e-6, "edge-on halfway through the 100ms flip")
        let done = drawing(secondsAfterLanding: 0.118)
        XCTAssertLessThan(done.scaleX, -0.9, "scaleX has swept 1 → 0 → −1")
        XCTAssertNotNil(drawing(secondsAfterLanding: 0.0).thread, "the new thread appears on arrival, not after the flip")
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

    func testWalkTagTurnFlipCarriesThroughAFlightThatSetsOffBeforeItHasFinished() {
        // 1/16 at 120 BPM = 125ms between hits ⇒ the flight departs 62.5ms after landing, mid-flip (flip = 20…120ms).
        let cfg = wtConfig(sub: 0.25, dir: .pendulum)
        let base: Int64 = 14 * 12
        let beat = Double(base + 7) * cfg.sub + 0.085 / 0.5   // 85ms after landing on step 8: in flight, 65ms into the flip
        let plan = euclideousWalkTagPlan(cfg: cfg, ranks: [1, 2, 3, 4, 5, 6, 7, 8], beat: beat, secondsPerBeat: 0.5, polledStep: 7, running: true)!
        let d = euclideousTagDrawing(lane: 0, plan: plan, cellW: wtW, cellH: wtH, gap: wtGap)
        XCTAssertNil(d.thread, "in flight")
        XCTAssertEqual(d.scaleX, 1 - 2 * (0.085 - 0.020) / 0.100, accuracy: 1e-6, "the flip is still running mid-flight")
        XCTAssertTrue(d.pointsRight, "still facing the way it arrived until the flip completes")
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

    // §10.1 — ring state, for each output and all 16 lane-mask combinations.
    func testFourfoldRingStateFollowsLanesAcrossAllSixteenCombinations() {
        for output in 0..<4 {
            for combo in 0..<16 {
                // bit i of `combo` = lane i routed to THIS output; the OTHER outputs' bits are noise that must not matter.
                let noise: UInt8 = 0b1111 & ~(1 << UInt8(output))
                let masks: [UInt8] = (0..<4).map { lane in
                    let routed = (combo >> lane) & 1 != 0
                    return (routed ? (1 << UInt8(output)) : 0) | (lane % 2 == 0 ? noise : 0)
                }
                let on = euclideousOutputRingState(output: output, laneMasks: masks, mainOutMask: 0b1111)
                XCTAssertEqual(on.lit, (0..<4).map { (combo >> $0) & 1 != 0 }, "output \(output) combo \(combo): quarters = lanes 0 TL, 1 TR, 2 BL, 3 BR")
                XCTAssertEqual(on.mode, combo == 0 ? .onUnrouted : .onRouted, "output \(output) combo \(combo)")
                XCTAssertFalse(on.dashed)
                let off = euclideousOutputRingState(output: output, laneMasks: masks, mainOutMask: 0b1111 & ~(1 << UInt8(output)))
                XCTAssertEqual(off.mode, .off, "output \(output) combo \(combo): the output's own main bit off → dashed for every combination")
                XCTAssertTrue(off.dashed)
                XCTAssertEqual(off.lit, on.lit, "…and lit quarters keep their lane colour")
                // another output's main bit must not affect this ring
                let other = euclideousOutputRingState(output: output, laneMasks: masks, mainOutMask: 1 << UInt8(output))
                XCTAssertEqual(other.mode, on.mode)
            }
        }
        XCTAssertEqual(euclideousRingQuarterCentreDegrees, [315, 45, 225, 135], "lane 0 TL … lane 3 BR, clockwise from 12 o'clock")
        XCTAssertEqual(euclideousRingArcDegrees, 66)
    }
    func testFourfoldRingAcceptanceExampleLane3ToBLanes1And4ToA() {
        // §11: lane 3 → B, lanes 1 and 4 → A. Lane indices are 0-based here.
        let masks: [UInt8] = [0b0001, 0, 0b0010, 0b0001]
        let a = euclideousOutputRingState(output: 0, laneMasks: masks, mainOutMask: 0b1111)
        XCTAssertEqual(a.lit, [true, false, false, true], "A: top-left (lane 1) and bottom-right (lane 4)")
        let b = euclideousOutputRingState(output: 1, laneMasks: masks, mainOutMask: 0b1111)
        XCTAssertEqual(b.lit, [false, false, true, false], "B: bottom-left (lane 3)")
        for o in 2..<4 { XCTAssertEqual(euclideousOutputRingState(output: o, laneMasks: masks, mainOutMask: 0b1111).mode, .onUnrouted) }
    }

    // §10.3 — the lane-card DIM half (RESTART CHAINS ferry §10: the ring half moved to MIX, tested below).
    func testFourfoldCuesPulseDimsNothingAndTraceDimsUnroutedLanes() {
        let masks: [UInt8] = [0b0001, 0b0010, 0b0010, 0b0001]   // lanes 0,3 → A; lanes 1,2 → B
        XCTAssertEqual(euclideousOutputCues(output: 0, laneMasks: masks, mode: .pulse),
                       [.none, .none, .none, .none], "a tap dims no lane card")
        XCTAssertEqual(euclideousOutputCues(output: 0, laneMasks: masks, mode: .trace),
                       [.none, .dim, .dim, .none], "hold A: lanes 2 and 3 (routed to B) drop to 42%, lanes 1 and 4 (routed to A) don't")
        XCTAssertEqual(euclideousOutputCues(output: 2, laneMasks: masks, mode: .trace),
                       [.dim, .dim, .dim, .dim], "no lane routed to C: all four dim")
        let all: [UInt8] = [0b1000, 0b1000, 0b1000, 0b1000]
        XCTAssertFalse(euclideousOutputCues(output: 3, laneMasks: all, mode: .trace).contains(.dim), "every lane routed: none dim")
    }
    // §10.2/§18 — "Trace targets... each lane dims or not, and the ring goes on its MIX OUT button when MIX
    // is showing, or once on the MIX tab otherwise." Cover no lane routed (no ring either) and every lane
    // routed (one ring per lane when MIX shows, one ring total on the tab otherwise).
    func testFourfoldRingTargetsGoOnMixButtonsWhenMixShowsOrOnceOnTheTabOtherwise() {
        let masks: [UInt8] = [0b0001, 0b0010, 0b0010, 0b0001]   // lanes 0,3 → A; lanes 1,2 → B
        XCTAssertEqual(euclideousOutputRingTargets(output: 0, laneMasks: masks, panelShowsMix: true),
                       [.mixOutButton(lane: 0), .mixOutButton(lane: 3)], "MIX showing: one ring per routed lane's own button")
        XCTAssertEqual(euclideousOutputRingTargets(output: 0, laneMasks: masks, panelShowsMix: false),
                       [.mixTab], "another tab showing: ONE ring on the MIX tab, however many lanes are routed")
        XCTAssertEqual(euclideousOutputRingTargets(output: 2, laneMasks: masks, panelShowsMix: true), [],
                       "no lane routed to C: no ring at all, MIX showing")
        XCTAssertEqual(euclideousOutputRingTargets(output: 2, laneMasks: masks, panelShowsMix: false), [],
                       "no lane routed to C: no ring at all, another tab showing")
        let all: [UInt8] = [0b1000, 0b1000, 0b1000, 0b1000]
        XCTAssertEqual(euclideousOutputRingTargets(output: 3, laneMasks: all, panelShowsMix: true).count, 4, "every lane routed, MIX showing: 4 rings")
        XCTAssertEqual(euclideousOutputRingTargets(output: 3, laneMasks: all, panelShowsMix: false), [.mixTab], "every lane routed, another tab showing: still just the one tab ring")
    }

    // §10.3 — the layout ladder.
    private typealias HM = EuclideousHeaderMetrics
    private func hdrLayout(_ containerW: CGFloat, landscape: Bool) -> EuclideousHeaderLayout {
        if landscape {
            let c = euclideousLandscapeColumns(containerW: containerW)
            return euclideousHeaderLayout(containerW: containerW, isLandscape: true, riffLeadingX: c.riffLeadingX, laneCentreX: c.laneCentreX)
        }
        return euclideousHeaderLayout(containerW: containerW, isLandscape: false, riffLeadingX: 0, laneCentreX: containerW / 2)
    }
    /// no two groups on a row closer than the layout's gap; nothing past either container edge.
    private func assertHeaderInvariants(_ l: EuclideousHeaderLayout, _ containerW: CGFloat, _ msg: String, file: StaticString = #filePath, line: UInt = #line) {
        let frames = [l.brand, l.outputs, l.notes, l.utilities]
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
    /// The x of the middle of the FOUR RINGS (not the OUTPUTS group): the group's x + the caption's lead + half the rings' span.
    private func ringsCentre(_ l: EuclideousHeaderLayout) -> CGFloat { l.outputs.x + l.widths.outputsLead + l.widths.ringsSpan / 2 }
    func testFourfoldGroupWidthsComeFromTheSameConstantsTheViewsDrawWith() {
        let f = euclideousHeaderGroupWidths(compact: false)
        let wordmark: CGFloat = 8 * 11 * 0.76          // 8 chars × 11pt × (0.6 advance + 0.16 tracking)
        let caption: CGFloat = 3 * 9 * 0.74            // "OUT": 3 chars × 9pt × (0.6 + 0.14)
        XCTAssertEqual(f.brand, 13 + 8 + wordmark + 16 + 88, accuracy: 1e-9)
        XCTAssertEqual(f.brand, 192, accuracy: 0.2)
        XCTAssertEqual(f.outputs, caption + 4 + 176, accuracy: 1e-9)
        XCTAssertEqual(f.outputsLead, caption + 4, accuracy: 1e-9, "the caption + sp4 before the first ring's target")
        XCTAssertEqual(f.ringsSpan, 176, accuracy: 1e-9)
        // UTILITIES is 3 icons (presets · SWING, 2026-10-17 · settings): 2×t / 3×t before/after.
        XCTAssertEqual(f.notes, 312); XCTAssertEqual(f.utilities, 132)
        XCTAssertEqual(HM.segmentedWidth, 184)
        let c = euclideousHeaderGroupWidths(compact: true)
        XCTAssertEqual(c.brand, 93); XCTAssertEqual(c.outputs, 160); XCTAssertEqual(c.utilities, 108)
        XCTAssertEqual(c.outputsLead, 0, "layout C hides the caption: the group IS the rings")
        XCTAssertEqual(c.brand + c.outputs + c.utilities + 2 * c.gap, 377, "layout C's row 1 — was ≈341 at 2 UTILITIES icons, 377 now that SWING made it 3")
        XCTAssertEqual(HM.topMargin, 9, "a 44pt row centred on the 31pt centre line")
    }
    // WIDENED from 1158 → 1300 (2026-10-17, UTILITIES grew from 2 to 3 icons — the SWING icon — so the
    // fully-unclamped "comfortable A" case now needs a wider container; 1158 now lands in the SLID case
    // the sibling test below covers).
    func testFourfoldLayoutAAt1300PutsNotesOnTheRiffPanelAndRingsOnTheLaneGutter() {
        let l = hdrLayout(1300, landscape: true)
        XCTAssertEqual(l.kind, .a); XCTAssertEqual(l.rowCount, 1); XCTAssertEqual(l.height, 44)
        let cols = euclideousLandscapeColumns(containerW: 1300)
        XCTAssertEqual(l.brand.x, 0); XCTAssertEqual(l.utilities.x + l.utilities.width, 1300, accuracy: 1e-9)
        XCTAssertEqual(l.notes.x, cols.riffLeadingX, accuracy: 1e-9, "NOTES' leading edge on the riff panel's")
        XCTAssertEqual(ringsCentre(l), cols.laneCentreX, accuracy: 1e-9, "the RINGS (not the caption-inclusive group) centred on the lane grid's centre (the 2×2's vertical gutter)")
        XCTAssertNotEqual(l.outputs.x + l.outputs.width / 2, cols.laneCentreX, "…so the caption-inclusive group is NOT what's centred")
        assertHeaderInvariants(l, 1300, "A@1300")
    }
    // WIDENED from 868 → 900 for the same reason as the test above — 900 is where the 3-icon UTILITIES
    // formula now reproduces the same "A, but both groups had to slide" case 868 used to demonstrate.
    func testFourfoldLayoutASlidesNotesAndRingsAt900() {
        let l = hdrLayout(900, landscape: true)
        let cols = euclideousLandscapeColumns(containerW: 900)
        XCTAssertEqual(l.kind, .a)
        XCTAssertLessThan(l.notes.x, cols.riffLeadingX, "NOTES slid left to clear UTILITIES")
        XCTAssertEqual(l.utilities.x - (l.notes.x + l.notes.width), 16, accuracy: 1e-9)
        XCTAssertGreaterThan(ringsCentre(l), cols.laneCentreX, "rings slid right to clear BRAND")
        XCTAssertEqual(l.outputs.x - (l.brand.x + l.brand.width), 16, accuracy: 1e-9)
        assertHeaderInvariants(l, 900, "A@900")
    }
    func testFourfoldLayoutBAt600AndCAt343() {
        let b = hdrLayout(600, landscape: false)
        XCTAssertEqual(b.kind, .b); XCTAssertEqual(b.rowCount, 2); XCTAssertEqual(b.height, 44 + 4 + 44)
        XCTAssertEqual(b.notes.row, 1); XCTAssertEqual(b.notes.x, 0, "NOTES on row 2's leading edge")
        XCTAssertEqual([b.brand.row, b.outputs.row, b.utilities.row], [0, 0, 0])
        assertHeaderInvariants(b, 600, "B@600")
        // WIDENED from 343 → 380 (2026-10-17): UTILITIES' 3rd icon (SWING) raised row-1's real floor from
        // 341 to 377 — 343 no longer fits at all (would overflow its own trailing edge).
        let c = hdrLayout(380, landscape: false)
        XCTAssertEqual(c.kind, .c); XCTAssertTrue(c.compact)
        XCTAssertEqual(c.widths.gap, 8)
        assertHeaderInvariants(c, 380, "C@380")
        // C's floor: the narrowest container it fits is its own row-1 need (377, was 341 at 2 icons) → page width 409.
        XCTAssertEqual(c.widths.brand + c.widths.outputs + c.widths.utilities + 2 * c.widths.gap + 2 * 16, 409)
        // a landscape page too narrow for A falls to B, never A.
        XCTAssertEqual(hdrLayout(700, landscape: true).kind, .b)
        // portrait never uses A, however wide.
        XCTAssertEqual(hdrLayout(1200, landscape: false).kind, .b)
    }
    func testFourfoldRingsCentreOnTheLaneGutterInBWhenNothingClampsThem() {
        // Portrait B at 900: lane grid spans the container, so the gutter is its centre; nothing clamps the rings.
        let b = hdrLayout(900, landscape: false)
        XCTAssertEqual(b.kind, .b)
        XCTAssertEqual(ringsCentre(b), 450, accuracy: 1e-9)
        assertHeaderInvariants(b, 900, "B@900")
        // A landscape window too narrow for A: B uses the LANE column's gutter, not the container's centre.
        let lb = hdrLayout(760, landscape: true)
        let cols = euclideousLandscapeColumns(containerW: 760)
        XCTAssertEqual(lb.kind, .b)
        XCTAssertEqual(ringsCentre(lb), max(cols.laneCentreX, lb.widths.brand + lb.widths.gap + lb.widths.outputsLead + lb.widths.ringsSpan / 2), accuracy: 1e-9)
        assertHeaderInvariants(lb, 760, "B@760 landscape")
        // C has no caption, so its group and its rings share one centre.
        // WIDENED from 520 → 560 (2026-10-17): UTILITIES' 3rd icon raised the B/C threshold from ≈512 to
        // ≈556 — 520 now falls on the C side instead of demonstrating "just above the line, still B".
        let c = hdrLayout(560, landscape: false)
        XCTAssertEqual(c.kind, .b) // 560 ≥ 556: still B
        let c2 = hdrLayout(500, landscape: false)
        XCTAssertEqual(c2.kind, .c)
        XCTAssertEqual(ringsCentre(c2), c2.outputs.x + c2.outputs.width / 2, accuracy: 1e-9)
    }
    func testFourfoldLayoutAFitsExactlyAtItsOwnNeedWithEveryGroupPacked() {
        let w = euclideousHeaderGroupWidths(compact: false)
        let need = w.brand + w.outputs + w.notes + w.utilities + 3 * w.gap
        let l = hdrLayout(need, landscape: true)
        XCTAssertEqual(l.kind, .a)
        assertHeaderInvariants(l, need, "A at its exact need")
        XCTAssertEqual(hdrLayout(need - 1, landscape: true).kind, .b, "one point narrower falls to B")
        for cw in stride(from: need, through: need + 400, by: 7) { assertHeaderInvariants(hdrLayout(cw, landscape: true), cw, "A@\(cw)") }
    }

    // §4.8 — the flare envelope.
    func testFourfoldRingFlareEnvelopeIsPeakAtTheStrikeAndGoneByTheAfterglow() {
        XCTAssertEqual(euclideousRingFlare(ageSteps: 0), 1, accuracy: 1e-12)
        XCTAssertEqual(euclideousRingFlare(ageSteps: -0.5), 0, "a strike that hasn't happened yet")
        XCTAssertEqual(euclideousRingFlare(ageSteps: euclideousFlareAfterglowSteps), 0, accuracy: 1e-12)
        XCTAssertEqual(euclideousRingFlare(ageSteps: 3), 0)
        var last = 2.0
        for i in 0...60 { let v = euclideousRingFlare(ageSteps: Double(i) * 0.03); XCTAssertLessThanOrEqual(v, last + 1e-12); last = v }
        XCTAssertEqual(euclideousFlareAfterglowSteps, 1.5); XCTAssertEqual(euclideousFlareBurstSteps, 0.35)
    }
    // The painter's disc/letter decision (held OFF must still get its light disc, or the ink letter vanishes on the ground).
    func testFourfoldRingDiscAndLetterTable() {
        typealias M = EuclideousOutputRingMode
        for mode in [M.onRouted, .onUnrouted, .off] {
            XCTAssertEqual(euclideousRingDisc(mode: mode, held: true), .held, "held always has the light disc, even OFF (\(mode))")
            XCTAssertEqual(euclideousRingLetterTone(mode: mode, held: true), .ink)
        }
        XCTAssertEqual(euclideousRingDisc(mode: .onRouted, held: false), .base)
        XCTAssertEqual(euclideousRingDisc(mode: .onUnrouted, held: false), .base)
        XCTAssertEqual(euclideousRingDisc(mode: .off, held: false), .none, "OFF: no disc, the ground shows through")
        XCTAssertEqual(euclideousRingLetterTone(mode: .onRouted, held: false), .on)
        XCTAssertEqual(euclideousRingLetterTone(mode: .onUnrouted, held: false), .unrouted)
        XCTAssertEqual(euclideousRingLetterTone(mode: .off, held: false), .off)
        // the invariant that was broken: an INK letter never sits without the light disc.
        for mode in [M.onRouted, .onUnrouted, .off] { for held in [false, true] {
            if euclideousRingLetterTone(mode: mode, held: held) == .ink { XCTAssertEqual(euclideousRingDisc(mode: mode, held: held), .held) }
        } }
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
    func testFourfoldLaneMasksReadTheSameFieldLaneOutRowEdits() {
        var a = EuclidLine(); a.emitterMask = 0b0101
        var b = EuclidLine(); b.emitterMask = nil
        XCTAssertEqual(euclideousLaneMasks([a, b]), [0b0101, 0, 0, 0], "nil = routed nowhere (as laneOutRow reads it); padded to 4")
    }
    func testFourfoldKeySpokenNameSpellsOutEveryScale() {
        XCTAssertEqual(euclideousKeySpokenName(root: 0, type: .naturalMinor), "C minor")
        XCTAssertEqual(euclideousKeySpokenName(root: 6, type: .mixolydian), "F sharp mixolydian")
        for t in ScaleType.allCases { XCTAssertFalse(euclideousKeySpokenName(root: 3, type: t).hasSuffix("MIXO"), "\(t)") }
        XCTAssertEqual(HM.wordmarkWidth, 8 * 11 * 0.76, accuracy: 1e-9); XCTAssertEqual(HM.captionWidth, 3 * 9 * 0.74, accuracy: 1e-9)
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

    // MARK: - Walk tags follow-ups (2026-10-15): GAPS / WITH threads, the footer under LOCK + ADV STEP

    private func listenLines(_ mode: EuclideousRhythmMode, laneRate: ArpRate = .r1_8, partnerRate: ArpRate = .r1_8) -> [EuclidLine] {
        var partner = EuclidLine(target: 0, pulses: 3, steps: 8, rate: partnerRate, useRiff: false, sourceMode: .midi)
        partner.restartMask = 0
        var lane = EuclidLine(target: 0, pulses: 5, steps: 8, rate: laneRate, useRiff: true, sourceMode: .midi)
        lane.restartMask = 0; lane.listenRhythmMode = mode; lane.listenRhythmPartner = 0
        return [partner, lane]
    }
    private func listenCfg(_ mode: EuclideousRhythmMode, laneRate: ArpRate = .r1_8, partnerRate: ArpRate = .r1_8) -> EuclideousWalkLaneConfig {
        euclideousWalkLaneConfig(lane: 1, lines: listenLines(mode, laneRate: laneRate, partnerRate: partnerRate), cyc: 4, resetSpanBars: 0,
                                 lanesSeqRate: .oneBar, lanesSeqLen: 8)!
    }
    // WITH and GAPS are exact complements on the lane's own raw hits, and neither changes the walk's ordinal (the engine counts
    // every raw hit — "the lane keeps its own rhythm" — and only gates whether a tick STRIKES).
    func testWalkTagWithAndGapsSplitTheLanesRawHitsAndLeaveTheOrdinalAlone() {
        for (laneRate, partnerRate) in [(ArpRate.r1_8, ArpRate.r1_8), (.r1_16, .r1_8), (.r1_8, .r1_16)] {
            let w = listenCfg(.with, laneRate: laneRate, partnerRate: partnerRate), g = listenCfg(.gaps, laneRate: laneRate, partnerRate: partnerRate)
            XCTAssertNotNil(w.listen); XCTAssertNotNil(g.listen)
            var withStrikes = 0, gapsStrikes = 0, raw = 0
            for tick in Int64(0)..<128 {
                let tw = euclideousWalkTick(w, tick: tick), tg = euclideousWalkTick(g, tick: tick)
                XCTAssertEqual(tw.isHit, tg.isHit, "the raw pattern is the lane's own either way")
                XCTAssertEqual(tw.advOrd, tg.advOrd, "tick \(tick): the filter never changes the walk ordinal")
                XCTAssertEqual(tw.playedStep, tg.playedStep)
                if tw.isHit {
                    raw += 1
                    XCTAssertNotEqual(tw.strikes, tg.strikes, "tick \(tick) (\(laneRate)/\(partnerRate)): exactly one of WITH / GAPS strikes a raw hit")
                    if tw.strikes { withStrikes += 1 } else { gapsStrikes += 1 }
                } else {
                    XCTAssertFalse(tw.strikes); XCTAssertFalse(tg.strikes)
                }
            }
            XCTAssertGreaterThan(withStrikes, 0, "\(laneRate)/\(partnerRate): WITH strikes somewhere (not vacuous)")
            XCTAssertGreaterThan(gapsStrikes, 0, "\(laneRate)/\(partnerRate): GAPS strikes somewhere (not vacuous)")
            XCTAssertEqual(withStrikes + gapsStrikes, raw)
        }
        // no filter: strikes == isHit
        let plain = euclideousWalkLaneConfig(lane: 0, lines: listenLines(.gaps), cyc: 4, resetSpanBars: 0, lanesSeqRate: .oneBar, lanesSeqLen: 8)!
        XCTAssertNil(plain.listen, "a lane with no WITH / GAPS mode has no filter")
        for tick in Int64(0)..<64 { let t = euclideousWalkTick(plain, tick: tick); XCTAssertEqual(t.strikes, t.isHit) }
    }
    // THE FEATURE: a GAPS lane gets its thread to the next tick that will actually SOUND, not to a raw hit the filter will silence.
    func testWalkTagGapsLaneThreadsToItsNextStrikeNotToASilencedHit() {
        let cfg = listenCfg(.gaps)
        var unfiltered = cfg; unfiltered.listen = nil
        let ranks = [1, 2, 3, 4, 5, 6, 7, 8]
        // two consecutive STRIKES with a silenced raw hit between them
        var pair: (a: Int64, b: Int64)? = nil
        var lastStrike: Int64? = nil, silencedSince = false
        for tick in Int64(0)..<128 {
            let t = euclideousWalkTick(cfg, tick: tick)
            if t.isHit && !t.strikes { silencedSince = true }
            if t.strikes {
                if let a = lastStrike, silencedSince { pair = (a, tick); break }
                lastStrike = tick; silencedSince = false
            }
        }
        guard let (a, b) = pair else { return XCTFail("the scenario needs a strike, a silenced hit, then a strike") }
        let beat = euclideousWalkRealBeat(cfg, tick: a) + 0.01
        let spb = 0.5
        let plan = euclideousWalkTagPlan(cfg: cfg, ranks: ranks, beat: beat, secondsPerBeat: spb,
                                         polledStep: euclideousWalkTick(cfg, tick: a).playedStep, running: true)
        guard let plan, let dest = plan.dest, let next = plan.nextSeconds else { return XCTFail("a GAPS lane should get a thread (a destination + a scheduled arrival)") }
        XCTAssertEqual(dest.step, euclideousWalkTick(cfg, tick: b).playedStep, "the thread ends at the step the next STRIKE lands on")
        XCTAssertEqual(next, (euclideousWalkRealBeat(cfg, tick: b) - beat) * spb, accuracy: 1e-9, "…and arrives at that strike's onset")
        // Ignoring the filter (the pre-fix behaviour) would have aimed at the silenced hit, sooner and at a different step.
        let old = euclideousWalkTagPlan(cfg: unfiltered, ranks: ranks, beat: beat, secondsPerBeat: spb,
                                        polledStep: euclideousWalkTick(cfg, tick: a).playedStep, running: true)
        XCTAssertLessThan(old?.nextSeconds ?? .infinity, next, "the unfiltered scan would arrive earlier — at a note the engine never plays")
    }
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


    // MARK: - FOLLOW lanes: bar + footer come from the pattern that actually plays (2026-10-15)

    private func followLines(partnerSteps: Int = 7, partnerRotate: Int = 1, ownRotate: Int = 2, ownInvert: Bool = false, dir: EuclidDir = .fwd) -> [EuclidLine] {
        var partner = EuclidLine(target: 0, pulses: 3, steps: partnerSteps, rate: .r1_8, useRiff: true, sourceMode: .midi)
        partner.rotate = partnerRotate; partner.restartMask = 0
        var follower = EuclidLine(target: 0, pulses: 2, steps: 8, rate: .r1_16, useRiff: true, sourceMode: .midi)   // its OWN 2-of-8 is irrelevant while following
        follower.listenRhythmMode = .follow; follower.listenRhythmPartner = 0
        follower.rotate = ownRotate; follower.restartMask = 0; follower.direction = dir
        if ownInvert { follower.patternMiss = true }
        return [partner, follower]
    }
    func testEffectivePatternOfAFollowLaneIsThePartnersWithItsOwnOffsetAndInvert() {
        let lines = followLines(ownInvert: true)
        guard let eff = euclideousEffectivePattern(lane: 1, lines: lines) else { return XCTFail("no pattern") }
        XCTAssertTrue(eff.followsPartner)
        XCTAssertEqual(eff.n, 7, "the follower takes the partner's step count, not its own 8")
        // by hand: the partner's finished pattern, then THIS lane's OFFSET, then its INV
        let partner = euclideousBuildPattern(lines[0])
        var expected = partner.buf
        euclidRotateBuffer(&expected, steps: partner.n, rotation: 2)
        for i in 0..<partner.n { expected[i].toggle() }
        XCTAssertEqual(Array(eff.buf.prefix(eff.n)), Array(expected.prefix(partner.n)))
        // …and it is NOT the follower's own 2-of-8
        let own = euclideousBuildPattern(lines[1])
        XCTAssertNotEqual(own.n, eff.n)
        // a lane that is not following, or whose partner doesn't exist, plays its OWN pattern
        let plain = euclideousEffectivePattern(lane: 0, lines: lines)!
        XCTAssertFalse(plain.followsPartner); XCTAssertEqual(plain.buf, euclideousBuildPattern(lines[0]).buf); XCTAssertEqual(plain.n, 7)
        var dangling = lines; dangling[1].listenRhythmPartner = 9
        XCTAssertFalse(euclideousEffectivePattern(lane: 1, lines: dangling)!.followsPartner)
        XCTAssertNil(euclideousEffectivePattern(lane: 4, lines: lines))
    }
    // The footer's hit ticks (what the bar's cells and bands are built from) == the engine mirror's hit ticks, for every direction.
    func testFollowLanesFooterHitsAreTheTicksTheEngineActuallyPlays() {
        for dir in [EuclidDir.fwd, .bkw, .pingpong] {
            for partnerSteps in [7, 8, 5] {
                let lines = followLines(partnerSteps: partnerSteps, ownRotate: 3, ownInvert: partnerSteps == 8, dir: dir)
                let eff = euclideousEffectivePattern(lane: 1, lines: lines)!
                let hits = euclideousLapHitSteps(buf: Array(eff.buf.prefix(eff.n)), dir: dir)
                let cfg = euclideousWalkLaneConfig(lane: 1, lines: lines, cyc: 4, resetSpanBars: 0, lanesSeqRate: .oneBar, lanesSeqLen: 8)!
                let cycleLen = euclidCycleLen(dir, n: eff.n)
                let engineTicks = (0..<cycleLen).filter { euclideousWalkTick(cfg, tick: Int64($0)).isHit }
                XCTAssertEqual(hits.map { $0.tick }, engineTicks, "\(dir) partner \(partnerSteps): footer hit ticks vs the engine's own")
                XCTAssertFalse(hits.isEmpty)
                // the bar has one cell per PARTNER step, so the footer must have exactly that many bands (the old code made 8)
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


    // MARK: - FOLLOW lanes: who is following, where their gestures go, how fast they sweep (2026-10-16)

    func testOnlyAValidFollowCountsAsFollowingAndItsGesturesGoToThePartner() {
        var lines = followLines()
        XCTAssertEqual(euclideousFollowPartner(lane: 1, lines: lines), 0)
        XCTAssertEqual(euclideousRhythmGestureTarget(lane: 1, lines: lines), 0, "a follower's bar gestures edit the lane it follows")
        XCTAssertNil(euclideousFollowPartner(lane: 0, lines: lines), "the partner itself is not following anyone")
        XCTAssertEqual(euclideousRhythmGestureTarget(lane: 0, lines: lines), 0)
        // WITH / GAPS keep the lane's OWN rhythm (they only gate it), so they are NOT following and edit themselves
        for mode in [EuclideousRhythmMode.with, .gaps] {
            lines[1].listenRhythmMode = mode
            XCTAssertNil(euclideousFollowPartner(lane: 1, lines: lines), "\(mode)")
            XCTAssertEqual(euclideousRhythmGestureTarget(lane: 1, lines: lines), 1)
        }
        lines[1].listenRhythmMode = nil
        XCTAssertNil(euclideousFollowPartner(lane: 1, lines: lines))
        // out of range
        XCTAssertNil(euclideousFollowPartner(lane: 9, lines: lines))
        XCTAssertEqual(euclideousRhythmGestureTarget(lane: 9, lines: lines), 9)
    }
    func testFollowLaneSweepsAtThePartnersRateTimesItsMultiplierExactlyAsTheEngineMirrorDoes() {
        for exp in -3...2 {
            var lines = followLines()
            lines[1].listenFollowMult = exp
            let eff = euclideousEffectivePattern(lane: 1, lines: lines)!
            XCTAssertEqual(eff.rateBeats, ArpRate.r1_8.beats * pow(2.0, Double(-exp)), accuracy: 1e-12, "×2^\(exp)")
            let cfg = euclideousWalkLaneConfig(lane: 1, lines: lines, cyc: 4, resetSpanBars: 0, lanesSeqRate: .oneBar, lanesSeqLen: 8)!
            XCTAssertEqual(cfg.sub, eff.rateBeats, accuracy: 1e-12, "the comet and the engine mirror use ONE step length")
        }
        // at ×1 the follower sweeps at the PARTNER's 1/8 — not the 1/16 it has stored for itself
        let plain = followLines()
        XCTAssertEqual(euclideousEffectivePattern(lane: 1, lines: plain)!.rateBeats, ArpRate.r1_8.beats)
        XCTAssertEqual(plain[1].rate?.beats, ArpRate.r1_16.beats, "(its own stored rate is different, so this is not just reading the lane's own field)")
        // not following: the lane's own rate; an unset rate takes the default
        var lines = followLines()
        XCTAssertEqual(euclideousEffectivePattern(lane: 0, lines: lines)!.rateBeats, ArpRate.r1_8.beats)
        lines[0].rate = nil
        XCTAssertEqual(euclideousEffectivePattern(lane: 0, lines: lines, defaultRateBeats: 0.375)!.rateBeats, 0.375)
        XCTAssertEqual(euclideousEffectivePattern(lane: 1, lines: lines, defaultRateBeats: 0.375)!.rateBeats, 0.375, "a follower whose partner has no rate takes the default × its multiplier")
        XCTAssertTrue(euclideousListenCellFade > 0.5 && euclideousListenCellFade < 1, "slightly faded, still clearly lit")
    }


    // MARK: - LISTEN: the partner (and per-mode settings) are REMEMBERED (2026-10-16)
    // Paul: "when moving from listen to own or hits, it's resetting the thing it's listening to, so I have to rechoose it every
    // time. Persist it." — turning a mode off, or swapping it for another mode in the same row, must never clear the partner.

    private func fourLanes() -> [EuclidLine] { (0..<4).map { _ in EuclidLine(target: 0, pulses: 3, steps: 8, rate: .r1_8, useRiff: true, sourceMode: .midi) } }

    func testRhythmPartnerSurvivesOffOnAndSwitchingBetweenFollowWithGaps() {
        var lines = fourLanes()
        lines = apply(lines, 0, euclideousListenToggleRhythm(lines, lane: 0, mode: .follow))
        XCTAssertEqual(lines[0].listenRhythmMode, .follow); XCTAssertEqual(lines[0].listenRhythmPartner, 1, "first light: the auto-pick (next lane)")
        lines[0].listenRhythmPartner = 3                                     // Paul picks lane 4 in the partner picker
        lines[0].listenFollowMult = 2                                        // …and a ×4 multiplier
        lines = apply(lines, 0, euclideousListenToggleRhythm(lines, lane: 0, mode: .follow))   // tap the lit mode: back to the lane's own rhythm
        XCTAssertNil(lines[0].listenRhythmMode)
        XCTAssertEqual(lines[0].listenRhythmPartner, 3, "turning the mode OFF remembers the partner")
        XCTAssertEqual(lines[0].listenFollowMult, 2, "…and the FOLLOW multiplier")
        for mode in [EuclideousRhythmMode.follow, .with, .gaps, .follow] {   // light it again, then swap modes within the row
            lines = apply(lines, 0, euclideousListenToggleRhythm(lines, lane: 0, mode: mode))
            XCTAssertEqual(lines[0].listenRhythmMode, mode)
            XCTAssertEqual(lines[0].listenRhythmPartner, 3, "\(mode): the remembered partner comes back, no re-choosing")
        }
        XCTAssertEqual(lines[0].listenFollowMult, 2)
    }
    func testAnIllegalRememberedPartnerFallsBackToTheAutoPickAndNoValidLaneMeansItCannotLight() {
        var lines = fourLanes()
        lines[0].listenRhythmPartner = 3                                     // remembered (mode off)
        lines[3].listenRhythmMode = .follow; lines[3].listenRhythmPartner = 1   // lane 4 now follows lane 2 → can't be FOLLOWed
        XCTAssertEqual(euclideousListenPartnerToLight(lines, lane: 0, row: .rhythm), 1, "a lane that is itself following is greyed: fall back to the next valid lane")
        // a loop: remembered level partner 3, but lane 4 now listens to lane 1's level → 3 reaches 0
        lines = fourLanes()
        lines[0].listenLevelPartner = 3
        lines[3].listenLevelMode = .duck; lines[3].listenLevelPartner = 0
        XCTAssertEqual(euclideousListenPartnerToLight(lines, lane: 0, row: .level), 1, "would close a loop: fall back")
        // nothing valid: every other lane is itself following → can't light, line unchanged
        lines = fourLanes()
        for i in 1...3 { lines[i].listenRhythmMode = .follow; lines[i].listenRhythmPartner = 0 }
        XCTAssertNil(euclideousListenToggleRhythm(lines, lane: 0, mode: .follow), "no valid partner: the mode can't be lit")
        // a never-chosen partner is the plain auto-pick
        XCTAssertEqual(euclideousListenPartnerToLight(fourLanes(), lane: 2, row: .pitch), 3)
        // out of range
        XCTAssertNil(euclideousListenPartnerToLight(fourLanes(), lane: 7, row: .rhythm))
    }
    func testPitchRowRemembersThePartnerAndAnyAndSwitchingToShadowDoesNotLoseThem() {
        var lines = fourLanes()
        lines = apply(lines, 0, euclideousListenTogglePitch(lines, lane: 0, mode: .avoid))
        XCTAssertEqual(lines[0].listenPitchPartner, 1); XCTAssertFalse(lines[0].listenPitchPartnerAnyResolved)
        lines[0].listenPitchPartner = 2                                       // pick lane 3…
        lines[0].listenPitchPartnerAny = true                                 // …then choose ANY (the picker KEEPS the specific partner)
        lines[0].listenAvoidAction = .move; lines[0].listenShadowInterval = 3; lines[0].listenShadowOctave = -1
        XCTAssertTrue(lines[0].listenPitchPartnerAnyResolved)
        // AVOID(ANY) → SHADOW: SHADOW needs a specific lane — it gets the remembered one — and ANY stops counting
        lines = apply(lines, 0, euclideousListenTogglePitch(lines, lane: 0, mode: .shadow))
        XCTAssertEqual(lines[0].listenPitchMode, .shadow); XCTAssertEqual(lines[0].listenPitchPartner, 2)
        XCTAssertFalse(lines[0].listenPitchPartnerAnyResolved, "ANY means nothing for SHADOW")
        XCTAssertEqual(euclideousListenEdges(lines)[0], [2], "…so a SHADOW lane depends on its ONE partner, not on every other lane")
        // SHADOW → off → AVOID: ANY is restored, the specific partner is still there, and the per-mode settings never moved
        lines = apply(lines, 0, euclideousListenTogglePitch(lines, lane: 0, mode: .shadow))
        XCTAssertNil(lines[0].listenPitchMode)
        XCTAssertEqual(lines[0].listenPitchPartner, 2); XCTAssertEqual(lines[0].listenPitchPartnerAny, true, "off remembers ANY")
        lines = apply(lines, 0, euclideousListenTogglePitch(lines, lane: 0, mode: .avoid))
        XCTAssertTrue(lines[0].listenPitchPartnerAnyResolved, "AVOID comes back as ANY")
        XCTAssertEqual(lines[0].listenPitchPartner, 2)
        XCTAssertEqual(lines[0].listenAvoidAction, .move); XCTAssertEqual(lines[0].listenShadowInterval, 3); XCTAssertEqual(lines[0].listenShadowOctave, -1)
        // the resolved flag only ever counts while AVOID is lit
        var l = EuclidLine(); l.listenPitchPartnerAny = true
        XCTAssertFalse(l.listenPitchPartnerAnyResolved); l.listenPitchMode = .shadow; XCTAssertFalse(l.listenPitchPartnerAnyResolved)
        l.listenPitchMode = .avoid; XCTAssertTrue(l.listenPitchPartnerAnyResolved)
    }
    func testRememberedAnyIsDroppedWhenItWouldNowCloseALoop() {
        var lines = fourLanes()
        lines[0].listenPitchPartner = 1; lines[0].listenPitchPartnerAny = true      // remembered, mode off
        XCTAssertTrue(euclideousListenAnyIsLegal(lines, lane: 0))
        lines[2].listenRhythmMode = .with; lines[2].listenRhythmPartner = 0          // lane 3 now listens to lane 1 → ANY (depends on lane 3) would loop
        XCTAssertFalse(euclideousListenAnyIsLegal(lines, lane: 0))
        lines = apply(lines, 0, euclideousListenTogglePitch(lines, lane: 0, mode: .avoid))
        XCTAssertEqual(lines[0].listenPitchMode, .avoid)
        XCTAssertEqual(lines[0].listenPitchPartnerAny, false, "the remembered ANY is no longer legal, so AVOID lights on its specific partner instead")
        XCTAssertEqual(lines[0].listenPitchPartner, 1)
    }
    func testLevelRowRemembersThePartnerAcrossDuckAccentAndOff() {
        var lines = fourLanes()
        lines = apply(lines, 1, euclideousListenToggleLevel(lines, lane: 1, mode: .duck))
        XCTAssertEqual(lines[1].listenLevelPartner, 2)
        lines[1].listenLevelPartner = 0; lines[1].listenLevelAmount = 0.7
        for mode in [EuclideousLevelMode.duck, .accent] {                   // DUCK off → ACCENT on → ACCENT off → DUCK on …
            lines = apply(lines, 1, euclideousListenToggleLevel(lines, lane: 1, mode: mode))
            lines = apply(lines, 1, euclideousListenToggleLevel(lines, lane: 1, mode: mode))
        }
        XCTAssertEqual(lines[1].listenLevelPartner, 0)
        lines = apply(lines, 1, euclideousListenToggleLevel(lines, lane: 1, mode: .accent))
        XCTAssertEqual(lines[1].listenLevelMode, .accent); XCTAssertEqual(lines[1].listenLevelPartner, 0, "swapping DUCK ↔ ACCENT keeps the partner")
        XCTAssertEqual(lines[1].listenLevelAmount, 0.7)
        // the three rows are independent: lighting one never touches another row's partner
        lines[1].listenRhythmPartner = 3
        lines = apply(lines, 1, euclideousListenToggleLevel(lines, lane: 1, mode: .accent))
        XCTAssertEqual(lines[1].listenRhythmPartner, 3)
    }
    /// Applies a toggle's result to `lines[lane]` the way the page does (`edit(idx) { $0 = updated }`); nil = unchanged.
    private func apply(_ lines: [EuclidLine], _ lane: Int, _ updated: EuclidLine?) -> [EuclidLine] {
        var out = lines; if let updated { out[lane] = updated }; return out
    }

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

    // RESTART CHAINS ferry §9.1/§16: a 401 × 264 grid area gives cellW 96.25, rowH 128, padH 76 (was 96 —
    // OUT moving into MIX adds sp4 + the 24pt OCT stepper + sp4 + the 20pt OUT row under each pad) and the
    // §2.7 origins (unchanged: the cells' own x/y origins don't move, only what sits below them does).
    func testMixGridAtTheReferenceSizeAndItsCellOrigins() {
        let g = euclideousMixGrid(width: 401, height: 264)
        XCTAssertEqual(g.cellW, 96.25, accuracy: 1e-9); XCTAssertEqual(g.rowH, 128, accuracy: 1e-9); XCTAssertEqual(g.padH, 76, accuracy: 1e-9)
        XCTAssertFalse(g.belowFloors)
        let xs: [CGFloat] = [0, 100.25, 204.5, 304.75], ys: [CGFloat] = [0, 136]
        var want: [CGPoint] = []
        for row in 0..<2 { for col in 0..<2 { for notes in [false, true] { want.append(CGPoint(x: xs[col * 2 + (notes ? 1 : 0)], y: ys[row])) } } }
        var got: [CGPoint] = []
        for lane in 0..<4 { for notes in [false, true] { got.append(g.origin(lane: lane, notes: notes)) } }
        // order: lane 1 riff, lane 1 notes, lane 2 riff, lane 2 notes, then lanes 3 and 4
        for (i, (a, b)) in zip(got, want).enumerated() { XCTAssertEqual(a.x, b.x, accuracy: 1e-9, "cell \(i) x"); XCTAssertEqual(a.y, b.y, accuracy: 1e-9, "cell \(i) y") }
        // the 8 cells + the OCT steppers + the OUT rows exactly tile the area: last cell's trailing edge = W, last row's bottom = H
        XCTAssertEqual(got[7].x + g.cellW, 401, accuracy: 1e-9)
        XCTAssertEqual(got[7].y + g.padH + 4 + EuclideousMixMetrics.stepperH + 4 + EuclideousMixMetrics.outRowH, 264, accuracy: 1e-9)
        // the panel → grid area: the ferry's 417 × 308 panel is 401 × 264 inside its padding, tab row and gap
        let area = euclideousMixGridArea(panelWidth: 417, panelHeight: 308)
        XCTAssertEqual(area.width, 401); XCTAssertEqual(area.height, 264)
    }
    // §9.3 — the floors are REPORTED (never shrunk): portrait panels are always short, narrow landscape panels are narrow;
    // below padH 60, MIX isn't built for that layout at all (§9.3, new — replaces the old "never shrunk" rule's own floor-less reporting).
    func testMixGridFlagsPanelsBelowTheLegibilityFloors() {
        let portrait = euclideousMixGrid(width: euclideousMixGridArea(panelWidth: 393, panelHeight: 248).width, height: euclideousMixGridArea(panelWidth: 393, panelHeight: 248).height)
        XCTAssertEqual(portrait.padH, 46, accuracy: 1e-9); XCTAssertTrue(portrait.belowFloors, "portrait: padH 46 < 76")
        XCTAssertLessThan(portrait.padH, EuclideousMixMetrics.floorPadH, "…and below the §9.3 60pt build floor too")
        let narrow = euclideousMixGridArea(panelWidth: 357.12, panelHeight: 333.5)
        XCTAssertTrue(euclideousMixGrid(width: narrow.width, height: narrow.height).belowFloors, "1024-wide landscape: cellW 81.3 < 84")
        let ok = euclideousMixGridArea(panelWidth: 416.88, panelHeight: 312.25)
        XCTAssertFalse(euclideousMixGrid(width: ok.width, height: ok.height).belowFloors)
    }
    // §9.2 — the pad maths: the three §3.5 points, the §3.6 ticks, and §4.1 inverting §3.5.
    func testMixPadPuckTicksAndTheTouchInverse() {
        let pad = EuclideousMixPadGeometry(cellW: 96.25, padH: 96)
        XCTAssertEqual(pad.plotW, 72.25, accuracy: 1e-9); XCTAssertEqual(pad.plotH, 82, accuracy: 1e-9)
        func near(_ p: CGPoint, _ x: Double, _ y: Double, _ msg: String) { XCTAssertEqual(Double(p.x), x, accuracy: 0.01, msg); XCTAssertEqual(Double(p.y), y, accuracy: 0.01, msg) }
        near(pad.puck(gate: 0.60, velocity: 104), 65.95, 19.31, "gate 60 / vel 104")
        near(pad.puck(gate: 1.00, velocity: 127), 89.25, 7, "100 / 127")
        near(pad.puck(gate: 0.01, velocity: 1), 31.58, 74.46, "1 / 1")
        XCTAssertEqual(pad.tickXs.map { Double($0) }.map { ($0 * 100).rounded() / 100 }, [45.56, 60.13, 74.69])
        XCTAssertEqual(pad.tickYs.map { Double($0) }, [58, 41, 24])
        // regions and axes (§3.3/§3.4)
        XCTAssertEqual(pad.velStrip, CGRect(x: 0, y: 0, width: 24, height: 82)); XCTAssertEqual(pad.gateStrip, CGRect(x: 24, y: 82, width: 72.25, height: 14))
        XCTAssertEqual(pad.plot, CGRect(x: 24, y: 0, width: 72.25, height: 82))
        XCTAssertEqual(pad.yAxis, CGRect(x: 24, y: 0, width: 1, height: 82)); XCTAssertEqual(pad.xAxis, CGRect(x: 24, y: 82, width: 72.25, height: 1))
        // §4.1 inverts §3.5 for EVERY gate 1…100 at velocities 1, 64 and 127
        for g in 1...100 { for v in [1, 64, 127] {
            let back = pad.values(at: pad.puck(gate: Double(g) / 100, velocity: v))
            XCTAssertEqual(Int((back.gate * 100).rounded()), g, "gate \(g) @ vel \(v)"); XCTAssertEqual(back.velocity, v, "vel \(v) @ gate \(g)")
        } }
        // …and points outside the plot clamp to each field's range
        XCTAssertEqual(pad.values(at: CGPoint(x: -50, y: 500)).gate, 0.01); XCTAssertEqual(pad.values(at: CGPoint(x: -50, y: 500)).velocity, 1)
        XCTAssertEqual(pad.values(at: CGPoint(x: 900, y: -500)).gate, 1.0); XCTAssertEqual(pad.values(at: CGPoint(x: 900, y: -500)).velocity, 127)
        XCTAssertEqual(pad.values(at: CGPoint(x: 10, y: 40)).gate, 0.01, "a touch on the VEL strip still sets both values; its x clamps the gate to 1%")
    }
    // RESTART CHAINS ferry §9.4/§16, literal: at padH 76 (the new grid-derived reference, OUT moved into
    // MIX): plotH 62, left-axis ticks at y 43/31/19 (bottom ticks unchanged), and the three named puck points.
    func testMixPadAtTheNewPadH76ReferenceMatchesTheFerrysOwnLiteralNumbers() {
        let pad = EuclideousMixPadGeometry(cellW: 96.25, padH: 76)
        XCTAssertEqual(pad.plotH, 62, accuracy: 1e-9)
        func near(_ p: CGPoint, _ x: Double, _ y: Double, _ msg: String) { XCTAssertEqual(Double(p.x), x, accuracy: 0.01, msg); XCTAssertEqual(Double(p.y), y, accuracy: 0.01, msg) }
        near(pad.puck(gate: 0.60, velocity: 104), 65.95, 15.69, "gate 60 / vel 104")
        near(pad.puck(gate: 1.00, velocity: 127), 89.25, 7, "100 / 127")
        near(pad.puck(gate: 0.01, velocity: 1), 31.58, 54.62, "1 / 1")
        XCTAssertEqual(pad.tickXs.map { Double($0) }.map { ($0 * 100).rounded() / 100 }, [45.56, 60.13, 74.69], "bottom-axis ticks unchanged")
        XCTAssertEqual(pad.tickYs.map { Double($0) }, [43, 31, 19])
    }
    // §9.3 — LEGATO at exactly 100% for BOTH layers, GATE otherwise; the strip texts and the spoken value.
    func testMixGateLabelIsLegatoAtExactly100ForBothLayers() {
        XCTAssertEqual(euclideousMixGateName(gate: 1.0), "LEGATO"); XCTAssertEqual(euclideousMixGateName(gate: 0.99), "GATE"); XCTAssertEqual(euclideousMixGateName(gate: 0.9), "GATE")
        XCTAssertEqual(euclideousMixGateName(gate: 0.996), "LEGATO", "rounds to a whole percent like the RHYTHM tab's rule")
        var l = EuclidLine(); l.gate = 1.0
        XCTAssertEqual(euclideousSliderLabelText(.gate, l), "LEGATO", "the RHYTHM tab (the riff layer)")
        l.gate = 0.7; l.notesGate = 1.0
        XCTAssertEqual(euclideousSliderLabelText(.gate, l), "GATE"); XCTAssertEqual(euclideousMixGateName(gate: l.notesGateResolved), "LEGATO", "the notes layer")
        XCTAssertTrue(euclideousGateIsLegato(1.0)); XCTAssertFalse(euclideousGateIsLegato(0.99))
        XCTAssertEqual(euclideousMixGateValueText(gate: 0.6), "60%"); XCTAssertEqual(euclideousMixGateValueText(gate: 1.0), "100%")
        XCTAssertEqual(euclideousMixPadAccessibilityValue(gate: 0.6, velocity: 104), "gate 60 percent, velocity 104")
        XCTAssertEqual(euclideousMixPadAccessibilityValue(gate: 1.0, velocity: 127), "gate 100 percent, legato, velocity 127")
        XCTAssertEqual(euclideousMixPadAccessibilityLabel(lane: 0, notes: false, off: false), "Lane 1 riff")
        XCTAssertEqual(euclideousMixPadAccessibilityLabel(lane: 3, notes: true, off: true), "Lane 4 notes, off")
        XCTAssertEqual(euclideousMixOctaveAccessibilityLabel(lane: 1, notes: true), "Lane 2 notes octave")
        XCTAssertEqual(euclideousMixVelocityStep(126, up: true), 127); XCTAssertEqual(euclideousMixVelocityStep(100, up: true), 104); XCTAssertEqual(euclideousMixVelocityStep(2, up: false), 1)
        XCTAssertEqual(euclideousMixGateStep(0.6, longer: true), 0.65, accuracy: 1e-12); XCTAssertEqual(euclideousMixGateStep(0.98, longer: true), 1.0, accuracy: 1e-12)
        XCTAssertEqual(euclideousMixGateStep(0.03, longer: false), 0.01, accuracy: 1e-12)
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
    // §9.4 — §6.4: the NOTES VEL bar as a view of notesVelocity relative to VEL.
    func testNotesVelBarIsARelativeViewOfNotesVelocity() {
        var l = EuclidLine(); l.velocityAbsolute = 100
        XCTAssertEqual(euclideousNotesVelBarValue(l), 0)
        l.notesVelOffset = 20; XCTAssertEqual(euclideousNotesVelBarValue(l), 20, "an old session's offset reads through unchanged")
        l.notesVelocity = 10; XCTAssertEqual(euclideousNotesVelBarValue(l), -64, "clamp(10 − 100, −64, 64)")
        l.velocityAbsolute = 20; l.notesVelocity = 127; XCTAssertEqual(euclideousNotesVelBarValue(l), 64, "clamped high")
        l.velocityAbsolute = 100
        euclideousNotesVelBarWrite(&l, offset: -30); XCTAssertEqual(l.notesVelocity, 70)
        euclideousNotesVelBarWrite(&l, offset: 64); XCTAssertEqual(l.notesVelocity, 127, "clamp(100 + 64, 1, 127)")
        euclideousNotesVelBarWrite(&l, offset: 500); XCTAssertEqual(l.notesVelocity, 127, "the offset itself clamps to ±64")
        l.velocityAbsolute = 10; euclideousNotesVelBarWrite(&l, offset: -64); XCTAssertEqual(l.notesVelocity, 1, "clamp(10 − 64, 1, 127)")
        var w = EuclidLine(); w.notesVelOffset = 7
        euclideousNotesVelBarWrite(&w, offset: 15); euclideousNotesVelBarDoubleTap(&w)
        XCTAssertEqual(w.notesVelOffset, 7, "nothing writes notesVelOffset any more"); XCTAssertEqual(w.notesVelocity, 100, "double tap stores VEL")
        XCTAssertEqual(euclideousNotesVelBarValue(w), 0)
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
    // "If it's in an off state and one note is selected then it should be enabled."
    func testSelectingOneNoteEnablesAnOffLayer() {
        // off because NOTHING is selected (the switch itself on)
        for (name, act) in [("key 3", { (l: inout EuclidLine) in euclideousToggleNotesKey(&l, rank: 3) }), ("TOP", { euclideousToggleNotesTop(&$0) }), ("TOP 2", { euclideousToggleNotesTop2(&$0) })] as [(String, (inout EuclidLine) -> Void)] {
            var l = laneWithNoNotesSelected(); XCTAssertFalse(euclideousNotesLayerIsOn(l))
            act(&l)
            XCTAssertTrue(euclideousNotesLayerIsOn(l), "from nothing selected, selecting \(name) turns the layer on")
        }
        // off because the SWITCH is off (nothing remembered): the same tap enables it
        var sw = laneWithNoNotesSelected(); sw.notesOn = false
        euclideousToggleNotesKey(&sw, rank: 1)
        XCTAssertEqual(sw.notesOn, true); XCTAssertEqual(sw.litNotes, 0b1); XCTAssertTrue(euclideousNotesLayerIsOn(sw))
        var sw2 = laneWithNoNotesSelected(); sw2.notesOn = false
        euclideousToggleNotesTop(&sw2); XCTAssertTrue(euclideousNotesLayerIsOn(sw2))
        var sw3 = laneWithNoNotesSelected(); sw3.notesOn = false
        euclideousToggleNotesTop2(&sw3); XCTAssertTrue(euclideousNotesLayerIsOn(sw3))
        // off with a remembered selection: selecting ANOTHER note enables it and keeps the remembered ones
        var mem = laneWithNoNotesSelected(); mem.litNotes = 0b0000_0010; mem.notesOn = false
        euclideousToggleNotesKey(&mem, rank: 5)
        XCTAssertTrue(euclideousNotesLayerIsOn(mem)); XCTAssertEqual(mem.litNotes, 0b0001_0010)
        // an out-of-range rank selects nothing and changes nothing
        var bad = laneWithNoNotesSelected(); let before = bad
        euclideousToggleNotesKey(&bad, rank: 0); euclideousToggleNotesKey(&bad, rank: 9)
        XCTAssertEqual(bad, before)
        // de-selecting the LAST note turns the layer off (it reads off with nothing selected); a second note keeps it on
        var one = laneWithNoNotesSelected(); euclideousToggleNotesKey(&one, rank: 4); XCTAssertTrue(euclideousNotesLayerIsOn(one))
        euclideousToggleNotesKey(&one, rank: 4)
        XCTAssertEqual(one.litNotes, 0); XCTAssertTrue(one.notesOnResolved, "the switch itself is untouched (still reads on)"); XCTAssertFalse(euclideousNotesLayerIsOn(one), "…but with nothing selected the layer is off")
        var two = laneWithNoNotesSelected(); euclideousToggleNotesKey(&two, rank: 2); euclideousToggleNotesKey(&two, rank: 6)
        euclideousToggleNotesKey(&two, rank: 2); XCTAssertTrue(euclideousNotesLayerIsOn(two), "one note still selected ⇒ still on")
    }
    // RESTART CHAINS ferry §9.5/§16, literal: "VELOCITY fits at padH 96 but not at 76, so the reference reads
    // VEL. It never truncates." (The grid-derived reference padH moved from 96 to 76 when OUT moved to MIX —
    // see testMixGridAtTheReferenceSizeAndItsCellOrigins — so "the reference" here means padH 96, the OLD
    // grid-derived value this test's own history used, still a valid fit/no-fit boundary case either way.)
    func testMixVelocityStripShowsVelocityWhenItFitsAndVelOtherwiseNeverTruncating() {
        XCTAssertEqual(euclideousMixVelocityName, "VELOCITY"); XCTAssertEqual(euclideousMixVelocityNameShort, "VEL")
        XCTAssertTrue(euclideousMixVelocityNameFits(plotH: EuclideousMixPadGeometry(cellW: 96.25, padH: 96).plotH), "padH 96: VELOCITY fits")
        XCTAssertFalse(euclideousMixVelocityNameFits(plotH: EuclideousMixPadGeometry(cellW: 96.25, padH: 76).plotH), "padH 76 (the new MIX-with-outputs reference): VELOCITY does not fit")
        XCTAssertEqual(euclideousMixVelocityDisplayName(plotH: EuclideousMixPadGeometry(cellW: 96.25, padH: 96).plotH), "VELOCITY")
        XCTAssertEqual(euclideousMixVelocityDisplayName(plotH: EuclideousMixPadGeometry(cellW: 96.25, padH: 76).plotH), "VEL")
        XCTAssertFalse(euclideousMixVelocityNameFits(plotH: 10), "a tiny pad never fits the long word")
    }

}
