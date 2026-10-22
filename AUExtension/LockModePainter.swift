//  LockModePainter.swift
//  LANE LOCK ferry (2026-10-21, §4 / §5): the lock card (what a lane card becomes while lock mode is on), the padlock button's touch, the snap ring, and the badge on a locked lane's tab row.
//
//  SwiftUI-only on purpose (GridUI seam rule). Every decision is pure and lives in EuclideousLock.swift: the grid, the count-down, the status words, the summary tags, every frame (`euclideousLockCardLayout`,
//  `EuclideousLockBadge`). This file only draws and wires a finger to them. Every sub-view is built by its own small function that returns an `AnyView` — the extension's 1 MB main-thread stack is nearly full
//  in a DEBUG build (Docs/claude-playbook.md), so the page's construction chain must only ever hold an 8-byte value per leaf.

import SwiftUI

enum EuclideousLockPalette {
    static let ink = Color(hex: 0x0D0F14)
    static let text = Color(hex: 0xF2F4F7)
    static let mute = Color(hex: 0x8A909A)
    static let soft = Color(hex: 0xAAB0BA)
    static let plate = Color(hex: 0x2A2D34)
    static let border = Color(hex: 0x3A3E47)
    static let heldFill = Color(hex: 0xDFE3EA)
    static let ground = Color(hex: 0x1B1D23)
    static let well = Color(hex: 0x22252C)
}

/// A button that tells a tap from a hold the way the SOLO button does (the solo ferry's pure `EuclideousSoloPress`, 300 ms = `EuclideousRingPress.holdSeconds`): release before 300 ms is a TAP; at 300 ms `onHold` fires
/// AT ONCE (7.2: "the capture happens at 300 ms, not on release") and the held look shows until the finger lifts; a lift after a hold does nothing more. A slide-off never cancels; a touch the system cancels, or a
/// button that goes away mid-touch, ends quietly. VoiceOver's activation is a tap; "Lock what's playing" is a custom action.
struct EuclideousLockPressable: View {
    let label: String
    let value: String
    let hint: String
    let holdActionName: String
    var extraTapName: String? = nil   // the badge's spec'd custom action "Unlock" (the default activation is the same tap)
    let content: (_ heldLook: Bool) -> AnyView
    let onTap: () -> Void
    let onHold: () -> Void

    @State private var press = EuclideousSoloPress()
    @State private var heldLook = false
    @State private var holdTask: Task<Void, Never>? = nil
    @GestureState private var touching = false

    private func now() -> Double { ProcessInfo.processInfo.systemUptime }

    var body: some View {
        content(heldLook)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .updating($touching) { _, t, _ in t = true }
                    .onChanged { _ in
                        guard !press.down else { return }
                        press.touchDown(at: now())
                        holdTask = Task { @MainActor in
                            try? await Task.sleep(nanoseconds: UInt64(EuclideousRingPress.holdSeconds * 1_000_000_000))
                            guard !Task.isCancelled, press.down else { return }
                            press.holdTimerFired()
                            heldLook = press.showsHeldLook
                            onHold()
                        }
                    }
                    .onEnded { _ in finish(cancelled: false) }
            )
            .onChange(of: touching) { t in
                guard !t else { return }
                Task { @MainActor in if press.down { finish(cancelled: true) } }
            }
            .onDisappear { if press.down { finish(cancelled: true) } }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(label)
            .accessibilityValue(value)
            .accessibilityHint(hint)
            .accessibilityAddTraits(.isButton)
            .ringToggleTrait()
            .accessibilityAction { onTap() }
            .accessibilityActions {
                if let n = extraTapName { Button(n) { onTap() } }
                Button(holdActionName) { onHold() }
            }
    }

    private func finish(cancelled: Bool) {
        holdTask?.cancel(); holdTask = nil
        let r = cancelled ? press.touchCancelled() : press.touchEnded(at: now())
        heldLook = false
        if !cancelled, case .ended(let isTap) = r, isTap { onTap() }
    }
}

