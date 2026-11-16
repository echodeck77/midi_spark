//  FourfoldReel.swift — REEL redesign Phase 3 (the new screen), slice 3b: the SwiftUI views over the pure layer in `ReelScreen.swift`.
//  Three shapes of ONE tape: OVERVIEW (whole session, stacked by lane, now = the right edge) → TAPE (a bar window with ×n repeat brackets + a snapping selection) → CLOSE-UP (the selection as a piano roll in lane colours),
//  plus a control bar (back to start · play from here · loop selection · close) and a LIVE/TAPE pill. Replay is anchored (phase 2): the pill / controls drive `FourfoldAudioUnit.reelPlayRange`. No "rotate to landscape" — the three
//  shapes cover portrait, landscape and the short AUM plug-in window. GEOMETRY IS DEVICE-OWED (`ReelScreenMetrics`); the look is for Paul to verify on device. Keeps + export are Phase 4; this slice delivers the screen + replay.

import SwiftUI
import UIKit

/// A share sheet for the REEL export (SMF files) — kept from the old browser for Phase 4.
struct FourfoldShareSheet: UIViewControllerRepresentable {
    let urls: [URL]
    func makeUIViewController(context: Context) -> UIActivityViewController { UIActivityViewController(activityItems: urls, applicationActivities: nil) }
    func updateUIViewController(_ vc: UIActivityViewController, context: Context) {}
}

struct FourfoldReelBrowser: View {
    weak var au: FourfoldAudioUnit?
    let size: CGSize
    let playing: Bool
    let tempo: Double
    let onClose: () -> Void

    // Palette (plan §tokens / `Docs/fourstep-design-tokens.md`): the reel's old cyan is gone.
    private static let ground = Color(hex: 0x15161A)
    private static let panel = Color(hex: 0x2A2D34)
    private static let ink = Color(hex: 0xDFE3EA)       // selection + text
    private static let dim = Color(hex: 0x6E737C)
    static let laneHues: [Color] = [Color(hex: 0xF25959), Color(hex: 0x59BFF2), Color(hex: 0xF2BF40), Color(hex: 0x8CD973)]   // A B C D
    private func laneColor(_ lane: Int) -> Color { Self.laneHues[max(0, min(3, lane))] }

    // §PHASE 3: 4/4 is assumed for the bar ruler until the host time signature is polled (flagged device-owed; most sessions are 4/4).
    private let beatsPerBar: Double = 4

    @State private var reelState = 0                 // 0 live/armed · 2 replaying (polled)
    @State private var reelMode = 0                  // 0 loop · 1 to-live (polled)
    @State private var sessionEnd = 0.0              // beats (polled)
    @State private var overviewNotes: [ReelDeck.Note] = []
    @State private var closeUpNotes: [ReelDeck.Note] = []
    @State private var sel = ReelSelection(startBeat: 0, endBeat: 4)
    @State private var window = ReelTapeWindow(startBeat: 0, bars: ReelScreenMetrics.defaultWindowBars)
    @State private var lastSelLoaded = ReelSelection(startBeat: -1, endBeat: -1)   // so the close-up refetches only when the selection changes
    @State private var keeps: [ReelKeep] = []                                      // Phase 4: the session's kept ranges
    @State private var reelShareURLs: [URL] = []
    @State private var reelShowShare = false

    private let poll = Timer.publish(every: 0.25, on: .main, in: .common).autoconnect()

    var body: some View {
        let L = reelScreenLayout(size: size)
        ZStack(alignment: .topLeading) {
            Self.ground.ignoresSafeArea()
            if sessionEnd <= 0 {
                emptyState
            } else {
                overviewView(L.overview, shape: L.shape)
                if L.hasTape { tapeView(L.tape) }
                closeUpView(L.closeUp)
                if !keeps.isEmpty { keepsStrip(y: L.controlBar.minY - 34, width: size.width) }
            }
            controlBar(L.controlBar)
            pill(L.pill)
        }
        .frame(width: size.width, height: size.height, alignment: .topLeading)
        .onAppear { au?.reelSetBrowsing(true); refresh(); seedSelection() }
        .onDisappear { au?.reelStopReplay(); au?.reelSetBrowsing(false) }
        .onReceive(poll) { _ in refresh() }
        .sheet(isPresented: $reelShowShare) { FourfoldShareSheet(urls: reelShareURLs) }
    }

