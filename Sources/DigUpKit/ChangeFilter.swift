import CoreServices
import Foundation

/// A path FSEvents reported and what happened to it (`kFSEventStreamEventFlag…`). FSEvents merges what happens to a
/// path in quick succession: one change can say created, modified and removed at once.
public struct FileChange: Sendable, Equatable {
    public let path: String
    public let flags: FSEventStreamEventFlags

    public init(path: String, flags: FSEventStreamEventFlags) {
        self.path = path
        self.flags = flags
    }

    private func has(_ flag: Int) -> Bool { flags & FSEventStreamEventFlags(flag) != 0 }

    var isFile: Bool { has(kFSEventStreamEventFlagItemIsFile) || has(kFSEventStreamEventFlagItemIsSymlink) }
    var isFolder: Bool { has(kFSEventStreamEventFlagItemIsDir) }
    /// FSEvents lost track (its queue overflowed), or a volume came or went: anything below `path` may have changed.
    var mustRescan: Bool {
        [kFSEventStreamEventFlagMustScanSubDirs, kFSEventStreamEventFlagUserDropped,
         kFSEventStreamEventFlagKernelDropped, kFSEventStreamEventFlagRootChanged, kFSEventStreamEventFlagMount,
         kFSEventStreamEventFlagUnmount].contains(where: has)
    }
    /// It appeared, went or moved (a copy, a download, a rename, a Finder duplicate), rather than changed in place.
    var cameOrWent: Bool {
        [kFSEventStreamEventFlagItemCreated, kFSEventStreamEventFlagItemRemoved, kFSEventStreamEventFlagItemRenamed,
         kFSEventStreamEventFlagItemCloned].contains(where: has)
    }
    /// It went or moved (a move reports both where it was and where it is now).
    var went: Bool {
        [kFSEventStreamEventFlagItemRemoved, kFSEventStreamEventFlagItemRenamed].contains(where: has)
    }
}

/// Whether a change can change what a walk of the folders finds (`Crawler`, `Rules`). The app syncs only for those: a
/// sync walks every chosen folder again (half a minute on a big OneDrive; the code index's, minutes), and some apps
/// write all day where nothing gets indexed: Excel autosaving a workbook every two minutes, OneDrive downloading a
/// folder of scripts, a build, a code project's assets. Decided from the path and the flags (FSEvents can report
/// thousands of files a minute): the disk is only asked about a file that would count, whether it's only in the
/// cloud, and about images inside code projects, whether they're screenshots. When in doubt, it's a change.
public struct ChangeFilter: Sendable {
    private let roots: [String]
    /// Chosen folders whose real path differs (/var → /private/var), as given and as FSEvents reports them.
    private let aliases: [(given: String, real: String)]
    private let excluded: [String]
    private let options: IndexOptions
    private let library: String
    private let inTheCloud: @Sendable (String) -> Bool
    private var projects: Set<String> = []

    /// The folders and options a sync walks with (`options.code`: the code index's).
    public init(roots: [String], options: IndexOptions) {
        self.init(roots: roots, options: options, inTheCloud: Rules.isInTheCloud)
    }

    /// `inTheCloud`: whether a file is a dataless placeholder (`Rules.isInTheCloud`; a test can't make one).
    init(roots: [String], options: IndexOptions, inTheCloud: @escaping @Sendable (String) -> Bool) {
        // FSEvents reports real paths (/private/var where the folder says /var).
        func withRealPaths(_ paths: [String]) -> [String] {
            var seen = Set<String>()
            return paths.flatMap { [$0, FolderSelection.realPath($0)] }.filter { seen.insert($0).inserted }
        }
        self.roots = withRealPaths(roots)
        aliases = roots.map { (given: $0, real: FolderSelection.realPath($0)) }.filter { $0.given != $0.real }
        excluded = withRealPaths(options.excludedFolders)
        self.options = options
        library = FileManager.default.homeDirectoryForCurrentUser.path + "/Library"
        self.inTheCloud = inTheCloud
    }

