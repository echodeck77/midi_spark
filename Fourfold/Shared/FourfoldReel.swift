//  FourfoldReel.swift
//  FOURFOLD Step 2 (2026-10-23, Docs/standalone-plan.md): the REEL pass browser as a standalone view. Converted from BuildReel.swift (an `extension DiagView` that needed 19 reel @State vars and the
//  8x8 host's 4 Hz poll) so Fourfold has no dependency on the 8x8 host: it owns its state, polls the AU itself while it is open, and shows the share sheet itself.
//  Fourfold differences from the 8x8 browser: the sidebar says "port" (Riff A … Notes D, `FourfoldPorts`) and shows `1 PASS = n BEATS` instead of RESTORE SETUP (that re-deploys an 8×8 play-grid scene; Fourfold has none).
//  Everything the browser reads comes from the AU's reel API (`reelPassNumbers`, `reelSelectedRoll`, `reelExportRangeFiles`…), shared with the 8x8 browser, so pass filing / replay / export behave identically.

import SwiftUI
import UIKit

// The 8x8 browser's own chrome colours (BuildPage.swift's `buildCyan` / `buildDim` / `buildCell` / `buildEdge`), copied so Fourfold does not compile BuildPage.
private let ffCyan = Color(red: 0.19, green: 0.83, blue: 0.91)
private let ffDim = Color(white: 0.36)
private let ffCell = Color(red: 0.10, green: 0.12, blue: 0.15)
private let ffEdge = Color(white: 1).opacity(0.17)

/// A share sheet for the REEL-TO-REEL export (SMF files).
struct FourfoldShareSheet: UIViewControllerRepresentable {
    let urls: [URL]
    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: urls, applicationActivities: nil)
    }
    func updateUIViewController(_ vc: UIActivityViewController, context: Context) {}
}

struct FourfoldReelBrowser: View {
    weak var au: FourfoldAudioUnit?
    let size: CGSize
    /// The host transport (the root view's polled diagnostics): drives the replay playhead's extrapolation.
    let playing: Bool
    let tempo: Double
    let onClose: () -> Void

    @State var reelState: Int = 0                        // 0 off · 1 armed · 2 replaying (polled)
    @State var reelShareURLs: [URL] = []                 // EXPORT: the written SMF files to share
    @State var reelShowShare = false
    @State var reelPassNumbers: [Int] = []               // the 64 ring slots, oldest→newest
    @State var reelRoll: [ReelDeck.Note] = []            // the selected pass's notes (cables 1…8: a lane's riff and its notes share a roll row)
    @State var reelSelPassNo: Int = -1                   // the currently selected/playing pass (−1 = auto latest)
    @State var reelCycle: Double = 4                     // the pass length in beats (piano-roll x-axis)
    @State var reelLastBeat: Double = 0                  // last polled beat + its wall-clock stamp → smooth roll playhead
    @State var reelLastBeatAt = Date()
    @State var reelPassSigs: [UInt64] = []               // per-pass content hashes → REMOVE DUPLICATES
    @State var reelDedup = false
    @State var reelPage = Int.max                        // clamped to the last page = newest → opens on newest
    @State var reelSelLoPass = -1                        // MULTI-PASS EXPORT: a pass RANGE [lo,hi] (◀/▶ extend)
    @State var reelSelHiPass = -1
    @State var reelRangeCyc: Double = 0                  // the concatenated range length in beats (0 ⇒ single pass, use reelCycle)
    @State var reelExportPorts: Set<Int> = []            // selected ports, bit index 0…7 (Riff A, Notes A … Notes D); empty ⇒ export the MASTER (the eight ports summed)

    private let poll = Timer.publish(every: 0.25, on: .main, in: .common).autoconnect()

