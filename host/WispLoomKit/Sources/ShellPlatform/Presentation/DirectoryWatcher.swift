import CoreServices
import Foundation

/// Reports file changes under a directory through FSEvents: event-driven, no polling. `latency` is the
/// debounce window, so a burst of writes arrives as one call.
@MainActor
public final class DirectoryWatcher {
    private var stream: FSEventStreamRef?
    private let handler: @MainActor ([String]) -> Void

    public init?(path: URL, latency: TimeInterval = 0.2, handler: @escaping @MainActor ([String]) -> Void) {
        self.handler = handler
        var context = FSEventStreamContext(
            version: 0, info: Unmanaged.passUnretained(self).toOpaque(), retain: nil, release: nil, copyDescription: nil
        )
        let callback: FSEventStreamCallback = { _, info, count, paths, _, _ in
            guard let info else { return }
            let watcher = Unmanaged<DirectoryWatcher>.fromOpaque(info).takeUnretainedValue()
            let list = unsafeBitCast(paths, to: NSArray.self)
            var changed: [String] = []
            for index in 0..<count { if let path = list[index] as? String { changed.append(path) } }
            // The stream runs on the main queue.
            MainActor.assumeIsolated { watcher.handler(changed) }
        }
        let flags = UInt32(kFSEventStreamCreateFlagFileEvents | kFSEventStreamCreateFlagUseCFTypes)
        guard
            let stream = FSEventStreamCreate(
                nil, callback, &context, [path.resolvingSymlinksInPath().path] as CFArray,
                FSEventStreamEventId(kFSEventStreamEventIdSinceNow), latency, flags)
        else { return nil }
        FSEventStreamSetDispatchQueue(stream, .main)
        guard FSEventStreamStart(stream) else {
            FSEventStreamInvalidate(stream)
            FSEventStreamRelease(stream)
            return nil
        }
        self.stream = stream
    }

    isolated deinit {
        guard let stream else { return }
        FSEventStreamStop(stream)
        FSEventStreamInvalidate(stream)
        FSEventStreamRelease(stream)
    }
}
