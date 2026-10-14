import AppKit
import DigUpKit
import Observation
import Quartz
import SwiftUI

enum SearchPhase: Equatable {
    case empty       // nothing typed
    case words       // keyword results, meaning results on the way
    case meaning     // words + meaning: final
    case wordsOnly   // final, but there's no meaning search (the model is downloading, or the encoder failed)
    case codeHint    // "code:" and nothing yet: what to type
    case codeOff     // "code:" without code folders: how to turn code search on
}

/// The hotkey panel: type, and what you described surfaces in one column per format (documents, screenshots, images,
/// video, audio), each best match first. The column you're in widens and its selected result opens up into a card with
/// a big preview; the arrows move through a column, ←→ / Tab / ⌘1–⌘5 between them. Open / reveal / Quick Look / copy
/// / drag work on the selected result as before.
///
/// Every keystroke shows keyword results at once (file names, OCR and document text, the last word as a prefix).
/// After a short pause in typing the query is embedded and the full hybrid results replace them.
@Observable
final class SearchPanelController {
    static let width: CGFloat = 1160
    static let fieldHeight: CGFloat = 68
    static let expandedHeight: CGFloat = 620
    static let cornerRadius: CGFloat = 24
    static let typingPause: Duration = .milliseconds(120)
    /// How far the meaning gate may come down for a query with no stand-out answer (`Searcher.search`'s `depth`), so
    /// each format's column has its next-best matches too, each with how sure it is.
    static let columnDepth = 0.5

    var query = "" {
        didSet { if query != oldValue { queryChanged() } }
    }
    private(set) var results = ResultSet.empty
    /// The column the arrows move in: the best match's format, until you pick another.
    private(set) var focusedKind: ResultGroupKind?
    /// Each column's selected result, kept while you look at the others.
    private(set) var cursors: [ResultGroupKind: String] = [:]
    private(set) var phase = SearchPhase.empty
    /// The query is a search of code ("code: …"): the code index, and nothing else.
    private(set) var isCode = false
    private(set) var note: String?
    var encoder: EngineStatus.Encoder { model.status.encoder }

    @ObservationIgnored let model: AppModel
    @ObservationIgnored private let engine: Engine
    @ObservationIgnored private unowned let app: AppController
    @ObservationIgnored private var window: SearchPanelWindow?
    @ObservationIgnored weak var field: NSTextField?
    @ObservationIgnored private var generation = 0
    /// The generation whose final (meaning) results are showing; late keyword results must not replace them.
    @ObservationIgnored private var finalGeneration = -1
    @ObservationIgnored private var meaningTask: Task<Void, Never>?
    @ObservationIgnored private var keyMonitor: Any?
    @ObservationIgnored private var mouseMonitor: Any?
    @ObservationIgnored private var resignObserver: NSObjectProtocol?
    @ObservationIgnored private var keyWindowObserver: NSObjectProtocol?
    @ObservationIgnored private var shownAt = Date.distantPast
    @ObservationIgnored private var activity: NSObjectProtocol?
    /// True once ↑/↓ (or a click) moved the selection since the last edit: then Space previews instead of typing a
    /// space, and ←→ change columns instead of moving the caret.
    @ObservationIgnored private var navigated = false
    @ObservationIgnored private var typedAt = Date()
    @ObservationIgnored private var noteTask: Task<Void, Never>?
    /// Called when the final results for the current query are on screen (debug hooks use it).
    @ObservationIgnored var onFinalResults: (() -> Void)?
    /// Where ⌘C puts the file (debug runs use a private pasteboard so the real clipboard stays untouched).
    @ObservationIgnored var pasteboard = NSPasteboard.general

    init(app: AppController) {
        self.app = app
        model = app.model
        engine = app.engine
    }

