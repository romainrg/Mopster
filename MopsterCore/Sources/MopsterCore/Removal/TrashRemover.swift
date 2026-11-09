import Darwin
import Foundation

public struct FileManagerTrash: TrashOperation {
    public init() {}

    public func trash(_ url: URL) throws -> URL? {
        var result: NSURL?
        try FileManager.default.trashItem(at: url, resultingItemURL: &result)
        return result as URL?
    }
}

/// Moves items to the Trash, never anywhere else. Each item is re-checked against the guard at call time.
public struct TrashRemover: ItemRemover {
    private let safetyGuard: SafetyGuard
    private let primary: TrashOperation
    private let fallback: TrashOperation?

    public init(guard safetyGuard: SafetyGuard, primary: TrashOperation, fallback: TrashOperation?) {
        self.safetyGuard = safetyGuard
        self.primary = primary
        self.fallback = fallback
    }

    public func remove(_ urls: [URL]) async -> RemovalReport {
        var report = RemovalReport()
        for url in Self.withoutNested(urls) {
            guard Self.existsWithoutFollowingLinks(url) else {
                report.failures.append(RemovalFailure(url: url, reason: .alreadyGone))
                continue
            }
            let size = DiskUsage.allocatedSize(of: url)
            if case .refused(let refusal) = safetyGuard.check(url) {
                report.failures.append(RemovalFailure(url: url, reason: .refused(refusal)))
                continue
            }
            do {
                _ = try trash(url)
                report.trashed.append(TrashedItem(url: url, size: size))
                report.trashedBytes += size
            } catch {
                report.failures.append(RemovalFailure(url: url, reason: .failed(error.localizedDescription)))
            }
        }
        return report
    }

    private func trash(_ url: URL) throws -> URL? {
        do {
            return try primary.trash(url)
        } catch {
            guard let fallback, Self.isPermissionError(error) else { throw error }
            return try fallback.trash(url)
        }
    }

    private static func existsWithoutFollowingLinks(_ url: URL) -> Bool {
        var info = stat()
        return lstat(url.path, &info) == 0
    }

    /// Drops duplicates and any URL located inside another selected URL, keeping input order.
    private static func withoutNested(_ urls: [URL]) -> [URL] {
        let components = urls.map(PathComponents.literal)
        return urls.indices.filter { index in
            !components.indices.contains { other in
                guard other != index, components[index].starts(with: components[other]) else { return false }
                return components[index].count > components[other].count || other < index
            }
        }.map { urls[$0] }
    }

    private static func isPermissionError(_ error: Error) -> Bool {
        var current: NSError? = error as NSError
        while let nsError = current {
            switch nsError.domain {
            case NSCocoaErrorDomain:
                if nsError.code == CocoaError.fileWriteNoPermission.rawValue
                    || nsError.code == CocoaError.fileReadNoPermission.rawValue
                {
                    return true
                }
            case NSPOSIXErrorDomain:
                if nsError.code == Int(EPERM) || nsError.code == Int(EACCES) { return true }
            default:
                break
            }
            current = nsError.userInfo[NSUnderlyingErrorKey] as? NSError
        }
        return false
    }
}
