import AppKit
import DigUpKit
import SwiftUI

/// Biblo's colors: Foundry's violet and indigo, with periwinkle and a little orchid in the ground. Violet is the ribbon
/// that marks your place in a book: it marks what Biblo finds, and in the search panel how surely (`ribbon`, `ink`).
/// It fills the search badge, the selected chip and onboarding's tiles (`button`, `accent`), and `Backdrop` washes every
/// window in it. Text stays the system's, so it reads on any ground.
enum Brand {
    static let violet = Color(red: 0.482, green: 0.361, blue: 1.0)         // #7B5CFF
    static let iris = Color(red: 0.416, green: 0.294, blue: 0.949)         // #6A4BF2
    static let indigo = Color(red: 0.290, green: 0.184, blue: 0.847)       // #4A2FD8
    static let periwinkle = Color(red: 0.557, green: 0.561, blue: 0.957)   // #8E8FF4
    static let orchid = Color(red: 0.784, green: 0.420, blue: 0.980)       // #C86BFA
    /// Accent icons, and the ribbon: light where it catches the light, deeper below; lighter in dark mode.
    static let gradient = LinearGradient(colors: [glowTop, glowBottom], startPoint: .top, endPoint: .bottom)
    static let ribbon = gradient
    /// Under a white symbol (the search badge, onboarding's tiles): ≥ 4.3:1 against white all the way.
    static let button = LinearGradient(colors: [violet, indigo], startPoint: .topLeading, endPoint: .bottomTrailing)
    static let tile = button
    /// Under white text (a selected chip): 5.4:1.
    static let accent = iris
    /// Violet for text, strokes and small marks: ≥ 5:1 on the window and the panel with their wash, light or dark.
    static let ink = adaptive("BibloInk", light: (0.333, 0.212, 0.839), dark: (0.718, 0.659, 1.0))   // #5536D6, #B7A8FF
    private static let glowTop = adaptive("BibloGlowTop", light: (0.482, 0.361, 1.0), dark: (0.761, 0.710, 1.0))
    private static let glowBottom = adaptive("BibloGlowBottom", light: (0.290, 0.184, 0.847), dark: (0.482, 0.361, 1.0))

    private static func adaptive(_ name: String, light: (CGFloat, CGFloat, CGFloat),
                                 dark: (CGFloat, CGFloat, CGFloat)) -> Color {
        Color(nsColor: NSColor(name: name) { @Sendable appearance in
            let (red, green, blue) = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? dark : light
            return NSColor(srgbRed: red, green: green, blue: blue, alpha: 1)
        })
    }
}

/// Biblo's ground, behind each window's content: violet glowing from the top-leading corner, periwinkle across the top
/// and orchid low on the other side, over the window's own background. Still. In light mode a faint violet-to-orchid
/// wash runs corner to corner and iris warms the bottom-leading corner, so no part of the window is plain grey.
struct Backdrop: View {
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let dark = scheme == .dark
        ZStack {
            if !dark {
                Color.white.opacity(0.35)
                LinearGradient(colors: [Brand.violet.opacity(0.07), Brand.periwinkle.opacity(0.03),
                                        Brand.orchid.opacity(0.09)],
                               startPoint: .topLeading, endPoint: .bottomTrailing)
            }
            glow(Brand.violet, dark ? 0.28 : 0.24, at: UnitPoint(x: 0.05, y: 0), reach: 0.8)
            glow(Brand.periwinkle, dark ? 0.12 : 0.2, at: UnitPoint(x: 0.82, y: 0), reach: 0.55)
            glow(Brand.orchid, dark ? 0.16 : 0.24, at: UnitPoint(x: 0.96, y: 1), reach: dark ? 0.7 : 0.75)
            if !dark { glow(Brand.iris, 0.08, at: UnitPoint(x: 0.1, y: 0.95), reach: 0.5) }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private func glow(_ color: Color, _ opacity: Double, at center: UnitPoint, reach: CGFloat) -> some View {
        EllipticalGradient(colors: [color.opacity(opacity), color.opacity(0)], center: center,
                           startRadiusFraction: 0, endRadiusFraction: reach)
    }
}

/// The search mark, at the field's trailing end: a violet disc with the magnifier, or code's mark while code is
/// searched. A click puts the cursor in the field.
struct SearchBadge: View {
    let code: Bool
    var side: CGFloat = 28
    var action: () -> Void = {}

