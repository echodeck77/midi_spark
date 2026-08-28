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
private let buildHues: [Color] = [
    Color(red: 0.91, green: 0.70, blue: 0.23),   // amber
    Color(red: 0.19, green: 0.83, blue: 0.91),   // cyan
    Color(red: 0.29, green: 0.49, blue: 1.00),   // blue
    Color(red: 0.91, green: 0.36, blue: 0.44),   // red
    Color(red: 0.35, green: 0.84, blue: 0.48),   // green
    Color(red: 0.69, green: 0.42, blue: 0.91),   // purple
]
private let buildPanel = Color(red: 0.08, green: 0.09, blue: 0.11)
private let buildCell  = Color(red: 0.10, green: 0.12, blue: 0.15)
private let buildDim   = Color(white: 0.36)
private let buildPink  = Color(red: 0.94, green: 0.41, blue: 0.85)
private let buildCyan  = Color(red: 0.19, green: 0.83, blue: 0.91)
private let buildRed   = Color(red: 0.91, green: 0.36, blue: 0.44)   // ROW 8 CLEAR + destructive verbs
private let buildEdge  = Color(white: 1).opacity(0.17)   // §0 MUTED-CHROME: a neutral whisper for default (non-armed) chrome borders — replaces standing cyan strokes
// BUILD grid PIANO-ROLL (Paul 2026-08-19): one scrolling note mark on a cell face; `lane` = pitch (0…1), born = when it sounded.
struct BuildRollNote: Equatable { var born: Date; var vel: Double; var lane: Double }

// BUILD UNDO (Paul 2026-08-27): one complete snapshot of the BUILD page's authoring @State + the document — every field a
// user action can change, so a restore is whole (never partial). Value types only (cheap COW copies).
struct BuildSnapshot {
    var stagingCells: [[String?]]; var stagingSel: [Int]; var stagingLane: UInt8
    var parts: [BuildPart]; var currentPart: Int; var returnPart: Int?
    var partEmitters: Set<Bus>; var partRate: StepRate?; var partLen: Int?
    var partCast: [String]; var castSlots: [Int: String]; var rowUnder: [String?]
    var rowReceiver: [Int?]; var rowEmitters: [Set<Bus>?]
    var performCells: [[String?]]; var performChain: [[[ProcessorSlot]]]; var performRecv: [Int]
    var performEmit: [Set<Bus>]; var performPart: [Int]; var performMute: Set<Int>
    var performStagingRow: [Int]; var performLane: UInt8
    var scenes: [BuildSceneSnapshot]; var activeScene: Int; var row8Cells: [Row8Cell]; var row8On: [Bool]
    var selID: String?; var selReceiver: Int
    var colourReg: [String: [ProcessorSlot]]; var colourTranspose: [String: Int]; var hueOverride: [String: UInt32]
    var idCounter: Int
    var doc: PluginState
}
private let buildRollLife = 1.6   // seconds a note takes to cross the cell
private let buildPartInk = Color(white: 1).opacity(0.9)  // §2 BRIGHTNESS = WHICH PART: a NEUTRAL bright accent (no second hue) — the part's presence across bench + stage

// iteration 4: the spring-held workbench verbs that replace the drag (the house law). Skeleton: tap arms/disarms.
enum BuildGridMode: String { case play = "PLAY", edit = "EDIT" }   // the per-grid PLAY/EDIT radio (play grid only now; the part grid's EDIT mode was retired 2026-08-16)
// The part grid's ROW-BUTTON mode (Paul 2026-08-16): a radio that changes what the left row buttons DO — SELECT the
// whole row's rung · PLACE the selected colour · MUTATE a value-tweaked variant of it.
enum BuildRowMode: String, CaseIterable { case select = "SELECT", place = "PLACE", mutate = "MUTATE" }
enum BuildFill { case none, cell, grid }   // header playhead fill period: none · one step (.cell) · the whole loop (.grid)

// BuildPart / BuildUnassignedData moved to BuildModel.swift (now persisted + test-target-visible).

extension DiagView {

