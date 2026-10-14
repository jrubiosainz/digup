import Compression
import Foundation

/// A PowerPoint deck (.pptx), read without PowerPoint: each slide's text with its speaker notes, in the deck's order,
/// and the pictures placed on it. Indexed as a document with one chunk per slide, so a match says which slide.
public enum SlideExtractor {
    public static let extensions: Set<String> = ["pptx"]

    public static func isDeck(_ path: String) -> Bool {
        extensions.contains((path as NSString).pathExtension.lowercased())
    }

    struct Slide {
        let text: String
        /// The zip parts of the pictures placed on it ("ppt/media/image3.png"), in the order they're linked.
        let pictures: [String]
    }

    /// A picture from a slide, written out for the model.
    struct Picture: Sendable {
        let slide: Int   // from 1
        let path: String
    }

    struct Deck {
        let slides: [Slide]
        fileprivate let zip: ZipReader
    }

    /// A slide's text past this is left out: it's speaker notes pasted from somewhere else.
    static let maxSlideText = 6000
    private static let pictureTypes: Set<String> = ["png", "jpg", "jpeg", "gif", "tif", "tiff", "bmp", "heic", "webp"]

    static func read(_ url: URL) throws -> Deck {
        let zip = try ZipReader(url)
        let slides = order(zip).map { part -> Slide in
            let links = relationships(zip, of: part)
            var text = paragraphs(zip.data(part)).joined(separator: "\n")
            if let notes = links.first(where: { $0.type.hasSuffix("/notesSlide") }) {
                let said = paragraphs(zip.data(notes.target)).joined(separator: "\n")
                if !said.isEmpty { text += (text.isEmpty ? "" : "\n\n") + said }
            }
            let pictures = links.filter {
                $0.type.hasSuffix("/image") && pictureTypes.contains(($0.target as NSString).pathExtension.lowercased())
            }.map(\.target)
            return Slide(text: String(text.prefix(maxSlideText)), pictures: pictures)
        }
        guard !slides.isEmpty else { throw ExtractError.empty("no slides") }
        return Deck(slides: slides, zip: zip)
    }

    /// The pictures on slides `read` (from 0), written into `folder` downscaled for the model: each picture once (a logo
    /// repeated on every slide counts where it's first seen), at most `limit`, and none too small to tell apart.
    static func pictures(of deck: Deck, slides read: Range<Int>, maxPixel: Int, minSide: Int, limit: Int,
                         to folder: URL) -> [Picture] {
        var seen = Set<String>()
        // Pictures on slides before `read` were taken in an earlier step.
        for slide in deck.slides[..<read.lowerBound] { seen.formUnion(slide.pictures) }
        var out: [Picture] = []
        for index in read {
            for part in deck.slides[index].pictures where out.count < limit && seen.insert(part).inserted {
                guard let data = deck.zip.data(part, limit: 64 << 20) else { continue }
                let name = "slide-\(index + 1)-\(out.count).\((part as NSString).pathExtension)"
                let original = folder.appendingPathComponent(name)
                guard (try? data.write(to: original)) != nil,
                      let prepared = try? ImageExtractor.prepare(original, maxPixel: maxPixel, minSide: minSide,
                                                                 to: folder, png: false)
                else { continue }
                out.append(Picture(slide: index + 1, path: prepared.path))
            }
        }
        return out
    }

    // MARK: The parts

    /// The slides' parts in the deck's order (presentation.xml's list), else by their numbers.
    private static func order(_ zip: ZipReader) -> [String] {
        let links = Dictionary(relationships(zip, of: "ppt/presentation.xml").map { ($0.id, $0.target) },
                               uniquingKeysWith: { first, _ in first })
        let listed = XMLScan(zip.data("ppt/presentation.xml")).values(of: "sldId", attribute: "id", prefixed: true)
            .compactMap { links[$0] }.filter { zip.entries[$0] != nil }
        if !listed.isEmpty { return listed }
        return zip.entries.keys.compactMap { name -> (Int, String)? in
            guard name.hasPrefix("ppt/slides/slide"), name.hasSuffix(".xml"),
                  let number = Int(name.dropFirst("ppt/slides/slide".count).dropLast(4)) else { return nil }
            return (number, name)
        }.sorted { $0.0 < $1.0 }.map(\.1)
    }