    var body: some View {
        Button(action: action) {
            Image(systemName: code ? FileKind.code.symbol : "magnifyingglass")
                .font(.system(size: side * (code ? 0.36 : 0.44), weight: .bold))
                .foregroundStyle(.white)
                .frame(width: side, height: side)
                .background(Circle().fill(Brand.button).shadow(color: Brand.indigo.opacity(0.3), radius: 4, y: 2))
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .help(code ? "Buscando en tu código" : "Buscar")
        .accessibilityLabel(code ? "Buscando en tu código" : "Buscar")
    }
}

/// How the search panel moves: columns widening and results opening up, quick and settling without a wobble; with
/// Reduce Motion, a short fade of the same change.
enum Motion {
    static func lens(_ reduceMotion: Bool) -> Animation {
        reduceMotion ? .easeOut(duration: 0.12) : .spring(response: 0.32, dampingFraction: 0.84)
    }
}

/// ⇧ ⌘ Space as keycaps.
struct Keycaps: View {
    let caps: [String]
    var size: CGFloat = 12

    var body: some View {
        HStack(spacing: size * 0.3) {
            ForEach(Array(caps.enumerated()), id: \.offset) { _, cap in
                Text(cap)
                    .font(.system(size: size, weight: .medium, design: .rounded))
                    .frame(minWidth: size * 1.6)
                    .padding(.horizontal, size * 0.45)
                    .padding(.vertical, size * 0.28)
                    .background(RoundedRectangle(cornerRadius: size * 0.42, style: .continuous)
                        .fill(Color.primary.opacity(0.07)))
                    .overlay(RoundedRectangle(cornerRadius: size * 0.42, style: .continuous)
                        .strokeBorder(Color.primary.opacity(0.14), lineWidth: 0.5))
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(caps.joined(separator: " "))
    }
}

/// "p. 3" or "0:06" on a result: the page or moment that matched.
struct PlaceBadge: View {
    let text: String
    var onImage = false

    var body: some View {
        Text(text)
            .font(.system(size: 10, weight: .semibold).monospacedDigit())
            .foregroundStyle(onImage ? AnyShapeStyle(.white) : AnyShapeStyle(.primary))
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(Capsule().fill(onImage ? AnyShapeStyle(.black.opacity(0.6)) : AnyShapeStyle(.quaternary)))
    }
}

/// Where a moment sits in a recording: a track with the matched stretch lit.
struct MomentBar: View {
    let start: Double
    let end: Double
    let duration: Double
    /// Drawn over a picture: white on a dark track.
    var onImage = false
    /// Where playback is, while it plays.
    var playhead: Double?

    var body: some View {
        GeometryReader { geometry in
            let width = geometry.size.width
            let from = max(0, min(1, start / duration)), to = max(from, min(1, end / duration))
            ZStack(alignment: .leading) {
                Capsule().fill(onImage ? Color.white.opacity(0.3) : Color.primary.opacity(0.12))
                Capsule()
                    .fill(onImage ? Color.white : Brand.ink)
                    .frame(width: max(4, width * (to - from)))
                    .offset(x: width * from)
                if let playhead {
                    Circle()
                        .fill(Color.primary)
                        .frame(width: 9, height: 9)
                        .offset(x: width * max(0, min(1, playhead / duration)) - 4.5)
                }
            }
        }
        .frame(height: 4)
        .accessibilityLabel("En \(ResultRow.clock(start)) de \(ResultRow.clock(duration))")
    }
}

/// What a folder holds, compactly: 📷 136  🖼 104  📄 25 … (the full wording in the tooltip).
struct KindCounts: View {
    let counts: [FileKind: Int]
    /// The tooltip in Spanish, as the search window speaks.
    var spanish = false

    var body: some View {
        HStack(spacing: 10) {
            ForEach(FileKind.allCases.filter { (counts[$0] ?? 0) > 0 }, id: \.self) { kind in
                Label(spanish ? counts[kind]!.formatted(.number.locale(ResultRow.spanish)) : counts[kind]!.formatted(),
                      systemImage: kind.symbol)
                    .labelStyle(CompactLabel())
                    .lineLimit(1)
                    .fixedSize()
            }
        }
        .font(.system(size: 11).monospacedDigit())
        .foregroundStyle(.secondary)
        .help(description)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(description)
    }

    /// "136 screenshots, 104 images, 25 PDFs"
    var description: String {
        FileKind.allCases.compactMap { kind in
            counts[kind].flatMap { $0 > 0 ? (spanish ? kind.spanishCounted($0) : kind.counted($0)) : nil }
        }.joined(separator: ", ")
    }
}

private struct CompactLabel: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 3) {
            configuration.icon.font(.system(size: 10))
            configuration.title
        }
    }
}

extension FileKind {
    /// "1 screenshot", "25 PDFs", "6 audio files"
    func counted(_ count: Int) -> String {
        let one = count == 1
        let noun = switch self {
        case .screenshot: one ? "screenshot" : "screenshots"
        case .image: one ? "image" : "images"
        case .pdf: one ? "PDF" : "PDFs"
        case .doc: one ? "document" : "documents"
        case .audio: one ? "audio file" : "audio files"
        case .video: one ? "video" : "videos"
        case .code: one ? "code file" : "code files"
        }
        return "\(count.formatted()) \(noun)"
    }

