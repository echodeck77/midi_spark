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
        var d = PluginState(colours: colours, scenes: [s])
        d.formatVersion = 3   // v3.0 fixtures set inputRow directly — skip the legacy chain migration
        return d
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

        Session(id: "T2", title: "reference chain",
                expect: "Sound leaves ONLY through row 1. Row 0 gold ARP has no letters lit → silent "
                      + "on every bus; row 1 references row 0 (FROM ROW 0) and MIRRORS it onto bus A. "
                      + "The old ▾ chain, now a receiver-picked reference (delta §1).") {
            doc(baseColours(), scene { s in
                s.cells[0][0] = Cell(colourID: "gold", buses: [])                                 // parent, emits nothing
                s.cells[0][1] = Cell(colourID: "cyan", buses: [.a], bypassed: true, inputRow: 0)  // references row 0
            })
        },

        Session(id: "T3", title: "sibling source tap",
                expect: "The old +SRC intent as SIBLINGS (delta §1 — no input union). Row 0 gold ARP "
                      + "(no bus); row 1 references row 0 → bus A (the processed feed); row 2 hears "
                      + "MIDI IN → bus A (the source chord). Bus A carries BOTH, denser than T2. Two "
                      + "cells on the same bus, each well-paired on the monitor.") {
            doc(baseColours(), scene { s in
                s.cells[0][0] = Cell(colourID: "gold", buses: [])                                 // parent arp
                s.cells[0][1] = Cell(colourID: "cyan", buses: [.a], bypassed: true, inputRow: 0)  // mirror the arp → A
                s.cells[0][2] = Cell(colourID: "teal", buses: [.a], bypassed: true)               // MIDI IN → source chord → A
            })
        },

        Session(id: "T4", title: "fan-out",
                expect: "Identical simultaneous streams on Synth1 and Synth2. Monitors A and B "
                      + "show duplicate events, each independently well-paired (§2.3).") {
            doc(baseColours(), scene { s in
                s.cells[0][0] = Cell(colourID: "gold", buses: [.a, .b])
            })
        },

        Session(id: "T5", title: "muted-parent reroute",
                expect: "Row 1 references row 0. MUTE row 0 (its parent): row 1 reverts to MIDI IN "
                      + "(delta §1 reroute) and plays the SOURCE chord — NOT silence; unmute → back to "
                      + "mirroring. Mute/unmute at speed while holding a chord: zero stuck notes "
                      + "(acceptance 30 — the reroute hotspot).") {
            doc(baseColours(), scene { s in
                var parent = Cell(colourID: "gold", buses: [])
                parent.muted = true
                s.cells[0][0] = parent
                s.cells[0][1] = Cell(colourID: "cyan", buses: [.a], bypassed: true, inputRow: 0)   // references (muted) row 0
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
            doc(baseColours(), scene { s in
                s.cells[0][0] = Cell(colourID: "teal", buses: [.a], bypassed: true)   // BYPASS identity: sustains its pool
                s.cells[0][1] = Cell(colourID: "gold", buses: [.a])                   // same pitch, arped
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

        // ---- v3.0 graph routing: fan-out, cycles, backward taps (acceptance 29/30/32) ----

        Session(id: "T9", title: "fan-out tree",
                expect: "One engine, several treatments (acceptance 29/30). Row 0 gold ARP (no bus). "
                      + "Row 1 references row 0 (azure ARP ×2oct) → bus A. Row 2 references row 0 "
                      + "(identity) → bus B. Row 3 references row 1 (grandchild identity) → bus C. A & "
                      + "B share melodic material from ONE arp under different processing; C follows "
                      + "row 1. MUTE row 0 → all three revert to source-derived behaviour at once.") {
            var c = baseColours()
            c[idx("azure")].paramsA.octaves = 2
            return doc(c, scene { s in
                s.cells[0][0] = Cell(colourID: "gold", buses: [])                                  // parent arp
                s.cells[0][1] = Cell(colourID: "azure", buses: [.a], inputRow: 0)                  // arp-of-arp → A
                s.cells[0][2] = Cell(colourID: "cyan", buses: [.b], bypassed: true, inputRow: 0)   // mirror parent → B
                s.cells[0][3] = Cell(colourID: "teal", buses: [.c], bypassed: true, inputRow: 1)   // grandchild of azure → C
            })
        },

        Session(id: "T10", title: "transpose accumulates",
                expect: "§2.6: transpose accumulates along a reference. Row 0 gold (+5, no bus); row "
                      + "1 cyan identity (+7) references row 0 → bus A sounds +12 semitones above the "
                      + "held notes (one octave up), NOT +7.") {
            var c = baseColours()
            c[idx("gold")].transpose = 5
            c[idx("cyan")].transpose = 7
            return doc(c, scene { s in
                s.cells[0][0] = Cell(colourID: "gold", buses: [])                                 // +5, no bus
                s.cells[0][1] = Cell(colourID: "cyan", buses: [.a], bypassed: true, inputRow: 0)  // +7 → +12
            })
        },

        Session(id: "T11", title: "cycle silence + backward tap",
                expect: "Acceptance 32. COL 0 = BACKWARD tap: row 0 azure ARP references row 1 (BELOW "
                      + "it); row 1 gold ARP hears MIDI IN. Row 0 arps row 1's current note — a "
                      + "downward reference that WORKS (ARP derivation) → bus A. COL 1 = a 2-cell "
                      + "CYCLE (row 0↔row 1 reference each other): nothing can enter → SILENT forever, "
                      + "no hang, no stuck notes. So: arp in column 0, silence in column 1.") {
            var c = baseColours()
            c[idx("azure")].paramsA.octaves = 2
            return doc(c, scene { s in
                s.cells[0][0] = Cell(colourID: "azure", buses: [.a], inputRow: 1)   // references BELOW → arps row 1
                s.cells[0][1] = Cell(colourID: "gold", buses: [])                   // MIDI IN source arp
                s.cells[1][0] = Cell(colourID: "gold", buses: [.a], inputRow: 1)    // cycle: refs row 1…
                s.cells[1][1] = Cell(colourID: "cyan", buses: [.a], inputRow: 0)    // …which refs row 0 → silent
            })
        },

        // ---- step 4: first real processor ----

        Session(id: "T12", title: "RATCHET",
                expect: "Hold a chord. Row 0 cyan RATCHET (count 4) on bus A re-strikes the WHOLE "
                      + "chord 4 times per column, staccato, with a velocity ramp (soft→loud, ramp "
                      + "0.8). Distinct from an ARP: no note-cycling — every stab is the full chord. "
                      + "Panel VOICES pulses to chord-size on each stab; EMIT climbs in bursts.") {
            var c = baseColours()
            c[idx("cyan")].type = .ratchet
            c[idx("cyan")].paramsA.count = 4                  // 4 stabs per column
            c[idx("cyan")].paramsA.ramp = 0.8                 // audible crescendo across the 4
            return doc(c, scene { s in
                s.cells[0][0] = Cell(colourID: "cyan", buses: [.a])   // unfed RATCHET on the source chord
            })
        },

        Session(id: "T13", title: "PASSGATE",
                expect: "§3/§4: gated per PASS (mod 4). Every column: row 0 gold ARP feeds row 1 "
                      + "cyan PASSGATE (bus A, mask [open, closed, open, closed]). Hold a chord: a "
                      + "CONTINUOUS arp for a whole cycle on pass 0, then full SILENCE for pass 1, "
                      + "arp again pass 2, silent pass 3 — repeating every 4 cycles (1 cycle = 16 "
                      + "beats at 1/2). Panel: 'pass' counts up; EMIT rises only on even passes. "
                      + "Click-safe — no stuck notes when it closes each cycle.") {
            var c = baseColours()
            c[idx("cyan")].type = .passgate
            c[idx("cyan")].paramsA.passes = [true, false, true, false]     // open on pass 0 & 2
            return doc(c, scene { s in
                for col in 0..<8 {
                    s.cells[col][0] = Cell(colourID: "gold", buses: [])                     // arp parent, no bus
                    s.cells[col][1] = Cell(colourID: "cyan", buses: [.a], inputRow: 0)      // PASSGATE references row 0
                }
            })
        },

        Session(id: "T14", title: "ARP patterns",
                expect: "Hold a 3–4 note chord. Each column arps it a different way on bus A: "
                      + "col 0 UP (ascending), col 1 DOWN (descending), col 2 UP-DN (up then back "
                      + "down, no repeated top/bottom note), col 3 RANDOM (shuffled but LOOP-"
                      + "CONSISTENT — identical every cycle; loop the host to confirm), col 4 "
                      + "AS-PLAYED (press-order). To hear AS-PLAYED differ from UP, press the notes "
                      + "in a NON-ascending order (e.g. highest first) — it follows your order.") {
            var c = baseColours()
            c[idx("orange")].paramsA.pattern = .down
            c[idx("vermilion")].paramsA.pattern = .upDown
            c[idx("wine")].paramsA.pattern = .random
            c[idx("magenta")].paramsA.pattern = .asPlayed
            return doc(c, scene { s in
                s.cells[0][0] = Cell(colourID: "gold", buses: [.a])        // UP (default)
                s.cells[1][0] = Cell(colourID: "orange", buses: [.a])      // DOWN
                s.cells[2][0] = Cell(colourID: "vermilion", buses: [.a])   // UP-DN
                s.cells[3][0] = Cell(colourID: "wine", buses: [.a])        // RANDOM
                s.cells[4][0] = Cell(colourID: "magenta", buses: [.a])     // AS-PLAYED
            })
        },

        Session(id: "T15", title: "STRUM",
                expect: "Hold a chord. Row 0 cyan STRUM on bus A rolls the chord in from LOW to HIGH "
                      + "over ~0.25 beat (spread), each note held to the column boundary, with a "
                      + "gentle crescendo (velTilt 0.4). Not simultaneous like a plain hold — you "
                      + "hear the notes arrive one after another. DIR up · spread 0.25 · curve 0 "
                      + "(even) · tilt +0.4.") {
            var c = baseColours()
            c[idx("cyan")].type = .strum
            c[idx("cyan")].paramsA.strumDir = .up
            c[idx("cyan")].paramsA.spread = 0.25
            c[idx("cyan")].paramsA.velTilt = 0.4
            return doc(c, scene { s in
                s.cells[0][0] = Cell(colourID: "cyan", buses: [.a])   // unfed STRUM on the source chord
            })
        },

        Session(id: "T16", title: "CHANCE",
                expect: "Hold a chord. Row 0 gold ARP feeds row 1 cyan CHANCE (probability 0.5) on "
                      + "bus A. Each arp note-on has a 50% chance to pass — you hear a thinned, "
                      + "stuttering arp (~half the notes). DETERMINISTIC: loop the host and the SAME "
                      + "notes drop every pass — not a live dice roll. Panel EMIT climbs ~half as "
                      + "fast as an ungated arp. (off follows on: dropped notes leave no stuck off.)") {
            var c = baseColours()
            c[idx("cyan")].type = .chance
            c[idx("cyan")].paramsA.probability = 0.5
            return doc(c, scene { s in
                s.cells[0][0] = Cell(colourID: "gold", buses: [])                    // arp parent, no bus
                s.cells[0][1] = Cell(colourID: "cyan", buses: [.a], inputRow: 0)     // CHANCE references row 0
            })
        },
    ]
}
