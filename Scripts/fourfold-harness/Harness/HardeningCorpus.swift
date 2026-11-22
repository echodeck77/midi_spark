//  HardeningCorpus.swift — ENGINE HARDENING 1 (2026-11-21), §2.1: the per-feature + combination documents.
//
//  One authored document per feature area of the coverage map, then seventeen combination documents, rendered
//  by `goldenHardening()` (HardeningGolden.swift): 32 bars at 120 BPM under a held C-major chord, each from a
//  full Kernel reset + fresh init (position-independent). A `drive` closure (window 0..<6400, the Host) scripts
//  deterministic live-word moves — scrub ribbons, part solo, reel replay, a hand on the keys. No RNG, no Date.
//
//  Field spellings are verified against Fourfold/Engine/Models.swift (the surveys' tables were cross-checked;
//  where a survey and Models.swift disagreed, Models.swift won):
//  - The scrub live word is `setEuclideousScrubHolds(riffColumn:riffRank:stackRank:)` (FourfoldAudioUnit.swift:315),
//    not the brief's `(column:rank:stackRank:)`.
//  - LET RING is `EuclidLine.notesRing` (Models.swift:666); there is no `letRing` field.
//  - The CC page has no STEP / GLIDE / FALL shape field and no ON-FROM field: a slot's shape is hold/ramp/to/curve
//    (STEP ≈ hold 100, GLIDE ≈ ramp to NEXT, FALL ≈ ramp to REST) and FROM is `driverLane` — expressed that way below.
//  - FILL's "V2 NOTES / STUTTER / BUILD" are not one mode field: `fillNotes` (riff/flat/pedal/oct/chord),
//    `fillOrder.stutter` and `fillHits.build`.
//  LEFT OUT (no release-reachable document field / no engine reader — not authorable here):
//  - TUTTI marks + ribbon settings (`PluginState.ribbonSettings`): SnapshotBuilder forces `.defaults` onto the
//    snapshot, so the stored field has no engine reader; the ribbons themselves are live words (documents P / COMBO 15).
//  - `euclideousEmitterVelocities` (the VEL tab is not in release) — skipped per the brief.
//  - `chordSlip`, `poolHold`, `poolSustainOn/Mode`, `euclideousFX`, `hocketRules`: decode-only / normalized away at
//    load — the engine no longer reads them for sound.
//  - The legacy per-lane mute (`EuclidLine.muteCells16`/`muteUnit`): engine-live for old sessions but retired from the
//    UI; the MUTE documents cover the live per-output gate instead.
//  Deliberate out-of-UI-range value: COMBO 08 stores a lane with steps 1 (the UI floor is 2) — a hand-edited /
//  future document must not break the engine; that is the point of the hardening corpus.

import Foundation

/// Mutate all four resolved lanes back into the document (the goldenPoly/goldenInputs idiom).
private func hardeningLanes(_ s: inout PluginState, _ f: (inout EuclidLine, Int) -> Void) {
    var ls = s.euclideousLinesResolved
    for i in 0..<ls.count { f(&ls[i], i) }
    s.euclideousLines = ls
}

/// Give lanes 3 and 4 hits (the fresh default leaves them at 0 hits, so a per-lane feature there would never
/// sound — same precedent as the alloc audit's EMITTER CC scenario).
private func hardeningWakeLanes34(_ s: inout PluginState) {
    hardeningLanes(&s) { l, i in if i >= 2 { l.pulses = [0, 0, 4, 7][i]; l.steps = [8, 16, 8, 12][i] } }
}

