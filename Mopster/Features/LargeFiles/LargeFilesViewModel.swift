import AppKit
import Foundation
import MopsterCore
import Observation

enum SizeThreshold: Int64, CaseIterable, Identifiable {
    case mb50 = 50_000_000
    case mb100 = 100_000_000
    case mb500 = 500_000_000
    case gb1 = 1_000_000_000

    var id: Int64 { rawValue }
}

enum AgeFilter: CaseIterable, Identifiable {
    case any, month, sixMonths, year

    var id: Self { self }

    var interval: TimeInterval? {
        switch self {
        case .any: nil
        case .month: 30 * 86_400
        case .sixMonths: 182 * 86_400
        case .year: 365 * 86_400
        }
    }
}

@MainActor @Observable
final class LargeFilesViewModel {
    typealias Scan = @Sendable (LargeFileQuery, @escaping @Sendable (ScanProgress) -> Void) async throws -> [LargeFile]

    /// The scan always uses the smallest threshold; the other filters apply to its result.
    nonisolated static let scanMinSize = SizeThreshold.mb50.rawValue

    let flow: ScanFlow<[LargeFile]>
    var minSize = SizeThreshold.mb50
    var age = AgeFilter.any
    var kinds = Set(FileKind.allCases)
    var sortOrder = [KeyPathComparator(\LargeFile.size, order: .reverse)]
    private(set) var includeLibraryAndHidden = false
    private(set) var scanned: [LargeFile] = []
    private(set) var checked: Set<String> = []
    var confirmingRemoval = false
    @ObservationIgnored private let env: AppEnvironment
    @ObservationIgnored private let now: @Sendable () -> Date

    convenience init(env: AppEnvironment) {
        let finder = env.largeFiles
        let ignore = env.ignoreList
        self.init(env: env) { query, progress in
            let list = await ignore.list
            return try await finder(list).find(query, progress: progress)
        }
    }

    /// Internal entry point for previews and screenshot scenes.
    init(
        env: AppEnvironment, initialPhase: ScanFlow<[LargeFile]>.Phase = .intro, initialSelection: Set<String> = [],
        now: @escaping @Sendable () -> Date = { .now }, scan: @escaping Scan
    ) {
        self.env = env
        self.now = now
        let box = WeakBox()
        flow = ScanFlow(initialPhase: initialPhase) { progress in
            let includeHidden = await box.model?.includeLibraryAndHidden
            let query = LargeFileQuery(
                minSize: LargeFilesViewModel.scanMinSize, includeLibraryAndHidden: includeHidden ?? false)
            let files = try await scan(query, progress)
            await box.model?.adopt(files)
            return files
        }
        box.model = self
        if case .results(let files) = initialPhase {
            adopt(files)
            checked = initialSelection
        }
    }

    @MainActor private final class WeakBox {
        weak var model: LargeFilesViewModel?
    }

    func start() { flow.start() }

    /// Runs inside the scan, before the flow publishes `.results`.
    private func adopt(_ files: [LargeFile]) {
        scanned = files
        checked = []
    }

    func setIncludeLibraryAndHidden(_ value: Bool) {
        guard value != includeLibraryAndHidden else { return }
        includeLibraryAndHidden = value
        if case .results = flow.phase { flow.start() }
    }

    // MARK: Filtering

    var visible: [LargeFile] {
        let reference = now()
        return scanned.filter { file in
            file.size >= minSize.rawValue && kinds.contains(file.kind)
                && age.interval.map { reference.timeIntervalSince(file.lastAccess) >= $0 } != false
        }
        .sorted(using: sortOrder)
    }

    func toggleKind(_ kind: FileKind) {
        if kinds.contains(kind) { kinds.remove(kind) } else { kinds.insert(kind) }
    }

    // MARK: Selection

    /// Checked files that the current filters still show, so the totals match what the user sees.
    var selectedFiles: [LargeFile] { visible.filter { checked.contains($0.id) } }
    var selectedSize: Int64 { selectedFiles.reduce(0) { $0 + $1.size } }

    /// The file's folder with the home abbreviated to `~`.
    func folder(of file: LargeFile) -> String {
        let home = env.isDemo ? DemoData.demoHome : env.home.path
        let folder = file.url.deletingLastPathComponent().path
        if folder == home { return "~" }
        return folder.hasPrefix(home + "/") ? "~" + folder.dropFirst(home.count) : folder
    }

    func isChecked(_ file: LargeFile) -> Bool { checked.contains(file.id) }

    func setChecked(_ file: LargeFile, _ value: Bool) {
        if value { checked.insert(file.id) } else { checked.remove(file.id) }
    }

    func reveal() {
        let urls = selectedFiles.map(\.url)
        guard !urls.isEmpty, !env.isDemo else { return }
        NSWorkspace.shared.activateFileViewerSelecting(urls)
    }

    func ignore(_ file: LargeFile) {
        env.ignoreList.add(file.url)
        scanned.removeAll { $0.id == file.id }
        checked.remove(file.id)
    }

    // MARK: Removal

    func requestRemoval() {
        guard !selectedFiles.isEmpty else { return }
        confirmingRemoval = true
    }

    func moveToTrash() {
        let urls = selectedFiles.map(\.url)
        guard !urls.isEmpty else { return }
        flow.remove(urls, using: env.remover)
    }
}