    /// `counted`, in Spanish: "1 captura", "25 PDF", "6 audios".
    func spanishCounted(_ count: Int) -> String {
        let one = count == 1
        let noun = switch self {
        case .screenshot: one ? "captura" : "capturas"
        case .image: one ? "imagen" : "imágenes"
        case .pdf: "PDF"
        case .doc: one ? "documento" : "documentos"
        case .audio: one ? "audio" : "audios"
        case .video: one ? "vídeo" : "vídeos"
        case .code: one ? "archivo de código" : "archivos de código"
        }
        return "\(count.formatted(.number.locale(ResultRow.spanish))) \(noun)"
    }
}

/// System Settings → Privacy & Security → Files and Folders, where a folder denied in macOS's prompt can be allowed.
func openFolderPrivacySettings() {
    if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_FilesAndFolders") {
        NSWorkspace.shared.open(url)
    }
}

/// Matched words, which FTS marks with « », in bold.
func highlighted(_ text: String, size: CGFloat) -> AttributedString {
    var result = AttributedString()
    var bold = false
    var piece = ""
    func flush() {
        guard !piece.isEmpty else { return }
        var run = AttributedString(piece)
        if bold {
            run.font = .system(size: size, weight: .bold)
            run.foregroundColor = .primary
        }
        result += run
        piece = ""
    }
    for character in text {
        switch character {
        case "«": flush(); bold = true
        case "»": flush(); bold = false
        default: piece.append(character)
        }
    }
    flush()
    return result
}

/// Click, then press the new shortcut; Esc cancels. While it listens, the global hotkey steps aside (`listening`) so
/// that pressing the current one lands here instead of opening the panel.
struct ShortcutRecorder: View {
    let combo: KeyCombo?
    /// Tries a combination: nil when it's set, else why it can't be used.
    let apply: (KeyCombo) -> String?
    let listening: (Bool) -> Void
    var capSize: CGFloat = 15
    @State private var recording = false
    @State private var problem: String?