/// 5.5 — the card's edge rings once when a lock snaps back or captures: a 2 pt lane100 inner ring, 100 % to 0 over 600 ms (random mode 7.3's ring). Reduce Motion: the same ring, shown without the fade, for the same time.
struct EuclideousLockRing: View {
    let start: Date?
    let accent: Color
    let radius: CGFloat
    let reduceMotion: Bool
    var body: some View {
        if let start {
            TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: false)) { tl in
                let t = tl.date.timeIntervalSince(start)
                if t >= 0 && t < 0.6 {
                    RoundedRectangle(cornerRadius: radius).strokeBorder(accent, lineWidth: 2)
                        .opacity(reduceMotion ? 1 : 1 - t / 0.6)
                } else { Color.clear }
            }
            .allowsHitTesting(false)
        }
    }
}

/// The lock card (4.1–4.9). `line` is the lane as it is playing now; `lock` is its saved lock. Unlocked, the summary shows what is playing (and what a tap would lock); locked, it shows L.
struct EuclideousLockCardView: View {
    let lane: Int
    let size: CGSize
    let accent: Color
    let line: EuclidLine
    let lock: EuclideousLaneLock
    let autoRate: ArpRate
    let held: Bool
    let running: Bool
    let tempo: Double
    let barBeats: Double
    let beatAt: (Date) -> Double
    let ringStart: Date?
    let reduceMotion: Bool
    let onTap: () -> Void
    let onHold: () -> Void
    let onGrid: (EuclideousLockGrid) -> Void

    typealias P = EuclideousLockPalette
    private var layout: EuclideousLockCardLayout { euclideousLockCardLayout(size: size) }
    private var locked: Bool { lock.isLocked }
    private var grid: EuclideousLockGrid { lock.gridResolved }
    private var deviated: Bool { locked && lock.state.map { euclideousLockDeviated(line: line, from: $0) } == true }

    private func place(_ r: CGRect, _ v: AnyView) -> AnyView { AnyView(v.frame(width: r.width, height: r.height).position(x: r.midX, y: r.midY)) }