    var isVisible: Bool { window?.isVisible == true }
    var windowNumber: Int { window?.windowNumber ?? 0 }
    var isPreviewing: Bool { QLPreviewPanel.sharedPreviewPanelExists() && QLPreviewPanel.shared().isVisible }
    /// Every result, column by column.
    var rowIDs: [String] { rows.map(\.id) }
    var rows: [ResultRow] { results.columns.flatMap(\.rows) }
    var focusedColumn: ResultColumn? { results.columns.first { $0.kind == focusedKind && !$0.isEmpty } }
    /// The selected result: the focused column's.
    var selection: String? { focusedKind.flatMap { cursors[$0] } }
    var selectedRow: ResultRow? { focusedColumn?.rows.first { $0.id == selection } }

    // MARK: Showing

    func toggle() {
        isVisible ? hide() : show()
    }

    func show() {
        let started = Date()
        shownAt = started
        engine.prewarm()
        let window = self.window ?? makeWindow()
        placeWindow(window)
        if AppController.offscreen { return }
        // Activate for real: a background app's main thread drops to efficiency cores (App Nap), which can make
        // search 5× slower.
        bringAppToFront()
        window.makeKeyAndOrderFront(nil)
        if let field {
            window.makeFirstResponder(field)
            field.currentEditor()?.selectAll(nil)   // like Spotlight: the last query, selected
        }
        installKeyMonitor()
        if activity == nil {
            activity = ProcessInfo.processInfo.beginActivity(options: .userInitiatedAllowingIdleSystemSleep,
                                                             reason: "Search panel open")
        }
        let shown = Date()
        DispatchQueue.main.async {
            // The next turn of the main loop, after the window's first layout and display.
            log("panel: shown in \(ms(since: started, until: shown)), drawn by \(ms(since: started))")
        }
    }

    func hide() {
        if QLPreviewPanel.sharedPreviewPanelExists(), QLPreviewPanel.shared().isVisible {
            QLPreviewPanel.shared().orderOut(nil)
        }
        window?.orderOut(nil)
        removeKeyMonitor()
        PreviewPlayback.shared.stop()
        if let activity { ProcessInfo.processInfo.endActivity(activity) }
        activity = nil
        Thumbnails.shared.clear()
        Previews.shared.clear()
    }

    // MARK: Searching

    private func queryChanged() {
        generation += 1
        let current = generation
        typedAt = Date()
        navigated = false
        meaningTask?.cancel()
        let typed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        let codeText = CodeQuery.text(of: typed)
        isCode = codeText != nil
        let code = isCode
        let text = codeText ?? typed
        guard !typed.isEmpty else {
            results = .empty
            clearSelection()
            phase = .empty
            resizeWindow()
            return
        }
        // "code:" alone, or without code folders: what to do instead of results.
        if code, !model.hasCode || text.isEmpty {
            results = .empty
            clearSelection()
            phase = model.hasCode ? .codeHint : .codeOff
            resizeWindow()
            return
        }
        // Words now. The last word is probably half-typed, so it matches as a prefix.
        Task {
            let started = Date()
            let hits = await engine.search(text, vector: nil, prefixLast: true, code: code)
            guard current == generation, finalGeneration != current else { return }
            show(hits, query: text, phase: .words)
            log("search \"\(typed)\": words \(hits.count) hits in \(ms(since: started))")
        }
        // Meaning results show once typing pauses, but they're computed now (embedding, then search), so they're
        // ready by then: the pause is the whole wait.
        engine.embedAhead(text, code: code)
        let showAt = ContinuousClock.now + Self.typingPause   // counted from the keystroke, not from when the task runs
        meaningTask = Task {
            let embedStarted = Date()
            let vector = await engine.embedQuery(text, code: code)
            guard !Task.isCancelled, current == generation else { return }
            let searchStarted = Date()
            let hits = await engine.search(text, vector: vector, prefixLast: false, depth: Self.columnDepth, code: code)
            let searched = Date()
            try? await Task.sleep(until: showAt, tolerance: .milliseconds(1), clock: .continuous)
            guard !Task.isCancelled, current == generation else { return }
            finalGeneration = current
            show(hits, query: text, phase: vector == nil ? .wordsOnly : .meaning)
            let shown = Date(), keystroke = typedAt
            log("search \"\(typed)\": \(vector == nil ? "words only" : "meaning") \(hits.count) hits "
                + "(\(results.strongRows.count) strong) · embed \(ms(since: embedStarted, until: searchStarted)) · "
                + "search \(ms(since: searchStarted, until: searched)) · shown \(ms(since: keystroke, until: shown)) after "
                + "the last keystroke")
            DispatchQueue.main.async {
                // The next turn of the main loop: the list and the preview pane have been laid out and drawn.
                log("search \"\(typed)\": drawn by \(ms(since: keystroke)) after the last keystroke")
            }
            onFinalResults?()
        }
    }