    var body: some View {
        VStack(spacing: 6) {
            Button { setRecording(!recording) } label: {
                Group {
                    if recording {
                        Text("Press the new shortcut…").foregroundStyle(.secondary)
                    } else if let combo {
                        Keycaps(caps: combo.caps, size: capSize)
                    } else {
                        Text("Click to set a shortcut").foregroundStyle(.secondary)
                    }
                }
                .font(.system(size: 13))
                .frame(minWidth: 190, minHeight: capSize * 2.4)
                .padding(.horizontal, 12)
                .contentShape(Rectangle())
                .background(RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .fill(Color.primary.opacity(recording ? 0.03 : 0.05)))
                .overlay(RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .strokeBorder(recording ? Brand.ink : Color.primary.opacity(0.15),
                                  lineWidth: recording ? 2 : 1))
            }
            .buttonStyle(.plain)
            .background(KeyCatcher(active: recording, onKey: handle, onResign: { setRecording(false) }))
            .accessibilityLabel(recording ? "Recording a new shortcut" : "Shortcut \(combo?.display ?? "none"), click to change")
            Text(problem ?? (recording ? "Esc cancels" : "Click to change"))
                .font(.system(size: 11))
                .foregroundStyle(problem == nil ? AnyShapeStyle(.tertiary) : AnyShapeStyle(Color.red))
                .multilineTextAlignment(.center)
        }
        .onDisappear { if recording { listening(false) } }
    }

    private func setRecording(_ on: Bool) {
        guard on != recording else { return }
        recording = on
        if !on { problem = nil }
        listening(on)
    }

    private func handle(_ event: NSEvent) {
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask).subtracting([.capsLock, .function,
                                                                                               .numericPad])
        if event.keyCode == 53, flags.isEmpty { return setRecording(false) }   // Esc
        guard let combo = KeyCombo(keyCode: event.keyCode, flags: flags) else {
            problem = "Use ⌘, ⌥ or ⌃ with a key"
            return
        }
        if let why = apply(combo) {
            problem = why
        } else {
            setRecording(false)
        }
    }
}

/// Takes key presses (⌘-combinations too, before any menu sees them) while `active`. `onResign`: the window or the
/// view lost the keyboard, so listening must stop (the global hotkey is off meanwhile).
private struct KeyCatcher: NSViewRepresentable {
    let active: Bool
    let onKey: (NSEvent) -> Void
    let onResign: () -> Void

    func makeNSView(context: Context) -> KeyCatcherView { KeyCatcherView() }

    func updateNSView(_ view: KeyCatcherView, context: Context) {
        view.onKey = onKey
        view.onResign = onResign
        guard view.active != active else { return }
        view.active = active
        DispatchQueue.main.async {
            if active {
                view.window?.makeFirstResponder(view)
            } else if view.window?.firstResponder === view {
                view.window?.makeFirstResponder(nil)
            }
        }
    }
}

private final class KeyCatcherView: NSView {
    var active = false
    var onKey: (NSEvent) -> Void = { _ in }
    var onResign: () -> Void = {}
    private var resignObserver: NSObjectProtocol?

    override var acceptsFirstResponder: Bool { active }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if let resignObserver { NotificationCenter.default.removeObserver(resignObserver) }
        resignObserver = nil
        guard let window else { return }
        resignObserver = NotificationCenter.default.addObserver(forName: NSWindow.didResignKeyNotification,
                                                                object: window, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, self.active else { return }
                self.onResign()
            }
        }
    }

    override func resignFirstResponder() -> Bool {
        if active { DispatchQueue.main.async { [weak self] in self?.onResign() } }
        return super.resignFirstResponder()
    }

    override func keyDown(with event: NSEvent) {
        if active { onKey(event) } else { super.keyDown(with: event) }
    }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        guard active, window?.firstResponder === self else { return super.performKeyEquivalent(with: event) }
        onKey(event)
        return true
    }
}
