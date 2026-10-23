import Foundation

// EUCLIDEOUS FACTORY PRESETS (Paul 2026-10-11, ratified: "create 20 musically interesting presets without using
// mask" + "remove any existing presets" — scope confirmed via AskUserQuestion as the WHOLE-PLUGIN factory list.
// These 20 REPLACE `MidiSparkAudioUnit.factoryPresetBuilders` entirely — INIT/ARC/THE LADDER/TIDE/FORGE/CHIME/
// SPARK/DELAYS and all 16 `SceneFactory` curriculum scenes are gone from the preset MENU. None of the underlying
// code is deleted (`PluginState.makeInit()` is still the real fresh-instance default at instantiation — see
// MidiSparkAudioUnit.swift's init — and `defaultArc`/`makeLadder*`/`makeDelays`/`SceneFactory` are still exercised
// directly by MigrationTests/SceneFactoryTests); only their factory-preset-list ENTRY is gone.
//
// Each preset is a full `PluginState` (the whole-document factory-preset contract is unchanged — `AUAudioUnitPreset`
// has no notion of "page-scoped") built from `PluginState.makeInit()` (empty 8×8 grid, silent) with ONLY
// Euclideous's own page-level fields configured. No `EuclidLineMask` field is ever touched anywhere in this file
// (Paul's explicit "without using mask" — EUCLID MASK is a separate, standalone chain processor, orthogonal to
// these presets). A field left unset reads EuclidLine's own bare default (pulses:1, steps:8, gate 0.9, velocity
// 100, sourceMode KEY) — presets lean on that default rather than restating it everywhere.
enum EuclideousPresets {
    private static func base(_ configure: (inout PluginState) -> Void) -> PluginState {
        var state = PluginState.makeInit()
        state.euclideousEnabled = true
        configure(&state)
        return state
    }

    // Six shared RIFF rank-shapes (8 steps, 0 = rest, 1...8 = pool rank), named in the same R-number convention
    // CLAUDE.md's own R1/R2 history already established for this page's shared pattern.
    private static let archShape    = [1, 4, 6, 8, 7, 5, 3, 2]   // R3 ARCH: rise then fall
    private static let zigzagShape  = [1, 6, 2, 7, 3, 8, 4, 5]   // R4 ZIGZAG: wide alternating leaps
    private static let runShape     = [1, 2, 3, 4, 5, 6, 7, 8]   // R5 RUN: a plain ascending run
    private static let sparseShape  = [1, 0, 0, 4, 0, 0, 7, 0]   // R6 SPARSE: mostly rest
    private static let callShape    = [5, 0, 3, 0, 1, 0, 6, 0]   // R7 CALL: alternating note/rest
    private static let descendShape = [8, 7, 6, 5, 4, 3, 2, 1]   // R8 DESCEND: a plain descending run

    static let all: [(name: String, make: () -> PluginState)] = [
        ("STRIDE WALK", strideWalk), ("MIRROR WALK", mirrorWalk), ("PENDULUM", pendulum),
        ("PING-PONG LEAD", pingPongLead), ("DRUNKEN WALK", drunkenWalk), ("RANDOM GARDEN", randomGarden),
        ("OCTAVE COLUMN", octaveColumn), ("KOTEKAN", kotekan), ("FIVE AGAINST EIGHT", fiveAgainstEight),
        ("MIRRORED PITCH", mirroredPitch), ("FIFTH ABOVE", fifthAbove), ("HELD BREATH", heldBreath),
        ("STUTTER FILL", stutterFill), ("CALL AND HOLD", callAndHold), ("LONG TAIL", longTail),
        ("GAPPED GROOVE", gappedGroove), ("EARLY BLOOM", earlyBloom), ("SCALE WALK", scaleWalk),
        ("ARPEGGIO LADDER", arpeggioLadder), ("BACKWARDS GLANCE", backwardsGlance),
    ]

