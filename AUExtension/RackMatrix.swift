import SwiftUI

/// THE RACK — the emitter treatment matrix (design-the-rack). Supersedes the tabbed EmitterPage. Draws INSIDE the
/// grid's cell area (the chevron column-key row + the L/R row rails stay framing it); the strips + master stay live.
/// Four COLUMNS = the emitters A–D; ROWS = the treatments, grouped by three families (THIS VOICE · OVER OTHERS ·
/// TOGETHER) per DESIGN §5. Each row×column = an on/off toggle with its PRIMARY param as a drag-chip directly
/// beneath — no row-selection step (the flat law). A DETAIL STRIP below the matrix follows the last-touched row.
///
/// PASS 1 re-surfaces only the three treatments with engine backing — OWNS (claim) · KEY (duck) · TURNS (alt) —
/// wired to the SAME callbacks the strips used; live + undoable, no transaction. MONO/FENCE/CURVE/POCKET/
/// LEAD-STANCE and every secondary detail param are dimmed "coming" seats (their engine is a later pass). The
/// two-tier law: these toggles ARM the pedals; the strip's RACK button decides whether the board is in the path
/// (a rack-off column reads RAW here and its armed treatments don't apply — the builder gates them).
struct RackMatrix: View {
    let busChannels: [Int]
    let busEnabled: [Bool]
    let rackMask: UInt8         // THE RACK: bit i = emitter i's board is in the signal path (else RAW)
    let claimMask: UInt8        // OWNS
    let claimLeak: [Int]
    let flattenMask: UInt8      // KEY (the DUCK engine; code stays flatten*)
    let flattenAmount: [Int]
    let altMask: UInt8          // TURNS
    let altCount: [Int]
    var emitPeak: [Double] = [0, 0, 0, 0]
    let onClaim: (Int) -> Void
    let onClaimLeak: (Int, Int) -> Void
    let onToggleDuck: (Int) -> Void
    let onDuckAmount: (Int, Int) -> Void
    let onToggleAlt: (Int) -> Void
    let onAltCount: (Int, Int) -> Void
    let onClose: () -> Void

    private let ink = Color.white
    private let cyan = Color(red: 0.15, green: 0.88, blue: 0.94)
    private let amber = Color(red: 0.98, green: 0.72, blue: 0.12)
    private let letters = ["A", "B", "C", "D"]
    private func bit(_ m: UInt8, _ i: Int) -> Bool { m & (1 << UInt8(i)) != 0 }
    private func at(_ a: [Int], _ i: Int, _ d: Int) -> Int { i < a.count ? a[i] : d }

