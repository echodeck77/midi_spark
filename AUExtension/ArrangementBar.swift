import SwiftUI

/// §2 THE ARRANGEMENT BAR — the header IS the arrangement: LOGO · the 8 scene chips · ⚙, one row (the old
/// header + scene strip merged; the reclaimed row goes to the grid). PIN: the LOGO yields (compressed to the
/// "8×8" mark), never the chips; the chips flex to fill. The ⚙ BECOMES the red trash can during a scene drag.
///
/// Extracted from AudioUnitViewController (churn-reduction pass) so its ~8 pieces of interactive state + the
/// tap/drag/sweep logic live in one cohesive place. The VC still owns the 4 Hz poll and the grid's scene/
/// colours: it passes the polled `sceneEmpty`/`activeSceneIdx` DOWN and gets `onSceneOpDone` back after any op.
///
/// The bar hosts the prominent PERFORM/EDIT toggle (`modeToggle`) + undo/redo, and is now rendered at the top of
/// BOTH the perform page and the edit page — one consistent header/scenes surface. The toggle replaces the old
/// verbs-box EDIT button and the edit page's DONE close button.
struct ArrangementBar: View {
    @Environment(\.animationsPaused) private var animPaused
    let au: MidiSparkAudioUnit?
    let d: KernelDiag                       // the VC's polled diagnostics (playing/pass/beat/tempo)
    let stepBeats: Double
    let sceneEmpty: [Bool]                  // polled by the VC, passed down (per-slot occupancy)
    let activeSceneIdx: Int                 // polled by the VC, passed down (the playing scene)
    let onSecretTap: () -> Void             // dev: a long-press on the logotype reveals the T-session loader
    let onOpenSettings: () -> Void          // the ⚙ → the cog page (rendered at the VC's top level; full-screen)
    let onRevertLiveFlips: () -> Void       // re-cue reverts the live ON-TAP flips (VC's clearOnTap)
    let onSceneOpDone: () -> Void           // after any op the VC re-polls sceneEmpty/activeSceneIdx + refreshes the grid
    var currentPreset: String = ""          // §3 PRESETS: the loaded preset's name ("" = unsaved)
    var onOpenPresets: () -> Void = {}       // the folder button → the preset browser (rendered at the VC top level)
    var canUndo: Bool = false               // /btw ②: UNDO/REDO beside the preset selector, dimmed when unavailable
    var canRedo: Bool = false
    var onUndo: () -> Void = {}
    var onRedo: () -> Void = {}
    var isEditMode: Bool = false            // the prominent PERFORM/EDIT toggle — reflected on BOTH pages (shared bar)
    var onSetEditMode: (Bool) -> Void = { _ in }
    var showScenes: Bool = true             // the 16-scene row is HIDDEN by default; toggled on the cog page (user 2026-08-03)
    var onOpenManual: () -> Void = {}        // the "?" → the in-app manual, scrolled to the last-touched control

    // The bar's own interactive/derived state (was 8 @State vars scattered in the VC).
    @State private var pendingScene: Int? = nil       // armed switch (fires at the next pass start)
    @State private var pendingRecue = false           // tap the ACTIVE chip: armed re-cue of the saved scene at next pass
    @State private var sceneBlink = false             // pending-chip blink (toggled while playing)
    @State private var beatSampledAt = Date()         // when d.beat was last seen — extrapolates the chip pass-sweep
    @State private var dragSceneSrc: Int? = nil       // the lifted chip mid-drag
    @State private var dragSceneTarget: Int? = nil    // chip under the finger (drop = MOVE/SWAP)
    @State private var dragOverTrash = false          // finger dragged onto the ⚙/can = TRASH
    @State private var sceneShakeX: CGFloat = 0       // the active-refuses-trash shake offset

    private let sceneAmber = Color(red: 0.98, green: 0.72, blue: 0.12)
    private let barCyan = Color(red: 0.15, green: 0.88, blue: 0.94)
    private let editHue = Color(red: 0.95, green: 0.47, blue: 0.85)   // orchid — the EDIT segment (matches DiagView.editHue)
    private let sceneStripSpace = "sceneStripRow"     // one name for the chip-row coordinate space + its drag gesture