    /// The code projects the last walk found (`CrawlReport.projectRoots`), where it keeps only screenshots. Not for the
    /// code index. Until a walk says, none: everything counts as it would anywhere.
    public mutating func setProjects(_ folders: [String]) {
        var known = Set<String>()
        for folder in folders {
            known.insert(folder)
            // The walk may say /var where FSEvents says /private/var, or the other way round.
            for (given, real) in aliases {
                if folder == given || FolderSelection.isInside(folder, given) {
                    known.insert(real + folder.dropFirst(given.count))
                } else if folder == real || FolderSelection.isInside(folder, real) {
                    known.insert(given + folder.dropFirst(real.count))
                }
            }
        }
        projects = known
    }

    public func concerns(_ change: FileChange) -> Bool {
        if change.mustRescan { return true }
        let path = change.path
        // The walk of the closest chosen folder decides: skips apply below a chosen folder, never to it or above it
        // (a folder chosen inside a skipped one is walked whole).
        guard let root = roots.filter({ path == $0 || FolderSelection.isInside(path, $0) })
            .max(by: { $0.count < $1.count }) else { return true }
        if excluded.contains(where: {
            FolderSelection.isInside($0, root) && (path == $0 || FolderSelection.isInside(path, $0))
        }) {
            return false
        }
        let base = root.hasSuffix("/") ? String(root.dropLast()) : root
        var names = path == root ? [] : path.dropFirst(base.count + 1).split(separator: "/").map(String.init)
        if !change.isFolder, !names.isEmpty { names.removeLast() }   // a file: the folders it's in
        var folder = base
        for name in names {
            folder += "/" + name
            if Rules.skipsFolder(named: name, code: options.code) || folder == library { return false }
        }
        if !options.code, let project = project(of: path) { return concerns(change, inProject: project) }
        if change.isFolder, change.cameOrWent { return true }   // with what's in it
        guard change.isFile else { return !change.isFolder }    // a folder changed in place (its date, its tags)
        let name = (path as NSString).lastPathComponent
        // A walk leaves out a file that's only in the cloud. OneDrive marks every file of a folder kept on the device,
        // and updates one changed elsewhere, without downloading it; its download comes as a change of its own. One
        // made cloud-only again ("Free up space") stays in the index until the next walk.
        if options.code {
            return Rules.mayBeCode(name) && !options.excludedExtensions.contains((name as NSString).pathExtension.lowercased())
                && !inTheCloud(path)
        }
        // A project's marker coming or going changes what's indexed around it (only screenshots, inside a project),
        // in the cloud too: the walk sees it there.
        return Rules.mayBeIndexed(name, options: options) && !inTheCloud(path)
            || change.cameOrWent && Rules.isProjectMarker(name)
    }

    /// The outermost known code project `path` is in, or is (as the walk sees it: above the chosen folder too).
    private func project(of path: String) -> String? {
        guard !projects.isEmpty else { return nil }
        var found: String?
        var folder = path
        while folder.count > 1 {
            if projects.contains(folder) { found = folder }
            folder = (folder as NSString).deletingLastPathComponent
        }
        return found
    }

    /// Inside a code project a walk keeps only screenshots, while OneDrive downloading it, a build or an editor can
    /// write there all day.
    private func concerns(_ change: FileChange, inProject project: String) -> Bool {
        // One that came brings its files' own events; one that went, or moved here (no events for what's in it), may
        // hold screenshots.
        if change.isFolder { return change.went }
        guard change.isFile else { return true }
        let path = change.path
        let name = (path as NSString).lastPathComponent
        let gone = !FileManager.default.fileExists(atPath: path)
        // Without its marker the folder may be a project no longer (an editor's save puts a new one in its place).
        if Rules.isProjectMarker(name), (path as NSString).deletingLastPathComponent == project {
            return change.went && gone
        }
        guard Rules.mayBeImage(name, options: options) else { return false }
        if gone { return change.went }   // it may have been a screenshot: the mark went with it
        return Rules.isScreenshot(URL(fileURLWithPath: path))
    }
}
