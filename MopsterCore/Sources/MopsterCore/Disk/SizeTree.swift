import Darwin
import Foundation

public final class SizeNode: Identifiable, @unchecked Sendable {
    public static let otherFilesName = "Other files"

    public let url: URL
    public let name: String
    public let isDirectory: Bool
    public let isAggregate: Bool
    public let size: Int64
    public let children: [SizeNode]

    public var id: String { isAggregate ? url.path + "\u{0}aggregate" : url.path }

    public init(
        url: URL, name: String, isDirectory: Bool, isAggregate: Bool = false, size: Int64,
        children: [SizeNode] = []
    ) {
        self.url = url
        self.name = name
        self.isDirectory = isDirectory
        self.isAggregate = isAggregate
        self.size = size
        self.children = children
    }
}

public struct SizeTreeResult: Sendable {
    public var root: SizeNode
    public var skipped: [URL]

    public init(root: SizeNode, skipped: [URL]) {
        self.root = root
        self.skipped = skipped
    }
}

public protocol SizeTreeBuilding: Sendable {
    func build(root: URL, progress: @escaping @Sendable (ScanProgress) -> Void) async throws -> SizeTreeResult
}

public struct FtsSizeTreeBuilder: SizeTreeBuilding {
    public var keepFilesPerDirectory: Int

    public init(keepFilesPerDirectory: Int = 20) {
        self.keepFilesPerDirectory = keepFilesPerDirectory
    }

    public func build(root: URL, progress: @escaping @Sendable (ScanProgress) -> Void) async throws -> SizeTreeResult {
        let builder = SizeTreeBuilder(root: root, keepFilesPerDirectory: keepFilesPerDirectory)
        let walk = Task.detached(priority: .userInitiated) { try builder.build(progress: progress) }
        return try await withTaskCancellationHandler { try await walk.value } onCancel: { walk.cancel() }
    }
}

public struct SizeTreeBuilder: Sendable {
    public let root: URL
    public let keepFilesPerDirectory: Int

    public init(root: URL, keepFilesPerDirectory: Int = 20) {
        self.root = root
        self.keepFilesPerDirectory = max(0, keepFilesPerDirectory)
    }

    private struct FileEntry {
        var name: String
        var size: Int64
        func ranksBefore(_ other: FileEntry) -> Bool {
            size != other.size ? size > other.size : name < other.name
        }
    }

    private struct Frame {
        let path: String
        let ownSize: Int64
        var subdirectories: [SizeNode] = []
        var topFiles: [FileEntry] = []
        var otherSize: Int64 = 0
        var otherCount = 0
        var total: Int64 = 0

        mutating func add(name: @autoclosure () -> String, size: Int64, keep: Int) {
            total += size
            if topFiles.count == keep, let last = topFiles.last, size < last.size {
                otherSize += size
                otherCount += 1
                return
            }
            let entry = FileEntry(name: name(), size: size)
            var low = 0
            var high = topFiles.count
            while low < high {
                let mid = (low + high) / 2
                if topFiles[mid].ranksBefore(entry) { low = mid + 1 } else { high = mid }
            }
            if low >= keep {
                otherSize += size
                otherCount += 1
                return
            }
            topFiles.insert(entry, at: low)
            if topFiles.count > keep {
                let evicted = topFiles.removeLast()
                otherSize += evicted.size
                otherCount += 1
            }
        }
    }