func hardeningCorpus() -> [HardeningDoc] {
    var docs: [HardeningDoc] = []
    func add(_ name: String, _ edit: @escaping (inout PluginState) -> Void, drive: ((Int, Host) -> Void)? = nil) {
        docs.append((name: name, edit: edit, drive: drive))
    }

    // A — EUCLID: the four directions + FLIP, distinct shapes, fine TILT, a fractional OFFSET, a hand pattern, mixed rates incl. a triplet and a dotted rate.
    add("EUCLID directions and timing", { s in
        hardeningLanes(&s) { l, i in
            switch i {
            case 0:
                l.pulses = 5; l.steps = 16; l.rotate = 2; l.direction = .fwd; l.rate = .r1_8
                l.offsetFraction = 0.37
            case 1:
                l.pulses = 7; l.steps = 12; l.rotate = 0; l.direction = .bkw; l.rate = .r1_16
                l.tilt = 0.6; l.tiltFine = 0.6
            case 2:
                l.pulses = 4; l.steps = 10; l.rotate = 4; l.direction = .pingpong; l.rate = .r1_8t
                l.customHits = [true, false, true, true, false, false, true, false, false, true]   // 4 hand hits over 10 steps
            default:
                l.pulses = 2; l.steps = 9; l.rotate = 3; l.direction = .fwd; l.rate = .r1_4d
                l.patternMiss = true   // FLIP: the inverted pattern (7 of 9 sound)
            }
        }
    })

    // B — EUCLID LET RING: the stack layer sustains to the walk-cycle boundary on two lanes with lit notes.
    add("EUCLID let ring", { s in
        hardeningLanes(&s) { l, i in
            guard i < 2 else { return }
            l.notesOn = true
            l.notesLitOrder = i == 0 ? [0, 2, 4] : [1, 3, 9]   // ranks 1·3·5 / ranks 2·4 + TOP
            l.notesRing = true
        }
    })

    // C — RIFF walks: stride / length / shift / TRANS / advance-every STEP / REV + PING-PONG, with TIE and REPEAT on a riff that has rests.
    add("RIFF walks", { s in
        s.riffs = [EuclideousRiff(steps: 16, ranks: [1, 0, 3, 5, 0, 2, 8, 0, 4, 6, 0, 7, 1, 0, 5, 3])]   // rests so TIE / REPEAT act
        hardeningWakeLanes34(&s)
        hardeningLanes(&s) { l, i in
            l.riffOn = true
            switch i {
            case 0:  l.riffStride = 3; l.riffDir = .forward; l.riffOnRest = .tie
            case 1:  l.riffLength = 5; l.riffRotate = 2; l.riffDir = .reverse; l.riffOnRest = .repeatLast
            case 2:  l.melodyTranspose = 3; l.riffAdvanceEvery = 2; l.riffAdvanceStep = true
            default: l.riffDir = .pingpong; l.riffInvert = true; l.riffOctave = -1
            }
        }
    })

    // D — STACK chains: distinct lit orders, ORDER/VOICES/SPREAD chains, rank roles, WHEN variants, BASS, CHANCE 50 (splitmix — deterministic).
    add("STACK chains", { s in
        s.riffs = [EuclideousRiff(steps: 8, ranks: [1, 0, 3, 0, 5, 2, 0, 8])]   // rests so a WHEN=RESTS lane strikes
        hardeningWakeLanes34(&s)
        hardeningLanes(&s) { l, i in
            l.notesOn = true
            switch i {
            case 0:
                l.notesLitOrder = [0, 2, 4]
                l.notesOrderChain = [EuclideousOrderChip(value: .down, hits: 3), EuclideousOrderChip(value: .shuffle, hits: 2)]
                l.notesWhen = 0b01   // PLAYS only
            case 1:
                l.notesLitOrder = [1, 3, 5, 7]
                l.notesVoicesChain = [EuclideousVoicesChip(value: .two, hits: 4), EuclideousVoicesChip(value: .grow, hits: 3)]
                l.notesWhen = 0b10   // RESTS only
                l.notesRankRoles = 0b0000_0010_0001_0011   // rank 1 PEDAL · rank 3 DOUBLE · rank 5 RETURN
            case 2:
                l.notesLitOrder = [9, 8, 0]   // TOP, TOP 2, rank 1
                l.notesSpreadChain = [EuclideousSpreadChip(value: .strum, hits: 2), EuclideousSpreadChip(value: .run, hits: 2)]
                l.notesBassOn = true; l.notesBassMode = .first
            default:
                l.notesLitOrder = [7, 6, 5, 4]
                l.notesOrderChain = [EuclideousOrderChip(value: .outsideIn, hits: 2), EuclideousOrderChip(value: .asAdded, hits: 4)]
                l.notesChance = 50
            }
        }
    })

    // E — STACK ring + shift / drift: notesRing beside the ORDER pop-up's SHIFT and DRIFT document fields.
    add("STACK ring and shift drift", { s in
        hardeningWakeLanes34(&s)
        hardeningLanes(&s) { l, i in
            l.notesOn = true
            l.notesLitOrder = [[0, 1, 2, 3], [2, 4, 6], [0, 3, 5, 7], [1, 5]][i].map { UInt8($0) }
            switch i {
            case 0:  l.notesRing = true
            case 1:  l.notesShiftStart = 5
            case 2:  l.notesDriftOn = true; l.notesDriftStep = -3
            default: l.notesRing = true; l.notesShiftStart = 12; l.notesDriftOn = true; l.notesDriftStep = 8
            }
        }
    })

    // F — INPUTS lanes apart: per-lane source chips (MIDI-only / MIDI+CHORD 1 / MIDI+CHORD 2 / PICK+KEY), REPLACE and ROOT where MIDI is on, a non-major key.
    add("INPUTS lanes apart", { s in
        s.euclideousSourcePlan = SourcePlan(midiOn: true, chordsOn: true, pickOn: true, keyOn: true, midiMode: .add, pickNotes: [72, 76, 79])
        s.euclideousKeyRoot = 2; s.euclideousKeyType = .dorian
        hardeningWakeLanes34(&s)
        hardeningLanes(&s) { l, i in
            l.poolSrcMask = [0b00001, 0b00011, 0b10001, 0b01100][i]   // bits: 0 MIDI · 1 CHORDS 1 · 2 PICK · 3 KEY · 4 CHORDS 2
            l.midiMode = [nil, .replace, .root, nil][i]
        }
    })

    // G — CANON delays: the shared chord-canon document, a lane's own STEPS as the unit, no slips (slip is retired).
    add("CANON delays", { s in
        canonDocument(&s, unit: .steps, delays: [0, 1, 2, 4], slips: [0, 0, 0, 0])
    })

    // H — RESETS units: a RIFF-unit chain reading another lane, a PASS chain on another lane, HIT links, one WITH RHYTHM.
    add("RESETS units", { s in
        hardeningWakeLanes34(&s)
        hardeningLanes(&s) { l, i in
            l.riffOn = true
            switch i {
            case 0:
                l.restartRhythmBars = [1]; l.restartRhythmUnit = .riff; l.restartRhythmSource = 1; l.restartRhythmOn = true
            case 1:
                l.restartRhythmBars = [2, 1]; l.restartRhythmUnit = .pass; l.restartRhythmSource = 2; l.restartRhythmOn = true
            case 2:
                l.restartMelodyPasses = [3, 5]; l.restartMelodyUnit = .hit; l.restartMelodyOn = true
            default:
                l.restartRhythmBars = [1]; l.restartRhythmUnit = .bar; l.restartRhythmOn = true
                l.restartMelodyWithRhythm = true
            }
        }
    })

    // I — FILL: all four lanes filling with different speed / length / order / hits / notes / shape / roll / chance / break / land.
    add("FILL", { s in
        hardeningWakeLanes34(&s)
        hardeningLanes(&s) { l, i in
            l.fillOn = true
            var bars = [Bool](repeating: false, count: 16)
            switch i {
            case 0:
                bars[0] = true; bars[4] = true
                l.fillSpeed = 3; l.fillLength = 0; l.fillOrder = .fwd; l.fillHits = .keep; l.fillNotes = .riff
                l.fillRanks = 3; l.fillSwell = 2; l.fillRoll = 2; l.fillCurve = .rush
            case 1:
                bars[1] = true; bars[3] = true; bars[5] = true
                l.fillSpeed = 4; l.fillLength = 2; l.fillOrder = .stutter; l.fillHits = .flip; l.fillNotes = .pedal
                l.fillBreak = true
            case 2:
                bars[2] = true; bars[6] = true
                l.fillOrder = .bounce; l.fillHits = .build; l.fillNotes = .oct; l.fillShape = .arch
                l.fillRanks = -5; l.fillLand = true
            default:
                for b in 0..<4 { bars[b] = true }
                l.fillLoop = 4; l.fillOrder = .shuffle; l.fillNotes = .chord; l.fillChance = 50; l.fillRoll = 4; l.fillSwell = -3
            }
            l.fillBars = bars
        }
    })

    // J — ALT: two lanes alternating MAIN/ALT with part overrides OUT / OCT / VEL / GATE (lane 2's ALT routes the stack nowhere — a rest that still advances).
    add("ALT", { s in
        hardeningLanes(&s) { l, i in
            switch i {
            case 0:
                l.altUnit = .bar; l.altMainCount = 2; l.altAltCount = 1
                var p = EuclideousAltPart()
                p.outOn = true; p.out = 0b0010; p.octOn = true; p.oct = 1; p.velOn = true; p.vel = 40; p.gateOn = true; p.gate = 30
                l.altRiff = p
            case 1:
                l.notesOn = true; l.notesLitOrder = [0, 2, 4]
                l.altUnit = .pass; l.altMainCount = 3; l.altAltCount = 2
                var p = EuclideousAltPart()
                p.outOn = true; p.out = 0; p.octOn = true; p.oct = -2; p.velOn = true; p.vel = 110; p.gateOn = true; p.gate = 95
                l.altNotes = p
            default: break
            }
        }
    })

    // K — RATCH emitters: A plain Euclid ×3, B a hand pattern with per-hit counts, C a spilling SPREAD with bend + swell ramp, D chance 50 restarting every 2 bars.
    add("RATCH emitters", { s in
        hardeningWakeLanes34(&s)
        var set = EmitterRatchetSet()
        set[0] = EmitterRatchet(on: true, steps: 16, hits: 5, offset: 0, chance: 100, strikes: 3)
        var b = EmitterRatchet(on: true, steps: 16, hits: 6, offset: 0, chance: 100, strikes: 3)
        b.customMask = 0b1010_0110_0101_1001; b.perHit = true; b.hitCountBits = 0xE4E4_E4E4   // counts 1·2·3·4 repeating by hit ordinal
        set[1] = b
        var c = EmitterRatchet(on: true, steps: 7, hits: 4, offset: 2, chance: 100, strikes: 3)
        c.length = .two; c.bend = 30; c.vel = .swell; c.depth = 80
        set[2] = c
        set[3] = EmitterRatchet(on: true, steps: 10, hits: 6, offset: 1, chance: 50, strikes: 4, restartBars: 2)
        s.euclideousEmitterRatchets = set
    })

    // L — CC slots: two outputs × two slots, distinct driver lanes and shapes (STEP = hold 100 · GLIDE = ramp to NEXT · FALL = ramp to REST); output B fully muted so its slots park at LOW.
    add("CC slots", { s in
        hardeningWakeLanes34(&s)
        var set = EmitterCCSet()
        set[output: 0, slot: 0] = EmitterCC(on: true, ccNumber: 74, valueMode: .riff, high: 127, low: 0, hold: 20, ramp: 80, to: .next, curve: .lin, driverLane: 1)     // GLIDE
        set[output: 0, slot: 1] = EmitterCC(on: true, ccNumber: 71, valueMode: .hits, high: 90, low: 20, hold: 100, ramp: 0, driverLane: 3)                             // STEP (hold 100)
        set[output: 1, slot: 0] = EmitterCC(on: true, ccNumber: 1, valueMode: .climb, high: 20, low: 110, hold: 0, ramp: 100, to: .rest, curve: .exp, passes: 2)        // FALL, inverted, AUTO driver
        set[output: 1, slot: 1] = EmitterCC(on: true, ccNumber: 11, valueMode: .pingPong, high: 127, low: 0, hold: 50, ramp: 50, to: .rest, curve: .lin, driverLane: 2)
        s.euclideousEmitterCCs = set
        var mutes = EuclideousOutputMutes()
        mutes[1] = EuclideousOutputMute(cells16: 0x0000, passes: 1, muteUnit: 0)   // output B muted — its slots park at LOW
        s.euclideousOutputMutes = mutes
    })

    // M — MUTE rows: each output a different unit + pattern; lane 1 at GATE 99 % so the §2.3 off-clamp (note-off at the first muted-cell boundary) runs.
    add("MUTE rows", { s in
        hardeningWakeLanes34(&s)
        hardeningLanes(&s) { l, i in if i == 0 { l.gate = 0.99 } }
        s.euclideousOutputMutes = EuclideousOutputMutes([
            EuclideousOutputMute(cells16: 0xAAAA, passes: 1, muteUnit: 0),   // A: 1/16
            EuclideousOutputMute(cells16: 0xCCCC, passes: 1, muteUnit: 1),   // B: 1/8
            EuclideousOutputMute(cells16: 0x0FF0, passes: 1, muteUnit: 2),   // C: 1/4
            EuclideousOutputMute(cells16: 0x00FF, passes: 1, muteUnit: 3),   // D: BAR
        ])
    })

    // N — MIX routing: a part on two outputs, a part routed nowhere, two lanes sharing an output, remapped channels, two part-solo bits latched (masters stay on).
    add("MIX routing", { s in
        hardeningWakeLanes34(&s)
        hardeningLanes(&s) { l, i in
            switch i {
            case 0:  l.riffOutMask = 0b0011                          // riff 1 → A + B
            case 1:  l.notesOn = true; l.notesLitOrder = [0, 2]; l.notesOutMask = 0   // stack 2 → nowhere (drawn, silent)
            case 2:  l.riffOutMask = 0b0010                          // riff 3 shares B with lane 1's riff
            default: break
            }
        }
        s.busChannels = [16, 1, 9, 2]
        s.euclideousPartSoloMask = 0b0000_0101   // lane 1 riff + lane 2 riff solo-latched
    })

    // O — HARMONY grids: both progressions authored (different rates), grid 1 advancing on a lane's LOOP with a BAR restart, two lanes on grid 2.
    add("HARMONY grids", { s in
        hardeningWakeLanes34(&s)
        var g1 = s.euclideousChordSetsResolved[0]
        g1.chordsSteps = 12
        g1.chordsDegrees = [0, 9, 3, 11, 4, 8, 10, 5, 2, 7, 6, 1]
        g1.chordsColours = [1, 2, 3, 4, 5, 6, 0, 1, 2, 3, 4, 5]
        g1.chordsRate = .r1_1
        g1.advanceUnit = .loop; g1.advanceLane = 0; g1.advanceEvery = 2
        g1.restartOn = true; g1.restartUnit = .bar; g1.restartEvery = 4
        s.setEuclideousChordSet(0, g1)
        var g2 = s.euclideousChordSetsResolved[1]
        g2.chordsSteps = 16
        g2.chordsDegrees = [1, 8, 2, 10, 5, 9, 11, 3, 6, 0, 4, 7, 1, 9, 10, 8]
        g2.chordsColours = [2, 3, 1, 4, 6, 5, 0, 2, 3, 4, 1, 5, 6, 0, 2, 1]
        g2.chordsRate = .r1_4
        g2.restartOn = true; g2.restartUnit = .loop; g2.restartLane = 1; g2.restartEvery = 2
        s.setEuclideousChordSet(1, g2)
        hardeningLanes(&s) { l, i in if i % 2 == 1 { l.poolSrcMask = 0b10001 } }   // lanes 2 + 4 read grid 2 (MIDI + CHORDS 2)
    })

    // P — SCRUB ribbons (drive): a column hold sweeping 1→8 every 400 windows, a rank hold 3 for 2000..<2400, a stack hold 5 for 4000..<4400.
    add("SCRUB ribbons", { _ in }, drive: { r, host in
        let col = r < 3200 ? r / 400 + 1 : 0
        let rank = (2000..<2400).contains(r) ? 3 : 0
        let stack = (4000..<4400).contains(r) ? 5 : 0
        host.au.setEuclideousScrubHolds(riffColumn: col, riffRank: rank, stackRank: stack)
    })

    // Q — PART SOLO live (drive): the live-word masks flip every 500 windows (the alloc audit's own six-state pattern).
    add("PART SOLO live", { _ in }, drive: { r, host in
        if r % 500 == 0 {
            host.au.setEuclideousPartSoloLive([0b0000_0001, 0b1000_0000, 0b0001_0100, 0, 0b0010_0010, 0][(r / 500) % 6])
            host.au.setEuclideousSoloLive([0, 0b0010, 0, 0, 0b0100, 0][(r / 500) % 6])
        }
    })

    // R — REEL replay (drive): replay the last filed pass from the middle of the run, hand back at three-quarters (the alloc audit's REPLAY moves).
    add("REEL replay", { _ in }, drive: { r, host in
        if r == 3200, let p = host.au.reelPassNumbers().last(where: { $0 >= 0 }) { host.au.reelSelectPass(p) }
        if r == 4800 { host.au.reelStopReplay() }
    })

    // S — HOLD sustains (drive): HOLD keeps the released chord sounding (1600..<3200 nothing is held), then a new hand replaces it.
    add("HOLD sustains", { s in
        s.euclideousHoldLatchMode = .hold
    }, drive: { r, host in
        if r == 1600 { host.release([60, 64, 67]) }
        if r == 3200 { host.hold([62, 65, 69]) }
        if r == 6300 { host.release([62, 65, 69]) }   // leave nothing held into the run's tail
    })

    // COMBO 01 — FILL + RATCH + MUTE all on output A (lanes 1 + 2 share it).
    add("COMBO 01 fill ratchet mute shared output", { s in
        hardeningLanes(&s) { l, i in
            guard i < 2 else { return }
            l.riffOutMask = 0b0001
            l.fillOn = true
            var bars = [Bool](repeating: false, count: 16); bars[0] = true; bars[2] = true; bars[5] = true
            l.fillBars = bars
            l.fillOrder = i == 0 ? .rev : .stutter; l.fillNotes = i == 0 ? .riff : .oct
        }
        var set = EmitterRatchetSet()
        set[0] = EmitterRatchet(on: true, steps: 8, hits: 4, offset: 1, chance: 75, strikes: 3)
        s.euclideousEmitterRatchets = set
        var mutes = EuclideousOutputMutes()
        mutes[0] = EuclideousOutputMute(cells16: 0xF0F0, passes: 1, muteUnit: 1)
        s.euclideousOutputMutes = mutes
    })

    // COMBO 02 — RESETS units + CANON delays + a ROOT lane, on one document.
    add("COMBO 02 resets canon root", { s in
        canonDocument(&s, unit: .passes, delays: [0, 1, 2, 3], slips: [0, 0, 0, 0])
        hardeningLanes(&s) { l, i in
            switch i {
            case 0: l.restartRhythmBars = [1]; l.restartRhythmUnit = .riff; l.restartRhythmSource = 0; l.restartRhythmOn = true
            case 1: l.midiMode = .root
            case 2: l.restartMelodyPasses = [4]; l.restartMelodyUnit = .hit; l.restartMelodyOn = true
            default: l.restartMelodyWithRhythm = true
            }
        }
    })

    // COMBO 03 — ALT + latched part solo + a lane routed nowhere.
    add("COMBO 03 alt part solo routed nowhere", { s in
        hardeningWakeLanes34(&s)
        hardeningLanes(&s) { l, i in
            switch i {
            case 0:
                l.altUnit = .hit; l.altMainCount = 3; l.altAltCount = 2
                var p = EuclideousAltPart(); p.outOn = true; p.out = 0b0100; p.velOn = true; p.vel = 50
                l.altRiff = p
            case 1:
                l.altUnit = .step; l.altMainCount = 4; l.altAltCount = 4
                var p = EuclideousAltPart(); p.octOn = true; p.oct = 2; p.gateOn = true; p.gate = 20
                l.altRiff = p
            case 2:
                l.riffOutMask = 0; l.notesOutMask = 0   // routed nowhere
            default: break
            }
        }
        s.euclideousPartSoloMask = 0b0000_0011   // lane 1 both parts
    })

    // COMBO 04 — CC slots + RATCH on the same outputs + remapped channels (emitterVelocities deliberately skipped — no VEL tab in release).
    add("COMBO 04 cc ratchet channels", { s in
        hardeningWakeLanes34(&s)
        var ccs = EmitterCCSet()
        ccs[output: 0, slot: 0] = EmitterCC(on: true, ccNumber: 74, valueMode: .riff, high: 110, low: 10, hold: 30, ramp: 60, to: .next, curve: .exp, driverLane: 1)
        ccs[output: 2, slot: 1] = EmitterCC(on: true, ccNumber: 1, valueMode: .hits, high: 100, low: 0, driverLane: 3)
        s.euclideousEmitterCCs = ccs
        var set = EmitterRatchetSet()
        set[0] = EmitterRatchet(on: true, steps: 12, hits: 5, offset: 0, chance: 100, strikes: 2)
        set[2] = EmitterRatchet(on: true, steps: 5, hits: 3, offset: 1, chance: 50, strikes: 4)
        s.euclideousEmitterRatchets = set
        s.busChannels = [5, 6, 7, 8]
    })

    // COMBO 05 — STACK chains + RING + LET RING + TIE over a riff with rests.
    add("COMBO 05 stack chains ring tie", { s in
        s.riffs = [EuclideousRiff(steps: 8, ranks: [2, 0, 4, 0, 6, 0, 8, 1])]
        hardeningWakeLanes34(&s)
        hardeningLanes(&s) { l, i in
            l.riffOn = true; l.riffOnRest = .tie
            l.notesOn = true
            l.notesLitOrder = [[0, 2], [1, 3, 5], [4, 6], [0, 7, 9]][i].map { UInt8($0) }
            l.notesRing = i % 2 == 0
            if i == 1 { l.notesOrderChain = [EuclideousOrderChip(value: .bounce, hits: 2), EuclideousOrderChip(value: .up, hits: 3)] }
            if i == 3 { l.notesVoicesChain = [EuclideousVoicesChip(value: .all, hits: 2), EuclideousVoicesChip(value: .one, hits: 2)] }
        }
    })

    // COMBO 06 — both chord grids + PICK + KEY + the document in REPLACE.
    add("COMBO 06 grids pick key replace", { s in
        s.euclideousSourcePlan = SourcePlan(midiOn: true, chordsOn: true, pickOn: true, keyOn: true, midiMode: .replace, pickNotes: [72, 76, 79])
        var g2 = s.euclideousChordSetsResolved[1]
        g2.chordsSteps = 8; g2.chordsDegrees = [5, 3, 0, 7, 2, 6, 1, 4]; g2.chordsRate = .r1_2
        s.setEuclideousChordSet(1, g2)
        hardeningWakeLanes34(&s)
        hardeningLanes(&s) { l, i in
            l.poolSrcMask = [0b01111, 0b11101, 0b11100, 0b01110][i]   // CH1+all / CH2+MIDI+PICK+KEY / CH2+PICK+KEY / CH1+PICK+KEY no MIDI
        }
    })

    // COMBO 07 — a stored POLY document (legacy-reachable): overlapping notes, every walk direction.
    add("COMBO 07 poly stored document", { s in
        s.riffPoly = true
        s.polyRiff = EuclideousPolyRiff(notes: [(0, 1, 8), (0, 4, 2), (3, 6, 10), (5, 2, 3), (7, 8, 1), (9, 3, 7), (9, 5, 7), (12, 7, 4), (15, 1, 1)].map { EuclideousPolyNote(col: $0.0, rank: $0.1, len: $0.2) })
        hardeningWakeLanes34(&s)
        hardeningLanes(&s) { l, i in
            l.riffOn = true; l.riffLength = nil
            l.riffDir = [.forward, .reverse, .pingpong, .forward][i]
            l.riffAdvanceEvery = [1, 2, 1, 3][i]
        }
    })

    // COMBO 08 — shape edges: a stored 1-step lane (below the UI's floor of 2), a 0-hit lane, hits == steps.
    add("COMBO 08 one step zero hits full hits", { s in
        hardeningLanes(&s) { l, i in
            switch i {
            case 0:  l.steps = 1; l.pulses = 1              // out-of-UI-range stored value, by design
            case 1:  l.pulses = 0; l.steps = 8              // no hits at all
            case 2:  l.steps = 16; l.pulses = 16            // every step a hit
            default: l.steps = 2; l.pulses = 2
            }
        }
    })

    // COMBO 09 — maximum lengths everywhere: 16/16 lanes, four chain links of 8, the longest FILL, full chains and lit orders.
    add("COMBO 09 maximum lengths", { s in
        hardeningLanes(&s) { l, _ in
            l.pulses = 16; l.steps = 16
            l.restartRhythmBars = [8, 8, 8, 8]; l.restartRhythmUnit = .bar; l.restartRhythmOn = true
            l.restartMelodyPasses = [8, 8, 8, 8]; l.restartMelodyUnit = .hit; l.restartMelodyOn = true
            l.riffOn = true; l.riffLength = 8; l.riffStride = 7; l.riffAdvanceEvery = 8
            l.notesOn = true; l.notesLitOrder = [0, 1, 2, 3, 4, 5, 6, 7, 8, 9]
            l.notesOrderChain = [EuclideousOrderChip(value: .up, hits: 32), EuclideousOrderChip(value: .down, hits: 32),
                                 EuclideousOrderChip(value: .bounce, hits: 32), EuclideousOrderChip(value: .shuffle, hits: 32)]
            l.fillOn = true; l.fillBars = [Bool](repeating: true, count: 16); l.fillLoop = 16
            l.fillSpeed = 4; l.fillLength = 0; l.fillRoll = 4
        }
    })

    // COMBO 10 — every lane on output A, every output stamped channel 1.
    add("COMBO 10 all lanes one output", { s in
        hardeningWakeLanes34(&s)
        hardeningLanes(&s) { l, _ in l.riffOutMask = 0b0001; l.notesOutMask = 0b0001 }
        s.busChannels = [1, 1, 1, 1]
    })

    // COMBO 11 — no outputs at all: both masks 0 on every lane (everything walks, nothing sends).
    add("COMBO 11 no outputs", { s in
        hardeningWakeLanes34(&s)
        hardeningLanes(&s) { l, _ in l.riffOutMask = 0; l.notesOutMask = 0 }
    })

    // COMBO 12 — every source off: an empty pool on every lane.
    add("COMBO 12 every source off", { s in
        hardeningWakeLanes34(&s)
        hardeningLanes(&s) { l, _ in l.poolSrcMask = 0 }
    })

    // COMBO 13 — an empty riff and nothing lit, with the riff and stack layers both ON (the silence pipeline).
    add("COMBO 13 empty riff nothing lit", { s in
        s.riffs = [EuclideousRiff.empty]
        hardeningWakeLanes34(&s)
        hardeningLanes(&s) { l, _ in l.riffOn = true; l.notesOn = true; l.notesLitOrder = [] }
    })

    // COMBO 14 — both masters OFF under a latched part solo (nothing may sound; the stack is lit so a master regression would).
    add("COMBO 14 masters off part solo", { s in
        hardeningWakeLanes34(&s)
        hardeningLanes(&s) { l, i in if i < 2 { l.notesOn = true; l.notesLitOrder = [0, 2] } }
        s.riffMaster = false
        s.stackMaster = false
        s.euclideousPartSoloMask = 0b0000_0110   // lane 1 stack + lane 2 riff
    })

    // COMBO 15 — stored locked lanes + a scrub drive over them.
    add("COMBO 15 locked lanes scrubbed", { s in
        hardeningWakeLanes34(&s)
        let ls = s.euclideousLinesResolved
        s.euclideousLocks = [
            EuclideousLaneLock.locking(ls[0], grid: .bars2),
            EuclideousLaneLock(),
            EuclideousLaneLock.locking(ls[2], grid: .beat),
            EuclideousLaneLock(),
        ]
    }, drive: { r, host in
        let col = (1000..<2000).contains(r) ? 4 : 0
        let stack = (3000..<3600).contains(r) ? 2 : 0
        host.au.setEuclideousScrubHolds(riffColumn: col, riffRank: 0, stackRank: stack)
    })

    // COMBO 16 — RATCH + CC + FILL + ALT all on at once.
    add("COMBO 16 ratchet cc fill alt", { s in
        hardeningWakeLanes34(&s)
        hardeningLanes(&s) { l, i in
            if i == 0 {
                l.fillOn = true
                var bars = [Bool](repeating: false, count: 16); bars[1] = true; bars[6] = true
                l.fillBars = bars; l.fillOrder = .bounce; l.fillNotes = .chord
            }
            if i == 1 {
                l.altUnit = .bar; l.altMainCount = 1; l.altAltCount = 1
                var p = EuclideousAltPart(); p.outOn = true; p.out = 0b1000; p.velOn = true; p.vel = 90
                l.altRiff = p
            }
        }
        var set = EmitterRatchetSet()
        set[0] = EmitterRatchet(on: true, steps: 8, hits: 3, offset: 0, chance: 100, strikes: 3)
        set[3] = EmitterRatchet(on: true, steps: 16, hits: 9, offset: 4, chance: 75, strikes: 2)
        s.euclideousEmitterRatchets = set
        var ccs = EmitterCCSet()
        ccs[output: 1, slot: 0] = EmitterCC(on: true, ccNumber: 74, valueMode: .climb, high: 127, low: 0, hold: 10, ramp: 90, to: .next, curve: .lin, passes: 4, driverLane: 2)
        s.euclideousEmitterCCs = ccs
    })

    // COMBO 17 — tempo-dense flood pressure: every lane 1/32 at 16/16, routed everywhere, every output ratcheting ×4.
    add("COMBO 17 tempo dense flood", { s in
        hardeningLanes(&s) { l, _ in
            l.pulses = 16; l.steps = 16; l.rate = .r1_32
            l.riffOn = true
            l.riffOutMask = 0x0F; l.notesOutMask = 0x0F
        }
        var set = EmitterRatchetSet()
        for o in 0..<4 { set[o] = EmitterRatchet(on: true, steps: 16, hits: 16, offset: 0, chance: 100, strikes: 4) }
        s.euclideousEmitterRatchets = set
    })

    return docs
}
