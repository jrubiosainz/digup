import AppKit
import DigUpKit
import SwiftUI

/// The panel's results: one column per format in a fixed order (`ResultSet.columnOrder`), each best match first. The
/// column the arrows are in is wide and the others narrow; a format with nothing found is a thin spine. Down every
/// column runs Biblo's violet ribbon, as wide as each result is likely, thinning to nothing after the last.
struct ColumnsView: View {
    let controller: SearchPanelController
    static let spacing: CGFloat = 10
    static let inset: CGFloat = 14
    @State private var appeared = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        GeometryReader { geometry in
            let columns = controller.results.columns
            let room = geometry.size.width - 2 * Self.inset - Self.spacing * CGFloat(max(0, columns.count - 1))
            let widths = ColumnLayout.widths(for: columns, focused: controller.focusedKind, in: room)
            HStack(alignment: .top, spacing: Self.spacing) {
                ForEach(Array(columns.enumerated()), id: \.element.id) { index, column in
                    Group {
                        if column.isEmpty {
                            EmptyRail(kind: column.kind)
                        } else {
                            ResultColumnView(controller: controller, column: column, number: index + 1,
                                             width: widths[index])
                        }
                    }
                    .frame(width: widths[index])
                    // The shelves come in one after another, the first time there's something on them.
                    .opacity(appeared ? 1 : 0)
                    .offset(y: appeared || reduceMotion ? 0 : 10)
                    .animation(reduceMotion ? .easeOut(duration: 0.15)
                                            : .spring(response: 0.4, dampingFraction: 0.86).delay(0.04 * Double(index)),
                               value: appeared)
                }
            }
            .padding(.horizontal, Self.inset)
            .padding(.top, 12)
            .padding(.bottom, 10)
            .frame(width: geometry.size.width, height: geometry.size.height, alignment: .topLeading)
            .animation(Motion.lens(reduceMotion), value: controller.focusedKind)
        }
        .onAppear { appeared = true }
    }
}

/// How wide each column is. A format with nothing found is a 44-point spine; the column you're in gets about half the
/// room (380 points at least), the others share the rest (300 at most each, anything left over going to yours).
enum ColumnLayout {
    static let rail: CGFloat = 44

    static func widths(for columns: [ResultColumn], focused: ResultGroupKind?, in room: CGFloat) -> [CGFloat] {
        let full = columns.filter { !$0.isEmpty }
        let space = max(0, room - rail * CGFloat(columns.count - full.count))
        guard full.count > 1 else { return columns.map { $0.isEmpty ? rail : space } }
        let others = CGFloat(full.count - 1)
        let active = min(max(380, space * 0.48), space - 140 * others)
        let other = max(0, min(300, (space - active) / others))
        let wide = space - other * others
        let open = full.contains { $0.kind == focused } ? focused : full.first?.kind
        return columns.map { $0.isEmpty ? rail : $0.kind == open ? wide : other }
    }
}

/// One format's results, best first, under its name. In the column you're in, the selected result opens into a card
/// with a big preview and its neighbours grow toward it: a lens moving down the column as you go. The other columns
/// show their selected result as a picture and the rest as a short list.
struct ResultColumnView: View {
    let controller: SearchPanelController
    let column: ResultColumn
    /// Its place, for ⌘1…⌘5.
    let number: Int
    let width: CGFloat
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    static let padding: CGFloat = 6

    private var focused: Bool { controller.focusedKind == column.kind }
    private var cursor: String? { controller.cursors[column.kind] }

    var body: some View {
        let cursorIndex = column.rows.firstIndex { $0.id == cursor } ?? 0
        VStack(alignment: .leading, spacing: 4) {
            ColumnHeader(kind: column.kind, count: column.rows.count, focused: focused, number: number) {
                controller.focus(column.kind)
            }
            .padding(.horizontal, 12)
            .padding(.top, 10)
            ScrollViewReader { proxy in
                ScrollView(.vertical) {
                    VStack(alignment: .leading, spacing: 0) {
                        ForEach(Array(column.rows.enumerated()), id: \.element.id) { index, row in
                            ResultCell(controller: controller, row: row,
                                       mode: CellMode(index: index, cursor: cursorIndex, focused: focused),
                                       width: width - 2 * Self.padding, weaker: index >= column.strong,
                                       ribbon: ribbon(at: index, cursor: cursorIndex))
                                .id(row.id)
                        }
                    }
                    .padding(.horizontal, Self.padding)
                    .padding(.top, 2)
                    .padding(.bottom, 24)
                }
                .scrollIndicators(.never)
                .onChange(of: cursor) { _, id in scroll(proxy, to: id) }
                .onChange(of: focused) { _, _ in scroll(proxy, to: cursor) }
            }
        }
        .frame(maxHeight: .infinity, alignment: .top)
        .background(RoundedRectangle(cornerRadius: 16, style: .continuous)
            .fill(Color.primary.opacity(focused ? 0.04 : 0)))
        .animation(Motion.lens(reduceMotion), value: cursor)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(column.kind.spanishTitle)
    }