    @ViewBuilder func buildPage(_ size: CGSize) -> some View {
        // AUv3 views get an initial ZERO / degenerate layout pass; laying the grids out then would compute a NEGATIVE
        // column width → SwiftUI's fatal "Invalid frame dimension" (the plugin fails to load in AUM). Draw nothing
        // until a real, finite size arrives.
        if size.width.isFinite, size.height.isFinite, size.width > 80, size.height > 80 {
            ZStack {
                // LANDSCAPE-ONLY (Paul 2026-08-24): always use the landscape layout — the app is designed for landscape, so
                // a narrow/portrait host pane keeps the landscape structure rather than switching to a separate portrait tree.
                AnyView(buildLandscape(size))
                if let slot = buildEditSlot { AnyView(buildProcessorEditor(slot: slot, size: size)) }   // the processor pop-up editor
                if buildStageEye, let slot = buildEditSlot { AnyView(buildStageEyeView(slot: slot, size: size)) }   // §4 THE STAGE EYE — layered above the editor (keeps the OUT feed flowing)
                if let slot = buildAddSlot { AnyView(buildProcessorPicker(slot: slot, size: size)) }    // the ADD-processor picker
                if buildFlowOpen { AnyView(buildFlowPopup(size: size)) }                               // the signal-flow diagram pop-up
                if let kind = buildGridPopup { AnyView(buildGridPopupView(kind, size: size)) }          // the full-screen grid pop-up
                if reelShowPopup { AnyView(buildReelPopup(size: size)) }                                 // THE PASS BROWSER pop-up
                if buildMidiConfigOpen { AnyView(buildMidiConfigSheet(size: size)) }                     // THE MIDI INPUTS sheet (config-sheets stage 5)
                if buildRackConfigOpen { AnyView(buildRackConfigSheet(size: size)) }                     // THE OUTPUT CHAIN sheet (config-sheets §6)
                if buildMidiOutConfigOpen { AnyView(buildMidiOutConfigSheet(size: size)) }               // THE MIDI OUTPUTS sheet (emitter stamp channels)
                if buildGridSelOpen { AnyView(buildGridSelectorOverlay(size: size)) }                    // THE GRID SELECTOR — the 8×8 chain browser
                if buildRow8EditOpen { AnyView(buildRow8EditPage(size: size)) }                          // ROW 8 — the action-cell authoring page (§4)
            }
            .overlay(alignment: .top) { buildIOHoldBanner() }                                            // "HOLD TO APPLY TO ALL" (Paul 2026-08-19)
            .fileImporter(isPresented: Binding(get: { buildFileImportDoor != nil }, set: { if !$0 { buildFileImportDoor = nil } }),
                          allowedContentTypes: [UTType.midi, UTType(filenameExtension: "mid") ?? .data], allowsMultipleSelection: false) { result in
                buildHandleFileImport(result)                                                             // FILE import → decode + load onto the picking door
            }
            .onChange(of: activeSceneIdx) { _ in buildSyncSceneSwitch(activeSceneIdx) }                    // SCENES V2: the EXISTING scene chips switched → swap the BUILD play-grid arrangement
        } else {
            Color.clear
        }
    }
    @ViewBuilder private func buildIOHoldBanner() -> some View {
        if let m = buildIOHoldMsg {
            Text(m).font(.system(size: 12, weight: .heavy, design: .monospaced)).tracking(1).foregroundColor(.black)
                .padding(.horizontal, 16).padding(.vertical, 9)
                .background(Capsule().fill(buildCyan))
                .padding(.top, 10).allowsHitTesting(false).transition(.opacity)
        }
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
                ZStack(alignment: .topTrailing) {
                    Text(["A", "B", "C", "D"][i]).font(.system(size: 15, weight: .black, design: .monospaced))
                        .foregroundColor(on ? .black : .white.opacity(0.7))
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
                    ForEach(DoorMode.allCases, id: \.self) { m in buildDoorModeOption(i, m, r: r) }
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
                buildConfigButton("MIDI IN")  { buildMidiConfigOpen = true }    // the MIDI-IN doors sheet
                buildConfigButton("MIDI OUT") { buildMidiOutConfigOpen = true } // the emitter stamp-channels sheet
                buildConfigButton("RACK")     { buildRackConfigOpen = true }    // the rack / OUTPUT CHAIN sheet (config-sheets §6)
                buildConfigButton("ROW 8")    { buildRow8EditSlot = max(0, buildRow8EditSlot); buildRow8EditOpen = true }   // the ROW 8 action-cell authoring page (Paul 2026-08-24: edit lives in the header, after RACK)
            }
            buildReelButton()                                   // RECORD — top-right (Paul 2026-08-23); handles the pass-browser hide + share anchor
        }
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
    func buildSetPartLen(_ n: Int?) {
        buildPartLen = n
        if buildCurrentPart >= 0, buildCurrentPart < buildParts.count { buildParts[buildCurrentPart].length = n }   // authoritative for performLen mapping
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

    // ── LANDSCAPE: three EQUAL columns (palette · staging · play) over the full-width machinery strip ──────────────
    @ViewBuilder private func buildLandscape(_ size: CGSize) -> some View {
        let avail = max(1, size.width - BuildGeom.colGap * 2 - 20)
        let leftW = max(1, avail / 3 * 0.726)                      // the MACHINE column: 0.968 × 0.75 → 25% narrower (Paul 2026-08-18)
        let gridColW = max(1, (avail - leftW) / 2)                 // staging + play split the reclaimed width
        // the PERFORM grid is widest: LEFT multi-row valve + LEFT single-row valve + 8 grid cells + RIGHT chevrons = 11 cells (+ 10 gaps).
        let cell = max(BuildGeom.cellMin, min(BuildGeom.cellMax, (gridColW - BuildGeom.cellGap * 10) / 11))
        VStack(spacing: 10) {
            HStack(alignment: .top, spacing: BuildGeom.colGap) {
                // AnyView boundaries: opaque `some View` types get INLINED into the parent's concrete type, so the
                // whole page collapses into ONE giant nested generic whose metadata instantiation overflows the Swift
                // demangler's stack (SIGSEGV opening BUILD). AnyView is a nominal type the demangler won't recurse
                // through — each column's type is instantiated separately + bounded.
                AnyView(buildPaletteColumn(colW: leftW, cell: cell).frame(width: leftW, alignment: .center))
                // the two GRID columns are grouped so the combined I/O box (buildIOBox) can span both, directly below them
                AnyView(VStack(spacing: 8) {
                    HStack(alignment: .top, spacing: BuildGeom.colGap) {
                        AnyView(buildStagingColumn(cell: cell).frame(width: gridColW, alignment: .center))
                        AnyView(buildPlayColumn(cell: cell).frame(width: gridColW, alignment: .center))
                    }
                    AnyView(buildIOBox())
                }.frame(width: gridColW * 2 + BuildGeom.colGap, alignment: .center))
            }
        }
        .padding(.horizontal, 10).padding(.top, 6)
    }

    // ── PORTRAIT: height is abundant → a plain stack (palette → staging → play → machinery) ────────────────────────
    // (buildPortrait retired 2026-08-24 — LANDSCAPE-ONLY; git history keeps the vertical-stack layout if ever needed.)

    // ── LEFT COLUMN: play-cell · part · input(+keyboard) · cast 4×4 (+🎲) · output · APPLY TO STAGING · litter ──────
    // IMPORTANT: keep this VStack SHALLOW — the INPUT/CAST/OUTPUT groups are SEPARATE opaque sub-views. A single
    // deeply-nested SwiftUI view type here makes the Swift runtime's type-metadata demangler recurse until it
    // overflows the stack when the AU instantiates the view → SIGSEGV the moment BUILD opens (device crash 2026-08-11).
    @ViewBuilder private func buildPaletteColumn(colW: CGFloat, cell: CGFloat) -> some View {
        let castW = max(160, colW - 4)                            // the cast + processor boxes FILL the column width
        VStack(alignment: .center, spacing: 8) {
            AnyView(buildColumnButton("PLAY THIS MIDI CHAIN", active: buildDisplayVoice == .chain, fill: .grid, action: { buildRequestWorkshopVoice(buildDisplayVoice == .chain ? .none : .chain) })).padding(.bottom, 6)   // tap = play/STOP the chain; sweeps over the whole scene like the grids (Paul 2026-08-18)
            AnyView(VStack(spacing: 8) {                          // THE OUTLINED MACHINE SECTION: ROW-SELECTOR tabs · receiver toggles · chain · buttons · emitter toggles (tabs moved INSIDE the border, Paul 2026-08-25)
                AnyView(buildColourTabs(castW: castW, cell: cell))    // the ROW SELECTOR tabs — now WITHIN the selected-colour frame
                AnyView(buildMachineBlock(castW: castW, cell: cell))
                AnyView(buildEmitterToggles(castW: castW)).padding(.top, 16)
            }
            .padding(10)
            // §3 THE QUIET LEFT BOX (design 2026-08-17): the frame is NEUTRAL chrome — the loud full-saturation hue box
            // was a CHANNEL COLLISION (frames = voice/zone duty, hue = machine duty). It gains the voice accent ONLY when
            // the chain audition is sounding (the frame doing its own job); the machine's hue speaks through the chips,
            // the slot tints, and a thin low-alpha SPINE on the left edge (the thread law's original form).
            // HIDE the selected-colour box while a processor CARD is open — show it only when the card is closed AND
            // PLAY THIS MIDI CHAIN is selected (Paul 2026-08-25). Otherwise the frame is the quiet neutral chrome.
            .overlay(RoundedRectangle(cornerRadius: 14).stroke(buildShowColourBox ? buildSelHue : buildEdge, lineWidth: buildShowColourBox ? 2 : 1))
            .overlay(alignment: .leading) { if buildShowColourBox { RoundedRectangle(cornerRadius: 1.5).fill(buildSelHue.opacity(0.5)).frame(width: 2).padding(.vertical, 9).padding(.leading, 1) } })
            Spacer(minLength: 0)                                 // any remaining column space sits below (RECORD/RATE/CONFIG moved to the top header, Paul 2026-08-23)
        }
        .frame(maxWidth: .infinity, alignment: .center)
    }

    // The 8×8-equivalent machine block. An INVISIBLE, untouchable header row lands the cast one cell down, on the
    // grids' DATA top (matching their loop-key row) rather than their header. Then the cast (rows 1–4) and the
    // chain-as-boxes (rows 5–8) stack to exactly 8 grid cells tall, so all three columns read at equal height.
    @ViewBuilder private func buildMachineBlock(castW: CGFloat, cell: CGFloat) -> some View {
        VStack(spacing: BuildGeom.castGap) {                      // (the colour TABS moved up to buildPaletteColumn, above the outlined section — Paul 2026-08-18)
            AnyView(buildReceiverSelector(castW: castW)).padding(.top, 6).padding(.bottom, 16)   // the MIDI-IN (receiver) selector — door CONFIG moved to the MIDI CONFIG sheet (config-sheets §5, Paul 2026-08-20)
            AnyView(HStack(alignment: .top, spacing: BuildGeom.castGap) {   // the CHAIN verb stack (LEFT) + the VERTICAL 2×4 MIDI chain (RIGHT) — Paul 2026-08-18
                AnyView(buildChainButtonStack(width: (castW / 2 - BuildGeom.castGap / 2) * 0.75,
                                              height: 4 * (cell * 2 + BuildGeom.castGap) + 3 * BuildGeom.castGap))   // LEFT: centred verb stack
                AnyView(buildProcessorBlock(castW: castW, cell: cell))      // RIGHT: 2×4 of 2×2-cell boxes — ~half the width
            })
        }
    }
    // The verb button stack, right of the MIDI chain. LEFT chevrons (<<<) act on the SELECTED colour's midi chain;
    // RIGHT chevrons (>>>) act on the PART grid. LIBRARY opens the cell library. (Paul 2026-08-18)
    @ViewBuilder private func buildChainButtonStack(width: CGFloat, height: CGFloat, showGrid: Bool = true) -> some View {
        VStack(spacing: BuildGeom.castGap) {                                  // the CHAIN-scope verbs — SHARE the fixed height (fill:true) so adding GRID never overflows/resizes the chain grid (Paul 2026-08-23)
            buildChainBtn("LIBRARY", fill: true)   { buildOpenLibrary() }
            if showGrid { buildChainBtn("GRID", fill: true) { buildOpenGridSel() } }   // THE GRID SELECTOR — hidden in the new interface (the SELECT room IS the grid, Paul 2026-08-28)
            buildChainBtn("RANDOMIZE", fill: true) { buildRandomizeSimple() } // reroll the chain
            buildChainBtn("MUTATE", fill: true)    { buildMutateChain() }     // nudge the chain
            buildChainBtn("CLEAR", fill: true)     { buildClearChain() }      // empty the chain
            HStack(spacing: BuildGeom.castGap) {                              // COPY | PASTE — copy this chain into a new row position (Paul 2026-08-25)
                buildChainBtn("COPY", fill: true) { buildCopyChain() }
                buildChainBtn("PASTE", enabled: !(buildChainClipboard ?? []).isEmpty, fill: true) { buildPasteChain() }   // disabled until the buffer holds a chain
            }
        }
        .frame(width: width)
        .frame(height: height, alignment: .center)                           // the stack is EXACTLY this tall (matches the 4-row processor block); the buttons share it
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
        VStack(spacing: gap) {
            AnyView(roomsPlayHeader(room)).frame(height: m.navH)             // BAND 1 — PLAY, parallel with the ▲PLAY door
            AnyView(roomsRecorderRow(castW: castW, h: m.ch))                 // BAND 2 — RECORD, parallel with the header row (moved up per Paul's stacking, ferry §2)
            VStack(spacing: 8) {                                            // THE INTERIOR COLUMN — from the grid's interiorTop to its bottom
                AnyView(buildReceiverSelector(castW: castW))                 // MIDI IN A–D — pinned at the interior TOP
                AnyView(HStack(alignment: .top, spacing: cgap) {           // verbs + the 2×4 MIDI chain
                    AnyView(buildChainButtonStack(width: (castW / 2 - cgap / 2) * 0.75, height: 4 * (cell * 2 + cgap) + 3 * cgap, showGrid: false))
                    AnyView(buildProcessorBlock(castW: castW, cell: cell))
                })
                Spacer(minLength: 8)
                AnyView(buildEmitterToggles(castW: castW))                   // MIDI OUT A–D — pinned at the interior BOTTOM (the grid's last row line)
            }.frame(height: m.interiorH)
        }
        .padding(pad)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(RoundedRectangle(cornerRadius: 12).fill(Color.white.opacity(0.05)))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(buildCyan.opacity(0.35), lineWidth: 1.5))   // matches the grid box + seam styling
    }
    // THE PLAY SECTION HEADER — the room-aware play/stop button, styled as a section header (equal height to the ▲PLAY
    // nav door). SELECT plays the CHAIN audition, PART plays the PART (mutually exclusive voices). (Paul 2026-08-28)
    @ViewBuilder func roomsPlayHeader(_ room: Room) -> some View {
        let partRoom = room == .part
        let voice: BuildWorkshopVoice = partRoom ? .part : .chain
        buildColumnButton(partRoom ? "PLAY THIS PART" : "PLAY THIS MIDI CHAIN", active: buildDisplayVoice == voice, fill: .grid,
                          action: { buildRequestWorkshopVoice(buildDisplayVoice == voice ? .none : voice) })
            .frame(height: 40)
    }
    // THE RECORDER ROW — the reel/RECORD button below the emitter toggles (Paul 2026-08-28). Reuses buildReelButton (the
    // breathing tape glyph → opens the pass browser).
    @ViewBuilder private func roomsRecorderRow(castW: CGFloat, h: CGFloat = 34) -> some View {
        HStack(spacing: 8) {
            Spacer()
            buildReelButton()
            Text("RECORD").font(.system(size: 10, weight: .heavy, design: .monospaced)).tracking(1).foregroundColor(buildDim)
                .contentShape(Rectangle()).onTapGesture { reelShowPopup = true }
            Spacer()
        }
        .frame(width: castW, height: h)                                     // fills the RECORD band (the grid's header-row height ch → ≥44pt target)
        .background(RoundedRectangle(cornerRadius: 8).fill(buildCell))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(buildEdge, lineWidth: 1))
    }

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
        if buildGridSelSel == nil && buildGridSelStampSourceRow == nil {      // RANDOMIZE THE INITIAL SELECTION (Paul 2026-08-28): nothing chosen yet → audition a random library cell
            if let i = (0..<64).filter({ buildGridSelPresent($0) }).randomElement() { buildGridSelAudition(i) }
        }
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
                ScrollView(.vertical, showsIndicators: false) {
                    buildProcessorPanel(slot: slot, proc: chain[slot], cid: cid, contentW: w).frame(width: w).frame(minHeight: h, alignment: .top)
                }
                .frame(width: w, height: h)
                .clipShape(RoundedRectangle(cornerRadius: 8))                 // clip the scroll to the panel's own (less-rounded) box
                .shadow(color: .black.opacity(0.5), radius: 14, y: 6)         // depth so it reads as a floating overlay
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
    @ViewBuilder func roomsPlayNavSliver(width: CGFloat, height: CGFloat) -> some View {
        RoundedRectangle(cornerRadius: 4).fill(buildCyan)
            .frame(width: width, height: height)
            .overlay(HStack(spacing: 4) { Image(systemName: "chevron.up"); Text("PLAY") }.font(.system(size: min(11, height * 0.7), weight: .heavy, design: .monospaced)).foregroundColor(.black))
            .contentShape(Rectangle()).onTapGesture { roomsRoom = .play }
    }
    @ViewBuilder func roomsSeamSliver(to room: Room, chevron: String, width: CGFloat, height: CGFloat) -> some View {
        RoundedRectangle(cornerRadius: 4).fill(buildCyan)
            .frame(width: width, height: height)
            .overlay(Text(chevron).font(.system(size: min(13, width * 0.7), weight: .heavy)).foregroundColor(.black))
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
    // A SELECT track-head (top-row selector) — tap toggles the track (play/stop grammar); shows the slot's hue if occupied.
    @ViewBuilder func roomsTrackHead(_ t: Int) -> some View {
        let on = t >= 0 && t < roomsTrackOn.count && roomsTrackOn[t]
        RoundedRectangle(cornerRadius: 4).fill(on ? buildCyan.opacity(0.9) : Color.white.opacity(0.11))
            .overlay(Text("\(t + 1)").font(.system(size: 10, weight: .heavy, design: .monospaced)).foregroundColor(on ? .black : .white.opacity(0.55)))
            .contentShape(Rectangle())
            .onTapGesture { if t >= 0 && t < roomsTrackOn.count { roomsTrackOn[t].toggle() } }
    }
    // ── THE SELECT GRID UNIT — the library grid + its edge selectors + the ▲PLAY sliver, in ONE box. The part↔select
    // SEAM has moved OUT to the far side of the page (roomsSeamColumn); the grid reflows to use the full width. (Paul 2026-08-28)
    @ViewBuilder func roomsSelectGridUnit(m: RoomsMetrics) -> some View {
        GeometryReader { g in
            let gap = RoomsMetrics.gap, pad = RoomsMetrics.pad                 // heights from the shared lattice (m); width per-view
            let cw = max(6, (g.size.width - 2 * pad - 8 * gap) / 9)            // 9 cols (8 interior + side button) → FILLS the width
            let ch = m.ch, navH = m.navH
            let interiorW = cw * 8 + gap * 7
            let interiorH = m.interiorH
            VStack(alignment: .leading, spacing: gap) {
                roomsPlayNavSliver(width: interiorW, height: navH)          // ▲PLAY directly above the track row, over cols 1–8
                VStack(spacing: gap) {
                    HStack(spacing: gap) {                                   // track (col-select) row + corner
                        ForEach(0..<8, id: \.self) { c in roomsTrackHead(c).frame(width: cw, height: ch) }
                        Color.clear.frame(width: cw, height: ch)
                    }
                    ForEach(0..<8, id: \.self) { r in                        // interior rows + right side buttons
                        HStack(spacing: gap) {
                            ForEach(0..<8, id: \.self) { c in roomsSelectGridCell(r * 8 + c).frame(width: cw, height: ch) }
                            roomsSideButton(r).frame(width: cw, height: ch)
                        }
                    }
                }
                .overlay(alignment: .topLeading) {                          // the processor card over the interior 8×8
                    roomsProcessorCardAt(x: 0, y: ch + gap, w: interiorW, h: interiorH)
                }
            }
            .padding(pad)
            .background(RoundedRectangle(cornerRadius: 12).fill(Color.white.opacity(0.05)))
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(buildCyan.opacity(0.35), lineWidth: 1.5))
        }
    }
    // The grid's cell WIDTH for a given box width — so the caller can size the far-edge seam column to 50% of a cell,
    // matching the old in-grid seam. SELECT = 9 cols, PART = 10 cols. (Paul 2026-08-28)
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
            buildGridSelCell(i, w: cg.size.width, h: cg.size.height)
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
        let cid = buildRowColour(n)
        let tint = cid.flatMap { colourColor($0) }
        let active = buildGridSelStampSourceRow == n                      // THE active side button — white border (§ "one cell or one side button is active")
        RoundedRectangle(cornerRadius: 5).fill(active ? (tint ?? buildCyan) : (cid != nil ? (tint ?? buildRowButtonFill).opacity(0.4) : buildRowButtonFill))
            .frame(height: height)
            .overlay { if cid != nil { buildGridSelDriftFace(buildGridSelRowRoll[n] ?? [], animated: false).padding(2).opacity(0.65) } }   // DSP: static fingerprint (no per-slot animation)
            .overlay(alignment: .bottom) { buildGridSelStampSweep(n, height: height) }   // the rising white fill + post-copy confirm
            .clipShape(RoundedRectangle(cornerRadius: 5))
            .overlay(RoundedRectangle(cornerRadius: 5).stroke(active ? Color.white : (tint ?? buildEdge), lineWidth: active ? 2 : 1))
            .overlay { if cid == nil { RoundedRectangle(cornerRadius: 5).stroke(style: StrokeStyle(lineWidth: 1, dash: [3, 2])).foregroundColor(buildEdge) } }
            .overlay(Text("\(n + 1)").font(.system(size: min(13, height * 0.4), weight: .heavy, design: .monospaced)).foregroundColor(active ? .black.opacity(0.75) : (tint ?? .white.opacity(0.7))))
            .contentShape(Rectangle())
            .onTapGesture { part ? roomsTapPartSide(n) : roomsTapSide(n) }
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
    // TAP a SELECT side button — it becomes the active selection + stamp source (if populated), and auditions its chain.
    private func roomsTapSide(_ n: Int) {
        buildGridSelAimRow(n)                                            // load + audition the part's chain (reflect its door/emitters in the panel)
        buildRoomsSetActiveSide(n)                                      // this side button is now THE active selection (white border) + the copy source when populated
    }
    // ── THE PART GRID UNIT (rooms) — the old-gui part/staging grid + its nav slivers, ALL in ONE box (Paul 2026-08-28):
    // a LEFT seam sliver (◂ → SELECT, beside the left side buttons) · LEFT row-slots (the selection) · an 8×8 interior
    // (one rung/col + playhead) · a RIGHT row-selector rail · a top track-head row · a ▲PLAY sliver above it (over the
    // interior cols). NO loop keys, no padding between the nav slivers and the grid.
    @ViewBuilder func roomsPartGrid(m: RoomsMetrics) -> some View {
        GeometryReader { g in
            let gap = RoomsMetrics.gap, pad = RoomsMetrics.pad               // heights come from the shared lattice (m); width stays per-view
            let cw = max(6, (g.size.width - 2 * pad - 9 * gap) / 10)          // 10 cols (leftRail + 8 interior + rightRail) → FILLS the width (seam moved out)
            let ch = m.ch, navH = m.navH
            let interiorW = cw * 8 + gap * 7
            let interiorH = m.interiorH
            let leftInset = cw + gap                                        // leftRail → the interior's left edge
            VStack(alignment: .leading, spacing: gap) {
                HStack(spacing: 0) {                                        // ▲PLAY over the interior columns (past the left rail)
                    Color.clear.frame(width: leftInset)
                    roomsPlayNavSliver(width: interiorW, height: navH)
                }
                HStack(spacing: gap) {                                      // track-head row over the interior
                    Color.clear.frame(width: cw)
                    ForEach(0..<8, id: \.self) { c in colSelCellPart(c).frame(width: cw, height: ch) }
                    Color.clear.frame(width: cw)
                }
                HStack(alignment: .top, spacing: gap) {                     // body: left rail | interior+playhead | right rail
                    VStack(spacing: gap) { ForEach(0..<8, id: \.self) { n in roomsSideButton(n, part: true).frame(width: cw, height: ch) } }
                    ZStack(alignment: .topLeading) {
                        VStack(spacing: gap) { ForEach(0..<8, id: \.self) { r in HStack(spacing: gap) { ForEach(0..<8, id: \.self) { c in roomsPartCell(c, r, w: cw, h: ch) } } } }
                        roomsPartPlayhead(colW: cw, gap: gap, height: interiorH)
                    }
                    VStack(spacing: gap) { ForEach(0..<8, id: \.self) { n in roomsPartRightRail(n).frame(width: cw, height: ch) } }
                }
                .overlay(alignment: .topLeading) { roomsProcessorCardAt(x: leftInset, y: 0, w: interiorW, h: interiorH) }
            }
            .padding(pad)
            .background(RoundedRectangle(cornerRadius: 12).fill(Color.white.opacity(0.05)))
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(buildCyan.opacity(0.35), lineWidth: 1.5))
        }
    }
    // A PART interior cell — ONE RUNG PER COLUMN (old-gui buildStagingTap): tap selects that rung for its column; tap the
    // selected rung to UNSELECT it (that column falls silent). Display shows its colour, the selected rung brighter.
    @ViewBuilder private func roomsPartCell(_ c: Int, _ r: Int, w: CGFloat, h: CGFloat) -> some View {
        let id = buildStagingCells[c][r]
        let selected = buildStagingSel[c] == r                            // the ONE selected rung for column c
        RoundedRectangle(cornerRadius: 5)
            .fill((id.flatMap { colourColor($0) } ?? buildCell).opacity(selected ? 1.0 : 0.5))
            .overlay { buildNoteSweep(idx: c * 8 + r, active: buildStagingPlaying && selected, id: id) }
            .clipShape(RoundedRectangle(cornerRadius: 5))
            .overlay(RoundedRectangle(cornerRadius: 5).stroke(selected ? .white.opacity(0.85) : buildEdge, lineWidth: selected ? 2 : 1))
            .frame(width: w, height: h)                                   // fixed size so the playhead pitch is exact
            .contentShape(Rectangle())
            .onTapGesture { buildStagingTap(c, r) }                       // one rung per column, toggle (the old-gui logic)
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
            let cols = buildPartLen ?? Snap.cols
            let width = colW * 8 + gap * 7
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
    // A PART track-head (top row) — placeholder track play/stop, matching the launchpad col-select style. (§2 header)
    private func colSelCellPart(_ t: Int) -> some View {
        let on = t >= 0 && t < 8 && buildRowColour(t) != nil
        return RoundedRectangle(cornerRadius: 4).fill(on ? (buildRowColour(t).flatMap { colourColor($0) } ?? buildCyan).opacity(0.5) : Color.white.opacity(0.11))
            .overlay(Text("\(t + 1)").font(.system(size: 10, weight: .heavy, design: .monospaced)).foregroundColor(.white.opacity(0.55)))
    }
    // TAP a PART LEFT side button — it becomes the SELECTED slot (the always-one selection, shared with SELECT) + the
    // copy source, and reflects its chain in the panel. It does NOT select a grid row — the RIGHT rail does that. (Paul 2026-08-28)
    private func roomsTapPartSide(_ n: Int) {
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
    // Carry the PLAYING state across a room switch onto the room's OWN voice, keeping the two mutually exclusive: if
    // something was playing, the room's voice plays (SELECT→chain / PART→part); if nothing, nothing plays. (Paul 2026-08-28)
    func roomsSyncVoice(_ room: Room) {
        let playing = buildWorkshopVoice != .none                     // was a workshop voice live before the switch?
        buildPendingWorkshopVoice = nil; buildPendingReengage = false
        switch room {
        case .select: buildApplyWorkshopVoice(playing ? .chain : .none)   // part→chain (chain off ⇒ part silent here)
        case .part:   buildApplyWorkshopVoice(playing ? .part : .none)    // chain→part (part off ⇒ chain silent here)
        default: break
        }
    }

    // The GRID-scope verbs, below the part grid (the ">>>" moved here from the left stack + dropped from the label). (Paul 2026-08-18)
    @ViewBuilder private func buildGridVerbButtons() -> some View {
        HStack(spacing: 6) {
            buildChainBtn("RANDOMIZE", enabled: !buildRandomizing) { buildRandomizeGrid() }   // generate 8 rows; disabled while running
            buildChainBtn("MUTATE", enabled: !buildMutating && !selectedColourChain().isEmpty) { buildMutateGrid() }   // variations of the selected chain; disabled when no chain / running
            buildChainBtn("CLEAR")     { buildClearGrid() }       // deselect the grid
        }
    }
    // The four OUTPUT-CHAIN SETUPS below the play grid — pick the LIVE config (§9 name "SETUP 1–4"; the same 4 configs
    // the OUTPUT CHAIN sheet's SETUPS radio edits). Now WIRED (the 4-config engine exists): tap = go live, active is lit.
    @ViewBuilder private func buildRackButtons() -> some View {
        let active = au?.uiRackConfig() ?? 0
        HStack(spacing: 6) {
            ForEach(0..<4, id: \.self) { c in
                let on = c == active
                Text("SETUP \(c + 1)").font(.system(size: 8, weight: .heavy, design: .monospaced)).tracking(0.2)
                    .foregroundColor(on ? .black : .white).lineLimit(1).minimumScaleFactor(0.5).padding(.horizontal, 3)
                    .frame(maxWidth: .infinity).frame(height: 33)
                    .background(RoundedRectangle(cornerRadius: 6).fill(on ? buildCyan : buildCell))
                    .contentShape(Rectangle()).onTapGesture { au?.setRackConfig(c); refreshFromDocument() }
            }
        }
    }
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
    /// Whether a lit ROW 8 cell has a LIVE engine (v1: only the FREEZE/HALFTIME toggles affect audio yet).
    private func row8Live(_ t: Row8Type) -> Bool { t == .freeze || t == .halftime }

    private func buildRow8Perform(_ i: Int) {
        guard i >= 0, i < 8, i < buildRow8Cells.count else { return }
        let c = buildRow8Cells[i]
        switch c.type {
        case .empty:
            buildRow8EditSlot = i; buildRow8EditOpen = true          // an empty cell invites authoring
        case .setup:
            au?.setRow8OnRadioSetup(i)                               // SETUP cells are a radio (lit state)
            au?.setRackConfig(max(0, min(3, c.setupN ?? 0)))         // …and activate that rack config (§5: the only rack link)
            refreshFromDocument()
        case .macro:
            let now = !(i < buildRow8On.count && buildRow8On[i])
            if i < buildRow8On.count { buildRow8On[i] = now }
            au?.setRow8On(i, now)
            au?.setMacroValue(max(0, min(7, c.macroN ?? 0)), now ? 1.0 : 0.0)   // fire/hold macro n
        case .kill:
            au?.masterPanic()                                        // one-shot: all-notes-off (hard = panic)
            let on = i < buildRow8On.count && buildRow8On[i]
            if on, i < buildRow8On.count { buildRow8On[i] = false; au?.setRow8On(i, false) }   // KILL never latches
        case .input:
            buildEngageDoor(c.doorRef ?? 0)                          // the door's mode-act (LATCH/HOLD/KEYS arm · REPLAY re-catch), shared with the strip's LATCH button
        case .ccPunch:
            let now = !(i < buildRow8On.count && buildRow8On[i])
            if i < buildRow8On.count { buildRow8On[i] = now }
            au?.setRow8On(i, now)
            au?.punchCC(max(0, min(127, c.ccNum ?? 74)), now ? max(0, min(127, c.ccVal ?? 127)) : 0)   // punch the value ON; release → 0 (a momentary punch, v1 via the toggle)
        case .pcSend:
            au?.sendProgramChange(max(0, min(127, c.pcNum ?? 0)))    // one-shot: a Program Change on the emitter wires
            let on = i < buildRow8On.count && buildRow8On[i]
            if on, i < buildRow8On.count { buildRow8On[i] = false; au?.setRow8On(i, false) }   // never latches (a brief flash)
        default:
            let now = !(i < buildRow8On.count && buildRow8On[i])
            if i < buildRow8On.count { buildRow8On[i] = now }         // optimistic
            au?.setRow8On(i, now)                                    // TAP = toggle the lit state (for TOGGLE/ONE-SHOT movers; HELD movers use the press gesture below)
        }
    }
    // HELD-MOVER momentary press (Paul 2026-08-26): a cell whose mover is HELD engages on finger-DOWN and RESTORES on
    // release (STUTTER/REDIRECT/BROADCAST/CC-PUNCH by default) — punch an effect in while held, out when you let go. The
    // engine already responds to the setRow8On edge (CC-PUNCH sends the value on / 0 off), so this only changes the gesture.
    private func buildRow8Press(_ i: Int) {
        guard i >= 0, i < 8, i < buildRow8Cells.count, buildRow8Cells[i].type != .empty else { return }
        if buildRow8HeldSlots.contains(i) { return }                // onChanged fires repeatedly — engage once per slot (a SET → two fingers can't strand one)
        buildRow8HeldSlots.insert(i)
        if buildRow8Cells[i].type == .ccPunch {                     // CC-PUNCH: punch the value on press
            let c = buildRow8Cells[i]
            au?.punchCC(max(0, min(127, c.ccNum ?? 74)), max(0, min(127, c.ccVal ?? 127)))
        }
        if i < buildRow8On.count { buildRow8On[i] = true }
        au?.setRow8On(i, true)
    }
    private func buildRow8Release(_ i: Int) {
        guard buildRow8HeldSlots.contains(i) else { return }        // release exactly THIS slot (never the last-pressed one)
        buildRow8HeldSlots.remove(i)
        if i < buildRow8Cells.count, buildRow8Cells[i].type == .ccPunch { au?.punchCC(max(0, min(127, buildRow8Cells[i].ccNum ?? 74)), 0) }   // restore CC to 0
        if i < buildRow8On.count { buildRow8On[i] = false }
        au?.setRow8On(i, false)
    }

    // ROW 8 lives in the PLAY GRID's BOTTOM row (row index 7) as POPULATED-looking cells (Paul 2026-08-24) — not a
    // separate strip. Same footprint + corner as a part cell; a lit toggle fills cyan; an empty cell is the [+] recess.
    // TAP performs; authoring lives on the ROW 8 EDIT PAGE (opened from the top header, after RACK — no long-press here).
    @ViewBuilder private func buildRow8GridCell(_ i: Int, cell: CGFloat) -> some View {
        let c = i < buildRow8Cells.count ? buildRow8Cells[i] : Row8Cell()
        let on = i < buildRow8On.count && buildRow8On[i] && c.type != .empty
        let empty = c.type == .empty
        let heldMover = c.type != .empty && c.mover == .held        // momentary press (Paul 2026-08-26) vs a tap for TOGGLE/ONE-SHOT
        let face = RoundedRectangle(cornerRadius: 7)
            .fill(empty ? Color.black.opacity(0.35) : (on ? buildCyan : buildCell))
            .frame(width: cell, height: cell)
            .overlay(RoundedRectangle(cornerRadius: 7).strokeBorder(
                empty ? Color.white.opacity(0.09) : (on ? buildCyan : Color.white.opacity(0.14)),
                style: StrokeStyle(lineWidth: empty ? 1 : 1.2, dash: empty ? [3, 3] : [])))
            .overlay {
                VStack(spacing: 1) {
                    Image(systemName: row8Glyph(c.type)).font(.system(size: min(15, cell * 0.34), weight: .black))
                        .foregroundColor(empty ? buildDim : (on ? .black : .white))
                    if cell > 30 { Text(row8Caption(c)).font(.system(size: min(6.5, cell * 0.15), weight: .heavy, design: .monospaced))
                        .foregroundColor(empty ? buildDim : (on ? .black : buildDim)).lineLimit(1).minimumScaleFactor(0.5) }
                }.padding(1)
            }
            .contentShape(Rectangle())
        if heldMover {                                              // finger-DOWN engages, release restores (DragGesture(0) survives the AU host — the house pattern)
            face.simultaneousGesture(DragGesture(minimumDistance: 0)
                .onChanged { _ in buildRow8Press(i) }
                .onEnded { _ in buildRow8Release(i) })
        } else {
            face.onTapGesture { buildRow8Perform(i) }
        }
    }

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

    @ViewBuilder private func buildChainBtn(_ label: String, enabled: Bool = true, fill: Bool = false, action: @escaping () -> Void) -> some View {
        Text(label).font(.system(size: 8, weight: .heavy, design: .monospaced)).tracking(0.2)
            .foregroundColor(.white).lineLimit(1).minimumScaleFactor(0.5).padding(.horizontal, 3)
            // fill = SHARE the stack's fixed height (so N buttons never overflow it → the chain grid keeps its size,
            // Paul 2026-08-23); else a compact fixed 33 (the GRID-verb HStack row).
            .frame(maxWidth: .infinity).frame(maxHeight: fill ? .infinity : nil).frame(height: fill ? nil : 33)
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
        // In the grid selector the audition door IS buildSelReceiver (what the toggle sets + the audition plays), so the chip
        // reflects that directly; on the main page it reflects the SELECTED row's resolved door. (Paul 2026-08-26)
        let on = buildGridSelOpen ? (buildSelReceiver == i) : (buildSelectedRow.map { buildRowReceiverResolved($0) == i } ?? false)
        buildIOSelectChip(top: "MIDI IN", letter: ["A", "B", "C", "D"][i], on: on, action: { buildSelectDoor(i) }, onAll: { buildSelectDoorAll(i) })
    }
    // THE EMITTER (MIDI-OUT) TOGGLES — below the left column's button box. Four toggles (A–D), IDENTICAL in style to
    // the MIDI-IN receiver selector, toggling the PART's output emitters (part-owned, so every colour follows). (Paul 2026-08-18)
    @ViewBuilder private func buildEmitterToggles(castW: CGFloat) -> some View {
        HStack(spacing: 4) {
            ForEach(Array(Bus.allCases.enumerated()), id: \.offset) { _, b in
                // Grid selector: the audition emitters ARE buildPartEmitters (what the toggle sets + the audition uses); main page: the selected row's resolved emitters. (Paul 2026-08-26)
                let on = buildGridSelOpen ? (buildPartEmitters.isEmpty ? [.a] : buildPartEmitters).contains(b) : (buildSelectedRow.map { buildRowEmittersResolved($0).contains(b) } ?? false)
                buildIOSelectChip(top: "MIDI OUT", letter: b.rawValue, on: on, action: { buildToggleBus(b) }, onAll: { buildToggleBusAll(b) })
            }
        }
        .frame(width: castW)
    }
    // The shared two-line I/O chip: a small top label over a big A/B/C/D, styled like the centre column's emitter A–D
    // chips (cyan-when-on, muted idle, height 48). Used by BOTH the MIDI-IN receiver selector and the MIDI-OUT
    // emitter toggles so they read identically. (Paul 2026-08-18)
    @ViewBuilder private func buildIOSelectChip(top: String, letter: String, on: Bool, action: @escaping () -> Void, onAll: @escaping () -> Void = {}) -> some View {
        VStack(spacing: 1) {
            Text(top).font(.system(size: 6, weight: .heavy, design: .monospaced)).tracking(0.5)
            Text(letter).font(.system(size: 15, weight: .black, design: .monospaced))
        }
        .foregroundColor(on ? Color.black : buildDim)
        .frame(maxWidth: .infinity).frame(height: 48)                        // matches the emitter chips (height 48, fill the row)
        .background(RoundedRectangle(cornerRadius: 7).fill(on ? buildCyan : buildCell))   // ON = the accent; idle mutes
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
    // THE COLOUR TABS (Paul 2026-08-17): 8 tabs numbered 1–8, one per part-grid row. Each tab is a colour/midi-chain;
    // the SELECTED tab drives the processor block + MIDI + visuals. A SET tab shows its colour; an empty tab reads blank.
    @ViewBuilder private func buildColourTabs(castW: CGFloat, cell: CGFloat, inEditor: Bool = false) -> some View {
        let gap = BuildGeom.castGap
        if inEditor {
            // The row selector: 8 chips. LONG-PRESS a chip applies a COPY of the current machine to that row. (The ◀/BANK▶
            // carriage buttons were removed 2026-08-25 — Paul.)
            let tabW = (castW - gap * 7) / 8
            HStack(spacing: gap) {
                ForEach(0..<8, id: \.self) { n in buildColourTab(n, w: tabW, cell: cell, inEditor: true) }
            }
        } else {
            let tabW = (castW - gap * 7) / 8
            HStack(spacing: gap) {
                ForEach(0..<8, id: \.self) { n in buildColourTab(n, w: tabW, cell: cell, inEditor: false) }
            }
        }
    }
    @ViewBuilder private func buildColourTab(_ n: Int, w: CGFloat, cell: CGFloat, inEditor: Bool = false) -> some View {
        let cid = buildRowColour(n)                              // tab N's colour = the colour on part-grid row N
        let selected = cid != nil && cid == ddSelectedColourID
        let tint = cid.flatMap { colourColor($0) }              // the tab's own colour (nil = empty)
        // Styled like the part-grid ROW buttons: the muted RAIL (light grey on dark grey) when empty or unselected;
        // a populated tab shows its colour as the NUMBER's text; the SELECTED tab keeps its solid-colour look. (Paul 2026-08-18)
        // §banking chip states (design 2026-08-17): in the EDITOR strip, OCCUPIED rows read FILLED, EMPTY rows HOLLOW
        // (dashed) — what a tap would destroy is visible before the tap; the current row (EDITING) keeps the white mark.
        let editorEmpty = inEditor && cid == nil
        RoundedRectangle(cornerRadius: 6)
            .fill(selected ? (tint ?? buildRowButtonFill) : (inEditor && cid != nil ? (tint ?? buildRowButtonFill).opacity(0.4) : buildRowButtonFill))
            .frame(width: w, height: cell)
            .overlay(RoundedRectangle(cornerRadius: 6).stroke(selected ? Color.white : (tint ?? (editorEmpty ? Color.clear : buildEdge)), lineWidth: (selected || tint != nil) ? 2 : 1))   // SELECTED = white; populated = its colour outline; empty = the faint edge
            .overlay { if editorEmpty { RoundedRectangle(cornerRadius: 6).stroke(style: StrokeStyle(lineWidth: 1, dash: [3, 2])).foregroundColor(buildEdge) } }   // HOLLOW empty
            .overlay { if buildPendingTab == n { buildPulseOverlay() } }   // PENDING (copied, unedited) → pulses
            .overlay { if cid != nil { buildTabNowPlaying(n).clipShape(RoundedRectangle(cornerRadius: 6)) } }   // NOW-PLAYING animation when this row sounds
            .overlay(Text("\(n + 1)").font(.system(size: 11, weight: .heavy, design: .monospaced))
                .foregroundColor(selected ? .black.opacity(0.7) : (tint ?? .white.opacity(0.7))))   // populated → the colour's TEXT; empty → grey; selected → black on the fill
            .contentShape(Rectangle())
            .onTapGesture { buildTapColourTab(n) }   // TAP = select/visit that row's colour (never stamps — Paul 2026-08-20)
            .onLongPressGesture(minimumDuration: 0.35) { if inEditor { buildEditorOverwriteRow(n) } }   // in the editor, HOLD = apply a COPY of the current machine to that row
    }
    // NOW-PLAYING (Paul 2026-08-19): a gentle left→right shimmer on the row-selector tab whose row is the active rung in
    // the playing column. Cheap: 3 soft marks in one Canvas, only while that row plays.
    @ViewBuilder private func buildTabNowPlaying(_ n: Int) -> some View {
        let playing = d.playing && buildStagingPlaying && d.effColumn >= 0 && d.effColumn < buildStagingSel.count && buildStagingSel[d.effColumn] == n   // only when the PART is the sounding voice (not the play grid)
        if playing {
            TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: animationsPaused)) { tl in
                Canvas { ctx, size in
                    let t = tl.date.timeIntervalSinceReferenceDate
                    for k in 0..<3 {
                        let phase = (t * 0.55 + Double(k) / 3.0).truncatingRemainder(dividingBy: 1.0)
                        let x = CGFloat(phase) * size.width
                        let a = sin(phase * .pi) * 0.45                      // fade in at the left, out at the right
                        let rect = CGRect(x: x - 1.5, y: size.height * 0.28, width: 3, height: size.height * 0.44)
                        ctx.fill(Path(roundedRect: rect, cornerRadius: 1.5), with: .color(.white.opacity(max(0, a))))
                    }
                }
            }.allowsHitTesting(false)
        }
    }
    // PROCESSOR EDITOR — a row-selector tab OVERWRITES that row with the CURRENT edits, KEEPS the original settings on the
    // source colour (reverts it to the open-snapshot), then FOLLOWS to the new row (everything switches). (Paul 2026-08-19)
    private func buildEditorOverwriteRow(_ n: Int) {
        guard let srcCid = ddSelectedColourID else { return }
        let cur = selectedColourChain()                                     // the current edited chain
        if let snapCid = buildEditorSnapCid, snapCid == srcCid {            // 1. keep the ORIGINAL on the source colour
            buildWriteColourMachine(srcCid, buildEditorSnapshot)
        }
        let targetID: String
        if let tgt = buildRowColour(n) {                                    // 2a. row n populated → overwrite its chain
            buildWriteColourMachine(tgt, cur); targetID = tgt
        } else {                                                            // 2b. row n empty → mint a colour carrying cur
            let y = buildNewTabColour(n, machine: cur)
            buildPartCast.append(y); buildSetRow(n, to: y)
            if n < buildRowReceiver.count { buildRowReceiver[n] = ddStickyReceiver; buildRowEmitters[n] = ddStickyBuses }
            targetID = y
        }
        for c in 0..<8 { buildStagingSel[c] = n }
        buildSelectID(targetID)                                            // 3. FOLLOW to the new row
        buildEditorSnapCid = targetID; buildEditorSnapshot = cur           // re-snapshot: further edits/cancel apply to the target
        buildPendingTab = nil
        buildStagingSyncIfPlaying()
        buildFlashPromote("ROW \(n + 1) ✓")                               // §banking: the STAMP TELL — confirm the deal (design 2026-08-17)
    }
    // A breathing white pulse (the pending-tab / previewed-row highlight).
    @ViewBuilder private func buildPulseOverlay() -> some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: animationsPaused)) { tl in
            let ph = 0.5 + 0.5 * sin(tl.date.timeIntervalSinceReferenceDate * 3.4)
            RoundedRectangle(cornerRadius: 6).fill(Color.black.opacity(0.12 + 0.32 * ph)).allowsHitTesting(false)
        }
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
        for c in 0..<8 { buildStagingSel[c] = n }
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
    @ViewBuilder private func buildProcessorBlock(castW: CGFloat, cell: CGFloat) -> some View {
        let chain = selectedColourChain()
        let gap = BuildGeom.castGap
        let swW = (castW - gap * 7) / 8                            // same swatch width as the cast → boxes sit on the 8-column grid
        let boxW = swW * 2 + gap                                   // 2 cast columns wide
        let boxH = cell * 2 + gap                                  // 2 cast rows tall
        VStack(spacing: gap) {                                      // VERTICAL 2×4 (was 4×2): 4 rows of 2 boxes, reading L→R then down (Paul 2026-08-18)
            ForEach(0..<4, id: \.self) { r in
                HStack(spacing: gap) {
                    ForEach(0..<2, id: \.self) { c in
                        buildProcBox(r * 2 + c, chain: chain, w: boxW, h: boxH, gap: gap)
                    }
                }
            }
        }
        // §1 THE FLOW LINE (design 2026-08-17): the dotted thread draws ORDER (the numbers' old job) — door ┈▶ slot 0 ┈▶
        // … ┈▶ slot 7 ┈▶ wire, in chain order, with a TURN MARK at each row wrap (the boustrophedon made visible).
        .background(buildChainFlowLine(boxW: boxW, boxH: boxH, gap: gap))
        .coordinateSpace(name: "chainBlock")                        // DRAG-TO-REORDER: a stable space for the finger track + the floating ghost
        .overlay(alignment: .topLeading) { buildChainDragGhost(chain: chain, boxW: boxW, boxH: boxH) }
    }
    // DRAG-TO-REORDER: the floating ghost of the box under the finger (drawn in the "chainBlock" space, hit-transparent).
    @ViewBuilder private func buildChainDragGhost(chain: [ProcessorSlot], boxW: CGFloat, boxH: CGFloat) -> some View {
        if let from = buildChainDragFrom, from < chain.count, !buildIsEmptySlot(chain[from]) {
            Text(buildProcLabel(chain[from]))
                .font(.system(size: 11, weight: .heavy, design: .monospaced))
                .foregroundColor(.black)
                .lineLimit(1).minimumScaleFactor(0.5).padding(.horizontal, 3)
                .frame(width: boxW * 0.8, height: boxH * 0.8)
                .background(RoundedRectangle(cornerRadius: 8).fill(buildSelHue))
                .shadow(color: .black.opacity(0.5), radius: 6, y: 2)
                .position(buildChainDragLoc)
                .allowsHitTesting(false)
        }
    }
    private func buildChainFlowLine(boxW: CGFloat, boxH: CGFloat, gap: CGFloat) -> some View {
        Canvas { ctx, size in
            func center(_ i: Int) -> CGPoint {
                CGPoint(x: CGFloat(i % 2) * (boxW + gap) + boxW / 2, y: CGFloat(i / 2) * (boxH + gap) + boxH / 2)
            }
            var path = Path()
            path.move(to: CGPoint(x: 0, y: center(0).y)); path.addLine(to: center(0))   // DOOR entry
            for i in 1..<8 { path.addLine(to: center(i)) }                               // chain order 0→…→7
            path.addLine(to: CGPoint(x: size.width, y: center(7).y))                     // WIRE exit
            ctx.stroke(path, with: .color(buildSelHue.opacity(0.32)), style: StrokeStyle(lineWidth: 1.5, lineCap: .round, dash: [2, 3]))
            for wrap in [1, 3, 5] {                                                      // TURN MARK at each row wrap (slot 1→2, 3→4, 5→6)
                let a = center(wrap), b = center(wrap + 1); let m = CGPoint(x: (a.x + b.x) / 2, y: (a.y + b.y) / 2)
                ctx.fill(Path(ellipseIn: CGRect(x: m.x - 2, y: m.y - 2, width: 4, height: 4)), with: .color(buildSelHue.opacity(0.5)))
            }
        }
    }

    @ViewBuilder private func buildProcBox(_ i: Int, chain: [ProcessorSlot], w: CGFloat, h: CGFloat, gap: CGFloat) -> some View {
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
                    .background(RoundedRectangle(cornerRadius: 8).fill(buildSelHue))
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

    @ViewBuilder private func buildInputSection(castW: CGFloat) -> some View {
        let recvs = au?.uiReceivers() ?? []
        let sel = buildSelReceiver
        let piano = sel < recvs.count && recvs[sel].latchPianoResolved
        let togW = min(50, max(28, (castW - 80) / 2))            // comfortable toggle targets, clamped so the row always FITS castW
        let midW = max(60, castW - togW * 2 - 10)                // the keyboard/channel box FILLS the span between the two toggles (all widths fixed → no greedy layout)
        VStack(alignment: .center, spacing: 8) {
            HStack(spacing: 4) {                                   // R1–R4: pick the door (⌨ piano · ⎓ MIDI); the face below edits it
                ForEach(0..<4, id: \.self) { i in
                    let isPiano = i < recvs.count && recvs[i].latchPianoResolved
                    buildIOChip("R\(i + 1) \(isPiano ? "⌨" : "⎓")", on: i == sel, keys: isPiano, fill: true) { buildSelectDoor(i) }
                }
            }
            .frame(width: castW)                                  // the receivers row fills the column
            HStack(spacing: 5) {                                   // the SELECTED door's SOURCE toggle: DIN (MIDI in) | in-app piano; the middle SHOWS the chosen source
                buildSourceToggle("cable.connector", active: !piano, width: togW) { buildSetSource(sel, piano: false) }
                if piano {
                    buildKeyboard(receiver: sel, held: sel < recvs.count ? Set(recvs[sel].pianoNotesResolved) : [], enabled: true, width: midW)
                } else {
                    buildChannelBox(receiver: sel, channel: sel < recvs.count ? recvs[sel].channel : 0).frame(width: midW)
                }
                buildSourceToggle("pianokeys", active: piano, width: togW, rotate: true) { buildSetSource(sel, piano: true) }
            }
            .frame(width: castW)                                  // the midi-select row fills the column
            HStack(spacing: 6) {                                   // octave shift for the selected door, with the current offset between
                buildOctBtn("OCT −") { nudgeReceiverOctave(sel, -1) }
                let oct = sel < receiverOctave.count ? receiverOctave[sel] : 0
                Text(oct > 0 ? "+\(oct)" : "\(oct)").font(.system(size: 12, weight: .heavy, design: .monospaced))
                    .foregroundColor(buildCyan).frame(minWidth: 30)
                buildOctBtn("OCT +") { nudgeReceiverOctave(sel, +1) }
            }.frame(width: 176)
        }
    }

    // §2: the INPUT door is PART-owned — one door for the whole part (every colour follows). Applied uniformly at
    // scene-build + audition; no per-colour cell fanning.
    private func buildSelectDoor(_ i: Int) {
        buildRecordUndo()   // BUILD UNDO: pick the input door (receiver)
        buildClearPendingOnEdit()                                // a RECEIVER change ends the fresh-row flash (Paul 2026-08-25)
        if let r = buildSelectedRow, r < buildRowReceiver.count { buildRowReceiver[r] = i }   // override THIS ROW only (per-row I/O, Paul 2026-08-18)
        else { buildSelReceiver = i }                            // nothing on a row → set the part DEFAULT
        ddStickyReceiver = i                                     // a new row inherits the LAST-USED
        receivers = au?.uiReceivers() ?? receivers               // mirror so the source toggle/keyboard reflect the newly-selected door at once
        buildStagingSyncIfPlaying()                              // the row's door applies to its staging cells, live
        refreshFromDocument()
    }

    // Flip the SELECTED door between MIDI-in and the in-app piano. Mirroring `receivers` guarantees SwiftUI
    // invalidates this row immediately (buildInputSection reads uiReceivers live, but the mirror forces the update).
    private func buildSetSource(_ i: Int, piano: Bool) {
        // route through the door mode (ONE source of truth): piano ⇒ KEYS, DIN ⇒ LATCH (preserves BUILD's live-input behaviour).
        // buildRecvEdit records a BUILD-undo step + re-polls/refreshes (U9 fix 2026-08-27 — was recording to the AU stack the header can't reach).
        buildRecvEdit { au?.setDoorMode(i, piano ? .keys : .latch) }
    }

    @ViewBuilder private func buildCastSection(castW: CGFloat, cell: CGFloat) -> some View {
        VStack(alignment: .center, spacing: 8) {
            buildCastPalette(castW: castW, cell: cell)
        }
    }

    @ViewBuilder private func buildOutputSection(castW: CGFloat) -> some View {
        let buses = buildPartEmitters                             // §2: OUTPUT is PART-owned — every colour follows
        VStack(alignment: .center, spacing: 8) {
            HStack(spacing: 4) {                                   // A–D toggle the PART's output emitters
                ForEach(Array(Bus.allCases.enumerated()), id: \.offset) { _, b in
                    buildIOChip(b.rawValue, on: buses.contains(b), fill: true) { buildToggleBus(b) }
                }
            }
            .frame(width: castW)                                  // the emitters row fills the column
            buildMidiOutInfo(buses: buses, castW: castW)          // the lit emitters + their channels
        }
    }

    // §2 (design ferry): the emitters are PART-owned now — shared across every colour/cell of the part.
    private func ddSelectedColourBuses() -> Set<Bus> { buildPartEmitters }

    private func buildToggleBus(_ bus: Bus) {
        buildRecordUndo()   // BUILD UNDO: toggle an output emitter
        buildClearPendingOnEdit()                                // an EMITTER change ends the fresh-row flash (Paul 2026-08-25)
        let selR = buildSelectedRow
        var buses = selR.map { buildRowEmittersResolved($0) } ?? (buildPartEmitters.isEmpty ? [.a] : buildPartEmitters)
        if buses.contains(bus) { buses.remove(bus) } else { buses.insert(bus) }
        if buses.isEmpty { buses = [bus] }                        // never leave a row with no output
        if let r = selR, r < buildRowEmitters.count { buildRowEmitters[r] = buses }   // override THIS ROW only (per-row I/O, Paul 2026-08-18)
        else { buildPartEmitters = buses }                        // nothing on a row → the part DEFAULT
        ddStickyBuses = buses                                     // a new row inherits the LAST-USED
        buildPublishScene()                                       // apply the row's output LIVE to whatever's sounding
    }
    // LONG-PRESS → apply the door to EVERY row (Paul 2026-08-19).
    private func buildSelectDoorAll(_ i: Int) {
        buildRecordUndo()   // BUILD UNDO: blanket-apply the door to every row (U7 fix 2026-08-27 — the single-row sibling records; this didn't)
        buildClearPendingOnEdit()                                // a RECEIVER change (all rows) ends the fresh-row flash (Paul 2026-08-25)
        for r in 0..<min(8, buildRowReceiver.count) { buildRowReceiver[r] = i }
        buildSelReceiver = i; ddStickyReceiver = i
        receivers = au?.uiReceivers() ?? receivers
        buildStagingSyncIfPlaying(); refreshFromDocument()
    }
    // LONG-PRESS → toggle the emitter on EVERY row (all rows take the reference row's toggled set). (Paul 2026-08-19)
    private func buildToggleBusAll(_ bus: Bus) {
        buildRecordUndo()   // BUILD UNDO: blanket-apply the emitter to every row (U7 fix 2026-08-27)
        buildClearPendingOnEdit()                                // an EMITTER change (all rows) ends the fresh-row flash (Paul 2026-08-25)
        var buses = buildSelectedRow.map { buildRowEmittersResolved($0) } ?? (buildPartEmitters.isEmpty ? [.a] : buildPartEmitters)
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
        buildStagingPlaying = false                              // CHAIN ⟂ PART; the PIECE is independent — it keeps sounding via the scene
        buildSeedCastIfNeeded()                                  // §2: part 1's cast reflects the already-defined colours (once); selects within the cast
        ddStickyReceiver = buildSelReceiver                      // §2: the chain audition uses the PART's I/O (door + emitters)
        ddStickyBuses = buildPartEmitters.isEmpty ? [.a] : buildPartEmitters
        // A document colour never given a chain shows an EMPTY chain but has a nil templateChain; make it an explicit []
        // once so the palette's shown-empty chain matches the raw sound (the injected cell reads buildColourChain, which
        // is [] here → a born-audible passthrough — never the legacy A-face arp). Only fires when the chain is unstored.
        if let cid = ddSelectedColourID, buildColourReg[cid] == nil, au?.colourHasStoredChain(cid) == false {
            au?.withChainColour(cid) { $0 = [] }; refreshFromDocument()   // document colour only — ephemeral colours always carry a registry machine
        }
        ddSolo = true                                           // the chain is the voice — sounded RAW via the ephemeral scene
        buildPublishScene()
    }
    private func buildSelectStagingVoice() {
        if ddSolo { ddSolo = false; au?.clearColourSolo() }      // CHAIN ⟂ PART: stop the chain audition (they're mutually exclusive)
        buildStagingPlaying = true                               // the PART is a voice — the PIECE (if playing) keeps sounding ALONGSIDE (correction)
        buildPublishScene()
    }

    // The LIVE workshop voice, read off the section flags (PART wins if somehow both are set — it shouldn't happen).
    var buildWorkshopVoice: BuildWorkshopVoice {
        if buildStagingPlaying { return .part }
        if ddSolo { return .chain }
        return .none
    }
    // The DISPLAYED workshop voice: the armed target if a switch is pending, else the live one. The HEADERS read this so
    // they highlight the new state IMMEDIATELY on tap, while the MIDI still switches quantized at the boundary. (Paul 2026-08-15)
    var buildDisplayVoice: BuildWorkshopVoice { buildPendingWorkshopVoice ?? buildWorkshopVoice }
    // The left column wears its SELECTED-COLOUR frame only when PLAY THIS MIDI CHAIN is the voice AND no processor card
    // is open — a card open hides the box (Paul 2026-08-25), so the two coloured frames don't fight while editing.
    var buildShowColourBox: Bool { buildDisplayVoice == .chain && buildEditSlot == nil }

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
        if ddSolo { ddSolo = false; au?.clearColourSolo() }
        buildStagingPlaying = false
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
    // Population (Paul 2026-08-15): real deployed play-grid cells (preview doesn't count) · any stocked staging cell.
    var buildPerformPopulated: Bool { buildPerformCells.contains { $0.contains { $0 != nil } } }
    var buildStagingPopulated: Bool { buildStagingCells.contains { $0.contains { $0 != nil } } }

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
        input.performChain = (0..<8).map { c in (0..<8).map { r -> [ProcessorSlot] in
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
        input.chainEmitters = selR.map { buildRowEmittersResolved($0) } ?? (buildPartEmitters.isEmpty ? [.a] : buildPartEmitters)
        // PER-PART CLOCK (Paul 2026-08-19): each play-grid ROW takes its owning deployed part's rate/length; the STAGING
        // audition takes the CURRENT part's. nil ⇒ the scene default (uniform = today). This is what makes deployed parts
        // at different rates play at DIFFERENT tempos in one play grid.
        input.performRate = (0..<8).map { r in let p = buildPerformPart[r]; return (p >= 0 && p < buildParts.count) ? buildParts[p].rate : nil }
        input.performLen  = (0..<8).map { r in let p = buildPerformPart[r]; return (p >= 0 && p < buildParts.count) ? buildParts[p].length : nil }
        input.stagingRate = buildPartRate
        input.stagingLen  = buildPartLen
        input.stagingLane = buildStagingLane                     // PER-ROW LAP: the two grids loop independently
        input.performLane = buildPerformLane
        au?.setBuildStagingScene(BuildSceneLogic.composeScene(input))
        // (The reference-chord fallback was REMOVED 2026-08-23, Paul: PLAY THIS MIDI CHAIN now sounds ONLY real input —
        // a synthetic C-major triad must never reach the user. With nothing held the audition is simply silent.)
        // FREE-RUN GATE (Paul 2026-08-27, FERRY-strike-anchor ①: REVERTS the 2026-08-25 held-note internal transport).
        // "Stopped = silent." The plugin drives its OWN clock while the host is STOPPED only when an explicit BUILD play
        // mode is running: PLAY THIS MIDI CHAIN (ddSolo) · PLAY THIS PART (buildStagingPlaying) · START THE PLAY GRID
        // (buildPerformPlaying). All three off ⇒ free-run OFF ⇒ a bare held note produces NO throughput. Host-playing is
        // unchanged (the Kernel free-run guard is `!playing`). Synced HERE — the one choke point every voice toggle and
        // scene restore routes through. (The no-machine passthrough live-wire monitors independently, governed by the
        // pending FERRY-passage-law, not this gate.)
        au?.setFreeRunEnabled(ddSolo || buildStagingPlaying || buildPerformPlaying)
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
        return buildPartEmitters.isEmpty ? [.a] : buildPartEmitters
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
        ddStickyBuses = buildPartEmitters.isEmpty ? [.a] : buildPartEmitters
        ddScopeToColour(id, anchor: nil, engage: false)          // BUILD never uses the AU solo — the chain plays via the scene
        if ddSolo {                                              // auditioning the chain → re-inject the newly-selected colour
            if d.playing { buildPendingReengage = true }         // SEAMLESS: swap on the next cell boundary
            else { buildPublishScene() }                         // stopped → immediate
        }
    }
    private func buildComplexity(_ chain: [ProcessorSlot]) -> Int { let e = Dice.evalRun(chain); return e.sig.count * 100 + e.peak }   // note frequency (×100) + concurrency
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
    private var buildRowButtonFill: Color {
        if buildRowMode != .select, let cid = ddSelectedColourID, buildIsDark(buildBaseHex(cid)) { return Color.white.opacity(0.9) }
        return Color.white.opacity(0.11)
    }
    // A NEW hue near `source` — lighter (mix toward white) or darker (toward black), with a floor so it's always distinguishable.
    private func buildSimilarHue(of source: String, lighter: Bool, srcC: Int, newC: Int) -> UInt32 {
        let amount = min(0.6, abs(Double(srcC - newC)) / 400.0 + 0.18)        // ≥0.18 so siblings are always tellable apart
        let base = buildBaseHex(source), t = lighter ? 255.0 : 0.0
        func mix(_ shift: Int) -> UInt32 { let ch = Double((base >> shift) & 0xFF); return UInt32(max(0, min(255, ch + (t - ch) * amount))) }
        return (mix(16) << 16) | (mix(8) << 8) | mix(0)
    }

    // STAGE THE GRID (Paul 2026-08-15) — MUTATE what's already placed, filling the grid to 8 rows. Each pass duplicates the
    // populated row that's been duplicated FEWEST so far, tweaks its machine, analyses complexity (note frequency +
    // concurrency), and inserts it just ABOVE the source if LESS complex (a LIGHTER new colour) or just BELOW if MORE
    // complex (DARKER), rearranging the rows. The new colours are NOT added to the palette — touch one on the grid to
    // preview + add it (the pulse flow). Needs ≥1 populated row (the button is disabled otherwise).
    // GARBAGE-COLLECT colours (Paul 2026-08-15). A colour LIVES if referenced by ANY retained state you can revert to:
    // any part's cast · any part's staging grid · the play grid · any part's rowUnder reverts · pending row/cell
    // restores · the pulse candidate · the current selection. Anything else — ephemeral registry entries AND document
    // VARIATION slots (hue-overridden) — is freed. The canonical defaults (no override) are never touched.
    private func buildGCColours() {
        var live = Set<String>()
        live.formUnion(buildPartCast); for p in buildParts { live.formUnion(p.cast) }
        func addCells(_ cells: [[String?]]) { for col in cells { for c in col { if let c = c { live.insert(c) } } } }
        addCells(buildStagingCells); addCells(buildPerformCells); for p in buildParts { addCells(p.stagingCells) }
        for u in buildRowUnder { if let u = u { live.insert(u) } }
        for p in buildParts { for u in p.rowUnder { if let u = u { live.insert(u) } } }
        for (_, row) in buildDeletedRows { for c in row { if let c = c { live.insert(c) } } }
        for (_, c) in buildPlacedOrig { if let c = c { live.insert(c) } }
        if let p = buildPulseColourID { live.insert(p) }
        if let s = buildSelID { live.insert(s) }
        for p in buildParts { if let s = p.selID { live.insert(s) } }               // C3 (Paul 2026-08-16): a part's STORED selection keeps its colour alive — else GC frees it and buildLoadPart selects a dead id
        let dead = Set(buildColourReg.keys).union(colourHueOverride.keys).subtracting(live)
        guard !dead.isEmpty else { return }
        for id in dead { buildColourReg[id] = nil; colourHueOverride[id] = nil; buildColourTranspose[id] = nil }   // free ephemeral + variation hues + register
        let docDead = dead.filter { colourIDs.contains($0) }                        // document VARIATION slots → undefine
        if !docDead.isEmpty {
            au?.editDocument { doc in for id in docDead { if let i = colourIDs.firstIndex(of: id), i < doc.colours.count { doc.colours[i].defined = false; doc.colours[i].templateChain = nil } } }
            refreshFromDocument()
        }
        buildSyncColours()
    }

    private func buildStageTheGrid() {
        buildRecordUndo()   // BUILD UNDO: stage the grid (the variation ladder)
        for c in 0..<8 { for r in 0..<8 { if let id = buildStagingCells[c][r], !buildPartCast.contains(id) { buildStagingCells[c][r] = nil } } }   // strip prior (un-adopted) variations → back to the originals
        buildGCColours()                                                       // free the reclaimed variation colours
        var order: [String] = (0..<8).compactMap { buildRowColour($0) }        // the ORIGINAL populated rows, top→bottom (one colour each)
        guard !order.isEmpty else { return }
        var rng = SystemRandomNumberGenerator()
        var dup: [String: Int] = Dictionary(uniqueKeysWithValues: order.map { ($0, 0) })
        while order.count < 8 {   // unlimited now — buildNewColour overflows to ephemeral colours past the 16 slots
            guard let source = order.min(by: { (dup[$0] ?? 0, order.firstIndex(of: $0)!) < (dup[$1] ?? 0, order.firstIndex(of: $1)!) }) else { break }
            let srcMachine = buildColourChain(source)
            let mutated = buildVaryChain(srcMachine, &rng)
            let srcC = buildComplexity(srcMachine), newC = buildComplexity(mutated)
            let hue = buildSimilarHue(of: source, lighter: newC < srcC, srcC: srcC, newC: newC)
            let newID = buildNewColour(hex: hue, machine: mutated)             // document slot OR ephemeral; NOT added to the cast
            order.insert(newID, at: newC < srcC ? order.firstIndex(of: source)! : order.firstIndex(of: source)! + 1)   // lighter above · darker below
            dup[newID] = 0; dup[source, default: 0] += 1
        }
        refreshFromDocument()
        for r in 0..<8 {                                                       // lay the reordered rows top→bottom; machines are on the templates
            let cid = r < order.count ? order[r] : nil
            for c in 0..<8 { buildStagingCells[c][r] = cid; buildPlacedOrig.removeValue(forKey: c * 8 + r) }
            if r < buildRowChain.count { buildRowChain[r] = [] }
            if r < buildRowUnder.count { buildRowUnder[r] = nil }
        }
        buildReconcileStagingSel()                                            // keep each column's pick valid after the reshuffle
        buildDeletedRows.removeAll()
        buildSelectStagingVoice()                                             // play the staging grid (publishes the scene)
    }

    // One VARIATION of `base`: 1–3 random mutations (insert / remove / retype / bypass a slot), guaranteed audible.
    private func buildVaryChain(_ base: [ProcessorSlot], _ rng: inout SystemRandomNumberGenerator) -> [ProcessorSlot] {
        var chain = base
        if chain.isEmpty { chain = Dice.rollSimple(using: &rng) }
        for _ in 0..<Int.random(in: 1...3, using: &rng) {
            switch Int.random(in: 0..<4, using: &rng) {
            case 0 where chain.count < 6:
                if let s = Dice.rollSimple(using: &rng).first { chain.insert(s, at: Int.random(in: 0...chain.count, using: &rng)) }
            case 1 where chain.count > 1:
                chain.remove(at: Int.random(in: 0..<chain.count, using: &rng))
            case 2:
                let i = Int.random(in: 0..<chain.count, using: &rng); chain[i].type = ProcessorType.allCases.randomElement(using: &rng)!
            default:
                let i = Int.random(in: 0..<chain.count, using: &rng); chain[i].bypassed.toggle()
            }
        }
        if chain.isEmpty || chain.allSatisfy({ $0.bypassed }) || Dice.signature(chain).isEmpty { chain = Dice.rollSimple(using: &rng) }
        return chain
    }

    // Keep the per-column selection VALID: a selection pointing at an empty cell falls back to the topmost stocked cell
    // in that column (the gentle default), or −1 if the column is empty. An explicit valid selection is preserved.
    private func buildReconcileStagingSel() {
        buildStagingSel = BuildSceneLogic.reconcileStagingSel(buildStagingSel, cells: buildStagingCells)   // C1: an explicit −1 deselect is preserved, not resurrected
    }

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
        for c in 0..<8 { buildStagingSel[c] = row }        // select the whole new row (like PLACE/MUTATE)
        buildStagingSyncIfPlaying()
    }
    // RANDOMIZE >>> — randomize the PART grid's performance: a random POPULATED rung per column. (Paul 2026-08-18)
    // RANDOMIZE (under the part grid): generate 8 rows and lay them on the standard colours in order of complexity.
    // Each chain is a SHORT 1–3-processor roll where EVERY processor contributes (Dice.rollSimple), never silent, and any
    // harmonizer is OCTAVES-ONLY (Dice.randomSlot's rule); no two rows produce the same output. Ordered by complexity, then allocated
    // in that order to the 8 standard palette hues (rows 1–8). (Paul 2026-08-18)
    private func buildRandomizeGrid() {
        guard !buildRandomizing else { return }
        buildRandomizing = true
        DispatchQueue.main.async { self.buildRunRandomizeGrid(); self.buildRandomizing = false }   // render the DISABLED state before the blocking compute
    }
    private func buildRunRandomizeGrid() {
        buildRecordUndo()   // BUILD UNDO: randomize the grid (an ensemble)
        var rng = SystemRandomNumberGenerator()
        // AN ENSEMBLE, not 8 rolls (design-ratified 2026-08-19): 8 CONTRASTING archetypes (pad · bass · stab · arp ·
        // groove · texture · sparkle · wild), each register-separated (transpose) with an inherent density. Sparse-biased
        // (most sparse→medium, ONE dense, the floor genuinely sparse), so the complexity sort orders something real.
        let scored = Dice.rollEnsemble(using: &rng)
            .map { (row: $0, cx: buildComplexity($0.chain)) }
            .sorted { $0.cx < $1.cx }                                        // simple→complex — true BY CONSTRUCTION now
        buildPartCast = []
        for r in 0..<8 {                                                     // ALLOCATE to the 8 standard colours (rows 1–8), carrying each row's register
            if r < buildRowUnder.count { buildRowUnder[r] = nil }
            let id = buildNewTabColour(r, machine: scored[r].row.chain, transpose: scored[r].row.transpose)
            buildPartCast.append(id)
            buildSetRow(r, to: id)
        }
        buildAssignArcRungs(&rng)                                            // rung-per-column = AN ARC, not random
        buildPendingTab = nil
        buildSelectID(buildRowColour(0) ?? "")
        buildGCColours()                                                     // free the colours the old rows used
        buildStagingSyncIfPlaying()
        buildRequestWorkshopVoice(.part)                                     // on loading, switch play to the PART grid (Paul 2026-08-19)
    }
    // Rung-per-column = AN ARC (design 2026-08-19). Rows are complexity-sorted (0 = sparsest), so pick LOW rows to OPEN,
    // build to a mid PEAK, take ONE breath/drop, then LAND low — a phrase, not random noise (call-and-response as jitter).
    private func buildAssignArcRungs(_ rng: inout SystemRandomNumberGenerator) {
        let peak = Int.random(in: 3...4, using: &rng)                        // where the build crests
        let breath = Int.random(in: 5...6, using: &rng)                     // the one breath/drop column
        for c in 0..<8 {
            if c == breath { buildStagingSel[c] = Int.random(in: 0...1, using: &rng); continue }   // drop to sparse
            let up = Double(c) / Double(max(1, peak))
            let down = Double(7 - c) / Double(max(1, 7 - peak))
            let t = min(1, min(up, down))                                    // 0…1 triangular arc: rise to the peak, then fall
            let base = Int((t * 6).rounded())
            buildStagingSel[c] = max(0, min(7, base + Int.random(in: -1...1, using: &rng)))   // jitter = call-and-response seasoning
        }
    }
    // MUTATE (under the part grid): 8 variations of the SELECTED colour's midi chain, laid onto the EXISTING row colours
    // in order of complexity. Each variation nudges a few params across all the chain's processors (mutateChain), may
    // add a SYMPATHETIC extra processor (kept only if the whole chain stays all-contributing), produces MIDI (non-silent),
    // and differs from the others. Disabled when the selected chain is empty (nothing set). (Paul 2026-08-18)
    private func buildMutateGrid() {
        guard !buildMutating, ddSelectedColourID != nil, !selectedColourChain().isEmpty else { return }
        buildMutating = true
        DispatchQueue.main.async { self.buildRunMutateGrid(); self.buildMutating = false }   // render the DISABLED state before the blocking compute
    }
    private func buildRunMutateGrid() {
        guard let selID = ddSelectedColourID else { return }
        let base = buildColourChain(selID)
        guard !base.isEmpty else { return }
        let existing = (0..<8).compactMap { buildRowColour($0) }.reduce(into: [String]()) { if !$0.contains($1) { $0.append($1) } }   // DISTINCT colours on the rows, row order
        guard !existing.isEmpty else { return }
        var rng = SystemRandomNumberGenerator()
        var variations: [[ProcessorSlot]] = []
        var seen = Set<[Int]>([Dice.fingerprint(base)])                      // avoid reproducing the source or a sibling
        var budget = 400
        while variations.count < existing.count && budget > 0 {
            budget -= 1
            guard var v = BuildSceneLogic.mutateChain(base, avoid: Array(seen), &rng) else { continue }   // nudge a few params across the processors
            if Int.random(in: 0...1, using: &rng) == 0 {                     // ~half → try a SYMPATHETIC extra processor
                for _ in 0..<6 {
                    let trial = v + [Dice.randomSlot(using: &rng)]
                    if Dice.allContribute(trial) { v = trial; break }        // kept only if every slot still contributes
                }
            }
            let fp = Dice.fingerprint(v)
            guard !Dice.signature(v).isEmpty, seen.insert(fp).inserted else { continue }   // produces MIDI + distinct
            variations.append(v)
        }
        guard variations.count == existing.count else { return }
        buildRecordUndo()   // BUILD UNDO: recorded HERE — after every bail guard — so a failed generation never pushes a no-op step (U11 fix 2026-08-27)
        variations.sort { buildComplexity($0) < buildComplexity($1) }        // ORDER BY complexity of output
        for (i, cid) in existing.enumerated() { buildWriteColourMachine(cid, variations[i]) }   // allocate to EXISTING colours only
        refreshFromDocument()
        buildStagingSyncIfPlaying()
    }
    // CLEAR >>> — clear the PART grid's active selection (every column deselected → the grid plays nothing). The placed
    // colours + tabs are KEPT (non-destructive). (Paul 2026-08-18)
    private func buildClearGrid() {
        buildRecordUndo()   // BUILD UNDO: CLEAR deselects every column — undoable (U8 fix 2026-08-27)
        for c in 0..<8 { buildStagingSel[c] = -1 }
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
    // An EMPTY processor box = a passthrough placeholder (a bypassed PASSGATE — a true no-op the engine passes through).
    private func buildIsEmptySlot(_ s: ProcessorSlot) -> Bool { s.type == .passgate && s.bypassed }
    private func buildPassthroughSlot() -> ProcessorSlot { var s = ProcessorSlot(type: .passgate); s.bypassed = true; return s }

    // ── PARTS lifecycle (unassigned → built → staged → deployed) ─────────────────────────────────────────────────
    // The CURRENT part's fields live in the working @State (buildStagingCells etc.); these snapshot/restore them so
    // switching parts keeps each part's workshop intact (§3). (design ferry: AcceptanceCriteria-part-lifecycle-io)
    private func buildSavePart() {
        guard buildCurrentPart >= 0, buildCurrentPart < buildParts.count else { return }
        var p = buildParts[buildCurrentPart]
        p.stagingCells = buildStagingCells; p.stagingSel = buildStagingSel
        p.rowChain = buildRowChain; p.rowShade = buildRowShade; p.rowUnder = buildRowUnder
        p.selID = buildSelID; p.receiver = buildSelReceiver; p.emitters = buildPartEmitters; p.cast = buildPartCast; p.castSlots = buildCastSlots
        p.rowReceiver = buildRowReceiver; p.rowEmitters = buildRowEmitters   // PER-ROW I/O overrides (Paul 2026-08-18)
        p.rate = buildPartRate; p.length = buildPartLen                      // PER-PART CLOCK (Paul 2026-08-19)
        buildParts[buildCurrentPart] = p
    }
    private func buildLoadPart(_ i: Int) {
        guard i >= 0, i < buildParts.count else { return }
        buildCurrentPart = i
        let p = buildParts[i]
        buildStagingCells = p.stagingCells; buildStagingSel = p.stagingSel
        buildRowChain = p.rowChain; buildRowShade = p.rowShade; buildRowUnder = p.rowUnder
        buildSelID = p.selID; ddColourSel = p.selID.flatMap { colourIDs.firstIndex(of: $0) } ?? -1; buildSelReceiver = p.receiver; buildPartEmitters = p.emitters; buildPartCast = p.cast; buildCastSlots = p.castSlots
        buildRowReceiver = p.rowReceiver ?? Array(repeating: nil, count: 8)   // PER-ROW I/O — old parts have nil → all rows inherit (Paul 2026-08-18)
        buildRowEmitters = p.rowEmitters ?? Array(repeating: nil, count: 8)
        buildPartRate = p.rate; buildPartLen = p.length                       // PER-PART CLOCK (Paul 2026-08-19)
        buildReslotCast()                                       // migrate old parts + backfill any extra colour missing a slot
        buildEnforceCastHues()                                  // strong rule: no two palette colours share a hue
        buildPulseColourID = nil; buildAuditionID = nil; buildDeletedRows = [:]; buildPlacedOrig = [:]   // transient — never crosses a part
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
        let colours = ephemeral.map { id -> Colour in var c = Colour(colourID: id, type: .arp); c.defined = true; c.templateChain = buildColourReg[id]; return c }
        var hues: [String: UInt32] = [:]; for id in ephemeral { if let h = colourHueOverride[id] { hues[id] = h } }
        return BuildUnassignedData(part: part, colours: colours, hues: hues, idCounter: buildIDCounter)
    }
    // RESTORE the saved unassigned part on load: re-register its ephemeral colours + hues, lift the id counter past
    // them (so new colours don't collide), then place it as the single unassigned part and load it into the workshop.
    func buildRestoreUnassigned(_ u: BuildUnassignedData) {
        for c in u.colours { buildColourReg[c.colourID] = c.templateChain ?? [] }
        for (id, hue) in u.hues { colourHueOverride[id] = hue }
        buildIDCounter = max(buildIDCounter, u.idCounter)
        buildSyncColours()
        var part = u.part; part.deployed = false
        if let i = buildParts.firstIndex(where: { !$0.deployed }) { buildParts[i] = part; buildLoadPart(i) }
        else { buildParts.append(part); buildLoadPart(buildParts.count - 1) }
    }
    // The per-poll persistence tick (BUILD active only): restore a just-loaded part ONCE, then keep the save-state current.
    func buildPersistTick() {
        guard activeTab == .build else { return }
        if let u = au?.consumeBuildUnassigned() { buildRestoreUnassigned(u) }   // a host load happened while on BUILD
        if let sc = au?.consumeBuildScenes() { buildRestoreScenes(sc.scenes, active: sc.active) }   // SCENES V2: restore the saved play-grid arrangements
        au?.setBuildUnassigned(buildCaptureUnassigned())                         // keep fullState's copy fresh
        au?.setBuildScenes(buildCaptureScenes(), active: buildActiveScene)       // …and the scenes — cheap (COW refcount bumps, not a deep copy), so no dirty-gate needed
    }
    // THE DEFAULT PALETTE (Paul 2026-08-14): eight starter colours, one per processor type (arp/ratchet/euclid/echo
    // named + strum/chance/harmonize/drone — NEVER passgate). They open the palette as 2 rows of 4 and are present in
    // every part's cast. Each carries a single-processor machine at that type's default settings.
    static let buildDefaultTypes: [ProcessorType] = [.arp, .ratchet, .euclid, .weave, .echo, .strum, .chance, .split, .tutti, .length, .harmonize, .drone]
    // Mint a FRESH set of 8 default colours for a PART — its OWN ephemeral copies (unique IDs, canonical hues), so a
    // colour is NEVER shared between parts. Editing one part's default doesn't touch another's. (Paul 2026-08-15)
    func buildFreshDefaultCast() -> [String] {
        var ids: [String] = []
        for (i, t) in Self.buildDefaultTypes.enumerated() {
            buildIDCounter += 1
            let id = "b\(buildIDCounter)"
            buildColourReg[id] = [ProcessorSlot(type: t)]
            colourHueOverride[id] = i < colourHexes.count ? colourHexes[i] : 0x808080
            ids.append(id)
        }
        buildSyncColours()
        return ids
    }
    // Mint a TAB colour: an ephemeral colour carrying `machine` with tab n's FIXED hue (colourHexes[n]), verbatim
    // (no uniquify — a tab always shows the same colour). (Paul 2026-08-17 — the 8-tab model)
    private func buildNewTabColour(_ n: Int, machine: [ProcessorSlot], transpose: Int = 0) -> String {
        let hex = n < colourHexes.count ? colourHexes[n] : 0x808080
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
        for c in 0..<8 { buildStagingSel[c] = -1 }                 // nothing selected → nothing plays until a colour is added
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
    private func buildSwitchPart(_ i: Int) { guard i != buildCurrentPart else { return }; buildReturnPart = nil; buildSavePart(); buildLoadPart(i) }   // any manual switch cancels a pending return
    // A RESTORE switch (via a valve): remember the UNDEFINED bench we're leaving, so the next promote returns to it
    // instead of a blank part. (Paul 2026-08-15 QoL)
    private func buildRestoreSwitch(to p: Int) {
        let returning = (buildCurrentPart >= 0 && buildCurrentPart < buildParts.count && !buildParts[buildCurrentPart].deployed) ? buildCurrentPart : nil
        buildSwitchPart(p)                                   // clears buildReturnPart …
        buildReturnPart = returning                          // … then records the bench to come back to
    }
    // A part is UNUSED when nothing distinguishes it from a just-created one: un-deployed, empty staging, and its cast
    // is exactly its 8 pristine per-part defaults (no edits/adds). (Paul 2026-08-15 — per-part colours)
    private func buildPartIsUnused(_ p: BuildPart) -> Bool {
        guard !p.deployed, p.stagingCells.allSatisfy({ $0.allSatisfy { $0 == nil } }), p.cast.count == Self.buildDefaultTypes.count else { return false }
        return zip(p.cast, Self.buildDefaultTypes).allSatisfy { id, t in buildColourReg[id] == [ProcessorSlot(type: t)] }
    }
    // §3: a NEW part arrives FRESH — empty staging, unset I/O; its palette opens on the 8 DEFAULTS (Paul 2026-08-14).
    // REUSE an existing unused part instead of appending, so flatten→restore stops accumulating stray "UNASSIGNED PART"
    // entries. Reuse touches only an empty, un-deployed slot, so no deployed part's stored index shifts. (Paul 2026-08-15)
    private func buildAddPart() {
        buildRecordUndo()   // BUILD UNDO: add a part
        buildSavePart()
        // QoL: if a restore left an undefined bench pending, RETURN to it (the part the user was building) instead of a
        // fresh one — so restore→promote drops them back on their in-progress work. (Paul 2026-08-15)
        if let ret = buildReturnPart, ret != buildCurrentPart, ret < buildParts.count, !buildParts[ret].deployed {
            buildReturnPart = nil; buildLoadPart(ret); buildRequestWorkshopVoice(.chain); return
        }
        buildReturnPart = nil
        if let reuse = buildParts.indices.first(where: { $0 != buildCurrentPart && buildPartIsUnused(buildParts[$0]) }) {
            buildLoadPart(reuse)   // pristine already — keep its OWN per-part defaults, just switch to it
        } else {
            let fresh = BuildPart()                                         // a new part opens on TAB 1 (empty passthrough)
            buildParts.append(fresh); buildLoadPart(buildParts.count - 1)
            buildSeedTab1()
        }
        buildRequestWorkshopVoice(.chain)                                    // default PLAY THIS MIDI CHAIN to ON for the new part (Paul 2026-08-25)
    }
    // A SINGLE deployed row = the staging SELECTION flattened: the selected cell per column (wherever its staging row
    // sits), and a column with NOTHING selected is left BLANK. Carries the part's I/O. Does NOT set deployed/claim/publish
    // — the caller owns those. (Paul 2026-08-14: single-row targets copy the selected cell regardless of row.)
    // PROMOTE = LOOPED COLUMNS (Paul 2026-08-19): the staging LOOP KEYS define the deployed part's LENGTH — the looped
    // SPAN (highest looped column + 1). Columns past it are dropped on deploy (a gap inside the span keeps its cell). No
    // loop set ⇒ the part's own LENGTH (or a full 8). This is how you build parts shorter than the bar.
    private func buildDeployLength() -> Int {
        if buildStagingLane != 0 {
            var hi = 0
            for c in 0..<8 where (buildStagingLane & (1 << UInt8(c))) != 0 { hi = c }
            return hi + 1
        }
        return buildPartLen ?? Snap.cols
    }
    // Set the CURRENT part's length from the deploy span (nil = a full 8), so performLen + the play-grid dimming reflect it.
    private func buildApplyDeployLength(_ len: Int) {
        let stored: Int? = len >= Snap.cols ? nil : len
        buildPartLen = stored
        if buildCurrentPart >= 0, buildCurrentPart < buildParts.count { buildParts[buildCurrentPart].length = stored }
    }
    private func buildCopySelectedRow(toRow R: Int, len: Int) {
        guard R >= 0, R < 8 else { return }
        var srcRows: [Int] = []                                        // the staging rows the selected cells come from
        for c in 0..<8 {
            let sr = c < buildStagingSel.count ? buildStagingSel[c] : -1   // this column's selected (playing) cell
            if c < len, sr >= 0, sr < 8, let cid = buildStagingCells[c][sr] {   // only columns within the looped span deploy
                buildPerformCells[c][R] = cid
                buildPerformChain[c][R] = (sr < buildRowChain.count && !buildRowChain[sr].isEmpty) ? buildRowChain[sr] : []
                srcRows.append(sr)
            } else {
                buildPerformCells[c][R] = nil; buildPerformChain[c][R] = []   // outside the loop span OR nothing selected → blank
            }
        }
        buildDeployRowIO(R, from: srcRows)                            // carry the SELECTED cells' OWN resolved I/O (Paul 2026-08-19)
    }

    // PER-ROW I/O on promote (Paul 2026-08-19): a deployed play-grid row carries the SELECTED cells' OWN resolved
    // receiver + emitters (their staging row's, per-row override honoured), NOT the part DEFAULT — so a row set to
    // emitter B stays on B when promoted (was the B→A bug). The promoted cells should all resolve to the SAME I/O;
    // if they diverge (selected cells sit on rows with different doors/emitters), carry the first + FLAG it, since the
    // play grid holds one I/O per row and the mix would otherwise change silently.
    private func buildDeployRowIO(_ R: Int, from srcRows: [Int]) {
        guard R >= 0, R < 8 else { return }
        let emitters = srcRows.map { buildRowEmittersResolved($0) }
        let receivers = srcRows.map { buildRowReceiverResolved($0) }
        let emit = emitters.first ?? (buildPartEmitters.isEmpty ? [.a] : buildPartEmitters)
        let recv = receivers.first ?? buildSelReceiver
        buildPerformEmit[R] = emit
        buildPerformRecv[R] = recv
        if emitters.contains(where: { $0 != emit }) || receivers.contains(where: { $0 != recv }) {
            buildFlashPromote("PROMOTED CELLS DIFFER IN I/O")        // the CHECK — the selected set wasn't uniform
        }
    }
    // A brief centre banner (reuses the HOLD-TO-ALL banner surface), auto-clears. (Paul 2026-08-19)
    private func buildFlashPromote(_ msg: String) {
        withAnimation { buildIOHoldMsg = msg }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.4) { if buildIOHoldMsg == msg { withAnimation { buildIOHoldMsg = nil } } }
    }

    // §1: deploying the current part to a SINGLE play-grid row CHRISTENS it (PART n) and copies its per-column selection
    // into the tapped row (selected cell regardless of staging row · blank where unselected), carrying the part's I/O.
    func buildDeployCurrentPart(toRow R: Int) {
        guard buildCurrentPart >= 0, buildCurrentPart < buildParts.count, R >= 0, R < 8 else { return }   // CR-18[extra]: >= 0 guard for symmetry with the siblings — a -1 part would trap on buildParts[-1]
        buildRecordUndo("deploy")   // BUILD UNDO: promote/deploy a part to the play grid
        buildParts[buildCurrentPart].deployed = true
        let len = buildDeployLength()                           // PROMOTE = LOOPED COLUMNS: the loop span sets the length
        buildApplyDeployLength(len)
        buildCopySelectedRow(toRow: R, len: len)
        buildPerformPart[R] = buildCurrentPart                   // §2: the row now belongs to this part
        buildPerformStagingRow[R] = -1                           // a single-rung lane — no rung map (per-cell mute, not selection)
        for c in 0..<8 { buildPerformMute.remove(c * 8 + R) }    // fresh row starts unmuted
        buildPublishScene()                                      // reflect live if the piece is playing
    }

    // Land the current part on a BAND. Christens like a flatten. (Paul 2026-08-14 — deployment semantics by target shape:)
    //   • MULTI-ROW band (rows > 1): copy the whole staging LADDER — every OCCUPIED staging row (selected AND muted cells)
    //     becomes a band rung, top-down, capped to the band's height. Nothing is dropped; the muted cells are the rungs.
    //   • SINGLE-ROW band (rows == 1): the selected cell per column (regardless of row), blank where unselected.
    func buildDeployBand(base: Int, rows: Int) {
        guard buildCurrentPart >= 0, buildCurrentPart < buildParts.count else { return }   // CR-18[extra]: >= 0 guard for symmetry
        buildRecordUndo("deploy")   // BUILD UNDO: deploy a part across a band
        buildParts[buildCurrentPart].deployed = true
        let len = buildDeployLength()                           // PROMOTE = LOOPED COLUMNS: the loop span sets the length
        buildApplyDeployLength(len)
        for i in 0..<rows where base + i < 8 { for c in 0..<8 { buildPerformCells[c][base + i] = nil; buildPerformChain[c][base + i] = []; buildPerformMute.remove(c * 8 + base + i) }; buildPerformPart[base + i] = buildCurrentPart; buildPerformStagingRow[base + i] = -1 }   // clear the band (+ its mutes + rung map) + claim it (§2)
        if rows <= 1 {
            buildCopySelectedRow(toRow: base, len: len)          // a lane: the selected melody, blank where unselected / past the span
        } else {
            let occupied = (0..<8).filter { sr in (0..<8).contains { c in buildStagingCells[c][sr] != nil } }   // staging rows that hold ANY cell
            for (i, sr) in occupied.prefix(rows).enumerated() {  // one rung per occupied staging row (muted cells included)
                let R = base + i; guard R < 8 else { break }
                buildPerformStagingRow[R] = sr                   // remember which staging row this rung came from (for selection sync-back)
                for c in 0..<8 where c < len {                   // only columns within the looped span deploy
                    if let cid = buildStagingCells[c][sr] {
                        buildPerformCells[c][R] = cid
                        buildPerformChain[c][R] = (sr < buildRowChain.count && !buildRowChain[sr].isEmpty) ? buildRowChain[sr] : []
                    }
                }
                buildDeployRowIO(R, from: [sr])                       // this rung IS one staging row — carry its OWN resolved I/O (Paul 2026-08-19)
            }
        }
        buildPublishScene()
    }

    // THE VALVE (design ferry: row-button-valve) — the LEFT band selector is a FLATTEN ⇄ RESTORE toggle.
    // EMPTY band → flatten the current part onto it (deploy + christen), STASH its workshop behind the band, and open
    // a FRESH part (staging/column clear). SET band (already holds a part) → UNLOAD it and RESTORE that part's stashed
    // workshop (a part switch: the current workshop retains under its own part). The RIGHT per-row rung-flatten is the
    // held exception — left unchanged until Paul defines it.
    // Shared valve output/focus (Paul 2026-08-14/15): chain audition off; FOCUS the part grid. PROMOTE starts the play
    // grid (it carries the output; the fresh part is empty/silent). RESTORE keeps the play grid going iff other parts
    // remain deployed, and the restored part plays from the part grid alongside.
    private func buildValveOutput(promote: Bool) {
        if ddSolo { ddSolo = false; au?.clearColourSolo() }
        buildStagingPlaying = true
        buildPerformPlaying = promote ? true : buildPerformPart.contains { $0 >= 0 }
        buildPublishScene()
    }
    // The play grid's band form → the (base, rows) range containing a grid row, and the band's 1-based label number.
    private func buildBandRange(forRow r: Int) -> (base: Int, rows: Int)? {
        var base = 0; for rows in [3, 2, 1, 1, 1] { if r >= base && r < base + rows { return (base, rows) }; base += rows }; return nil
    }
    private func buildBandNumber(base: Int) -> Int {
        var acc = 0; for (b, rows) in [3, 2, 1, 1, 1].enumerated() { if acc == base { return b + 1 }; acc += rows }; return 1
    }
    // A band is WHOLE (one part fills every rung — a LEFT-valve deploy) vs PER-RUNG (separate sub-parts on its rungs, or
    // partly empty — RIGHT-valve deploys). The two are mutually exclusive on a band. (Paul 2026-08-15)
    private func buildBandIsWhole(base: Int, rows: Int) -> Bool {
        let ps = (0..<rows).compactMap { base + $0 < 8 ? buildPerformPart[base + $0] : nil }
        return ps.allSatisfy { $0 >= 0 } && Set(ps).count == 1
    }
    private func buildRowInWholeBand(_ r: Int) -> Bool { buildBandRange(forRow: r).map { buildBandIsWhole(base: $0.base, rows: $0.rows) } ?? false }

    // LEFT band valve — the WHOLE band. EMPTY → flatten the current part onto every rung (deploy + christen · stash ·
    // clear · fresh part). WHOLE (one part fills it) → restore ALL rungs to the part grid. PER-RUNG band → INERT (use
    // the right buttons to restore individual rungs).
    func buildBandValve(base: Int, rows: Int) {
        let anySet = (0..<rows).contains { base + $0 < 8 && buildPerformPart[base + $0] >= 0 }
        if !anySet {
            buildDeployBand(base: base, rows: rows); buildAddPart(); buildValveOutput(promote: true)
        } else if buildBandIsWhole(base: base, rows: rows), buildPerformPart[base] >= 0, buildPerformPart[base] < buildParts.count {
            let p = buildPerformPart[base]
            buildRestoreSwitch(to: p)
            for i in 0..<rows where base + i < 8 { for c in 0..<8 { buildPerformCells[c][base + i] = nil; buildPerformChain[c][base + i] = []; buildPerformMute.remove(c * 8 + base + i) }; buildPerformPart[base + i] = -1; buildPerformStagingRow[base + i] = -1 }
            buildParts[p].deployed = false
            buildValveOutput(promote: false)
        }
        // else PER-RUNG → inert
    }
    // RIGHT per-rung valve (Paul 2026-08-15) — a SINGLE rung of a multi-row band, stored as a sub-part "PART na/nb/nc".
    // EMPTY rung → flatten the current part onto it (single-row flatten · stash · clear · fresh part). SET rung → restore
    // JUST that sub-part to the part grid (one at a time; the other rungs stay deployed). Inert on a WHOLE-band band.
    func buildRowValve(row R: Int) {
        guard R >= 0, R < 8, !buildRowInWholeBand(R) else { return }
        let p = buildPerformPart[R]
        if p >= 0, p < buildParts.count {                    // SET → restore this rung's sub-part
            buildRestoreSwitch(to: p)
            for c in 0..<8 { buildPerformCells[c][R] = nil; buildPerformChain[c][R] = []; buildPerformMute.remove(c * 8 + R) }
            buildPerformPart[R] = -1; buildPerformStagingRow[R] = -1
            buildParts[p].deployed = false
            buildValveOutput(promote: false)
        } else {                                             // EMPTY rung → deploy the current part to this single rung
            buildDeployCurrentPart(toRow: R); buildAddPart(); buildValveOutput(promote: true)
        }
    }

    // START/STOP THE PLAY GRID — the PIECE voice (third zoom level). INDEPENDENT of the auditions (correction):
    // starting/stopping it never touches the chain/part; the stage plays until the user stops it.
    private func buildTogglePerformVoice() {
        buildPerformPlaying.toggle()
        buildPublishScene()
    }
    // How many play-grid rows a deployed part occupies (1 = single-rung lane · >1 = multi-rung ladder).
    private func buildPerformPartRows(_ part: Int) -> Int { part < 0 ? 0 : (0..<8).filter { buildPerformPart[$0] == part }.count }
    // MUTE a single-rung part's cell (dropped from the mix) — toggled on the play grid, reflected live.
    private func buildTogglePerformMute(_ c: Int, _ r: Int) {
        let k = c * 8 + r
        if buildPerformMute.contains(k) { buildPerformMute.remove(k) } else { buildPerformMute.insert(k) }
        buildPublishScene()
    }
    // A play-grid cell SOUNDS this column when it's the active rung: single-rung parts always; a multi-rung part only
    // when its column's selection points at this rung's source staging row. (Paul 2026-08-15)
    private func buildPerformActiveRung(_ c: Int, _ r: Int) -> Bool {
        let part = buildPerformPart[r]
        guard part >= 0, buildPerformPartRows(part) > 1 else { return true }   // single-rung / empty band → always
        let sr = buildPerformStagingRow[r]
        return sr >= 0 && part < buildParts.count && c < buildParts[part].stagingSel.count && buildParts[part].stagingSel[c] == sr
    }
    // Tap a multi-rung cell → make it the column's active rung, or deselect it (column silent). Writes the DEPLOYED
    // part's stashed selection directly, so live changes mirror back to the part grid on revert. (Paul 2026-08-15)
    private func buildTogglePerformRung(_ c: Int, _ r: Int) {
        let sr = buildPerformStagingRow[r]; let part = buildPerformPart[r]
        guard sr >= 0, part >= 0, part < buildParts.count, c < buildParts[part].stagingSel.count else { return }
        let newSel = (buildParts[part].stagingSel[c] == sr) ? -1 : sr
        buildParts[part].stagingSel[c] = newSel
        if part == buildCurrentPart, c < buildStagingSel.count { buildStagingSel[c] = newSel }   // C2 (Paul 2026-08-16): keep the LIVE copy in sync, else the next buildSavePart clobbers this rung toggle
        buildPublishScene()
    }
    private var buildCurrentDeployed: Bool { buildCurrentPart < buildParts.count && buildParts[buildCurrentPart].deployed }
    // A deployed part is named for WHERE it lives: a WHOLE band → "PART n" (n = band number); a single rung of a
    // multi-row band → "PART na/nb/nc" (letter = the rung). Unassigned → "UNASSIGNED PART". (Paul 2026-08-15)
    private func buildPartName(_ i: Int) -> String {
        guard i >= 0, i < buildParts.count, buildParts[i].deployed else { return "UNASSIGNED PART" }
        let rows = (0..<8).filter { buildPerformPart[$0] == i }
        guard let first = rows.first, let (base, bandRows) = buildBandRange(forRow: first) else { return "PART \(i + 1)" }
        let n = buildBandNumber(base: base)
        if rows.count >= bandRows { return "PART \(n)" }                          // whole band (incl. a single-row lane)
        let letters = ["a", "b", "c", "d"], rung = first - base
        return "PART \(n)\(rung < letters.count ? letters[rung] : "")"           // a single rung of a multi-row band
    }

    @ViewBuilder private func buildPartHeader() -> some View {
        HStack(spacing: 6) {
            Menu {                                                // the selector — switch between parts
                ForEach(0..<buildParts.count, id: \.self) { i in Button(buildPartName(i)) { buildSwitchPart(i) } }
            } label: {
                Text("\(buildPartName(buildCurrentPart)) ▾").font(.system(size: 10, weight: .heavy, design: .monospaced)).foregroundColor(.white)
                    .lineLimit(1).minimumScaleFactor(0.7)
                    .padding(.horizontal, 10).frame(height: 26)
                    .background(RoundedRectangle(cornerRadius: 8).fill(buildPanel))
                    .overlay(alignment: .bottom) { Rectangle().fill(buildPartInk).frame(height: 2) }   // §2: the part's bright-ink underline
            }
            // ADD PART — GLOWS (pink) once the current part is deployed; only then is it askable.
            Text("ADD PART").font(.system(size: 9, weight: .heavy, design: .monospaced))
                .foregroundColor(buildCurrentDeployed ? .black : buildDim)
                .padding(.horizontal, 8).frame(height: 26)
                .background(RoundedRectangle(cornerRadius: 8).fill(buildCurrentDeployed ? buildPink : buildCell))
                .opacity(buildCurrentDeployed ? 1 : 0.45)
                .contentShape(Rectangle())
                .onTapGesture { if buildCurrentDeployed { buildAddPart() } }
            Spacer(minLength: 0)
        }
    }

    // The per-grid PLAY/EDIT radio — two chips styled exactly like the PART 1 ▾ header (size-10 heavy mono, h26,
    // buildPanel), RIGHT-aligned so it sits at PART 1's row above each grid. The active side fills cyan.
    @ViewBuilder private func buildGridModeRadio(_ mode: Binding<BuildGridMode>, onEye: (() -> Void)? = nil) -> some View {
        HStack(spacing: 6) {
            Spacer(minLength: 0)                                  // the eye moved to the grid's top-left corner (buildGridCornerEye)
            ForEach([BuildGridMode.play, .edit], id: \.self) { m in
                Text(m.rawValue).font(.system(size: 10, weight: .heavy, design: .monospaced))
                    .foregroundColor(mode.wrappedValue == m ? .black : buildDim)
                    .padding(.horizontal, 10).frame(height: 26)
                    .background(RoundedRectangle(cornerRadius: 8).fill(mode.wrappedValue == m ? buildCyan : buildPanel))
                    .contentShape(Rectangle())
                    .onTapGesture { mode.wrappedValue = m }
            }
        }
    }
    // The grid's full-screen "eye" — seated in the grid's TOP-LEFT CORNER cell (immediately left of the column
    // selectors, immediately above the row selectors). popup 0 = the part grid · 1 = the play grid. (Paul 2026-08-17)
    @ViewBuilder private func buildGridCornerEye(cell: CGFloat, popup: Int) -> some View {
        Image(systemName: "eye").font(.system(size: min(22, cell * 0.82), weight: .semibold)).foregroundColor(buildCyan)   // bigger eye (Paul 2026-08-19)
            .frame(width: cell, height: cell)
            .background(RoundedRectangle(cornerRadius: 6).fill(buildPanel))
            .contentShape(Rectangle())
            .onTapGesture { if popup == 1 { buildPlayMode = .play }; buildGridPopup = popup }
    }

    // The selected door's MIDI-IN CHANNEL box (keyboard-sized) — tap opens a channel selector (OMNI · CH 1–16).
    @ViewBuilder private func buildChannelBox(receiver i: Int, channel: Int) -> some View {
        Menu {
            Button("OMNI") { buildRecordUndo("recv"); au?.setReceiverChannel(i, 0); refreshFromDocument() }
            ForEach(1..<17, id: \.self) { ch in Button("CH \(ch)") { buildRecordUndo("recv"); au?.setReceiverChannel(i, ch); refreshFromDocument() } }
        } label: {
            VStack(spacing: 2) {
                Text("MIDI IN ▾").font(.system(size: 7, weight: .heavy, design: .monospaced)).foregroundColor(buildDim).tracking(1)
                Text(channel == 0 ? "OMNI" : "CH \(channel)").font(.system(size: 16, weight: .heavy, design: .monospaced)).foregroundColor(buildCyan)
            }
            .frame(maxWidth: .infinity).frame(height: 52)         // fills the midi-select row
            .background(RoundedRectangle(cornerRadius: 7).fill(buildCell))
            .overlay(RoundedRectangle(cornerRadius: 7).stroke(buildEdge, lineWidth: 1))
        }
    }

    // The octave keyboard for the selected PIANO door (one octave from C3, matching the receiver keyboard). Tap a key
    // to pick/unpick it into the door's frozen pool; dimmed + inert when the door isn't in PIANO mode.
    @ViewBuilder private func buildKeyboard(receiver i: Int, held: Set<Int>, enabled: Bool, width: CGFloat) -> some View {
        let startNote = 48                                    // C3, one octave (matches ReceiverConfigView)
        let whiteOffsets = [0, 2, 4, 5, 7, 9, 11]
        let blackAfter: [Int: Int] = [0: 1, 1: 3, 3: 6, 4: 8, 5: 10]
        let ww = max(1, width / 7)
        let bw = ww * 0.62
        ZStack(alignment: .topLeading) {
            // WHITE keys — a real HStack (LAYOUT-positioned, NOT .offset). `.offset` keeps each view's layout frame at
            // x=0 and only shifts the render, which breaks hit-testing here; an HStack gives each key an honest frame.
            HStack(spacing: 1) {
                ForEach(0..<7, id: \.self) { wi in
                    let note = startNote + whiteOffsets[wi]
                    RoundedRectangle(cornerRadius: 3).fill(held.contains(note) ? buildCyan : Color(white: 0.9))
                        .overlay(RoundedRectangle(cornerRadius: 3).stroke(buildPanel, lineWidth: 1))
                        .frame(width: max(1, ww - 1), height: 52)
                        .contentShape(Rectangle())
                        .onTapGesture { buildRecvEdit { au?.toggleReceiverPianoNote(i, note) } }
                }
            }
            // BLACK keys straddle white-key boundaries → positioned in an overlay HStack of per-white slots (still
            // layout-based: each slot is ww wide, its black key pinned trailing so it sits over the boundary).
            HStack(spacing: 0) {
                ForEach(0..<7, id: \.self) { wi in
                    Color.clear.frame(width: ww, height: 52)
                        .overlay(alignment: .trailing) {
                            if let bOff = blackAfter[wi] {
                                let note = startNote + bOff       // pinned to the white-key boundary (trailing) — NO .offset, so its hit frame is honest
                                RoundedRectangle(cornerRadius: 2).fill(held.contains(note) ? buildCyan : buildPanel)
                                    .frame(width: bw, height: 31)
                                    .contentShape(Rectangle())
                                    .onTapGesture { buildRecvEdit { au?.toggleReceiverPianoNote(i, note) } }
                            }
                        }
                }
            }
            .allowsHitTesting(true)
        }
        .frame(width: width, height: 52, alignment: .topLeading)
        .padding(.vertical, 2)
        .opacity(enabled ? 1 : 0.35)
        .allowsHitTesting(enabled)
    }

    // The per-receiver SOURCE toggle flanking the piano: a DIN connector (MIDI in) on the left, the in-app piano on
    // the right — piano-height, half an R1 button wide. The active side is filled cyan.
    @ViewBuilder private func buildSourceToggle(_ icon: String, active: Bool, width: CGFloat, rotate: Bool = false, action: (() -> Void)? = nil) -> some View {
        Button { action?() } label: {                        // a Button (not onTapGesture) — reliable hit-testing on this small target
            Image(systemName: icon).font(.system(size: 18, weight: .semibold))
                .rotationEffect(.degrees(rotate ? 90 : 0))
                .foregroundColor(active ? .black : buildDim)
                .frame(width: width, height: 52)
                .background(RoundedRectangle(cornerRadius: 7).fill(active ? buildCyan : buildCell))
                .overlay(RoundedRectangle(cornerRadius: 7).stroke(active ? Color.clear : buildEdge, lineWidth: 1))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
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

    // MIDI OUT readout below the emitters — the lit emitters + their stamp channels. Piano-height, cast-width.
    @ViewBuilder private func buildMidiOutInfo(buses: Set<Bus>, castW: CGFloat) -> some View {
        let chans = au?.uiBusChannels() ?? [1, 2, 3, 4]
        let lit = Array(Bus.allCases.enumerated()).filter { buses.contains($0.element) }
        let summary = lit.isEmpty ? "—"
            : lit.map { "\($0.element.rawValue)→CH\(chans.indices.contains($0.offset) ? chans[$0.offset] : $0.offset + 1)" }.joined(separator: "   ")
        VStack(spacing: 3) {
            Text("MIDI OUT").font(.system(size: 8, weight: .heavy, design: .monospaced)).foregroundColor(buildPink).tracking(1.2)
            Text(summary).font(.system(size: lit.count > 1 ? 11 : 15, weight: .heavy, design: .monospaced)).foregroundColor(buildCyan)
                .lineLimit(1).minimumScaleFactor(0.55)
        }
        .frame(width: castW, height: 52)
        .background(RoundedRectangle(cornerRadius: 8).fill(buildCell))
    }

    @ViewBuilder private func buildCastPalette(castW: CGFloat, cell: CGFloat) -> some View {
        let cols = 8                                                // 8×4 grid (original proportions); defaults sit in the top-left 4×2 block
        let swW = (castW - BuildGeom.castGap * CGFloat(cols - 1)) / CGFloat(cols)   // 8 swatches fill the column width
        let pulseSlot: Int? = {                                    // where the pulsing candidate lives (Paul 2026-08-14)
            guard let pid = buildPulseColourID else { return nil }
            if let existing = buildPartCast.firstIndex(of: pid) {  // already in the palette → pulse THAT slot, never a phantom new one …
                return pid == ddSelectedColourID ? nil : (0..<32).first { buildCastMemberAt($0) == existing }   // … UNLESS already selected
            }
            return buildFirstFreePaletteSlot()                     // a genuinely NEW colour → the "create me" candidate at the bottom-right
        }()
        VStack(spacing: BuildGeom.castGap) {
            ForEach(0..<4, id: \.self) { row in
                HStack(spacing: BuildGeom.castGap) {
                    ForEach(0..<cols, id: \.self) { col in
                        buildCastSlot(row * cols + col, swW: swW, swH: cell, pulseSlot: pulseSlot)   // rows sit at GRID-cell height so the cast aligns with the two grids
                    }
                }
            }
        }
    }

    // THE TARGET — a reticle marking the SELECTED machine wherever it appears: the cast swatch, the footer EXAMPLE cell,
    // and every grid cell that shares the selected colour (matches its properties). (Paul 2026-08-14)
    @ViewBuilder private func buildTargetMark(_ size: CGFloat) -> some View {
        Image(systemName: "scope")
            .font(.system(size: size, weight: .medium))
            .foregroundColor(.white)
            .shadow(color: .black.opacity(0.7), radius: 1)
            .allowsHitTesting(false)
    }

    // One cast slot (of the 4×4 palette). DEFAULTS fill top-left, adds fill bottom-right (see buildCastMemberAt).
    @ViewBuilder private func buildCastSlot(_ i: Int, swW: CGFloat, swH: CGFloat, pulseSlot: Int?) -> some View {
        if i == pulseSlot, let pid = buildPulseColourID {          // the PULSING candidate → tap to commit (SELECT it; never a duplicate)
            TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: animationsPaused)) { tl in
                let phase = 0.5 + 0.5 * sin(tl.date.timeIntervalSinceReferenceDate * 3.4)   // pulse the colour in/out over black
                ZStack {
                    RoundedRectangle(cornerRadius: 6).fill(Color.black)
                    RoundedRectangle(cornerRadius: 6).fill(colourColor(pid) ?? buildCell).opacity(0.15 + 0.85 * phase)
                }
                .frame(width: swW, height: swH)
                .overlay(RoundedRectangle(cornerRadius: 6).stroke(buildEdge, lineWidth: 1))   // a NEUTRAL border — pulsing is NOT the selected/targeted state
                .contentShape(Rectangle())
                .onTapGesture { buildCommitPulse() }
            }
        } else if let m = buildCastMemberAt(i) {                   // a MEMBER of the cast — TAP selects, LONG-PRESS adds
            let id = buildPartCast[m]
            RoundedRectangle(cornerRadius: 6).fill(colourColor(id) ?? buildCell)
                .frame(width: swW, height: swH)
                .overlay(RoundedRectangle(cornerRadius: 6)
                    .stroke(Color.white, style: StrokeStyle(lineWidth: 2, dash: [3]))
                    .opacity(id == ddSelectedColourID ? 1 : 0))
                .overlay { if id == ddSelectedColourID { buildTargetMark(min(swW, swH) * 0.6) } }   // THE TARGET rides the selected cast cell
                .contentShape(Rectangle())
                .onTapGesture { buildSelectID(id) }
                .onLongPressGesture(minimumDuration: 0.4) { buildAddCastColour() }   // ANY button can ADD a colour — via long press (Paul 2026-08-14)
        } else {                                                   // an EMPTY slot — a "+" that ADDS on LONG PRESS (every button can add)
            RoundedRectangle(cornerRadius: 6).fill(buildCell)
                .frame(width: swW, height: swH)
                .overlay(Text("+").font(.system(size: 14, weight: .heavy, design: .monospaced)).foregroundColor(buildDim))
                .overlay(RoundedRectangle(cornerRadius: 6).stroke(buildEdge, lineWidth: 1))
                .contentShape(Rectangle())
                .onLongPressGesture(minimumDuration: 0.4) { buildCloneLastColour(atSlot: i) }   // long-press an empty cell → clone the last-used colour onto THIS cell
        }
    }

    // THE PALETTE GRID stays 8×4 (32 slots). The 8 DEFAULTS occupy the TOP-LEFT 4×2 block (a proportion of the grid);
    // user-added colours fill from the BOTTOM-RIGHT corner (slot 31 first, then 30, …) so a new colour "starts bottom-right".
    private var buildCastDefaultCount: Int { min(Self.buildDefaultTypes.count, buildPartCast.count) }
    // Is a slot part of the top-left 4×2 DEFAULT block (which is positional), vs the freely-placeable extras region?
    private func buildIsDefaultSlot(_ slot: Int) -> Bool { let row = slot / 8, col = slot % 8; return row < 2 && col < 4 }
    // slot (0–31) → the buildPartCast index shown there, or nil (an empty slot). 8 cols × 4 rows. The default block is
    // positional (top-left); every OTHER colour sits where it was explicitly placed (buildCastSlots).
    private func buildCastMemberAt(_ slot: Int) -> Int? {
        let dc = buildCastDefaultCount
        if buildIsDefaultSlot(slot) {                                 // the top-left 4×2 default block
            let row = slot / 8, col = slot % 8, k = row * 4 + col
            return k < dc ? k : nil
        }
        guard let id = buildCastSlots[slot] else { return nil }       // extras live at their explicitly-placed slot
        return buildPartCast.firstIndex(of: id)
    }
    // The bottom-right-most FREE add slot — where the next auto-added colour lands (nil once the palette is full).
    private func buildFirstFreeCastSlot() -> Int? {
        for slot in stride(from: 31, through: 0, by: -1) where !buildIsDefaultSlot(slot) && buildCastSlots[slot] == nil { return slot }
        return nil
    }
    private func buildFirstFreePaletteSlot() -> Int? { buildFirstFreeCastSlot() }
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
    private func buildCloneLastColour(atSlot slot: Int? = nil) {
        guard let src = buildSelID else { buildAddCastColour(atSlot: slot); return }
        buildRecordUndo()   // BUILD UNDO: record BEFORE minting so undo reverts the whole clone, not just the slot placement (U6 fix 2026-08-27)
        let id = buildNewColour(hex: buildDistinctHue(), machine: buildColourMachine(src))   // SAME settings, a genuinely DIFFERENT colour (never reuse the source hue)
        if !buildPartCast.contains(id) { buildPartCast.append(id) }
        buildPlaceCastSlot(id, slot)                                                          // land it on the LONG-PRESSED cell (else first-free)
        buildEnforceCastHues()                                                                // strong rule: never two alike in the cast
        buildPulseColourID = nil                                                              // the clone IS the commit — never leave the SOURCE strobing
        buildSelectID(id)
    }
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
    private func buildCommitPulse() {
        guard let pid = buildPulseColourID else { buildPulseColourID = nil; return }
        buildRecordUndo()   // BUILD UNDO: committing the pulsing candidate into the cast (U6 fix 2026-08-27 — buildPlaceCastSlot no longer self-records)
        if !buildPartCast.contains(pid) { buildPartCast.append(pid); buildPlaceCastSlot(pid, nil); buildEnforceCastHues() }   // LAST TOUCHED promotes the colour INTO the cast (first-free slot)
        if pid == buildAuditionID { buildAuditionID = nil }           // it graduated from candidate to a real cast colour
        buildSelectID(pid)                                             // select it (loads its machine into the footer)
        buildPulseColourID = nil; buildPulseChain = []
        refreshFromDocument()
    }
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

    // ── MIDDLE COLUMN: STAGING (header · rail+loopkeys+grid · label) with the VERBS in their own box below ──────────
    @ViewBuilder private func buildStagingColumn(cell: CGFloat) -> some View {
        let hue = buildSelHue
        VStack(alignment: .center, spacing: 8) {
            AnyView(buildColumnButton("PLAY THIS PART", active: buildDisplayVoice == .part, fill: .grid, enabled: buildStagingPopulated || buildPerformPopulated, action: { buildRequestWorkshopVoice(buildDisplayVoice == .part ? .none : .part) })).padding(.bottom, 6)   // tap = play/STOP the part; enabled once EITHER grid has content
            AnyView(buildStagingGrid(cell: cell, hue: hue)).padding(.bottom, 12)   // the PART grid (doubled gap to the verb buttons, Paul 2026-08-18)
            AnyView(buildGridVerbButtons())                       // RANDOMIZE · MUTATE · CLEAR — the grid-scope verbs (Paul 2026-08-18)
            Spacer(minLength: 0)                                  // the I/O box now spans BOTH grid columns below them (buildIOBox); receivers moved there (Paul 2026-08-18)
        }
        .frame(maxWidth: .infinity, alignment: .center)
    }

    // STAGE THE GRID — the prominent call-to-action at the bottom of the centre column (upward chevron above the text).
    @ViewBuilder private func buildPopulate(gridW: CGFloat) -> some View {
        let enabled = buildStagingPopulated                                                  // disabled until ≥1 row is placed (Paul 2026-08-15)
        HStack(spacing: 5) {
            Image(systemName: "chevron.up").font(.system(size: 12, weight: .heavy)).foregroundColor(buildPink)
            Text("STAGE THE GRID").font(.system(size: 12, weight: .heavy, design: .monospaced)).foregroundColor(buildPink).tracking(1)
        }
        .frame(width: gridW).frame(height: 34)
        .background(RoundedRectangle(cornerRadius: 10).fill(buildCell))                      // §0 MUTED: a restrained CTA — pink is a WHISPER (ink + edge), not a slab
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(buildPink.opacity(0.55), lineWidth: 1))
        .opacity(enabled ? 1 : 0.35)
        .contentShape(Rectangle())
        .onTapGesture { if enabled { buildStageTheGrid() } }
        .allowsHitTesting(enabled)
    }

    // the staging 8×8 (row rail · loop keys · variation rows) — its OWN opaque view so its deep generic type doesn't
    // blow the metadata demangler's stack (see buildPaletteColumn's note).
    @ViewBuilder private func buildStagingGrid(cell: CGFloat, hue: Color) -> some View {
        HStack(alignment: .top, spacing: BuildGeom.cellGap) {
            buildRowButtons(cell: cell, hue: hue, bands: [8]) { buildTapColourTab($0) }  // LEFT row rail — same behaviour as the top colour tabs (select the row's colour / populate if empty) (Paul 2026-08-18)
            VStack(spacing: BuildGeom.cellGap) {
                buildLoopKeys(cell: cell, staging: true)           // the STAGING grid's OWN column loop
                VStack(spacing: BuildGeom.cellGap) {               // the staging grid — BLANK until stocked (PLACE)
                    ForEach(0..<8, id: \.self) { r in
                        HStack(spacing: BuildGeom.cellGap) {
                            ForEach(0..<8, id: \.self) { c in
                                let id = buildStagingCells[c][r]
                                let selected = buildStagingSel[c] == r   // a rung can be selected even when EMPTY (Paul 2026-08-15)
                                let inLoop = c < (buildPartLen ?? Snap.cols)   // PER-PART LENGTH: columns past the loop are OUTSIDE it — dimmed, never sound (Paul 2026-08-19)
                                RoundedRectangle(cornerRadius: 7)
                                    .fill((id.flatMap { colourColor($0) } ?? buildCell).opacity(selected ? 1.0 : 0.62))   // non-selected cells slightly DIMMER (Paul 2026-08-19)
                                    .frame(width: cell, height: cell)
                                    .overlay(RoundedRectangle(cornerRadius: 7)     // WHITE box = the SELECTED (playing) rung; that alone decides playback
                                        .stroke(buildStagingStroke(c: c, r: r, stocked: id != nil), lineWidth: selected ? 2.5 : 2))
                                    // (the per-cell TARGET is gone — the selected colour now shows as the tinted ROW NUMBER on its rail, Paul 2026-08-17)
                                    .overlay { ZStack {
                                        if buildPendingTab == r { buildPulseOverlay() }   // PENDING tab → its row previews, pulsing
                                        // ONLY the ACTIVE RUNG sweeps: the part renders just its selected rung per column (the rest of the
                                        // scene is the DEPLOYED piece), so a non-selected part cell must NOT read the piece's sounding. (Paul 2026-08-19 bug)
                                        buildNoteSweep(idx: c * 8 + r, active: buildStagingPlaying && selected && inLoop, id: id)
                                    } }
                                    .opacity(inLoop ? 1 : 0.3)   // OUTSIDE the loop → dimmed (still tappable — extend the length to include it)
                                    .contentShape(Rectangle())
                                    .onTapGesture { buildStagingTap(c, r) }
                            }
                        }
                    }
                }
                .overlay(alignment: .topLeading) { buildPlayhead(cell: cell, active: buildStagingPlaying, stepB: buildPartRate?.beats, lenC: buildStagingLane != 0 ? buildDeployLength() : buildPartLen) }   // PER-PART: rate/length — and when LOOPED, the playhead covers only the looped span (Paul 2026-08-19)
                .overlay { RoundedRectangle(cornerRadius: 10).stroke(buildPartInk, lineWidth: 1.5).padding(-4) }   // §2: the STAGING FRAME — bright-ink = the current part's bench
            }
            buildStagingRightRail(cell: cell)                                               // RIGHT rail — static right-pointing chevrons (Paul 2026-08-18)
        }
        .overlay(alignment: .topLeading) { buildGridCornerEye(cell: cell, popup: 0) }   // the eye in the grid's top-left corner cell
    }
    // The part-grid row-button action, shared by the LEFT and RIGHT rails (Paul 2026-08-18).
    private func buildStagingRowAction(_ row: Int) {
        switch buildRowMode {
        case .select: buildSelectRow(row)                                               // select the whole row's rung
        case .place:  buildSelectRow(row)                                               // (PLACE retired — the colour tabs place now)
        case .mutate: buildMutateRow(row)                                               // a value-tweaked variant of the selected colour
        }
    }
    // The part grid's RIGHT rail — static right-pointing chevrons that never change colour (unlike the left rail's
    // colour-tinted numbers). Same row action as the left. (Paul 2026-08-18)
    @ViewBuilder private func buildStagingRightRail(cell: CGFloat) -> some View {
        VStack(spacing: BuildGeom.cellGap) {
            Color.clear.frame(width: cell, height: cell)                                 // align past the loop-key row
            ForEach(0..<8, id: \.self) { r in
                RoundedRectangle(cornerRadius: 7).fill(Color.white.opacity(0.11))
                    .frame(width: cell, height: cell)
                    .overlay(RoundedRectangle(cornerRadius: 7).stroke(buildEdge, lineWidth: 1))
                    .overlay(Image(systemName: "chevron.right").font(.system(size: 12, weight: .bold)).foregroundColor(.white.opacity(0.7)))
                    .contentShape(Rectangle())
                    .onTapGesture { buildStagingRowAction(r) }
            }
        }
    }

    // The outline colour for a staging cell: WHITE for the ONE selected (playing) cell of its column; otherwise none.
    private func buildStagingStroke(c: Int, r: Int, stocked: Bool) -> Color {
        if buildStagingSel[c] == r { return .white }   // the selected (playing) rung — WHITE even when unpopulated (Paul 2026-08-15)
        return .clear
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

    private func buildRowColour(_ r: Int) -> String? { r >= 0 && r < 8 ? (0..<8).compactMap { buildStagingCells[$0][r] }.first : nil }
    private func buildColumnHasSelection(_ c: Int) -> Bool { let s = buildStagingSel[c]; return s >= 0 && s < 8 }   // an empty rung counts as a selection (Paul 2026-08-15)
    private func buildSetRow(_ r: Int, to cid: String?) {         // fill (or clear) a whole row with one colour
        for c in 0..<8 { buildStagingCells[c][r] = cid; buildPlacedOrig.removeValue(forKey: c * 8 + r) }
        if r < buildRowChain.count { buildRowChain[r] = [] }      // the row carries the colour's OWN machine (no per-row variation override)
        if r < buildRowShade.count { buildRowShade[r] = 0 }
        buildDeletedRows[r] = nil
    }

    // Press a staging ROW button → SET that row to the SELECTED colour + its machine. ONE COLOUR PER ROW (Paul 2026-08-15):
    //  • overwrites the row, remembering what it displaced (rowUnder) so it can come back;
    //  • if the colour already occupies ANOTHER row, that row REVERTS to what it held before this colour arrived — it does
    //    NOT blank (e.g. row A red → stamp green on A → A green; stamp green on B → A reverts to red).
    //  • a column with NO current selection then selects the placed cell (so a fresh stamp plays; it never steals an
    //    existing pick — the existing population survives).
    private func buildStampRow(_ row: Int) {
        buildRecordUndo()   // BUILD UNDO: place/relocate a colour on a row
        guard let cid = ddSelectedColourID, row >= 0, row < 8 else { return }
        if buildRowColour(row) == cid { return }                 // already this colour → nothing to do
        for r in 0..<8 where r != row && buildRowColour(r) == cid {   // the colour's PRIOR row → REVERT it to what it displaced
            let under = r < buildRowUnder.count ? buildRowUnder[r] : nil
            buildSetRow(r, to: under)
            if r < buildRowUnder.count { buildRowUnder[r] = nil }
        }
        if row < buildRowUnder.count { buildRowUnder[row] = buildRowColour(row) }   // remember what THIS row displaces
        buildSetRow(row, to: cid)
        for c in 0..<8 { buildStagingSel[c] = row }              // the WHOLE new row becomes selected immediately (Paul 2026-08-16)
        buildStagingSyncIfPlaying()
    }

    // SELECT mode: make this row the selected rung in EVERY column — the whole-row equivalent of tapping a cell.
    private func buildSelectRow(_ row: Int) {
        guard row >= 0, row < 8 else { return }
        for c in 0..<8 { buildStagingSel[c] = row }
        buildStagingSyncIfPlaying()
    }

    // MUTATE mode (Paul 2026-08-16): create (empty) / replace (populated) row R with a VALUE-tweaked variant of the
    // SELECTED palette colour — same processor structure, up to 3 nudged values (biased to one), GUARANTEED to sound
    // different from the source and NOT silent (Dice signature), tinted a lighter/darker tone of the source by complexity.
    private func buildMutateRow(_ row: Int) {
        guard let cid = ddSelectedColourID, row >= 0, row < 8 else { return }
        let base = buildColourChain(cid)
        let srcC = buildComplexity(base)                        // note-frequency + concurrency (for the lighter/darker tint)
        let srcFP = Dice.fingerprint(base)
        var avoid = [srcFP]                                     // PREFER: don't reproduce the SOURCE (velocity+gate aware) …
        for r in 0..<8 where r != row {                         // … or ANY other row already on the grid (else repeats)
            if let rid = buildRowColour(r) { avoid.append(Dice.fingerprint(buildColourChain(rid))) }
        }
        var rng = SystemRandomNumberGenerator()
        // Relaxed fallback: only unlike the SOURCE + what's on THIS row now. Once the grid fills with variants the
        // strict search exhausts the source's small param space and returns nil — MUTATE would silently stop. Falling
        // back keeps it responsive (an occasional chain-repeat under a distinct colour beats a dead button). (2026-08-17)
        var relaxed = [srcFP]
        if let rid = buildRowColour(row) { relaxed.append(Dice.fingerprint(buildColourChain(rid))) }
        guard let mutated = BuildSceneLogic.mutateChain(base, avoid: avoid, &rng)
                ?? BuildSceneLogic.mutateChain(base, avoid: relaxed, &rng) else { return }   // no audible variant at all
        buildRecordUndo()   // BUILD UNDO: recorded after the bail guards so a failed mutate never pushes a no-op step (U5 fix 2026-08-27)
        let newC = buildComplexity(mutated)
        let hue = buildSimilarHue(of: cid, lighter: newC < srcC, srcC: srcC, newC: newC)
        let newID = buildNewColour(hex: hue, machine: mutated)   // a NEW colour (never already placed) → no relocation
        if row < buildRowUnder.count { buildRowUnder[row] = buildRowColour(row) }   // remember what this row displaces
        buildSetRow(row, to: newID)
        for c in 0..<8 { buildStagingSel[c] = row }              // select the whole new row (like PLACE)
        buildPulseColourID = newID; buildPulseChain = mutated    // a new colour PULSES in the palette as a "create me" candidate (Paul 2026-08-16)
        buildStagingSyncIfPlaying()
    }


    // THE VERB BOX (a different box below staging): the workbench verbs, then the workshop's outcomes.
    @ViewBuilder private func buildStagingVerbBox(gridW: CGFloat) -> some View {
        VStack(spacing: 6) {
            HStack(spacing: 6) { buildRowModeBtn(.select); buildRowModeBtn(.mutate); buildBlankSlot() }   // SELECT ⟷ MUTATE radio (PLACE moved to the left column); FLATTEN retired — both valves are always on the play grid now (Paul 2026-08-18)
            HStack(spacing: 6) { buildBlankSlot(); buildBlankSlot(); buildBlankSlot() }   // reserved — left blank for now (Paul 2026-08-16)
        }
        .padding(8)
        .frame(width: gridW)                                       // match the verb box to the grid above it
        .background(RoundedRectangle(cornerRadius: 12).fill(buildPanel))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(buildEdge, lineWidth: 1))   // the outline that matches the left/right button boxes
    }

    // A part boundary. It occupies exactly ONE inter-cell gap so the grid stays uniformly spaced; the LINE is drawn
    // only where asked (the row buttons), centred in that gap so nothing shifts and both columns stay row-aligned.
    @ViewBuilder private func partDivider(line: Bool) -> some View {
        Color.clear.frame(maxWidth: .infinity).frame(height: BuildGeom.cellGap)
            .overlay { if line { Rectangle().fill(Color.white.opacity(0.6)).frame(height: 2) } }
    }

    // the top-row REPLAY (column) keys — SAME STYLE as the row buttons (a filled rounded cell), FULL cell size; a ▾
    // chevron per column, a ↻ repeat glyph when the column is in the loop/replay set. Shared by staging + play.
    // PER-ROW LAP (Paul 2026-08-19): each grid owns its OWN column loop — the STAGING keys drive `buildStagingLane`,
    // the PLAY keys drive `buildPerformLane`; both are baked into the composed scene per-row (composeScene), so looping
    // one grid never loops the other. `staging` picks which mask this key row edits + shows.
    @ViewBuilder private func buildLoopKeys(cell: CGFloat, staging: Bool) -> some View {
        let mask = staging ? buildStagingLane : buildPerformLane
        HStack(spacing: BuildGeom.cellGap) {
            ForEach(0..<8, id: \.self) { c in
                let held = (mask & (1 << UInt8(c))) != 0            // this grid's OWN lap set — tap/hold a key to add/remove its column
                let inLoop = !staging || c < (buildPartLen ?? Snap.cols)   // staging: a column past the part's LENGTH is outside the loop (dimmed); perform grid mixes lengths, so never dim its keys
                RoundedRectangle(cornerRadius: 7).fill(Color.white.opacity(held ? 0.22 : 0.11))   // §0 MUTED: neutral keys, held reads as a slight brightening
                    .frame(width: cell, height: cell)
                    .overlay(RoundedRectangle(cornerRadius: 7).stroke(held ? sceneAmberHue : buildEdge, lineWidth: held ? 2 : 1))
                    .overlay(Image(systemName: "repeat")           // ALWAYS the loop glyph (never a chevron); held shows via the fill
                        .font(.system(size: 12, weight: .heavy)).foregroundColor(.white.opacity(held ? 0.85 : 0.55)))
                    .opacity(inLoop ? 1 : 0.3)                      // PER-PART LENGTH: keys past the loop are dimmed
                    .contentShape(Rectangle())                     // LOOP: tap or long-press toggles the column in THIS grid's lap set (Paul 2026-08-19)
                    .onTapGesture { buildToggleLoop(staging: staging, c) }
                    .onLongPressGesture(minimumDuration: 0.3) { buildToggleLoop(staging: staging, c) }
            }
        }
    }
    private func buildToggleLoop(staging: Bool, _ c: Int) {
        let bit = UInt8(1) << UInt8(c)
        if staging { buildStagingLane ^= bit } else { buildPerformLane ^= bit }
        buildPublishScene()                                        // the per-row lap is baked into the composed scene
    }

    // ROW BUTTONS — a cell-sized selector per grid row on the LEFT edge; shared by both grids. `bands` is the row
    // grouping (staging = [8]; play = [3,2,1,1,1]) so the buttons carry the SAME part dividers as the grid → they align
    // row-for-row. A top spacer clears the loop-key row.
    @ViewBuilder private func buildRowButtons(cell: CGFloat, hue: Color, bands: [Int], onRow: ((Int) -> Void)? = nil) -> some View {
        VStack(spacing: BuildGeom.cellGap) {
            Color.clear.frame(width: cell, height: cell)   // align past the loop-key row (now full cell height)
            VStack(spacing: 0) {
                ForEach(Array(bands.enumerated()), id: \.offset) { idx, rows in
                    if idx > 0 { partDivider(line: true) }         // the DIVIDING LINE lives here, between the row buttons
                    let base = bands.prefix(idx).reduce(0, +)      // absolute grid-row offset for this band
                    VStack(spacing: BuildGeom.cellGap) {
                        ForEach(0..<rows, id: \.self) { r in
                            let gridRow = base + r
                            let rowCid = buildRowColour(gridRow)
                            let isSel = rowCid != nil && rowCid == ddSelectedColourID   // this row holds the SELECTED colour
                            RoundedRectangle(cornerRadius: 7).fill(buildRowButtonFill)   // muted rail; inverts to light when a DARK colour's icon needs contrast
                                .frame(width: cell, height: cell)
                                .overlay(RoundedRectangle(cornerRadius: 7).stroke(isSel ? (rowCid.flatMap { colourColor($0) } ?? buildEdge) : buildEdge, lineWidth: isSel ? 2 : 1))
                                .overlay(Text("\(gridRow + 1)").font(.system(size: 13, weight: .heavy, design: .monospaced))
                                    .foregroundColor(isSel ? (rowCid.flatMap { colourColor($0) } ?? .white) : .white.opacity(0.7)))   // ROW NUMBER 1–8 — SHOWS THE SELECTED COLOUR when this row holds it (replaces the per-cell target)
                                .contentShape(Rectangle())
                                .onTapGesture { onRow?(gridRow) }  // press → run the current row mode on that grid row
                        }
                    }
                }
            }
        }
    }

    // PART BUTTONS — the PERFORM grid's left selector: ONE button PER PART, MERGED across its rows (part 1 = rows 1–3,
    // part 2 = rows 4–5, then 6, 7, 8), styled identically to the staging row buttons but labelled with the part NUMBER
    // instead of a chevron. Same rhythm as the grid (top spacer + cellGap spacing) so it aligns row-for-row.
    @ViewBuilder private func buildPartButtons(cell: CGFloat, hue: Color, bands: [Int]) -> some View {
        VStack(spacing: BuildGeom.cellGap) {
            Color.clear.frame(width: cell, height: cell)   // align past the loop-key row (now full cell height)
            ForEach(Array(bands.enumerated()), id: \.offset) { idx, rows in
                let h = cell * CGFloat(rows) + BuildGeom.cellGap * CGFloat(rows - 1)   // merge across the part's rows
                let base = bands.prefix(idx).reduce(0, +)          // this band's first grid row
                let mine = (0..<rows).contains { base + $0 < 8 && buildPerformPart[base + $0] == buildCurrentPart }   // §2: does the CURRENT part live in this band?
                let set = (0..<rows).contains { base + $0 < 8 && buildPerformPart[base + $0] >= 0 }   // VALVE: this band HOLDS a part (SET)
                RoundedRectangle(cornerRadius: 7).fill(buildHues[idx % buildHues.count].opacity(set ? 0.7 : 0.4))   // §4 band hue; SET reads more solid
                    .frame(width: cell, height: h)
                    .overlay(Text(set ? "\(idx + 1)" : "+").font(.system(size: 14, weight: .heavy, design: .monospaced)).foregroundColor(.white.opacity(set ? (mine ? 0.95 : 0.6) : 0.4)))   // SET shows the number; EMPTY shows a + (deploy-here)
                    .overlay(alignment: .leading) { if mine { Rectangle().fill(buildPartInk).frame(width: 3) } }   // §2: the deployed band's bright-ink RAIL BRACKET (others sit dim)
                    .contentShape(Rectangle())
                    .onTapGesture { buildExitPlaceMode(); buildBandValve(base: base, rows: rows) }   // play-grid button → not a part-grid row, so it leaves PLACE mode; THE VALVE: empty → flatten+stash+clear · set → restore
            }
        }
    }

    // RIGHT-side per-row buttons on the PERFORM grid — one per row for parts 1 & 2 ONLY (rows 1–3 = "1", rows 4–5 = "2");
    // rows 6–8 (parts 3–5) get no button here since they're already on the left. Identical appearance to the part buttons.
    @ViewBuilder private func buildRightPartButtons(cell: CGFloat, hue: Color) -> some View {
        VStack(spacing: BuildGeom.cellGap) {
            Color.clear.frame(width: cell, height: cell)   // align past the loop-key row (now full cell height)
            ForEach(0..<5, id: \.self) { r in                            // rows 1–5 only
                let bandIndex = r < 3 ? 0 : 1                             // rows 0–2 = band 1 · rows 3–4 = band 2
                let base = bandIndex == 0 ? 0 : 3
                let whole = buildRowInWholeBand(r)                        // this band is a WHOLE-band part → the rung valve is inert (restore via LEFT)
                let set = buildPerformPart[r] >= 0 && !whole             // this rung holds its own sub-part
                let mine = buildPerformPart[r] == buildCurrentPart
                let letter = ["a", "b", "c"][min(r - base, 2)]           // the rung letter (a/b/c)
                RoundedRectangle(cornerRadius: 7).fill(buildHues[bandIndex % buildHues.count].opacity(whole ? 0.15 : (set ? 0.7 : 0.4)))
                    .frame(width: cell, height: cell)
                    .overlay(Text(whole ? "" : (set ? letter : "+")).font(.system(size: 13, weight: .heavy, design: .monospaced)).foregroundColor(.white.opacity(whole ? 0.2 : (set ? (mine ? 0.95 : 0.6) : 0.4))))   // SET → the rung letter · EMPTY → + · WHOLE band → inert
                    .overlay(alignment: .trailing) { if set && mine { Rectangle().fill(buildPartInk).frame(width: 3) } }   // §2: current part's rung gets the bright-ink bracket
                    .contentShape(Rectangle())
                    .onTapGesture { buildExitPlaceMode(); buildRowValve(row: r) }   // play-grid button → leaves PLACE mode; then the per-rung valve
            }
        }
    }

    // ── RIGHT COLUMN: the PLAY grid — five fixed bands + glyph rail; the target decides the verb ───────────────────
    @ViewBuilder private func buildPlayColumn(cell: CGFloat) -> some View {
        VStack(alignment: .center, spacing: 8) {
            AnyView(buildColumnButton("START/STOP THE PLAY GRID", active: buildPerformPlaying, fill: .grid, enabled: buildPerformPopulated, action: { buildTogglePerformVoice() })).padding(.bottom, 6)   // disabled until the play grid has REAL cells (preview doesn't count)
            // PLAY/EDIT radio dropped (Paul 2026-08-17); the eye moved to the grid's corner
            // LEFT: merged PART BUTTONS 1–4 (part 5/row 8 removed). RIGHT: per-row buttons for parts 1 & 2 only (1,1,1,2,2)
            // — parts 3–5 aren't repeated on the right since they're already on the left. Assign STAGING → PERFORM (wires later).
            AnyView(HStack(alignment: .top, spacing: BuildGeom.cellGap) {   // same spacing as staging → attached the same way
                AnyView(buildPartButtons(cell: cell, hue: buildCyan, bands: [3, 2, 1, 1]))   // LEFT 1: the MULTI-ROW valve
                AnyView(buildRightPartButtons(cell: cell, hue: buildCyan))                    // LEFT 2: the SINGLE-ROW valve — both valves now on the left (FLATTEN retired, Paul 2026-08-18)
                VStack(spacing: BuildGeom.cellGap) {
                    buildLoopKeys(cell: cell, staging: false)    // the PLAY grid's OWN column loop
                    AnyView(buildPlayBands(cell: cell))          // AnyView — keeps the deep bands type out of this body
                }
                AnyView(buildPerformRowButtons(cell: cell))       // RIGHT: the row-master chevrons (replaces the FLATTEN-gated right valve)
            }.overlay(alignment: .topLeading) { buildGridCornerEye(cell: cell, popup: 1) }).padding(.bottom, 12)   // the eye in the play grid's top-left corner cell (ROW 8 now lives IN the grid's bottom row)
            AnyView(buildRackButtons())                          // four RACK placeholders below the play grid (Paul 2026-08-18)
            // the emitters box moved into the combined I/O box spanning both grid columns (buildIOBox, Paul 2026-08-18)
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .center)
    }
    // THE COMBINED I/O BOX — spans the bottom of BOTH grid columns (middle + right): the four MIDI-IN receiver controls
    // (A–D) and the four MIDI-OUT emitter controls (A–D) in one panel, split by a divider. (Paul 2026-08-18)
    @ViewBuilder private func buildIOBox() -> some View {
        HStack(alignment: .top, spacing: 6) {                                  // receivers then emitters, each headed by a top-right label (Paul 2026-08-18)
            VStack(alignment: .leading, spacing: 3) {
                Text("MIDI IN").font(.system(size: 9, weight: .heavy, design: .monospaced)).tracking(0.6).foregroundColor(buildDim)
                HStack(alignment: .top, spacing: 6) { ForEach(0..<4, id: \.self) { i in buildReceiverControl(i) } }
            }
            VStack(alignment: .leading, spacing: 3) {
                Text("MIDI OUT").font(.system(size: 9, weight: .heavy, design: .monospaced)).tracking(0.6).foregroundColor(buildDim)
                HStack(alignment: .top, spacing: 6) { ForEach(0..<4, id: \.self) { i in buildEmitterControl(i) } }
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity)
        .background(RoundedRectangle(cornerRadius: 12).fill(buildPanel))   // outline removed (Paul 2026-08-18)
    }

    // EMITTERS — the four output strips (A–D), in the style of the GRID page's emitter section (placeholder). Sits
    // directly below the perform grid; since both grids are the same height and both columns share the button + spacing
    // rhythm, this aligns with the staging verb box.
    @ViewBuilder private func buildEmitters(cell: CGFloat) -> some View {
        let w = cell * 10 + BuildGeom.cellGap * 9                 // the perform grid's width → the strips sit under it
        HStack(spacing: 6) {
            ForEach(Array(["A", "B", "C", "D"].enumerated()), id: \.offset) { i, e in
                VStack(spacing: 4) {
                    Text(e).font(.system(size: 13, weight: .heavy, design: .monospaced)).foregroundColor(.white.opacity(0.55))   // §0 MUTED: neutral identifier (was standing cyan)
                    RoundedRectangle(cornerRadius: 4).fill(buildCell)   // the velocity fader STRETCHES down to the M/S row
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .overlay(RoundedRectangle(cornerRadius: 4).fill(Color.white.opacity(0.22)).frame(height: 26), alignment: .bottom)   // §0 MUTED: the level bar reads as a neutral value, not a cyan slab
                    Text("CH \(i + 1)").font(.system(size: 8, weight: .heavy, design: .monospaced)).foregroundColor(buildDim)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity).padding(.vertical, 6)
                .background(RoundedRectangle(cornerRadius: 8).fill(buildPanel))
            }
        }
        .frame(width: w).frame(maxHeight: .infinity)              // the emitters fill the space down to the M/S buttons
    }

    // per-emitter MUTE / SOLO — a row of four A–D groups, each with an M and an S button. Spans the emitter width so
    // it sits under the strips; placed at the bottom of the perform column to line up with STAGE THE GRID.
    @ViewBuilder private func buildEmitterMuteSolo(cell: CGFloat) -> some View {
        let w = cell * 10 + BuildGeom.cellGap * 9
        HStack(spacing: 6) {
            ForEach(Array(["A", "B", "C", "D"].enumerated()), id: \.offset) { _, _ in
                HStack(spacing: 4) {
                    buildMSBtn("M", tint: buildHues[3])          // mute (red)
                    buildMSBtn("S", tint: buildHues[0])          // solo (amber)
                }
                .frame(maxWidth: .infinity)
            }
        }
        .frame(width: w)
    }

    @ViewBuilder private func buildMSBtn(_ label: String, tint: Color) -> some View {
        Text(label).font(.system(size: 12, weight: .heavy, design: .monospaced)).foregroundColor(tint)
            .frame(maxWidth: .infinity).frame(height: 34)
            .background(RoundedRectangle(cornerRadius: 7).fill(buildCell))
            .overlay(RoundedRectangle(cornerRadius: 7).stroke(tint.opacity(0.5), lineWidth: 1.5))
    }

    // THE DIMMED PREVIEW (Paul 2026-08-14): while the CURRENT part is UNASSIGNED, show its staging SELECTION on every
    // UNASSIGNED play-grid band. The shape follows the count of DISTINCT selected rows K:
    //   • a SINGLE-rung band always shows the FLATTEN (each column's selected cell — the same algorithm as deployment);
    //   • a multi-rung band with K == 1 shows the flatten on its TOP rung;
    //   • a multi-rung band whose rung count == K shows the K selected rows on its K rungs;
    //   • otherwise (K > 1 and ≠ the band's rungs) the selection doesn't fit that band → no preview.
    // Returns [col][row] colourIDs (nil = nothing to preview there).
    private func buildPreviewCells() -> [[String?]] {
        var out = Array(repeating: Array(repeating: String?.none, count: 8), count: 8)
        // Only while the PARTS (staging) grid is playing — NOT during a MIDI-chain audition. (Paul 2026-08-14)
        guard buildStagingPlaying, buildCurrentPart >= 0, buildCurrentPart < buildParts.count, !buildParts[buildCurrentPart].deployed else { return out }
        let selRows = Set((0..<8).compactMap { buildStagingSel[$0] >= 0 ? buildStagingSel[$0] : nil }).sorted()
        let K = selRows.count
        guard K > 0 else { return out }
        func flatten(intoRow R: Int) {                             // deployment's flatten: each column's selected cell, wherever its row
            for c in 0..<8 {
                let sr = buildStagingSel[c]
                if sr >= 0, sr < 8, let cid = buildStagingCells[c][sr] { out[c][R] = cid }
            }
        }
        let bands = [3, 2, 1, 1, 1]
        for (bi, N) in bands.enumerated() {
            let base = bands.prefix(bi).reduce(0, +)
            if (0..<N).contains(where: { base + $0 < 8 && buildPerformPart[base + $0] >= 0 }) { continue }   // band already holds a deployed part
            if N == 1 || K == 1 {
                flatten(intoRow: base)                             // single lane, or one selected row → flatten onto the (top) rung
            } else if K == N {
                for (i, sr) in selRows.enumerated() {              // K selected rows → the band's K rungs, top-down
                    for c in 0..<8 where buildStagingSel[c] == sr {
                        if let cid = buildStagingCells[c][sr] { out[c][base + i] = cid }
                    }
                }
            }
        }
        return out
    }

    // the PLAY grid rows — THE PIECE: real deployed cells. §4 BAND WASHES (design ferry): each band carries its own hue
    // family as a low-alpha WASH BEHIND its cells (empty cells go clear so the wash reads); the cells keep their TRUE
    // colour on top — rails differentiate, machines stay recognisable across grids. Alpha is a starting point.
    @ViewBuilder private func buildPlayBands(cell: CGFloat) -> some View {
        let bands = [3, 2, 1, 1, 1]                                // the play grid's band form (8 rows)
        let preview = buildPreviewCells()                          // the dimmed preview of the current unassigned part
        VStack(spacing: BuildGeom.cellGap) {
            ForEach(Array(bands.enumerated()), id: \.offset) { bi, rows in
                let base = bands.prefix(bi).reduce(0, +)
                VStack(spacing: BuildGeom.cellGap) {
                    ForEach(0..<rows, id: \.self) { ri in
                        let r = base + ri
                        HStack(spacing: BuildGeom.cellGap) {
                            ForEach(0..<8, id: \.self) { c in
                                if r == 7 { buildRow8GridCell(c, cell: cell)   // ROW 8 = the play grid's BOTTOM row, as populated cells (Paul 2026-08-24)
                                } else {
                                let id = buildPerformCells[c][r]
                                let ghost = id == nil ? preview[c][r] : nil   // preview only where no cell is deployed
                                let muted = buildPerformMute.contains(c * 8 + r)
                                let multiRung = buildPerformPart[r] >= 0 && buildPerformPartRows(buildPerformPart[r]) > 1
                                let mutable = id != nil && buildPerformPart[r] >= 0 && !multiRung   // SINGLE-RUNG part → per-cell mute
                                let activeRung = buildPerformActiveRung(c, r)                        // MULTI-rung: the selected rung of this column
                                let plen = (buildPerformPart[r] >= 0 && buildPerformPart[r] < buildParts.count) ? (buildParts[buildPerformPart[r]].length ?? Snap.cols) : Snap.cols
                                let inLoop = c < plen                                                 // PER-PART LENGTH: this row's part loops over `plen` columns — the rest are outside
                                RoundedRectangle(cornerRadius: 7)
                                    .fill(id.flatMap { colourColor($0) } ?? Color.black.opacity(0.35))   // TRUE colour · else the empty recess (preview shows as an outline, not a fill)
                                    .frame(width: cell, height: cell)
                                    .overlay(RoundedRectangle(cornerRadius: 7).stroke(Color.white.opacity(0.09), lineWidth: 1))   // outline every cell → the grid READS even when empty
                                    .overlay { if let g = ghost, let gc = colourColor(g) {   // THE PREVIEW = a THICK, DIMMED OUTLINE in the colour (not a fill)
                                        RoundedRectangle(cornerRadius: 7).strokeBorder(gc.opacity(0.45), lineWidth: 3) } }
                                    .overlay { if id != nil && multiRung && activeRung { RoundedRectangle(cornerRadius: 7).stroke(Color.white, lineWidth: 2.5) } }   // WHITE = the selected rung (like the part grid)
                                    .overlay { ZStack {                                            // TARGET + NOTE SWEEP (folded into one overlay to keep the cell type-checkable)
                                        if id != nil && id == ddSelectedColourID { buildTargetMark(cell * 0.55) }   // THE TARGET rides every play-grid cell matching the selected machine
                                        buildNoteSweep(idx: c * 8 + r, active: buildPerformPlaying && inLoop, id: id)   // THE NOTE SWEEP (v1) — only when the PLAY grid plays
                                    } }
                                    .opacity((!inLoop || muted || (id != nil && multiRung && !activeRung)) ? 0.3 : 1)   // OUTSIDE the loop · MUTED · non-selected rung → dim
                                    .contentShape(Rectangle())
                                    .onTapGesture {
                                        if mutable { buildTogglePerformMute(c, r) }               // single-rung → mute
                                        else if id != nil && multiRung { buildTogglePerformRung(c, r) }   // multi-rung → pick the active rung
                                    }
                                }
                            }
                        }
                    }
                }
                .background(RoundedRectangle(cornerRadius: 8).fill(buildHues[bi % buildHues.count].opacity(0.16)))   // §4 the band's hue WASH, behind the cells
            }
        }
        .overlay(alignment: .topLeading) { buildPerformPlayheads(cell: cell) }   // PER-PART: one playhead per row at its part's tempo
    }

    // THE PLAYHEAD — a 2pt vertical line sweeping L→R across the 8 grid columns, phase-locked to the transport beat and
    // looping with the engine's 8-column cycle. Attached to the CELLS block only (topLeading), so it never crosses the
    // loop-key row above or the row buttons to the side. Extrapolates the polled beat between frames (like the palette
    // playhead) and warps by SWING so it tracks the real (swung) column windows. (user 2026-08-12)
    @ViewBuilder private func buildPlayhead(cell: CGFloat, active: Bool, stepB: Double? = nil, lenC: Int? = nil) -> some View {
        if d.playing && active {                                  // only when THIS grid is the playing voice (Paul 2026-08-14)
            let sb = stepB ?? stepBeats                                // PER-PART CLOCK: the part's own rate (nil ⇒ scene default)
            let cols = lenC ?? Snap.cols
            let width = cell * 8 + BuildGeom.cellGap * 7               // the cells span: 8 cells + the 7 gaps between them
            TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: animationsPaused)) { tl in
                let live = meters.beatAnchor + tl.date.timeIntervalSince(meters.beatAnchorAt) * meters.tempo / 60.0   // extrapolate the polled beat
                let musical = musicalOf(live, stepBeats: sb, a: max(1.0, Double(swing) / 50.0))       // column progress in MUSICAL (swung) time
                let colF = sb > 0 ? musical / sb : 0                  // continuous column index since transport start
                let wrapped = colF.truncatingRemainder(dividingBy: Double(cols))
                let p = wrapped < 0 ? wrapped + Double(cols) : wrapped   // 0…len across the loop, looping with the engine
                let x = min(width, CGFloat(p) * (cell + BuildGeom.cellGap))
                Rectangle().fill(Color.white.opacity(0.85))
                    .frame(width: 2, height: width == 0 ? 0 : cell * 8 + BuildGeom.cellGap * 7)
                    .offset(x: x)
                    .allowsHitTesting(false)
            }
        }
    }

    // PER-PART PLAYHEADS (Paul 2026-08-19): the PLAY grid draws ONE playhead PER ROW, each sweeping at its owning part's
    // OWN rate + loop length — so rows deployed at different tempos drift out of phase visibly (a row belonging to no part
    // draws nothing). Rows share the uniform pitch (cell + gap), so each head spans one row's height at its row offset.
    @ViewBuilder private func buildPerformPlayheads(cell: CGFloat) -> some View {
        if d.playing && buildPerformPlaying {
            let width = cell * 8 + BuildGeom.cellGap * 7
            let pitch = cell + BuildGeom.cellGap
            TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: animationsPaused)) { tl in
                let live = meters.beatAnchor + tl.date.timeIntervalSince(meters.beatAnchorAt) * meters.tempo / 60.0
                ZStack(alignment: .topLeading) {
                    ForEach(0..<8, id: \.self) { r in
                        let part = buildPerformPart[r]
                        if part >= 0 {
                            let sb = (part < buildParts.count ? buildParts[part].rate?.beats : nil) ?? stepBeats
                            let cols = (part < buildParts.count ? buildParts[part].length : nil) ?? Snap.cols
                            let musical = musicalOf(live, stepBeats: sb, a: max(1.0, Double(swing) / 50.0))
                            let colF = sb > 0 ? musical / sb : 0
                            let wrapped = colF.truncatingRemainder(dividingBy: Double(cols))
                            let p = wrapped < 0 ? wrapped + Double(cols) : wrapped
                            let x = min(width, CGFloat(p) * pitch)
                            Rectangle().fill(Color.white.opacity(0.85))
                                .frame(width: 2, height: cell)
                                .offset(x: x, y: CGFloat(r) * pitch)
                                .allowsHitTesting(false)
                        }
                    }
                }
            }
        }
    }

    // THE NOTE SWEEP (v1 — spec `AcceptanceCriteria-note-sweep.md`, ratified 2026-08-16). A line sweeps across the
    // cell for as long as the note SOUNDS (note-off mid-travel = the line freezes where it got to → the note's length
    // reads visually). VELOCITY is the stroke (weight + opacity). AXIS = ROTATION: each new strike moment takes the
    // next edge (L→R · T→B · R→L · B→T) via cellStrikeSeq. Reuses the existing per-cell feeds (no new plumbing).
    // Deferred: velocity-fed density governor · CONTOUR axis (needs a per-note pitch feed) · face-dimming. (2026-08-17)
    // A hex lightened toward white by `t` (0…1) — the hue's BRIGHT tone.
    private func buildLighten(_ hex: UInt32, _ t: Double) -> UInt32 {
        func ch(_ s: Int) -> UInt32 { let c = Double((hex >> s) & 0xFF); return UInt32(max(0, min(255, c + (255 - c) * t))) }
        return (ch(16) << 16) | (ch(8) << 8) | ch(0)
    }
    // THE PIANO-ROLL FACE on the BUILD grid cells (Paul 2026-08-19): soft note marks enter at the RIGHT as the cell sounds
    // and drift LEFT at REAL pitch lanes (the per-cell note feed), tinted the cell's own bright tone. ONLY on a populated
    // cell of the grid that is the PLAYING voice. Accumulated in the VC poll (buildCellRoll); paused when the cell rests.
    @ViewBuilder private func buildNoteSweep(idx: Int, active: Bool, id: String?) -> some View {
      if active, let cid = id {
        let hue = Color(hex: buildLighten(buildBaseHex(cid), 0.72))
        let notes = idx < buildCellRoll.count ? buildCellRoll[idx] : []
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

    // ── MACHINERY STRIP (bottom, full width): the chain — ID · IN box · slots + ghost · OUT box ────────────────────
    @ViewBuilder private func buildMachinery() -> some View {
        let chain = selectedColourChain()                         // the SELECTED colour's real processors (empty for a new colour)
        HStack(alignment: .center, spacing: 10) {                  // THE CHAIN — RANDOMIZE · EXAMPLE cell · IN box · slots (all in a row, none overlapping)
            buildFooterBtn("🎲 RANDOMIZE", pink: true) { buildRandomizeSimple() }   // LEFT: the SIMPLER roll — now IN the row (was an overlay covering the example cell)
            RoundedRectangle(cornerRadius: 9).fill(buildSelHue).frame(width: 40, height: 40)   // the EXAMPLE cell = the selected machine, to the LEFT of the processor boxes
                .overlay { if ddSelectedColourID != nil { buildTargetMark(24) } }              // …wearing the same TARGET as the cast swatch
            buildBox("R1: MIDI IN", "OMNI")
            Text("┈┈▶").foregroundColor(buildDim).font(.system(size: 10, design: .monospaced))
            ForEach(0..<8, id: \.self) { i in                     // UP TO 8 processor slots (the chain's capacity)
                if i < chain.count && !buildIsEmptySlot(chain[i]) {
                    buildSlot(buildProcLabel(chain[i]), colour: buildSelHue, bypassed: chain[i].bypassed)   // a real processor — the selected colour + its mode
                        .onTapGesture { buildEditSlot = i }       // touch → open the processor pop-up editor
                } else {
                    buildSlot("+", dashed: true)                  // EVERY empty box is a "+" — tap to add a processor AT THIS position
                        .onTapGesture { buildAddSlot = i }
                }
                if i < 7 { Text("┈").foregroundColor(buildDim) }
            }
        }
        .frame(maxWidth: .infinity, minHeight: 46, alignment: .leading)
        .padding(.horizontal, 14).padding(.vertical, 9)          // symmetric padding → the boxes centre in the footer
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 12).fill(buildPanel))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(buildSelHue.opacity(0.45), lineWidth: 1.5))   // §1 THE THREAD: the chain frame wears the machine's hue (reads with the left column)
        .overlay(alignment: .bottomTrailing) {                   // EYE (bottom-right) → the signal-flow diagram pop-up
            Image(systemName: "eye").font(.system(size: 21, weight: .semibold)).foregroundColor(buildDim)   // §0 muted chrome: a whisper, not an accent (bigger — Paul 2026-08-19)
                .padding(10).contentShape(Rectangle()).onTapGesture { buildFlowOpen = true }
        }
    }

    // A 3×2 button box that sits beneath a column. All three (processor · staging · play) are built by this one
    // function → identical styling + button size; only the column width differs. `labels` fills row-major; an empty
    // string renders a blank placeholder button. RANDOMIZE is wired live; everything else is a stub for now.
    @ViewBuilder private func buildFooterBox(labels: [String]) -> some View {
        VStack(spacing: BuildGeom.cellGap) {
            ForEach(0..<2, id: \.self) { r in
                HStack(spacing: BuildGeom.cellGap) {
                    ForEach(0..<3, id: \.self) { c in
                        let idx = r * 3 + c
                        let label = idx < labels.count ? labels[idx] : ""
                        buildFooterBoxBtn(label)
                    }
                }
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity)
        .background(RoundedRectangle(cornerRadius: 12).fill(buildPanel))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(buildEdge, lineWidth: 1))
    }

    @ViewBuilder private func buildFooterBoxBtn(_ label: String) -> some View {
        let empty = label.isEmpty
        let live = label.contains("RANDOMIZE")   // RANDOMIZE runs the simple roll — but is styled plain, like MUTATE/LIBRARY (Paul 2026-08-18)
        Text(label)
            .font(.system(size: 10, weight: .heavy, design: .monospaced)).tracking(0.5)
            .foregroundColor(.white)
            .lineLimit(1).minimumScaleFactor(0.5).padding(.horizontal, 4)
            .frame(maxWidth: .infinity, minHeight: 34, maxHeight: 34)   // FIXED height (min==max) — a flexible box competes with the column's Spacer and stretches to the screen bottom
            .background(RoundedRectangle(cornerRadius: 8).fill(buildCell))
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(buildEdge, lineWidth: 1).opacity(empty ? 0.5 : 1))
            .contentShape(Rectangle())
            .onTapGesture { buildExitPlaceMode(); if live { buildRandomizeSimple() } }   // any control button leaves PLACE mode
    }

    // PLACE is armed by the PLACE button / the verb-box radio; clicking any button that ISN'T a grid row selector
    // turns it back off (→ SELECT). Wired into the control buttons (transports + footer buttons).
    private func buildExitPlaceMode() { if buildPlaceArmed { buildPlaceArmed = false } }

    // The LEFT column's control box. Row 1: RANDOMIZE · MUTATE · AUTOFILL (all plain-styled). Row 2: the cell
    // LIBRARY, spanning the full width. (Paul 2026-08-18: AUTOFILL moved up from row 2; LIBRARY now full-width.)
    @ViewBuilder private func buildLeftControlBox() -> some View {
        let gap = BuildGeom.cellGap
        VStack(spacing: gap) {
            HStack(spacing: gap) {
                buildFooterBoxBtn("RANDOMIZE")
                buildFooterBoxBtn("MUTATE")
                buildFillButton()                                           // AUTOFILL — moved into the third cell (was PLACE's placeholder)
            }
            buildLibraryButton()                                            // now spans the full row width
        }
        .padding(10)
        .frame(maxWidth: .infinity)
        .background(RoundedRectangle(cornerRadius: 12).fill(buildPanel))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(buildEdge, lineWidth: 1))
    }

    // The cell LIBRARY opener, sat across the two left cells of the control box. On BUILD the browser saves/stamps
    // the SELECTED COLOUR's chain (not an EDIT grid cell).
    @ViewBuilder private func buildLibraryButton() -> some View {
        Text("LIBRARY").font(.system(size: 10, weight: .heavy, design: .monospaced)).tracking(0.5)
            .foregroundColor(.white).lineLimit(1).minimumScaleFactor(0.5).padding(.horizontal, 4)
            .frame(maxWidth: .infinity, minHeight: 34, maxHeight: 34)
            .background(RoundedRectangle(cornerRadius: 8).fill(buildCell))
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(buildEdge, lineWidth: 1))
            .contentShape(Rectangle())
            .onTapGesture { buildExitPlaceMode(); buildOpenLibrary() }
    }
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

    // FILL — styled identically to PLACE (colour chip + ">>>"), but it's an ACTION not a mode: it runs the old
    // STAGE THE GRID (fills the part grid to 8 rows). Disabled until the staging grid has content.
    @ViewBuilder private func buildFillButton() -> some View {
        let enabled = buildStagingPopulated
        let selDark = buildIsDark(buildBaseHex(buildSelID ?? ""))
        let chipGround: Color = selDark ? Color.white.opacity(0.92) : Color.black.opacity(0.78)
        HStack(spacing: 3) {
            RoundedRectangle(cornerRadius: 3).fill(chipGround).frame(width: 15, height: 15)
                .overlay(RoundedRectangle(cornerRadius: 2).fill(buildSelHue).frame(width: 9, height: 9))   // the same colour square as PLACE
            Text("AUTOFILL").font(.system(size: 9, weight: .heavy, design: .monospaced)).tracking(0.3)
                .foregroundColor(.white).lineLimit(1).minimumScaleFactor(0.4)
            Text(">>>").font(.system(size: 10, weight: .black, design: .monospaced)).foregroundColor(buildSelHue)
        }
        .padding(.horizontal, 5)
        .frame(maxWidth: .infinity, minHeight: 34, maxHeight: 34)
        .background(RoundedRectangle(cornerRadius: 8).fill(buildCell))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(buildEdge, lineWidth: 1))
        .opacity(enabled ? 1 : 0.35)
        .contentShape(Rectangle())
        .onTapGesture { if enabled { buildExitPlaceMode(); buildStageTheGrid() } }
        .allowsHitTesting(enabled)
    }

    // FLATTEN — the third verb-box button (where MUTATE used to sit): a colour chip (the same small box as PLACE/
    // FILL) + "FLATTEN >>>". A TOGGLE for the PLAY grid's mode — ON shows the valve/part buttons, OFF (default)
    // shows plain row-master chevrons. Sized to the verb-box buttons (36pt). (Paul 2026-08-17)
    @ViewBuilder private func buildFlattenButton() -> some View {
        let armed = buildFlattenMode
        let selDark = buildIsDark(buildBaseHex(buildSelID ?? ""))
        let chipGround: Color = selDark ? Color.white.opacity(0.92) : Color.black.opacity(0.78)
        HStack(spacing: 3) {
            RoundedRectangle(cornerRadius: 3).fill(chipGround).frame(width: 15, height: 15)
                .overlay(RoundedRectangle(cornerRadius: 2).fill(buildSelHue).frame(width: 9, height: 9))   // same size as the PLACE/FILL chip
            Text("FLATTEN").font(.system(size: 9, weight: .heavy, design: .monospaced)).tracking(0.3)
                .foregroundColor(armed ? .black : .white).lineLimit(1).minimumScaleFactor(0.4)
            Text(">>>").font(.system(size: 10, weight: .black, design: .monospaced)).foregroundColor(armed ? .black : buildSelHue)
        }
        .padding(.horizontal, 4)
        .frame(maxWidth: .infinity).frame(minHeight: 36, maxHeight: 36)          // match the SELECT/MUTATE buttons
        .background(RoundedRectangle(cornerRadius: 9).fill(armed ? buildCyan : buildCell))
        .overlay(RoundedRectangle(cornerRadius: 9).stroke(armed ? Color.clear : buildEdge, lineWidth: 1))
        .contentShape(Rectangle())
        .onTapGesture { buildFlattenMode.toggle() }
    }
    // NORMAL-mode play grid (FLATTEN off): a plain right-chevron button per row — a ROW MASTER. One per grid row,
    // aligned past the loop-key row like the part buttons.
    @ViewBuilder private func buildPerformRowButtons(cell: CGFloat) -> some View {
        VStack(spacing: BuildGeom.cellGap) {
            Color.clear.frame(width: cell, height: cell)   // align past the loop-key row
            ForEach(0..<8, id: \.self) { r in
                RoundedRectangle(cornerRadius: 7).fill(Color.white.opacity(0.11))
                    .frame(width: cell, height: cell)
                    .overlay(RoundedRectangle(cornerRadius: 7).stroke(buildEdge, lineWidth: 1))
                    .overlay(Image(systemName: "chevron.right").font(.system(size: 12, weight: .bold)).foregroundColor(.white.opacity(0.7)))
                    .contentShape(Rectangle())
                    .onTapGesture { buildPerformRowToggle(r) }
            }
        }
    }
    // The row master: if any populated cell in the row is muted, UNMUTE the whole row; if every populated cell is
    // already unmuted, MUTE the whole row — exactly as if each cell had been pressed. Empty cells are left alone.
    private func buildPerformRowToggle(_ r: Int) {
        let cols = (0..<8).filter { buildPerformCells[$0][r] != nil }
        guard !cols.isEmpty else { return }
        let allUnmuted = cols.allSatisfy { !buildPerformMute.contains($0 * 8 + r) }
        for c in cols { let k = c * 8 + r; if allUnmuted { buildPerformMute.insert(k) } else { buildPerformMute.remove(k) } }
        buildPublishScene()
    }

    // THE RECEIVERS BOX (left column, bottom): four identical controls (A–D), one per input door. Each = a live
    // incoming-velocity meter (left) + a control stack (right): Mute/Solo on one line, then LATCH, then an ENABLE
    // button showing the door's MIDI channel — LATCH and ENABLE are the prominent pair. (Paul 2026-08-17)
    @ViewBuilder private func buildReceiversBox() -> some View {
        HStack(spacing: 6) {                                       // the four doors A–D sit side by side
            ForEach(0..<4, id: \.self) { i in buildReceiverControl(i) }
        }
        .padding(10)
        .frame(maxWidth: .infinity)
        .background(RoundedRectangle(cornerRadius: 12).fill(buildPanel))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(buildEdge, lineWidth: 1))
    }
    @ViewBuilder private func buildReceiverControl(_ i: Int) -> some View {
        let rec = i < receivers.count ? receivers[i] : Receiver()
        let letter = ["A", "B", "C", "D"][i]
        let soloed = soloReceiverMask & (1 << UInt8(i)) != 0
        let h: CGFloat = 148                                                    // total control height, split into 4 EQUAL rows on the right (Paul 2026-08-18)
        HStack(spacing: 6) {
            buildReceiverFader(i, letter: letter).frame(width: 22, height: h)   // velocity INDICATOR — draggable to override input velocity (spring-back on release)
            VStack(spacing: 3) {                                                // four EQUAL rows, top → bottom
                buildRecProminent(recChanLabel(rec), on: rec.inputEnabledResolved, colour: Color(red: 0.36, green: 0.92, blue: 0.52)) { toggleReceiverEnabled(i) }   // TOP: OMNI / CH n (ENABLE)
                buildReceiverLatchButton(i, rec)                                    // LATCH — SET (no mode) / mode label / "LAST N" · pulses when ready · solid when armed
                buildOctRow(oct: i < receiverOctave.count ? receiverOctave[i] : 0, onDown: { nudgeReceiverOctave(i, -1) }, onUp: { nudgeReceiverOctave(i, 1) })   // OCT −/+ (between LATCH and S/M)
                HStack(spacing: 3) {                                            // BOTTOM: SOLO (left) · MUTE (right)
                    buildRecMini("S", on: soloed, colour: buildCyan) { toggleReceiverSolo(i) }
                    buildRecMini("M", on: rec.muted, colour: buildPink) { toggleReceiverMute(i) }
                }
            }.frame(height: h)
        }
    }
    // THE LATCH/arm button on a receiver strip (Paul 2026-08-23) — shared by the main-page I/O box AND the MIDI-IN
    // settings tab (the same buildReceiverControl is used in both). States: no mode chosen → "SET" (cyan pulse; tap
    // OPENS that door's tab); a mode chosen but not armed → the mode label (LATCH/HOLD/KEYS/"LAST N"/.MID) with an
    // amber "ready to arm" pulse; ARMED → solid amber. Arming reuses the real latch/replay engage.
    @ViewBuilder private func buildReceiverLatchButton(_ i: Int, _ rec: Receiver) -> some View {
        let amber = Color(red: 1.0, green: 0.72, blue: 0.2)
        let bit = UInt8(1) << UInt8(i)
        let m = rec.doorMode
        let unset = m == nil                             // no mode chosen at all → PULSE (prompt the user to pick)
        let isThru = m == .thru                          // THRU = "play straight": also reads SET, but STATIC (a deliberate choice)
        // Either arm can be live (replay OR latch). Compute BOTH so a running loop is always stoppable even if the mode
        // was switched afterwards (review finding: a mode switch used to strand a running REPLAY loop).
        let replayOn = (replayEngagedMask & bit) != 0
        let latchOn  = (latchMask & bit) != 0
        let engaged  = replayOn || latchOn
        let showsSet = (unset || isThru) && !engaged     // SET only when neutral AND nothing is armed
        let mode = rec.doorModeResolved
        let modeLabel: String = {
            switch mode {
            case .thru:   return "SET"                   // (unreachable via showsSet, but keeps the switch exhaustive)
            case .latch:  return "LATCH"
            case .hold:   return "HOLD"
            case .keys:   return "KEYS"
            case .replay: return "LAST \(rec.replayPassesResolved)"   // Paul: "last 2 for playback"
            case .file:   return ".MID"
            case .scale:  return "SCALE"
            }
        }()
        // When engaged but the mode was switched to a non-armable one, show what's actually running.
        let label = showsSet ? "SET" : (engaged && (isThru || unset) ? (replayOn ? "LAST \(rec.replayPassesResolved)" : "LATCH") : modeLabel)
        let accent = showsSet ? buildCyan : amber
        // PULSE only when UNSET (no mode chosen). THRU, any armable mode, and any engaged state are all STATIC (Paul 2026-08-23).
        TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: animationsPaused || !unset)) { tl in
            let pulse = unset ? stagingPulseFraction(tl.date, period: 0.9) : 0
            Text(label).font(.system(size: 10, weight: .heavy, design: .monospaced)).tracking(0.5)
                .foregroundColor(engaged ? .black : (showsSet ? buildCyan : .white.opacity(0.85)))
                .lineLimit(1).minimumScaleFactor(0.55)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(RoundedRectangle(cornerRadius: 5).fill(engaged ? amber : accent.opacity(0.10 + 0.18 * pulse)))
                .overlay(RoundedRectangle(cornerRadius: 5).stroke(engaged ? Color.clear : accent.opacity(0.35 + 0.5 * pulse), lineWidth: 1.5))
                .contentShape(Rectangle())
                .onTapGesture {
                    if showsSet { buildMidiConfigTab = i; buildMidiConfigOpen = true }   // SET / THRU → open this door's tab
                    else { buildEngageDoor(i) }                                          // else the door's mode-act (shared with ROW 8 INPUT)
                }
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
    // A shared OCTAVE nudge row: −  OCT ±n  + (±3 octaves). Used by both the receiver and emitter controls. (Paul 2026-08-18)
    @ViewBuilder private func buildOctRow(oct: Int, onDown: @escaping () -> Void, onUp: @escaping () -> Void) -> some View {
        HStack(spacing: 3) {
            buildRecMini("−", on: false, colour: buildCyan, action: onDown).frame(width: 16)
            Text("OCT \(oct > 0 ? "+" : "")\(oct)").font(.system(size: 8, weight: .heavy, design: .monospaced))
                .foregroundColor(oct == 0 ? .white.opacity(0.6) : buildCyan).lineLimit(1).minimumScaleFactor(0.5)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(RoundedRectangle(cornerRadius: 4).fill(buildCell))
                .overlay(RoundedRectangle(cornerRadius: 4).stroke(buildEdge, lineWidth: 1))
            buildRecMini("+", on: false, colour: buildCyan, action: onUp).frame(width: 16)
        }
    }
    // The INTERACTIVE input-velocity indicator: the incoming-velocity meter (sustained while held, brief attack flash)
    // normally; DRAG to force this door's input velocity (top = 127 · bottom = 0) via setReceiverVel; release springs
    // back to the natural velocity — the receiver mirror of buildEmitterFader. (Paul 2026-08-18)
    @ViewBuilder private func buildReceiverFader(_ i: Int, letter: String) -> some View {
        let override = i < recvDragVel.count ? recvDragVel[i] : nil
        VStack(spacing: 2) {
            Text(override.map { "\($0)" } ?? letter).font(.system(size: 10, weight: .black, design: .monospaced)).foregroundColor(override != nil ? buildPink : buildDim)
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
                        RoundedRectangle(cornerRadius: 3).fill((override != nil ? buildPink : buildCyan).opacity(0.9)).frame(height: g.size.height * CGFloat(min(1, max(0, level))))
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
    // The incoming-velocity meter: the door letter over a bottom-filling bar that peaks on input then decays.
    @ViewBuilder private func buildReceiverMeter(_ i: Int, letter: String) -> some View {
        VStack(spacing: 2) {
            Text(letter).font(.system(size: 10, weight: .black, design: .monospaced)).foregroundColor(buildDim)
            TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: animationsPaused)) { tl in
                let held = i < recvHeld.count ? (recvHeld[i].max() ?? 0) : 0     // SUSTAINED while notes are held → the bar shows note LENGTH
                let age = tl.date.timeIntervalSince(i < meters.receiverPeakAt.count ? meters.receiverPeakAt[i] : .distantPast)
                let flash = (i < meters.receiverPeak.count ? meters.receiverPeak[i] : 0) * max(0, 1 - age / 0.3)   // a brief attack flash on note-on
                let level = max(0, min(1, max(held, flash)))
                GeometryReader { g in
                    ZStack(alignment: .bottom) {
                        RoundedRectangle(cornerRadius: 3).fill(Color.black.opacity(0.5))
                        RoundedRectangle(cornerRadius: 3).fill(buildCyan.opacity(0.9)).frame(height: g.size.height * CGFloat(level))
                    }
                }
            }
        }
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

    // THE EMITTER SELECT box (centre column, bottom): the four PART-owned output emitter toggles (A–D) + the
    // MIDI-OUT readout (lit emitters → their channels). Emitters are part-owned, so every colour follows. (2026-08-17)
    @ViewBuilder private func buildEmitterSelectBox(gridW: CGFloat) -> some View {
        let buses = buildPartEmitters
        VStack(spacing: 6) {
            HStack(spacing: 4) {                                  // A–D toggle the PART's output emitters
                ForEach(Array(Bus.allCases.enumerated()), id: \.offset) { _, b in
                    buildIOChip(b.rawValue, on: buses.contains(b), fill: true) { buildToggleBus(b) }
                }
            }
            buildMidiOutInfo(buses: buses, castW: gridW - 20)    // the lit emitters + their channels
        }
        .padding(10)
        .frame(width: gridW)
        .background(RoundedRectangle(cornerRadius: 12).fill(buildPanel))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(buildEdge, lineWidth: 1))
    }

    // THE MAIN EMITTERS BOX (right column, bottom): four output controls (A–D), styled like the receivers panel.
    // Each = an INTERACTIVE velocity fader (drag to override output velocity; bottom = kill; release = spring back)
    // + Mute/Solo on one line + a prominent RACK toggle. (Paul 2026-08-17)
    @ViewBuilder private func buildEmittersBox() -> some View {
        HStack(spacing: 6) {                                       // the four emitters A–D sit side by side
            ForEach(0..<4, id: \.self) { i in buildEmitterControl(i) }
        }
        .padding(10)
        .frame(maxWidth: .infinity)
        .background(RoundedRectangle(cornerRadius: 12).fill(buildPanel))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(buildEdge, lineWidth: 1))
    }
    @ViewBuilder private func buildEmitterControl(_ i: Int) -> some View {
        let letter = ["A", "B", "C", "D"][i]
        let muted = !(i < busEnabled.count ? busEnabled[i] : true)
        let soloed = emitterFootSolo & (1 << UInt8(i)) != 0
        let racked = rackMask & (1 << UInt8(i)) != 0
        let ch = i < busChannels.count ? busChannels[i] : i + 1
        let h: CGFloat = 148                                                   // match the receiver control — four EQUAL rows (Paul 2026-08-18)
        HStack(spacing: 6) {
            buildEmitterFader(i, letter: letter).frame(width: 22, height: h)   // interactive velocity fader — drag to override output velocity
            VStack(spacing: 3) {                                               // four EQUAL rows, top → bottom (mirrors the receiver control)
                buildRecProminent("CH \(ch)", on: !muted, colour: Color(red: 0.36, green: 0.92, blue: 0.52)) { toggleEmitter(i) }   // TOP: CH n — acts as the MUTE (dim = muted / bus disabled)
                buildRecProminent("RACK", on: racked, colour: Color(red: 1.0, green: 0.72, blue: 0.2)) { toggleRack(i) }             // RACK
                buildOctRow(oct: i < emitterOctave.count ? emitterOctave[i] : 0, onDown: { nudgeEmitterOctave(i, -1) }, onUp: { nudgeEmitterOctave(i, 1) })   // OCT −/+
                buildRecMini("SOLO", on: soloed, colour: buildCyan) { toggleEmitterSolo(i) }   // BOTTOM: SOLO only (CH is the mute)
            }.frame(height: h)
        }
    }
    // NEW INTERFACE (Paul 2026-08-28): the real MIXER strips reused verbatim in the slideover mixer overlay — the full
    // MIDI-IN receiver console (fader · ENABLE/CH · LATCH · OCT · S/M) and MIDI-OUT emitter console (fader · CH · RACK ·
    // OCT · SOLO). Internal wrappers so RoomsPage can call the private controls.
    @ViewBuilder func roomsMixerReceiver(_ i: Int) -> some View { buildReceiverControl(i) }
    @ViewBuilder func roomsMixerEmitter(_ i: Int) -> some View { buildEmitterControl(i) }

    // The colour currently PLAYING the cell (the active rung in the playing column) → the emitter velocity-strip tint. (Paul 2026-08-19)
    private var buildPlayingColourHue: Color? {
        guard d.playing, d.effColumn >= 0, d.effColumn < buildStagingSel.count else { return nil }
        let rung = buildStagingSel[d.effColumn]
        guard rung >= 0, let cid = buildRowColour(rung) else { return nil }
        return colourColor(cid)
    }
    // The interactive velocity fader: the meter (emitPeak, decayed) normally; while DRAGGED it forces the emitter's
    // output velocity (top = 127 · bottom = 0/KILL) via setVelOverride, and releases (springs back) on lift.
    @ViewBuilder private func buildEmitterFader(_ i: Int, letter: String) -> some View {
        let override = i < emitDragVel.count ? emitDragVel[i] : nil
        VStack(spacing: 2) {
            Text(override.map { "\($0)" } ?? letter).font(.system(size: 10, weight: .black, design: .monospaced)).foregroundColor(override != nil ? buildPink : buildDim)
            GeometryReader { g in
                TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: animationsPaused)) { tl in
                    // DECAY + note-priority (Paul 2026-08-19): the bar FALLS from the last peak; a new note resets
                    // emitPeakAt → the bar jumps back up, so new notes take priority over the fall reaching the bottom.
                    let level: Double = {
                        if let o = override { return Double(o) / 127.0 }
                        let age = tl.date.timeIntervalSince(i < meters.emitPeakAt.count ? meters.emitPeakAt[i] : .distantPast)
                        return max(0, min(1, (i < meters.emitPeak.count ? meters.emitPeak[i] : 0) * (1 - age / 0.9)))
                    }()
                    let hue = override != nil ? buildPink : (buildPlayingColourHue ?? buildCyan)   // the colour currently playing the cell
                    ZStack(alignment: .bottom) {
                        RoundedRectangle(cornerRadius: 3).fill(Color.black.opacity(0.5))
                        RoundedRectangle(cornerRadius: 3).fill(hue.opacity(0.3 + 0.6 * level)).frame(height: g.size.height * CGFloat(level))   // fade OUT as it drops
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

    // A bottom-of-column placeholder box (receivers · emitter-select · emitter-out). Contents are stubs for now;
    // the styling (panel fill + edge outline + fixed height) matches the button boxes so all columns read alike.
    @ViewBuilder private func buildBottomPlaceholder(_ title: String) -> some View {
        HStack(spacing: 6) {
            Text(title).font(.system(size: 10, weight: .heavy, design: .monospaced)).tracking(1).foregroundColor(buildDim)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 12)
        .frame(maxWidth: .infinity, minHeight: 52, maxHeight: 52)   // fixed height (min==max) → no stretch, consistent across columns
        .background(RoundedRectangle(cornerRadius: 12).fill(buildPanel))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(buildEdge, lineWidth: 1))
    }

    // a fixed-width footer button (the footer uses a Spacer, so these can't be maxWidth-fill like a fill button).
    @ViewBuilder private func buildFooterBtn(_ label: String, pink: Bool = false, action: (() -> Void)? = nil) -> some View {
        Text(label).font(.system(size: 11, weight: .heavy, design: .monospaced)).tracking(0.5)
            .foregroundColor(pink ? buildPink : Color.white)                                 // §0 MUTED: pink is a WHISPER (ink + edge on neutral), not a slab
            .padding(.horizontal, 16).frame(height: 46)
            .background(RoundedRectangle(cornerRadius: 11).fill(buildCell))
            .overlay(RoundedRectangle(cornerRadius: 11).stroke(pink ? buildPink.opacity(0.55) : buildEdge, lineWidth: 1))
            .contentShape(Rectangle())
            .onTapGesture { action?() }
    }

    // ── small shared placeholder widgets ─────────────────────────────────────────────────────────────────────────
    // The identical audition button at the top of each column (transport glyph + label, cyan-bordered). `active` marks
    // it the playing voice; when active AND the transport plays, it becomes a PLAYHEAD — filling cyan L→R over `fill`'s
    // period (.cell = one step · .grid = the whole 8-column loop), looping. Inactive buttons never animate. (user 2026-08-13)
    @ViewBuilder private func buildColumnButton(_ label: String, active: Bool = false, fill: BuildFill = .none, enabled: Bool = true, action: (() -> Void)? = nil) -> some View {
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
        .frame(maxWidth: .infinity).frame(height: 38)
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
    @ViewBuilder private func buildStep(_ s: String) -> some View {
        Text(s).font(.system(size: 8, weight: .heavy, design: .monospaced)).foregroundColor(buildDim).tracking(1.2)   // §0 MUTED: step labels recede (were loud pink)
    }
    @ViewBuilder private func buildIOChip(_ s: String, on: Bool = false, keys: Bool = false, fill: Bool = false, action: (() -> Void)? = nil) -> some View {
        Text(s).font(.system(size: 9, weight: on ? .heavy : .regular, design: .monospaced))
            .foregroundColor(on ? Color.black : (keys ? buildCyan : buildDim))
            .padding(.horizontal, 7)
            .frame(maxWidth: fill ? .infinity : nil).frame(height: 48)   // fill → the row spreads evenly to the cast width; height doubled (24→48)
            .background(RoundedRectangle(cornerRadius: 7).fill(on ? buildCyan : buildCell))   // ON keeps the accent (armed); idle mutes
            .overlay(RoundedRectangle(cornerRadius: 7).stroke(on ? Color.clear : buildEdge, lineWidth: 1))   // §0: neutral border when idle (was standing cyan)
            .contentShape(Rectangle())
            .onTapGesture { action?() }
    }
    // The SELECT · PLACE · MUTATE radio — a pure radio (always one active) that changes what the left row buttons DO.
    @ViewBuilder private func buildRowModeBtn(_ m: BuildRowMode, enabled: Bool = true) -> some View {
        let armed = buildRowMode == m && enabled
        Text(m.rawValue).font(.system(size: 9, weight: .heavy, design: .monospaced)).tracking(0.5)
            .foregroundColor(armed ? Color.black : Color.white)
            .frame(maxWidth: .infinity).frame(minHeight: 36, maxHeight: 36)   // FIXED height — else the verb box stretches to the page bottom (competes with the Spacer)
            .background(RoundedRectangle(cornerRadius: 9).fill(armed ? buildCyan : buildCell))
            .overlay(RoundedRectangle(cornerRadius: 9).stroke(armed ? Color.clear : buildEdge, lineWidth: 1))   // §0: armed keeps the cyan fill; idle mutes to a whisper
            .opacity(enabled ? 1 : 0.3)                                        // DISABLED (PLACE) → greyed, inert
            .contentShape(Rectangle())
            .onTapGesture { if enabled { buildExitPlaceMode(); buildRowMode = m } }   // a verb is not a play-grid row → leaves PLACE mode
            .allowsHitTesting(enabled)
    }
    // The left row-button icon for the current mode: a chevron (SELECT), the TARGET (PLACE) or a wand (MUTATE); the
    // latter two carry the SELECTED palette colour so you see what a press will lay down. (Paul 2026-08-16)
    @ViewBuilder private func buildRowButtonIcon() -> some View {
        switch buildRowMode {
        case .select: Image(systemName: "chevron.right").font(.system(size: 10, weight: .bold)).foregroundColor(.white.opacity(0.55))
        case .place:  Image(systemName: "scope").font(.system(size: 13, weight: .medium)).foregroundColor(buildSelHue)
        case .mutate: Image(systemName: "wand.and.stars").font(.system(size: 12, weight: .medium)).foregroundColor(buildSelHue)
        }
    }
    // A reserved (inert) button slot — the second verb-box row is blank for now (Paul 2026-08-16).
    @ViewBuilder private func buildBlankSlot() -> some View {
        Color.clear.frame(maxWidth: .infinity).frame(minHeight: 36, maxHeight: 36)   // FIXED height — matches the row buttons; keeps the verb box compact
            .background(RoundedRectangle(cornerRadius: 9).fill(buildCell.opacity(0.4)))
            .overlay(RoundedRectangle(cornerRadius: 9).stroke(buildEdge.opacity(0.5), lineWidth: 1))
    }
    @ViewBuilder private func buildBox(_ title: String, _ ch: String) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(title).font(.system(size: 9, design: .monospaced)).foregroundColor(.white)
            Text(ch).font(.system(size: 8, design: .monospaced)).foregroundColor(buildDim)   // §0 MUTED: channel readout recedes (was standing cyan)
        }
        .padding(.horizontal, 9).padding(.vertical, 5)
        .background(RoundedRectangle(cornerRadius: 9).fill(buildCell))
    }
    // A processor slot in the footer chain. `colour` fills a REAL processor with the selected colour; else a dashed
    // empty/ghost slot. Boxes are a little bigger than before (50×40).
    @ViewBuilder private func buildSlot(_ s: String, dashed: Bool = false, colour: Color? = nil, bypassed: Bool = false) -> some View {
        Text(s).font(.system(size: 9, weight: colour != nil ? .heavy : .regular, design: .monospaced))
            .foregroundColor(colour != nil ? .black : (dashed ? buildSelHue : .white))   // dashed capacity/ghost slots = the SELECTED colour
            .lineLimit(1).minimumScaleFactor(0.6)
            .frame(width: 50, height: 40)
            .background(RoundedRectangle(cornerRadius: 7).fill(colour ?? (dashed ? Color.clear : buildCell)))
            .overlay(RoundedRectangle(cornerRadius: 7).stroke(colour != nil ? Color.clear : (dashed ? buildSelHue : Color(white: 0.15)),
                                                              style: StrokeStyle(lineWidth: dashed ? 1.3 : 1, dash: dashed ? [4] : [])))
            .overlay(bypassed ? RoundedRectangle(cornerRadius: 7).fill(Color.black.opacity(0.45)) : nil)   // a BYPASSED processor reads dimmed
            .opacity(bypassed ? 0.7 : 1)
    }

    // ── PROCESSOR POP-UP EDITOR ──────────────────────────────────────────────────────────────────────────────────
    // Touching a footer processor opens this large, colour-tinted pop-up showing ALL of that processor's controls
    // (reusing ProcessorBox in slotMode). The dimmed scrim closes on tap, but leaves the FOOTER exposed & live — so
    // touching another processor switches straight to its editor. DELETE PROCESSOR + BYPASS sit at the top. (user 2026-08-12)
    @ViewBuilder private func buildProcessorEditor(slot: Int, size: CGSize) -> some View {
        let chain = selectedColourChain()
        let topReserve: CGFloat = 54                           // clear the top play-button row ("Play this part") — the panel docks BELOW it
        // Keep the LEFT column (machine · chain · tabs) UNCOVERED (Paul 2026-08-19): in landscape the panel docks to the
        // RIGHT of it (over the two grid columns + I/O box); in portrait the columns stack, so no left offset.
        let landscape = size.width >= size.height
        let leftW = landscape ? max(1, (size.width - BuildGeom.colGap * 2 - 20) / 3 * 0.726) : 0
        let leftReserve = landscape ? 10 + leftW + BuildGeom.colGap : 12
        let contentW = max(200, size.width - leftReserve - 24)
        if slot < chain.count, let cid = ddSelectedColourID {
            VStack(spacing: 0) {                               // NO backdrop: every control OUTSIDE the panel stays usable (the DONE button closes)
                Color.clear.frame(height: topReserve).allowsHitTesting(false)   // pass taps through to the play-button row
                HStack(spacing: 0) {
                    Color.clear.frame(width: leftReserve).allowsHitTesting(false)   // pass taps through to the LEFT column
                    // The panel now FILLS the width to the page's right border (Paul 2026-08-25) — the earlier ≤600pt cap
                    // ("controls feel too wide") is lifted; the card reaches the right edge (a small margin via contentW's −24).
                    let panelW = contentW
                    buildProcessorPanel(slot: slot, proc: chain[slot], cid: cid, contentW: panelW)
                        .frame(width: panelW).frame(maxHeight: .infinity)
                        .padding(.bottom, 12)
                    Spacer(minLength: 0)
                }
            }
            .onAppear { buildEditorSnapshot = selectedColourChain(); buildEditorSnapCid = ddSelectedColourID }   // capture the OPEN snapshot (for CANCEL / overwrite-revert)
            // CR-14[review 15]: the editor has NO backdrop, so the user can switch the selected colour mid-edit. Re-snapshot
            // the NEW target — else CANCEL reverts the ORIGINAL colour to ITS snapshot and strands the new colour's edits.
            .onChange(of: ddSelectedColourID) { newID in
                guard let newID, newID != buildEditorSnapCid else { return }
                buildEditorSnapshot = selectedColourChain(); buildEditorSnapCid = newID
            }
        }
    }

    // CANCEL: revert the CURRENT target colour to the snapshot taken when the editor opened, then close. (Exit any other
    // way = SAVE the live edits.) After an overwrite-and-follow the snapshot is the target's committed chain (a no-op).
    private func buildEditorCancel() {
        if let cid = buildEditorSnapCid { buildWriteColourMachine(cid, buildEditorSnapshot) }
        buildEditSlot = nil; buildStageEye = false
    }

    @ViewBuilder private func buildProcessorPanel(slot: Int, proc: ProcessorSlot, cid: String, contentW: CGFloat) -> some View {
        let hue = buildSelHue
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
            VStack(alignment: .leading, spacing: 5) {          // ROW SELECTOR — a tab OVERWRITES that row with the current edits
                Text("Long press to copy").font(.system(size: 11, weight: .heavy, design: .monospaced)).foregroundColor(buildDim).tracking(1)
                AnyView(buildColourTabs(castW: contentW - 40, cell: 30, inEditor: true))
            }
            .padding(.horizontal, 16).padding(.vertical, 10)
            Rectangle().fill(hue.opacity(0.25)).frame(height: 1)
            buildTruthStrips().padding(.horizontal, 16).padding(.vertical, 8)   // §1 IN | OUT truths — silence explains itself
            Rectangle().fill(hue.opacity(0.25)).frame(height: 1)
            ScrollView { buildSlotBox(slot, proc, cid: cid).padding(16) }   // CONTROLS — reuse ProcessorBox (our chrome hidden)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(RoundedRectangle(cornerRadius: 8).fill(buildPanel))
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
        let hue = buildSelHue
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
            let hue = buildSelHue
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
    // The IN silhouette: a compact C1–C7 keyboard (black keys fainter for orientation), held notes filled the colour hue.
    private func buildInKeyboard(_ held: [Int], hue: Color) -> some View {
        let lo = 24, hi = 96   // C1..C7 — covers the usual playing range; out-of-range notes simply don't light (v1)
        return Canvas { ctx, size in
            let n = hi - lo
            let bw = size.width / CGFloat(n)
            for s in 0..<n {
                let midi = lo + s
                let isBlack = [1, 3, 6, 8, 10].contains(((midi % 12) + 12) % 12)
                let rect = CGRect(x: CGFloat(s) * bw, y: 0, width: max(1, bw - 0.4), height: size.height)
                ctx.fill(Path(rect), with: .color(.white.opacity(isBlack ? 0.05 : 0.11)))
                if held.contains(midi) { ctx.fill(Path(rect), with: .color(hue)) }
            }
        }
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
            accentOverride: buildSelHue,
            passHead: d.playing ? (d.pass & 3) : -1,
            liveStep: d.playing ? ((d.effColumn % 8) + 8) % 8 : -1,   // PLAYHEAD (idea 15): the live grid column sweeps the matrix/lane
            onBypass: { buildChainToggleBypass(i) },
            onRemove: { buildChainRemoveSlot(i); buildEditSlot = nil },
            onMacro: nil, plainTitle: true, showSlotChrome: false)
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
        // PLACED: a pending tab whose chain has diverged from its source is committed (stops pulsing). (2026-08-17)
        if let p = buildPendingTab, buildRowColour(p) == cid, chain != buildPendingSource {
            buildPendingTab = nil; buildPendingSource = []
        }
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
        let base = s.type == .passgate ? "PASSES" : (s.type == .muteMatrix ? "MUTE MTX" : s.type.rawValue)
        let m: String
        switch s.type {
        case .ratchet: switch s.params.rtcMode ?? .all { case .all: m = "ALL"; case .coin: m = "COIN"; case .pattern: m = "PAT" }
        case .burst:   switch s.params.burstMode ?? .once { case .once: m = "ONCE"; case .coin: m = "COIN"; case .pattern: m = "PAT" }
        case .tutti:   switch s.params.tuttiMode ?? .coin { case .coin: m = "COIN"; case .pattern: m = "PAT" }
        case .weave:   switch s.params.weaveMode ?? .ladder { case .ladder: m = "LAD"; case .harmonic: m = "HARM"; case .drawn: m = "DRAWN"; case .euclid: m = "EUC" }
        case .mod:     switch s.params.modSource ?? .shape { case .shape: m = "LFO"; case .follow: m = "FOLLOW"; case .steps: m = "STEP"; case .strike: m = "ENV"; case .extern: m = "CC IN" }
        case .hocket:  switch s.params.hocketMode ?? .gaps { case .gaps: m = "GAPS"; case .trade: m = "TRADE" }
        default:       m = ""
        }
        return m.isEmpty ? base : "\(base) \(m)"
    }

    // ADD a catalog CARD at box `i`: populate the box with the card's type, pre-set its mode, open its editor.
    private func buildChainAddCard(_ i: Int, _ card: BuildCard) {
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
        let hue = buildSelHue
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

    // ── SIGNAL-FLOW DIAGRAM POP-UP (footer eye) ──────────────────────────────────────────────────────────────────
    // Reuses the PROCESSORS page's flow diagram (MIDI in → processor row → emitter row, one dotted thread) for the
    // SELECTED colour's machine. Display-only for now; animation is a later slice. (user 2026-08-13)
    @ViewBuilder private func buildFlowPopup(size: CGSize) -> some View {
        let hue = buildSelHue
        let w = min(1000, size.width - 80)
        let cell: Cell = {
            var c = Cell(colourID: ddSelectedColourID ?? "")
            c.processors = selectedColourChain()                  // show exactly the footer chain (incl. empty "+" slots)
            c.inputReceiver = buildSelReceiver
            c.buses = ddSelectedColourBuses()
            return c
        }()
        ZStack {
            Color.black.opacity(0.6).ignoresSafeArea().contentShape(Rectangle()).onTapGesture { buildFlowOpen = false }
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 8) {
                    Image(systemName: "eye").font(.system(size: 16, weight: .semibold)).foregroundColor(hue)
                    Text("THE MIDI CHAIN").font(.system(size: 18, weight: .heavy, design: .monospaced)).foregroundColor(.white).tracking(1)
                    Spacer()
                }
                flowDiagram(cell, width: w).allowsHitTesting(false)   // the exact processors-page diagram — display-only
            }
            .padding(18)
            .frame(width: w + 36)
            .background(RoundedRectangle(cornerRadius: 16).fill(buildPanel))
            .overlay(RoundedRectangle(cornerRadius: 16).stroke(hue, lineWidth: 2))
            .shadow(color: .black.opacity(0.5), radius: 20, y: 8)
            .contentShape(Rectangle()).onTapGesture { }
        }
    }

    // ── FULL-SCREEN GRID POP-UP (grid eye) ───────────────────────────────────────────────────────────────────────
    // Shows JUST the respective grid (0 = staging, 1 = perform) at a large cell size, in PLAY mode. (user 2026-08-13)
    @ViewBuilder private func buildGridPopupView(_ kind: Int, size: CGSize) -> some View {
        let hue = buildSelHue
        let popupW = min(920, size.width - 80)
        let cellByW = (popupW - BuildGeom.cellGap * 9 - 44) / 10          // 10-cell span (matches the perform grid)
        let cellByH = (size.height - 150 - BuildGeom.cellGap * 8) / 10    // ~9 cells tall + header/padding → clamp so it FITS onscreen
        let cell = max(20, min(46, min(cellByW, cellByH)))
        ZStack {
            Color.black.opacity(0.6).ignoresSafeArea().contentShape(Rectangle()).onTapGesture { buildGridPopup = nil }
            VStack(alignment: .center, spacing: 12) {
                HStack(spacing: 8) {
                    Image(systemName: "eye").font(.system(size: 16, weight: .semibold)).foregroundColor(hue)
                    Text(kind == 0 ? "STAGING GRID" : "PERFORM GRID").font(.system(size: 18, weight: .heavy, design: .monospaced)).foregroundColor(.white).tracking(1)
                    Spacer()
                }
                if kind == 0 {
                    AnyView(buildStagingGrid(cell: cell, hue: hue))
                } else {
                    AnyView(HStack(alignment: .top, spacing: BuildGeom.cellGap) {
                        AnyView(buildPartButtons(cell: cell, hue: buildCyan, bands: [3, 2, 1, 1]))   // multi-row valve
                        AnyView(buildRightPartButtons(cell: cell, hue: buildCyan))                    // single-row valve — both on the left
                        VStack(spacing: BuildGeom.cellGap) { buildLoopKeys(cell: cell, staging: false); AnyView(buildPlayBands(cell: cell)) }
                        AnyView(buildPerformRowButtons(cell: cell))                                   // right chevrons
                    })
                }
            }
            .padding(22)
            .background(RoundedRectangle(cornerRadius: 16).fill(buildPanel))
            .overlay(RoundedRectangle(cornerRadius: 16).stroke(hue, lineWidth: 2))
            .shadow(color: .black.opacity(0.5), radius: 20, y: 8)
            .contentShape(Rectangle()).onTapGesture { }
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
        buildGridSelSel = nil
        buildGridSelBuildCorpus()                                        // §3.1 kick the pregen corpus (background, once) — DEAL upgrades to it when ready
        if buildGridSelDealt.isEmpty || !buildGridSelCorpus.isEmpty { buildGridSelDeal() }   // corpus ready ⇒ instant draw; else a fresh 64
        else { buildGridSelComputeCellRolls() }                          // dealt already stocked (reopen) → compute its drifting faces now
        buildGridSelComputeRowRolls()                                    // the row selectors' drifting faces
        buildGridSelOpen = true
    }
    // INTERFACE REDESIGN (§6): close the grid selector — stop the audition voice + restore — when leaving the SELECT room.
    func buildCloseGridSel() { if buildGridSelOpen { buildGridSelTeardown(select: buildGridSelPriorSel, restoreSolo: true) } }
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
    private func buildGridSelReDeal() {
        guard !buildGridSelGenerating else { return }
        buildGridSelStopAudition()                                       // a live audition points at a chain about to vanish — stop it first
        buildGridSelOverride = [:]                                       // re-deal replaces the bank → drop the cell-to-cell copy instances
        buildGridSelDealSeed &+= 1; buildGridSelDeal()
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
            guard i >= 0 && i < buildGridSelLib.count else { return nil }
            let name = buildGridSelLib[i].name
            // Resolve by SECTION, not by name — a saved cell may share a factory cell's name (saved rows are [0, factoryFrom)).
            let cell = i >= buildGridSelLibFactoryFrom ? au?.factoryLibraryCell(name: name) : au?.loadLibraryCell(name: name)
            return (cell?.processors ?? [], 0, colourHexes[i % 16])
        }
    }
    private func buildGridSelPresent(_ i: Int) -> Bool { buildGridSelOverride[i] != nil || (buildGridSelTab == 0 ? i < buildGridSelDealt.count : i < buildGridSelLib.count) }   // a cell-to-cell COPY makes an empty position present too (Paul 2026-08-28)
    private func buildGridSelCellHex(_ i: Int) -> UInt32 { buildGridSelOverride[i]?.hex ?? (buildGridSelTab == 0 ? colourHexes[((i % 8) * 2) % 16] : colourHexes[i % 16]) }
    private func buildGridSelSummary(_ i: Int) -> String {
        if buildGridSelTab == 0 {
            guard i < buildGridSelDealt.count else { return "—" }
            let c = buildGridSelDealt[i].chain
            return c.isEmpty ? "PASS" : c.map { $0.type.rawValue.uppercased() }.joined(separator: " → ")
        } else {
            guard i < buildGridSelLib.count else { return "—" }
            return buildGridSelLib[i].chainSummary.uppercased()
        }
    }

    // AUDITION — register the browsed chain on the ONE transient colour, select it, and drive the existing chain-voice
    // path: turn the chain voice ON (quantized) if not already, else swap which chain (quantized). Piece plays on.
    private func buildGridSelAudition(_ i: Int) {
        guard let hit = buildGridSelChainAt(i) else { return }
        buildGridSelStampSourceRow = nil                                 // a library CELL is now the active source → clear the active side button (mutual exclusivity; no-op in old BUILD)
        buildGridSelLoadChain(hit.chain, transpose: hit.transpose, hex: hit.hex, sel: i)   // a DEALT/LIBRARY cell — its index is the commit source
    }
    // Load a chain onto the ONE transient audition colour, select it, and drive the chain voice (quantized). Shared by a
    // cell audition (sel = the cell index → the commit source) and a ROW press (sel = nil → a view/hear of that part's chain).
    private func buildGridSelLoadChain(_ raw: [ProcessorSlot], transpose: Int, hex: UInt32, sel: Int?) {
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
        guard buildGridSelSel != nil || ddSolo || buildPendingWorkshopVoice != nil || buildPendingReengage else { return }
        buildGridSelSel = nil; buildGridSelActiveRoll = []
        buildPendingWorkshopVoice = nil; buildPendingReengage = false
        buildColourReg[buildGridSelAudID] = nil; colourHueOverride[buildGridSelAudID] = nil; buildColourTranspose[buildGridSelAudID] = nil
        if ddSolo { ddSolo = false }
        buildSelID = buildGridSelPriorSel; ddColourSel = colourIDs.firstIndex(of: buildGridSelPriorSel ?? "") ?? -1
        au?.clearColourSolo(); buildSyncColours(); buildPublishScene()
    }
    // COMMIT — overwrite the FROZEN arrival row's chain with the selected cell's chain (populated row → one undo via the
    // document colour; empty row → mint a colour carrying the chain + its register home), then tear down.
    // COMMIT button → the frozen arrival row (or the first empty). LONG-PRESS a row chip → that specific row (Paul 2026-08-25).
    private func buildGridSelCommit() { buildGridSelCommit(to: buildGridSelArrivalRow ?? (0..<8).first { buildRowColour($0) == nil }) }
    private func buildGridSelCommit(to r: Int?) {
        guard let row = r, let i = buildGridSelSel, let hit = buildGridSelChainAt(i) else { buildGridSelCancel(); return }   // no target/selection → restore, don't discard the selection
        buildRecordUndo()   // BUILD UNDO: commit a browsed chain to a row
        let targetID: String
        if let tgt = buildRowColour(row) {                               // populated → overwrite its chain (keeps its hue/register; v1 doesn't move the register home onto an existing colour)
            buildWriteColourMachine(tgt, hit.chain); targetID = tgt
        } else {                                                          // empty → mint a colour carrying the chain + its register home, and SELECT the whole row (else it stays silent)
            let y = buildNewTabColour(row, machine: hit.chain, transpose: hit.transpose)
            buildPartCast.append(y)
            if row < buildRowUnder.count { buildRowUnder[row] = buildRowColour(row) }
            buildSetRow(row, to: y)
            if row < buildRowReceiver.count { buildRowReceiver[row] = ddStickyReceiver; buildRowEmitters[row] = ddStickyBuses }
            for c in 0..<8 { buildStagingSel[c] = row }                  // mirror buildStampRow — the row plays immediately
            targetID = y
        }
        buildStagingSyncIfPlaying()
        buildFlashPromote("ROW \(row + 1) ✓")
        buildGridSelTeardown(select: targetID, restoreSolo: false)      // the chain is on a row now → stop the transient audition
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
        if let i = buildGridSelSel, let hit = buildGridSelChainAt(i) { return (hit.chain, hit.transpose) }
        if let s = buildGridSelStampSourceRow, let cid = buildRowColour(s) { return (buildColourChain(cid), buildColourTranspose[cid] ?? 0) }
        return nil
    }
    // Make the side button the ONE active source (clear the library-cell source) — "one thing is active". (Paul 2026-08-28)
    private func buildRoomsSetActiveSide(_ n: Int) { buildGridSelStampSourceRow = n; buildGridSelSel = nil }
    private func buildGridSelStampCommit(_ row: Int) {
        guard let hit = buildGridSelStampSource() else { return }
        buildRecordUndo()   // BUILD UNDO: stamp the auditioning chain onto a part
        if let tgt = buildRowColour(row) {                               // populated → overwrite its chain, KEEP its colour
            buildWriteColourMachine(tgt, hit.chain)
        } else {                                                         // empty → mint a colour carrying the chain + its register home
            let y = buildNewTabColour(row, machine: hit.chain, transpose: hit.transpose)
            buildPartCast.append(y)
            if row < buildRowUnder.count { buildRowUnder[row] = buildRowColour(row) }
            buildSetRow(row, to: y)
            if row < buildRowReceiver.count { buildRowReceiver[row] = ddStickyReceiver; buildRowEmitters[row] = ddStickyBuses }
        }
        buildStagingSyncIfPlaying()
        buildGridSelComputeRowRolls()                                    // the row's drifting face updates to the stamped chain
        buildGridSelStampFlashRow = row; buildGridSelStampFlashAt = Date()   // the white→fade confirm
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.55) { if buildGridSelStampFlashRow == row { buildGridSelStampFlashRow = nil; buildGridSelStampFlashAt = nil } }
    }
    // CANCEL — the arrival colour was never written (audition rode the transient); restore the PRE-OPEN workshop voice.
    private func buildGridSelCancel() { buildGridSelTeardown(select: buildGridSelPriorSel, restoreSolo: true) }
    // Shared teardown: reap the transient, restore the selection + (on CANCEL) the pre-open voice + borrowed door, republish.
    private func buildGridSelTeardown(select: String?, restoreSolo: Bool) {
        buildGridSelOpen = false; buildGridSelSel = nil; buildGridSelActiveRoll = []
        buildPendingWorkshopVoice = nil; buildPendingReengage = false
        buildColourReg[buildGridSelAudID] = nil; colourHueOverride[buildGridSelAudID] = nil; buildColourTranspose[buildGridSelAudID] = nil
        buildSelID = select; ddColourSel = colourIDs.firstIndex(of: select ?? "") ?? -1
        ddSolo = restoreSolo ? buildGridSelPriorSolo : false             // CANCEL restores the pre-open audition; COMMIT stops it
        buildStagingPlaying = buildGridSelPriorStaging
        buildSelReceiver = buildGridSelPriorReceiver                      // give back the door + emitters we borrowed for the faithful preview
        buildPartEmitters = buildGridSelPriorEmitters
        au?.clearColourSolo(); buildSyncColours()                        // push the transient removal BEFORE republishing (no dead-transient rebuild)
        buildPublishScene()
        buildGCColours()
    }

    // INTERFACE REDESIGN (§6 reuse): the grid selector = a full-screen modal overlay (its backdrop + the inner body). The
    // BODY alone (backdrop-free) re-houses as the SELECT room in the new shell, with the room's doors around it.
    private func buildGridSelectorOverlay(size: CGSize) -> some View {
        ZStack {
            Color(red: 0.055, green: 0.065, blue: 0.085).ignoresSafeArea()
            buildGridSelectorBody(size: size)
        }
        .onDisappear { }   // teardown is explicit (COMMIT/CANCEL) so a stray dismiss can't strand the transient voice
    }
    @ViewBuilder func buildGridSelectorBody(size: CGSize) -> some View {
        let outerPad: CGFloat = 16, headerH: CGFloat = 46, gap: CGFloat = 3
        let bodyH = max(80, size.height - 2 * outerPad - headerH - 14)
        let rightW = min(300, size.width * 0.30)
        let gridAvail = size.width - 2 * outerPad - rightW - 32 - 44   // reserve the row-selector strip (~44) + two HStack gaps
        let side = max(80, min(gridAvail, bodyH))
        let cell = (side - 7 * gap) / 8
        VStack(spacing: 12) {
                HStack(spacing: 10) {
                    Text("GRID SELECTOR").font(.system(size: 12, weight: .heavy, design: .monospaced)).tracking(1.5).foregroundColor(buildCyan)
                    buildGridSelTabChip("DEALT", 0)
                    buildGridSelTabChip("MY LIBRARY", 1)
                    buildGridSelSmallChip(buildGridSelQuantStep ? "STEP" : "INSTANT", on: false) { buildGridSelQuantStep.toggle() }
                    if buildGridSelTab == 0 { buildGridSelSmallChip("RE-DEAL", on: false) { buildGridSelReDeal() } }
                    Spacer()
                    if let r = buildGridSelArrivalRow {
                        Text("→ ROW \(r + 1)").font(.system(size: 11, weight: .heavy, design: .monospaced)).tracking(1).foregroundColor(buildDim)
                    }
                    Button { buildGridSelCommit() } label: {
                        Text("COMMIT").font(.system(size: 11, weight: .heavy, design: .monospaced)).tracking(1)
                            .foregroundColor(buildGridSelSel != nil ? .black : buildDim)
                            .padding(.horizontal, 14).padding(.vertical, 7)
                            .background(RoundedRectangle(cornerRadius: 6).fill(buildGridSelSel != nil ? buildCyan.opacity(0.92) : buildCell))
                    }.disabled(buildGridSelSel == nil)
                    Button { buildGridSelCancel() } label: {
                        Image(systemName: "xmark").font(.system(size: 15, weight: .bold)).foregroundColor(buildDim).padding(8)
                    }
                }.frame(height: headerH)
                HStack(alignment: .top, spacing: 16) {
                    ZStack {
                        VStack(spacing: gap) {
                            ForEach(0..<8, id: \.self) { r in
                                HStack(spacing: gap) { ForEach(0..<8, id: \.self) { c in buildGridSelCell(r * 8 + c, w: cell, h: cell) } }
                            }
                        }.frame(width: side, height: side)
                        if buildGridSelGenerating {
                            VStack(spacing: 10) {
                                ProgressView().tint(buildCyan)
                                Text("DEALING 64 CHAINS…").font(.system(size: 11, weight: .heavy, design: .monospaced)).tracking(1).foregroundColor(buildDim)
                            }.frame(width: side, height: side).background(RoundedRectangle(cornerRadius: 8).fill(Color.black.opacity(0.55)))
                        }
                    }
                    // §3.2 ROW SELECTORS ON THE GRID EDGE (Paul 2026-08-25): a vertical strip of 8 PART buttons aligned to the
                    // grid rows (Launchpad-mappable — the scene-launch column). TAP = aim + load that part's chain.
                    VStack(spacing: gap) {
                        ForEach(0..<8, id: \.self) { r in buildGridSelRowChip(r, height: cell) }
                    }.frame(width: max(30, cell), height: side)
                    buildGridSelRightColumn(width: rightW)
                    Spacer(minLength: 0)
                }
            }.padding(outerPad)
    }
    @ViewBuilder private func buildGridSelTabChip(_ label: String, _ tab: Int) -> some View {
        let on = buildGridSelTab == tab
        Text(label).font(.system(size: 10, weight: .heavy, design: .monospaced)).tracking(0.8)
            .foregroundColor(on ? .black : .white.opacity(0.7))
            .padding(.horizontal, 10).padding(.vertical, 6)
            .background(RoundedRectangle(cornerRadius: 5).fill(on ? buildCyan.opacity(0.9) : buildCell))
            .contentShape(Rectangle()).onTapGesture { if buildGridSelTab != tab { buildGridSelStopAudition(); buildGridSelOverride = [:]; buildGridSelTab = tab; buildGridSelComputeCellRolls() } }   // stop the transient before switching banks (no stranded voice); drop copy instances; recompute the tab's drifting faces
    }
    @ViewBuilder private func buildGridSelSmallChip(_ label: String, on: Bool, _ action: @escaping () -> Void) -> some View {
        Text(label).font(.system(size: 10, weight: .heavy, design: .monospaced)).tracking(0.6)
            .foregroundColor(on ? .black : .white.opacity(0.7))
            .padding(.horizontal, 9).padding(.vertical, 6)
            .background(RoundedRectangle(cornerRadius: 5).fill(on ? buildCyan.opacity(0.9) : buildCell))
            .contentShape(Rectangle()).onTapGesture(perform: action)
    }
    @ViewBuilder private func buildGridSelCell(_ i: Int, w: CGFloat, h: CGFloat) -> some View {
        let present = buildGridSelPresent(i)
        let hue = Color(hex: buildGridSelCellHex(i))
        let sel = buildGridSelSel == i
        ZStack {
            RoundedRectangle(cornerRadius: 6).fill(present ? hue.opacity(sel ? 0.85 : 0.42) : Color.white.opacity(0.03))
            if present {   // EVERY present cell wears its chain's notes drifting right→left (like the part/play grid) — the active one brighter, over its live roll
                buildGridSelDriftFace(sel ? buildGridSelActiveRoll : (buildGridSelCellRoll[i] ?? []), animated: sel).padding(3).opacity(sel ? 1.0 : 0.7)   // DSP: only the SELECTED cell drifts; the other 63 draw static (no 64× animation) (2026-08-28)
            }
            if sel {       // THE ACTIVE CELL — a breathing live frame
                TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: animationsPaused)) { tl in
                    let f = stagingPulseFraction(tl.date, period: 0.9)
                    RoundedRectangle(cornerRadius: 6).stroke(Color.white.opacity(0.45 + 0.5 * f), lineWidth: 3)
                }
            }
        }
        .frame(width: w, height: h)
        .contentShape(Rectangle())
        .onTapGesture { if present { buildGridSelAudition(i) } }
    }
    // THE DRIFTING NOTE FACE (Paul 2026-08-26): notes scroll RIGHT→LEFT, looping — the same aesthetic as the part/play grid
    // cells (buildNoteSweep). Every present cell + row selector wears its chain's fingerprint drifting across it (a browse
    // preview: you can't run 64 live voices, so each cell loops its chain's note pattern). Opacity by velocity.
    @ViewBuilder private func buildGridSelDriftFace(_ bars: [GridSelBar], animated: Bool, period: Double = 2.4) -> some View {
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
                        ctx.fill(Path(roundedRect: rect, cornerRadius: barH / 2), with: .color(.white.opacity(0.3 + 0.5 * b.vel)))
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
    // §3.3 THE BROWSE CONTEXT (Paul 2026-08-25): the panel REUSES the main-page left-column objects — the MIDI IN
    // (receiver) selector · the MIDI CHAIN processor boxes · the MIDI OUT (emitter) toggles — so the grid selector reads
    // and edits identically to BUILD (the audition rides the transient gsAud colour, so these show/edit its machine + I/O).
    @ViewBuilder private func buildGridSelRightColumn(width: CGFloat) -> some View {
        let loaded = buildColourReg[buildGridSelAudID] != nil            // a chain is loaded — from a CELL tap OR a ROW press (Paul 2026-08-26)
        let castW = width - 2
        VStack(alignment: .center, spacing: 10) {
            Text("THE MACHINE  ·  tap a cell or a row").font(.system(size: 9, weight: .heavy, design: .monospaced)).tracking(0.6).foregroundColor(buildDim).frame(width: castW, alignment: .leading)
            if loaded {
                buildColumnButton("PLAY THIS MIDI CHAIN", active: buildDisplayVoice == .chain, fill: .grid,   // ABOVE the receivers (Paul 2026-08-26) — the header for the whole machine
                                  action: { buildRequestWorkshopVoice(buildDisplayVoice == .chain ? .none : .chain) }).frame(width: castW)
                buildReceiverSelector(castW: castW)                      // MIDI IN — reused from the main page
                buildProcessorBlock(castW: castW, cell: 14)              // the MIDI CHAIN boxes — reused
                buildEmitterToggles(castW: castW).padding(.top, 8)       // MIDI OUT — reused
                Text(d.playing ? "playing against your input" : "press ▶ play to hear it sweep")
                    .font(.system(size: 9, weight: .medium, design: .monospaced)).foregroundColor(d.playing ? buildDim : buildCyan.opacity(0.8))
                if buildGridSelSel != nil {                              // a browse cell is auditioning → the hold-to-stamp hint
                    Text("HOLD a row to stamp this chain onto that part (keeps the part's colour)").font(.system(size: 9, weight: .medium, design: .monospaced)).foregroundColor(buildCyan.opacity(0.8)).fixedSize(horizontal: false, vertical: true).frame(width: castW, alignment: .leading)
                }
            } else {
                Text("tap a cell to hear its chain, or a\nrow to load that part's chain").font(.system(size: 11, weight: .medium, design: .monospaced))
                    .foregroundColor(buildDim).fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }.frame(width: width, alignment: .center)
    }
    // A row chip = a PART (the destination). OCCUPIED shows its hue, EMPTY is hollow; the AIMED part wears a white ring.
    @ViewBuilder private func buildGridSelRowChip(_ n: Int, height: CGFloat = 28) -> some View {
        let cid = buildRowColour(n)
        let tint = cid.flatMap { colourColor($0) }
        let aimed = buildGridSelArrivalRow == n
        RoundedRectangle(cornerRadius: 5).fill(aimed ? (tint ?? buildCyan) : (cid != nil ? (tint ?? buildRowButtonFill).opacity(0.4) : buildRowButtonFill))
            .frame(height: height)
            .overlay { if cid != nil { buildGridSelDriftFace(buildGridSelRowRoll[n] ?? [], animated: false).padding(2).opacity(0.65) } }   // DSP: static fingerprint (no per-slot animation)
            .overlay(alignment: .bottom) { buildGridSelStampSweep(n, height: height) }   // HOLD-TO-STAMP: the rising white fill + post-commit flash
            .clipShape(RoundedRectangle(cornerRadius: 5))
            .overlay(RoundedRectangle(cornerRadius: 5).stroke(aimed ? Color.white : (tint ?? buildEdge), lineWidth: aimed ? 2 : 1))
            .overlay { if cid == nil { RoundedRectangle(cornerRadius: 5).stroke(style: StrokeStyle(lineWidth: 1, dash: [3, 2])).foregroundColor(buildEdge) } }
            .overlay(Text("\(n + 1)").font(.system(size: min(13, height * 0.4), weight: .heavy, design: .monospaced)).foregroundColor(aimed ? .black.opacity(0.75) : (tint ?? .white.opacity(0.7))))
            .contentShape(Rectangle())
            .onTapGesture { buildGridSelAimRow(n) }                       // TAP = aim + load that part's chain
            // HOLD = stamp the auditioning chain onto this part, KEEP its colour, keep the browser open (Paul 2026-08-26).
            .onLongPressGesture(minimumDuration: buildGridSelStampDur, maximumDistance: 44,
                                pressing: { p in buildGridSelStampPressing(n, p) }, perform: { buildGridSelStampFire(n) })
    }
    private var buildGridSelStampDur: Double { 0.65 }
    private func buildGridSelStampPressing(_ n: Int, _ pressing: Bool) {
        if pressing {
            if buildGridSelCanStamp { buildGridSelStampRow = n; buildGridSelStampAt = Date() }
        } else if buildGridSelStampRow == n {                            // released before completion → cancel the rising fill
            buildGridSelStampRow = nil; buildGridSelStampAt = nil
        }
    }
    private func buildGridSelStampFire(_ n: Int) {
        guard buildGridSelCanStamp else { return }
        buildGridSelStampRow = nil; buildGridSelStampAt = nil            // hand the rising fill over to the confirm flash
        buildGridSelStampCommit(n)
    }
    // The rising WHITE fill while a row is held (fraction = elapsed / stampDur), then a full-white → fade CONFIRM once stamped.
    @ViewBuilder private func buildGridSelStampSweep(_ n: Int, height: CGFloat) -> some View {
        if buildGridSelStampRow == n, let start = buildGridSelStampAt {
            TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: animationsPaused)) { tl in
                let f = min(1.0, max(0.0, tl.date.timeIntervalSince(start) / buildGridSelStampDur))
                Rectangle().fill(Color.white.opacity(0.9)).frame(height: max(0, height * CGFloat(f)))
            }
        } else if buildGridSelStampFlashRow == n, let fs = buildGridSelStampFlashAt {
            TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: animationsPaused)) { tl in
                let a = max(0.0, 0.9 * (1 - tl.date.timeIntervalSince(fs) / 0.5))   // full white → clear over ~0.5s
                Rectangle().fill(Color.white.opacity(a))
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
            buildGridSelLoadChain(buildColourChain(cid), transpose: buildColourTranspose[cid] ?? 0, hex: buildBaseHex(cid), sel: nil)
        } else {
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