    var body: some View {
        let L = layout
        return ZStack(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: 12).fill(P.ground)
            RoundedRectangle(cornerRadius: 12).strokeBorder(accent.opacity(locked ? 1 : 0.45), lineWidth: 1)
            place(L.numberCircle, numberCircle())
            place(L.titleRow, title())
            place(L.statusRow, status())
            place(L.padlock, padlock())
            summaryRows(L)
            place(L.snapBackLabel, label("SNAP BACK", color: P.mute, size: 8.5, tracking: 0.85, alignment: .leading))
            selector(L)
            place(L.ruleLine, label(grid.ruleLine, color: locked ? P.text : P.mute, size: 9, tracking: 0.72, alignment: .center))
            place(L.gridTicks, ticks())
            place(L.hint, label("TAP TO LOCK OR UNLOCK · HOLD TO LOCK WHAT'S PLAYING", color: P.mute, size: 8, tracking: 0.64, alignment: .center))
            EuclideousLockRing(start: ringStart, accent: accent, radius: 12, reduceMotion: reduceMotion)
        }
        .frame(width: size.width, height: size.height)
    }

    private func label(_ s: String, color: Color, size: CGFloat, tracking: CGFloat, alignment: Alignment) -> AnyView {
        AnyView(Text(s).font(.system(size: size, weight: .heavy)).tracking(tracking).foregroundColor(color)
            .lineLimit(1).truncationMode(.tail).frame(maxWidth: .infinity, alignment: alignment))
    }

    // MARK: 4.2 top row
    private func numberCircle() -> AnyView {
        AnyView(Circle().fill(accent).overlay(Text("\(lane + 1)").font(.system(size: 12, weight: .heavy)).foregroundColor(P.ink)))
    }
    private func title() -> AnyView {
        AnyView(Text("LANE \(lane + 1)").font(.system(size: 11, weight: .heavy)).tracking(1.1).foregroundColor(P.text).lineLimit(1)
            .frame(maxWidth: .infinity, alignment: .leading))
    }
    private func status() -> AnyView {
        let color: Color = locked ? accent : P.mute
        func text(_ at: Date?) -> AnyView {
            let countdown: EuclideousLockCountdown? = deviated
                ? euclideousLockCountdown(grid: grid, beat: running ? beatAt(at ?? Date()) : 0, barBeats: barBeats, marginBeats: EuclideousLockMargin.beats(tempo: tempo), held: held)
                : nil
            let s = euclideousLockStatusText(locked: locked, deviated: deviated, grid: grid, countdown: running || held ? countdown : nil)
            return AnyView(Text(s).font(.system(size: 9, weight: .heavy)).tracking(0.9).foregroundColor(color).lineLimit(1).truncationMode(.tail)
                .frame(maxWidth: .infinity, alignment: .trailing))
        }
        if deviated && running {
            return AnyView(TimelineView(.periodic(from: Date(), by: 0.1)) { tl in text(tl.date) })
        }
        return text(nil)
    }

    // MARK: 4.3 the padlock
    private func padlock() -> AnyView {
        let word = locked ? "Locked" : "Unlocked"
        return AnyView(EuclideousLockPressable(label: "Lock lane \(lane + 1)", value: word.lowercased(), hint: "Double-tap to lock or unlock", holdActionName: "Lock what's playing",
                                               content: { heldLook in padlockFace(heldLook) }, onTap: onTap, onHold: onHold))
    }
    private func padlockFace(_ heldLook: Bool) -> AnyView {
        let fill: Color = heldLook ? P.heldFill : (locked ? accent : P.plate)
        let dark = heldLook || locked
        let glyphColor: Color = dark ? P.ink : P.soft
        return AnyView(
            ZStack {
                RoundedRectangle(cornerRadius: 14).fill(fill)
                if !dark { RoundedRectangle(cornerRadius: 14).inset(by: 0.5).stroke(P.border, lineWidth: 1) }
                Image(systemName: dark ? "lock.fill" : "lock.open").font(.system(size: 30)).foregroundColor(glyphColor)
                Text(locked ? "LOCKED" : "LOCK").font(.system(size: 9, weight: .heavy)).tracking(0.9).foregroundColor(glyphColor)
                    .position(x: 44, y: 88 - 14)
            }
            .frame(width: 88, height: 88)
            .transaction { $0.animation = nil }
        )
    }

    // MARK: 4.4 what the lock holds
    private func summaryRows(_ L: EuclideousLockCardLayout) -> AnyView {
        let fields: LaneLockFields = (locked ? lock.state : nil) ?? LaneLockFields(line: line)
        let changed: Set<EuclideousLockTab> = (locked && lock.state != nil)
            ? euclideousLockChangedTabs(euclideousLockChangedControls(from: lock.state!, to: line)) : []
        let values = [euclideousLockRhythmTag(fields, autoRate: autoRate), euclideousLockRiffTag(fields, base: line), euclideousLockNotesTag(fields, base: line)]
        let names = ["RHYTHM", "RIFF", "NOTES"]
        let tabs: [EuclideousLockTab] = [.rhythm, .riff, .notes]
        return AnyView(ZStack(alignment: .topLeading) {
            ForEach(0..<3, id: \.self) { i in
                summaryRow(L, i, name: names[i], value: values[i], dot: changed.contains(tabs[i]))
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(euclideousLockSummaryAccessibility(lane: lane, locked: locked, fields: fields, base: line)))
    }
    private func summaryRow(_ L: EuclideousLockCardLayout, _ i: Int, name: String, value: String, dot: Bool) -> AnyView {
        let label = L.summaryLabel(i), v = L.summaryValue(i)
        return AnyView(ZStack(alignment: .topLeading) {
            HStack(spacing: 6) {
                Text(name).font(.system(size: 8.5, weight: .heavy)).tracking(0.85).foregroundColor(P.mute).lineLimit(1)
                if dot { Circle().fill(accent).frame(width: 6, height: 6) }
            }
            .frame(width: label.width, height: label.height, alignment: .leading).position(x: label.midX, y: label.midY)
            Text(value).font(.system(size: 10, weight: .heavy)).tracking(0.6).foregroundColor(locked ? P.text : P.mute)
                .lineLimit(1).truncationMode(.tail)
                .frame(width: v.width, height: v.height, alignment: .leading).position(x: v.midX, y: v.midY)
        })
    }

    // MARK: 4.6 the grid selector
    private func selector(_ L: EuclideousLockCardLayout) -> AnyView {
        AnyView(ZStack(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: 8).fill(P.well)
                .frame(width: L.selector.width, height: L.selector.height).position(x: L.selector.midX, y: L.selector.midY)
            ForEach(0..<6, id: \.self) { i in segment(L, i) }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Snap back grid")
        .accessibilityValue(grid.accessibilityValue)
        .accessibilityAdjustableAction { dir in
            let all = EuclideousLockGrid.allCases
            let at = all.firstIndex(of: grid) ?? 1
            let to = dir == .increment ? min(all.count - 1, at + 1) : max(0, at - 1)
            if to != at { onGrid(all[to]) }
        })
    }
    private func segment(_ L: EuclideousLockCardLayout, _ i: Int) -> AnyView {
        let g = EuclideousLockGrid.allCases[i]
        let on = g == grid
        let seg = L.segment(i), touch = L.segmentTouch(i)
        return AnyView(ZStack {
            if on { RoundedRectangle(cornerRadius: 6).fill(P.heldFill).frame(width: seg.width, height: seg.height).position(x: seg.midX, y: seg.midY) }
            Text(g.segmentLabel).font(.system(size: 10, weight: .heavy)).tracking(0.8).foregroundColor(on ? P.ink : P.soft)
                .lineLimit(1).frame(width: seg.width, height: seg.height).position(x: seg.midX, y: seg.midY)
            Color.clear.contentShape(Rectangle()).frame(width: touch.width, height: touch.height).position(x: touch.midX, y: touch.midY)
                .onTapGesture { onGrid(g) }
        })
    }

    // MARK: 4.7 the grid ticks
    private func ticks() -> AnyView {
        guard running else { return AnyView(Color.clear) }
        func dots(_ at: Date) -> AnyView {
            let t = euclideousLockTicks(grid: grid, beat: beatAt(at), barBeats: barBeats)
            return AnyView(HStack(spacing: 3) {
                ForEach(0..<t.count, id: \.self) { i in Circle().fill(t[i] ? accent : P.border).frame(width: 4, height: 4) }
            }.frame(maxWidth: .infinity))
        }
        return AnyView(TimelineView(.periodic(from: Date(), by: 0.25)) { tl in dots(tl.date) })
    }
}

// MARK: - 5.4 the outline of a control that differs from L

/// A 1.5 pt dashed lane100 frame (dash 4, gap 3), 3 pt outside the control, radius 10 — drawn on a control of the tab now showing whose value differs from the lane's locked state. Visual only: it never blocks a touch.
struct EuclideousLockOutline: ViewModifier {
    let on: Bool
    let accent: Color
    var radius: CGFloat = 10
    func body(content: Content) -> some View {
        content.overlay {
            if on {
                RoundedRectangle(cornerRadius: radius)
                    .stroke(accent, style: StrokeStyle(lineWidth: 1.5, dash: [4, 3]))
                    .padding(-3)
                    .allowsHitTesting(false)
            }
        }
    }
}
extension View {
    func lockOutline(_ on: Bool, accent: Color, radius: CGFloat = 10) -> some View { modifier(EuclideousLockOutline(on: on, accent: accent, radius: radius)) }
}

// MARK: - 6.2 / 6.9 held fingers and momentary buttons

/// For a control that writes a lock field with a drag (a slider, the STEPS stepper, the comet bar): while the lane is LOCKED a simultaneous zero-distance drag counts a finger on it — the page's HELD word (6.2). An
/// unlocked lane gets the bare control: nothing about a control changes until its lane is locked.
struct EuclideousLockHold: ViewModifier {
    let active: Bool
    let onTouch: (Bool) -> Void
    @State private var down = false
    func body(content: Content) -> some View {
        if active {
            content
                .simultaneousGesture(DragGesture(minimumDistance: 0)
                    .onChanged { _ in if !down { down = true; onTouch(true) } }
                    .onEnded { _ in if down { down = false; onTouch(false) } })
                .onDisappear { if down { down = false; onTouch(false) } }
        } else { content }
    }
}
/// For a control that acts on a TAP: an unlocked lane (or a locked one on a bar grid) gets exactly `.onTapGesture` as before — with a finger counted while locked (6.2) — and a lane locked on the BEAT grid gets the
/// action at TOUCH-DOWN instead (6.9), so a tap is momentary: it sounds from the touch until the first beat after the lift. Lock and unlock never happen under a finger the page is counting (the count is reset by the VC).
struct EuclideousLaneTap: ViewModifier {
    let locked: Bool
    let momentary: Bool
    let onTouch: (Bool) -> Void
    let action: () -> Void
    @State private var down = false
    func body(content: Content) -> some View {
        if momentary {
            content
                .gesture(DragGesture(minimumDistance: 0)
                    .onChanged { _ in if !down { down = true; onTouch(true); action() } }
                    .onEnded { _ in if down { down = false; onTouch(false) } })
                .onDisappear { if down { down = false; onTouch(false) } }
        } else if locked {
            content
                .onTapGesture(perform: action)
                .simultaneousGesture(DragGesture(minimumDistance: 0)
                    .onChanged { _ in if !down { down = true; onTouch(true) } }
                    .onEnded { _ in if down { down = false; onTouch(false) } })
                .onDisappear { if down { down = false; onTouch(false) } }
        } else {
            content.onTapGesture(perform: action)
        }
    }
}

// MARK: - 5.1 / 5.2 the badge on a locked lane's tab row

/// The padlock badge: 34 × 34 at the trailing end of the tab row, a 44-tall touch target centred on it. Tap unlocks (7.3), a hold locks what's playing (7.2). At L it is a quiet outline; while the lane has moved it counts
/// down to the line it will snap back on — a number of bars, then, in the last bar (and on the BEAT grid), one dot per beat left (more than 4: the number). It never dims.
struct EuclideousLockBadgeView: View {
    let lane: Int
    let accent: Color
    let deviated: Bool
    let grid: EuclideousLockGrid
    let held: Bool
    let running: Bool
    let tempo: Double
    let barBeats: Double
    let beatAt: (Date) -> Double
    let onTap: () -> Void
    let onHold: () -> Void
    typealias P = EuclideousLockPalette

    private func countdown(_ at: Date?) -> EuclideousLockCountdown? {
        guard deviated else { return nil }
        if held { return .held }
        guard running else { return nil }
        return euclideousLockCountdown(grid: grid, beat: beatAt(at ?? Date()), barBeats: barBeats, marginBeats: EuclideousLockMargin.beats(tempo: tempo), held: false)
    }
    private func spoken(_ c: EuclideousLockCountdown?) -> String {
        guard deviated, let c else { return deviated ? "back on the next line" : "at its locked state" }
        switch c {
        case .held: return "back after you let go"
        case .bars(let n): return "back in \(n) bars"
        case .beats: return grid == .beat ? "back on the next beat" : "back this bar"
        }
    }
    private func face(_ heldLook: Bool, _ c: EuclideousLockCountdown?) -> AnyView {
        let fill: Color = heldLook ? P.heldFill : (deviated ? accent.opacity(0.2) : Color.clear)
        let stroke: Color = deviated || heldLook ? accent : accent.opacity(0.6)
        return AnyView(
            ZStack {
                RoundedRectangle(cornerRadius: 8).fill(fill)
                if !heldLook { RoundedRectangle(cornerRadius: 8).inset(by: 0.5).stroke(stroke, lineWidth: 1) }
                VStack(spacing: 2) {
                    Image(systemName: "lock.fill").font(.system(size: deviated ? 12 : 14)).foregroundColor(heldLook ? P.ink : accent)
                    if deviated, !heldLook, let c { indicator(c) }
                }
            }
            .frame(width: 34, height: 34)
            .transaction { $0.animation = nil }
        )
    }
    private func indicator(_ c: EuclideousLockCountdown) -> AnyView {
        switch c {
        case .held: return AnyView(EmptyView())
        case .bars(let n): return AnyView(Text("\(n)").font(.system(size: 9, weight: .heavy)).foregroundColor(P.text).lineLimit(1))
        case .beats(let m):
            if m > 4 { return AnyView(Text("\(m)").font(.system(size: 9, weight: .heavy)).foregroundColor(P.text).lineLimit(1)) }
            return AnyView(HStack(spacing: 2) { ForEach(0..<m, id: \.self) { _ in Circle().fill(accent).frame(width: 3, height: 3) } }.frame(height: 9))
        }
    }
    private func pressable(_ c: EuclideousLockCountdown?) -> AnyView {
        AnyView(EuclideousLockPressable(label: "Lane \(lane + 1) locked", value: spoken(c), hint: "Double-tap to unlock", holdActionName: "Lock what's playing", extraTapName: "Unlock",
                                        content: { heldLook in face(heldLook, c) }, onTap: onTap, onHold: onHold))
    }
    var body: some View {
        Group {
            if deviated && running && !held {
                TimelineView(.periodic(from: Date(), by: 0.1)) { tl in pressable(countdown(tl.date)) }
            } else {
                pressable(countdown(nil))
            }
        }
        .frame(width: 34, height: 44)
    }
}