    private func show(_ hits: [SearchHit], query: String, phase: SearchPhase) {
        results = ResultSet(hits, query: query, code: isCode)
        let columns = results.columns.filter { !$0.isEmpty }
        if navigated, let kind = focusedKind, columns.contains(where: { $0.kind == kind }) {
            // You picked something: keep it wherever it's still there; the other columns start at their best.
            var kept: [ResultGroupKind: String] = [:]
            for column in columns {
                let id = cursors[column.kind]
                kept[column.kind] = column.rows.contains { $0.id == id } ? id : column.rows.first?.id
            }
            cursors = kept
        } else {
            // Follow the best match (and each column's) until you pick something.
            focusedKind = hits.first.map { ResultGroupKind($0.kind) } ?? columns.first?.kind
            cursors = Dictionary(uniqueKeysWithValues: columns.compactMap { column in
                column.rows.first.map { (column.kind, $0.id) }
            })
        }
        self.phase = phase
        resizeWindow()
        if QLPreviewPanel.sharedPreviewPanelExists(), QLPreviewPanel.shared().isVisible { updateQuickLook() }
    }

    private func clearSelection() {
        focusedKind = nil
        cursors = [:]
    }

    // MARK: Keys

    private func installKeyMonitor() {
        guard keyMonitor == nil else { return }
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self, self.isVisible, self.owns(event) else { return event }
            return self.handle(event) ? nil : event
        }
        // A click back in the search field: Space types again (after a click on a result, it previewed).
        mouseMonitor = NSEvent.addLocalMonitorForEvents(matching: .leftMouseDown) { [weak self] event in
            guard let self, let field, event.window === field.window else { return event }
            if field.bounds.contains(field.convert(event.locationInWindow, from: nil)) { navigated = false }
            return event
        }
        resignObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didResignActiveNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.hide() }
        }
        // Another of the app's windows came forward (⌘, or ⌘N while the panel was up): the panel steps away, like
        // Spotlight, rather than float over it and take its keys.
        keyWindowObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.didBecomeKeyNotification, object: nil, queue: .main
        ) { [weak self] note in
            let window = note.object as? NSWindow
            MainActor.assumeIsolated {
                guard let self, let window, window !== self.window, !(window is QLPreviewPanel) else { return }
                if Date().timeIntervalSince(self.shownAt) < 0.5 {
                    // Activating the app can hand the key to its last window just after the panel opened: take it back.
                    self.window?.makeKey()
                } else {
                    self.hide()
                }
            }
        }
    }

    private func removeKeyMonitor() {
        for monitor in [keyMonitor, mouseMonitor].compactMap({ $0 }) { NSEvent.removeMonitor(monitor) }
        keyMonitor = nil
        mouseMonitor = nil
        for observer in [resignObserver, keyWindowObserver].compactMap({ $0 }) {
            NotificationCenter.default.removeObserver(observer)
        }
        resignObserver = nil
        keyWindowObserver = nil
    }

    /// Keys typed in the panel, or in Quick Look while the panel is the one showing it.
    private func owns(_ event: NSEvent) -> Bool {
        if event.window === window { return true }
        guard QLPreviewPanel.sharedPreviewPanelExists(), let preview = QLPreviewPanel.shared() else { return false }
        return event.window === preview && preview.dataSource === window
    }

    /// True when the key was handled here (it then doesn't reach the search field).
    private func handle(_ event: NSEvent) -> Bool {
        // An input method is composing (Japanese, Chinese…): ↩, the arrows and Esc are its keys until it's done.
        if (field?.currentEditor() as? NSTextView)?.hasMarkedText() == true { return false }
        let modifiers = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
            .subtracting([.capsLock, .numericPad, .function])
        let previewing = QLPreviewPanel.sharedPreviewPanelExists() && QLPreviewPanel.shared().isVisible
        switch event.keyCode {
        case 53:  // Esc
            if previewing { QLPreviewPanel.shared().orderOut(nil) } else { dismiss() }
            return true
        case 125, 126:  // ↓ ↑
            guard modifiers.isEmpty else { return false }
            moveSelection(by: event.keyCode == 125 ? 1 : -1)
            navigated = true
            return true
        case 123, 124:  // ← →: another format, once you're among the results (before that they move the caret)
            guard modifiers.isEmpty, navigated, focusedColumn != nil else { return false }
            moveColumn(by: event.keyCode == 124 ? 1 : -1, wrap: false)
            return true
        case 48:  // Tab, ⇧Tab: another format, always
            guard modifiers.isEmpty || modifiers == .shift, focusedColumn != nil else { return false }
            moveColumn(by: modifiers == .shift ? -1 : 1, wrap: true)
            navigated = true
            return true
        case 18, 19, 20, 21, 23:  // ⌘1…⌘5: that format's column (in its fixed place)
            guard modifiers == .command, let number = [18: 0, 19: 1, 20: 2, 21: 3, 23: 4][event.keyCode],
                  focusedColumn != nil else { return false }
            focusColumn(at: number)
            return true
        case 36, 76:  // ↩, enter
            if modifiers == .command {
                revealSelected()
            } else if modifiers.isEmpty {
                openSelected()
            } else {
                return false
            }
            return true
        case 49 where modifiers.isEmpty && (navigated || previewing) && selection != nil:  // Space
            toggleQuickLook()
            return true
        case 16 where modifiers == .command:  // ⌘Y
            toggleQuickLook()
            return true
        case 31 where modifiers == .command:  // ⌘O: the same search in the window, for a bigger look
            openInWindow()
            return true
        case 8 where modifiers == .command:
            // ⌘C copies the selected file, except right after you selected some of the query text (the panel opens
            // with the last query selected, and arrowing to a result means you want the file).
            let textSelected = (field?.currentEditor()?.selectedRange.length ?? 0) > 0
            if textSelected, !navigated { return false }
            copySelected()
            return true
        default:
            return false
        }
    }

    /// ↑↓: up and down the focused column.
    func moveSelection(by step: Int) {
        guard let column = focusedColumn else { return }
        let ids = column.rows.map(\.id)
        let index = cursors[column.kind].flatMap { ids.firstIndex(of: $0) } ?? 0
        cursors[column.kind] = ids[max(0, min(ids.count - 1, index + step))]
        quickLookFollows()
    }

    /// ←→ / Tab: the next column with results (Tab wraps around).
    func moveColumn(by step: Int, wrap: Bool) {
        let kinds = results.columns.filter { !$0.isEmpty }.map(\.kind)
        guard !kinds.isEmpty else { return }
        let index = focusedKind.flatMap { kinds.firstIndex(of: $0) } ?? 0
        let next = wrap ? (index + step + kinds.count) % kinds.count : max(0, min(kinds.count - 1, index + step))
        focus(kinds[next])
    }

    /// ⌘1…⌘5: the column in that place, if it has results.
    func focusColumn(at index: Int) {
        guard results.columns.indices.contains(index), !results.columns[index].isEmpty else { return NSSound.beep() }
        focus(results.columns[index].kind)
    }

    /// A column, at the result it had selected.
    func focus(_ kind: ResultGroupKind) {
        guard let column = results.columns.first(where: { $0.kind == kind }), !column.isEmpty else { return }
        if cursors[kind] == nil { cursors[kind] = column.rows.first?.id }
        focusedKind = kind
        navigated = true
        quickLookFollows()
    }

    func select(_ row: ResultRow) {
        let kind = ResultGroupKind(row.kind)
        cursors[kind] = row.id
        focusedKind = kind
        navigated = true
        quickLookFollows()
    }

    private func quickLookFollows() {
        if QLPreviewPanel.sharedPreviewPanelExists(), QLPreviewPanel.shared().isVisible { updateQuickLook() }
    }

    // MARK: Actions

    /// ↩: the file in its app, at the page or moment that matched when the app can be told where.
    func openSelected() {
        guard let row = selectedRow else { return }
        engine.open(row)
        hide()
    }

    func revealSelected() {
        guard let row = selectedRow else { return }
        NSWorkspace.shared.activateFileViewerSelecting([row.url])
        hide()
    }

    func copySelected() {
        guard let row = selectedRow else { return }
        pasteboard.clearContents()
        // As a file, like ⌘C in Finder: paste into a folder, a chat or a mail.
        pasteboard.writeObjects([row.url as NSURL])
        flash("Copiado: \(row.name)")
    }

    /// The search window, with this query (and only one kind, if given): for a bigger look.
    func openInWindow(_ kind: ResultGroupKind? = nil) {
        let text = query
        hide()
        app.showSearchWindow(query: text, kind: kind)
    }

    /// No folders yet: hide, and open where they're chosen.
    func chooseFolders() {
        hide()
        app.chooseFolders()
    }

    /// "code:" without code search: hide, and open where code folders are chosen.
    func setUpCodeSearch() {
        hide()
        app.chooseCodeFolders()
    }

    /// An example from the code hint, as if typed.
    func tryExample(_ text: String) {
        query = text
    }

    /// Esc: hide, and give the keyboard back to the app you came from.
    private func dismiss() {
        hide()
        NSApp.hide(nil)
    }

    private func flash(_ text: String) {
        note = text
        noteTask?.cancel()
        noteTask = Task {
            try? await Task.sleep(for: .seconds(1.6))
            guard !Task.isCancelled else { return }
            note = nil
        }
    }

    // MARK: Quick Look

    func toggleQuickLook() {
        let panel = QLPreviewPanel.shared()!
        if QLPreviewPanel.sharedPreviewPanelExists(), panel.isVisible {
            panel.orderOut(nil)
        } else if selectedRow != nil {
            updateQuickLook()
            panel.makeKeyAndOrderFront(nil)
        }
    }

    /// Quick Look shows the selected result at its page or moment.
    private func updateQuickLook() {
        window?.previewURL = selectedRow?.url
        QLPreviewPanel.shared().reloadData()
        QuickLookMoment.show(selectedRow, in: QLPreviewPanel.shared())
    }

    // MARK: Window

    private func makeWindow() -> SearchPanelWindow {
        let window = SearchPanelWindow()
        let hosting = NSHostingView(rootView: SearchPanelView(controller: self).tint(Brand.accent))
        hosting.sizingOptions = []
        window.contentView = Self.background(containing: hosting)
        self.window = window
        return window
    }

    private var desiredHeight: CGFloat {
        guard !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return Self.fieldHeight }
        // A short screen (a 13" laptop's 832 points) keeps a margin under the panel.
        let screen = (window?.screen ?? NSScreen.main)?.visibleFrame.height ?? 900
        return min(Self.expandedHeight, (screen * 0.78).rounded())
    }

    /// Centered on the screen with the pointer, a little above the middle, like Spotlight; as wide as fits.
    private func placeWindow(_ window: NSWindow) {
        let screen = NSScreen.screens.first { NSMouseInRect(NSEvent.mouseLocation, $0.frame, false) } ?? NSScreen.main
        let area = screen?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        let top = area.maxY - area.height * 0.14
        let width = min(Self.width, area.width - 48)
        let height = desiredHeight
        window.setFrame(NSRect(x: area.midX - width / 2, y: top - height, width: width, height: height),
                        display: true)
    }

    /// Grows or shrinks downward, keeping the search field where it is.
    private func resizeWindow() {
        guard let window else { return }
        let height = desiredHeight
        guard abs(window.frame.height - height) > 0.5 else { return }
        // Not in the middle of a SwiftUI update: resizing from inside one sizes the view wrong.
        DispatchQueue.main.async {
            var frame = window.frame
            frame.origin.y += frame.height - height
            frame.size.height = height
            window.setFrame(frame, display: true)
        }
    }

    /// Glass (or vibrancy before macOS 26) behind the SwiftUI content. The content sits beside the glass rather than
    /// inside it, since NSGlassEffectView resizes its contentView itself.
    private static func background(containing content: NSView) -> NSView {
        let radius = cornerRadius
        let backdrop: NSView
        if #available(macOS 26.0, *) {
            let glass = NSGlassEffectView()
            glass.cornerRadius = radius
            backdrop = glass
        } else {
            let effect = NSVisualEffectView()
            effect.material = .popover
            effect.state = .active
            effect.blendingMode = .behindWindow
            effect.wantsLayer = true
            effect.layer?.cornerRadius = radius
            effect.layer?.masksToBounds = true
            backdrop = effect
        }
        let container = NSView()
        for view in [backdrop, content] {
            view.frame = container.bounds
            view.autoresizingMask = [.width, .height]
            container.addSubview(view)
        }
        return container
    }

    /// Draws the panel into a PNG (see `Snapshot`); the glass doesn't draw that way, so it's on the window color.
    func snapshot(to url: URL) throws {
        try Snapshot.write(window, to: url, cornerRadius: Self.cornerRadius)
    }
}

