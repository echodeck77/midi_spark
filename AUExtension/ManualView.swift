import SwiftUI

// THE IN-APP MANUAL (user 2026-08-05): a "?" in the header opens the manual scrolled to the LAST-TOUCHED control.
// Native SwiftUI (ScrollViewReader anchor-scroll — no WKWebView); the content is the bundled manual markdown.

/// Tracks the doc-anchor of the last-touched control. NOT @Published — read lazily when the "?" opens, so a touch
/// never triggers a re-render (the AuditionBox-style silent reference). Controls report via `.helpAnchor("#id")`.
final class HelpTracker: ObservableObject {
    var lastAnchor: String = ""   // the anchor id WITHOUT the leading '#', e.g. "recv-live"
}

/// A view modifier that records a control's manual anchor on touch (simultaneous tap → never steals the control's
/// own gesture). Apply as `.helpAnchor("#recv-live")` (the '#' is optional and stripped).
struct HelpAnchorModifier: ViewModifier {
    let anchor: String
    @EnvironmentObject private var help: HelpTracker
    func body(content: Content) -> some View {
        content.simultaneousGesture(TapGesture().onEnded { help.lastAnchor = anchor.hasPrefix("#") ? String(anchor.dropFirst()) : anchor })
    }
}
extension View { func helpAnchor(_ anchor: String) -> some View { modifier(HelpAnchorModifier(anchor: anchor)) } }

// MARK: - the parsed manual

struct ManualBlock: Identifiable {
    let id: Int
    let anchor: String?          // scroll target (without '#'); nil = not linkable
    let kind: Kind
    let text: String             // display text (the {#anchor} tokens stripped; inline markdown kept)
    enum Kind { case h1, h2, h3, bullet, para, rule }
}

enum ManualDoc {
    /// Load the bundled manual markdown (the plugin runs in the extension bundle).
    static func load() -> String {
        for b in [Bundle.main] + Bundle.allBundles {
            if let url = b.url(forResource: "manual-skeleton", withExtension: "md"),
               let s = try? String(contentsOf: url, encoding: .utf8) { return s }
        }
        return "# Manual\n\nThe manual resource is not bundled in this build."
    }

    /// Parse the manual's line-based markdown into blocks. The FIRST `{#anchor}` on a line becomes its scroll id;
    /// every `{#anchor}` token is stripped from the display text. Headings/bullets/rules by prefix.
    static func parse(_ md: String) -> [ManualBlock] {
        var blocks: [ManualBlock] = []
        var idx = 0
        for rawLine in md.components(separatedBy: "\n") {
            let line = rawLine.trimmingCharacters(in: CharacterSet(charactersIn: " "))
            if line.isEmpty { continue }
            // capture the first anchor, then strip ALL {#..} tokens
            var anchor: String? = nil
            if let r = line.range(of: "\\{#([A-Za-z0-9-]+)\\}", options: .regularExpression) {
                anchor = String(line[r].dropFirst(2).dropLast())
            }
            var body = line.replacingOccurrences(of: "\\{#[A-Za-z0-9-]+\\}", with: "", options: .regularExpression)
                           .trimmingCharacters(in: CharacterSet(charactersIn: " "))
            let kind: ManualBlock.Kind
            if body.hasPrefix("### ") { kind = .h3; body = String(body.dropFirst(4)) }
            else if body.hasPrefix("## ") { kind = .h2; body = String(body.dropFirst(3)) }
            else if body.hasPrefix("# ") { kind = .h1; body = String(body.dropFirst(2)) }
            else if body.hasPrefix("- ") { kind = .bullet; body = String(body.dropFirst(2)) }
            else if body.hasPrefix("---") { kind = .rule; body = "" }
            else { kind = .para }
            blocks.append(ManualBlock(id: idx, anchor: anchor, kind: kind, text: body))
            idx += 1
        }
        return blocks
    }
}

// MARK: - the reader

struct ManualView: View {
    let blocks: [ManualBlock]
    let initialAnchor: String    // the last-touched anchor (without '#'); "" = top
    let onClose: () -> Void

    private let ink = Color.white
    private let cyan = Color(red: 0.15, green: 0.88, blue: 0.94)

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("MANUAL").font(.system(size: 13, weight: .heavy, design: .monospaced)).tracking(2).foregroundColor(cyan)
                Spacer()
                Text("DONE").font(.system(size: 12, weight: .heavy, design: .monospaced)).foregroundColor(.black)
                    .padding(.horizontal, 12).frame(height: 28)
                    .background(RoundedRectangle(cornerRadius: 6).fill(ink.opacity(0.85)))
                    .contentShape(Rectangle()).onTapGesture { onClose() }
            }.padding(12)
            Divider().overlay(ink.opacity(0.12))
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 7) {
                        ForEach(blocks) { b in
                            row(b).id(b.anchor ?? "b\(b.id)")
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }.padding(14)
                }
                .onAppear {
                    guard !initialAnchor.isEmpty else { return }
                    DispatchQueue.main.async { withAnimation(.easeInOut(duration: 0.3)) { proxy.scrollTo(initialAnchor, anchor: .top) } }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Color(red: 0.07, green: 0.08, blue: 0.10))
    }

    @ViewBuilder private func row(_ b: ManualBlock) -> some View {
        let hit = b.anchor != nil && b.anchor == initialAnchor
        switch b.kind {
        case .rule:   Divider().overlay(ink.opacity(0.10)).padding(.vertical, 4)
        case .h1:     inline(b.text).font(.system(size: 18, weight: .heavy, design: .monospaced)).foregroundColor(cyan).padding(.top, 8)
        case .h2:     inline(b.text).font(.system(size: 15, weight: .heavy, design: .monospaced)).foregroundColor(ink.opacity(0.9)).padding(.top, 6)
        case .h3:     inline(b.text).font(.system(size: 13, weight: .heavy, design: .monospaced)).foregroundColor(ink.opacity(0.8)).padding(.top, 4)
        case .bullet: inline(b.text).font(.system(size: 12, design: .monospaced)).foregroundColor(ink.opacity(0.85))
                          .padding(8).background(RoundedRectangle(cornerRadius: 5).fill(hit ? cyan.opacity(0.14) : ink.opacity(0.03)))
                          .overlay(RoundedRectangle(cornerRadius: 5).stroke(hit ? cyan.opacity(0.6) : .clear, lineWidth: 1.5))
        case .para:   inline(b.text).font(.system(size: 12, design: .monospaced)).foregroundColor(ink.opacity(0.6))
        }
    }

    /// Render a line's inline markdown (**bold** / _italic_ / [links]) via AttributedString; fall back to plain text.
    private func inline(_ s: String) -> Text {
        if let a = try? AttributedString(markdown: s, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)) {
            return Text(a)
        }
        return Text(s)
    }
}
