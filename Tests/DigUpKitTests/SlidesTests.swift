import Foundation
import ImageIO
import Testing
import UniformTypeIdentifiers
@testable import DigUpKit

/// PowerPoint decks: their slides in the deck's order with their notes, the pictures on them, and a chunk per slide.
@Suite final class SlidesTests {
    let folder: URL = {
        let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        let url = caches.appendingPathComponent("DigUpTests-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }()

    deinit {
        try? FileManager.default.removeItem(at: folder)
    }

    var files: URL { folder.appendingPathComponent("files") }

    static let namespaces = """
        xmlns:a="http://schemas.openxmlformats.org/drawingml/2006/main" \
        xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships" \
        xmlns:p="http://schemas.openxmlformats.org/presentationml/2006/main" \
        xmlns:mc="http://schemas.openxmlformats.org/markup-compatibility/2006"
        """
    static let relationship = "http://schemas.openxmlformats.org/officeDocument/2006/relationships"

    static func slide(_ body: String) -> String {
        "<?xml version=\"1.0\" encoding=\"UTF-8\"?><p:sld \(namespaces)><p:cSld><p:spTree>\(body)</p:spTree></p:cSld></p:sld>"
    }

    static func rels(_ links: [(String, String, String)]) -> String {
        "<?xml version=\"1.0\" encoding=\"UTF-8\"?><Relationships xmlns=\"http://schemas.openxmlformats.org/package/2006/relationships\">"
            + links.map { "<Relationship Id=\"\($0.0)\" Type=\"\(relationship)/\($0.1)\" Target=\"\($0.2)\"/>" }.joined()
            + "</Relationships>"
    }

    /// A deck as PowerPoint writes one, zipped by /usr/bin/zip (pictures stored, XML deflated). Its list shows slide2.xml
    /// first; that slide has a picture, notes and a slide-number field; slide1.xml has a line break and content with a
    /// fallback copy; slide3.xml has no text, the same picture again, and a vector picture.
    func makeDeck(_ name: String) throws -> URL {
        let parts = folder.appendingPathComponent("parts-\(UUID().uuidString)")
        func write(_ path: String, _ text: String) throws {
            let url = parts.appendingPathComponent(path)
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try text.write(to: url, atomically: true, encoding: .utf8)
        }
        try write("[Content_Types].xml", "<?xml version=\"1.0\"?><Types xmlns=\"http://schemas.openxmlformats.org/package/2006/content-types\"/>")
        try write("ppt/presentation.xml", """
            <?xml version="1.0" encoding="UTF-8"?><p:presentation \(Self.namespaces)><p:sldIdLst>\
            <p:sldId id="256" r:id="rId3"/><p:sldId id="257" r:id="rId2"/><p:sldId id="258" r:id="rId4"/>\
            </p:sldIdLst></p:presentation>
            """)
        try write("ppt/_rels/presentation.xml.rels", Self.rels([
            ("rId1", "slideMaster", "slideMasters/slideMaster1.xml"), ("rId2", "slide", "slides/slide1.xml"),
            ("rId3", "slide", "slides/slide2.xml"), ("rId4", "slide", "slides/slide3.xml"),
        ]))
        try write("ppt/slides/slide2.xml", Self.slide("""
            <p:sp><p:txBody><a:p><a:r><a:t>Fabric &amp; OneLake</a:t></a:r></a:p><a:p><a:r><a:t>Lakehouse</a:t></a:r>\
            <a:fld id="{1}" type="slidenum"><a:t>1</a:t></a:fld></a:p><a:p></a:p></p:txBody></p:sp>
            """))
        try write("ppt/slides/_rels/slide2.xml.rels", Self.rels([
            ("rId1", "slideLayout", "../slideLayouts/slideLayout1.xml"), ("rId2", "image", "../media/image1.png"),
            ("rId3", "notesSlide", "../notesSlides/notesSlide1.xml"),
        ]))
        try write("ppt/notesSlides/notesSlide1.xml", """
            <?xml version="1.0" encoding="UTF-8"?><p:notes \(Self.namespaces)><p:cSld><p:spTree><p:sp><p:txBody>\
            <a:p><a:r><a:t>Say: the logo is on this slide</a:t></a:r></a:p>\
            <a:p><a:fld id="{2}" type="slidenum"><a:t>1</a:t></a:fld></a:p></p:txBody></p:sp></p:spTree></p:cSld></p:notes>
            """)
        try write("ppt/slides/slide1.xml", Self.slide("""
            <p:sp><p:txBody><a:p><a:r><a:t>Quarterly roadmap</a:t></a:r></a:p><a:p><a:r><a:t>Line one</a:t></a:r><a:br/>\
            <a:r><a:t>Line two</a:t></a:r></a:p></p:txBody></p:sp><mc:AlternateContent><mc:Choice Requires="p14">\
            <p:sp><p:txBody><a:p><a:r><a:t>Zoomed</a:t></a:r></a:p></p:txBody></p:sp></mc:Choice><mc:Fallback>\
            <p:sp><p:txBody><a:p><a:r><a:t>Zoomed</a:t></a:r></a:p></p:txBody></p:sp></mc:Fallback></mc:AlternateContent>
            """))
        try write("ppt/slides/slide3.xml", Self.slide("<p:pic/>"))
        try write("ppt/slides/_rels/slide3.xml.rels", Self.rels([
            ("rId2", "image", "../media/image1.png"), ("rId3", "image", "../media/image2.emf"),
        ]))
        try write("ppt/media/image2.emf", "not a raster picture")
        try makePNG(parts.appendingPathComponent("ppt/media/image1.png"), side: 320)

        try FileManager.default.createDirectory(at: files, withIntermediateDirectories: true)
        let deck = files.appendingPathComponent(name)
        let zip = Process()
        zip.executableURL = URL(fileURLWithPath: "/usr/bin/zip")
        zip.currentDirectoryURL = parts
        zip.arguments = ["-q", "-r", "-X", "-n", ".png", deck.path, "."]
        try zip.run()
        zip.waitUntilExit()
        #expect(zip.terminationStatus == 0)
        try FileManager.default.removeItem(at: parts)
        return deck
    }

    /// A logo-like picture: a dark square on a see-through background.
    func makePNG(_ url: URL, side: Int) throws {
        let context = CGContext(data: nil, width: side, height: side, bitsPerComponent: 8, bytesPerRow: 0,
                                space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.setFillColor(CGColor(red: 0.1, green: 0.2, blue: 0.3, alpha: 1))
        context.fill(CGRect(x: side / 4, y: side / 4, width: side / 2, height: side / 2))
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let destination = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil)!
        CGImageDestinationAddImage(destination, context.makeImage()!, nil)
        #expect(CGImageDestinationFinalize(destination))
    }

    @Test func readsTheSlidesInTheDecksOrder() throws {
        let deck = try SlideExtractor.read(try makeDeck("Overview.pptx"))
        #expect(deck.slides.map(\.text) == [
            "Fabric & OneLake\nLakehouse\n\nSay: the logo is on this slide",
            "Quarterly roadmap\nLine one\nLine two\nZoomed",
            "",
        ])
        #expect(deck.slides.map(\.pictures) == [["ppt/media/image1.png"], [], ["ppt/media/image1.png"]])
    }