/// The floating panel. Unlike most floating panels it becomes key, because you type into it.
final class SearchPanelWindow: NSPanel, QLPreviewPanelDataSource {
    /// What Space / ⌘Y previews.
    var previewURL: URL?

    init() {
        super.init(contentRect: NSRect(x: 0, y: 0, width: SearchPanelController.width,
                                       height: SearchPanelController.fieldHeight),
                   styleMask: [.borderless, .fullSizeContentView], backing: .buffered, defer: true)
        isFloatingPanel = true
        level = .floating
        hidesOnDeactivate = false   // the controller hides it, and also tidies up
        collectionBehavior = [.moveToActiveSpace, .fullScreenAuxiliary, .ignoresCycle]
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        isReleasedWhenClosed = false
        animationBehavior = .none
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    // Quick Look asks the responder chain who controls it; the panel does. (These come from a nonisolated NSObject
    // category; Quick Look calls them on the main thread.)
    nonisolated override func acceptsPreviewPanelControl(_ panel: QLPreviewPanel!) -> Bool { true }

    nonisolated override func beginPreviewPanelControl(_ panel: QLPreviewPanel!) {
        MainActor.assumeIsolated {
            panel.dataSource = self
            // Above the floating search panel.
            panel.level = NSWindow.Level(rawValue: level.rawValue + 1)
        }
    }

    nonisolated override func endPreviewPanelControl(_ panel: QLPreviewPanel!) {
        MainActor.assumeIsolated {
            panel.dataSource = nil
        }
    }

    func numberOfPreviewItems(in panel: QLPreviewPanel!) -> Int {
        previewURL == nil ? 0 : 1
    }

    func previewPanel(_ panel: QLPreviewPanel!, previewItemAt index: Int) -> (any QLPreviewItem)! {
        previewURL as NSURL?
    }
}