    static let laneHues: [Color] = [Color(red: 0.19, green: 0.83, blue: 0.91),   // A cyan
                                    Color(red: 0.36, green: 0.92, blue: 0.52),   // B green
                                    Color(red: 1.0,  green: 0.72, blue: 0.2),    // C amber
                                    Color(red: 0.85, green: 0.5,  blue: 0.95)]   // D violet
    /// The same hues lightened, for a lane's NOTES layer — it shares the lane's roll row with the riff.
    static let notesHues: [Color] = [Color(red: 0.62, green: 0.93, blue: 0.97), Color(red: 0.68, green: 0.97, blue: 0.78),
                                     Color(red: 1.0, green: 0.86, blue: 0.58), Color(red: 0.93, green: 0.74, blue: 0.98)]

    /// The 4 Hz refresh the 8x8 host's poll did while its pop-up was open: the ring, the selected roll, the pass length, the beat stamp.
    private func refresh() {
        guard let au else { return }
        let rs = au.uiReelState(); if rs != reelState { reelState = rs }
        let pn = au.reelPassNumbers();     if pn != reelPassNumbers { reelPassNumbers = pn }
        let ps = au.reelPassSignatures();  if ps != reelPassSigs { reelPassSigs = ps }   // REMOVE DUPLICATES
        if reelRangeCyc <= 0 { let rr = au.reelSelectedRoll(); if rr != reelRoll { reelRoll = rr } }   // single pass → live roll; a multi-pass RANGE roll is set on selection
        let sp = au.reelSelectedPassNo();  if sp != reelSelPassNo { reelSelPassNo = sp }
        let cy = au.reelCycleBeats();      if cy != reelCycle { reelCycle = cy }
        let beat = au.kernelDiagnostics().beat
        if beat != reelLastBeat { reelLastBeat = beat; reelLastBeatAt = Date() }   // stamp for the smooth roll playhead
    }

