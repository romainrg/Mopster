import AppKit
import Foundation
import MopsterCore
import Observation

enum DuplicateMinSize: Int64, CaseIterable, Identifiable {
    case mb1 = 1_000_000
    case mb10 = 10_000_000
    case mb100 = 100_000_000

    var id: Int64 { rawValue }
}

@MainActor @Observable
final class DuplicatesViewModel {
    typealias Scan = @Sendable ([URL], Int64, @escaping @Sendable (ScanProgress) -> Void) async throws -> DuplicateScan

    let flow: ScanFlow<[DuplicateGroup]>
    let isDemo: Bool
    private(set) var folders: [URL]
    var minSize = DuplicateMinSize.mb1
    private(set) var groups: [DuplicateGroup] = []
    private(set) var selection: Set<String> = []
    private(set) var skippedCloudOnly = 0
    /// The group whose last toggle was refused, showing the inline note.
    private(set) var refusedGroup: String?
    var confirmingRemoval = false
    @ObservationIgnored private let env: AppEnvironment
    @ObservationIgnored private var scanGuard: SafetyGuard
    @ObservationIgnored private var refusedVerdicts: [String: Bool] = [:]

    convenience init(env: AppEnvironment) {
        let finder = env.duplicates
        let ignore = env.ignoreList
        self.init(env: env) { folders, minSize, progress in
            let list = await ignore.list
            return try await finder(list).scan(in: folders, minSize: minSize, progress: progress)
        }
    }

    /// Internal entry point for previews and screenshot scenes.
    init(
        env: AppEnvironment, initialPhase: ScanFlow<[DuplicateGroup]>.Phase = .intro,
        initialSelection: Set<String> = [], initialRefusal: String? = nil, initialSkippedCloudOnly: Int = 0,
        scan: @escaping Scan
    ) {
        self.env = env
        scanGuard = env.guardian
        isDemo = env.isDemo
        let base = env.isDemo ? URL(fileURLWithPath: DemoData.demoHome) : env.home
        let defaults = ["Desktop", "Documents", "Downloads", "Pictures"].map {
            base.appendingPathComponent($0, isDirectory: true)
        }
        folders = env.isDemo ? defaults : defaults.filter { FileManager.default.fileExists(atPath: $0.path) }
        let box = WeakBox()
        flow = ScanFlow(initialPhase: initialPhase) { progress in
            let request = await box.request()
            let found = try await scan(request.0, request.1) { update in
                progress(DuplicatesViewModel.localized(update))
            }
            await box.model?.adopt(found.groups, skippedCloudOnly: found.skippedCloudOnly)
            return found.groups
        }
        box.model = self
        if case .results(let found) = initialPhase {
            adopt(found, skippedCloudOnly: initialSkippedCloudOnly)
            selection = DuplicateSelection.repaired(initialSelection, in: groups)
            refusedGroup = initialRefusal
        }
    }

    @MainActor private final class WeakBox {
        weak var model: DuplicatesViewModel?

        func request() -> ([URL], Int64) {
            model.map { ($0.folders, $0.minSize.rawValue) } ?? ([], DuplicateMinSize.mb1.rawValue)
        }
    }

    nonisolated private static func localized(_ progress: ScanProgress) -> ScanProgress {
        var progress = progress
        switch progress.location {
        case DuplicateStage.comparingSizes.rawValue: progress.location = String(localized: "Comparing sizes")
        case DuplicateStage.hashing.rawValue: progress.location = String(localized: "Hashing")
        default: break
        }
        return progress
    }

    func start() {
        guard !folders.isEmpty else { return }
        flow.start()
    }

    /// Runs inside the scan, before the flow publishes `.results`.
    private func adopt(_ found: [DuplicateGroup], skippedCloudOnly skipped: Int) {
        groups = found
        skippedCloudOnly = skipped
        scanGuard = folders.reduce(env.guardian) { $0.adding(root: $1.resolvingSymlinksInPath()) }
        refusedVerdicts = [:]
        selection = DuplicateSelection.repaired([], in: found)
        refusedGroup = nil
    }