    struct Link {
        let id: String
        let type: String
        let target: String   // the zip part it points to
    }

    /// A part's relationships (its _rels file), with their targets made into zip part names.
    static func relationships(_ zip: ZipReader, of part: String) -> [Link] {
        let folder = (part as NSString).deletingLastPathComponent
        let rels = (folder.isEmpty ? "" : folder + "/") + "_rels/" + (part as NSString).lastPathComponent + ".rels"
        return XMLScan(zip.data(rels)).elements(named: "Relationship").compactMap { attributes in
            guard attributes["TargetMode"] != "External", let id = attributes["Id"], let type = attributes["Type"],
                  let target = attributes["Target"] else { return nil }
            return Link(id: id, type: type, target: resolve(target.removingPercentEncoding ?? target, from: part))
        }
    }

    /// "../media/image1.png" from "ppt/slides/slide1.xml" → "ppt/media/image1.png".
    static func resolve(_ target: String, from part: String) -> String {
        if target.hasPrefix("/") { return String(target.dropFirst()) }
        var path = part.split(separator: "/").dropLast().map(String.init)
        for piece in target.split(separator: "/") {
            if piece == ".." { _ = path.popLast() } else if piece != "." { path.append(String(piece)) }
        }
        return path.joined(separator: "/")
    }

    /// The text of a slide or notes part, a line per paragraph. Fields (the slide number, the date) are left out, and so
    /// is the plain copy PowerPoint keeps of newer content for older apps (`mc:Fallback`), which would say it twice.
    static func paragraphs(_ xml: Data?) -> [String] {
        guard let xml else { return [] }
        let collector = TextCollector()
        let parser = XMLParser(data: xml)
        parser.delegate = collector
        parser.parse()
        return collector.paragraphs
    }

    private final class TextCollector: NSObject, XMLParserDelegate {
        var paragraphs: [String] = []
        private var line = ""
        private var inText = false
        private var skipping = 0

        func parser(_ parser: XMLParser, didStartElement name: String, namespaceURI: String?, qualifiedName: String?,
                    attributes: [String: String] = [:]) {
            switch name {
            case "a:t": inText = true
            case "a:fld", "mc:Fallback": skipping += 1
            case "a:br": if skipping == 0 { line += "\n" }
            default: break
            }
        }

        func parser(_ parser: XMLParser, foundCharacters string: String) {
            if inText, skipping == 0 { line += string }
        }

        func parser(_ parser: XMLParser, didEndElement name: String, namespaceURI: String?, qualifiedName: String?) {
            switch name {
            case "a:t": inText = false
            case "a:fld", "mc:Fallback": skipping = max(0, skipping - 1)
            case "a:p":
                let text = line.trimmingCharacters(in: .whitespacesAndNewlines)
                if !text.isEmpty { paragraphs.append(text) }
                line = ""
            default: break
            }
        }
    }
}

/// The elements of a small XML part (a _rels file, presentation.xml), with their attributes.
private struct XMLScan {
    private let found: [(name: String, attributes: [String: String])]

    init(_ xml: Data?) {
        guard let xml else { found = []; return }
        let collector = Collector()
        let parser = XMLParser(data: xml)
        parser.delegate = collector
        parser.parse()
        found = collector.found
    }

    /// Elements whose local name is `name` ("Relationship"; "p:sldId" for "sldId").
    func elements(named name: String) -> [[String: String]] {
        found.filter { $0.name == name || $0.name.hasSuffix(":" + name) }.map(\.attributes)
    }

    /// `attribute` of each element named `name`; `prefixed` wants it with a namespace prefix ("r:id", not "id").
    func values(of name: String, attribute: String, prefixed: Bool) -> [String] {
        elements(named: name).compactMap { attributes in
            attributes.first { prefixed ? $0.key.hasSuffix(":" + attribute) : $0.key == attribute }?.value
        }
    }

    private final class Collector: NSObject, XMLParserDelegate {
        var found: [(name: String, attributes: [String: String])] = []

        func parser(_ parser: XMLParser, didStartElement name: String, namespaceURI: String?, qualifiedName: String?,
                    attributes: [String: String] = [:]) {
            found.append((name, attributes))
        }
    }
}