    // MARK: data

    private func refresh() {
        guard let au else { return }
        let rs = au.uiReelState(); if rs != reelState { reelState = rs }
        let rm = au.reelModeValue(); if rm != reelMode { reelMode = rm }
        let end = au.reelSessionEndBeat()
        if abs(end - sessionEnd) > 1e-6 {
            sessionEnd = end
            overviewNotes = au.reelNotesInRange(fromBeat: 0, toBeat: end)   // the whole session (fine for moderate sessions; a binned summary is a later optimisation)
            window = reelClampWindow(window, sessionEndBeat: end, beatsPerBar: beatsPerBar)
        }
        if sel != lastSelLoaded {
            closeUpNotes = au.reelNotesInRange(fromBeat: sel.startBeat, toBeat: sel.endBeat)
            lastSelLoaded = sel
        }
        let k = au.reelKeeps(); if k != keeps { keeps = k }
    }

    // MARK: Phase 4 — keep + export

    private func addKeep() {
        guard let au, sel.spanBeats > 0 else { return }
        au.reelSetKeeps(reelAddKeep(au.reelKeeps(), startBeat: sel.startBeat, endBeat: sel.endBeat, beatsPerBar: beatsPerBar, at: Date()))
        keeps = au.reelKeeps()
    }
    private func removeKeep(_ i: Int) { guard let au else { return }; au.reelSetKeeps(reelRemoveKeep(au.reelKeeps(), at: i)); keeps = au.reelKeeps() }
    private func loadKeep(_ k: ReelKeep) { setSelection(ReelSelection(startBeat: k.startBeat, endBeat: k.endBeat)); window = reelClampWindow(ReelTapeWindow(startBeat: max(0, k.startBeat - 4 * beatsPerBar), bars: window.bars), sessionEndBeat: sessionEnd, beatsPerBar: beatsPerBar) }

