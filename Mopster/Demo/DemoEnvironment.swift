import Foundation
import MopsterCore

/// Simulated removal: reports every item as trashed and never touches the disk.
enum DemoEnvironment {
    static let remover: any ItemRemover = DemoRemover()
}

private struct DemoRemover: ItemRemover {
    func remove(_ urls: [URL]) async -> RemovalReport {
        try? await Task.sleep(for: .milliseconds(500))
        let trashed = urls.map { TrashedItem(url: $0, size: DemoData.sizes[$0.path] ?? 0) }
        return RemovalReport(trashed: trashed, trashedBytes: trashed.reduce(0) { $0 + $1.size })
    }
}
