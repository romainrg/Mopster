import Foundation

public enum GroupState: Sendable { case none, some, all }

public struct Selection: Hashable, Sendable {
    public private(set) var selectedIDs: Set<String>

    public init(defaultsFrom groups: [CleanupGroup]) {
        selectedIDs = Set(groups.flatMap(\.items).filter(\.isSelectedByDefault).map(\.id))
    }

    public func contains(_ id: String) -> Bool { selectedIDs.contains(id) }

    public mutating func toggle(_ id: String) {
        if !selectedIDs.insert(id).inserted { selectedIDs.remove(id) }
    }

    public mutating func setAll(in group: CleanupGroup, _ on: Bool) {
        for item in group.items {
            if on { selectedIDs.insert(item.id) } else { selectedIDs.remove(item.id) }
        }
    }

    public func state(of group: CleanupGroup) -> GroupState {
        let count = group.items.filter { selectedIDs.contains($0.id) }.count
        if count == 0 { return .none }
        return count == group.items.count ? .all : .some
    }

    public func totalSize(in groups: [CleanupGroup]) -> Int64 {
        groups.flatMap(\.items).filter { selectedIDs.contains($0.id) }.reduce(0) { $0 + $1.size }
    }

    /// Selected URLs in group, then item, order.
    public func urls(in groups: [CleanupGroup]) -> [URL] {
        groups.flatMap(\.items).filter { selectedIDs.contains($0.id) }.map(\.url)
    }
}