    // 1. STRIDE WALK — two riff lanes walk the SAME shared pattern at different STRIDEs over a 5-step window
    // (3 and 2), so they visit the same 5 ranks in a different order; a plain low bass anchors underneath.
    static func strideWalk() -> PluginState { base { s in
        var l = [EuclidLine(), EuclidLine(), EuclidLine(), EuclidLine()]
        l[0].sourceMode = .key; l[0].useRiff = true; l[0].riffDir = .forward
        l[0].riffStride = 3; l[0].riffLength = 5; l[0].pulses = 5; l[0].steps = 8; l[0].rate = .r1_8
        l[1].sourceMode = .key; l[1].useRiff = true; l[1].riffDir = .forward
        l[1].riffStride = 2; l[1].riffLength = 5; l[1].pulses = 3; l[1].steps = 8; l[1].rate = .r1_8
        l[1].riffOctave = -1
        l[2].sourceMode = .key; l[2].noteSel = .low; l[2].pulses = 2; l[2].steps = 8; l[2].octave = -2; l[2].rate = .r1_4
        l[3].enabled = false
        s.euclideousLines = l
        s.euclideousRiff = EuclideousRiff(steps: 8, ranks: nil)
    } }

    // 2. MIRROR WALK — a riff lane walks a wide zigzag shape; a second lane walks the SAME positions with
    // riffInvert engaged (9−rank mirror), so the two trace complementary pitch contours against each other.
    static func mirrorWalk() -> PluginState { base { s in
        var l = [EuclidLine(), EuclidLine(), EuclidLine(), EuclidLine()]
        l[0].sourceMode = .key; l[0].useRiff = true; l[0].riffDir = .forward; l[0].pulses = 6; l[0].steps = 8; l[0].rate = .r1_8
        l[1].sourceMode = .key; l[1].useRiff = true; l[1].riffDir = .forward; l[1].riffInvert = true
        l[1].pulses = 6; l[1].steps = 8; l[1].rate = .r1_8; l[1].riffOctave = -1
        l[2].enabled = false; l[3].enabled = false
        s.euclideousLines = l
        s.euclideousRiff = EuclideousRiff(steps: 8, ranks: zigzagShape)
    } }

    // 3. PENDULUM — the riff walk bounces once off each end of the shared pattern (RiffDir.pendulum) over a
    // steady 1/8 pulse; a sparse low lane marks every other bounce.
    static func pendulum() -> PluginState { base { s in
        var l = [EuclidLine(), EuclidLine(), EuclidLine(), EuclidLine()]
        l[0].sourceMode = .key; l[0].useRiff = true; l[0].riffDir = .pendulum; l[0].pulses = 7; l[0].steps = 8; l[0].rate = .r1_8
        l[1].sourceMode = .key; l[1].noteSel = .low; l[1].pulses = 2; l[1].steps = 8; l[1].octave = -1; l[1].rate = .r1_4
        l[2].enabled = false; l[3].enabled = false
        s.euclideousLines = l
    } }

    // 4. PING-PONG LEAD — the riff walk bounces TWICE at each end (RiffDir.pingpong — a genuinely different
    // mechanism from PENDULUM, each endpoint sounds on two consecutive ticks), transposed up a third and
    // given a brighter octave to read as a lead line over a held low root.
    static func pingPongLead() -> PluginState { base { s in
        var l = [EuclidLine(), EuclidLine(), EuclidLine(), EuclidLine()]
        l[0].sourceMode = .key; l[0].useRiff = true; l[0].riffDir = .pingpong
        l[0].pulses = 6; l[0].steps = 8; l[0].rate = .r1_16; l[0].riffOctave = 1; l[0].melodyTranspose = 2
        l[1].sourceMode = .key; l[1].noteSel = .low; l[1].pulses = 1; l[1].steps = 8; l[1].octave = -2; l[1].rate = .r1_2; l[1].gate = 0.95
        l[2].enabled = false; l[3].enabled = false
        s.euclideousLines = l
    } }

    // 5. DRUNKEN WALK — a true random walk over the shared pattern (RiffDir.drunk), neutral bias, so the
    // melody wanders without a strong forward/backward pull; a plain pulse keeps time underneath.
    static func drunkenWalk() -> PluginState { base { s in
        var l = [EuclidLine(), EuclidLine(), EuclidLine(), EuclidLine()]
        l[0].sourceMode = .key; l[0].useRiff = true; l[0].riffDir = .drunk; l[0].riffDirBias = 0
        l[0].pulses = 5; l[0].steps = 8; l[0].rate = .r1_8
        l[1].sourceMode = .key; l[1].noteSel = .low; l[1].pulses = 4; l[1].steps = 8; l[1].octave = -1; l[1].rate = .r1_8
        l[2].enabled = false; l[3].enabled = false
        s.euclideousLines = l
    } }