    @State private var focus: Int = 0            // the column whose social sentence the readout shows
    @State private var lastRow: String? = nil    // the row the DETAIL STRIP follows (last touched)
    @State private var dragKey: String? = nil    // "<row>-<col>" of the chip being dragged
    @State private var dragBase: Int = 0

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            headerBar
            columnHeaders
            readout
            ScrollView(.vertical, showsIndicators: false) {
                VStack(alignment: .leading, spacing: 6) {
                    familyLabel("THIS VOICE")
                    dimRow("MONO"); dimRow("FENCE"); dimRow("CURVE"); dimRow("POCKET")
                    familyLabel("OVER OTHERS")
                    liveRow(key: "OWNS", title: "Claims this note from others", hue: amber,
                            isOn: { bit(claimMask, $0) }, value: { at(claimLeak, $0, 0) },
                            unit: "%", maxV: 100, onToggle: onClaim, onSet: onClaimLeak)
                    liveRow(key: "KEY", title: "Ducks others' velocity", hue: amber,
                            isOn: { bit(flattenMask, $0) }, value: { at(flattenAmount, $0, 0) },
                            unit: "%", maxV: 100, onToggle: onToggleDuck, onSet: onDuckAmount)
                    familyLabel("TOGETHER")
                    liveRow(key: "TURNS", title: "Takes turns with others", hue: amber,
                            isOn: { bit(altMask, $0) }, value: { max(1, at(altCount, $0, 1)) },
                            unit: "×", maxV: 8, minV: 1, onToggle: onToggleAlt, onSet: onAltCount)
                    dimRow("LEAD / STANCE")
                    dimRow("ECHO"); dimRow("CHOKE"); dimRow("GOVERNOR")
                    detailStrip
                }.padding(.bottom, 12)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(RoundedRectangle(cornerRadius: 8).fill(Color(red: 0.09, green: 0.10, blue: 0.12)))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(ink.opacity(0.08)))
    }

    // MARK: header — title + DONE
    private var headerBar: some View {
        HStack {
            Text("THE RACK").font(.system(size: 12, weight: .heavy, design: .monospaced)).tracking(2).foregroundColor(cyan)
            Spacer()
            Text("DONE").font(.system(size: 12, weight: .heavy, design: .monospaced)).foregroundColor(.black)
                .padding(.horizontal, 12).frame(height: 26)
                .background(RoundedRectangle(cornerRadius: 5).fill(ink.opacity(0.85)))
                .contentShape(Rectangle()).onTapGesture { onClose() }
        }
    }

    // MARK: column headers — the four emitters (hue dot · letter · ch · mini-meter). Tap = focus the readout.
    // A rack-OFF column reads RAW (its armed treatments don't apply — the two-tier law, made visible).
    private var columnHeaders: some View {
        HStack(spacing: 4) {
            Spacer().frame(width: rowLabelWidth)
            ForEach(0..<4, id: \.self) { i in
                let enabled = i < busEnabled.count ? busEnabled[i] : true
                let inPath = bit(rackMask, i)
                let pointed = i == focus
                VStack(spacing: 2) {
                    HStack(spacing: 3) {
                        Circle().fill(enabled ? cyan : ink.opacity(0.25)).frame(width: 6, height: 6)
                        Text(letters[i]).font(.system(size: 12, weight: .heavy, design: .monospaced))
                            .foregroundColor(pointed ? .black : (enabled ? ink.opacity(0.85) : ink.opacity(0.3)))
                    }
                    Text(inPath ? "ch\(at(busChannels, i, i + 1))" : "RAW")
                        .font(.system(size: 7, weight: .heavy, design: .monospaced))
                        .foregroundColor(inPath ? ink.opacity(0.5) : amber.opacity(0.8))
                    meterBar(i)
                }
                .frame(maxWidth: .infinity).padding(.vertical, 3)
                .background(RoundedRectangle(cornerRadius: 4).fill(pointed ? cyan.opacity(0.9) : ink.opacity(inPath ? 0.06 : 0.02)))
                .contentShape(Rectangle()).onTapGesture { focus = i }
            }
        }
    }

    private func meterBar(_ i: Int) -> some View {
        let p = i < emitPeak.count ? emitPeak[i] : 0
        return GeometryReader { g in
            ZStack(alignment: .leading) {
                Capsule().fill(ink.opacity(0.08))
                Capsule().fill(cyan.opacity(0.7)).frame(width: max(1, g.size.width * CGFloat(p)))
            }
        }.frame(height: 3).padding(.horizontal, 4)
    }

    // MARK: readout — the focused emitter's social sentence (only TRUE clauses)
    private var readout: some View {
        var clauses: [String] = []
        if bit(claimMask, focus) { clauses.append(at(claimLeak, focus, 0) > 0 ? "OWNS · leaks \(at(claimLeak, focus, 0))%" : "OWNS (hard)") }
        if bit(flattenMask, focus) { clauses.append("KEY: ducks others \(at(flattenAmount, focus, 0))%") }
        if bit(altMask, focus) { let n = max(1, at(altCount, focus, 1)); clauses.append("TURNS ×\(n)") }
        let raw = !bit(rackMask, focus)
        let line = raw ? "\(letters[focus]) — RAW (rack out of path)"
                       : (clauses.isEmpty ? "\(letters[focus]) — a plain voice, no pedals armed." : "\(letters[focus]) — " + clauses.joined(separator: "  ·  "))
        return Text(line).font(.system(size: 10, weight: .semibold, design: .monospaced))
            .foregroundColor(raw ? amber.opacity(0.75) : ink.opacity(0.6)).fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    private let rowLabelWidth: CGFloat = 132   // wide, for legible descriptive labels (user: trade space for legibility)
    private let knobSize: CGFloat = 30
    private func familyLabel(_ t: String) -> some View {
        Text(t).font(.system(size: 8, weight: .heavy, design: .monospaced)).tracking(1.5).foregroundColor(ink.opacity(0.4))
            .padding(.top, 4)
    }

    // MARK: a LIVE treatment row — a descriptive `title` (wide, wrapping) + 4 narrow columns of (toggle over a
    // rotary knob). `key` is the stable identity ("OWNS"/"KEY"/"TURNS") used for the detail strip + last-touched.
    // A rack-off column dims (its arming is inert until the strip patches the board back in).
    private func liveRow(key: String, title: String, hue: Color, isOn: @escaping (Int) -> Bool,
                         value: @escaping (Int) -> Int, unit: String, maxV: Int, minV: Int = 0,
                         onToggle: @escaping (Int) -> Void, onSet: @escaping (Int, Int) -> Void) -> some View {
        HStack(alignment: .center, spacing: 4) {
            Text(title).font(.system(size: 11, weight: .semibold, design: .monospaced))
                .foregroundColor(ink.opacity(0.8)).fixedSize(horizontal: false, vertical: true)
                .frame(width: rowLabelWidth, alignment: .leading)
            ForEach(0..<4, id: \.self) { i in
                let on = isOn(i), inPath = bit(rackMask, i)
                VStack(spacing: 4) {
                    Text(on ? "ON" : "·").font(.system(size: 9, weight: .heavy, design: .monospaced))
                        .foregroundColor(on ? .black : ink.opacity(0.45)).frame(maxWidth: .infinity).frame(height: 22)
                        .background(RoundedRectangle(cornerRadius: 3).fill(on ? hue.opacity(0.82) : ink.opacity(0.08)))
                        .contentShape(Rectangle()).onTapGesture { lastRow = key; onToggle(i) }
                    knob(rowKey: key, col: i, value: value(i), unit: unit, maxV: maxV, minV: minV, enabled: on, onSet: onSet)
                }
                .frame(maxWidth: .infinity)
                .opacity(inPath ? 1 : 0.4)   // two-tier law: a rack-off column's arming is inert (visibly recessive)
            }
        }
    }

    // A ROTARY knob for a treatment's primary param (user: rotary over a slider for legibility in the narrow
    // column). A 270° gauge + pointer; the reading sits beneath. A VERTICAL drag turns it (up = more) relative to
    // the value at drag start (one knob at a time). Recessive when the treatment is off.
    private func knob(rowKey: String, col: Int, value: Int, unit: String, maxV: Int, minV: Int,
                      enabled: Bool, onSet: @escaping (Int, Int) -> Void) -> some View {
        let key = "\(rowKey)-\(col)"
        let span = max(1, maxV - minV)
        let frac = CGFloat(value - minV) / CGFloat(span)
        let hue = enabled ? amber : ink.opacity(0.25)
        return VStack(spacing: 2) {
            ZStack {
                Circle().trim(from: 0, to: 0.75)
                    .stroke(ink.opacity(0.14), style: StrokeStyle(lineWidth: 2.5, lineCap: .round)).rotationEffect(.degrees(135))
                Circle().trim(from: 0, to: 0.75 * frac)
                    .stroke(hue.opacity(enabled ? 0.9 : 0.5), style: StrokeStyle(lineWidth: 2.5, lineCap: .round)).rotationEffect(.degrees(135))
                Capsule().fill(hue).frame(width: 2, height: knobSize * 0.36)
                    .offset(y: -knobSize * 0.22).rotationEffect(.degrees(-135 + 270 * Double(frac)))
            }
            .frame(width: knobSize, height: knobSize)
            Text(unit == "×" ? "×\(value)" : "\(value)\(unit)")
                .font(.system(size: 8, weight: .heavy, design: .monospaced))
                .foregroundColor(enabled ? amber.opacity(0.9) : ink.opacity(0.3))
        }
        .contentShape(Rectangle())
        .gesture(DragGesture(minimumDistance: 0)
            .onChanged { v in
                if dragKey != key { dragKey = key; dragBase = value; lastRow = rowKey }
                onSet(col, max(minV, min(maxV, dragBase + Int(-v.translation.height / 6))))
            }
            .onEnded { _ in dragKey = nil })
    }

    // MARK: a DIMMED future treatment row — present so the matrix never reflows when its engine lands.
    private func dimRow(_ label: String) -> some View {
        HStack(spacing: 4) {
            Text(label).font(.system(size: 9, weight: .heavy, design: .monospaced))
                .foregroundColor(ink.opacity(0.25)).frame(width: rowLabelWidth, alignment: .leading)
            ForEach(0..<4, id: \.self) { _ in
                Text("·").font(.system(size: 9, weight: .heavy, design: .monospaced)).foregroundColor(ink.opacity(0.18))
                    .frame(maxWidth: .infinity).frame(height: 22)
                    .background(RoundedRectangle(cornerRadius: 3).fill(ink.opacity(0.02)))
            }
        }
    }

    // MARK: the DETAIL STRIP — follows the last-touched row. Pass 1: the live rows' secondary params are named but
    // dimmed ("coming"); their engine is a later pass.
    private var detailStrip: some View {
        let detail: String
        switch lastRow {
        case "OWNS":  detail = "OWNS detail — SCOPE (CLASS | RANGE + lo/hi) · RELEASE LAG — coming"
        case "KEY":   detail = "KEY detail — DUCKS → B·C·D · ATTACK · RELEASE · MATCH-CLASS — coming"
        case "TURNS": detail = "TURNS detail — ROTATE | DEAL · RING · RESET-AT-PASS — coming"
        default:      detail = "Touch a row to see its detail."
        }
        return VStack(alignment: .leading, spacing: 4) {
            Divider().overlay(ink.opacity(0.12))
            Text(detail).font(.system(size: 9, weight: .semibold, design: .monospaced)).foregroundColor(ink.opacity(0.32))
                .frame(maxWidth: .infinity, alignment: .leading)
        }.padding(.top, 6)
    }
}
