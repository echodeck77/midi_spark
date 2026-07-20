//  TestSessions.swift
//  Canned documents for on-device verification (docs/test-procedures.md T1–T8).
//
//  There is no grid UI until step 5, so the router cannot be exercised without these.
//  Each session is a complete PluginState loaded through the NORMAL document path
//  (see MidiSparkAudioUnit.loadTestSession), which incidentally exercises fullState-shaped
//  mutation end-to-end.
//
//  Deliberately NOT built on PluginState.factory(): the factory carries designed defaults
//  (gold octaves 2 / B rate 1/32, cyan = RATCHET, magenta transpose +12 & OUT CH 2) that
//  would silently colour every result. Tests start from a flat, explicit baseline so a
//  failure means the engine, not the fixture.
//
//  IDENTITY TYPES: only ARP is implemented. Per docs/router-design.md, every other
//  processor type behaves as identity (its sounding set = its input pool, articulated at
//  step entry). T2/T3/T5/T7 rely on that — they use non-ARP types deliberately.

import Foundation

enum TestSessions {

    struct Session {
        let id: String          // "T1"
        let title: String       // short button label detail
        let expect: String      // what correct behaviour sounds like (shown in the panel)
        let make: () -> PluginState
    }

    // MARK: - Fixtures

    /// 16 ARP Colours, all at documented defaults: UP, 1/16, 1 octave, gate 0.6, RETRIG,
    /// morph 0, transpose 0, OUT CH INHERIT. Sessions override only what they are testing.
    private static func baseColours() -> [Colour] {
        colourIDs.map { Colour(colourID: $0, type: .arp) }
    }

    private static func idx(_ id: String) -> Int { colourIDs.firstIndex(of: id)! }

    /// Scene with the standing defaults: stepRate 1/2 (2 beats = 8 ticks of 1/16 per column),
    /// swing 50 (identity), QUANT off. Swing stays at 50 so T-cases never confound the
    /// bridge's swing warp with router behaviour — B3 tests swing, these do not.
    private static func scene(_ build: (inout SceneState) -> Void) -> SceneState {
        var s = SceneState.empty()
        s.stepRate = .r1_2
        s.swing = 50
        build(&s)
        return s
    }

    private static func doc(_ colours: [Colour], _ s: SceneState) -> PluginState {
        PluginState(colours: colours, scenes: [s])
    }

    // MARK: - T1–T8

