import CoreServices
import Foundation
import Testing
import UniformTypeIdentifiers
@testable import DigUpKit

/// Which changes make the app walk the folders again (`ChangeFilter`): only those that can change what a walk finds.
@Suite struct ChangeFilterTests {
    let root = "/Volumes/BibloTest/OneDrive"
    let created = kFSEventStreamEventFlagItemCreated
    let modified = kFSEventStreamEventFlagItemModified
    let renamed = kFSEventStreamEventFlagItemRenamed
    let removed = kFSEventStreamEventFlagItemRemoved

    func filter(code: Bool = false, includeCode: Bool = false, excludedFolders: [String] = [],
                excludedTypes: String = "", roots: [String]? = nil) -> ChangeFilter {
        var options = IndexOptions()
        options.code = code
        options.includeCode = includeCode
        options.excludedFolders = excludedFolders
        options.excludedExtensions = IndexOptions.extensions(excludedTypes)
        return ChangeFilter(roots: roots ?? [root], options: options)
    }

    func change(_ path: String, _ flags: [Int]) -> FileChange {
        FileChange(path: path, flags: flags.reduce(FSEventStreamEventFlags(0)) { $0 | FSEventStreamEventFlags($1) })
    }
    func file(_ path: String, _ events: Int...) -> FileChange {
        change(path, events + [kFSEventStreamEventFlagItemIsFile])
    }
    func folder(_ path: String, _ events: Int...) -> FileChange {
        change(path, events + [kFSEventStreamEventFlagItemIsDir])
    }
    /// OneDrive making a file local ("Always keep on this device"): 0x1d400.
    func downloaded(_ path: String) -> FileChange {
        change(path, [kFSEventStreamEventFlagItemIsFile, kFSEventStreamEventFlagItemModified,
                      kFSEventStreamEventFlagItemInodeMetaMod, kFSEventStreamEventFlagItemChangeOwner,
                      kFSEventStreamEventFlagItemXattrMod])
    }

    /// Every type the rules name, and common ones they don't.
    var extensions: [String] {
        let media = ["pdf", "png", "jpg", "jpeg", "heic", "heif", "gif", "tiff", "bmp", "webp", "svg", "dng", "psd",
                     "mov", "mp4", "m4v", "avi", "mkv", "webm", "mpg", "3gp", "m4a", "mp3", "wav", "aiff", "aac",
                     "flac", "ogg", "caf", "mid"]
        let other = ["key", "numbers", "pages", "xlsx", "xls", "zip", "dmg", "epub", "eml", "ics", "vcf", "ps1",
                     "psm1", "psd1", "ts", "mts", "m2ts", "ipynb", "sqlite"]
        return Set(media + other).union(Rules.docExtensions).union(Rules.codeExtensions)
            .union(Rules.sourceExtensions).union(Rules.codeTextExtensions).sorted()
    }

    @Test func excelAutosaveIsIgnored() {
        let workbook = root + "/Milestones  Detailed View.xlsx"
        for watcher in [filter(), filter(code: true)] {
            #expect(!watcher.concerns(file(workbook, modified)))
            #expect(!watcher.concerns(file(workbook, created, renamed, modified)))   // an atomic save
            #expect(!watcher.concerns(file(root + "/~$Milestones  Detailed View.xlsx", created, removed)))   // its lock
            #expect(!watcher.concerns(file(root + "/2F3A4B10", created, modified, renamed, removed)))   // its temp file
        }
    }

    @Test func scriptsCountOnlyWhereTheyAreRead() {
        let module = root + "/Documents/WindowsPowerShell/Modules/Az.DevCenter/1.0.0/"
        #expect(!filter().concerns(file(module + "Az.DevCenter.ps1", created, modified)))
        #expect(filter(includeCode: true).concerns(file(module + "Az.DevCenter.ps1", created, modified)))
        #expect(filter(code: true).concerns(file(module + "Az.DevCenter.ps1", created, modified)))
        for name in ["Az.DevCenter.psm1", "Az.DevCenter.psd1"] {
            #expect(!filter().concerns(file(module + name, created, modified)), "\(name)")
            #expect(!filter(code: true).concerns(file(module + name, created, modified)), "\(name)")
        }
    }

