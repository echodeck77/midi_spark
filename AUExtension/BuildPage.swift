import SwiftUI
import UIKit   // ReelShareSheet (UIActivityViewController) — REEL-TO-REEL export
import UniformTypeIdentifiers   // FILE import: the .mid content type for the door sheet's file picker

// The ONE workshop voice: which SHOP section sounds — the MIDI CHAIN audition, the PART grid, or NEITHER. Each header
// toggles its own section (play ⇄ stop) so both can be off; picking one stops the other (they never sound together).
enum BuildWorkshopVoice { case none, chain, part }

// THE BUILD PAGE — design: Docs/AcceptanceCriteria/AcceptanceCriteria-build-page-two-grid-flow.md +
// -build-page-iteration-3.md + -build-page-iteration-4.md + Docs/mockup-build-three-grids-landscape.html
// (user 2026-08-11). The new PRIMARY workshop and default landing tab. Destined to REPLACE the DRAG&DROP + PROCESSORS
// (cell-edit) pages (both kept live until it supersedes them).
//
// THE FORM (user 2026-08-11: THREE EQUAL COLUMNS + the machinery strip along the bottom; NO focus highlight):
//   • LEFT COLUMN (the build flow, top→bottom): [● PLAY THIS CELL] → [PART ▾][+ NEW] → 1·INPUT (R1–R4, MIDI ⎓ | PIANO
//     ⌨ per door; a PIANO door reveals its octave keyboard) → 2·THE CAST (the FULL 4×4 palette, 16 slots) · 🎲
//     RANDOMIZE (the chain's die = roll the colour's machine) → 3·OUTPUT (A–D) → [APPLY TO STAGING →] → LITTER.
//   • MIDDLE COLUMN — STAGING (the workshop 8×8: row rail · loop keys · variation rows), with the VERBS in their own
//     box BELOW: [PLACE · MOVE · DELETE] (spring-held workbench verbs) then [APPLY TO PLAY → · MUTATE · 🎲 RE-ROLL].
//   • RIGHT COLUMN — the PLAY grid: five FIXED bands. THE TARGET DECIDES THE VERB: APPLY TO PLAY arms the bands →
//     tap a LANE = FLATTEN · tap a LADDER = COPY ROWS · tap FREE = takes land · long-press a ladder = flatten-into-row.
//   • MACHINERY STRIP (bottom, full width) — the chain: ID · receiver box · slots + ghost · emitter box.
//
// ┌─ BUILD STATUS ─ INCREMENT 1 (this file): LAYOUT SKELETON — placeholder content, NO engine wiring. Every dimension
// │ is a named constant in `BuildGeom`; each region is its own helper (placement edits are one-liners). NEXT (region
// │ by region): left-column I/O + cast → staging roll (reuse Dice) → the PLACE/MOVE/DELETE verbs (spring-hold + engine;
// │ retires the DRAG&DROP tab) → APPLY TO PLAY arming + the band-decides-verb landings → the real machinery snake.
// │ Deferred here: the PIANO keyboard is a placeholder; the real voice behind the buttons.  ──────────────────────────┘

// PLACEMENT KNOBS — every geometry number lives here so layout tweaks are one-liners.
private enum BuildGeom {
    static let colGap:   CGFloat = 10       // gap between the three equal columns
    static let cellMin:  CGFloat = 18       // grid cell clamp (both 8×8 grids share one cell size)
    static let cellMax:  CGFloat = 34
    static let cellGap:  CGFloat = 4         // inter-cell gap
    static let seam:     CGFloat = 2        // the gap between play bands
    static let barH:     CGFloat = 76       // the machinery snake bar height
    static let playCalm: Double = 0.45      // the PLAY grid CALMS — dimmer cells
    static let castSwatch: CGFloat = 28     // the cast palette swatch (8 across · 4 down)
    static let castGap:    CGFloat = 4
    static var castW: CGFloat { castSwatch * 8 + castGap * 7 }   // the cast's total width — INPUT/OUTPUT rows match it
}

// Placeholder cast hues (mockup palette). Real colours come from the part's cast when the palette is wired.
private let buildPanel = Color(red: 0.08, green: 0.09, blue: 0.11)
private let buildCell  = Color(red: 0.10, green: 0.12, blue: 0.15)
// PART AUTOMATION (Paul 2026-09-01): each chain (colour) gets FIVE Auto lanes — a DIRECT param automation (macros dropped
// to v2). A lane picks a processor param, sets its BEFORE→AFTER, a SPAN that shapes the curve/repeat WITHIN the painted
// extent (disabled for binary params), and an EXTENT of grid cells (painted via APPLY). Baked per-cell at build (rides the
// M2 substrate). Per-colour (shared across the colour's cells). `AutoLane`/`PartAutoColour` live in BuildModel.swift
// (Foundation-only, in the test target + Codable so the automation travels with the document).
private let buildDim   = Color(white: 0.36)
private let buildPink  = Color(red: 0.94, green: 0.41, blue: 0.85)
private let buildCyan  = Color(red: 0.19, green: 0.83, blue: 0.91)
private let buildRed   = Color(red: 0.91, green: 0.36, blue: 0.44)   // ROW 8 CLEAR + destructive verbs
private let buildEdge  = Color(white: 1).opacity(0.17)   // §0 MUTED-CHROME: a neutral whisper for default (non-armed) chrome borders — replaces standing cyan strokes
// THE ROOM SIGNATURES (Paul 2026-08-29, §8b WAYFINDING): each room owns a colour and every DOOR wears its DESTINATION's
// signature — RAINBOW = SELECT (a multicolour strip, refuses one hue) · AMBER = PART · INDIGO = PLAY (retires cyan) ·
// RED = REEL/record. Hex are starting points (Paul's glass tunes; the STRUCTURE is the instruction).
// TIDE & EMBER (Paul 2026-09-01): direction as temperature — IN cool, OUT warm; PART wears the warm "ember" signature,
// PLAY the cool "tide" one. (roomsIndigo keeps its name but now holds a sea-blue.)
let roomsAmber   = Color(red: 0.910, green: 0.592, blue: 0.239)   // PART — ~#E8973D (warm "ember" signature; RoomsPage uses these too)
let roomsIndigo  = Color(red: 0.227, green: 0.420, blue: 0.541)   // PLAY — ~#3A6B8A (cool "tide" signature; name kept, hue is sea-blue)
let roomsRedSig  = Color(red: 0.86, green: 0.30, blue: 0.30)   // REEL / record
let roomsRainbowHues: [Color] = [                              // SELECT — the mini-rainbow strip (Tide & Ember: warm→cool span)
    Color(red: 0.941, green: 0.275, blue: 0.235), Color(red: 1.000, green: 0.549, blue: 0.102),
    Color(red: 0.961, green: 0.773, blue: 0.094), Color(red: 0.400, green: 0.788, blue: 0.541),
    Color(red: 0.306, green: 0.604, blue: 0.784), Color(red: 0.561, green: 0.416, blue: 0.816)]
// BUILD grid PIANO-ROLL (Paul 2026-08-19): one scrolling note mark on a cell face; `lane` = pitch (0…1), born = when it sounded.
struct BuildRollNote: Equatable { var born: Date; var vel: Double; var lane: Double }

// BUILD UNDO (Paul 2026-08-27): one complete snapshot of the BUILD page's authoring @State + the document — every field a
// user action can change, so a restore is whole (never partial). Value types only (cheap COW copies).
struct BuildSnapshot {
    var stagingCells: [[String?]]; var stagingSel: [Int]; var stagingLane: UInt16
    var parts: [BuildPart]; var currentPart: Int; var returnPart: Int?
    var partEmitters: Set<Bus>; var partRate: StepRate?; var partLen: Int?
    var partCast: [String]; var castSlots: [Int: String]; var rowUnder: [String?]
    var rowReceiver: [Int?]; var rowEmitters: [Set<Bus>?]
    var performCells: [[String?]]; var performChain: [[[ProcessorSlot]]]; var performRecv: [Int]
    var performEmit: [Set<Bus>]; var performPart: [Int]; var performMute: Set<Int>
    var performStagingRow: [Int]; var performLane: UInt16
    var scenes: [BuildSceneSnapshot]; var activeScene: Int; var row8Cells: [Row8Cell]; var row8On: [Bool]
    var selID: String?; var selReceiver: Int
    var colourReg: [String: [ProcessorSlot]]; var colourTranspose: [String: Int]; var hueOverride: [String: UInt32]
    var idCounter: Int
    // THE ROOMS PLAY GRID (2026-08-31): the 10 parallel play-column arrays — added so play-grid edits (▲▼ swaps, ferries)
    // are undoable. Was omitted → the play grid had NO undo coverage. (Persistence via BuildPlayGridData is orthogonal.)
    var playCells: [[String?]]; var playSel: [Int]; var playColOn: [Bool]; var playColRecv: [Int]; var playColEmit: [Set<Bus>]
    var playColLen: [Int]; var playColSteps: [[String?]]; var playColRate: [StepRate?]; var playColStepRecv: [[Int]]; var playColStepEmit: [[Set<Bus>]]
    var doc: PluginState
}
private let buildRollLife = 1.6   // seconds a note takes to cross the cell

// iteration 4: the spring-held workbench verbs that replace the drag (the house law). Skeleton: tap arms/disarms.
// The part grid's ROW-BUTTON mode (Paul 2026-08-16): a radio that changes what the left row buttons DO — SELECT the
// whole row's rung · PLACE the selected colour · MUTATE a value-tweaked variant of it.
enum BuildRowMode: String, CaseIterable { case select = "SELECT", place = "PLACE", mutate = "MUTATE" }
enum BuildFill { case none, cell, grid }   // header playhead fill period: none · one step (.cell) · the whole loop (.grid)

// BuildPart / BuildUnassignedData moved to BuildModel.swift (now persisted + test-target-visible).

extension DiagView {

    @ViewBuilder private func buildIOHoldBanner() -> some View {
        if let m = buildIOHoldMsg {
            Text(m).font(.system(size: 12, weight: .heavy, design: .monospaced)).tracking(1).foregroundColor(.black)
                .padding(.horizontal, 16).padding(.vertical, 9)
                .background(Capsule().fill(buildCyan))
                .padding(.top, 10).allowsHitTesting(false).transition(.opacity)
        }
    }
    // ROOMS SHARED OVERLAYS + CHROME (Paul 2026-08-30, old-UI removal): the overlays/modifiers the rooms interface triggers
    // (config sheets, stage-eye, reel, ROW 8, file import, the IO-hold banner, scene-switch) — lifted out of the retired
    // buildPage. Kept HERE so they can reach the PRIVATE config-sheet views; roomsPage wraps its content with roomsChrome +
    // includes roomsSharedOverlays in its ZStack. (Before this, these were rendered only inside buildPage → dead in rooms,
    // so the header MIDI IN/OUT/RACK/ROW 8/RECORD buttons + the strip spanners silently did nothing.)
    @ViewBuilder func roomsSharedOverlays(_ size: CGSize) -> some View {
        if buildStageEye, let slot = buildEditSlot { AnyView(buildStageEyeView(slot: slot, size: size)) }   // §4 stage eye (from the card's truth strips)
        if reelShowPopup { AnyView(buildReelPopup(size: size)) }                                             // the reel PASS BROWSER (header RECORD)
        if buildMidiConfigOpen { AnyView(buildMidiConfigSheet(size: size)) }                                 // MIDI INPUTS (strip spanner + header)
        if buildRackConfigOpen { AnyView(buildRackConfigSheet(size: size)) }                                 // THE RACK (header)
        if buildMidiOutConfigOpen { AnyView(buildMidiOutConfigSheet(size: size)) }                           // MIDI OUTPUTS (strip spanner + header)
        if buildRow8EditOpen { AnyView(buildRow8EditPage(size: size)) }                                      // ROW 8 authoring (header)
    }
    @ViewBuilder func roomsChrome<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        content()
            .overlay(alignment: .top) { buildIOHoldBanner() }                                               // "HOLD TO APPLY TO ALL"
            .fileImporter(isPresented: Binding(get: { buildFileImportDoor != nil }, set: { if !$0 { buildFileImportDoor = nil } }),
                          allowedContentTypes: [UTType.midi, UTType(filenameExtension: "mid") ?? .data], allowsMultipleSelection: false) { result in
                buildHandleFileImport(result)                                                                // FILE import onto the picking door
            }
            .onChange(of: activeSceneIdx) { _ in buildSyncSceneSwitch(activeSceneIdx) }                       // scene chips → swap the play-grid arrangement
            .onChange(of: d.playing) { playing in if !playing { buildStopAllOnTransportStop() } }             // HOST TRANSPORT STOPPED → stop everything (Paul 2026-08-31)
    }
    // THE REEL-TO-REEL glyph (Paul 2026-08-19): tap → open the PASS BROWSER pop-up. The tape is ALWAYS capturing live
    // output while playing, so it reads as RECORDING — red with a pulsing record dot; GREEN while a pass replays; dim stopped.
    // ── THE MIDI INPUTS SHEET (config-sheets stage 5, §1/§5/§7/§9 — Paul 2026-08-20) ─────────────────────────────────
    // The SPACIOUS detail layer for the four INPUT doors. Each door: header (INPUT letter · channel [NONE/OMNI/1-16] ·
    // octave · range) + the INPUT MODE list where the SELECTED mode's own controls appear INLINE beneath it (KEYS = a
    // fresh multi-octave piano; REPLAY = passes + a realtime right→left input roll; FILE = import placeholder). Config
    // teaches here (wordy allowed); performance stays silent elsewhere. Names per §9: "MIDI INPUTS" · "INPUT MODE".
    private func buildDoorModeCopy(_ m: DoorMode) -> String {
        switch m {
        case .thru:   return "Play straight — live input feeds the grid, nothing latches."
        case .latch:  return "Each note toggles in or out of the held pool."
        case .hold:   return "A new chord replaces the held pool."
        case .keys:   return "Pick the held notes on the keyboard below."
        case .replay: return "Records this input and loops the last N passes back in."
        case .file:   return "Loops a loaded .mid into this input — a machine reading this input plays it."
        case .scale:  return "The pool is a whole scale — pick a key, no playing needed."
        }
    }
    @ViewBuilder private func buildMidiConfigSheet(size: CGSize) -> some View {
        let recvs = au?.uiReceivers() ?? []
        ZStack(alignment: .top) {                                   // TOP-aligned so the sheet sits high on the screen (Paul 2026-08-21)
            Color.black.opacity(0.65).ignoresSafeArea().contentShape(Rectangle()).onTapGesture { buildMidiConfigOpen = false }
            VStack(spacing: 0) {
                HStack {
                    Text("MIDI INPUTS").font(.system(size: 17, weight: .heavy, design: .monospaced)).tracking(2).foregroundColor(buildCyan)
                    Spacer()
                    Button { buildMidiConfigOpen = false } label: {
                        Image(systemName: "xmark").font(.system(size: 17, weight: .bold)).foregroundColor(buildDim).padding(10)
                    }
                }.padding(.horizontal, 26).padding(.top, 20).padding(.bottom, 10)
                buildMidiTabBar(recvs).padding(.horizontal, 26).padding(.bottom, 8)   // A/B/C/D tab header — one door at a time
                ScrollView(.vertical, showsIndicators: false) {
                    buildDoorSection(buildMidiConfigTab, r: buildMidiConfigTab < recvs.count ? recvs[buildMidiConfigTab] : Receiver())
                        .padding(.horizontal, 26).padding(.bottom, 30)
                }
            }
            .frame(width: min(720, size.width - 32), height: size.height - 96)
            .background(RoundedRectangle(cornerRadius: 18).fill(Color(red: 0.07, green: 0.08, blue: 0.10)))
            .overlay(RoundedRectangle(cornerRadius: 18).stroke(Color.white.opacity(0.12), lineWidth: 1))
            .padding(.top, 20)
        }
    }
    // THE A/B/C/D TAB BAR (Paul 2026-08-23) — one door shown at a time. A switch resets the two GLOBAL range-keyboard
    // flags so a pop-up left open on the previous door can't strand (the KEYS/REPLAY/FILE inline controls are per-door,
    // so they follow the tab). A small cyan dot marks a door with no mode chosen yet (needs SET).
    @ViewBuilder private func buildMidiTabBar(_ recvs: [Receiver]) -> some View {
        HStack(spacing: 6) {
            ForEach(0..<4, id: \.self) { i in
                let on = buildMidiConfigTab == i
                let hue = i < receiverHues.count ? receiverHues[i] : buildCyan
                let unset = (i < recvs.count ? recvs[i].doorMode : nil) == nil
                let tabLabel = (i < recvs.count ? recvs[i].scaleLabel : nil) ?? ["A", "B", "C", "D"][i]   // a SCALE door names itself ("A MIXO"); else the letter
                ZStack(alignment: .topTrailing) {
                    Text(tabLabel).font(.system(size: 15, weight: .black, design: .monospaced))
                        .foregroundColor(on ? .black : .white.opacity(0.7))
                        .lineLimit(1).minimumScaleFactor(0.5)
                        .frame(maxWidth: .infinity).frame(height: 34)
                        .background(RoundedRectangle(cornerRadius: 7).fill(on ? hue : buildCell))
                        .overlay(RoundedRectangle(cornerRadius: 7).stroke(on ? Color.clear : hue.opacity(0.4), lineWidth: 1))
                    if unset { Circle().fill(buildCyan).frame(width: 6, height: 6).padding(5) }   // "needs SET" dot
                }
                .contentShape(Rectangle())
                .onTapGesture { if buildMidiConfigTab != i { buildRangeKbdDoor = nil; buildRangeSetHi = false; buildMidiConfigTab = i } }
            }
        }
    }
    // THE MIDI OUTPUTS sheet (Paul 2026-08-23) — the twin of MIDI INPUTS, moved out of the cog: each emitter A–D with a
    // live OUT dot + its stamp CHANNEL (1–16). The RACK sheet stays separate (treatments/membership/setups).
    @ViewBuilder private func buildMidiOutConfigSheet(size: CGSize) -> some View {
        let chans = au?.uiBusChannels() ?? [1, 2, 3, 4]
        ZStack(alignment: .top) {
            Color.black.opacity(0.65).ignoresSafeArea().contentShape(Rectangle()).onTapGesture { buildMidiOutConfigOpen = false }
            VStack(spacing: 0) {
                HStack {
                    Text("MIDI OUTPUTS").font(.system(size: 17, weight: .heavy, design: .monospaced)).tracking(2).foregroundColor(buildCyan)
                    Spacer()
                    Button { buildMidiOutConfigOpen = false } label: {
                        Image(systemName: "xmark").font(.system(size: 17, weight: .bold)).foregroundColor(buildDim).padding(10)
                    }
                }.padding(.horizontal, 26).padding(.top, 20).padding(.bottom, 12)
                ScrollView(.vertical, showsIndicators: false) {
                    VStack(spacing: 14) {
                        ForEach(0..<4, id: \.self) { i in buildEmitterOutRow(i, chan: i < chans.count ? chans[i] : i + 1) }
                    }.padding(.horizontal, 26).padding(.bottom, 30)
                }
            }
            .frame(width: min(720, size.width - 32), height: size.height - 96)
            .background(RoundedRectangle(cornerRadius: 18).fill(Color(red: 0.07, green: 0.08, blue: 0.10)))
            .overlay(RoundedRectangle(cornerRadius: 18).stroke(Color.white.opacity(0.12), lineWidth: 1))
            .padding(.top, 20)
        }
    }
    @ViewBuilder private func buildEmitterOutRow(_ i: Int, chan: Int) -> some View {
        let letter = ["A", "B", "C", "D"][i]
        HStack(spacing: 14) {
            Text(letter).font(.system(size: 20, weight: .heavy, design: .monospaced)).foregroundColor(buildCyan).frame(width: 34, alignment: .leading)
            TimelineView(.animation(minimumInterval: 1.0 / 20.0, paused: animationsPaused)) { tl in   // live OUT dot — lights on emit, fades
                let age = i < meters.emitPeakAt.count ? tl.date.timeIntervalSince(meters.emitPeakAt[i]) : 999
                Circle().fill(Color(red: 0.36, green: 0.92, blue: 0.52).opacity(age < 0.4 ? 1.0 - age / 0.4 * 0.75 : 0.18)).frame(width: 10, height: 10)
            }
            Text("EMITTER \(letter)").font(.system(size: 12, weight: .semibold, design: .monospaced)).foregroundColor(.white.opacity(0.55))
            Spacer()
            Text("CHANNEL").font(.system(size: 10, weight: .heavy, design: .monospaced)).foregroundColor(buildDim)
            Menu {
                ForEach(1...16, id: \.self) { c in Button { setEmitterChannel(i, c) } label: { Label("CH \(c)", systemImage: chan == c ? "checkmark" : "circle") } }
            } label: {
                Text("CH \(chan)").font(.system(size: 14, weight: .heavy, design: .monospaced)).foregroundColor(buildCyan)
                    .padding(.horizontal, 12).frame(height: 32)
                    .background(RoundedRectangle(cornerRadius: 7).fill(buildCyan.opacity(0.14)))
                    .overlay(RoundedRectangle(cornerRadius: 7).stroke(buildCyan.opacity(0.6), lineWidth: 1))
            }
        }
    }
    // THE RACK sheet (config-sheets §6, Paul 2026-08-21; public name RACK everywhere, Paul 2026-08-22) — the twin of MIDI INPUTS. A SETUPS radio (RACK 1–4 =
    // the 4 membership configs) · a compact per-emitter MEMBERSHIP row (on the board / bypassed = raw wire) · the deep
    // TREATMENT stack inline (the RackMatrix editor, embedded). One self-contained surface — no jump to another page.
    @ViewBuilder private func buildRackConfigSheet(size: CGSize) -> some View {
        let active = au?.uiRackConfig() ?? 0
        let mask = au?.uiRackMask() ?? 0b1111
        let chans = au?.uiBusChannels() ?? [1, 2, 3, 4]
        ZStack(alignment: .top) {
            Color.black.opacity(0.65).ignoresSafeArea().contentShape(Rectangle()).onTapGesture { buildRackConfigOpen = false }
            VStack(spacing: 0) {
                HStack(spacing: 12) {
                    Text("THE RACK").font(.system(size: 17, weight: .heavy, design: .monospaced)).tracking(2).foregroundColor(buildCyan)
                    Text("SETUP · \(active + 1)").font(.system(size: 11, weight: .heavy, design: .monospaced)).foregroundColor(.black)
                        .padding(.horizontal, 8).frame(height: 22).background(RoundedRectangle(cornerRadius: 5).fill(buildCyan))
                    Spacer()
                    Button { buildRackConfigOpen = false } label: {
                        Image(systemName: "xmark").font(.system(size: 17, weight: .bold)).foregroundColor(buildDim).padding(10)
                    }
                }.padding(.horizontal, 26).padding(.top, 20).padding(.bottom, 12)
                ScrollView(.vertical, showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 18) {
                        buildRackSetupsRadio(active)                // RACK 1 · 2 · 3 · 4 (which config is live)
                        buildRackMembershipRow(mask: mask, chans: chans)   // ON BOARD: A B C D (each emitter's board in/out of path)
                        Text("TREATMENTS").font(.system(size: 9, weight: .heavy, design: .monospaced)).tracking(1).foregroundColor(buildDim)
                        rackMatrixView                              // the deep per-emitter treatment editor, inline (embedded mode)
                    }.padding(.horizontal, 26).padding(.bottom, 30)
                }
            }
            .frame(width: min(720, size.width - 32), height: size.height - 96)
            .background(RoundedRectangle(cornerRadius: 18).fill(Color(red: 0.07, green: 0.08, blue: 0.10)))
            .overlay(RoundedRectangle(cornerRadius: 18).stroke(Color.white.opacity(0.12), lineWidth: 1))
            .padding(.top, 20)
        }
    }
    // SETUPS radio: the 4 rack CONFIGS — tap to make one LIVE (setRackConfig). Membership edits below write the live one.
    @ViewBuilder private func buildRackSetupsRadio(_ active: Int) -> some View {
        let refresh = { self.receivers = self.au?.uiReceivers() ?? self.receivers; self.refreshFromDocument() }
        VStack(alignment: .leading, spacing: 6) {
            Text("SETUPS").font(.system(size: 9, weight: .heavy, design: .monospaced)).tracking(1).foregroundColor(buildDim)
            HStack(spacing: 8) {
                ForEach(0..<4, id: \.self) { c in
                    let on = c == active
                    Text("SETUP \(c + 1)").font(.system(size: 12, weight: .heavy, design: .monospaced)).foregroundColor(on ? .black : buildCyan)
                        .frame(maxWidth: .infinity).frame(height: 34)
                        .background(RoundedRectangle(cornerRadius: 7).fill(on ? buildCyan : buildCyan.opacity(0.14)))
                        .contentShape(Rectangle()).onTapGesture { au?.setRackConfig(c); refresh() }
                }
            }
        }
    }
    // MEMBERSHIP — a compact row: ON BOARD? A · B · C · D. A lit (green) chip = the emitter's board is in the path (its
    // armed treatments apply); a dim chip = BYPASSED (raw wire, RAW in the matrix below). Tap toggles the LIVE config.
    @ViewBuilder private func buildRackMembershipRow(mask: UInt8, chans: [Int]) -> some View {
        let green = Color(red: 0.36, green: 0.92, blue: 0.52)
        let refresh = { self.receivers = self.au?.uiReceivers() ?? self.receivers; self.refreshFromDocument() }
        VStack(alignment: .leading, spacing: 6) {
            Text("ON BOARD").font(.system(size: 9, weight: .heavy, design: .monospaced)).tracking(1).foregroundColor(buildDim)
            HStack(spacing: 8) {
                ForEach(0..<4, id: \.self) { b in
                    let onBoard = (mask & (UInt8(1) << UInt8(b))) != 0
                    let ch = b < chans.count ? chans[b] : b + 1
                    VStack(spacing: 1) {
                        Text(["A", "B", "C", "D"][b]).font(.system(size: 14, weight: .black, design: .monospaced))
                        Text(onBoard ? "ch\(ch)" : "RAW").font(.system(size: 8, weight: .heavy, design: .monospaced))
                    }
                    .foregroundColor(onBoard ? .black : green)
                    .frame(maxWidth: .infinity).frame(height: 40)
                    .background(RoundedRectangle(cornerRadius: 7).fill(onBoard ? green : green.opacity(0.14)))
                    .contentShape(Rectangle()).onTapGesture { au?.setRack(b, !onBoard); refresh() }
                }
            }
        }
    }
    @ViewBuilder private func buildDoorSection(_ i: Int, r: Receiver) -> some View {
        let hue = i < receiverHues.count ? receiverHues[i] : buildCyan
        VStack(alignment: .leading, spacing: 14) {                 // FULL-WIDTH column — LATCH/HOLD/KEYS keep their ORIGINAL width (Paul 2026-08-23)
            buildChannelButtons(i, r)                              // CHANNELS: 1–16 multi-select + ALL + NONE
            HStack(spacing: 14) {
                buildDoorOctave(i)                                 // OCT − / +
                buildDoorRangeRow(i, r)                             // RANGE: Full / a note window → the keyboard picker
            }
            if buildRangeKbdDoor == i { buildRangeKeyboard(i, r) } // the large multi-octave range keyboard (min/max + DONE)
            ZStack(alignment: .topTrailing) {                      // the mode list, with the EXACT main-page strip OVERLAID over LATCH/HOLD/KEYS on the right, below OCT/RANGE (Paul 2026-08-23)
                VStack(alignment: .leading, spacing: 8) {          // the mode list — FULL width, selected mode carries its controls inline
                    ForEach(DoorMode.allCases.filter { $0 != .thru }, id: \.self) { m in buildDoorModeOption(i, m, r: r) }   // THRU retired (Paul 2026-08-31)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                buildReceiverControl(i).frame(width: 96)           // the receiver strip at its OWN width, floating over the radios (not squeezing the column)
                    .padding(6)                                    // ABOVE the mode-row highlight (Paul 2026-08-26): an opaque backing + zIndex so the selected LATCH/HOLD row's cyan tint can't bleed through the strip's gaps
                    .background(RoundedRectangle(cornerRadius: 10).fill(Color(red: 0.10, green: 0.115, blue: 0.145)).allowsHitTesting(false))   // DECORATIVE only — must not swallow taps meant for the mode rows behind it (review fix 2026-08-26)
                    .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.white.opacity(0.08), lineWidth: 1).allowsHitTesting(false))
                    .zIndex(1)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(20)
        .background(RoundedRectangle(cornerRadius: 14).fill(hue.opacity(0.07)))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(hue.opacity(0.3), lineWidth: 1))
    }
    // CHANNELS (multi-channel, Paul 2026-08-21): 1–16 each independently on/off (the door hears the SUBSET). ALL leads
    // row 1 (before CH 1), NONE leads row 2 (before CH 9) — both amber like NONE (a set-the-whole-mask control).
    @ViewBuilder private func buildChannelButtons(_ i: Int, _ r: Receiver) -> some View {
        let mask = r.channelMaskResolved
        let enabled = r.inputEnabledResolved
        let refresh = { self.receivers = self.au?.uiReceivers() ?? self.receivers; self.refreshFromDocument() }
        VStack(alignment: .leading, spacing: 6) {
            Text("CHANNELS").font(.system(size: 9, weight: .heavy, design: .monospaced)).tracking(1).foregroundColor(buildDim)
            ForEach(0..<2, id: \.self) { row in
                HStack(spacing: 4) {
                    if row == 0 {                                   // ALL — left of channel 1
                        buildChanSideButton("ALL", active: enabled && mask == 0xFFFF) { buildRecordUndo("recv"); au?.setReceiverChannelMask(i, 0xFFFF); refresh() }
                    } else {                                        // NONE — left of channel 9
                        buildChanSideButton("NONE", active: !enabled || mask == 0) { buildRecordUndo("recv"); au?.setReceiverChannelMask(i, 0); refresh() }
                    }
                    ForEach(0..<8, id: \.self) { coln in
                        let ch = row * 8 + coln + 1
                        let on = enabled && (mask & (UInt16(1) << UInt16(ch - 1))) != 0
                        Text("\(ch)").font(.system(size: 11, weight: .heavy, design: .monospaced)).foregroundColor(on ? .black : buildCyan.opacity(0.85))
                            .frame(maxWidth: .infinity).frame(height: 30)
                            .background(RoundedRectangle(cornerRadius: 5).fill(on ? buildCyan : buildCyan.opacity(0.13)))
                            .contentShape(Rectangle()).onTapGesture { buildRecordUndo("recv"); au?.toggleReceiverChannel(i, ch); refresh() }
                    }
                }
            }
        }
    }
    // ALL / NONE — the amber whole-mask control (both share NONE's styling).
    @ViewBuilder private func buildChanSideButton(_ label: String, active: Bool, _ tap: @escaping () -> Void) -> some View {
        let amber = Color(red: 0.9, green: 0.4, blue: 0.4)
        Text(label).font(.system(size: 10, weight: .heavy, design: .monospaced)).foregroundColor(active ? .black : amber)
            .frame(width: 54, height: 30).background(RoundedRectangle(cornerRadius: 5).fill(active ? amber : Color.white.opacity(0.08)))
            .contentShape(Rectangle()).onTapGesture(perform: tap)
    }
    // RANGE row: "Range: Full" / "Range: C2–C5" — tap to open the large keyboard picker.
    @ViewBuilder private func buildDoorRangeRow(_ i: Int, _ r: Receiver) -> some View {
        let lo = Int(r.rangeLoResolved), hi = Int(r.rangeHiResolved)
        let full = lo == 0 && hi == 127
        let label = full ? "Range: Full" : "Range: \(midiNoteName(UInt8(lo)))–\(midiNoteName(UInt8(hi)))"
        let open = buildRangeKbdDoor == i
        Text(label).font(.system(size: 12, weight: .heavy, design: .monospaced)).foregroundColor(open ? .black : buildCyan)
            .padding(.horizontal, 12).frame(height: 30)
            .background(RoundedRectangle(cornerRadius: 6).fill(open ? buildCyan : buildPanel))
            .contentShape(Rectangle()).onTapGesture { buildRangeKbdDoor = open ? nil : i; buildRangeSetHi = false }
    }
    // The large RANGE keyboard: pick a MIN then a MAX (the active bound highlights); the range is washed. DONE closes.
    @ViewBuilder private func buildRangeKeyboard(_ i: Int, _ r: Receiver) -> some View {
        let lo = Int(r.rangeLoResolved), hi = Int(r.rangeHiResolved)
        let refresh = { self.receivers = self.au?.uiReceivers() ?? self.receivers; self.refreshFromDocument() }
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Text("SET").font(.system(size: 9, weight: .heavy, design: .monospaced)).foregroundColor(buildDim)
                buildRangeBoundChip("MIN \(midiNoteName(UInt8(lo)))", active: !buildRangeSetHi) { buildRangeSetHi = false }
                buildRangeBoundChip("MAX \(midiNoteName(UInt8(hi)))", active: buildRangeSetHi) { buildRangeSetHi = true }
                Spacer(minLength: 0)
                Text("FULL").font(.system(size: 10, weight: .heavy, design: .monospaced)).foregroundColor(buildDim)
                    .padding(.horizontal, 10).frame(height: 26).background(RoundedRectangle(cornerRadius: 5).fill(Color.white.opacity(0.08)))
                    .contentShape(Rectangle()).onTapGesture { buildRecordUndo("recv"); au?.setReceiverRange(i, lo: 0, hi: 127); refresh() }
                Text("DONE").font(.system(size: 10, weight: .heavy, design: .monospaced)).foregroundColor(.black)
                    .padding(.horizontal, 14).frame(height: 26).background(RoundedRectangle(cornerRadius: 5).fill(buildCyan))
                    .contentShape(Rectangle()).onTapGesture { buildRangeKbdDoor = nil }
            }
            // CR-15[review 17]: derive the keyboard width from the sheet's available width (was hard-coded 660, which
            // ran the top octaves off-screen on a < ~712 pt AUM pane → high MIN/MAX bounds untappable). 76 = the piano's fixed height.
            GeometryReader { g in buildRangePiano(i, lo: lo, hi: hi, width: max(200, g.size.width)) }
                .frame(height: 76)
        }
    }
    @ViewBuilder private func buildRangeBoundChip(_ label: String, active: Bool, _ tap: @escaping () -> Void) -> some View {
        Text(label).font(.system(size: 11, weight: .heavy, design: .monospaced)).foregroundColor(active ? .black : buildCyan)
            .padding(.horizontal, 10).frame(height: 26).background(RoundedRectangle(cornerRadius: 5).fill(active ? buildCyan : buildCyan.opacity(0.14)))
            .contentShape(Rectangle()).onTapGesture(perform: tap)
    }
    // A WIDE keyboard (C1…C7, 6 octaves) for the range picker: notes inside [lo,hi] wash cyan; tapping a key sets the
    // ACTIVE bound (MIN or MAX), auto-ordered so lo ≤ hi. (Paul 2026-08-21)
    @ViewBuilder private func buildRangePiano(_ i: Int, lo: Int, hi: Int, width: CGFloat) -> some View {
        let startOct = 1, octaves = 6
        let base = (startOct + 1) * 12                              // MIDI C1 = 24
        let whiteSemis = [0, 2, 4, 5, 7, 9, 11]
        let blackSemis: [Int?] = [1, 3, nil, 6, 8, 10, nil]
        let whiteCount = octaves * 7
        let gap: CGFloat = 1
        let ww = (width - CGFloat(whiteCount - 1) * gap) / CGFloat(whiteCount)
        let height: CGFloat = 76, bw = ww * 0.62, bh = height * 0.6
        let refresh = { self.receivers = self.au?.uiReceivers() ?? self.receivers; self.refreshFromDocument() }
        func setBound(_ note: Int) {
            buildRecordUndo("recv")   // BUILD UNDO: a range-bound edit
            if buildRangeSetHi { au?.setReceiverRange(i, lo: min(lo, note), hi: note) }
            else { au?.setReceiverRange(i, lo: note, hi: max(hi, note)) }
            refresh(); buildRangeSetHi.toggle()                     // after MIN → set MAX next
        }
        func inRange(_ n: Int) -> Bool { n >= lo && n <= hi }
        return ZStack(alignment: .topLeading) {
            HStack(spacing: gap) {
                ForEach(0..<whiteCount, id: \.self) { wi in
                    let note = base + (wi / 7) * 12 + whiteSemis[wi % 7]
                    RoundedRectangle(cornerRadius: 3).fill(inRange(note) ? buildCyan.opacity(0.55) : Color.white.opacity(0.85))
                        .frame(width: ww, height: height)
                        .overlay(alignment: .bottom) { if wi % 7 == 0 { Text("C\(startOct + wi / 7)").font(.system(size: 7, weight: .heavy, design: .monospaced)).foregroundColor(.black.opacity(0.45)).padding(.bottom, 2) } }
                        .contentShape(Rectangle()).onTapGesture { setBound(note) }
                }
            }
            ForEach(0..<whiteCount, id: \.self) { wi in
                if let bs = blackSemis[wi % 7] {
                    let note = base + (wi / 7) * 12 + bs
                    RoundedRectangle(cornerRadius: 2).fill(inRange(note) ? buildCyan : Color.black)
                        .frame(width: bw, height: bh).overlay(RoundedRectangle(cornerRadius: 2).stroke(Color.white.opacity(0.25), lineWidth: 0.5))
                        .offset(x: CGFloat(wi + 1) * (ww + gap) - bw / 2 - gap / 2, y: 0)
                        .contentShape(Rectangle()).onTapGesture { setBound(note) }
                }
            }
        }.frame(width: width, height: height, alignment: .topLeading)
    }
    // One INPUT MODE row: the radio + description, and — when SELECTED — its own controls INLINE beneath (Paul 2026-08-20).
    // Pick a MIDI-input mode + reconcile the arm/engage state so the modes are mutually exclusive in FACT, not just on the
    // radio (Paul 2026-08-26: "when REPLAY is selected, turn off KEYS/HOLD/LATCH"). Leaving a latch-type mode drops this
    // input's KEYS/HOLD/LATCH arm (else a stale arm makes a not-yet-engaged REPLAY input behave as HOLD); entering one
    // releases any running REPLAY loop, so an input is never both looping and latching.
    private func buildSelectDoorMode(_ i: Int, _ m: DoorMode) {
        buildRecordUndo()   // BUILD UNDO: change an input's mode
        au?.setDoorMode(i, m)
        let bit = UInt8(1 << i)
        switch m {
        case .replay, .file, .thru:
            // These DON'T auto-engage: REPLAY needs an explicit capture-N arm, FILE plays its loaded clip, THRU is passive.
            // Drop any running latch so the door isn't left in a stale armed state from the previous mode.
            if latchMask & bit != 0 { latchMask &= ~bit; au?.setLatchArm(latchMask) }
        case .latch, .hold, .keys, .scale:
            // AUTO-ENGAGE (Paul 2026-08-27): selecting an armable mode ARMS it on the receiver at once — no separate SET tap.
            if replayEngagedMask & bit != 0 { buildToggleReplay(i) }        // release a running loop first
            if latchMask & bit == 0 { latchMask |= bit; au?.setLatchArm(latchMask) }
        }
        receivers = au?.uiReceivers() ?? receivers
        refreshFromDocument()
    }
    @ViewBuilder private func buildDoorModeOption(_ i: Int, _ m: DoorMode, r: Receiver) -> some View {
        let on = r.doorMode == m                              // EXPLICIT choice — nil ⇒ nothing highlighted (the "no mode / SET" state, Paul 2026-08-23)
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 12) {
                Circle().stroke(buildCyan.opacity(0.85), lineWidth: 1.5).frame(width: 17, height: 17)
                    .overlay(Circle().fill(buildCyan).frame(width: 9, height: 9).opacity(on ? 1 : 0)).padding(.top, 1)
                VStack(alignment: .leading, spacing: 2) {
                    Text(m.rawValue.uppercased()).font(.system(size: 13, weight: .heavy, design: .monospaced)).foregroundColor(.white.opacity(on ? 0.98 : 0.55))
                    Text(buildDoorModeCopy(m)).font(.system(size: 11, weight: .regular, design: .monospaced)).foregroundColor(buildDim).fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
            }
            .contentShape(Rectangle())
            .onTapGesture { buildSelectDoorMode(i, m) }
            if on {                                                 // the SELECTED mode's controls, inline (§ "controls next to the item")
                Group {
                    switch m {
                    case .keys:   buildDoorKeyboardInline(i, r)
                    case .scale:  buildDoorScaleInline(i, r)
                    case .latch, .hold: buildDoorLatchInline(i, r)   // §3: the KEY FILTER — restrict this input's pool to a declared key/chord
                    case .replay: buildDoorReplayInline(i, r)
                    case .file:   buildDoorFileInline(i, r)
                    default:      EmptyView()
                    }
                }.padding(.leading, 29)
            }
        }
        .padding(11)
        .background(RoundedRectangle(cornerRadius: 9).fill(on ? buildCyan.opacity(0.1) : Color.clear))
    }
    // REPLAY (inline): the loop-length passes · a "LAST N" catch button (capture+loop / release) · a realtime right→left
    // input roll whose visible window = the N passes selected.
    @ViewBuilder private func buildDoorReplayInline(_ i: Int, _ r: Receiver) -> some View {
        let cur = r.replayPassesResolved
        let engaged = (replayEngagedMask & (1 << UInt8(i))) != 0
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                Text("LOOP").font(.system(size: 10, weight: .heavy, design: .monospaced)).foregroundColor(buildDim)
                ForEach([1, 2, 4, 8], id: \.self) { n in
                    Text("\(n)").font(.system(size: 13, weight: .heavy, design: .monospaced)).foregroundColor(cur == n ? .black : buildCyan)
                        .frame(width: 38, height: 28).background(RoundedRectangle(cornerRadius: 6).fill(cur == n ? buildCyan : buildCyan.opacity(0.14)))
                        .contentShape(Rectangle()).onTapGesture { buildRecvEdit { au?.setReplayPasses(i, n) } }
                }
                Text("passes").font(.system(size: 10, weight: .heavy, design: .monospaced)).foregroundColor(buildDim.opacity(0.7))
                Spacer(minLength: 0)
                // LAST N — capture the last N passes NOW and loop them; press again to release (back to live). Lit while looping.
                Text(engaged ? "LOOPING · TAP TO STOP" : "LAST \(cur)").font(.system(size: 11, weight: .heavy, design: .monospaced))
                    .foregroundColor(engaged ? .black : buildCyan)
                    .padding(.horizontal, 12).frame(height: 28)
                    .background(RoundedRectangle(cornerRadius: 6).fill(engaged ? Color(red: 0.36, green: 0.92, blue: 0.52) : buildCyan.opacity(0.18)))
                    .contentShape(Rectangle()).onTapGesture { buildToggleReplay(i) }
            }
            buildReplayInputRoll(door: i, passes: cur, width: 360, height: 84)
        }
    }
    // THE REPLAY ROLL (Paul 2026-08-23): while ARMED (looping), show the RECORDED LOOP as duration bars — held chords
    // sustain, note lengths are real, and the notes currently SOUNDING are lit — so it reflects exactly what's playing
    // from the recording (live play-along input is NOT drawn). While NOT armed, show the scrolling live-input preview so
    // you can SEE what LAST-N will grab.
    @ViewBuilder private func buildReplayInputRoll(door i: Int, passes: Int, width: CGFloat, height: CGFloat) -> some View {
        let engaged = (replayEngagedMask & (1 << UInt8(i))) != 0
        let loop = i < recvReplayRoll.count ? recvReplayRoll[i] : []
        if engaged && !loop.isEmpty {
            buildReplayLoopRoll(door: i, width: width, height: height)
        } else {
            buildReplayLiveRoll(door: i, passes: passes, width: width, height: height)
        }
    }
    // ARMED: the captured loop as DURATION bars, x = beat within [0, loopLen]. A PLAYHEAD sweeps across in sync with playback
    // and LIGHTS each note as it passes over it (Paul 2026-08-26) — not "every bar of a sounding pitch lights at once". The
    // cursor phase = (currentBeat − loopAnchor) mod loopLen, extrapolated between polls; frozen when stopped.
    @ViewBuilder private func buildReplayLoopRoll(door i: Int, width: CGFloat, height: CGFloat) -> some View {
        let notes = i < recvReplayRoll.count ? recvReplayRoll[i] : []
        let len = max(0.0625, i < recvReplayLen.count ? recvReplayLen[i] : 0)
        let anchor = i < recvReplayAnchor.count ? recvReplayAnchor[i] : 0
        let ns = notes.map { Int($0.note) }
        let rawLo = ns.min() ?? 48, rawHi = ns.max() ?? 72
        let lo = (rawLo / 12) * 12, hi = max(lo + 12, ((rawHi + 11) / 12) * 12)
        let span = CGFloat(max(12, hi - lo))
        let green = Color(red: 0.36, green: 0.92, blue: 0.52)
        let passBeats = max(0.0625, Double(Snap.cols) * stepBeats)
        return RoundedRectangle(cornerRadius: 6).fill(Color.white.opacity(0.04)).frame(width: width, height: height)
            .overlay(
                TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: animationsPaused || !d.playing)) { tl in
                    Canvas { ctx, sz in
                        func xOf(_ beat: Double) -> CGFloat { sz.width * CGFloat(min(len, max(0, beat)) / len) }
                        func yOf(_ note: Int) -> CGFloat { (1 - CGFloat(note - lo) / span) * (sz.height - 6) + 3 }
                        // ONE CLOCK: the current beat, extrapolated from the last poll while playing; frozen when stopped.
                        let cb = d.playing ? meters.beatAnchor + tl.date.timeIntervalSince(meters.beatAnchorAt) * meters.tempo / 60.0 : meters.beatAnchor
                        let phase = d.playing ? (((cb - anchor).truncatingRemainder(dividingBy: len) + len).truncatingRemainder(dividingBy: len)) : -1   // -1 = not playing → no cursor
                        var b = passBeats                                        // PASS boundary lines (each = one grid pass)
                        while b < len - 1e-6 { let x = xOf(b); ctx.stroke(Path { $0.move(to: CGPoint(x: x, y: 0)); $0.addLine(to: CGPoint(x: x, y: sz.height)) }, with: .color(.white.opacity(0.18)), lineWidth: 1); b += passBeats }
                        for n in stride(from: lo, through: hi, by: 12) {         // octave (C) lines
                            let y = yOf(n); ctx.stroke(Path { $0.move(to: CGPoint(x: 0, y: y)); $0.addLine(to: CGPoint(x: sz.width, y: y)) }, with: .color(.white.opacity(0.1)), lineWidth: 0.5)
                        }
                        for nt in notes {                                       // NOTE BARS — real duration; lit ONLY while the playhead is over this bar
                            let x0 = xOf(nt.start), x1 = xOf(nt.end), w = max(2, x1 - x0)
                            let on = phase >= 0 && phase >= nt.start && phase < nt.end
                            let col = on ? green : buildCyan.opacity(0.28 + 0.5 * Double(nt.vel) / 127.0)
                            ctx.fill(Path(roundedRect: CGRect(x: x0, y: yOf(Int(nt.note)) - (on ? 3 : 2.5), width: w, height: on ? 6 : 5), cornerRadius: 2.5), with: .color(col))
                        }
                        if phase >= 0 {                                         // THE PLAYHEAD — a bright cursor sweeping the loop
                            let px = xOf(phase)
                            ctx.fill(Path(CGRect(x: px - 0.75, y: 0, width: 1.5, height: sz.height)), with: .color(green.opacity(0.9)))
                        }
                    }.frame(width: width, height: height)
                }
            )
    }
    // NOT armed: the realtime INPUT ROLL — BEAT-driven (Paul 2026-08-23): notes onset at the RIGHT and drift LEFT by BEAT,
    // not wall-clock, so it FREEZES when the transport stops and stays locked to the passes. The visible window = N+1
    // passes: the N GRABBED passes (highlighted — what LAST-N captures) · plus the CURRENT pass being input. Fed by recvInputRoll.
    @ViewBuilder private func buildReplayLiveRoll(door i: Int, passes: Int, width: CGFloat, height: CGFloat) -> some View {
        let marks = i < recvInputRoll.count ? recvInputRoll[i] : []
        let held = i < recvHeldNotes.count ? recvHeldNotes[i] : []                // CURRENTLY-held input — drawn LIVE at the right edge
        let passBeats = max(0.0625, Double(Snap.cols) * stepBeats)               // one pass in beats
        let windowBeats = Double(passes + 1) * passBeats                         // N grabbed + 1 extra pass (Paul 2026-08-23: N+2 was too wide)
        let ns = marks.map { Int($0.note) } + held.map { Int($0) }
        let rawLo = ns.min() ?? 48, rawHi = ns.max() ?? 72
        let lo = (rawLo / 12) * 12, hi = max(lo + 12, ((rawHi + 11) / 12) * 12)
        let span = CGFloat(max(12, hi - lo))
        return RoundedRectangle(cornerRadius: 6).fill(Color.white.opacity(0.04)).frame(width: width, height: height)
            .overlay(
                TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: animationsPaused || !d.playing)) { tl in
                    Canvas { ctx, sz in
                        // ONE CLOCK: the current beat, extrapolated from the last poll while playing; FROZEN when stopped.
                        let cb = d.playing ? meters.beatAnchor + tl.date.timeIntervalSince(meters.beatAnchorAt) * meters.tempo / 60.0 : meters.beatAnchor
                        func xOf(_ beat: Double) -> CGFloat { sz.width * (1 - CGFloat((cb - beat) / windowBeats)) }
                        func yOf(_ note: Int) -> CGFloat { (1 - CGFloat(note - lo) / span) * (sz.height - 6) + 3 }
                        let passStart = (cb / passBeats).rounded(.down) * passBeats   // start of the CURRENT (incomplete) pass
                        // 1) HIGHLIGHT the N GRABBED passes = the N COMPLETED passes before the current one (what LAST-N takes)
                        let hx0 = max(0, xOf(passStart - Double(passes) * passBeats)), hx1 = min(sz.width, xOf(passStart))
                        if hx1 > hx0 { ctx.fill(Path(roundedRect: CGRect(x: hx0, y: 0, width: hx1 - hx0, height: sz.height), cornerRadius: 3), with: .color(buildCyan.opacity(0.13))) }
                        // 2) CELL + PASS boundary lines (beat-derived, drift with the notes; heavier every Snap.cols = a pass)
                        let cellBeats = passBeats / Double(Snap.cols)
                        var k = Int((cb / cellBeats).rounded(.down))
                        while true {
                            let x = xOf(Double(k) * cellBeats)
                            if x < 0 { break }
                            if x <= sz.width {
                                let onPass = ((k % Snap.cols) + Snap.cols) % Snap.cols == 0
                                ctx.stroke(Path { $0.move(to: CGPoint(x: x, y: 0)); $0.addLine(to: CGPoint(x: x, y: sz.height)) },
                                           with: .color(.white.opacity(onPass ? 0.22 : 0.07)), lineWidth: onPass ? 1 : 0.5)
                            }
                            k -= 1
                        }
                        for n in stride(from: lo, through: hi, by: 12) {         // octave lines (C) — pitch, static
                            let y = yOf(n)
                            ctx.stroke(Path { $0.move(to: CGPoint(x: 0, y: y)); $0.addLine(to: CGPoint(x: sz.width, y: y)) }, with: .color(.white.opacity(0.1)), lineWidth: 0.5)
                        }
                        for m in marks {                                          // the onset marks — placed by their onset BEAT
                            let x = xOf(m.beat)
                            if x < -6 || x > sz.width + 6 { continue }
                            let a = max(0.0, min(1.0, (x + 6) / sz.width))         // dimmer toward the left (older)
                            ctx.fill(Path(roundedRect: CGRect(x: x - 5, y: yOf(Int(m.note)) - 2.5, width: 10, height: 5), cornerRadius: 2.5), with: .color(buildCyan.opacity(0.3 + 0.6 * a)))
                        }
                        for note in held {                                       // CURRENTLY-held notes — a bright bar pinned at the RIGHT edge (live input now)
                            ctx.fill(Path(roundedRect: CGRect(x: sz.width - 13, y: yOf(Int(note)) - 3, width: 12, height: 6), cornerRadius: 3), with: .color(Color(red: 0.36, green: 0.92, blue: 0.52)))
                        }
                    }
                }.frame(width: width, height: height)
            )
    }
    // FILE (inline): load a .mid → it loops into THIS input. Shows the loaded name + REPLACE/REMOVE, or a LOAD button.
    // The clip feeds this MIDI INPUT (like live keys on it) — a machine must READ this input to play it, and (v1) the
    // host transport must be RUNNING for the loop to advance. (Paul 2026-08-27: the copy was misleading — clarified.)
    @ViewBuilder private func buildDoorFileInline(_ i: Int, _ r: Receiver) -> some View {
        let letter = ["A", "B", "C", "D"][i]
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 10) {
                if let name = r.fileName {
                    Image(systemName: "music.note").font(.system(size: 12)).foregroundColor(buildCyan)
                    Text(name).font(.system(size: 11, weight: .heavy, design: .monospaced)).foregroundColor(.white.opacity(0.9)).lineLimit(1).truncationMode(.middle)
                    Spacer(minLength: 0)
                    Text("REPLACE").font(.system(size: 10, weight: .heavy, design: .monospaced)).foregroundColor(buildCyan)
                        .padding(.horizontal, 10).frame(height: 26).background(RoundedRectangle(cornerRadius: 5).fill(buildCyan.opacity(0.16)))
                        .contentShape(Rectangle()).onTapGesture { buildFileImportDoor = i }
                    Text("REMOVE").font(.system(size: 10, weight: .heavy, design: .monospaced)).foregroundColor(buildDim)
                        .padding(.horizontal, 10).frame(height: 26).background(RoundedRectangle(cornerRadius: 5).fill(Color.white.opacity(0.08)))
                        .contentShape(Rectangle()).onTapGesture { au?.clearDoorFile(i); receivers = au?.uiReceivers() ?? receivers; refreshFromDocument() }
                } else {
                    Text("LOAD .MID").font(.system(size: 11, weight: .heavy, design: .monospaced)).foregroundColor(.black)
                        .padding(.horizontal, 14).frame(height: 30).background(RoundedRectangle(cornerRadius: 6).fill(buildCyan))
                        .contentShape(Rectangle()).onTapGesture { buildFileImportDoor = i }
                    Text("loops a .mid into this input").font(.system(size: 10, design: .monospaced)).foregroundColor(buildDim.opacity(0.7))
                    Spacer(minLength: 0)
                }
            }
            // The routing/transport contract — the two things a user must do or they hear nothing (the reported confusion).
            Text(r.fileName != nil
                 ? "▶ The clip feeds MIDI IN \(letter). A machine must READ input \(letter) to play it, and the host transport must be RUNNING."
                 : "The clip becomes this input's notes — point a machine's INPUT at MIDI IN \(letter) to hear it (transport running).")
                .font(.system(size: 9, design: .monospaced)).foregroundColor(r.fileName != nil ? buildCyan.opacity(0.85) : buildDim)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
    // Handle the Files-picker result: read the .mid bytes (security-scoped) and decode onto the picking door.
    private func buildHandleFileImport(_ result: Result<[URL], Error>) {
        let door = buildFileImportDoor; buildFileImportDoor = nil
        guard let door, case .success(let urls) = result, let url = urls.first else { return }
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        guard let data = try? Data(contentsOf: url) else { buildFlashPromote("COULDN'T READ THE FILE"); return }
        if au?.setDoorFile(door, data: data, name: url.lastPathComponent) == true {
            receivers = au?.uiReceivers() ?? receivers; refreshFromDocument()
            buildFlashPromote("LOADED \(url.lastPathComponent)")
        } else {
            buildFlashPromote("NOT A READABLE MIDI FILE")
        }
    }
    // KEYS (inline): the fresh multi-octave piano + CLEAR. (buildKeyboard is NOT reused — it's broken from a prior context.)
    @ViewBuilder private func buildDoorKeyboardInline(_ i: Int, _ r: Receiver) -> some View {
        let kbW: CGFloat = 520
        VStack(alignment: .leading, spacing: 8) {
            buildInputPiano(receiver: i, held: Set(r.pianoNotesResolved), width: kbW, height: 128)
            HStack {
                Text("\(r.pianoNotesResolved.count) note\(r.pianoNotesResolved.count == 1 ? "" : "s") picked").font(.system(size: 10, weight: .heavy, design: .monospaced)).foregroundColor(buildDim)
                Spacer()
                Text("CLEAR").font(.system(size: 10, weight: .heavy, design: .monospaced)).foregroundColor(buildDim)
                    .padding(.horizontal, 10).padding(.vertical, 4).background(RoundedRectangle(cornerRadius: 5).fill(Color.white.opacity(0.08)))
                    .contentShape(Rectangle()).onTapGesture { buildRecvEdit { au?.clearReceiverPianoNotes(i) } }
            }.frame(width: kbW)
            buildDoorExcludeRow(i, width: kbW)
        }
    }
    // LATCH/HOLD inline (ratified §3): just the KEY FILTER — restrict this latched input to a declared key/chord (ONLY:B),
    // BLOCK the out-of-key or SNAP it to the nearest legal note. The "always-right lead" when B is a SCALE key-door.
    @ViewBuilder private func buildDoorLatchInline(_ i: Int, _ r: Receiver) -> some View {
        buildDoorExcludeRow(i, width: 520)
    }
    // KEYS/SCALE EXCLUDE (Paul 2026-08-22): the complement — this input plays its pool MINUS another MIDI input's live chord.
    // Shared by the KEYS keyboard and the SCALE picker (SCALE + EXCLUDE = the ratified diatonic-complement combo, §3). Labelled
    // as a MIDI INPUT (not a "door"), the user-facing term (Paul 2026-08-26).
    @ViewBuilder private func buildDoorExcludeRow(_ i: Int, width: CGFloat) -> some View {
        let r = i < receivers.count ? receivers[i] : Receiver()
        let exSel = r.excludeDoorResolved
        let only = r.excludeModeResolved == .only, snap = r.excludeRejectResolved == .snap
        let on = exSel >= 0
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Text(only ? "ONLY MIDI IN" : "EXCLUDE MIDI IN").font(.system(size: 10, weight: .heavy, design: .monospaced)).foregroundColor(buildDim).frame(width: 118, alignment: .leading)
                ForEach([-1, 0, 1, 2, 3].filter { $0 != i }, id: \.self) { d in
                    Text(d < 0 ? "NONE" : "IN \(["A", "B", "C", "D"][d])").font(.system(size: 10, weight: .heavy, design: .monospaced))
                        .foregroundColor(exSel == d ? .black : .white.opacity(0.7))
                        .padding(.horizontal, 9).padding(.vertical, 4)
                        .background(RoundedRectangle(cornerRadius: 5).fill(exSel == d ? buildCyan : Color.white.opacity(0.08)))
                        .contentShape(Rectangle()).onTapGesture { buildRecvEdit { au?.setExcludeDoor(i, d) } }
                }
            }
            if on {                                                   // §3: MODE = subtract vs intersect · REJECT = what happens to a note that doesn't pass. Labelled + plain-worded (Paul 2026-08-27).
                HStack(spacing: 8) {
                    Text("MODE").font(.system(size: 9, weight: .heavy, design: .monospaced)).foregroundColor(buildDim).frame(width: 64, alignment: .leading)
                    buildDoorSeg2("MINUS · remove these", "ONLY · keep only these", first: !only,
                                  a: { au?.setReceiverExcludeMode(i, .minus) }, b: { au?.setReceiverExcludeMode(i, .only) })
                    Spacer(minLength: 0)
                }
                HStack(spacing: 8) {
                    Text("REJECTED").font(.system(size: 9, weight: .heavy, design: .monospaced)).foregroundColor(buildDim).frame(width: 64, alignment: .leading)
                    buildDoorSeg2("BLOCK · silence it", "SNAP · nudge to nearest", first: !snap,
                                  a: { au?.setReceiverExcludeReject(i, .block) }, b: { au?.setReceiverExcludeReject(i, .snap) })
                    Spacer(minLength: 0)
                }
            }
            Text(buildExcludeCopy(on: on, only: only, snap: snap)).font(.system(size: 9, design: .monospaced)).foregroundColor(buildDim).fixedSize(horizontal: false, vertical: true)
        }.frame(width: width, alignment: .leading)
    }
    // A 2-option segmented toggle for the key-filter axes; taps re-poll the receivers.
    @ViewBuilder private func buildDoorSeg2(_ optA: String, _ optB: String, first: Bool, a: @escaping () -> Void, b: @escaping () -> Void) -> some View {
        HStack(spacing: 0) {
            ForEach([(optA, true), (optB, false)], id: \.0) { (label, isA) in
                let sel = isA == first
                Text(label).font(.system(size: 10, weight: .heavy, design: .monospaced)).foregroundColor(sel ? .black : .white.opacity(0.7))
                    .padding(.horizontal, 11).frame(height: 26).background(sel ? buildCyan : Color.white.opacity(0.08))
                    .contentShape(Rectangle()).onTapGesture { buildRecvEdit { (isA ? a : b)() } }
            }
        }.clipShape(RoundedRectangle(cornerRadius: 5))
    }
    private func buildExcludeCopy(on: Bool, only: Bool, snap: Bool) -> String {
        guard on else { return "Filter this input's pool against another MIDI input — the complement (MINUS) or the key/chord lock (ONLY)." }
        switch (only, snap) {
        case (false, false): return "Plays this pool MINUS the excluded input's notes (any octave) — the flourish layer."
        case (false, true):  return "MINUS the excluded notes; a landed-on note nudges to the nearest note that ISN'T excluded."
        case (true, false):  return "Plays ONLY notes also in the referenced input (any octave) — out-of-key notes are silent."
        case (true, true):   return "Snaps every note to the nearest note in the referenced input — always in key, never a wrong note."
        }
    }
    // THE SCALE PICKER (ratified §1): ROOT (C–B) · SCALE (curated list) · the home-octave window (base octave + span). The
    // derived pool feeds the KEYS pipeline (self-arm · EXCLUDE · play-along all reused) — no keyboard, no typing.
    @ViewBuilder private func buildDoorScaleInline(_ i: Int, _ r: Receiver) -> some View {
        let w: CGFloat = 520
        let names = ["C", "C#", "D", "D#", "E", "F", "F#", "G", "G#", "A", "A#", "B"]
        let root = r.scaleRootResolved, type = r.scaleTypeResolved
        let pool = scaleNotes(root: root, type: type, baseOct: r.scaleBaseOctResolved, octaves: r.scaleOctavesResolved)
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 5) {                                       // ROOT — 12 chips
                Text("ROOT").font(.system(size: 10, weight: .heavy, design: .monospaced)).foregroundColor(buildDim).frame(width: 40, alignment: .leading)
                ForEach(0..<12, id: \.self) { k in
                    Text(names[k]).font(.system(size: 11, weight: .heavy, design: .monospaced)).foregroundColor(root == k ? .black : .white.opacity(0.7))
                        .frame(width: 34, height: 26).background(RoundedRectangle(cornerRadius: 5).fill(root == k ? buildCyan : Color.white.opacity(0.08)))
                        .contentShape(Rectangle()).onTapGesture { buildRecvEdit { au?.setReceiverScaleRoot(i, k) } }
                }
            }
            HStack(alignment: .top, spacing: 5) {                      // SCALE — the curated list, wrapping into an adaptive grid
                Text("SCALE").font(.system(size: 10, weight: .heavy, design: .monospaced)).foregroundColor(buildDim).frame(width: 40, alignment: .leading).padding(.top, 4)
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 5), count: 5), spacing: 5) {
                    ForEach(ScaleType.allCases, id: \.self) { st in
                        Text(st.label).font(.system(size: 10, weight: .heavy, design: .monospaced)).foregroundColor(type == st ? .black : .white.opacity(0.75)).lineLimit(1).minimumScaleFactor(0.7)
                            .frame(maxWidth: .infinity).frame(height: 26).background(RoundedRectangle(cornerRadius: 5).fill(type == st ? buildCyan : Color.white.opacity(0.08)))
                            .contentShape(Rectangle()).onTapGesture { buildRecvEdit { au?.setReceiverScaleType(i, st) } }
                    }
                }.frame(width: w - 46)
            }
            HStack(spacing: 10) {                                      // RANGE — base octave + how many octaves
                Text("RANGE").font(.system(size: 10, weight: .heavy, design: .monospaced)).foregroundColor(buildDim).frame(width: 40, alignment: .leading)
                buildScaleStepper("OCT", value: r.scaleBaseOctResolved, lo: 0, hi: 8) { v in buildRecvEdit { au?.setReceiverScaleBaseOct(i, v) } }
                buildScaleStepper("× OCT", value: r.scaleOctavesResolved, lo: 1, hi: 4) { v in buildRecvEdit { au?.setReceiverScaleOctaves(i, v) } }
                Spacer(minLength: 0)
                Text("\(pool.count) notes · \(names[root]) \(type.label)").font(.system(size: 10, weight: .heavy, design: .monospaced)).foregroundColor(buildCyan.opacity(0.85)).lineLimit(1).minimumScaleFactor(0.7)
            }
            buildDoorExcludeRow(i, width: w)                           // SCALE + EXCLUDE = the diatonic complement (ratified §3)
        }.frame(width: w, alignment: .leading)
    }
    // A tiny ◀ value ▶ stepper for the scale RANGE (clamped [lo,hi]).
    @ViewBuilder private func buildScaleStepper(_ label: String, value: Int, lo: Int, hi: Int, _ set: @escaping (Int) -> Void) -> some View {
        HStack(spacing: 4) {
            Text(label).font(.system(size: 9, weight: .heavy, design: .monospaced)).foregroundColor(buildDim)
            Image(systemName: "chevron.left").font(.system(size: 11, weight: .heavy)).foregroundColor(value > lo ? buildCyan : buildDim)
                .frame(width: 26, height: 26).background(RoundedRectangle(cornerRadius: 5).fill(Color.white.opacity(0.08)))
                .contentShape(Rectangle()).onTapGesture { if value > lo { set(value - 1) } }
            Text("\(value)").font(.system(size: 12, weight: .heavy, design: .monospaced)).foregroundColor(.white).frame(minWidth: 16)
            Image(systemName: "chevron.right").font(.system(size: 11, weight: .heavy)).foregroundColor(value < hi ? buildCyan : buildDim)
                .frame(width: 26, height: 26).background(RoundedRectangle(cornerRadius: 5).fill(Color.white.opacity(0.08)))
                .contentShape(Rectangle()).onTapGesture { if value < hi { set(value + 1) } }
        }
    }
    // A BRAND-NEW multi-octave piano (C2…B4, 3 octaves): white keys in a row, black keys overlaid; tap = pick/unpick a
    // note into the door's held set. Built fresh (buildKeyboard was broken by an earlier reuse). (Paul 2026-08-20)
    @ViewBuilder private func buildInputPiano(receiver i: Int, held: Set<Int>, width: CGFloat, height: CGFloat = 100) -> some View {
        let startOct = 2, octaves = 3
        let base = (startOct + 1) * 12                              // MIDI C2 = 36
        let whiteSemis = [0, 2, 4, 5, 7, 9, 11]
        let blackSemis: [Int?] = [1, 3, nil, 6, 8, 10, nil]        // the black key to the RIGHT of each white (nil = none)
        let whiteCount = octaves * 7
        let gap: CGFloat = 1
        let ww = (width - CGFloat(whiteCount - 1) * gap) / CGFloat(whiteCount)
        let bw = ww * 0.64, bh = height * 0.6
        func pick(_ note: Int) { buildRecvEdit { au?.toggleReceiverPianoNote(i, note) } }
        return ZStack(alignment: .topLeading) {
            HStack(spacing: gap) {                                  // WHITE keys
                ForEach(0..<whiteCount, id: \.self) { wi in
                    let note = base + (wi / 7) * 12 + whiteSemis[wi % 7]
                    RoundedRectangle(cornerRadius: 3).fill(held.contains(note) ? buildCyan : Color.white.opacity(0.85))
                        .frame(width: ww, height: height)
                        .overlay(alignment: .bottom) { if wi % 7 == 0 { Text("C\(startOct + wi / 7)").font(.system(size: 8, weight: .heavy, design: .monospaced)).foregroundColor(.black.opacity(0.45)).padding(.bottom, 2) } }
                        .contentShape(Rectangle()).onTapGesture { pick(note) }
                }
            }
            // BLACK keys — LAYOUT-positioned (per-white-slot HStack, key pinned trailing + straddling the boundary via a
            // negative trailing inset). NOT `.offset` — that shifts only the render and leaves the hit frame at x=0, which
            // is why black-key taps missed (Paul 2026-08-25). Padding is layout, so the hit frame moves with the key.
            HStack(spacing: gap) {
                ForEach(0..<whiteCount, id: \.self) { wi in
                    Color.clear.frame(width: ww, height: height)
                        .overlay(alignment: .trailing) {
                            if let bs = blackSemis[wi % 7] {
                                let note = base + (wi / 7) * 12 + bs
                                RoundedRectangle(cornerRadius: 2).fill(held.contains(note) ? buildCyan : Color.black)
                                    .frame(width: bw, height: bh)
                                    .overlay(RoundedRectangle(cornerRadius: 2).stroke(Color.white.opacity(0.25), lineWidth: 0.5))
                                    .contentShape(Rectangle())
                                    .onTapGesture { pick(note) }
                                    .padding(.trailing, -(bw / 2 + gap / 2))   // straddle the white-key boundary (still layout ⇒ honest hit frame)
                            }
                        }
                }
            }
        }.frame(width: width, height: height, alignment: .topLeading)
    }
    @ViewBuilder private func buildDoorOctave(_ i: Int) -> some View {
        let oct = i < receiverOctave.count ? receiverOctave[i] : 0
        HStack(spacing: 4) {                                        // hug the content — the OCT ± keys are narrow, not full-width
            Text("OCT").font(.system(size: 9, weight: .heavy, design: .monospaced)).foregroundColor(buildDim)
            buildOctBtn("−") { nudgeReceiverOctave(i, -1) }.frame(width: 40)
            Text(oct > 0 ? "+\(oct)" : "\(oct)").font(.system(size: 12, weight: .heavy, design: .monospaced)).foregroundColor(buildCyan).frame(minWidth: 24)
            buildOctBtn("+") { nudgeReceiverOctave(i, +1) }.frame(width: 40)
        }.fixedSize()
    }
    // THE HEADER CONTROLS (Paul 2026-08-23): RATE (per-part) · MIDI IN · MIDI OUT · RACK — wide/prominent menu buttons —
    // then RECORD (reel) at the far RIGHT (top-right corner). Rendered IN the top header bar (ArrangementBar), rightmost.
    // Internal so the VC's `arrangementBar` var can embed it.
    @ViewBuilder func buildHeaderControls() -> some View {
        HStack(alignment: .center, spacing: 8) {
            if !reelShowPopup {
                buildRateControl()                              // the per-part rate
                buildStepsControl()                             // §E: the per-part STEP count (8 | 16)
                buildConfigButton("MIDI IN")  { buildMidiConfigOpen = true }    // the MIDI-IN doors sheet
                buildConfigButton("MIDI OUT") { buildMidiOutConfigOpen = true } // the emitter stamp-channels sheet
                buildConfigButton("RACK")     { buildRackConfigOpen = true }    // the rack / OUTPUT CHAIN sheet (config-sheets §6)
                buildConfigButton("ROW 8")    { buildRow8EditSlot = max(0, buildRow8EditSlot); buildRow8EditOpen = true }   // the ROW 8 action-cell authoring page (Paul 2026-08-24: edit lives in the header, after RACK)
            }
            buildReelButton()                                   // RECORD — top-right (Paul 2026-08-23); handles the pass-browser hide + share anchor
        }
    }
    // The global STOP — stops every playing voice (chain audition · part · every play column). Lives in the SELECT grid's
    // top-right EMPTY corner cell (Paul 2026-08-31). Cell-sized; red + lit when anything plays.
    @ViewBuilder func buildStopAllButton() -> some View {
        let anyPlaying = buildDisplayVoice != .none || buildPlayColOn.contains(true)
        Image(systemName: "stop.fill").font(.system(size: 15, weight: .black))
            .foregroundColor(roomsDoorInk(to: .play))                                             // white ink — like the nav buttons (Paul 2026-08-31)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(RoundedRectangle(cornerRadius: 5).fill(anyPlaying ? roomsIndigo : roomsIndigo.opacity(0.35)))   // PLAY-GRID indigo (dimmer when idle)
            .contentShape(Rectangle()).onTapGesture { buildStopAllOnTransportStop() }
    }
    @ViewBuilder private func buildConfigButton(_ label: String, _ action: @escaping () -> Void) -> some View {
        Text(label).font(.system(size: 11, weight: .heavy, design: .monospaced)).tracking(0.5)
            .foregroundColor(buildCyan).lineLimit(1).minimumScaleFactor(0.8)
            .frame(width: 84, height: 30)                                   // wide/prominent header menu button (Paul 2026-08-23)
            .background(RoundedRectangle(cornerRadius: 6).fill(buildPanel))
            .overlay(RoundedRectangle(cornerRadius: 6).stroke(buildCyan.opacity(0.4), lineWidth: 1))
            .contentShape(Rectangle()).onTapGesture(perform: action)
    }
    @ViewBuilder private func buildReelButton() -> some View {
        if reelShowPopup {
            Color.clear.frame(width: 1, height: 1)                            // HIDDEN while the pass browser is open (Paul 2026-08-19)
                .sheet(isPresented: $reelShowShare) { ReelShareSheet(urls: reelShareURLs) }   // keep the share-sheet anchor alive
        } else {
            let recording = d.playing && reelState != 2                       // the tape captures live output while playing
            let c: Color = recording ? Color(red: 0.95, green: 0.24, blue: 0.24) : buildDim   // RED while recording (stays red), dim stopped
            // ANIMATED while recording (Paul 2026-08-20): the whole tape glyph BREATHES (scale + a soft red glow) and the
            // record dot pulses — so "it's recording" reads at a glance. Static + dim when stopped.
            TimelineView(.animation(minimumInterval: 1.0 / 24.0, paused: !recording)) { tl in
                let t = tl.date.timeIntervalSinceReferenceDate
                let p = recording ? abs(sin(t * 2.4)) : 0.0                    // 0…1 breathing
                ZStack(alignment: .topTrailing) {
                    Image(systemName: "recordingtape").font(.system(size: 22, weight: .regular)).foregroundColor(c)   // header scale (Paul 2026-08-23)
                        .scaleEffect(1.0 + 0.07 * p)
                        .shadow(color: Color(red: 0.98, green: 0.2, blue: 0.2).opacity(recording ? 0.35 + 0.4 * p : 0), radius: 5)
                    if recording {
                        Circle().fill(Color(red: 0.98, green: 0.2, blue: 0.2))
                            .frame(width: 7, height: 7).opacity(0.7 + 0.3 * p).offset(x: 3, y: -1)
                    }
                }
            }
            .contentShape(Rectangle())                                        // no padding — flush-left in the box (Paul 2026-08-20)
            .onTapGesture { reelShowPopup = true }                            // tap = open the pass browser
            .sheet(isPresented: $reelShowShare) { ReelShareSheet(urls: reelShareURLs) }
        }
    }

    // PER-PART CLOCK (Paul 2026-08-19): the CURRENT part's step RATE — a compact PILL FLOATING at the part grid's top-
    // right edge (not a grid cell). A part deployed at a different rate plays at a DIFFERENT TEMPO. "—" = scene default.
    // (LENGTH dropped from here — it's now driven by the staging LOOP KEYS on promote. Paul 2026-08-19.)
    @ViewBuilder private func buildRateControl() -> some View {
        Menu {
            Button { buildSetPartRate(nil) } label: { Label("DEFAULT (scene rate)", systemImage: buildPartRate == nil ? "checkmark" : "circle") }
            ForEach(StepRate.allCases, id: \.self) { r in
                Button { buildSetPartRate(r) } label: { Label(r.rawValue, systemImage: buildPartRate == r ? "checkmark" : "circle") }
            }
        } label: {
            let effRate = buildPartRate ?? StepRate.allCases[min(stepIndex, StepRate.allCases.count - 1)]   // the ACTUAL rate — the part override, else the scene default
            HStack(spacing: 4) {                                              // MATCH the header clock chip's format (Paul 2026-08-23)
                Image(systemName: "timer").font(.system(size: 10, weight: .semibold))
                Text(effRate.rawValue).font(.system(size: 10, weight: .heavy, design: .monospaced))
            }
            .foregroundColor(buildCyan)
            .padding(.horizontal, 8).frame(height: 26)
            .background(RoundedRectangle(cornerRadius: 5).fill(Color.white.opacity(0.08)))
            .contentShape(Rectangle())
        }
    }
    func buildSetPartRate(_ r: StepRate?) {
        buildPartRate = r
        if buildCurrentPart >= 0, buildCurrentPart < buildParts.count { buildParts[buildCurrentPart].rate = r }   // keep buildParts authoritative for performRate mapping
        buildPublishScene()
    }
    // §E 16-STEP (Paul 2026-09-02): the CURRENT part's STEP COUNT (its active width = loop length). nil ⇒ the 8-wide
    // default (byte-identical); 16 ⇒ the part grid renders + loops 16 columns. A compact 8|16 menu beside the rate pill.
    @ViewBuilder private func buildStepsControl() -> some View {
        Menu {
            Button { buildSetPartLen(nil) } label: { Label("8 STEPS", systemImage: buildPartCols <= 8 ? "checkmark" : "circle") }
            Button { buildSetPartLen(16) }  label: { Label("16 STEPS", systemImage: buildPartCols == 16 ? "checkmark" : "circle") }
        } label: {
            HStack(spacing: 4) {
                Image(systemName: "rectangle.split.2x1").font(.system(size: 10, weight: .semibold))
                Text("\(buildPartCols) STEP").font(.system(size: 10, weight: .heavy, design: .monospaced))
            }
            .foregroundColor(buildCyan)
            .padding(.horizontal, 8).frame(height: 26)
            .background(RoundedRectangle(cornerRadius: 5).fill(Color.white.opacity(0.08)))
            .contentShape(Rectangle())
        }
    }
    func buildSetPartLen(_ n: Int?) {
        buildPartLen = n
        if buildCurrentPart >= 0, buildCurrentPart < buildParts.count { buildParts[buildCurrentPart].length = n }   // keep buildParts authoritative for performLen mapping
        buildStagingSel = BuildSceneLogic.reconcileStagingSel(buildStagingSel, cells: buildStagingCells)            // keep the selection valid across the new width
        buildPublishScene()
    }

    // THE PASS BROWSER (Paul 2026-08-19): an 8×8 grid — TOP 4 rows = the last 32 passes (newest bottom-right), tap one to
    // replay it live; BOTTOM 4 rows = the selected pass drawn as A/B/C/D piano-roll lanes. SAVE exports the selected pass.
    private var reelLaneHues: [Color] { [Color(red: 0.19, green: 0.83, blue: 0.91),   // A cyan
                                         Color(red: 0.36, green: 0.92, blue: 0.52),   // B green
                                         Color(red: 1.0,  green: 0.72, blue: 0.2),    // C amber
                                         Color(red: 0.85, green: 0.5,  blue: 0.95)] } // D violet
    // THE PASS BROWSER (Paul 2026-08-26 redesign): the whole thing reads as ONE 8×8 grid — the recorded PASSES fill the
    // top 4 rows (uniform SQUARE cells), the four A/B/C/D MIDI lanes fill the bottom 4 rows (each the full grid width, one
    // cell tall). The page header + instructions + controls live in a COLUMN on the RIGHT (was a banner above). PREV/NEXT
    // PAGINATE the pass block; REMOVE DUPLICATES collapses runs of identical passes.
    private func buildReelPopup(size: CGSize) -> some View {
        let outerPad: CGFloat = 16, gap: CGFloat = 3, sidebarW: CGFloat = 234, colGap: CGFloat = 18
        let areaW = size.width - 2 * outerPad - sidebarW - colGap
        let areaH = size.height - 2 * outerPad
        let cellSize = max(14, min((areaW - 7 * gap) / 8, (areaH - 7 * gap) / 8))   // one SQUARE cell → a uniform 8×8
        let gridSide = 8 * cellSize + 7 * gap
        let visible = buildReelVisiblePasses()                                   // non-empty (+ deduped if toggled), in ring order
        let pageCount = max(1, (visible.count + 31) / 32)
        let page = min(max(0, reelPage), pageCount - 1)
        let pageSlice = Array(visible.dropFirst(page * 32).prefix(32))           // this page's ≤32 passes → the 4×8 block
        return ZStack {
            Color(red: 0.055, green: 0.065, blue: 0.085).ignoresSafeArea()      // FULL-SCREEN opaque backdrop
            if size.width <= size.height {                                      // PORTRAIT — the pass browser is a LANDSCAPE-ONLY view; prompt to rotate rather than cram the landscape block into a tall window
                buildReelRotatePrompt()
            } else {
                HStack(alignment: .top, spacing: colGap) {
                    VStack(spacing: gap) {                                      // LEFT — the 8×8 grid
                        ForEach(0..<4, id: \.self) { r in                      // TOP 4 rows — the passes (this page)
                            HStack(spacing: gap) {
                                ForEach(0..<8, id: \.self) { c in
                                    let idx = r * 8 + c
                                    buildReelPassCell(idx < pageSlice.count ? pageSlice[idx] : -1, w: cellSize, h: cellSize)
                                }
                            }
                        }
                        buildReelRollSection(width: gridSide, laneH: cellSize, gap: gap)   // BOTTOM 4 rows — A/B/C/D lanes + playhead
                    }.frame(width: gridSide, height: gridSide)
                    buildReelSidebar(pageCount: pageCount, page: page)          // RIGHT — header · instructions · controls
                        .frame(width: sidebarW, height: gridSide, alignment: .top)
                }
            }
        }
        .onAppear {
            au?.reelSetBrowsing(true)                                             // freeze the history tape while browsing
            reelPage = Int.max                                                    // OPEN ON THE NEWEST PAGE (clamped to the last page) — Paul 2026-08-26
            reelSelLoPass = -1; reelSelHiPass = -1; reelRangeCyc = 0              // fresh selection (the anchor = the auto-latest pass)
            reelExportLanes = []                                                  // start exporting the master mix
        }
        .onDisappear { au?.reelStopReplay(); au?.reelSetBrowsing(false) }         // close → stop any replay + resume normal play, record again next pass
    }
    // PORTRAIT fallback (Paul 2026-08-26): the pass browser is a landscape-only view; in a tall window, prompt to rotate.
    @ViewBuilder private func buildReelRotatePrompt() -> some View {
        VStack(spacing: 16) {
            Image(systemName: "arrow.clockwise").font(.system(size: 40, weight: .light)).foregroundColor(buildCyan)
            Text("ROTATE TO LANDSCAPE").font(.system(size: 15, weight: .heavy, design: .monospaced)).tracking(2).foregroundColor(.white.opacity(0.85))
            Text("The pass browser is a landscape view.").font(.system(size: 12, weight: .medium)).foregroundColor(.white.opacity(0.5))
            Button { reelShowPopup = false } label: {
                Text("CLOSE").font(.system(size: 11, weight: .heavy, design: .monospaced)).tracking(1).foregroundColor(buildDim)
                    .padding(.horizontal, 24).padding(.vertical, 10)
                    .background(RoundedRectangle(cornerRadius: 6).fill(buildCell)).overlay(RoundedRectangle(cornerRadius: 6).stroke(buildEdge, lineWidth: 1))
            }.padding(.top, 6)
        }.padding(40)
    }
    // The passes to show: non-empty, in ring order; when REMOVE DUPLICATES is on, a pass whose content matches the last
    // KEPT pass is hidden (collapses a run — e.g. a held loop filing the same bar every pass). (Paul 2026-08-26)
    private func buildReelVisiblePasses() -> [Int] {
        var out: [Int] = []
        var lastSig: UInt64? = nil
        for (i, p) in reelPassNumbers.enumerated() where p >= 0 {
            let s = i < reelPassSigs.count ? reelPassSigs[i] : 0
            if reelDedup, s == lastSig { continue }                            // duplicate of the last kept → hide
            out.append(p); lastSig = s
        }
        return out
    }
    // The RIGHT sidebar — title + a plain-language instruction + PAGINATION + REMOVE DUPLICATES + RESTORE SETUP (#5) + SAVE.
    @ViewBuilder private func buildReelSidebar(pageCount: Int, page: Int) -> some View {
        let anyPass = reelPassNumbers.contains { $0 >= 0 }
        let hasState = reelSelPassNo >= 0 && reelStateRing[reelSelPassNo] != nil
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 2) {
                Text("REEL").font(.system(size: 24, weight: .heavy, design: .monospaced)).tracking(3).foregroundColor(buildCyan)
                Text("PASS BROWSER").font(.system(size: 11, weight: .bold, design: .monospaced)).tracking(2).foregroundColor(buildDim)
            }
            Text("Tap a pass to hear it. PAGE steps through the whole history; EXTEND grows the selection across passes (the roll and SAVE cover the range). Tap a lane to export just that emitter (none = the master mix).")
                .font(.system(size: 11, weight: .medium)).foregroundColor(.white.opacity(0.55)).fixedSize(horizontal: false, vertical: true)
            Rectangle().fill(buildEdge).frame(height: 1)
            let visible = buildReelVisiblePasses()
            let (rlo, rhi) = buildReelExportRange()
            let selLabel = rlo < 0 ? "—" : (rlo == rhi ? "PASS \(rlo + 1)" : "PASSES \(rlo + 1)–\(rhi + 1)")
            let laneLabel = reelExportLanes.isEmpty ? "MASTER" : reelExportLanes.sorted().map { ["A", "B", "C", "D"][$0] }.joined(separator: "·")
            // PAGINATION — page the whole history (32 passes at a time), independent of the selection (Paul 2026-08-26).
            HStack(spacing: 8) {
                buildReelStepBtn(back: true, enabled: page > 0) { reelPage = max(0, page - 1) }
                VStack(spacing: 1) {
                    Text("PAGE").font(.system(size: 8, weight: .heavy, design: .monospaced)).tracking(1).foregroundColor(buildDim)
                    Text("\(page + 1)/\(pageCount)").font(.system(size: 11, weight: .heavy, design: .monospaced)).foregroundColor(.white.opacity(0.8))
                }.frame(maxWidth: .infinity)
                buildReelStepBtn(back: false, enabled: page < pageCount - 1) { reelPage = min(pageCount - 1, page + 1) }
            }
            // EXTEND — grow the SELECTION to the neighbouring recorded pass; the page follows so the new edge stays visible.
            HStack(spacing: 8) {
                buildReelStepBtn(back: true, enabled: rlo >= 0 && visible.contains { $0 < rlo }) { buildReelExtend(-1) }
                VStack(spacing: 1) {
                    Text("EXTEND").font(.system(size: 8, weight: .heavy, design: .monospaced)).tracking(1).foregroundColor(buildDim)
                    Text(selLabel).font(.system(size: 10, weight: .heavy, design: .monospaced)).foregroundColor(buildCyan).lineLimit(1).minimumScaleFactor(0.7)
                }.frame(maxWidth: .infinity)
                buildReelStepBtn(back: false, enabled: rhi >= 0 && visible.contains { $0 > rhi }) { buildReelExtend(1) }
            }
            buildReelToggle(label: "REMOVE DUPLICATES", on: reelDedup) { reelDedup.toggle(); reelPage = Int.max }
            Button { buildReelRestoreState() } label: {                        // #5 — restore the setup live during the pass + CLOSE the reel
                Text(hasState ? "RESTORE SETUP · PASS \(reelSelPassNo + 1)" : "RESTORE SETUP")
                    .font(.system(size: 10.5, weight: .heavy, design: .monospaced)).tracking(0.5).lineLimit(1).minimumScaleFactor(0.7)
                    .foregroundColor(hasState ? .black : buildDim).frame(maxWidth: .infinity).padding(.vertical, 9)
                    .background(RoundedRectangle(cornerRadius: 6).fill(hasState ? Color(red: 0.85, green: 0.5, blue: 0.95).opacity(0.9) : buildCell))
                    .overlay(hasState ? nil : RoundedRectangle(cornerRadius: 6).stroke(buildEdge, lineWidth: 1))
            }.disabled(!hasState)
            Spacer()
            Button { buildReelExport() } label: {                             // SAVE the pass RANGE × the emitter selection → share sheet
                Text(rlo >= 0 ? "SAVE \(selLabel) · \(laneLabel)" : "SAVE").font(.system(size: 10.5, weight: .heavy, design: .monospaced)).tracking(0.5).lineLimit(1).minimumScaleFactor(0.7)
                    .foregroundColor(rlo >= 0 || anyPass ? .black : buildDim).frame(maxWidth: .infinity).padding(.vertical, 10)
                    .background(RoundedRectangle(cornerRadius: 6).fill(buildCyan.opacity(0.9)))
            }
            Button { reelShowPopup = false } label: {
                Text("CLOSE").font(.system(size: 11, weight: .heavy, design: .monospaced)).tracking(1).foregroundColor(buildDim)
                    .frame(maxWidth: .infinity).padding(.vertical, 10)
                    .background(RoundedRectangle(cornerRadius: 6).fill(buildCell)).overlay(RoundedRectangle(cornerRadius: 6).stroke(buildEdge, lineWidth: 1))
            }
        }
    }
    private func buildReelToggle(label: String, on: Bool, _ act: @escaping () -> Void) -> some View {
        Button(action: act) {
            HStack(spacing: 8) {
                Image(systemName: on ? "checkmark.square.fill" : "square").font(.system(size: 14, weight: .bold)).foregroundColor(on ? buildCyan : buildDim)
                Text(label).font(.system(size: 10, weight: .heavy, design: .monospaced)).tracking(0.5).foregroundColor(on ? .white : buildDim)
                Spacer(minLength: 0)
            }.padding(.vertical, 8).padding(.horizontal, 9)
            .background(RoundedRectangle(cornerRadius: 6).fill(on ? buildCyan.opacity(0.12) : buildCell))
            .overlay(RoundedRectangle(cornerRadius: 6).stroke(on ? buildCyan.opacity(0.5) : buildEdge, lineWidth: 1))
        }
    }
    // A generic ◀/▶ chevron step button — shared by PAGINATION (page the history) and EXTEND (grow the selection); disabled at the ends.
    @ViewBuilder private func buildReelStepBtn(back: Bool, enabled: Bool, _ act: @escaping () -> Void) -> some View {
        Button(action: act) {
            Image(systemName: back ? "chevron.left" : "chevron.right").font(.system(size: 14, weight: .heavy))
                .foregroundColor(enabled ? buildCyan : buildDim).frame(width: 44, height: 30)
                .background(RoundedRectangle(cornerRadius: 6).fill(buildCell)).overlay(RoundedRectangle(cornerRadius: 6).stroke(buildEdge, lineWidth: 1))
        }.disabled(!enabled)
    }
    // #5 (Paul 2026-08-26): restore the deployed play-grid arrangement that was live during the selected pass. v1 = a LIVE
    // switch (like a scene change); the append-only / undo-integrated "forward event" model is the next increment.
    private func buildReelRestoreState() {
        guard reelSelPassNo >= 0, let snap = reelStateRing[reelSelPassNo] else { return }
        buildRestoreScene(snap)          // restore the play-grid arrangement that was live during that pass
        reelShowPopup = false            // CLOSE the reel (Paul 2026-08-26) → .onDisappear stops the replay + unfreezes, so the UI shows the restored state live
    }
    // The 4 piano-roll lanes (bottom 4 rows of the 8×8) + a shared PLAYHEAD that sweeps while a pass replays. Each lane is
    // ONE grid-cell tall and the full grid width, laid out with the SAME gap as the pass rows so the whole page reads as a
    // uniform 8×8 (Paul 2026-08-26). Lanes do not collapse — all four always render.
    private func buildReelRollSection(width: CGFloat, laneH: CGFloat, gap: CGFloat) -> some View {
        let rollH = 4 * laneH + 3 * gap
        return TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: reelState != 2)) { tl in
            let phase = reelPlayheadPhase(tl.date)                                // 0…1 across the pass, or nil (not replaying)
            VStack(spacing: gap) {
                ForEach(0..<4, id: \.self) { lane in
                    buildReelLane(lane, width: width, height: laneH, phase: phase)
                }
            }
            .background(RoundedRectangle(cornerRadius: 4).fill(Color.white.opacity(reelSelPassNo >= 0 ? 0.05 : 0)))   // SELECTION WASH (design §1.2) — links the cyan chip to the roll
            .overlay(alignment: .leading) {
                if let phase { Rectangle().fill(Color.white.opacity(0.75)).frame(width: 1.5, height: rollH).offset(x: CGFloat(phase) * width) }
            }
        }
    }
    // The playhead position (0…1) NOW, extrapolated from the last beat poll (one-clock rule). Only while replaying.
    private func reelPlayheadPhase(_ now: Date) -> Double? {
        guard reelState == 2, reelRangeCyc <= 0, reelCycle > 0 else { return nil }   // the sweeping playhead follows single-pass replay only (a range roll is static — no replay yet)
        let beat = d.playing ? reelLastBeat + now.timeIntervalSince(reelLastBeatAt) * d.tempo / 60.0 : reelLastBeat
        var p = beat.truncatingRemainder(dividingBy: reelCycle) / reelCycle
        if p < 0 { p += 1 }
        return p
    }
    // One pass cell. Populated → shows its 1-based pass number; the pinned/replaying pass lights cyan. Tap = select+replay,
    // or (if it's already the replaying pass) stop and resume live.
    @ViewBuilder private func buildReelPassCell(_ pass: Int, w: CGFloat, h: CGFloat) -> some View {
        let lo = min(reelSelLoPass, reelSelHiPass), hi = max(reelSelLoPass, reelSelHiPass)
        let inRange = pass >= 0 && reelSelLoPass >= 0 && pass >= lo && pass <= hi   // in the export/highlight range (Paul 2026-08-26)
        let anchor = pass >= 0 && pass == reelSelPassNo                            // the replaying/audition pass
        let lit = inRange || anchor
        let playing = anchor && reelState == 2
        RoundedRectangle(cornerRadius: 3)
            .fill(pass < 0 ? Color.white.opacity(0.03) : (lit ? buildCyan : Color.white.opacity(0.08)))
            .frame(width: w, height: h)
            .overlay(playing ? RoundedRectangle(cornerRadius: 3).stroke(Color(red: 0.36, green: 0.92, blue: 0.52), lineWidth: 2)
                             : (anchor && hi > lo ? RoundedRectangle(cornerRadius: 3).stroke(Color.white, lineWidth: 1.5) : nil))   // the anchor within a multi-pass range
            .overlay(pass >= 0 ? Text("\(pass + 1)").font(.system(size: min(15, min(w, h) * 0.42), weight: .heavy, design: .monospaced))
                        .foregroundColor(lit ? .black : buildCyan.opacity(0.9)) : nil)
            .contentShape(Rectangle())
            .onTapGesture {
                guard pass >= 0 else { return }
                if playing { au?.reelStopReplay() } else { buildReelSelectPass(pass) }
            }
    }
    // One emitter piano-roll lane. Draws the selected pass's notes for cable = lane+1 over a reference grid: 8 CELL
    // dividers (vertical), OCTAVE dividers (horizontal at each C) with the C labelled on the left + right axis. Pitch is
    // framed to whole octaves and shared across all lanes; x = pass length; opacity = velocity; the playhead lights notes.
    private func buildReelLane(_ lane: Int, width: CGFloat, height: CGFloat, phase: Double?) -> some View {
        let hue = reelLaneHues[lane]
        let notes = reelRoll.filter { Int($0.cable) == lane + 1 }
        let all = reelRoll.map { Int($0.note) }
        let rawLo = all.min() ?? 48, rawHi = all.max() ?? 72
        let lo = (rawLo / 12) * 12, hi = max(lo + 12, ((rawHi + 11) / 12) * 12)   // frame to whole octaves → a C at top + bottom
        let span = CGFloat(hi - lo)
        let cyc = max(0.0001, reelEffCycle)                                      // the range total (multi-pass) or the single pass length
        let selected = reelExportLanes.contains(lane)                           // this emitter is in the export selection (Paul 2026-08-26)
        let head = phase.map { $0 * cyc }                                        // the playhead's beat, or nil
        func yOf(_ note: Int) -> CGFloat { (1 - CGFloat(note - lo) / span) * (height - 6) + 3 }
        return ZStack(alignment: .leading) {
            RoundedRectangle(cornerRadius: 3).fill(Color.white.opacity(0.04)).frame(width: width, height: height)
            Canvas { ctx, sz in
                // CELL dividers — 8 columns of the bar
                for i in 1..<8 {
                    let x = CGFloat(i) / 8 * sz.width
                    ctx.stroke(Path { $0.move(to: CGPoint(x: x, y: 0)); $0.addLine(to: CGPoint(x: x, y: sz.height)) },
                               with: .color(.white.opacity(0.07)), lineWidth: 0.5)
                }
                // OCTAVE dividers (horizontal at each C)
                var n = lo
                while n <= hi {
                    let y = yOf(n)
                    ctx.stroke(Path { $0.move(to: CGPoint(x: 0, y: y)); $0.addLine(to: CGPoint(x: sz.width, y: y)) },
                               with: .color(.white.opacity(0.10)), lineWidth: 0.5)
                    n += 12
                }
                // NOTES — each painted the COLOUR of the cell that played it (upcoming + already-played alike);
                // falls back to the lane hue when the pass predates the colour tag. (Paul 2026-08-19)
                for note in notes {
                    let nc = note.colour != 0 ? Color(hex: note.colour) : hue
                    let x = CGFloat(note.start / cyc) * sz.width
                    let w = max(2, CGFloat((note.end - note.start) / cyc) * sz.width)
                    let y = yOf(Int(note.note))
                    let active = head.map { $0 >= note.start && $0 < note.end } ?? false
                    let base = 0.45 + 0.5 * Double(note.vel) / 127
                    let rect = CGRect(x: x, y: y - (active ? 2.5 : 1.5), width: min(w, sz.width - x), height: active ? 5 : 3)
                    if active { ctx.fill(Path(roundedRect: rect.insetBy(dx: -1.5, dy: -1.5), cornerRadius: 2), with: .color(nc.opacity(0.35))) }   // glow under
                    ctx.fill(Path(roundedRect: rect, cornerRadius: 1.4), with: .color(nc.opacity(active ? 1.0 : base)))
                }
            }.frame(width: width, height: height)
            HStack(spacing: 3) {
                Image(systemName: selected ? "checkmark.circle.fill" : "circle").font(.system(size: 8, weight: .bold)).foregroundColor(selected ? hue : hue.opacity(0.4))
                Text(["A", "B", "C", "D"][lane]).font(.system(size: 9, weight: .heavy, design: .monospaced)).foregroundColor(hue.opacity(selected ? 1 : 0.8))
            }.padding(.leading, 4)
        }
        .overlay(selected ? RoundedRectangle(cornerRadius: 3).stroke(hue, lineWidth: 1.5) : nil)   // SELECTED emitter — highlighted for export (Paul 2026-08-26)
        .contentShape(Rectangle())
        .onTapGesture { if reelExportLanes.contains(lane) { reelExportLanes.remove(lane) } else { reelExportLanes.insert(lane) } }   // tap a lane → toggle it in the export selection (none ⇒ master)
    }
    // EXPORT the recorded pass to SMF files (the A–D sum + per-emitter stems), then present a share sheet. (Paul 2026-08-18)
    // EXPORT the selected pass RANGE × the selected emitter LANES (Paul 2026-08-26). No lane selected ⇒ the MASTER (A–D sum).
    private func buildReelExport() {
        let (lo, hi) = buildReelExportRange()
        guard lo >= 0, hi >= 0 else { return }
        var mask: UInt8 = 0; for l in reelExportLanes where l >= 0 && l < 4 { mask |= (1 << UInt8(l)) }
        let files = au?.reelExportRangeFiles(fromPass: lo, toPass: hi, emitterMask: mask) ?? []
        guard !files.isEmpty else { return }
        let dir = FileManager.default.temporaryDirectory
        var urls: [URL] = []
        for f in files {
            let url = dir.appendingPathComponent(f.name)
            if (try? f.data.write(to: url)) != nil { urls.append(url) }
        }
        guard !urls.isEmpty else { return }
        reelShareURLs = urls
        reelShowShare = true
    }
    // The pass range to export/highlight: the [lo,hi] set by ◀/▶, else the single selected pass. (pass numbers)
    private func buildReelExportRange() -> (Int, Int) {
        if reelSelLoPass >= 0 && reelSelHiPass >= 0 { return (min(reelSelLoPass, reelSelHiPass), max(reelSelLoPass, reelSelHiPass)) }
        return (reelSelPassNo, reelSelPassNo)
    }
    // Tap a pass: collapse the range to that single pass + select/replay it (the anchor drives the live roll + audition).
    private func buildReelSelectPass(_ pass: Int) {
        reelSelLoPass = pass; reelSelHiPass = pass; reelRangeCyc = 0
        au?.reelSelectPass(pass)
    }
    // ◀/▶ EXTEND (Paul 2026-08-26): grow the selection's LEFT (dir<0) or RIGHT (dir>0) edge to the next recorded pass; the
    // page follows so the growing edge stays visible; the roll refreshes to the whole concatenated range.
    private func buildReelExtend(_ dir: Int) {
        let visible = buildReelVisiblePasses()
        guard !visible.isEmpty else { return }
        if reelSelLoPass < 0 || reelSelHiPass < 0 {   // nothing yet → seed from the anchor / newest
            let seed = reelSelPassNo >= 0 ? reelSelPassNo : (visible.last ?? -1)
            reelSelLoPass = seed; reelSelHiPass = seed
        }
        if dir < 0 {
            if let prev = visible.last(where: { $0 < min(reelSelLoPass, reelSelHiPass) }) { reelSelLoPass = prev; buildReelPageFor(prev, visible: visible) }
        } else {
            if let next = visible.first(where: { $0 > max(reelSelLoPass, reelSelHiPass) }) { reelSelHiPass = next; buildReelPageFor(next, visible: visible) }
        }
        buildReelRefreshRange()
    }
    private func buildReelPageFor(_ pass: Int, visible: [Int]) { if let idx = visible.firstIndex(of: pass) { reelPage = idx / 32 } }
    // Recompute the displayed roll for the current range: multi-pass ⇒ the concatenated range roll (+ its total length);
    // single ⇒ leave reelRangeCyc 0 so the poll drives reelRoll from the anchor pass.
    private func buildReelRefreshRange() {
        guard reelSelLoPass >= 0, reelSelHiPass >= 0 else { reelRangeCyc = 0; return }
        let lo = min(reelSelLoPass, reelSelHiPass), hi = max(reelSelLoPass, reelSelHiPass)
        if hi > lo, let r = au?.reelRangeRoll(fromPass: lo, toPass: hi) { reelRoll = r.notes; reelRangeCyc = r.cycle }
        else { reelRangeCyc = 0 }
    }
    private var reelEffCycle: Double { reelRangeCyc > 0 ? reelRangeCyc : reelCycle }   // the roll's x-axis span: the range total, or the single pass length

    // The selected colour's real hue (the cast selection drives the machine ID + grid tints). Falls back to cyan.
    fileprivate var buildSelHue: Color { colourColor(ddSelectedColourID ?? "") ?? buildCyan }
    // THE MACHINE DISPLAY HUE (Paul 2026-08-30): the ONE hue for the machine BOX + MIDI CHAIN + PLAY button, so the three
    // stay consistent. Colour is a thing on the PART/PLAY grids + ferries only — it has LEFT the SELECT grid (its cells show
    // the inverse light grey). So a PLAIN select-grid audition (the transient gsAud, which carries no colour) shows the
    // machine that SAME light grey. But once a REAL colour is the selection — a ferry has just been copied and becomes
    // selected, or PART's own machine — the box + chain + play button all wear THAT colour (not grey/white). PART always
    // wears its machine's colour. (The machine box only appears on SELECT + PART.)
    // The part's DEFAULT output emitters — its chosen set, or emitter A when none. A row/cell/ferry inherits this when
    // it has no emitters of its own. (refactor 2026-08-30: was `buildPartEmitters.isEmpty ? [.a] : buildPartEmitters`
    // inlined at ~10 sites.)
    var buildDefaultEmitters: Set<Bus> { buildPartEmitters.isEmpty ? [.a] : buildPartEmitters }
    // Two BRIGHT shades that alternate each new SELECT pick (buildSelectGreyAlt flips on selection) so the machine section
    // visibly shifts even though the audition colour is always the same transient "gsAud" (Paul 2026-09-01).
    var buildSelectGrey: Color { Color(white: buildSelectGreyAlt ? 0.90 : 0.80) }
    // THE MACHINE BINDING (Paul 2026-09-01, state-unification): the ONE truth for what the machine represents + its play
    // state, gathered from the four @State axes into the pure BuildSceneLogic resolver. The machine hue, the play button,
    // (and in a follow-up, every represented-cell indicator) all DERIVE from this so they can't diverge.
    func buildMachineBinding(_ room: Room) -> BuildSceneLogic.MachineBinding {
        BuildSceneLogic.machineBinding(selID: buildSelID, audID: buildGridSelAudID, onSelectPage: room == .select,
                                       chainActive: buildDisplayVoice == .chain, partActive: buildDisplayVoice == .part,
                                       selectedPlayCol: room == .select ? buildSelectedPlayCol : nil, playColOn: buildPlayColOn)
    }
    func buildMachineHue(_ room: Room) -> Color {
        buildMachineBinding(room).isGrey ? buildSelectGrey : buildSelHue   // grey = the colourless SELECT audition; else the machine/ferry's own hue
    }
    // THE ONE HUE for every machine/card/editor surface (Paul 2026-08-31: the processor card was a DIFFERENT colour to the
    // machine box — a throwback to the multi-colour select grid, because the card read raw buildSelHue while the box read
    // the room-aware buildMachineHue). Both now resolve through this single accessor, so the card can never diverge again.
    var buildCardHue: Color { buildMachineHue(roomsRoom) }


    // ── PORTRAIT: height is abundant → a plain stack (palette → staging → play → machinery) ────────────────────────
    // (buildPortrait retired 2026-08-24 — LANDSCAPE-ONLY; git history keeps the vertical-stack layout if ever needed.)


    // The verb button stack, right of the MIDI chain. LEFT chevrons (<<<) act on the SELECTED colour's midi chain;
    // RIGHT chevrons (>>>) act on the PART grid. LIBRARY opens the cell library. (Paul 2026-08-18)
    @ViewBuilder private func buildChainButtonStack(width: CGFloat, height: CGFloat, showGrid: Bool = true) -> some View {
        VStack(spacing: BuildGeom.castGap) {                                  // the CHAIN-scope verbs
            if showGrid {                                                     // OLD build page — the full verb set, filling the stack (unchanged)
                buildChainBtn("LIBRARY", fill: true)   { buildOpenLibrary() }
                buildChainBtn("GRID", fill: true)      { buildOpenGridSel() }
                buildChainBtn("RANDOMIZE", fill: true) { buildRandomizeSimple() } // reroll the chain
                buildChainBtn("MUTATE", fill: true)    { buildMutateChain() }     // nudge the chain
                buildChainBtn("CLEAR", fill: true)     { buildClearChain() }      // empty the chain
                HStack(spacing: BuildGeom.castGap) {                              // COPY | PASTE — copy this chain into a new row position
                    buildChainBtn("COPY", fill: true) { buildCopyChain() }
                    buildChainBtn("PASTE", enabled: !(buildChainClipboard ?? []).isEmpty, fill: true) { buildPasteChain() }
                }
            } else {                                                         // ROOMS machine section — SMALLER buttons (text unchanged); RANDOMIZE + COPY/PASTE dropped (Paul 2026-08-29)
                buildChainBtn("LIBRARY", h: 26) { buildOpenLibrary() }
                buildChainBtn("MUTATE", h: 26)  { buildMutateChain() }
                buildChainBtn("CLEAR", h: 26)   { buildClearChain() }
            }
        }
        .frame(width: width)
        .frame(height: height, alignment: .center)                           // the stack matches the 4-row processor block height; the compact buttons centre within it
        .frame(maxWidth: .infinity, alignment: .center)                      // centre HORIZONTALLY in the space beside the chain
    }

    // ── NEW INTERFACE (rooms) reuse — THE REAL MACHINE STRIP for the SELECT/PART chain panel. Composes the EXACT
    // components Paul named — PLAY THIS MIDI CHAIN button · MIDI-IN receiver toggles · the MIDI chain (2×4 boxes) +
    // its side-button stack · MIDI-OUT emitter toggles — reusing the private left-column helpers VERBATIM (no
    // recreation). Only THIS assembler is internal so RoomsPage.swift can call it; the pieces stay private to this
    // file. Functionality (which colour/row it edits) may be un-wired in the new shell — that's wired in later. (Paul 2026-08-28)
    // THE LEFT PANEL — mapped onto the grid's LATTICE (design ferry INSTRUCTIONS-layout-lattice, 2026-08-29). The panel
    // mirrors the grid's band structure EXACTLY — VStack(spacing: gap){ PLAY(navH) · RECORD(ch) · interior(interiorH) }
    // .padding(pad) — so BAND 1 (PLAY) rhymes with the ▲PLAY door, BAND 2 (RECORD) rhymes with the header row, and the
    // interior column runs from the grid's interiorTop to its bottom (receiver pinned TOP · chain · Spacer · emitter
    // pinned BOTTOM). The reused I/O widgets keep their fixed heights — the lattice insets do the aligning (option a).
    @ViewBuilder func roomsMachineStrip(width: CGFloat, room: Room, m: RoomsMetrics) -> some View {
        let pad = RoomsMetrics.pad, gap = RoomsMetrics.gap
        let castW = max(160, width - 2 * pad)                                // content width inside the box's pad
        let cgap = BuildGeom.castGap                                         // the chain block keeps its own 8-column grain (4)
        let swW = (castW - cgap * 7) / 8
        let cell = max(BuildGeom.cellMin, min(BuildGeom.cellMax, swW))
        let blockH = 4 * (cell + cgap) * 1.5 + 3 * cgap                     // the MIDI-chain block height — +50% box height (Paul 2026-08-30); verb buttons + play square share it
        let blockW = 4 * swW + 3 * cgap                                     // its intrinsic width (~half castW)
        let sideW  = max(1, (castW - blockW) / 2)                           // EQUAL flanks → the chain stays CENTRED in its box; the (narrower) buttons fill ONE flank
        // On the SELECT grid a running cell is shown in the INVERSE LIGHT GREY (not its hue), so the machine box matches that
        // same light grey while a cell runs there — instead of the chain's colour (Paul 2026-08-30).
        let boxHue: Color = buildMachineHue(room)   // grey on SELECT (colour left it), the machine colour on PART — Paul 2026-08-30
        VStack(spacing: gap) {
            AnyView(buildReceiverSelector(castW: castW))                       // the 4 MIDI IN toggles — CONTENT-sized (was .frame(height: m.ch), whose extra space read as padding above the chain; the emitter toggles below are content-sized, now symmetric — Paul 2026-08-30)
            VStack(spacing: 8) {                                            // THE INTERIOR COLUMN — from the grid's interiorTop to its bottom
                Spacer(minLength: 8)                                         // centre the chain row VERTICALLY
                AnyView(HStack(alignment: .center, spacing: 0) {           // verb buttons on ONE side · MIDI CHAIN centred · VERTICAL PLAY + PLAYHEAD on the OPPOSITE side (Paul 2026-08-29)
                    if room == .part {                                     // PART → verb buttons LEFT · vertical play RIGHT
                        AnyView(buildChainButtonStack(width: sideW, height: blockH, showGrid: false))
                    } else {                                               // SELECT → PLAY + SELECT column LEFT (opposite the right verb buttons)
                        AnyView(roomsPlaySelectColumn(room, height: blockH)).frame(width: sideW)
                    }
                    AnyView(buildProcessorBlock(castW: castW, cell: cell, hue: boxHue)).frame(width: blockW)   // the chain wears the SAME machine hue as the box (grey on SELECT) — Paul 2026-08-30
                    if room == .part {
                        AnyView(roomsPlaySelectColumn(room, height: blockH)).frame(width: sideW)   // PART → PLAY + SELECT column RIGHT (opposite the left verb buttons)
                    } else {
                        AnyView(buildChainButtonStack(width: sideW, height: blockH, showGrid: false))   // SELECT → verb buttons RIGHT
                    }
                }.overlay { buildChainFlowOverlay(sideW: sideW, blockW: blockW, blockH: blockH, boxH: (cell + cgap) * 1.5, gap: cgap, hue: boxHue, chain: selectedColourChain()) })   // circles + connectors + NOTE COMETS (spans the circles, clipped out of POPULATED boxes) — Paul 2026-08-31
                Spacer(minLength: 8)
                AnyView(buildEmitterToggles(castW: castW))                   // MIDI OUT A–D — pinned at the interior BOTTOM (the grid's last row line)
            }.frame(height: m.interiorH)
        }
        .padding(pad)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)    // CENTRED (Paul 2026-08-31): top-align dumped the whole leftover BELOW the emitter toggles (padding there) while the receiver toggles sat flush at the top — centring splits it so the gap above the receiver toggles == the gap below the emitter toggles
        .background(Rectangle().fill(Color.white.opacity(0.05)))                 // SQUARE edges (Paul 2026-08-30, was cornerRadius 12)
        // PAIRING (Paul 2026-08-30): the whole machine strip wears the FOCUSED machine's hue (buildSelHue) — the SAME hue
        // the focused grid cell's frame brightens to. Matched frame ⇄ strip = "this cell is the machine in view."
        // PAIRING: the selected-colour box wears the focused machine's hue — or the SELECT running-cell light grey (boxHue).
        // GLOWING border (Paul 2026-08-31): the selected-colour's machine box (its toggles · MIDI chain · button box) wears a
        // soft hue glow around its frame so the current colour reads at a glance.
        .overlay(Rectangle().stroke(boxHue.opacity(0.9), lineWidth: 2.5)
            .shadow(color: boxHue.opacity(0.75), radius: 5)
            .shadow(color: boxHue.opacity(0.5), radius: 9))                       // SQUARE edges (Paul 2026-08-30, was cornerRadius 12)
    }
    // THE PLAY SECTION HEADER — the room-aware play/stop button. Now sits in the machine strip's BAND 2 (m.ch), PARALLEL
    // with the grid's FERRY row (the caller frames it to m.ch); fillHeight makes the button FILL that band so its top/
    // bottom line up exactly with the ferry buttons. SELECT plays the CHAIN audition, PART plays the PART. (Paul 2026-08-29)
    // THE VERTICAL PLAY BUTTON + PLAYHEAD (Paul 2026-08-29) — a tall thin play/stop toggle beside the MIDI chain, on the
    // OPPOSITE side from the verb buttons. Its PLAYHEAD is a TOP→BOTTOM fill running the chain's play duration (buildHeaderFill).
    // THE PLAY BUTTON — now a SQUARE (~one MIDI-chain box) with a LEFT→RIGHT playhead sweep (Paul 2026-08-30, was a tall
    // narrow button with a top→bottom fill). Sits centred in its flank; tap = play/stop the chain (SELECT) or part (PART).
    @ViewBuilder func roomsVerticalPlay(_ room: Room, buttonH: CGFloat) -> some View {
        let voice: BuildWorkshopVoice = room == .part ? .part : .chain
        // If the SELECTED machine IS a play-ferry's chain, this button STARTS/STOPS THAT FERRY (its play column) — not a
        // separate isolated chain audition. "This MIDI chain IS the one of the ferry button." (Paul 2026-08-31)
        let bind = buildMachineBinding(room)     // ONE source of truth for what the machine represents + its play state (Paul 2026-09-01)
        let active = bind.playing
        let hue: Color = bind.isGrey ? buildSelectGrey : buildSelHue   // SAME hue as the machine box + chain (grey on SELECT audition, the machine/ferry colour otherwise)
        ZStack {
            RoundedRectangle(cornerRadius: 8).fill(buildCell)            // DARK STAGE (like a grid cell)
            if active { RoundedRectangle(cornerRadius: 8).fill(hue.opacity(0.24)) }   // machine-hue wash when playing
            if active && d.playing {                                    // the PLAYHEAD — a fill sweeping LEFT→RIGHT over the chain's duration
                TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: animationsPaused)) { tl in
                    GeometryReader { g in
                        RoundedRectangle(cornerRadius: 8).fill(hue.opacity(0.34))
                            .frame(width: g.size.width * buildHeaderFill(.grid, tl.date))
                            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)   // grows from the left across
                    }
                }
            }
            Image(systemName: active ? "stop.fill" : "play.fill").font(.system(size: 16, weight: .black))
                .foregroundColor(active ? hue : hue.opacity(0.8))
        }
        .frame(maxWidth: .infinity).frame(height: buttonH)              // FILL the slot (Paul 2026-08-31: no centring gap between play + SELECT)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(active ? hue : buildEdge, lineWidth: active ? 3 : 1))   // BRIGHT hue frame when playing
        .shadow(color: active ? hue.opacity(0.6) : .clear, radius: active ? 5 : 0)   // hue glow when playing (ferry-style)
        .contentShape(Rectangle())
        .onTapGesture {
            if case let .playFerry(pc) = bind.kind { buildTogglePlayColumn(pc) }   // the ferry's OWN play column (start/stop the ferry)
            else { buildRequestWorkshopVoice(active ? .none : voice) }             // else the chain/part audition
        }
    }
    // THE SELECT-MODE BUTTON (Paul 2026-08-31) — directly under the play button, SAME size/style. Toggles buildSelectMode: while
    // on, every cell (select + ferry) lights white and a TAP only FOCUSES it into the machine (no start/stop). A way to pick a
    // cell for editing/viewing without playing it.
    @ViewBuilder func roomsSelectButton(buttonH: CGFloat) -> some View {
        let on = buildSelectMode
        ZStack {
            RoundedRectangle(cornerRadius: 8).fill(buildCell)
            if on { RoundedRectangle(cornerRadius: 8).fill(buildCyan.opacity(0.28)) }   // lit cyan when armed
            Text("SELECT").font(.system(size: min(11, buttonH * 0.48), weight: .black, design: .monospaced))
                .foregroundColor(on ? buildCyan : buildDim).lineLimit(1).minimumScaleFactor(0.5)
        }
        .frame(maxWidth: .infinity).frame(height: buttonH)              // FILL the slot — matches the play button, no gap
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(on ? buildCyan : buildEdge, lineWidth: on ? 3 : 1))
        .shadow(color: on ? buildCyan.opacity(0.5) : .clear, radius: on ? 4 : 0)
        .contentShape(Rectangle())
        .onTapGesture { buildSelectMode.toggle() }
    }
    // THE PLAY + SELECT COLUMN — the machine's flank: PLAY on top, SELECT DIRECTLY beneath it (equal size/style, NO gap between
    // them — Paul 2026-08-31), the pair centred vertically in the flank.
    @ViewBuilder func roomsPlaySelectColumn(_ room: Room, height: CGFloat) -> some View {
        GeometryReader { g in
            let bh = max(18, min(g.size.width * 0.5, (height - 2) / 2))   // wide-short buttons, capped to fit the flank
            VStack(spacing: 0) {                                          // ADJACENT — no spacing between play + SELECT
                roomsVerticalPlay(room, buttonH: bh)
                roomsSelectButton(buttonH: bh)
            }
            .frame(width: g.size.width, height: height, alignment: .center)   // centre the pair in the flank
        }
    }
    // (The wide RECORD row was RETIRED 2026-08-29 — the PLAY button took its band. The reel is still reached via the
    // REEL room. buildReelButton remains for that room / a future RECORD home.)

    // ── NEW INTERFACE (rooms) reuse — THE SELECT GRID = the LIBRARY-backed chain browser. Populate the SELECT room's
    // 8×8 with real chains from MY LIBRARY (saved + factory cells) by opening the existing grid selector on its LIBRARY
    // tab; each interior cell reuses buildGridSelCell (the drifting-note fingerprint face + tap-to-audition), verbatim.
    // Idempotent — safe to call on every SELECT-room appear. (Paul 2026-08-28)
    func roomsSelectSetup() {
        buildEnsureGridSelOpen()                                              // opens the selector (loads library summaries + deals), guarded — no-op if already open
        if buildGridSelTab != 1 {                                            // SELECT shows MY LIBRARY, not the DEALT bank
            buildGridSelStopAudition()
            buildGridSelTab = 1
            buildGridSelComputeCellRolls()                                    // the library cells' drifting faces
        }
        // No startup randomization (Paul 2026-08-29): the corpus is split into deterministic PAGES via the left rail
        // (page 0 = row 1 default). A cell auditions only when the user taps it.
        roomsSyncVoice(.select)                                              // part→chain (nothing from PART plays here)
    }

    // ── NEW INTERFACE — the PROCESSOR CARD overlay. A populated chain box opens its editor (buildProcessorPanel) as a
    // NON-MODAL card bounded to the GRID INTERIOR (inset from the header row + the side buttons), so everything outside
    // it stays reachable. Attached as an .overlay on the grid, so it's automatically clipped to the grid's frame; the
    // fractional insets carve out the side-button column(s) + the top selector row. (Paul 2026-08-28)
    // The card positioned at an EXPLICIT rect (the grid units compute the interior 8×8 rect + place it there). Non-modal.
    // NO outer box (buildProcessorPanel already draws its OWN selected-colour box + background) + NO padding, so that box
    // fills the whole card (Paul 2026-08-28) — only the panel's hue border shows, occupying the full space.
    @ViewBuilder func roomsProcessorCardAt(x: CGFloat, y: CGFloat, w: CGFloat, h: CGFloat) -> some View {
        if let slot = buildEditSlot {
            let chain = selectedColourChain()
            if slot < chain.count, let cid = ddSelectedColourID {
                buildProcessorPanel(slot: slot, proc: chain[slot], cid: cid, contentW: w)
                .frame(width: w, height: h)                                   // fixed card box — the panel pins its header + scrolls its body inside this
                .offset(x: x, y: y)
                .onAppear { buildEditorSnapshot = selectedColourChain(); buildEditorSnapCid = ddSelectedColourID }   // OPEN snapshot for CANCEL
                .onChange(of: ddSelectedColourID) { newID in
                    guard let newID, newID != buildEditorSnapCid else { return }
                    buildEditorSnapshot = selectedColourChain(); buildEditorSnapCid = newID
                }
            }
        }
    }
    // ── THE NAV SLIVERS — thin navigation bars that are a COMPONENT OF THE GRID BOX (Paul 2026-08-28). The ▲PLAY sliver
    // sits directly above the top-row selector buttons (1/3 cell tall, spanning cols 1–8); the SEAM sliver sits beside
    // the side buttons (1/3 cell wide, spanning the interior rows). Destination-cyan for now.
    // A DOOR BAR fills with its DESTINATION's signature (§8b): a RAINBOW strip to SELECT · AMBER to PART · INDIGO to
    // PLAY · RED to REEL. Used by every nav door/sliver so a door always announces where it leads.
    @ViewBuilder func roomsDoorBar(to room: Room, corner: CGFloat = 4) -> some View {
        let shape = RoundedRectangle(cornerRadius: corner)
        switch room {
        case .select: shape.fill(LinearGradient(colors: roomsRainbowHues, startPoint: .leading, endPoint: .trailing))
        case .part:   shape.fill(roomsAmber)
        case .play:   shape.fill(roomsIndigo)
        case .reel:   shape.fill(roomsRedSig)
        }
    }
    // The legible ink for a door's label on its signature fill.
    func roomsDoorInk(to room: Room) -> Color {
        switch room {
        case .select, .part: return .black.opacity(0.82)   // on the rainbow strip / amber
        case .play, .reel:   return .white                 // on indigo / red
        }
    }
    // The room's FIELD tint behind everything (§8b): charcoal floor in every room; PLAY is the dark stage (near-black).
    func roomsField(_ room: Room) -> Color {
        room == .play ? Color(red: 0.02, green: 0.02, blue: 0.03) : Color(red: 0.06, green: 0.07, blue: 0.085)
    }
    @ViewBuilder func roomsPlayNavSliver(width: CGFloat, height: CGFloat) -> some View {
        roomsDoorBar(to: .play)                                             // → PLAY = INDIGO (retires cyan)
            .frame(width: width, height: height)
            .overlay(HStack(spacing: 5) { Image(systemName: "chevron.up"); Text("PLAY GRID"); Image(systemName: "chevron.up") }.font(.system(size: min(11, height * 0.7), weight: .heavy, design: .monospaced)).foregroundColor(roomsDoorInk(to: .play)))   // a chevron on EACH side (Paul 2026-08-31)
            .contentShape(Rectangle()).onTapGesture { roomsRoom = .play }
    }
    @ViewBuilder func roomsSeamSliver(to room: Room, chevron: String, width: CGFloat, height: CGFloat) -> some View {
        // The DESTINATION grid's name, written VERTICALLY, with a left/right chevron pointing to it (Paul 2026-08-31):
        // on the SELECT page the seam → PART ("PART GRID", far RIGHT, ▸); on the PART page → SELECT ("SELECT GRID", far LEFT, ◂).
        let label = room == .part ? "PART GRID" : (room == .select ? "SELECT GRID" : room.rawValue)
        let toRight = room == .part
        let ink = roomsDoorInk(to: .play)                                   // ALL nav buttons wear the PLAY-GRID colour (Paul 2026-08-31)
        roomsDoorBar(to: .play)                                             // → the PLAY-GRID indigo (not the destination's own signature)
            .frame(width: width, height: height)
            .overlay(
                VStack(spacing: 6) {
                    Image(systemName: toRight ? "chevron.right" : "chevron.left").font(.system(size: min(13, width * 0.6), weight: .heavy))
                    Text(label).font(.system(size: 11, weight: .heavy, design: .monospaced)).fixedSize()
                        .rotationEffect(.degrees(90)).frame(width: width, height: min(height * 0.75, 130))   // VERTICAL text
                }.foregroundColor(ink)
            )
            .contentShape(Rectangle()).onTapGesture { roomsRoom = room }
    }
    // THE SEAM COLUMN (Paul 2026-08-28) — the part↔select nav, relocated to the FAR side of the page (opposite the MIDI
    // chain): a PARTIALLY-INVISIBLE single-column control that takes the grid's height into account so the visible seam
    // aligns EXACTLY with the grid's interior rows (same ch + offset as the grid: below the ▲PLAY sliver + track row).
    // The column width is set by the caller (50% of a grid cell) so it looks identical to the old in-grid seam.
    @ViewBuilder func roomsSeamColumn(to room: Room, chevron: String, m: RoomsMetrics) -> some View {
        GeometryReader { g in                                               // the shared lattice (m) places the seam over the grid's interior rows
            roomsSeamSliver(to: room, chevron: chevron, width: g.size.width, height: m.interiorH)
                .offset(y: m.interiorTop)                                    // the rest of the column is empty → partially invisible
        }
    }
    // THE PLAY FERRY button (Paul 2026-08-29) — the SELECT grid's top-row buttons that FERRY the selected cell to the
    // PLAY grid. LONG-PRESS copies the currently-selected cell onto the play grid at THIS column's selected rung (→ its
    // grid position + the play bottom readout), with the rising-white overwrite warning (buildGridSelStampSweep, offset
    // +8 so the play-ferry fill never collides with the PART-ferry side buttons that share the select grid). Each button
    // shows a PLAY ICON in its predetermined PLAY colour (INDIGO); the button itself stays neutral — a white "set" keyline
    // + brighter field mark a column that has been ferried (was a number on a hue field).
    // THE FERRY-ROW CURSOR (Paul 2026-08-31): ▲▼ chooses which grid ROW the play-ferry buttons target — so you can ferry
    // a cell to row 1 of a column, then move the cursor and ferry another to row 3 (each cell stays independent). Sits in
    // the ferry row's left corner. Compact: ▲ · Rn · ▼ in one cell.
    @ViewBuilder func roomsPlayFerryRowSelector() -> some View {
        // BOTTOM-UP (Paul 2026-08-31): the play grid climbs — Row 1 at the bottom, UP goes to a new higher row (lit at Row 1),
        // DOWN goes back. Big, touchable ▲/▼ each filling a half of the cell.
        let canUp = buildPlayFerryRow < 7, canDown = buildPlayFerryRow > 0
        GeometryReader { g in
            let s = min(g.size.width, g.size.height) * 0.5
            // ONE SOLID BLOCK (Paul 2026-09-01): a single indigo fill; the two chevrons are just tap-halves over it (only the
            // CHEVRON dims at an edge, never the block) so it reads as one control, not two buttons.
            ZStack {
                RoundedRectangle(cornerRadius: 4).fill(roomsIndigo)
                VStack(spacing: 0) {
                    Image(systemName: "chevron.up").font(.system(size: s, weight: .black)).foregroundColor(canUp ? roomsDoorInk(to: .play) : .white.opacity(0.28))
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .contentShape(Rectangle()).onTapGesture { if canUp { buildPlayFerryStep(1) } }
                    Text("R\(buildPlayFerryRow + 1)").font(.system(size: 9, weight: .black, design: .monospaced)).foregroundColor(.white.opacity(0.9)).lineLimit(1).minimumScaleFactor(0.5)
                    Image(systemName: "chevron.down").font(.system(size: s, weight: .black)).foregroundColor(canDown ? roomsDoorInk(to: .play) : .white.opacity(0.28))
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .contentShape(Rectangle()).onTapGesture { if canDown { buildPlayFerryStep(-1) } }
                }
            }
        }
    }
    @ViewBuilder func roomsPlayFerry(_ t: Int) -> some View {
        GeometryReader { g in
            let sel = buildPlayFerryRow                                  // the ferry buttons show + act on the CURSOR ROW (▲▼-chosen), not a fixed rung (Paul 2026-08-31)
            let id = (sel >= 0 && t < buildPlayCells.count && sel < buildPlayCells[t].count) ? buildPlayCells[t][sel] : nil
            let set = id != nil                                          // has this column been ferried at the cursor row?
            // FAINT COPY (Paul 2026-08-31): an EMPTY cursor cell whose ROW-BELOW holds a cell → a faint, pulsing copy of it;
            // tap DUPLICATES it onto this row (same colour) + starts it playing.
            let copyId: String? = (!set && sel > 0 && t < buildPlayCells.count && (sel - 1) < buildPlayCells[t].count) ? buildPlayCells[t][sel - 1] : nil
            let copyHue = copyId.flatMap { colourColor($0) } ?? Color(hex: playHexes[t % playHexes.count])
            let on = (t < buildPlayColOn.count && buildPlayColOn[t]) && (t < buildPlaySel.count && buildPlaySel[t] == buildPlayFerryRow)   // PLAYING iff the cursor row is this column's active rung
            let mHue = id.flatMap { colourColor($0) } ?? Color(hex: playHexes[t % playHexes.count])   // MACHINE identity — dusk (the ferried cell's colour, or the play grid's dusk slot when empty; Paul 2026-08-30)
            let eHue = emitterHue(t < buildPlayColEmit.count ? buildPlayColEmit[t] : [.a])  // EMITTER colour (routing)
            let focused = set && id == ddSelectedColourID               // this play ferry is the SELECTED machine (Paul 2026-08-30)
            // THREE STATES (Paul 2026-08-30): NULL · POPULATED (machine frame, calm) · PLAYING (bright frame + EMITTER glow +
            // the live drift). Machine = the frame, emitter = the drift tint + a corner dot + the playing glow. SELECTED (not
            // playing) also brightens the frame so the ferry ↔ machine pairing is visible.
            RoundedRectangle(cornerRadius: 4).fill(buildCell)            // DARK STAGE
                .overlay(RoundedRectangle(cornerRadius: 4).fill(mHue.opacity(set ? (on ? 0.24 : 0.10) : 0)))   // faint MACHINE wash
                .overlay { if copyId != nil {                            // FAINT PULSING COPY — tap to duplicate the row-below cell here
                    TimelineView(.animation(minimumInterval: 1.0 / 20.0, paused: animationsPaused)) { tl in
                        let f = stagingPulseFraction(tl.date, period: 1.1)
                        RoundedRectangle(cornerRadius: 4).fill(copyHue.opacity(0.06 + 0.12 * f))
                            .overlay(RoundedRectangle(cornerRadius: 4).stroke(copyHue.opacity(0.28 + 0.4 * f), style: StrokeStyle(lineWidth: 1.5, dash: [3, 3])))
                            .overlay(Image(systemName: "plus").font(.system(size: min(13, g.size.height * 0.42), weight: .black)).foregroundColor(copyHue.opacity(0.4 + 0.4 * f)))
                    }
                } }
                .overlay { if set { buildNoteSweep(indices: buildPlayColSweepIndices(t), active: on, id: id, emitter: t < buildPlayColEmit.count ? buildPlayColEmit[t] : [.a]).padding(2) } }   // live drift in the EMITTER colour (a multi-step pass gathers all its steps)
                .overlay { if set { roomsCellPlayhead(active: on).padding(2) } }   // PER-CELL PLAYHEAD
                .overlay(alignment: .bottom) { buildGridSelStampSweep(t + 8, height: g.size.height, hue: mHue) }   // rising fill + the COMMIT colour-bloom (reveal) in this ferry's hue
                .clipShape(RoundedRectangle(cornerRadius: 4))
                .overlay(RoundedRectangle(cornerRadius: 4).stroke(set ? mHue.opacity(on ? 1.0 : (focused ? 0.9 : 0.5)) : buildEdge, lineWidth: on ? 3 : (focused ? 2.5 : (set ? 2 : 1))))   // MACHINE frame: dim → BRIGHT when PLAYING or SELECTED
                .overlay { if buildSelectMode && set { RoundedRectangle(cornerRadius: 4).stroke(Color.white, lineWidth: 2.5) } }   // SELECT MODE: light white — tap to focus (Paul 2026-08-31)
                .overlay(alignment: .topTrailing) { if set { Circle().fill(eHue).frame(width: 5, height: 5).padding(3) } }   // EMITTER dot — routing, always visible when populated
                .overlay { if copyId == nil { Image(systemName: on ? "stop.fill" : "play.fill").font(.system(size: min(12, g.size.height * 0.5), weight: .black)).foregroundColor(set ? mHue : buildDim).opacity(on ? 0.85 : 1.0) } }   // PLAY/STOP (a COPY cell shows its own "+" instead)
                .shadow(color: on ? eHue.opacity(0.7) : .clear, radius: on ? 5 : 0)   // PLAYING → an EMITTER-coloured glow
                .contentShape(Rectangle())
                .onTapGesture {
                    if copyId != nil { buildPlayFerryDuplicate(t); return }   // FAINT COPY → duplicate the row-below cell here + play
                    if t < buildPlaySel.count { buildPlaySel[t] = buildPlayFerryRow }
                    if buildSelectMode { buildSelectPlayColumn(t); buildSelectMode = false }   // SELECT MODE: focus this ferry (no start/stop), then end SELECT (Paul 2026-08-31)
                    else { buildTogglePlayColumn(t); buildSelectPlayColumn(t) }        // TAP = make the cursor row this column's active rung, then start/stop + SELECT it
                }
                .onLongPressGesture(minimumDuration: buildGridSelStampDur, maximumDistance: 44,
                                    pressing: { p in buildGridSelStampPressing(t + 8, p) }, perform: { roomsAssignPlayColumn(t) })   // HOLD = ferry the selected cell here
        }
    }
    // Move the ferry-row cursor (bottom-up) with a soft slide. (Paul 2026-08-31)
    func buildPlayFerryStep(_ dir: Int) {
        let n = max(0, min(7, buildPlayFerryRow + dir))
        guard n != buildPlayFerryRow else { return }
        withAnimation(.easeInOut(duration: 0.26)) { buildPlayFerryRow = n }
    }
    // DUPLICATE the ROW-BELOW's cell onto the cursor row (same colour) + start it playing immediately (Paul 2026-08-31).
    func buildPlayFerryDuplicate(_ t: Int) {
        let cur = buildPlayFerryRow
        guard cur > 0, t >= 0, t < buildPlayCells.count, cur < buildPlayCells[t].count, (cur - 1) < buildPlayCells[t].count,
              let src = buildPlayCells[t][cur - 1] else { return }
        buildRecordUndo()
        buildPlayCells[t][cur] = src                                     // same colour (a copy of the row below)
        if t < buildPlaySel.count { buildPlaySel[t] = cur }             // the cursor row becomes this column's active rung
        if t < buildPlayColOn.count { buildPlayColOn[t] = true }        // …and starts playing immediately
        buildVoiceOwner = .none; au?.clearColourSolo()                  // the play layer is the voice
        buildSelectPlayColumn(t)                                        // reflect it in the machine + deselect the source
        buildPublishScene()
    }
    // LONG-PRESS a SELECT top button → copy the currently-selected cell onto the PLAY grid at column t's SELECTED RUNG
    // (default row 1). Writes ONLY the play grid's OWN store (buildPlayCells) — NOT the shared buildStagingCells — so it
    // appears at the play grid's selected position + column t's bottom readout, and NEVER touches the part-grid side
    // buttons (the bug this fixes). Mints a colour carrying the source chain + register home; a confirm flash.
    private func roomsAssignPlayColumn(_ t: Int) {
        guard t >= 0 && t < 8 else { return }
        if roomsRoom == .part { roomsFlattenPartToPlay(t); return }           // PART page → FLATTEN the part into a multi-step pass (Paul 2026-08-30)
        guard let hit = buildGridSelStampSource() else { return }
        buildRecordUndo()                                                    // the play grid is now in the undo snapshot → ferrying is undoable (2026-08-31)
        buildGridSelStampRow = nil; buildGridSelStampAt = nil                 // hand the rising fill over to the confirm flash
        buildPlayColLen[t] = 1; buildPlayColSteps[t] = []; buildPlayColRate[t] = nil   // a SELECT single-cell ferry clears any prior multi-step pass on this column
        buildPlayColStepRecv[t] = []; buildPlayColStepEmit[t] = []
        let r = max(0, min(7, buildPlayFerryRow))   // the FERRY CURSOR row (▲▼-chosen) — Paul 2026-08-31
        let y = buildNewTabColour(t, machine: hit.chain, transpose: hit.transpose, hex: playHexes[t % playHexes.count])   // a colour carrying the chain + register home, in the PLAY grid's DUSK hue per column (Paul 2026-08-30)
        buildPlayCells[t][r] = y
        let io = roomsStampSourceIO()                                        // COPY the source's I/O (Paul 2026-08-29: "play will have the copied settings")
        if t < buildPlayColRecv.count { buildPlayColRecv[t] = io.recv }
        if t < buildPlayColEmit.count { buildPlayColEmit[t] = io.emit }
        if t < buildPlaySel.count { buildPlaySel[t] = r }                    // make the assigned rung the selected one (so it shows on play)
        // FERRYING TO PLAY STARTS IT (Paul 2026-08-30): start this play column, and STOP the select grid's audition (its
        // extra voice) — parallel to the select→part ferry, which switches playback to the held target. The play layer
        // then sounds via its persistent voice; the previously-auditioning library cell goes quiet.
        if t < buildPlayColOn.count { buildPlayColOn[t] = true }
        buildVoiceOwner = .none; au?.clearColourSolo()                       // the SELECT/PART shared audition stops — the play layer is the voice now
        buildSelectPlayColumn(t)                                             // the FERRIED play cell becomes THE selection (deselects the source; machine strip + I/O toggles reflect it — Paul 2026-08-30)
        buildGridSelStampFlashRow = t + 8; buildGridSelStampFlashAt = Date()   // the white→fade confirm (offset space, so no side-button collision)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.55) { if buildGridSelStampFlashRow == t + 8 { buildGridSelStampFlashRow = nil; buildGridSelStampFlashAt = nil } }
        buildPublishScene()                                                  // republish: the started column plays, the audition is off
    }
    // FLATTEN THE PART → a multi-step play pass (Paul 2026-08-30). Long-pressing a play ferry on the PART page captures the
    // current part's SEQUENCE — its per-column selected-rung colours across the loop length — onto play column t as an N-step
    // pass (playColSteps/Len/Rate). The play layer then sweeps + loops that pass at the part's tempo, disjoint from the part
    // rows. v1: one output (the part's default door + emitters) for the whole pass; per-step I/O is a follow-up.
    private func roomsFlattenPartToPlay(_ t: Int) {
        let len = max(1, min(Snap.maxCols, buildPartLen ?? Snap.cols))   // §E: flatten up to 16 steps
        let steps: [String?] = (0..<len).map { c in
            let rr = c < buildStagingSel.count ? buildStagingSel[c] : -1
            return (rr >= 0 && c < buildStagingCells.count && rr < buildStagingCells[c].count) ? buildStagingCells[c][rr] : nil
        }
        guard let rep = steps.compactMap({ $0 }).first else { return }       // nothing selected in the part → nothing to flatten
        buildRecordUndo()                                                    // flattening a part onto a play column is undoable (2026-08-31)
        buildGridSelStampRow = nil; buildGridSelStampAt = nil
        let r = max(0, min(7, buildPlayFerryRow))   // the FERRY CURSOR row (▲▼-chosen) — Paul 2026-08-31
        buildPlayColSteps[t] = steps
        buildPlayColLen[t] = len
        buildPlayColRate[t] = buildPartRate                                  // the pass plays at the part's own tempo
        // PER-STEP I/O (Paul 2026-08-30): each step keeps the door + emitters of the part ROW (rung) it flattened from, so a
        // part whose columns route to different doors/emitters keeps that routing on the play pass.
        buildPlayColStepRecv[t] = (0..<len).map { c in
            let rung = c < buildStagingSel.count ? buildStagingSel[c] : -1
            return rung >= 0 ? buildRowReceiverResolved(rung) : buildSelReceiver
        }
        buildPlayColStepEmit[t] = (0..<len).map { c in
            let rung = c < buildStagingSel.count ? buildStagingSel[c] : -1
            return rung >= 0 ? buildRowEmittersResolved(rung) : (buildDefaultEmitters)
        }
        buildPlayCells[t][r] = buildNewTabColour(t, machine: buildColourChain(rep), hex: playHexes[t % playHexes.count])   // a DUSK representative (carries the first step's chain) so the play column reads dusk, not the part's vivid hue (Paul 2026-08-30)
        buildPlaySel[t] = r
        buildPlayColRecv[t] = buildSelReceiver                               // the column DEFAULT (the ferry dot/drift tint + any rest-step fallback)
        buildPlayColEmit[t] = buildDefaultEmitters
        buildPlayColOn[t] = true                                            // start it
        buildVoiceOwner = .none; au?.clearColourSolo()                      // the part/chain shared audition stops — the play column now carries the sequence (no doubling)
        buildSelectPlayColumn(t)
        buildGridSelStampFlashRow = t + 8; buildGridSelStampFlashAt = Date()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.55) { if buildGridSelStampFlashRow == t + 8 { buildGridSelStampFlashRow = nil; buildGridSelStampFlashAt = nil } }
        buildPublishScene()
    }
    // The I/O the ferry SOURCE is currently playing through (Paul 2026-08-29: the play cell copies the settings). An aimed
    // side-row source uses that row's resolved door/emitters; otherwise the SELECT audition's door + emitters.
    private func roomsStampSourceIO() -> (recv: Int, emit: Set<Bus>) {
        if let s = buildGridSelStampSourceRow, buildRowColour(s) != nil {
            return (buildRowReceiverResolved(s), buildRowEmittersResolved(s))
        }
        return (buildSelReceiver, buildDefaultEmitters)
    }
    // ── THE SELECT GRID UNIT — the library grid + its edge selectors + the ▲PLAY sliver, in ONE box. The part↔select
    // SEAM has moved OUT to the far side of the page (roomsSeamColumn); the grid reflows to use the full width. (Paul 2026-08-28)
    @ViewBuilder func roomsSelectGridUnit(m: RoomsMetrics) -> some View {
        GeometryReader { g in
            let gap = RoomsMetrics.gap, pad = RoomsMetrics.pad                 // heights from the shared lattice (m); width per-view
            let cw = max(6, (g.size.width - 2 * pad - 9 * gap) / 10)           // 10 cols (LEFT page rail + 8 interior + right side button)
            let ch = m.ch, navH = m.navH
            let interiorW = cw * 8 + gap * 7
            let interiorH = m.interiorH
            let leftInset = cw + gap                                        // the left page rail → the interior's left edge
            VStack(alignment: .leading, spacing: gap) {
                HStack(spacing: 0) {                                        // ▲PLAY over the interior columns (past the left rail)
                    Color.clear.frame(width: leftInset)
                    roomsPlayNavSliver(width: interiorW, height: navH)
                }
                VStack(spacing: gap) {
                    HStack(spacing: gap) {                                   // ▲▼ row cursor + PLAY-ferry row + right corner
                        roomsPlayFerryRowSelector().frame(width: cw, height: ch)
                        ForEach(0..<8, id: \.self) { c in roomsPlayFerry(c).frame(width: cw, height: ch) }   // the PLAY-ferry buttons (select → play)
                        buildStopAllButton().frame(width: cw, height: ch)   // STOP — the select grid's top-right corner (Paul 2026-08-31)
                    }
                    ForEach(0..<8, id: \.self) { r in                        // LEFT page rail + interior cells + right side buttons
                        HStack(spacing: gap) {
                            roomsSelectPage(r).frame(width: cw, height: ch)  // the PAGE selector (loads a page of presets)
                            ForEach(0..<8, id: \.self) { c in roomsSelectGridCell(r * 8 + c).frame(width: cw, height: ch) }
                            roomsSideButton(r).frame(width: cw, height: ch)
                        }
                    }
                }
                .overlay(alignment: .topLeading) {                          // the processor card over the interior 8×8 (past the left rail)
                    roomsProcessorCardAt(x: 0, y: ch + gap, w: leftInset + interiorW, h: interiorH)   // extend LEFT over the page-select rail (Paul 2026-08-29)
                }
            }
            .padding(pad)
            .background(RoundedRectangle(cornerRadius: 12).fill(Color.white.opacity(0.05)))
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.clear, lineWidth: 0))
            .onChange(of: buildGridSelSel) { new in if new != nil { buildSelectGreyAlt.toggle() } }   // a NEW select pick → shift the bright machine grey (Paul 2026-09-01)
        }
    }
    // THE CATEGORY RAIL (Paul 2026-08-29) — the SELECT grid's LEFT buttons are FIXED processor-type categories; tapping one
    // filters the library grid to presets containing that processor. ONE is always selected (default 0 = ARP).
    var roomsSelectCategories: [(label: String, type: ProcessorType)] {
        [("ARP", .arp), ("RIFF", .riff), ("EUCLID", .euclid), ("RATCHET", .ratchet),
         ("CHANCE", .chance), ("HARMONY", .harmonize), ("MOD/CC", .mod), ("GATE", .passgate)]
    }
    private func buildGridSelCategoryType(_ c: Int) -> ProcessorType { roomsSelectCategories[max(0, min(roomsSelectCategories.count - 1, c))].type }
    // Recompute the CURRENT category's matching library indices (an entry matches if its chain contains the category's
    // processor). Called on a category change + when the library loads. Cheap O(lib) scan, cached in buildGridSelCatIndices.
    func buildGridSelRecomputeCategory() {
        let ty = buildGridSelCategoryType(buildGridSelPage)
        buildGridSelCatIndices = buildGridSelLib.indices.filter { buildGridSelLib[$0].types.contains(ty) }
    }
    @ViewBuilder private func roomsSelectPage(_ r: Int) -> some View {
        let cat = r < roomsSelectCategories.count ? roomsSelectCategories[r].label : ""
        let selected = buildGridSelPage == r
        RoundedRectangle(cornerRadius: 5).fill(selected ? buildCyan.opacity(0.9) : Color.white.opacity(0.10))
            .overlay(RoundedRectangle(cornerRadius: 5).stroke(selected ? Color.white.opacity(0.8) : buildEdge, lineWidth: selected ? 2 : 1))
            .overlay(Text(cat).font(.system(size: 8, weight: .heavy, design: .monospaced)).foregroundColor(selected ? .black : .white.opacity(0.75)).lineLimit(1).minimumScaleFactor(0.5).padding(.horizontal, 1))
            .contentShape(Rectangle())
            .onTapGesture { if buildGridSelPage != r && r < roomsSelectCategories.count { buildGridSelSetPage(r) } }
    }
    // Switch the SELECT grid to a new CATEGORY: stop the transient audition, drop cell-copy overrides + the selection,
    // set the category, recompute its matching library slice + the drifting faces.
    private func buildGridSelSetPage(_ c: Int) {
        buildGridSelStopAudition()
        buildGridSelOverride = [:]; buildGridSelSel = nil
        buildGridSelPage = c
        buildGridSelRecomputeCategory()
        buildGridSelComputeCellRolls()
    }
    // The grid's cell WIDTH for a given box width — so the caller can size the far-edge seam column to 50% of a cell,
    // matching the old in-grid seam. SELECT = 10 cols (left page rail + 8 + right side), PART = 10 cols. (Paul 2026-08-29)
    func roomsGridCellW(_ boxW: CGFloat, cols: Int) -> CGFloat { max(6, (boxW - 2 * 3 - CGFloat(cols - 1) * 3) / CGFloat(cols)) }
    // The empty-box PROCESSOR SELECTOR window (the catalog) — the existing modal picker, rendered in the rooms shell. (Paul 2026-08-28)
    @ViewBuilder func roomsProcessorPicker(size: CGSize) -> some View {
        if let slot = buildAddSlot { buildProcessorPicker(slot: slot, size: size) }
    }
    // The MIDI config CONTENT, restyled INLINE for the mixer's stage-2 full page (below the selected control) — reuses
    // the existing per-door / per-emitter sections from the config sheets, minus the modal chrome. (Paul 2026-08-28)
    @ViewBuilder func roomsMixerConfig(_ k: Int) -> some View {
        if k < 4 {                                                          // IN A–D → the per-door section (channels · oct · range · mode)
            let recvs = au?.uiReceivers() ?? []
            buildDoorSection(k, r: k < recvs.count ? recvs[k] : Receiver())
        } else {                                                           // OUT A–D → the per-emitter stamp channel + live dot
            let e = k - 4, chans = au?.uiBusChannels() ?? [1, 2, 3, 4]
            buildEmitterOutRow(e, chan: e < chans.count ? chans[e] : e + 1)
        }
    }
    // One SELECT-grid interior cell (0…63): the real library face + tap-audition, plus a LONG-PRESS to copy the active
    // source onto it as a new instance (cell-to-cell). buildGridSelCell itself is untouched (old BUILD unaffected). (Paul 2026-08-28)
    @ViewBuilder func roomsSelectGridCell(_ i: Int) -> some View {
        GeometryReader { cg in
            buildGridSelCell(i, w: cg.size.width, h: cg.size.height, greyUnlessSel: true, vPad: cg.size.height * 0.15)   // SELECT grid: grey-unless-selected + 15% roll padding (Paul 2026-08-29)
                .onLongPressGesture(minimumDuration: buildGridSelStampDur, maximumDistance: 44, perform: { roomsCopyToSelectCell(i) })
        }
    }
    // A SELECT-grid SIDE BUTTON (the row-select column) = a PART slot that holds a chain (the §4 shared exclusive column).
    // Reuses the grid selector's visual pieces (drift face + rising-white STAMP SWEEP) with NEW-INTERFACE gestures:
    //   TAP        = make this the ACTIVE selection (white border) + play/load its chain (reflected in the chain/IN/OUT
    //                panel) + arm it as a STAMP SOURCE when populated (buildGridSelStampSourceRow).
    //   LONG-PRESS = copy the active source (a browse CELL *or* another SIDE BUTTON) onto this slot — the rising white
    //                fill → white-fade CONFIRM revealing the part's pre-allocated colour (colourHexes[n]).
    // The stamp writes the shared part row, so the PART grid's slot + row light up too (one model, two rooms). (Paul 2026-08-28)
    @ViewBuilder func roomsSideButton(_ n: Int, part: Bool = false) -> some View {
        GeometryReader { g in roomsSideChip(n, height: g.size.height, part: part) }
    }
    @ViewBuilder private func roomsSideChip(_ n: Int, height: CGFloat, part: Bool) -> some View {
        let populated = buildRowColour(n) != nil                          // this slot/row holds a chain
        let active = buildGridSelStampSourceRow == n                      // THE active side button
        let mHue = Color(hex: colourHexes[n % 16])                        // MACHINE identity (the row's predetermined colour)
        let eHue = emitterHue(buildRowEmittersResolved(n))               // EMITTER colour (routing)
        let selectedVis = active && populated
        // IS THIS ROW'S CELL SOUNDING? PART grid → the SEQUENCER's active rung; SELECT→part ferry → the AIMED audition
        // (the select page's extra voice; the sequenced part does NOT run on select).
        let ec = max(0, min(7, d.effColumn))
        let playing = populated && (part
            ? (buildStagingPlaying && ec < buildStagingSel.count && buildStagingSel[ec] == n)
            : (buildGridSelStampSourceRow == n && buildDisplayVoice == .chain))
        // THREE STATES (Paul 2026-08-30): NULL (dark + thin edge) · POPULATED (machine-hue frame + a calm fingerprint) ·
        // PLAYING (bright machine frame + an EMITTER glow + REAL drifting notes). Machine = the frame, emitter = the drift
        // tint + a corner dot. When the select→part ferry is the AIMED/auditioning one, it now shows the audition's LIVE
        // emitted notes (#5, Paul 2026-08-30): the audition parks on buildChainAuditionRow (col 0), so its strike feed lives
        // at that engine index — read it here. Idle → the static CHAIN fingerprint (buildGridSelRowRoll) as the calm tell.
        let liveIdx = (!part && playing) ? buildChainAuditionRow : nil    // this ferry is auditioning → its live-strike engine row (col 0)
        RoundedRectangle(cornerRadius: 5).fill(buildCell)                // DARK STAGE
            .frame(height: height)
            .overlay(RoundedRectangle(cornerRadius: 5).fill(mHue.opacity(populated ? (playing ? 0.24 : 0.10) : 0)))   // faint MACHINE wash
            .overlay { if populated && !part {
                ZStack {
                    // BASE: the chain's fingerprint. While PLAYING it DRIFTS (a guaranteed "this is running" tell that covers the
                    // edges where the live strike feed is momentarily empty or the audition row shifted — Paul 2026-08-30, the
                    // "subsequent copies didn't animate" bug); idle → a calm static fingerprint.
                    buildGridSelDriftFace(buildGridSelRowRoll[n] ?? [], animated: playing, tint: eHue)
                        .padding(.vertical, 3).padding(.horizontal, 2).opacity(playing ? 0.45 : 0.55)
                    // REAL audition notes ride ON TOP when this ferry's live-strike row is known (brighter, the honest signal).
                    if let li = liveIdx { buildNoteSweep(idx: li, active: true, id: buildRowColour(n), emitter: buildRowEmittersResolved(n)) }
                }
            } }
            .overlay(alignment: .bottom) { buildGridSelStampSweep(n, height: height, hue: mHue) }   // rising fill + the COMMIT colour-bloom (reveal) in this row's hue
            .clipShape(RoundedRectangle(cornerRadius: 5))
            .overlay(RoundedRectangle(cornerRadius: 5).stroke(populated ? mHue.opacity(playing ? 1.0 : (selectedVis ? 0.9 : 0.5)) : buildEdge,
                                                              lineWidth: playing ? 3 : (selectedVis ? 2.5 : (populated ? 2 : 1))))   // MACHINE frame: dim → BRIGHT when PLAYING
            .overlay { if buildSelectMode && populated { RoundedRectangle(cornerRadius: 5).stroke(Color.white, lineWidth: 2.5) } }   // SELECT MODE: light white — tap to focus (Paul 2026-08-31)
            .overlay(alignment: .topTrailing) { if populated { Circle().fill(eHue).frame(width: 5, height: 5).padding(3) } }   // EMITTER dot — routing, always visible when populated
            .overlay {
                if part {                                                // PART rail → the slot NUMBER in the machine hue
                    Text("\(n + 1)").font(.system(size: min(13, height * 0.42), weight: .heavy, design: .monospaced)).foregroundColor(mHue.opacity(populated ? 1.0 : 0.5))
                } else {                                                 // SELECT→part ferry → a small PLAY/STOP status glyph in the machine hue (over a calm fingerprint)
                    Image(systemName: playing ? "stop.fill" : "play.fill").font(.system(size: min(11, height * 0.4), weight: .black)).foregroundColor(populated ? mHue : buildDim).opacity(playing ? 0.85 : 1.0)
                }
            }
            .shadow(color: playing ? eHue.opacity(0.7) : .clear, radius: playing ? 5 : 0)   // PLAYING → an EMITTER-coloured glow (the "this is alive" tell)
            .contentShape(Rectangle())
            .onTapGesture {
                if buildSelectMode { if let cid = buildRowColour(n) { buildSelectID(cid) }; buildSelectMode = false }   // SELECT MODE: focus this row's colour, then end SELECT (Paul 2026-08-31)
                else { part ? roomsTapPartSide(n) : roomsTapSide(n) }
            }
            .onLongPressGesture(minimumDuration: buildGridSelStampDur, maximumDistance: 44,
                                pressing: { p in buildGridSelStampPressing(n, p) }, perform: { roomsStampFire(n, part: part) })
    }
    // ROOMS long-press stamp: copy the active source onto side button n, then make the TARGET the active selection
    // (Paul 2026-08-28) — the copied slot becomes the currently-selected cell + reflects its chain. (Old BUILD's row
    // chips keep buildGridSelStampFire directly, so their multi-stamp source is untouched.)
    private func roomsStampFire(_ n: Int, part: Bool) {
        let did = buildGridSelCanStamp
        buildGridSelStampFire(n)
        guard did else { return }
        buildRoomsSetActiveSide(n)                                       // the TARGET side button is now the active selection
        if buildRowColour(n) != nil { part ? buildSelectRow(n) : buildGridSelAimRow(n); buildTapColourTab(n) }   // reflect its chain (+ on PART, play that row)
    }
    // TAP a SELECT side button — a POPULATED one becomes the active selection + stamp source (and auditions its chain); an
    // EMPTY one only AIMS (targets a future stamp) — it must not read as selected when the user hasn't committed. (Paul 2026-08-29)
    private func roomsTapSide(_ n: Int) {
        if buildFerryHeld { buildFerryHeld = false; return }            // released-early hold → don't steal focus / re-audition the playing cell
        buildGridSelAimRow(n)                                            // aim this row as the stamp/commit target (+ audition if populated)
        if buildRowColour(n) != nil { buildRoomsSetActiveSide(n) }      // only a POPULATED button becomes THE active selection + copy source
    }
    // ── THE PART GRID UNIT (rooms) — the old-gui part/staging grid + its nav slivers, ALL in ONE box (Paul 2026-08-28):
    // a LEFT seam sliver (◂ → SELECT, beside the left side buttons) · LEFT row-slots (the selection) · an 8×8 interior
    // (one rung/col + playhead) · a RIGHT row-selector rail · a top track-head row · a ▲PLAY sliver above it (over the
    // interior cols). NO loop keys, no padding between the nav slivers and the grid.
    // PART-GRID PROPORTIONS (Paul 2026-09-01): the interior 8-row grid is SHRUNK below the header (ferry row + ▲PLAY nav +
    // ▲▼/STOP stay their size) to free a LARGE PANEL below (the future macro band / part surface). Tunable — device-owed.
    static let roomsPartInteriorFraction: CGFloat = 0.5   // interior cell height = this × the lattice cell height
    // §E 16-STEP (Paul 2026-09-02): the part's ACTIVE WIDTH = its loop length (buildPartLen, 1…16; nil ⇒ the 8-wide
    // default). The grid renders this many STEP columns (cells shrink to fit), the engine loops them (rowLength).
    var buildPartCols: Int { max(1, min(Snap.maxCols, buildPartLen ?? Snap.cols)) }
    @ViewBuilder func roomsPartGrid(m: RoomsMetrics) -> some View {
        GeometryReader { g in
            let gap = RoomsMetrics.gap, pad = RoomsMetrics.pad               // heights come from the shared lattice (m); width stays per-view
            let cols = buildPartCols                                         // §E: the part-grid STEP count = the active width (8 or up to 16)
            let cw = max(6, (g.size.width - 2 * pad - CGFloat(cols + 1) * gap) / CGFloat(cols + 2))   // leftRail + `cols` interior + rightRail → FILLS the width
            let ch = m.ch, navH = m.navH
            let partCH = max(6, ch * DiagView.roomsPartInteriorFraction)     // SHRUNK interior cell height (the header rows keep `ch`)
            let interiorW = cw * CGFloat(cols) + gap * CGFloat(cols - 1)
            let interiorH = partCH * 8 + gap * 7                            // 8 rungs at the shrunk height
            let leftInset = cw + gap                                        // leftRail → the interior's left edge
            // The lower region = everything under the ferry row. FIXED heights that sum EXACTLY to the column (like the
            // SELECT grid — no maxHeight:.infinity, which floated the content): [interior] + [piano roll] + [macro].
            let lowerH = max(interiorH, g.size.height - 2 * pad - navH - gap - ch - gap)
            let pianoH = partCH * 2 + gap                                   // the piano-roll strip = 2 cells (halved)
            let macroH = max(0, lowerH - interiorH - pianoH - 2 * gap)      // the macro section fills the remainder EXACTLY
            VStack(alignment: .leading, spacing: gap) {
                HStack(spacing: 0) {                                        // ▲PLAY over the interior columns (past the left rail)
                    Color.clear.frame(width: leftInset)
                    roomsPlayNavSliver(width: interiorW, height: navH)
                }
                HStack(spacing: gap) {                                      // the PLAY-ferry row — stays FULL SIZE (Paul: ferry/▲▼/STOP unchanged)
                    roomsPlayFerryRowSelector().frame(width: cw, height: ch) //   the ▲▼ row cursor (shared with the select grid's)
                    ForEach(0..<cols, id: \.self) { c in roomsPlayFerry(c).frame(width: cw, height: ch) }
                    Color.clear.frame(width: cw)
                }
                ZStack(alignment: .topLeading) {                           // the lower region: shrunk grid on top, the LARGE PANEL beneath
                    VStack(alignment: .leading, spacing: gap) {
                        HStack(alignment: .top, spacing: gap) {             // body: left rail | interior+playhead | right rail (all at partCH)
                            VStack(spacing: gap) { ForEach(0..<8, id: \.self) { n in roomsSideButton(n, part: true).frame(width: cw, height: partCH) } }
                            ZStack(alignment: .topLeading) {
                                VStack(spacing: gap) { ForEach(0..<8, id: \.self) { r in HStack(spacing: gap) { ForEach(0..<cols, id: \.self) { c in roomsPartCell(c, r, w: cw, h: partCH) } } } }
                                roomsPartPlayhead(colW: cw, gap: gap, height: interiorH)
                            }
                            VStack(spacing: gap) { ForEach(0..<8, id: \.self) { n in roomsPartRightRail(n).frame(width: cw, height: partCH) } }
                        }
                        // SECTION 1 — the PIANO ROLL strip: aligned UNDER the interior columns, 4 cells tall. A STATIC MOCK of
                        // the merged-lane notation (the real view will fold every row's output into one "what will play" roll).
                        HStack(spacing: 0) {
                            Color.clear.frame(width: leftInset)
                            roomsPartPianoRoll(cols: cols, colW: cw, gap: gap).frame(width: interiorW, height: pianoH)   // 2 cells tall (halved, Paul 2026-09-01)
                        }
                        // SECTION 2 — the MACRO section: its header bars (the 4 tabs) + panel, filling the rest. Mocked (the
                        // BIND/PLAY/PUNCH/SPAN engine lands overnight — M3–M6 over the proven M1/M2 fold).
                        roomsPartMacroSection().frame(maxWidth: .infinity).frame(height: macroH)
                    }
                    // the processor-editor card, when open, covers the WHOLE lower region (grid + roll + macro) so it keeps its room
                    roomsProcessorCardAt(x: leftInset, y: 0, w: interiorW + gap + cw, h: lowerH)
                }
            }
            .padding(pad)
            .background(RoundedRectangle(cornerRadius: 12).fill(Color.white.opacity(0.05)))
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.clear, lineWidth: 0))
        }
    }
    // SECTION 1 — THE PIANO ROLL (Paul 2026-09-01): a STATIC MOCK for now. Intended as a read-only notation view that MERGES
    // the notes of every lane (row) into one "what will play" roll, its x-axis aligned to the part grid's step columns above.
    // Draws a fixed, pleasant phrase over faint step gridlines; not data-driven yet.
    @ViewBuilder func roomsPartPianoRoll(cols: Int, colW: CGFloat, gap: CGFloat) -> some View {
        GeometryReader { g in
            let lanes = 14                                   // pitch lanes shown (mock)
            let laneH = g.size.height / CGFloat(lanes)
            let stepW = colW + gap                           // the SAME column pitch as the grid above → the steps line up
            // a fixed merged-looking phrase: (startStep, pitchLane-from-top, lengthInSteps)
            let notes: [(Int, Int, Int)] = [(0, 9, 2), (0, 6, 2), (0, 2, 4), (2, 10, 1), (3, 8, 1),
                                            (4, 11, 2), (4, 5, 2), (4, 1, 4), (6, 9, 1), (7, 7, 1)]
            ZStack(alignment: .topLeading) {
                RoundedRectangle(cornerRadius: 6).fill(Color.black.opacity(0.20))
                ForEach(1..<max(2, cols), id: \.self) { c in                     // step gridlines (aligned to the grid columns)
                    Rectangle().fill(Color.white.opacity(0.06)).frame(width: 1).offset(x: CGFloat(c) * stepW)
                }
                ForEach(Array(notes.enumerated()), id: \.offset) { (_, n) in     // the merged notes (static)
                    RoundedRectangle(cornerRadius: 2).fill(roomsAmber.opacity(0.75))
                        .frame(width: max(3, CGFloat(n.2) * stepW - 2), height: max(2, laneH - 2))
                        .offset(x: CGFloat(n.0) * stepW + 1, y: CGFloat(n.1) * laneH + 1)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 6))
            .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.white.opacity(0.10), lineWidth: 1))
        }
    }
    // SECTION 2 — THE AUTO FLOW (Paul 2026-09-01, rev 2): AUTO-lane + PROCESSOR selector buttons over a PARAMETER TABLE
    // (each param + BEFORE/AFTER — a lane alters MULTIPLE params as a GROUP), + a right stack MERGE · RATE · APPLY. Macros
    // dropped (v2). Per-colour lanes. FLAGGED next stage: the APPLY grid-paint of the extent + the per-cell engine fold.
    func buildAutoLanesFor(_ cid: String) -> [AutoLane] {
        let a = buildAutoLanes[cid]?.lanes ?? []
        return (0..<5).map { $0 < a.count ? a[$0] : AutoLane() }
    }
    // The ACTIVE lane of the FOCUSED colour (−1 = NONE). Per-colour (each colour's automation is independent).
    func buildAutoActive() -> Int { buildAutoLanes[ddSelectedColourID ?? ""]?.activeLane ?? -1 }
    func buildAutoSetActive(_ i: Int) {
        let cid = ddSelectedColourID ?? ""; guard !cid.isEmpty else { return }
        var pa = buildAutoLanes[cid] ?? PartAutoColour()
        if pa.lanes.count < 5 { pa.lanes += Array(repeating: AutoLane(), count: 5 - pa.lanes.count) }
        pa.activeLane = i; buildAutoLanes[cid] = pa
        buildPublishScene()   // P3: selecting a lane ENABLES it → republish so it plays immediately
    }
    func buildSetAutoLane(_ mutate: (inout AutoLane) -> Void) {
        let cid = ddSelectedColourID ?? ""; guard !cid.isEmpty else { return }
        var pa = buildAutoLanes[cid] ?? PartAutoColour()
        if pa.lanes.count < 5 { pa.lanes += Array(repeating: AutoLane(), count: 5 - pa.lanes.count) }
        let li = pa.activeLane >= 0 ? pa.activeLane : 0
        mutate(&pa.lanes[max(0, min(4, li))]); buildAutoLanes[cid] = pa
        buildPublishScene()   // P3: any lane edit (param/machine/extent) republishes → plays live
    }
    // THE AUTO FLOW (Paul 2026-09-01, rev 2): two selector buttons (AUTO lane · PROCESSOR) over a PARAMETER TABLE — every
    // param + its BEFORE/AFTER, so a lane alters MULTIPLE params as a GROUP — with a right-side stack MERGE · RATE · APPLY.
    // THE AUTO FLOW (Paul 2026-09-01, rev 3 — IMMEDIATE PUNCH): a thin selector — AUTO 1–5 · MACHINE · PARAM (pre-mapped
    // useful default) — then you PUNCH values straight onto the main part grid (drag a cell = its value for that param),
    // felt with the fewest steps. Tap a lane to arm; the grid becomes a value canvas for the selected colour's cells.
    // (before/after/merge/span/apply all dropped.) FLAGGED next: bake the punched per-cell values into the render (audible).
    @ViewBuilder func roomsPartMacroSection() -> some View {
        let cid = ddSelectedColourID ?? ""
        let chain = buildFocusedChain()
        let active = buildAutoActive()
        let lanes = buildAutoLanesFor(cid)
        let lane = lanes[max(0, min(4, active))]
        let procIdx = chain.isEmpty ? 0 : min(lane.slot, chain.count - 1)
        let params = chain.isEmpty ? [] : macroParamsForProcessor(chain[procIdx].type)
        let paramKey = chain.isEmpty ? "" : autoResolvedParamKey(lane: lane, type: chain[procIdx].type, params: params)
        let param = params.first(where: { $0.key == paramKey })
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 0) {                                              // THE TAB STRIP: NONE · AUTO 1–5 (span) · CLEAR (separate, right)
                autoTab("NONE", on: active < 0, dot: false) { buildAutoSetActive(-1) }.frame(maxWidth: .infinity)   // NONE = disabled (left)
                ForEach(0..<5, id: \.self) { i in
                    autoTab("AUTO \(i + 1)", on: active == i, dot: !lanes[i].cells.isEmpty) { buildAutoSetActive(i) }   // select = ENABLE this lane (plays immediately)
                        .frame(maxWidth: .infinity)                           // the five tabs SPAN the header width
                }
                autoChip("CLEAR", on: false, dot: false, wide: true, red: true) { if active >= 0 { buildSetAutoLane { $0.cells = [] } } }   // CLEAR — distinctly separate, right
                    .opacity(active >= 0 && !lane.cells.isEmpty ? 1 : 0.35)
                    .padding(.leading, 8)
            }
            if active < 0 {                                                  // NONE → hide the controls entirely (a calm invitation)
                macroHint("Automation off — pick an AUTO tab to sweep a parameter across the grid").frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if chain.isEmpty {
                macroHint("add a machine to this colour").frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                HStack(spacing: 4) {                                          // MACHINE — the chain's stages (direct)
                    macroColHead("MACHINE").frame(width: 58, alignment: .leading)
                    ScrollView(.horizontal, showsIndicators: false) { HStack(spacing: 4) {
                        ForEach(Array(chain.enumerated()), id: \.offset) { (i, s) in
                            autoChip(buildProcLabel(s), on: i == procIdx, dot: false, wide: true) { buildSetAutoLane { $0.slot = i; $0.param = ""; $0.lo = nil; $0.hi = nil } }   // new machine → reset the sweep
                        }
                    } }
                }
                HStack(spacing: 4) {                                          // PARAM — pre-mapped useful default leads; tap to change
                    macroColHead("PARAM").frame(width: 58, alignment: .leading)
                    ScrollView(.horizontal, showsIndicators: false) { HStack(spacing: 4) {
                        ForEach(params, id: \.key) { p in
                            autoChip(p.label, on: p.key == paramKey, dot: false, wide: true) { buildSetAutoLane { $0.param = p.key; $0.lo = nil; $0.hi = nil } }   // new param → reset the sweep to its default range
                        }
                    } }
                }
                if let p = param {                                            // THE SWEEP — FROM → TO faders (the "before/after" the ramp travels between)
                    let full = BuildSceneLogic.autoParamFullRange(p.kind)
                    let sub = BuildSceneLogic.autoSubRange(paramKey, p.kind)
                    HStack(spacing: 8) {
                        macroColHead("SWEEP").frame(width: 58, alignment: .leading)
                        autoRangeFader("FROM", value: lane.lo ?? sub.lo, lo: full.lo, hi: full.hi, p: p) { v in buildSetAutoLane { $0.lo = v } }
                        autoRangeFader("TO",   value: lane.hi ?? sub.hi, lo: full.lo, hi: full.hi, p: p) { v in buildSetAutoLane { $0.hi = v } }
                    }
                    Text("tap cells on the grid — the sweep plays FROM→TO across them (live)")
                        .font(.system(size: 9, weight: .bold, design: .monospaced)).foregroundColor(roomsAmber).lineLimit(1)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                Spacer(minLength: 0)
            }
        }.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
    // §AUTO TAB (Paul 2026-09-02): the AUTO 1–5 + NONE selector reads as TABS — a top-rounded cell with a bottom ACCENT
    // underline (amber when active, a faint baseline when not), sitting over the controls it reveals. The active-cell dot
    // marks a lane that already holds an extent.
    @ViewBuilder private func autoTab(_ t: String, on: Bool, dot: Bool, _ tap: @escaping () -> Void) -> some View {
        VStack(spacing: 0) {
            HStack(spacing: 4) {
                if dot { Circle().fill(roomsAmber).frame(width: 4, height: 4) }
                Text(t).font(.system(size: 10, weight: on ? .heavy : .semibold, design: .monospaced))
                    .foregroundColor(on ? roomsAmber : .white.opacity(0.5)).lineLimit(1)
            }
            .frame(maxWidth: .infinity).frame(height: 22)
            .background(UnevenRoundedRectangle(topLeadingRadius: 5, topTrailingRadius: 5).fill(on ? roomsAmber.opacity(0.16) : Color.white.opacity(0.04)))
            Rectangle().fill(on ? roomsAmber : Color.white.opacity(0.12)).frame(height: on ? 2 : 1)   // the tab underline / baseline
        }
        .contentShape(Rectangle()).onTapGesture(perform: tap)
    }
    // §SWEEP FADER (Paul 2026-09-02): a compact FROM/TO endpoint fader — drag anywhere to set the value across the param's
    // FULL range; the label reads the value formatted per the param kind. (NumPair/FineSlider are private to GridUI.)
    @ViewBuilder private func autoRangeFader(_ label: String, value: Double, lo: Double, hi: Double, p: MacroControlParam, _ set: @escaping (Double) -> Void) -> some View {
        let span = max(1e-9, hi - lo)
        let frac = min(1, max(0, (value - lo) / span))
        VStack(alignment: .leading, spacing: 2) {
            Text(label).font(.system(size: 8, weight: .heavy, design: .monospaced)).tracking(1.5).foregroundColor(.white.opacity(0.42))
            GeometryReader { g in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 4).fill(Color.white.opacity(0.06))
                    RoundedRectangle(cornerRadius: 4).fill(roomsAmber.opacity(0.55)).frame(width: max(3, g.size.width * frac))
                    Text(autoFmt(value, p)).font(.system(size: 9, weight: .heavy, design: .monospaced)).foregroundColor(.white.opacity(0.9)).padding(.leading, 6)
                }
                .contentShape(Rectangle())
                .gesture(DragGesture(minimumDistance: 0).onChanged { gg in set(lo + min(1, max(0, gg.location.x / max(1, g.size.width))) * span) })
            }.frame(height: 24)
        }.frame(maxWidth: .infinity)
    }
    // Format a sweep-endpoint value for its param kind (continuous → 2dp for small ranges, else int; toggle → ON/OFF;
    // option → its label; stepper/mask → int).
    private func autoFmt(_ v: Double, _ p: MacroControlParam) -> String {
        switch p.kind {
        case .continuous(let lo, let hi): return (hi - lo) <= 2 ? String(format: "%.2f", v) : String(Int(v.rounded()))
        case .toggle: return v >= 0.5 ? "ON" : "OFF"
        case .option(let opts): let i = min(opts.count - 1, max(0, Int(v.rounded()))); return opts.indices.contains(i) ? opts[i] : "\(i)"
        case .stepper, .mask: return String(Int(v.rounded()))
        }
    }
    @ViewBuilder private func macroColHead(_ t: String) -> some View {
        Text(t).font(.system(size: 8.5, weight: .heavy, design: .monospaced)).tracking(2).foregroundColor(.white.opacity(0.32))
    }
    @ViewBuilder private func macroHint(_ t: String) -> some View {
        Text(t).font(.system(size: 10, design: .monospaced)).foregroundColor(.white.opacity(0.28)).frame(maxWidth: .infinity, alignment: .center)
    }
    @ViewBuilder private func autoChip(_ t: String, on: Bool, dot: Bool, wide: Bool, red: Bool = false, _ tap: @escaping () -> Void) -> some View {
        let accent = red ? buildRed : roomsAmber
        HStack(spacing: 4) {
            if dot { Circle().fill(roomsAmber).frame(width: 4, height: 4) }
            Text(t).font(.system(size: 10, weight: .bold, design: .monospaced)).foregroundColor(on ? .black : .white.opacity(0.6)).lineLimit(1)
        }
        .padding(.horizontal, wide ? 9 : 0).frame(minWidth: wide ? 0 : 26, minHeight: 24).frame(height: 24)
        .background(RoundedRectangle(cornerRadius: 5).fill(on ? accent : Color.white.opacity(0.06)))
        .overlay(RoundedRectangle(cornerRadius: 5).stroke(on ? accent : Color.white.opacity(0.12), lineWidth: 1))
        .contentShape(Rectangle()).onTapGesture(perform: tap)
    }
    // The useful default param for a processor (Paul 2026-09-01: "length for arp"). Falls to the lane's chosen param, else
    // the curated primary if present, else the first param. Curation mirrors the "order params by usefulness" intent.
    // The resolved param key for a lane — delegates to the SHARED pure logic (single source of truth, testable).
    private func autoResolvedParamKey(lane: AutoLane, type: ProcessorType, params: [MacroControlParam]) -> String {
        BuildSceneLogic.autoResolvedParamKey(type, laneParam: lane.param)
    }
    // The currently-ARMED punch context (nil ⇒ punch off): the param + its continuous range for the main-grid value canvas.
    func buildAutoArmedParam() -> (param: MacroControlParam, lo: Double, hi: Double)? {
        let active = buildAutoActive()
        guard active >= 0, let cid = ddSelectedColourID, !cid.isEmpty else { return nil }   // NONE (−1) = disabled
        let chain = buildFocusedChain(); guard !chain.isEmpty else { return nil }
        let lane = buildAutoLanesFor(cid)[max(0, min(4, active))]
        let procIdx = min(lane.slot, chain.count - 1)
        let params = macroParamsForProcessor(chain[procIdx].type)
        let key = autoResolvedParamKey(lane: lane, type: chain[procIdx].type, params: params)
        guard let p = params.first(where: { $0.key == key }) else { return nil }
        if case .continuous(let lo, let hi) = p.kind { return (p, lo, hi) }
        return (p, 0, 1)   // binary/discrete punch as 0…1 for now
    }
    // PUNCH = TOGGLE (Paul 2026-09-01): tap flips a cell in/out of the current lane's EXTENT.
    func buildAutoToggle(_ idx: Int) {
        buildSetAutoLane { if $0.cells.contains(idx) { $0.cells.remove(idx) } else { $0.cells.insert(idx) } }
    }
    func buildAutoInExtent(_ idx: Int) -> Bool {
        buildAutoLanesFor(ddSelectedColourID ?? "")[max(0, min(4, buildAutoActive()))].cells.contains(idx)
    }
    // The RANGE displayed across the extent: a cell's ramp position (0…1) by its rank among the toggled cells in
    // column→row order — so the toggled cells read as a ramp (the param sweeping low→high across the extent). nil = not in.
    func buildAutoRampFrac(_ idx: Int) -> Double? {
        let cells = buildAutoLanesFor(ddSelectedColourID ?? "")[max(0, min(4, buildAutoActive()))].cells
        guard cells.contains(idx) else { return nil }
        let ordered = cells.sorted { ($0 / Snap.rows, $0 % Snap.rows) < ($1 / Snap.rows, $1 % Snap.rows) }
        guard ordered.count > 1, let rank = ordered.firstIndex(of: idx) else { return 1 }
        return Double(rank) / Double(ordered.count - 1)
    }
    // SHARED grid-cell body (Paul 2026-08-30 colour language): a DARK neutral STAGE (so the vivid EMITTER drift pops) + a
    // faint MACHINE-hue identity WASH + the sweep + a MACHINE-hue FRAME that's dim normally and BRIGHT when this cell's
    // colour is the one FOCUSED in the machine strip/card (abundantly-clear cell↔machine pairing). The rung-SELECTED state
    // reads as a brighter wash + a medium frame (it's the one that plays — the drift already confirms it).
    @ViewBuilder private func roomsGridCellBody<S: View>(id: String?, selected: Bool, @ViewBuilder sweep: () -> S) -> some View {
        let mHue = id.flatMap { colourColor($0) } ?? buildCell            // the machine's identity hue
        // FOCUS = the machine shown in the strip/card. While a SELECT ferry is aimed the shown machine is the transient
        // gsAud, so ALSO pair the MIRRORED part row's REAL colour (#6, Paul 2026-08-30) — else that row's cells, whose id is
        // the real colour, never light focused during ferry editing even though the card is editing them.
        let mirrorCid = buildFerryMirrorRow.flatMap { buildRowColour($0) }
        let focused = id != nil && (id == ddSelectedColourID || (mirrorCid != nil && id == mirrorCid))
        RoundedRectangle(cornerRadius: 5).fill(buildCell)                // DARK STAGE
            .overlay(RoundedRectangle(cornerRadius: 5).fill(mHue.opacity(id == nil ? 0 : (selected ? 0.30 : 0.13))))   // faint machine-hue identity wash
            .overlay { sweep() }                                        // the EMITTER-coloured drift
            .clipShape(RoundedRectangle(cornerRadius: 5))
            .overlay(RoundedRectangle(cornerRadius: 5).stroke(id == nil ? buildEdge : mHue.opacity(focused ? 1.0 : (selected ? 0.7 : 0.4)),
                                                              lineWidth: focused ? 2.5 : (selected ? 2 : 1)))   // MACHINE-HUE FRAME: dim → BRIGHT on focus
            .overlay { if buildSelectMode && id != nil { RoundedRectangle(cornerRadius: 5).stroke(Color.white, lineWidth: 2.5) } }   // SELECT MODE: light white — tap to focus (Paul 2026-08-31)
    }
    // A PART interior cell — ONE RUNG PER COLUMN (old-gui buildStagingTap): tap selects that rung for its column; tap the
    // selected rung to UNSELECT it (that column falls silent). Dark stage + machine-hue frame; the selected rung brighter.
    @ViewBuilder private func roomsPartCell(_ c: Int, _ r: Int, w: CGFloat, h: CGFloat) -> some View {
        let id = (c < buildStagingCells.count && r < buildStagingCells[c].count) ? buildStagingCells[c][r] : nil   // Rooms4: bounds-safe against a ragged decoded doc
        let selected = (c < buildStagingSel.count ? buildStagingSel[c] : -1) == r   // the ONE selected rung for column c
        let idx = c * Snap.rows + r
        // AUTO PUNCH (Paul 2026-09-01): when a lane is armed, THIS colour's cells become a value canvas — a bottom-up
        // amber fill = the punched param value, and a vertical DRAG punches it. Other-colour cells dim (not this lane).
        let punch = buildAutoArmedParam()
        let punchable = punch != nil && id != nil && id == ddSelectedColourID
        let cellBody = roomsGridCellBody(id: id, selected: selected,
                          sweep: { buildNoteSweep(idx: idx, active: buildStagingPlaying && selected, id: id, emitter: buildRowEmittersResolved(r)) })
        if punchable {
            let ramp = buildAutoRampFrac(idx)   // nil = not in the extent; else its ramp position 0…1
            cellBody
                .overlay(alignment: .bottom) {
                    if let f = ramp {            // in the extent → a bottom-up fill whose height ramps across the toggled cells (the RANGE)
                        GeometryReader { g in
                            VStack(spacing: 0) { Spacer(minLength: 0); Rectangle().fill(roomsAmber.opacity(0.6)).frame(height: g.size.height * CGFloat(0.15 + 0.85 * f)) }
                        }
                        .clipShape(RoundedRectangle(cornerRadius: 5)).allowsHitTesting(false)
                    }
                }
                .overlay(RoundedRectangle(cornerRadius: 5).stroke(roomsAmber.opacity(ramp != nil ? 1 : 0.45), lineWidth: ramp != nil ? 1.5 : 1))
                .frame(width: w, height: h).contentShape(Rectangle())
                .onTapGesture { buildAutoToggle(idx) }   // TAP = toggle this cell in/out of the extent
        } else {
            cellBody
                .frame(width: w, height: h).opacity(punch != nil ? 0.4 : 1)   // armed-but-other-colour cells recede
                .contentShape(Rectangle())
                .onTapGesture {
                    if punch != nil { return }                                  // punch armed elsewhere → ignore stray taps
                    if buildSelectMode { if let cid = id { buildSelectID(cid) }; buildSelectMode = false }   // SELECT MODE: focus this cell's colour
                    else { buildStagingTap(c, r) }                                  // else: one rung per column, toggle
                }
        }
    }
    // The RIGHT rail — selects the ENTIRE row (every column → this row), like the old gui's row-select. Lights when the
    // whole row is the current per-column selection. (Paul 2026-08-28)
    @ViewBuilder private func roomsPartRightRail(_ n: Int) -> some View {
        let rowSel = buildStagingSel.allSatisfy { $0 == n }
        RoundedRectangle(cornerRadius: 5).fill(rowSel ? buildCyan.opacity(0.5) : Color.white.opacity(0.11))
            .overlay(RoundedRectangle(cornerRadius: 5).stroke(rowSel ? Color.white.opacity(0.6) : buildEdge, lineWidth: 1))
            .overlay(Image(systemName: "chevron.right").font(.system(size: 11, weight: .bold)).foregroundColor(.white.opacity(0.7)))   // same as the old gui's right rail
            .contentShape(Rectangle())
            .onTapGesture { buildSelectRow(n) }                          // select the WHOLE row for playback
    }
    // THE PART PLAYHEAD — a 2pt line sweeping the 8 interior columns, phase-locked to the beat (reuses the buildPlayhead
    // math: extrapolated beat → musical/swung column progress → x). Flexible-cell variant for the rooms grid.
    @ViewBuilder private func roomsPartPlayhead(colW: CGFloat, gap: CGFloat, height: CGFloat) -> some View {
        if d.playing && buildStagingPlaying {
            let sb = buildPartRate?.beats ?? stepBeats
            let cols = buildPartCols                                        // §E: the active width
            let width = colW * CGFloat(cols) + gap * CGFloat(cols - 1)
            TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: animationsPaused)) { tl in
                let live = meters.beatAnchor + tl.date.timeIntervalSince(meters.beatAnchorAt) * meters.tempo / 60.0
                let musical = musicalOf(live, stepBeats: sb, a: max(1.0, Double(swing) / 50.0))
                let colF = sb > 0 ? musical / sb : 0
                let wrapped = colF.truncatingRemainder(dividingBy: Double(cols))
                let p = wrapped < 0 ? wrapped + Double(cols) : wrapped
                let x = min(width, CGFloat(p) * (colW + gap))
                Rectangle().fill(Color.white.opacity(0.85)).frame(width: 2, height: height).offset(x: x).allowsHitTesting(false)
            }
        }
    }
    // TAP a PART LEFT side button — it becomes the SELECTED slot (the always-one selection, shared with SELECT) + the
    // copy source, and reflects its chain in the panel. It does NOT select a grid row — the RIGHT rail does that. (Paul 2026-08-28)
    private func roomsTapPartSide(_ n: Int) {
        if buildFerryHeld { buildFerryHeld = false; return }            // released-early hold → don't steal focus / re-audition the playing cell
        buildRoomsSetActiveSide(n)                                      // this left button is THE selected slot (+ copy source); clears any library-cell source
        if buildRowColour(n) != nil { buildTapColourTab(n) }           // reflect its chain in the MIDI CHAIN panel (does NOT touch the grid rung selection)
    }
    // Entering PART: hand a running chain audition to the part voice; keep ONE left button selected (default: the
    // last-selected SELECT side button, else the first) + reflect its chain; if NO rung is selected anywhere, seed one
    // rung per column from a populated row; refresh the side faces. (Paul 2026-08-28)
    func roomsPartSetup() {
        buildGridSelComputeRowRolls()                                  // the side buttons' part-chain fingerprints
        let focus = buildGridSelStampSourceRow ?? 0                    // the always-one selected LEFT button (from SELECT, else first)
        buildRoomsSetActiveSide(focus)
        if buildRowColour(focus) != nil { buildTapColourTab(focus) }   // reflect the focused slot's chain
        if buildStagingSel.allSatisfy({ $0 < 0 }) {                    // no rung selected anywhere → seed one-per-column with a default row
            let row = buildRowColour(focus) != nil ? focus : ((0..<8).first { buildRowColour($0) != nil } ?? focus)
            buildSelectRow(row)
        }
        roomsSyncVoice(.part)                                          // chain→part (nothing from SELECT plays here)
    }
    // THE EXTRA VOICE IS EXCLUSIVE PER PAGE (Paul 2026-08-29). The 8 play cells are a PERSISTENT layer (buildPlayColOn) that
    // sound on EVERY page and are NEVER touched here. Beyond them, exactly ONE "extra" cell sounds, determined by the page:
    //   SELECT → the SELECTED cell auditions (chain), continuous.   PART → the SEQUENCER's active cell (the sequenced part).
    // So switching pages switches ONLY the extra voice — and the sequenced part must NOT run on select (the bug the earlier
    // "non-disruptive" change caused: the part kept sequencing while on the select grid).
    func roomsSyncVoice(_ room: Room) {
        buildPendingWorkshopVoice = nil; buildPendingReengage = false
        switch room {
        case .select:
            // Auto-audition ONLY when the selection is a real SELECT-grid cell (buildGridSelSel). Otherwise the machine would
            // PLAY a colour with NO visible cell showing it — e.g. a part colour carried in from PART, or a ferry colour that
            // would then double the play layer (Paul 2026-08-31: "it'll be playing but the UI doesn't show that").
            if buildGridSelSel != nil { buildApplyWorkshopVoice(.chain) } else { buildApplyWorkshopVoice(.none) }
        case .part:   buildApplyWorkshopVoice(.part)     // extra = the sequenced part; audition OFF (play layer persists)
        case .play:   buildApplyWorkshopVoice(.none)     // no extra cell — just the 8 play cells
        default: break
        }
    }
    // ANY play column is running (the free-run gate + "is the play grid a voice"). Each column is independent (buildPlayColOn).
    var buildPlayPlaying: Bool { buildPlayColOn.contains(true) }
    // Toggle ONE play column's independent playback + republish. (Paul 2026-08-29 — each play cell starts/stops on its own.)
    func buildTogglePlayColumn(_ c: Int) {
        guard c >= 0, c < buildPlayColOn.count, buildPlayColHasContent(c) else { return }
        buildPlayColOn[c].toggle()
        // Starting a play column: the play LAYER is the voice — the shared select/part audition must be OFF, else it would
        // keep sounding this chain on rows 0…7 and this column's own stop (buildPlayColOn) could never silence it (Paul 2026-08-31).
        if buildPlayColOn[c] { buildVoiceOwner = .none; au?.clearColourSolo() }
        buildPublishScene()
    }
    // SELECT a play column's cell → the machine strip + the I/O toggles reflect it (Paul 2026-08-30: play-ferry selection,
    // parity with ferry-to-part). Independent of playback: focusing a play ferry never starts/stops it. Clears the SELECT
    // browse-cell + active-side selection so the SOURCE deselects (else it stays lit). buildSelectedPlayCol then resolves
    // buildSelID → this column, so buildSelectDoor/buildToggleBus reflect + edit its OWN receiver/emitters.
    func buildSelectPlayColumn(_ c: Int) {
        let r = c < buildPlaySel.count ? buildPlaySel[c] : -1
        guard r >= 0, c < buildPlayCells.count, r < buildPlayCells[c].count, let cid = buildPlayCells[c][r] else { return }
        buildGridSelSel = nil; buildGridSelStampSourceRow = nil      // the source select cell / active side button deselects
        buildVoiceOwner = .none                                      // a play column owns its OWN voice (the play layer) — never route it through the shared audition (else buildSelectID would re-inject it there, unstoppable by the ferry). Paul 2026-08-31
        buildSelectID(cid)
    }
    // The PLAY column currently selected — its selected-rung cell's colour == buildSelID. The play-grid analogue of
    // buildSelectedRow (which only searches STAGING rows), so the I/O toggles reflect + edit a ferried play cell's OWN
    // receiver/emitters. nil unless buildSelID names a live play cell. (Paul 2026-08-30)
    var buildSelectedPlayCol: Int? {
        guard let id = buildSelID else { return nil }
        return (0..<8).first { c in
            let r = c < buildPlaySel.count ? buildPlaySel[c] : -1
            return r >= 0 && c < buildPlayCells.count && r < buildPlayCells[c].count && buildPlayCells[c][r] == id
        }
    }
    // MASTER: start EVERY populated column (or stop all if any is on). The play room's big button.
    func buildTogglePlayGrid() {
        let anyOn = buildPlayColOn.contains(true)
        for c in 0..<8 { buildPlayColOn[c] = anyOn ? false : buildPlayColHasContent(c) }
        buildPublishScene()
    }
    // Column c has a populated selected rung (something to sound).
    func buildPlayColPopulated(_ c: Int) -> Bool {
        let r = c < buildPlaySel.count ? buildPlaySel[c] : -1
        return r >= 0 && r < 8 && c < buildPlayCells.count && r < buildPlayCells[c].count && buildPlayCells[c][r] != nil
    }
    // Column c has SOMETHING to sound — a populated selected rung OR a MULTI-STEP pass (Rooms2 fix, Paul 2026-08-30).
    // A pass plays independent of the rung (composeScene reads playColSteps, not playSel), so a deselected-rung pass
    // must still be startable/stoppable + count toward the grid transport — else it strands playing/unstartable.
    func buildPlayColHasContent(_ c: Int) -> Bool {
        buildPlayColPopulated(c) || (c < buildPlayColLen.count && buildPlayColLen[c] > 1)
    }
    // The play grid has at least one column with content (a rung OR a pass).
    var buildPlayPopulated: Bool { (0..<8).contains { buildPlayColHasContent($0) } }

    // ── THE PLAY GRID (Paul 2026-08-29 — "treat as new", BANDS DROPPED). A clean 8×8 over the play grid's OWN arrangement
    // (buildPlayCells — INDEPENDENT of the part's buildStagingCells), ONE selected rung per column (buildPlaySel, default
    // ROW 1), plus a BOTTOM READOUT row reflecting each column's selected cell (the numbered slots also shown at the TOP
    // of the SELECT/PART grids). Cells arrive by the SELECT TOP-button ferry (roomsAssignPlayColumn) — which writes ONLY
    // buildPlayCells, so it never touches the part-grid side buttons. Self-sizing: 9 equal rows (8 interior + 1 readout).
    // MASTER START/STOP — starts EVERY populated column at once (or stops all). Per-column control lives on the bottom
    // readout buttons (roomsPlayBottom) + the SELECT play-ferry buttons. Disabled until the grid has a populated rung.
    @ViewBuilder func roomsPlayStartStop() -> some View {
        buildColumnButton(buildPlayPlaying ? "STOP ALL" : "START ALL", active: buildPlayPlaying, fill: .grid, enabled: buildPlayPopulated, fillHeight: true,
                          action: { buildTogglePlayGrid() })
    }
    @ViewBuilder func roomsPlayGrid() -> some View {
        GeometryReader { g in
            let gap = RoomsMetrics.gap, pad = RoomsMetrics.pad
            let cw = max(6, (g.size.width - 2 * pad - 7 * gap) / 8)        // 8 cols, no rails → fills the width
            let ch = max(6, (g.size.height - 2 * pad - 8 * gap) / 9)       // 9 rows (8 interior + 1 bottom readout)
            VStack(spacing: gap) {
                VStack(spacing: gap) {                                      // the interior 8×8 — the play grid's OWN cells (rung-per-column select). No playhead (Paul 2026-08-29).
                    ForEach(0..<8, id: \.self) { r in
                        HStack(spacing: gap) { ForEach(0..<8, id: \.self) { c in roomsPlayCell(c, r).frame(width: cw, height: ch) } }
                    }
                }
                HStack(spacing: gap) {                                      // the BOTTOM readout — each column's selected cell
                    ForEach(0..<8, id: \.self) { c in roomsPlayBottom(c).frame(width: cw, height: ch) }
                }
            }
            .padding(pad)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(RoundedRectangle(cornerRadius: 12).fill(Color.white.opacity(0.05)))
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.clear, lineWidth: 0))
        }
    }
    // A PLAY interior cell — reads the play grid's OWN store (buildPlayCells), ONE selected rung per column via
    // buildPlaySel; tap selects that rung (re-tap the selected rung → deselect, column silent). Selected rung brighter.
    @ViewBuilder private func roomsPlayCell(_ c: Int, _ r: Int) -> some View {
        let id = (c < buildPlayCells.count && r < buildPlayCells[c].count) ? buildPlayCells[c][r] : nil
        let selected = c < buildPlaySel.count && buildPlaySel[c] == r
        let on = (c < buildPlayColOn.count && buildPlayColOn[c]) && selected
        roomsGridCellBody(id: id, selected: selected, sweep: {
            buildNoteSweep(indices: buildPlayColSweepIndices(c), active: on, id: id, emitter: c < buildPlayColEmit.count ? buildPlayColEmit[c] : [.a])   // CONTINUOUS drift in the EMITTER colour (multi-step gathers all steps)
            roomsCellPlayhead(active: on)   // PER-CELL PLAYHEAD — the pass sweeping L→R
        })
            .contentShape(Rectangle())
            .onTapGesture {
                if c < buildPlaySel.count { buildPlaySel[c] = (buildPlaySel[c] == r) ? -1 : r }   // one rung per column, toggle
                if c < buildPlayColOn.count, buildPlayColOn[c] { buildPublishScene() }   // Rooms1: a rung change while playing must re-publish so the engine FOLLOWS the selection (was UI-only → audio stayed on the old rung / kept sounding after deselect)
            }
    }
    // A PLAY bottom-row button — column c's PER-COLUMN TRANSPORT (Paul 2026-08-29): shows the selected cell's colour + a
    // play/stop icon reflecting the column's independent state; TAP = start/stop THIS column. Empty column → inert readout.
    @ViewBuilder private func roomsPlayBottom(_ c: Int) -> some View {
        let sel = c < buildPlaySel.count ? buildPlaySel[c] : -1
        let id = (sel >= 0 && c < buildPlayCells.count && sel < buildPlayCells[c].count) ? buildPlayCells[c][sel] : nil
        let hue = id.flatMap { colourColor($0) }
        let populated = buildPlayColPopulated(c)
        let on = c < buildPlayColOn.count && buildPlayColOn[c]
        RoundedRectangle(cornerRadius: 4).fill(hue?.opacity(on ? 1.0 : 0.55) ?? Color.white.opacity(0.11))
            .overlay {
                if populated {
                    Image(systemName: on ? "stop.fill" : "play.fill").font(.system(size: 11, weight: .black)).foregroundColor(.black.opacity(0.8))
                } else {
                    Text("\(c + 1)").font(.system(size: 10, weight: .heavy, design: .monospaced)).foregroundColor(.white.opacity(0.4))
                }
            }
            .contentShape(Rectangle())
            .onTapGesture { buildTogglePlayColumn(c) }
    }
    // (The GRID-WIDE play-grid playhead was removed 2026-08-29. The PER-CELL playhead below replaces it.)
    // PER-CELL PLAYHEAD (Paul 2026-08-29) — a thin line sweeping LEFT→RIGHT over one bar, BEAT-LOCKED, on each ACTIVE play
    // cell + play ferry. It makes a looping pass legible: independent per cell, cycling with the beat. Works under free-run
    // too (diag.beat is now the EFFECTIVE beat). One bar per loop today (a 1-step continuous pass); when N-step passes land
    // (part loop-length / reel) the loop maps to the pass's real length.
    @ViewBuilder private func roomsCellPlayhead(active: Bool) -> some View {
        if active {
            GeometryReader { g in
                let sb = max(0.0001, stepBeats)
                let barBeats = Double(Snap.cols) * sb                // one bar = 8 steps
                TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: animationsPaused)) { tl in
                    let live = meters.beatAnchor + tl.date.timeIntervalSince(meters.beatAnchorAt) * meters.tempo / 60.0
                    let ph = (live.truncatingRemainder(dividingBy: barBeats)) / barBeats
                    let p = ph < 0 ? ph + 1 : ph                     // 0…1 across the cell over one bar
                    Rectangle().fill(Color.white.opacity(0.6)).frame(width: 1.5)
                        .position(x: CGFloat(p) * g.size.width, y: g.size.height / 2)
                        .allowsHitTesting(false)
                }
            }
        }
    }

    // (The play-grid I/O toggles were REMOVED 2026-08-29 — Paul: the play grid has NO I/O toggles. Each ferried cell
    // DERIVES its door + emitters from the source it was copied from, stored per-column in buildPlayColRecv/Emit.)

    // MARK: - ROW 8 — the action strip (Paul 2026-08-22, Docs/row8-spec.md)
    // A perform-only strip below the play grid: the 8 typed action cells. TAP performs (toggle/radio/fire); LONG-PRESS
    // opens the EDIT PAGE at that cell (authoring). v1 ENGINE: FREEZE + HALFTIME are live (toggle cells); the routing-class
    // + seated types render + light but their engines land in the next increments.
    private func row8Glyph(_ t: Row8Type) -> String {
        switch t {
        case .empty:     return "plus"
        case .stutter:   return "repeat"
        case .freeze:    return "snowflake"
        case .halftime:  return "tortoise.fill"
        case .redirect:  return "arrow.turn.up.right"
        case .swap:      return "arrow.left.arrow.right"
        case .broadcast: return "antenna.radiowaves.left.and.right"
        case .kill:      return "xmark.octagon.fill"
        case .part:      return "square.grid.3x3.fill"
        case .sequence:  return "music.note.list"
        case .setup:     return "slider.horizontal.3"
        case .macro:     return "dial.medium.fill"
        case .input:     return "pianokeys"
        case .ccPunch:   return "hand.point.up.left.fill"
        case .pcSend:    return "paperplane.fill"
        }
    }
    private func row8Caption(_ c: Row8Cell) -> String {
        switch c.type {
        case .empty:     return "＋"
        case .stutter:   return "STUT " + (c.rate?.rawValue ?? "")
        case .freeze:    return "FREEZE"
        case .halftime:  return ["÷2", "×1", "×2"][max(0, min(2, c.halftimeMode ?? 1))] + " TIME"
        case .redirect:  return "\(busLetter(c.wireFrom ?? 0))→\(busLetter(c.wireTo ?? 1))"
        case .swap:      return "\(busLetter(c.wireFrom ?? 0))↔\(busLetter(c.wireTo ?? 1))"
        case .broadcast: return "CAST"
        case .kill:      return (c.killHard ?? false) ? "KILL!" : "KILL"
        case .part:      return "PART \((c.partRef ?? 0) + 1)"
        case .sequence:  return "SEQ"
        case .setup:     return "SETUP \((c.setupN ?? 0) + 1)"
        case .macro:     return "MACRO \((c.macroN ?? 0) + 1)"
        case .input:     return "IN \(busLetter(c.doorRef ?? 0))"
        case .ccPunch:   return "CC \(c.ccNum ?? 74)"
        case .pcSend:    return "PC \(c.pcNum ?? 0)"
        }
    }
    private func busLetter(_ i: Int) -> String { i >= 0 && i < 4 ? String(UnicodeScalar(UInt8(65 + i))) : "?" }



    // THE ROW 8 EDIT PAGE (§4): a spacious authoring surface. The 8 cells across the top; tap one to select; below, the
    // TYPE picker (cards), the MOVER chip, and the selected type's payload. Config lives here (the grid is perform-only).
    private static let row8Catalog: [Row8Type] = [.stutter, .freeze, .halftime, .redirect, .swap, .broadcast, .kill,
                                                  .part, .sequence, .setup, .macro, .input, .ccPunch, .pcSend]
    private func row8TypeName(_ t: Row8Type) -> String {
        switch t {
        case .empty: return "EMPTY"; case .stutter: return "STUTTER"; case .freeze: return "FREEZE"
        case .halftime: return "HALFTIME"; case .redirect: return "REDIRECT"; case .swap: return "SWAP"
        case .broadcast: return "BROADCAST"; case .kill: return "KILL"; case .part: return "PART"
        case .sequence: return "SEQUENCE"; case .setup: return "SETUP"; case .macro: return "MACRO"
        case .input: return "INPUT"; case .ccPunch: return "CC PUNCH"; case .pcSend: return "PC SEND"
        }
    }
    private func row8TypeBlurb(_ t: Row8Type) -> String {
        switch t {
        case .empty: return "an empty slot"
        case .stutter: return "held: retrigger the sounding set at a rate"
        case .freeze: return "toggle: sustain the sound + pause the grid"
        case .halftime: return "toggle: ÷2 · ×1 · ×2 the whole grid clock"
        case .redirect: return "held: send one wire's stream onto another"
        case .swap: return "two wires exchange their streams"
        case .broadcast: return "held: mirror every note to all wires"
        case .kill: return "one-shot: all-notes-off, soft or hard"
        case .part: return "toggle: play a part from the cell, any scene"
        case .sequence: return "toggle: a captured phrase loops"
        case .setup: return "one-shot radio: activate a rack setup"
        case .macro: return "fire or hold a macro"
        case .input: return "the door's mode-act (latch/keys/replay…)"
        case .ccPunch: return "held: punch a CC value"
        case .pcSend: return "one-shot: send a program change"
        }
    }
    private func buildRow8Edit(_ slot: Int, _ mutate: (inout Row8Cell) -> Void) {
        guard slot >= 0, slot < 8, slot < buildRow8Cells.count else { return }
        buildRecordUndo("row8")   // BUILD UNDO: authoring a ROW 8 action cell (coalesced within a config burst)
        var c = buildRow8Cells[slot]; mutate(&c)
        buildRow8Cells[slot] = c                     // optimistic
        au?.setRow8Cell(slot, c); refreshFromDocument()
    }
    @ViewBuilder private func buildRow8EditPage(size: CGSize) -> some View {
        let slot = (buildRow8EditSlot >= 0 && buildRow8EditSlot < 8) ? buildRow8EditSlot : 0
        let c = slot < buildRow8Cells.count ? buildRow8Cells[slot] : Row8Cell()
        ZStack {
            Color.black.opacity(0.55).ignoresSafeArea().onTapGesture { buildRow8EditOpen = false }
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    Text("ROW 8 · ACTIONS").font(.system(size: 15, weight: .heavy, design: .monospaced)).tracking(1).foregroundColor(.white)
                    Spacer()
                    Text("DONE").font(.system(size: 12, weight: .heavy, design: .monospaced)).foregroundColor(.black)
                        .padding(.horizontal, 16).frame(height: 30).background(RoundedRectangle(cornerRadius: 6).fill(buildCyan))
                        .contentShape(Rectangle()).onTapGesture { buildRow8EditOpen = false }
                }
                // the 8 cells — tap to select which one to author
                HStack(spacing: 6) {
                    ForEach(0..<8, id: \.self) { i in
                        let cc = i < buildRow8Cells.count ? buildRow8Cells[i] : Row8Cell()
                        VStack(spacing: 2) {
                            Image(systemName: row8Glyph(cc.type)).font(.system(size: 16, weight: .black)).foregroundColor(cc.type == .empty ? buildDim : .white)
                            Text(row8Caption(cc)).font(.system(size: 6.5, weight: .heavy, design: .monospaced)).foregroundColor(buildDim).lineLimit(1).minimumScaleFactor(0.5)
                        }
                        .frame(maxWidth: .infinity).frame(height: 46)
                        .background(RoundedRectangle(cornerRadius: 6).fill(i == slot ? buildCell : Color.white.opacity(0.04)))
                        .overlay(RoundedRectangle(cornerRadius: 6).stroke(i == slot ? buildCyan : buildEdge, lineWidth: i == slot ? 2 : 1))
                        .contentShape(Rectangle()).onTapGesture { buildRow8EditSlot = i }
                    }
                }
                Text("CELL \(slot + 1) — TYPE").font(.system(size: 9, weight: .heavy, design: .monospaced)).foregroundColor(buildDim)
                // the TYPE picker — cards with one-liners (the storefront grammar, reused)
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: 4), spacing: 6) {
                    ForEach(Self.row8Catalog, id: \.self) { t in
                        let sel = c.type == t
                        VStack(spacing: 3) {
                            Image(systemName: row8Glyph(t)).font(.system(size: 15, weight: .black)).foregroundColor(sel ? .black : .white)
                            Text(row8TypeName(t)).font(.system(size: 8, weight: .heavy, design: .monospaced)).foregroundColor(sel ? .black : .white).lineLimit(1).minimumScaleFactor(0.6)
                        }
                        .frame(maxWidth: .infinity).frame(height: 42)
                        .background(RoundedRectangle(cornerRadius: 6).fill(sel ? buildCyan : buildCell))
                        .contentShape(Rectangle())
                        .onTapGesture { buildRow8Edit(slot) { $0 = Row8Cell.make(t) } }   // pick = re-author the cell to this type (default mover + payload)
                    }
                }
                Text(row8TypeBlurb(c.type)).font(.system(size: 10, design: .monospaced)).foregroundColor(buildDim)
                // MOVER + the type's payload
                if c.type != .empty {
                    HStack(spacing: 6) {
                        Text("MOVER").font(.system(size: 9, weight: .heavy, design: .monospaced)).foregroundColor(buildDim)
                        ForEach(Row8Mover.allCases, id: \.self) { m in
                            let on = c.mover == m
                            Text(m == .oneShot ? "ONE-SHOT" : m.rawValue.uppercased())
                                .font(.system(size: 9, weight: .heavy, design: .monospaced)).foregroundColor(on ? .black : .white)
                                .padding(.horizontal, 10).frame(height: 26)
                                .background(RoundedRectangle(cornerRadius: 5).fill(on ? buildCyan : buildCell))
                                .contentShape(Rectangle()).onTapGesture { buildRow8Edit(slot) { $0.mover = m } }
                        }
                        Spacer(minLength: 0)
                    }
                    buildRow8Payload(slot: slot, c: c)
                }
                // DELETE → the [+] invitation
                HStack {
                    Spacer()
                    Text("CLEAR CELL").font(.system(size: 10, weight: .heavy, design: .monospaced)).foregroundColor(buildRed)
                        .padding(.horizontal, 14).frame(height: 28).background(RoundedRectangle(cornerRadius: 6).fill(buildRed.opacity(0.15)))
                        .contentShape(Rectangle()).onTapGesture { buildRow8Edit(slot) { $0 = Row8Cell() }; au?.setRow8On(slot, false) }
                }
                Spacer(minLength: 0)
            }
            .padding(20)
            .frame(width: min(560, size.width - 32), height: min(size.height - 60, 520))
            .background(RoundedRectangle(cornerRadius: 16).fill(buildPanel))
            .overlay(RoundedRectangle(cornerRadius: 16).stroke(buildEdge, lineWidth: 1))
        }
    }
    // The payload editor for the selected type (rate/mode/wire pair/number). Compact steppers + cycles.
    @ViewBuilder private func buildRow8Payload(slot: Int, c: Row8Cell) -> some View {
        switch c.type {
        case .stutter:
            row8Row("RATE") { HStack(spacing: 6) { ForEach([ArpRate.r1_8, .r1_16, .r1_32], id: \.self) { r in
                row8Chip(r.rawValue, on: (c.rate ?? .r1_16) == r) { buildRow8Edit(slot) { $0.rate = r } } } } }
        case .halftime:
            row8Row("SPEED") { HStack(spacing: 6) { ForEach(0..<3, id: \.self) { m in
                row8Chip(["÷2", "×1", "×2"][m], on: (c.halftimeMode ?? 1) == m) { buildRow8Edit(slot) { $0.halftimeMode = m } } } } }
        case .redirect, .swap:
            VStack(alignment: .leading, spacing: 6) {
                row8Row("FROM") { HStack(spacing: 6) { ForEach(0..<4, id: \.self) { w in
                    row8Chip(busLetter(w), on: (c.wireFrom ?? 0) == w) { buildRow8Edit(slot) { $0.wireFrom = w } } } } }
                row8Row("TO") { HStack(spacing: 6) { ForEach(0..<4, id: \.self) { w in
                    row8Chip(busLetter(w), on: (c.wireTo ?? 1) == w) { buildRow8Edit(slot) { $0.wireTo = w } } } } }
            }
        case .kill:
            row8Row("MODE") { HStack(spacing: 6) {
                row8Chip("SOFT", on: !(c.killHard ?? false)) { buildRow8Edit(slot) { $0.killHard = false } }
                row8Chip("HARD", on: c.killHard ?? false) { buildRow8Edit(slot) { $0.killHard = true } } } }
        case .broadcast:
            row8Row("CHANNELS") { HStack(spacing: 6) {
                row8Chip("WIRES", on: !(c.broadcastAllChannels ?? false)) { buildRow8Edit(slot) { $0.broadcastAllChannels = false } }   // nil ⇒ 4-wire, matching the engine's `?? false` (review fix 2026-08-26 — was `?? true`, a display lie for old docs)
                row8Chip("+ ALL CH", on: c.broadcastAllChannels ?? false) { buildRow8Edit(slot) { $0.broadcastAllChannels = true } } } }
        case .setup:
            row8Row("SETUP") { row8Stepper(value: (c.setupN ?? 0) + 1, lo: 1, hi: 4) { v in buildRow8Edit(slot) { $0.setupN = v - 1 } } }
        case .macro:
            row8Row("MACRO") { row8Stepper(value: (c.macroN ?? 0) + 1, lo: 1, hi: 8) { v in buildRow8Edit(slot) { $0.macroN = v - 1 } } }
        case .part:
            row8Row("PART") { row8Stepper(value: (c.partRef ?? 0) + 1, lo: 1, hi: 8) { v in buildRow8Edit(slot) { $0.partRef = v - 1 } } }
        case .input:
            row8Row("DOOR") { HStack(spacing: 6) { ForEach(0..<4, id: \.self) { d in
                row8Chip(busLetter(d), on: (c.doorRef ?? 0) == d) { buildRow8Edit(slot) { $0.doorRef = d } } } } }
        case .ccPunch:
            VStack(alignment: .leading, spacing: 6) {
                row8Row("CC #") { row8Stepper(value: c.ccNum ?? 74, lo: 0, hi: 127) { v in buildRow8Edit(slot) { $0.ccNum = v } } }
                row8Row("VALUE") { row8Stepper(value: c.ccVal ?? 127, lo: 0, hi: 127) { v in buildRow8Edit(slot) { $0.ccVal = v } } }
            }
        case .pcSend:
            row8Row("PROGRAM") { row8Stepper(value: c.pcNum ?? 0, lo: 0, hi: 127) { v in buildRow8Edit(slot) { $0.pcNum = v } } }
        default:
            EmptyView()
        }
    }
    @ViewBuilder private func row8Row<C: View>(_ label: String, @ViewBuilder _ content: () -> C) -> some View {
        HStack(spacing: 8) {
            Text(label).font(.system(size: 9, weight: .heavy, design: .monospaced)).foregroundColor(buildDim).frame(width: 74, alignment: .leading)
            content(); Spacer(minLength: 0)
        }
    }
    @ViewBuilder private func row8Chip(_ label: String, on: Bool, _ tap: @escaping () -> Void) -> some View {
        Text(label).font(.system(size: 9, weight: .heavy, design: .monospaced)).foregroundColor(on ? .black : .white)
            .padding(.horizontal, 10).frame(height: 26).background(RoundedRectangle(cornerRadius: 5).fill(on ? buildCyan : buildCell))
            .contentShape(Rectangle()).onTapGesture(perform: tap)
    }
    @ViewBuilder private func row8Stepper(value: Int, lo: Int, hi: Int, _ set: @escaping (Int) -> Void) -> some View {
        HStack(spacing: 8) {
            Text("−").font(.system(size: 16, weight: .black)).foregroundColor(.white).frame(width: 34, height: 26)
                .background(RoundedRectangle(cornerRadius: 5).fill(buildCell)).contentShape(Rectangle()).onTapGesture { set(max(lo, value - 1)) }
            Text("\(value)").font(.system(size: 12, weight: .heavy, design: .monospaced)).foregroundColor(.white).frame(minWidth: 34)
            Text("+").font(.system(size: 16, weight: .black)).foregroundColor(.white).frame(width: 34, height: 26)
                .background(RoundedRectangle(cornerRadius: 5).fill(buildCell)).contentShape(Rectangle()).onTapGesture { set(min(hi, value + 1)) }
        }
    }

    @ViewBuilder private func buildChainBtn(_ label: String, enabled: Bool = true, fill: Bool = false, h: CGFloat? = nil, action: @escaping () -> Void) -> some View {
        Text(label).font(.system(size: 8, weight: .heavy, design: .monospaced)).tracking(0.2)
            .foregroundColor(.white).lineLimit(1).minimumScaleFactor(0.5).padding(.horizontal, 3)
            // fill = SHARE the stack's fixed height (so N buttons never overflow it → the chain grid keeps its size,
            // Paul 2026-08-23); else a compact fixed height (`h`, default 33 = the GRID-verb HStack row). Text size is
            // unchanged (8pt) regardless of the button height.
            .frame(maxWidth: .infinity).frame(maxHeight: fill ? .infinity : nil).frame(height: fill ? nil : (h ?? 33))
            .background(RoundedRectangle(cornerRadius: 6).fill(buildCell))
            .overlay(RoundedRectangle(cornerRadius: 6).stroke(buildEdge, lineWidth: 1))
            .opacity(enabled ? 1 : 0.35)                                      // DISABLED → dimmed + inert (Paul 2026-08-18)
            .contentShape(Rectangle())
            .onTapGesture { if enabled { buildExitPlaceMode(); action() } }
            .allowsHitTesting(enabled)
    }
    // THE RECEIVER (MIDI-IN) SELECTOR — sits between the row selector and the MIDI-chain box. Four buttons styled
    // like the centre column's emitter A–D chips (buildIOChip: cyan-when-armed, muted idle), but two-line: "MIDI IN"
    // small over a big A/B/C/D. A radio — one door selected, feeding the part. (Paul 2026-08-18)
    @ViewBuilder private func buildReceiverSelector(castW: CGFloat) -> some View {
        HStack(spacing: 4) {
            ForEach(0..<4, id: \.self) { i in buildReceiverSelectChip(i) }
        }
        .frame(width: castW)
    }
    @ViewBuilder private func buildReceiverSelectChip(_ i: Int) -> some View {
        // RELIABILITY FIX (Paul 2026-08-29): the chip's lit state MUST read from the SAME place the toggle WRITES, or it
        // shows wrong. buildSelectDoor writes buildRowReceiver[row] when a row is selected, else buildSelReceiver (the part
        // default). So read exactly that: the selected row's RESOLVED door, else buildSelReceiver — never a `?? false`
        // (which used to blank the chip when no row was selected) and never a mismatched buildGridSelOpen branch (which
        // read buildSelReceiver while the write went to the row → the toggle looked dead/incorrect).
        // A selected PLAY cell (buildSelectedPlayCol) reads its OWN receiver, between the staging row and the part default (Paul 2026-08-30).
        let on = buildSelectedRow.map { buildRowReceiverResolved($0) == i }
            ?? buildSelectedPlayCol.map { ($0 < buildPlayColRecv.count ? buildPlayColRecv[$0] : buildSelReceiver) == i }
            ?? (buildSelReceiver == i)
        // If the door has a KEY selected (a SCALE door → its root), show the KEY as the label; the door letter moves to the
        // top so its identity is kept. Otherwise the plain A/B/C/D letter. (Paul 2026-08-29)
        let letter = ["A", "B", "C", "D"][i]
        let key: String? = i < receivers.count ? receivers[i].scaleLabel : nil   // "A MIXO" for a SCALE door (shared helper), else nil
        buildIOSelectChip(top: key != nil ? letter : "MIDI IN", letter: key ?? letter, on: on, accent: receiverGrey(i), action: { buildSelectDoor(i) }, onAll: { buildSelectDoorAll(i) })   // ON = the receiver's SIGNATURE GREY (Paul 2026-08-30)
    }
    // THE EMITTER (MIDI-OUT) TOGGLES — below the left column's button box. Four toggles (A–D), IDENTICAL in style to
    // the MIDI-IN receiver selector, toggling the PART's output emitters (part-owned, so every colour follows). (Paul 2026-08-18)
    @ViewBuilder private func buildEmitterToggles(castW: CGFloat) -> some View {
        HStack(spacing: 4) {
            ForEach(Array(Bus.allCases.enumerated()), id: \.offset) { _, b in
                // RELIABILITY FIX (Paul 2026-08-29): read from the SAME place buildToggleBus writes — the selected row's
                // RESOLVED emitters, else the part default (buildPartEmitters, [.a] when empty). Was a mismatched
                // buildGridSelOpen branch + a `?? false` that blanked the chips when no row was selected.
                let on = buildSelectedRow.map { buildRowEmittersResolved($0).contains(b) }
                    ?? buildSelectedPlayCol.map { ($0 < buildPlayColEmit.count ? buildPlayColEmit[$0] : [.a]).contains(b) }
                    ?? ((buildDefaultEmitters).contains(b))
                buildIOSelectChip(top: "MIDI OUT", letter: b.rawValue, on: on, accent: emitterColour(b), action: { buildToggleBus(b) }, onAll: { buildToggleBusAll(b) })   // ON = the emitter's SIGNATURE colour (Paul 2026-08-30)
            }
        }
        .frame(width: castW)
    }
    // The shared two-line I/O chip: a small top label over a big A/B/C/D, styled like the centre column's emitter A–D
    // chips (cyan-when-on, muted idle, height 48). Used by BOTH the MIDI-IN receiver selector and the MIDI-OUT
    // emitter toggles so they read identically. (Paul 2026-08-18)
    @ViewBuilder private func buildIOSelectChip(top: String, letter: String, on: Bool, accent: Color? = nil, action: @escaping () -> Void, onAll: @escaping () -> Void = {}) -> some View {
        // Paul 2026-08-30: HALF height (48→24) + only the LARGER line (the letter) — the small "MIDI IN"/"MIDI OUT" caption dropped.
        Text(letter).font(.system(size: 15, weight: .black, design: .monospaced)).lineLimit(1).minimumScaleFactor(0.4)   // scale to fit a longer key label like "A MIXO"
        .foregroundColor(on ? Color.black : buildDim)
        .frame(maxWidth: .infinity).frame(height: 36)                        // +50% over the halved 24 (Paul 2026-08-30)
        .background(RoundedRectangle(cornerRadius: 7).fill(on ? (accent ?? buildCyan) : buildCell))   // ON = the accent (emitter signature colour for MIDI OUT); idle mutes
        .overlay(RoundedRectangle(cornerRadius: 7).stroke(on ? Color.clear : buildEdge, lineWidth: 1))
        .contentShape(Rectangle())
        .onTapGesture(perform: action)                                       // TAP = this row (or the part default)
        .onLongPressGesture(minimumDuration: 0.75, perform: {               // HOLD = apply to EVERY row (Paul 2026-08-19)
            buildIOHoldPressing = false; withAnimation { buildIOHoldMsg = nil }; onAll()
        }, onPressingChanged: { pressing in
            buildIOHoldPressing = pressing
            if pressing {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {      // the hint appears a moment BEFORE it applies
                    if buildIOHoldPressing { withAnimation { buildIOHoldMsg = "HOLD TO APPLY TO ALL" } }
                }
            } else { withAnimation { buildIOHoldMsg = nil } }
        })
    }
    private func buildTapColourTab(_ n: Int) {
        if let cid = buildRowColour(n) {                         // a SET tab → SELECT its colour ONLY (does NOT set the playing rung — Paul 2026-08-20)
            buildSelectID(cid)                                   // the grid cells / loop keys set the rung; the row button just picks the colour to edit
            buildStagingSyncIfPlaying()
        } else {
            buildPopulateTab(n)                                  // an EMPTY tab → create/copy/place, then pulse until edited
        }
    }
    // Touch an EMPTY tab: mint tab n's colour with an EMPTY chain (NO duplication of the current settings — Paul
    // 2026-08-25), place it on row n, default its I/O to the LAST-USED receivers/emitters, select it, and mark it
    // PENDING (flashing). The flash stays until a change is made to the processors, emitters, or receivers (see
    // buildApplyChain + buildClearPendingOnEdit). Only one pending → revert the previous unedited candidate first.
    private func buildPopulateTab(_ n: Int) {
        buildRecordUndo()   // BUILD UNDO: tapping an empty row-tab mints a colour + places it on a row (U4 fix 2026-08-27)
        let sourceChain: [ProcessorSlot] = []                    // a fresh EMPTY row (was: a copy of the last-selected chain)
        if let p = buildPendingTab, p != n {                     // ONE pending → discard the previous unedited candidate
            if let old = buildRowColour(p) { buildPartCast.removeAll { $0 == old } }
            buildSetRow(p, to: nil)
        }
        let y = buildNewTabColour(n, machine: sourceChain)       // tab n's fixed hue + the empty chain
        buildPartCast.append(y)
        buildSetRow(n, to: y)                                    // placed on part-grid row n
        if n < buildRowReceiver.count { buildRowReceiver[n] = ddStickyReceiver; buildRowEmitters[n] = ddStickyBuses }   // DEFAULT the new row's I/O to the LAST-USED receivers/emitters (Paul 2026-08-18/25)
        for c in 0..<Snap.maxCols { buildStagingSel[c] = n }   // §E: the 16-col staging storage (width governs view/play)
        buildSelectID(y)
        buildPendingTab = n
        buildPendingSource = selectedColourChain()               // == [] here; buildApplyChain clears the flash once the chain diverges
        buildStagingSyncIfPlaying()
    }
    // The PENDING (flashing) row ends its flash the moment the user changes its EMITTERS or RECEIVERS — the processor
    // path already clears it via buildApplyChain. Only fires while the pending row is the selected one. (Paul 2026-08-25)
    private func buildClearPendingOnEdit() {
        if let p = buildPendingTab, buildSelectedRow == p { buildPendingTab = nil; buildPendingSource = [] }
    }

    // The chain as the block's lower half: 8 processor boxes, each the size of 2×2 cast cells, laid 1·2·3·4 /
    // 5·6·7·8 with NO connectors. Empty slots read as their number (1–8); populated show the processor type.
    @ViewBuilder private func buildProcessorBlock(castW: CGFloat, cell: CGFloat, hue: Color) -> some View {
        let chain = selectedColourChain()
        let gap = BuildGeom.castGap
        let swW = (castW - gap * 7) / 8                            // same swatch width as the cast → boxes sit on the 8-column grid
        let boxW = swW * 2 + gap                                   // 2 cast columns wide
        let boxH = (cell + gap) * 1.5                              // +50% over the halved height (Paul 2026-08-30)
        VStack(spacing: gap) {                                      // VERTICAL 2×4 (was 4×2): 4 rows of 2 boxes, reading L→R then down (Paul 2026-08-18)
            ForEach(0..<4, id: \.self) { r in
                HStack(spacing: gap) {
                    ForEach(0..<2, id: \.self) { c in
                        buildProcBox(r * 2 + c, chain: chain, w: boxW, h: boxH, gap: gap, hue: hue)
                    }
                }
            }
        }
        // §1 THE FLOW LINE (design 2026-08-17): the dotted thread draws ORDER (the numbers' old job) — door ┈▶ slot 0 ┈▶
        // … ┈▶ slot 7 ┈▶ wire, in chain order, with a TURN MARK at each row wrap (the boustrophedon made visible).
        .background(buildChainFlowLine(boxW: boxW, boxH: boxH, gap: gap, hue: hue))   // the dotted ORDER thread (behind the boxes); the COMETS live in the chain-row overlay (buildChainFlowOverlay) so they span the flank circles + clip out of the boxes (Paul 2026-08-31)
        .coordinateSpace(name: "chainBlock")                        // DRAG-TO-REORDER: a stable space for the finger track + the floating ghost
        .overlay(alignment: .topLeading) { buildChainDragGhost(chain: chain, boxW: boxW, boxH: boxH, hue: hue) }
        // (The offline chain re-simulation was RETIRED 2026-08-31 — the comets now draw the engine's REAL emitted notes via
        // buildFocusNotes; the input line uses the real held chord. buildChainStageSets is kept only for its unit tests.)
    }
    // The LIVE held chord at the chain's input door — the notes ACTUALLY coming through (empty ⇒ no comets). (Paul 2026-08-31)
    private var buildChainLiveChord: [Int] {
        let door: Int
        if let pc = buildSelectedPlayCol, pc >= 0, pc < buildPlayColRecv.count { door = buildPlayColRecv[pc] }   // a selected FERRY reads ITS door
        else { door = buildSelectedRow.map { buildRowReceiverResolved($0) } ?? buildSelReceiver }
        guard door >= 0, door < recvHeldNotes.count else { return [] }
        return recvHeldNotes[door].map(Int.init).sorted()
    }
    // DRAG-TO-REORDER: the floating ghost of the box under the finger (drawn in the "chainBlock" space, hit-transparent).
    @ViewBuilder private func buildChainDragGhost(chain: [ProcessorSlot], boxW: CGFloat, boxH: CGFloat, hue: Color) -> some View {
        if let from = buildChainDragFrom, from < chain.count, !buildIsEmptySlot(chain[from]) {
            Text(buildProcLabel(chain[from]))
                .font(.system(size: 11, weight: .heavy, design: .monospaced))
                .foregroundColor(.black)
                .lineLimit(1).minimumScaleFactor(0.5).padding(.horizontal, 3)
                .frame(width: boxW * 0.8, height: boxH * 0.8)
                .background(RoundedRectangle(cornerRadius: 8).fill(hue))
                .shadow(color: .black.opacity(0.5), radius: 6, y: 2)
                .position(buildChainDragLoc)
                .allowsHitTesting(false)
        }
    }
    // A structural signature of the selected chain (type + bypass per slot + which colour) — the comets recompute when it
    // changes. (Param-only edits keep the same signature; the comets refresh on the next structural change / reselect — v1.)
    // NOTE COMETS along the MIDI chain (Paul 2026-08-31): a CIRCLE at each end (the door entry, aligned with the input/A
    // side + the top chain row · the wire exit, aligned with the D side), and comets flowing DOOR ┈▶ slot 0 ┈▶ … ┈▶ slot 7
    // ┈▶ WIRE. Each SEGMENT carries that stage's real MIDI (buildChainStages: the offline OUTPUT after each processor), so a
    // comet stream matches exactly what leaves that processor. Size + glow by velocity; flows with the beat (idle drift when
    // stopped). Drawn in the same "chainBlock" geometry as the flow line.
    // THE FLOW OVERLAY — circles + dotted connectors + note COMETS, drawn on the CHAIN ROW (the HStack, not the block) so the
    // whole path spans the top-left circle → the boxes → the bottom-right circle. The comets are CLIPPED OUT of the processor
    // boxes, so they flow through the connectors + gaps and vanish BEHIND each box — never drawn over the box labels (Paul
    // 2026-08-31: the additive comets were bleeding through the text). Each output note journeys the full path over `transit`
    // beats (HALVED speed) with a tail ∝ its duration — timed to the real note rhythm.
    // The LAST non-bypassed processor that turns a held chord into a RHYTHM (arp/ratchet/strum/euclid/burst/cascade/weave/
    // riff/hocket). Before it the chord is still held (a line); from it the notes are rhythmic (comets). nil ⇒ no rhythm
    // processor (the whole chain is a held-chord line). (Paul 2026-08-31.)
    private func buildRhythmDriverSlot(_ chain: [ProcessorSlot]) -> Int? {
        let rhythm: Set<ProcessorType> = [.arp, .ratchet, .strum, .euclid, .burst, .cascade, .weave, .riff, .hocket]
        var last: Int? = nil
        for (i, s) in chain.enumerated() where !s.bypassed && rhythm.contains(s.type) { last = i }
        return last
    }
    @ViewBuilder private func buildChainFlowOverlay(sideW: CGFloat, blockW: CGFloat, blockH: CGFloat, boxH: CGFloat, gap: CGFloat, hue: Color, chain: [ProcessorSlot]) -> some View {
        let boxW = (blockW - gap) / 2                                          // 2 columns of boxes
        let populated = (0..<8).map { $0 < chain.count && !buildIsEmptySlot(chain[$0]) }   // only POPULATED (opaque) boxes clip the comets — EMPTY boxes are transparent, the comet flows through (Paul 2026-08-31)
        TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: animationsPaused)) { tl in
            Canvas { ctx, _ in
                let cr = max(3.5, min(boxH * 0.16, sideW * 0.42))
                let lx = sideW / 2, rx = sideW + blockW + sideW / 2            // flank-column centres
                let ty = boxH / 2, by = blockH - boxH / 2                      // first / last processor rows
                func boxC(_ i: Int) -> CGPoint { CGPoint(x: sideW + CGFloat(i % 2) * (boxW + gap) + boxW / 2, y: CGFloat(i / 2) * (boxH + gap) + boxH / 2) }   // box centre in HStack space
                // THE FULL PATH: left circle ▸ door ▸ box 0 … box 7 ▸ wire ▸ right circle.
                var P: [CGPoint] = [CGPoint(x: lx, y: ty), CGPoint(x: sideW, y: ty)]
                for i in 0..<8 { P.append(boxC(i)) }
                P.append(CGPoint(x: sideW + blockW, y: by)); P.append(CGPoint(x: rx, y: by))
                // DOTTED CONNECTORS (circle ▸ block edge) — the in-block flow line carries the middle; these reach the circles.
                let dash = StrokeStyle(lineWidth: 1.5, lineCap: .round, dash: [2, 3])
                var lseg = Path(); lseg.move(to: CGPoint(x: lx + cr, y: ty)); lseg.addLine(to: CGPoint(x: sideW, y: ty))
                var rseg = Path(); rseg.move(to: CGPoint(x: sideW + blockW, y: by)); rseg.addLine(to: CGPoint(x: rx - cr, y: by))
                ctx.stroke(lseg, with: .color(hue.opacity(0.32)), style: dash)
                ctx.stroke(rseg, with: .color(hue.opacity(0.32)), style: dash)
                for end in [CGPoint(x: lx, y: ty), CGPoint(x: rx, y: by)] {     // THE CIRCLES
                    ctx.stroke(Path(ellipseIn: CGRect(x: end.x - cr, y: end.y - cr, width: 2 * cr, height: 2 * cr)), with: .color(hue.opacity(0.85)), lineWidth: 1.8)
                    ctx.fill(Path(ellipseIn: CGRect(x: end.x - cr * 0.34, y: end.y - cr * 0.34, width: cr * 0.68, height: cr * 0.68)), with: .color(hue.opacity(0.5)))
                }
                // REAL FLOW (Paul 2026-08-31): driven by the engine's actual data — the held INPUT chord (buildChainLiveChord)
                // draws as a HARD LINE up to the processor that turns it rhythmic, and the REAL emitted notes (buildFocusNotes,
                // pitch + true beat) flow out from there as comets at their ACTUAL timing. No offline simulation.
                let ferryOn = buildSelectedPlayCol.map { $0 < buildPlayColOn.count && buildPlayColOn[$0] } ?? false
                guard buildDisplayVoice == .chain || ferryOn else { return }   // the machine is a live voice (real feed = empty when silent)
                let live = meters.beatAnchor + tl.date.timeIntervalSince(meters.beatAnchorAt) * meters.tempo / 60.0
                let nSeg = P.count - 1
                // THE PIVOT box — the last rhythm-creating processor (arp/ratchet/…); before it the chord is still held, from it
                // the notes are rhythmic. No such processor ⇒ the whole chain is a held-chord line to the wire.
                let pivot: Int = buildRhythmDriverSlot(chain).map { min($0 + 2, nSeg) } ?? nSeg
                func subPoint(_ from: Int, _ f: Double) -> CGPoint {          // a point at fraction f along the sub-path P[from … end]
                    var lens = [CGFloat](); var tot: CGFloat = 0
                    for j in from..<nSeg { let l = max(0.001, hypot(P[j + 1].x - P[j].x, P[j + 1].y - P[j].y)); lens.append(l); tot += l }
                    guard !lens.isEmpty else { return P[min(from, P.count - 1)] }
                    var dist = CGFloat(max(0, min(1, f))) * tot
                    for i in 0..<lens.count {
                        if dist <= lens[i] || i == lens.count - 1 { let t = dist / lens[i], a = P[from + i], b = P[from + i + 1]; return CGPoint(x: a.x + (b.x - a.x) * t, y: a.y + (b.y - a.y) * t) }
                        dist -= lens[i]
                    }
                    return P.last!
                }
                // CLIP out the POPULATED boxes for BOTH the line and the comets → nothing ever draws over a processor's opaque
                // face or its label (Paul 2026-08-31: the flow was showing through the box text). Flows through the gaps + empties.
                var boxesPath = Path()
                for i in 0..<8 where populated[i] { let c = boxC(i); boxesPath.addRoundedRect(in: CGRect(x: c.x - boxW * 0.4, y: c.y - boxH * 0.4, width: boxW * 0.8, height: boxH * 0.8), cornerSize: CGSize(width: 8, height: 8)) }
                if !boxesPath.isEmpty { ctx.clip(to: boxesPath, options: .inverse) }
                // INPUT LINE circle → pivot: the held chord, one solid line (clipped out of the boxes).
                if !buildChainLiveChord.isEmpty {
                    var linePath = Path(); linePath.move(to: P[0]); for j in 1...pivot { linePath.addLine(to: P[j]) }
                    ctx.stroke(linePath, with: .color(hue.opacity(0.72)), style: StrokeStyle(lineWidth: 2.4, lineCap: .round, lineJoin: .round))
                }
                // OUTPUT COMETS from the pivot to the wire — the REAL emitted notes, each flowing over ONE STEP from the moment it
                // actually fired (live − note.beat).
                guard pivot < nSeg, !buildFocusNotes.isEmpty else { return }
                ctx.blendMode = .plusLighter
                let transit = max(0.06, stepBeats)                            // beats to cross the output region (one step)
                for note in buildFocusNotes {
                    let age = live - note.beat
                    guard age >= 0, age <= transit else { continue }
                    let prog = age / transit
                    let head = subPoint(pivot, prog)
                    let r = 1.3 + 2.4 * CGFloat(note.vel)
                    let steps = 5                                             // FINE tail — follows the zig-zag path, never cuts a corner (Paul 2026-08-31)
                    for k in 0..<steps {
                        let p0 = max(0, prog - 0.16 * Double(k + 1) / Double(steps)), p1 = max(0, prog - 0.16 * Double(k) / Double(steps))
                        var s = Path(); s.move(to: subPoint(pivot, p0)); s.addLine(to: subPoint(pivot, p1))
                        ctx.stroke(s, with: .color(hue.opacity((0.32 * note.vel) * (1 - Double(k) / Double(steps)))), style: StrokeStyle(lineWidth: r, lineCap: .round))
                    }
                    ctx.fill(Path(ellipseIn: CGRect(x: head.x - r, y: head.y - r, width: 2 * r, height: 2 * r)), with: .color(hue.opacity(0.6 + 0.4 * note.vel)))
                }
            }
            .allowsHitTesting(false)
        }
    }
    private func buildChainFlowLine(boxW: CGFloat, boxH: CGFloat, gap: CGFloat, hue: Color) -> some View {
        Canvas { ctx, size in
            func center(_ i: Int) -> CGPoint {
                CGPoint(x: CGFloat(i % 2) * (boxW + gap) + boxW / 2, y: CGFloat(i / 2) * (boxH + gap) + boxH / 2)
            }
            var path = Path()
            path.move(to: CGPoint(x: 0, y: center(0).y)); path.addLine(to: center(0))   // DOOR entry
            for i in 1..<8 { path.addLine(to: center(i)) }                               // chain order 0→…→7
            path.addLine(to: CGPoint(x: size.width, y: center(7).y))                     // WIRE exit
            ctx.stroke(path, with: .color(hue.opacity(0.32)), style: StrokeStyle(lineWidth: 1.5, lineCap: .round, dash: [2, 3]))
            for wrap in [1, 3, 5] {                                                      // TURN MARK at each row wrap (slot 1→2, 3→4, 5→6)
                let a = center(wrap), b = center(wrap + 1); let m = CGPoint(x: (a.x + b.x) / 2, y: (a.y + b.y) / 2)
                ctx.fill(Path(ellipseIn: CGRect(x: m.x - 2, y: m.y - 2, width: 4, height: 4)), with: .color(hue.opacity(0.5)))
            }
        }
    }

    @ViewBuilder private func buildProcBox(_ i: Int, chain: [ProcessorSlot], w: CGFloat, h: CGFloat, gap: CGFloat, hue: Color) -> some View {
        let populated = i < chain.count && !buildIsEmptySlot(chain[i])
        let bw = w * 0.8, bh = h * 0.8                             // the button is 80% of the 2×2-cell footprint …
        let isDragged = buildChainDragFrom == i
        let isDropTarget = buildChainDragFrom != nil && buildChainDragFrom != i && buildChainDropTo == i
        Group {
            if populated {
                Text(buildProcLabel(chain[i]))
                    .font(.system(size: 11, weight: .heavy, design: .monospaced))
                    .foregroundColor(.black)
                    .lineLimit(1).minimumScaleFactor(0.5).padding(.horizontal, 3)
                    .frame(width: bw, height: bh)
                    .background(RoundedRectangle(cornerRadius: 8).fill(hue))
                    .overlay { if chain[i].bypassed { RoundedRectangle(cornerRadius: 8).fill(Color.black.opacity(0.45)) } }
            } else {
                // §1 GHOST-DASHED EMPTY (design 2026-08-17): numbers OUT (the FLOW LINE now carries ORDER) — the house
                // grammar for an empty slot is a dashed ghost + a faint "+" add-invitation.
                Image(systemName: "plus")
                    .font(.system(size: min(bh * 0.34, 15), weight: .semibold))
                    .foregroundColor(Color(white: 0.4))
                    .frame(width: bw, height: bh)
                    .background(RoundedRectangle(cornerRadius: 8).fill(buildCell.opacity(0.5)))
                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(style: StrokeStyle(lineWidth: 1, dash: [4, 3])).foregroundColor(buildEdge))
            }
        }
        .frame(width: w, height: h)                               // … centred in the full cell footprint
        .opacity(isDragged ? 0.3 : 1)                             // DRAG-TO-REORDER: the lifted source recedes (the ghost carries it)
        .overlay {                                                 // … and the slot the finger is over rings cyan (where it will land)
            if isDropTarget { RoundedRectangle(cornerRadius: 8).stroke(buildCyan, lineWidth: 3).frame(width: bw + 4, height: bh + 4) }
        }
        .contentShape(Rectangle())
        .onTapGesture { buildExitPlaceMode(); buildPlaceMsg = nil; if populated { buildEditSlot = i } else { buildAddSlot = i } }   // fresh pop-up → clear stale PLACE feedback; box is not a play-grid row → leaves PLACE mode
        // DRAG-TO-REORDER (Paul 2026-08-25): a populated box is a drag source — track the finger in the "chainBlock" space,
        // ring the slot under it, and on release move the processor there (array move, chain folds in the new order). A
        // simultaneousGesture so a plain TAP still opens the editor; a >14pt drag reorders. Empty boxes aren't sources.
        .simultaneousGesture(
            DragGesture(minimumDistance: 14, coordinateSpace: .named("chainBlock"))
                .onChanged { g in
                    guard populated else { return }
                    buildChainDragFrom = i; buildChainDragLoc = g.location
                    buildChainDropTo = buildChainTargetIndex(g.location, boxW: w, boxH: h, gap: gap, count: chain.count)
                }
                .onEnded { _ in
                    if let from = buildChainDragFrom, let to = buildChainDropTo, from != to { buildChainMoveSlot(from: from, to: to) }
                    buildChainDragFrom = nil; buildChainDropTo = nil
                }
        )
    }


    // §2: the INPUT door is PART-owned — one door for the whole part (every colour follows). Applied uniformly at
    // scene-build + audition; no per-colour cell fanning.
    private func buildSelectDoor(_ i: Int) {
        buildRecordUndo()   // BUILD UNDO: pick the input door (receiver)
        buildClearPendingOnEdit()                                // a RECEIVER change ends the fresh-row flash (Paul 2026-08-25)
        if let r = buildSelectedRow, r < buildRowReceiver.count { buildRowReceiver[r] = i }   // override THIS ROW only (per-row I/O, Paul 2026-08-18)
        else if let pc = buildSelectedPlayCol, pc < buildPlayColRecv.count { buildPlayColRecv[pc] = i; buildPublishScene() }   // a selected PLAY cell edits its OWN door (Paul 2026-08-30)
        else { buildSelReceiver = i }                            // nothing on a row → set the part DEFAULT
        ddStickyReceiver = i                                     // a new row inherits the LAST-USED
        receivers = au?.uiReceivers() ?? receivers               // mirror so the source toggle/keyboard reflect the newly-selected door at once
        buildStagingSyncIfPlaying()                              // the row's door applies to its staging cells, live
        refreshFromDocument()
    }





    private func buildToggleBus(_ bus: Bus) {
        buildRecordUndo()   // BUILD UNDO: toggle an output emitter
        buildClearPendingOnEdit()                                // an EMITTER change ends the fresh-row flash (Paul 2026-08-25)
        let selR = buildSelectedRow
        let selPC = selR == nil ? buildSelectedPlayCol : nil       // a selected PLAY cell edits its OWN emitters (Paul 2026-08-30)
        var buses = selR.map { buildRowEmittersResolved($0) }
            ?? selPC.map { $0 < buildPlayColEmit.count ? buildPlayColEmit[$0] : [.a] }
            ?? (buildDefaultEmitters)
        if buses.contains(bus) { buses.remove(bus) } else { buses.insert(bus) }
        if buses.isEmpty { buses = [bus] }                        // never leave a row with no output
        if let r = selR, r < buildRowEmitters.count { buildRowEmitters[r] = buses }   // override THIS ROW only (per-row I/O, Paul 2026-08-18)
        else if let pc = selPC, pc < buildPlayColEmit.count { buildPlayColEmit[pc] = buses }   // the selected play column
        else { buildPartEmitters = buses }                        // nothing on a row → the part DEFAULT
        ddStickyBuses = buses                                     // a new row inherits the LAST-USED
        buildPublishScene()                                       // apply the row's output LIVE to whatever's sounding
    }
    // LONG-PRESS → apply the door to EVERY row (Paul 2026-08-19).
    private func buildSelectDoorAll(_ i: Int) {
        if buildSelectedRow == nil, buildSelectedPlayCol != nil { buildSelectDoor(i); return }   // a play cell has no "all rows" — edit just its door (Paul 2026-08-30)
        buildRecordUndo()   // BUILD UNDO: blanket-apply the door to every row (U7 fix 2026-08-27 — the single-row sibling records; this didn't)
        buildClearPendingOnEdit()                                // a RECEIVER change (all rows) ends the fresh-row flash (Paul 2026-08-25)
        for r in 0..<min(8, buildRowReceiver.count) { buildRowReceiver[r] = i }
        buildSelReceiver = i; ddStickyReceiver = i
        receivers = au?.uiReceivers() ?? receivers
        buildStagingSyncIfPlaying(); refreshFromDocument()
    }
    // LONG-PRESS → toggle the emitter on EVERY row (all rows take the reference row's toggled set). (Paul 2026-08-19)
    private func buildToggleBusAll(_ bus: Bus) {
        if buildSelectedRow == nil, buildSelectedPlayCol != nil { buildToggleBus(bus); return }   // a play cell has no "all rows" — edit just its emitters (Paul 2026-08-30)
        buildRecordUndo()   // BUILD UNDO: blanket-apply the emitter to every row (U7 fix 2026-08-27)
        buildClearPendingOnEdit()                                // an EMITTER change (all rows) ends the fresh-row flash (Paul 2026-08-25)
        var buses = buildSelectedRow.map { buildRowEmittersResolved($0) } ?? (buildDefaultEmitters)
        if buses.contains(bus) { buses.remove(bus) } else { buses.insert(bus) }
        if buses.isEmpty { buses = [bus] }
        for r in 0..<min(8, buildRowEmitters.count) { buildRowEmitters[r] = buses }
        buildPartEmitters = buses; ddStickyBuses = buses
        buildPublishScene()
    }

    // The MIDI-CHAIN voice. Paul 2026-08-15: it plays the selected colour's machine RAW — behind the scenes a 1-row play
    // grid whose EVERY column is "selected", so the machine sounds on every column with NONE of the part grid's column
    // rules. It rides the SAME ephemeral scene as the part/piece (buildPublishScene injects it), so it coexists with the
    // play grid instead of owning the render via an isolating solo. `ddSolo` is just the "chain is the voice" flag now.
    func buildSelectMachineVoice() {
        buildSeedCastIfNeeded()                                  // §2: part 1's cast reflects the already-defined colours (once); selects within the cast
        ddStickyReceiver = buildSelReceiver                      // §2: the chain audition uses the PART's I/O (door + emitters)
        ddStickyBuses = buildDefaultEmitters
        // A document colour never given a chain shows an EMPTY chain but has a nil templateChain; make it an explicit []
        // once so the palette's shown-empty chain matches the raw sound (the injected cell reads buildColourChain, which
        // is [] here → a born-audible passthrough — never the legacy A-face arp). Only fires when the chain is unstored.
        if let cid = ddSelectedColourID, buildColourReg[cid] == nil, au?.colourHasStoredChain(cid) == false {
            au?.withChainColour(cid) { $0 = [] }; refreshFromDocument()   // document colour only — ephemeral colours always carry a registry machine
        }
        buildVoiceOwner = .chain                                // the chain is the voice — sounded RAW via the ephemeral scene (CHAIN ⟂ PART; the PIECE keeps sounding via the scene)
        buildPublishScene()
    }
    private func buildSelectStagingVoice() {
        au?.clearColourSolo()                                    // CHAIN ⟂ PART: leaving the chain audition
        buildVoiceOwner = .part                                 // the PART is the voice (the PIECE keeps sounding ALONGSIDE)
        buildPublishScene()
    }

    // The LIVE workshop voice IS the single-source-of-truth owner (Paul 2026-08-31 — was derived from two booleans that
    // could drift; now the owner is authoritative and ddSolo/buildStagingPlaying are read-only mirrors of it).
    var buildWorkshopVoice: BuildWorkshopVoice { buildVoiceOwner }
    // Read-only mirrors so the ~40 existing reads (composeScene inputs, `if ddSolo`, UI gates) are untouched — only the
    // ~11 WRITE sites route through buildVoiceOwner now, so "who is the voice" lives in ONE place.
    var ddSolo: Bool { buildVoiceOwner == .chain }               // the SELECT chain audition
    var buildStagingPlaying: Bool { buildVoiceOwner == .part }   // the PART sequencer audition
    // The DISPLAYED workshop voice: the armed target if a switch is pending, else the live one. The HEADERS read this so
    // they highlight the new state IMMEDIATELY on tap, while the MIDI still switches quantized at the boundary. (Paul 2026-08-15)
    var buildDisplayVoice: BuildWorkshopVoice { buildPendingWorkshopVoice ?? buildWorkshopVoice }

    // A header TOGGLES its section: play it if stopped, STOP it if playing (Paul 2026-08-15). Both sections can be off.
    // While the transport runs the switch is QUANTIZED to the next cell boundary (buildCommitPendingVoice, fired from the
    // VC's absoluteStep hook) so it lands on the grid, not mid-cell. Stopped, or re-requesting the live voice → immediate.
    func buildRequestWorkshopVoice(_ target: BuildWorkshopVoice) {
        if d.playing && target != buildWorkshopVoice {
            buildPendingWorkshopVoice = target                   // arm — applied at the next cell boundary
        } else {
            buildPendingWorkshopVoice = nil
            buildApplyWorkshopVoice(target)
        }
    }
    private func buildApplyWorkshopVoice(_ v: BuildWorkshopVoice) {
        switch v {
        case .chain: buildSelectMachineVoice()
        case .part:  buildSelectStagingVoice()
        case .none:  buildStopWorkshop()
        }
    }
    // Stop BOTH shop sections (the header's STOP action). The PIECE (play grid) is independent and keeps sounding.
    private func buildStopWorkshop() {
        au?.clearColourSolo()
        buildVoiceOwner = .none
        buildPublishScene()
    }
    // (The reference-chord fallback — engine + UI — was REMOVED 2026-08-23, Paul: a synthetic chord must never reach
    // the user. PLAY THIS MIDI CHAIN sounds only real input; silent when nothing is held.)
    // Apply an armed voice switch at a cell boundary (or on transport stop). Called from the VC.
    func buildCommitPendingVoice() {
        if let v = buildPendingWorkshopVoice {
            buildPendingWorkshopVoice = nil; buildPendingReengage = false
            buildApplyWorkshopVoice(v)
        } else if buildPendingReengage {                 // a palette colour change → re-inject the new chain colour on the boundary
            buildPendingReengage = false
            if ddSolo { buildPublishScene() }
        }
    }

    // Publish the ephemeral scene for the ACTIVE voices. §correction (2026-08-13): the PIECE is INDEPENDENT of the
    // audition — PLAY THIS PART + START/STOP THE PLAY GRID sound TOGETHER (the shopping/alongside workflow). Each
    // staging/perform cell takes its PART-owned I/O + the colour's machine (or a staged variation chain). Paul 2026-08-15:
    // the MIDI CHAIN now ALSO rides this scene (a 1-row grid, every column active → raw, no part-grid column rules), so it
    // sounds ALONGSIDE the play grid instead of owning the render via a solo.
    // The SHELL: gather @State into a pure input, let BuildSceneLogic.composeScene do the work (testable), publish it.
    // SCENES V2 (Paul 2026-08-12): capture the current play-grid ARRANGEMENT (not the shared parts/colours) into a snapshot.
    func buildCaptureCurrentScene() -> BuildSceneSnapshot {   // internal: the reel poll (other file) captures per-pass state (#5)
        BuildSceneSnapshot(performCells: buildPerformCells, performChain: buildPerformChain, performRecv: buildPerformRecv,
                           performEmit: buildPerformEmit, performPart: buildPerformPart, performMute: buildPerformMute,
                           performStagingRow: buildPerformStagingRow, performLane: buildPerformLane, row8On: buildRow8On)
    }
    private func buildRestoreScene(_ s: BuildSceneSnapshot) {
        buildPerformCells = s.performCells; buildPerformChain = s.performChain; buildPerformRecv = s.performRecv
        buildPerformEmit = s.performEmit; buildPerformPart = s.performPart; buildPerformMute = s.performMute
        buildPerformStagingRow = s.performStagingRow; buildPerformLane = s.performLane
        buildPerformPlaying = buildPerformPart.contains { $0 >= 0 }
        for i in 0..<min(8, s.row8On.count) { au?.setRow8On(i, s.row8On[i]) }   // restore the scene's ROW 8 lit toggles
        buildRow8On = s.row8On
        buildPublishScene()                                     // reflect the new arrangement live (instant switch, v1)
    }
    /// SCENES V2 (Paul 2026-08-24): USE THE EXISTING scene strip (ArrangementBar, below the main header). It drives the
    /// document's `activeScene`; the VC polls it into `activeSceneIdx`. When it changes, BUILD SAVES the arrangement it was
    /// showing into the old slot and RESTORES the target slot's — so the existing chips switch play-grid arrangements. The
    /// parts/colours/master stay shared (a scene arranges the same band). v1: in-memory, instant (pass-quant + persist = follow-ups).
    func buildSyncSceneSwitch(_ newIdx: Int) {
        guard newIdx >= 0, newIdx != buildActiveScene else { return }
        while buildScenes.count <= max(newIdx, buildActiveScene) { buildScenes.append(buildCaptureCurrentScene()) }   // grow lazily (a fresh slot = a copy of the current)
        buildScenes[buildActiveScene] = buildCaptureCurrentScene()   // save where we were
        buildActiveScene = newIdx
        buildRestoreScene(buildScenes[newIdx])                        // load the target arrangement
    }
    // PERSISTENCE (Paul 2026-08-24): the scenes travel with the document — and since a scene snapshot IS the deployed
    // play grid, this also persists the deployed arrangement (the long-open gap). Fold the LIVE arrangement into the active
    // slot so what's on screen is what's saved; single-scene use still persists slot 0.
    func buildCaptureScenes() -> [BuildSceneSnapshot] {
        var s = buildScenes
        let cur = buildCaptureCurrentScene()
        if s.isEmpty { s = [cur] }
        else if buildActiveScene >= 0, buildActiveScene < s.count { s[buildActiveScene] = cur }
        return s
    }
    func buildRestoreScenes(_ scenes: [BuildSceneSnapshot], active: Int) {
        guard !scenes.isEmpty else { return }
        buildScenes = scenes
        buildActiveScene = max(0, min(scenes.count - 1, active))
        buildRestoreScene(scenes[buildActiveScene])                  // restore the live arrangement (the deployed grid) + republish
    }

    // ── BUILD UNDO (Paul 2026-08-27) — snapshot the WHOLE authoring @State + the document, so a restore is complete ────
    func buildCaptureSnapshot() -> BuildSnapshot {
        BuildSnapshot(stagingCells: buildStagingCells, stagingSel: buildStagingSel, stagingLane: buildStagingLane,
                      parts: buildParts, currentPart: buildCurrentPart, returnPart: buildReturnPart,
                      partEmitters: buildPartEmitters, partRate: buildPartRate, partLen: buildPartLen,
                      partCast: buildPartCast, castSlots: buildCastSlots, rowUnder: buildRowUnder,
                      rowReceiver: buildRowReceiver, rowEmitters: buildRowEmitters,
                      performCells: buildPerformCells, performChain: buildPerformChain, performRecv: buildPerformRecv,
                      performEmit: buildPerformEmit, performPart: buildPerformPart, performMute: buildPerformMute,
                      performStagingRow: buildPerformStagingRow, performLane: buildPerformLane,
                      scenes: buildScenes, activeScene: buildActiveScene, row8Cells: buildRow8Cells, row8On: buildRow8On,
                      selID: buildSelID, selReceiver: buildSelReceiver, colourReg: buildColourReg,
                      colourTranspose: buildColourTranspose, hueOverride: colourHueOverride, idCounter: buildIDCounter,
                      playCells: buildPlayCells, playSel: buildPlaySel, playColOn: buildPlayColOn, playColRecv: buildPlayColRecv,
                      playColEmit: buildPlayColEmit, playColLen: buildPlayColLen, playColSteps: buildPlayColSteps,
                      playColRate: buildPlayColRate, playColStepRecv: buildPlayColStepRecv, playColStepEmit: buildPlayColStepEmit,
                      doc: au?.documentSnapshot() ?? PluginState.makeInit())
    }
    /// Record the pre-action state. Call at the START of any authoring action. `coalesce` collapses a continuous gesture
    /// (a scrub/drag) into ONE step. A missed call just leaves that action non-undoable — never corrupts (restore is whole).
    func buildRecordUndo(_ coalesce: String? = nil) {
        if buildApplyingSnapshot { return }   // an onChange fired mid-restore — never record while applying an undo/redo
        if let k = coalesce, k == buildUndoKey, !buildUndoStack.isEmpty { return }
        buildUndoStack.append(buildCaptureSnapshot())
        if buildUndoStack.count > 64 { buildUndoStack.removeFirst(buildUndoStack.count - 64) }   // bounded depth
        buildRedoStack.removeAll()
        buildUndoKey = coalesce
    }
    private func buildApplySnapshot(_ s: BuildSnapshot) {
        buildApplyingSnapshot = true
        defer { buildApplyingSnapshot = false }
        buildStagingCells = s.stagingCells; buildStagingSel = s.stagingSel; buildStagingLane = s.stagingLane
        buildParts = s.parts; buildCurrentPart = s.currentPart; buildReturnPart = s.returnPart
        buildPartEmitters = s.partEmitters; buildPartRate = s.partRate; buildPartLen = s.partLen
        buildPartCast = s.partCast; buildCastSlots = s.castSlots; buildRowUnder = s.rowUnder
        buildRowReceiver = s.rowReceiver; buildRowEmitters = s.rowEmitters
        buildPerformCells = s.performCells; buildPerformChain = s.performChain; buildPerformRecv = s.performRecv
        buildPerformEmit = s.performEmit; buildPerformPart = s.performPart; buildPerformMute = s.performMute
        buildPerformStagingRow = s.performStagingRow; buildPerformLane = s.performLane
        buildScenes = s.scenes; buildActiveScene = s.activeScene; buildRow8Cells = s.row8Cells; buildRow8On = s.row8On
        buildSelID = s.selID; buildSelReceiver = s.selReceiver
        buildColourReg = s.colourReg; buildColourTranspose = s.colourTranspose; colourHueOverride = s.hueOverride
        buildIDCounter = s.idCounter
        buildPlayCells = s.playCells; buildPlaySel = s.playSel; buildPlayColOn = s.playColOn; buildPlayColRecv = s.playColRecv
        buildPlayColEmit = s.playColEmit; buildPlayColLen = s.playColLen; buildPlayColSteps = s.playColSteps
        buildPlayColRate = s.playColRate; buildPlayColStepRecv = s.playColStepRecv; buildPlayColStepEmit = s.playColStepEmit
        au?.restoreDocumentFromUndo(s.doc)          // the document (document-colour chains / receivers / rack) restored WITHOUT recording
        buildSyncColours()                          // push the ephemeral registry to the render
        buildPublishScene()                         // re-publish the composed scene
        receivers = au?.uiReceivers() ?? receivers
        refreshFromDocument()                       // reload document-derived state (docColours, receivers, rack, ROW 8…)
        buildUndoKey = nil                          // a fresh coalesce run after any undo/redo
    }
    /// A door-sheet receiver-config edit (channel · range · scale · exclude · …): record a BUILD-undo step (coalesced into
    /// one "recv" burst so a run of config tweaks is a single undo), run the AU mutation, then re-poll + refresh. Keeps the
    /// config edits inside the BUILD undo stack (the header no longer reaches the AU stack).
    func buildRecvEdit(_ body: () -> Void) {
        buildRecordUndo("recv")
        body()
        receivers = au?.uiReceivers() ?? receivers
        refreshFromDocument()
    }
    func buildDoUndo() { guard let prev = buildUndoStack.popLast() else { return }; buildRedoStack.append(buildCaptureSnapshot()); buildApplySnapshot(prev) }
    func buildDoRedo() { guard let next = buildRedoStack.popLast() else { return }; buildUndoStack.append(buildCaptureSnapshot()); buildApplySnapshot(next) }
    var buildCanUndo: Bool { !buildUndoStack.isEmpty }
    var buildCanRedo: Bool { !buildRedoStack.isEmpty }

    private func buildPublishScene() {
        au?.clearColourSolo()                                    // BUILD never uses the AU solo now — drop any left by the vestigial ddCreateColour path, so the scene sweeps freely
        // (the loop keys now DRIVE the lap — same `laneMask` as the GRID tab; a held column-set laps the workshop. Paul 2026-08-19)
        var input = BuildSceneLogic.Input()
        input.stagingPlaying = buildStagingPlaying
        input.performPlaying = buildPerformPlaying
        input.chainActive = ddSolo
        input.performCells = buildPerformCells
        input.performMute = buildPerformMute
        input.performActiveRung = { self.buildPerformActiveRung($0, $1) }
        input.performEmit = buildPerformEmit
        input.performRecv = buildPerformRecv
        // RESOLVE the effective chain per PERFORM cell (Paul 2026-08-23): a per-cell VARIATION if it has one, else the
        // colour's OWN machine (buildColourChain → [] for a NO-MACHINE colour). composeScene then passes it EXPLICITLY,
        // so a no-machine cell is a passthrough (live wire) in the play grid too — not only via PLAY THIS MIDI CHAIN.
        input.performChain = (0..<Snap.maxCols).map { c in (0..<8).map { r -> [ProcessorSlot] in   // §E: 16 part columns × 8 rows
            let v = (c < buildPerformChain.count && r < buildPerformChain[c].count) ? buildPerformChain[c][r] : []
            let cid = (c < buildPerformCells.count && r < buildPerformCells[c].count) ? buildPerformCells[c][r] : nil
            return v.isEmpty ? buildColourChain(cid ?? "") : v
        } }
        input.stagingCells = buildStagingCells
        input.stagingSel = buildStagingSel
        input.partEmitters = buildPartEmitters
        input.selReceiver = buildSelReceiver
        input.rowReceiver = (0..<8).map { buildRowReceiverResolved($0) }     // per-row I/O, resolved (nil → part default)
        input.rowEmitters = (0..<8).map { buildRowEmittersResolved($0) }
        // RESOLVE the effective chain per STAGING row (same rule as PERFORM/CHAIN): the row's VARIATION if present, else
        // the row colour's OWN machine ([] for a no-machine colour → passthrough wire). (Paul 2026-08-23)
        input.rowChain = (0..<8).map { r -> [ProcessorSlot] in
            let v = r < buildRowChain.count ? buildRowChain[r] : []
            return v.isEmpty ? buildColourChain(buildRowColour(r) ?? "") : v
        }
        if ddSolo, let cid = ddSelectedColourID {
            input.chainColourID = cid
            input.chainMachine = buildColourChain(cid)
        }
        let selR = buildSelectedRow                                          // the chain audition takes the SELECTED colour's row I/O
        input.chainReceiver = selR.map { buildRowReceiverResolved($0) } ?? buildSelReceiver
        input.chainEmitters = selR.map { buildRowEmittersResolved($0) } ?? (buildDefaultEmitters)
        // PER-PART CLOCK (Paul 2026-08-19): each play-grid ROW takes its owning deployed part's rate/length; the STAGING
        // audition takes the CURRENT part's. nil ⇒ the scene default (uniform = today). This is what makes deployed parts
        // at different rates play at DIFFERENT tempos in one play grid.
        input.performRate = (0..<8).map { r in let p = buildPerformPart[r]; return (p >= 0 && p < buildParts.count) ? buildParts[p].rate : nil }
        input.performLen  = (0..<8).map { r in let p = buildPerformPart[r]; return (p >= 0 && p < buildParts.count) ? buildParts[p].length : nil }
        input.stagingRate = buildPartRate
        input.stagingLen  = buildPartLen
        input.stagingLane = buildStagingLane                     // PER-ROW LAP: the two grids loop independently
        input.performLane = buildPerformLane
        // THE PLAY GRID (Paul 2026-08-29): each column an INDEPENDENT voice — only STARTED columns (buildPlayColOn) sound,
        // each carrying its ferried machine AND the I/O it was ferried with (buildPlayColRecv/Emit). No shared I/O toggles.
        input.playPlaying = buildPlayColOn.contains(true)
        input.playCells = buildPlayCells
        input.playSel = buildPlaySel
        input.playColOn = buildPlayColOn
        input.playColRecv = buildPlayColRecv
        input.playColEmit = buildPlayColEmit
        input.playColChain = (0..<8).map { c -> [ProcessorSlot] in
            let r = c < buildPlaySel.count ? buildPlaySel[c] : -1
            guard r >= 0, r < 8, c < buildPlayCells.count, r < buildPlayCells[c].count, let cid = buildPlayCells[c][r] else { return [] }
            return buildColourChain(cid)
        }
        // MULTI-STEP PASS (Paul 2026-08-30): a flattened part rides a play column as N steps — resolve each step's chain here.
        input.playColLen = buildPlayColLen
        input.playColSteps = buildPlayColSteps
        input.playColRate = buildPlayColRate
        input.playColStepRecv = buildPlayColStepRecv
        input.playColStepEmit = buildPlayColStepEmit
        input.playColStepChain = (0..<8).map { c -> [[ProcessorSlot]] in
            let len = c < buildPlayColLen.count ? buildPlayColLen[c] : 1
            guard len > 1, c < buildPlayColSteps.count else { return [] }
            return buildPlayColSteps[c].map { cid in cid.map { buildColourChain($0) } ?? [] }
        }
        input.partAuto = buildAutoLanes                                       // PART AUTOMATION (Paul 2026-09-02): bake the active AUTO lanes per cell
        let composed = BuildSceneLogic.composeSceneMeta(input)
        au?.setBuildStagingScene(composed.scene)
        buildChainAuditionRow = composed.auditionRow                          // #5: the engine row the audition parked on → the aimed ferry reads its LIVE strikes there
        // (The reference-chord fallback was REMOVED 2026-08-23, Paul: PLAY THIS MIDI CHAIN now sounds ONLY real input —
        // a synthetic C-major triad must never reach the user. With nothing held the audition is simply silent.)
        // FREE-RUN GATE (Paul 2026-08-31): "when I press play, start playing." Pressing a PLAY control in 8x8 arms a voice
        // (ddSolo chain audition · buildStagingPlaying part · a play column), and THAT drives the internal clock so it sounds
        // even while the host transport is stopped — an explicit play starts playback. Nothing auto-plays (roomsSyncVoice no
        // longer auto-auditions), and a HOST transport-stop edge still clears the armed voices (buildStopAllOnTransportStop),
        // so a stopped host with nothing pressed stays silent.
        au?.setFreeRunEnabled(ddSolo || buildStagingPlaying || buildPerformPlaying || buildPlayPlaying)
    }
    // TRANSPORT STOPPED → stop everything (Paul 2026-08-31). Clears the shared audition + every play column and republishes,
    // so the machine play button, the ferries, the cells and the comets/rolls all read STOPPED. Called on the d.playing
    // falling edge (the poll's transport flag).
    func buildStopAllOnTransportStop() {
        var changed = false
        if buildVoiceOwner != .none { buildVoiceOwner = .none; changed = true }
        for i in buildPlayColOn.indices where buildPlayColOn[i] { buildPlayColOn[i] = false; changed = true }
        buildPendingWorkshopVoice = nil; buildPendingReengage = false
        if changed { au?.clearColourSolo(); buildPublishScene() }
    }
    // The staging row currently being EDITED = the row holding the selected colour (nil ⇒ nothing on a row). (Paul 2026-08-18)
    private var buildSelectedRow: Int? {
        guard let id = buildSelID else { return nil }
        return (0..<8).first { buildRowColour($0) == id }
    }
    // PER-ROW I/O resolution (Paul 2026-08-18): a row's OWN door/emitters, or the part default when unset (nil).
    private func buildRowReceiverResolved(_ r: Int) -> Int {
        ((r >= 0 && r < buildRowReceiver.count) ? buildRowReceiver[r] : nil) ?? buildSelReceiver
    }
    private func buildRowEmittersResolved(_ r: Int) -> Set<Bus> {
        let own = (r >= 0 && r < buildRowEmitters.count) ? buildRowEmitters[r] : nil
        if let own, !own.isEmpty { return own }
        return buildDefaultEmitters
    }

    // A colour's OWN machine (templateChain), audible slots only.
    // A colour's machine — EPHEMERAL registry (beyond the 16) OR the document templateChain (the canonical 16).
    private func buildColourMachine(_ cid: String) -> [ProcessorSlot] {
        buildColourReg[cid] ?? (docColours.first { $0.colourID == cid }?.templateChain ?? [])
    }
    private func buildColourChain(_ cid: String) -> [ProcessorSlot] {
        buildColourMachine(cid).filter { !buildIsEmptySlot($0) }
    }
    // Write a colour's machine to the right store, and reflect it live.
    private func buildWriteColourMachine(_ cid: String, _ chain: [ProcessorSlot]) {
        if buildColourReg[cid] != nil { buildColourReg[cid] = chain; buildSyncColours() }   // ephemeral
        else { au?.setColourChain(cid, chain); refreshFromDocument() }                       // document colour
        buildStagingSyncIfPlaying()
    }
    // Push the ephemeral colour registry to the AU so renderDoc appends them (their machines resolve).
    func buildSyncColours() { au?.setBuildEphemeralColours(buildColourReg.map { (id: $0.key, machine: $0.value, transpose: buildColourTranspose[$0.key] ?? 0) }) }
    // Allocate a NEW colour carrying `machine` + a custom hue: a free DOCUMENT slot if one remains, else an unlimited
    // EPHEMERAL colour ("b<n>"). Returns its id. (Paul 2026-08-15 — lifts the 16-slot cap.)
    private func buildNewColour(hex rawHex: UInt32, machine: [ProcessorSlot]) -> String {
        let hex = buildUniqueHue(rawHex)                                     // RULE: no two colours share a hue (Paul 2026-08-16)
        if let j = buildFirstUndefinedGlobal() {
            let id = colourIDs[j]
            ddCreateColour(j); au?.withChainColour(id) { $0 = machine }; refreshFromDocument()
            colourHueOverride[id] = hex
            return id
        }
        buildIDCounter += 1
        let id = "b\(buildIDCounter)"
        buildColourReg[id] = machine; colourHueOverride[id] = hex; buildSyncColours()
        return id
    }
    // Select a colour BY ID (document or ephemeral) — the ID-based BUILD selection.
    private func buildSelectID(_ id: String) {
        buildExitPlaceMode()                                     // choosing a colour is a non-(play-row) touch → leave PLACE mode
        buildSelID = id                                          // the DISPLAY selection updates immediately (target, footer, highlight)
        ddColourSel = colourIDs.firstIndex(of: id) ?? -1
        ddStickyReceiver = buildSelReceiver
        ddStickyBuses = buildDefaultEmitters
        ddScopeToColour(id, anchor: nil, engage: false)          // BUILD never uses the AU solo — the chain plays via the scene
        if ddSolo {                                              // auditioning the chain → re-inject the newly-selected colour
            if d.playing { buildPendingReengage = true }         // SEAMLESS: swap on the next cell boundary
            else { buildPublishScene() }                         // stopped → immediate
        }
    }
    // The base hue of a colour (its override if any, else its palette hex).
    private func buildBaseHex(_ id: String) -> UInt32 { colourHueOverride[id] ?? colourIDs.firstIndex(of: id).map { colourHexes[$0] } ?? 0x808080 }
    // Every hue currently IN USE by a live colour: the materialised document colours + every ephemeral/recoloured
    // override. An UNASSIGNED canonical hex is NOT counted — so a new colour can claim a genuinely distinct
    // canonical hue rather than a near-shade of its source. (Paul 2026-08-17)
    private func buildUsedHues() -> Set<UInt32> {
        var used = Set(colourHueOverride.values)
        for (i, id) in colourIDs.enumerated() where ddColourShown(i) { used.insert(buildBaseHex(id)) }
        return used
    }
    // A hue guaranteed UNUSED and, wherever possible, VISIBLY distinct: an unassigned canonical palette hue first,
    // else a canonical seed perturbed until it clears everything in use. The engine behind the "no two alike" rule.
    private func buildDistinctHue() -> UInt32 {
        let used = buildUsedHues()
        if let fresh = colourHexes.first(where: { !used.contains($0) }) { return fresh }
        for seed in colourHexes {
            var h = seed, n = 0
            while used.contains(h) && n < 128 { n += 1; h = buildPerturbHex(seed, by: n) }
            if !used.contains(h) { return h }
        }
        return 0x808080
    }
    // STRONG RULE (Paul 2026-08-17): no two colours may EVER share a hue. Keep `hex` if it is free, else nudge to
    // the nearest distinct shade, and if THAT still collides fall back to a guaranteed-distinct hue. Never returns
    // a used hue.
    private func buildUniqueHue(_ hex: UInt32) -> UInt32 {
        let used = buildUsedHues()
        if !used.contains(hex) { return hex }
        var h = hex, n = 0
        while used.contains(h) && n < 128 { n += 1; h = buildPerturbHex(hex, by: n) }
        return used.contains(h) ? buildDistinctHue() : h
    }
    // STRONG RULE: no two PALETTE (cast) colours share a hue. Any member whose hue duplicates an earlier member is
    // recoloured to a distinct hue. Call after any cast mutation.
    private func buildEnforceCastHues() {
        var seen = Set<UInt32>(); var changed = false
        for id in buildPartCast {
            let h = buildBaseHex(id)
            if seen.contains(h) { let nh = buildDistinctHue(); colourHueOverride[id] = nh; seen.insert(nh); changed = true }
            else { seen.insert(h) }
        }
        if changed { buildSyncColours() }
    }
    private func buildPerturbHex(_ h: UInt32, by d: Int) -> UInt32 {
        func ch(_ shift: Int) -> UInt32 { let c = Int((h >> shift) & 0xFF); return UInt32(max(0, min(255, c + (c < 128 ? d : -d)))) }   // push each channel toward its extreme by an increasing step
        return (ch(16) << 16) | (ch(8) << 8) | ch(0)
    }
    // Perceived darkness of a hex — used to invert a row button's background when its coloured icon would vanish.
    private func buildIsDark(_ hex: UInt32) -> Bool {
        let r = Double((hex >> 16) & 0xFF), g = Double((hex >> 8) & 0xFF), b = Double(hex & 0xFF)
        return (0.299 * r + 0.587 * g + 0.114 * b) / 255.0 < 0.45
    }
    // The row button's background: normally the muted rail; but in PLACE/MUTATE, if the SELECTED colour (the icon
    // colour) is DARK, invert to a light button so the icon still reads. (Paul 2026-08-16)





    // Push the current staging grid to the engine IF the staging voice is live (call after any staging-grid edit).
    private func buildStagingSyncIfPlaying() { buildPublishScene() }   // re-publish the combined (part + piece) scene after an edit

    // BUILD RANDOMIZE — the SIMPLER roll (a short 1–3-slot all-contributing chain, no macros); writes it colour-wide.
    private func buildRandomizeSimple() {
        guard let cid = ddSelectedColourID else { return }
        var rng = SystemRandomNumberGenerator()
        au?.withChainColour(cid) { $0 = Dice.rollSimple(using: &rng) }
        refreshFromDocument()
    }
    // <<< MUTATE — nudge the SELECTED colour's midi chain in place (a value-tweaked variant of its OWN machine). (Paul 2026-08-18)
    private func buildMutateChain() {
        guard let cid = ddSelectedColourID else { return }
        let base = buildColourChain(cid)
        var rng = SystemRandomNumberGenerator()
        if let mutated = BuildSceneLogic.mutateChain(base, avoid: [Dice.fingerprint(base)], &rng) { buildWriteColourMachine(cid, mutated) }
        refreshFromDocument()
    }
    // <<< CLEAR — empty the SELECTED colour's midi chain (every processor box → "+"). (Paul 2026-08-18)
    private func buildClearChain() {
        buildRecordUndo()   // BUILD UNDO: clear the selected colour's chain
        guard let cid = ddSelectedColourID else { return }
        buildWriteColourMachine(cid, [])
        refreshFromDocument()
    }
    // <<< COPY / PASTE (Paul 2026-08-25): COPY grabs the SELECTED colour's chain into a buffer; PASTE drops that chain
    // into a NEW row (mints a fresh colour carrying it on the first empty row, then selects it). PASTE is disabled
    // until the buffer holds a non-empty chain. Used to copy one chain into a new row position.
    private func buildCopyChain() {
        let chain = selectedColourChain()
        guard !chain.isEmpty else { return }               // nothing to copy → leave the buffer (paste stays disabled)
        buildChainClipboard = chain
    }
    private func buildPasteChain() {
        buildRecordUndo()   // BUILD UNDO: paste a chain onto a new colour
        guard let chain = buildChainClipboard, !chain.isEmpty else { return }
        guard let row = (0..<8).first(where: { buildRowColour($0) == nil }) else { return }   // the first EMPTY row (a new position)
        let newID = buildNewColour(hex: buildDistinctHue(), machine: chain)
        if row < buildRowUnder.count { buildRowUnder[row] = nil }   // an empty row displaces nothing
        buildSetRow(row, to: newID)
        buildSelectID(newID)                               // focus the pasted colour
        for c in 0..<Snap.maxCols { buildStagingSel[c] = row }        // select the whole new row (like PLACE/MUTATE) — §E 16-col
        buildStagingSyncIfPlaying()
    }

    // The selected colour's OWN processors (its templateChain) — shown on the footer. Interior EMPTY boxes (passthrough
    // placeholders) are kept so a processor's POSITION is remembered even with empty boxes to its left; TRAILING empties
    // collapse to "+" capacity slots. A fully blank/new colour → [] (all boxes are "+").
    private func selectedColourChain() -> [ProcessorSlot] {
        guard let cid = ddSelectedColourID else { return [] }
        var chain = buildColourMachine(cid)
        while let last = chain.last, buildIsEmptySlot(last) { chain.removeLast() }
        return chain
    }
    // The FOCUSED machine's chain for the AUTO flow (Paul 2026-09-01): the selected colour's built chain, else its A-FACE
    // as a single slot. A canonical/factory colour stores its machine as `type`+`paramsA` (not a templateChain), which
    // buildColourMachine doesn't surface — the SnapshotBuilder resolves exactly this fallback, so mirror it here so the
    // PROCESSOR list populates for ANY focused colour that actually has a processor (was empty for A-face colours).
    func buildFocusedChain() -> [ProcessorSlot] {
        let c = selectedColourChain()
        if !c.isEmpty { return c }
        guard let cid = ddSelectedColourID, let col = docColours.first(where: { $0.colourID == cid }) else { return [] }
        var s = ProcessorSlot(type: col.type); s.params = col.paramsA
        return buildIsEmptySlot(s) ? [] : [s]
    }
    // An EMPTY processor box = a passthrough placeholder (a bypassed PASSGATE — a true no-op the engine passes through).
    private func buildIsEmptySlot(_ s: ProcessorSlot) -> Bool { s.type == .passgate && s.bypassed }
    private func buildPassthroughSlot() -> ProcessorSlot { var s = ProcessorSlot(type: .passgate); s.bypassed = true; return s }

    // Normalise a decoded staging grid to EXACTLY 8×8 (Paul 2026-09-01 bug-hunt Finding 3): a corrupt / truncated / hand-
    // edited saved doc can decode stagingCells/Sel with < 8 columns or short columns (BuildPart.init only substitutes the
    // default when the KEY is absent, not when it's present-but-ragged). The write/tap siblings (buildStagingTap / buildSetRow
    // / buildSelectRow / buildPopulateTab / buildPasteChain / buildSeedTab1) index [c][r] UNGUARDED → a trap. Pad/clamp on the
    // load boundary so every downstream write is in-bounds (the read siblings were already ragged-safe).
    private func buildNormalizeStaging(_ cells: [[String?]], _ sel: [Int]) -> (cells: [[String?]], sel: [Int]) {
        var c = cells                                       // §E: normalize to maxCols(16) COLUMNS × 8 visible ROWS (was 8×8 — truncated 16-wide parts)
        if c.count > Snap.maxCols { c = Array(c.prefix(Snap.maxCols)) }
        while c.count < Snap.maxCols { c.append(Array(repeating: nil, count: 8)) }
        for i in c.indices {
            if c[i].count > 8 { c[i] = Array(c[i].prefix(8)) }
            while c[i].count < 8 { c[i].append(nil) }
        }
        var s = sel
        if s.count > Snap.maxCols { s = Array(s.prefix(Snap.maxCols)) }
        while s.count < Snap.maxCols { s.append(-1) }
        return (c, s)
    }
    private func buildLoadPart(_ i: Int) {
        guard i >= 0, i < buildParts.count else { return }
        buildCurrentPart = i
        let p = buildParts[i]
        let ns = buildNormalizeStaging(p.stagingCells, p.stagingSel); buildStagingCells = ns.cells; buildStagingSel = ns.sel
        buildRowChain = p.rowChain; buildRowShade = p.rowShade; buildRowUnder = p.rowUnder
        buildSelID = p.selID; ddColourSel = p.selID.flatMap { colourIDs.firstIndex(of: $0) } ?? -1; buildSelReceiver = p.receiver; buildPartEmitters = p.emitters; buildPartCast = p.cast; buildCastSlots = p.castSlots
        buildRowReceiver = p.rowReceiver ?? Array(repeating: nil, count: 8)   // PER-ROW I/O — old parts have nil → all rows inherit (Paul 2026-08-18)
        buildRowEmitters = p.rowEmitters ?? Array(repeating: nil, count: 8)
        buildPartRate = p.rate; buildPartLen = p.length                       // PER-PART CLOCK (Paul 2026-08-19)
        buildReslotCast()                                       // migrate old parts + backfill any extra colour missing a slot
        buildEnforceCastHues()                                  // strong rule: no two palette colours share a hue
        buildPulseColourID = nil; buildAuditionID = nil; buildDeletedRows = [:]   // transient — never crosses a part
        buildEnsureCastSelection()                              // §2: keep the selection inside this part's cast (empty cast → none)
        buildStagingSyncIfPlaying()
    }

    // ── PERSISTENCE (Paul 2026-08-16): the single UNASSIGNED part is saved with the document ("saving = committing").
    // CAPTURE is READ-ONLY (never touches @State, so it's safe to call from the 4 Hz poll): the live workshop if the
    // current part is the unassigned one, else the stored unassigned part. Bundles the EPHEMERAL colours it references
    // (machine + hue) so it reconstructs on load; canonical document colours are always present, so they aren't bundled.
    func buildCaptureUnassigned() -> BuildUnassignedData? {
        let part: BuildPart
        if buildCurrentPart >= 0, buildCurrentPart < buildParts.count, !buildParts[buildCurrentPart].deployed {
            var p = BuildPart()                                 // the live workshop IS the unassigned part — freshest from @State
            p.stagingCells = buildStagingCells; p.stagingSel = buildStagingSel; p.rowChain = buildRowChain
            p.rowShade = buildRowShade; p.rowUnder = buildRowUnder; p.selID = buildSelID
            p.receiver = buildSelReceiver; p.emitters = buildPartEmitters; p.cast = buildPartCast; p.castSlots = buildCastSlots; p.deployed = false
            p.rate = buildPartRate; p.length = buildPartLen         // PER-PART CLOCK (Paul 2026-08-19)
            part = p
        } else if let stored = buildParts.first(where: { !$0.deployed }) {
            part = stored                                       // viewing a deployed part → the unassigned one is stored
        } else { return nil }
        guard part.stagingCells.contains(where: { $0.contains { $0 != nil } }) else { return nil }   // no content yet → nothing to save
        var ids = Set(part.cast)                                // every colour the part could reference
        ids.formUnion(part.stagingCells.flatMap { $0.compactMap { $0 } })
        ids.formUnion(part.rowUnder.compactMap { $0 })
        if let s = part.selID { ids.insert(s) }
        let ephemeral = ids.filter { buildColourReg[$0] != nil }.sorted()
        let colours = ephemeral.map { id -> Colour in var c = Colour(colourID: id, type: .arp); c.defined = true; c.templateChain = buildColourReg[id]; c.transpose = buildColourTranspose[id] ?? 0; return c }   // carry the register-home so a saved ensemble restores in the right octave (BUG state-loss 2026-08-29)
        var hues: [String: UInt32] = [:]; for id in ephemeral { if let h = colourHueOverride[id] { hues[id] = h } }
        return BuildUnassignedData(part: part, colours: colours, hues: hues, idCounter: buildIDCounter)
    }
    // RESTORE the saved unassigned part on load: re-register its ephemeral colours + hues, lift the id counter past
    // them (so new colours don't collide), then place it as the single unassigned part and load it into the workshop.
    func buildRestoreUnassigned(_ u: BuildUnassignedData) {
        for c in u.colours { buildColourReg[c.colourID] = c.templateChain ?? []; if c.transpose != 0 { buildColourTranspose[c.colourID] = c.transpose } }   // restore the register-home too (BUG state-loss 2026-08-29)
        for (id, hue) in u.hues { colourHueOverride[id] = hue }
        buildIDCounter = max(buildIDCounter, u.idCounter)
        buildSyncColours()
        var part = u.part; part.deployed = false
        if let i = buildParts.firstIndex(where: { !$0.deployed }) { buildParts[i] = part; buildLoadPart(i) }
        else { buildParts.append(part); buildLoadPart(buildParts.count - 1) }
    }
    // THE ROOMS PLAY GRID (Paul 2026-08-30): capture the 8 play columns + their multi-step passes + the ephemeral colours
    // they reference, so a reload restores the whole play grid. Only when there's content (a populated/multi-step column).
    func buildCapturePlayGrid() -> BuildPlayGridData? {
        let hasContent = (0..<8).contains { c in buildPlayColPopulated(c) || (c < buildPlayColLen.count && buildPlayColLen[c] > 1) }
        guard hasContent else { return nil }
        var ids = Set<String>()
        for col in buildPlayCells { for cell in col { if let id = cell { ids.insert(id) } } }
        for col in buildPlayColSteps { for step in col { if let id = step { ids.insert(id) } } }
        let ephemeral = ids.filter { buildColourReg[$0] != nil }.sorted()
        let colours = ephemeral.map { id -> Colour in var c = Colour(colourID: id, type: .arp); c.defined = true; c.templateChain = buildColourReg[id]; c.transpose = buildColourTranspose[id] ?? 0; return c }
        var hues: [String: UInt32] = [:]; for id in ephemeral { if let h = colourHueOverride[id] { hues[id] = h } }
        return BuildPlayGridData(cells: buildPlayCells, sel: buildPlaySel, colOn: buildPlayColOn, colRecv: buildPlayColRecv,
                                 colEmit: buildPlayColEmit, colLen: buildPlayColLen, colSteps: buildPlayColSteps, colRate: buildPlayColRate,
                                 colStepRecv: buildPlayColStepRecv, colStepEmit: buildPlayColStepEmit, colours: colours, hues: hues, idCounter: buildIDCounter)
    }
    func buildRestorePlayGrid(_ d: BuildPlayGridData) {
        for c in d.colours { buildColourReg[c.colourID] = c.templateChain ?? []; if c.transpose != 0 { buildColourTranspose[c.colourID] = c.transpose } }
        for (id, hue) in d.hues { colourHueOverride[id] = hue }
        buildIDCounter = max(buildIDCounter, d.idCounter)
        buildSyncColours()
        // Restore the arrays only when the shapes are exactly right (a valid round-trip is 8 columns × ≥8 rungs); a malformed
        // doc keeps the empty defaults rather than risking an out-of-range ferry write later (defensive).
        guard d.cells.count == 8, d.cells.allSatisfy({ $0.count >= 8 }), d.sel.count == 8, d.colOn.count == 8, d.colRecv.count == 8,
              d.colEmit.count == 8, d.colLen.count == 8, d.colSteps.count == 8, d.colRate.count == 8, d.colStepRecv.count == 8, d.colStepEmit.count == 8 else { return }
        buildPlayCells = d.cells; buildPlaySel = d.sel; buildPlayColOn = d.colOn; buildPlayColRecv = d.colRecv; buildPlayColEmit = d.colEmit
        buildPlayColLen = d.colLen; buildPlayColSteps = d.colSteps; buildPlayColRate = d.colRate; buildPlayColStepRecv = d.colStepRecv; buildPlayColStepEmit = d.colStepEmit
        buildPublishScene()   // republish so restored STARTED columns sound at once
    }
    // PART AUTOMATION (Paul 2026-09-02): capture the per-colour AUTO lanes for the save (prune colours with no active
    // lane AND no extents, so the map stays sparse). nil when nothing's armed → byte-identical fullState.
    func buildCaptureAuto() -> [String: PartAutoColour]? {
        let live = buildAutoLanes.filter { $0.value.activeLane >= 0 || $0.value.lanes.contains(where: { !$0.cells.isEmpty }) }
        return live.isEmpty ? nil : live
    }
    func buildRestoreAuto(_ d: [String: PartAutoColour]) { buildAutoLanes = d; buildPublishScene() }
    // The per-poll persistence tick (BUILD active only): restore a just-loaded part ONCE, then keep the save-state current.
    func buildPersistTick() {
        guard activeTab == .build else { return }
        if let u = au?.consumeBuildUnassigned() { buildRestoreUnassigned(u) }   // a host load happened while on BUILD
        if let sc = au?.consumeBuildScenes() { buildRestoreScenes(sc.scenes, active: sc.active) }   // SCENES V2: restore the saved play-grid arrangements
        if let pg = au?.consumeBuildPlayGrid() { buildRestorePlayGrid(pg) }     // ROOMS PLAY GRID: restore the play columns + passes
        if let pa = au?.consumePartAuto() { buildRestoreAuto(pa) }              // PART AUTOMATION: restore the AUTO lanes
        au?.setBuildUnassigned(buildCaptureUnassigned())                         // keep fullState's copy fresh
        au?.setBuildScenes(buildCaptureScenes(), active: buildActiveScene)       // …and the scenes — cheap (COW refcount bumps, not a deep copy), so no dirty-gate needed
        au?.setBuildPlayGrid(buildCapturePlayGrid())                             // …and the play grid
        au?.setPartAuto(buildCaptureAuto())                                      // …and the AUTO lanes
    }
    // THE DEFAULT PALETTE (Paul 2026-08-14): eight starter colours, one per processor type (arp/ratchet/euclid/echo
    // named + strum/chance/harmonize/drone — NEVER passgate). They open the palette as 2 rows of 4 and are present in
    // every part's cast. Each carries a single-processor machine at that type's default settings.
    static let buildDefaultTypes: [ProcessorType] = [.arp, .ratchet, .euclid, .weave, .echo, .strum, .chance, .split, .tutti, .length, .harmonize, .drone]
    // Mint a TAB colour: an ephemeral colour carrying `machine` with tab n's FIXED hue (colourHexes[n]), verbatim
    // (no uniquify — a tab always shows the same colour). (Paul 2026-08-17 — the 8-tab model)
    private func buildNewTabColour(_ n: Int, machine: [ProcessorSlot], transpose: Int = 0, hex hexOverride: UInt32? = nil) -> String {
        let hex = hexOverride ?? (n < colourHexes.count ? colourHexes[n] : 0x808080)   // PLAY columns pass a DUSK hex; PART keeps the vivid colourHexes (Paul 2026-08-30)
        buildIDCounter += 1
        let id = "b\(buildIDCounter)"
        buildColourReg[id] = machine
        if transpose != 0 { buildColourTranspose[id] = transpose } else { buildColourTranspose[id] = nil }   // REGISTER HOME
        colourHueOverride[id] = hex
        buildSyncColours()
        return id
    }
    // A NEW part starts EMPTY — NO default colour/midi chain, no rung selected (Paul 2026-08-19). The user adds a colour
    // (tap a tab / RANDOMIZE) when ready. (Was: TAB 1 seeded with a default passthrough colour.)
    private func buildSeedTab1() {
        buildPartCast = []; buildCastSlots = [:]
        for c in 0..<Snap.maxCols { buildStagingSel[c] = -1 }                 // nothing selected → nothing plays until a colour is added (§E 16-col)
        buildSelID = nil; ddColourSel = -1
    }
    // Seed the workshop ONCE, on first BUILD appear. (Was: 8×4 default cast; now the single TAB 1.) §2.
    func buildSeedCastIfNeeded() {
        guard !buildCastSeeded else { return }
        buildCastSeeded = true
        buildSeedTab1()
        if buildCurrentPart >= 0, buildCurrentPart < buildParts.count { buildParts[buildCurrentPart].cast = buildPartCast }
    }
    // Keep the selection within the PART's cast (its own palette). A fresh, EMPTY cast → NO selection: the footer + the
    // machine audition have nothing until the user adds a colour. Replaces the global ddEnsureSelection on BUILD. §2.
    func buildEnsureCastSelection() {
        if let cid = ddSelectedColourID, buildPartCast.contains(cid) { return }   // already a valid cast member
        if let first = buildPartCast.first { buildSelectID(first) } else { buildSelID = nil; ddColourSel = -1 }
    }

    // A brief centre banner (reuses the HOLD-TO-ALL banner surface), auto-clears. (Paul 2026-08-19)
    private func buildFlashPromote(_ msg: String) {
        withAnimation { buildIOHoldMsg = msg }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.4) { if buildIOHoldMsg == msg { withAnimation { buildIOHoldMsg = nil } } }
    }





    // How many play-grid rows a deployed part occupies (1 = single-rung lane · >1 = multi-rung ladder).
    private func buildPerformPartRows(_ part: Int) -> Int { part < 0 ? 0 : (0..<8).filter { buildPerformPart[$0] == part }.count }
    // A play-grid cell SOUNDS this column when it's the active rung: single-rung parts always; a multi-rung part only
    // when its column's selection points at this rung's source staging row. (Paul 2026-08-15)
    private func buildPerformActiveRung(_ c: Int, _ r: Int) -> Bool {
        let part = buildPerformPart[r]
        guard part >= 0, buildPerformPartRows(part) > 1 else { return true }   // single-rung / empty band → always
        let sr = buildPerformStagingRow[r]
        return sr >= 0 && part < buildParts.count && c < buildParts[part].stagingSel.count && buildParts[part].stagingSel[c] == sr
    }






    // OCT −/+ buttons under the piano (octave shift for the selected PIANO door).
    @ViewBuilder private func buildOctBtn(_ s: String, action: (() -> Void)? = nil) -> some View {
        Text(s).font(.system(size: 9, weight: .heavy, design: .monospaced)).foregroundColor(.white)
            .frame(maxWidth: .infinity).frame(height: 26)
            .background(RoundedRectangle(cornerRadius: 7).fill(buildCell))
            .overlay(RoundedRectangle(cornerRadius: 7).stroke(buildEdge, lineWidth: 1))
            .contentShape(Rectangle())
            .onTapGesture { action?() }
    }





    // THE PALETTE GRID stays 8×4 (32 slots). The 8 DEFAULTS occupy the TOP-LEFT 4×2 block (a proportion of the grid);
    // user-added colours fill from the BOTTOM-RIGHT corner (slot 31 first, then 30, …) so a new colour "starts bottom-right".
    private var buildCastDefaultCount: Int { min(Self.buildDefaultTypes.count, buildPartCast.count) }
    // Is a slot part of the top-left 4×2 DEFAULT block (which is positional), vs the freely-placeable extras region?
    private func buildIsDefaultSlot(_ slot: Int) -> Bool { let row = slot / 8, col = slot % 8; return row < 2 && col < 4 }
    // The bottom-right-most FREE add slot — where the next auto-added colour lands (nil once the palette is full).
    private func buildFirstFreeCastSlot() -> Int? {
        for slot in stride(from: 31, through: 0, by: -1) where !buildIsDefaultSlot(slot) && buildCastSlots[slot] == nil { return slot }
        return nil
    }
    // Reconcile buildCastSlots with membership: drop stale slots, and give every extra member a slot (migrates old
    // parts saved before castSlots existed, and keeps auto-added colours visible).
    private func buildReslotCast() {
        buildCastSlots = buildCastSlots.filter { buildPartCast.contains($0.value) && !buildIsDefaultSlot($0.key) }
        let dc = buildCastDefaultCount
        var slotted = Set(buildCastSlots.values)
        for m in dc..<buildPartCast.count {
            let id = buildPartCast[m]
            if !slotted.contains(id), let s = buildFirstFreeCastSlot() { buildCastSlots[s] = id; slotted.insert(id) }
        }
    }
    // The next UNDEFINED global colour to materialize (nil = all 16 exist).
    private func buildFirstUndefinedGlobal() -> Int? { (0..<colourIDs.count).first { !ddColourShown($0) } }
    // ADD a fresh (passthrough) colour to THIS part's cast: a free DOCUMENT slot if one remains, else an unlimited
    // EPHEMERAL colour with a canonical-ish hue. Then select it. (Paul 2026-08-15 — no 16-colour cap.)
    // Long-pressing an empty cast cell CLONES the last-used colour: a brand-new colour carrying the SAME machine
    // (settings) as the currently-selected colour — the last one placed or whose settings were changed — under a
    // fresh unique hue. Falls back to a blank colour when nothing is selected yet. (Paul 2026-08-17)
    private func buildAddCastColour(atSlot slot: Int? = nil) {
        buildRecordUndo()   // BUILD UNDO: record BEFORE minting so undo reverts the new colour + its placement (U6 fix 2026-08-27)
        let id: String
        if let j = buildFirstUndefinedGlobal() {
            buildCreateColour(j); id = colourIDs[j]
        } else {
            buildIDCounter += 1; id = "b\(buildIDCounter)"
            buildColourReg[id] = []; colourHueOverride[id] = colourHexes[buildIDCounter % colourHexes.count]; buildSyncColours()
        }
        if !buildPartCast.contains(id) { buildPartCast.append(id) }
        buildPlaceCastSlot(id, slot)
        buildEnforceCastHues()                                                                // strong rule: never two alike in the cast
        buildSelectID(id)
    }
    // Assign a NON-default colour its cast slot: the requested one if it's a free extras cell, else the first free.
    // The undo step is recorded by each CALLER (before it mints the colour) so undo reverts the whole action — not
    // just this placement (U6 fix 2026-08-27; the three callers are buildCloneLastColour/buildAddCastColour/buildCommitPulse).
    private func buildPlaceCastSlot(_ id: String, _ requested: Int?) {
        buildCastSlots = buildCastSlots.filter { $0.value != id }                             // this colour claims exactly one slot
        if let s = requested, !buildIsDefaultSlot(s), buildCastSlots[s] == nil { buildCastSlots[s] = id }
        else if let s = buildFirstFreeCastSlot() { buildCastSlots[s] = id }
    }
    // Commit the pulsing candidate: a staged VARIATION becomes a NEW palette colour (carrying its machine); an existing
    // colour is simply selected. Either way the colour is SELECTED (its machine loads into the footer) — and THE TARGET
    // then marks it in the cast + on its selected grid cells, so the user edits the machine knowing what's in focus.
    // Create a colour on BUILD as a PASSTHROUGH machine (empty chain → unprocessed MIDI). A bare `defined` colour
    // has a nil templateChain, which the engine resolves via the LEGACY A-face — and every default colour is type
    // .arp, so it would play an arp the user can't see in the (empty) chain. Store a passthrough placeholder so the
    // audio matches the shown-empty chain. (user 2026-08-12)
    private func buildCreateColour(_ i: Int) {
        guard i < colourIDs.count else { return }
        ddCreateColour(i)
        au?.withChainColour(colourIDs[i]) { $0 = [] }          // [] → a bypassed-passgate passthrough (not the arp A-face)
        refreshFromDocument()
    }





    // A staging cell tap. In PLAY mode the verbs are DISABLED — a tap on a STOCKED cell just makes it the active
    // (playing) cell for its column. In EDIT mode: PLACE stocks the selected colour, DELETE clears, etc.
    private func buildStagingTap(_ c: Int, _ r: Int) {
        if let id = buildStagingCells[c][r] {                     // touching a STOCKED cell offers its colour+settings as a PULSING palette candidate
            buildPulseColourID = id
            buildPulseChain = (r < buildRowChain.count && !buildRowChain[r].isEmpty) ? buildRowChain[r] : []
        }
        // A cell tap always SELECTS / DESELECTS one rung per column (populated or NOT — Paul 2026-08-15). EDIT mode is
        // retired; the row BUTTONS carry the place/mutate actions now (buildRowMode). (Paul 2026-08-16)
        buildStagingSel[c] = (buildStagingSel[c] == r) ? -1 : r   // tap the selected rung → deselect (column silent); else select it
        buildStagingSyncIfPlaying()
    }

    private func buildRowColour(_ r: Int) -> String? { r >= 0 && r < 8 ? (0..<Snap.maxCols).compactMap { $0 < buildStagingCells.count && r < buildStagingCells[$0].count ? buildStagingCells[$0][r] : nil }.first : nil }   // Rooms4: bounds-safe; §E: scan all 16 columns
    private func buildSetRow(_ r: Int, to cid: String?) {         // fill (or clear) a whole row with one colour
        for c in 0..<Snap.maxCols { buildStagingCells[c][r] = cid }   // §E: fill the whole 16-col row (width governs view/play)
        if r < buildRowChain.count { buildRowChain[r] = [] }      // the row carries the colour's OWN machine (no per-row variation override)
        if r < buildRowShade.count { buildRowShade[r] = 0 }
        buildDeletedRows[r] = nil
    }


    // SELECT mode: make this row the selected rung in EVERY column — the whole-row equivalent of tapping a cell.
    private func buildSelectRow(_ row: Int) {
        guard row >= 0, row < 8 else { return }
        for c in 0..<Snap.maxCols { buildStagingSel[c] = row }   // §E 16-col
        buildStagingSyncIfPlaying()
    }

















    // THE PIANO-ROLL FACE on the BUILD grid cells (Paul 2026-08-19): soft note marks enter at the RIGHT as the cell sounds
    // and drift LEFT at REAL pitch lanes (the per-cell note feed), tinted the cell's own bright tone. ONLY on a populated
    // cell of the grid that is the PLAYING voice. Accumulated in the VC poll (buildCellRoll); paused when the cell rests.
    @ViewBuilder private func buildNoteSweep(idx: Int, active: Bool, id: String?, emitter: Set<Bus> = [.a]) -> some View {
        buildNoteSweep(indices: [idx], active: active, id: id, emitter: emitter)
    }
    // MULTI-STEP PASS (Paul 2026-08-30): a play column's pass strikes across several engine cells (col step, row 8+c → index
    // step*Snap.rows + 8+c), so the ferry gathers ALL its steps' feeds → the whole pass's notes drift, not just step 0.
    @ViewBuilder private func buildNoteSweep(indices: [Int], active: Bool, id: String?, emitter: Set<Bus> = [.a]) -> some View {
      if active, id != nil {
        let hue = emitterHue(emitter)   // ROUTING channel (Paul 2026-08-30): the drift is the cell's EMITTER colour, not its machine hue
        let notes = indices.flatMap { $0 >= 0 && $0 < buildCellRoll.count ? buildCellRoll[$0] : [] }
        TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: animationsPaused || notes.isEmpty)) { tl in
            let now = tl.date
            Canvas { ctx, size in
                let barW = size.width * 0.17, barH = max(2.5, size.height * 0.10)
                for n in notes {
                    let age = now.timeIntervalSince(n.born)
                    if age < 0 || age > buildRollLife { continue }
                    let prog = age / buildRollLife                      // 0 (right, just sounded) → 1 (left, gone)
                    let x = CGFloat(1 - prog) * size.width              // notes enter at the RIGHT and drift LEFT (Paul 2026-08-19)
                    let y = CGFloat(1 - n.lane) * size.height           // lane = pitch (high = top)
                    let fade = min(1.0, prog / 0.10) * min(1.0, (1 - prog) / 0.45)
                    let a = max(0.0, min(1.0, fade)) * (0.5 + 0.5 * n.vel)
                    let rect = CGRect(x: x - barW / 2, y: y - barH / 2, width: barW, height: barH)
                    ctx.fill(Path(roundedRect: rect, cornerRadius: barH / 2), with: .color(hue.opacity(a)))
                }
            }
            .padding(2)
        }
        .allowsHitTesting(false)
      }
    }
    // The engine strike-feed indices for play column t: a single-cell column is (col 0, row 8+t); a multi-step pass strikes
    // across (col step, row 8+t) for each step. (Paul 2026-08-30)
    private func buildPlayColSweepIndices(_ t: Int) -> [Int] {
        let base = Snap.playLayerRowBase + t
        let len = BuildSceneLogic.passLen(buildPlayColLen, t)   // shared clamp (refactor 2026-08-30)
        return len <= 1 ? [base] : (0..<len).map { $0 * Snap.rows + base }
    }




    // PLACE is armed by the PLACE button / the verb-box radio; clicking any button that ISN'T a grid row selector
    // turns it back off (→ SELECT). Wired into the control buttons (transports + footer buttons).
    private func buildExitPlaceMode() { if buildPlaceArmed { buildPlaceArmed = false } }


    // Open the library IN BUILD CONTEXT: its Save/Stamp act on the selected colour's chain. Remember the colour's
    // CURRENT chain so a preview can be reverted if the user leaves without APPLY.
    func buildOpenLibrary() {
        cellLibraryFromBuild = true
        buildLibraryOriginalChain = buildSelID.map { buildColourMachine($0) }
        buildLibraryPreviewed = false
        cellLibraryList = au?.libraryCellSummaries() ?? []
        showCellLibrary = true
    }
    // Save the SELECTED colour's chain as a named library cell.
    func buildSaveColourToLibrary(_ name: String) {
        guard let cid = buildSelID else { return }
        au?.saveChainToLibrary(colourID: cid, chain: buildColourMachine(cid), name: name)
        cellLibraryList = au?.libraryCellSummaries() ?? []
    }
    // PREVIEW a library cell: temporarily overwrite the selected colour's chain so it auditions live. Reverted on
    // close unless the user commits with APPLY.
    func buildPreviewLibrary(_ cell: Cell?) {
        guard let cell, let cid = buildSelID else { return }
        buildWriteColourMachine(cid, cell.processors ?? [])
        buildLibraryPreviewed = true
    }
    // APPLY — commit a library cell's chain ONTO the selected colour (keeps the colour + its I/O); no revert.
    func buildStampLibrary(_ cell: Cell?) {
        guard let cell, let cid = buildSelID else { return }
        buildWriteColourMachine(cid, cell.processors ?? [])
        buildLibraryPreviewed = false; buildLibraryOriginalChain = nil
        showCellLibrary = false; cellLibraryFromBuild = false
    }
    // CLOSE without APPLY → restore the colour's original chain if a preview changed it.
    func buildCloseLibrary() {
        if buildLibraryPreviewed, let cid = buildSelID { buildWriteColourMachine(cid, buildLibraryOriginalChain ?? []) }
        buildLibraryPreviewed = false; buildLibraryOriginalChain = nil
        showCellLibrary = false; cellLibraryFromBuild = false
    }



    // A small SPANNER button (Paul 2026-08-30) — sits ABOVE a strip's velocity fader, in the fader's 22-wide column (no wider),
    // replacing the A/B/C/D label. Tap → open the MIDI settings page focused on this receiver/emitter strip.
    // The strip config button — styled like the other strip buttons (buildRecMini), CH-height, fader-width (Paul 2026-08-30).
    @ViewBuilder private func buildStripSpanner(height: CGFloat, _ action: @escaping () -> Void) -> some View {
        Image(systemName: "wrench.fill").font(.system(size: 11, weight: .bold)).foregroundColor(.white.opacity(0.7))
            .frame(maxWidth: .infinity).frame(height: height)
            .background(RoundedRectangle(cornerRadius: 4).fill(buildCell))
            .overlay(RoundedRectangle(cornerRadius: 4).stroke(buildEdge, lineWidth: 1))
            .contentShape(Rectangle()).onTapGesture(perform: action)
    }
    @ViewBuilder private func buildReceiverControl(_ i: Int, height: CGFloat = 148, spanner: (() -> Void)? = nil) -> some View {
        let rec = i < receivers.count ? receivers[i] : Receiver()
        let letter = ["A", "B", "C", "D"][i]
        let soloed = soloReceiverMask & (1 << UInt8(i)) != 0
        let h = height                                                          // total control height (the column strip passes the 2-cell height, Paul 2026-08-30)
        let rowH = (h - 9) / 4                                                   // the CH/ENABLE button's height (right column = 4 equal rows, spacing 3) — the spanner matches it (Paul 2026-08-30)
        HStack(spacing: 6) {
            VStack(spacing: 2) {                                                // the FADER column: a SPANNER above · the velocity fader (label dropped when the spanner is present)
                if let spanner { buildStripSpanner(height: rowH, spanner) }      // CH-height, fader-width, styled like the strip buttons
                buildReceiverFader(i, letter: spanner != nil ? "" : letter)     // velocity INDICATOR — draggable to override input velocity (spring-back on release)
            }.frame(width: 22, height: h)
            VStack(spacing: 3) {                                                // EQUAL rows, top → bottom
                buildRecProminent(recChanLabel(rec), on: rec.inputEnabledResolved, colour: receiverGrey(i)) { toggleReceiverEnabled(i) }   // TOP: OMNI / CH n (ENABLE) — the receiver's SIGNATURE GREY (Paul 2026-08-30)
                buildReceiverLatchButton(i, rec)                                    // LATCH — SET (no mode) / mode label / "LAST N" · pulses when ready · solid when armed
                buildOctRow(oct: i < receiverOctave.count ? receiverOctave[i] : 0, onDown: { nudgeReceiverOctave(i, -1) }, onUp: { nudgeReceiverOctave(i, 1) })   // OCT −/+ (between LATCH and S/M)
                HStack(spacing: 3) {                                            // SOLO (left) · MUTE (right)
                    buildRecMini("S", on: soloed, colour: buildCyan) { toggleReceiverSolo(i) }
                    buildRecMini("M", on: rec.muted, colour: buildPink) { toggleReceiverMute(i) }
                }
            }.frame(height: h)
        }
    }
    // THE MODE-TOGGLE button on a receiver strip (Paul 2026-08-31): "SET" and "THRU" are GONE. The door DEFAULTS to HOLD
    // and the button just ARMS/DISARMS the current mode — tap to arm (solid amber), tap to disarm (the mode label, dim).
    // The mode itself is changed from the config sheet (header MIDI IN / the strip spanner), not this button.
    @ViewBuilder private func buildReceiverLatchButton(_ i: Int, _ rec: Receiver) -> some View {
        let amber = Color(red: 1.0, green: 0.72, blue: 0.2)
        let bit = UInt8(1) << UInt8(i)
        let engaged = ((replayEngagedMask | latchMask) & bit) != 0   // a running loop OR latch — always stoppable
        let label: String = {
            switch rec.doorModeResolved {                            // defaults to HOLD (Paul 2026-08-31)
            case .latch:       return "LATCH"
            case .hold, .thru: return "HOLD"                          // THRU retired → shows/acts as HOLD
            case .keys:        return "KEYS"
            case .replay:      return "LAST \(rec.replayPassesResolved)"
            case .file:        return ".MID"
            case .scale:       return "SCALE"
            }
        }()
        Text(label).font(.system(size: 10, weight: .heavy, design: .monospaced)).tracking(0.5)
            .foregroundColor(engaged ? .black : .white.opacity(0.8))
            .lineLimit(1).minimumScaleFactor(0.55)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(RoundedRectangle(cornerRadius: 5).fill(engaged ? amber : amber.opacity(0.12)))
            .overlay(RoundedRectangle(cornerRadius: 5).stroke(engaged ? Color.clear : amber.opacity(0.4), lineWidth: 1.5))
            .contentShape(Rectangle())
            .onTapGesture { buildEngageDoor(i) }                     // TOGGLE the door's arm (unset until tapped)
    }
    // The door's MODE-ACT — engage/clear per its mode (shared by the strip's LATCH button + ROW 8's INPUT cell, Paul 2026-08-24).
    // Engage/release a REPLAY loop, and while it PLAYS, DISABLE OMNI so live input doesn't bleed alongside the loop (Paul
    // 2026-08-26). Engaging an OMNI input → set its channel filter to NONE; releasing → restore OMNI ONLY if we still hold
    // the NONE we set (a manual channel pick made while looping is left alone). The loop itself always plays (omniRead).
    func buildToggleReplay(_ i: Int) {
        guard i >= 0, i < 4 else { return }
        let bit = UInt8(1 << i)
        let engaging = (replayEngagedMask & bit) == 0
        let cur = i < receivers.count ? receivers[i].channelMaskResolved : 0xFFFF
        if engaging { if cur == 0xFFFF { au?.setReceiverChannelMask(i, 0) } }   // disable OMNI (re-enablable — tap ALL / a channel to play along)
        else { if cur == 0 { au?.setReceiverChannelMask(i, 0xFFFF) } }          // restore OMNI on release if untouched
        au?.toggleReplayCatch(i)
        receivers = au?.uiReceivers() ?? receivers
    }
    // A running arm (REPLAY loop or latch) always stops regardless of the current mode; else arm per the chosen mode.
    func buildEngageDoor(_ i: Int) {
        guard i >= 0, i < 4 else { return }
        let bit = UInt8(1 << i)
        let replayOn = (replayEngagedMask & bit) != 0
        let latchOn  = (latchMask & bit) != 0
        let mode = i < receivers.count ? receivers[i].doorModeResolved : .latch
        if replayOn { buildToggleReplay(i) }
        else if latchOn { toggleReceiverLatch(i) }
        else if mode == .replay { buildToggleReplay(i) } else { toggleReceiverLatch(i) }
        receivers = au?.uiReceivers() ?? receivers; refreshFromDocument()
    }
    // A shared OCTAVE nudge row (Paul 2026-08-30): just two boxes, − and +, NO middle value box. The active box LIGHTS by
    // the current octave amount — ORANGE for ±1, RED for ±2 (and beyond). The colour IS the octave readout. (±3 range.)
    @ViewBuilder private func buildOctRow(oct: Int, onDown: @escaping () -> Void, onUp: @escaping () -> Void) -> some View {
        let orange = Color(hex: 0xFF9F0A), red = Color(hex: 0xFF453A)
        HStack(spacing: 3) {
            buildRecMini("−", on: oct < 0, colour: oct <= -2 ? red : orange, action: onDown)   // lit when octave is DOWN
            buildRecMini("+", on: oct > 0, colour: oct >= 2 ? red : orange, action: onUp)        // lit when octave is UP
        }
    }
    // The INTERACTIVE input-velocity indicator: the incoming-velocity meter (sustained while held, brief attack flash)
    // normally; DRAG to force this door's input velocity (top = 127 · bottom = 0) via setReceiverVel; release springs
    // back to the natural velocity — the receiver mirror of buildEmitterFader. (Paul 2026-08-18)
    // One velocity-meter colour band + whether it wears the ENERGY effect (only the SELECTED colour's band — Paul 2026-08-31).
    private struct MeterBand { let color: Color; let energy: Bool }
    // The velocity-meter FILL as vertical colour bands (one per feeding/playing cell) rising to `level`. (Paul 2026-08-31)
    // `faded` (the receiver strips): EVERY band fades to alpha 0 at the bottom; the SELECTED colour's band ALSO gets the
    // INVERTED overlay (screen-blended) so it reads as energy — the pinched waist. No feed at all → a light-grey band with a
    // downward-moving shimmer ("notes that aren't on a cell", e.g. a scale-door audition), NOT cyan. Emitters (faded=false)
    // stay flat.
    @ViewBuilder private func buildMeterBands(_ bands: [MeterBand], level: Double, height: CGFloat, override: Color?, faded: Bool = false) -> some View {
        HStack(spacing: bands.count > 1 ? 0.7 : 0) {
            if let ov = override {
                Rectangle().fill(ov.opacity(0.9))
            } else if bands.isEmpty {
                if faded { buildMeterNoFeedBand() } else { Rectangle().fill(buildCyan.opacity(0.9)) }   // no cell feeds this door → light grey downward (receivers), else the cyan default
            } else {
                ForEach(bands.indices, id: \.self) { k in
                    let c = bands[k].color
                    if faded {
                        ZStack {
                            Rectangle().fill(LinearGradient(colors: [c.opacity(0.92), c.opacity(0)], startPoint: .top, endPoint: .bottom))   // ALL bands: fade to 0 at the bottom
                            if bands[k].energy {   // the SELECTED colour only: the inverted overlay → the energy waist + glow
                                Rectangle().fill(LinearGradient(colors: [c.opacity(0), c.opacity(0.92)], startPoint: .top, endPoint: .bottom)).blendMode(.screen)
                            }
                        }.compositingGroup()
                    } else {
                        Rectangle().fill(c.opacity(0.9))
                    }
                }
            }
        }
        .frame(height: height * CGFloat(min(1, max(0, level))))
        .clipShape(RoundedRectangle(cornerRadius: 3))
    }
    // The velocity-meter fill when NO cell feeds this door but it IS receiving (a scale-door audition, or any input not on a
    // placed cell): light grey + transparency + a soft band drifting DOWNWARD. (Paul 2026-08-31, replaces the cyan fallback.)
    @ViewBuilder private func buildMeterNoFeedBand() -> some View {
        // STATIC light grey (Paul 2026-08-31: no animation for input not assigned to a colour) — a calm translucent fill.
        Rectangle().fill(Color(white: 0.82).opacity(0.34))
    }
    @ViewBuilder private func buildReceiverFader(_ i: Int, letter: String) -> some View {
        let override = i < recvDragVel.count ? recvDragVel[i] : nil
        let feed = buildReceiverFeedColours(i)   // the colour(s) of the cell(s) this door feeds (vertical bands if >1)
        VStack(spacing: 2) {
            Text(letter).font(.system(size: 10, weight: .black, design: .monospaced)).foregroundColor(buildDim)   // NO drag-velocity number over the slider (Paul 2026-08-30)
            GeometryReader { g in
                TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: animationsPaused)) { tl in
                    let held = i < recvHeld.count ? (recvHeld[i].max() ?? 0) : 0   // SUSTAINED while notes are held (no decay/drop animation, Paul 2026-08-18)
                    // ATTACK FLASH (Paul 2026-08-23): an event-driven, decaying flash on every note-on (30 Hz peak feed),
                    // so QUICK TAPS register even though the ~4 Hz held-velocity poll misses a note pressed+released
                    // between two polls. Mirrors buildReceiverMeter. max(held, flash) → sustained holds still show full.
                    let age = tl.date.timeIntervalSince(i < meters.receiverPeakAt.count ? meters.receiverPeakAt[i] : .distantPast)
                    let flash = (i < meters.receiverPeak.count ? meters.receiverPeak[i] : 0) * max(0, 1 - age / 0.3)
                    let level = override != nil ? Double(override!) / 127.0 : max(0, min(1, max(held, flash)))
                    ZStack(alignment: .bottom) {
                        RoundedRectangle(cornerRadius: 3).fill(Color.black.opacity(0.5))
                        buildMeterBands(feed, level: level, height: g.size.height, override: override != nil ? buildPink : nil, faded: true)   // ALL bands fade; inverse only on the SELECTED colour; light-grey downward when no cell feeds it (Paul 2026-08-31)
                    }
                }
                .contentShape(Rectangle())
                .gesture(DragGesture(minimumDistance: 0)
                    .onChanged { v in
                        let frac = 1 - min(1, max(0, v.location.y / g.size.height))
                        let vel = Int((frac * 127).rounded())
                        if i < recvDragVel.count { recvDragVel[i] = vel }
                        setReceiverVel(i, vel)                          // 0 = the input is silenced while held down
                    }
                    .onEnded { _ in
                        if i < recvDragVel.count { recvDragVel[i] = nil }
                        setReceiverVel(i, nil)                          // release → natural velocity
                    })
            }
        }
    }
    // The channel-button caption ALWAYS reflects the chosen channel(s) (Paul 2026-08-23): reads the multi-channel MASK
    // (the source of truth since 2026-08-21), not the legacy single `channel` field. OMNI = all · CH n = one · CH ×k =
    // a subset · OFF = none.
    private func recChanLabel(_ rec: Receiver) -> String {
        let mask = rec.channelMaskResolved
        if mask == 0xFFFF { return "OMNI" }
        if mask == 0 { return "OFF" }
        let chans = (0..<16).filter { mask & (UInt16(1) << UInt16($0)) != 0 }
        return chans.count == 1 ? "CH \(chans[0] + 1)" : "CH ×\(chans.count)"
    }
    // A small square-ish Mute/Solo toggle.
    @ViewBuilder private func buildRecMini(_ label: String, on: Bool, colour: Color, action: @escaping () -> Void) -> some View {
        Text(label).font(.system(size: 9, weight: .heavy, design: .monospaced))
            .foregroundColor(on ? .black : .white.opacity(0.7))
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(RoundedRectangle(cornerRadius: 4).fill(on ? colour : buildCell))
            .overlay(RoundedRectangle(cornerRadius: 4).stroke(on ? Color.clear : buildEdge, lineWidth: 1))
            .contentShape(Rectangle()).onTapGesture(perform: action)
    }
    // A PROMINENT toggle (thicker edge, bold, strong lit colour) — used for LATCH and ENABLE.
    @ViewBuilder private func buildRecProminent(_ label: String, on: Bool, colour: Color, action: @escaping () -> Void) -> some View {
        Text(label).font(.system(size: 10, weight: .heavy, design: .monospaced)).tracking(0.5)
            .foregroundColor(on ? .black : .white.opacity(0.85)).lineLimit(1).minimumScaleFactor(0.6)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(RoundedRectangle(cornerRadius: 5).fill(on ? colour : buildCell))
            .overlay(RoundedRectangle(cornerRadius: 5).stroke(on ? Color.clear : buildEdge, lineWidth: 1.5))
            .contentShape(Rectangle()).onTapGesture(perform: action)
    }


    @ViewBuilder private func buildEmitterControl(_ i: Int, showRack: Bool = true, height: CGFloat = 148, spanner: (() -> Void)? = nil) -> some View {
        let letter = ["A", "B", "C", "D"][i]
        let muted = !(i < busEnabled.count ? busEnabled[i] : true)
        let soloed = emitterFootSolo & (1 << UInt8(i)) != 0
        let racked = rackMask & (1 << UInt8(i)) != 0
        let ch = i < busChannels.count ? busChannels[i] : i + 1
        let h = height                                                        // match the receiver control (the column strip passes the 2-cell height, Paul 2026-08-30)
        let rowH = (h - 9) / 4                                                // CH-button height (right column = 4 equal rows, spacing 3, RACK hidden on the column strip) — the spanner matches it (Paul 2026-08-30)
        HStack(spacing: 6) {
            VStack(spacing: 2) {                                              // the FADER column: a SPANNER above · the velocity fader (label dropped when the spanner is present)
                if let spanner { buildStripSpanner(height: rowH, spanner) }   // CH-height, fader-width, styled like the strip buttons
                buildEmitterFader(i, letter: spanner != nil ? "" : letter)    // interactive velocity fader — drag to override output velocity
            }.frame(width: 22, height: h)
            VStack(spacing: 3) {                                               // EQUAL rows, top → bottom (mirrors the receiver control)
                buildRecProminent("CH \(ch)", on: !muted, colour: emitterColour(Bus.allCases[i])) { toggleEmitter(i) }   // TOP: CH n — lit in the emitter's SIGNATURE colour (consistent with the MIDI-OUT toggles, Paul 2026-08-30); acts as the MUTE
                if showRack { buildRecProminent("RACK", on: racked, colour: Color(red: 1.0, green: 0.72, blue: 0.2)) { toggleRack(i) } }   // RACK (hidden on the column strip, Paul 2026-08-30)
                buildRecProminent("···", on: false, colour: buildDim) { }      // PLACEHOLDER (Paul 2026-08-30) — a future emitter control, between CH and OCT
                buildOctRow(oct: i < emitterOctave.count ? emitterOctave[i] : 0, onDown: { nudgeEmitterOctave(i, -1) }, onUp: { nudgeEmitterOctave(i, 1) })   // OCT −/+
                buildRecMini("SOLO", on: soloed, colour: buildCyan) { toggleEmitterSolo(i) }   // SOLO only (CH is the mute)
            }.frame(height: h)
        }
    }
    // NEW INTERFACE (Paul 2026-08-28): the real MIXER strips reused verbatim in the slideover mixer overlay — the full
    // MIDI-IN receiver console (fader · ENABLE/CH · LATCH · OCT · S/M) and MIDI-OUT emitter console (fader · CH · RACK ·
    // OCT · SOLO). Internal wrappers so RoomsPage can call the private controls.
    @ViewBuilder func roomsMixerReceiver(_ i: Int) -> some View { buildReceiverControl(i) }
    @ViewBuilder func roomsMixerEmitter(_ i: Int) -> some View { buildEmitterControl(i) }

    // THE MACHINE-COLUMN I/O STRIPS (Paul 2026-08-30, footer-retirement stage 1): the 4 full receiver / emitter controls
    // COPIED into the machine column — receiver strip on TOP, emitter strip at the BOTTOM. NO RACK (emitter). The receiver
    // has no separate SCALE button — its LATCH row shows the mode (SCALE included), kept as the arm control. The SPANNER now
    // opens the MIXER expanded on this door (all 8 strips visible, this one highlighted), the salvaged footer console — the
    // footer itself is retired (Paul 2026-08-31).
    @ViewBuilder func roomsColumnReceivers(height: CGFloat) -> some View {
        HStack(spacing: 4) {
            ForEach(0..<4, id: \.self) { i in
                buildReceiverControl(i, height: height, spanner: { roomsMixerSel = i; roomsMixerOpen = true }).frame(maxWidth: .infinity)   // spanner → the MIXER, this door (IN) selected
            }
        }
    }
    @ViewBuilder func roomsColumnEmitters(height: CGFloat) -> some View {
        HStack(spacing: 4) {
            ForEach(0..<4, id: \.self) { i in
                buildEmitterControl(i, showRack: false, height: height, spanner: { roomsMixerSel = 4 + i; roomsMixerOpen = true }).frame(maxWidth: .infinity)   // spanner → the MIXER, this emitter (OUT) selected
            }
        }
    }

    // The colours of every CELL FEEDING receiver `door` (its velocity-strip tint) — the part rows whose input is this door
    // + any live play column reading it. Multiple → a vertical strip of all of them. (Paul 2026-08-31)
    private func buildReceiverFeedColours(_ door: Int) -> [MeterBand] {
        var bands: [MeterBand] = []
        var seen = Set<String>()
        func add(_ cid: String?, color: Color? = nil) {
            guard let cid, !seen.contains(cid) else { return }
            seen.insert(cid)
            bands.append(MeterBand(color: color ?? colourColor(cid) ?? buildCyan, energy: cid == ddSelectedColourID))   // ENERGY (inverted overlay) only on the SELECTED colour
        }
        for r in 0..<8 where buildRowColour(r) != nil && buildRowReceiverResolved(r) == door { add(buildRowColour(r)) }   // part rows on this door
        for c in 0..<8 where c < buildPlayColRecv.count && buildPlayColRecv[c] == door {                                   // play columns on this door
            let r = c < buildPlaySel.count ? buildPlaySel[c] : -1
            if r >= 0, c < buildPlayCells.count, r < buildPlayCells[c].count { add(buildPlayCells[c][r]) }
        }
        // A CHAIN AUDITION (the SELECT-grid cell playing) on this door → the STANDARDIZED machine hue (LIGHT GREY on SELECT),
        // not its palette colour, and not empty — so the select-grid audition IS reflected in the input strip. (Paul 2026-08-31)
        if buildDisplayVoice == .chain {
            let aDoor = buildSelectedRow.map { buildRowReceiverResolved($0) } ?? buildSelReceiver
            if aDoor == door { add(ddSelectedColourID, color: buildMachineHue(roomsRoom)) }
        }
        // A door with NO feeding cell (a scale-door audition, input not on a placed cell) returns EMPTY → the strip shows the
        // light-grey downward shimmer. (Paul 2026-08-31)
        return bands
    }
    // The colours of every CELL currently PLAYING through emitter `e` (its velocity-strip tint) — the sounding part rungs +
    // the chain audition + the live play columns that emit on `e`. Multiple → a vertical strip of all of them. (Paul 2026-08-31)
    private func buildEmitterPlayingColours(_ e: Bus) -> [MeterBand] {
        var bands: [MeterBand] = []
        var seen = Set<String>()
        func add(_ cid: String?, color: Color? = nil) {
            guard let cid, !seen.contains(cid) else { return }
            seen.insert(cid)
            bands.append(MeterBand(color: color ?? colourColor(cid) ?? buildCyan, energy: false))    // emitters keep the flat fill (energy is receivers-only)
        }
        if buildStagingPlaying {                                                                     // PART: the selected rungs that emit on e
            for c in 0..<Snap.maxCols { let r = c < buildStagingSel.count ? buildStagingSel[c] : -1
                if r >= 0, buildRowColour(r) != nil, buildRowEmittersResolved(r).contains(e) { add(buildRowColour(r)) } }
        }
        // CHAIN audition → the STANDARDIZED machine hue (LIGHT GREY on SELECT), not the old palette colour. (Paul 2026-08-31)
        if ddSolo, buildDefaultEmitters.contains(e) { add(ddSelectedColourID, color: buildMachineHue(roomsRoom)) }
        for c in 0..<8 where c < buildPlayColOn.count && buildPlayColOn[c] {                          // PLAY columns emitting on e
            let emit = c < buildPlayColEmit.count ? buildPlayColEmit[c] : []
            if emit.contains(e) { let r = c < buildPlaySel.count ? buildPlaySel[c] : -1
                if r >= 0, c < buildPlayCells.count, r < buildPlayCells[c].count { add(buildPlayCells[c][r]) } }
        }
        return bands
    }
    // The interactive velocity fader: the meter (emitPeak, decayed) normally; while DRAGGED it forces the emitter's
    // output velocity (top = 127 · bottom = 0/KILL) via setVelOverride, and releases (springs back) on lift.
    @ViewBuilder private func buildEmitterFader(_ i: Int, letter: String) -> some View {
        let override = i < emitDragVel.count ? emitDragVel[i] : nil
        let playing = buildEmitterPlayingColours(Bus.allCases[i])   // the colour(s) of every cell playing through this emitter (vertical bands if >1)
        VStack(spacing: 2) {
            Text(letter).font(.system(size: 10, weight: .black, design: .monospaced)).foregroundColor(buildDim)   // NO drag-velocity number over the slider (Paul 2026-08-30)
            GeometryReader { g in
                TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: animationsPaused)) { tl in
                    // DECAY + note-priority (Paul 2026-08-19): the bar FALLS from the last peak; a new note resets
                    // emitPeakAt → the bar jumps back up, so new notes take priority over the fall reaching the bottom.
                    let level: Double = {
                        if let o = override { return Double(o) / 127.0 }
                        let age = tl.date.timeIntervalSince(i < meters.emitPeakAt.count ? meters.emitPeakAt[i] : .distantPast)
                        return max(0, min(1, (i < meters.emitPeak.count ? meters.emitPeak[i] : 0) * (1 - age / 0.9)))
                    }()
                    ZStack(alignment: .bottom) {
                        RoundedRectangle(cornerRadius: 3).fill(Color.black.opacity(0.5))
                        buildMeterBands(playing, level: level, height: g.size.height, override: override != nil ? buildPink : nil)   // tinted by the playing cell(s)
                    }
                }
                .contentShape(Rectangle())
                .gesture(DragGesture(minimumDistance: 0)
                    .onChanged { v in
                        let frac = 1 - min(1, max(0, v.location.y / g.size.height))
                        let vel = Int((frac * 127).rounded())
                        if i < emitDragVel.count { emitDragVel[i] = vel }
                        setVelOverride(i, vel)                          // 0 = kill
                    }
                    .onEnded { _ in
                        if i < emitDragVel.count { emitDragVel[i] = nil }
                        setVelOverride(i, nil)                          // release → natural velocity
                    })
            }
        }
    }



    // ── small shared placeholder widgets ─────────────────────────────────────────────────────────────────────────
    // The identical audition button at the top of each column (transport glyph + label, cyan-bordered). `active` marks
    // it the playing voice; when active AND the transport plays, it becomes a PLAYHEAD — filling cyan L→R over `fill`'s
    // period (.cell = one step · .grid = the whole 8-column loop), looping. Inactive buttons never animate. (user 2026-08-13)
    @ViewBuilder private func buildColumnButton(_ label: String, active: Bool = false, fill: BuildFill = .none, enabled: Bool = true, fillHeight: Bool = false, action: (() -> Void)? = nil) -> some View {
        HStack(spacing: 8) {
            HStack(spacing: 5) {                                    // BOTH transport signs, the CURRENT state boldly lit (Paul 2026-08-15)
                Image(systemName: "play.fill").font(.system(size: 15, weight: .black))
                    .foregroundColor(active ? Color(red: 0.36, green: 0.92, blue: 0.52) : .white.opacity(0.22))   // PLAYING → GREEN play
                Image(systemName: "stop.fill").font(.system(size: 15, weight: .black))
                    .foregroundColor(active ? .white.opacity(0.22) : Color(red: 0.98, green: 0.5, blue: 0.5))     // STOPPED → RED stop
            }
            Text(label).font(.system(size: 10, weight: .heavy, design: .monospaced)).foregroundColor(active ? .white : buildCyan).tracking(1)
                .lineLimit(1).minimumScaleFactor(0.6)
        }
        .frame(maxWidth: .infinity, minHeight: fillHeight ? 0 : 38, maxHeight: fillHeight ? .infinity : 38)   // fillHeight ⇒ fill the caller's band (exact grid alignment); else the intrinsic 38
        .background(
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 10).fill(active ? buildCyan.opacity(0.28) : buildCell)   // active = dim cyan base (empty)
                if active && d.playing && fill != .none {
                    GeometryReader { g in
                        TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: animationsPaused)) { tl in
                            RoundedRectangle(cornerRadius: 10).fill(buildCyan.opacity(0.3))              // dim fill = the playhead sweeping L→R
                                .frame(width: g.size.width * buildHeaderFill(fill, tl.date))
                        }
                    }
                }
            }
        )
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(active ? buildCyan : buildEdge, lineWidth: 1))   // §0: the voice keeps the accent; idle mutes
        // DISABLED (empty grid) looks IDENTICAL to the stopped state — full opacity — but stays inert (Paul 2026-08-18)
        .contentShape(Rectangle())
        .onTapGesture { if enabled { buildExitPlaceMode(); action?() } }   // a transport button is not a row selector → leaves PLACE mode
        .allowsHitTesting(enabled)
    }

    // The header playhead's fill fraction (0…1) — phase-locked to the transport, warped by SWING (as the grid playhead).
    // .cell fills over ONE step; .grid fills over the whole 8-column loop.
    private func buildHeaderFill(_ fill: BuildFill, _ now: Date) -> CGFloat {
        let live = meters.beatAnchor + now.timeIntervalSince(meters.beatAnchorAt) * meters.tempo / 60.0
        let musical = musicalOf(live, stepBeats: stepBeats, a: max(1.0, Double(swing) / 50.0))
        let period = fill == .cell ? stepBeats : stepBeats * Double(Snap.cols)
        let raw = period > 0 ? (musical / period).truncatingRemainder(dividingBy: 1) : 0
        return CGFloat(max(0, min(1, raw < 0 ? raw + 1 : raw)))
    }
    // CANCEL: revert the CURRENT target colour to the snapshot taken when the editor opened, then close. (Exit any other
    // way = SAVE the live edits.) After an overwrite-and-follow the snapshot is the target's committed chain (a no-op).
    private func buildEditorCancel() {
        if let cid = buildEditorSnapCid { buildWriteColourMachine(cid, buildEditorSnapshot) }
        buildEditSlot = nil; buildStageEye = false
    }

    @ViewBuilder private func buildProcessorPanel(slot: Int, proc: ProcessorSlot, cid: String, contentW: CGFloat) -> some View {
        let hue = buildCardHue   // the ONE machine/card hue (grey on the SELECT audition) — never the raw gsAud palette throwback
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 10) {                               // HEADER: colour + name · BYPASS · CANCEL · DELETE
                RoundedRectangle(cornerRadius: 8).fill(hue).frame(width: 34, height: 34)
                Image(systemName: emblemSymbol(proc.type)).font(.system(size: 20, weight: .black)).foregroundColor(.white)
                Text(buildProcLabel(proc)).font(.system(size: 22, weight: .heavy, design: .monospaced)).foregroundColor(.white)   // type + its fixed mode (the radio moved to the card)
                Spacer()
                // HOLD-BYPASS A/B (idea 23): TAP = toggle (persistent); HOLD = momentary flip (hear it in/out, restore on
                // release). The momentary uses the same undoable bypass edit (v1: may add an undo step for a placed colour).
                Text(proc.bypassed ? "BYPASSED" : "BYPASS").font(.system(size: 12, weight: .heavy, design: .monospaced))
                    .foregroundColor(.white)
                    .padding(.horizontal, 14).frame(height: 34)
                    .background(RoundedRectangle(cornerRadius: 8).fill(Color.black))
                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.white.opacity(proc.bypassed ? 0.9 : 0.3), lineWidth: buildBypassHeld == slot ? 2 : 1))
                    .contentShape(Rectangle())
                    .onTapGesture { buildChainToggleBypass(slot) }
                    .onLongPressGesture(minimumDuration: 0.22, pressing: { pressing in
                        if !pressing, buildBypassHeld == slot { buildChainToggleBypass(slot); buildBypassHeld = nil }   // release → restore
                    }, perform: { buildChainToggleBypass(slot); buildBypassHeld = slot })                              // held → momentary flip
                Button { buildChainRemoveSlot(slot); buildEditSlot = nil; buildStageEye = false } label: {
                    Text("DELETE").font(.system(size: 12, weight: .heavy, design: .monospaced))
                        .foregroundColor(.red)
                        .padding(.horizontal, 14).frame(height: 34)
                        .background(RoundedRectangle(cornerRadius: 8).fill(Color.black))
                        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.red.opacity(0.7), lineWidth: 1))
                }.buttonStyle(.plain)
                Button { buildEditorCancel() } label: {          // CANCEL — revert to the open-snapshot (Paul 2026-08-19)
                    Text("CANCEL").font(.system(size: 12, weight: .heavy, design: .monospaced))
                        .foregroundColor(buildDim)
                        .padding(.horizontal, 14).frame(height: 34)
                        .background(RoundedRectangle(cornerRadius: 8).fill(Color.black))
                        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.white.opacity(0.3), lineWidth: 1))
                }.buttonStyle(.plain)
                Button { buildEditSlot = nil; buildStageEye = false } label: {          // DONE — keep the edits + close (Paul 2026-08-19)
                    Text("DONE").font(.system(size: 12, weight: .heavy, design: .monospaced))
                        .foregroundColor(.black)
                        .padding(.horizontal, 16).frame(height: 34)
                        .background(RoundedRectangle(cornerRadius: 8).fill(buildCyan))
                }.buttonStyle(.plain)
            }
            .padding(.horizontal, 16).padding(.vertical, 12)
            .background(hue.opacity(0.22))
            // FIXED HEADER above · SCROLLABLE BODY below (Paul 2026-08-30) — the title + DONE/CANCEL/DELETE/BYPASS stay
            // pinned while SOURCE/OCT, the truth strips, and the controls scroll under them.
            ScrollView(.vertical, showsIndicators: true) {
              VStack(alignment: .leading, spacing: 0) {
            // §1 STANDARD PANEL ANATOMY (Paul 2026-08-27) — the per-STAGE header standard: OCT ◀n▶ (this stage's own
            // voice, ±3 octaves, dimmed at 0). Distinct from the OCTAVE utility card (a positional stream transform).
            HStack(spacing: 10) {
                // SOURCE: CHAIN | MIDI IN | BOTH — this stage reads the upstream chain, the row's own door, or both.
                Text("SOURCE").font(.system(size: 11, weight: .heavy, design: .monospaced)).foregroundColor(buildDim).tracking(1)
                let ssrc = proc.params.stageSource ?? .chain
                ForEach([StageSource.chain, .midiIn, .both], id: \.self) { s in
                    let on = ssrc == s
                    Text(s == .chain ? "CHAIN" : (s == .midiIn ? "MIDI IN" : "BOTH")).font(.system(size: 11, weight: .heavy, design: .monospaced))
                        .foregroundColor(on ? .black : .white.opacity(0.6)).padding(.horizontal, 10).frame(height: 28)
                        .background(RoundedRectangle(cornerRadius: 6).fill(on ? buildCyan : Color.white.opacity(0.08)))
                        .contentShape(Rectangle()).onTapGesture { buildChainEditSlot(slot) { $0.params.stageSource = s } }
                }
                Rectangle().fill(Color.white.opacity(0.15)).frame(width: 1, height: 22)
                Text("OCT").font(.system(size: 11, weight: .heavy, design: .monospaced)).foregroundColor(buildDim).tracking(1)
                let oct = proc.params.stageOct ?? 0
                Button { buildChainEditSlot(slot) { $0.params.stageOct = max(-3, ($0.params.stageOct ?? 0) - 1) } } label: {
                    Image(systemName: "chevron.left").font(.system(size: 12, weight: .bold)).foregroundColor(.white).frame(width: 30, height: 28)
                        .background(RoundedRectangle(cornerRadius: 6).fill(Color.white.opacity(0.08)))
                }.buttonStyle(.plain)
                Text(oct == 0 ? "0" : (oct > 0 ? "+\(oct)" : "\(oct)")).font(.system(size: 14, weight: .heavy, design: .monospaced))
                    .foregroundColor(oct == 0 ? buildDim : .white).frame(minWidth: 28)
                Button { buildChainEditSlot(slot) { $0.params.stageOct = min(3, ($0.params.stageOct ?? 0) + 1) } } label: {
                    Image(systemName: "chevron.right").font(.system(size: 12, weight: .bold)).foregroundColor(.white).frame(width: 30, height: 28)
                        .background(RoundedRectangle(cornerRadius: 6).fill(Color.white.opacity(0.08)))
                }.buttonStyle(.plain)
                Text("this stage's own voice").font(.system(size: 10, design: .monospaced)).foregroundColor(buildDim.opacity(0.7))
                Spacer()
            }
            .padding(.horizontal, 16).padding(.vertical, 8)
            .background(hue.opacity(0.10))
            Rectangle().fill(hue.opacity(0.5)).frame(height: 1)
            // (ROW SELECTOR — the "Long press to copy" 1–8 tabs — removed, no longer required. Paul 2026-08-30)
            buildTruthStrips().padding(.horizontal, 16).padding(.vertical, 8)   // §1 IN | OUT truths — silence explains itself
            Rectangle().fill(hue.opacity(0.25)).frame(height: 1)
            buildSlotBox(slot, proc, cid: cid).padding(16)   // CONTROLS — reuse ProcessorBox (our chrome hidden)
              }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(RoundedRectangle(cornerRadius: 8).fill(buildPanel))
        .clipShape(RoundedRectangle(cornerRadius: 8))                           // clip the header's top corners + the scroll body to the panel box
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(hue, lineWidth: 4))   // THICKER + LESS ROUNDED (Paul 2026-08-28)
        .shadow(color: .black.opacity(0.5), radius: 20, y: 8)
        .contentShape(Rectangle()).onTapGesture { }            // swallow taps inside the panel so they don't reach the backdrop (close)
    }

    // §1 TRUTH STRIPS (Paul 2026-08-22, the TUTTI-confusion cure): a slim IN | OUT band above the controls. IN = the
    // held-note silhouette at the colour's INPUT door — and when NOTHING is held it TEACHES ("nothing held — LATCH or
    // play at INPUT A"), so silence explains itself instead of reading as breakage (the spec's §7 teach-in-place law).
    // OUT = a live mini-roll of what the plugin emits (the processor's effect made visible). v1: OUT aggregates the whole
    // board — during a chain audition (part stopped) that IS the chain's output. Tap-to-expand (the §4 STAGE EYE) is later.
    // Is the EDITED cell the one actually sounding right now? In "PLAY THIS MIDI CHAIN" the OUT IS this chain (true). In
    // "PLAY THIS PART" it's only this cell when the edited colour's rung is the active one under the playhead — otherwise
    // the OUT strip is showing OTHER cells of the part, so we say so + dim it (idea 24 follow-up, Paul 2026-08-25).
    private var buildTruthOutContext: (label: String, live: Bool) {
        switch buildDisplayVoice {
        case .chain: return ("this chain", true)
        case .part:
            let r = buildSelectedRow
            let sounding = d.playing && r != nil && d.effColumn >= 0 && d.effColumn < buildStagingSel.count && buildStagingSel[d.effColumn] == r
            return (sounding ? "this cell — live" : "part — not this cell", sounding)
        case .none: return ("press ▶ to hear it", false)
        }
    }
    @ViewBuilder private func buildTruthStrips() -> some View {
        let door = buildSelectedRow.map { buildRowReceiverResolved($0) } ?? buildSelReceiver
        let held = (door >= 0 && door < recvHeldNotes.count) ? recvHeldNotes[door].map { Int($0) } : []
        let inGrace = door >= 0 && door < buildInGrace.count && buildInGrace[door]
        let sticky = (door >= 0 && door < buildInSticky.count) ? buildInSticky[door] : []
        let letter = (door >= 0 && door < 4) ? ["A", "B", "C", "D"][door] : "A"
        let hue = buildCardHue   // the ONE machine/card hue (grey on the SELECT audition) — never the raw gsAud palette throwback
        let out = buildTruthOutContext
        HStack(alignment: .top, spacing: 14) {
            VStack(alignment: .leading, spacing: 4) {
                buildStripLabel("IN")
                if !held.isEmpty {
                    buildInKeyboard(held, hue: hue)                         // live input → lit
                } else if inGrace {
                    buildInKeyboard(sticky, hue: hue).opacity(0.4)          // §1: recent input (within a pass) → sticky, dimmed; NO flashing text
                } else {
                    Text("nothing held — LATCH or play at INPUT \(letter)")  // truly empty for a whole pass
                        .font(.system(size: 11, weight: .heavy, design: .monospaced)).foregroundColor(buildCyan.opacity(0.85))
                        .lineLimit(2).minimumScaleFactor(0.8).frame(height: 30, alignment: .leading)
                }
            }.frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle()).onTapGesture { buildOpenStageEye() }   // tap → the STAGE EYE (§4)
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    buildStripLabel("OUT")
                    Text(out.label).font(.system(size: 9, weight: .heavy, design: .monospaced))   // §2: what's driving OUT right now
                        .foregroundColor(out.live ? hue.opacity(0.9) : buildDim).lineLimit(1)
                }
                buildOutStrip(hue: hue).opacity(out.live ? 1 : 0.4)        // §2: dim when the OUT isn't this cell
            }.frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle()).onTapGesture { buildOpenStageEye() }
        }
    }
    private func buildStripLabel(_ t: String) -> some View {
        HStack(spacing: 4) {
            Text(t).font(.system(size: 10, weight: .heavy, design: .monospaced)).foregroundColor(buildDim).tracking(1)
            Image(systemName: "arrow.up.left.and.arrow.down.right").font(.system(size: 8, weight: .heavy)).foregroundColor(buildDim.opacity(0.7))
        }
    }
    private func buildOpenStageEye() {
        buildStageEyeDoor = buildSelectedRow.map { buildRowReceiverResolved($0) } ?? buildSelReceiver
        buildEyeInRoll = []; buildEyeInPrev = []
        buildStageEye = true
    }
    // §4 THE STAGE EYE (Paul 2026-08-22, "captured with enthusiasm"): tap a truth strip → the spacious three-strata page.
    // TOP = the INPUT roll (what arrives) · MIDDLE = the MECHANISM (the stage working, a position light on the step) ·
    // BOTTOM = the OUTPUT roll (what leaves) — cause → machine → effect, on one shared pitch axis. v1 = the DRIFT model
    // (rolls scroll, "now" = the right edge; the mechanism is the live machine with a lit current column). The fully
    // column-aligned sweep (output tagged by its emitting step) is v2. EUCLID draws its pulse pattern; others a step lane.
    @ViewBuilder func buildStageEyeView(slot: Int, size: CGSize) -> some View {
        let chain = selectedColourChain()
        if slot < chain.count {
            let proc = chain[slot]
            let hue = buildCardHue   // the ONE machine/card hue (grey on the SELECT audition) — never the raw gsAud palette throwback
            let door = buildStageEyeDoor
            let letter = (door >= 0 && door < 4) ? ["A", "B", "C", "D"][door] : "A"
            let held = (door >= 0 && door < recvHeldNotes.count) ? recvHeldNotes[door].map { Int($0) } : []
            ZStack {
                Color.black.opacity(0.94).ignoresSafeArea()
                    .contentShape(Rectangle()).onTapGesture { buildStageEye = false }   // tap the backdrop → close
                VStack(spacing: 10) {
                    HStack(spacing: 10) {                                                // HEADER
                        RoundedRectangle(cornerRadius: 7).fill(hue).frame(width: 28, height: 28)
                        Image(systemName: emblemSymbol(proc.type)).font(.system(size: 17, weight: .black)).foregroundColor(.white)
                        Text(buildProcLabel(proc)).font(.system(size: 20, weight: .heavy, design: .monospaced)).foregroundColor(.white)
                        Text("· THE EYE").font(.system(size: 12, weight: .heavy, design: .monospaced)).foregroundColor(buildDim)
                        Spacer()
                        Text("IN: \(letter)").font(.system(size: 12, weight: .heavy, design: .monospaced)).foregroundColor(hue)
                        Button { buildStageEye = false } label: {
                            Text("CLOSE").font(.system(size: 12, weight: .heavy, design: .monospaced)).foregroundColor(.black)
                                .padding(.horizontal, 16).frame(height: 32).background(RoundedRectangle(cornerRadius: 8).fill(buildCyan))
                        }.buttonStyle(.plain)
                    }
                    // three strata, one shared pitch axis (top+bottom); the mechanism sits between
                    buildEyeLane("INPUT — what arrives", empty: (held.isEmpty && !(door >= 0 && door < buildInGrace.count && buildInGrace[door])) ? "nothing held — LATCH or play at INPUT \(letter)" : nil) {
                        buildEyeRoll(buildEyeInRoll, hue: hue)
                    }
                    buildEyeLane("MECHANISM — the \(buildProcLabel(proc))", empty: nil) {
                        buildEyeMechanism(proc, poolN: held.isEmpty ? 3 : held.count, hue: hue)
                    }
                    buildEyeLane("OUTPUT — what leaves", empty: buildOutRoll.isEmpty && buildEditStartedAt == nil ? "—" : nil) {
                        buildEyeRoll(buildOutRoll, hue: hue, editStart: buildEditStartedAt)   // TOUCH-TO-DIFF (idea 24)
                    }
                }
                .padding(18)
            }
            .transition(.opacity)
        }
    }
    // A titled full-width lane; `empty` (if set) shows teaching/idle text instead of the content.
    @ViewBuilder private func buildEyeLane<C: View>(_ title: String, empty: String?, @ViewBuilder _ content: () -> C) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title).font(.system(size: 11, weight: .heavy, design: .monospaced)).foregroundColor(buildDim).tracking(1)
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 8).fill(Color.white.opacity(0.04))
                if let empty {
                    Text(empty).font(.system(size: 13, weight: .heavy, design: .monospaced)).foregroundColor(buildCyan.opacity(0.8)).padding(.leading, 14)
                } else {
                    content()
                }
            }
        }.frame(maxHeight: .infinity)
    }
    // A drifting note roll (input or output): marks enter at the right ("now"), drift left over 2.5s; y = pitch (C1–C7),
    // opacity by velocity + age. A bright NOW line marks the right edge (the shared present across the lanes).
    @ViewBuilder private func buildEyeRoll(_ marks: [OutMark], hue: Color, editStart: Date? = nil) -> some View {
        let lo = 24.0, span = 72.0
        TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: animationsPaused || (marks.isEmpty && editStart == nil))) { tl in
            let now = tl.date
            let glow = editStart == nil ? 0.0 : max(0.0, 1 - (buildLastEditAt.map { now.timeIntervalSince($0) } ?? 1) / 0.6)
            Canvas { ctx, size in
                for oct in stride(from: 0.0, through: 1.0, by: 12.0 / span) {           // faint octave gridlines
                    let y = size.height * (1 - CGFloat(oct))
                    ctx.stroke(Path { $0.move(to: CGPoint(x: 0, y: y)); $0.addLine(to: CGPoint(x: size.width, y: y)) }, with: .color(.white.opacity(0.05)), lineWidth: 1)
                }
                for m in marks {
                    let age = now.timeIntervalSince(m.born)
                    if age < 0 || age > 2.5 { continue }
                    let x = size.width * CGFloat(1 - age / 2.5)
                    let lane = CGFloat(min(1, max(0, (Double(m.note) - lo) / span)))
                    let y = size.height * (1 - lane)
                    let isNew = editStart.map { m.born >= $0 } ?? false
                    let op = (1 - age / 2.5) * (isNew ? 1.0 : (0.5 + 0.5 * m.vel) * (editStart == nil ? 1.0 : 0.35))
                    let r = CGRect(x: x - 4, y: y - 3, width: 8, height: 6)
                    ctx.fill(Path(roundedRect: r, cornerRadius: 3), with: .color(hue.opacity(op)))
                    if isNew { ctx.stroke(Path(roundedRect: r.insetBy(dx: -1.5, dy: -1.5), cornerRadius: 4), with: .color(.white.opacity(0.9 * (1 - age / 2.5))), lineWidth: 1.2) }
                }
                ctx.stroke(Path { $0.move(to: CGPoint(x: size.width - 1, y: 0)); $0.addLine(to: CGPoint(x: size.width - 1, y: size.height)) },
                           with: .color(.white.opacity(0.35)), lineWidth: 2)                // the NOW line
            }
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(hue.opacity(glow), lineWidth: 2))
        }
    }
    // The MECHANISM lane: the machine drawn live + read-only, with a position light on where it is now. EUCLID draws its
    // pulse pattern; ARP draws its note-WALK contour (up/down/triangle/scatter — self-explaining); every other type shows
    // the generic 8-step position lane (bespoke per-type art is the v2 rollout — Paul 2026-08-25).
    @ViewBuilder private func buildEyeMechanism(_ proc: ProcessorSlot, poolN: Int, hue: Color) -> some View {
        if proc.type == .arp { buildEyeArp(proc, poolN: poolN, hue: hue) }
        else if proc.type == .euclid { buildEyeEuclid(proc, hue: hue) }
        else { buildEyeStepLane(proc, hue: hue) }
    }
    // EUCLID: the K-of-N rhythm on a rail — a BOLD hue dot on every HIT step, a faint tick on the rests, and a ring on the
    // step under the playhead (whether hit or rest). INVERT strikes the rests (matches the engine). Reads as the pattern.
    private func buildEyeEuclid(_ proc: ProcessorSlot, hue: Color) -> some View {
        let n = max(2, min(16, proc.params.euclidSteps ?? 8))
        let k = max(0, min(n, proc.params.euclidPulses ?? 5))
        let base = euclidPattern(pulses: k, steps: n, rotation: proc.params.euclidRot ?? 0)
        let inv = proc.params.euclidInvert ?? false
        let live = (d.playing && d.effColumn >= 0) ? d.effColumn % n : -1
        return Canvas { ctx, size in
            let cw = size.width / CGFloat(n), cy = size.height / 2
            ctx.stroke(Path { $0.move(to: CGPoint(x: cw / 2, y: cy)); $0.addLine(to: CGPoint(x: size.width - cw / 2, y: cy)) },
                       with: .color(.white.opacity(0.1)), lineWidth: 1)                 // the rail
            for s in 0..<n {
                let cx = CGFloat(s) * cw + cw / 2
                let isHit = (s < base.count && base[s]) != inv                          // INVERT flips hit⇄rest
                if isHit {
                    let r: CGFloat = s == live ? 8 : 6
                    ctx.fill(Path(ellipseIn: CGRect(x: cx - r, y: cy - r, width: 2 * r, height: 2 * r)), with: .color(hue.opacity(s == live ? 1 : 0.75)))
                } else {
                    ctx.fill(Path(ellipseIn: CGRect(x: cx - 2, y: cy - 2, width: 4, height: 4)), with: .color(.white.opacity(0.2)))
                }
                if s == live {
                    ctx.stroke(Path(ellipseIn: CGRect(x: cx - 12, y: cy - 12, width: 24, height: 24)), with: .color(.white.opacity(0.85)), lineWidth: 1.5)
                }
            }
        }
    }
    // GENERIC MECHANISM (types without bespoke art yet): the 8-column position lane, the live column lit.
    private func buildEyeStepLane(_ proc: ProcessorSlot, hue: Color) -> some View {
        let col = (d.playing && d.effColumn >= 0) ? d.effColumn % 8 : -1
        return Canvas { ctx, size in
            let cw = size.width / 8
            for s in 0..<8 {
                let cell = CGRect(x: CGFloat(s) * cw + 2, y: 6, width: max(2, cw - 4), height: size.height - 12)
                ctx.fill(Path(roundedRect: cell, cornerRadius: 5), with: .color(.white.opacity(0.08)))
                if s == col { ctx.fill(Path(roundedRect: cell, cornerRadius: 5), with: .color(hue.opacity(0.9))) }
            }
        }
    }
    // ARP note-WALK: the arp visits `pool × octaves` notes one per rate-tick, ordered by PATTERN. Drawn as a contour of
    // dots (height = the pool rank it lands on) joined by faint lines — UP climbs, DOWN falls, UP-DN bounces, RANDOM
    // scatters — with the current step lit + a rising sweep line. Reads as "an UP arp, here now", not eight blank boxes.
    private func buildEyeArp(_ proc: ProcessorSlot, poolN: Int, hue: Color) -> some View {
        let pat = proc.params.pattern ?? .up
        let oct = max(1, min(4, proc.params.octaves ?? 1))
        let cyc = min(16, max(2, max(1, poolN) * oct))
        let ranks = (0..<cyc).map { arpRankForStep($0, cyc: cyc, pattern: pat) }
        let rate = proc.params.rate?.beats ?? 0.25
        let pos = (d.playing && rate > 0) ? ((Int((d.beat / rate).rounded(.down)) % cyc) + cyc) % cyc : -1
        return Canvas { ctx, size in
            let cw = size.width / CGFloat(cyc)
            func pt(_ i: Int) -> CGPoint {
                CGPoint(x: CGFloat(i) * cw + cw / 2,
                        y: size.height - 8 - (size.height - 16) * CGFloat(ranks[i]) / CGFloat(max(1, cyc - 1)))
            }
            var line = Path()                                                   // the walk contour
            for i in 0..<cyc { i == 0 ? line.move(to: pt(i)) : line.addLine(to: pt(i)) }
            ctx.stroke(line, with: .color(hue.opacity(0.35)), lineWidth: 1.5)
            for i in 0..<cyc {
                let p = pt(i), live = i == pos, r: CGFloat = live ? 6 : 4
                ctx.fill(Path(ellipseIn: CGRect(x: p.x - r, y: p.y - r, width: 2 * r, height: 2 * r)),
                         with: .color(live ? hue : hue.opacity(0.55)))
                if live { ctx.stroke(Path { $0.move(to: CGPoint(x: p.x, y: 0)); $0.addLine(to: CGPoint(x: p.x, y: size.height)) },
                                     with: .color(.white.opacity(0.25)), lineWidth: 1) }
            }
        }
    }
    // The pool-RANK the arp lands on at step i (its note-order shape). Pure geometry — the drawing, not the exact pitch.
    private func arpRankForStep(_ i: Int, cyc: Int, pattern: ArpPattern) -> Int {
        guard cyc > 1 else { return 0 }
        switch pattern {
        case .up, .asPlayed: return i % cyc
        case .down:          return (cyc - 1) - (i % cyc)
        case .upDown:        let period = 2 * (cyc - 1); let j = i % period; return j < cyc ? j : period - j
        case .random:        return Int(splitmix64Mix(UInt64(i) &+ 0x9E3779B9) % UInt64(cyc))
        }
    }
    // The IN silhouette: a compact C1–C7 piano (proper white/black keys), held notes filled the colour hue.
    private func buildInKeyboard(_ held: [Int], hue: Color) -> some View {
        let set = Set(held)
        return pianoKeysCanvas(lo: 24, hi: 96) { midi in set.contains(midi) ? hue : nil }   // C1..C7
            .frame(height: 30)
            .background(RoundedRectangle(cornerRadius: 4).fill(Color.black.opacity(0.25)))
    }
    // The OUT mini-roll: emitted note-ons drift right→left over ~2.5s, lane = pitch, opacity by velocity + age. A "—" when
    // idle. TOUCH-TO-DIFF (idea 24): while a control is being edited, the notes the NEW settings produce (born after the
    // gesture started) draw bright + ringed, the OLD ones dim, and the box glows — so your edit's effect stands out live.
    @ViewBuilder private func buildOutStrip(hue: Color) -> some View {
        let editStart = buildEditStartedAt
        TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: animationsPaused || (buildOutRoll.isEmpty && editStart == nil))) { tl in
            let now = tl.date
            let glow = editStart == nil ? 0.0 : max(0.0, 1 - (buildLastEditAt.map { now.timeIntervalSince($0) } ?? 1) / 0.6)
            buildRollCanvas(buildOutRoll, hue: hue, now: now, editStart: editStart)
                .overlay(RoundedRectangle(cornerRadius: 4).stroke(hue.opacity(glow), lineWidth: 2))
        }
        .frame(height: 30)
        .background(RoundedRectangle(cornerRadius: 4).fill(Color.black.opacity(0.25)))
        .overlay(alignment: .leading) {
            if buildOutRoll.isEmpty {
                Text("—").font(.system(size: 12, weight: .heavy, design: .monospaced)).foregroundColor(buildDim).padding(.leading, 8)
            }
        }
    }
    // Shared note-roll drawing (OUT strip + Stage Eye lanes). `editStart` non-nil ⇒ TOUCH-TO-DIFF: marks born at/after it
    // are the NEW behaviour (bright + white ring), earlier ones dim to a "before" ghost. nil ⇒ a plain roll (input lane).
    private func buildRollCanvas(_ marks: [OutMark], hue: Color, now: Date, editStart: Date?) -> some View {
        let lo = 24.0, span = 72.0
        return Canvas { ctx, size in
            for m in marks {
                let age = now.timeIntervalSince(m.born)
                if age < 0 || age > 2.5 { continue }
                let x = size.width * CGFloat(1 - age / 2.5)
                let lane = CGFloat(min(1, max(0, (Double(m.note) - lo) / span)))
                let y = size.height * (1 - lane)
                let isNew = editStart.map { m.born >= $0 } ?? false
                let base = 0.45 + 0.55 * m.vel
                let op = (1 - age / 2.5) * (isNew ? 1.0 : base * (editStart == nil ? 1.0 : 0.35))   // dim the "before" while editing
                let r = CGRect(x: x - 3, y: y - 2, width: 6, height: 4)
                ctx.fill(Path(roundedRect: r, cornerRadius: 2), with: .color(hue.opacity(op)))
                if isNew {
                    ctx.stroke(Path(roundedRect: r.insetBy(dx: -1.5, dy: -1.5), cornerRadius: 3),
                               with: .color(.white.opacity(0.9 * (1 - age / 2.5))), lineWidth: 1)
                }
            }
        }
    }

    // ProcessorBox for a BUILD colour-template slot — mirrors DiagView.slotBox but writes COLOUR-scoped (the selected
    // colour's templateChain via withChainColour). Our own header carries Delete/Bypass, so the box's chrome is hidden.
    @ViewBuilder private func buildSlotBox(_ i: Int, _ slot: ProcessorSlot, cid: String) -> some View {
        let sc: Colour = { var c = Colour(colourID: cid, type: slot.type); c.paramsA = slot.params; return c }()
        ProcessorBox(
            colour: sc, colourIndex: -1, face: .a,
            onEdit: { mutate in
                buildChainEditSlot(i) { s in
                    var tmp = Colour(colourID: cid, type: s.type); tmp.paramsA = s.params
                    mutate(&tmp); s.params = tmp.paramsA
                }
            },
            onTranspose: { _ in }, onMorph: { _ in },
            onSetTypeA: { t in buildChainSetType(i, t) },
            height: 260, slotMode: true, slotBypassed: slot.bypassed,
            accentOverride: buildCardHue,   // the ONE machine/card hue (grey on the SELECT audition) — matches the machine box
            passHead: d.playing ? (d.pass & 3) : -1,
            liveStep: d.playing ? ((d.effColumn % 8) + 8) % 8 : -1,   // PLAYHEAD (idea 15): the live grid column sweeps the matrix/lane
            onBypass: { buildChainToggleBypass(i) },
            onRemove: { buildChainRemoveSlot(i); buildEditSlot = nil },
            onMacro: nil, plainTitle: true, showSlotChrome: false,
            avoidInputNotes: recvHeldNotes.map { $0.map(Int.init) },   // AVOID piano: per-input held notes (armed/scale doors report their pool) — live while the editor is open
            avoidChainInputDoor: buildSelectedRow.map { buildRowReceiverResolved($0) } ?? buildSelReceiver)   // the door feeding THIS chain → the OUTPUT piano predicts from its notes
    }

    // BUILD chain edits — colour-scoped + POSITION-PRESERVING: every edit works on the SHOWN chain and is written
    // whole with setColourChain (so slot indices stay put; a deleted slot leaves a passthrough GAP, not a shift).
    private func buildApplyChain(_ chain: [ProcessorSlot]) {
        guard let cid = ddSelectedColourID else { return }   // guard ABOVE the record so a nil selection never pushes a no-op undo step (U10 fix 2026-08-27)
        buildRecordUndo("chain")   // BUILD UNDO: chain edit (add/remove/move/param) — coalesced so a param scrub is one step
        // idea 24 TOUCH-TO-DIFF: every chain edit funnels here — stamp the edit clock so the OUT read-out glows and the
        // notes the NEW settings produce (born after the gesture started) stand out from the old ones, as you drag.
        let now = Date(); if buildEditStartedAt == nil { buildEditStartedAt = now }; buildLastEditAt = now
        buildWriteColourMachine(cid, chain)
        // FERRY MIRROR (Paul 2026-08-30): a SELECT-grid ferry aim edits the transient gsAud (so the audition stays quantized-
        // swappable). Card edits were auditioned but never written back — an ARP change was HEARD in the audition so it read
        // as "working", a PASSGATE change wasn't obvious → "not applied", and NEITHER persisted to the part row. Mirror the
        // edited chain (minus its baked register-home) straight to the aimed row's REAL colour so the part row updates too.
        if cid == buildGridSelAudID, let mr = buildFerryMirrorRow, let real = buildRowColour(mr) {
            let t = buildColourTranspose[real] ?? 0
            buildWriteColourMachine(real, buildStripRegisterHome(chain, transpose: t))
        }
        // PLACED: a pending tab whose chain has diverged from its source is committed (stops pulsing). (2026-08-17)
        if let p = buildPendingTab, buildRowColour(p) == cid, chain != buildPendingSource {
            buildPendingTab = nil; buildPendingSource = []
        }
    }
    // Reverse buildGridSelLoadChain's register-home bake: it inserts a leading TRANSPOSE utility (== the colour's own
    // transpose) so the ephemeral audition swaps atomically. Dropping it before writing to the REAL colour (which stores
    // the register home in buildColourTranspose, not as a slot) avoids double-transposing. No baked slot ⇒ returned as-is.
    private func buildStripRegisterHome(_ chain: [ProcessorSlot], transpose: Int) -> [ProcessorSlot] {
        guard transpose != 0, let first = chain.first, first.type == .transpose,
              (first.params.utilTranspose ?? 0) == max(-24, min(24, transpose)) else { return chain }
        return Array(chain.dropFirst())
    }
    private func buildChainEditSlot(_ i: Int, _ mutate: (inout ProcessorSlot) -> Void) {
        var c = selectedColourChain(); guard i < c.count else { return }; mutate(&c[i]); buildApplyChain(c)
    }
    private func buildChainToggleBypass(_ i: Int) { buildChainEditSlot(i) { $0.bypassed.toggle() } }
    private func buildChainSetType(_ i: Int, _ t: ProcessorType) { buildChainEditSlot(i) { $0.type = t } }
    private func buildChainRemoveSlot(_ i: Int) {                  // DELETE → leave an empty (passthrough) box, keep positions
        var c = selectedColourChain(); guard i < c.count else { return }; c[i] = buildPassthroughSlot(); buildApplyChain(c)
    }
    // DRAG-TO-REORDER (Paul 2026-08-25): a POSITIONAL move — the dragged processor LANDS at the target box (box index `to`,
    // OVERWRITING whatever was there) and its ORIGINAL box is vacated (→ empty passthrough). Nothing else shifts. So RIFF on
    // box 1 + ARP on box 2, RIFF→box 3 ⇒ box 1 empty · box 2 ARP · box 3 RIFF. The chain folds in box order (composeChainSet).
    private func buildChainMoveSlot(from: Int, to: Int) {
        guard from != to, from >= 0, to >= 0, to < 8 else { return }
        var c = selectedColourChain()
        guard from < c.count else { return }
        let moved = c[from]
        while c.count <= to { c.append(buildPassthroughSlot()) }   // extend to reach the target box (dropping onto an empty slot)
        c[to] = moved                                              // land at the target box (overwrite it)
        c[from] = buildPassthroughSlot()                           // vacate the original box (trailing empties are trimmed on read)
        buildApplyChain(c)
    }
    // The 2×4 processor grid: map a finger location (in the "chainBlock" space) to the box index under it (any of the 8,
    // incl. empty ones — a processor can be dropped onto an empty box).
    private func buildChainTargetIndex(_ loc: CGPoint, boxW: CGFloat, boxH: CGFloat, gap: CGFloat, count: Int) -> Int {
        let col = loc.x < (boxW + gap * 0.5) ? 0 : 1
        let row = max(0, min(3, Int(max(0, loc.y) / (boxH + gap))))
        return max(0, min(7, row * 2 + col))
    }
    // ── THE STOREFRONT CATALOG ───────────────────────────────────────────────────────────────────────────────────
    // ONE ENGINE, MANY DOORS (design ratified by Paul 2026-08-22, AcceptanceCriteria-storefront-catalog.md):
    // multi-mode stages split into MULTIPLE CARDS, each pre-setting its mode; grouped by musical intent; each card
    // carries a plain one-liner (the selector teaches). Codable type IDs never rename — a split card is (type + a
    // params preset); `apply` sets the mode field on a fresh slot. Names/blurbs are DISPLAY-ONLY.
    struct BuildCard {
        let name: String            // storefront name (e.g. "RATCHET COIN", "LFO")
        let blurb: String           // catalog one-liner
        let type: ProcessorType     // the frozen engine ID this card opens
        let apply: (inout ColourParams) -> Void   // pre-set the mode ({ } for a single-mode card)
    }
    struct BuildCardGroup { let title: String; let note: String?; let cards: [BuildCard] }

    // THE STOREFRONT SPLIT (Paul 2026-08-22): multi-mode stages appear as SEPARATE cards, each pre-setting its mode;
    // the mode is then FIXED (no in-editor radio — GridUI dropped it) and WRITTEN on the chain box (`buildProcLabel`).
    // To change mode you pick a different card. Grouped by musical intent; each card carries a plain one-liner.
    // Codable type IDs never rename — a split card is (type + a params mode-preset).
    private var buildCatalog: [BuildCardGroup] {
        func C(_ n: String, _ b: String, _ t: ProcessorType, _ a: @escaping (inout ColourParams) -> Void = { _ in }) -> BuildCard {
            BuildCard(name: n, blurb: b, type: t, apply: a)
        }
        return [
            BuildCardGroup(title: "MELODY", note: nil, cards: [
                C("ARP", "Walks the held chord one note at a time.", .arp),
                C("RIFF", "An authored line that follows the held chord — the same shape in any key.", .riff),
                C("CASCADE", "Builds the chord up one note at a time, holding each.", .cascade),
                C("STRUM", "Rolls the chord in like a guitar rake.", .strum),
                C("GLIDE", "One sliding voice: small steps bend, big leaps jump.", .glide),
            ]),
            BuildCardGroup(title: "HARMONY", note: nil, cards: [
                C("HARMONIZE", "Adds up to three tuned voices to every note.", .harmonize),
                C("TUTTI COIN", "Flips a coin each step: the whole chord, or one note.", .tutti) { $0.tuttiMode = .coin },
                C("TUTTI PATTERN", "Paints the chord's shape per step — full, top two, one note, rest.", .tutti) { $0.tuttiMode = .pattern },
                C("SPLIT", "Keeps only part of the chord: top, bottom, or a range.", .split),
                C("DRONE", "Holds the chord as a sustained pad.", .drone),
                C("LOCK TO KEY", "Plays only the notes another input is playing — point it at a scale channel to stay in its key.", .avoid) { $0.avoidRefKind = .door; $0.avoidRefIndex = 1; $0.avoidMode = .lock; $0.avoidAction = .move },
                C("AVOID CLASHES", "Keeps clear of everything already playing — its notes and the semitones that clash with them.", .avoid) { $0.avoidRefKind = .sounding; $0.avoidMode = .avoid; $0.avoidAction = .remove; $0.avoidWhat = .clash },
                C("CHORDS", "Play a note → its diatonic chord, in key. FOLLOW the notes you play, or switch to a drawn PROGRESSION (plays in any key). Follow with STRUM / ARP / DRONE.", .chords) { $0.chordsMode = .follow },   // Paul 2026-09-01: FOLLOW is the responsive default (play → chord); PATTERN/WALK are picked in the editor
            ]),
            BuildCardGroup(title: "RHYTHM", note: nil, cards: [
                C("RATCHET", "Re-strikes the whole chord in fast rolls, every step.", .ratchet) { $0.rtcMode = .all },
                C("RATCHET COIN", "Rolls by chance: some steps burst, some hit plain.", .ratchet) { $0.rtcMode = .coin },
                C("RATCHET PATTERN", "Paint which steps roll, and how many hits each.", .ratchet) { $0.rtcMode = .pattern },
                C("BURST", "One accelerating (or slowing) roll per step.", .burst) { $0.burstMode = .once },
                C("BURST COIN", "A roll by chance: some steps fire, some rest.", .burst) { $0.burstMode = .coin },
                C("BURST PATTERN", "Paint where rolls start and how far they stretch.", .burst) { $0.burstMode = .pattern },
                C("EUCLID", "Spreads K hits evenly around the cycle.", .euclid),
                C("WEAVE LADDER", "Every note pulses at its own speed: bass slow, top fast.", .weave) { $0.weaveMode = .ladder },
                C("WEAVE HARMONIC", "Note speeds follow the harmonic series: 1×, 2×, 3×…", .weave) { $0.weaveMode = .harmonic },
                C("WEAVE DRAWN", "You set each note's pulse speed by hand.", .weave) { $0.weaveMode = .drawn },
                C("WEAVE EUCLID", "Each note gets its own euclidean rhythm, denser on top.", .weave) { $0.weaveMode = .euclid },
                C("PASSES", "Plays only on the laps you choose (1–4).", .passgate),
                C("CHANCE", "Lets notes through by dice roll — the same roll every loop.", .chance),
                C("HOCKET GAPS", "Plays your notes in another synth's silences — call and response.", .hocket) { $0.hocketMode = .gaps },
                C("HOCKET TRADE", "Trades hits with another synth — one line split across two.", .hocket) { $0.hocketMode = .trade },
            ]),
            BuildCardGroup(title: "DYNAMICS", note: nil, cards: [
                C("HUMANIZE", "Loosens the timing and softens the hits: a human touch.", .humanize),
            ]),
            BuildCardGroup(title: "CONTROL", note: "Moves synth controls — makes no notes of its own.", cards: [
                C("LFO", "A wave moving a synth knob: sweeps and wobbles.", .mod) { $0.modSource = .shape },
                C("FOLLOWER", "Your playing becomes the control: busier = higher.", .mod) { $0.modSource = .follow },
                C("STEP MOD", "Draw an 8-step pattern that moves a knob.", .mod) { $0.modSource = .steps },
                C("ENVELOPE", "A rise-and-fall sweep each time the cell starts.", .mod) { $0.modSource = .strike },
                C("CC IN", "Reads an incoming knob and re-ranges it onward.", .mod) { $0.modSource = .extern },
            ]),
            BuildCardGroup(title: "TIME", note: nil, cards: [
                C("ECHO", "Repeats each note, fading away like a delay.", .echo),
                C("SHIFT", "Drags the whole chord behind the beat: laid-back.", .shift),
                C("LENGTH", "Shapes how long each step rings: staccato to ties.", .length),
            ]),
            BuildCardGroup(title: "UTILITY", note: "Plain per-chain overrides — move one chain without touching the door.", cards: [
                C("OCTAVE", "Plays this chain a few octaves up or down.", .octave),
                C("TRANSPOSE", "Shifts this chain by semitones (off the held chord).", .transpose),
                C("CHANNEL", "Sends this chain out on its own MIDI channel.", .channel),
                C("NUDGE", "Slides this chain a little earlier or later in time.", .nudge),
                C("DEST", "Sends each step to a chosen emitter — hocket between synths.", .dest),
                C("MUTE MATRIX", "Mutes chosen emitters per step — gate parts in and out.", .muteMatrix),
                C("TAP", "Sends a copy of the stream out here + passes it on — layered parallel outputs.", .tap),
            ]),
        ]
    }

    // A chain-box / editor label: the type name + its fixed mode written in (e.g. "WEAVE HARM", "MOD LFO"), so the
    // mode is legible without an in-editor radio (Paul 2026-08-22). Single-mode processors show just the type.
    private func buildProcLabel(_ s: ProcessorSlot) -> String {
        // AVOID/LOCK self-names by its MODE (Paul §7): the slot reads "LOCK A MIXO" / "AVOID CLASHES".
        let avoidBase = (s.params.avoidMode ?? .avoid) == .lock ? "LOCK" : "AVOID"
        let base = s.type == .passgate ? "PASSES" : (s.type == .muteMatrix ? "MUTE MTX" : (s.type == .avoid ? avoidBase : s.type.rawValue))
        let m: String
        let letters = ["A", "B", "C", "D"]
        switch s.type {
        case .ratchet: switch s.params.rtcMode ?? .all { case .all: m = "ALL"; case .coin: m = "COIN"; case .pattern: m = "PAT" }
        case .burst:   switch s.params.burstMode ?? .once { case .once: m = "ONCE"; case .coin: m = "COIN"; case .pattern: m = "PAT" }
        case .tutti:   switch s.params.tuttiMode ?? .coin { case .coin: m = "COIN"; case .pattern: m = "PAT" }
        case .weave:   switch s.params.weaveMode ?? .ladder { case .ladder: m = "LAD"; case .harmonic: m = "HARM"; case .drawn: m = "DRAWN"; case .euclid: m = "EUC" }
        case .mod:     switch s.params.modSource ?? .shape { case .shape: m = "LFO"; case .follow: m = "FOLLOW"; case .steps: m = "STEP"; case .strike: m = "ENV"; case .extern: m = "CC IN" }
        case .hocket:  switch s.params.hocketMode ?? .gaps { case .gaps: m = "GAPS"; case .trade: m = "TRADE" }
        case .avoid:
            switch s.params.avoidRefKind ?? .sounding {
            case .key:      m = "\(["C","C#","D","D#","E","F","F#","G","G#","A","A#","B"][(((s.params.avoidRoot ?? 0) % 12) + 12) % 12]) \((s.params.avoidScale ?? .major).label)"   // legacy/decode-only — the KEY reference is no longer settable in the UI (Paul 2026-08-31)
            case .door:     m = "IN \(letters[max(0, min(3, s.params.avoidRefIndex ?? 0))])"
            case .wire:     m = "OUT \(letters[max(0, min(3, s.params.avoidRefIndex ?? 0))])"
            case .sounding: m = "CLASHES"
            }
        default:       m = ""
        }
        return m.isEmpty ? base : "\(base) \(m)"
    }

    // ADD a catalog CARD at box `i`: populate the box with the card's type, pre-set its mode, open its editor.
    private func buildChainAddCard(_ i: Int, _ card: BuildCard) {
        if ddSelectedColourID == nil {                                    // no colour holds the chain (SELECT grid, nothing auditioned since the auto-audition was retired) →
            buildColourReg[buildGridSelAudID] = []                        // start a FRESH transient so buildApplyChain has a target + the card can open (BUG fix 2026-08-29)
            colourHueOverride[buildGridSelAudID] = colourHexes.first ?? 0x808080
            buildColourTranspose[buildGridSelAudID] = 0
            buildSyncColours()
            buildSelID = buildGridSelAudID
        }
        var c = selectedColourChain()
        while c.count <= i { c.append(buildPassthroughSlot()) }
        var slot = ProcessorSlot(type: card.type)
        card.apply(&slot.params)
        c[i] = slot
        buildApplyChain(c)
        buildAddSlot = nil; buildEditSlot = i
    }

    // ── ADD-PROCESSOR PICKER (THE CATALOG) ───────────────────────────────────────────────────────────────────────
    // The storefront: 31 cards grouped by musical intent, each with a plain one-liner. Selecting one populates box
    // `slot` (pre-set to the card's mode) and opens its editor.
    @ViewBuilder private func buildProcessorPicker(slot: Int, size: CGSize) -> some View {
        let hue = buildCardHue   // the ONE machine/card hue (grey on the SELECT audition) — never the raw gsAud palette throwback
        ZStack {
            Color.black.opacity(0.55).ignoresSafeArea().contentShape(Rectangle()).onTapGesture { buildAddSlot = nil }
            VStack(alignment: .leading, spacing: 12) {
                Text("ADD PROCESSOR").font(.system(size: 20, weight: .heavy, design: .monospaced)).foregroundColor(.white).tracking(1)
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        ForEach(buildCatalog, id: \.title) { group in
                            VStack(alignment: .leading, spacing: 6) {
                                Text(group.title).font(.system(size: 12, weight: .heavy, design: .monospaced)).tracking(2).foregroundColor(hue)
                                if let n = group.note {
                                    Text(n).font(.system(size: 11, weight: .regular, design: .monospaced)).foregroundColor(.white.opacity(0.5))
                                }
                                ForEach(group.cards, id: \.name) { card in
                                    Button { buildChainAddCard(slot, card) } label: {
                                        HStack(spacing: 10) {
                                            Image(systemName: emblemSymbol(card.type)).font(.system(size: 18, weight: .black)).foregroundColor(hue).frame(width: 26)
                                            VStack(alignment: .leading, spacing: 2) {
                                                Text(card.name).font(.system(size: 15, weight: .heavy, design: .monospaced)).foregroundColor(.white)
                                                Text(card.blurb).font(.system(size: 11, weight: .regular, design: .monospaced)).foregroundColor(.white.opacity(0.6)).fixedSize(horizontal: false, vertical: true)
                                            }
                                            Spacer(minLength: 0)
                                        }
                                        .padding(.horizontal, 12).padding(.vertical, 8).frame(maxWidth: .infinity, alignment: .leading)
                                        .background(RoundedRectangle(cornerRadius: 10).fill(Color.white.opacity(0.06)))
                                        .overlay(RoundedRectangle(cornerRadius: 10).stroke(hue.opacity(0.5), lineWidth: 1))
                                    }.buttonStyle(.plain)
                                }
                            }
                        }
                    }
                }
            }
            .padding(18)
            .frame(width: min(640, size.width - 60)).frame(maxHeight: size.height * 0.82)
            .background(RoundedRectangle(cornerRadius: 16).fill(buildPanel))
            .overlay(RoundedRectangle(cornerRadius: 16).stroke(hue, lineWidth: 2))
            .shadow(color: .black.opacity(0.5), radius: 20, y: 8)
            .contentShape(Rectangle()).onTapGesture { }           // swallow taps inside the panel
        }
    }



    // ─────────────────────────────────────────────────────────────────────────────────────────────────────────────
    // THE GRID SELECTOR (AcceptanceCriteria-grid-selector.md, ratified 2026-08-22) — a full-page 8×8 where each cell is
    // a COMPLETE MIDI chain. Tap = audition it live against the current input (mutually-exclusive, quantized next-step,
    // the deployed piece plays on); the RIGHT column shows the selected chain read-only; COMMIT overwrites the ARRIVAL
    // row's chain (one undo), CANCEL restores. It rides the EXISTING chain-audition path (ddSolo + buildPublishScene)
    // on ONE reusable transient ephemeral colour, so the document is untouched until COMMIT (non-destructive by
    // construction). Banks v1: DEALT (Dice.rollEnsemble ×8 = 64 seeded chains, RE-DEAL) + MY LIBRARY (saved + factory
    // cells). FACTORY-as-a-curated-bank + EXCLUSIVE-OFF layering are deferred (flagged for Paul). The reel records every
    // audition for free (real emission). §6 governor: ordinary derivation, standing caps apply.
    private var buildGridSelAudID: String { "gsAud" }   // the ONE reusable transient colour that carries the browsed chain

    func buildOpenGridSel() {
        buildGridSelArrivalRow = buildSelectedRow                        // FREEZE the arrival row (buildSelectedRow resolves live)
        buildGridSelPriorSolo = ddSolo                                   // snapshot the pre-open workshop voice so CANCEL restores it (never silence a voice we didn't own)
        buildGridSelPriorStaging = buildStagingPlaying
        buildGridSelPriorSel = buildSelID
        buildGridSelPriorReceiver = buildSelReceiver
        buildGridSelPriorEmitters = buildPartEmitters
        if let r = buildGridSelArrivalRow { buildSelReceiver = buildRowReceiverResolved(r) }   // audition through the ARRIVAL row's door (faithful preview)
        let saved = au?.libraryCellSummaries() ?? []
        buildGridSelLib = saved + (au?.factoryLibrarySummaries() ?? [])  // v1 folds factory in so first run isn't empty
        buildGridSelLibFactoryFrom = saved.count                         // entries at/after this index are FACTORY (resolve by section, not by name)
        buildGridSelRecomputeCategory()                                  // the current category's matching library slice (SELECT rail filter)
        buildGridSelSel = nil
        buildGridSelBuildCorpus()                                        // §3.1 kick the pregen corpus (background, once) — DEAL upgrades to it when ready
        if buildGridSelDealt.isEmpty || !buildGridSelCorpus.isEmpty { buildGridSelDeal() }   // corpus ready ⇒ instant draw; else a fresh 64
        else { buildGridSelComputeCellRolls() }                          // dealt already stocked (reopen) → compute its drifting faces now
        buildGridSelComputeRowRolls()                                    // the row selectors' drifting faces
        buildGridSelOpen = true
    }
    // Open it for the SELECT room only if it isn't already live (roomsPage drives this on room entry).
    func buildEnsureGridSelOpen() { if !buildGridSelOpen { buildOpenGridSel() } }
    // DEALT — 64 seeded, replay-safe chains (8 archetypes × 8 re-rolls). rollEnsemble runs the offline Router many times,
    // so generate OFF the main thread with a spinner (64 = 8× the grid-RANDOMIZE cost, too much to block on).
    private func buildGridSelDeal() {
        // §3.1 THE PREGEN CORPUS: once the pool exists, DEAL is INSTANT — a seeded shuffle drawing 64 (RE-DEAL bumps the
        // seed → a fresh 64). While the corpus is still building, fall back to a fresh 64-roll so the first open isn't empty.
        if !buildGridSelCorpus.isEmpty {
            var rng = DiceRNG(seed: buildGridSelDealSeed)
            buildGridSelDealt = Array(buildGridSelCorpus.shuffled(using: &rng).prefix(64))
            buildGridSelComputeCellRolls()                               // the drifting note faces for the freshly-dealt 64
            return
        }
        guard !buildGridSelGenerating else { return }                    // re-entrancy: one deal at a time (racing deals could land out of seed order)
        buildGridSelGenerating = true
        let seed = buildGridSelDealSeed
        DispatchQueue.global(qos: .userInitiated).async {
            var rng = DiceRNG(seed: seed)
            var out: [Dice.EnsembleRow] = []
            for _ in 0..<8 { out.append(contentsOf: Dice.rollEnsemble(using: &rng)) }   // each call = 8 contrasting archetypes
            DispatchQueue.main.async { self.buildGridSelDealt = out; self.buildGridSelGenerating = false; self.buildGridSelComputeCellRolls() }
        }
    }
    // §3.1 build the corpus INCREMENTALLY on a low-priority background thread — a batch of 64 at a time, chaining until the
    // target, so it never blocks and DEAL upgrades to the richer pool after each batch (the "background queue tops it up").
    // Each batch is seeded by the offset ⇒ a stable, deterministic library per session (persisting to disk is a follow-up).
    private func buildGridSelBuildCorpus() {
        let target = 256
        guard !buildGridSelCorpusBuilding, buildGridSelCorpus.count < target else { return }
        buildGridSelCorpusBuilding = true
        let have = buildGridSelCorpus.count
        DispatchQueue.global(qos: .utility).async {
            var rng = DiceRNG(seed: 0xC0DE_5EED &+ UInt64(have))         // per-batch seed offset → deterministic, non-repeating
            let batch = Dice.rollCorpus(count: 64, using: &rng)
            DispatchQueue.main.async {
                self.buildGridSelCorpus.append(contentsOf: batch)
                self.buildGridSelCorpusBuilding = false
                if self.buildGridSelOpen { self.buildGridSelDeal() }     // upgrade the shown 64 to the growing pool
                if self.buildGridSelCorpus.count < target { self.buildGridSelBuildCorpus() }   // top up
            }
        }
    }
    // NEW INTERFACE — SELECT cell-to-cell COPY: stamp the active source onto grid cell i as a NEW in-memory INSTANCE
    // (a fresh hue), never overwriting the saved library; the copied cell then becomes the active/selected cell. (Paul 2026-08-28)
    func roomsCopyToSelectCell(_ i: Int) {
        guard let src = buildGridSelStampSource(), i >= 0, i < 64 else { return }
        var chain = src.chain
        if src.transpose != 0 { var t = ProcessorSlot(type: .transpose); t.params.utilTranspose = max(-24, min(24, src.transpose)); chain.insert(t, at: 0) }   // bake the register home
        buildGridSelOverride[i] = (chain, colourHexes[i % 16])          // the NEW instance (in-memory; disk library untouched)
        buildGridSelComputeCellRolls()                                  // recompute the faces (picks up the override)
        buildGridSelAudition(i)                                         // the copied cell becomes the active/selected cell + auditions
    }

    // Resolve a cell's chain + register + hue. DEALT reads memory; MY LIBRARY loads the cell from disk (TAP/COMMIT only,
    // never per render — the cell FACE uses the cheap in-memory key hash instead).
    private func buildGridSelChainAt(_ i: Int) -> (chain: [ProcessorSlot], transpose: Int, hex: UInt32)? {
        if let ov = buildGridSelOverride[i] { return (ov.chain, 0, ov.hex) }   // NEW INTERFACE: a cell-to-cell COPY instance wins over the bank (Paul 2026-08-28)
        if buildGridSelTab == 0 {
            guard i >= 0 && i < buildGridSelDealt.count else { return nil }
            let e = buildGridSelDealt[i]
            return (e.chain, e.transpose, colourHexes[((i % 8) * 2) % 16])
        } else {
            guard i >= 0 && i < buildGridSelCatIndices.count else { return nil }   // CATEGORY: grid position i → the i-th library entry in the current category
            let L = buildGridSelCatIndices[i]
            guard L >= 0 && L < buildGridSelLib.count else { return nil }
            let name = buildGridSelLib[L].name
            // Resolve by SECTION, not by name — a saved cell may share a factory cell's name (saved rows are [0, factoryFrom)).
            let cell = L >= buildGridSelLibFactoryFrom ? au?.factoryLibraryCell(name: name) : au?.loadLibraryCell(name: name)
            return (cell?.processors ?? [], 0, colourHexes[i % 16])       // hue position-based
        }
    }
    private func buildGridSelPresent(_ i: Int) -> Bool { buildGridSelOverride[i] != nil || (buildGridSelTab == 0 ? i < buildGridSelDealt.count : i < buildGridSelCatIndices.count) }   // a cell-to-cell COPY makes an empty position present too (Paul 2026-08-28); library filtered by CATEGORY (2026-08-29)
    private func buildGridSelCellHex(_ i: Int) -> UInt32 { buildGridSelOverride[i]?.hex ?? (buildGridSelTab == 0 ? colourHexes[((i % 8) * 2) % 16] : colourHexes[i % 16]) }

    // AUDITION — register the browsed chain on the ONE transient colour, select it, and drive the existing chain-voice
    // path: turn the chain voice ON (quantized) if not already, else swap which chain (quantized). Piece plays on.
    private func buildGridSelAudition(_ i: Int) {
        guard let hit = buildGridSelChainAt(i) else { return }
        buildGridSelStampSourceRow = nil                                 // a library CELL is now the active source → clear the active side button (mutual exclusivity; no-op in old BUILD)
        buildGridSelLoadChain(hit.chain, transpose: hit.transpose, hex: hit.hex, sel: i)   // a DEALT/LIBRARY cell — its index is the commit source
    }
    // A select-grid TAP: SELECT MODE focuses the cell into the machine (no play/stop); else it auditions. (Paul 2026-08-31)
    private func buildGridSelTapCell(_ i: Int) {
        guard buildGridSelPresent(i) else { return }
        if buildSelectMode { buildGridSelFocus(i); buildSelectMode = false } else { buildGridSelAudition(i) }   // SELECT ends after one pick (Paul 2026-08-31)
    }
    // FOCUS ONLY (SELECT mode): load the cell into the machine + select it, but DON'T start/swap the audition voice. (Paul 2026-08-31)
    private func buildGridSelFocus(_ i: Int) {
        guard let hit = buildGridSelChainAt(i) else { return }
        buildGridSelStampSourceRow = nil
        buildGridSelLoadChain(hit.chain, transpose: hit.transpose, hex: hit.hex, sel: i, play: false)
    }
    // Load a chain onto the ONE transient audition colour, select it, and drive the chain voice (quantized). Shared by a
    // cell audition (sel = the cell index → the commit source) and a ROW press (sel = nil → a view/hear of that part's chain).
    private func buildGridSelLoadChain(_ raw: [ProcessorSlot], transpose: Int, hex: UInt32, sel: Int?, play: Bool = true) {
        buildGridSelSel = sel
        buildGridSelActiveRoll = gridSelRollBars(raw)                     // the piano-roll shown on the cell + the right column
        // BAKE the register home into the CHAIN (a leading TRANSPOSE utility) rather than the ephemeral colour's transpose:
        // the chain is baked into the published scene + swapped atomically at the STEP boundary, whereas the colour's
        // transpose is re-resolved on every rebuild — so an ephemeral transpose would jump the still-sounding old chain a
        // step early on a quantized swap. This keeps the whole swap quantized. (transpose stays 0 on the transient colour.)
        var chain = raw
        if transpose != 0 { var t = ProcessorSlot(type: .transpose); t.params.utilTranspose = max(-24, min(24, transpose)); chain.insert(t, at: 0) }
        buildColourReg[buildGridSelAudID] = chain
        colourHueOverride[buildGridSelAudID] = hex
        buildColourTranspose[buildGridSelAudID] = 0
        buildSyncColours()
        buildSelID = buildGridSelAudID; ddColourSel = -1                  // ddSelectedColourID now returns the transient
        guard play else { return }                                        // FOCUS ONLY (SELECT mode): shown in the machine, voice untouched (Paul 2026-08-31)
        let instant = !buildGridSelQuantStep || !d.playing
        if !ddSolo {                                                       // chain voice OFF → turn it on
            if instant { buildPendingWorkshopVoice = nil; buildPendingReengage = false; buildSelectMachineVoice() }   // now (+ drop any stale arm)
            else { buildPendingWorkshopVoice = .chain }                   // quantized: commit on the next d.absoluteStep boundary
        } else {                                                          // already the voice → swap the chain
            if instant { buildPendingReengage = false; buildPublishScene() } else { buildPendingReengage = true }
        }
    }
    // Stop the transient audition but KEEP the browser open (tab-switch / RE-DEAL): silence the chain voice, reap the
    // transient, and re-select the pre-open colour so nothing is stranded. The deployed piece plays on.
    private func buildGridSelStopAudition() {
        buildFerryMirrorRow = nil                                        // stop mirroring — the transient is being reaped
        guard buildGridSelSel != nil || ddSolo || buildPendingWorkshopVoice != nil || buildPendingReengage else { return }
        buildGridSelSel = nil; buildGridSelActiveRoll = []
        buildPendingWorkshopVoice = nil; buildPendingReengage = false
        buildColourReg[buildGridSelAudID] = nil; colourHueOverride[buildGridSelAudID] = nil; buildColourTranspose[buildGridSelAudID] = nil
        if buildVoiceOwner == .chain { buildVoiceOwner = .none }
        buildSelID = buildGridSelPriorSel; ddColourSel = colourIDs.firstIndex(of: buildGridSelPriorSel ?? "") ?? -1
        au?.clearColourSolo(); buildSyncColours(); buildPublishScene()
    }
    // HOLD-TO-STAMP (Paul 2026-08-26): while a browse CELL auditions, HOLDING a part-row stamps the auditioning chain onto
    // that row — KEEPING the row's own colour — WITHOUT closing the browser (so you can stamp one machine onto several
    // parts). A populated row keeps its hue + register (chain overwritten); an empty row mints a colour carrying the chain.
    // Fires a white→fade FLASH on the row. Requires a browse cell to be the source (buildGridSelSel != nil).
    private var buildGridSelCanStamp: Bool { buildGridSelStampSource() != nil }
    // The active STAMP SOURCE — one of two (mutually exclusive, "one thing is active"): a browse CELL
    // (buildGridSelSel, SELECT library) or an active SIDE BUTTON's populated part row (buildGridSelStampSourceRow).
    // This is what a long-press copy stamps. (Paul 2026-08-28)
    private func buildGridSelStampSource() -> (chain: [ProcessorSlot], transpose: Int)? {
        // Resolve the three candidates from @State, then defer to the pure, unit-tested priority (roomsStampSource):
        // the live audition (gsAud) holds card EDITS — on SELECT BOTH a browse cell AND an aimed side button load + edit
        // it (buildSelID == gsAud), so it wins (register home baked → transpose 0). PART edits the REAL colour instead
        // (buildSelID != gsAud there → falls through to the browse cell / side row, which already reflects the edit).
        // (BUG 2026-08-29: the old code read buildGridSelChainAt/buildColourChain = the ORIGINAL, dropping edits.)
        roomsStampSource(
            auditionEdited: buildSelID == buildGridSelAudID ? buildColourReg[buildGridSelAudID] : nil,
            libraryCell: buildGridSelSel.flatMap { buildGridSelChainAt($0) }.map { ($0.chain, $0.transpose) },
            sideRow: buildGridSelStampSourceRow.flatMap { s in buildRowColour(s).map { (buildColourChain($0), buildColourTranspose[$0] ?? 0) } })
    }
    // Make the side button the ONE active source (clear the library-cell source) — "one thing is active". (Paul 2026-08-28)
    private func buildRoomsSetActiveSide(_ n: Int) { buildGridSelStampSourceRow = n; buildGridSelSel = nil }
    private func buildGridSelStampCommit(_ row: Int) {
        guard let hit = buildGridSelStampSource() else { return }
        buildRecordUndo()   // BUILD UNDO: capture the auditioning chain onto a part row
        // CAPTURE-INTO-MIRROR (Paul 2026-08-29): every long-press makes a FRESH cell in the row's PREDETERMINED colour
        // (colourHexes[row]) carrying whatever's CURRENTLY PLAYING (hit = the audition's chain + its register home), written
        // to the part ROW — so the ferry button and that part row are ONE cell thereafter (edits mirror). An INDEPENDENT
        // copy: not linked to the source. (Was: keep an existing row's colour + overwrite only the chain.)
        if row < buildRowUnder.count { buildRowUnder[row] = buildRowColour(row) }
        let y = buildNewTabColour(row, machine: hit.chain, transpose: hit.transpose)
        if !buildPartCast.contains(y) { buildPartCast.append(y) }
        buildSetRow(row, to: y)
        if row < buildRowReceiver.count { buildRowReceiver[row] = ddStickyReceiver; buildRowEmitters[row] = ddStickyBuses }
        buildStagingSyncIfPlaying()
        buildGridSelComputeRowRolls()                                    // the row's drifting face updates to the captured chain
        buildGridSelStampFlashRow = row; buildGridSelStampFlashAt = Date()   // the white→fade confirm
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.55) { if buildGridSelStampFlashRow == row { buildGridSelStampFlashRow = nil; buildGridSelStampFlashAt = nil } }
    }

    @ViewBuilder private func buildGridSelCell(_ i: Int, w: CGFloat, h: CGFloat, greyUnlessSel: Bool = false, vPad: CGFloat = 3) -> some View {
        let present = buildGridSelPresent(i)
        let hue = Color(hex: buildGridSelCellHex(i))
        let sel = buildGridSelSel == i
        // greyUnlessSel (SELECT grid, Paul 2026-08-29): an unselected present cell is a DARK-GREY button with a LIGHT-GREY
        // piano roll; only the SELECTED cell wears its chain's colour + white roll. Else (old grid selector) = coloured.
        let unselGrey = greyUnlessSel && !sel
        // SELECT grid (greyUnlessSel): the PLAYING (selected) cell is ONE colour — the INVERSE of the unselected dark-grey
        // view (a LIGHT-grey button with a DARK roll), NOT the chain's own hue (Paul 2026-08-30). Non-SELECT grids keep the hue.
        let selGrey = greyUnlessSel && sel
        let fill = present ? (sel ? (selGrey ? buildSelectGrey : hue.opacity(0.85)) : (unselGrey ? Color(white: 0.16) : hue.opacity(0.42))) : Color.white.opacity(0.03)   // selGrey ALTERNATES two bright shades per selection (matches the machine box; Paul 2026-09-01)
        let rollTint: Color = selGrey ? Color(white: 0.22) : (unselGrey ? Color(white: 0.78) : .white)
        // TASTEFUL CHEQUER (Paul 2026-08-31): the SELECT grid reads as a BOARD — a faint two-tone parity wash on every
        // non-selected cell (the classic chessboard), subtle enough not to fight the roll. SELECT grid only (greyUnlessSel);
        // the bright selected/focus cell stays clean.
        let chequer = greyUnlessSel && !sel && ((i / 8 + i % 8) % 2 == 0)
        ZStack {
            RoundedRectangle(cornerRadius: 6).fill(fill)
            if chequer { RoundedRectangle(cornerRadius: 6).fill(Color.white.opacity(0.05)) }   // the lighter square of the board
            if present {   // EVERY present cell wears its chain's notes drifting right→left (like the part/play grid) — the active one brighter, over its live roll
                // The drift ANIMATES only while the chain is actually PLAYING (Paul 2026-08-30 bug): gating on `sel` alone kept
                // the fingerprint looping after STOP on "play this midi chain" (MIDI stopped, animation didn't) — reads as still running.
                buildGridSelPianoRoll(sel ? buildGridSelActiveRoll : (buildGridSelCellRoll[i] ?? []), playing: sel && buildDisplayVoice == .chain && !buildChainLiveChord.isEmpty, tint: rollTint)   // precise one-frame roll; SCROLLS only while real MIDI is flowing (Paul 2026-08-31: a generator no longer looks like it's "playing" with nothing held)
                    .padding(.vertical, vPad).padding(.horizontal, 3).opacity(sel ? 1.0 : 0.7)   // SELECT grid pads the roll 15% top/bottom (Paul 2026-08-29)
            }
            if sel {       // THE ACTIVE CELL — a breathing live frame (DARK on the light-grey SELECT cell, else white)
                TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: animationsPaused)) { tl in
                    let f = stagingPulseFraction(tl.date, period: 0.9)
                    RoundedRectangle(cornerRadius: 6).stroke((selGrey ? Color.black : Color.white).opacity(0.45 + 0.5 * f), lineWidth: 3)
                }
            }
            if buildSelectMode && present { RoundedRectangle(cornerRadius: 6).stroke(Color.white, lineWidth: 2.5) }   // SELECT MODE: every cell lights white — tap to focus (Paul 2026-08-31)
        }
        .frame(width: w, height: h)
        .contentShape(Rectangle())
        .onTapGesture { buildGridSelTapCell(i) }   // SELECT mode focuses; else auditions
    }
    // THE SELECT-CELL PIANO ROLL (Paul 2026-08-31 — replaces the looping drift on the SELECT grid CELLS only; the ferries
    // keep buildGridSelDriftFace/buildNoteSweep). A PRECISE one-frame piano roll of the chain's real output (gridSelRollBars
    // = an offline render → each note's start · LENGTH (x0→x1 = bar width) · PITCH lane · VELOCITY (opacity)). STATIC at the
    // real note positions when idle; when the cell is auditioning it SCROLLS LEFT→RIGHT, beat-locked to the music (the same
    // extrapolated beat the cell playheads use). Same colour scheme (the caller's `tint`).
    @ViewBuilder private func buildGridSelPianoRoll(_ bars: [GridSelBar], playing: Bool, tint: Color) -> some View {
        GeometryReader { g in
            let loopBeats = max(0.0001, Double(Snap.cols) * stepBeats)   // one bar (8 steps) per full sweep — the playhead cadence
            TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: animationsPaused || !playing || bars.isEmpty)) { tl in
                let live = meters.beatAnchor + tl.date.timeIntervalSince(meters.beatAnchorAt) * meters.tempo / 60.0
                let raw = playing ? (live.truncatingRemainder(dividingBy: loopBeats)) / loopBeats : 0
                let phase = raw < 0 ? raw + 1 : raw                      // 0…1 with the beat; 0 (real positions) when idle
                Canvas { ctx, size in
                    let laneH = max(1.5, size.height * 0.11)
                    let inset = size.height * 0.16                       // PADDING above + below the notes (Paul 2026-08-31)
                    for b in bars {
                        let w = max(1.5, (b.x1 - b.x0) * size.width)     // LENGTH
                        let y = inset + b.y * (size.height - laneH - 2 * inset)   // PITCH (high = top), inset from the cell edges
                        let base = ((b.x0 - phase).truncatingRemainder(dividingBy: 1.0) + 1).truncatingRemainder(dividingBy: 1.0)   // RIGHT→LEFT scroll with the beat (Paul 2026-08-31)
                        for k in (playing ? [-1.0, 0.0, 1.0] : [0.0]) {  // draw the note + its wrap copies while scrolling, so the flow is seamless either way
                            let rect = CGRect(x: (base + k) * size.width, y: y, width: w, height: laneH)
                            ctx.fill(Path(roundedRect: rect, cornerRadius: laneH / 2), with: .color(tint.opacity(0.35 + 0.55 * b.vel)))   // VELOCITY = opacity
                        }
                    }
                }
            }
        }
    }
    // THE DRIFTING NOTE FACE (Paul 2026-08-26): notes scroll RIGHT→LEFT, looping — the same aesthetic as the part/play grid
    // cells (buildNoteSweep). Every present cell + row selector wears its chain's fingerprint drifting across it (a browse
    // preview: you can't run 64 live voices, so each cell loops its chain's note pattern). Opacity by velocity.
    @ViewBuilder private func buildGridSelDriftFace(_ bars: [GridSelBar], animated: Bool, period: Double = 2.4, tint: Color = .white) -> some View {
        TimelineView(.animation(minimumInterval: 1.0 / 24.0, paused: animationsPaused || !animated || bars.isEmpty)) { tl in
            Canvas { ctx, size in
                let barH = max(1.5, size.height * 0.09)
                let phase = tl.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: period) / period   // 0→1 loop
                for b in bars {
                    let w = max(1.5, (b.x1 - b.x0) * size.width)
                    let y = b.y * (size.height - barH) + barH / 2
                    let base = ((b.x0 - phase).truncatingRemainder(dividingBy: 1.0) + 1).truncatingRemainder(dividingBy: 1.0)   // frac(x0 - phase)
                    for k in [0.0, -1.0] {                                  // draw the note + its wrap-around copy so the flow is seamless at the right edge
                        let rect = CGRect(x: (base + k) * size.width, y: y - barH / 2, width: w, height: barH)
                        ctx.fill(Path(roundedRect: rect, cornerRadius: barH / 2), with: .color(tint.opacity(0.3 + 0.5 * b.vel)))
                    }
                }
            }
        }
    }
    // Compute the drifting-note fingerprint for every present cell of the CURRENT tab, off the main thread (64× gridSelRollBars
    // is too much to block on — the same reason DEAL is backgrounded). A generation token discards a batch if the deal/tab
    // changed under it. Chains are gathered on the main thread first (library resolves via `au`), then bars computed pure.
    private func buildGridSelComputeCellRolls() {
        buildGridSelRollGen &+= 1
        let gen = buildGridSelRollGen
        var chains: [(Int, [ProcessorSlot])] = []
        for i in 0..<64 where buildGridSelPresent(i) { if let hit = buildGridSelChainAt(i) { chains.append((i, hit.chain)) } }
        buildGridSelCellRoll = [:]
        DispatchQueue.global(qos: .userInitiated).async {
            var out: [Int: [GridSelBar]] = [:]
            for (i, chain) in chains { out[i] = gridSelRollBars(chain) }
            DispatchQueue.main.async { if self.buildGridSelRollGen == gen { self.buildGridSelCellRoll = out } }
        }
    }
    // The 8 row selectors get the same drifting face — each row chip loops its PART's chain fingerprint. Cheap (≤8), computed
    // on open; rows only change on COMMIT (which closes the selector), so no live recompute is needed.
    private func buildGridSelComputeRowRolls() {
        var chains: [(Int, [ProcessorSlot])] = []
        for n in 0..<8 { if let cid = buildRowColour(n) { chains.append((n, buildColourChain(cid))) } }
        buildGridSelRowRoll = [:]
        DispatchQueue.global(qos: .userInitiated).async {
            var out: [Int: [GridSelBar]] = [:]
            for (n, chain) in chains { out[n] = gridSelRollBars(chain) }
            DispatchQueue.main.async { self.buildGridSelRowRoll = out }
        }
    }
    private var buildGridSelStampDur: Double { 0.65 }
    private func buildGridSelStampPressing(_ n: Int, _ pressing: Bool) {
        if pressing {
            buildFerryHeld = false                                       // fresh gesture
            if buildGridSelCanStamp { buildGridSelStampRow = n; buildGridSelStampAt = Date() }
        } else if buildGridSelStampRow == n {                            // released before completion → cancel the rising fill
            // A DELIBERATE hold (fill was running > ~0.2s) released before the copy committed → suppress the follow-up TAP
            // so it doesn't steal focus / re-audition the playing cell. A quick tap (< 0.2s) still selects normally. (Paul 2026-08-29)
            if let at = buildGridSelStampAt, Date().timeIntervalSince(at) > 0.2 { buildFerryHeld = true }
            buildGridSelStampRow = nil; buildGridSelStampAt = nil
        }
    }
    private func buildGridSelStampFire(_ n: Int) {
        guard buildGridSelCanStamp else { return }
        buildGridSelStampRow = nil; buildGridSelStampAt = nil            // hand the rising fill over to the confirm flash
        buildGridSelStampCommit(n)
    }
    // The rising WHITE fill while a row is held (fraction = elapsed / stampDur), then a full-white → fade CONFIRM once stamped.
    @ViewBuilder private func buildGridSelStampSweep(_ n: Int, height: CGFloat, hue: Color = .white) -> some View {
        if buildGridSelStampRow == n, let start = buildGridSelStampAt {
            TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: animationsPaused)) { tl in
                let f = min(1.0, max(0.0, tl.date.timeIntervalSince(start) / buildGridSelStampDur))
                Rectangle().fill(Color.white.opacity(0.9)).frame(height: max(0, height * CGFloat(f)))   // rising WHITE progress while held
            }
        } else if buildGridSelStampFlashRow == n, let fs = buildGridSelStampFlashAt {
            // THE REVEAL (Paul 2026-09-01): on COMMIT the cell BLOOMS its real machine COLOUR — a saturated wash of `hue`
            // eases out over ~0.6s, settling to the now-populated cell. The disposable grey draft "becomes real" in its own
            // colour (colour = kept). Was a plain white flash — invisible as a colour payoff on these mostly-dark cells.
            TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: animationsPaused)) { tl in
                let raw = min(1.0, tl.date.timeIntervalSince(fs) / 0.6)
                let e = 1 - (1 - raw) * (1 - raw)                                   // ease-out
                Rectangle().fill(hue.opacity(0.9 * (1 - e)))                        // full colour → clear (the bloom)
            }
        }
    }
    private func buildGridSelAimRow(_ n: Int) {
        buildGridSelArrivalRow = n
        buildSelReceiver = buildRowReceiverResolved(n)                    // the audition plays through the AIMED part's door + emitters (so the MIDI-IN/OUT chips reflect it)
        buildPartEmitters = buildRowEmittersResolved(n)
        receivers = au?.uiReceivers() ?? receivers
        // LOAD the pressed part's own chain into the MIDI CHAIN panel + audition it (Paul 2026-08-26). sel = nil → it's a
        // view/hear of what's on the row, not a commit source (re-deal or tap a cell to change it). Empty row → clear.
        if let cid = buildRowColour(n) {
            buildFerryMirrorRow = n                                       // a POPULATED ferry aim MIRRORS this row: card edits on gsAud write straight back to it (Paul 2026-08-30)
            buildGridSelLoadChain(buildColourChain(cid), transpose: buildColourTranspose[cid] ?? 0, hex: buildBaseHex(cid), sel: nil)
        } else {
            buildFerryMirrorRow = nil                                     // empty row → no mirror target
            buildGridSelStopAudition()                                    // empty part → nothing to load; silence the transient
        }
    }
    // The selected chain as compact read-only processor boxes (the transient gsAud machine, minus the register-home transpose).
}

// One note of a GRID SELECTOR chain's piano-roll fingerprint — normalized 0…1 (x = time, y = pitch, w = gate).
struct GridSelBar: Equatable { let x0: Double; let x1: Double; let y: Double; let vel: Double }

// The piano-roll fingerprint of a chain: an OFFLINE render (Dice.runRecorder vs a standard chord) → its emitter-A notes
// as normalized bars. Pure + Foundation-only, so it runs off the main thread during a deal. Empty for a silent chain.
func gridSelRollBars(_ chain: [ProcessorSlot]) -> [GridSelBar] {
    let rec = Dice.runRecorder(chain)
    let ons = rec.ons.filter { $0.cable == 1 }
    guard !ons.isEmpty else { return [] }
    let notes = ons.map { Int($0.note) }
    let lo = notes.min()!, hi = notes.max()!, span = max(1, hi - lo)
    let maxS = Double(max(Int64(1), max(ons.map { $0.sample }.max() ?? 1, rec.offs.map { $0.sample }.max() ?? 1)))
    var bars: [GridSelBar] = []
    for on in ons {
        let off = rec.offs.filter { $0.cable == 1 && $0.note == on.note && $0.sample >= on.sample }.map { $0.sample }.min()
        let x0 = Double(on.sample) / maxS
        let x1 = off.map { Double($0) / maxS } ?? min(1.0, x0 + 0.05)
        bars.append(GridSelBar(x0: x0, x1: max(x0 + 0.02, min(1.0, x1)), y: 1.0 - Double(Int(on.note) - lo) / Double(span), vel: Double(on.vel) / 127.0))
    }
    return bars
}

// A share sheet for the REEL-TO-REEL export (SMF files). (Paul 2026-08-18)
struct ReelShareSheet: UIViewControllerRepresentable {
    let urls: [URL]
    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: urls, applicationActivities: nil)
    }
    func updateUIViewController(_ vc: UIActivityViewController, context: Context) {}
}
