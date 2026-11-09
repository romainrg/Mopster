import AppKit
import Foundation
import Observation

@MainActor @Observable
final class FullDiskAccess {
    private(set) var isGranted: Bool
    private let isDemo: Bool
    @ObservationIgnored private var observer: (any NSObjectProtocol)?

    init(isDemo: Bool = false) {
        self.isDemo = isDemo
        isGranted = isDemo
        refresh()
        observer = NotificationCenter.default.addObserver(
            forName: NSApplication.didBecomeActiveNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.refresh() }
        }
    }

    deinit {
        if let observer { NotificationCenter.default.removeObserver(observer) }
    }

    func refresh() {
        isGranted = isDemo || Self.probe()
    }

    private static func probe() -> Bool {
        let path = "/Library/Application Support/com.apple.TCC/TCC.db"
        guard let handle = FileHandle(forReadingAtPath: path) else { return false }
        defer { try? handle.close() }
        return (try? handle.read(upToCount: 1)) != nil
    }
}