    // 6. RANDOM GARDEN — three independent RANDOM-walk riff lanes, each with its own seed, all reading the
    // same shared pattern — three voices scattering differently over identical material.
    static func randomGarden() -> PluginState { base { s in
        var l = [EuclidLine(), EuclidLine(), EuclidLine(), EuclidLine()]
        for i in 0..<3 {
            l[i].sourceMode = .key; l[i].useRiff = true; l[i].riffDir = .random; l[i].riffDirSeed = i * 7 + 3
            l[i].pulses = 4; l[i].steps = 8; l[i].rate = i == 0 ? .r1_8 : (i == 1 ? .r1_16 : .r1_4)
            l[i].riffOctave = i - 1
        }
        l[3].enabled = false
        s.euclideousLines = l
        s.euclideousRiff = EuclideousRiff(steps: 8, ranks: zigzagShape)
    } }

    // 7. OCTAVE COLUMN — all 4 lanes walk the SAME arch-shaped pattern, forward, in lockstep (same HITS/rate),
    // stacked a fourth octave apart — one rhythm read simultaneously as a column of octaves.
    static func octaveColumn() -> PluginState { base { s in
        var l = [EuclidLine(), EuclidLine(), EuclidLine(), EuclidLine()]
        for i in 0..<4 {
            l[i].sourceMode = .key; l[i].useRiff = true; l[i].riffDir = .forward
            l[i].pulses = 5; l[i].steps = 8; l[i].rate = .r1_8; l[i].riffOctave = i - 2
        }
        s.euclideousLines = l
        s.euclideousRiff = EuclideousRiff(steps: 8, ranks: archShape)
    } }

    // 8. KOTEKAN — the classic Balinese interlocking-hands figure: two fast plain Euclid lanes share the same
    // density (4-of-8) but are offset by one ROTATE step, so their hits never coincide and interlock into one
    // composite pulse.
    static func kotekan() -> PluginState { base { s in
        var l = [EuclidLine(), EuclidLine(), EuclidLine(), EuclidLine()]
        l[0].sourceMode = .key; l[0].noteSel = .low; l[0].pulses = 4; l[0].steps = 8; l[0].rotate = 0; l[0].rate = .r1_16
        l[1].sourceMode = .key; l[1].noteSel = .high; l[1].pulses = 4; l[1].steps = 8; l[1].rotate = 1; l[1].rate = .r1_16
        l[1].octave = 1
        l[2].enabled = false; l[3].enabled = false
        s.euclideousLines = l
    } }

    // 9. FIVE AGAINST EIGHT — a 5-step lane and an 8-step lane at the SAME rate, each a dense Euclid pattern —
    // a textbook polymeter, the two cycles slipping in and out of phase with each other.
    static func fiveAgainstEight() -> PluginState { base { s in
        var l = [EuclidLine(), EuclidLine(), EuclidLine(), EuclidLine()]
        l[0].sourceMode = .key; l[0].noteSel = .low; l[0].pulses = 3; l[0].steps = 5; l[0].rate = .r1_8
        l[1].sourceMode = .key; l[1].noteSel = .high; l[1].pulses = 5; l[1].steps = 8; l[1].rate = .r1_8; l[1].octave = 1
        l[2].enabled = false; l[3].enabled = false
        s.euclideousLines = l
    } }

    // 10. MIRRORED PITCH — a plain reference lane (lowest note, steady) sits beside a riff lane with riffInvert
    // engaged, so every pitch the riff lane plays is the 9-rank mirror of the shared pattern — heard against
    // the fixed reference, the contrast is the point.
    static func mirroredPitch() -> PluginState { base { s in
        var l = [EuclidLine(), EuclidLine(), EuclidLine(), EuclidLine()]
        l[0].sourceMode = .key; l[0].noteSel = .low; l[0].pulses = 2; l[0].steps = 8; l[0].rate = .r1_4
        l[1].sourceMode = .key; l[1].useRiff = true; l[1].riffDir = .forward; l[1].riffInvert = true
        l[1].pulses = 6; l[1].steps = 8; l[1].rate = .r1_8
        l[2].enabled = false; l[3].enabled = false
        s.euclideousLines = l
    } }