    // THE PASS BROWSER (Paul 2026-08-26 redesign): the whole thing reads as ONE 8×8 grid — the recorded PASSES fill the
    // top 4 rows (uniform SQUARE cells), the four A/B/C/D MIDI lanes fill the bottom 4 rows (each the full grid width, one
    // cell tall). The page header + instructions + controls live in a COLUMN on the RIGHT (was a banner above). PREV/NEXT
    // PAGINATE the pass block; REMOVE DUPLICATES collapses runs of identical passes.
    var body: some View {
        let outerPad: CGFloat = 16, gap: CGFloat = 3, sidebarW: CGFloat = 234, colGap: CGFloat = 18
        let areaW = size.width - 2 * outerPad - sidebarW - colGap
        let areaH = size.height - 2 * outerPad
        let cellSize = max(14, min((areaW - 7 * gap) / 8, (areaH - 7 * gap) / 8))   // one SQUARE cell → a uniform 8×8
        let gridSide = 8 * cellSize + 7 * gap
        let visible = reelVisiblePasses()                                   // non-empty (+ deduped if toggled), in ring order
        let pageCount = max(1, (visible.count + 31) / 32)
        let page = min(max(0, reelPage), pageCount - 1)
        let pageSlice = Array(visible.dropFirst(page * 32).prefix(32))           // this page's ≤32 passes → the 4×8 block
        return ZStack {
            Color(red: 0.055, green: 0.065, blue: 0.085).ignoresSafeArea()      // FULL-SCREEN opaque backdrop
            if size.width <= size.height {                                      // PORTRAIT — the pass browser is a LANDSCAPE-ONLY view; prompt to rotate rather than cram the landscape block into a tall window
                reelRotatePrompt()
            } else {
                HStack(alignment: .top, spacing: colGap) {
                    VStack(spacing: gap) {                                      // LEFT — the 8×8 grid
                        ForEach(0..<4, id: \.self) { r in                      // TOP 4 rows — the passes (this page)
                            HStack(spacing: gap) {
                                ForEach(0..<8, id: \.self) { c in
                                    let idx = r * 8 + c
                                    reelPassCell(idx < pageSlice.count ? pageSlice[idx] : -1, w: cellSize, h: cellSize)
                                }
                            }
                        }
                        reelRollSection(width: gridSide, laneH: cellSize, gap: gap)   // BOTTOM 4 rows — A/B/C/D lanes + playhead
                    }.frame(width: gridSide, height: gridSide)
                    reelSidebar(pageCount: pageCount, page: page)          // RIGHT — header · instructions · controls
                        .frame(width: sidebarW, height: gridSide, alignment: .top)
                }
            }
        }
        .onAppear {
            au?.reelSetBrowsing(true)                                             // freeze the history tape while browsing
            refresh()
            reelPage = Int.max                                                    // OPEN ON THE NEWEST PAGE (clamped to the last page) — Paul 2026-08-26
            reelSelLoPass = -1; reelSelHiPass = -1; reelRangeCyc = 0              // fresh selection (the anchor = the auto-latest pass)
            reelExportPorts = []                                                  // start exporting the master mix
        }
        .onDisappear { au?.reelStopReplay(); au?.reelSetBrowsing(false) }         // close → stop any replay + resume normal play, record again next pass
        .onReceive(poll) { _ in refresh() }
        .sheet(isPresented: $reelShowShare) { FourfoldShareSheet(urls: reelShareURLs) }
    }
    // PORTRAIT fallback (Paul 2026-08-26): the pass browser is a landscape-only view; in a tall window, prompt to rotate.
    @ViewBuilder private func reelRotatePrompt() -> some View {
        VStack(spacing: 16) {
            Image(systemName: "arrow.clockwise").font(.system(size: 40, weight: .light)).foregroundColor(ffCyan)
            Text("ROTATE TO LANDSCAPE").font(.system(size: 15, weight: .heavy, design: .monospaced)).tracking(2).foregroundColor(.white.opacity(0.85))
            Text("The pass browser is a landscape view.").font(.system(size: 12, weight: .medium)).foregroundColor(.white.opacity(0.5))
            Button { onClose() } label: {
                Text("CLOSE").font(.system(size: 11, weight: .heavy, design: .monospaced)).tracking(1).foregroundColor(ffDim)
                    .padding(.horizontal, 24).padding(.vertical, 10)
                    .background(RoundedRectangle(cornerRadius: 6).fill(ffCell)).overlay(RoundedRectangle(cornerRadius: 6).stroke(ffEdge, lineWidth: 1))
            }.padding(.top, 6)
        }.padding(40)
    }
    // The passes to show: non-empty, in ring order; when REMOVE DUPLICATES is on, a pass whose content matches the last
    // KEPT pass is hidden (collapses a run — e.g. a held loop filing the same bar every pass). (Paul 2026-08-26)
    private func reelVisiblePasses() -> [Int] {
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
    @ViewBuilder private func reelSidebar(pageCount: Int, page: Int) -> some View {
        let anyPass = reelPassNumbers.contains { $0 >= 0 }
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 2) {
                Text("REEL").font(.system(size: 24, weight: .heavy, design: .monospaced)).tracking(3).foregroundColor(ffCyan)
                Text("PASS BROWSER").font(.system(size: 11, weight: .bold, design: .monospaced)).tracking(2).foregroundColor(ffDim)
            }
            Text(reelInstructionText(fourfold: true))
                .font(.system(size: 11, weight: .medium)).foregroundColor(.white.opacity(0.55)).fixedSize(horizontal: false, vertical: true)
            Rectangle().fill(ffEdge).frame(height: 1)
            let visible = reelVisiblePasses()
            let (rlo, rhi) = reelExportRange()
            let selLabel = rlo < 0 ? "—" : (rlo == rhi ? "PASS \(rlo + 1)" : "PASSES \(rlo + 1)–\(rhi + 1)")
            let laneLabel = reelExportPortsLabel(reelExportPorts)
            // PAGINATION — page the whole history (32 passes at a time), independent of the selection (Paul 2026-08-26).
            HStack(spacing: 8) {
                reelStepBtn(back: true, enabled: page > 0) { reelPage = max(0, page - 1) }
                VStack(spacing: 1) {
                    Text("PAGE").font(.system(size: 8, weight: .heavy, design: .monospaced)).tracking(1).foregroundColor(ffDim)
                    Text("\(page + 1)/\(pageCount)").font(.system(size: 11, weight: .heavy, design: .monospaced)).foregroundColor(.white.opacity(0.8))
                }.frame(maxWidth: .infinity)
                reelStepBtn(back: false, enabled: page < pageCount - 1) { reelPage = min(pageCount - 1, page + 1) }
            }
            // EXTEND — grow the SELECTION to the neighbouring recorded pass; the page follows so the new edge stays visible.
            HStack(spacing: 8) {
                reelStepBtn(back: true, enabled: rlo >= 0 && visible.contains { $0 < rlo }) { reelExtend(-1) }
                VStack(spacing: 1) {
                    Text("EXTEND").font(.system(size: 8, weight: .heavy, design: .monospaced)).tracking(1).foregroundColor(ffDim)
                    Text(selLabel).font(.system(size: 10, weight: .heavy, design: .monospaced)).foregroundColor(ffCyan).lineLimit(1).minimumScaleFactor(0.7)
                }.frame(maxWidth: .infinity)
                reelStepBtn(back: false, enabled: rhi >= 0 && visible.contains { $0 > rhi }) { reelExtend(1) }
            }
            reelToggle(label: "REMOVE DUPLICATES", on: reelDedup) { reelDedup.toggle(); reelPage = Int.max }
            Text(reelPassLengthText(beats: reelCycle))                                // 1 PASS = n BEATS (RESTORE SETUP re-deploys an 8×8 scene — Fourfold has none)
                .font(.system(size: 10, weight: .heavy, design: .monospaced)).tracking(0.5).foregroundColor(ffDim)
                .frame(maxWidth: .infinity, alignment: .leading)
            // REEL PHASE 0 (2026-10-25, REEL-1): the ring keeps only the newest 64 passes; say so instead of letting the oldest quietly vanish.
            if let dropped = reelDroppedPassesNotice(passNumbers: reelPassNumbers) {
                Text(dropped).font(.system(size: 10, weight: .semibold)).foregroundColor(Color(red: 1.0, green: 0.71, blue: 0.33)).fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            Spacer()
            // REEL PHASE 0 (REEL-6): SAVE used to do nothing, silently, with no selection or an empty output. It now says why it cannot.
            let avail = reelExportAvailability(anyPass: anyPass, selected: rlo >= 0, outputCounts: reelOutputCounts(), lanes: reelExportPorts)
            if let why = avail.reason {
                Text(why).font(.system(size: 11, weight: .medium)).foregroundColor(.white.opacity(0.6)).fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            Button { reelExport() } label: {                             // SAVE the pass RANGE × the port selection → share sheet
                Text(rlo >= 0 ? "SAVE \(selLabel) · \(laneLabel)" : "SAVE").font(.system(size: 10.5, weight: .heavy, design: .monospaced)).tracking(0.5).lineLimit(1).minimumScaleFactor(0.7)
                    .foregroundColor(avail.ok ? .black : ffDim).frame(maxWidth: .infinity).padding(.vertical, 10)
                    .background(RoundedRectangle(cornerRadius: 6).fill(avail.ok ? ffCyan.opacity(0.9) : ffCell))
                    .overlay(RoundedRectangle(cornerRadius: 6).stroke(avail.ok ? Color.clear : ffEdge, lineWidth: 1))
            }
            .disabled(!avail.ok)
            .accessibilityHint(avail.reason ?? "Writes the selected passes as MIDI files.")
            Button { onClose() } label: {
                Text("CLOSE").font(.system(size: 11, weight: .heavy, design: .monospaced)).tracking(1).foregroundColor(ffDim)
                    .frame(maxWidth: .infinity).padding(.vertical, 10)
                    .background(RoundedRectangle(cornerRadius: 6).fill(ffCell)).overlay(RoundedRectangle(cornerRadius: 6).stroke(ffEdge, lineWidth: 1))
            }
        }
    }
    private func reelToggle(label: String, on: Bool, _ act: @escaping () -> Void) -> some View {
        Button(action: act) {
            HStack(spacing: 8) {
                Image(systemName: on ? "checkmark.square.fill" : "square").font(.system(size: 14, weight: .bold)).foregroundColor(on ? ffCyan : ffDim)
                Text(label).font(.system(size: 10, weight: .heavy, design: .monospaced)).tracking(0.5).foregroundColor(on ? .white : ffDim)
                Spacer(minLength: 0)
            }.padding(.vertical, 8).padding(.horizontal, 9)
            .background(RoundedRectangle(cornerRadius: 6).fill(on ? ffCyan.opacity(0.12) : ffCell))
            .overlay(RoundedRectangle(cornerRadius: 6).stroke(on ? ffCyan.opacity(0.5) : ffEdge, lineWidth: 1))
        }
    }
    // A generic ◀/▶ chevron step button — shared by PAGINATION (page the history) and EXTEND (grow the selection); disabled at the ends.
    @ViewBuilder private func reelStepBtn(back: Bool, enabled: Bool, _ act: @escaping () -> Void) -> some View {
        Button(action: act) {
            Image(systemName: back ? "chevron.left" : "chevron.right").font(.system(size: 14, weight: .heavy))
                .foregroundColor(enabled ? ffCyan : ffDim).frame(width: 44, height: 30)
                .background(RoundedRectangle(cornerRadius: 6).fill(ffCell)).overlay(RoundedRectangle(cornerRadius: 6).stroke(ffEdge, lineWidth: 1))
        }.disabled(!enabled)
    }
    // The 4 piano-roll lanes (bottom 4 rows of the 8×8; each holds that lane's riff AND its notes) + a shared PLAYHEAD that sweeps while a pass replays. Each lane is
    // ONE grid-cell tall and the full grid width, laid out with the SAME gap as the pass rows so the whole page reads as a
    // uniform 8×8 (Paul 2026-08-26). Lanes do not collapse — all four always render.
    private func reelRollSection(width: CGFloat, laneH: CGFloat, gap: CGFloat) -> some View {
        let rollH = 4 * laneH + 3 * gap
        return TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: reelState != 2)) { tl in
            let phase = reelPlayheadPhase(tl.date)                                // 0…1 across the pass, or nil (not replaying)
            VStack(spacing: gap) {
                ForEach(0..<4, id: \.self) { lane in
                    reelLane(lane, width: width, height: laneH, phase: phase)
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
        let beat = playing ? reelLastBeat + now.timeIntervalSince(reelLastBeatAt) * tempo / 60.0 : reelLastBeat
        var p = beat.truncatingRemainder(dividingBy: reelCycle) / reelCycle
        if p < 0 { p += 1 }
        return p
    }
    // One pass cell. Populated → shows its 1-based pass number; the pinned/replaying pass lights cyan. Tap = select+replay,
    // or (if it's already the replaying pass) stop and resume live.
    @ViewBuilder private func reelPassCell(_ pass: Int, w: CGFloat, h: CGFloat) -> some View {
        let lo = min(reelSelLoPass, reelSelHiPass), hi = max(reelSelLoPass, reelSelHiPass)
        let inRange = pass >= 0 && reelSelLoPass >= 0 && pass >= lo && pass <= hi   // in the export/highlight range (Paul 2026-08-26)
        let anchor = pass >= 0 && pass == reelSelPassNo                            // the replaying/audition pass
        let lit = inRange || anchor
        let playing = anchor && reelState == 2
        RoundedRectangle(cornerRadius: 3)
            .fill(pass < 0 ? Color.white.opacity(0.03) : (lit ? ffCyan : Color.white.opacity(0.08)))
            .frame(width: w, height: h)
            .overlay(playing ? RoundedRectangle(cornerRadius: 3).stroke(Color(red: 0.36, green: 0.92, blue: 0.52), lineWidth: 2)
                             : (anchor && hi > lo ? RoundedRectangle(cornerRadius: 3).stroke(Color.white, lineWidth: 1.5) : nil))   // the anchor within a multi-pass range
            .overlay(pass >= 0 ? Text("\(pass + 1)").font(.system(size: min(15, min(w, h) * 0.42), weight: .heavy, design: .monospaced))
                        .foregroundColor(lit ? .black : ffCyan.opacity(0.9)) : nil)
            .contentShape(Rectangle())
            .onTapGesture {
                guard pass >= 0 else { return }
                if playing { au?.reelStopReplay() } else { reelSelectPass(pass) }
            }
    }
    // One lane's piano-roll row. Draws the selected pass's notes for BOTH of the lane's ports (cable 2·lane+1 = RIFF, 2·lane+2 = NOTES) over a reference grid: 8 CELL
    // dividers (vertical), OCTAVE dividers (horizontal at each C) with the C labelled on the left + right axis. Pitch is framed to whole octaves and shared across
    // all lanes; x = pass length; opacity = velocity; the playhead lights notes. The riff is the lane's colour, the notes a lighter shade of it.
    // Export: the two tags at the left toggle ONE port each; a tap anywhere else on the row toggles both.
    private func reelLane(_ lane: Int, width: CGFloat, height: CGFloat, phase: Double?) -> some View {
        let hue = Self.laneHues[lane], notesHue = Self.notesHues[lane]
        let riffBus = FourfoldPorts.bus(lane: lane, part: .riff), notesBus = FourfoldPorts.bus(lane: lane, part: .notes)
        let riffNotes = reelRoll.filter { Int($0.cable) == riffBus + 1 }
        let notesNotes = reelRoll.filter { Int($0.cable) == notesBus + 1 }
        let all = reelRoll.map { Int($0.note) }
        let rawLo = all.min() ?? 48, rawHi = all.max() ?? 72
        let lo = (rawLo / 12) * 12, hi = max(lo + 12, ((rawHi + 11) / 12) * 12)   // frame to whole octaves → a C at top + bottom
        let span = CGFloat(hi - lo)
        let cyc = max(0.0001, reelEffCycle)                                      // the range total (multi-pass) or the single pass length
        let riffSelected = reelExportPorts.contains(riffBus), notesSelected = reelExportPorts.contains(notesBus)   // this port is in the export selection
        let head = phase.map { $0 * cyc }                                        // the playhead's beat, or nil
        func yOf(_ note: Int) -> CGFloat { (1 - CGFloat(note - lo) / span) * (height - 6) + 3 }
        func toggle(_ ports: [Int]) {
            if ports.allSatisfy({ reelExportPorts.contains($0) }) { ports.forEach { reelExportPorts.remove($0) } } else { ports.forEach { reelExportPorts.insert($0) } }
        }
        func tag(_ name: String, _ count: Int, selected: Bool, tint: Color) -> some View {
            HStack(spacing: 3) {
                Image(systemName: selected ? "checkmark.circle.fill" : "circle").font(.system(size: 8, weight: .bold)).foregroundColor(selected ? tint : tint.opacity(0.4))
                Text(name).font(.system(size: 9, weight: .heavy, design: .monospaced)).foregroundColor(tint.opacity(selected ? 1 : 0.8))
                if reelSelPassNo >= 0 || reelSelLoPass >= 0 {   // how many notes this port holds in the selection (a port with none cannot be saved)
                    Text("\(count)").font(.system(size: 9, weight: .medium, design: .monospaced)).foregroundColor(ffDim)
                }
            }
            .padding(.horizontal, 3)
            .background(RoundedRectangle(cornerRadius: 3).fill(Color.black.opacity(0.35)))
            .overlay(selected ? RoundedRectangle(cornerRadius: 3).stroke(tint, lineWidth: 1) : nil)
            .contentShape(Rectangle())
        }
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
                // NOTES — each painted in its layer's colour (Fourfold has one machine, so the machine hue told nothing): the riff in the lane colour, the notes layer lighter.
                for (layer, tint) in [(riffNotes, hue), (notesNotes, notesHue)] {
                    for note in layer {
                        let x = CGFloat(note.start / cyc) * sz.width
                        let w = max(2, CGFloat((note.end - note.start) / cyc) * sz.width)
                        let y = yOf(Int(note.note))
                        let active = head.map { $0 >= note.start && $0 < note.end } ?? false
                        let base = 0.45 + 0.5 * Double(note.vel) / 127
                        let rect = CGRect(x: x, y: y - (active ? 2.5 : 1.5), width: min(w, sz.width - x), height: active ? 5 : 3)
                        if active { ctx.fill(Path(roundedRect: rect.insetBy(dx: -1.5, dy: -1.5), cornerRadius: 2), with: .color(tint.opacity(0.35))) }   // glow under
                        ctx.fill(Path(roundedRect: rect, cornerRadius: 1.4), with: .color(tint.opacity(active ? 1.0 : base)))
                    }
                }
            }.frame(width: width, height: height)
            VStack(alignment: .leading, spacing: 2) {
                tag("RIFF \(FourfoldPorts.laneLetters[lane])", riffNotes.count, selected: riffSelected, tint: hue)
                    .onTapGesture { toggle([riffBus]) }
                tag("NOTES \(FourfoldPorts.laneLetters[lane])", notesNotes.count, selected: notesSelected, tint: notesHue)
                    .onTapGesture { toggle([notesBus]) }
            }.padding(.leading, 4)
        }
        .overlay(riffSelected && notesSelected ? RoundedRectangle(cornerRadius: 3).stroke(hue, lineWidth: 1.5) : nil)   // BOTH ports selected for export
        .contentShape(Rectangle())
        .onTapGesture { toggle([riffBus, notesBus]) }   // tap the lane → toggle both its ports in the export selection (none ⇒ master)
    }
    // EXPORT the recorded pass to SMF files (the sum of the eight ports + per-port stems), then present a share sheet. (Paul 2026-08-18)
    // EXPORT the selected pass RANGE × the selected PORTS (Paul 2026-08-26). No port selected ⇒ the MASTER (the eight ports summed).
    private func reelExport() {
        let (lo, hi) = reelExportRange()
        guard lo >= 0, hi >= 0, reelExportAvailability(anyPass: reelPassNumbers.contains { $0 >= 0 }, selected: true, outputCounts: reelOutputCounts(), lanes: reelExportPorts).ok else { return }
        var mask: UInt8 = 0; for l in reelExportPorts where l >= 0 && l < FourfoldPorts.busCount { mask |= (1 << UInt8(l)) }
        let files = au?.reelExportRangeFiles(fromPass: lo, toPass: hi, emitterMask: mask) ?? []
        guard !files.isEmpty else { return }
        // In the standalone app the exports are kept in Documents/Reel exports (visible in the Files app, like the presets); in the AU extension they stay temporary — its container is invisible.
        var dir = FileManager.default.temporaryDirectory
        if PresetStore.useDocumentsFolder {
            let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0].appendingPathComponent("Reel exports", isDirectory: true)
            if (try? FileManager.default.createDirectory(at: docs, withIntermediateDirectories: true)) != nil { dir = docs }
        }
        // REEL PHASE 0 (REEL-5): every file used to be "Fourfold-A.mid", so the second SAVE overwrote the first. Now each is named for its time, passes and output, and an existing name is never reused.
        let stamp = reelExportStamp(Date())
        var urls: [URL] = []
        for f in files {
            let wanted = reelExportFileName(stamp: stamp, lo: lo, hi: hi, label: reelExportLabel(kernelName: f.name))
            let name = reelUniqueFileName(wanted, exists: { FileManager.default.fileExists(atPath: dir.appendingPathComponent($0).path) })
            let url = dir.appendingPathComponent(name)
            if (try? f.data.write(to: url)) != nil { urls.append(url) }
        }
        guard !urls.isEmpty else { return }
        reelShareURLs = urls
        reelShowShare = true
    }
    /// Notes per port (Riff A, Notes A … Notes D) in what is selected now (the roll holds the selected pass, or the whole range).
    private func reelOutputCounts() -> [Int] {
        var c = [Int](repeating: 0, count: FourfoldPorts.busCount)
        for n in reelRoll where n.cable >= 1 && Int(n.cable) <= FourfoldPorts.busCount { c[Int(n.cable) - 1] += 1 }
        return c
    }
    // The pass range to export/highlight: the [lo,hi] set by ◀/▶, else the single selected pass. (pass numbers)
    private func reelExportRange() -> (Int, Int) {
        if reelSelLoPass >= 0 && reelSelHiPass >= 0 { return (min(reelSelLoPass, reelSelHiPass), max(reelSelLoPass, reelSelHiPass)) }
        return (reelSelPassNo, reelSelPassNo)
    }
    // Tap a pass: collapse the range to that single pass + select/replay it (the anchor drives the live roll + audition).
    private func reelSelectPass(_ pass: Int) {
        reelSelLoPass = pass; reelSelHiPass = pass; reelRangeCyc = 0
        au?.reelSelectPass(pass)
    }
    // ◀/▶ EXTEND (Paul 2026-08-26): grow the selection's LEFT (dir<0) or RIGHT (dir>0) edge to the next recorded pass; the
    // page follows so the growing edge stays visible; the roll refreshes to the whole concatenated range.
    private func reelExtend(_ dir: Int) {
        let visible = reelVisiblePasses()
        guard !visible.isEmpty else { return }
        if reelSelLoPass < 0 || reelSelHiPass < 0 {   // nothing yet → seed from the anchor / newest
            let seed = reelSelPassNo >= 0 ? reelSelPassNo : (visible.last ?? -1)
            reelSelLoPass = seed; reelSelHiPass = seed
        }
        if dir < 0 {
            if let prev = visible.last(where: { $0 < min(reelSelLoPass, reelSelHiPass) }) { reelSelLoPass = prev; reelPageFor(prev, visible: visible) }
        } else {
            if let next = visible.first(where: { $0 > max(reelSelLoPass, reelSelHiPass) }) { reelSelHiPass = next; reelPageFor(next, visible: visible) }
        }
        reelRefreshRange()
    }
    private func reelPageFor(_ pass: Int, visible: [Int]) { if let idx = visible.firstIndex(of: pass) { reelPage = idx / 32 } }
    // Recompute the displayed roll for the current range: multi-pass ⇒ the concatenated range roll (+ its total length);
    // single ⇒ leave reelRangeCyc 0 so the poll drives reelRoll from the anchor pass.
    private func reelRefreshRange() {
        guard reelSelLoPass >= 0, reelSelHiPass >= 0 else { reelRangeCyc = 0; return }
        let lo = min(reelSelLoPass, reelSelHiPass), hi = max(reelSelLoPass, reelSelHiPass)
        if hi > lo, let r = au?.reelRangeRoll(fromPass: lo, toPass: hi) { reelRoll = r.notes; reelRangeCyc = r.cycle }
        else { reelRangeCyc = 0 }
    }
    private var reelEffCycle: Double { reelRangeCyc > 0 ? reelRangeCyc : reelCycle }   // the roll's x-axis span: the range total, or the single pass length
}
