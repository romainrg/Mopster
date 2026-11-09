import CryptoKit
import Darwin
import Foundation

public struct DuplicateFile: Sendable, Equatable {
    public var url: URL
    public var created: Date?

    public init(url: URL, created: Date?) {
        self.url = url
        self.created = created
    }
}

public struct DuplicateGroup: Identifiable, Sendable, Equatable {
    /// The full SHA-256 of the content, in hex.
    public var id: String
    public var size: Int64
    /// Oldest first (by creation date, then path).
    public var files: [DuplicateFile]

    public var wastedSpace: Int64 { size * Int64(max(files.count - 1, 0)) }

    public init(id: String, size: Int64, files: [DuplicateFile]) {
        self.id = id
        self.size = size
        self.files = files
    }
}

/// Neutral stage names reported in `ScanProgress.location`; the app localizes them.
public enum DuplicateStage: String, Sendable {
    case comparingSizes = "Comparing sizes"
    case hashing = "Hashing"
}

public struct DuplicateScan: Sendable, Equatable {
    public var groups: [DuplicateGroup]
    /// Files left out because their content lives only in the cloud (reading them would download them).
    public var skippedCloudOnly: Int

    public init(groups: [DuplicateGroup], skippedCloudOnly: Int = 0) {
        self.groups = groups
        self.skippedCloudOnly = skippedCloudOnly
    }
}

public protocol DuplicateFinding: Sendable {
    func scan(
        in folders: [URL], minSize: Int64, progress: @escaping @Sendable (ScanProgress) -> Void
    ) async throws -> DuplicateScan
}

public extension DuplicateFinding {
    func find(
        in folders: [URL], minSize: Int64, progress: @escaping @Sendable (ScanProgress) -> Void
    ) async throws -> [DuplicateGroup] {
        try await scan(in: folders, minSize: minSize, progress: progress).groups
    }

    func find(
        in folders: [URL], progress: @escaping @Sendable (ScanProgress) -> Void
    ) async throws -> [DuplicateGroup] {
        try await find(in: folders, minSize: 1_000_000, progress: progress)
    }
}

public enum DuplicateSelection {
    /// Selects every copy but the oldest of each group (creation date, then path order). Selection ids are file paths.
    public static func autoSelect(_ groups: [DuplicateGroup]) -> Set<String> {
        var selection: Set<String> = []
        for group in groups {
            guard let keeper = group.files.min(by: isOlder) else { continue }
            for file in group.files where file.url.path != keeper.url.path { selection.insert(file.url.path) }
        }
        return selection
    }

    /// False when the selection would remove every copy of some group.
    public static func allows(_ selection: Set<String>, in groups: [DuplicateGroup]) -> Bool {
        !groups.contains { group in
            !group.files.isEmpty && group.files.allSatisfy { selection.contains($0.url.path) }
        }
    }

    /// Drops selected paths that no longer belong to a group of two or more files, and deselects the oldest
    /// remaining copy of any group that ended up fully selected.
    public static func repaired(_ selection: Set<String>, in groups: [DuplicateGroup]) -> Set<String> {
        var result: Set<String> = []
        for group in groups where group.files.count > 1 {
            var chosen = Set(group.files.map(\.url.path)).intersection(selection)
            if chosen.count == group.files.count, let keeper = group.files.min(by: isOlder) {
                chosen.remove(keeper.url.path)
            }
            result.formUnion(chosen)
        }
        return result
    }

    fileprivate static func isOlder(_ lhs: DuplicateFile, _ rhs: DuplicateFile) -> Bool {
        let left = lhs.created ?? .distantFuture
        let right = rhs.created ?? .distantFuture
        return left != right ? left < right : lhs.url.path < rhs.url.path
    }
}

public struct DuplicateFinder: DuplicateFinding {
    /// `SF_DATALESS` from `<sys/stat.h>`: the file's content is not on disk.
    static let datalessFlag: UInt32 = 0x4000_0000

    private let ignore: IgnoreList
    private let statFlags: @Sendable (String) -> UInt32

    public init(ignore: IgnoreList = IgnoreList()) {
        self.init(ignore: ignore, statFlags: { Self.lstatFlags($0) })
    }

    init(ignore: IgnoreList = IgnoreList(), statFlags: @escaping @Sendable (String) -> UInt32) {
        self.ignore = ignore
        self.statFlags = statFlags
    }

    private static func lstatFlags(_ path: String) -> UInt32 {
        var info = stat()
        return lstat(path, &info) == 0 ? info.st_flags : 0
    }

    public func scan(
        in folders: [URL], minSize: Int64, progress: @escaping @Sendable (ScanProgress) -> Void
    ) async throws -> DuplicateScan {
        let scan = Task.detached(priority: .userInitiated) {
            try self.run(folders, minSize: minSize, progress: progress)
        }
        return try await withTaskCancellationHandler { try await scan.value } onCancel: { scan.cancel() }
    }

    private struct Candidate {
        var url: URL
        var created: Date?
    }

    private static let keys: [URLResourceKey] = [
        .isDirectoryKey, .isPackageKey, .isSymbolicLinkKey, .isRegularFileKey, .isHiddenKey, .fileSizeKey,
        .creationDateKey,
    ]
    private static let firstBlock = 4_096
    private static let chunk = 1_048_576

    private func realPath(_ path: String) -> String? {
        guard let resolved = realpath(path, nil) else { return nil }
        defer { free(resolved) }
        return String(cString: resolved)
    }