    @Test func whatGetsIndexedCounts() {
        for name in ["Q3 review.pdf", "IMG_0001.HEIC", "clip.mov", "voice memo.m4a", "deck.pptx", "notes.docx",
                     "logo.png", "song.mp3", "page.html", "app.ts", "clip.mts", "clip.m2ts"] {
            #expect(filter().concerns(file(root + "/Work/" + name, modified)), "\(name)")
        }
    }

    @Test func skippedFoldersAreIgnored() {
        let main = filter(), code = filter(code: true)
        #expect(!main.concerns(file(root + "/web/node_modules/react/index.js", created)))
        #expect(!code.concerns(file(root + "/web/node_modules/react/index.js", created)))
        #expect(!main.concerns(file(root + "/App/Caches/thumb.png", created)))
        #expect(code.concerns(file(root + "/App/Cache/log.swift", created)))   // in a project, often its own code
        #expect(!code.concerns(file(root + "/App/build/Generated.swift", created)))
        #expect(main.concerns(file(root + "/App/build/Manual.pdf", created)))
        #expect(!main.concerns(file(root + "/Photos.noindex/a.pdf", created)))
        #expect(!code.concerns(file(root + "/Photos.noindex/a.swift", created)))
    }

    @Test func theClosestChosenFolderDecides() {
        let docs = root + "/web/node_modules/docs"
        let watcher = filter(roots: [root, docs])
        #expect(watcher.concerns(file(docs + "/guide.pdf", created)))
        #expect(!watcher.concerns(file(root + "/web/node_modules/react/guide.pdf", created)))
    }

    @Test func libraryIsSkippedBelowHomeButNotWhenChosen() {
        // A made-up folder in ~/Library: OneDrive's is ~/Library/CloudStorage/OneDrive-…, which mustn't be touched here.
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let chosen = home + "/Library/BibloTest/OneDrive"
        let watcher = filter(roots: [home, chosen])
        #expect(!watcher.concerns(file(home + "/Library/Mail/V10/attachment.pdf", created)))
        #expect(watcher.concerns(file(chosen + "/Taxes.pdf", created)))
        #expect(watcher.concerns(file(home + "/Documents/Taxes.pdf", created)))
        #expect(!filter(roots: [home]).concerns(file(chosen + "/Taxes.pdf", created)))
    }

