import Darwin
import Foundation

public struct LargeFileQuery: Sendable, Equatable {
    public var minSize: Int64
    public var olderThan: TimeInterval?
    public var kinds: Set<FileKind>
    public var includeLibraryAndHidden: Bool

    public init(
        minSize: Int64 = 50_000_000, olderThan: TimeInterval? = nil, kinds: Set<FileKind> = Set(FileKind.allCases),
        includeLibraryAndHidden: Bool = false
    ) {
        self.minSize = minSize
        self.olderThan = olderThan
        self.kinds = kinds
        self.includeLibraryAndHidden = includeLibraryAndHidden
    }
}

public struct LargeFile: Identifiable, Sendable, Equatable {
    public var url: URL
    public var size: Int64
    /// Content access date, falling back to the modification date.
    public var lastAccess: Date
    public var kind: FileKind

    public var id: String { url.path }

    public init(url: URL, size: Int64, lastAccess: Date, kind: FileKind) {
        self.url = url
        self.size = size
        self.lastAccess = lastAccess
        self.kind = kind
    }
}

public protocol LargeFileFinding: Sendable {
    func find(_ query: LargeFileQuery, progress: @escaping @Sendable (ScanProgress) -> Void) async throws -> [LargeFile]
}

public struct LargeFileFinder: LargeFileFinding {
    private let home: URL
    private let ignore: IgnoreList
    private let now: Date

    public init(home: URL, ignore: IgnoreList = IgnoreList(), now: Date = .now) {
        self.home = home.standardizedFileURL
        self.ignore = ignore
        self.now = now
    }

    public func find(
        _ query: LargeFileQuery, progress: @escaping @Sendable (ScanProgress) -> Void
    ) async throws -> [LargeFile] {
        let scan = Task.detached(priority: .userInitiated) { try self.walk(query, progress: progress) }
        return try await withTaskCancellationHandler { try await scan.value } onCancel: { scan.cancel() }
    }

    private func realPath(_ path: String) -> String? {
        guard let resolved = realpath(path, nil) else { return nil }
        defer { free(resolved) }
        return String(cString: resolved)
    }

    private static let keys: [URLResourceKey] = [
        .isDirectoryKey, .isPackageKey, .isSymbolicLinkKey, .isHiddenKey, .totalFileAllocatedSizeKey,
        .fileAllocatedSizeKey, .contentAccessDateKey, .contentModificationDateKey,
    ]

    private func walk(
        _ query: LargeFileQuery, progress: @escaping @Sendable (ScanProgress) -> Void
    ) throws -> [LargeFile] {
        guard
            let enumerator = FileManager.default.enumerator(
                at: home, includingPropertiesForKeys: Self.keys, options: [.skipsPackageDescendants],
                errorHandler: { _, _ in true })
        else { return [] }

        let physicalRoot = realPath(home.path)
        func logical(_ url: URL) -> URL {
            guard let physicalRoot, physicalRoot != home.path, url.path.hasPrefix(physicalRoot) else { return url }
            return URL(fileURLWithPath: home.path + url.path.dropFirst(physicalRoot.count))
        }

        var found: [LargeFile] = []
        var visited = 0
        let checkIgnore = !ignore.paths.isEmpty

        while let physical = enumerator.nextObject() as? URL {
            try Task.checkCancellation()
            let url = logical(physical)
            visited += 1
            if visited % 500 == 0 {
                progress(ScanProgress(location: url.deletingLastPathComponent().path, itemsFound: found.count))
            }
            guard let values = try? physical.resourceValues(forKeys: Set(Self.keys)) else { continue }
            if values.isSymbolicLink == true { continue }
            let isDirectory = values.isDirectory == true
            let isPackage = values.isPackage == true

            if !query.includeLibraryAndHidden {
                let name = url.lastPathComponent
                let isHome = url.deletingLastPathComponent().standardizedFileURL.path == home.path
                if name.hasPrefix(".") || values.isHidden == true || (isHome && name == "Library") {
                    if isDirectory { enumerator.skipDescendants() }
                    continue
                }
            }
            if checkIgnore && ignore.contains(url) {
                if isDirectory { enumerator.skipDescendants() }
                continue
            }
            if isDirectory && !isPackage { continue }
            if isPackage && url.pathExtension.lowercased() == "app" { continue }

            let size = isPackage
                ? DiskUsage.allocatedSize(of: url)
                : Int64(values.totalFileAllocatedSize ?? values.fileAllocatedSize ?? 0)
            guard size >= query.minSize else { continue }
            let lastAccess = values.contentAccessDate ?? values.contentModificationDate ?? .distantPast
            if let olderThan = query.olderThan, now.timeIntervalSince(lastAccess) < olderThan { continue }
            let kind = isPackage ? FileKind.other : FileKind.of(extension: url.pathExtension)
            guard query.kinds.contains(kind) else { continue }
            found.append(LargeFile(url: url, size: size, lastAccess: lastAccess, kind: kind))
        }
        found.sort { $0.size != $1.size ? $0.size > $1.size : $0.url.path < $1.url.path }
        return found
    }
}