    /// The selected result a little below the top, so what comes after it shows.
    private func scroll(_ proxy: ScrollViewProxy, to id: String?) {
        guard let id else { return }
        withAnimation(Motion.lens(reduceMotion)) { proxy.scrollTo(id, anchor: UnitPoint(x: 0.5, y: 0.22)) }
    }

    /// The ribbon beside result `index`: as wide as it is likely at its top and as the next result at its bottom
    /// (nothing after the last), brightest at the selected result of the column you're in.
    private func ribbon(at index: Int, cursor: Int) -> RibbonPiece {
        func opacity(_ row: Int) -> Double {
            let likely = column.rows[row].confidence
            return focused ? (row == cursor ? 1 : 0.35 + 0.65 * likely) : 0.25 + 0.35 * likely
        }
        let next = index + 1 < column.rows.count ? index + 1 : nil
        return RibbonPiece(top: RibbonPiece.width(column.rows[index].confidence),
                           bottom: next.map { RibbonPiece.width(column.rows[$0].confidence) } ?? 0,
                           topOpacity: opacity(index), bottomOpacity: next.map(opacity) ?? opacity(index))
    }
}

/// A column's name, its count, and a click to move into it.
struct ColumnHeader: View {
    let kind: ResultGroupKind
    let count: Int
    let focused: Bool
    let number: Int
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: kind.symbol)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(focused ? AnyShapeStyle(Brand.ink) : AnyShapeStyle(.secondary))
                    .frame(width: 16)
                Text(kind.spanishTitle)
                    .font(.system(size: 12.5, weight: focused ? .semibold : .medium))
                    .foregroundStyle(focused ? .primary : .secondary)
                    .lineLimit(1)
                Text("\(count)")
                    .font(.system(size: 11).monospacedDigit())
                    .foregroundStyle(.tertiary)
                Spacer(minLength: 0)
            }
            .frame(height: 22)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help("\(kind.spanishTitle): ⌘\(number)")
        .accessibilityAddTraits(.isHeader)
    }
}

/// A format with nothing found for this search: a thin spine with its name, read bottom to top like a Spanish book's.
struct EmptyRail: View {
    let kind: ResultGroupKind

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: kind.symbol)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.tertiary)
            Text(kind.spanishNone)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.tertiary)
                .fixedSize()
                .rotationEffect(.degrees(-90))
                .frame(width: 20, height: 110)
            Spacer(minLength: 0)
        }
        .padding(.top, 14)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color.primary.opacity(0.035)))
        .help("Nada en \(kind.spanishTitle.lowercased()) para esta búsqueda")
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(kind.spanishNone)
    }
}

/// How big a result is drawn: the lens of the column you're in is on `card`, with its neighbours `near`; another
/// column's selected result is a `peek` (its picture); everything else is `compact`.
enum CellMode: Equatable {
    case card, near, compact, peek

    init(index: Int, cursor: Int, focused: Bool) {
        if index == cursor {
            self = focused ? .card : .peek
        } else {
            self = focused && abs(index - cursor) == 1 ? .near : .compact
        }
    }
}

/// A stretch of the ribbon: its width at the top and bottom of a result, and how bright it is there.
struct RibbonPiece: Equatable {
    var top: CGFloat
    var bottom: CGFloat
    var topOpacity: Double
    var bottomOpacity: Double

    /// 2 points for a long shot, 10 for a sure thing.
    static func width(_ likely: Double) -> CGFloat { 2 + 8 * CGFloat(likely) }
}

