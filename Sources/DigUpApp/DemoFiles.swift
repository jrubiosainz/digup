import Foundation

/// Demo mode's sample files: documents, slides, pictures, screenshots, recordings, videos and code about public
/// Microsoft products and made-up companies (Contoso, Fabrikam), nobody's real work. scripts/make-demo.sh makes them
/// into Resources/Demo and the app carries them; turning demo mode on, and each launch in it, copies them to
/// ~/Biblo Demo, where they open, preview and show in Finder like any file. So a demo, or a screen recording of one,
/// never shows a real file.
nonisolated enum DemoFiles {
    /// ~/Biblo Demo: in the home folder, not Documents or Desktop, which macOS guards app by app. `-demoFolder` for tests.
    static let folder: URL = {
        let path = UserDefaults.standard.string(forKey: "demoFolder").flatMap { $0.isEmpty ? nil : $0 }
            ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Biblo Demo").path
        return AppSettings.folderURL(path)
    }()

    /// The samples' code projects, searched with "code:" as code in any code folder is.
    static var code: URL { folder.appendingPathComponent("Code") }

    /// The app's copy (Contents/Resources/Demo).
    static var bundled: URL? {
        guard let url = Bundle.main.resourceURL?.appendingPathComponent("Demo"), AppSettings.isFolder(url) else {
            return nil
        }
        return url
    }

    /// Copies the app's samples into `folder`: each one missing there, or not the same as the app's (a newer Biblo's).
    /// Files added there stay. Returns how many were copied.
    @discardableResult
    static func install() throws -> Int {
        guard let source = bundled?.standardizedFileURL else { throw Problem.notInThisCopy }
        let manager = FileManager.default
        let keys: Set<URLResourceKey> = [.isDirectoryKey, .fileSizeKey, .contentModificationDateKey]
        guard let walk = manager.enumerator(at: source, includingPropertiesForKeys: Array(keys)) else {
            throw Problem.notInThisCopy
        }
        try manager.createDirectory(at: folder, withIntermediateDirectories: true)
        var copied = 0
        for case let url as URL in walk where url.lastPathComponent != ".DS_Store" {   // .gitignore is a sample too
            let parts = url.standardizedFileURL.pathComponents
            guard parts.count > source.pathComponents.count,
                  Array(parts.prefix(source.pathComponents.count)) == source.pathComponents else { continue }
            let target = parts.dropFirst(source.pathComponents.count)
                .reduce(folder) { $0.appendingPathComponent($1) }
            let values = try url.resourceValues(forKeys: keys)
            if values.isDirectory == true {
                try manager.createDirectory(at: target, withIntermediateDirectories: true)
                continue
            }
            if let there = try? target.resourceValues(forKeys: keys), there.fileSize == values.fileSize,
               there.contentModificationDate == values.contentModificationDate { continue }
            if manager.fileExists(atPath: target.path) { try manager.removeItem(at: target) }
            try manager.copyItem(at: url, to: target)   // a clone on APFS: no space taken, and the same date
            copied += 1
        }
        return copied
    }

    enum Problem: Error, CustomStringConvertible {
        case notInThisCopy

        var description: String { "this copy of Biblo has no sample files" }
    }
}
