import SwiftUI
import UIKit   // ReelShareSheet (UIActivityViewController) — REEL-TO-REEL export
import UniformTypeIdentifiers   // FILE import: the .mid content type for the door sheet's file picker

// The ONE workshop voice: which SHOP section sounds — the MIDI CHAIN audition, the PART grid, or NEITHER. Each header
// toggles its own section (play ⇄ stop) so both can be off; picking one stops the other (they never sound together).
enum BuildWorkshopVoice { case none, chain, part }

// FERRY DRAG-AND-DROP (Paul 2026-09-12, supersedes the long-press copy/seed). A drag carries a SELECT grid cell or a play
// ferry; it drops onto a ferry (populate / move-overwrite) or the machine-box trash (delete a ferry). Drop-zone frames are
// collected in the shared "rooms" coordinate space via FerryZoneKey (reported by each ferry + the trash). The FerryDragSource
// / FerryDropZone enums + the pure hit-test/reallocation cores live in BuildSceneLogic.swift (so they reach the test target).
struct FerryZoneKey: PreferenceKey {
    static let defaultValue: [FerryDropZone: CGRect] = [:]
    static func reduce(value: inout [FerryDropZone: CGRect], nextValue: () -> [FerryDropZone: CGRect]) {
        value.merge(nextValue()) { _, b in b }
    }
}

// After MUTATE/RANDOM on the part-grid row creator, the generated row offers KEEP | TRY AGAIN (Paul 2026-09-11).
// `random` remembers which mode to re-run on TRY AGAIN. Cleared on KEEP or when focus leaves the row.
struct RowGenConfirm: Equatable { let row: Int; let random: Bool }

// Run heavy offline Dice→Router evaluation on a dedicated LARGE-STACK thread (Paul 2026-09-11, crash fix). The grid-
// selector DEAL / corpus / library-warm / face computation each drive `Dice.runRecorder` → the full `Router.process` →
// `openVoice` chain — a very deep call stack with a huge per-frame footprint. A GCD global-queue worker has only a
// ~512 KB stack, which this chain overflows at launch (SIGBUS at the stack guard, `___chkstk_darwin`). A Thread lets
// us set an ample stack. The closure marshals its own results back to the main queue (unchanged).
func runOnLargeStack(qos: QualityOfService = .userInitiated, _ body: @escaping () -> Void) {
    let t = Thread { body() }
    t.stackSize = 16 * 1024 * 1024   // 16 MB — ample for the offline-eval recursion (GCD workers give ~512 KB)
    t.qualityOfService = qos
    t.start()
}

// THE BUILD PAGE — design: Docs/AcceptanceCriteria/AcceptanceCriteria-build-page-two-grid-flow.md +
// -build-page-iteration-3.md + -build-page-iteration-4.md + Docs/mockup-build-three-grids-landscape.html
// (user 2026-08-11). The new PRIMARY workshop and default landing tab. Destined to REPLACE the DRAG&DROP + PROCESSORS
// (cell-edit) pages (both kept live until it supersedes them).
//
// THE FORM (user 2026-08-11: THREE EQUAL COLUMNS + the machinery strip along the bottom; NO focus highlight):
//   • LEFT COLUMN (the build flow, top→bottom): [● PLAY THIS CELL] → [PART ▾][+ NEW] → 1·INPUT (R1–R4, MIDI ⎓ | PIANO
//     ⌨ per door; a PIANO door reveals its octave keyboard) → 2·THE CAST (the FULL 4×4 palette, 16 slots) · 🎲
//     RANDOMIZE (the chain's die = roll the machine's machine) → 3·OUTPUT (A–D) → [APPLY TO STAGING →] → LITTER.
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