/// A result in a column, as big as it is close to where you are (`CellMode`), with its stretch of ribbon beside it.
/// Click selects it, double-click opens it, drag copies the file out.
struct ResultCell: View {
    let controller: SearchPanelController
    let row: ResultRow
    let mode: CellMode
    /// The column's inner width.
    let width: CGFloat
    /// Below half the best score (`ResultColumn.strong`): drawn fainter, unless it's the one you're on.
    let weaker: Bool
    let ribbon: RibbonPiece

    static let gutter: CGFloat = 16

    var body: some View {
        content
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.leading, Self.gutter)
            .background(alignment: .leading) {
                RibbonSegment(top: ribbon.top, bottom: ribbon.bottom)
                    .fill(LinearGradient(colors: [Brand.ink.opacity(ribbon.topOpacity),
                                                  Brand.ink.opacity(ribbon.bottomOpacity)],
                                         startPoint: .top, endPoint: .bottom))
                    .frame(width: 14)
            }
            .opacity(weaker && mode != .card ? 0.55 : 1)
            .accessibilityElement(children: .combine)
            .accessibilityLabel("\(row.kind.spanishTitle), \(row.name), \(row.spanishReason), acierto \(row.percent) %")
            .accessibilityAddTraits(mode == .card ? .isSelected : [])
    }

    @ViewBuilder private var content: some View {
        switch mode {
        case .card:
            CardCell(controller: controller, row: row, width: width - Self.gutter, dragArea: dragArea)
        case .peek:
            PeekCell(row: row, width: width - Self.gutter)
                .overlay(dragArea)
        case .near:
            NearCell(row: row)
                .overlay(dragArea)
        case .compact:
            CompactCell(row: row, showsPercent: width >= 200)
                .overlay(dragArea)
        }
    }

    private var dragArea: FileDragArea {
        FileDragArea(url: row.url, openTitle: row.spanishOpenTitle.capitalizedFirst, spanish: true,
                     onClick: { controller.select(row) },
                     onOpen: {
                         controller.select(row)
                         controller.openSelected()
                     })
    }
}

/// The selected result of the column you're in, opened up: a big preview of what matched (the page, the frame, the
/// passage, the stretch of sound) and why it's here.
private struct CardCell: View {
    let controller: SearchPanelController
    let row: ResultRow
    let width: CGFloat
    let dragArea: FileDragArea

    var body: some View {
        let inner = width - 24
        Group {
            if width >= 560 {
                HStack(alignment: .top, spacing: 16) {
                    picture(CGSize(width: (inner - 16) * 0.58, height: 240))
                    info
                }
            } else {
                VStack(alignment: .leading, spacing: 12) {
                    picture(CGSize(width: inner, height: min(inner * 0.56, 216)))
                    info
                }
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Color.primary.opacity(0.045)))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous)
            .strokeBorder(Color.primary.opacity(0.08), lineWidth: 0.5))
        .padding(.vertical, 4)
    }

    private func picture(_ size: CGSize) -> some View {
        PreviewPicture(row: row, size: size, open: { controller.openSelected() }, ambient: true)
            .frame(width: size.width)
    }

    private var info: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text(row.title)
                    .font(.system(size: 15, weight: .semibold))
                    .lineLimit(2)
                    .truncationMode(.middle)
                Spacer(minLength: 0)
                Acierto(percent: row.percent, size: 20, labeled: true)
            }
            Label {
                Text(row.spanishReason)
            } icon: {
                Image(systemName: row.matchedMeaning ? "sparkle.magnifyingglass" : "textformat")
            }
            .font(.system(size: 12, weight: .medium))
            .foregroundStyle(Brand.ink)
            if let excerpt = row.excerpt, row.matchedWords, row.kind != .code, row.segment != .chunk {
                Text(highlighted(excerpt, size: 12))
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .lineLimit(3)
            }
            Text(row.folder)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.head)
            Text(row.spanishDetails)
                .font(.system(size: 11).monospacedDigit())
                .foregroundStyle(.tertiary)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
        // Over the words only: the preview keeps its own clicks (play, double-click to open).
        .overlay(dragArea)
    }
}

/// Next to the selected result: growing toward it.
private struct NearCell: View {
    let row: ResultRow

    var body: some View {
        HStack(spacing: 10) {
            Thumb(row: row, side: 38)
            VStack(alignment: .leading, spacing: 3) {
                Text(row.title)
                    .font(.system(size: 13, weight: .semibold))
                    .lineLimit(1)
                    .truncationMode(.middle)
                HStack(spacing: 6) {
                    if let place = row.spanishPlace { PlaceBadge(text: place) }
                    Text(row.folder)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.head)
                }
            }
            Spacer(minLength: 6)
            Acierto(percent: row.percent, size: 13)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 7)
        .contentShape(Rectangle())
    }
}