    // 11. FIFTH ABOVE — two riff lanes walk the identical shared pattern/stride/length in lockstep; the second
    // carries MELODY TRANSPOSE +4 (a fifth, in scale-degree/rank space) over the first — parallel harmony a
    // fifth above, not a doubled unison.
    static func fifthAbove() -> PluginState { base { s in
        var l = [EuclidLine(), EuclidLine(), EuclidLine(), EuclidLine()]
        l[0].sourceMode = .key; l[0].useRiff = true; l[0].riffDir = .forward; l[0].pulses = 5; l[0].steps = 8; l[0].rate = .r1_8
        l[1].sourceMode = .key; l[1].useRiff = true; l[1].riffDir = .forward; l[1].pulses = 5; l[1].steps = 8; l[1].rate = .r1_8
        l[1].melodyTranspose = 4
        l[2].enabled = false; l[3].enabled = false
        s.euclideousLines = l
    } }

    // 12. HELD BREATH — very sparse hits (2 of 8) at a slow rate with GATE pushed near its ceiling, so each
    // struck note sustains almost to the next — long held tones separated by real silence, a breath between.
    static func heldBreath() -> PluginState { base { s in
        var l = [EuclidLine(), EuclidLine(), EuclidLine(), EuclidLine()]
        l[0].sourceMode = .key; l[0].noteSel = .low; l[0].pulses = 2; l[0].steps = 8; l[0].rate = .r1_2; l[0].gate = 0.98
        l[1].sourceMode = .key; l[1].noteSel = .high; l[1].pulses = 1; l[1].steps = 8; l[1].rate = .r1_1; l[1].gate = 0.98
        l[1].octave = 1
        l[2].enabled = false; l[3].enabled = false
        s.euclideousLines = l
    } }

    // 13. STUTTER FILL — a fast, dense riff lane (14-of-16, 1/32) with ADVANCE=STEP (every grid step moves the
    // walk forward, not just hits), so a rest doesn't pause the walk — it reads as a rapid, stuttering fill.
    static func stutterFill() -> PluginState { base { s in
        var l = [EuclidLine(), EuclidLine(), EuclidLine(), EuclidLine()]
        l[0].sourceMode = .key; l[0].useRiff = true; l[0].riffDir = .forward; l[0].riffAdvanceStep = true
        l[0].riffLength = 8; l[0].pulses = 14; l[0].steps = 16; l[0].rate = .r1_32
        l[1].sourceMode = .key; l[1].noteSel = .low; l[1].pulses = 1; l[1].steps = 8; l[1].octave = -2; l[1].rate = .r1_1
        l[2].enabled = false; l[3].enabled = false
        s.euclideousLines = l
    } }

    // 14. CALL AND HOLD — a sparse "call" riff lane (the CALL shared shape: alternating note/rest) answered by
    // a second riff lane set to ON-REST=TIE, so its own hits ring on through every rest instead of cutting —
    // the call rings, held.
    static func callAndHold() -> PluginState { base { s in
        var l = [EuclidLine(), EuclidLine(), EuclidLine(), EuclidLine()]
        l[0].sourceMode = .key; l[0].useRiff = true; l[0].riffDir = .forward; l[0].pulses = 8; l[0].steps = 8; l[0].rate = .r1_8
        l[1].sourceMode = .key; l[1].useRiff = true; l[1].riffDir = .forward; l[1].riffOnRest = .tie
        l[1].pulses = 5; l[1].steps = 8; l[1].rate = .r1_8; l[1].riffOctave = -1
        l[2].enabled = false; l[3].enabled = false
        s.euclideousLines = l
        s.euclideousRiff = EuclideousRiff(steps: 8, ranks: callShape)
    } }

    // 15. LONG TAIL — every riff rest is filled by extending the PRECEDING note's own gate (ON-REST=TIE) over
    // a dense pattern, so almost nothing re-articulates — the melody reads as one long, slowly evolving tone.
    static func longTail() -> PluginState { base { s in
        var l = [EuclidLine(), EuclidLine(), EuclidLine(), EuclidLine()]
        l[0].sourceMode = .key; l[0].useRiff = true; l[0].riffDir = .forward; l[0].riffOnRest = .tie
        l[0].pulses = 6; l[0].steps = 8; l[0].rate = .r1_8
        l[1].sourceMode = .key; l[1].noteSel = .low; l[1].pulses = 1; l[1].steps = 8; l[1].octave = -2; l[1].rate = .r1_1; l[1].gate = 0.98
        l[2].enabled = false; l[3].enabled = false
        s.euclideousLines = l
        s.euclideousRiff = EuclideousRiff(steps: 8, ranks: sparseShape)
    } }