    /// Export a beat range as SMF files (the A–D mix as "All", here; per-output is a later toggle) to the app's "Reel exports" folder (or temp in the extension), uniquely named, then present the share sheet.
    private func exportRange(_ lo: Double, _ hi: Double) {
        guard let au else { return }
        let files = au.reelExportKeepFiles(fromBeat: lo, toBeat: hi, emitterMask: 0)
        guard !files.isEmpty else { return }
        var dir = FileManager.default.temporaryDirectory
        if PresetStore.useDocumentsFolder {
            let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0].appendingPathComponent("Reel exports", isDirectory: true)
            if (try? FileManager.default.createDirectory(at: docs, withIntermediateDirectories: true)) != nil { dir = docs }
        }
        let stamp = reelExportStamp(Date())
        var urls: [URL] = []
        for f in files {
            let wanted = reelKeepExportFileName(stamp: stamp, startBeat: lo, endBeat: hi, beatsPerBar: beatsPerBar, label: f.label)
            let name = reelUniqueFileName(wanted, exists: { FileManager.default.fileExists(atPath: dir.appendingPathComponent($0).path) })
            let url = dir.appendingPathComponent(name)
            if (try? f.data.write(to: url)) != nil { urls.append(url) }
        }
        guard !urls.isEmpty else { return }
        reelShareURLs = urls; reelShowShare = true
    }
    private func seedSelection() {
        let end = au?.reelSessionEndBeat() ?? 0
        guard end > 0 else { return }
        sel = reelSelectionBars(endingAt: end, bars: ReelScreenMetrics.defaultKeepBars, beatsPerBar: beatsPerBar, sessionEndBeat: end)
        window = reelClampWindow(ReelTapeWindow(startBeat: max(0, sel.startBeat - 4 * beatsPerBar), bars: ReelScreenMetrics.defaultWindowBars), sessionEndBeat: end, beatsPerBar: beatsPerBar)
    }
    private func setSelection(_ s: ReelSelection) { sel = s; if let au { closeUpNotes = au.reelNotesInRange(fromBeat: s.startBeat, toBeat: s.endBeat); lastSelLoaded = s } }

    // MARK: overview — the whole session, stacked by lane, now = the right edge

    private func overviewView(_ r: CGRect, shape: ReelScreenShape) -> some View {
        let bins = max(1, Int(r.width / 2))
        let density = reelOverviewDensity(notes: overviewNotes, sessionEndBeat: sessionEnd, bins: bins)
        return ZStack(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: 8).fill(Self.panel.opacity(0.5))
            Canvas { ctx, sz in
                let laneH = sz.height / 4
                for lane in 0..<4 {
                    let y0 = CGFloat(lane) * laneH
                    let hue = laneColor(lane)
                    for b in 0..<bins {
                        let v = density[lane][b]
                        guard v > 0 else { continue }
                        let x = CGFloat(b) / CGFloat(bins) * sz.width
                        let h = CGFloat(v) * (laneH - 3)
                        ctx.fill(Path(CGRect(x: x, y: y0 + laneH - 3 - h, width: max(1, sz.width / CGFloat(bins) - 0.5), height: h)), with: .color(hue.opacity(0.9)))
                    }
                    ctx.stroke(Path { $0.move(to: CGPoint(x: 0, y: y0 + laneH)); $0.addLine(to: CGPoint(x: sz.width, y: y0 + laneH)) }, with: .color(.white.opacity(0.05)), lineWidth: 0.5)
                }
                // the selection span
                let sx = CGFloat(sel.startBeat / max(0.0001, sessionEnd)) * sz.width
                let ex = CGFloat(sel.endBeat / max(0.0001, sessionEnd)) * sz.width
                ctx.fill(Path(CGRect(x: sx, y: 0, width: max(2, ex - sx), height: sz.height)), with: .color(Self.ink.opacity(0.18)))
                ctx.stroke(Path(CGRect(x: sx, y: 0, width: max(2, ex - sx), height: sz.height)), with: .color(Self.ink.opacity(0.7)), lineWidth: 1)
            }.padding(1)
        }
        .frame(width: r.width, height: r.height).offset(x: r.minX, y: r.minY)
        .contentShape(Rectangle())
        // small shape: the overview IS the selector — drag selects a span; a tap grabs the default keep ending there.
        .gesture(DragGesture(minimumDistance: 0).onChanged { g in
            let f0 = Double(min(g.startLocation.x, g.location.x) / r.width), f1 = Double(max(g.startLocation.x, g.location.x) / r.width)
            let b0 = reelSnapToBar(beat: f0 * sessionEnd, beatsPerBar: beatsPerBar), b1 = reelSnapToBar(beat: f1 * sessionEnd, beatsPerBar: beatsPerBar)
            if b1 - b0 >= beatsPerBar { setSelection(ReelSelection(startBeat: max(0, b0), endBeat: min(sessionEnd, b1))) }
            else { setSelection(reelSelectionBars(endingAt: f1 * sessionEnd, bars: ReelScreenMetrics.defaultKeepBars, beatsPerBar: beatsPerBar, sessionEndBeat: sessionEnd)) }
            window = reelClampWindow(ReelTapeWindow(startBeat: max(0, sel.startBeat - 4 * beatsPerBar), bars: window.bars), sessionEndBeat: sessionEnd, beatsPerBar: beatsPerBar)
        })
    }

    // MARK: tape — a bar window with ×n brackets + a snapping selection (wide/tall)

    private func tapeView(_ r: CGRect) -> some View {
        let winBars = Int(window.bars.rounded())
        let notes = overviewNotes.filter { $0.start >= window.startBeat - beatsPerBar && $0.start <= window.startBeat + window.bars * beatsPerBar }
        let fp = reelBarFingerprints(notes: notes.map { ReelDeck.Note(cable: $0.cable, note: $0.note, vel: $0.vel, start: $0.start - window.startBeat, end: $0.end - window.startBeat, machine: 0) }, beatsPerBar: beatsPerBar, bars: winBars)
        let brackets = reelRepeatBrackets(fingerprints: fp)
        return ZStack(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: 8).fill(Self.panel.opacity(0.5))
            Canvas { ctx, sz in
                let tape = CGRect(x: 0, y: 0, width: sz.width, height: sz.height)
                let rulerH: CGFloat = 16
                // bar ticks + numbers
                let step = max(1, winBars / 12)
                for bar in stride(from: 0, through: winBars, by: step) {
                    let beat = window.startBeat + Double(bar) * beatsPerBar
                    let x = reelTapeXAtBeat(beat, tape: tape, window: window, beatsPerBar: beatsPerBar)
                    ctx.stroke(Path { $0.move(to: CGPoint(x: x, y: rulerH)); $0.addLine(to: CGPoint(x: x, y: sz.height)) }, with: .color(.white.opacity(0.06)), lineWidth: 0.5)
                    let barNo = Int(beat / beatsPerBar) + 1
                    ctx.draw(Text("\(barNo)").font(.system(size: 8, weight: .bold, design: .monospaced)).foregroundColor(Self.dim), at: CGPoint(x: x + 2, y: 8), anchor: .leading)
                }
                // notes (faint blocks, lane-coloured)
                for n in notes {
                    let x = reelTapeXAtBeat(n.start, tape: tape, window: window, beatsPerBar: beatsPerBar)
                    let w = max(1, reelTapeXAtBeat(n.end, tape: tape, window: window, beatsPerBar: beatsPerBar) - x)
                    let lane = Int(n.cable) - 1
                    let y = rulerH + CGFloat(max(0, min(3, lane))) / 4 * (sz.height - rulerH)
                    ctx.fill(Path(roundedRect: CGRect(x: x, y: y + 2, width: w, height: (sz.height - rulerH) / 4 - 3), cornerRadius: 1), with: .color(laneColor(max(0, lane)).opacity(0.55)))
                }
                // ×n brackets along the ruler
                for br in brackets {
                    let b0 = window.startBeat + Double(br.firstBar) * beatsPerBar
                    let x0 = reelTapeXAtBeat(b0, tape: tape, window: window, beatsPerBar: beatsPerBar)
                    let x1 = reelTapeXAtBeat(b0 + Double(br.count) * beatsPerBar, tape: tape, window: window, beatsPerBar: beatsPerBar)
                    ctx.stroke(Path { $0.move(to: CGPoint(x: x0 + 1, y: 2)); $0.addLine(to: CGPoint(x: x1 - 1, y: 2)) }, with: .color(Self.ink.opacity(0.5)), lineWidth: 1)
                    ctx.draw(Text("×\(br.count)").font(.system(size: 8, weight: .heavy, design: .monospaced)).foregroundColor(Self.ink.opacity(0.7)), at: CGPoint(x: (x0 + x1) / 2, y: 8), anchor: .center)
                }
                // the selection + handles
                let sx = reelTapeXAtBeat(sel.startBeat, tape: tape, window: window, beatsPerBar: beatsPerBar)
                let ex = reelTapeXAtBeat(sel.endBeat, tape: tape, window: window, beatsPerBar: beatsPerBar)
                ctx.fill(Path(CGRect(x: sx, y: rulerH, width: max(2, ex - sx), height: sz.height - rulerH)), with: .color(Self.ink.opacity(0.14)))
                for hx in [sx, ex] {
                    ctx.fill(Path(CGRect(x: hx - 2, y: rulerH, width: 4, height: sz.height - rulerH)), with: .color(Self.ink.opacity(0.85)))
                }
            }.padding(1)
        }
        .frame(width: r.width, height: r.height).offset(x: r.minX, y: r.minY)
        .contentShape(Rectangle())
        .gesture(DragGesture(minimumDistance: 0).onChanged { g in
            let tape = CGRect(x: 0, y: 0, width: r.width, height: r.height)
            // grab the nearer handle and drag it; if the drag starts well away from both, start a fresh span.
            let sx = reelTapeXAtBeat(sel.startBeat, tape: tape, window: window, beatsPerBar: beatsPerBar)
            let ex = reelTapeXAtBeat(sel.endBeat, tape: tape, window: window, beatsPerBar: beatsPerBar)
            let beat = reelTapeBeatAtX(g.location.x, tape: tape, window: window, beatsPerBar: beatsPerBar)
            if abs(g.startLocation.x - sx) < 18 { setSelection(reelMoveHandle(sel, .start, toBeat: beat, beatsPerBar: beatsPerBar, sessionEndBeat: sessionEnd)) }
            else if abs(g.startLocation.x - ex) < 18 { setSelection(reelMoveHandle(sel, .end, toBeat: beat, beatsPerBar: beatsPerBar, sessionEndBeat: sessionEnd)) }
            else {
                let b0 = reelTapeBeatAtX(min(g.startLocation.x, g.location.x), tape: tape, window: window, beatsPerBar: beatsPerBar)
                let b1 = reelTapeBeatAtX(max(g.startLocation.x, g.location.x), tape: tape, window: window, beatsPerBar: beatsPerBar)
                let s = reelMoveHandle(ReelSelection(startBeat: reelSnapToBar(beat: b0, beatsPerBar: beatsPerBar), endBeat: reelSnapToBar(beat: b0, beatsPerBar: beatsPerBar) + beatsPerBar), .end, toBeat: b1, beatsPerBar: beatsPerBar, sessionEndBeat: sessionEnd)
                setSelection(ReelSelection(startBeat: max(0, reelSnapToBar(beat: b0, beatsPerBar: beatsPerBar)), endBeat: s.endBeat))
            }
        })
    }

    // MARK: close-up — the selection as a piano roll, notes in lane colours

    private func closeUpView(_ r: CGRect) -> some View {
        let notes = closeUpNotes
        let span = max(0.0001, sel.spanBeats)
        let all = notes.map { Int($0.note) }
        let rawLo = all.min() ?? 48, rawHi = all.max() ?? 72
        let lo = (rawLo / 12) * 12, hi = max(lo + 12, ((rawHi + 11) / 12) * 12)
        let pspan = CGFloat(hi - lo)
        return ZStack(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: 8).fill(Self.panel.opacity(0.35))
            Canvas { ctx, sz in
                func yOf(_ n: Int) -> CGFloat { (1 - CGFloat(n - lo) / pspan) * (sz.height - 8) + 4 }
                var n = lo
                while n <= hi { let y = yOf(n); ctx.stroke(Path { $0.move(to: CGPoint(x: 0, y: y)); $0.addLine(to: CGPoint(x: sz.width, y: y)) }, with: .color(.white.opacity(0.07)), lineWidth: 0.5); n += 12 }
                for note in notes {
                    let x = CGFloat((note.start - sel.startBeat) / span) * sz.width
                    let w = max(2, CGFloat((note.end - note.start) / span) * sz.width)
                    let y = yOf(Int(note.note))
                    let alpha = 0.5 + 0.5 * Double(note.vel) / 127
                    ctx.fill(Path(roundedRect: CGRect(x: x, y: y - 2, width: min(w, sz.width - x), height: 4), cornerRadius: 1.5), with: .color(laneColor(Int(note.cable) - 1).opacity(alpha)))
                }
            }.padding(1)
        }
        .frame(width: r.width, height: r.height).offset(x: r.minX, y: r.minY)
    }

    // MARK: control bar + the LIVE/TAPE pill

    private func controlBar(_ r: CGRect) -> some View {
        HStack(spacing: 7) {
            ctlButton("backward.to.line", "START") { au?.reelPlayRange(fromTapeBeat: 0, toTapeBeat: sessionEnd, loop: false) }
            ctlButton("play.fill", "PLAY") { au?.reelPlayRange(fromTapeBeat: sel.startBeat, toTapeBeat: max(sel.startBeat + beatsPerBar, sessionEnd), loop: false) }
            ctlButton("repeat", "LOOP") { au?.reelPlayRange(fromTapeBeat: sel.startBeat, toTapeBeat: sel.endBeat, loop: true) }
            Spacer(minLength: 0)
            Text(selLabel).font(.system(size: 9.5, weight: .heavy, design: .monospaced)).foregroundColor(Self.ink.opacity(0.8)).lineLimit(1).minimumScaleFactor(0.7)
            Spacer(minLength: 0)
            ctlButton("star", "KEEP") { addKeep() }
            ctlButton("square.and.arrow.up", "EXPORT") { exportRange(sel.startBeat, sel.endBeat) }
            ctlButton("xmark", "CLOSE") { onClose() }
        }
        .padding(.horizontal, 12)
        .frame(width: r.width, height: r.height).offset(x: r.minX, y: r.minY)
    }
    // Phase 4: the keeps as chips (tap a chip to load its range; × removes it). Shown only when keeps exist, just above the control bar.
    private func keepsStrip(y: CGFloat, width: CGFloat) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                Text("KEEPS").font(.system(size: 9, weight: .heavy, design: .monospaced)).tracking(0.5).foregroundColor(Self.dim)
                ForEach(Array(keeps.enumerated()), id: \.offset) { i, k in
                    HStack(spacing: 5) {
                        Text(reelKeepBarLabel(startBeat: k.startBeat, endBeat: k.endBeat, beatsPerBar: beatsPerBar))
                            .font(.system(size: 10, weight: .heavy, design: .monospaced)).foregroundColor(Self.ink)
                            .contentShape(Rectangle()).onTapGesture { loadKeep(k) }
                        Button { removeKeep(i) } label: { Image(systemName: "xmark").font(.system(size: 8, weight: .bold)).foregroundColor(Self.dim) }
                            .accessibilityLabel("Remove keep \(reelKeepBarLabel(startBeat: k.startBeat, endBeat: k.endBeat, beatsPerBar: beatsPerBar))")
                    }
                    .padding(.horizontal, 8).padding(.vertical, 5)
                    .background(RoundedRectangle(cornerRadius: 6).fill(Self.panel))
                    .overlay(RoundedRectangle(cornerRadius: 6).stroke(.white.opacity(0.1), lineWidth: 1))
                }
            }.padding(.horizontal, 12)
        }
        .frame(width: width, height: 30).offset(x: 0, y: y)
    }
    private var selLabel: String {
        let b0 = Int(sel.startBeat / beatsPerBar) + 1, n = max(1, Int((sel.spanBeats / beatsPerBar).rounded()))
        return "bars \(b0)–\(b0 + n - 1) · \(n) bar\(n == 1 ? "" : "s")"
    }
    private func ctlButton(_ icon: String, _ label: String, _ act: @escaping () -> Void) -> some View {
        Button(action: act) {
            HStack(spacing: 5) {
                Image(systemName: icon).font(.system(size: 13, weight: .bold))
                Text(label).font(.system(size: 9.5, weight: .heavy, design: .monospaced)).tracking(0.5)
            }
            .foregroundColor(Self.ink).padding(.horizontal, 11).padding(.vertical, 9)
            .background(RoundedRectangle(cornerRadius: 7).fill(Self.panel)).overlay(RoundedRectangle(cornerRadius: 7).stroke(.white.opacity(0.1), lineWidth: 1))
        }.accessibilityLabel(label)
    }
    private func pill(_ r: CGRect) -> some View {
        let tape = reelState == 2
        return Button { if tape { au?.reelStopReplay() } } label: {
            Text(tape ? "TAPE" : "LIVE").font(.system(size: 11, weight: .heavy, design: .monospaced)).tracking(1)
                .foregroundColor(tape ? Color(hex: 0x0D0F14) : Self.ink)
                .frame(width: r.width, height: r.height)
                .background(RoundedRectangle(cornerRadius: r.height / 2).fill(tape ? Self.ink : Self.panel))
                .overlay(RoundedRectangle(cornerRadius: r.height / 2).stroke(.white.opacity(tape ? 0 : 0.15), lineWidth: 1))
        }
        .offset(x: r.minX, y: r.minY)
        .accessibilityLabel(tape ? "Playing the tape; tap to return to live" : "Live")
    }

    private var emptyState: some View {
        VStack(spacing: 10) {
            Image(systemName: "recordingtape").font(.system(size: 36, weight: .light)).foregroundColor(Self.dim)
            Text("Play to start the tape.").font(.system(size: 14, weight: .semibold)).foregroundColor(Self.ink.opacity(0.7))
            Button { onClose() } label: {
                Text("CLOSE").font(.system(size: 11, weight: .heavy, design: .monospaced)).tracking(1).foregroundColor(Self.dim)
                    .padding(.horizontal, 24).padding(.vertical, 10).background(RoundedRectangle(cornerRadius: 6).fill(Self.panel))
            }.padding(.top, 6)
        }
        .frame(width: size.width, height: size.height)
    }
}