/// Further down (or up) the shelf.
private struct CompactCell: View {
    let row: ResultRow
    let showsPercent: Bool

    var body: some View {
        HStack(spacing: 8) {
            Thumb(row: row, side: 26)
            Text(row.title)
                .font(.system(size: 12))
                .lineLimit(1)
                .truncationMode(.middle)
            Spacer(minLength: 4)
            if showsPercent { Acierto(percent: row.percent, size: 11) }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .contentShape(Rectangle())
    }
}

/// The selected result of a column you're not in: its picture (the frame, the page; for sound, where it matched) and
/// how likely it is.
private struct PeekCell: View {
    let row: ResultRow
    let width: CGFloat

    var body: some View {
        let inner = max(40, width - 16)
        VStack(alignment: .leading, spacing: 6) {
            if row.kind == .audio {
                WaveGlyph(row: row)
                    .frame(width: inner, height: 52)
            } else {
                MomentThumb(row: row, size: CGSize(width: inner, height: min(inner * 0.62, 118)))
            }
            Text(row.title)
                .font(.system(size: 12, weight: .semibold))
                .lineLimit(1)
                .truncationMode(.middle)
            HStack(spacing: 6) {
                Acierto(percent: row.percent, size: 12)
                if row.kind == .audio, let place = row.spanishPlace { PlaceBadge(text: place) }
            }
        }
        .padding(8)
        .contentShape(Rectangle())
    }
}

/// A file's thumbnail, loaded once at the near size and scaled, so the lens can grow and shrink it smoothly.
private struct Thumb: View {
    let row: ResultRow
    let side: CGFloat

    var body: some View {
        // Code's thumbnail would be a page of tiny text: its file type's icon says more.
        ThumbnailView(url: row.url, side: 38, iconOnly: row.kind == .code)
            .scaleEffect(side / 38)
            .frame(width: side, height: side)
    }
}

/// A result's picture, filling `size`: the video frame or the PDF page that matched, else the file's thumbnail.
struct MomentThumb: View {
    let row: ResultRow
    let size: CGSize
    @State private var image: NSImage?
    @Environment(\.displayScale) private var scale

    /// Loaded at a few sizes only, so columns changing width don't reload it at every step.
    private var side: CGFloat { (max(size.width, size.height) / 80).rounded(.up) * 80 }

    var body: some View {
        ZStack {
            Color.primary.opacity(0.05)
            if let image {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: size.width, height: size.height)
            } else {
                Image(nsImage: NSWorkspace.shared.icon(forFile: row.url.path))
                    .resizable()
                    .frame(width: 36, height: 36)
            }
        }
        .frame(width: size.width, height: size.height)
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous)
            .strokeBorder(Color.primary.opacity(0.08), lineWidth: 0.5))
        .overlay(alignment: .bottomLeading) {
            if let place = row.spanishPlace { PlaceBadge(text: place, onImage: true).padding(6) }
        }
        .task(id: Previews.shared.key(row, side)) {
            if let cached = Previews.shared.cached(row, side: side) {
                image = cached
            } else if let loaded = await Previews.shared.load(row, side: side, scale: scale) {
                image = loaded
            }
        }
        .accessibilityHidden(true)
    }
}

/// Sound has no picture: a waveform drawn from the file's name (the same every time), with the stretch that matched
/// in violet.
struct WaveGlyph: View {
    let row: ResultRow
    static let bars = 28