    /// Whether the removal guard would refuse this file, so its row is disabled.
    func isProtected(_ file: DuplicateFile) -> Bool {
        let path = file.url.path
        if let cached = refusedVerdicts[path] { return cached }
        let refused = scanGuard.check(file.url) != .allowed
        refusedVerdicts[path] = refused
        return refused
    }

    // MARK: Folders

    func addFolder(_ url: URL) {
        let standardized = url.standardizedFileURL
        guard !folders.contains(where: { $0.standardizedFileURL.path == standardized.path }) else { return }
        folders.append(standardized)
    }

    func removeFolders(_ paths: Set<String>) {
        folders.removeAll { paths.contains($0.path) }
    }

    func display(_ folder: URL) -> String { abbreviate(folder.path) }

    // MARK: Selection

    var selectedFiles: [DuplicateFile] {
        groups.flatMap(\.files).filter { selection.contains($0.url.path) }
    }

    var selectedSize: Int64 {
        groups.reduce(0) { total, group in
            total + group.size * Int64(group.files.filter { selection.contains($0.url.path) }.count)
        }
    }

    var totalWasted: Int64 { groups.reduce(0) { $0 + $1.wastedSpace } }

    func isChecked(_ file: DuplicateFile) -> Bool { selection.contains(file.url.path) }

    func setChecked(_ file: DuplicateFile, in group: DuplicateGroup, _ value: Bool) {
        guard !isProtected(file) else { return }
        var candidate = selection
        if value { candidate.insert(file.url.path) } else { candidate.remove(file.url.path) }
        if DuplicateSelection.allows(candidate, in: groups) {
            selection = candidate
            refusedGroup = nil
        } else {
            refusedGroup = group.id
        }
    }

    func autoSelect() {
        selection = DuplicateSelection.autoSelect(groups).filter { !isProtected(path: $0) }
        refusedGroup = nil
    }

    func clearSelection() {
        selection = []
        refusedGroup = nil
    }

    func changeFolders() { flow.reset() }

    /// The file's folder with the home abbreviated to `~`.
    func folder(of file: DuplicateFile) -> String { abbreviate(file.url.deletingLastPathComponent().path) }

    private func abbreviate(_ path: String) -> String {
        let home = env.isDemo ? DemoData.demoHome : env.home.path
        if path == home { return "~" }
        return path.hasPrefix(home + "/") ? "~" + path.dropFirst(home.count) : path
    }

    func reveal(_ file: DuplicateFile) {
        guard !env.isDemo else { return }
        NSWorkspace.shared.activateFileViewerSelecting([file.url])
    }

    func ignore(_ file: DuplicateFile) {
        if !env.isDemo { env.ignoreList.add(file.url) }
        groups = groups.compactMap { group in
            var group = group
            group.files.removeAll { $0.url.path == file.url.path }
            return group.files.count > 1 ? group : nil
        }
        selection = DuplicateSelection.repaired(selection, in: groups)
        refusedGroup = nil
    }

    // MARK: Removal

    func requestRemoval() {
        guard !selection.isEmpty else { return }
        confirmingRemoval = true
    }

    func moveToTrash() {
        selection = selection.filter { !isProtected(path: $0) }
        let files = selectedFiles
        guard !files.isEmpty else { return }
        guard DuplicateSelection.allows(selection, in: groups) else {
            refusedGroup = groups.first { group in group.files.allSatisfy { selection.contains($0.url.path) } }?.id
            return
        }
        flow.remove(files.map(\.url), using: env.makeRemover(folders.map { $0.resolvingSymlinksInPath() }))
    }

    private func isProtected(path: String) -> Bool {
        isProtected(DuplicateFile(url: URL(fileURLWithPath: path), created: nil))
    }
}