    static let all: [Session] = [

        Session(id: "T1", title: "single ARP",
                expect: "Ascending 1/16 arp on Synth1 (bus A) only, and only while column 0 is "
                      + "active — 1 step in 8. Monitor A: clean on/off pairs, silence for the "
                      + "other 7 steps.") {
            doc(baseColours(), scene { s in
                s.cells[0][0] = Cell(colourID: "gold")            // buses default [.a]
            })
        },

        Session(id: "T2", title: "chain",
                expect: "Sound leaves ONLY through row 1 (§2.3). Row 0 has no letters lit, so it "
                      + "must be silent on every bus despite driving the chain. Row 1 (identity) "
                      + "MIRRORS the feed — a faithful copy of the arp, emitted from row 1.") {
            var c = baseColours()
            c[idx("cyan")].type = .ratchet                     // identity stand-in (RATCHET unimplemented)
            return doc(c, scene { s in
                s.cells[0][0] = Cell(colourID: "gold", stack: true, buses: [])   // feeds down, emits nothing
                s.cells[0][1] = Cell(colourID: "cyan", buses: [.a])              // identity: mirrors the feed
            })
        },

        Session(id: "T3", title: "+SRC merge",
                expect: "As T2 but row 1's input = feed ∪ source (§2.2). Audibly denser than T2 "
                      + "on the same chord: the held notes sound alongside the arp's output.") {
            var c = baseColours()
            c[idx("cyan")].type = .ratchet                     // identity for now; explicit for clarity
            return doc(c, scene { s in
                s.cells[0][0] = Cell(colourID: "gold", stack: true, buses: [])
                s.cells[0][1] = Cell(colourID: "cyan", buses: [.a], srcMix: true)
            })
        },

        Session(id: "T4", title: "fan-out",
                expect: "Identical simultaneous streams on Synth1 and Synth2. Monitors A and B "
                      + "show duplicate events, each independently well-paired (§2.3).") {
            doc(baseColours(), scene { s in
                s.cells[0][0] = Cell(colourID: "gold", buses: [.a, .b])
            })
        },

        Session(id: "T5", title: "muted-feeder reroute",
                expect: "Feeder (row 0) is muted, so row 1 reverts to SOURCE input (§2.1) and "
                      + "plays as if unchained — NOT silence. Diag panel is the visual check "
                      + "until the wiring UI exists.") {
            var c = baseColours()
            c[idx("cyan")].type = .ratchet                     // identity: unfed → holds the source chord
            return doc(c, scene { s in
                var feeder = Cell(colourID: "gold", stack: true, buses: [])
                feeder.muted = true
                s.cells[0][0] = feeder
                s.cells[0][1] = Cell(colourID: "cyan", buses: [.a])
            })
        },

        Session(id: "T6", title: "OUT CH stamping",
                expect: "Monitor A shows the gold cell on the keyboard's ORIGINAL channel "
                      + "(INHERIT) and the magenta cell on ch 5 (§2.6). Set Synth1 to omni to "
                      + "hear both. Neither is an input filter — both hear the same source.") {
            var c = baseColours()
            c[idx("magenta")].outChannel = 5
            return doc(c, scene { s in
                s.cells[0][0] = Cell(colourID: "gold", buses: [.a])        // INHERIT
                s.cells[0][1] = Cell(colourID: "magenta", buses: [.a])     // stamped ch 5
            })
        },

        Session(id: "T7", title: "collision policy",
                expect: "Hold ONE note. Row 0 (identity) sustains it; row 1 arps the same pitch "
                      + "on the same bus+channel. Expect ZERO dropouts in the sustained note, "
                      + "every arp strike re-articulating, and exactly ONE note-off after the "
                      + "last holder releases (§7 clauses 1–4). No off 'holes' mid-step.") {
            var c = baseColours()
            c[idx("teal")].type = .strum                       // identity: sustains its input pool
            return doc(c, scene { s in
                s.cells[0][0] = Cell(colourID: "teal", buses: [.a])        // sustained
                s.cells[0][1] = Cell(colourID: "gold", buses: [.a])        // same pitch, arped
            })
        },

        Session(id: "T8", title: "PHASE modes",
                expect: "Hold a 4-note chord. Cols 0 & 2 = RETRIG (each restarts at index 0). "
                      + "Cols 4–5 = LEGATO across a 2-column run: the 8-note pattern (4 notes × "
                      + "2 oct) must complete ONCE across the run — no repeats, no skips; a gap "
                      + "restarts at 0. Col 7 = FREE, pattern length 3 (hold 3 notes) against 8 "
                      + "ticks per column, so successive passes catch different slices; loop the "
                      + "host and the slices stay consistent (no drift).") {
            var c = baseColours()
            c[idx("gold")].paramsA.phase = .retrig
            c[idx("azure")].paramsA.phase = .legato
            c[idx("azure")].paramsA.octaves = 2                // 4-note chord × 2 = the 8-note pattern
            c[idx("azure")].paramsA.rate = .r1_8              // 4 ticks/col × 2-col run = 8 = one pass of the pattern
            c[idx("mint")].paramsA.phase = .free
            c[idx("mint")].paramsA.octaves = 1                 // length 3 on a 3-note hold: coprime with 8
            return doc(c, scene { s in
                s.cells[0][0] = Cell(colourID: "gold", buses: [.a])    // RETRIG, column 0
                s.cells[2][0] = Cell(colourID: "gold", buses: [.a])    // RETRIG, column 2
                s.cells[4][0] = Cell(colourID: "azure", buses: [.a])   // LEGATO run, columns 4…
                s.cells[5][0] = Cell(colourID: "azure", buses: [.a])   // …and 5
                s.cells[7][0] = Cell(colourID: "mint", buses: [.a])    // FREE
            })
        },
    ]
}