    public func build(progress: @escaping @Sendable (ScanProgress) -> Void) throws -> SizeTreeResult {
        let rootURL = root.resolvingSymlinksInPath().standardizedFileURL
        var rootInfo = stat()
        if lstat(rootURL.path, &rootInfo) == 0, rootInfo.st_mode & S_IFMT != S_IFDIR {
            let leaf = SizeNode(
                url: rootURL, name: rootURL.lastPathComponent, isDirectory: false,
                size: Int64(rootInfo.st_blocks) * 512)
            return SizeTreeResult(root: leaf, skipped: [])
        }
        guard let cRoot = strdup(rootURL.path) else {
            return SizeTreeResult(root: SizeNode(url: rootURL, name: rootURL.lastPathComponent, isDirectory: true, size: 0), skipped: [])
        }
        defer { free(cRoot) }
        var paths: [UnsafeMutablePointer<CChar>?] = [cRoot, nil]
        guard let stream = fts_open(&paths, FTS_PHYSICAL | FTS_XDEV | FTS_NOCHDIR, nil) else {
            return SizeTreeResult(root: SizeNode(url: rootURL, name: rootURL.lastPathComponent, isDirectory: true, size: 0), skipped: [rootURL])
        }
        defer { fts_close(stream) }

        let keep = keepFilesPerDirectory
        var stack: [Frame] = []
        var rootNode: SizeNode?
        var skipped: [URL] = []
        var skippedSeen = Set<String>()
        var visited = 0
        var lastReport = ContinuousClock.now
        var lastReportedCount = 0
        var currentPath = rootURL.path

        func skip(_ path: String) {
            if skippedSeen.insert(path).inserted { skipped.append(URL(fileURLWithPath: path)) }
        }

        func name(of entry: UnsafeMutablePointer<FTSENT>) -> String {
            let pathLength = Int(entry.pointee.fts_pathlen)
            let nameLength = Int(entry.pointee.fts_namelen)
            return String(cString: entry.pointee.fts_path + (pathLength - nameLength))
        }

        func directoryNode(path: String, size: Int64, children: [SizeNode]) -> SizeNode {
            let url = URL(fileURLWithPath: path, isDirectory: true)
            return SizeNode(url: url, name: url.lastPathComponent, isDirectory: true, size: size, children: children)
        }

        func attach(_ node: SizeNode) {
            if stack.isEmpty {
                rootNode = node
            } else {
                stack[stack.count - 1].subdirectories.append(node)
                stack[stack.count - 1].total += node.size
            }
        }

        while let entry = fts_read(stream) {
            visited += 1
            if visited & 0xFF == 0 {
                try Task.checkCancellation()
                let now = ContinuousClock.now
                if visited - lastReportedCount >= 2000 || now - lastReport >= .milliseconds(100) {
                    progress(ScanProgress(location: currentPath, fraction: nil, itemsFound: visited))
                    lastReport = now
                    lastReportedCount = visited
                }
            } else if visited == 1 {
                try Task.checkCancellation()
            }

            let blocks = entry.pointee.fts_statp.map { Int64($0.pointee.st_blocks) * 512 } ?? 0
            switch Int32(entry.pointee.fts_info) {
            case FTS_D:
                let path = String(cString: entry.pointee.fts_path)
                currentPath = path
                stack.append(Frame(path: path, ownSize: blocks))
            case FTS_DP:
                guard let frame = stack.popLast() else { continue }
                var children = frame.subdirectories
                for file in frame.topFiles {
                    let url = URL(fileURLWithPath: frame.path, isDirectory: true).appendingPathComponent(file.name)
                    children.append(SizeNode(url: url, name: file.name, isDirectory: false, size: file.size))
                }
                if frame.otherCount > 0 {
                    children.append(
                        SizeNode(
                            url: URL(fileURLWithPath: frame.path, isDirectory: true), name: SizeNode.otherFilesName,
                            isDirectory: false, isAggregate: true, size: frame.otherSize))
                }
                children.sort { $0.size != $1.size ? $0.size > $1.size : $0.name < $1.name }
                attach(directoryNode(path: frame.path, size: frame.ownSize + frame.total, children: children))
            case FTS_DNR, FTS_ERR, FTS_NS:
                let path = String(cString: entry.pointee.fts_path)
                skip(path)
                if stack.last?.path == path, let frame = stack.popLast() {
                    attach(directoryNode(path: path, size: frame.ownSize, children: []))
                } else if Int32(entry.pointee.fts_info) == FTS_DNR {
                    attach(directoryNode(path: path, size: blocks, children: []))
                }
            case FTS_F, FTS_SL, FTS_SLNONE, FTS_DEFAULT, FTS_NSOK:
                if stack.isEmpty { continue }
                stack[stack.count - 1].add(name: name(of: entry), size: blocks, keep: keep)
            default:
                continue
            }
        }

        let node = rootNode ?? directoryNode(path: rootURL.path, size: 0, children: [])
        return SizeTreeResult(root: node, skipped: skipped)
    }
}