    var body: some View {
        let heights = Self.heights(seed: row.id)
        let lit = litBars
        GeometryReader { geometry in
            let gap: CGFloat = 2
            let bar = max(1, (geometry.size.width - 20 - gap * CGFloat(Self.bars - 1)) / CGFloat(Self.bars))
            HStack(alignment: .center, spacing: gap) {
                ForEach(0..<Self.bars, id: \.self) { index in
                    Capsule()
                        .fill(lit.contains(index) ? AnyShapeStyle(Brand.ink) : AnyShapeStyle(Color.primary.opacity(0.2)))
                        .frame(width: bar, height: max(3, (geometry.size.height - 16) * heights[index]))
                }
            }
            .frame(width: geometry.size.width, height: geometry.size.height)
        }
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Color.primary.opacity(0.05)))
        .accessibilityHidden(true)
    }

    /// The bars of the stretch that matched (from `loc` to `locEnd`, or 30 seconds), when the length is known.
    private var litBars: Range<Int> {
        guard let start = row.loc, let duration = row.duration, duration > 0 else { return 0..<0 }
        let end = row.locEnd ?? start + 30
        let first = max(0, min(Self.bars - 1, Int(start / duration * Double(Self.bars))))
        let last = max(first + 1, min(Self.bars, Int((end / duration * Double(Self.bars)).rounded(.up))))
        return first..<last
    }

    /// Bar heights (0…1) from a stable hash of `seed` (FNV-1a, then a little LCG), quieter toward the ends.
    static func heights(seed: String) -> [CGFloat] {
        var hash: UInt64 = 0xcbf2_9ce4_8422_2325
        for byte in seed.utf8 { hash = (hash ^ UInt64(byte)) &* 0x0000_0100_0000_01b3 }
        return (0..<bars).map { index in
            hash = hash &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
            let noise = CGFloat((hash >> 33) & 0xFFFF) / 65535
            let envelope = 0.55 + 0.45 * sin(CGFloat(index) / CGFloat(bars - 1) * .pi)
            return (0.3 + 0.7 * noise) * envelope
        }
    }
}

/// How likely a result is what you described (`ResultRow.percent`): "87 %", the sign smaller. The card's says so
/// underneath, in violet.
struct Acierto: View {
    let percent: Int
    var size: CGFloat = 12
    var labeled = false

    var body: some View {
        VStack(alignment: .trailing, spacing: 0) {
            HStack(alignment: .firstTextBaseline, spacing: size * 0.12) {
                Text("\(percent)")
                    .font(.system(size: size, weight: .semibold).monospacedDigit())
                Text("%")
                    .font(.system(size: size * 0.62, weight: .semibold))
            }
            .foregroundStyle(labeled ? AnyShapeStyle(Brand.ink) : AnyShapeStyle(.secondary))
            if labeled {
                Text("acierto")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.tertiary)
            }
        }
        .fixedSize()
        .help("Acierto estimado: cuánto se parece a lo que describiste")
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Acierto \(percent) %")
    }
}

/// A stretch of ribbon beside a result: `top` wide at its top edge, `bottom` at its bottom, centered.
nonisolated struct RibbonSegment: Shape {
    var top: CGFloat
    var bottom: CGFloat

    var animatableData: AnimatablePair<CGFloat, CGFloat> {
        get { AnimatablePair(top, bottom) }
        set { (top, bottom) = (newValue.first, newValue.second) }
    }

    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.midX - top / 2, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.midX + top / 2, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.midX + bottom / 2, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.midX - bottom / 2, y: rect.maxY))
        path.closeSubpath()
        return path
    }
}

/// A bookmark ribbon: a strip with a V cut into its end.
nonisolated struct RibbonShape: Shape {
    var notch: CGFloat = 5

    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.midX, y: rect.maxY - min(notch, rect.height / 2)))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
        path.closeSubpath()
        return path
    }
}

/// Biblo's mark: a violet bookmark ribbon hanging from the panel's top edge, left of the field. Short while there's
/// nothing to find, it sways while meaning search warms up and hangs long over results, pointing down into them.
struct RibbonMark: View {
    enum Hang: Equatable { case short, swaying, long }
    let hang: Hang
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        TimelineView(.animation(paused: hang != .swaying || reduceMotion)) { context in
            RibbonShape()
                .fill(Brand.ribbon)
                .frame(width: 14, height: length(at: context.date))
                .shadow(color: Brand.indigo.opacity(0.3), radius: 1.5, y: 1)
        }
        .animation(Motion.lens(reduceMotion), value: hang)
        .accessibilityHidden(true)
    }

    private func length(at date: Date) -> CGFloat {
        switch hang {
        case .short: 30
        case .long: 46
        case .swaying:
            reduceMotion ? 40 : 41 + 5 * CGFloat(sin(date.timeIntervalSinceReferenceDate * 2 * .pi / 1.2))
        }
    }
}

extension String {
    /// "Abrir en 0:06" from "abrir en 0:06": for a menu item.
    var capitalizedFirst: String { prefix(1).uppercased() + dropFirst() }
}