    @Test func eventsComeWithRealPaths() throws {
        // FSEvents reports /private/var/… where the chosen folder says /var/…, as the temporary folder does.
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("BibloTest-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder.appendingPathComponent("Private"),
                                                withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let real = FolderSelection.realPath(folder.path)
        #expect(real != folder.path)
        let watcher = filter(excludedFolders: [folder.path + "/Private"], roots: [folder.path])
        #expect(watcher.concerns(file(real + "/a.pdf", created)))
        #expect(!watcher.concerns(file(real + "/node_modules/b.pdf", created)))   // inside the folder, not elsewhere
        #expect(!watcher.concerns(file(real + "/Private/c.pdf", created)))
    }

    @Test func excludedFoldersAreIgnored() {
        let watcher = filter(excludedFolders: [root + "/Private"])
        #expect(!watcher.concerns(file(root + "/Private/a.pdf", created)))
        #expect(!watcher.concerns(file(root + "/Private/Taxes/b.pdf", modified)))
        #expect(!watcher.concerns(folder(root + "/Private", created)))
        #expect(watcher.concerns(file(root + "/Privateer/a.pdf", created)))
        // One around the chosen folder doesn't stop its walk.
        #expect(filter(excludedFolders: ["/Volumes/BibloTest"]).concerns(file(root + "/a.pdf", created)))
    }

    @Test func excludedTypesAreIgnored() {
        let main = filter(excludedTypes: "heic, *.TXT")
        #expect(!main.concerns(file(root + "/IMG_0001.HEIC", created)))
        #expect(!main.concerns(file(root + "/notes.txt", modified)))
        #expect(main.concerns(file(root + "/IMG_0002.jpg", created)))
        let code = filter(code: true, excludedTypes: "md")
        #expect(!code.concerns(file(root + "/repo/README.MD", modified)))
        #expect(code.concerns(file(root + "/repo/main.swift", modified)))
    }

    @Test func foldersCountWhenTheyComeOrGo() {
        let main = filter()
        #expect(!main.concerns(folder(root + "/Photos", kFSEventStreamEventFlagItemInodeMetaMod)))
        #expect(!main.concerns(folder(root + "/Photos", kFSEventStreamEventFlagItemXattrMod,
                                      kFSEventStreamEventFlagItemFinderInfoMod)))
        #expect(main.concerns(folder(root + "/Photos 2", created)))   // a copy, with what's in it
        #expect(main.concerns(folder(root + "/Old photos", renamed)))
        #expect(main.concerns(folder(root + "/Old photos", removed)))
        #expect(!main.concerns(folder(root + "/web/node_modules", created)))
        #expect(main.concerns(folder(root + "/App/build", created)))
        #expect(!filter(code: true).concerns(folder(root + "/App/build", created)))
    }

    @Test func lostTrackMeansRescan() {
        for flag in [kFSEventStreamEventFlagMustScanSubDirs, kFSEventStreamEventFlagUserDropped,
                     kFSEventStreamEventFlagKernelDropped, kFSEventStreamEventFlagRootChanged,
                     kFSEventStreamEventFlagMount, kFSEventStreamEventFlagUnmount] {
            #expect(filter().concerns(change(root + "/web/node_modules", [flag])))
            #expect(filter(code: true).concerns(change(root + "/web/node_modules", [flag])))
        }
    }

    @Test func whenInDoubtItIsAChange() {
        #expect(filter().concerns(file("/Volumes/Elsewhere/Budget.xlsx", modified)))   // outside every chosen folder
        #expect(filter().concerns(change(root + "/Budget.xlsx", [modified])))   // neither a file nor a folder
        #expect(filter().concerns(change(root + "/Budget.xlsx", [])))
    }

    @Test func aProjectMarkerCountsWhenItComesOrGoes() {
        // In a code project only screenshots are indexed: a marker coming or going changes what's indexed around it.
        #expect(filter().concerns(file(root + "/site/package.json", created)))
        #expect(filter().concerns(file(root + "/site/Package.swift", removed)))
        #expect(!filter().concerns(file(root + "/site/package.json", modified)))
    }

    @Test func namesWithoutAType() {
        #expect(!filter().concerns(file(root + "/README", created, modified)))
        let code = filter(code: true)
        #expect(code.concerns(file(root + "/repo/Makefile", modified)))
        #expect(code.concerns(file(root + "/repo/Dockerfile.dev", modified)))
        #expect(code.concerns(file(root + "/repo/README.md", modified)))
        #expect(!code.concerns(file(root + "/repo/LICENSE", modified)))
        #expect(!code.concerns(file(root + "/repo/package-lock.json", modified)))   // data
    }

    /// The filter must never hide a change a walk would index: whatever `classify` indexes, a change to it counts.
    @Test func neverMissesWhatAWalkIndexes() {
        var indexed = 0
        for includeCode in [false, true] {
            var options = IndexOptions()
            options.includeCode = includeCode
            let watcher = ChangeFilter(roots: [root], options: options)
            for name in extensions.flatMap({ ["x." + $0, "X." + $0.uppercased()] }) {
                let type = UTType(filenameExtension: (name as NSString).pathExtension)
                guard case .index = Rules.classify(URL(fileURLWithPath: "/nonexistent/" + name), type: type,
                                                   options: options) else { continue }
                indexed += 1
                #expect(watcher.concerns(file(root + "/" + name, modified)), "\(name), includeCode \(includeCode)")
            }
        }
        #expect(indexed > 100)

        var options = IndexOptions()
        options.code = true
        let code = ChangeFilter(roots: [root], options: options)
        var read = 0
        for name in extensions.map({ "x." + $0 }) + Rules.codeFileNames + ["Dockerfile.dev", "README", "LICENSE"] {
            guard case .index = Rules.classifyCode(URL(fileURLWithPath: "/nonexistent/" + name), options: options)
            else { continue }
            read += 1
            #expect(code.concerns(file(root + "/" + name, modified)), "\(name)")
        }
        #expect(read > 100)
    }

    /// OneDrive keeping a folder on the device marks each of its files before downloading it, and updates the
    /// placeholder of one changed elsewhere: a walk leaves those out. The download counts.
    @Test func filesOnlyInTheCloudAreIgnored() {
        let demos = root + "/Desktop/demos"
        let cloud: Set<String> = [demos + "/api/src/index.ts", root + "/Documents/Q3 review.pdf",
                                  demos + "/site/package.json"]
        var options = IndexOptions()
        let main = ChangeFilter(roots: [root], options: options, inTheCloud: { cloud.contains($0) })
        options.code = true
        let code = ChangeFilter(roots: [root], options: options, inTheCloud: { cloud.contains($0) })
        for watcher in [main, code] {
            #expect(!watcher.concerns(downloaded(demos + "/api/src/index.ts")))
            #expect(!watcher.concerns(file(root + "/Documents/Q3 review.pdf", modified)))
            #expect(!watcher.concerns(file(root + "/Documents/Q3 review.pdf", created)))   // a new one, elsewhere
        }
        #expect(code.concerns(downloaded(demos + "/api/src/server.ts")))
        #expect(main.concerns(downloaded(root + "/Documents/Q4 review.pdf")))
        #expect(main.concerns(file(root + "/Documents/Q4 review.pdf", removed)))
        // The walk sees a project's marker in the cloud too.
        #expect(main.concerns(file(demos + "/site/package.json", created)))
    }

    // MARK: Code projects (a walk keeps only screenshots inside one)

    @Test func insideACodeProjectOnlyScreenshotsCount() {
        let desktop = root + "/Desktop", demos = desktop + "/demos"
        var watcher = filter()
        watcher.setProjects([demos])
        // OneDrive downloading a web project: a walk keeps none of it.
        for name in ["index.html", "CLAUDE.md", "notes.txt", "src/game.ts", "assets/sprites/hero.png", "docs/plan.pdf",
                     "clip.mov"] {
            #expect(!watcher.concerns(downloaded(demos + "/" + name)), "\(name)")
            #expect(!watcher.concerns(file(demos + "/" + name, created, modified)), "\(name)")
            #expect(watcher.concerns(downloaded(desktop + "/" + name)), "\(name)")   // outside it
            #expect(filter().concerns(downloaded(demos + "/" + name)), "\(name)")    // before a walk said
        }
        #expect(watcher.concerns(downloaded(desktop + "/demos2/index.html")))   // a name that starts the same
        #expect(watcher.concerns(change(demos + "/index.html", [modified])))   // neither a file nor a folder
        var code = filter(code: true)
        code.setProjects([demos])
        #expect(code.concerns(file(demos + "/src/main.swift", modified)))   // the code index reads projects
        watcher.setProjects([])
        #expect(watcher.concerns(downloaded(demos + "/index.html")))   // a project no longer
    }

    @Test func aProjectCountsWhenWhatMayHoldScreenshotsGoes() {
        let demos = root + "/Desktop/demos"
        var watcher = filter()
        watcher.setProjects([demos])
        // A folder that came brings its files' own events; one that went (or moved here) may have held screenshots.
        #expect(!watcher.concerns(folder(demos + "/assets", created)))
        #expect(!watcher.concerns(folder(demos + "/assets", kFSEventStreamEventFlagItemInodeMetaMod)))
        #expect(watcher.concerns(folder(demos + "/assets", removed)))
        #expect(watcher.concerns(folder(demos + "/assets", renamed)))
        #expect(watcher.concerns(folder(demos, removed)))
        #expect(watcher.concerns(folder(demos + "/.git", removed)))   // maybe its only marker
        #expect(!watcher.concerns(folder(demos + "/.git", created)))
        // Its marker gone, it may be a project no longer. A nested project's makes no difference.
        #expect(watcher.concerns(file(demos + "/package.json", removed)))
        #expect(!watcher.concerns(file(demos + "/package.json", modified)))
        #expect(!watcher.concerns(file(demos + "/package.json", created)))
        #expect(!watcher.concerns(file(demos + "/server/package.json", removed)))
        #expect(!watcher.concerns(file(demos + "/server/package.json", created)))
        // An image that went may have been a screenshot: the mark went with it.
        #expect(watcher.concerns(file(demos + "/assets/hero.png", removed)))
        #expect(watcher.concerns(file(demos + "/assets/hero.png", renamed)))
        #expect(!watcher.concerns(file(demos + "/assets/hero.png", modified)))   // gone: its removal says so itself
        #expect(!watcher.concerns(file(demos + "/src/game.ts", removed)))
    }

    /// Inside a project the filter asks `Rules.mayBeImage` first: it must hold for every screenshot a walk keeps.
    @Test func neverMissesAScreenshotInAProject() {
        var screenshots = 0
        for includeCode in [false, true] {
            var options = IndexOptions()
            options.includeCode = includeCode
            for name in extensions.flatMap({ ["Screenshot 1." + $0, "CleanShot 2." + $0.uppercased()] }) {
                let type = UTType(filenameExtension: (name as NSString).pathExtension)
                guard Rules.classify(URL(fileURLWithPath: "/nonexistent/" + name), type: type, options: options)
                    == .index(.screenshot) else { continue }
                screenshots += 1
                #expect(Rules.mayBeImage(name, options: options), "\(name), includeCode \(includeCode)")
            }
        }
        #expect(screenshots > 20)
    }

    /// The projects a walk finds, passed on as the app does: inside them only what the walk keeps counts.
    @Test func projectsComeFromTheWalk() throws {
        let fm = FileManager.default
        let folder = fm.temporaryDirectory.appendingPathComponent("BibloTest-\(UUID().uuidString)")
        defer { try? fm.removeItem(at: folder) }
        let demos = folder.appendingPathComponent("Desktop/demos")
        let marker = demos.appendingPathComponent("package.json")
        let nested = demos.appendingPathComponent("server/package.json")
        let byName = demos.appendingPathComponent("Screenshot 2026-10-12 at 10.00.00.png")
        let marked = demos.appendingPathComponent("assets/Captura de pantalla 2026-10-12 a las 10.00.00.png")
        let sprite = demos.appendingPathComponent("assets/hero.png")
        let notes = folder.appendingPathComponent("Desktop/notes.md")
        let png = Data([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A])
        for (file, data) in [(marker, Data("{}".utf8)), (nested, Data("{}".utf8)), (byName, png), (marked, png),
                             (sprite, png), (notes, Data("# Notes\n".utf8))] {
            try fm.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
            try data.write(to: file)
        }
        // How macOS marks a screenshot whatever its name (a Spanish Mac's "Captura de pantalla").
        let yes = try PropertyListSerialization.data(fromPropertyList: true, format: .binary, options: 0)
        let marking = yes.withUnsafeBytes {
            setxattr(marked.path, "com.apple.metadata:kMDItemIsScreenCapture", $0.baseAddress, $0.count, 0, 0)
        }
        try #require(marking == 0)

        let report = Crawler.crawl([folder], options: IndexOptions())
        let real = FolderSelection.realPath
        #expect(report.projectRoots.map(real) == [real(demos.path)])   // the outermost only
        #expect(Set(report.candidates.map { real($0.path) }) == Set([byName, marked, notes].map { real($0.path) }))

        // As the walk names them, and in the form the folder was given (/var, where FSEvents says /private/var).
        for projects in [report.projectRoots, [demos.path]] {
            var watcher = ChangeFilter(roots: [folder.path], options: IndexOptions())
            watcher.setProjects(projects)
            for kept in report.candidates {
                #expect(watcher.concerns(file(real(kept.path), modified)), "\(kept.path)")
            }
            #expect(!watcher.concerns(downloaded(real(sprite.path))))
            #expect(!watcher.concerns(file(real(nested.path), modified)))
            #expect(!watcher.concerns(file(real(marker.path), created, renamed, modified)))   // saved: still there
            #expect(watcher.concerns(file(real(demos.path) + "/assets/old.png", removed)))
            #expect(watcher.concerns(downloaded(real(folder.path) + "/Desktop/hero.png")))
        }
    }
}