    @Test func takesEachPictureOnceAndOnWhite() throws {
        let deck = try SlideExtractor.read(try makeDeck("Overview.pptx"))
        let out = folder.appendingPathComponent("scratch")
        try FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)
        let pictures = SlideExtractor.pictures(of: deck, slides: 0..<3, maxPixel: 512, minSide: 256, limit: 40, to: out)
        #expect(pictures.map(\.slide) == [1])
        // Seen on slide 1 in an earlier step: not again.
        #expect(SlideExtractor.pictures(of: deck, slides: 2..<3, maxPixel: 512, minSide: 256, limit: 40, to: out).isEmpty)
        // Too small for the model: left out.
        #expect(SlideExtractor.pictures(of: deck, slides: 0..<1, maxPixel: 512, minSide: 400, limit: 40, to: out).isEmpty)

        // The see-through corner is white, not black.
        let image = try #require(ImageExtractor.fullImage(URL(fileURLWithPath: pictures[0].path)))
        let context = CGContext(data: nil, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4,
                                space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
        context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))   // the corner pixel
        let corner = context.data!.assumingMemoryBound(to: UInt8.self)
        #expect(corner[0] > 240 && corner[1] > 240 && corner[2] > 240)
    }

    @Test func resolvesPartNames() {
        #expect(SlideExtractor.resolve("../media/image1.png", from: "ppt/slides/slide1.xml") == "ppt/media/image1.png")
        #expect(SlideExtractor.resolve("slides/slide1.xml", from: "ppt/presentation.xml") == "ppt/slides/slide1.xml")
        #expect(SlideExtractor.resolve("/ppt/media/a.png", from: "ppt/slides/slide1.xml") == "ppt/media/a.png")
    }

    @Test func tellsWhatIsntADeck() throws {
        try FileManager.default.createDirectory(at: files, withIntermediateDirectories: true)
        let text = files.appendingPathComponent("renamed.pptx")
        try "just text".write(to: text, atomically: true, encoding: .utf8)
        #expect(throws: (any Error).self) { try SlideExtractor.read(text) }
        let locked = files.appendingPathComponent("locked.pptx")
        try Data([0xD0, 0xCF, 0x11, 0xE0, 0xA1, 0xB1, 0x1A, 0xE1] + [UInt8](repeating: 0, count: 600)).write(to: locked)
        do {
            _ = try SlideExtractor.read(locked)
            Issue.record("read a password-protected deck")
        } catch {
            #expect("\(error)" == "password-protected")
        }
    }

    @Test func indexesAChunkPerSlideAndThePictures() throws {
        let deck = try makeDeck("Platform overview.pptx")
        let store = try IndexStore(directory: folder.appendingPathComponent("index"))
        let indexer = try Indexer(store: store, options: IndexOptions(), makeEmbedder: { FakeEmbedder() })
        _ = try indexer.sync([files])
        #expect(try indexer.run()["done"] == 1)

        func locs(_ kind: String) throws -> [Int] {
            var out: [Int] = []
            try store.db.query("""
                SELECT s.loc FROM segments s JOIN files f ON f.id = s.file WHERE f.path = ? AND s.kind = ? ORDER BY s.loc
                """, [.text(deck.path), .text(kind)]) { out.append(Int($0.double(0))) }
            return out
        }
        func found(_ word: String) throws -> [Int] {
            var out: [Int] = []
            try store.db.query("SELECT s.loc FROM fts JOIN segments s ON s.id = fts.rowid WHERE fts MATCH ? ORDER BY s.loc",
                               [.text("\"\(word)\"")]) { out.append(Int($0.double(0))) }
            return out
        }
        #expect(try locs("chunk") == [1, 2])        // slide 3 has no text
        #expect(try locs("page_image") == [1])
        #expect(try found("OneLake") == [1])
        #expect(try found("logo") == [1])           // from the speaker notes
        #expect(try found("Zoomed") == [2])
        var info: [String: String] = [:]
        try store.db.query("SELECT id FROM files WHERE path = ?", [.text(deck.path)]) { info = (try? store.info(of: $0.int(0))) ?? [:] }
        #expect(info["slides"] == "3")
    }
}