    private func run(
        _ folders: [URL], minSize: Int64, progress: @escaping @Sendable (ScanProgress) -> Void
    ) throws -> DuplicateScan {
        let (bySize, skippedCloudOnly) = try collect(folders, minSize: minSize, progress: progress)
        let sizeCandidates = bySize.filter { $0.value.count > 1 }
        let total = sizeCandidates.values.reduce(0) { $0 + $1.count }
        var hashed = 0
        var groups: [DuplicateGroup] = []

        func report(_ stage: DuplicateStage) {
            progress(
                ScanProgress(
                    location: stage.rawValue, fraction: total == 0 ? nil : min(Double(hashed) / Double(total * 2), 1),
                    itemsFound: groups.count))
        }

        report(.comparingSizes)
        var byFirstBlock: [String: [Candidate]] = [:]
        for (size, candidates) in sizeCandidates {
            for candidate in candidates {
                try Task.checkCancellation()
                hashed += 1
                if hashed % 20 == 0 { report(.comparingSizes) }
                guard let digest = try digest(of: candidate.url, limit: Self.firstBlock) else { continue }
                byFirstBlock["\(size)-\(digest)", default: []].append(candidate)
            }
        }

        hashed = total
        for (key, candidates) in byFirstBlock where candidates.count > 1 {
            let size = Int64(key.prefix { $0 != "-" }) ?? 0
            var byDigest: [String: [Candidate]] = [:]
            for candidate in candidates {
                try Task.checkCancellation()
                hashed += 1
                report(.hashing)
                let limit = size <= Int64(Self.firstBlock) ? Self.firstBlock : nil
                guard let digest = try digest(of: candidate.url, limit: limit) else { continue }
                byDigest[digest, default: []].append(candidate)
            }
            for (digest, same) in byDigest where same.count > 1 {
                let files = same.map { DuplicateFile(url: $0.url, created: $0.created) }
                    .sorted(by: DuplicateSelection.isOlder)
                groups.append(DuplicateGroup(id: digest, size: size, files: files))
            }
        }

        groups.sort { lhs, rhs in
            lhs.wastedSpace != rhs.wastedSpace ? lhs.wastedSpace > rhs.wastedSpace : lhs.id < rhs.id
        }
        return DuplicateScan(groups: groups, skippedCloudOnly: skippedCloudOnly)
    }

    /// Candidates grouped by exact size, one per inode, in the spelling of the folders passed in, and the
    /// number of cloud-only files left out.
    private func collect(
        _ folders: [URL], minSize: Int64, progress: @escaping @Sendable (ScanProgress) -> Void
    ) throws -> ([Int64: [Candidate]], Int) {
        var skippedCloudOnly = 0
        var bySize: [Int64: [Candidate]] = [:]
        var seenPaths: Set<String> = []
        var seenInodes: Set<InodeKey> = []
        var visited = 0
        let checkIgnore = !ignore.paths.isEmpty

        for folder in folders {
            let root = folder.standardizedFileURL
            guard
                let enumerator = FileManager.default.enumerator(
                    at: root, includingPropertiesForKeys: Self.keys, options: [.skipsPackageDescendants],
                    errorHandler: { _, _ in true })
            else { continue }
            let physicalRoot = realPath(root.path)
            func logical(_ url: URL) -> URL {
                guard let physicalRoot, physicalRoot != root.path, url.path.hasPrefix(physicalRoot) else { return url }
                return URL(fileURLWithPath: root.path + url.path.dropFirst(physicalRoot.count))
            }

            while let physical = enumerator.nextObject() as? URL {
                try Task.checkCancellation()
                visited += 1
                let url = logical(physical)
                if visited % 500 == 0 {
                    progress(ScanProgress(location: url.deletingLastPathComponent().path, itemsFound: visited))
                }
                guard let values = try? physical.resourceValues(forKeys: Set(Self.keys)) else { continue }
                let isDirectory = values.isDirectory == true
                if values.isSymbolicLink == true { continue }
                if url.lastPathComponent.hasPrefix(".") || values.isHidden == true {
                    if isDirectory { enumerator.skipDescendants() }
                    continue
                }
                if checkIgnore && ignore.contains(url) {
                    if isDirectory { enumerator.skipDescendants() }
                    continue
                }
                if values.isPackage == true {
                    enumerator.skipDescendants()
                    continue
                }
                guard values.isRegularFile == true else { continue }
                let size = Int64(values.fileSize ?? 0)
                guard size >= minSize, size > 0 else { continue }
                guard seenPaths.insert(url.standardizedFileURL.path).inserted else { continue }
                if statFlags(physical.path) & Self.datalessFlag != 0 {
                    skippedCloudOnly += 1
                    continue
                }
                guard let inode = InodeKey(path: physical.path), seenInodes.insert(inode).inserted else { continue }
                bySize[size, default: []].append(Candidate(url: url, created: values.creationDate))
            }
        }
        return (bySize, skippedCloudOnly)
    }

    private struct InodeKey: Hashable {
        let device: Int32
        let inode: UInt64

        init?(path: String) {
            var info = stat()
            guard lstat(path, &info) == 0 else { return nil }
            device = info.st_dev
            inode = info.st_ino
        }
    }

    /// Hex SHA-256 of the first `limit` bytes (the whole file when `nil`), streamed in 1 MB chunks.
    /// `nil` when the file cannot be read.
    private func digest(of url: URL, limit: Int?) throws -> String? {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? handle.close() }
        var hasher = SHA256()
        var remaining = limit ?? Int.max
        while remaining > 0 {
            try Task.checkCancellation()
            let data: Data?
            do { data = try handle.read(upToCount: min(Self.chunk, remaining)) } catch { return nil }
            guard let data, !data.isEmpty else { break }
            hasher.update(data: data)
            remaining -= data.count
        }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }
}
