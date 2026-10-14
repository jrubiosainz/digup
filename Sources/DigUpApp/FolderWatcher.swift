import CoreServices
import DigUpKit
import Foundation

/// File-level FSEvents on the chosen folders. Reports what changed, a batch at a time; the engine debounces and
/// syncs. Costs nothing while nothing changes (no polling). Each sync walks every folder again (minutes, on a big
/// OneDrive), so what it would find the same is left out: hidden files (.DS_Store, editors' temp files), since
/// browsing a folder in Finder writes those; what `filter` says can't change the index (a workbook autosaving every
/// two minutes, a folder of scripts downloading, a code project's files); and what changes inside packages, which the
/// walk never reads (Photos keeps writing its library in ~/Pictures).
nonisolated final class FolderWatcher: @unchecked Sendable {
    private var stream: FSEventStreamRef?
    private let roots: [String]
    private var filter: ChangeFilter   // on the queue
    private let handler: @Sendable (_ changed: [FileChange], _ ignored: [FileChange]) -> Void

    init?(paths: [String], filter: ChangeFilter, latency: TimeInterval, queue: DispatchQueue,
          handler: @escaping @Sendable (_ changed: [FileChange], _ ignored: [FileChange]) -> Void) {
        self.roots = paths.flatMap { [$0, FolderSelection.realPath($0)] }  // events come with real paths
        self.filter = filter
        self.handler = handler
        guard !paths.isEmpty else { return nil }
        var context = FSEventStreamContext(version: 0, info: Unmanaged.passUnretained(self).toOpaque(),
                                           retain: nil, release: nil, copyDescription: nil)
        let flags = kFSEventStreamCreateFlagUseCFTypes | kFSEventStreamCreateFlagFileEvents
            | kFSEventStreamCreateFlagNoDefer
        guard let stream = FSEventStreamCreate(kCFAllocatorDefault, folderWatcherCallback, &context,
                                               paths as CFArray, FSEventStreamEventId(kFSEventStreamEventIdSinceNow),
                                               latency, FSEventStreamCreateFlags(flags)) else { return nil }
        self.stream = stream
        FSEventStreamSetDispatchQueue(stream, queue)
        guard FSEventStreamStart(stream) else {
            FSEventStreamInvalidate(stream)
            FSEventStreamRelease(stream)
            self.stream = nil
            return nil
        }
    }

    deinit {
        guard let stream else { return }
        FSEventStreamStop(stream)
        FSEventStreamInvalidate(stream)
        FSEventStreamRelease(stream)
    }

    /// The code projects the last walk found (`ChangeFilter.setProjects`). On the queue it was made with.
    func setProjects(_ projects: [String]) { filter.setProjects(projects) }

    fileprivate func received(_ changes: [FileChange]) {
        // A project's .git going is noticed (what's around it is indexed again), not what changes inside it.
        let visible = changes.filter { change in
            let names = change.path.split(separator: "/")
            return !names.enumerated().contains { $1.hasPrefix(".") && ($0 < names.count - 1 || $1 != ".git") }
        }
        // The filter before the package check: it hardly touches the disk (thousands of files a minute, downloading).
        var changed: [FileChange] = [], ignored: [FileChange] = []
        for change in visible {
            if filter.concerns(change), !Crawler.isInPackage(change.path, below: roots) {
                changed.append(change)
            } else {
                ignored.append(change)
            }
        }
        if !visible.isEmpty { handler(changed, ignored) }
    }
}

private nonisolated func folderWatcherCallback(
    _ stream: ConstFSEventStreamRef, _ info: UnsafeMutableRawPointer?, _ count: Int,
    _ paths: UnsafeMutableRawPointer, _ flags: UnsafePointer<FSEventStreamEventFlags>,
    _ ids: UnsafePointer<FSEventStreamEventId>
) {
    guard let info else { return }
    let watcher = Unmanaged<FolderWatcher>.fromOpaque(info).takeUnretainedValue()
    let list = Unmanaged<CFArray>.fromOpaque(paths).takeUnretainedValue() as? [String] ?? []
    watcher.received(zip(list, UnsafeBufferPointer(start: flags, count: count)).map(FileChange.init))
}
