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

    func testMorphTierDerivation() {
        // delta §9 item 5: unpaired = none; same type = full (glide); different types = swap (flip).
        XCTAssertEqual(morphTier(selfType: .arp, partner: nil), .none)
        XCTAssertEqual(morphTier(selfType: .arp, partner: .arp), .full)
        XCTAssertEqual(morphTier(selfType: .arp, partner: .passgate), .swap)
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
        XCTAssertTrue(thruAudible(isNote: false, filter: 0, cableMask: any, eventCable: 1, channel: 5))
        // A non-note event on the WRONG channel is blocked; a note soundcheck ignores channel (mute-gated only).
        XCTAssertFalse(thruAudible(isNote: false, filter: 3, cableMask: any, eventCable: 1, channel: 5))  // filter 3 = wire ch 2
        XCTAssertTrue(thruAudible(isNote: true, filter: 3, cableMask: any, eventCable: 1, channel: 5))    // note ignores channel
        // A non-note event on the wrong CABLE is blocked.
        XCTAssertFalse(thruAudible(isNote: false, filter: 0, cableMask: 0b0010, eventCable: 1, channel: 5))
        // A MUTED THRU (filter ≥ mutedSourceFilter) blocks EVERYTHING — non-note AND the note soundcheck.
        XCTAssertFalse(thruAudible(isNote: false, filter: Snap.mutedSourceFilter, cableMask: any, eventCable: 1, channel: 5))
        XCTAssertFalse(thruAudible(isNote: true, filter: Snap.mutedSourceFilter, cableMask: any, eventCable: 1, channel: 5))
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

    func testArriveAltAlternateFlipsEveryN() {
        var on = OnConfig(); on.arrive = .altAlternate; on.arriveEvery = 1
        XCTAssertEqual([0, 1, 2, 3].map { arriveAlt(base: false, on: on, arrivals: $0) }, [false, true, false, true])
        // base true just inverts the sequence.
        XCTAssertEqual([0, 1, 2].map { arriveAlt(base: true, on: on, arrivals: $0) }, [true, false, true])
        // EVERY-2: flips every second arrival.
        on.arriveEvery = 2
        XCTAssertEqual([0, 1, 2, 3, 4].map { arriveAlt(base: false, on: on, arrivals: $0) }, [false, false, true, true, false])
        // A non-alt-alternate config is inert.
        on.arrive = .morphDrift
        XCTAssertFalse(arriveAlt(base: false, on: on, arrivals: 3))
    }

    func testArriveMorphDriftLoopAndPingpong() {
        var on = OnConfig(); on.arrive = .morphDrift; on.arriveEvery = 1; on.driftPct = 25
        on.driftMode = .loop                                      // sawtooth: 0 .25 .5 .75 0 .25 …
        for (i, want) in [0, 0.25, 0.5, 0.75, 0.0, 0.25].enumerated() {
            XCTAssertEqual(arriveMorph(base: 0, on: on, arrivals: i), want, accuracy: 1e-9)
        }
        on.driftMode = .pingpong                                 // triangle: 0 .25 .5 .75 1 .75 .5 .25 0
        for (i, want) in [0, 0.25, 0.5, 0.75, 1, 0.75, 0.5, 0.25, 0.0].enumerated() {
            XCTAssertEqual(arriveMorph(base: 0, on: on, arrivals: i), want, accuracy: 1e-9)
        }
        // arrivals 0 = the base morph, always; a non-drift config is inert.
        XCTAssertEqual(arriveMorph(base: 0.4, on: on, arrivals: 0), 0.4, accuracy: 1e-9)
        on.arrive = .dice
        XCTAssertEqual(arriveMorph(base: 0.4, on: on, arrivals: 5), 0.4, accuracy: 1e-9)
    }

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

    func testTapOnsetQuantization() {
        let step = 2.0   // cycle = 16 beats
        XCTAssertEqual(tapOnsetBeat(tapBeat: 5.3, quant: .now,  stepBeats: step), 5.3, accuracy: 1e-9)
        XCTAssertEqual(tapOnsetBeat(tapBeat: 5.3, quant: .step, stepBeats: step), 6.0, accuracy: 1e-9)   // next step (…4,6,8)
        XCTAssertEqual(tapOnsetBeat(tapBeat: 5.3, quant: .pass, stepBeats: step), 16.0, accuracy: 1e-9)  // next pass (0,16)
        XCTAssertEqual(tapOnsetBeat(tapBeat: 5.3, quant: .lap,  stepBeats: step), 16.0, accuracy: 1e-9)  // v1: LAP ≈ PASS
        XCTAssertEqual(tapOnsetBeat(tapBeat: 4.0, quant: .step, stepBeats: step), 6.0, accuracy: 1e-9)   // on a boundary → the NEXT
    }

    func testTapExpiry() {
        XCTAssertEqual(tapExpiryBeat(onsetBeat: 6.0, duration: .retap, stepBeats: 2.0), .infinity)
        XCTAssertEqual(tapExpiryBeat(onsetBeat: 6.0, duration: .onePass, stepBeats: 2.0), 22.0, accuracy: 1e-9)  // 6 + 16
        XCTAssertEqual(tapExpiryBeat(onsetBeat: 6.0, duration: .oneLap, stepBeats: 2.0), 22.0, accuracy: 1e-9)
    }

    // MARK: - ON-TAP overlay: apply (retap/replace) + live masks (expire/onset gate/solo union)

    func testApplyTapReplacesPriorForSameCellAndKind() {
        var a: [TapOverlay] = []
        a = applyTapOverlay(a, cell: 5, kind: .alt, busMask: 1, onset: 0, expiry: .infinity, retap: false)
        a = applyTapOverlay(a, cell: 5, kind: .alt, busMask: 1, onset: 8, expiry: .infinity, retap: false)  // re-tap same cell/kind
        XCTAssertEqual(a.count, 1, "a second non-retap tap REPLACES, never stacks")
        XCTAssertEqual(a.first?.onset, 8, "…with the fresh onset")
    }

    func testApplyTapRetapTogglesOffThenBackOn() {
        var a: [TapOverlay] = []
        a = applyTapOverlay(a, cell: 3, kind: .mute, busMask: 0, onset: 0, expiry: .infinity, retap: true)
        XCTAssertEqual(a.count, 1, "first RETAP arms it")
        a = applyTapOverlay(a, cell: 3, kind: .mute, busMask: 0, onset: 0, expiry: .infinity, retap: true)
        XCTAssertTrue(a.isEmpty, "second RETAP toggles it off")
        a = applyTapOverlay(a, cell: 3, kind: .mute, busMask: 0, onset: 0, expiry: .infinity, retap: true)
        XCTAssertEqual(a.count, 1, "third RETAP arms again")
    }

    func testApplyTapKeepsDifferentKindsAndCellsSeparate() {
        var a: [TapOverlay] = []
        a = applyTapOverlay(a, cell: 5, kind: .alt,  busMask: 0, onset: 0, expiry: .infinity, retap: false)
        a = applyTapOverlay(a, cell: 5, kind: .mute, busMask: 0, onset: 0, expiry: .infinity, retap: false)  // same cell, other kind
        a = applyTapOverlay(a, cell: 6, kind: .alt,  busMask: 0, onset: 0, expiry: .infinity, retap: false)  // other cell
        XCTAssertEqual(a.count, 3, "a tap only replaces the SAME cell+kind — others coexist")
    }

    func testTapOverlayMasksExpireDropOnsetGateAndSoloUnion() {
        let acts: [TapOverlay] = [
            TapOverlay(cell: 5, kind: .alt,  busMask: 0,    onset: 4,  expiry: 20),   // onset reached at now=10
            TapOverlay(cell: 9, kind: .mute, busMask: 0,    onset: 12, expiry: .infinity),  // onset NOT yet reached
            TapOverlay(cell: 0, kind: .solo, busMask: 0b10, onset: 0,  expiry: 8),    // EXPIRED by now=10
            TapOverlay(cell: 1, kind: .solo, busMask: 0b01, onset: 0,  expiry: .infinity),
        ]
        let r = tapOverlayMasks(acts, now: 10, footSolo: 0b1000)
        XCTAssertEqual(r.surviving.count, 3, "the expired solo action is dropped")
        XCTAssertEqual(r.alt, 1 << 5, "the onset-reached alt contributes its cell bit")
        XCTAssertEqual(r.mute, 0, "the not-yet-onset mute does NOT contribute")
        XCTAssertEqual(r.solo, 0b1001, "live solo busMask ∪ footSolo; the expired one is gone")
    }

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
        XCTAssertEqual(cellMode(type: .arp, bypassed: false, passMask: 0, pass: 0), .arp)
        XCTAssertEqual(cellMode(type: .ratchet, bypassed: false, passMask: 0, pass: 0), .ratchet)
        XCTAssertEqual(cellMode(type: .strum, bypassed: false, passMask: 0, pass: 0), .strum)
        XCTAssertEqual(cellMode(type: .chance, bypassed: false, passMask: 0, pass: 0), .chance)
        XCTAssertEqual(cellMode(type: .harmonize, bypassed: false, passMask: 0, pass: 0), .harmonize)
        XCTAssertEqual(cellMode(type: .harmonize, bypassed: true, passMask: 0, pass: 0), .identity)  // bypass wins
    }

    func testPassgateGating() {
        let mask: UInt8 = 0b0101   // open on pass 0 and 2
        XCTAssertEqual(cellMode(type: .passgate, bypassed: false, passMask: mask, pass: 0), .identity)
        XCTAssertEqual(cellMode(type: .passgate, bypassed: false, passMask: mask, pass: 1), .silent)
        XCTAssertEqual(cellMode(type: .passgate, bypassed: false, passMask: mask, pass: 2), .identity)
        XCTAssertEqual(cellMode(type: .passgate, bypassed: false, passMask: mask, pass: 3), .silent)
        XCTAssertEqual(cellMode(type: .passgate, bypassed: false, passMask: mask, pass: 4), .identity) // wraps mod 4
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
        let mask: UInt8 = 1 << 2                                   // hold column 2 only
        for step in 0..<20 { XCTAssertEqual(lapColumn(laneMask: mask, absoluteStep: step, trueColumn: step % 8), 2) }
    }

    func testLapContiguousK2Alternates() {
        let mask: UInt8 = (1 << 3) | (1 << 4)                     // hold columns 3,4 (loop brace)
        let got = (0..<6).map { lapColumn(laneMask: mask, absoluteStep: $0, trueColumn: $0 % 8) }
        XCTAssertEqual(got, [3, 4, 3, 4, 3, 4])
    }

    func testLapK3RotatesAsPolymeterAgainstTheEightStep() {
        // Hold three columns {1,3,5}: the 3-cycle phases against the 8-step timeline and is NEVER reset
        // at the pass boundary (step 8 continues the rotation, landing off-phase vs the grid).
        let mask: UInt8 = (1 << 1) | (1 << 3) | (1 << 5)
        let got = (0..<9).map { lapColumn(laneMask: mask, absoluteStep: $0, trueColumn: $0 % 8) }
        XCTAssertEqual(got, [1, 3, 5, 1, 3, 5, 1, 3, 5])          // step 8 → index 2 → col 5, not reset to col 1
    }

    func testLapSortsHeldColumnsLeftToRight() {
        // The mask bit order IS left→right regardless of the "order pressed" — sorted wins (spec).
        let mask: UInt8 = (1 << 6) | (1 << 0)                     // columns 0 and 6
        XCTAssertEqual(lapColumn(laneMask: mask, absoluteStep: 0, trueColumn: 0), 0)   // leftmost first
        XCTAssertEqual(lapColumn(laneMask: mask, absoluteStep: 1, trueColumn: 1), 6)
    }

    func testLapNegativeStepIsSafe() {
        let mask: UInt8 = (1 << 2) | (1 << 4)
        XCTAssertEqual(lapColumn(laneMask: mask, absoluteStep: -1, trueColumn: 0), 4)  // (-1 mod 2) → index 1
        XCTAssertEqual(lapColumn(laneMask: mask, absoluteStep: -2, trueColumn: 0), 2)
    }

    // MARK: - passthrough routing (§2.6 / §7b)

    func testPassthroughGoesToAllAndEmitA() {
        let allAndA: UInt8 = 0b11   // cable 0 (All) + cable 1 (Emit A)
        // CC/PB/AT (non-note) ALWAYS forward, both transport states.
        XCTAssertEqual(passthroughCableMask(isNote: false, playing: true,  auditionSuppressing: false), allAndA)
        XCTAssertEqual(passthroughCableMask(isNote: false, playing: false, auditionSuppressing: true),  allAndA)
        // Notes forward ONLY when stopped and not audition-suppressed.
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

    // drainActive returns every note still awaiting its OFF (for a panic all-notes-off), then clears.
    func testGateDrainActiveReportsHeldPassthroughNotes() {
        var g = PassthroughGate()
        _ = g.mask(statusByte: 0x90, note: 60, velocity: 100, playing: false, auditionSuppressing: false)
        _ = g.mask(statusByte: 0x91, note: 72, velocity: 100, playing: false, auditionSuppressing: false)
        let held = g.drainActive().sorted { ($0.channel, $0.note) < ($1.channel, $1.note) }
        XCTAssertEqual(held.count, 2)
        XCTAssertEqual(held[0].channel, 0); XCTAssertEqual(held[0].note, 60)
        XCTAssertEqual(held[1].channel, 1); XCTAssertEqual(held[1].note, 72)
        XCTAssertTrue(g.drainActive().isEmpty, "drain clears")
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
        // playing → the sequencer legitimately sounds
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
    func testChordSplitCodableAndMigration() throws {
        var c = Cell(colourID: "gold"); c.chordSplit = ChordSplit(mode: .top, n: 3)
        let back = try JSONDecoder().decode(Cell.self, from: JSONEncoder().encode(c))
        XCTAssertEqual(back.chordSplit, ChordSplit(mode: .top, n: 3), "a set split round-trips")
        // a default cell omits the Optional key (encodeIfPresent) — decoding that is the OLD-doc migration path
        let d = try JSONDecoder().decode(Cell.self, from: JSONEncoder().encode(Cell(colourID: "gold")))
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
        var c = Cell(colourID: "gold"); c.velWindow = VelWindow(floor: 40, ceil: 110)
        let back = try JSONDecoder().decode(Cell.self, from: JSONEncoder().encode(c))
        XCTAssertEqual(back.velWindow, VelWindow(floor: 40, ceil: 110))
        let d = try JSONDecoder().decode(Cell.self, from: JSONEncoder().encode(Cell(colourID: "gold")))
        XCTAssertNil(d.velWindow, "no key ⇒ nil")
        XCTAssertEqual(d.velWindowResolved.floor, 1); XCTAssertEqual(d.velWindowResolved.ceil, 127)
    }
    func testChopBusMaskRoutes() {   // §cell-edit F — the per-slice emit routing
        XCTAssertEqual(chopBusMask(0b0011, slot: .main, altMask: 0b1100), 0b0011, "MAIN keeps the cell's own emitters")
        XCTAssertEqual(chopBusMask(0b0011, slot: .alt,  altMask: 0b1100), 0b1100, "ALT swaps to the alt destination")
        XCTAssertEqual(chopBusMask(0b0011, slot: .mute, altMask: 0b1100), 0,      "MUTE silences")
    }
    func testChopCodableAndMigration() throws {   // §cell-edit F — chop model round-trips; absent key ⇒ all-MAIN
        var ch = Chop(); ch.slots[2] = .alt; ch.slots[5] = .mute; ch.altDest = [.c]
        var c = Cell(colourID: "gold"); c.chop = ch
        let back = try JSONDecoder().decode(Cell.self, from: JSONEncoder().encode(c))
        XCTAssertEqual(back.chop, ch, "a set chop round-trips (slots + altDest)")
        let d = try JSONDecoder().decode(Cell.self, from: JSONEncoder().encode(Cell(colourID: "gold")))
        XCTAssertNil(d.chop, "no chop key ⇒ nil")
        XCTAssertEqual(d.chopResolved.slots, Array(repeating: ChopSlot.main, count: 8), "…resolves to all-MAIN")
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

    func testColumnSweepFractionSwingAwareSpansTheRealColumn() {
        let S = 1.0
        // swing 50: identity — the raw fraction.
        XCTAssertEqual(columnSweepFraction(realBeat: 0.0, stepBeats: S, swing: 50), 0.0, accuracy: 1e-9)
        XCTAssertEqual(columnSweepFraction(realBeat: 0.5, stepBeats: S, swing: 50), 0.5, accuracy: 1e-9)

        // swing 62 stretches the FIRST column to realOf(S) > S raw beats. The raw fraction would WRAP to
        // 0 at real beat 1.0 (the bug); the swing-aware fraction is still mid-sweep there and only wraps
        // at the true (swung) column end.
        let colEnd = realOf(1.0, stepBeats: S, a: 62.0 / 50.0)         // ≈ 1.24
        XCTAssertGreaterThan(colEnd, 1.0, "swing stretches the first column past 1 raw beat")
        let fAtRawWrap = columnSweepFraction(realBeat: 1.0, stepBeats: S, swing: 62)
        XCTAssertGreaterThan(fAtRawWrap, 0.5, "still sweeping at real 1.0 — NOT wrapped early")
        XCTAssertLessThan(fAtRawWrap, 1.0)
        XCTAssertEqual(columnSweepFraction(realBeat: 0.0, stepBeats: S, swing: 62), 0.0, accuracy: 1e-9)
        XCTAssertEqual(columnSweepFraction(realBeat: colEnd - 1e-4, stepBeats: S, swing: 62), 1.0, accuracy: 1e-3)
        XCTAssertEqual(columnSweepFraction(realBeat: colEnd, stepBeats: S, swing: 62), 0.0, accuracy: 1e-9)  // wraps AT the column end
    }

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

    // MARK: multi-cell route foci (per-column, exactly-one)

    func testRouteFociEmpty() {
        XCTAssertTrue(routeFociByColumn([]).isEmpty)
    }
    func testRouteFociOnePerColumn() {
        let foci = routeFociByColumn([(col: 1, row: 3), (col: 4, row: 0), (col: 4 - 4, row: 7)])   // cols 1,4,0
        XCTAssertEqual(foci, [1: 3, 4: 0, 0: 7])
    }
    func testRouteFociTwoInAColumnExcludesThatColumn() {
        // col 2 has two selected → no focus there; cols 1 and 5 each have one → foci.
        let foci = routeFociByColumn([(2, 1), (2, 5), (1, 0), (5, 6)])
        XCTAssertNil(foci[2], "a column with 2+ selected cells is ambiguous — no focus")
        XCTAssertEqual(foci[1], 0)
        XCTAssertEqual(foci[5], 6)
        XCTAssertEqual(foci.count, 2)
    }

    // (Removed 2026-07-30: sticky-routing tests — freshly placed cells no longer inherit or nudge routing;
    //  a new cell is created with the plain model defaults, so there is no derivation left to test here.)

    // MARK: routing visualisation graph

    private func grid8() -> [[Cell?]] { [[Cell?]](repeating: [Cell?](repeating: nil, count: 8), count: 8) }

    func testRoutingEdgesChainIsLitThroughSelectedCell() {
        var cells = grid8()
        cells[0][0] = { var c = Cell(colourID: "gold", buses: [.a]); c.inputReceiver = 1; return c }()   // MIDI-IN ⇐ R2
        cells[0][2] = { var c = Cell(colourID: "cyan", buses: [.b]); c.inputRow = 0; return c }()         // ⇐ row 0
        cells[3][0] = { var c = Cell(colourID: "teal", buses: [.c]); c.inputReceiver = 0; return c }()    // unrelated column
        let e = routingEdges(cells: cells, selected: [RouteCell(col: 0, row: 2)])
        XCTAssertTrue(e.contains(RouteEdge(from: .receiver(1), to: .cell(RouteCell(col: 0, row: 0)), lit: true)))
        XCTAssertTrue(e.contains(RouteEdge(from: .cell(RouteCell(col: 0, row: 0)), to: .cell(RouteCell(col: 0, row: 2)), lit: true)))
        XCTAssertTrue(e.contains(RouteEdge(from: .cell(RouteCell(col: 0, row: 0)), to: .emitter(0), lit: true)))
        XCTAssertTrue(e.contains(RouteEdge(from: .cell(RouteCell(col: 0, row: 2)), to: .emitter(1), lit: true)))
        XCTAssertTrue(e.contains(RouteEdge(from: .receiver(0), to: .cell(RouteCell(col: 3, row: 0)), lit: false)))
    }
    func testRoutingEdgesNoSelectionAllDim() {
        var cells = grid8()
        cells[0][0] = { var c = Cell(colourID: "gold", buses: [.a]); c.inputReceiver = 0; return c }()
        let e = routingEdges(cells: cells, selected: [])
        XCTAssertFalse(e.isEmpty)
        XCTAssertTrue(e.allSatisfy { !$0.lit })
    }
    func testRoutingEdgesNullCellHasNoReceiverOrEmitterEdge() {
        // A freshly placed, fully-unrouted cell (nil receiver, nil row, EMPTY buses) draws NO edges at all —
        // no receiver→cell entry (it must not default to R1) and no cell→emitter exit.
        var cells = grid8()
        cells[0][0] = Cell(colourID: "gold", buses: [])   // inputRow nil, inputReceiver nil, no emitters
        let e = routingEdges(cells: cells, selected: [])
        XCTAssertTrue(e.isEmpty, "a null cell should contribute no routing edges, got \(e)")
    }

    // MARK: emblems (cells & colour desk)

    func testEmblemForEveryTypeIsDistinctAndNonEmpty() {
        for t in ProcessorType.allCases { XCTAssertFalse(emblemSymbol(t).isEmpty, "\(t) needs an emblem") }
        XCTAssertEqual(Set(ProcessorType.allCases.map(emblemSymbol)).count, ProcessorType.allCases.count, "one distinct glyph per type")
    }

    // MARK: trigger glyph (deviation-shown)

    func testTriggerMarkDefaultIsNil() {
        XCTAssertNil(triggerMark(OnConfig()))                                   // both default → no mark
    }
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
    func testTriggerMarkTapPlusHoldRings() {
        var on = OnConfig(); on.tap = .alt; on.hold = .oct
        XCTAssertEqual(triggerMark(on)?.ring, true, "a hold rings the tap glyph")
    }

    // MARK: colour census (D3 delete protection)

    func testColourCensusCountsAcrossScenes() {
        var s1 = SceneState.empty(); s1.cells[0][0] = Cell(colourID: "gold"); s1.cells[1][0] = Cell(colourID: "gold")
        var s2 = SceneState.empty(); s2.cells[0][0] = Cell(colourID: "cyan")
        let c = colourCensus([s1, s2])
        XCTAssertEqual(c["gold"], 2); XCTAssertEqual(c["cyan"], 1); XCTAssertNil(c["teal"], "unpainted ⇒ absent (census 0)")
    }
}