/// The parts of a zip file (an Office document is one), read in place: the central directory once, then each part when
/// it's asked for, inflated in memory. Stored and deflated parts, and no zip64: Office never needs it below 4 GB.
struct ZipReader {
    struct Entry {
        let method: Int
        let compressedSize: Int
        let size: Int
        let header: Int   // where its local header starts
    }

    private let bytes: Data
    let entries: [String: Entry]

    init(_ url: URL) throws {
        let bytes = try Data(contentsOf: url, options: .mappedIfSafe)
        // A password-protected Office document is an OLE file holding the encrypted zip.
        if bytes.prefix(4) == Data([0xD0, 0xCF, 0x11, 0xE0]) { throw ExtractError.locked }
        self.bytes = bytes
        // The central directory's end record: 22 bytes, then a comment of up to 64 KB.
        var end: Int?
        var at = bytes.count - 22
        while at >= max(0, bytes.count - 22 - 0xFFFF) {
            if Self.u32(bytes, at) == 0x0605_4B50 { end = at; break }
            at -= 1
        }
        guard let end, let count = Self.u16(bytes, end + 10), var at = Self.u32(bytes, end + 16), at != 0xFFFF_FFFF
        else { throw ExtractError.unreadable("not a zip file") }
        var entries: [String: Entry] = [:]
        for _ in 0..<count {
            guard Self.u32(bytes, at) == 0x0201_4B50, let flags = Self.u16(bytes, at + 8),
                  let method = Self.u16(bytes, at + 10), let compressed = Self.u32(bytes, at + 20),
                  let size = Self.u32(bytes, at + 24), let nameLength = Self.u16(bytes, at + 28),
                  let extra = Self.u16(bytes, at + 30), let comment = Self.u16(bytes, at + 32),
                  let header = Self.u32(bytes, at + 42), at + 46 + nameLength <= bytes.count
            else { throw ExtractError.unreadable("damaged zip file") }
            let start = bytes.startIndex + at + 46
            let name = String(decoding: bytes[start..<start + nameLength], as: UTF8.self)
            // Encrypted parts (flag bit 0) can't be read; zip64 sizes aren't expected.
            if flags & 1 == 0, compressed != 0xFFFF_FFFF, size != 0xFFFF_FFFF {
                entries[name] = Entry(method: method, compressedSize: compressed, size: size, header: header)
            }
            at += 46 + nameLength + extra + comment
        }
        self.entries = entries
    }

    /// A part's bytes, or nil when it's missing, bigger than `limit`, or can't be inflated.
    func data(_ name: String, limit: Int = 32 << 20) -> Data? {
        guard let entry = entries[name], entry.size <= limit, Self.u32(bytes, entry.header) == 0x0403_4B50,
              let nameLength = Self.u16(bytes, entry.header + 26), let extra = Self.u16(bytes, entry.header + 28)
        else { return nil }
        let start = entry.header + 30 + nameLength + extra
        guard start + entry.compressedSize <= bytes.count else { return nil }
        let packed = bytes[(bytes.startIndex + start)..<(bytes.startIndex + start + entry.compressedSize)]
        switch entry.method {
        case 0:
            return packed.count == entry.size ? Data(packed) : nil
        case 8:
            guard entry.size > 0 else { return Data() }
            guard !packed.isEmpty else { return nil }
            var out = Data(count: entry.size)
            let written = out.withUnsafeMutableBytes { target in
                packed.withUnsafeBytes { source in
                    // COMPRESSION_ZLIB is raw DEFLATE (RFC 1951), which is what zip stores.
                    compression_decode_buffer(target.bindMemory(to: UInt8.self).baseAddress!, entry.size,
                                              source.bindMemory(to: UInt8.self).baseAddress!, packed.count,
                                              nil, COMPRESSION_ZLIB)
                }
            }
            return written == entry.size ? out : nil
        default:
            return nil
        }
    }

    private static func u16(_ data: Data, _ at: Int) -> Int? {
        guard at >= 0, at + 2 <= data.count else { return nil }
        let i = data.startIndex + at
        return Int(data[i]) | Int(data[i + 1]) << 8
    }

    private static func u32(_ data: Data, _ at: Int) -> Int? {
        guard at >= 0, at + 4 <= data.count else { return nil }
        let i = data.startIndex + at
        return Int(data[i]) | Int(data[i + 1]) << 8 | Int(data[i + 2]) << 16 | Int(data[i + 3]) << 24
    }
}
