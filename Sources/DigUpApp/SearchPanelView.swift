import AppKit
import DigUpKit
import SwiftUI

// Biblo · contrato de diseño del panel (impeccable; también en .impeccable/brief.md y DESIGN.md)
// TESIS: encontrar es reconocer. Biblo no da una lista: abre cada formato por donde más probable es que esté.
// MUNDO PROPIO: Biblos, la ciudad fenicia que dio nombre al libro; tu Mac como biblioteca. Cristal del sistema con un
//   velo violeta quieto (`Backdrop`: violeta, pervinca y orquídea, los de Foundry), y una sola cinta de registro violeta
//   que marca dónde está. La lupa es un disco violeta al final de la barra, nunca al principio.
// HISTORIA: escribes como lo recuerdas → cada formato abre su estante → la cinta cae por cada columna, ancha donde
//   más acierta → al bajar, cada hallazgo sale del estante y se abre grande.
// PRIMERA VISTA: la barra; columnas por formato en orden fijo; la activa ancha, con su mejor hallazgo abierto y su
//   % de acierto.
// FORMA: columnas con muelle, lupa vertical, cinta que adelgaza con la probabilidad; SF Pro con cifras tabulares.
//   Nada de neón, ni texto en degradado, ni crema con serifa, ni rótulos mono en mayúsculas.

/// The hotkey panel: the search field between Biblo's ribbon, hanging from the panel's top edge, and the search badge;
/// one column per format underneath (`ColumnsView`), and a footer saying what the keys do. The panel speaks Spanish.
struct SearchPanelView: View {
    @Bindable var controller: SearchPanelController