// Placeholder cast hues (mockup palette). Real machines come from the part's cast when the palette is wired.
private let buildPanel = Color(red: 0.08, green: 0.09, blue: 0.11)
private let buildCell  = Color(red: 0.10, green: 0.12, blue: 0.15)
// PART AUTOMATION (Paul 2026-09-01): each chain (machine) gets FIVE Auto lanes — a DIRECT param automation (macros dropped
// to v2). A lane picks a processor param, sets its BEFORE→AFTER, a SPAN that shapes the curve/repeat WITHIN the painted
// extent (disabled for binary params), and an EXTENT of grid cells (painted via APPLY). Baked per-cell at build (rides the
// M2 substrate). Per-machine (shared across the machine's cells). `AutoLane`/`PartAutoMachine` live in BuildModel.swift
// (Foundation-only, in the test target + Codable so the automation travels with the document).
private let buildDim   = Color(white: 0.36)
private let buildPink  = Color(red: 0.94, green: 0.41, blue: 0.85)
private let buildCyan  = Color(red: 0.19, green: 0.83, blue: 0.91)
private let buildRed   = Color(red: 0.91, green: 0.36, blue: 0.44)   // ROW 8 CLEAR + destructive verbs
private let buildEdge  = Color(white: 1).opacity(0.17)   // §0 MUTED-CHROME: a neutral whisper for default (non-armed) chrome borders — replaces standing cyan strokes
// THE ROOM SIGNATURES (Paul 2026-08-29, §8b WAYFINDING): each room owns a machine and every DOOR wears its DESTINATION's
// signature — RAINBOW = SELECT (a multimachine strip, refuses one hue) · AMBER = PART · INDIGO = PLAY (retires cyan) ·
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
    var machineReg: [String: [ProcessorSlot]]; var machineTranspose: [String: Int]; var hueOverride: [String: UInt32]
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
// whole row's rung · PLACE the selected machine · MUTATE a value-tweaked variant of it.
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
        if let d = buildScalePopupDoor { AnyView(buildReceiverScalePopup(door: d, size: size)) }             // FOUR SCALE POOLS (strip SCALE button)
        if let d = buildChordPopupDoor { AnyView(buildReceiverChordPopup(door: d, size: size)) }             // THE CHORD DOOR (strip CHORD button)
    }
    @ViewBuilder func roomsChrome<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        content()
            .overlay(alignment: .top) { buildIOHoldBanner() }                                               // "HOLD TO APPLY TO ALL"
            .fileImporter(isPresented: Binding(get: { buildFileImportDoor != nil }, set: { if !$0 { buildFileImportDoor = nil } }),
                          allowedContentTypes: [UTType.midi, UTType(filenameExtension: "mid") ?? .data], allowsMultipleSelection: false) { result in
                buildHandleFileImport(result)                                                                // FILE import onto the picking door
            }
            .onChange(of: activeSceneIdx) { _ in buildSyncSceneSwitch(activeSceneIdx) }                       // scene chips → swap the play-grid arrangement
            .onChange(of: d.playing) { playing in buildTransportEdge(playing) }                               // HOST TRANSPORT: STOP halts (keeps cells armed) · START resumes in sync (Paul 2026-09-02)
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
        case .chord:  return "The pool is a diatonic chord — from a scale door, pick a degree."
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
                let tabLabel = (i < recvs.count ? recvs[i].scaleLabel : nil) ?? buildChordDoorLabel(recvs, i) ?? ["A", "B", "C", "D"][i]   // SCALE ("A MIXO") / CHORD ("A · V7") doors name themselves; else the letter
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
            VStack(alignment: .leading, spacing: 8) {              // the mode list — FULL width, selected mode carries its controls inline (the overlaid main-page strip was removed, Paul 2026-09-10)
                ForEach(DoorMode.allCases.filter { $0 != .thru }, id: \.self) { m in buildDoorModeOption(i, m, r: r) }   // THRU retired (Paul 2026-08-31)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
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
        case .latch, .hold, .keys, .scale, .chord:
            // AUTO-ENGAGE (Paul 2026-08-27): selecting an armable mode ARMS it on the receiver at once — no separate SET tap.
            // (SCALE/CHORD also self-arm via their derived pool, but arm the manual latch too so the strip reads engaged.)
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
                    case .chord:  buildDoorChordInline(i, r)
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
    // FOUR SCALE POOLS (Paul 2026-09-04): the door sheet's scale row is now a LAUNCHER — a summary of the ACTIVE pool + a
    // button that opens the same 4-pool pop-up the strip SCALE button opens (config lives in ONE place). The pop-up is where
    // you configure + switch; the strip is the fast performance switch.
    @ViewBuilder private func buildDoorScaleInline(_ i: Int, _ r: Receiver) -> some View {
        let w: CGFloat = 520
        let names = ["C", "C#", "D", "D#", "E", "F", "F#", "G", "G#", "A", "A#", "B"]
        let pool = scaleNotes(root: r.scaleRootResolved, type: r.scaleTypeResolved, baseOct: r.scaleBaseOctResolved, octaves: r.scaleOctavesResolved)
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                Text("ACTIVE").font(.system(size: 10, weight: .heavy, design: .monospaced)).foregroundColor(buildDim).frame(width: 44, alignment: .leading)
                Text("\(r.activeScaleResolved + 1) · \(names[r.scaleRootResolved]) \(r.scaleTypeResolved.label) · \(pool.count) notes")
                    .font(.system(size: 12, weight: .heavy, design: .monospaced)).foregroundColor(buildCyan).lineLimit(1).minimumScaleFactor(0.7)
                Spacer(minLength: 0)
            }
            Text("EDIT 4 SCALE POOLS ▸").font(.system(size: 11, weight: .heavy, design: .monospaced)).foregroundColor(.black)
                .frame(maxWidth: .infinity).frame(height: 34).background(RoundedRectangle(cornerRadius: 6).fill(buildCyan))
                .contentShape(Rectangle()).onTapGesture { buildScalePopupDoor = i }
        }.frame(width: w, alignment: .leading)
    }
    // The FOUR-POOL editor — the slot RADIO (tap = switch active, live) over the ROOT/SCALE/RANGE editor for the active pool
    // (the four legacy setters target the active slot). Shared by the pop-up (strip SCALE button + door-sheet launcher).
    @ViewBuilder private func buildScalePoolEditor(_ i: Int, _ r: Receiver) -> some View {
        let w: CGFloat = 520
        let names = ["C", "C#", "D", "D#", "E", "F", "F#", "G", "G#", "A", "A#", "B"]
        let root = r.scaleRootResolved, type = r.scaleTypeResolved
        let pools = r.scalePoolsResolved, active = r.activeScaleResolved
        let pool = scaleNotes(root: root, type: type, baseOct: r.scaleBaseOctResolved, octaves: r.scaleOctavesResolved)
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 6) {                                       // the 4 slot toggles — RADIO (one active), each names its scale
                ForEach(0..<4, id: \.self) { k in
                    let p = pools[k], on = active == k
                    VStack(spacing: 1) {
                        Text("\(k + 1)").font(.system(size: 12, weight: .heavy, design: .monospaced))
                        Text("\(names[((p.root % 12) + 12) % 12]) \(p.type.label)").font(.system(size: 8, weight: .heavy, design: .monospaced)).lineLimit(1).minimumScaleFactor(0.55)
                    }
                    .foregroundColor(on ? .black : .white.opacity(0.75))
                    .frame(maxWidth: .infinity).frame(height: 38)
                    .background(RoundedRectangle(cornerRadius: 6).fill(on ? buildCyan : Color.white.opacity(0.08)))
                    .overlay(RoundedRectangle(cornerRadius: 6).stroke(on ? Color.clear : buildCyan.opacity(0.35), lineWidth: 1.5))
                    .contentShape(Rectangle()).onTapGesture { buildRecvEdit { au?.setReceiverActiveScale(i, k) } }
                }
            }.frame(width: w)
            Text("CONFIGURE SCALE \(active + 1)").font(.system(size: 10, weight: .heavy, design: .monospaced)).foregroundColor(buildDim)
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
            }.frame(width: w, alignment: .leading)                     // close the inner CONFIGURE body
        }.frame(width: w, alignment: .leading)                         // close the outer editor VStack
    }
    // THE 4-POOL POP-UP (Paul 2026-09-04): opened by the strip SCALE button + the door-sheet launcher. Top-aligned card (like
    // the MIDI INPUTS sheet) wrapping the shared editor. Switching a slot is LIVE (buildRecvEdit republishes). A future CHORD
    // door will reuse this same pop-up shell with a chord editor swapped in ("later show as chord selected — to be defined").
    @ViewBuilder private func buildReceiverScalePopup(door i: Int, size: CGSize) -> some View {
        let recvs = au?.uiReceivers() ?? []
        let r = i < recvs.count ? recvs[i] : Receiver()
        let hue = i < receiverHues.count ? receiverHues[i] : buildCyan
        ZStack(alignment: .top) {
            Color.black.opacity(0.65).ignoresSafeArea().contentShape(Rectangle()).onTapGesture { buildScalePopupDoor = nil }
            VStack(spacing: 0) {
                HStack {
                    Text("SCALE POOLS · \(["A", "B", "C", "D"][min(3, max(0, i))])").font(.system(size: 17, weight: .heavy, design: .monospaced)).tracking(2).foregroundColor(hue)
                    Spacer()
                    Button { buildScalePopupDoor = nil } label: {
                        Image(systemName: "xmark").font(.system(size: 17, weight: .bold)).foregroundColor(buildDim).padding(10)
                    }
                }.padding(.horizontal, 26).padding(.top, 20).padding(.bottom, 12)
                ScrollView(.vertical, showsIndicators: false) {
                    buildScalePoolEditor(i, r).padding(.horizontal, 26).padding(.bottom, 30)
                }
            }
            .frame(width: min(600, size.width - 32), height: min(560, size.height - 96))
            .background(RoundedRectangle(cornerRadius: 18).fill(Color(red: 0.07, green: 0.08, blue: 0.10)))
            .overlay(RoundedRectangle(cornerRadius: 18).stroke(Color.white.opacity(0.12), lineWidth: 1))
            .padding(.top, 20)
        }
    }
    // ═══ THE CHORD DOOR = a chord SEQUENCER (Paul 2026-09-04) — the door reuses the CHORDS PROCESSOR wholesale: each of four
    // instances IS a MachineParams, and the pop-up mounts the processor's own ProcessorBox editor, so the controls are LITERALLY
    // identical and future CHORDS work reflects on the door for free. ═══
    /// The strip/tab label for a CHORD door ("A · CHRD"), else nil. Parallels `Receiver.scaleLabel`. (The live chord changes on
    /// the beat, so the strip names the door, not a frozen chord.)
    func buildChordDoorLabel(_ recvs: [Receiver], _ i: Int) -> String? {
        guard i >= 0, i < recvs.count, recvs[i].doorModeResolved == .chord else { return nil }
        return "\(["A", "B", "C", "D"][min(3, max(0, i))]) · CHRD"
    }
    // The door sheet's CHORD row = a LAUNCHER into the same pop-up the strip CHORD button opens.
    @ViewBuilder private func buildDoorChordInline(_ i: Int, _ r: Receiver) -> some View {
        let w: CGFloat = 520
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                Text("ACTIVE").font(.system(size: 10, weight: .heavy, design: .monospaced)).foregroundColor(buildDim).frame(width: 44, alignment: .leading)
                Text("SEQ \(r.activeChordResolved + 1) — the chord sequencer walks the progression on the beat")
                    .font(.system(size: 12, weight: .heavy, design: .monospaced)).foregroundColor(buildCyan).lineLimit(1).minimumScaleFactor(0.55)
                Spacer(minLength: 0)
            }
            Text("EDIT CHORD SEQUENCER ▸").font(.system(size: 11, weight: .heavy, design: .monospaced)).foregroundColor(.black)
                .frame(maxWidth: .infinity).frame(height: 34).background(RoundedRectangle(cornerRadius: 6).fill(buildCyan))
                .contentShape(Rectangle()).onTapGesture { buildChordPopupDoor = i }
        }.frame(width: w, alignment: .leading)
    }
    // The FOUR-SEQUENCE editor — the slot RADIO (tap = switch active, live) over the CHORDS PROCESSOR's OWN ProcessorBox editor
    // bound to the active instance's MachineParams. Identical controls to the grid processor; future changes reflect here.
    @ViewBuilder private func buildChordSeqEditor(_ i: Int, _ r: Receiver) -> some View {
        let w: CGFloat = 560
        let seqs = r.chordSeqsResolved, active = r.activeChordResolved
        let hue = i < receiverHues.count ? receiverHues[i] : buildCyan
        let synth: Machine = { var c = Machine(machineID: "chordDoor\(i)", type: .chords); c.paramsA = seqs[active]; return c }()
        return VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 6) {                                       // the 4 sequence slots — RADIO (one active)
                ForEach(0..<4, id: \.self) { k in
                    let on = active == k
                    Text("SEQ \(k + 1)").font(.system(size: 12, weight: .heavy, design: .monospaced))
                        .foregroundColor(on ? .black : .white.opacity(0.75))
                        .frame(maxWidth: .infinity).frame(height: 34)
                        .background(RoundedRectangle(cornerRadius: 6).fill(on ? buildCyan : Color.white.opacity(0.08)))
                        .overlay(RoundedRectangle(cornerRadius: 6).stroke(on ? Color.clear : buildCyan.opacity(0.35), lineWidth: 1.5))
                        .contentShape(Rectangle()).onTapGesture { buildRecvEdit { au?.setReceiverActiveChord(i, k) } }
                }
            }.frame(width: w)
            Text("SEQUENCE \(active + 1) — the same chord sequencer as the processor").font(.system(size: 10, weight: .heavy, design: .monospaced)).foregroundColor(buildDim)
            ProcessorBox(
                machine: synth, machineIndex: -1, face: .a,
                onEdit: { mutate in
                    buildRecvEdit {
                        var tmp = synth; mutate(&tmp); au?.setReceiverChordSeq(i, active, tmp.paramsA)
                    }
                },
                onTranspose: { _ in }, onMorph: { _ in },
                slotMode: true, accentOverride: hue, plainTitle: true, showSlotChrome: false)
                .frame(width: w)
        }.frame(width: w, alignment: .leading)
    }
    // THE CHORD-SEQUENCER POP-UP — twin of the scale pop-up (strip CHORD button + door-sheet launcher).
    @ViewBuilder private func buildReceiverChordPopup(door i: Int, size: CGSize) -> some View {
        let recvs = au?.uiReceivers() ?? []
        let r = i < recvs.count ? recvs[i] : Receiver()
        let hue = i < receiverHues.count ? receiverHues[i] : buildCyan
        ZStack(alignment: .top) {
            Color.black.opacity(0.65).ignoresSafeArea().contentShape(Rectangle()).onTapGesture { buildChordPopupDoor = nil }
            VStack(spacing: 0) {
                HStack {
                    Text("CHORD SEQUENCER · \(["A", "B", "C", "D"][min(3, max(0, i))])").font(.system(size: 17, weight: .heavy, design: .monospaced)).tracking(2).foregroundColor(hue)
                    Spacer()
                    Button { buildChordPopupDoor = nil } label: {
                        Image(systemName: "xmark").font(.system(size: 17, weight: .bold)).foregroundColor(buildDim).padding(10)
                    }
                }.padding(.horizontal, 26).padding(.top, 20).padding(.bottom, 12)
                ScrollView(.vertical, showsIndicators: false) {
                    buildChordSeqEditor(i, r).padding(.horizontal, 26).padding(.bottom, 30)
                }
            }
            .frame(width: min(640, size.width - 32), height: min(620, size.height - 80))
            .background(RoundedRectangle(cornerRadius: 18).fill(Color(red: 0.07, green: 0.08, blue: 0.10)))
            .overlay(RoundedRectangle(cornerRadius: 18).stroke(Color.white.opacity(0.12), lineWidth: 1))
            .padding(.top, 20)
        }
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
                #if DEBUG
                buildResetButton()            // DEV-ONLY (Paul 2026-09-11): wipe to the fresh INIT document
                #endif
                // The SELECT|PART grid toggle is RETIRED (Paul 2026-09-08): the ferry row IS the navigation — tap a populated
                // ferry to open its part, an empty ferry to reach the SELECT browser. CLEARing a part empties its ferry.
                // RATE + STEPS (8|16) moved to the FERRY SETTINGS card; MIDI IN / MIDI OUT buttons deleted (Paul 2026-09-10).
                buildConfigButton("RACK")     { buildRackConfigOpen = true }    // the rack / OUTPUT CHAIN sheet (config-sheets §6)
            }
            buildReelButton()                                   // RECORD — top-right (Paul 2026-08-23); handles the pass-browser hide + share anchor
        }
    }
    #if DEBUG
    // DEV-ONLY RESET (Paul 2026-09-11): FULLY RELOADS the app to its "just added" state. Posting .midiSparkReloadUI lets the
    // VIEW CONTROLLER (which survives the rebuild) reset the document to INIT AND tear down + recreate the SwiftUI hosting
    // controller, so every BUILD @State (ferries, staging, ephemeral colours, play columns) is discarded and rebuilt fresh.
    // (Calling loadFactoryPreset from here only reset the document — the GUI @State persisted, so the button seemed dead.)
    // Red-tinted to mark it destructive; never ships on the product face.
    @ViewBuilder private func buildResetButton() -> some View {
        let red = Color(red: 0.95, green: 0.24, blue: 0.24)
        Text("RESET").font(.system(size: 11, weight: .heavy, design: .monospaced)).tracking(0.5)
            .foregroundColor(red).lineLimit(1).minimumScaleFactor(0.8)
            .frame(width: 84, height: 30)
            .background(RoundedRectangle(cornerRadius: 6).fill(buildPanel))
            .overlay(RoundedRectangle(cornerRadius: 6).stroke(red.opacity(0.5), lineWidth: 1))
            .contentShape(Rectangle()).onTapGesture { NotificationCenter.default.post(name: .midiSparkReloadUI, object: nil) }
    }
    #endif
    // THE PLAY STRIP (Paul 2026-09-09) — the transport, in the HEADER right of the preset button (replaces the grid's
    // corner STOP/PLAY buttons). A play/stop toggle + a playhead that sweeps L→R across the strip in beat-time while
    // playing (host transport only, like the ferry sweep). Tap toggles the play grid.
    @ViewBuilder func buildPlayStrip() -> some View {
        let playing = buildPlayPlaying
        HStack(spacing: 7) {
            Image(systemName: playing ? "stop.fill" : "play.fill").font(.system(size: 12, weight: .black))
                .foregroundColor(playing ? roomsIndigo : .white.opacity(0.85))
            GeometryReader { g in
                let barBeats = Double(Snap.cols) * max(0.0001, stepBeats)
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 3).fill(Color.white.opacity(0.10))                       // the track
                    if playing && d.playing {
                        TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: animationsPaused)) { tl in
                            let live = meters.beatAnchor + tl.date.timeIntervalSince(meters.beatAnchorAt) * meters.tempo / 60.0
                            let ph = (live.truncatingRemainder(dividingBy: barBeats)) / barBeats
                            let p = CGFloat(ph < 0 ? ph + 1 : ph)
                            ZStack(alignment: .leading) {
                                RoundedRectangle(cornerRadius: 3).fill(roomsIndigo.opacity(0.45)).frame(width: max(0, p * g.size.width))   // progress fill
                                Rectangle().fill(Color.white.opacity(0.9)).frame(width: 2).offset(x: p * g.size.width - 1)                  // the sweeping head
                            }
                        }
                    }
                }
            }.frame(width: 96, height: 12)
        }
        .padding(.horizontal, 9).frame(height: 26)
        .background(RoundedRectangle(cornerRadius: 5).fill(Color.white.opacity(0.08)))
        .contentShape(Rectangle()).onTapGesture { buildTogglePlayGrid() }
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

    // (The per-part RATE pill was removed from the header 2026-09-08 — the header clock chip carries the step rate; the
    // per-part-rate model + setter stay.)
    func buildSetPartRate(_ r: StepRate?) {
        buildPartRate = r
        if buildCurrentPart >= 0, buildCurrentPart < buildParts.count { buildParts[buildCurrentPart].rate = r }   // keep buildParts authoritative for performRate mapping
        buildPublishScene()
    }
    func buildSetPartLen(_ n: Int?) {
        let old = buildPartCols
        buildPartLen = n
        let new = buildPartCols
        // EXTENDING (e.g. 8 → 16, Paul 2026-09-08/09): TILE the existing pattern into the newly-revealed columns so the
        // whole loop sounds — a bare widen left them empty, so the playhead swept the second half in silence. FORCE-tile
        // every revealed column from its modulo source (was: only fill empty columns — but a part that was ever 16-wide
        // could keep a STALE, top-row-empty second half → the "rightmost 8 cells on the top row missing" bug, Paul 2026-09-09).
        // Extend only ever reveals columns that were HIDDEN at the narrower width, so re-tiling them to the current pattern
        // is exactly what "extend = tile" means.
        if new > old, old > 0 {
            for c in old..<new where c < buildStagingCells.count {
                let src = c % old
                if src < buildStagingCells.count { buildStagingCells[c] = buildStagingCells[src] }
                if c < buildStagingSel.count, src < buildStagingSel.count { buildStagingSel[c] = buildStagingSel[src] }
            }
        }
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
                // NOTES — each painted the MACHINE of the cell that played it (upcoming + already-played alike);
                // falls back to the lane hue when the pass predates the machine tag. (Paul 2026-08-19)
                for note in notes {
                    let nc = note.machine != 0 ? Color(hex: note.machine) : hue
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

    // The selected machine's real hue (the cast selection drives the machine ID + grid tints). Falls back to cyan.
    // THE ONE machine hue, DERIVED FROM POSITION (Paul 2026-09-06). A bench focus (a ferry / part row) has no intrinsic
    // "true machine" — its machine IS its row position (design-cell-language decision 4, partRowHexes), derived at render,
    // NEVER a stored per-machine hue (the old machineHueOverride used a DIFFERENT palette, machineHexes, and diverged →
    // "orange cell, red machine"). Every MIDI-chain-machine surface (box · chain boxes · cards · AUTO band · meter · part
    // roll) funnels through here, so touching a cell always shows its true machine. Play cell → its dusk (positional by
    // column, still via machineHue); a plain SELECT browse audition → the callers grey it.
    fileprivate var buildSelHue: Color {
        if let n = buildGridSelStampSourceRow { return Color(hex: partFerryHue(n)) }   // BENCH: the focused part row = its ACTIVE-FERRY shade (P2b palette) — so the machine box/chain/card MATCH the row's cell (was partPosHue → mismatch after the palette move, Paul 2026-09-09)
        return machineHue(ddSelectedMachineID ?? "") ?? buildCyan       // play dusk / browse (greyed by callers) / fallback
    }
    // THE MACHINE DISPLAY HUE (Paul 2026-08-30): the ONE hue for the machine BOX + MIDI CHAIN + PLAY button, so the three
    // stay consistent. Machine is a thing on the PART/PLAY grids + ferries only — it has LEFT the SELECT grid (its cells show
    // the inverse light grey). So a PLAIN select-grid audition (the transient gsAud, which carries no machine) shows the
    // machine that SAME light grey. But once a REAL machine is the selection — a ferry has just been copied and becomes
    // selected, or PART's own machine — the box + chain + play button all wear THAT machine (not grey/white). PART always
    // wears its machine's machine. (The machine box only appears on SELECT + PART.)
    // The part's DEFAULT output emitters — its chosen set, or emitter A when none. A row/cell/ferry inherits this when
    // it has no emitters of its own. (refactor 2026-08-30: was `buildPartEmitters.isEmpty ? [.a] : buildPartEmitters`
    // inlined at ~10 sites.)
    var buildDefaultEmitters: Set<Bus> { buildIONullPending ? [] : (buildPartEmitters.isEmpty ? [.a] : buildPartEmitters) }   // Paul 2026-09-05: null-pending ⇒ NO emitter (busMask 0 → the fresh cell is SILENT until wired)
    // Two BRIGHT shades that alternate each new SELECT pick (buildSelectGreyAlt flips on selection) so the machine section
    // visibly shifts even though the audition machine is always the same transient "gsAud" (Paul 2026-09-01).
    var buildSelectGrey: Color { Color(white: buildSelectGreyAlt ? 0.90 : 0.80) }
    // THE MACHINE BINDING (Paul 2026-09-01, state-unification): the ONE truth for what the machine represents + its play
    // state, gathered from the four @State axes into the pure BuildSceneLogic resolver. The machine hue, the play button,
    // (and in a follow-up, every represented-cell indicator) all DERIVE from this so they can't diverge.
    // THE TWO SELECT-SOURCE PROJECTIONS (Paul 2026-09-06): buildGridSelSel (a browse cell) and buildGridSelStampSourceRow (a
    // ferry row) are now COMPUTED views over the ONE model value `buildSelectSource`, so they can never both be set (the old
    // desync that let a ferry render grey). Every existing read/write site keeps working; a nil-write clears only ITS OWN case
    // (so the paired `stampSourceRow = n; sel = nil` / `sel = i; stampSourceRow = nil` idioms compose correctly).
    var buildGridSelSel: Int? {
        get { buildSelectSource.browseCell }
        nonmutating set { if let v = newValue { buildSelectSource = .browseCell(v) } else if buildSelectSource.browseCell != nil { buildSelectSource = .none } }
    }
    var buildGridSelStampSourceRow: Int? {
        get { buildSelectSource.ferryRow }
        nonmutating set { if let v = newValue { buildSelectSource = .ferryRow(v) } else if buildSelectSource.isFerry { buildSelectSource = .none } }
    }
    func buildMachineBinding(_ room: Room) -> BuildSceneLogic.MachineBinding {
        BuildSceneLogic.machineBinding(selID: buildSelID, audID: buildGridSelAudID, onSelectPage: room == .select,
                                       chainActive: buildDisplayVoice == .chain, partActive: buildDisplayVoice == .part,
                                       selectedPlayCol: room == .select ? buildSelectedPlayCol : nil, playColOn: buildPlayColOn,
                                       source: buildSelectSource)   // grey ⇔ .browseCell; a .ferryRow keeps its machine (Paul 2026-09-06)
    }
    func buildMachineHue(_ room: Room) -> Color {
        // SELECT (Paul 2026-09-12): everything (machine box · chain · processor boxes · card · play button) wears the
        // SELECTED selector's PRE-ALLOCATED colour — clicking between selectors changes it live; never the old grey audition.
        if room == .select { return Color(hex: buildFerryHex(buildActiveFerry ?? 0)) }
        return buildSelHue   // PART/PLAY: the focused machine (positional for a bench focus, dusk for a play cell)
    }
    // THE ONE HUE for every machine/card/editor surface (Paul 2026-08-31: the processor card was a DIFFERENT machine to the
    // machine box — a throwback to the multi-machine select grid, because the card read raw buildSelHue while the box read
    // the room-aware buildMachineHue). Both now resolve through this single accessor, so the card can never diverge again.
    var buildCardHue: Color { buildMachineHue(roomsRoom) }


    // ── PORTRAIT: height is abundant → a plain stack (palette → staging → play → machinery) ────────────────────────
    // (buildPortrait retired 2026-08-24 — LANDSCAPE-ONLY; git history keeps the vertical-stack layout if ever needed.)


    // The verb button stack, right of the MIDI chain. LEFT chevrons (<<<) act on the SELECTED machine's midi chain;
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
    // file. Functionality (which machine/row it edits) may be un-wired in the new shell — that's wired in later. (Paul 2026-08-28)
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
        // same light grey while a cell runs there — instead of the chain's machine (Paul 2026-08-30).
        let boxHue: Color = buildMachineHue(room)   // grey on SELECT (machine left it), the machine machine on PART — Paul 2026-08-30
        VStack(spacing: gap) {
            AnyView(buildReceiverSelector(castW: castW))                       // the 4 MIDI IN toggles — CONTENT-sized (was .frame(height: m.ch), whose extra space read as padding above the chain; the emitter toggles below are content-sized, now symmetric — Paul 2026-08-30)
            VStack(spacing: 8) {                                            // THE INTERIOR COLUMN — from the grid's interiorTop to its bottom
                Spacer(minLength: 8)                                         // centre the chain row VERTICALLY
                if room == .part, let sr = buildGridSelStampSourceRow, buildRowMachine(sr) == nil {
                    // EMPTY part row selected (Paul 2026-09-10): the row-creator MENU is gone (creation is now the 4 in-row
                    // buttons). The machine box instead shows a FADED, EMPTY, UNSELECTABLE chain — same layout + footprint as
                    // a real chain (blockH, no scale change), just dimmed + inert so it clearly reads "nothing here yet".
                    AnyView(HStack(alignment: .center, spacing: 0) {           // TRASH flank LEFT · chain centred · LIBRARY/MUTATE/CLEAR RIGHT — matches the populated layout (Paul 2026-09-10)
                        AnyView(roomsChainTrash(width: sideW, height: blockH))
                        AnyView(buildProcessorBlock(castW: castW, cell: cell, hue: boxHue, chainOverride: [])).frame(width: blockW)
                        AnyView(buildChainButtonStack(width: sideW, height: blockH, showGrid: false))
                    }
                    .opacity(0.35)
                    .allowsHitTesting(false))
                } else {
                    AnyView(HStack(alignment: .center, spacing: 0) {           // TRASH flank LEFT · MIDI CHAIN centred · verb buttons (LIBRARY/MUTATE/CLEAR) RIGHT — same sides in BOTH rooms (Paul 2026-09-10)
                        AnyView(roomsChainTrash(width: sideW, height: blockH))   // LEFT — the DELETE trash (invisible until a chain box is held; PLAY + SELECT removed, Paul 2026-09-10)
                        AnyView(buildProcessorBlock(castW: castW, cell: cell, hue: boxHue)).frame(width: blockW)   // the chain wears the SAME machine hue as the box (grey on SELECT) — Paul 2026-08-30
                        AnyView(buildChainButtonStack(width: sideW, height: blockH, showGrid: false))   // RIGHT — LIBRARY / MUTATE / CLEAR (always the right, both rooms)
                    }.overlay { buildChainFlowOverlay(sideW: sideW, blockW: blockW, blockH: blockH, boxH: (cell + cgap) * 1.5, gap: cgap, hue: boxHue, chain: selectedMachineChain()) })   // circles + connectors + NOTE COMETS (spans the circles, clipped out of POPULATED boxes) — Paul 2026-08-31
                }
                Spacer(minLength: 8)
                AnyView(buildEmitterToggles(castW: castW))                   // MIDI OUT A–D — pinned at the interior BOTTOM (the grid's last row line)
            }.frame(height: m.interiorH)
        }
        .padding(pad)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)    // CENTRED (Paul 2026-08-31): top-align dumped the whole leftover BELOW the emitter toggles (padding there) while the receiver toggles sat flush at the top — centring splits it so the gap above the receiver toggles == the gap below the emitter toggles
        // THE BOX WEARS A TINT OF THE SELECTED COLOUR (Paul 2026-09-10): the box background is now the focused machine's
        // hue (grey on the SELECT audition, via boxHue), sitting BELOW the toggles · MIDI chain · buttons. The glowing
        // border is REMOVED — the tint alone signals "this cell is the machine in view."
        // TAP OUTSIDE ANY BUTTON (Paul 2026-09-10): the box's tinted background is itself tappable — a tap that no control
        // consumes DESELECTS the processor (buildEditSlot = nil), so the card region falls back to the FERRY SETTINGS panel
        // (or the invitation when no ferry is on the bench). Buttons/boxes/toggles sit in front and swallow their own taps.
        .background(
            Rectangle().fill(boxHue.opacity(0.16))
                .contentShape(Rectangle())
                .onTapGesture { buildEditSlot = nil; buildAddSlot = nil; buildStageEye = false }
        )
    }
    // roomsVerticalPlay + roomsSelectButton RETIRED (Paul 2026-09-12 dead-code sweep — neither view is mounted. NOTE:
    // roomsSelectButton was the only thing that toggled buildSelectMode true, so SELECT-mode is already inaccessible; its
    // readers are now a dormant cluster — flagged in pending-tasks for a follow-up, not removed here.)
    // THE CHAIN TRASH (Paul 2026-09-10) — replaces the PLAY + SELECT flank. INVISIBLE + non-interactive at rest (it
    // renders nothing and never intercepts touch). While a MIDI-chain processor box is HELD (buildChainDragFrom set) a big
    // red garbage-can box appears here; dragging the box over it (detected via the chainBlock x — the trash is the left
    // flank, at x < 0) turns it EVEN REDDER, and dropping there deletes the processor from the chain (handled in buildProcBox).
    @ViewBuilder func roomsChainTrash(width: CGFloat, height: CGFloat) -> some View {
        // Appears during EITHER a chain-box drag (delete a processor) OR a ferry drag (delete a ferry — Paul 2026-09-12).
        let chainDrag = chainDragActive && buildChainDragMoved   // DRAG ONLY (Paul 2026-09-11): shown once the held box actually MOVES, not on the hold itself (chainDragActive auto-resets so it never sticks)
        let ferryDrag = ferryDragActive && buildFerryDragMoved && buildFerryDrag.map { if case .ferry = $0 { return true } else { return false } } == true   // a FERRY (not a select cell) can land here
        let dragging = chainDrag || ferryDrag
        let over = (chainDrag && buildChainOverTrash) || (ferryDrag && buildFerryHover == .trash)
        let boxH = 3 * 26 + 2 * BuildGeom.castGap   // SMALLER: the footprint of the LIBRARY/MUTATE/CLEAR stack (3 × 26 + 2 gaps) — Paul 2026-09-10
        ZStack {
            if dragging {
                RoundedRectangle(cornerRadius: 10)
                    .fill(Color(red: 0.62, green: 0.12, blue: 0.10).opacity(over ? 0.92 : 0.28))
                    .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color(red: 0.98, green: 0.28, blue: 0.22).opacity(over ? 1.0 : 0.5), lineWidth: over ? 3 : 1.5))
                    .overlay(Image(systemName: "trash.fill").font(.system(size: over ? 26 : 20, weight: .bold)).foregroundColor(.white.opacity(over ? 1.0 : 0.8)))
                    .shadow(color: over ? Color(red: 0.98, green: 0.2, blue: 0.16).opacity(0.7) : .clear, radius: over ? 9 : 0)
                    .frame(width: width, height: boxH)   // centred in the flank (like the button stack)
            }
        }
        .frame(width: width, height: height)
        // Register the trash frame in the shared "rooms" space so a ferry drag can hit-test it (the chain drag keeps using
        // the chainBlock-x trick). The whole flank is the drop target — forgiving. (Paul 2026-09-12)
        .background(GeometryReader { geo in Color.clear.preference(key: FerryZoneKey.self, value: [.trash: geo.frame(in: .named("rooms"))]) })
        .allowsHitTesting(false)   // never responds to touch (drags hit-test via coords, not this view) — Paul 2026-09-10
    }
    // (The wide RECORD row was RETIRED 2026-08-29 — the PLAY button took its band. The reel is still reached via the
    // REEL room. buildReelButton remains for that room / a future RECORD home.)

    // ── NEW INTERFACE (rooms) reuse — THE SELECT GRID = the LIBRARY-backed chain browser. Populate the SELECT room's
    // 8×8 with real chains from MY LIBRARY (saved + factory cells) by opening the existing grid selector on its LIBRARY
    // tab; each interior cell reuses buildGridSelCell (the drifting-note fingerprint face + tap-to-audition), verbatim.
    // Idempotent — safe to call on every SELECT-room appear. (Paul 2026-08-28)
    func roomsSelectSetup() {
        let carryFromPart = buildStagingPlaying                              // the PART was playing (active ferry ON) → carry the playing cell onto SELECT (Option A: derived, Paul 2026-09-13)
        buildEnsureGridSelOpen()                                              // opens the selector (loads library summaries + deals), guarded — no-op if already open
        // SELECT shows MY LIBRARY — but ONLY once it's LOADED (the summaries build async off-main, Paul 2026-09-11). Forcing
        // tab 1 before the load left the grid EMPTY at startup; stay on the DEALT bank until the library arrives (the async
        // lib-load completion in buildOpenGridSel flips to tab 1 when ready). A re-entry after load goes straight to library.
        if buildGridSelTab != 1 && !buildGridSelLib.isEmpty {
            buildGridSelStopAudition()                                       // (no-op while owner == .part — its guard needs a chain/browse voice)
            buildGridSelTab = 1
            buildGridSelComputeCellRolls()                                    // the library cells' drifting faces
        }
        // CARRY THE PLAYING PART CELL (Paul 2026-09-03): part→select while the part is PLAYING keeps that cell sounding on
        // the SELECT grid — a ONE-row (uniform) selection carries that exact cell; a MULTI-row selection carries the LAST-
        // selected side ferry (the active side button). Play ferries are a separate persistent layer and continue regardless.
        if carryFromPart, let row = buildPartCarryRow(), let cid = buildRowMachine(row) {
            buildSelectID(cid)                                              // the SELECT audition target = the playing part cell's machine
            buildApplyWorkshopVoice(.chain)                                 // continue it as the SELECT chain audition (seamless)
        } else {
            // No startup randomization (Paul 2026-08-29): the corpus is split into deterministic PAGES via the left rail
            // (page 0 = row 1 default). A cell auditions only when the user taps it.
            roomsSyncVoice(.select)                                          // normal entry — chain iff a browse cell is selected, else none
        }
    }
    // The PART row to CARRY into the SELECT audition on a part→select switch (Paul 2026-09-03): ONE distinct selected row
    // across the active columns → that exact cell; MULTIPLE distinct rows → the LAST-selected SIDE FERRY (the active side
    // button); nil if nothing populated carries. Used only when the part was playing (roomsSelectSetup).
    private func buildPartCarryRow() -> Int? {
        let distinct = Set(buildStagingSel.prefix(buildPartCols).filter { $0 >= 0 })
        if distinct.count == 1, let r = distinct.first, buildRowMachine(r) != nil { return r }   // ONE row → the same cell
        if let s = buildGridSelStampSourceRow, buildRowMachine(s) != nil { return s }             // MULTIPLE → the last selected side ferry
        return distinct.first { buildRowMachine($0) != nil }                                      // fallback: any populated selected row
    }

    // ── NEW INTERFACE — the PROCESSOR CARD overlay. A populated chain box opens its editor (buildProcessorPanel) as a
    // NON-MODAL card bounded to the GRID INTERIOR (inset from the header row + the side buttons), so everything outside
    // it stays reachable. Attached as an .overlay on the grid, so it's automatically clipped to the grid's frame; the
    // fractional insets carve out the side-button column(s) + the top selector row. (Paul 2026-08-28)
    // The card positioned at an EXPLICIT rect (the grid units compute the interior 8×8 rect + place it there). Non-modal.
    // NO outer box (buildProcessorPanel already draws its OWN selected-machine box + background) + NO padding, so that box
    // fills the whole card (Paul 2026-08-28) — only the panel's hue border shows, occupying the full space.
    @ViewBuilder func roomsProcessorCardAt(x: CGFloat, y: CGFloat, w: CGFloat, h: CGFloat) -> some View {
        let chain = selectedMachineChain()
        // §MERGE (Paul 2026-09-08): the card region is PERMANENT — always present below the grid, reflecting the selected
        // row/cell. Its CONTENT is the processor picked from the chain (buildEditSlot). With no pick (or an empty/stale
        // chain) it shows an invitation, so the space always reads as "the editor lives here".
        // TABS ALONG THE TOP (Paul 2026-09-10): a persistent header band — the CELL NAME tab (default "UNSET") then one tab
        // per processor in the chain. The active tab selects the view below (cell/ferry settings when the cell tab is active,
        // else that processor's controls). The card is FLAT now (no floating pop-up border/shadow) — it reads as part of the
        // page, keeping only the header-band styling.
        VStack(spacing: 0) {
            buildProcCardTabs(chain: chain)
            Group {
                if let slot = buildEditSlot, slot < chain.count, let cid = ddSelectedMachineID {
                    buildProcessorPanel(slot: slot, proc: chain[slot], cid: cid, contentW: w)
                } else if let a = buildActiveFerry, a >= 0, a < buildFerryParts.count, buildFerryParts[a] != nil {
                    // PLAY-FERRY LAUNCH SETTINGS (Paul 2026-09-09): the CELL tab (no processor selected) shows the selected
                    // ferry's launch/identity panel — until a processor tab is chosen.
                    roomsFerryLaunchPanel(a)
                } else {
                    roomsCardPlaceholder(empty: chain.isEmpty)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(width: w, height: h, alignment: .top)
        .background(buildPanel)                                            // FLAT panel fill — not a floating pop-up (no hue border, no shadow)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .offset(x: x, y: y)                                                // OFFSET LAST — so the opaque background moves DOWN with the card (was before .background → the fill rendered at the un-offset origin, covering the select grid). Paul 2026-09-10 fix.
    }
    // THE CARD TAB ROW (Paul 2026-09-10) — the header band. Leftmost = the CELL NAME (the active ferry's name, else "UNSET";
    // tap → the cell/ferry view, no processor selected). Then a tab per POPULATED processor in the chain (tap → edit it). The
    // active tab wears the machine hue. Keeps the old header's hue-tinted styling.
    @ViewBuilder private func buildProcCardTabs(chain: [ProcessorSlot]) -> some View {
        let hue = buildCardHue
        // The first (cell/ferry-settings) tab's name: a COMMITTED audition's generated hash name wins (Paul 2026-09-12), else
        // the active ferry's own name, else "UNSET".
        let committedName = buildGridSelSel.flatMap { buildGridSelName[$0] }
        let ferryName = buildActiveFerry
            .flatMap { $0 >= 0 && $0 < buildFerryParts.count ? buildFerryParts[$0]?.ferryName : nil }
            .flatMap { $0.isEmpty ? nil : $0 }
        let cellName = committedName ?? ferryName ?? "UNSET"
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                buildProcTab(cellName.uppercased(), active: buildEditSlot == nil, hue: hue) { buildEditSlot = nil; buildStageEye = false }
                // THE FOUR PART-ROW SELECTORS (Paul 2026-09-12): after the name tab, a compact mirror of the part grid's
                // right-rail selector buttons (roomsSideButton part:true — IDENTICAL styling + behaviour) showing which of the
                // 4 rows is selected + in focus. PART grid only (the 4-row rail is a part concept; the SELECT card has no rows).
                if roomsRoom == .part {
                    ForEach(0..<DiagView.roomsGridRows, id: \.self) { n in
                        roomsSideButton(n, part: true).frame(width: 26, height: 26)
                            .overlay { roomsCardRowPlayhead(n, w: 26, h: 26).clipShape(RoundedRectangle(cornerRadius: 5)) }   // a 1-step sweep while THIS row plays (Paul 2026-09-12)
                    }
                }
                ForEach(0..<chain.count, id: \.self) { s in
                    if !buildIsEmptySlot(chain[s]) {
                        Image(systemName: "chevron.right").font(.system(size: 10, weight: .bold)).foregroundColor(.white.opacity(0.45))   // the chain flow, tab → tab (Paul 2026-09-12)
                        buildProcTab(buildProcLabel(chain[s]), active: buildEditSlot == s, hue: hue) { buildEditSlot = s; buildStageEye = false }
                    }
                }
            }
            .padding(.horizontal, 16).padding(.vertical, 10)
        }
        .background(hue.opacity(0.22))   // the KEPT header styling
    }
    @ViewBuilder private func buildProcTab(_ label: String, active: Bool, hue: Color, _ tap: @escaping () -> Void) -> some View {
        Text(label).font(.system(size: 13, weight: .heavy, design: .monospaced))
            .lineLimit(2).multilineTextAlignment(.center).minimumScaleFactor(0.7)   // LONGER names wrap to two lines (Paul 2026-09-12); a single long word shrinks rather than clip
            .foregroundColor(active ? .black : .white.opacity(0.7))
            .frame(maxWidth: 64)                                                    // cap the text width → a long label wraps; a short one stays compact + one line
            .padding(.horizontal, 12).padding(.vertical, 6).frame(minHeight: 30)     // min touch height; grows to fit two lines
            .background(RoundedRectangle(cornerRadius: 7).fill(active ? hue : Color.white.opacity(0.08)))
            .contentShape(Rectangle()).onTapGesture(perform: tap)
    }
    // The always-present card region when no processor is being viewed: an invitation to pick one from the chain (or,
    // when the selected cell has no chain yet, to add one). Keeps the below-grid section permanently visible (Paul 2026-09-08).
    @ViewBuilder private func roomsCardPlaceholder(empty: Bool) -> some View {
        RoundedRectangle(cornerRadius: 12).fill(Color.white.opacity(0.03))
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.white.opacity(0.08), lineWidth: 1))
            .overlay(
                VStack(spacing: 8) {
                    Image(systemName: empty ? "plus.rectangle.on.rectangle" : "hand.tap")
                        .font(.system(size: 22, weight: .semibold)).foregroundColor(.white.opacity(0.28))
                    Text(empty ? "ADD A PROCESSOR FROM THE CHAIN" : "TAP A PROCESSOR IN THE CHAIN TO EDIT IT")
                        .font(.system(size: 11, weight: .heavy, design: .monospaced)).tracking(1).foregroundColor(.white.opacity(0.4))
                        .multilineTextAlignment(.center)
                }.padding(12)
            )
    }
    // ── PLAY-FERRY LAUNCH SETTINGS (Paul 2026-09-09, Docs/PLAN-play-ferry-launch.md) — the empty-card panel for the
    // selected part's ferry: identity (name · colour) + how it fires when performed (playback · trigger · start · choke).
    // Phase 1 = STORE the settings only (no engine yet). Edits write buildFerryParts[t] directly (its source of truth);
    // buildCaptureBenchPart preserves these across a bench write-back, and buildCapturePlayGrid persists them.
    @ViewBuilder func roomsFerryLaunchPanel(_ t: Int) -> some View {
        let p = (t >= 0 && t < buildFerryParts.count ? buildFerryParts[t] : nil) ?? BuildPart()
        let cur = t < buildFerryParts.count ? buildFerryParts[t]?.ferryHue : nil
        let starts: [FerryStart] = [.sync, .instant, .step, .beat, .pass]
        let startLabels = ["SYNC", "INSTANT", "STEP", "BEAT", "PASS"]
        let chokeOpts = ["OFF", "1", "2", "3", "4", "5", "6", "7", "8"]
        let leftW: CGFloat = 26 * 4 + 6 * 3   // the 4×4 colour grid width — the whole left column
        // PER-PART TIMING (Paul 2026-09-10) — moved here from the header: RATE ("—" = the scene default) + STEPS (8 | 16). The
        // ferry IS a part, so these edit the on-bench part via the existing setters (the card only shows for the active ferry).
        let rateLabels = ["\u{2014}"] + StepRate.allCases.map(\.rawValue)
        let rateSel = buildPartRate.flatMap { StepRate.allCases.firstIndex(of: $0) }.map { $0 + 1 } ?? 0
        RoundedRectangle(cornerRadius: 12).fill(Color(hex: buildFerryHex(t)).opacity(0.16))   // the SAME selected-colour tint as the machine box, in this ferry's hue (Paul 2026-09-10)
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.white.opacity(0.08), lineWidth: 1))
            .overlay(
                ScrollView(showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack(spacing: 6) {
                            Image(systemName: "slider.horizontal.3").font(.system(size: 12, weight: .bold)).foregroundColor(buildCyan)
                            Text("FERRY SETTINGS").font(.system(size: 11, weight: .heavy, design: .monospaced)).tracking(1).foregroundColor(.white.opacity(0.7))
                            Spacer()
                        }
                        // THREE COLUMNS (Paul 2026-09-09): LEFT = NAME (big) over the 4×4 COLOUR grid · CENTER = two controls
                        // stacked · RIGHT = the final two controls stacked. Bigger, easy-to-click dropdowns.
                        HStack(alignment: .top, spacing: 12) {
                            VStack(alignment: .leading, spacing: 8) {
                                launchLabel("NAME")
                                TextField("name", text: Binding(
                                    get: { (t < buildFerryParts.count ? buildFerryParts[t]?.ferryName : nil) ?? "" },
                                    set: { v in buildEditFerry(t, publish: false) { $0.ferryName = v.isEmpty ? nil : v } }))
                                    .font(.system(size: 15, weight: .semibold, design: .monospaced)).textFieldStyle(.plain)
                                    .foregroundColor(.white).padding(.horizontal, 8).frame(maxWidth: .infinity).frame(height: 38)
                                    .background(RoundedRectangle(cornerRadius: 7).fill(Color.white.opacity(0.07)))
                                launchLabel("COLOUR")
                                LazyVGrid(columns: Array(repeating: GridItem(.fixed(26), spacing: 6), count: 4), alignment: .leading, spacing: 6) {
                                    ForEach(Array(machineHexes.enumerated()), id: \.offset) { _, hex in
                                        RoundedRectangle(cornerRadius: 5).fill(Color(hex: hex))
                                            .frame(width: 26, height: 26)
                                            .overlay(RoundedRectangle(cornerRadius: 5).stroke(cur == hex ? Color.white : Color.clear, lineWidth: 2))
                                            .contentShape(Rectangle()).onTapGesture { buildEditFerry(t) { $0.ferryHue = hex } }
                                    }
                                }
                            }.frame(width: leftW)
                            VStack(alignment: .leading, spacing: 12) {   // CENTER column
                                launchInline("PLAYBACK", ["LOOP", "ONE-SHOT"], sel: p.launchPlaybackResolved == .oneShot ? 1 : 0, minChip: 62) { i in
                                    buildEditFerry(t) { $0.launchPlayback = i == 1 ? .oneShot : .loop } }
                                launchInline("TRIGGER", ["LATCH", "SPRING"], sel: p.launchTriggerResolved == .spring ? 1 : 0, minChip: 62) { i in
                                    buildEditFerry(t) { $0.launchTrigger = i == 1 ? .spring : .latch } }
                            }.frame(maxWidth: .infinity, alignment: .leading)
                            VStack(alignment: .leading, spacing: 12) {   // RIGHT column
                                launchInline("START", startLabels, sel: starts.firstIndex(of: p.launchStartResolved) ?? 0, minChip: 54) { i in
                                    buildEditFerry(t) { $0.launchStart = starts[i] } }
                                launchInline("CHOKE", chokeOpts, sel: p.chokeGroupResolved, minChip: 34) { i in
                                    buildEditFerry(t) { $0.chokeGroup = i == 0 ? nil : i } }
                            }.frame(maxWidth: .infinity, alignment: .leading)
                        }
                        // PER-PART TIMING — RATE + STEPS, moved from the header (Paul 2026-09-10). Edits the on-bench part.
                        HStack(alignment: .top, spacing: 12) {
                            VStack(alignment: .leading, spacing: 12) {   // RATE ("—" = scene default)
                                launchInline("RATE", rateLabels, sel: rateSel, minChip: 44) { i in
                                    buildSetPartRate(i == 0 ? nil : StepRate.allCases[i - 1]) }
                            }.frame(maxWidth: .infinity, alignment: .leading)
                            VStack(alignment: .leading, spacing: 12) {   // STEPS 8 | 16 (the part width / loop length)
                                launchInline("STEPS", ["8", "16"], sel: buildPartCols == 16 ? 1 : 0, minChip: 54) { i in
                                    buildSetPartLen(i == 1 ? 16 : nil) }
                            }.frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }.padding(12)
                }
            )
    }
    // Mutate the selected ferry's stored part (its source of truth). `publish:false` for the name field (display-only, avoids
    // a republish per keystroke); the launch selectors publish so downstream (the Phase-2 engine) will pick them up.
    func buildEditFerry(_ t: Int, publish: Bool = true, _ mut: (inout BuildPart) -> Void) {
        guard t >= 0, t < buildFerryParts.count, var p = buildFerryParts[t] else { return }
        mut(&p); buildFerryParts[t] = p
        if publish { buildPublishScene() }
    }
    @ViewBuilder private func launchLabel(_ s: String) -> some View {
        Text(s).font(.system(size: 9, weight: .heavy, design: .monospaced)).tracking(1.5).foregroundColor(.white.opacity(0.4))
    }
    // An INLINE segmented control — every option is a VISIBLE tappable chip (no pop-up). The chips WRAP to fill the column
    // (LazyVGrid adaptive); `minChip` sets roughly how wide each chip is (so 2/5/9 options pack sensibly). Big + easy to
    // click; selected = cyan (Paul 2026-09-09).
    @ViewBuilder private func launchInline(_ label: String, _ options: [String], sel: Int, minChip: CGFloat, _ onPick: @escaping (Int) -> Void) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            launchLabel(label)
            LazyVGrid(columns: [GridItem(.adaptive(minimum: minChip), spacing: 5, alignment: .leading)], alignment: .leading, spacing: 5) {
                ForEach(Array(options.enumerated()), id: \.offset) { idx, opt in
                    let on = idx == sel
                    Text(opt).font(.system(size: 12, weight: .heavy, design: .monospaced)).lineLimit(1).minimumScaleFactor(0.7)
                        .foregroundColor(on ? .black : .white.opacity(0.65))
                        .frame(maxWidth: .infinity, minHeight: 36)
                        .background(RoundedRectangle(cornerRadius: 6).fill(on ? buildCyan : Color.white.opacity(0.07)))
                        .contentShape(Rectangle()).onTapGesture { onPick(idx) }
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
    // roomsPlayNavSliver RETIRED (Paul 2026-09-12 dead-code sweep — not mounted; the ferry row is the sole navigation).
    // The part↔select SEAM sliver/column are RETIRED (Paul 2026-09-08, Phase 3): the ferry row is the sole navigation.
    // THE PLAY FERRY button (Paul 2026-08-29) — the SELECT grid's top-row buttons that FERRY the selected cell to the
    // PLAY grid. LONG-PRESS copies the currently-selected cell onto the play grid at THIS column's selected rung (→ its
    // grid position + the play bottom readout), with the rising-white overwrite warning (buildGridSelStampSweep, offset
    // +8 so the play-ferry fill never collides with the PART-ferry side buttons that share the select grid). Each button
    // shows a PLAY ICON in its predetermined PLAY machine (INDIGO); the button itself stays neutral — a white "set" keyline
    // + brighter field mark a column that has been ferried (was a number on a hue field).
    // THE FERRY-ROW CURSOR (Paul 2026-08-31): ▲▼ chooses which grid ROW the play-ferry buttons target — so you can ferry
    // a cell to row 1 of a column, then move the cursor and ferry another to row 3 (each cell stays independent). Sits in
    // the ferry row's left corner. Compact: ▲ · Rn · ▼ in one cell.
    // The ▲▼ FERRY-ROW CURSOR is RETIRED (Paul 2026-09-08, Phase 3): a ferry is one PART now, not a column of per-row cells.
    // A ferry's ONE identity colour as a hex: its explicit `ferryHue` override, else the P1 ferry-base palette (8 jewel
    // tones by position). The header redesign (Paul 2026-09-09) reads this for the focus highlight + the fading gradient.
    func buildFerryHex(_ t: Int) -> UInt32 {
        if let hue = ((t >= 0 && t < buildFerryParts.count) ? buildFerryParts[t]?.ferryHue : nil) { return hue }   // populated → the part's own hue (inherited from the ferried cell)
        return buildFerryHueAlloc[t] ?? ferryBaseHex(t)   // empty → a re-allocated displaced colour, else the positional base
    }
    @ViewBuilder func roomsPlayFerry(_ t: Int) -> some View {
        GeometryReader { g in
            // THE PLAY FERRIES ARE PARTS (Paul 2026-09-08): each ferry IS a BuildPart slot. The SELECTOR (top ⅓) opens
            // the part on the bench (empty → the SELECT grid); the PLAY button (bottom ⅔) starts/stops it (several may
            // play at once). A long-press on an EMPTY ferry (on SELECT) seeds a new part from the selected chain.
            let part = t < buildFerryParts.count ? buildFerryParts[t] : nil
            let set = part != nil
            // PLAY-FERRY LAUNCH (Paul 2026-09-09): the ferry's ONE identity colour = its ferryHue override, else the P1
            // ferry-base palette (supersedes the old representative-machine hue). The header gradient is the SELECTED
            // ferry's colour in lighter shades; each ferry shows its OWN colour only on its selector icon.
            let mHex = buildFerryHex(t)
            let mHue = Color(hex: mHex)
            let focusHex = buildActiveFerry.map { buildFerryHex($0) } ?? mHex   // the SELECTED colour the header bar fades from
            let ferryName = part?.ferryName
            let spring = part?.launchTriggerResolved == .spring   // PLAY-FERRY LAUNCH (Phase 2b): SPRING = momentary (hold-to-play); LATCH = tap-toggle (today)
            let eHue = emitterHue(part?.emitters ?? [.a])
            let on = t < buildPlayColOn.count && buildPlayColOn[t]        // this part is sounding
            let focused = buildActiveFerry == t                          // this part is the one loaded on the bench
            let selH = max(10, g.size.height * 0.24)              // selector height — the M/S row below matches it (Paul 2026-09-09)
            let playH = max(12, g.size.height - 2 * selH - 6)     // the PLAY button = the rest (largest); selector + M/S are the two equal-height ends
            VStack(spacing: 3) {
                // ── THE SELECTOR (top ⅓) = the header bar (Paul 2026-09-09, no cyan) ──
                // LIGHT EMANATES from the SELECTED ferry along the whole row: a strong tint of the selected colour,
                // brightest at the focus and DIMMING outward (each ferry paints its slice of the continuous falloff →
                // non-stepped, spanning populated AND empty selectors). Unselected ferries dim with distance; only the
                // focused one highlights (its own full colour). The icon is FOUR DOTS in the ferry's own pre-allocated
                // colour (identity); empty ferries show a "+".
                // NO SELECTION (fresh app start / nothing on the bench) ⇒ NO given-colour emanation (Paul 2026-09-11): with
                // buildActiveFerry nil the glow used to fake each ferry as its own focus, washing the whole row in colour at
                // startup. Only emanate once a ferry is actually SELECTED; until then the selectors are the neutral dark base.
                let hasFocus = buildActiveFerry != nil
                let focusPos = Double(buildActiveFerry ?? t) + 0.5          // the selected ferry's centre, in ferry units
                let iLo = hasFocus ? max(0.0, 1.0 - abs(Double(t) - focusPos) / 5.5) : 0        // glow reach ≈ 5–6 ferries
                let iHi = hasFocus ? max(0.0, 1.0 - abs(Double(t + 1) - focusPos) / 5.5) : 0
                let glow = mixHex(focusHex, 0xFFFFFF, 0.12)
                let base = hasFocus ? 0.05 : 0.0                            // no selection → fully neutral (dark base only)
                let sliceLo = Color(hex: glow).opacity(base + iLo * iLo * 0.80)   // near focus = bright · far = dim (dark base shows through)
                let sliceHi = Color(hex: glow).opacity(base + iHi * iHi * 0.80)
                let dotHue: Color = focused ? Color(hex: mixHex(mHex, 0x000000, 0.55)) : mHue   // the ferry's OWN pre-allocated colour (deepened on the focused own-colour highlight for contrast)
                let dotD = max(2.5, selH * 0.16)
                RoundedRectangle(cornerRadius: 4).fill(Color.white.opacity(0.04))
                    .overlay { RoundedRectangle(cornerRadius: 4).fill(LinearGradient(colors: [sliceLo, sliceHi], startPoint: .leading, endPoint: .trailing)) }   // the CONTINUOUS emanation (this ferry's slice)
                    .overlay { if focused { RoundedRectangle(cornerRadius: 4).fill(mHue.opacity(0.95)) } }              // FOCUSED = the light source: its OWN full colour
                    .overlay {
                        if set {
                            // THE SELECTED selector PULSES with the part's MIDI output (Paul 2026-09-12): the focused ferry is
                            // the part on the bench, so its identity dots flash the same velocity feed as its play button —
                            // matching the play-ferry pulse. Non-focused selectors stay static (only the selected one animates).
                            if focused {
                                TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: animationsPaused)) { tl in
                                    let lvl = buildFlashLevel(buildPlayColSweepIndices(t), now: tl.date)
                                    HStack(spacing: max(1.5, selH * 0.09)) { ForEach(0..<4, id: \.self) { _ in Circle().fill(dotHue).frame(width: dotD, height: dotD) } }
                                        .brightness(lvl * 0.6).scaleEffect(1.0 + lvl * 0.22)
                                }
                            } else {
                                HStack(spacing: max(1.5, selH * 0.09)) { ForEach(0..<4, id: \.self) { _ in Circle().fill(dotHue).frame(width: dotD, height: dotD) } }
                            }
                        } else {
                            Image(systemName: "plus").font(.system(size: min(10, selH * 0.5), weight: .bold)).foregroundColor(buildDim)
                        }
                    }
                    .overlay(RoundedRectangle(cornerRadius: 4).stroke(focused ? Color.white.opacity(0.9) : Color.white.opacity(0.10), lineWidth: focused ? 2 : 1))
                    .frame(height: selH)
                    .contentShape(Rectangle())
                    .onTapGesture { buildActivateFerry(t) }
                // ── THE PLAY BUTTON (bottom ⅔): start/stop this part; long-press an EMPTY ferry (on SELECT) seeds one ──
                RoundedRectangle(cornerRadius: 4).fill(buildCell)            // DARK STAGE
                    .overlay(RoundedRectangle(cornerRadius: 4).fill(mHue.opacity(set ? (on ? 0.24 : 0.10) : 0)))   // faint MACHINE wash (deeper while playing)
                    .overlay { if set { roomsCellPlayhead(active: on && !(focused && roomsRoom == .part)).padding(2) } }   // PER-CELL PLAYHEAD — but the SELECTED ferry playing on the part grid already shows playheads on its part cells, so don't double the sweep here (Paul 2026-09-10)
                    .clipShape(RoundedRectangle(cornerRadius: 4))
                    .overlay(RoundedRectangle(cornerRadius: 4).stroke(set ? mHue.opacity(on ? 1.0 : 0.5) : buildEdge, lineWidth: on ? 3 : (set ? 2 : 1)))   // focus no longer marks the PLAY button — the SELECTOR carries it (Paul 2026-09-09)
                    .shadow(color: on ? eHue.opacity(0.7) : .clear, radius: on ? 5 : 0)   // PLAYING → an EMITTER-coloured glow
                    // PLAY/STOP icon (left) + the ferry NAME on ONE vertically-centred line — the name LEFT-aligned, right of the
                    // icon (a trailing Spacer keeps the icon+name group hugging the left). Paul 2026-09-10.
                    .overlay {
                        HStack(spacing: 6) {
                            if set && on {   // RUNNING → the PLAY icon FLASHES the play column's velocity (Paul 2026-09-12: always a PLAY icon, never STOP — keep the velocity flash)
                                flashingIcon("play.fill", size: min(12, playH * 0.5), tint: mHue, baseOpacity: 0.85, indices: buildPlayColSweepIndices(t))
                            } else {
                                Image(systemName: set ? "play.fill" : "plus").font(.system(size: min(12, playH * 0.5), weight: .black)).foregroundColor(set ? mHue : buildDim)
                            }
                            if let nm = ferryName, !nm.isEmpty {
                                Text(nm).font(.system(size: min(9, playH * 0.3), weight: .heavy, design: .monospaced)).lineLimit(1).minimumScaleFactor(0.6)
                                    .foregroundColor(.white.opacity(0.9)).multilineTextAlignment(.leading)
                            }
                            Spacer(minLength: 0)
                        }.padding(.horizontal, 5)
                    }
                    .frame(maxHeight: .infinity)
                    .contentShape(Rectangle())
                    .onTapGesture { if set { if !spring { buildToggleFerryPlay(t) } } else { buildActivateFerry(t) } }   // LATCH toggles on tap; SPRING is momentary (the press below); empty PLAY tap → open the browser
                    // SPRING populated → MOMENTARY play (press on, release off; minDuration ∞ so perform never fires). The
                    // empty-ferry SEED long-press is RETIRED (Paul 2026-09-12) — populate a ferry by DRAGGING a SELECT cell
                    // onto it instead (the whole-ferry drag registered on the VStack below).
                    .onLongPressGesture(minimumDuration: .infinity, maximumDistance: 44,
                                        pressing: { p in if set && spring { buildSetFerryPlay(t, on: p) } }, perform: {})
                // ── M / S (Paul 2026-09-09): mute · solo THIS ferry's part, below the play cell, equal height to the selector ──
                let muted = t < buildPlayColMute.count && buildPlayColMute[t]
                let soloed = t < buildPlayColSolo.count && buildPlayColSolo[t]
                HStack(spacing: 3) {
                    Text("M").font(.system(size: min(11, selH * 0.5), weight: .heavy, design: .monospaced))
                        .foregroundColor(muted ? .white : (set ? .white.opacity(0.55) : buildDim.opacity(0.5)))
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .background(RoundedRectangle(cornerRadius: 4).fill(muted ? Color(hex: 0xC0392B) : Color.white.opacity(0.06)))
                        .contentShape(Rectangle()).onTapGesture { if set { buildToggleFerryMute(t) } }
                    Text("S").font(.system(size: min(11, selH * 0.5), weight: .heavy, design: .monospaced))
                        .foregroundColor(soloed ? .black : (set ? .white.opacity(0.55) : buildDim.opacity(0.5)))
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .background(RoundedRectangle(cornerRadius: 4).fill(soloed ? roomsAmber : Color.white.opacity(0.06)))
                        .contentShape(Rectangle()).onTapGesture { if set { buildToggleFerrySolo(t) } }
                }
                .frame(height: selH)
            }
            // DRAG-AND-DROP (Paul 2026-09-12): register this ferry's frame in the shared "rooms" space (a drop target), and
            // make a POPULATED ferry a drag SOURCE (move it to another ferry, or to the machine-box trash to delete it). The
            // hovered drop target rings cyan. An EMPTY ferry isn't a source (`including: .subviews` disables its drag).
            .background(GeometryReader { geo in Color.clear.preference(key: FerryZoneKey.self, value: [.ferry(t): geo.frame(in: .named("rooms"))]) })
            .overlay { if ferryDragActive && buildFerryDragMoved && buildFerryHover == .ferry(t) && buildFerryDrag != .ferry(t) { RoundedRectangle(cornerRadius: 6).stroke(Color.cyan, lineWidth: 3).padding(-1) } }
            .simultaneousGesture(buildFerryDragGesture(.ferry(t)), including: set ? .all : .subviews)
            // FOCUS is now shown by the SELECTOR (its own full colour) against the header's lighter-shade gradient —
            // the whole-ferry cyan ring is retired (Paul 2026-09-09: no cyan; highlight the small selector, not the ferry).
        }
    }
    // buildPlayFerryStep (the ▲▼ cursor mover) + buildPlayFerryDuplicate (the faint-copy) are RETIRED (Paul 2026-09-08,
    // Phase 3) — a ferry is one PART now, not a column of per-row cells.
    // ── THE PLAY FERRIES ARE PARTS (Paul 2026-09-08, AcceptanceCriteria-play-ferries-as-parts) — Phase 2 operations ──
    // Flatten ferry `t`'s stored part into the per-column PLAYBACK arrays (the SAME representation the engine already
    // plays, so up to 8 ferries sound at once). Mono line = the SELECTED RUNG per column (poly is future). If `t` is the
    // ACTIVE (on-bench) ferry, its live edits are captured first so what plays matches what you're editing.
    func buildFlattenFerry(_ t: Int) {
        guard t >= 0, t < 8 else { return }
        if buildActiveFerry == t, buildFerryParts[t] != nil { buildFerryParts[t] = buildCaptureBenchPart() }   // capture live edits only for a POPULATED active ferry — never populate an empty one (Paul 2026-09-12)
        guard let p = buildFerryParts[t] else {
            if t < buildPlayColSteps.count { buildPlayColSteps[t] = [] }
            if t < buildPlayColLen.count { buildPlayColLen[t] = 1 }
            if t < buildPlayColStepRecv.count { buildPlayColStepRecv[t] = [] }
            if t < buildPlayColStepEmit.count { buildPlayColStepEmit[t] = [] }
            return
        }
        let len = max(1, min(Snap.maxCols, p.length ?? Snap.cols))
        let rungAt: (Int) -> Int = { c in c < p.stagingSel.count ? p.stagingSel[c] : -1 }
        buildPlayColSteps[t]     = (0..<len).map { c in let r = rungAt(c); return (r >= 0 && c < p.stagingCells.count && r < p.stagingCells[c].count) ? p.stagingCells[c][r] : nil }
        buildPlayColLen[t]       = len
        buildPlayColRate[t]      = p.rate
        buildPlayColStepRecv[t]  = (0..<len).map { c in let r = rungAt(c); return r >= 0 ? (p.rowReceiver.flatMap { r < $0.count ? $0[r] : nil } ?? p.receiver) : p.receiver }
        buildPlayColStepEmit[t]  = (0..<len).map { c in let r = rungAt(c); return r >= 0 ? (p.rowEmitters.flatMap { r < $0.count ? $0[r] : nil } ?? p.emitters) : p.emitters }
    }
    // SELECTOR tap: bring ferry `t`'s part onto the bench (empty ferry → the SELECT grid). The ferry is a LIVE VIEW of its
    // part, so the outgoing ferry's bench edits are written back first.
    // PER-FERRY MUTE / SOLO (Paul 2026-09-09) — the M/S buttons below each play cell. Gate the AUDIO only (buildPlayColOn,
    // the play glyph, is unchanged): a ferry is audible iff NOT muted and (no ferry soloed, or it is soloed).
    func buildToggleFerryMute(_ t: Int) { guard t >= 0, t < buildPlayColMute.count else { return }; buildPlayColMute[t].toggle(); buildPublishScene() }
    func buildToggleFerrySolo(_ t: Int) { guard t >= 0, t < buildPlayColSolo.count else { return }; buildPlayColSolo[t].toggle(); buildPublishScene() }
    func buildFerryAudible(_ t: Int) -> Bool {
        let anySolo = buildPlayColSolo.contains(true)
        let muted = t >= 0 && t < buildPlayColMute.count && buildPlayColMute[t]
        let soloed = t >= 0 && t < buildPlayColSolo.count && buildPlayColSolo[t]
        return !muted && (!anySolo || soloed)
    }
    func buildActivateFerry(_ t: Int) {
        guard t >= 0, t < 8 else { return }
        if t == buildActiveFerry {                                            // RE-TAPPING the ferry already on the bench
            // The LIVE bench is the truth — capture it BEFORE the reload below, so re-tapping never discards
            // in-progress edits by reloading the STALE stored part (Paul 2026-09-12: was silent data loss).
            if buildFerryParts[t] != nil { buildFerryParts[t] = buildCaptureBenchPart() }
        } else if let a = buildActiveFerry, a >= 0, a < 8 {                    // the OUTGOING active ferry
            if buildFerryParts[a] != nil { buildFerryParts[a] = buildCaptureBenchPart() }   // write back ONLY a POPULATED ferry's bench edits — an EMPTY selector must NOT be captured into a part (Paul 2026-09-12: navigating away from an empty selector was populating it)
            if a < buildPlayColOn.count, buildPlayColOn[a] { buildFlattenFerry(a) } else { buildClearFerryPlayback(a) }   // if it's still ON it keeps sounding in the BACKGROUND (the play layer); its STAGING voice ends because it stops being the active ferry (derived — Option A)
        }
        if let p = buildFerryParts[t] {
            buildLoadBenchPart(p); buildActiveFerry = t; roomsRoom = .part
            if buildVoiceOwner == .chain { buildVoiceOwner = .none }          // leaving the chain audition; the part plays iff its ferry is ON (Option A — never auto-play on open)
            if t < buildPlayColOn.count, buildPlayColOn[t] { buildClearFerryPlayback(t) }   // active + ON → the STAGING sequencer (derived from buildPlayColOn[t]); never ALSO on the play layer
            roomsPartSetup()                                                  // same per-grid setup the retired toggle ran (rolls + focus default)
        } else {
            buildActiveFerry = t; roomsRoom = .select; buildVoiceOwner = .none   // an empty ferry opens the browser but STAYS SELECTED — its pre-allocated colour becomes the selected colour (Paul 2026-09-12: always one selected, never back to grey)
            roomsSelectSetup()                                                // opens the library browser (buildEnsureGridSelOpen), like the retired toggle
        }
        buildPublishScene()
    }
    // PLAY-button tap: start/stop ferry `t`. The ACTIVE (on-bench) ferry plays via the STAGING step-sequencer — the part
    // grid sweeps, each column's SELECTED rung fires, edits respond live. A BACKGROUND ferry plays via the play-layer
    // flatten (its mono line). Several may be on at once: one staging (the active) + up to seven play-layer.
    func buildToggleFerryPlay(_ t: Int) {
        guard t >= 0, t < 8, buildFerryParts[t] != nil else { return }
        buildSetFerryPlay(t, on: !(t < buildPlayColOn.count && buildPlayColOn[t]))
    }
    // FORCE a ferry on/off (the toggle, spring press/release, one-shot expiry, and bulk play-all all route through this so the
    // launch anchor is stamped/cleared consistently). PLAY-FERRY LAUNCH (Paul 2026-09-09).
    func buildSetFerryPlay(_ t: Int, on willOn: Bool, choke: Bool = true) {
        guard t >= 0, t < 8, buildFerryParts[t] != nil else { return }
        if t < buildPlayColOn.count, buildPlayColOn[t] == willOn { return }   // no-op if already in that state (spring onChanged fires repeatedly)
        if willOn && choke { buildChokeGroup(t) }   // PLAY-FERRY LAUNCH (Phase 3): launching one ferry stops the others in its choke group (a bulk START-ALL passes choke:false so members don't choke each other)
        if t < buildPlayColOn.count { buildPlayColOn[t] = willOn }
        buildStampFerryLaunch(t, on: willOn)                                  // PLAY-FERRY LAUNCH: anchor (from-top/quantized) on start, clear on stop
        if t == buildActiveFerry {
            buildClearFerryPlayback(t)                                        // active → the STAGING sequencer (derived from buildPlayColOn[t]); never ALSO on the play layer (no double-audition)
        } else {
            if willOn { buildFlattenFerry(t) } else { buildClearFerryPlayback(t) }   // background → the play layer
        }
        if willOn { au?.clearMachineSolo(); buildHostHalted = false }
        buildPublishScene()
    }
    // CHOKE GROUP (Paul 2026-09-09, Phase 3): launching ferry `t` stops every OTHER currently-ON ferry that shares its non-OFF
    // choke group (mutually-exclusive launch — a drum-fill group, an exclusive bassline, etc.). Victims are resolved BEFORE any
    // state changes (pure chokeVictims), then each stopped via the normal stop path. group OFF (0/nil) ⇒ nothing chokes.
    func buildChokeGroup(_ t: Int) {
        guard t >= 0, t < buildFerryParts.count, let g = buildFerryParts[t]?.chokeGroup, g > 0 else { return }
        let victims = BuildSceneLogic.chokeVictims(launching: t, group: g, parts: buildFerryParts, on: buildPlayColOn)
        for u in victims { buildSetFerryPlay(u, on: false) }   // depth-1: a victim's stop never chokes (choke fires on launch only)
    }
    // ONE-SHOT expiry (Paul 2026-09-09, Phase 2b): a ferry whose PLAYBACK is ONE-SHOT stops itself one part-length after its
    // launch. Driven by the 4 Hz poll (so the stop lands within a poll of the pass end — the ≤poll-granularity tail is a v1
    // limit; a sample-accurate engine stop is a follow-up). `beat` = the effective (host/free-run) beat. Reuses the proven
    // stop path (buildSetFerryPlay off), so a legato part's notes close cleanly like any ferry stop.
    func buildTickFerryOneShot(_ beat: Double) {
        for t in 0..<8 where t < buildPlayColOn.count && buildPlayColOn[t] {
            guard let p = buildFerryParts[t], p.launchPlaybackResolved == .oneShot, t < launchBeat.count else { continue }
            let step = p.rate?.beats ?? stepBeats
            let expiry = launchBeat[t] + Double(max(1, p.length ?? Snap.cols)) * step
            if beat >= expiry { buildSetFerryPlay(t, on: false) }
        }
    }
    // PLAY-FERRY LAUNCH (Paul 2026-09-09): stamp/clear a ferry's launch anchor. SYNC ⇒ 0 (transport-locked, today). INSTANT/
    // STEP/BEAT/PASS ⇒ the from-top phase anchor at that boundary (pure ferryLaunchAnchor). The beat is the tight extrapolated
    // live beat (host or free-run) so INSTANT plays the part from column 0 at the tap. launchBeat mirrors it (one-shot expiry, 2b).
    func buildStampFerryLaunch(_ t: Int, on: Bool) {
        guard t >= 0, t < 8, t < launchAnchor.count else { return }
        if on, let p = buildFerryParts[t] {
            let step = p.rate?.beats ?? stepBeats
            let passBeats = Double(max(1, p.length ?? Snap.cols)) * step
            let beat = max(0, meters.beatAnchor + Date().timeIntervalSince(meters.beatAnchorAt) * meters.tempo / 60.0)
            launchAnchor[t] = ferryLaunchAnchor(beat: beat, start: p.launchStartResolved, stepBeats: step, passBeats: passBeats)
            launchBeat[t] = beat
        } else {
            launchAnchor[t] = 0; launchBeat[t] = 0
        }
    }
    // Clear ferry `t`'s play-layer playback line — when it stops, OR when it becomes the ACTIVE ferry (then it plays via
    // the staging sequencer, so its play-layer row must be empty). Resets the pass to the inert single-cell default.
    func buildClearFerryPlayback(_ t: Int) {
        guard t >= 0, t < 8 else { return }
        if t < buildPlayColSteps.count { buildPlayColSteps[t] = [] }
        if t < buildPlayColLen.count { buildPlayColLen[t] = 1 }
        if t < buildPlayColStepRecv.count { buildPlayColStepRecv[t] = [] }
        if t < buildPlayColStepEmit.count { buildPlayColStepEmit[t] = [] }
        if t < buildPlayCells.count { for r in 0..<buildPlayCells[t].count { buildPlayCells[t][r] = nil } }   // no legacy single-cell either
    }
    // ── FERRY DRAG-AND-DROP (Paul 2026-09-12) — supersedes the long-press seed/copy. ──────────────────────────────────
    // The drag gesture: a SELECT cell or a populated ferry, tracked in the shared "rooms" space. Mirrors the chain-reorder
    // pattern — `ferryDragActive` is a @GestureState that AUTO-RESETS on end/cancel, so the ghost + highlights never stick.
    func buildFerryDragGesture(_ src: FerryDragSource) -> some Gesture {
        DragGesture(minimumDistance: 12, coordinateSpace: .named("rooms"))
            .updating($ferryDragActive) { _, state, _ in state = true }
            .onChanged { g in
                buildFerryDrag = src
                buildFerryDragMoved = true
                buildFerryDragLoc = g.location
                buildFerryHover = buildFerryZoneAt(g.location)
            }
            .onEnded { g in
                let s = buildFerryDrag; let zone = buildFerryZoneAt(g.location)
                buildFerryDrag = nil; buildFerryDragMoved = false; buildFerryHover = nil
                if let s = s { buildFerryDrop(source: s, zone: zone) }
            }
    }
    // Which drop zone (if any) contains point `p` (in the "rooms" space) — the pure core lives in BuildSceneLogic.
    func buildFerryZoneAt(_ p: CGPoint) -> FerryDropZone? { BuildSceneLogic.ferryZoneAt(p, zones: buildFerryZones) }
    // Resolve a completed drag: SELECT cell → ferry = populate (overwrite); ferry → ferry = move (overwrite); ferry →
    // trash = delete. A SELECT cell on the trash is a no-op (library entries aren't deleted this way — Paul 2026-09-12).
    func buildFerryDrop(source: FerryDragSource, zone: FerryDropZone?) {
        switch (source, zone) {
        case let (.selectCell(i), .ferry(t)):            buildPopulateFerryFromSelect(i, into: t)
        case let (.ferry(f), .ferry(t)) where f != t:    buildMoveFerry(f, to: t)
        case let (.ferry(f), .trash):                    buildDeleteFerry(f)
        default: break
        }
    }
    // Populate ferry `t` with SELECT grid cell `i` — a PART WITH ONE ROW (Paul 2026-09-12). The ferry INHERITS the cell's
    // name, colour and settings (chain). Overwrites a populated ferry.
    func buildPopulateFerryFromSelect(_ i: Int, into t: Int) {
        guard let hit = buildGridSelChainAt(i) else { return }
        let name = buildGridSelName[i] ?? buildChainShortHash(hit.chain)             // the committed name, else a short hash (inherit a name either way)
        buildPopulateFerry(t, chain: hit.chain, transpose: hit.transpose, hue: hit.hex, name: name)
    }
    // The shared populate core: mint a part carrying `chain` across a full 16-step row, inheriting `hue`/`name`, store it in
    // ferry `t`, open it. COLOUR REALLOCATION (Paul 2026-09-12): if this overwrites a populated ferry of a DIFFERENT colour
    // whose incoming colour is currently allocated to an EMPTY ferry, that empty ferry is re-allocated the DISPLACED colour
    // (so the palette never doubles up).
    func buildPopulateFerry(_ t: Int, chain: [ProcessorSlot], transpose: Int, hue: UInt32? = nil, name: String? = nil) {
        guard t >= 0, t < 8 else { return }
        buildRecordUndo()
        if let cellHex = hue, t < buildFerryParts.count, buildFerryParts[t] != nil {   // overwriting a populated ferry
            let oldHex = buildFerryHex(t)
            let empty = (0..<8).map { buildFerryParts[$0] == nil }
            let hex = (0..<8).map { buildFerryHex($0) }
            if let u = BuildSceneLogic.ferryColourDisplacement(target: t, cellHex: cellHex, oldHex: oldHex, empty: empty, hex: hex) {
                buildFerryHueAlloc[u] = oldHex                                        // the displaced colour moves to the empty ferry that held the incoming colour
            }
        }
        // FERRY HUE UNIQUENESS (Paul 2026-09-13): a machine's colour STICKS to it, seeded from where it's placed — but two
        // populated ferries must never wear the SAME colour (a real "which is which" confusion). Only reassign on an ACTUAL
        // clash with another populated ferry (so a clean inherited palette colour is kept when it's already distinct);
        // buildDistinctHue avoids every live hue, so it can't re-collide.
        var effHue = hue
        if let h = hue, (0..<8).contains(where: { $0 != t && buildFerryParts[$0] != nil && buildFerryHex($0) == h }) {
            effHue = buildDistinctHue()
        }
        let y = buildNewTabMachine(t, machine: chain, transpose: transpose, hex: effHue)   // a fresh part machine carrying the chain, in the CELL's (distinct) hue (nil ⇒ the vivid part hue)
        var p = BuildPart()
        p.length = Snap.maxCols                                                       // a full 16-step part (the grid defaults to 16)
        for c in 0..<Snap.maxCols { p.stagingCells[c][0] = y; p.stagingSel[c] = 0 }   // the chain across the WHOLE first row → a full sequence, not one cell
        p.selID = y; p.cast = [y]
        p.receiver = buildSelReceiver; p.emitters = buildDefaultEmitters
        p.ferryHue = effHue                                                           // the ferry inherits the cell's colour, made distinct from other ferries (Paul 2026-09-13)
        p.ferryName = name                                                            // …and its name
        buildFerryParts[t] = p
        buildFerryHueAlloc[t] = nil                                                   // a populated ferry's colour comes from its part now, not the empty-slot alloc
        buildSyncMachines()
        if t < buildPlayColOn.count { buildPlayColOn[t] = true }                      // a populated ferry starts playing at once (via the staging sequencer once activated)
        buildReactivateFerry(t)                                                       // fresh load of the NEW part (skip the stale-bench writeback)
    }
    // MOVE ferry `from` → `to` (overwrites the target; vacates the source), carrying play/mute/solo state. (Paul 2026-09-12)
    func buildMoveFerry(_ from: Int, to: Int) {
        guard from >= 0, from < 8, to >= 0, to < 8, from != to, buildFerryParts[from] != nil else { return }
        buildRecordUndo()
        if buildActiveFerry == from { buildFerryParts[from] = buildCaptureBenchPart() }   // capture the source's live bench edits first
        let part = buildFerryParts[from]
        let on   = from < buildPlayColOn.count   ? buildPlayColOn[from]   : false
        let mute = from < buildPlayColMute.count ? buildPlayColMute[from] : false
        let solo = from < buildPlayColSolo.count ? buildPlayColSolo[from] : false
        buildResetFerrySlot(from); buildResetFerrySlot(to)                            // clear both (stale playback), then set the target
        buildFerryParts[to] = part
        if to < buildPlayColOn.count   { buildPlayColOn[to]   = on }
        if to < buildPlayColMute.count { buildPlayColMute[to] = mute }
        if to < buildPlayColSolo.count { buildPlayColSolo[to] = solo }
        buildSyncMachines()
        buildReactivateFerry(to)                                                      // fresh activate the moved part (the source is now empty → no stale writeback)
    }
    // DELETE ferry `t` (drag it to the machine-box trash). Clears the slot; if it was on the bench, falls back to the
    // SELECT browser (the empty-ferry behaviour), keeping it selected. (Paul 2026-09-12)
    func buildDeleteFerry(_ t: Int) {
        guard t >= 0, t < 8, buildFerryParts[t] != nil else { return }
        buildRecordUndo()
        let wasActive = buildActiveFerry == t
        buildResetFerrySlot(t)
        buildSyncMachines()
        if wasActive { buildReactivateFerry(t) }                                      // t is now empty → opens the browser, stays selected
        else { buildPublishScene() }
    }
    // Clear ferry slot `t` FULLY — part + on/mute/solo + launch anchors + play-layer playback. No undo (callers record).
    func buildResetFerrySlot(_ t: Int) {
        guard t >= 0, t < 8 else { return }
        buildFerryParts[t] = nil
        if t < buildPlayColOn.count   { buildPlayColOn[t]   = false }
        if t < buildPlayColMute.count { buildPlayColMute[t] = false }
        if t < buildPlayColSolo.count { buildPlayColSolo[t] = false }
        if t < launchAnchor.count     { launchAnchor[t] = 0 }
        if t < launchBeat.count       { launchBeat[t] = 0 }
        buildFerryHueAlloc[t] = nil                                                   // a freshly-emptied slot returns to its positional base colour
        buildClearFerryPlayback(t)                                                    // steps/len/recv/emit/playCells
    }
    // Activate ferry `t` with a FRESH load — clear any stale active-ferry pointer first so buildActivateFerry doesn't write
    // the OLD bench back over the new/moved part (the source slot is already emptied by the caller). (Paul 2026-09-12)
    func buildReactivateFerry(_ t: Int) {
        if buildActiveFerry == t { buildActiveFerry = nil }
        buildActivateFerry(t)
    }
    // The FLOATING GHOST that follows the finger during a ferry drag (drawn in the "rooms" space, hit-transparent).
    @ViewBuilder func buildFerryDragGhost() -> some View {
        if ferryDragActive, buildFerryDragMoved, let src = buildFerryDrag {
            let hex: UInt32 = {
                switch src {
                case let .selectCell(i): return buildGridSelCellHex(i)
                case let .ferry(t):      return buildFerryHex(t)
                }
            }()
            RoundedRectangle(cornerRadius: 6).fill(Color(hex: hex).opacity(0.9))
                .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.white.opacity(0.85), lineWidth: 2))
                .frame(width: 40, height: 30)
                .shadow(color: .black.opacity(0.4), radius: 6)
                .position(buildFerryDragLoc)
                .allowsHitTesting(false)
        }
    }
    // roomsAssignPlayColumn / roomsFlattenPartToPlay / roomsStampSourceIO (the old SELECT-top-button + part-flatten play-column
    // ferry, long-press-driven) are RETIRED (Paul 2026-09-12) — the ferry-is-a-part model + drag-and-drop (buildPopulateFerry /
    // buildMoveFerry / buildFlattenFerry) replaced them; they had no call site left.
    // ── THE SELECT GRID UNIT — the library grid + its edge selectors + the ▲PLAY sliver, in ONE box. The part↔select
    // SEAM has moved OUT to the far side of the page (roomsSeamColumn); the grid reflows to use the full width. (Paul 2026-08-28)
    // §MERGE (Paul 2026-09-08): the SELECT browser is now FOUR rows (was 8) — the left rail's 4 categories (ARP·RIFF·
    // RATCHET·CC) sit one per row — with the processor card docked permanently in the freed lower half. The ▲PLAY sliver
    // is gone (play grid retired → the ferries drive playback).
    @ViewBuilder func roomsSelectGridUnit(m: RoomsMetrics) -> some View {
        GeometryReader { g in
            let gap = RoomsMetrics.gap, pad = RoomsMetrics.pad                 // heights from the shared lattice (m); width per-view
            let rows = DiagView.roomsGridRows                                 // §MERGE: 4 interior rows
            let cw = max(6, (g.size.width - 2 * pad - 9 * gap) / 10)           // 10 cols (LEFT page rail + 8 interior + right side button)
            let ch = m.ch
            let rowH = ch * 0.5                                             // §MERGE (Paul 2026-09-08): interior cells are HALF the ferry-cell height
            let interiorH = rowH * CGFloat(rows) + gap * CGFloat(rows - 1)   // the 4-row browser (half-height cells)
            let footerH = ch / 3.0                                           // HALVED (Paul 2026-09-09): the footer rail is now 1/3 the ferry height
            let footerY = interiorH + gap                                    // the footer sits flush beneath the last grid row (NOT at the bottom of the unit)
            let cardY = footerY + ch * 2.0 / 3.0 + gap                       // the card stays put → the freed half is a HIDDEN-CELL GAP between the footer and the card (Paul 2026-09-09)
            let lowerH = max(interiorH, g.size.height - 2 * pad - ch - gap)  // below the ferry row: the 4-row browser + the footer + the docked card
            VStack(alignment: .leading, spacing: gap) {
                HStack(spacing: gap) {                                       // the PLAY-ferry row (transport moved to the header play strip — Paul 2026-09-09)
                    Color.clear.frame(width: cw, height: ch)                 // left rail slot — keeps the ferries aligned with the grid's left rail
                    ForEach(0..<8, id: \.self) { c in roomsPlayFerry(c).frame(width: cw, height: ch) }   // the PLAY-ferry buttons (select → play)
                    Color.clear.frame(width: cw, height: ch)                 // right rail slot
                }
                ZStack(alignment: .topLeading) {                            // the 4-row browser + the docked card below
                    VStack(spacing: gap) {
                        ForEach(0..<rows, id: \.self) { r in                  // LEFT page rail (category) + interior cells + right side button
                            HStack(spacing: gap) {
                                roomsSelectPage(r).frame(width: cw, height: rowH)  // the CATEGORY selector (ARP·RIFF·RATCHET·CC)
                                ForEach(0..<8, id: \.self) { c in roomsSelectGridCell(r * 8 + c).frame(width: cw, height: rowH) }
                                roomsSideButton(r).frame(width: cw, height: rowH)
                            }
                        }
                    }
                    // The footer row (Paul 2026-09-08): flush BENEATH the grid rows, spanning the interior body (rails excluded).
                    roomsGridFooter(cells: 8, railW: cw, gap: gap, h: footerH)
                        .frame(width: cw * 10 + gap * 9, height: footerH).offset(y: footerY)   // SELECT = pages (placeholder, not wired)
                    // The processor-editor card (Paul 2026-09-08): docked BELOW the footer (so it no longer covers it),
                    // filling the rest of the freed lower half, spanning the full grid-region width.
                    roomsProcessorCardAt(x: 0, y: cardY, w: cw * 10 + gap * 9, h: max(0, lowerH - cardY))
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
    // §MERGE (Paul 2026-09-08): FOUR categories, one per rail row (the SELECT grid is now 4 rows): ARP · RIFF · RATCHET · CC.
    // FOUR rail rows, one per SELECT grid row. Each covers a SET of processor types (Paul 2026-09-11): PULSE gathers the
    // rhythm/strike drivers (euclid · ratchet + the variety strikers) so euclid machines are browsable within the 4-row rail.
    var roomsSelectCategories: [(label: String, types: [ProcessorType])] {
        [("ARP", [.arp]), ("RIFF", [.riff]), ("PULSE", [.euclid, .ratchet, .cascade, .strum, .weave, .burst]), ("CC", [.mod])]
    }
    private func buildGridSelCategoryTypes(_ c: Int) -> [ProcessorType] { roomsSelectCategories[max(0, min(roomsSelectCategories.count - 1, c))].types }
    // Recompute the CURRENT category's matching library indices (an entry matches if its chain contains the category's
    // processor). Called on a category change + when the library loads. Cheap O(lib) scan, cached in buildGridSelCatIndices.
    func buildGridSelRecomputeCategory() {
        let cats = buildGridSelCategoryTypes(buildGridSelPage)
        buildGridSelCatIndices = buildGridSelLib.indices.filter { i in buildGridSelLib[i].types.contains { cats.contains($0) } }
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
        buildGridSelName.removeAll()                                    // committed names are index-keyed → stale after a page remap (Paul 2026-09-12)
        buildGridSelLastSlot.removeAll()                                // page remaps index→chain → the last-viewed-slot memory is stale (Paul 2026-09-10)
        buildGridSelPage = c
        buildGridSelRecomputeCategory()
        buildGridSelComputeCellRolls()
    }
    // THE GRID FOOTER (Paul 2026-09-08) — a row at the BOTTOM of each grid, mirroring the top ferry row at 2/3 its height,
    // spanning the MAIN BODY only (the interior columns, NOT the side rails: flanked by rail-width spacers). PLACEHOLDER for
    // now — SELECT = pages · PART = column-loop buttons (behaviour deliberately NOT wired yet; this just reserves the space).
    @ViewBuilder private func roomsGridFooter(cells: Int, railW: CGFloat, gap: CGFloat, h: CGFloat) -> some View {
        HStack(spacing: gap) {
            Color.clear.frame(width: railW, height: h)                       // left rail — excluded from the footer's width
            HStack(spacing: gap) {                                            // the body: one cell per interior column, filling the interior width
                ForEach(0..<max(1, cells), id: \.self) { _ in
                    RoundedRectangle(cornerRadius: 5).fill(Color.white.opacity(0.05))
                        .overlay(RoundedRectangle(cornerRadius: 5).stroke(buildEdge, lineWidth: 1))
                        .frame(maxWidth: .infinity)
                }
            }
            Color.clear.frame(width: railW, height: h)                       // right rail — excluded
        }
        .frame(height: h)
    }
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
            let present = buildGridSelPresent(i)
            buildGridSelCell(i, w: cg.size.width, h: cg.size.height, greyUnlessSel: true, vPad: cg.size.height * 0.15)   // SELECT grid: grey-unless-selected + 15% roll padding (Paul 2026-08-29)
                .onLongPressGesture(minimumDuration: buildGridSelStampDur, maximumDistance: 44, perform: { roomsCopyToSelectCell(i) })
                // DRAG a populated SELECT cell onto a play ferry to populate it (Paul 2026-09-12). `including: .subviews`
                // disables the drag on an empty cell; a plain tap (<12pt) still auditions, a stationary hold still copies.
                .simultaneousGesture(buildFerryDragGesture(.selectCell(i)), including: present ? .all : .subviews)
        }
    }
    // A SELECT-grid SIDE BUTTON (the row-select column) = a PART slot that holds a chain (the §4 shared exclusive column).
    // Reuses the grid selector's visual pieces (drift face + rising-white STAMP SWEEP) with NEW-INTERFACE gestures:
    //   TAP        = make this the ACTIVE selection (white border) + play/load its chain (reflected in the chain/IN/OUT
    //                panel) + arm it as a STAMP SOURCE when populated (buildGridSelStampSourceRow).
    //   LONG-PRESS = copy the active source (a browse CELL *or* another SIDE BUTTON) onto this slot — the rising white
    //                fill → white-fade CONFIRM revealing the part's fixed-by-row-position machine (partPosHex(n)).
    // The stamp writes the shared part row, so the PART grid's slot + row light up too (one model, two rooms). (Paul 2026-08-28)
    @ViewBuilder func roomsSideButton(_ n: Int, part: Bool = false) -> some View {
        GeometryReader { g in roomsSideChip(n, height: g.size.height, part: part) }
    }
    @ViewBuilder private func roomsSideChip(_ n: Int, height: CGFloat, part: Bool) -> some View {
        let populated = buildRowMachine(n) != nil                          // this slot/row holds a chain
        let active = buildGridSelStampSourceRow == n                      // THE active side button
        // The PART rail (part:true) now wears the ACTIVE ferry's colour in shades (P2b palette), matching the grid rows —
        // was the 4 fixed-position primaries (Paul 2026-09-09). The SELECT→part ferry chip (part:false) keeps its own recipe.
        let mHue = part ? Color(hex: partFerryHue(n)) : partPosHue(n)
        let selectedVis = active && (populated || part)   // PART rail: an EMPTY slot can be selected too (Paul 2026-09-03), so it highlights when active
        // IS THIS ROW'S CELL SOUNDING? PART grid → the SEQUENCER's active rung; SELECT→part ferry → the AIMED audition
        // (the select page's extra voice; the sequenced part does NOT run on select).
        // The PART rail is a SIMPLE SELECTOR (Paul 2026-09-04): it must NOT follow the sequencer — the playhead + the cells
        // already show what's playing. So `playing` is always false on the part rail; only populated/selected drive its look.
        let playing = populated && !part && buildGridSelStampSourceRow == n && buildDisplayVoice == .chain
        // THREE STATES (Paul 2026-08-30): NULL (dark + thin edge) · POPULATED (machine-hue frame + a calm fingerprint) ·
        // PLAYING (bright machine frame + an EMITTER glow + REAL drifting notes). Machine = the frame, emitter = the drift
        // tint + a corner dot. When the select→part ferry is the AIMED/auditioning one, it now shows the audition's LIVE
        // emitted notes (#5, Paul 2026-08-30): the audition parks on buildChainAuditionRow (col 0), so its strike feed lives
        // at that engine index — read it here. Idle → the static CHAIN fingerprint (buildGridSelRowRoll) as the calm tell.
        RoundedRectangle(cornerRadius: 5).fill(buildCell)                // DARK STAGE
            .frame(height: height)
            // FLAT dark, FIXED-BY-ROW-POSITION ground for BOTH rails (Paul 2026-09-06, design-cell-language decision 4):
            // the ferry reads IDENTICAL to the part slot it stamps, and the two halves of the one component finally agree —
            // dark position hue, no wash. (Was: part rail = a faint machine wash; ferry = a machine-hued partCellFill.)
            // BACKGROUND COLOUR only when SELECTED (Paul 2026-09-09): every other rail cell stays the plain dark stage.
            .overlay(RoundedRectangle(cornerRadius: 5).fill(selectedVis ? (part ? partFerryFill(n) : partPosFill(n)) : Color.clear))
            // (No piano-roll note face on the rail — Paul 2026-09-09: lose the old drifting-notes look here too. The
            //  long-press COPY/stamp + its rising-fill animation are RETIRED here — Paul 2026-09-12.)
            .clipShape(RoundedRectangle(cornerRadius: 5))
            // INVERTED when this row is the FOCUSED machine (shown in the machine view): the WHOLE chip becomes the
            // row-position machine and the number goes to an alpha knockout (Paul 2026-09-04, kept as the part-rail focus
            // tell per Paul 2026-09-06). Part rail only.
            .overlay { if part && selectedVis { RoundedRectangle(cornerRadius: 5).fill(mHue) } }
            // FRAME (Paul 2026-09-06): BOTH rails now wear the DARK, FLAT partPosFrame (never brightens on play — only the
            // notes animate), with a WHITE RING when the button is the active/aimed source (design-cell-language decision 5:
            // selected = white ring, not a hue brighten). Was: part rail = a bright machine frame; ferry = a machine partCellFrame.
            .overlay(RoundedRectangle(cornerRadius: 5).stroke(
                populated ? (selectedVis ? Color.white.opacity(0.85) : (part ? buildEdge : partPosFrame(n)))   // part rail: NEUTRAL edge unless selected (no stray shade — Paul 2026-09-09)
                          : (selectedVis ? Color.white.opacity(0.7) : buildEdge),
                lineWidth: playing ? 3 : (selectedVis ? 2.5 : (populated ? 2 : 1))))
            .overlay { if buildSelectMode && populated { RoundedRectangle(cornerRadius: 5).stroke(Color.white, lineWidth: 2.5) } }   // SELECT MODE: light white — tap to focus (Paul 2026-08-31)
            // (the corner EMITTER dot was removed — Paul 2026-09-10)
            .overlay {
                if part {                                                // PART rail → UNPOPULATED shows a "+" (add invitation); POPULATED shows its preallocated NUMBER (Paul 2026-09-11)
                    if populated {
                        Text("\(n + 1)").font(.system(size: min(13, height * 0.42), weight: .heavy, design: .monospaced))
                            .foregroundColor(selectedVis ? Color.black.opacity(0.6) : Color.white.opacity(0.6))   // NEUTRAL number unless selected — no stray shade (Paul 2026-09-09)
                    } else {
                        Image(systemName: "plus").font(.system(size: min(12, height * 0.42), weight: .bold))
                            .foregroundColor(selectedVis ? Color.black.opacity(0.6) : Color.white.opacity(0.35))   // empty row → add invitation
                    }
                } else {                                                 // SELECT→part ferry → a small PLAY/STOP status glyph in the machine hue (over the flat dark ground)
                    Image(systemName: playing ? "stop.fill" : "play.fill").font(.system(size: min(11, height * 0.4), weight: .black)).foregroundColor(populated ? mHue : buildDim).opacity(playing ? 0.85 : 1.0)
                }
            }
            .contentShape(Rectangle())
            .onTapGesture {
                if buildSelectMode { if let cid = buildRowMachine(n) { buildSelectID(cid) }; buildSelectMode = false }   // SELECT MODE: focus this row's machine, then end SELECT (Paul 2026-08-31)
                else { part ? roomsTapPartSide(n) : roomsTapSide(n) }
            }
            // The long-press COPY (roomsStampFire) is RETIRED (Paul 2026-09-12) — the rail is tap-to-select only now.
    }
    // roomsStampFire (the side-rail long-press copy) is RETIRED (Paul 2026-09-12 — ferry drag-and-drop; rail is tap-only).
    // TAP a SELECT side button — a POPULATED one becomes the active selection + stamp source (and auditions its chain); an
    // EMPTY one only AIMS (targets a future stamp) — it must not read as selected when the user hasn't committed. (Paul 2026-08-29)
    private func roomsTapSide(_ n: Int) {
        buildGridSelAimRow(n)                                            // aim this row as the stamp/commit target (+ audition if populated)
        if buildRowMachine(n) != nil { buildRoomsSetActiveSide(n) }      // only a POPULATED button becomes THE active selection + copy source
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
    // §MERGE (Paul 2026-09-08): the PART grid is now FOUR interior rows (was 8) — a compact 8|16 × 4 main body — with the
    // processor card docked permanently in the freed lower half. The ▲PLAY sliver + the piano-roll + the AUTO section are
    // GONE (the standalone play grid is retired → the ferries drive playback; piano-roll/AUTO not ported yet per Paul).
    static let roomsGridRows = 4                                            // the merged main-body row count (was 8)
    @ViewBuilder func roomsPartGrid(m: RoomsMetrics) -> some View {
        GeometryReader { g in
            let gap = RoomsMetrics.gap, pad = RoomsMetrics.pad               // heights come from the shared lattice (m); width stays per-view
            let cols = buildPartCols                                         // §E: the part-grid STEP count = the active width (8 or up to 16)
            let rows = DiagView.roomsGridRows                               // §MERGE: 4 interior rows
            // FULL-WIDTH SIDE RAILS (Paul 2026-09-02): the left/right rails (+ the ferry-row STOP/▲▼ that cap them) are ONE
            // interior cell wide — same as the play/ferry cells. Width = `cols` interior cells + 2 rails (cols+2 cells worth).
            let cw = max(6, (g.size.width - 2 * pad - CGFloat(cols + 1) * gap) / CGFloat(cols + 2))   // cell width (cols interior + 2 full-width rails)
            let railW = cw                                                   // the side rails + the STOP/▲▼ header slots = a full cell (Paul 2026-09-02)
            let ch = m.ch
            let rowH = ch * 0.5                                             // §MERGE (Paul 2026-09-08): interior cells are HALF the ferry-cell height (freed space → the card)
            let interiorW = cw * CGFloat(cols) + gap * CGFloat(cols - 1)
            // The PLAY LAYER is ALWAYS 8 columns (buildPlayColOn etc.), independent of the part grid width. So there are
            // always 8 play ferries — when the part is 16 steps wide they simply widen to fill the interior (a ferry per
            // two columns), never becoming 16 (which would index the 8-slot play layer out of range). (Paul 2026-09-04)
            let ferryW = (interiorW - CGFloat(7) * gap) / 8
            let interiorH = rowH * CGFloat(rows) + gap * CGFloat(rows - 1)  // the 4-row grid
            let footerH = ch / 3.0                                           // HALVED (Paul 2026-09-09): the footer rail is now 1/3 the ferry height
            let footerY = interiorH + gap                                    // flush beneath the last grid row
            let cardY = footerY + ch * 2.0 / 3.0 + gap                       // the card stays put → the freed half is a HIDDEN-CELL GAP between the footer and the card (Paul 2026-09-09)
            // The lower region = everything under the ferry row: the 4-row grid on top, then the footer, then the docked
            // CARD filling the rest (the freed space from 8→4 rows).
            let lowerH = max(interiorH, g.size.height - 2 * pad - ch - gap)
            VStack(alignment: .leading, spacing: gap) {
                HStack(spacing: gap) {                                      // the PLAY-ferry row (transport moved to the header play strip — Paul 2026-09-09)
                    Color.clear.frame(width: railW, height: ch)              // left rail slot — keeps the ferries aligned with the grid's left rail
                    ForEach(0..<8, id: \.self) { c in roomsPlayFerry(c).frame(width: ferryW, height: ch) }   // ALWAYS 8 ferries (the play layer), widening to fill when the part is 16 wide (Paul 2026-09-04)
                    Color.clear.frame(width: railW, height: ch)              // right rail slot
                }
                ZStack(alignment: .topLeading) {                           // the lower region: the 4-row grid on top, the docked CARD beneath
                    VStack(alignment: .leading, spacing: gap) {
                        HStack(alignment: .top, spacing: gap) {             // body: LEFT chevron rail | interior+playhead | RIGHT numbered rail (Paul 2026-09-08 — rails swapped)
                            VStack(spacing: gap) { ForEach(0..<rows, id: \.self) { n in roomsPartRightRail(n).frame(width: railW, height: rowH) } }   // LEFT = chevron (row-select for playback)
                            ZStack(alignment: .topLeading) {
                                VStack(spacing: gap) { ForEach(0..<rows, id: \.self) { r in
                                    if buildRowGenConfirm?.row == r {   // just MUTATE/RANDOM'd this row → KEEP | TRY AGAIN, same place/style (Paul 2026-09-11)
                                        roomsRowConfirmInline(r, random: buildRowGenConfirm?.random ?? true, cw: cw, gap: gap, cols: cols, rowH: rowH)
                                    } else if r == buildGridSelStampSourceRow && buildRowMachine(r) == nil {   // selected EMPTY row → 4 in-row creator buttons (Paul 2026-09-10)
                                        roomsRowCreatorInline(r, cw: cw, gap: gap, cols: cols, rowH: rowH)
                                    } else {
                                        HStack(spacing: gap) { ForEach(0..<cols, id: \.self) { c in roomsPartCell(c, r, w: cw, h: rowH) } }
                                    }
                                } }
                                roomsPartSelectionOverlay(colW: cw, gap: gap, rowH: rowH)   // ONE outline around each contiguous selected run (Paul 2026-09-10)
                                roomsPartPlayhead(colW: cw, gap: gap, rowH: rowH).allowsHitTesting(false)
                            }
                            .contentShape(Rectangle())
                            .coordinateSpace(name: "partInt")
                            .gesture(DragGesture(minimumDistance: 0, coordinateSpace: .named("partInt"))   // TAP + DRAG select (empty cells too, Paul 2026-09-02)
                                .onChanged { g in buildPartGridDrag(g.location, cw: cw, ch: rowH, gap: gap, cols: cols) }
                                .onEnded { _ in buildPartDragLast = nil; buildPartDragAnchor = nil })
                            VStack(spacing: gap) { ForEach(0..<rows, id: \.self) { n in roomsSideButton(n, part: true).frame(width: railW, height: rowH) } }   // RIGHT = numbered (the part-position selector / copy source)
                        }
                    }
                    // The footer row (Paul 2026-09-08): flush BENEATH the grid rows, spanning the interior body (rails excluded).
                    roomsGridFooter(cells: cols, railW: railW, gap: gap, h: footerH)
                        .frame(width: cw * CGFloat(cols + 2) + gap * CGFloat(cols + 1), height: footerH).offset(y: footerY)   // PART = column-loop buttons (placeholder, not wired)
                    // The processor-editor card (Paul 2026-09-08): docked BELOW the footer (no longer covering it), filling
                    // the rest of the freed lower half. Spans the FULL grid-region width (every rail + interior cell).
                    roomsProcessorCardAt(x: 0, y: cardY, w: cw * CGFloat(cols + 2) + gap * CGFloat(cols + 1), h: max(0, lowerH - cardY))
                }
            }
            .padding(pad)
            // NO full-region background (Paul 2026-09-10): the cells, rails, footer + docked card each carry their own —
            // a region-wide panel here (a leftover from the taller 8-row grid) DOUBLED with the card's own background in the
            // large lower area, reading as two overlapping shades in the bottom-left.
        }
    }
    // SECTION 1 — THE PIANO ROLL (Paul 2026-09-03, rev 6 — 8-STEP SCROLLING + a CAMERA vertical axis): the accurate continuous
    // roll (true LIVE output from partRollNotes / the PartRollDeck tap — real note geometry, real-duration horizontal bars),
    // ZOOMED to a WINDOW 8 STEPS wide that SCROLLS with a CENTRED playhead (4 steps back, 4 ahead; notes wrap across the loop
    // so it's seamless). The vertical axis is a CAMERA that smoothly PANS + ZOOMS to fit the notes in view: the centre is the
    // weighted-mean pitch, the zoom the weighted spread (each note weighted by how much it overlaps the window). Because that's
    // a continuous function of the scroll, the axis is STILL on a sustained chord and eases to re-frame only when the pitch
    // content actually shifts — a stylish "the view follows the music" scale, floored to 1.5 octaves. Notes stay horizontal
    // (accurate); outliers pin to the edge. Each visible STEP is framed in the SELECTED cell's machine; a note blooms under the
    // playhead. No keyboard gutter.
    // The CAMERA fit for the part roll — weighted mean μ (pan) + weighted spread σ (zoom) over the notes overlapping the
    // window. The overlap-fraction weight tapers to 0 at the edges, so a note entering ramps its influence smoothly → the
    // axis eases (no per-frame @State needed — it's a continuous function of the scroll). A faint anchor at C4 regularises
    // the empty window (μ→60, no divide-by-zero jump). win = ±2σ + pad, floored to 1.5 octaves, capped at 4. (Not in a
    // ViewBuilder, so the loop is legal here.)
    private func partRollCamera(_ notes: [PartRollDeck.Note], winStart: Double, winEnd: Double, cyc: Double) -> (mu: Double, pLoF: Double, win: Double) {
        var wsum = 0.5, msum = 0.5 * 60, m2 = 0.5 * 3600
        for n in notes {
            for off in [-cyc, 0, cyc] {
                let ov = min(n.end + off, winEnd) - max(n.start + off, winStart)
                if ov <= 0 { continue }
                let p = Double(n.note); wsum += ov; msum += ov * p; m2 += ov * p * p
            }
        }
        let mu = msum / wsum
        let sd = max(0, m2 / wsum - mu * mu).squareRoot()
        let win = min(54.0, max(30.0, 4.0 * sd + 6.0))   // min 2.5 octaves (less zoomed-in — Paul 2026-09-03), cap 4.5
        return (mu, mu - win / 2, win)
    }
    // SECTION 2 — THE AUTO FLOW (Paul 2026-09-01, rev 2): AUTO-lane + PROCESSOR selector buttons over a PARAMETER TABLE
    // (each param + BEFORE/AFTER — a lane alters MULTIPLE params as a GROUP), + a right stack MERGE · RATE · APPLY. Macros
    // dropped (v2). Per-machine lanes. FLAGGED next stage: the APPLY grid-paint of the extent + the per-cell engine fold.
    func buildAutoLanesFor(_ cid: String) -> [AutoLane] {
        let a = buildAutoLanes[cid]?.lanes ?? []
        return (0..<5).map { $0 < a.count ? a[$0] : AutoLane() }
    }
    // AUTO RETIRED FROM THE GUI (Paul 2026-09-11): the span-automation UI is gone — its job moves to an LFO processor. Forcing
    // −1 inerts every live AUTO surface at once (hollow cells · amber extent wash · "AUTO N" label · span-draw drag · the ring
    // fade) AND removes the AUTO trigger from the per-step fold. The engine/model (partAuto, applyAuto, AutoLane) is left
    // DORMANT (no active lane ⇒ no fold) — revertible; the orphaned panel roomsPartMacroSection is already unmounted.
    func buildAutoActive() -> Int { -1 }
    // (buildLiveStepNeeded removed Paul 2026-09-11: the processor-editor matrices/lanes/passgate + the stage-eye now SELF-CLOCK
    //  their playheads from the free-running beat anchor, so NOTHING needs the live step folded into the whole-page `d` — the
    //  per-step fold that re-rendered the page every step, hitching every playhead, is gone. The VC poll no longer reads it.)
    func buildAutoSetActive(_ i: Int) {
        let cid = ddSelectedMachineID ?? ""; guard !cid.isEmpty else { return }
        var pa = buildAutoLanes[cid] ?? PartAutoMachine()
        if pa.lanes.count < 5 { pa.lanes += Array(repeating: AutoLane(), count: 5 - pa.lanes.count) }
        // DEFAULT SPAN ON ARM (Paul 2026-09-04): arming a lane with no span yet applies a WHOLE-PART sweep immediately, so
        // the automation is audible at once (drag on the grid to draw a tighter span). span-only: no punch step needed.
        if i >= 0, i < 5, pa.lanes[i].spanStart == nil, pa.lanes[i].spanLen == nil {
            pa.lanes[i].spanStart = 0; pa.lanes[i].spanLen = buildPartCols
        }
        pa.activeLane = i; buildAutoLanes[cid] = pa
        buildPublishScene()   // P3: selecting a lane ENABLES it → republish so it plays immediately
    }
    func buildSetAutoLane(_ mutate: (inout AutoLane) -> Void) {
        let cid = ddSelectedMachineID ?? ""; guard !cid.isEmpty else { return }
        var pa = buildAutoLanes[cid] ?? PartAutoMachine()
        if pa.lanes.count < 5 { pa.lanes += Array(repeating: AutoLane(), count: 5 - pa.lanes.count) }
        let li = pa.activeLane >= 0 ? pa.activeLane : 0
        mutate(&pa.lanes[max(0, min(4, li))]); buildAutoLanes[cid] = pa
        buildPublishScene()   // P3: any lane edit (param/machine/extent) republishes → plays live
    }
    // THE SPAN LADDER (Paul 2026-09-04): the AUTO panel's right ~20% column. Row 1 = 1…8 STEPS (re-anchor the FROM→TO
    // sweep every N steps), row 2 = ×2/×4/×8 PASSES (every 2/4/8 bars). "1" is one full sweep (the engine treats span<2
    // as FULL — re-anchoring every single step would leave no ramp). GREYED for on/off params — SPAN can't apply to a
    // binary value.
    @ViewBuilder private func autoSpanColumn(p: MacroControlParam, lane: AutoLane) -> some View {
        let na = p.kind.isToggle
        let cur = lane.spanLen ?? buildPartCols          // the span LENGTH in steps (span-only); default = the whole part
        let passes = lane.spanPasses ?? 0                 // ×N passes = span N whole bars (render-time, Phase 2); 0 = a step-length span
        let isCont: Bool = { if case .continuous = p.kind { return true } else { return false } }()   // SMOOTH only interpolates continuous params
        let renderable = AutoParamField(key: p.key) != nil   // scalar params only reach the render-time engine; nested (intervals/split) stay step-bake
        VStack(alignment: .leading, spacing: 4) {
            macroColHead("SPAN")
            HStack(spacing: 3) {                                         // 1…8 STEPS — the span length (or DRAG on the grid to draw it)
                ForEach(1...8, id: \.self) { n in                        // mutually exclusive with ×N passes: picking a step length clears passes
                    autoSpanChip("\(n)", on: passes == 0 && cur == n) { buildSetAutoLane { $0.spanLen = n; $0.spanPasses = nil; if $0.spanStart == nil { $0.spanStart = 0 } } }
                }
            }
            HStack(spacing: 3) {                                         // ×2 / ×4 / ×8 PASSES — span N whole bars, ramps per pass (render-time)
                ForEach([2, 4, 8], id: \.self) { m in                    // mutually exclusive with the 1…8 ladder: picking passes clears spanLen
                    autoSpanChip("×\(m)", on: passes == m) { buildSetAutoLane { $0.spanPasses = ($0.spanPasses == m ? nil : m); $0.spanLen = nil; if $0.spanStart == nil { $0.spanStart = 0 } } }
                }
            }
            .opacity(renderable ? 1 : 0.3).allowsHitTesting(renderable)   // ×N is render-time only — greyed for nested params (step-length spans still work)
            HStack(spacing: 3) {                                         // STEP | SMOOTH — stepped per-column vs a continuous ramp (render-time; SMOOTH continuous-only)
                autoSpanChip("STEP", on: !lane.smooth) { buildSetAutoLane { $0.smooth = false } }
                autoSpanChip("SMOOTH", on: lane.smooth) { if isCont && renderable { buildSetAutoLane { $0.smooth = true } } }
                    .opacity(isCont && renderable ? 1 : 0.3).allowsHitTesting(isCont && renderable)
            }
        }
        .opacity(na ? 0.3 : 1)                                           // GREYED for on/off params (SPAN can't apply to a binary value)
        .allowsHitTesting(!na)
        .overlay(alignment: .topTrailing) { if na { Text("n/a").font(.system(size: 8, weight: .heavy, design: .monospaced)).foregroundColor(.white.opacity(0.45)) } }
    }
    @ViewBuilder private func autoSpanChip(_ t: String, on: Bool, _ tap: @escaping () -> Void) -> some View {
        Text(t).font(.system(size: 9, weight: .bold, design: .monospaced)).lineLimit(1).minimumScaleFactor(0.7)
            .frame(maxWidth: .infinity).frame(height: 20)
            .background(RoundedRectangle(cornerRadius: 4).fill(on ? buildSelHue.opacity(0.28) : Color.white.opacity(0.06)))
            .overlay(RoundedRectangle(cornerRadius: 4).stroke(on ? buildSelHue : Color.white.opacity(0.15), lineWidth: on ? 1.5 : 1))
            .foregroundColor(on ? buildSelHue : .white.opacity(0.6))
            .contentShape(Rectangle()).onTapGesture(perform: tap)
    }
    // §AUTO TAB (Paul 2026-09-02): the AUTO 1–5 + NONE selector reads as TABS — a top-rounded cell with a bottom ACCENT
    // underline (amber when active, a faint baseline when not), sitting over the controls it reveals. The active-cell dot
    // marks a lane that already holds an extent.
    @ViewBuilder private func autoTab(_ t: String, on: Bool, dot: Bool, _ tap: @escaping () -> Void) -> some View {
        let tabHue = buildSelHue   // AUTO tabs wear the machine of the MACHINE the automation is applied to (Paul 2026-09-04)
        VStack(spacing: 0) {
            HStack(spacing: 4) {
                if dot { Circle().fill(tabHue).frame(width: 4, height: 4) }
                Text(t).font(.system(size: 10, weight: on ? .heavy : .semibold, design: .monospaced))
                    .foregroundColor(on ? tabHue : .white.opacity(0.5)).lineLimit(1)
            }
            .frame(maxWidth: .infinity).frame(height: 22)
            .background(UnevenRoundedRectangle(topLeadingRadius: 5, topTrailingRadius: 5).fill(on ? tabHue.opacity(0.16) : Color.white.opacity(0.04)))
            Rectangle().fill(on ? tabHue : Color.white.opacity(0.12)).frame(height: on ? 2 : 1)   // the tab underline / baseline
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
    // A SWEEP endpoint (FROM / TO), rendered with the control APPROPRIATE to the param kind (Paul 2026-09-04): a slider
    // ONLY for a continuous value; a toggle gets an ON/OFF button (a bypass is never a slider), an option gets a
    // tap-to-cycle chip, a stepper gets ◀ n ▶, a mask falls back to a raw slider.
    @ViewBuilder private func autoSweepEndpoint(_ label: String, value: Double, p: MacroControlParam, _ set: @escaping (Double) -> Void) -> some View {
        switch p.kind {
        case .continuous(let lo, let hi):
            autoRangeFader(label, value: value, lo: lo, hi: hi, p: p, set)
        case .toggle:
            autoSweepButton(label, text: value >= 0.5 ? "ON" : "OFF", on: value >= 0.5) { set(value >= 0.5 ? 0 : 1) }   // tap = flip
        case .option(let opts):
            let i = min(max(0, opts.count - 1), max(0, Int(value.rounded())))
            autoSweepButton(label, text: opts.indices.contains(i) ? opts[i] : "\(i)", on: true) { set(Double((i + 1) % max(1, opts.count))) }   // tap = cycle
        case .stepper(let lo, let hi):
            autoSweepStepper(label, value: Int(value.rounded()), lo: lo, hi: hi, set)
        case .mask(let bits):
            autoRangeFader(label, value: value, lo: 0, hi: Double((1 << max(1, bits)) - 1), p: p, set)   // rare — raw packed int
        }
    }
    @ViewBuilder private func autoSweepButton(_ label: String, text: String, on: Bool, _ tap: @escaping () -> Void) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label).font(.system(size: 8, weight: .heavy, design: .monospaced)).tracking(1.5).foregroundColor(.white.opacity(0.42))
            Text(text).font(.system(size: 10, weight: .heavy, design: .monospaced)).lineLimit(1).minimumScaleFactor(0.7)
                .frame(maxWidth: .infinity).frame(height: 24)
                .background(RoundedRectangle(cornerRadius: 4).fill(on ? buildSelHue.opacity(0.22) : Color.white.opacity(0.06)))
                .overlay(RoundedRectangle(cornerRadius: 4).stroke(on ? buildSelHue : Color.white.opacity(0.15), lineWidth: 1))
                .foregroundColor(on ? buildSelHue : .white.opacity(0.75))
                .contentShape(Rectangle()).onTapGesture(perform: tap)
        }.frame(maxWidth: .infinity)
    }
    @ViewBuilder private func autoSweepStepper(_ label: String, value: Int, lo: Int, hi: Int, _ set: @escaping (Double) -> Void) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label).font(.system(size: 8, weight: .heavy, design: .monospaced)).tracking(1.5).foregroundColor(.white.opacity(0.42))
            HStack(spacing: 0) {
                Text("◀").font(.system(size: 11, weight: .black)).frame(width: 22, height: 24).contentShape(Rectangle()).onTapGesture { set(Double(max(lo, value - 1))) }
                Text("\(value)").font(.system(size: 10, weight: .heavy, design: .monospaced)).frame(maxWidth: .infinity)
                Text("▶").font(.system(size: 11, weight: .black)).frame(width: 22, height: 24).contentShape(Rectangle()).onTapGesture { set(Double(min(hi, value + 1))) }
            }
            .frame(maxWidth: .infinity).frame(height: 24)
            .background(RoundedRectangle(cornerRadius: 4).fill(Color.white.opacity(0.06)))
            .foregroundColor(.white.opacity(0.85))
        }.frame(maxWidth: .infinity)
    }
    // SWEEP STATE (Paul 2026-09-04): a live picture of the sweep below the FROM/TO row — the FROM→TO ramp drawn as a line
    // with endpoint dots (updates as you drag FROM/TO), plus a PLAYHEAD marker riding the ramp at the cell currently being
    // swept while the part plays. Shape = up-ramp / down-ramp / flat at a glance; playhead = where the sweep is right now.
    @ViewBuilder private func autoSweepState(p: MacroControlParam, from: Double, to: Double) -> some View {
        let full = BuildSceneLogic.autoParamFullRange(p.kind)
        let span = max(1e-9, full.hi - full.lo)
        let f = min(1, max(0, (from - full.lo) / span)), t = min(1, max(0, (to - full.lo) / span))
        let playFrac: Double? = {                                   // the currently-swept cell's ramp position (0…1) while playing
            guard d.playing && buildStagingPlaying else { return nil }
            let col = max(0, min(Snap.maxCols - 1, d.effColumn))
            guard col < buildStagingSel.count else { return nil }
            let rung = buildStagingSel[col]; guard rung >= 0 else { return nil }
            return buildAutoRampFrac(col * Snap.rows + rung)
        }()
        ZStack {
            RoundedRectangle(cornerRadius: 4).fill(Color.white.opacity(0.06))
            Canvas { ctx, size in
                let pad: CGFloat = 6
                func y(_ frac: Double) -> CGFloat { pad + (size.height - 2 * pad) * CGFloat(1 - frac) }
                let x0 = pad, x1 = size.width - pad
                var line = Path(); line.move(to: CGPoint(x: x0, y: y(f))); line.addLine(to: CGPoint(x: x1, y: y(t)))
                ctx.stroke(line, with: .color(buildSelHue.opacity(0.9)), style: StrokeStyle(lineWidth: 2, lineCap: .round))
                ctx.fill(Path(ellipseIn: CGRect(x: x0 - 3, y: y(f) - 3, width: 6, height: 6)), with: .color(buildSelHue))
                ctx.fill(Path(ellipseIn: CGRect(x: x1 - 3, y: y(t) - 3, width: 6, height: 6)), with: .color(buildSelHue))
                if let pf = playFrac {                              // the PLAYHEAD — where on the ramp the sweep is right now
                    let px = x0 + (x1 - x0) * CGFloat(pf), py = y(f + (t - f) * pf)
                    ctx.fill(Path(ellipseIn: CGRect(x: px - 4, y: py - 4, width: 8, height: 8)), with: .color(.white))
                    ctx.stroke(Path(ellipseIn: CGRect(x: px - 4, y: py - 4, width: 8, height: 8)), with: .color(buildSelHue), lineWidth: 1.5)
                }
            }
        }.frame(height: 30).frame(maxWidth: .infinity)
    }
    @ViewBuilder private func macroColHead(_ t: String) -> some View {
        Text(t).font(.system(size: 8.5, weight: .heavy, design: .monospaced)).tracking(2).foregroundColor(buildSelHue.opacity(0.85))   // the AUTO section's row headers wear the SELECTED machine (Paul 2026-09-04)
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
    // (SPAN-ONLY, Paul 2026-09-04: the old PUNCH context/toggle — buildAutoArmedParam / buildAutoToggle — are retired;
    // a lane's extent is now a drawn SPAN, drag-authored in buildPartGridDrag.)
    // SPAN-ONLY (Paul 2026-09-04): a cell HAS the automation applied iff it is the SELECTED machine's cell and its column is
    // at/after the span start (the span tiles rightward across the row). Drives the "AUTO N" label + the amber highlight.
    func buildAutoInExtent(_ idx: Int) -> Bool {
        let active = buildAutoActive(); guard active >= 0 else { return false }
        let col = idx / Snap.rows, row = idx % Snap.rows
        guard col < buildStagingCells.count, row < buildStagingCells[col].count,
              buildStagingCells[col][row] == ddSelectedMachineID else { return false }   // the AUTOMATED machine's cell only
        let start = max(0, buildAutoLanesFor(ddSelectedMachineID ?? "")[max(0, min(4, active))].spanStart ?? 0)
        return col >= start
    }
    // A cell's ramp position (0…1) WITHIN its span tile — rank = (col − start) mod len — so the STATE playhead + any
    // per-cell shading read the tiling sweep. nil = before the span / no lane.
    func buildAutoRampFrac(_ idx: Int) -> Double? {
        let active = buildAutoActive(); guard active >= 0 else { return nil }
        let lane = buildAutoLanesFor(ddSelectedMachineID ?? "")[max(0, min(4, active))]
        let col = idx / Snap.rows
        let start = max(0, lane.spanStart ?? 0), len = max(1, lane.spanLen ?? buildPartCols)
        guard col >= start else { return nil }
        let rank = (col - start) % len
        return len > 1 ? Double(rank) / Double(len - 1) : 1
    }
    // SHARED grid-cell body (Paul 2026-08-30 machine language): a DARK neutral STAGE (so the vivid EMITTER drift pops) + a
    // faint MACHINE-hue identity WASH + the sweep + a MACHINE-hue FRAME that's dim normally and BRIGHT when this cell's
    // machine is the one FOCUSED in the machine strip/card (abundantly-clear cell↔machine pairing). The rung-SELECTED state
    // reads as a brighter wash + a medium frame (it's the one that plays — the drift already confirms it).
    @ViewBuilder private func roomsGridCellBody<S: View>(id: String?, selected: Bool, fade: Bool = true, hollow: Bool = false, flatFill: Color? = nil, flatFrame: Color? = nil, @ViewBuilder sweep: () -> S) -> some View {
        let mHue = id.flatMap { machineHue($0) } ?? buildCell            // the machine's identity hue
        // FOCUS = the machine shown in the strip/card. While a SELECT ferry is aimed the shown machine is the transient
        // gsAud, so ALSO pair the MIRRORED part row's REAL machine (#6, Paul 2026-08-30) — else that row's cells, whose id is
        // the real machine, never light focused during ferry editing even though the card is editing them.
        let mirrorCid = buildFerryMirrorRow.flatMap { buildRowMachine($0) }
        let focused = id != nil && (id == ddSelectedMachineID || (mirrorCid != nil && id == mirrorCid))
        // fade=false = the PART grid's UNIFORM look (Paul 2026-09-03): NOTHING is dimmed AND the machine-in-view FOCUS
        // highlight is suppressed — EVERY populated cell reads at full brightness; the ONLY per-cell mark is the selected
        // rung's white outline (added by the caller). So focusing a machine (e.g. tapping the numbered side rail) loads it
        // into the editor/strip WITHOUT lighting its cells on the grid.
        let lit = selected || !fade
        let showFocus = fade && focused
        // PART GRID (Paul 2026-09-05): a populated cell is a FLAT, DARK, FIXED-ROW machine + a row-machine frame — no wash/
        // opacity math, no focus brighten (flatFill supplied). Empty/HOLLOW cells stay the dark stage. Otherwise (SELECT
        // audition etc.) the legacy machine-hue wash.
        let useFlat = flatFill != nil && id != nil && !hollow
        RoundedRectangle(cornerRadius: 5).fill(buildCell)                // DARK STAGE
            .overlay(RoundedRectangle(cornerRadius: 5).fill(useFlat ? flatFill! : mHue.opacity(id == nil || hollow ? 0 : (lit ? 0.30 : 0.13))))   // FLAT row machine, or the machine-hue wash
            .overlay { sweep() }                                        // the EMITTER-coloured constellation
            .clipShape(RoundedRectangle(cornerRadius: 5))
            .overlay(RoundedRectangle(cornerRadius: 5).stroke(useFlat ? (flatFrame ?? buildEdge) : (id == nil ? buildEdge : mHue.opacity(showFocus ? 1.0 : (lit ? 0.7 : 0.4))),
                                                              lineWidth: useFlat ? 1.5 : (showFocus ? 2.5 : (lit ? 2 : 1))))   // ROW-machine frame (part) / MACHINE-HUE FRAME (else)
            .overlay { if buildSelectMode && id != nil { RoundedRectangle(cornerRadius: 5).stroke(Color.white, lineWidth: 2.5) } }   // SELECT MODE: light white — tap to focus (Paul 2026-08-31)
    }
    // A PART interior cell — RENDERING ONLY (Paul 2026-09-02): the whole grid is DIMMED except the SELECTED rung; taps +
    // DRAGS are handled by ONE gesture on the interior (buildPartGridDrag), so empty cells are selectable and a drag paints
    // the selection. Selected = a bright WHITE outline (works for empty OR populated). Punch mode keeps its amber extent look.
    @ViewBuilder private func roomsPartCell(_ c: Int, _ r: Int, w: CGFloat, h: CGFloat) -> some View {
        let id = (c < buildStagingCells.count && r < buildStagingCells[c].count) ? buildStagingCells[c][r] : nil   // Rooms4: bounds-safe against a ragged decoded doc
        let selected = (c < buildStagingSel.count ? buildStagingSel[c] : -1) == r   // the ONE selected rung for column c
        let idx = c * Snap.rows + r
        // When an AUTO tab is selected, every cell that ISN'T the selected rung loses its face machine (drops to the
        // background) but keeps its border — so the sweep's target rung stands out. (Paul 2026-09-04)
        let hollow = buildAutoActive() >= 0 && !selected
        let cellBody = roomsGridCellBody(id: id, selected: selected, fade: false, hollow: hollow,   // PART grid: NOTHING dimmed — every cell at full brightness (Paul 2026-09-03)
                          flatFill: partFerryFill(r), flatFrame: partFerryFrame(r),   // P2b (Paul 2026-09-09): the 4 rows are the ACTIVE ferry's colour in darkening SHADES (was fixed-by-position)
                          sweep: { EmptyView() })   // NO piano-roll notes on the part cells (Paul 2026-09-09: lose them altogether) — the cell is its ferry-shade tile + state rings
        // THE SELECTED RUNG IS ALWAYS A WHITE OUTLINE (Paul 2026-09-04): drawn LAST, on top of everything (incl. the amber
        // punch look), so it is always clear + legible and NEVER becomes another machine. It fades only VERY slightly while
        // an AUTO tab is armed, so the amber extent editing can still read underneath.
        let laneActive = buildAutoActive()
        let inExtent = laneActive >= 0 && buildAutoInExtent(idx)   // this cell HAS the automation applied
        ZStack {
            if inExtent {                                               // AUTOMATED cell (span-only): the span tiles across the row → amber wash + border
                cellBody
                    .overlay { RoundedRectangle(cornerRadius: 5).fill(roomsAmber.opacity(0.30)) }
                    .overlay(RoundedRectangle(cornerRadius: 5).stroke(roomsAmber, lineWidth: 2))
            } else {
                cellBody
            }
            // (The selected-rung VELOCITY FLASH is now drawn in roomsPartPlayhead's single loop — Paul 2026-09-11 — not a
            // per-cell TimelineView here, which spawned 8–16 always-on 30 fps loops and stuttered the playhead.)
            // (The edited-row dashed keyline is removed — Paul 2026-09-09: the machine box already matches the focused
            // row's colour, so the extra marker was redundant + confusing.)
            // AUTOMATION APPLIED → the lane label "AUTO N" on every extent cell (replaces the old dot).
            if inExtent {
                Text("AUTO \(laneActive + 1)").font(.system(size: 8, weight: .heavy, design: .monospaced)).lineLimit(1).minimumScaleFactor(0.55)
                    .foregroundColor(.white).shadow(color: .black.opacity(0.8), radius: 1).padding(.horizontal, 2)
                    .allowsHitTesting(false)
            }
            // (The selected-rung WHITE ring is now drawn by roomsPartSelectionOverlay — ONE outline around a contiguous
            //  run of selected cells in a row, not a per-cell ring — Paul 2026-09-10.)
        }
        .frame(width: w, height: h)
    }
    // THE PART GRID GESTURE (Paul 2026-09-02): ONE drag over the interior handles tap AND drag selection — so empty cells
    // select too and a drag PAINTS the per-column rung. Maps the finger to (col,row); acts once per cell entered. Punch mode
    // toggles this machine's extent; SELECT mode focuses; otherwise the FIRST cell tap-toggles the rung (deselect if it was
    // the selected one) and subsequent dragged cells paint-select. (buildPartDragLast @State lives in the VC struct.)
    func buildPartGridDrag(_ loc: CGPoint, cw: CGFloat, ch: CGFloat, gap: CGFloat, cols: Int) {
        let c = Int(loc.x / (cw + gap)), r = Int(loc.y / (ch + gap))
        guard c >= 0, c < cols, r >= 0, r < 8 else { return }
        if buildRowGenConfirm?.row == r { return }   // this row shows KEEP | TRY AGAIN, not cells — its buttons own the touch
        buildKeepRowGen()                            // touching any OTHER row's cells acts as KEEP (Paul 2026-09-11)
        let key = c * 100 + r
        let first = buildPartDragLast == nil
        // SPAN DRAW (Paul 2026-09-04, span-only): while an AUTO lane is armed (and not SELECT mode), the drag DRAWS the
        // automation SPAN — press column = the anchor, current column = the other end. It fills live as you drag; a single
        // tap = a 1-column span. Needs the drag ANCHOR (@State), so it lives here rather than in the pure partGridTap.
        if buildAutoActive() >= 0 && !buildSelectMode {
            if first { buildPartDragAnchor = c }
            let a = buildPartDragAnchor ?? c
            let start = min(a, c), len = abs(c - a) + 1
            buildSetAutoLane { $0.spanStart = start; $0.spanLen = len; $0.spanPasses = nil }   // drawing a step span = step mode (clears ×N passes)
            buildPartDragLast = key
            return
        }
        guard key != buildPartDragLast else { return }                  // act ONCE per cell entered
        buildPartDragLast = key
        let cid = (c < buildStagingCells.count && r < buildStagingCells[c].count) ? buildStagingCells[c][r] : nil
        let cur = c < buildStagingSel.count ? buildStagingSel[c] : -1
        // ONE pure decision (BuildSceneLogic.partGridTap) — rung selection / SELECT-mode focus; empty cells stay selectable.
        switch BuildSceneLogic.partGridTap(col: c, row: r, currentRung: cur, cid: cid, selectedMachineID: ddSelectedMachineID,
                                           selectMode: buildSelectMode, firstTapOfGesture: first) {
        case .focus(let fid): buildSelectID(fid); buildSelectMode = false
        case .exitSelectMode: buildSelectMode = false
        case .deselect:
            buildPartTouched = true; if c < buildStagingSel.count { buildStagingSel[c] = -1 }; buildStagingSyncIfPlaying()
        case .selectRung(let row):
            buildPartTouched = true; if c < buildStagingSel.count { buildStagingSel[c] = row }; buildStagingSyncIfPlaying()
        }
    }
    // The RIGHT rail — selects the ENTIRE row (every column → this row), like the old gui's row-select. Lights when the
    // whole row is the current per-column selection. (Paul 2026-08-28)
    @ViewBuilder private func roomsPartRightRail(_ n: Int) -> some View {
        let rowSel = buildStagingSel.allSatisfy { $0 == n }
        let rowSelectedAny = buildStagingSel.prefix(buildPartCols).contains(n)   // row n is the active rung in AT LEAST ONE column (Paul 2026-09-10)
        // THE LEFT RAIL = the DARK VERSION of the right rail (Paul 2026-09-09): plain dark unless the whole row is
        // selected for playback, then a DARK shade of the row's ferry colour (same hue family as the right rail, darker).
        RoundedRectangle(cornerRadius: 5).fill(rowSel ? Color(hex: mixHex(partFerryHue(n), 0x0E1116, 0.68)) : Color.white.opacity(0.05))
            .overlay(RoundedRectangle(cornerRadius: 5).stroke(rowSel ? Color.white.opacity(0.6) : buildEdge, lineWidth: 1))
            // The chevron takes the ROW's colour when the row is selected at ANY column, else stays neutral (Paul 2026-09-10).
            .overlay(Image(systemName: "chevron.right").font(.system(size: 11, weight: .bold)).foregroundColor(rowSelectedAny ? Color(hex: partFerryHue(n)) : Color.white.opacity(0.7)))   // same as the old gui's right rail
            .contentShape(Rectangle())
            .onTapGesture { buildPartTouched = true; buildSelectRow(n) }  // select the WHOLE row for playback (user edit)
    }
    // THE PART PLAYHEAD — a 2pt line sweeping the 8 interior columns, phase-locked to the beat (reuses the buildPlayhead
    // math: extrapolated beat → musical/swung column progress → x). Flexible-cell variant for the rooms grid.
    // THE PART PLAYHEAD (Paul 2026-09-10): NO LONGER a full-height line sweeping the whole grid. Instead the playhead sweeps
    // ALONG THE LENGTH of the ACTIVE CELL (the current column's selected rung) — a short line crossing that one cell's width
    // over the column's step, jumping to the next column's active cell as the sequencer advances. One TimelineView (perf).
    @ViewBuilder private func roomsPartPlayhead(colW: CGFloat, gap: CGFloat, rowH: CGFloat) -> some View {
        if d.playing && (buildStagingPlaying || buildActiveFerryPlaying) {   // follow the active ferry's play-layer line (Paul 2026-09-08), not only the old staging voice
            let sb = buildPartRate?.beats ?? stepBeats
            let cols = buildPartCols                                        // §E: the active width
            let rows = DiagView.roomsGridRows
            TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: animationsPaused)) { tl in
                let live = meters.beatAnchor + tl.date.timeIntervalSince(meters.beatAnchorAt) * meters.tempo / 60.0
                let musical = musicalOf(live, stepBeats: sb, a: max(1.0, Double(swing) / 50.0))
                let colF = sb > 0 ? musical / sb : 0
                let wrapped = colF.truncatingRemainder(dividingBy: Double(cols))
                let pcol = wrapped < 0 ? wrapped + Double(cols) : wrapped
                let c = min(cols - 1, max(0, Int(pcol)))                    // the CURRENT column
                let fract = min(1.0, max(0.0, pcol - Double(c)))           // progress ALONG that column's active cell, [0,1)
                let r = c < buildStagingSel.count ? buildStagingSel[c] : -1 // the ACTIVE cell = this column's selected rung
                // (The per-cell VELOCITY FLASH on the grid body was removed 2026-09-11 — Paul: no flashing on the main grid.
                // Velocity now flashes only on the play-ferry icons + the focused machine's play button.)
                if r >= 0 && r < rows {
                    let sweepX = CGFloat(c) * (colW + gap) + colW * CGFloat(fract)
                    let cellY = CGFloat(r) * (rowH + gap)
                    Rectangle().fill(Color.white.opacity(0.85)).frame(width: 2, height: rowH)
                        .offset(x: sweepX, y: cellY).allowsHitTesting(false)
                }
            }
        }
    }
    // THE CARD-HEADER ROW PLAYHEAD (Paul 2026-09-12): a 1-step left→right sweep over the row-`n` selector box in the
    // processor-card header — shown ONLY while THAT row is the active rung of the current column (i.e. that row of THIS part
    // is playing). Same clock/column math as roomsPartPlayhead; `fract` is the progress along the current column = one step.
    @ViewBuilder private func roomsCardRowPlayhead(_ n: Int, w: CGFloat, h: CGFloat) -> some View {
        if d.playing && (buildStagingPlaying || buildActiveFerryPlaying) {
            let sb = buildPartRate?.beats ?? stepBeats
            let cols = buildPartCols
            TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: animationsPaused)) { tl in
                let live = meters.beatAnchor + tl.date.timeIntervalSince(meters.beatAnchorAt) * meters.tempo / 60.0
                let musical = musicalOf(live, stepBeats: sb, a: max(1.0, Double(swing) / 50.0))
                let colF = sb > 0 ? musical / sb : 0
                let wrapped = colF.truncatingRemainder(dividingBy: Double(cols))
                let pcol = wrapped < 0 ? wrapped + Double(cols) : wrapped
                let c = min(cols - 1, max(0, Int(pcol)))
                let fract = min(1.0, max(0.0, pcol - Double(c)))
                let r = c < buildStagingSel.count ? buildStagingSel[c] : -1   // the current column's ACTIVE rung
                // LEADING-anchored in a FULL box-sized frame so the bar actually sweeps edge→edge (an offset inside a
                // content-sized view collapses the layout → the old version got clipped to a mid-box flash). Paul 2026-09-12.
                ZStack(alignment: .leading) {
                    Color.clear
                    if r == n {
                        Rectangle().fill(Color.white.opacity(0.9)).frame(width: 2, height: h)
                            .offset(x: max(0, min(w - 2, w * CGFloat(fract))))   // leading edge → x = w·fract, over one step
                    }
                }
                .frame(width: w, height: h, alignment: .leading)
                .allowsHitTesting(false)
            }
        }
    }
    // THE SELECTION OUTLINE (Paul 2026-09-10): a run of successive selected cells in a ROW (consecutive columns whose
    // selected rung == r) is outlined as ONE block, spanning the whole run (internal gaps bridged), instead of a white ring
    // per cell. An isolated selected cell is just a 1-cell run → a single-cell box. Drawn as an overlay so it can span gaps.
    private func roomsSelectionRuns(row r: Int, cols: Int) -> [Range<Int>] {
        var runs: [Range<Int>] = []; var start: Int? = nil
        for c in 0..<cols {
            let sel = (c < buildStagingSel.count ? buildStagingSel[c] : -1) == r
            if sel { if start == nil { start = c } }
            else if let s = start { runs.append(s..<c); start = nil }
        }
        if let s = start { runs.append(s..<cols) }
        return runs
    }
    @ViewBuilder private func roomsPartSelectionOverlay(colW: CGFloat, gap: CGFloat, rowH: CGFloat) -> some View {
        let cols = buildPartCols
        let rows = DiagView.roomsGridRows
        let ring: Color = buildAutoActive() >= 0 ? Color.white.opacity(0.8) : Color.white   // fades slightly while an AUTO tab is armed
        // FADE the select border on the row showing the MUTATE/RANDOM/CREATE/CLONE creator buttons (a selected EMPTY row) —
        // the bright ring fights those buttons; a faint outline is enough there (Paul 2026-09-10).
        let creatorRow: Int? = buildGridSelStampSourceRow.flatMap { buildRowMachine($0) == nil ? $0 : nil }
        ZStack(alignment: .topLeading) {
            ForEach(0..<rows, id: \.self) { r in
                ForEach(roomsSelectionRuns(row: r, cols: cols), id: \.self) { run in
                    RoundedRectangle(cornerRadius: 5).stroke(r == creatorRow ? ring.opacity(0.2) : ring, lineWidth: 2)
                        .frame(width: CGFloat(run.count) * colW + CGFloat(run.count - 1) * gap, height: rowH)
                        .offset(x: CGFloat(run.lowerBound) * (colW + gap), y: CGFloat(r) * (rowH + gap))
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .allowsHitTesting(false)
    }
    // TAP the PART NUMBERED rail (now on the RIGHT, Paul 2026-09-08) — it becomes the SELECTED slot (the always-one
    // selection, shared with SELECT) + the copy source, and reflects its chain in the panel. It does NOT select a grid
    // row — the CHEVRON rail (now on the LEFT, roomsPartRightRail) does that. (Paul 2026-08-28)
    private func roomsTapPartSide(_ n: Int) {
        buildRoomsSetActiveSide(n)                                      // this left button is THE selected slot (+ copy source); clears any library-cell source
        if buildRowMachine(n) != nil { buildTapMachineTab(n) }           // reflect its chain in the MIDI CHAIN panel (does NOT touch the grid rung selection)
    }
    // Entering PART: hand a running chain audition to the part voice; keep ONE left button selected (default: the
    // last-selected SELECT side button, else the first) + reflect its chain; if NO rung is selected anywhere, seed one
    // rung per column from a populated row; refresh the side faces. (Paul 2026-08-28)
    func roomsPartSetup() {
        // The row CURRENTLY PLAYING coming in from SELECT = the part row holding the auditioned machine (Paul 2026-09-02).
        let playingRow = ddSelectedMachineID.flatMap { cid in (0..<8).first { buildRowMachine($0) == cid } }
        // FOCUS IS USER-DRIVEN (Paul 2026-09-03: "the 1-8 buttons change focus by itself — fix"). Only set a default on the
        // FIRST entry (nothing focused yet); NEVER override the user's own pick on a re-entry. The side buttons are the sole
        // way focus changes (a plain tap selects any slot — populated or empty; long-press still copies).
        if buildGridSelStampSourceRow == nil {
            let focus = playingRow ?? (0..<8).first { buildRowMachine($0) != nil } ?? 0
            buildRoomsSetActiveSide(focus)
            if buildRowMachine(focus) != nil { buildTapMachineTab(focus) }
        }
        // ENTRY DEFAULT: until the user has EDITED the part grid, default the selected row to the one CURRENTLY PLAYING
        // (the SELECT audition's row), else the first populated row. Once touched, the user's own selection is respected.
        if !buildPartTouched, let pr = playingRow ?? (0..<8).first(where: { buildRowMachine($0) != nil }) {
            buildSelectRow(pr)                                         // programmatic — does NOT mark touched
        } else if buildStagingSel.allSatisfy({ $0 < 0 }) {            // (edited but nothing selected) → seed one-per-column with a default row
            let row = (0..<8).first { buildRowMachine($0) != nil } ?? (buildGridSelStampSourceRow ?? 0)
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
            // PLAY a machine with NO visible cell showing it — e.g. a part machine carried in from PART, or a ferry machine that
            // would then double the play layer (Paul 2026-08-31: "it'll be playing but the UI doesn't show that").
            if buildGridSelSel != nil { buildApplyWorkshopVoice(.chain) } else { buildApplyWorkshopVoice(.none) }
        case .part:   buildApplyWorkshopVoice(.part)     // extra = the sequenced part; audition OFF (play layer persists)
        case .play:   buildApplyWorkshopVoice(.none)     // no extra cell — just the 8 play cells
        default: break
        }
    }
    // ANY play column is running (the free-run gate + "is the play grid a voice"). Each column is independent (buildPlayColOn).
    // Option A: buildStagingPlaying is now DERIVED from buildPlayColOn[active], so "the play surface is sounding" is
    // simply any column ON — no separate staging term needed (Paul 2026-09-13).
    var buildPlayPlaying: Bool { buildPlayColOn.contains(true) }
    // Toggle ONE play column's independent playback + republish. (Paul 2026-08-29 — each play cell starts/stops on its own.)
    func buildTogglePlayColumn(_ c: Int) {
        guard c >= 0, c < buildPlayColOn.count, buildPlayColHasContent(c) else { return }
        buildPlayColOn[c].toggle()
        // Starting a play column: the play LAYER is the voice — the shared select/part audition must be OFF, else it would
        // keep sounding this chain on rows 0…7 and this column's own stop (buildPlayColOn) could never silence it (Paul 2026-08-31).
        if buildPlayColOn[c] { buildVoiceOwner = .none; au?.clearMachineSolo(); buildHostHalted = false }   // an explicit start re-enables free-run after a host halt
        buildPublishScene()
    }
    // buildSelectPlayColumn RETIRED (Paul 2026-09-12 dead-code sweep — its callers were the removed play-column ferry paths).
    // The PLAY column currently selected — its selected-rung cell's machine == buildSelID. The play-grid analogue of
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
        // ONE PATH (Paul 2026-09-13, Option A): route every ferry through buildSetFerryPlay so START-ALL actually flattens
        // background ferries (the old direct buildPlayColOn write never did → START started nothing) and STOP stops the
        // active-ferry STAGING voice too (it's derived from buildPlayColOn now, so clearing the columns clears it).
        if buildPlayColOn.contains(true) {
            for c in 0..<8 where c < buildPlayColOn.count && buildPlayColOn[c] { buildSetFerryPlay(c, on: false) }
        } else {
            for c in 0..<8 where c < buildFerryParts.count && buildFerryParts[c] != nil { buildSetFerryPlay(c, on: true, choke: false) }   // choke:false — a master start must not have group members choke each other
            au?.clearMachineSolo(); buildHostHalted = false                  // re-enable free-run after a host halt
        }
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
        buildColumnButton(buildPlayPlaying ? "STOP ALL" : "START ALL", active: buildPlayPlaying, fill: .grid, enabled: buildPlayPopulated || buildPlayPlaying || buildFerryParts.contains { $0 != nil }, fillHeight: true,   // enabled if any ferry exists (START ALL now starts ferries) or anything's playing (Paul 2026-09-13)
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
            buildNoteSweep(indices: buildPlayColSweepIndices(c), active: on, id: id, emitter: c < buildPlayColEmit.count ? buildPlayColEmit[c] : [.a])   // CONTINUOUS drift in the EMITTER machine (multi-step gathers all steps)
            roomsCellPlayhead(active: on)   // PER-CELL PLAYHEAD — the pass sweeping L→R
        })
            .contentShape(Rectangle())
            .onTapGesture {
                if c < buildPlaySel.count { buildPlaySel[c] = (buildPlaySel[c] == r) ? -1 : r }   // one rung per column, toggle
                if c < buildPlayColOn.count, buildPlayColOn[c] { buildPublishScene() }   // Rooms1: a rung change while playing must re-publish so the engine FOLLOWS the selection (was UI-only → audio stayed on the old rung / kept sounding after deselect)
            }
    }
    // A PLAY bottom-row button — column c's PER-COLUMN TRANSPORT (Paul 2026-08-29): shows the selected cell's machine + a
    // play/stop icon reflecting the column's independent state; TAP = start/stop THIS column. Empty column → inert readout.
    @ViewBuilder private func roomsPlayBottom(_ c: Int) -> some View {
        let sel = c < buildPlaySel.count ? buildPlaySel[c] : -1
        let id = (sel >= 0 && c < buildPlayCells.count && sel < buildPlayCells[c].count) ? buildPlayCells[c][sel] : nil
        let hue = id.flatMap { machineHue($0) }
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
        // PERFECTLY STILL WHENEVER THE HOST TRANSPORT IS STOPPED (Paul 2026-09-04). Gated on d.playing (the HOST), NOT
        // free-run: when the host stops but the ferry keeps sounding a held/latched chord, free-run takes over and its
        // beat jumps to 0 then advances in blocks — which is exactly the "jump to the wrong spot, jump back, jiggle" on
        // stop. Host-only means the sweep shows + runs smoothly while playing and vanishes cleanly on stop. (Same rule as
        // the machine play button.)
        if active && d.playing {
            GeometryReader { g in
                let sb = max(0.0001, stepBeats)
                let barBeats = Double(Snap.cols) * sb                // one bar = 8 steps
                TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: animationsPaused)) { tl in
                    let live = meters.beatAnchor + tl.date.timeIntervalSince(meters.beatAnchorAt) * meters.tempo / 60.0
                    let ph = (live.truncatingRemainder(dividingBy: barBeats)) / barBeats
                    let p = ph < 0 ? ph + 1 : ph                     // 0…1 across the cell over one bar
                    let x = CGFloat(p) * g.size.width
                    // P3 THE BEAT-SWEEP (Paul 2026-09-09): a bright head with a trailing glow, swept in beat-time — the
                    // ferry's playing motion (the ratified "bright line swept in time"). White so it reads on any hue.
                    ZStack(alignment: .leading) {
                        LinearGradient(colors: [.white.opacity(0), .white.opacity(0.28)], startPoint: .leading, endPoint: .trailing)
                            .frame(width: 20, height: g.size.height)
                            .position(x: x - 10, y: g.size.height / 2)          // the trail, behind the head
                        Rectangle().fill(Color.white.opacity(0.95)).frame(width: 2, height: g.size.height)
                            .position(x: x, y: g.size.height / 2)               // the bright leading edge
                    }
                    .allowsHitTesting(false)
                }
            }
        }
    }
    // VELOCITY FLASH (Paul 2026-09-11): the peak recent-strike intensity across `indices`, 0…1, decaying over ~0.28s.
    // Reads the live STRIKE feed (cellHitAt/cellHitVel on `meters`, off @State so it never re-runs the body). Meant to be
    // called INSIDE a TimelineView — one flash per note, brightness = that note's velocity, so a cell "flashes its velocity".
    private func buildFlashLevel(_ indices: [Int], now: Date) -> Double {
        var lvl = 0.0
        for idx in indices where idx >= 0 && idx < meters.cellHitVel.count {
            let age = now.timeIntervalSince(meters.cellHitAt[idx])
            if age >= 0, age < 0.28 { lvl = max(lvl, meters.cellHitVel[idx] * (1.0 - age / 0.28)) }
        }
        return lvl
    }
    // An SF-symbol ICON that FLASHES its velocity on each strike across `indices` (brighten + a subtle pulse) — used for the
    // play/stop icon on a running play ferry AND the focused machine's play button (Paul 2026-09-11: flash the ICON, not the
    // cell body). One TimelineView; reads the live strike feed (meters, off @State).
    @ViewBuilder private func flashingIcon(_ systemName: String, size: CGFloat, tint: Color, baseOpacity: Double, indices: [Int]) -> some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: animationsPaused)) { tl in
            let lvl = buildFlashLevel(indices, now: tl.date)
            Image(systemName: systemName).font(.system(size: size, weight: .black))
                .foregroundColor(tint).opacity(baseOpacity)
                .brightness(lvl * 0.6).scaleEffect(1.0 + lvl * 0.22)
        }
    }
    // (buildFerryPlayFlash + buildPartCellFlash removed 2026-09-11 — the cell-body flashes are gone; velocity now flashes the
    // play-ferry icon + the focused machine's play button via flashingIcon, and the grid body no longer flashes at all.)

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
        let key: String? = (i < receivers.count ? receivers[i].scaleLabel : nil) ?? buildChordDoorLabel(receivers, i)   // "A MIXO" (SCALE) / "A · V7" (CHORD), else nil
        buildIOSelectChip(top: key != nil ? letter : "MIDI IN", letter: key ?? letter, on: buildIONullPending ? false : on, accent: receiverGrey(i), pulse: buildIONullPending, action: { buildSelectDoor(i) }, onAll: { buildSelectDoorAll(i) })   // ON = the receiver's SIGNATURE GREY (Paul 2026-08-30); null-pending ⇒ off + pulse (Paul 2026-09-05)
    }
    // THE EMITTER (MIDI-OUT) TOGGLES — below the left column's button box. Four toggles (A–D), IDENTICAL in style to
    // the MIDI-IN receiver selector, toggling the PART's output emitters (part-owned, so every machine follows). (Paul 2026-08-18)
    @ViewBuilder private func buildEmitterToggles(castW: CGFloat) -> some View {
        HStack(spacing: 4) {
            ForEach(Array(Bus.allCases.enumerated()), id: \.offset) { _, b in
                // RELIABILITY FIX (Paul 2026-08-29): read from the SAME place buildToggleBus writes — the selected row's
                // RESOLVED emitters, else the part default (buildPartEmitters, [.a] when empty). Was a mismatched
                // buildGridSelOpen branch + a `?? false` that blanked the chips when no row was selected.
                let on = buildSelectedRow.map { buildRowEmittersResolved($0).contains(b) }
                    ?? buildSelectedPlayCol.map { ($0 < buildPlayColEmit.count ? buildPlayColEmit[$0] : [.a]).contains(b) }
                    ?? ((buildDefaultEmitters).contains(b))
                buildIOSelectChip(top: "MIDI OUT", letter: b.rawValue, on: buildIONullPending ? false : on, accent: emitterHue(b), pulse: buildIONullPending, action: { buildToggleBus(b) }, onAll: { buildToggleBusAll(b) })   // ON = the emitter's SIGNATURE machine (Paul 2026-08-30); null-pending ⇒ off + pulse (Paul 2026-09-05)
            }
        }
        .frame(width: castW)
    }
    // The shared two-line I/O chip: a small top label over a big A/B/C/D, styled like the centre column's emitter A–D
    // chips (cyan-when-on, muted idle, height 48). Used by BOTH the MIDI-IN receiver selector and the MIDI-OUT
    // emitter toggles so they read identically. (Paul 2026-08-18)
    @ViewBuilder private func buildIOSelectChip(top: String, letter: String, on: Bool, accent: Color? = nil, pulse: Bool = false, action: @escaping () -> Void, onAll: @escaping () -> Void = {}) -> some View {
        // Paul 2026-08-30: HALF height (48→24) + only the LARGER line (the letter) — the small "MIDI IN"/"MIDI OUT" caption dropped.
        Text(letter).font(.system(size: 15, weight: .black, design: .monospaced)).lineLimit(1).minimumScaleFactor(0.4)   // scale to fit a longer key label like "A MIXO"
        .foregroundColor(on ? Color.black : buildDim)
        .frame(maxWidth: .infinity).frame(height: 36)                        // +50% over the halved 24 (Paul 2026-08-30)
        .background(RoundedRectangle(cornerRadius: 7).fill(on ? (accent ?? buildCyan) : buildCell))   // ON = the accent (emitter signature machine for MIDI OUT); idle mutes
        .overlay(RoundedRectangle(cornerRadius: 7).stroke(on ? Color.clear : buildEdge, lineWidth: 1))
        // NULL invite — a STATIC cyan keyline on every unset toggle (Paul 2026-09-08: the breathe strobed; a steady mark instead).
        .overlay(Group { if pulse {
            RoundedRectangle(cornerRadius: 7).stroke(buildCyan.opacity(0.7), lineWidth: 2).allowsHitTesting(false)
        } })
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
    private func buildTapMachineTab(_ n: Int) {
        if let cid = buildRowMachine(n) {                         // a SET tab → SELECT its machine ONLY (does NOT set the playing rung — Paul 2026-08-20)
            buildSelectID(cid)                                   // the grid cells / loop keys set the rung; the row button just picks the machine to edit
            buildStagingSyncIfPlaying()
        } else {
            buildPopulateTab(n)                                  // an EMPTY tab → create/copy/place, then pulse until edited
        }
    }
    // Touch an EMPTY tab: mint tab n's machine with an EMPTY chain (NO duplication of the current settings — Paul
    // 2026-08-25), place it on row n, default its I/O to the LAST-USED receivers/emitters, select it, and mark it
    // PENDING (flashing). The flash stays until a change is made to the processors, emitters, or receivers (see
    // buildApplyChain + buildClearPendingOnEdit). Only one pending → revert the previous unedited candidate first.
    private func buildPopulateTab(_ n: Int) {
        buildRecordUndo()   // BUILD UNDO: tapping an empty row-tab mints a machine + places it on a row (U4 fix 2026-08-27)
        let sourceChain: [ProcessorSlot] = []                    // a fresh EMPTY row (was: a copy of the last-selected chain)
        if let p = buildPendingTab, p != n {                     // ONE pending → discard the previous unedited candidate
            if let old = buildRowMachine(p) { buildPartCast.removeAll { $0 == old } }
            buildSetRow(p, to: nil)
        }
        let y = buildNewTabMachine(n, machine: sourceChain)       // tab n's fixed hue + the empty chain
        buildPartCast.append(y)
        buildSetRow(n, to: y)                                    // placed on part-grid row n
        if n < buildRowReceiver.count { buildRowReceiver[n] = ddStickyReceiver; buildRowEmitters[n] = ddStickyBuses }   // DEFAULT the new row's I/O to the LAST-USED receivers/emitters (Paul 2026-08-18/25)
        for c in 0..<Snap.maxCols { buildStagingSel[c] = n }   // §E: the 16-col staging storage (width governs view/play)
        buildSelectID(y)
        buildPendingTab = n
        buildPendingSource = selectedMachineChain()               // == [] here; buildApplyChain clears the flash once the chain diverges
        buildStagingSyncIfPlaying()
    }
    // The PENDING (flashing) row ends its flash the moment the user changes its EMITTERS or RECEIVERS — the processor
    // path already clears it via buildApplyChain. Only fires while the pending row is the selected one. (Paul 2026-08-25)
    private func buildClearPendingOnEdit() {
        if let p = buildPendingTab, buildSelectedRow == p { buildPendingTab = nil; buildPendingSource = [] }
    }

    // The chain as the block's lower half: 8 processor boxes, each the size of 2×2 cast cells, laid 1·2·3·4 /
    // 5·6·7·8 with NO connectors. Empty slots read as their number (1–8); populated show the processor type.
    @ViewBuilder private func buildProcessorBlock(castW: CGFloat, cell: CGFloat, hue: Color, chainOverride: [ProcessorSlot]? = nil) -> some View {
        let chain = chainOverride ?? selectedMachineChain()   // chainOverride: force an EMPTY ghost chain for an unselectable empty row (Paul 2026-09-10)
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
        if chainDragActive, let from = buildChainDragFrom, from < chain.count, !buildIsEmptySlot(chain[from]) {   // ghost only while actively held (auto-resets — never sticks). Paul 2026-09-10
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
    // A structural signature of the selected chain (type + bypass per slot + which machine) — the comets recompute when it
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
    // buildRhythmDriverSlot RETIRED (Paul 2026-09-12 dead-code sweep — no caller).
    @ViewBuilder private func buildChainFlowOverlay(sideW: CGFloat, blockW: CGFloat, blockH: CGFloat, boxH: CGFloat, gap: CGFloat, hue: Color, chain: [ProcessorSlot]) -> some View {
        // THE FLOW COMETS ARE REMOVED (Paul 2026-09-11) — only the dotted connectors + the two flank circles remain (the
        // dotted ORDER thread through the boxes is buildChainFlowLine, kept). The circles are now LIVE VELOCITY METERS:
        // LEFT = the loudest note HELD at this machine's input door (what's going IN); RIGHT = the loudest recent EMITTED
        // note (what's coming OUT) — so the user can read what MIDI enters the machine and what leaves it. A held chord
        // fills the left circle even when the transport is stopped.
        let inVel = (buildSelReceiver >= 0 && buildSelReceiver < recvHeld.count) ? (recvHeld[buildSelReceiver].max() ?? 0) : 0
        let active = !buildChainLiveChord.isEmpty || !buildFocusNotes.isEmpty      // freeze the loop when there's no MIDI either side
        TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: animationsPaused || !active)) { tl in
            Canvas { ctx, _ in
                let cr = max(3.5, min(boxH * 0.16, sideW * 0.42))
                let lx = sideW / 2, rx = sideW + blockW + sideW / 2            // flank-column centres
                let ty = boxH / 2, by = blockH - boxH / 2                      // first / last processor rows
                // DOTTED CONNECTORS (kept) — circle ▸ block edge, both flanks.
                let dash = StrokeStyle(lineWidth: 1.5, lineCap: .round, dash: [2, 3])
                var lseg = Path(); lseg.move(to: CGPoint(x: lx + cr, y: ty)); lseg.addLine(to: CGPoint(x: sideW, y: ty))
                var rseg = Path(); rseg.move(to: CGPoint(x: sideW + blockW, y: by)); rseg.addLine(to: CGPoint(x: rx - cr, y: by))
                ctx.stroke(lseg, with: .color(hue.opacity(0.32)), style: dash)
                ctx.stroke(rseg, with: .color(hue.opacity(0.32)), style: dash)
                // OUTPUT level — the loudest recent emitted note, decaying at its real timing (a live pulse, not a flowing comet).
                let liveBeat = meters.beatAnchor + tl.date.timeIntervalSince(meters.beatAnchorAt) * meters.tempo / 60.0
                var outVel = 0.0
                for note in buildFocusNotes { let age = liveBeat - note.beat; if age >= 0, age < 0.5 { outVel = max(outVel, note.vel * (1 - age / 0.5)) } }
                // THE TWO VELOCITY CIRCLES — a fill disc that grows + brightens with velocity, over the machine-hue outline.
                func velCircle(_ c: CGPoint, _ v: Double) {
                    let lvl = min(1, max(0, v))
                    ctx.stroke(Path(ellipseIn: CGRect(x: c.x - cr, y: c.y - cr, width: 2 * cr, height: 2 * cr)), with: .color(hue.opacity(0.85)), lineWidth: 1.8)
                    let fr = cr * CGFloat(0.18 + 0.82 * lvl)
                    ctx.fill(Path(ellipseIn: CGRect(x: c.x - fr, y: c.y - fr, width: 2 * fr, height: 2 * fr)), with: .color(hue.opacity(0.28 + 0.62 * lvl)))
                }
                velCircle(CGPoint(x: lx, y: ty), inVel)      // LEFT = INPUT going into the machine
                velCircle(CGPoint(x: rx, y: by), outVel)     // RIGHT = OUTPUT coming out
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
        // DRAG ONLY (Paul 2026-09-12): the box highlights now appear only once the held box actually MOVES (buildChainDragMoved),
        // matching the delete box — a hold alone no longer lights them. chainDragActive still auto-resets so they never stick.
        let dragging = chainDragActive && buildChainDragMoved
        let isDragged = dragging && buildChainDragFrom == i
        let isDropTarget = dragging && buildChainDragFrom != i && buildChainDropTo == i
        let isDest = dragging && buildChainDragFrom != i && !isDropTarget   // during a drag, EVERY other box reads as a droppable destination (Paul 2026-09-10)
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
            else if isDest {                                       // a POTENTIAL destination while dragging — a soft dashed cyan ring + faint wash so it reads as droppable
                RoundedRectangle(cornerRadius: 8).fill(buildCyan.opacity(0.10)).frame(width: bw, height: bh)
                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(buildCyan.opacity(0.55), style: StrokeStyle(lineWidth: 2, dash: [4, 3])).frame(width: bw, height: bh))
            }
            else if populated && buildEditSlot == i {              // FOCUS (Paul 2026-09-10): the processor currently open in the card — a
                // crisp white ring + a soft white halo, drawn as an OVERLAY so the box footprint / fill / section layout are
                // untouched. Obvious where the focus sits, but stylish and quiet (static — no strobe, per Paul 2026-09-08).
                RoundedRectangle(cornerRadius: 8).stroke(Color.white, lineWidth: 2).frame(width: bw, height: bh)
                    .shadow(color: Color.white.opacity(0.6), radius: 5)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture { buildExitPlaceMode(); if populated { buildEditSlot = i } else { buildAddSlot = i } }   // quick TAP → open the editor (empty box → the ADD PROCESSOR picker)
        // IMMEDIATE DRAG (Paul 2026-09-12): a populated box enters drag mode as soon as the finger MOVES — NO long-press first.
        // The red TRASH + the droppable destination rings appear at once (gated on chainDragActive && buildChainDragMoved,
        // both set on the first move). minimumDistance 8 keeps a stationary TAP falling through to the editor (onTapGesture).
        // Drop on the trash (chainBlock x < 0) = DELETE; drop on another box = REORDER. BYPASS moved to the hold below now
        // that the drag no longer needs a hold. Empty boxes are not sources (`including: .none`) → their tap/hold reach ADD.
        .highPriorityGesture(
            DragGesture(minimumDistance: 8, coordinateSpace: .named("chainBlock"))
                // AUTO-RESETTING "actively dragging" flag — true while the drag is live; SwiftUI resets it when the gesture
                // ends OR is CANCELLED, so the trash/targets/ghost can never stick visible. Paul 2026-09-10.
                .updating($chainDragActive) { _, state, _ in if populated { state = true } }
                .onChanged { drag in
                    guard populated else { return }
                    if buildChainDragFrom == nil { buildChainDragFrom = i }   // drag just started → lift this box
                    buildChainDragMoved = true                                // a real drag is underway → reveal the trash + targets
                    buildChainDragLoc = drag.location
                    let overTrash = drag.location.x < -6                      // the trash is the LEFT flank (negative x in the box-grid space)
                    buildChainOverTrash = overTrash
                    buildChainDropTo = overTrash ? nil : buildChainTargetIndex(drag.location, boxW: w, boxH: h, gap: gap, count: chain.count)
                }
                .onEnded { _ in
                    defer { buildChainDragFrom = nil; buildChainDropTo = nil; buildChainOverTrash = false; buildChainDragMoved = false }
                    guard populated else { return }
                    if buildChainOverTrash { buildChainRemoveSlot(i); if buildEditSlot == i { buildEditSlot = nil } }   // dropped on the trash → DELETE
                    else if let to = buildChainDropTo, to != i { buildChainMoveSlot(from: i, to: to) }                  // dropped on another box → REORDER
                },
            including: populated ? .all : .none)
        // HOLD in place (Paul 2026-09-12): empty box → ADD PROCESSOR card; populated box → toggle BYPASS (moved off the drag,
        // which is now immediate). Guarded `!buildChainDragMoved` so a hold can never fire BYPASS mid-drag.
        .onLongPressGesture(minimumDuration: buildGridSelStampDur, maximumDistance: 44) {
            if !populated { buildExitPlaceMode(); buildAddSlot = i }
            else if !buildChainDragMoved { buildChainToggleBypass(i) }
        }
    }


    // §2: the INPUT door is PART-owned — one door for the whole part (every machine follows). Applied uniformly at
    // scene-build + audition; no per-machine cell fanning.
    private func buildSelectDoor(_ i: Int) {
        buildKeepRowGen()   // a toggle acts as KEEP
        buildRecordUndo()   // BUILD UNDO: pick the input door (receiver)
        buildIONullPending = false                               // Paul 2026-09-05: picking the door dismisses the fresh-cell null/pulse invitation
        buildClearPendingOnEdit()                                // a RECEIVER change ends the fresh-row flash (Paul 2026-08-25)
        if let r = buildSelectedRow, r < buildRowReceiver.count { buildRowReceiver[r] = i }   // override THIS ROW only (per-row I/O, Paul 2026-08-18)
        else if let pc = buildSelectedPlayCol, pc < buildPlayColRecv.count {   // a selected PLAY cell edits its OWN door (Paul 2026-08-30)
            buildPlayColRecv[pc] = i
            // FLATTENED-PASS FIX (Paul 2026-09-10): mirror the emitter fix — a multi-step pass plays from the PER-STEP door,
            // so update every step + persist onto the ferry part, else the door change is silent for a flattened ferry.
            if pc < buildPlayColStepRecv.count, !buildPlayColStepRecv[pc].isEmpty { buildPlayColStepRecv[pc] = buildPlayColStepRecv[pc].map { _ in max(0, min(3, i)) } }
            if pc < buildFerryParts.count, buildFerryParts[pc] != nil { buildEditFerry(pc, publish: false) { $0.receiver = i; $0.rowReceiver = nil } }
            buildPublishScene()
        }
        else { buildSelReceiver = i }                            // nothing on a row → set the part DEFAULT
        ddStickyReceiver = i                                     // a new row inherits the LAST-USED
        receivers = au?.uiReceivers() ?? receivers               // mirror so the source toggle/keyboard reflect the newly-selected door at once
        buildStagingSyncIfPlaying()                              // the row's door applies to its staging cells, live
        refreshFromDocument()
    }





    private func buildToggleBus(_ bus: Bus) {
        buildKeepRowGen()   // a toggle acts as KEEP
        buildRecordUndo()   // BUILD UNDO: toggle an output emitter
        let wasNull = buildIONullPending; buildIONullPending = false   // Paul 2026-09-05: the first emitter pick WIRES the fresh cell — build from EMPTY, not the [.a] default
        buildClearPendingOnEdit()                                // an EMITTER change ends the fresh-row flash (Paul 2026-08-25)
        let selR = buildSelectedRow
        let selPC = selR == nil ? buildSelectedPlayCol : nil       // a selected PLAY cell edits its OWN emitters (Paul 2026-08-30)
        var buses = wasNull ? [] : (selR.map { buildRowEmittersResolved($0) }
            ?? selPC.map { $0 < buildPlayColEmit.count ? buildPlayColEmit[$0] : [.a] }
            ?? (buildDefaultEmitters))
        if buses.contains(bus) { buses.remove(bus) } else { buses.insert(bus) }
        if buses.isEmpty { buses = [bus] }                        // never leave a row with no output
        if let r = selR, r < buildRowEmitters.count { buildRowEmitters[r] = buses }   // override THIS ROW only (per-row I/O, Paul 2026-08-18)
        else if let pc = selPC, pc < buildPlayColEmit.count {     // the selected play column
            buildPlayColEmit[pc] = buses
            // FLATTENED-PASS FIX (Paul 2026-09-10): a play ferry / multi-step pass (len>1) plays from the PER-STEP emitters,
            // NOT buildPlayColEmit — composeScene ignores the latter there — so re-pointing a play ferry's emitter was SILENT
            // (both same-source ferries stayed on the ORIGINAL emitter → identical output collided into one voice). Re-point
            // EVERY step of this column, and persist onto the ferry part (nil per-row overrides) so a re-flatten keeps it.
            if pc < buildPlayColStepEmit.count, !buildPlayColStepEmit[pc].isEmpty { buildPlayColStepEmit[pc] = buildPlayColStepEmit[pc].map { _ in buses } }
            if pc < buildFerryParts.count, buildFerryParts[pc] != nil { buildEditFerry(pc, publish: false) { $0.emitters = buses; $0.rowEmitters = nil } }
        }
        else { buildPartEmitters = buses }                        // nothing on a row → the part DEFAULT
        ddStickyBuses = buses                                     // a new row inherits the LAST-USED
        buildPublishScene()                                       // apply the row's output LIVE to whatever's sounding
    }
    // LONG-PRESS → apply the door to EVERY row (Paul 2026-08-19).
    private func buildSelectDoorAll(_ i: Int) {
        buildKeepRowGen()   // a toggle acts as KEEP
        if buildSelectedRow == nil, buildSelectedPlayCol != nil { buildSelectDoor(i); return }   // a play cell has no "all rows" — edit just its door (Paul 2026-08-30)
        buildRecordUndo()   // BUILD UNDO: blanket-apply the door to every row (U7 fix 2026-08-27 — the single-row sibling records; this didn't)
        buildIONullPending = false                               // Paul 2026-09-05: dismiss the fresh-cell invitation
        buildClearPendingOnEdit()                                // a RECEIVER change (all rows) ends the fresh-row flash (Paul 2026-08-25)
        for r in 0..<min(8, buildRowReceiver.count) { buildRowReceiver[r] = i }
        buildSelReceiver = i; ddStickyReceiver = i
        receivers = au?.uiReceivers() ?? receivers
        buildStagingSyncIfPlaying(); refreshFromDocument()
    }
    // LONG-PRESS → toggle the emitter on EVERY row (all rows take the reference row's toggled set). (Paul 2026-08-19)
    private func buildToggleBusAll(_ bus: Bus) {
        buildKeepRowGen()   // a toggle acts as KEEP
        if buildSelectedRow == nil, buildSelectedPlayCol != nil { buildToggleBus(bus); return }   // a play cell has no "all rows" — edit just its emitters (Paul 2026-08-30)
        buildRecordUndo()   // BUILD UNDO: blanket-apply the emitter to every row (U7 fix 2026-08-27)
        let wasNull = buildIONullPending; buildIONullPending = false   // Paul 2026-09-05: dismiss the fresh-cell invitation, build from EMPTY
        buildClearPendingOnEdit()                                // an EMITTER change (all rows) ends the fresh-row flash (Paul 2026-08-25)
        var buses = wasNull ? [] : (buildSelectedRow.map { buildRowEmittersResolved($0) } ?? (buildDefaultEmitters))
        if buses.contains(bus) { buses.remove(bus) } else { buses.insert(bus) }
        if buses.isEmpty { buses = [bus] }
        for r in 0..<min(8, buildRowEmitters.count) { buildRowEmitters[r] = buses }
        buildPartEmitters = buses; ddStickyBuses = buses
        buildPublishScene()
    }

    // The MIDI-CHAIN voice. Paul 2026-08-15: it plays the selected machine's machine RAW — behind the scenes a 1-row play
    // grid whose EVERY column is "selected", so the machine sounds on every column with NONE of the part grid's column
    // rules. It rides the SAME ephemeral scene as the part/piece (buildPublishScene injects it), so it coexists with the
    // play grid instead of owning the render via an isolating solo. `ddSolo` is just the "chain is the voice" flag now.
    func buildSelectMachineVoice() {
        buildSeedCastIfNeeded()                                  // §2: part 1's cast reflects the already-defined machines (once); selects within the cast
        ddStickyReceiver = buildSelReceiver                      // §2: the chain audition uses the PART's I/O (door + emitters)
        ddStickyBuses = buildDefaultEmitters
        // A document machine never given a chain shows an EMPTY chain but has a nil templateChain; make it an explicit []
        // once so the palette's shown-empty chain matches the raw sound (the injected cell reads buildMachineChain, which
        // is [] here → a born-audible passthrough — never the legacy A-face arp). Only fires when the chain is unstored.
        if let cid = ddSelectedMachineID, buildMachineReg[cid] == nil, au?.machineHasStoredChain(cid) == false {
            au?.withChainMachine(cid) { $0 = [] }; refreshFromDocument()   // document machine only — ephemeral machines always carry a registry machine
        }
        buildVoiceOwner = .chain                                // the chain is the voice — sounded RAW via the ephemeral scene (CHAIN ⟂ PART; the PIECE keeps sounding via the scene)
        buildPublishScene()
    }
    private func buildSelectStagingVoice() {
        au?.clearMachineSolo()                                    // CHAIN ⟂ PART: leaving the chain audition
        if buildVoiceOwner == .chain { buildVoiceOwner = .none }   // Option A: entering the bench only STOPS the chain audition — the part plays iff its ferry is ON (buildPlayColOn), never auto-started on open (Paul 2026-09-13)
        buildPublishScene()
    }

    // The LIVE workshop voice IS the single-source-of-truth owner (Paul 2026-08-31 — was derived from two booleans that
    // could drift; now the owner is authoritative and ddSolo/buildStagingPlaying are read-only mirrors of it).
    // The live workshop voice, COMPOSED from the two truths (Paul 2026-09-13, Option A): the SELECT chain audition
    // (buildVoiceOwner == .chain) OR the PART = the active ferry playing (derived). So the truth strips / headers still
    // read `.part` while a ferry plays, without buildVoiceOwner ever holding .part.
    var buildWorkshopVoice: BuildWorkshopVoice {
        if buildVoiceOwner == .chain { return .chain }
        if buildStagingPlaying { return .part }
        return .none
    }
    // Read-only mirrors so the ~40 existing reads (composeScene inputs, `if ddSolo`, UI gates) are untouched — only the
    // ~11 WRITE sites route through buildVoiceOwner now, so "who is the voice" lives in ONE place.
    var ddSolo: Bool { buildVoiceOwner == .chain }               // the SELECT chain audition
    // PLAYBACK IS ONE TRUTH (Paul 2026-09-13, "collapse" — Option A): the PART staging voice IS simply "the active ferry
    // is ON" (buildPlayColOn[active]). buildVoiceOwner no longer holds .part, so the header/ferry buttons + the free-run
    // gate can't desync from what's actually sounding, and opening a ferry no longer auto-plays it (was the two-tap-to-stop
    // + STOP-won't-stop cluster). buildStagingPlaying is now DERIVED from the play state.
    var buildStagingPlaying: Bool { buildActiveFerryPlaying }
    // THE PLAY FERRIES ARE PARTS (Paul 2026-09-08): the bench shows the ACTIVE ferry's part; playback happens on the play
    // layer, so the part-grid playhead follows the active ferry's own on/off (not the old staging voice).
    var buildActiveFerryPlaying: Bool { if let a = buildActiveFerry, a >= 0, a < buildPlayColOn.count { return buildPlayColOn[a] }; return false }
    // The DISPLAYED workshop voice: the armed target if a switch is pending, else the live one. The HEADERS read this so
    // they highlight the new state IMMEDIATELY on tap, while the MIDI still switches quantized at the boundary. (Paul 2026-08-15)
    var buildDisplayVoice: BuildWorkshopVoice { buildPendingWorkshopVoice ?? buildWorkshopVoice }

    // A header TOGGLES its section: play it if stopped, STOP it if playing (Paul 2026-08-15). Both sections can be off.
    // While the transport runs the switch is QUANTIZED to the next cell boundary (buildCommitPendingVoice, fired from the
    // VC's absoluteStep hook) so it lands on the grid, not mid-cell. Stopped, or re-requesting the live voice → immediate.
    func buildRequestWorkshopVoice(_ target: BuildWorkshopVoice) {
        buildKeepRowGen()   // playing the machine acts as KEEP
        if d.playing && target != buildWorkshopVoice {
            buildPendingWorkshopVoice = target                   // arm — applied at the next cell boundary
        } else {
            buildPendingWorkshopVoice = nil
            buildApplyWorkshopVoice(target)
        }
    }
    private func buildApplyWorkshopVoice(_ v: BuildWorkshopVoice) {
        if v != .none { buildHostHalted = false }   // an explicit PLAY re-enables free-run (audition while the host is stopped after a halt)
        switch v {
        case .chain: buildSelectMachineVoice()
        case .part:  buildSelectStagingVoice()
        case .none:  buildStopWorkshop()
        }
    }
    // Stop BOTH shop sections (the header's STOP action). The PIECE (play grid) is independent and keeps sounding.
    private func buildStopWorkshop() {
        au?.clearMachineSolo()
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
        } else if buildPendingReengage {                 // a palette machine change → re-inject the new chain machine on the boundary
            buildPendingReengage = false
            if ddSolo { buildPublishScene() }
        }
    }

    // Publish the ephemeral scene for the ACTIVE voices. §correction (2026-08-13): the PIECE is INDEPENDENT of the
    // audition — PLAY THIS PART + START/STOP THE PLAY GRID sound TOGETHER (the shopping/alongside workflow). Each
    // staging/perform cell takes its PART-owned I/O + the machine's machine (or a staged variation chain). Paul 2026-08-15:
    // the MIDI CHAIN now ALSO rides this scene (a 1-row grid, every column active → raw, no part-grid column rules), so it
    // sounds ALONGSIDE the play grid instead of owning the render via a solo.
    // The SHELL: gather @State into a pure input, let BuildSceneLogic.composeScene do the work (testable), publish it.
    // SCENES V2 (Paul 2026-08-12): capture the current play-grid ARRANGEMENT (not the shared parts/machines) into a snapshot.
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
    /// parts/machines/master stay shared (a scene arranges the same band). v1: in-memory, instant (pass-quant + persist = follow-ups).
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
                      selID: buildSelID, selReceiver: buildSelReceiver, machineReg: buildMachineReg,
                      machineTranspose: buildMachineTranspose, hueOverride: machineHueOverride, idCounter: buildIDCounter,
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
        buildMachineReg = s.machineReg; buildMachineTranspose = s.machineTranspose; machineHueOverride = s.hueOverride
        buildIDCounter = s.idCounter
        buildPlayCells = s.playCells; buildPlaySel = s.playSel; buildPlayColOn = s.playColOn; buildPlayColRecv = s.playColRecv
        buildPlayColEmit = s.playColEmit; buildPlayColLen = s.playColLen; buildPlayColSteps = s.playColSteps
        buildPlayColRate = s.playColRate; buildPlayColStepRecv = s.playColStepRecv; buildPlayColStepEmit = s.playColStepEmit
        au?.restoreDocumentFromUndo(s.doc)          // the document (document-machine chains / receivers / rack) restored WITHOUT recording
        buildSyncMachines()                          // push the ephemeral registry to the render
        buildPublishScene()                         // re-publish the composed scene
        receivers = au?.uiReceivers() ?? receivers
        refreshFromDocument()                       // reload document-derived state (docMachines, receivers, rack, ROW 8…)
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
        // THE PLAY FERRIES ARE PARTS (Paul 2026-09-08): the ACTIVE ferry plays via the STAGING sequencer, which composes
        // the LIVE bench each publish — so a selection/content edit is heard + swept at once, no flatten needed here. A
        // BACKGROUND ferry's play-layer line is (re)flattened only when it goes on / when it stops being the active one.
        au?.clearMachineSolo()                                    // BUILD never uses the AU solo now — drop any left by the vestigial ddCreateMachine path, so the scene sweeps freely
        // (the loop keys now DRIVE the lap — same `laneMask` as the GRID tab; a held column-set laps the workshop. Paul 2026-08-19)
        var input = BuildSceneLogic.Input()
        // MUTE/SOLO (Paul 2026-09-09): gate the AUDIO by buildFerryAudible — the active ferry's staging voice is silenced
        // if the active ferry is muted / solo-excluded; the background play layer is gated below (input.playColOn).
        input.stagingPlaying = buildStagingPlaying && (buildActiveFerry.map { buildFerryAudible($0) } ?? true)
        input.performPlaying = buildPerformPlaying
        input.chainActive = ddSolo
        input.performCells = buildPerformCells
        input.performMute = buildPerformMute
        input.performActiveRung = { self.buildPerformActiveRung($0, $1) }
        input.performEmit = buildPerformEmit
        input.performRecv = buildPerformRecv
        // RESOLVE the effective chain per PERFORM cell (Paul 2026-08-23): a per-cell VARIATION if it has one, else the
        // machine's OWN machine (buildMachineChain → [] for a NO-MACHINE machine). composeScene then passes it EXPLICITLY,
        // so a no-machine cell is a passthrough (live wire) in the play grid too — not only via PLAY THIS MIDI CHAIN.
        input.performChain = (0..<Snap.maxCols).map { c in (0..<8).map { r -> [ProcessorSlot] in   // §E: 16 part columns × 8 rows
            let v = (c < buildPerformChain.count && r < buildPerformChain[c].count) ? buildPerformChain[c][r] : []
            let cid = (c < buildPerformCells.count && r < buildPerformCells[c].count) ? buildPerformCells[c][r] : nil
            return v.isEmpty ? buildMachineChain(cid ?? "") : v
        } }
        input.stagingCells = buildStagingCells
        input.stagingSel = buildStagingSel
        input.partEmitters = buildPartEmitters
        input.selReceiver = buildSelReceiver
        input.rowReceiver = (0..<8).map { buildRowReceiverResolved($0) }     // per-row I/O, resolved (nil → part default)
        input.rowEmitters = (0..<8).map { buildRowEmittersResolved($0) }
        // RESOLVE the effective chain per STAGING row (same rule as PERFORM/CHAIN): the row's VARIATION if present, else
        // the row machine's OWN machine ([] for a no-machine machine → passthrough wire). (Paul 2026-08-23)
        input.rowChain = (0..<8).map { r -> [ProcessorSlot] in
            let v = r < buildRowChain.count ? buildRowChain[r] : []
            return v.isEmpty ? buildMachineChain(buildRowMachine(r) ?? "") : v
        }
        if ddSolo, let cid = ddSelectedMachineID {
            input.chainMachineID = cid
            input.chainMachine = buildMachineChain(cid)
        }
        let selR = buildSelectedRow                                          // the chain audition takes the SELECTED machine's row I/O
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
        let playColEffectiveOn = (0..<buildPlayColOn.count).map { buildPlayColOn[$0] && buildFerryAudible($0) }   // MUTE/SOLO gate (background ferries)
        input.playPlaying = playColEffectiveOn.contains(true) || input.stagingPlaying
        input.playCells = buildPlayCells
        input.playSel = buildPlaySel
        input.playColOn = playColEffectiveOn   // MUTE/SOLO: the ENGINE plays the effective set; the UI glyph still reads buildPlayColOn
        input.playColRecv = buildPlayColRecv
        input.playColEmit = buildPlayColEmit
        input.playColChain = (0..<8).map { c -> [ProcessorSlot] in
            let r = c < buildPlaySel.count ? buildPlaySel[c] : -1
            guard r >= 0, r < 8, c < buildPlayCells.count, r < buildPlayCells[c].count, let cid = buildPlayCells[c][r] else { return [] }
            return buildMachineChain(cid)
        }
        // MULTI-STEP PASS (Paul 2026-08-30): a flattened part rides a play column as N steps — resolve each step's chain here.
        input.playColLen = buildPlayColLen
        input.playColSteps = buildPlayColSteps
        input.playColRate = buildPlayColRate
        // PLAY-FERRY LAUNCH (Paul 2026-09-09): map each ON ferry's per-ferry anchor to its ENGINE row(s) — the active ferry
        // plays via staging (rows 0–7), a background ferry t via the play layer (row 8+t) — so the anchor follows the ferry.
        var launchRows = [Double](repeating: 0, count: Snap.rows)
        for t in 0..<8 where t < buildPlayColOn.count && buildPlayColOn[t] && t < launchAnchor.count && launchAnchor[t] != 0 {
            if t == buildActiveFerry { for r in 0..<8 { launchRows[r] = launchAnchor[t] } }
            else { launchRows[Snap.playLayerRowBase + t] = launchAnchor[t] }
        }
        input.rowLaunchAnchor = launchRows
        input.playColStepRecv = buildPlayColStepRecv
        input.playColStepEmit = buildPlayColStepEmit
        input.playColStepChain = (0..<8).map { c -> [[ProcessorSlot]] in
            let len = c < buildPlayColLen.count ? buildPlayColLen[c] : 1
            guard len > 1, c < buildPlayColSteps.count else { return [] }
            return buildPlayColSteps[c].map { cid in cid.map { buildMachineChain($0) } ?? [] }
        }
        input.partAuto = buildAutoLanes                                       // PART AUTOMATION (Paul 2026-09-02): bake the active AUTO lanes per cell
        input.partWidth = buildPartCols                                       // SPAN-ONLY (Paul 2026-09-04): the part's active width = the default span + tile reference
        au?.setBuildAuto(buildAutoLanes.isEmpty ? nil : buildAutoLanes)        // PHASE 2: push the LIVE lanes so the box carries render-time (×N/SMOOTH) descriptors
        let composed = BuildSceneLogic.composeSceneMeta(input)
        au?.setBuildStagingScene(composed.scene)
        buildPartRollGen &+= 1                                                // the box changed → force an OFFLINE part-roll recompute (picks up cell/chain edits)
        buildChainAuditionRow = composed.auditionRow                          // #5: the engine row the audition parked on → the aimed ferry reads its LIVE strikes there
        // (The reference-chord fallback was REMOVED 2026-08-23, Paul: PLAY THIS MIDI CHAIN now sounds ONLY real input —
        // a synthetic C-major triad must never reach the user. With nothing held the audition is simply silent.)
        // FREE-RUN GATE (Paul 2026-08-31): "when I press play, start playing." Pressing a PLAY control in 8x8 arms a voice
        // (ddSolo chain audition · buildStagingPlaying part · a play column), and THAT drives the internal clock so it sounds
        // even while the host transport is stopped. HOST TRANSPORT SYNC (Paul 2026-09-02): a host-transport STOP does NOT
        // de-arm — it sets buildHostHalted, gating free-run OFF (halt/silence) while the cells stay armed; the host START
        // edge clears it so the armed voices RESUME in sync. An explicit BUILD play also clears it (audition while stopped).
        au?.setFreeRunEnabled((ddSolo || buildStagingPlaying || buildPerformPlaying || buildPlayPlaying) && !buildHostHalted)   // halted (host stopped after playing) → NO free-run, the voices resume when the host does
    }
    // buildStopAllOnTransportStop RETIRED (Paul 2026-09-12): the OLD "host stop de-arms everything" handler. SUPERSEDED by
    // buildTransportEdge (wired at the poll) — which HALTS play but KEEPS cells armed so START resumes in sync (Paul
    // 2026-09-02). It had no caller; wiring it back would regress that intentional behaviour. NOT a bug.
    // THE HOST TRANSPORT drives 8×8's playback (Paul 2026-09-02): hitting STOP in the host HALTS play (silence) but does
    // NOT de-arm any cell — the armed state (owner + play columns + rung selections) is kept, so PLAY resumes IN SYNC with
    // the host. `buildHostHalted` gates free-run OFF while the host is stopped-after-playing (so it truly halts, not
    // free-runs); it's cleared on host START (host drives) and on any explicit BUILD play (a deliberate stopped audition).
    func buildTransportEdge(_ playing: Bool) {
        if playing {
            if buildHostHalted { buildHostHalted = false; buildPublishScene() }   // RESUME: host drives the armed voices, in sync
        } else {
            buildHostHalted = true; buildPublishScene()                           // HALT: keep every cell armed, suppress free-run → silence until the host resumes (the VC's own stop-edge commits any pending voice switch)
        }
    }
    // The staging row currently being EDITED = the row holding the selected machine (nil ⇒ nothing on a row). (Paul 2026-08-18)
    private var buildSelectedRow: Int? {
        guard let id = buildSelID else { return nil }
        return (0..<8).first { buildRowMachine($0) == id }
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

    // A machine's OWN machine (templateChain), audible slots only.
    // A machine's machine — EPHEMERAL registry (beyond the 16) OR the document templateChain (the canonical 16).
    private func buildMachineSlots(_ cid: String) -> [ProcessorSlot] {
        buildMachineReg[cid] ?? (docMachines.first { $0.machineID == cid }?.templateChain ?? [])
    }
    private func buildMachineChain(_ cid: String) -> [ProcessorSlot] {
        buildMachineSlots(cid).filter { !buildIsEmptySlot($0) }
    }
    // Write a machine's machine to the right store, and reflect it live.
    private func buildWriteMachineSlots(_ cid: String, _ chain: [ProcessorSlot]) {
        buildKeepRowGen()   // editing the processor/machine chain acts as KEEP
        if buildMachineReg[cid] != nil { buildMachineReg[cid] = chain; buildSyncMachines() }   // ephemeral
        else { au?.setMachineChain(cid, chain); refreshFromDocument() }                       // document machine
        buildStagingSyncIfPlaying()
    }
    // Push the ephemeral machine registry to the AU so renderDoc appends them (their machines resolve).
    func buildSyncMachines() { au?.setBuildEphemeralMachines(buildMachineReg.map { (id: $0.key, machine: $0.value, transpose: buildMachineTranspose[$0.key] ?? 0) }) }
    // Allocate a NEW machine carrying `machine` + a custom hue: a free DOCUMENT slot if one remains, else an unlimited
    // EPHEMERAL machine ("b<n>"). Returns its id. (Paul 2026-08-15 — lifts the 16-slot cap.)
    private func buildNewMachine(hex rawHex: UInt32, machine: [ProcessorSlot]) -> String {
        let hex = buildUniqueHue(rawHex)                                     // RULE: no two machines share a hue (Paul 2026-08-16)
        if let j = buildFirstUndefinedGlobal() {
            let id = machineIDs[j]
            ddCreateMachine(j); au?.withChainMachine(id) { $0 = machine }; refreshFromDocument()
            machineHueOverride[id] = hex
            return id
        }
        buildIDCounter += 1
        let id = "b\(buildIDCounter)"
        buildMachineReg[id] = machine; machineHueOverride[id] = hex; buildSyncMachines()
        return id
    }
    // Select a machine BY ID (document or ephemeral) — the ID-based BUILD selection.
    private func buildSelectID(_ id: String) {
        buildExitPlaceMode()                                     // choosing a machine is a non-(play-row) touch → leave PLACE mode
        buildSelID = id                                          // the DISPLAY selection updates immediately (target, footer, highlight)
        ddMachineSel = machineIDs.firstIndex(of: id) ?? -1
        ddStickyReceiver = buildSelReceiver
        ddStickyBuses = buildDefaultEmitters
        ddScopeToMachine(id, anchor: nil, engage: false)          // BUILD never uses the AU solo — the chain plays via the scene
        if ddSolo {                                              // auditioning the chain → re-inject the newly-selected machine
            if d.playing { buildPendingReengage = true }         // SEAMLESS: swap on the next cell boundary
            else { buildPublishScene() }                         // stopped → immediate
        }
    }
    // The base hue of a machine (its override if any, else its palette hex).
    private func buildBaseHex(_ id: String) -> UInt32 { machineHueOverride[id] ?? machineIDs.firstIndex(of: id).map { machineHexes[$0] } ?? 0x808080 }
    // Every hue currently IN USE by a live machine: the materialised document machines + every ephemeral/recoloured
    // override. An UNASSIGNED canonical hex is NOT counted — so a new machine can claim a genuinely distinct
    // canonical hue rather than a near-shade of its source. (Paul 2026-08-17)
    private func buildUsedHues() -> Set<UInt32> {
        var used = Set(machineHueOverride.values)
        for (i, id) in machineIDs.enumerated() where ddMachineShown(i) { used.insert(buildBaseHex(id)) }
        return used
    }
    // A hue guaranteed UNUSED and, wherever possible, VISIBLY distinct: an unassigned canonical palette hue first,
    // else a canonical seed perturbed until it clears everything in use. The engine behind the "no two alike" rule.
    private func buildDistinctHue() -> UInt32 {
        let used = buildUsedHues()
        if let fresh = machineHexes.first(where: { !used.contains($0) }) { return fresh }
        for seed in machineHexes {
            var h = seed, n = 0
            while used.contains(h) && n < 128 { n += 1; h = buildPerturbHex(seed, by: n) }
            if !used.contains(h) { return h }
        }
        return 0x808080
    }
    // STRONG RULE (Paul 2026-08-17): no two machines may EVER share a hue. Keep `hex` if it is free, else nudge to
    // the nearest distinct shade, and if THAT still collides fall back to a guaranteed-distinct hue. Never returns
    // a used hue.
    private func buildUniqueHue(_ hex: UInt32) -> UInt32 {
        let used = buildUsedHues()
        if !used.contains(hex) { return hex }
        var h = hex, n = 0
        while used.contains(h) && n < 128 { n += 1; h = buildPerturbHex(hex, by: n) }
        return used.contains(h) ? buildDistinctHue() : h
    }
    // STRONG RULE: no two PALETTE (cast) machines share a hue. Any member whose hue duplicates an earlier member is
    // recoloured to a distinct hue. Call after any cast mutation.
    private func buildEnforceCastHues() {
        var seen = Set<UInt32>(); var changed = false
        for id in buildPartCast {
            let h = buildBaseHex(id)
            if seen.contains(h) { let nh = buildDistinctHue(); machineHueOverride[id] = nh; seen.insert(nh); changed = true }
            else { seen.insert(h) }
        }
        if changed { buildSyncMachines() }
    }
    private func buildPerturbHex(_ h: UInt32, by d: Int) -> UInt32 {
        func ch(_ shift: Int) -> UInt32 { let c = Int((h >> shift) & 0xFF); return UInt32(max(0, min(255, c + (c < 128 ? d : -d)))) }   // push each channel toward its extreme by an increasing step
        return (ch(16) << 16) | (ch(8) << 8) | ch(0)
    }
    // Perceived darkness of a hex — used to invert a row button's background when its coloured icon would vanish.





    // Push the current staging grid to the engine IF the staging voice is live (call after any staging-grid edit).
    private func buildStagingSyncIfPlaying() { buildPublishScene() }   // re-publish the combined (part + piece) scene after an edit

    // BUILD RANDOMIZE — the SIMPLER roll (a short 1–3-slot all-contributing chain, no macros); writes it machine-wide.
    private func buildRandomizeSimple() {
        guard let cid = ddSelectedMachineID else { return }
        var rng = SystemRandomNumberGenerator()
        au?.withChainMachine(cid) { $0 = Dice.rollSimple(using: &rng) }
        refreshFromDocument()
    }
    // <<< MUTATE — nudge the SELECTED machine's midi chain in place (a value-tweaked variant of its OWN machine). (Paul 2026-08-18)
    private func buildMutateChain() {
        guard let cid = ddSelectedMachineID else { return }
        let base = buildMachineChain(cid)
        var rng = SystemRandomNumberGenerator()
        if let mutated = BuildSceneLogic.mutateChain(base, avoid: [Dice.fingerprint(base)], &rng) { buildWriteMachineSlots(cid, mutated) }
        refreshFromDocument()
    }
    // ── ADD A ROW (Paul 2026-09-08): when an EMPTY part row is selected on the right rail, the machine box's interior
    // (the chain + verb/play buttons — everything between the two toggle sets) is REPLACED by these big creation buttons,
    // in the SAME footprint. Each mints a machine onto the empty row (the machine box then edits it, available to sequence).
    private func buildCreateRowMachine(_ row: Int, chain: [ProcessorSlot]) {
        guard row >= 0, row < 8 else { return }
        buildRecordUndo()
        let y = buildNewMachine(hex: buildDistinctHue(), machine: chain)
        buildSetRow(row, to: y)                                  // place the machine across the row's cells (selectable in any column)
        buildSelectRow(row)                                      // AUTO-SELECT the new row across every column (Paul 2026-09-10)
        buildRoomsSetActiveSide(row); buildSelectID(y); buildTapMachineTab(row)   // focus the new row → the machine box now edits it
        buildStagingSyncIfPlaying()
    }
    // IN-ROW ROW CREATOR (Paul 2026-09-10): a SELECTED EMPTY part row becomes 4 equal buttons — MUTATE · RANDOM · CREATE
    // · CLONE — RIGHT IN THAT ROW, styled identically to the cells. Equal quarters → the total row width is unchanged, so
    // nothing around it shifts. CLONE/MUTATE work off the first populated row (empty ⇒ they behave like CREATE).
    @ViewBuilder private func roomsRowCreatorInline(_ row: Int, cw: CGFloat, gap: CGFloat, cols: Int, rowH: CGFloat) -> some View {
        let rowW = cw * CGFloat(cols) + gap * CGFloat(cols - 1)                    // EXACT normal-row width → identical scale
        let ref = (0..<8).first { buildRowMachine($0) != nil }
        let refChain = ref.flatMap { buildRowMachine($0).map { buildMachineChain($0) } } ?? []
        HStack(spacing: gap) {
            // MUTATE/RANDOM generate, then OFFER KEEP | TRY AGAIN (Paul 2026-09-11); CREATE/CLONE commit directly (no confirm).
            roomsRowCreatorSeg("MUTATE") { var rng = SystemRandomNumberGenerator(); buildCreateRowMachine(row, chain: BuildSceneLogic.mutateChain(refChain, avoid: [Dice.fingerprint(refChain)], &rng) ?? refChain); buildRowGenConfirm = RowGenConfirm(row: row, random: false) }
            roomsRowCreatorSeg("RANDOM") { var rng = SystemRandomNumberGenerator(); buildCreateRowMachine(row, chain: Dice.rollSimple(using: &rng)); buildRowGenConfirm = RowGenConfirm(row: row, random: true) }
            roomsRowCreatorSeg("CREATE") { buildCreateRowMachine(row, chain: []); buildAddSlot = 0 }   // mint an empty machine + open the ADD PROCESSOR card (Paul 2026-09-10)
            roomsRowCreatorSeg("CLONE")  { buildCreateRowMachine(row, chain: refChain) }
        }.frame(width: rowW, height: rowH)
    }
    // KEEP | TRY AGAIN — shown in the row after MUTATE/RANDOM, in the SAME place/style as the creator buttons (Paul 2026-09-11).
    // KEEP accepts (the confirm DISAPPEARS → the row shows the generated cells); TRY AGAIN regenerates the same mode + re-offers.
    @ViewBuilder private func roomsRowConfirmInline(_ row: Int, random: Bool, cw: CGFloat, gap: CGFloat, cols: Int, rowH: CGFloat) -> some View {
        let rowW = cw * CGFloat(cols) + gap * CGFloat(cols - 1)
        HStack(spacing: gap) {
            roomsRowCreatorSeg("KEEP")      { buildRowGenConfirm = nil }        // accept → the menu disappears
            roomsRowCreatorSeg("TRY AGAIN") { buildRegenRow(row, random: random) }   // regenerate (same mode) → still offering KEEP | TRY AGAIN
        }.frame(width: rowW, height: rowH)
    }
    // Re-run MUTATE/RANDOM on `row` for TRY AGAIN. MUTATE re-mutates the ORIGINAL source (a populated OTHER row), not the
    // just-generated result. The confirm stays set (same row/mode) so KEEP | TRY AGAIN re-presents for the new result.
    private func buildRegenRow(_ row: Int, random: Bool) {
        var rng = SystemRandomNumberGenerator()
        if random {
            buildCreateRowMachine(row, chain: Dice.rollSimple(using: &rng))
        } else {
            let ref = (0..<8).first { $0 != row && buildRowMachine($0) != nil }
            let refChain = ref.flatMap { buildRowMachine($0).map { buildMachineChain($0) } } ?? []
            buildCreateRowMachine(row, chain: BuildSceneLogic.mutateChain(refChain, avoid: [Dice.fingerprint(refChain)], &rng) ?? refChain)
        }
        buildRowGenConfirm = RowGenConfirm(row: row, random: random)   // re-assert: TRY AGAIN keeps offering KEEP | TRY AGAIN for the new result
    }
    // IMPLICIT KEEP (Paul 2026-09-11): any real action on the processor / machine / toggles / grid accepts a pending
    // MUTATE/RANDOM result → the KEEP | TRY AGAIN confirm disappears. (The TRY AGAIN button re-asserts it above; KEEP nils it.)
    private func buildKeepRowGen() { if buildRowGenConfirm != nil { buildRowGenConfirm = nil } }
    @ViewBuilder private func roomsRowCreatorSeg(_ label: String, _ action: @escaping () -> Void) -> some View {
        RoundedRectangle(cornerRadius: 5).fill(buildCell)                          // identical cell styling: dark stage + edge
            .overlay(RoundedRectangle(cornerRadius: 5).stroke(buildEdge, lineWidth: 1))
            .overlay(Text(label).font(.system(size: 14, weight: .bold, design: .rounded)).tracking(0.5)
                        .foregroundColor(.white.opacity(0.95)).lineLimit(1).minimumScaleFactor(0.55).padding(.horizontal, 3))
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .contentShape(Rectangle())
            .onTapGesture(perform: action)
    }
    // (buildRowCreatorMenu / buildRowCreatorButton removed 2026-09-10 — creation is now the 4 in-row buttons
    //  MUTATE/RANDOM/CREATE/CLONE via roomsRowCreatorInline; CREATE opens the ADD PROCESSOR card.)
    // <<< CLEAR — empty the SELECTED machine's midi chain (every processor box → "+"). (Paul 2026-08-18)
    // On the PART grid (Paul 2026-09-08) CLEAR ALSO removes the machine's PRESENCE from the part (its row); and when the
    // whole part is thereby empty it clears the ACTIVE FERRY too → an empty ferry, which is how you reach the SELECT
    // browser (the empty-ferry-only navigation, once the toggle is gone).
    private func buildClearChain() {
        buildRecordUndo()   // BUILD UNDO: clear the selected machine's chain
        guard let cid = ddSelectedMachineID else { return }
        buildWriteMachineSlots(cid, [])
        if roomsRoom == .part {
            for r in 0..<8 where buildRowMachine(r) == cid { buildSetRow(r, to: nil) }          // remove the machine's presence on the part grid (its row)
            buildStagingSel = BuildSceneLogic.reconcileStagingSel(buildStagingSel, cells: buildStagingCells)
            if (0..<8).allSatisfy({ buildRowMachine($0) == nil }), let a = buildActiveFerry, a >= 0, a < 8 {   // the whole part is now empty → clear the ferry cell
                buildResetFerrySlot(a)                                    // FULL reset — parts + on + MUTE/SOLO + launch + hue-alloc (Paul 2026-09-12: was leaving solo/mute STALE, so a soloed ferry cleared to empty silenced every OTHER ferry with no UI path back)
                buildVoiceOwner = .none; roomsRoom = .select              // → the SELECT browser; ferry `a` STAYS SELECTED (now empty) so a selector is always selected (Paul 2026-09-12)
                roomsSelectSetup()                                                                // open the library browser (like the retired toggle)
            }
            buildPublishScene()
        }
        refreshFromDocument()
    }
    // <<< COPY / PASTE (Paul 2026-08-25): COPY grabs the SELECTED machine's chain into a buffer; PASTE drops that chain
    // into a NEW row (mints a fresh machine carrying it on the first empty row, then selects it). PASTE is disabled
    // until the buffer holds a non-empty chain. Used to copy one chain into a new row position.
    private func buildCopyChain() {
        let chain = selectedMachineChain()
        guard !chain.isEmpty else { return }               // nothing to copy → leave the buffer (paste stays disabled)
        buildChainClipboard = chain
    }
    private func buildPasteChain() {
        buildRecordUndo()   // BUILD UNDO: paste a chain onto a new machine
        guard let chain = buildChainClipboard, !chain.isEmpty else { return }
        guard let row = (0..<8).first(where: { buildRowMachine($0) == nil }) else { return }   // the first EMPTY row (a new position)
        let newID = buildNewMachine(hex: buildDistinctHue(), machine: chain)
        if row < buildRowUnder.count { buildRowUnder[row] = nil }   // an empty row displaces nothing
        buildSetRow(row, to: newID)
        buildSelectID(newID)                               // focus the pasted machine
        for c in 0..<Snap.maxCols { buildStagingSel[c] = row }        // select the whole new row (like PLACE/MUTATE) — §E 16-col
        buildStagingSyncIfPlaying()
    }

    // The selected machine's OWN processors (its templateChain) — shown on the footer. Interior EMPTY boxes (passthrough
    // placeholders) are kept so a processor's POSITION is remembered even with empty boxes to its left; TRAILING empties
    // collapse to "+" capacity slots. A fully blank/new machine → [] (all boxes are "+").
    private func selectedMachineChain() -> [ProcessorSlot] {
        guard let cid = ddSelectedMachineID else { return [] }
        var chain = buildMachineSlots(cid)
        while let last = chain.last, buildIsEmptySlot(last) { chain.removeLast() }
        return chain
    }
    // buildFocusedChain RETIRED (Paul 2026-09-12 dead-code sweep — the AUTO-flow focused-chain reader, no caller).
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
        buildLoadBenchPart(buildParts[i])
    }
    // Load a standalone BuildPart onto the bench @State (the part-grid editor). Shared by buildLoadPart (from buildParts)
    // and PLAY-GRID UNPACK (a play cell's stored part). Does NOT set buildCurrentPart — the caller owns that. (Paul 2026-09-05)
    func buildLoadBenchPart(_ p: BuildPart) {
        let ns = buildNormalizeStaging(p.stagingCells, p.stagingSel); buildStagingCells = ns.cells; buildStagingSel = ns.sel
        buildRowChain = p.rowChain; buildRowShade = p.rowShade; buildRowUnder = p.rowUnder
        buildSelID = p.selID; ddMachineSel = p.selID.flatMap { machineIDs.firstIndex(of: $0) } ?? -1; buildSelReceiver = p.receiver; buildPartEmitters = p.emitters; buildPartCast = p.cast; buildCastSlots = p.castSlots
        buildRowReceiver = p.rowReceiver ?? Array(repeating: nil, count: 8)   // PER-ROW I/O — old parts have nil → all rows inherit (Paul 2026-08-18)
        buildRowEmitters = p.rowEmitters ?? Array(repeating: nil, count: 8)
        buildPartRate = p.rate; buildPartLen = p.length                       // PER-PART CLOCK (Paul 2026-08-19)
        buildReslotCast()                                       // migrate old parts + backfill any extra machine missing a slot
        buildEnforceCastHues()                                  // strong rule: no two palette machines share a hue
        buildDeletedRows = [:]   // transient — never crosses a part
        buildPartTouched = !buildStagingSel.allSatisfy { $0 < 0 }   // a part that already has a selection is "touched" (respect it); an empty part re-defaults on PART entry
        buildEnsureCastSelection()                              // §2: keep the selection inside this part's cast (empty cast → none)
        buildStagingSyncIfPlaying()
    }
    // Capture the current bench @State as a BuildPart (the whole part-grid state), for archiving onto a play cell on
    // flatten/promote → lossless UNPACK. More complete than buildCaptureUnassigned (it also carries per-row I/O). The
    // transient deletedRows (undo scratch) is intentionally NOT carried. (Paul 2026-09-05, PLAY-GRID FERRY EDITING)
    func buildCaptureBenchPart() -> BuildPart {
        var p = BuildPart()
        p.stagingCells = buildStagingCells; p.stagingSel = buildStagingSel; p.rowChain = buildRowChain
        p.rowShade = buildRowShade; p.rowUnder = buildRowUnder; p.selID = buildSelID
        p.receiver = buildSelReceiver; p.emitters = buildPartEmitters; p.cast = buildPartCast; p.castSlots = buildCastSlots
        p.rowReceiver = buildRowReceiver; p.rowEmitters = buildRowEmitters
        p.rate = buildPartRate; p.length = buildPartLen; p.deployed = false
        // PLAY-FERRY LAUNCH SETTINGS (Paul 2026-09-09): these aren't bench @State — carry them from the active ferry's stored
        // part so a bench write-back (this fresh capture) never wipes name/hue/launch. Every capture site captures the ACTIVE
        // ferry, so buildFerryParts[buildActiveFerry] holds the authoritative launch fields (the panel edits it directly).
        if let a = buildActiveFerry, a >= 0, a < buildFerryParts.count, let cur = buildFerryParts[a] {
            p.ferryName = cur.ferryName; p.ferryHue = cur.ferryHue
            p.launchPlayback = cur.launchPlayback; p.launchTrigger = cur.launchTrigger
            p.launchStart = cur.launchStart; p.chokeGroup = cur.chokeGroup
        }
        return p
    }

    // ── PERSISTENCE (Paul 2026-08-16): the single UNASSIGNED part is saved with the document ("saving = committing").
    // CAPTURE is READ-ONLY (never touches @State, so it's safe to call from the 4 Hz poll): the live workshop if the
    // current part is the unassigned one, else the stored unassigned part. Bundles the EPHEMERAL machines it references
    // (machine + hue) so it reconstructs on load; canonical document machines are always present, so they aren't bundled.
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
        var ids = Set(part.cast)                                // every machine the part could reference
        ids.formUnion(part.stagingCells.flatMap { $0.compactMap { $0 } })
        ids.formUnion(part.rowUnder.compactMap { $0 })
        if let s = part.selID { ids.insert(s) }
        let ephemeral = ids.filter { buildMachineReg[$0] != nil }.sorted()
        let machines = ephemeral.map { id -> Machine in var c = Machine(machineID: id, type: .arp); c.defined = true; c.templateChain = buildMachineReg[id]; c.transpose = buildMachineTranspose[id] ?? 0; return c }   // carry the register-home so a saved ensemble restores in the right octave (BUG state-loss 2026-08-29)
        var hues: [String: UInt32] = [:]; for id in ephemeral { if let h = machineHueOverride[id] { hues[id] = h } }
        return BuildUnassignedData(part: part, machines: machines, hues: hues, idCounter: buildIDCounter)
    }
    // RESTORE the saved unassigned part on load: re-register its ephemeral machines + hues, lift the id counter past
    // them (so new machines don't collide), then place it as the single unassigned part and load it into the workshop.
    func buildRestoreUnassigned(_ u: BuildUnassignedData) {
        for c in u.machines { buildMachineReg[c.machineID] = c.templateChain ?? []; if c.transpose != 0 { buildMachineTranspose[c.machineID] = c.transpose } }   // restore the register-home too (BUG state-loss 2026-08-29)
        for (id, hue) in u.hues { machineHueOverride[id] = hue }
        buildIDCounter = max(buildIDCounter, u.idCounter)
        buildSyncMachines()
        var part = u.part; part.deployed = false
        if let i = buildParts.firstIndex(where: { !$0.deployed }) { buildParts[i] = part; buildLoadPart(i) }
        else { buildParts.append(part); buildLoadPart(buildParts.count - 1) }
    }
    // THE ROOMS PLAY GRID (Paul 2026-08-30): capture the 8 play columns + their multi-step passes + the ephemeral machines
    // they reference, so a reload restores the whole play grid. Only when there's content (a populated/multi-step column).
    func buildCapturePlayGrid() -> BuildPlayGridData? {
        var parts = buildFerryParts                                          // THE PLAY FERRIES ARE PARTS — the source of truth
        if let a = buildActiveFerry, a >= 0, a < 8, buildFerryParts[a] != nil { parts[a] = buildCaptureBenchPart() }   // fold in a POPULATED active ferry's live bench edits — never persist an empty selector as a part (Paul 2026-09-12)
        let anyPart = parts.contains { $0 != nil }
        let hasContent = anyPart || !buildGridSelName.isEmpty || (0..<8).contains { c in buildPlayColPopulated(c) || (c < buildPlayColLen.count && buildPlayColLen[c] > 1) }   // committed SELECT cells are content too (Paul 2026-09-12)
        guard hasContent else { return nil }
        var ids = Set<String>()
        for col in buildPlayCells { for cell in col { if let id = cell { ids.insert(id) } } }
        for col in buildPlayColSteps { for step in col { if let id = step { ids.insert(id) } } }
        for p in parts.compactMap({ $0 }) {                                  // every machine a ferry part references
            ids.formUnion(p.stagingCells.flatMap { $0.compactMap { $0 } }); ids.formUnion(p.cast)
            ids.formUnion(p.rowUnder.compactMap { $0 }); if let s = p.selID { ids.insert(s) }
        }
        let ephemeral = ids.filter { buildMachineReg[$0] != nil }.sorted()
        let machines = ephemeral.map { id -> Machine in var c = Machine(machineID: id, type: .arp); c.defined = true; c.templateChain = buildMachineReg[id]; c.transpose = buildMachineTranspose[id] ?? 0; return c }
        var hues: [String: UInt32] = [:]; for id in ephemeral { if let h = machineHueOverride[id] { hues[id] = h } }
        var data = BuildPlayGridData(cells: buildPlayCells, sel: buildPlaySel, colOn: buildPlayColOn, colRecv: buildPlayColRecv,
                                     colEmit: buildPlayColEmit, colLen: buildPlayColLen, colSteps: buildPlayColSteps, colRate: buildPlayColRate,
                                     colStepRecv: buildPlayColStepRecv, colStepEmit: buildPlayColStepEmit, machines: machines, hues: hues, idCounter: buildIDCounter)
        data.parts = parts
        if !buildGridSelOverride.isEmpty {   // COMMITTED SELECT cells — persist the pinned chain + colour (Paul 2026-09-12)
            data.gridSelChains = buildGridSelOverride.mapValues { $0.chain }
            data.gridSelHues = buildGridSelOverride.mapValues { $0.hex }
        }
        if !buildGridSelName.isEmpty { data.gridSelNames = buildGridSelName }   // …and their generated hash names
        if !buildFerryHueAlloc.isEmpty { data.ferryHueAlloc = buildFerryHueAlloc }   // empty-ferry colour reallocation (Paul 2026-09-12)
        return data
    }
    func buildRestorePlayGrid(_ d: BuildPlayGridData) {
        for c in d.machines { buildMachineReg[c.machineID] = c.templateChain ?? []; if c.transpose != 0 { buildMachineTranspose[c.machineID] = c.transpose } }
        for (id, hue) in d.hues { machineHueOverride[id] = hue }
        buildIDCounter = max(buildIDCounter, d.idCounter)
        buildSyncMachines()
        buildFerryParts = d.partsResolved                                    // THE PLAY FERRIES ARE PARTS — restore/migrate the 8 slots (source of truth)
        // Restore the legacy arrays only when the shapes are exactly right; a malformed doc keeps the defaults (defensive).
        // (These are now derived playback state; the parts re-flatten below regardless, so `colOn` is what really matters.)
        if d.cells.count == 8, d.cells.allSatisfy({ $0.count >= 8 }), d.sel.count == 8, d.colOn.count == 8, d.colRecv.count == 8,
           d.colEmit.count == 8, d.colLen.count == 8, d.colSteps.count == 8, d.colRate.count == 8, d.colStepRecv.count == 8, d.colStepEmit.count == 8 {
            buildPlayCells = d.cells; buildPlaySel = d.sel; buildPlayColOn = d.colOn; buildPlayColRecv = d.colRecv; buildPlayColEmit = d.colEmit
            buildPlayColLen = d.colLen; buildPlayColSteps = d.colSteps; buildPlayColRate = d.colRate; buildPlayColStepRecv = d.colStepRecv; buildPlayColStepEmit = d.colStepEmit
        }
        for t in 0..<8 { buildFlattenFerry(t) }                              // regenerate each ferry's playback line from its part (canonical)
        // COMMITTED SELECT cells (Paul 2026-09-12): restore the pinned chain + colour + name so an edited cell survives reload.
        if let chains = d.gridSelChains {
            let hues = d.gridSelHues ?? [:]
            var ov: [Int: (chain: [ProcessorSlot], hex: UInt32)] = [:]
            for (i, ch) in chains { ov[i] = (ch, hues[i] ?? machineHexes[((i % 8) * 2) % 16]) }
            buildGridSelOverride = ov
        }
        if let names = d.gridSelNames { buildGridSelName = names }
        buildFerryHueAlloc = d.ferryHueAlloc ?? [:]   // empty-ferry colour reallocation (Paul 2026-09-12)
        buildPublishScene()   // republish so restored STARTED ferries sound at once
    }
    // PART AUTOMATION (Paul 2026-09-02): capture the per-machine AUTO lanes for the save (prune machines with no active
    // lane AND no extents, so the map stays sparse). nil when nothing's armed → byte-identical fullState.
    func buildCaptureAuto() -> [String: PartAutoMachine]? {
        let live = buildAutoLanes.filter { $0.value.activeLane >= 0 || $0.value.lanes.contains(where: { $0.spanStart != nil || $0.spanLen != nil }) }   // span-only: a lane has content if it holds a span
        return live.isEmpty ? nil : live
    }
    func buildRestoreAuto(_ d: [String: PartAutoMachine]) { buildAutoLanes = d; buildPublishScene() }
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
    // THE DEFAULT PALETTE (Paul 2026-08-14): eight starter machines, one per processor type (arp/ratchet/euclid/echo
    // named + strum/chance/harmonize/drone — NEVER passgate). They open the palette as 2 rows of 4 and are present in
    // every part's cast. Each carries a single-processor machine at that type's default settings.
    static let buildDefaultTypes: [ProcessorType] = [.arp, .ratchet, .euclid, .weave, .echo, .strum, .chance, .split, .tutti, .length, .harmonize, .drone]
    // Mint a TAB machine: an ephemeral machine carrying `machine` with tab n's FIXED hue (machineHexes[n]), verbatim
    // (no uniquify — a tab always shows the same machine). (Paul 2026-08-17 — the 8-tab model)
    private func buildNewTabMachine(_ n: Int, machine: [ProcessorSlot], transpose: Int = 0, hex hexOverride: UInt32? = nil) -> String {
        let hex = hexOverride ?? (n < machineHexes.count ? machineHexes[n] : 0x808080)   // PLAY columns pass a DUSK hex; PART keeps the vivid machineHexes (Paul 2026-08-30)
        buildIDCounter += 1
        let id = "b\(buildIDCounter)"
        buildMachineReg[id] = machine
        if transpose != 0 { buildMachineTranspose[id] = transpose } else { buildMachineTranspose[id] = nil }   // REGISTER HOME
        machineHueOverride[id] = hex
        buildSyncMachines()
        return id
    }
    // A NEW part starts EMPTY — NO default machine/midi chain, no rung selected (Paul 2026-08-19). The user adds a machine
    // (tap a tab / RANDOMIZE) when ready. (Was: TAB 1 seeded with a default passthrough machine.)
    private func buildSeedTab1() {
        buildPartCast = []; buildCastSlots = [:]
        for c in 0..<Snap.maxCols { buildStagingSel[c] = -1 }                 // nothing selected → nothing plays until a machine is added (§E 16-col)
        buildSelID = nil; ddMachineSel = -1
        buildPartTouched = false                                             // a fresh part re-defaults its row to the playing one on PART entry
    }
    // Seed the workshop ONCE, on first BUILD appear. (Was: 8×4 default cast; now the single TAB 1.) §2.
    func buildSeedCastIfNeeded() {
        guard !buildCastSeeded else { return }
        buildCastSeeded = true
        buildSeedTab1()
        if buildCurrentPart >= 0, buildCurrentPart < buildParts.count { buildParts[buildCurrentPart].cast = buildPartCast }
    }
    // Keep the selection within the PART's cast (its own palette). A fresh, EMPTY cast → NO selection: the footer + the
    // machine audition have nothing until the user adds a machine. Replaces the global ddEnsureSelection on BUILD. §2.
    func buildEnsureCastSelection() {
        if let cid = ddSelectedMachineID, buildPartCast.contains(cid) { return }   // already a valid cast member
        if let first = buildPartCast.first { buildSelectID(first) } else { buildSelID = nil; ddMachineSel = -1 }
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
    // user-added machines fill from the BOTTOM-RIGHT corner (slot 31 first, then 30, …) so a new machine "starts bottom-right".
    private var buildCastDefaultCount: Int { min(Self.buildDefaultTypes.count, buildPartCast.count) }
    // Is a slot part of the top-left 4×2 DEFAULT block (which is positional), vs the freely-placeable extras region?
    private func buildIsDefaultSlot(_ slot: Int) -> Bool { let row = slot / 8, col = slot % 8; return row < 2 && col < 4 }
    // The bottom-right-most FREE add slot — where the next auto-added machine lands (nil once the palette is full).
    private func buildFirstFreeCastSlot() -> Int? {
        for slot in stride(from: 31, through: 0, by: -1) where !buildIsDefaultSlot(slot) && buildCastSlots[slot] == nil { return slot }
        return nil
    }
    // Reconcile buildCastSlots with membership: drop stale slots, and give every extra member a slot (migrates old
    // parts saved before castSlots existed, and keeps auto-added machines visible).
    private func buildReslotCast() {
        buildCastSlots = buildCastSlots.filter { buildPartCast.contains($0.value) && !buildIsDefaultSlot($0.key) }
        let dc = buildCastDefaultCount
        var slotted = Set(buildCastSlots.values)
        for m in dc..<buildPartCast.count {
            let id = buildPartCast[m]
            if !slotted.contains(id), let s = buildFirstFreeCastSlot() { buildCastSlots[s] = id; slotted.insert(id) }
        }
    }
    // The next UNDEFINED global machine to materialize (nil = all 16 exist).
    private func buildFirstUndefinedGlobal() -> Int? { (0..<machineIDs.count).first { !ddMachineShown($0) } }
    // buildAddCastMachine + buildPlaceCastSlot RETIRED (Paul 2026-09-12 dead-code sweep — the empty-cast-cell long-press
    // clone gesture is gone; buildPlaceCastSlot was orphaned once buildAddCastMachine (its only caller) went).
    // Commit the pulsing candidate: a staged VARIATION becomes a NEW palette machine (carrying its machine); an existing
    // machine is simply selected. Either way the machine is SELECTED (its machine loads into the footer) — and THE TARGET
    // then marks it in the cast + on its selected grid cells, so the user edits the machine knowing what's in focus.
    // Create a machine on BUILD as a PASSTHROUGH machine (empty chain → unprocessed MIDI). A bare `defined` machine
    // has a nil templateChain, which the engine resolves via the LEGACY A-face — and every default machine is type
    // .arp, so it would play an arp the user can't see in the (empty) chain. Store a passthrough placeholder so the
    // audio matches the shown-empty chain. (user 2026-08-12)
    private func buildCreateMachine(_ i: Int) {
        guard i < machineIDs.count else { return }
        ddCreateMachine(i)
        au?.withChainMachine(machineIDs[i]) { $0 = [] }          // [] → a bypassed-passgate passthrough (not the arp A-face)
        refreshFromDocument()
    }





    // buildStagingTap RETIRED (Paul 2026-09-12 dead-code sweep — no caller; the part grid drives selection elsewhere).
    private func buildRowMachine(_ r: Int) -> String? { r >= 0 && r < 8 ? (0..<Snap.maxCols).compactMap { $0 < buildStagingCells.count && r < buildStagingCells[$0].count ? buildStagingCells[$0][r] : nil }.first : nil }   // Rooms4: bounds-safe; §E: scan all 16 columns
    private func buildSetRow(_ r: Int, to cid: String?) {         // fill (or clear) a whole row with one machine
        for c in 0..<Snap.maxCols { buildStagingCells[c][r] = cid }   // §E: fill the whole 16-col row (width governs view/play)
        if r < buildRowChain.count { buildRowChain[r] = [] }      // the row carries the machine's OWN machine (no per-row variation override)
        if r < buildRowShade.count { buildRowShade[r] = 0 }
        buildDeletedRows[r] = nil
    }
    // buildClearPartGrid + buildArchivePartToPlay RETIRED (Paul 2026-09-12 dead-code sweep — the old PROMOTE-to-play-cell
    // archive path; its only caller (roomsAssignPlayColumn/roomsFlattenPartToPlay) went in the 2026-09-12 ferry sweep).
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
    // THE PART cell machine (Paul 2026-09-05 v2): a DARK, SATURATED, FLAT version of the row's MACHINE hue (row 7 = its yellow
    // machine, etc.) — matches the row selector (same hue), no wash/fade. The bright emitter constellation rides on top.
    // partCellFill / partCellFrame RETIRED (Paul 2026-09-12 dead-code sweep — no caller; the part cells use partPos* now).
    // FIXED-BY-ROW-POSITION dark-flat ground for the BENCH surfaces — the part cells + the part/SELECT→part side rails
    // (design-cell-language.md decision 4, RATIFIED: "row 7 always yellow", fixed by POSITION not machine identity; Paul
    // 2026-09-06 — "dark machines for the side rails and bright machines for the emitters", using partRowHexes). The dark
    // ground = the row's fixed hue mixed deep into the stage; the BRIGHT row hue (partPosHue) is reserved for the identity
    // number, the focus inverse, and the stamp bloom, while the constellation stays the bright EMITTER machine.
    private func partPosHex(_ row: Int) -> UInt32 { partRowHexes[((row % partRowHexes.count) + partRowHexes.count) % partRowHexes.count] }
    private func partPosHue(_ row: Int) -> Color { Color(hex: partPosHex(row)) }
    private func partPosFill(_ row: Int) -> Color { Color(hex: mixHex(0x0E1116, partPosHex(row), 0.16)) }   // DARK + FLAT, the same recipe as partCellFill but keyed on POSITION
    private func partPosFrame(_ row: Int) -> Color { Color(hex: mixHex(0x0E1116, partPosHex(row), 0.34)) }  // subtly-lighter dark edge — never the bright hue
    // GRID REBUILD P2b (Paul 2026-09-09): the part grid's 4 rows are the ACTIVE ferry's colour in four darkening SHADES
    // (the P1 palette) — its identity carries from the ferry into the bench. Each ground is that shade darkened toward the
    // field so the bright ribbon still pops; the frame keeps more of the shade (a visible edge). The 0.5/0.28 mixes are
    // the key device tunables (how differentiable the 4 shades read vs. how dark the ground sits behind the ribbon).
    private func partFerryHue(_ row: Int) -> UInt32 { ferryShadeHex(buildFerryHex(buildActiveFerry ?? 0), row) }
    private func partFerryFill(_ row: Int) -> Color { Color(hex: mixHex(partFerryHue(row), 0x0E1116, 0.5)) }
    private func partFerryFrame(_ row: Int) -> Color { Color(hex: mixHex(partFerryHue(row), 0x0E1116, 0.28)) }
    // THE CONSTELLATION face (Paul 2026-09-05, design-cell-language.md): a dot per note (radius ∝ velocity) at (x=time,
    // y=pitch, both 0…1 with y already inverted so 0=top), joined by a faint path in x-order — the cell's output as a sigil.
    // SHARED by the live drift (buildNoteSweep + buildOutputFace playing) and the offline blueprint (buildOutputFace idle).
    // THE CONSTELLATION — a sigil: dot per note (size ∝ velocity), joined by a faint path in x-order. The caller decides what
    // the points ARE (live emitted notes when playing, the offline expected output when idle) and their brightness/position.
    private func drawConstellation(_ ctx: inout GraphicsContext, _ size: CGSize, _ points: [(x: Double, y: Double, v: Double, a: Double)], tint: Color) {
        guard !points.isEmpty else { return }
        let inset = size.height * 0.16, hh = size.height - 2 * inset
        func px(_ x: Double, _ y: Double) -> CGPoint { CGPoint(x: CGFloat(x) * size.width, y: inset + CGFloat(y) * hh) }
        if points.count > 1 {                                          // the sigil path (x-order)
            let sorted = points.sorted { $0.x < $1.x }
            var path = Path()
            for (i, p) in sorted.enumerated() { let c = px(p.x, p.y); if i == 0 { path.move(to: c) } else { path.addLine(to: c) } }
            ctx.stroke(path, with: .color(tint.opacity(0.5)), lineWidth: max(1, size.height * 0.025))
        }
        for p in points {
            let c = px(p.x, p.y), r = max(1.2, size.height * (0.028 + 0.05 * p.v))
            ctx.fill(Path(ellipseIn: CGRect(x: c.x - r, y: c.y - r, width: 2 * r, height: 2 * r)), with: .color(tint.opacity(p.a)))
        }
    }
    // THE CELL FACE (Paul 2026-09-05, corrected AGAIN): "what I see must tally with what I hear."
    //   IDLE   → the STATIC blueprint sigil (the offline expected output, `bars`) — the cell's identity at rest.
    //   PLAYING→ the ACTUAL EMITTED NOTES (the live strike feed): a dot per real note, at its real pitch, drifting right→left
    //            and lit brightest as it sounds. The dots ARE the notes you hear (by construction) → no pitch/sequence
    //            mismatch. (The blueprint is rendered against a STANDARD chord, so it can NOT be trusted to match the live
    //            output — that was the disconnect: the sigil flashed on the beat grid but showed a different chord's notes.)
    // `live` = animate the drifting piano-roll (Paul 2026-09-08: ONLY the play ferries animate now; every other cell —
    // SELECT · PART · row/side selectors — draws the STATIC blueprint constellation, no drift, no blink).
    // GRID REBUILD P2 (Paul 2026-09-08): the cell face is now the STATIC piano-roll RIBBON (GridSkin.roomsRibbonFace) —
    // no constellation, no drift, no blink, no per-cell TimelineView. The `playing`/`strikeIdx`/`live` params are kept
    // for call-site compatibility but ignored: cells are calm, and the ferry row carries the motion (its playhead/glow).
    @ViewBuilder private func buildOutputFace(_ bars: [GridSelBar], tint: Color, playing: Bool = false, strikeIdx: [Int] = [], live: Bool = false) -> some View {
        roomsRibbonFace(bars, tint: tint)
    }
    @ViewBuilder private func buildNoteSweep(indices: [Int], active: Bool, id: String?, emitter: Set<Bus> = [.a]) -> some View {
      if active, id != nil {
        let hue = emitterHue(emitter)   // ROUTING channel (Paul 2026-08-30): the drift is the cell's EMITTER machine, not its machine hue
        // Read the drifting roll LIVE from `meters` inside the TimelineView (Paul 2026-09-10): it lives off @State so a new
        // strike no longer re-runs the body — this closure re-reads it each frame instead. Only ACTIVE cells (a few at most)
        // build a TimelineView, so running it while momentarily silent is cheap (was: paused on notes.isEmpty, which needed
        // the body re-run to un-pause — the very thing we're removing).
        TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: animationsPaused)) { tl in
            let now = tl.date
            let notes = indices.flatMap { $0 >= 0 && $0 < meters.cellRoll.count ? meters.cellRoll[$0] : [] }
            Canvas { ctx, size in
                var pts: [(x: Double, y: Double, v: Double, a: Double)] = []
                for n in notes {
                    let age = now.timeIntervalSince(n.born)
                    if age < 0 || age > buildRollLife { continue }
                    let prog = age / buildRollLife                      // 0 (right, just sounded) → 1 (left, gone)
                    let fade = min(1.0, prog / 0.10) * min(1.0, (1 - prog) / 0.45)
                    let a = max(0.0, min(1.0, fade)) * (0.55 + 0.45 * n.vel)
                    pts.append((x: 1 - prog, y: 1 - n.lane, v: n.vel, a: a))   // enter RIGHT drift LEFT; lane=1 → top
                }
                drawConstellation(&ctx, size, pts, tint: hue)          // CONSTELLATION (was note bars, Paul 2026-09-05)
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


    // Open the library IN BUILD CONTEXT: its Save/Stamp act on the selected machine's chain. Remember the machine's
    // CURRENT chain so a preview can be reverted if the user leaves without APPLY.
    func buildOpenLibrary() {
        cellLibraryFromBuild = true
        buildLibraryOriginalChain = buildSelID.map { buildMachineSlots($0) }
        buildLibraryPreviewed = false
        cellLibraryList = au?.libraryCellSummaries() ?? []
        showCellLibrary = true
    }
    // Save the SELECTED machine's chain as a named library cell.
    func buildSaveMachineToLibrary(_ name: String) {
        guard let cid = buildSelID else { return }
        au?.saveChainToLibrary(machineID: cid, chain: buildMachineSlots(cid), name: name)
        cellLibraryList = au?.libraryCellSummaries() ?? []
    }
    // PREVIEW a library cell: temporarily overwrite the selected machine's chain so it auditions live. Reverted on
    // close unless the user commits with APPLY.
    func buildPreviewLibrary(_ cell: Cell?) {
        guard let cell, let cid = buildSelID else { return }
        buildWriteMachineSlots(cid, cell.processors ?? [])
        buildLibraryPreviewed = true
    }
    // APPLY — commit a library cell's chain ONTO the selected machine (keeps the machine + its I/O); no revert.
    func buildStampLibrary(_ cell: Cell?) {
        guard let cell, let cid = buildSelID else { return }
        buildWriteMachineSlots(cid, cell.processors ?? [])
        buildLibraryPreviewed = false; buildLibraryOriginalChain = nil
        showCellLibrary = false; cellLibraryFromBuild = false
    }
    // CLOSE without APPLY → restore the machine's original chain if a preview changed it.
    func buildCloseLibrary() {
        if buildLibraryPreviewed, let cid = buildSelID { buildWriteMachineSlots(cid, buildLibraryOriginalChain ?? []) }
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
                buildRecProminent(recChanLabel(rec), on: rec.inputEnabledResolved, machine: receiverGrey(i)) { toggleReceiverEnabled(i) }   // TOP: OMNI / CH n (ENABLE) — the receiver's SIGNATURE GREY (Paul 2026-08-30)
                buildReceiverLatchButton(i, rec)                                    // LATCH — SET (no mode) / mode label / "LAST N" · pulses when ready · solid when armed
                buildOctRow(oct: i < receiverOctave.count ? receiverOctave[i] : 0, onDown: { nudgeReceiverOctave(i, -1) }, onUp: { nudgeReceiverOctave(i, 1) })   // OCT −/+ (between LATCH and S/M)
                HStack(spacing: 3) {                                            // SOLO (left) · MUTE (right)
                    buildRecMini("S", on: soloed, machine: buildCyan) { toggleReceiverSolo(i) }
                    buildRecMini("M", on: rec.muted, machine: buildPink) { toggleReceiverMute(i) }
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
            case .chord:       return "CHORD"
            }
        }()
        Text(label).font(.system(size: 10, weight: .heavy, design: .monospaced)).tracking(0.5)
            .foregroundColor(engaged ? .black : .white.opacity(0.8))
            .lineLimit(1).minimumScaleFactor(0.55)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(RoundedRectangle(cornerRadius: 5).fill(engaged ? amber : amber.opacity(0.12)))
            .overlay(RoundedRectangle(cornerRadius: 5).stroke(engaged ? Color.clear : amber.opacity(0.4), lineWidth: 1.5))
            .contentShape(Rectangle())
            .onTapGesture {
                // FOUR SCALE POOLS (Paul 2026-09-04): a SCALE door's button opens the 4-pool switch/config pop-up (a SCALE
                // door self-arms via the derived pool — there's nothing to toggle here). Every other mode keeps arming.
                if rec.doorModeResolved == .scale { buildScalePopupDoor = i }
                else if rec.doorModeResolved == .chord { buildChordPopupDoor = i }   // THE CHORD DOOR: open the 4-chord pop-up
                else { buildEngageDoor(i) }
            }
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
    // the current octave amount — ORANGE for ±1, RED for ±2 (and beyond). The machine IS the octave readout. (±3 range.)
    @ViewBuilder private func buildOctRow(oct: Int, onDown: @escaping () -> Void, onUp: @escaping () -> Void) -> some View {
        let orange = Color(hex: 0xFF9F0A), red = Color(hex: 0xFF453A)
        HStack(spacing: 3) {
            buildRecMini("−", on: oct < 0, machine: oct <= -2 ? red : orange, action: onDown)   // lit when octave is DOWN
            buildRecMini("+", on: oct > 0, machine: oct >= 2 ? red : orange, action: onUp)        // lit when octave is UP
        }
    }
    // The INTERACTIVE input-velocity indicator: the incoming-velocity meter (sustained while held, brief attack flash)
    // normally; DRAG to force this door's input velocity (top = 127 · bottom = 0) via setReceiverVel; release springs
    // back to the natural velocity — the receiver mirror of buildEmitterFader. (Paul 2026-08-18)
    // One velocity-meter machine band + whether it wears the ENERGY effect (only the SELECTED machine's band — Paul 2026-08-31).
    private struct MeterBand { let color: Color; let energy: Bool; var cellIdxs: [Int] = [] }   // cellIdxs (emitter strips only, Paul 2026-09-07): the grid cells this machine feeds → each band rises to ITS OWN velocity from cellHitVel
    // The velocity-meter FILL as vertical machine bands (one per feeding/playing cell) rising to `level`. (Paul 2026-08-31)
    // `faded` (the receiver strips): EVERY band fades to alpha 0 at the bottom; the SELECTED machine's band ALSO gets the
    // INVERTED overlay (screen-blended) so it reads as energy — the pinched waist. No feed at all → a light-grey band with a
    // downward-moving shimmer ("notes that aren't on a cell", e.g. a scale-door audition), NOT cyan. Emitters (faded=false)
    // stay flat.
    @ViewBuilder private func buildMeterBands(_ bands: [MeterBand], level: Double, bandLevels: [Double]? = nil, height: CGFloat, override: Color?, faded: Bool = false) -> some View {
        if let bl = bandLevels, override == nil, !bands.isEmpty {
            // PER-BAND (emitters, Paul 2026-09-07): each machine strip rises to ITS OWN velocity (bottom-anchored), not the
            // shared emitter peak. Same flat fill + machines + spacing as below — only the per-strip HEIGHT differs. Override +
            // the receiver/no-feed paths (bandLevels nil) fall through UNCHANGED to the original block below.
            HStack(spacing: bands.count > 1 ? 0.7 : 0) {
                ForEach(bands.indices, id: \.self) { k in
                    VStack(spacing: 0) {
                        Spacer(minLength: 0)
                        Rectangle().fill(bands[k].color.opacity(0.9))
                            .frame(height: height * CGFloat(min(1, max(0, k < bl.count ? bl[k] : 0))))
                    }
                }
            }
            .frame(height: height, alignment: .bottom)
            .clipShape(RoundedRectangle(cornerRadius: 3))
        } else {
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
                            if bands[k].energy {   // the SELECTED machine only: the inverted overlay → the energy waist + glow
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
    }
    // The velocity-meter fill when NO cell feeds this door but it IS receiving (a scale-door audition, or any input not on a
    // placed cell): light grey + transparency + a soft band drifting DOWNWARD. (Paul 2026-08-31, replaces the cyan fallback.)
    @ViewBuilder private func buildMeterNoFeedBand() -> some View {
        // STATIC light grey (Paul 2026-08-31: no animation for input not assigned to a machine) — a calm translucent fill.
        Rectangle().fill(Color(white: 0.82).opacity(0.34))
    }
    @ViewBuilder private func buildReceiverFader(_ i: Int, letter: String) -> some View {
        let override = i < recvDragVel.count ? recvDragVel[i] : nil
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
                        // SIMPLE VELOCITY INDICATOR (Paul 2026-09-06): one flat bar rising to the input level — cyan for the
                        // metered/held velocity, pink while dragging the override. The per-machine feed machines + the chord/key
                        // "energy" meter treatment were stripped back; the level itself (held · attack flash · override) is unchanged.
                        RoundedRectangle(cornerRadius: 3).fill((override != nil ? buildPink : buildCyan).opacity(0.9))
                            .frame(height: g.size.height * CGFloat(min(1, max(0, level))))
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
    @ViewBuilder private func buildRecMini(_ label: String, on: Bool, machine: Color, action: @escaping () -> Void) -> some View {
        Text(label).font(.system(size: 9, weight: .heavy, design: .monospaced))
            .foregroundColor(on ? .black : .white.opacity(0.7))
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(RoundedRectangle(cornerRadius: 4).fill(on ? machine : buildCell))
            .overlay(RoundedRectangle(cornerRadius: 4).stroke(on ? Color.clear : buildEdge, lineWidth: 1))
            .contentShape(Rectangle()).onTapGesture(perform: action)
    }
    // A PROMINENT toggle (thicker edge, bold, strong lit machine) — used for LATCH and ENABLE.
    @ViewBuilder private func buildRecProminent(_ label: String, on: Bool, machine: Color, action: @escaping () -> Void) -> some View {
        Text(label).font(.system(size: 10, weight: .heavy, design: .monospaced)).tracking(0.5)
            .foregroundColor(on ? .black : .white.opacity(0.85)).lineLimit(1).minimumScaleFactor(0.6)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(RoundedRectangle(cornerRadius: 5).fill(on ? machine : buildCell))
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
                buildRecProminent("CH \(ch)", on: !muted, machine: emitterHue(Bus.allCases[i])) { toggleEmitter(i) }   // TOP: CH n — lit in the emitter's SIGNATURE machine (consistent with the MIDI-OUT toggles, Paul 2026-08-30); acts as the MUTE
                if showRack { buildRecProminent("RACK", on: racked, machine: Color(red: 1.0, green: 0.72, blue: 0.2)) { toggleRack(i) } }   // RACK (hidden on the column strip, Paul 2026-08-30)
                buildRecProminent("···", on: false, machine: buildDim) { }      // PLACEHOLDER (Paul 2026-08-30) — a future emitter control, between CH and OCT
                buildOctRow(oct: i < emitterOctave.count ? emitterOctave[i] : 0, onDown: { nudgeEmitterOctave(i, -1) }, onUp: { nudgeEmitterOctave(i, 1) })   // OCT −/+
                buildRecMini("SOLO", on: soloed, machine: buildCyan) { toggleEmitterSolo(i) }   // SOLO only (CH is the mute)
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

    // (buildReceiverFeedMachines removed 2026-09-06 — the receiver strip is a simple velocity indicator again; the fader no
    //  longer tints by the machines it feeds. The emitter side keeps its own buildEmitterPlayingHues below.)
    // The machines of every CELL currently PLAYING through emitter `e` (its velocity-strip tint) — the sounding part rungs +
    // the chain audition + the live play columns that emit on `e`. Multiple → a vertical strip of all of them. (Paul 2026-08-31)
    private func buildEmitterPlayingHues(_ e: Bus) -> [MeterBand] {
        // One band per MACHINE feeding e, in first-seen order; each band ACCUMULATES the grid cells that machine occupies so
        // the fader can rise each strip to that machine's OWN velocity (max decayed cellHitVel across its cells). (Paul 2026-09-07)
        var order: [String] = []
        var byCid: [String: (color: Color, idxs: [Int])] = [:]
        func add(_ cid: String?, color: Color? = nil, idx: Int? = nil) {
            guard let cid else { return }
            if byCid[cid] == nil { order.append(cid); byCid[cid] = (color ?? machineHue(cid) ?? buildCyan, []) }
            if let idx { byCid[cid]!.idxs.append(idx) }
        }
        // The ACTIVE ferry plays via the STAGING sequencer (rows 0–7). Map its selected rungs whenever it is ON — not only
        // when buildStagingPlaying (a shared-voice mirror) is set — so its band never falls through the gap between here and
        // the background branch below (which excludes the active ferry). Fixes the strip going blank on some ferry passes.
        let activeOn = buildActiveFerry.map { $0 >= 0 && $0 < buildPlayColOn.count && buildPlayColOn[$0] } ?? false
        if buildStagingPlaying || activeOn {                                                         // PART: the selected rungs that emit on e
            for c in 0..<Snap.maxCols { let r = c < buildStagingSel.count ? buildStagingSel[c] : -1
                if r >= 0, buildRowMachine(r) != nil, buildRowEmittersResolved(r).contains(e) { add(buildRowMachine(r), idx: c * Snap.rows + r) } }
        }
        // CHAIN audition → the STANDARDIZED machine hue (LIGHT GREY on SELECT), not the old palette machine. (Paul 2026-08-31)
        if ddSolo, buildDefaultEmitters.contains(e) { add(ddSelectedMachineID, color: buildMachineHue(roomsRoom), idx: buildChainAuditionRow) }
        // BACKGROUND ferries (Paul 2026-09-08): a non-active "on" ferry plays via the FLATTEN on play-layer row (base+c) —
        // map EVERY non-nil step's machine that emits on e (its index = step·rows + (base+c)), so a multi-machine part shows
        // all its bands and every step reflects, not just step 0. (The active ferry is on the STAGING branch above.)
        for c in 0..<8 where c != buildActiveFerry && c < buildPlayColOn.count && buildPlayColOn[c] {
            let steps = c < buildPlayColSteps.count ? buildPlayColSteps[c] : []
            let stepEmit = c < buildPlayColStepEmit.count ? buildPlayColStepEmit[c] : []
            for s in 0..<steps.count {
                guard let cid = steps[s] else { continue }
                let em = s < stepEmit.count ? stepEmit[s] : (c < buildPlayColEmit.count ? buildPlayColEmit[c] : [.a])
                if em.contains(e) { add(cid, idx: s * Snap.rows + (Snap.playLayerRowBase + c)) }
            }
        }
        return order.map { MeterBand(color: byCid[$0]!.color, energy: false, cellIdxs: byCid[$0]!.idxs) }
    }
    // The interactive velocity fader: the meter (emitPeak, decayed) normally; while DRAGGED it forces the emitter's
    // output velocity (top = 127 · bottom = 0/KILL) via setVelOverride, and releases (springs back) on lift.
    @ViewBuilder private func buildEmitterFader(_ i: Int, letter: String) -> some View {
        let override = i < emitDragVel.count ? emitDragVel[i] : nil
        let playing = buildEmitterPlayingHues(Bus.allCases[i])   // the machine(s) of every cell playing through this emitter (vertical bands if >1)
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
                    // PER-MACHINE velocity (Paul 2026-09-07, SMOOTHED — "too jumpy"): each band rises to ITS OWN velocity, as max
                    // over the machine's cells of a SINGLE smooth curve: while the cell is SOUNDING it HOLDS STEADY at the sounding
                    // velocity (cellSoundVel — no per-note flash-to-full, which was the jumpiness); once RELEASED it decays smoothly
                    // over 0.9 s from the note's velocity (timestamp-based off cellReleasedAt, so it's frame-smooth, not 4 Hz-stepped).
                    // Held chords sit steady, releases fall like the old meter; the rhythm still reads as each note's held pulse.
                    let bandLevels: [Double]? = override != nil ? nil : playing.map { band in
                        guard !band.cellIdxs.isEmpty else { return level }
                        var best = 0.0
                        for idx in band.cellIdxs where idx >= 0 && idx < meters.cellSoundVel.count {   // read live from `meters` (off @State, Paul 2026-09-10)
                            let lvl: Double
                            if idx < meters.cellSounding.count && meters.cellSounding[idx] {   // HELD → steady at the sounding velocity
                                lvl = meters.cellSoundVel[idx]
                            } else {                                             // RELEASED → smooth 0.9 s decay from the note's velocity
                                let age = tl.date.timeIntervalSince(idx < meters.cellReleasedAt.count ? meters.cellReleasedAt[idx] : .distantPast)
                                lvl = max(0, meters.cellHitVel[idx] * (1 - age / 0.9))
                            }
                            best = max(best, lvl)
                        }
                        return best
                    }
                    ZStack(alignment: .bottom) {
                        RoundedRectangle(cornerRadius: 3).fill(Color.black.opacity(0.5))
                        buildMeterBands(playing, level: level, bandLevels: bandLevels, height: g.size.height, override: override != nil ? buildPink : nil)   // per-machine strip heights (tinted by the playing cell(s))
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
    @ViewBuilder private func buildProcessorPanel(slot: Int, proc: ProcessorSlot, cid: String, contentW: CGFloat) -> some View {
        let hue = buildCardHue   // the ONE machine/card hue (grey on the SELECT audition) — never the raw gsAud palette throwback
        // BODY ONLY (Paul 2026-09-10): the old header (machine cell · emblem · name · BYPASS/DELETE/CANCEL/DONE) is GONE — the
        // TAB ROW (buildProcCardTabs) now heads the card; bypass = long-press a chain box, delete = the trash. Just the controls.
        VStack(alignment: .leading, spacing: 0) {
            // SCROLLABLE BODY — SOURCE/OCT, the truth strips, and the controls.
            ScrollView(.vertical, showsIndicators: true) {
              VStack(alignment: .leading, spacing: 0) {
            // (SOURCE / OCT stage header removed 2026-09-12 — the §1 ANATOMY per-stage CHAIN|MIDI IN|BOTH + OCT ±3 feature was deleted.)
            // (RIFF CAPTURE row removed 2026-09-10 — the §2 capture feature was deleted.)
            // (ROW SELECTOR — the "Long press to copy" 1–8 tabs — removed, no longer required. Paul 2026-08-30)
            buildTruthStrips().padding(.horizontal, 16).padding(.vertical, 8)   // §1 IN | OUT truths — silence explains itself
            Rectangle().fill(hue.opacity(0.25)).frame(height: 1)
            buildSlotBox(slot, proc, cid: cid).padding(16)   // CONTROLS — reuse ProcessorBox (our chrome hidden)
              }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        // (The pop-up chrome — buildPanel fill · rounded clip · thick hue border · drop shadow · tap-swallow — is REMOVED so the
        // card reads as part of the page. The card region (roomsProcessorCardAt) provides the flat fill + clip. Paul 2026-09-10.)
    }

    // §1 TRUTH STRIPS (Paul 2026-08-22, the TUTTI-confusion cure): a slim IN | OUT band above the controls. IN = the
    // held-note silhouette at the machine's INPUT door — and when NOTHING is held it TEACHES ("nothing held — LATCH or
    // play at INPUT A"), so silence explains itself instead of reading as breakage (the spec's §7 teach-in-place law).
    // OUT = a live mini-roll of what the plugin emits (the processor's effect made visible). v1: OUT aggregates the whole
    // board — during a chain audition (part stopped) that IS the chain's output. Tap-to-expand (the §4 STAGE EYE) is later.
    // Is the EDITED cell the one actually sounding right now? In "PLAY THIS MIDI CHAIN" the OUT IS this chain (true). In
    // "PLAY THIS PART" it's only this cell when the edited machine's rung is the active one under the playhead — otherwise
    // the OUT strip is showing OTHER cells of the part, so we say so + dim it (idea 24 follow-up, Paul 2026-08-25).
    // Is MIDI actually reaching THIS focused processor instance right now? (Paul 2026-09-12) — the ONE gate the IN piano +
    // the OUT roll share: a chain audition IS this processor; a PART cell only while its row is the active rung under the
    // playhead (the playhead on a column where this row isn't selected ⇒ NOT processing); nothing when stopped/no voice.
    var buildProcessingNow: Bool {
        switch buildDisplayVoice {
        case .chain: return true
        case .part:
            guard d.playing, let r = buildSelectedRow else { return false }
            return d.effColumn >= 0 && d.effColumn < buildStagingSel.count && buildStagingSel[d.effColumn] == r
        case .none: return false
        }
    }
    private var buildTruthOutContext: (label: String, live: Bool) {
        switch buildDisplayVoice {
        case .chain: return ("this chain", true)
        case .part:  return (buildProcessingNow ? "this cell — live" : "part — not this cell", buildProcessingNow)
        case .none:  return ("press ▶ to hear it", false)
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
                    buildInKeyboard(held, hue: hue).opacity(buildProcessingNow ? 1 : 0.4)   // BRIGHT when MIDI reaches this instance; GRAYED (notes still shown) when the playhead isn't on this row (Paul 2026-09-12)
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
        let chain = selectedMachineChain()
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
    // STAGE-EYE live beat — extrapolated from the free-running anchor (Paul 2026-09-11), so the eye's playhead self-animates
    // inside its own TimelineView instead of reading the polled `d.effColumn`/`d.beat` (which had to fold into the whole-page
    // @State → a per-step re-render + playhead stutter). -1/stopped handled by the callers.
    private func buildEyeLiveBeat(_ date: Date) -> Double {
        meters.beatAnchor + date.timeIntervalSince(meters.beatAnchorAt) * meters.tempo / 60.0
    }
    private func buildEyeEuclid(_ proc: ProcessorSlot, hue: Color) -> some View {
        let n = max(2, min(16, proc.params.euclidSteps ?? 8))
        let k = max(0, min(n, proc.params.euclidPulses ?? 5))
        let base = euclidPattern(pulses: k, steps: n, rotation: proc.params.euclidRot ?? 0)
        let inv = proc.params.euclidInvert ?? false
        return TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: animationsPaused || !d.playing)) { tl in
        let live = d.playing ? (((Int((buildEyeLiveBeat(tl.date) / max(0.0001, stepBeats)).rounded(.down)) % n) + n) % n) : -1
        Canvas { ctx, size in
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
    }
    // GENERIC MECHANISM (types without bespoke art yet): the 8-column position lane, the live column lit.
    private func buildEyeStepLane(_ proc: ProcessorSlot, hue: Color) -> some View {
        return TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: animationsPaused || !d.playing)) { tl in
        let col = d.playing ? (((Int((buildEyeLiveBeat(tl.date) / max(0.0001, stepBeats)).rounded(.down)) % 8) + 8) % 8) : -1
        Canvas { ctx, size in
            let cw = size.width / 8
            for s in 0..<8 {
                let cell = CGRect(x: CGFloat(s) * cw + 2, y: 6, width: max(2, cw - 4), height: size.height - 12)
                ctx.fill(Path(roundedRect: cell, cornerRadius: 5), with: .color(.white.opacity(0.08)))
                if s == col { ctx.fill(Path(roundedRect: cell, cornerRadius: 5), with: .color(hue.opacity(0.9))) }
            }
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
        return TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: animationsPaused || !d.playing)) { tl in
        let pos = (d.playing && rate > 0) ? ((Int((buildEyeLiveBeat(tl.date) / rate).rounded(.down)) % cyc) + cyc) % cyc : -1
        Canvas { ctx, size in
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
    // The IN silhouette: a compact C1–C7 piano (proper white/black keys), held notes filled the machine hue.
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

    // ProcessorBox for a BUILD machine-template slot — mirrors DiagView.slotBox but writes MACHINE-scoped (the selected
    // machine's templateChain via withChainMachine). Our own header carries Delete/Bypass, so the box's chrome is hidden.
    @ViewBuilder private func buildSlotBox(_ i: Int, _ slot: ProcessorSlot, cid: String) -> some View {
        let sc: Machine = { var c = Machine(machineID: cid, type: slot.type); c.paramsA = slot.params; return c }()
        // RATCHET PATTERN NOTE clock (Paul 2026-09-07): the playhead advances one column per note through, at the rate notes
        // arrive = the nearest upstream DRIVER's note rate. Read it from the chain so the visual sweeps in NOTE mode (0 = none).
        let driverNoteRate: Double = {
            guard slot.type == .ratchet else { return 0 }
            let chain = buildMachineChain(cid); let drivers: Set<ProcessorType> = [.arp, .ratchet, .strum, .euclid, .burst, .cascade, .drone, .shift, .humanize, .weave, .riff, .hocket]
            var k = min(i, chain.count) - 1
            while k >= 0 { if drivers.contains(chain[k].type) { return chain[k].params.rate?.beats ?? 0 }; k -= 1 }
            return 0
        }()
        ProcessorBox(
            machine: sc, machineIndex: -1, face: .a,
            onEdit: { mutate in
                buildChainEditSlot(i) { s in
                    var tmp = Machine(machineID: cid, type: s.type); tmp.paramsA = s.params
                    mutate(&tmp); s.params = tmp.paramsA
                }
            },
            onTranspose: { _ in }, onMorph: { _ in },
            onSetTypeA: { t in buildChainSetType(i, t) },
            height: 260, slotMode: true, slotBypassed: slot.bypassed,
            accentOverride: buildCardHue,   // the ONE machine/card hue (grey on the SELECT audition) — matches the machine box
            // PLAYHEADS (Paul 2026-09-11): the matrix/lane/passgate playheads now SELF-CLOCK inside ProcessorBox from the beat
            // anchor below (gridStepBeats = the scene step), so `liveStep`/`passHead` no longer fold the step into the whole-page
            // @State (which re-rendered the page every step → the per-step playhead stutter). Left at their -1 defaults.
            beatAnchor: meters.beatAnchor, beatAnchorAt: meters.beatAnchorAt, tempo: meters.tempo, clockPlaying: d.playing,   // RATCHET PATTERN extrapolates its OWN-clock playhead (Paul 2026-09-07)
            driverNoteRate: driverNoteRate,   // NOTE clock: the upstream driver's note rate → the playhead sweeps per-note
            gridStepBeats: stepBeats,   // the DEFAULT grid-column clock for the generic matrices/lanes/passgate (Paul 2026-09-11)

            onBypass: { buildChainToggleBypass(i) },
            onRemove: { buildChainRemoveSlot(i); buildEditSlot = nil },
            onMacro: nil, plainTitle: true, showSlotChrome: false,
            avoidInputNotes: recvHeldNotes.map { $0.map(Int.init) },   // AVOID piano: per-input held notes (armed/scale doors report their pool) — live while the editor is open
            avoidChainInputDoor: buildSelectedRow.map { buildRowReceiverResolved($0) } ?? buildSelReceiver)   // the door feeding THIS chain → the OUTPUT piano predicts from its notes
    }

    // BUILD chain edits — machine-scoped + POSITION-PRESERVING: every edit works on the SHOWN chain and is written
    // whole with setMachineChain (so slot indices stay put; a deleted slot leaves a passthrough GAP, not a shift).
    private func buildApplyChain(_ chain: [ProcessorSlot]) {
        buildKeepRowGen()   // editing the processor chain acts as KEEP
        guard let cid = ddSelectedMachineID else { return }   // guard ABOVE the record so a nil selection never pushes a no-op undo step (U10 fix 2026-08-27)
        buildRecordUndo("chain")   // BUILD UNDO: chain edit (add/remove/move/param) — coalesced so a param scrub is one step
        // idea 24 TOUCH-TO-DIFF: every chain edit funnels here — stamp the edit clock so the OUT read-out glows and the
        // notes the NEW settings produce (born after the gesture started) stand out from the old ones, as you drag.
        let now = Date(); if buildEditStartedAt == nil { buildEditStartedAt = now }; buildLastEditAt = now
        buildWriteMachineSlots(cid, chain)
        // PERSIST SELECT-GRID CELL EDITS (Paul 2026-09-10): a plain cell audition edits the transient gsAud. Store the edited
        // chain onto the cell's in-memory OVERRIDE so LEAVING the cell and RETURNING restores it — buildGridSelChainAt reads
        // the override BEFORE the dealt/library source (which would otherwise reload the ORIGINAL, dropping the edits). Only a
        // real cell selection (buildGridSelSel != nil); a ferry aim (sel == nil) mirrors to its part row below instead.
        if cid == buildGridSelAudID, let sel = buildGridSelSel, sel >= 0, sel < 64 {
            // EDIT = COMMIT (Paul 2026-09-12): the FIRST control change NAMES the cell (a short lowercase hash of the chain)
            // and recolours it to the SELECTED selector's pre-allocated colour; the machine box + card follow (buildMachineHue
            // reads machineHueOverride[gsAud] once committed). Once named it keeps that name; later edits only update the chain.
            // A tap-select alone never commits (that loads via buildGridSelLoadChain, not here).
            let selColour = buildFerryHex(buildActiveFerry ?? 0)
            if buildGridSelName[sel] == nil { buildGridSelName[sel] = buildChainShortHash(chain) }
            machineHueOverride[buildGridSelAudID] = selColour
            buildGridSelOverride[sel] = (chain, selColour)
        }
        // FERRY MIRROR (Paul 2026-08-30): a SELECT-grid ferry aim edits the transient gsAud (so the audition stays quantized-
        // swappable). Card edits were auditioned but never written back — an ARP change was HEARD in the audition so it read
        // as "working", a PASSGATE change wasn't obvious → "not applied", and NEITHER persisted to the part row. Mirror the
        // edited chain (minus its baked register-home) straight to the aimed row's REAL machine so the part row updates too.
        if cid == buildGridSelAudID, let mr = buildFerryMirrorRow, let real = buildRowMachine(mr) {
            let t = buildMachineTranspose[real] ?? 0
            buildWriteMachineSlots(real, buildStripRegisterHome(chain, transpose: t))
        }
        // PLACED: a pending tab whose chain has diverged from its source is committed (stops pulsing). (2026-08-17)
        if let p = buildPendingTab, buildRowMachine(p) == cid, chain != buildPendingSource {
            buildPendingTab = nil; buildPendingSource = []
        }
    }
    // Reverse buildGridSelLoadChain's register-home bake: it inserts a leading TRANSPOSE utility (== the machine's own
    // transpose) so the ephemeral audition swaps atomically. Dropping it before writing to the REAL machine (which stores
    // the register home in buildMachineTranspose, not as a slot) avoids double-transposing. No baked slot ⇒ returned as-is.
    private func buildStripRegisterHome(_ chain: [ProcessorSlot], transpose: Int) -> [ProcessorSlot] {
        guard transpose != 0, let first = chain.first, first.type == .transpose,
              (first.params.utilTranspose ?? 0) == max(-24, min(24, transpose)) else { return chain }
        return Array(chain.dropFirst())
    }
    // A SHORT lowercase hash NAME for a chain (Paul 2026-09-12) — a deterministic 4-char base-36 FNV-1a over the chain's
    // sorted-key JSON, so the name is derived from the machine's content. Assigned once on a cell's first edit.
    private func buildChainShortHash(_ chain: [ProcessorSlot]) -> String {
        let enc = JSONEncoder(); enc.outputFormatting = .sortedKeys
        let data = (try? enc.encode(chain)) ?? Data()
        var h: UInt64 = 1469598103934665603
        for b in data { h = (h ^ UInt64(b)) &* 1099511628211 }
        let alphabet = Array("abcdefghijklmnopqrstuvwxyz0123456789")
        var s = "", v = h
        for _ in 0..<4 { s.append(alphabet[Int(v % 36)]); v /= 36 }
        return s
    }
    private func buildChainEditSlot(_ i: Int, _ mutate: (inout ProcessorSlot) -> Void) {
        var c = selectedMachineChain(); guard i < c.count else { return }; mutate(&c[i]); buildApplyChain(c)
    }
    private func buildChainToggleBypass(_ i: Int) { buildChainEditSlot(i) { $0.bypassed.toggle() } }
    private func buildChainSetType(_ i: Int, _ t: ProcessorType) { buildChainEditSlot(i) { $0.type = t } }
    private func buildChainRemoveSlot(_ i: Int) {                  // DELETE → leave an empty (passthrough) box, keep positions
        var c = selectedMachineChain(); guard i < c.count else { return }; c[i] = buildPassthroughSlot(); buildApplyChain(c)
    }
    // DRAG-TO-REORDER (Paul 2026-08-25): a POSITIONAL move — the dragged processor LANDS at the target box (box index `to`,
    // OVERWRITING whatever was there) and its ORIGINAL box is vacated (→ empty passthrough). Nothing else shifts. So RIFF on
    // box 1 + ARP on box 2, RIFF→box 3 ⇒ box 1 empty · box 2 ARP · box 3 RIFF. The chain folds in box order (composeChainSet).
    private func buildChainMoveSlot(from: Int, to: Int) {
        guard from != to, from >= 0, to >= 0, to < 8 else { return }
        var c = selectedMachineChain()
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
        let apply: (inout MachineParams) -> Void   // pre-set the mode ({ } for a single-mode card)
    }
    struct BuildCardGroup { let title: String; let note: String?; let cards: [BuildCard] }

    // THE STOREFRONT SPLIT (Paul 2026-08-22): multi-mode stages appear as SEPARATE cards, each pre-setting its mode;
    // the mode is then FIXED (no in-editor radio — GridUI dropped it) and WRITTEN on the chain box (`buildProcLabel`).
    // To change mode you pick a different card. Grouped by musical intent; each card carries a plain one-liner.
    // Codable type IDs never rename — a split card is (type + a params mode-preset).
    private var buildCatalog: [BuildCardGroup] {
        func C(_ n: String, _ b: String, _ t: ProcessorType, _ a: @escaping (inout MachineParams) -> Void = { _ in }) -> BuildCard {
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
                C("VELOCITY", "A per-step velocity sequencer — draw the accents, or pass a step through.", .velocity),
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
            case .soundingOut: m = "OUT ALL"
            }
        default:       m = ""
        }
        return m.isEmpty ? base : "\(base) \(m)"
    }

    // ADD a catalog CARD at box `i`: populate the box with the card's type, pre-set its mode, open its editor.
    private func buildChainAddCard(_ i: Int, _ card: BuildCard) {
        if ddSelectedMachineID == nil {                                    // no machine holds the chain (SELECT grid, nothing auditioned since the auto-audition was retired) →
            buildMachineReg[buildGridSelAudID] = []                        // start a FRESH transient so buildApplyChain has a target + the card can open (BUG fix 2026-08-29)
            machineHueOverride[buildGridSelAudID] = machineHexes.first ?? 0x808080
            buildMachineTranspose[buildGridSelAudID] = 0
            buildSyncMachines()
            buildSelID = buildGridSelAudID
        }
        var c = selectedMachineChain()
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
    // on ONE reusable transient ephemeral machine, so the document is untouched until COMMIT (non-destructive by
    // construction). Banks v1: DEALT (Dice.rollEnsemble ×8 = 64 seeded chains, RE-DEAL) + MY LIBRARY (saved + factory
    // cells). FACTORY-as-a-curated-bank + EXCLUSIVE-OFF layering are deferred (flagged for Paul). The reel records every
    // audition for free (real emission). §6 governor: ordinary derivation, standing caps apply.
    private var buildGridSelAudID: String { "gsAud" }   // the ONE reusable transient machine that carries the browsed chain

    func buildOpenGridSel() {
        buildGridSelArrivalRow = buildSelectedRow                        // FREEZE the arrival row (buildSelectedRow resolves live)
        buildGridSelPriorSel = buildSelID                                // snapshot the pre-open selection so CANCEL restores it
        if let r = buildGridSelArrivalRow { buildSelReceiver = buildRowReceiverResolved(r) }   // audition through the ARRIVAL row's door (faithful preview)
        // THE LIBRARY (saved-cell disk scan + decode · the 200-chain factory set) OFF THE MAIN THREAD (Paul 2026-09-11,
        // startup perf): this ran SYNCHRONOUSLY on the SELECT room's first appear — the default — blocking the UI from
        // showing. The DEAL/corpus are already async; load the library the same way and fill buildGridSelLib when ready. The
        // grid shows at once; the MY-LIBRARY section populates a beat later (faithful — same result, just not blocking).
        // INSTANT SEED (Paul 2026-09-11): the CHEAP library cells (saved disk scan + the hand-authored factory cells) load
        // SYNCHRONOUSLY so the SELECT grid is populated AT ONCE. The heavy part — the ~200 Dice.factorySet chains, each of
        // which runs the offline Router (tens of seconds total) — appends in the BACKGROUND. Before, the WHOLE library incl.
        // the Dice chains loaded async, so the grid sat EMPTY for tens of seconds at startup (the reported bug).
        let saved = au?.libraryCellSummaries() ?? []
        buildGridSelLib = saved + (au?.handFactorySummaries() ?? [])      // cheap → instant; the grid has real cells immediately
        buildGridSelLibFactoryFrom = saved.count                         // entries at/after this index are FACTORY (resolve by section, not name)
        buildGridSelRecomputeCategory()                                  // fill the category slice now so cells are PRESENT on the first frame
        let auRef = au
        runOnLargeStack {                                                // large stack: the FULL factory warms Dice.factorySet (deep Router eval)
            let savedFull = auRef?.libraryCellSummaries() ?? []
            let factory = auRef?.factoryLibrarySummaries() ?? []        // the full set (hand + the 200 Dice chains)
            DispatchQueue.main.async {
                self.buildGridSelLib = savedFull + factory              // append the Dice chains now they're ready
                self.buildGridSelLibFactoryFrom = savedFull.count
                self.buildGridSelRecomputeCategory()
                self.buildGridSelComputeCellRolls()                     // faces for the now-complete library
            }
        }
        buildGridSelSel = nil
        buildGridSelBuildCorpus()                                        // §3.1 kick the pregen corpus (background, once) — DEAL upgrades to it when ready
        if buildGridSelDealt.isEmpty || !buildGridSelCorpus.isEmpty { buildGridSelDeal() }   // corpus ready ⇒ instant draw; else a fresh 64
        else { buildGridSelComputeCellRolls() }                          // dealt already stocked (reopen) → compute its drifting faces now
        buildGridSelOpen = true
    }
    // Open it for the SELECT room only if it isn't already live (roomsPage drives this on room entry).
    func buildEnsureGridSelOpen() { if !buildGridSelOpen { buildOpenGridSel() } }
    // DEALT — 64 seeded, replay-safe chains (8 archetypes × 8 re-rolls). rollEnsemble runs the offline Router many times,
    // so generate OFF the main thread with a spinner (64 = 8× the grid-RANDOMIZE cost, too much to block on).
    private func buildGridSelDeal() {
        // §3.1 THE PREGEN CORPUS: once the pool exists, DEAL is INSTANT — a seeded shuffle drawing 64 (RE-DEAL bumps the
        // seed → a fresh 64). While the corpus is still building, fall back to a fresh 64-roll so the first open isn't empty.
        buildGridSelLastSlot.removeAll()                                // a re-deal remaps index→chain → drop the last-viewed-slot memory (Paul 2026-09-10)
        // COMMITTED cells PERSIST across a re-deal (Paul 2026-09-12): their override pins the index, so DON'T clear
        // buildGridSelName here — the background corpus upgrade re-deals, and wiping names made committed cells revert by themselves.
        if !buildGridSelCorpus.isEmpty {
            var rng = DiceRNG(seed: buildGridSelDealSeed)
            buildGridSelDealt = Array(buildGridSelCorpus.shuffled(using: &rng).prefix(64))
            buildGridSelComputeCellRolls()                               // the drifting note faces for the freshly-dealt 64
            return
        }
        guard !buildGridSelGenerating else { return }                    // re-entrancy: one deal at a time (racing deals could land out of seed order)
        buildGridSelGenerating = true
        let seed = buildGridSelDealSeed
        runOnLargeStack {                                                // large stack: rollEnsemble runs the offline Router many times
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
        runOnLargeStack(qos: .utility) {                                 // large stack: rollCorpus runs the offline Router many times
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
        buildGridSelOverride[i] = (chain, machineHexes[i % 16])          // the NEW instance (in-memory; disk library untouched)
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
            return (e.chain, e.transpose, machineHexes[((i % 8) * 2) % 16])
        } else {
            guard i >= 0 && i < buildGridSelCatIndices.count else { return nil }   // CATEGORY: grid position i → the i-th library entry in the current category
            let L = buildGridSelCatIndices[i]
            guard L >= 0 && L < buildGridSelLib.count else { return nil }
            let name = buildGridSelLib[L].name
            // Resolve by SECTION, not by name — a saved cell may share a factory cell's name (saved rows are [0, factoryFrom)).
            let cell = L >= buildGridSelLibFactoryFrom ? au?.factoryLibraryCell(name: name) : au?.loadLibraryCell(name: name)
            return (cell?.processors ?? [], 0, machineHexes[i % 16])       // hue position-based
        }
    }
    private func buildGridSelPresent(_ i: Int) -> Bool { buildGridSelOverride[i] != nil || (buildGridSelTab == 0 ? i < buildGridSelDealt.count : i < buildGridSelCatIndices.count) }   // a cell-to-cell COPY makes an empty position present too (Paul 2026-08-28); library filtered by CATEGORY (2026-08-29)
    private func buildGridSelCellHex(_ i: Int) -> UInt32 { buildGridSelOverride[i]?.hex ?? (buildGridSelTab == 0 ? machineHexes[((i % 8) * 2) % 16] : machineHexes[i % 16]) }

    // AUDITION — register the browsed chain on the ONE transient machine, select it, and drive the existing chain-voice
    // path: turn the chain voice ON (quantized) if not already, else swap which chain (quantized). Piece plays on.
    private func buildGridSelAudition(_ i: Int) {
        guard let hit = buildGridSelChainAt(i) else { return }
        buildGridSelStampSourceRow = nil                                 // a library CELL is now the active source → clear the active side button (mutual exclusivity; no-op in old BUILD)
        buildGridSelLoadChain(hit.chain, transpose: hit.transpose, hex: hit.hex, sel: i)   // a DEALT/LIBRARY cell — its index is the commit source
    }
    // A select-grid TAP: SELECT MODE focuses the cell into the machine (no play/stop); else it auditions. (Paul 2026-08-31)
    private func buildGridSelTapCell(_ i: Int) {
        guard buildGridSelPresent(i) else { return }
        // Paul 2026-09-05: a NEW select-grid cell after a PART promote starts with NULL I/O + all-8-pulsing (silent until wired).
        if buildPartJustPromoted { buildPartJustPromoted = false; buildIONullPending = true }
        if buildSelectMode { buildGridSelFocus(i); buildSelectMode = false } else { buildGridSelAudition(i) }   // SELECT ends after one pick (Paul 2026-08-31)
    }
    // FOCUS ONLY (SELECT mode): load the cell into the machine + select it, but DON'T start/swap the audition voice. (Paul 2026-08-31)
    private func buildGridSelFocus(_ i: Int) {
        guard let hit = buildGridSelChainAt(i) else { return }
        buildGridSelStampSourceRow = nil
        buildGridSelLoadChain(hit.chain, transpose: hit.transpose, hex: hit.hex, sel: i, play: false)
    }
    // THE MOST IMPACTFUL PROCESSOR (Paul 2026-09-10): when a chain is chosen (or defaulted) on the SELECT grid, the
    // processor card defaults to whichever slot carries the most impact — a note-generating DRIVER (arp/riff/…) wins over
    // a harmony/dynamics shaper, which wins over a utility/routing stage. Skips bypassed slots; nil for an empty/all-util
    // chain (→ the card shows its invitation). Ranking mirrors isDriverType's spirit (drivers first).
    private func buildImpactRank(_ t: ProcessorType) -> Int {
        switch t {
        case .arp, .riff:                                                    return 100   // the headline drivers (Paul's examples)
        case .ratchet, .strum, .euclid, .burst, .cascade, .weave, .hocket:  return 90    // other note-generating drivers
        case .chords, .harmonize:                                           return 70    // harmony set-shapers
        case .tutti, .chance, .split, .avoid, .length, .velocity:           return 60    // set / dynamics shapers
        case .drone, .shift, .humanize:                                     return 50    // texture generators
        case .echo, .glide, .mod:                                          return 40
        default:                                                           return 20    // octave/transpose/channel/nudge/dest/muteMatrix/tap/passgate — utility & routing
        }
    }
    private func buildMostImpactfulSlot(_ chain: [ProcessorSlot]) -> Int? {
        var best: Int? = nil; var bestRank = Int.min
        for (i, s) in chain.enumerated() where !s.bypassed {
            let r = buildImpactRank(s.type)
            if r > bestRank { bestRank = r; best = i }                       // first slot wins ties → earliest-in-chain
        }
        return best
    }
    // Load a chain onto the ONE transient audition machine, select it, and drive the chain voice (quantized). Shared by a
    // cell audition (sel = the cell index → the commit source) and a ROW press (sel = nil → a view/hear of that part's chain).
    private func buildGridSelLoadChain(_ raw: [ProcessorSlot], transpose: Int, hex: UInt32, sel: Int?, play: Bool = true) {
        if let prev = buildGridSelSel, prev != sel, let s = buildEditSlot { buildGridSelLastSlot[prev] = s }   // REMEMBER the last processor viewed on the cell we're leaving (Paul 2026-09-10)
        buildGridSelSel = sel
        buildGridSelActiveRoll = gridSelRollBars(raw)                     // the piano-roll shown on the cell + the right column
        // BAKE the register home into the CHAIN (a leading TRANSPOSE utility) rather than the ephemeral machine's transpose:
        // the chain is baked into the published scene + swapped atomically at the STEP boundary, whereas the machine's
        // transpose is re-resolved on every rebuild — so an ephemeral transpose would jump the still-sounding old chain a
        // step early on a quantized swap. This keeps the whole swap quantized. (transpose stays 0 on the transient machine.)
        var chain = raw
        if transpose != 0 { var t = ProcessorSlot(type: .transpose); t.params.utilTranspose = max(-24, min(24, transpose)); chain.insert(t, at: 0) }
        buildMachineReg[buildGridSelAudID] = chain
        machineHueOverride[buildGridSelAudID] = hex
        buildMachineTranspose[buildGridSelAudID] = 0
        buildSyncMachines()
        buildSelID = buildGridSelAudID; ddMachineSel = -1                  // ddSelectedMachineID now returns the transient
        // THE PROCESSOR CARD (Paul 2026-09-10): RETURNING to a cell re-opens the LAST processor viewed there; a first visit
        // defaults to the most impactful stage of the chain (arp/riff …) — either way the card lands on a processor, not the
        // empty invitation. (The stored slot is guarded against a chain that changed length under it.)
        if let s = sel, let last = buildGridSelLastSlot[s], last < chain.count { buildEditSlot = last }
        else { buildEditSlot = buildMostImpactfulSlot(chain) }
        buildAddSlot = nil; buildStageEye = false
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
    // transient, and re-select the pre-open machine so nothing is stranded. The deployed piece plays on.
    private func buildGridSelStopAudition() {
        buildFerryMirrorRow = nil                                        // stop mirroring — the transient is being reaped
        guard buildGridSelSel != nil || ddSolo || buildPendingWorkshopVoice != nil || buildPendingReengage else { return }
        buildGridSelSel = nil; buildGridSelActiveRoll = []
        buildPendingWorkshopVoice = nil; buildPendingReengage = false
        buildMachineReg[buildGridSelAudID] = nil; machineHueOverride[buildGridSelAudID] = nil; buildMachineTranspose[buildGridSelAudID] = nil
        if buildVoiceOwner == .chain { buildVoiceOwner = .none }
        buildSelID = buildGridSelPriorSel; ddMachineSel = machineIDs.firstIndex(of: buildGridSelPriorSel ?? "") ?? -1
        au?.clearMachineSolo(); buildSyncMachines(); buildPublishScene()
    }
    // HOLD-TO-STAMP (Paul 2026-08-26): while a browse CELL auditions, HOLDING a part-row stamps the auditioning chain onto
    // that row — KEEPING the row's own machine — WITHOUT closing the browser (so you can stamp one machine onto several
    // parts). A populated row keeps its hue + register (chain overwritten); an empty row mints a machine carrying the chain.
    // The active STAMP SOURCE — one of two (mutually exclusive, "one thing is active"): a browse CELL
    // (buildGridSelSel, SELECT library) or an active SIDE BUTTON's populated part row (buildGridSelStampSourceRow).
    // This is what a long-press copy stamps. (Paul 2026-08-28)
    private func buildGridSelStampSource() -> (chain: [ProcessorSlot], transpose: Int)? {
        // Resolve the three candidates from @State, then defer to the pure, unit-tested priority (roomsStampSource):
        // the live audition (gsAud) holds card EDITS — on SELECT BOTH a browse cell AND an aimed side button load + edit
        // it (buildSelID == gsAud), so it wins (register home baked → transpose 0). PART edits the REAL machine instead
        // (buildSelID != gsAud there → falls through to the browse cell / side row, which already reflects the edit).
        // (BUG 2026-08-29: the old code read buildGridSelChainAt/buildMachineChain = the ORIGINAL, dropping edits.)
        roomsStampSource(
            auditionEdited: buildSelID == buildGridSelAudID ? buildMachineReg[buildGridSelAudID] : nil,
            libraryCell: buildGridSelSel.flatMap { buildGridSelChainAt($0) }.map { ($0.chain, $0.transpose) },
            sideRow: buildGridSelStampSourceRow.flatMap { s in buildRowMachine(s).map { (buildMachineChain($0), buildMachineTranspose[$0] ?? 0) } })
    }
    // Make the side button the ONE active source (clear the library-cell source) — "one thing is active". (Paul 2026-08-28)
    private func buildRoomsSetActiveSide(_ n: Int) {
        if n != buildRowGenConfirm?.row { buildRowGenConfirm = nil }   // focusing a DIFFERENT row drops any pending KEEP|TRY-AGAIN (never sticks) — Paul 2026-09-11
        buildGridSelStampSourceRow = n; buildGridSelSel = nil
    }
    // buildGridSelStampCommit (the ferry/rail long-press capture-into-mirror) is RETIRED (Paul 2026-09-12 — ferry drag-and-drop).

    @ViewBuilder private func buildGridSelCell(_ i: Int, w: CGFloat, h: CGFloat, greyUnlessSel: Bool = false, vPad: CGFloat = 3) -> some View {
        let present = buildGridSelPresent(i)
        let hue = Color(hex: buildGridSelCellHex(i))
        let sel = buildGridSelSel == i
        // COMMITTED (Paul 2026-09-12): a cell that's been edited + named wears the SELECTED colour (not grey) + shows its hash
        // name — even when not the current audition. It overrides the grey-unless-selected treatment below.
        let committed = greyUnlessSel && buildGridSelName[i] != nil
        // greyUnlessSel (SELECT grid, Paul 2026-08-29): an unselected present cell is a DARK-GREY button with a LIGHT-GREY
        // piano roll; only the SELECTED cell wears its chain's machine + white roll. Else (old grid selector) = coloured.
        let unselGrey = greyUnlessSel && !sel && !committed
        // SELECT grid (greyUnlessSel): the PLAYING (selected) cell is ONE machine — the INVERSE of the unselected dark-grey
        // view (a LIGHT-grey button with a DARK roll), NOT the chain's own hue (Paul 2026-08-30). Non-SELECT grids keep the hue.
        let selGrey = greyUnlessSel && sel && !committed
        let fill = present ? (sel ? (selGrey ? buildSelectGrey : hue.opacity(0.85)) : (unselGrey ? Color(white: 0.16) : hue.opacity(0.42))) : Color.white.opacity(0.03)   // selGrey ALTERNATES two bright shades per selection (matches the machine box; Paul 2026-09-01)
        let rollTint: Color = selGrey ? Color(white: 0.22) : (unselGrey ? Color(white: 0.78) : .white)
        // TASTEFUL CHEQUER (Paul 2026-08-31): the SELECT grid reads as a BOARD — a faint two-tone parity wash on every
        // non-selected cell (the classic chessboard), subtle enough not to fight the roll. SELECT grid only (greyUnlessSel);
        // the bright selected/focus cell stays clean.
        let chequer = greyUnlessSel && !sel && !committed && ((i / 8 + i % 8) % 2 == 0)
        ZStack {
            RoundedRectangle(cornerRadius: 6).fill(fill)
            if chequer { RoundedRectangle(cornerRadius: 6).fill(Color.white.opacity(0.05)) }   // the lighter square of the board
            if present && !committed {   // the piano-roll face — shown UNTIL the cell is committed, then REPLACED by its name (Paul 2026-09-12)
                buildGridSelPianoRoll(sel ? buildGridSelActiveRoll : (buildGridSelCellRoll[i] ?? []), playing: sel, tint: rollTint, strikeIdx: sel ? (buildChainAuditionRow.map { [$0] } ?? []) : [])
                    .padding(.vertical, vPad).padding(.horizontal, 3).opacity(sel ? 1.0 : 0.7)   // SELECT grid pads the roll 15% top/bottom (Paul 2026-08-29)
            }
            if committed, let nm = buildGridSelName[i] {   // the generated hash name, REPLACING the roll on a committed cell (Paul 2026-09-12)
                Text(nm).font(.system(size: min(11, h * 0.4), weight: .heavy, design: .monospaced)).tracking(0.5)
                    .foregroundColor(.black.opacity(0.8)).lineLimit(1).minimumScaleFactor(0.5).padding(.horizontal, 3)
                    .shadow(color: .white.opacity(0.25), radius: 1)
            }
            if sel {       // THE ACTIVE CELL — a STATIC strong frame (Paul 2026-09-08: was a breathing strobe)
                RoundedRectangle(cornerRadius: 6).stroke(selGrey ? Color.black : Color.white, lineWidth: 3)
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
    // extrapolated beat the cell playheads use). Same machine scheme (the caller's `tint`).
    @ViewBuilder private func buildGridSelPianoRoll(_ bars: [GridSelBar], playing: Bool, tint: Color, strikeIdx: [Int] = []) -> some View {
        buildOutputFace(bars, tint: tint, playing: playing, strikeIdx: strikeIdx)   // SELECT face = the unified expected-output constellation (Paul 2026-09-05 v2)
    }
    // THE DRIFTING NOTE FACE (Paul 2026-08-26): notes scroll RIGHT→LEFT, looping — the same aesthetic as the part/play grid
    // cells (buildNoteSweep). Every present cell + row selector wears its chain's fingerprint drifting across it (a browse
    // preview: you can't run 64 live voices, so each cell loops its chain's note pattern). Opacity by velocity.
    @ViewBuilder private func buildGridSelDriftFace(_ bars: [GridSelBar], animated: Bool, period: Double = 2.4, tint: Color = .white) -> some View {
        buildOutputFace(bars, tint: tint, playing: animated)   // Paul 2026-09-05 v2: the row selectors wear the SAME constellation as the cells (was drifting bars)
    }
    // Compute the drifting-note fingerprint for every present cell of the CURRENT tab, off the main thread (64× gridSelRollBars
    // is too much to block on — the same reason DEAL is backgrounded). A generation token discards a batch if the deal/tab
    // changed under it. Chains are gathered on the main thread first (library resolves via `au`), then bars computed pure.
    private func buildGridSelComputeCellRolls() {
        buildGridSelRollGen &+= 1
        let gen = buildGridSelRollGen
        var chains: [(Int, [ProcessorSlot])] = []
        for i in 0..<64 where buildGridSelPresent(i) { if let hit = buildGridSelChainAt(i) { chains.append((i, hit.chain)) } }
        // Paul 2026-09-05: do NOT clear the cache here — keep the old faces until the new ones are ready, else every cell
        // blanks in the async gap ("goes blank then redraws"). The gen guard + full-dict swap below replace them atomically.
        runOnLargeStack {                                                // large stack: gridSelRollBars → Dice.runRecorder (deep Router eval) ×64
            var out: [Int: [GridSelBar]] = [:]
            for (i, chain) in chains { out[i] = gridSelRollBars(chain) }
            DispatchQueue.main.async { if self.buildGridSelRollGen == gen { self.buildGridSelCellRoll = out } }
        }
    }
    private var buildGridSelStampDur: Double { 0.65 }   // still LIVE: the SELECT cell→cell long-press copy (roomsCopyToSelectCell)
    // buildGridSelStampPressing / buildGridSelStampFire / buildGridSelStampSweep (the ferry+rail long-press copy gesture,
    // its rising-fill + commit-bloom animation) are RETIRED (Paul 2026-09-12) — superseded by ferry drag-and-drop.
    private func buildGridSelAimRow(_ n: Int) {
        buildGridSelArrivalRow = n
        buildSelReceiver = buildRowReceiverResolved(n)                    // the audition plays through the AIMED part's door + emitters (so the MIDI-IN/OUT chips reflect it)
        buildPartEmitters = buildRowEmittersResolved(n)
        receivers = au?.uiReceivers() ?? receivers
        // LOAD the pressed part's own chain into the MIDI CHAIN panel + audition it (Paul 2026-08-26). sel = nil → it's a
        // view/hear of what's on the row, not a commit source (re-deal or tap a cell to change it). Empty row → clear.
        if let cid = buildRowMachine(n) {
            buildFerryMirrorRow = n                                       // a POPULATED ferry aim MIRRORS this row: card edits on gsAud write straight back to it (Paul 2026-08-30)
            buildGridSelLoadChain(buildMachineChain(cid), transpose: buildMachineTranspose[cid] ?? 0, hex: buildBaseHex(cid), sel: nil)
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