    var body: some View {
        VStack(spacing: 6) {                                 // the MAIN HEADER, then the SCENE row on its own line below
            HStack(alignment: .center, spacing: 8) {
                Text("8×8").font(.system(size: 12, weight: .heavy, design: .monospaced)).tracking(2)
                    .foregroundColor(.white.opacity(0.85)).fixedSize()
                    .onLongPressGesture(minimumDuration: 1.2) { onSecretTap() }   // dev: reveal the T-session loader
                    .helpAnchor("#logo")
                presetButton.helpAnchor("#presets-open")                           // §3 PRESETS: right of the logo (user 2026-08-03)
                modeToggle.helpAnchor("#perform-edit-toggle")                      // PERFORM/EDIT toggle: right of the preset button
                Spacer(minLength: 8)                                               // the chips moved down → the cog trails the header
                if d.playing {
                    Text(String(format: "P%d·%.0f", d.pass + 1, d.tempo))
                        .font(.system(size: 9, weight: .heavy, design: .monospaced)).foregroundColor(barCyan).fixedSize()
                        .helpAnchor("#transport-readout")
                }
                undoRedo.helpAnchor("#undo")                                       // labelled UNDO/REDO, moved to the right (user 2026-08-03)
                helpButton                                                         // "?" → the in-app manual at the last-touched control
                cogOrCan.helpAnchor("#cog-open")                                    // ⚙ ⇄ 🗑 (the can in place during a drag)
            }
            if showScenes { sceneChipRow }                                          // THE 16 SCENE CHIPS — hidden by default; toggled on the cog
        }
        .offset(x: sceneShakeX)                              // shake when the active scene refuses the trash
        .background(sceneArmWatcher)                         // S2c: tight commit at the pass boundary (~1 render window)
        .onChange(of: d.pass) { _ in commitArmedScene() }   // 4 Hz fallback (e.g. backgrounded, watcher paused)
        .onChange(of: d.beat) { _ in                        // moved from the VC poll: re-anchor the sweep + drive the blink
            beatSampledAt = Date()
            if pendingScene != nil || pendingRecue { sceneBlink.toggle() } else if sceneBlink { sceneBlink = false }
        }
    }