    // 16. GAPPED GROOVE — a normally-dense Euclid lane (6 of 8) with GAPS engaged (the pattern inverts, so it
    // strikes only its 2 ORIGINAL rests) sits against a lane playing the un-inverted original — the "groove"
    // and its own photographic-negative gap pattern, side by side.
    static func gappedGroove() -> PluginState { base { s in
        var l = [EuclidLine(), EuclidLine(), EuclidLine(), EuclidLine()]
        l[0].sourceMode = .key; l[0].noteSel = .low; l[0].pulses = 6; l[0].steps = 8; l[0].rate = .r1_8
        l[1].sourceMode = .key; l[1].noteSel = .high; l[1].pulses = 6; l[1].steps = 8; l[1].rate = .r1_8
        l[1].patternMiss = true; l[1].octave = 1
        l[2].enabled = false; l[3].enabled = false
        s.euclideousLines = l
    } }

    // 17. EARLY BLOOM — TILT pushed hard negative bunches a lane's hits early in its own cycle, leaving the
    // back half silent — the pattern "blooms" at the start of every pass then rests.
    static func earlyBloom() -> PluginState { base { s in
        var l = [EuclidLine(), EuclidLine(), EuclidLine(), EuclidLine()]
        l[0].sourceMode = .key; l[0].noteSel = .cycle; l[0].pulses = 4; l[0].steps = 8; l[0].tilt = -1; l[0].rate = .r1_8
        l[1].sourceMode = .key; l[1].noteSel = .low; l[1].pulses = 1; l[1].steps = 8; l[1].octave = -1; l[1].rate = .r1_1
        l[2].enabled = false; l[3].enabled = false
        s.euclideousLines = l
    } }

    // 18. SCALE WALK — every active lane reads straight from the page's own KEY (D dorian), each cycling
    // ascending through the scale pool at a different rate/octave — a literal walk up and down the key.
    static func scaleWalk() -> PluginState { base { s in
        var l = [EuclidLine(), EuclidLine(), EuclidLine(), EuclidLine()]
        l[0].sourceMode = .key; l[0].noteSel = .cycle; l[0].pulses = 8; l[0].steps = 8; l[0].rate = .r1_8
        l[1].sourceMode = .key; l[1].noteSel = .cycle; l[1].pulses = 4; l[1].steps = 8; l[1].rate = .r1_4; l[1].octave = -1
        l[2].enabled = false; l[3].enabled = false
        s.euclideousLines = l
        s.euclideousKeyRoot = 2    // D
        s.euclideousKeyType = .dorian
    } }

    // 19. ARPEGGIO LADDER — the shared ascending RUN shape, walked forward by one riff lane and simultaneously
    // by a second lane an octave up, each ROTATE-offset from the other — a rising ladder of thirds.
    static func arpeggioLadder() -> PluginState { base { s in
        var l = [EuclidLine(), EuclidLine(), EuclidLine(), EuclidLine()]
        l[0].sourceMode = .key; l[0].useRiff = true; l[0].riffDir = .forward; l[0].pulses = 8; l[0].steps = 8; l[0].rate = .r1_16
        l[1].sourceMode = .key; l[1].useRiff = true; l[1].riffDir = .forward; l[1].riffRotate = 2
        l[1].pulses = 8; l[1].steps = 8; l[1].rate = .r1_16; l[1].riffOctave = 1
        l[2].enabled = false; l[3].enabled = false
        s.euclideousLines = l
        s.euclideousRiff = EuclideousRiff(steps: 8, ranks: runShape)
    } }

    // 20. BACKWARDS GLANCE — the shared DESCEND shape, walked REVERSE (RiffDir.reverse — a true backward
    // read, not just a descending shape played forward) alongside a lane whose Euclid PATTERN direction is
    // itself BKW — two independent senses of "backward" layered together.
    static func backwardsGlance() -> PluginState { base { s in
        var l = [EuclidLine(), EuclidLine(), EuclidLine(), EuclidLine()]
        l[0].sourceMode = .key; l[0].useRiff = true; l[0].riffDir = .reverse; l[0].pulses = 6; l[0].steps = 8; l[0].rate = .r1_8
        l[1].sourceMode = .key; l[1].noteSel = .low; l[1].pulses = 4; l[1].steps = 8; l[1].direction = .bkw; l[1].octave = -1; l[1].rate = .r1_8
        l[2].enabled = false; l[3].enabled = false
        s.euclideousLines = l
        s.euclideousRiff = EuclideousRiff(steps: 8, ranks: descendShape)
    } }
}
