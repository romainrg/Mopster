import Foundation

public protocol TrashOperation: Sendable {
    /// Moves the item to the Trash and returns its new location when known.
    func trash(_ url: URL) throws -> URL?
}

public struct TrashedItem: Sendable, Equatable {
    public let url: URL
    public let size: Int64

    public init(url: URL, size: Int64) {
        self.url = url
        self.size = size
    }
}

public struct RemovalFailure: Sendable, Equatable {
    public enum Reason: Sendable, Equatable {
        case refused(SafetyRefusal)
        case alreadyGone
        case failed(String)
    }

    public let url: URL
    public let reason: Reason

    public init(url: URL, reason: Reason) {
        self.url = url
        self.reason = reason
    }
}

public struct RemovalReport: Sendable, Equatable {
    public var trashed: [TrashedItem]
    public var failures: [RemovalFailure]
    public var trashedBytes: Int64

    public init(trashed: [TrashedItem] = [], failures: [RemovalFailure] = [], trashedBytes: Int64 = 0) {
        self.trashed = trashed
        self.failures = failures
        self.trashedBytes = trashedBytes
    }
}

public protocol ItemRemover: Sendable {
    func remove(_ urls: [URL]) async -> RemovalReport
}