    // THE PERFORM/EDIT TOGGLE — a prominent two-segment control, present on BOTH pages (the shared bar). PERFORM
    // lights cyan, EDIT lights orchid. Replaces the verbs-box EDIT button + the edit page's DONE close button.
    private var modeToggle: some View {
        HStack(spacing: 0) {
            modeSeg("PERFORM", active: !isEditMode, hue: barCyan)
            modeSeg("EDIT", active: isEditMode, hue: editHue)
        }
        .padding(2)
        .background(RoundedRectangle(cornerRadius: 8).fill(Color.white.opacity(0.06)))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.white.opacity(0.10), lineWidth: 1))
        .fixedSize()
    }
    private func modeSeg(_ label: String, active: Bool, hue: Color) -> some View {
        Text(label).font(.system(size: 12, weight: .heavy, design: .monospaced)).tracking(1)
            .foregroundColor(active ? .black : .white.opacity(0.55))
            .padding(.horizontal, 13).padding(.vertical, 6)
            .background(RoundedRectangle(cornerRadius: 6).fill(active ? hue : Color.clear))
            .contentShape(Rectangle())
            .onTapGesture { onSetEditMode(label == "EDIT") }
    }

    // §3 the preset selector: a folder + the loaded preset's name (or "PRESETS"); tap → the browser sheet.
    // /btw ②: ENLARGED — bigger type + hit target (it's a headline control, not a footnote).
    private var presetButton: some View {
        HStack(spacing: 5) {
            Image(systemName: "folder.fill").font(.system(size: 11))
            Text(currentPreset.isEmpty ? "PRESETS" : currentPreset)
                .font(.system(size: 11, weight: .heavy, design: .monospaced)).lineLimit(1).truncationMode(.tail)
        }
        .foregroundColor(.white.opacity(0.78))
        .padding(.horizontal, 10).padding(.vertical, 6)
        .background(RoundedRectangle(cornerRadius: 5).fill(Color.white.opacity(0.09)))
        .frame(maxWidth: 150).fixedSize(horizontal: true, vertical: false)
        .contentShape(Rectangle()).onTapGesture { onOpenPresets() }
    }
    // UNDO / REDO — LABELLED, on the right of the header (user 2026-08-03). Dimmed + inert when unavailable.
    private var undoRedo: some View {
        HStack(spacing: 4) {
            undoRedoBtn("UNDO", "arrow.uturn.backward", on: canUndo, action: onUndo)
            undoRedoBtn("REDO", "arrow.uturn.forward", on: canRedo, action: onRedo)
        }
    }
    private func undoRedoBtn(_ label: String, _ symbol: String, on: Bool, action: @escaping () -> Void) -> some View {
        HStack(spacing: 3) {
            Image(systemName: symbol).font(.system(size: 10, weight: .heavy))
            Text(label).font(.system(size: 9, weight: .heavy, design: .monospaced))
        }
        .foregroundColor(.white.opacity(on ? 0.82 : 0.22))
        .padding(.horizontal, 7).frame(height: 26)
        .background(RoundedRectangle(cornerRadius: 4).fill(Color.white.opacity(on ? 0.08 : 0.03)))
        .contentShape(Rectangle()).onTapGesture { if on { action() } }
    }
    private var sceneChipRow: some View {
        GeometryReader { geo in
            let chipW = geo.size.width / CGFloat(PluginState.maxScenes)
            HStack(spacing: 4) {
                ForEach(0..<PluginState.maxScenes, id: \.self) { i in sceneChip(i, chipW: chipW, rowWidth: geo.size.width) }
            }
            .coordinateSpace(name: sceneStripSpace)
        }
        .frame(height: 26).frame(minWidth: 180)             // the chips keep a usable floor; the logo yields, not them
    }
    // §2/§7b the ⚙ BECOMES the red can during a scene drag (one corner, one identity — never a floating can beside
    // settings; reverts on drag-end). Otherwise it opens the cog page. Drag a chip onto it (x past the strip) to trash.
    private var cogOrCan: some View {
        Group {
            if dragSceneSrc != nil {
                Image(systemName: "trash.fill").font(.system(size: 13, weight: .bold))
                    .foregroundColor(dragOverTrash ? Color(red: 0.98, green: 0.32, blue: 0.28) : .white.opacity(0.5))
                    .scaleEffect(dragOverTrash ? 1.3 : 1)
                    .animation(.easeOut(duration: 0.12), value: dragOverTrash)
            } else {
                Image(systemName: "gearshape.fill").font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.white.opacity(0.6))
                    .onTapGesture { onOpenSettings() }
            }
        }
        .frame(width: 34, height: 26).contentShape(Rectangle())
    }
    // "?" — opens the in-app manual scrolled to whatever control you last touched.
    private var helpButton: some View {
        Image(systemName: "questionmark.circle").font(.system(size: 15, weight: .semibold))
            .foregroundColor(.white.opacity(0.6))
            .frame(width: 30, height: 26).contentShape(Rectangle())
            .onTapGesture { onOpenManual() }
    }
    private func sceneChip(_ i: Int, chipW: CGFloat, rowWidth: CGFloat) -> some View {
        let empty = i >= sceneEmpty.count || sceneEmpty[i]
        let active = i == activeSceneIdx && !empty
        let pending = (i == pendingScene || (pendingRecue && i == activeSceneIdx)) && !empty
        let lifted = i == dragSceneSrc
        let target = i == dragSceneTarget
        return Text(empty ? "+" : "\(i + 1)").font(.system(size: 11, weight: .heavy, design: .monospaced))
            .foregroundColor(active ? .black : (empty ? .white.opacity(0.3) : .white.opacity(0.8)))
            .frame(maxWidth: .infinity).frame(height: 26)
            .background(RoundedRectangle(cornerRadius: 4).fill(active ? sceneAmber : Color.white.opacity(empty ? 0.03 : 0.08)))
            .overlay { if active { passSweepOverlay } }         // S3: the active chip wears the pass-sweep
            .overlay(RoundedRectangle(cornerRadius: 4)          // PENDING blink (black on the amber active chip, else amber) · drop TARGET = white
                .stroke(target ? Color.white.opacity(0.9)
                        : (active ? Color.black : sceneAmber).opacity(pending ? (sceneBlink ? 0.95 : 0.25) : 0),
                        lineWidth: target ? 2 : 1.5))
            .scaleEffect(lifted ? 1.12 : 1)
            .shadow(color: .black.opacity(lifted ? 0.5 : 0), radius: lifted ? 4 : 0, y: lifted ? 2 : 0)
            .zIndex(lifted ? 1 : 0)
            .contentShape(Rectangle())
            .onTapGesture(count: 2) { doubleTapScene(i) }
            .onTapGesture { tapScene(i) }
            .gesture(sceneDragGesture(source: i, chipW: chipW, rowWidth: rowWidth))
    }
    // S3: the active chip's pass-sweep — a 2pt mini-playhead crossing L→R once per pass, extrapolated between
    // the 4 Hz polls (one-clock, same liveBeat idea as the cell mutation lines). Present only while playing.
    @ViewBuilder private var passSweepOverlay: some View {
        if d.playing {
            GeometryReader { g in
                TimelineView(.animation(minimumInterval: nil, paused: animPaused)) { tl in
                    Rectangle().fill(Color.black.opacity(0.5)).frame(width: 2)
                        .position(x: max(1, min(g.size.width - 1, CGFloat(passFraction(tl.date)) * g.size.width)),
                                  y: g.size.height / 2)
                }
            }
            .allowsHitTesting(false)
        }
    }
    private func passFraction(_ now: Date) -> Double {
        let cyc = 8.0 * stepBeats; guard cyc > 0 else { return 0 }
        let lb = d.beat + now.timeIntervalSince(beatSampledAt) * d.tempo / 60.0
        let m = lb.truncatingRemainder(dividingBy: cyc)
        return (m < 0 ? m + cyc : m) / cyc
    }
    // S3/AB: long-press a chip to LIFT it, then drag — sideways to another chip = MOVE (onto +) / SWAP (onto a
    // scene); onto the ⚙-turned-can (x past the strip's end) OR down out of the row = TRASH. Never overwrites;
    // the active scene refuses. The can lives where the cog is (§2), so dragging a chip toward it reads as trash.
    private func sceneDragGesture(source i: Int, chipW: CGFloat, rowWidth: CGFloat) -> some Gesture {
        LongPressGesture(minimumDuration: 0.3)
            .sequenced(before: DragGesture(minimumDistance: 0, coordinateSpace: .named(sceneStripSpace)))
            .onChanged { value in
                guard case .second(true, let drag?) = value else { return }
                if dragSceneSrc == nil {
                    guard i < sceneEmpty.count, !sceneEmpty[i] else { return }   // only real scenes lift (not a +)
                    dragSceneSrc = i
                }
                let toTrash = drag.location.x > rowWidth || drag.location.y > 44   // past the strip → the cog/can
                dragOverTrash = toTrash
                if toTrash { dragSceneTarget = nil }
                else {
                    let t = max(0, min(PluginState.maxScenes - 1, Int(drag.location.x / max(1, chipW))))
                    dragSceneTarget = (t == dragSceneSrc) ? nil : t
                }
            }
            .onEnded { _ in resolveSceneDrag() }
    }
    private func resolveSceneDrag() {
        defer { dragSceneSrc = nil; dragSceneTarget = nil; dragOverTrash = false }
        guard let au, let src = dragSceneSrc else { return }
        if dragOverTrash {
            if au.deleteScene(src) { onSceneOpDone() } else { refuseTrashShake() }   // active refused
        } else if let t = dragSceneTarget, t != src {
            au.moveOrSwapScene(from: src, to: t); onSceneOpDone()
        }
    }
    private func refuseTrashShake() {
        withAnimation(.linear(duration: 0.05).repeatCount(5, autoreverses: true)) { sceneShakeX = 5 }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { sceneShakeX = 0 }
    }
    // S2c: while a switch is ARMED, poll the ENGINE's live pass at display rate and commit on the boundary —
    // ~1 render window (≈40ms) vs the 4 Hz poll's ~250ms, which fixes the scene-start dropout (bug 4a). Present
    // only when armed (no churn otherwise; obeys the coming invisible=frozen rule since it's a TimelineView).
    @ViewBuilder private var sceneArmWatcher: some View {
        if pendingScene != nil || pendingRecue {
            TimelineView(.animation(minimumInterval: nil, paused: animPaused)) { _ in
                let livePass = au?.uiPass() ?? 0
                Color.clear.onChange(of: livePass) { _ in commitArmedScene() }
            }
        }
    }
    // Single tap: empty → SAVE-HERE · the active chip → re-cue the SAVED scene at the next pass · pending → CANCEL
    // · another non-empty → ARM (immediate if stopped).
    private func tapScene(_ i: Int) {
        guard let au else { return }
        if i >= sceneEmpty.count || sceneEmpty[i] { au.saveSceneHere(i); onSceneOpDone(); return }
        if i == activeSceneIdx {                          // the ACTIVE chip: re-cue the SAVED scene at the next pass
            if pendingRecue { pendingRecue = false; return }   // tap again = CANCEL the armed re-cue
            if d.playing { pendingRecue = true }               // ARM: revert live flips + play from the top at the next pass
            else { onRevertLiveFlips(); onSceneOpDone() }      // stopped ⇒ no pass to wait for; just drop the live flips
            return
        }
        if i == pendingScene { pendingScene = nil; return }   // CANCEL the arm
        if d.playing { pendingScene = i }                 // ARM — fires at the next pass start
        else { au.setActiveScene(i); pendingScene = nil; onSceneOpDone() }   // stopped ⇒ no pass to wait for
    }
    // Double tap: another non-empty chip = IMMEDIATE switch; the ACTIVE chip = re-cue the saved scene NOW.
    private func doubleTapScene(_ i: Int) {
        guard let au, !(i >= sceneEmpty.count || sceneEmpty[i]) else { return }
        if i == activeSceneIdx { pendingRecue = false; onRevertLiveFlips(); au.restartPass(); return }   // NOW: from the top, flips reverted
        au.setActiveScene(i); pendingScene = nil; onSceneOpDone()
    }
    private func commitArmedScene() {
        guard let au else { return }
        if pendingRecue {                                 // re-cue the saved scene from the top (live flips reverted, voices flushed)
            onRevertLiveFlips(); au.restartPass(); pendingRecue = false
        }
        if let p = pendingScene { au.setActiveScene(p); pendingScene = nil; onSceneOpDone() }
    }
}