    var body: some View {
        VStack(spacing: 0) {
            header
            if controller.phase != .empty {
                Divider().opacity(0.5)
                content
                    .frame(maxHeight: .infinity)
                Divider().opacity(0.5)
                footer
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        // Glass alone is too see-through over busy backgrounds; Biblo's violet glows through what covers it.
        .background {
            ZStack {
                Color(nsColor: .windowBackgroundColor).opacity(0.75)
                Backdrop()
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: SearchPanelController.cornerRadius, style: .continuous))
    }

    private var header: some View {
        HStack(spacing: 14) {
            RibbonMark(hang: hang)
                .frame(width: 24, height: SearchPanelController.fieldHeight, alignment: .top)
            // With code search on, one example is code's: nothing else in the panel shows "code:".
            SearchField(text: $controller.query, fontSize: 24,
                        placeholder: controller.model.hasCode
                            ? "Descríbelo como lo recuerdes: «pingüino en un vídeo», «code: reintentar con espera»…"
                            : "Descríbelo como lo recuerdes: «receta de paella», «pingüino en un vídeo»…",
                        label: "Buscar") {
                controller.field = $0
            }
            if controller.phase == .words, controller.encoder == .starting {
                ProgressView().controlSize(.small)
            }
            if let activity = controller.model.panelBadge {
                Text(activity)
                    .font(.system(size: 11, weight: .medium).monospacedDigit())
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(Capsule().fill(Color.primary.opacity(0.07)))
                    .help(controller.model.spanishStatusLine)
            }
            // A search of code shows it: code's mark in the badge.
            SearchBadge(code: controller.isCode, side: 34) { focusField() }
        }
        .padding(.leading, 22)
        .padding(.trailing, 16)
        .frame(height: SearchPanelController.fieldHeight)
    }

    private func focusField() {
        guard let field = controller.field else { return }
        field.window?.makeFirstResponder(field)
    }

    /// How far the ribbon hangs: short with nothing found, swaying while meaning search warms up, long over results.
    private var hang: RibbonMark.Hang {
        if controller.phase == .words, controller.encoder == .starting { return .swaying }
        return controller.results.isEmpty ? .short : .long
    }

    @ViewBuilder private var content: some View {
        if controller.phase == .codeHint || controller.phase == .codeOff {
            CodeHint(controller: controller)
        } else if controller.results.isEmpty {
            VStack(spacing: 8) {
                if controller.phase == .words {
                    Text("Buscando…").foregroundStyle(.secondary)
                } else if !controller.model.hasFolders {
                    Text("Aún no hay carpetas").font(.system(size: 15, weight: .semibold))
                    Text("Biblo solo busca en las carpetas que elijas.").foregroundStyle(.secondary)
                    Button("Elegir carpetas…") { controller.chooseFolders() }
                        .padding(.top, 4)
                } else if controller.isCode {
                    Text("Nada parecido en tu código").font(.system(size: 15, weight: .semibold))
                    Text("Prueba a decir qué hace el código, o un nombre que aparezca en él.")
                        .foregroundStyle(.secondary)
                } else {
                    Text("Nada parecido en tus carpetas").font(.system(size: 15, weight: .semibold))
                    Text("Prueba con lo que se veía o se oía, o con palabras que recuerdes.")
                        .foregroundStyle(.secondary)
                }
            }
            .font(.system(size: 13))
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            ColumnsView(controller: controller)
        }
    }

    private var footer: some View {
        HStack(spacing: 12) {
            Text(statusText)
                .foregroundStyle(.secondary)
                .lineLimit(1)
            Spacer(minLength: 8)
            Text(keysText)
                .foregroundStyle(.tertiary)
                .lineLimit(1)
        }
        .font(.system(size: 11).monospacedDigit())
        .padding(.horizontal, 20)
        .frame(height: 32)
    }

    /// The keys, saying where ↩ goes: "↩ abrir en 0:06", and for code at which line: "↩ abrir en Zed, línea 12".
    private var keysText: String {
        let row = controller.selectedRow
        var open = "↩ " + (row?.spanishOpenTitle ?? "abrir")
        if let row, row.kind == .code, row.segment == .lines { open += ", línea \(row.codeLine)" }
        let formats = controller.results.columns.count { !$0.isEmpty } > 1 ? "⇥ otro formato   " : ""
        return "↑↓ recorrer   \(formats)\(open)   ␣ vista rápida   ⌘↩ Finder   ⌘C copiar"
    }

    private var statusText: String {
        if let note = controller.note { return note }
        switch controller.phase {
        case .words:
            return controller.encoder == .starting ? "Buscando por palabras; el significado llega enseguida…"
                                                   : "Buscando por palabras…"
        case .wordsOnly:
            return controller.model.panelMeaningUnavailable
                ?? "Solo por palabras: la búsqueda por significado no está disponible"
        case .codeHint, .codeOff:
            return controller.phase == .codeOff ? "La búsqueda de código está apagada" : "Buscando en tu código"
        case .meaning, .empty:
            if controller.isCode, let indexing = controller.model.status.code.indexing, indexing.total > 0 {
                let percent = Int(Double(indexing.done) / Double(indexing.total) * 100)
                return "Aún leyendo código (\(percent) %): falta una parte"
            }
            if !controller.isCode, let caveat = controller.model.panelCaveat { return caveat }
            let columns = controller.results.columns.filter { !$0.isEmpty }
            let strong = columns.reduce(0) { $0 + $1.strong }
            let weaker = controller.results.weaker.count
            let formats = columns.count { $0.strong > 0 }
            let found = strong == 1 ? "1 hallazgo" : "\(strong) hallazgos"
            let place = controller.isCode ? " en tu código"
                : formats == 1 ? " en 1 formato" : " en \(formats) formatos"
            return found + place + (weaker > 0 ? " · \(weaker) con menos acierto" : "")
        }
    }
}

extension AppModel {
    /// `activityBadge`, in the panel's words: "Indexando 42 %".
    var panelBadge: String? {
        if download.isActive { return "Descargando modelo · \(Int(download.fraction * 100)) %" }
        if case .indexing(let done, let total) = status.activity, total > 0 {
            return "Indexando \(Int(Double(done) / Double(total) * 100)) %"
        }
        if status.paused, status.pending > 0 { return "Indexado en pausa" }
        return nil
    }

    /// `meaningUnavailable`, in the panel's words.
    var panelMeaningUnavailable: String? {
        guard !download.isReady else { return nil }
        if download.isActive {
            return "Solo por palabras hasta que se descargue el modelo (\(Int(download.fraction * 100)) %)"
        }
        return "Solo por palabras: el modelo no está descargado"
    }

    /// `resultsCaveat`, in the panel's words.
    var panelCaveat: String? {
        if let panelMeaningUnavailable { return panelMeaningUnavailable }
        if case .indexing(let done, let total) = status.activity, total > 0 {
            return "Aún indexando (\(Int(Double(done) / Double(total) * 100)) %): faltan archivos"
        }
        if status.pending > 0 {
            return status.pending == 1 ? "Falta 1 archivo por indexar"
                : "Faltan \(status.pending.formatted(.number.locale(ResultRow.spanish))) archivos por indexar"
        }
        return nil
    }

    /// `statusLine`, in Spanish: the search window's status bar and the panel's activity tooltip.
    var spanishStatusLine: String {
        let status = self.status
        guard hasFolders else { return "Aún no hay carpetas" }
        if let folder = status.opening { return "Esperando acceso a \((folder as NSString).lastPathComponent)" }
        switch status.activity {
        case .starting: return "Arrancando…"
        case .failed(let problem): return "⚠︎ \(problem)"
        case .syncing: return "Revisando carpetas…"
        case .indexing(let done, let total):
            return "Indexando \(Self.percent(done, of: total)) % · \(Self.number(done)) de \(Self.number(total))"
        case .finishing(let done, let total, let files):
            let which = files == 1 ? "1 archivo largo" : files > 0 ? "\(Self.number(files)) archivos largos"
                : "los archivos largos"
            return "Terminando de leer \(which) · \(Self.percent(done, of: total)) %"
        case .idle:
            if let line = spanishDownloadLine { return line }
            if let code = status.code.indexing, code.total > 0 {
                return "Indexando código \(Self.percent(code.done, of: code.total)) % · "
                    + "\(Self.number(code.done)) de \(Self.number(code.total))"
            }
            let reason = status.waitingFor.map(Self.spanishWaiting)
            if status.pending > 0 {
                let waiting = status.pending == 1 ? "1 archivo en espera" : "\(Self.number(status.pending)) archivos en espera"
                if status.paused { return "En pausa · \(waiting)" }
                if let reason { return "\(waiting) · \(reason)" }
                return status.pending == 1 ? "Falta 1 archivo por indexar"
                    : "Faltan \(Self.number(status.pending)) archivos por indexar"
            }
            if status.unfinished > 0 {
                let rest = status.unfinished == 1 ? "1 archivo largo por terminar"
                    : "\(Self.number(status.unfinished)) archivos largos por terminar"
                if status.paused { return "En pausa · \(rest)" }
                if let reason { return "\(rest) · \(reason)" }
            }
            let indexed = status.searchable == 1 ? "1 archivo indexado" : "\(Self.number(status.searchable)) archivos indexados"
            return indexed + (status.paused ? " · en pausa" : "")
        }
    }

    /// `downloadLine`, in Spanish.
    private var spanishDownloadLine: String? {
        switch download.phase {
        case .ready: nil
        case .downloading: "Descargando el modelo · \(Int(download.fraction * 100)) %"
        case .verifying: "Comprobando la descarga del modelo…"
        case .retrying: "Descarga del modelo: esperando a la red"
        case .failed: "⚠︎ La descarga del modelo se ha detenido"
        case .needed: status.pending > 0 ? "El modelo aún no está descargado" : nil
        }
    }

    /// Why the first pass waits (`PowerPolicy.backfillBlocker`), in Spanish.
    private static func spanishWaiting(_ reason: String) -> String {
        switch reason {
        case "Low Power Mode": "modo de bajo consumo"
        case "Mac is warm": "el Mac está caliente"
        case "on battery": "con batería"
        default: reason
        }
    }

    private static func number(_ value: Int) -> String { value.formatted(.number.locale(ResultRow.spanish)) }

    private static func percent(_ done: Int, of total: Int) -> Int {
        total > 0 ? Int((Double(done) / Double(total) * 100).rounded(.down)) : 0
    }
}

struct ThumbnailView: View {
    static let side: CGFloat = 36
    let url: URL
    var side: CGFloat = ThumbnailView.side
    /// The file type's icon, not a picture of the file.
    var iconOnly = false
    @State private var image: NSImage?
    @Environment(\.displayScale) private var scale

    var body: some View {
        ZStack {
            if let image {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } else {
                Image(nsImage: NSWorkspace.shared.icon(forFile: url.path))
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .padding(2)
            }
        }
        .frame(width: side, height: side)
        .clipShape(RoundedRectangle(cornerRadius: side > 60 ? 8 : 6, style: .continuous))
        .task(id: url) {
            guard !iconOnly else { return }
            image = Thumbnails.shared.cached(url, side: side)
            if image == nil {
                image = await Thumbnails.shared.load(url, side: side, scale: scale)
            }
        }
    }
}

/// The search field. AppKit, so the panel and the window can focus it and see its text selection (for ⌘C) directly;
/// the arrows, ↩ and Esc never reach it, because their key monitors take those first.
struct SearchField: NSViewRepresentable {
    @Binding var text: String
    var fontSize: CGFloat = 22
    let placeholder: String
    /// What VoiceOver calls the field.
    var label = "Search"
    var onMake: (NSTextField) -> Void = { _ in }
    /// The field got the cursor (true) or lost it (false).
    var onFocus: (Bool) -> Void = { _ in }

    func makeNSView(context: Context) -> NSTextField {
        let field = FocusReportingField()
        field.onFocus = onFocus
        field.isBordered = false
        field.drawsBackground = false
        field.focusRingType = .none
        field.font = .systemFont(ofSize: fontSize)
        field.placeholderString = placeholder
        field.usesSingleLineMode = true
        field.cell?.isScrollable = true
        field.cell?.wraps = false
        field.delegate = context.coordinator
        field.setAccessibilityLabel(label)
        onMake(field)
        return field
    }

    func updateNSView(_ field: NSTextField, context: Context) {
        context.coordinator.text = $text
        (field as? FocusReportingField)?.onFocus = onFocus
        if field.stringValue != text { field.stringValue = text }
        if field.placeholderString != placeholder { field.placeholderString = placeholder }
    }

    func makeCoordinator() -> Coordinator { Coordinator(text: $text) }

    final class Coordinator: NSObject, NSTextFieldDelegate {
        var text: Binding<String>

        init(text: Binding<String>) {
            self.text = text
        }

        func controlTextDidChange(_ notification: Notification) {
            guard let field = notification.object as? NSTextField else { return }
            text.wrappedValue = field.stringValue
        }
    }
}

/// A text field that says when it gets the cursor and when it gives it up (its editing ends).
final class FocusReportingField: NSTextField {
    var onFocus: (Bool) -> Void = { _ in }

    override func becomeFirstResponder() -> Bool {
        let became = super.becomeFirstResponder()
        if became { onFocus(true) }
        return became
    }

    override func textDidEndEditing(_ notification: Notification) {
        super.textDidEndEditing(notification)
        onFocus(false)
    }
}

/// Click to select, double-click to open, drag to copy the file into Finder, Mail, a chat… (an AppKit dragging
/// source, `FileDragView`).
struct FileDragArea: NSViewRepresentable {
    let url: URL
    /// "Open at 0:06": what double-click and the menu's first item do.
    var openTitle = "Open"
    /// The menu in Spanish (the search panel's language).
    var spanish = false
    let onClick: () -> Void
    let onOpen: () -> Void

    func makeNSView(context: Context) -> FileDragView { FileDragView() }

    func updateNSView(_ view: FileDragView, context: Context) {
        view.url = url
        view.openTitle = openTitle
        view.spanish = spanish
        view.onClick = onClick
        view.onOpen = onOpen
    }
}

final class FileDragView: NSView, NSDraggingSource {
    var url: URL?
    var openTitle = "Open"
    var spanish = false
    var onClick: () -> Void = {}
    var onOpen: () -> Void = {}
    private var mouseDownEvent: NSEvent?

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func mouseDown(with event: NSEvent) {
        if event.clickCount == 2 {
            mouseDownEvent = nil
            onOpen()
        } else {
            mouseDownEvent = event
            onClick()
        }
    }

    override func mouseDragged(with event: NSEvent) {
        guard let down = mouseDownEvent, let url else { return }
        let dx = event.locationInWindow.x - down.locationInWindow.x
        let dy = event.locationInWindow.y - down.locationInWindow.y
        guard dx * dx + dy * dy > 9 else { return }
        mouseDownEvent = nil
        let item = NSDraggingItem(pasteboardWriter: url as NSURL)
        let point = convert(down.locationInWindow, from: nil)
        let side: CGFloat = 44
        let image = Thumbnails.shared.cached(url, side: ThumbnailView.side) ?? NSWorkspace.shared.icon(forFile: url.path)
        item.setDraggingFrame(NSRect(x: point.x - side / 2, y: point.y - side / 2, width: side, height: side),
                              contents: image)
        beginDraggingSession(with: [item], event: down, source: self)
    }

    override func mouseUp(with event: NSEvent) {
        mouseDownEvent = nil
    }

    /// Right-click: select it, and offer what you'd do with a file.
    override func menu(for event: NSEvent) -> NSMenu? {
        guard let url else { return nil }
        onClick()
        let menu = NSMenu()
        menu.addItem(ActionMenuItem(openTitle) { [onOpen] in onOpen() })
        menu.addItem(ActionMenuItem(spanish ? "Mostrar en el Finder" : "Show in Finder") { NSWorkspace.shared.activateFileViewerSelecting([url]) })
        menu.addItem(.separator())
        menu.addItem(ActionMenuItem(spanish ? "Copiar" : "Copy") {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.writeObjects([url as NSURL])
        })
        menu.addItem(ActionMenuItem(spanish ? "Copiar ruta" : "Copy Path") {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(url.path, forType: .string)
        })
        return menu
    }

    func draggingSession(_ session: NSDraggingSession,
                         sourceOperationMaskFor context: NSDraggingContext) -> NSDragOperation {
        // Copy, never move: dropping a result into a Finder folder must not take it away from where it lives.
        context == .outsideApplication ? [.copy, .generic] : []
    }
}

/// "code:" typed: what to type after it, or (without code folders) how to turn code search on.
private struct CodeHint: View {
    let controller: SearchPanelController

    static let examples = AppSettings.demo
        ? ["code: crear un agente con una herramienta", "code: desplegar el modelo con Bicep",
           "code: evaluar las respuestas del agente"]
        : ["code: reintentar una petición con espera", "code: dónde se guardan los ajustes",
           "code: leer las opciones de la línea de comandos"]

    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: FileKind.code.symbol)
                .font(.system(size: 26, weight: .medium))
                .foregroundStyle(Brand.gradient)
            if controller.phase == .codeOff {
                Text("La búsqueda de código está apagada").font(.system(size: 15, weight: .semibold))
                Text("Biblo puede encontrar código por lo que hace, en las carpetas que elijas. El código tiene su "
                     + "propio índice y nunca aparece en otras búsquedas.")
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 440)
                Button("Elegir carpetas de código…") { controller.setUpCodeSearch() }
                    .padding(.top, 4)
            } else {
                Text("Busca en tu código").font(.system(size: 15, weight: .semibold))
                Text("Di qué hace el código, o escribe un nombre que aparezca en él.").foregroundStyle(.secondary)
                VStack(spacing: 6) {
                    ForEach(Self.examples, id: \.self) { example in
                        Button { controller.tryExample(example) } label: {
                            Text(example)
                                .font(.system(size: 12, design: .monospaced))
                                .padding(.horizontal, 10)
                                .padding(.vertical, 4)
                                .background(Capsule().fill(Color.primary.opacity(0.06)))
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.top, 6)
            }
        }
        .font(.system(size: 13))
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
