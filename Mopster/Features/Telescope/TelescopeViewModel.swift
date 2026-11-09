import AppKit
import Foundation
import MopsterCore
import Observation
import UniformTypeIdentifiers

/// One tile of the map and one row of the side list: a child of the current folder, or the "Smaller items" remainder.
struct TelescopeItem: Identifiable {
    enum Kind { case folder, media, archive, application, file, aggregate, smaller }

    static let smallerID = "\u{0}smaller"

    let id: String
    let node: SizeNode?
    let name: String
    let size: Int64
    let kind: Kind
    var isProtected = false

    var url: URL? { node?.url }
    var isSelectable: Bool { node != nil && kind != .aggregate && !isProtected }
    var isDiveable: Bool { node?.isDirectory == true && !(node?.children.isEmpty ?? true) }
}

@MainActor @Observable
final class TelescopeViewModel {
    static let maxTiles = 300

    let flow: ScanFlow<SizeTreeResult>
    private(set) var root: URL
    private(set) var tree: SizeNode?
    private(set) var skipped: [URL] = []
    private(set) var path: [SizeNode] = []
    private(set) var selection: Set<String> = []
    private(set) var removed: [String: Int64] = [:]
    var hoveredID: String?
    var confirmingRemoval = false
    private(set) var showsReport = false
    @ObservationIgnored private var known: [String: SizeNode] = [:]
    @ObservationIgnored private var protectedVerdicts: [String: Bool] = [:]
    @ObservationIgnored private var scanGuard: SafetyGuard?
    @ObservationIgnored private let env: AppEnvironment

    convenience init(env: AppEnvironment) {
        let builder = env.sizeTree
        self.init(env: env) { root, progress in try await builder.build(root: root, progress: progress) }
    }

    /// Internal entry point for previews and screenshot scenes. `initialDive` lists folder names below the root.
    init(
        env: AppEnvironment, initialPhase: ScanFlow<SizeTreeResult>.Phase = .intro, initialDive: [String] = [],
        initialSelection: Set<String> = [],
        scan: @escaping @Sendable (URL, @escaping @Sendable (ScanProgress) -> Void) async throws -> SizeTreeResult
    ) {
        self.env = env
        root = env.isDemo ? DemoSizeTree.root : env.home
        let box = WeakBox()
        flow = ScanFlow(initialPhase: initialPhase) { progress in
            let root = await box.model?.root ?? DemoSizeTree.root
            let result = try await scan(root, progress)
            await box.model?.adopt(result)
            return result
        }
        box.model = self
        if case .results(let result) = initialPhase {
            adopt(result)
            for name in initialDive {
                if let child = path.last?.children.first(where: { $0.name == name && $0.isDirectory }) { path.append(child) }
            }
            for id in initialSelection { if let node = path.last?.children.first(where: { $0.id == id }) { select(node) } }
        }
    }

    @MainActor private final class WeakBox {
        weak var model: TelescopeViewModel?
    }

    var current: SizeNode? { path.last }
    var displayedRoot: URL { tree?.url ?? root }
    var isDirty: Bool { !removed.isEmpty }

    func scan() {
        if case .scanning = flow.phase { flow.cancel() }
        flow.start()
    }

    func choose() {
        guard !env.isDemo else { return }
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.directoryURL = root
        panel.message = String(localized: "Choose a folder or volume to scan")
        panel.prompt = String(localized: "Scan")
        guard panel.runModal() == .OK, let url = panel.url else { return }
        root = url
        tree = nil
        path = []
        scan()
    }

    private func adopt(_ result: SizeTreeResult) {
        tree = result.root
        skipped = result.skipped
        path = [result.root]
        selection = []
        known = [:]
        removed = [:]
        protectedVerdicts = [:]
        scanGuard = env.guardian.adding(root: result.root.url)
        showsReport = false
    }

    /// Whether the guard would refuse this node (structural folders, the scanned root, secret stores).
    private func isProtected(_ node: SizeNode) -> Bool {
        guard !node.isAggregate, let scanGuard else { return false }
        if let cached = protectedVerdicts[node.id] { return cached }
        let refused = scanGuard.check(node.url) != .allowed
        protectedVerdicts[node.id] = refused
        return refused
    }

    // MARK: Navigation

    func dive(into item: TelescopeItem) {
        guard item.isDiveable, let node = item.node else { return }
        path.append(node)
        hoveredID = nil
    }

    func climb(to index: Int) {
        guard path.indices.contains(index), index < path.count - 1 else { return }
        path.removeSubrange((index + 1)...)
        hoveredID = nil
    }

    // MARK: Display

    func displayedSize(_ node: SizeNode) -> Int64 {
        guard !removed.isEmpty, !node.isAggregate else { return node.size }
        let own = node.url.path
        let prefix = own.hasSuffix("/") ? own : own + "/"
        let gone = removed.reduce(Int64(0)) { $0 + ($1.key == own || $1.key.hasPrefix(prefix) ? $1.value : 0) }
        return max(0, node.size - gone)
    }

    private func isRemoved(_ node: SizeNode) -> Bool {
        !node.isAggregate && removed[node.url.path] != nil
    }

    var totalSize: Int64 { tree.map(displayedSize) ?? 0 }
    var currentSize: Int64 { current.map(displayedSize) ?? 0 }

    /// The current folder's visible children by size, the largest `maxTiles` plus one "Smaller items" remainder.
    var items: [TelescopeItem] {
        guard let current else { return [] }
        let sized = current.children.filter { !isRemoved($0) }.map { ($0, displayedSize($0)) }
            .sorted { $0.1 != $1.1 ? $0.1 > $1.1 : $0.0.name < $1.0.name }
        var result = sized.prefix(Self.maxTiles).map { node, size in
            TelescopeItem(
                id: node.id, node: node, name: Self.displayName(node), size: size, kind: Self.kind(of: node),
                isProtected: isProtected(node))
        }
        let rest = sized.dropFirst(Self.maxTiles).reduce(Int64(0)) { $0 + $1.1 }
        if rest > 0 {
            result.append(
                TelescopeItem(
                    id: TelescopeItem.smallerID, node: nil, name: String(localized: "Smaller items"), size: rest,
                    kind: .smaller))
        }
        return result
    }

    static func displayName(_ node: SizeNode) -> String {
        node.isAggregate ? String(localized: "Other files") : node.name
    }

    static func kind(of node: SizeNode) -> TelescopeItem.Kind {
        if node.isAggregate { return .aggregate }
        let ext = node.url.pathExtension
        if node.isDirectory { return ext.lowercased() == "app" ? .application : .folder }
        guard let type = UTType(filenameExtension: ext) else { return .file }
        if type.conforms(to: .movie) || type.conforms(to: .audio) || type.conforms(to: .image) { return .media }
        if type.conforms(to: .archive) || type.conforms(to: .diskImage) { return .archive }
        return .file
    }

    // MARK: Selection

    func toggle(_ item: TelescopeItem) {
        guard item.isSelectable, let node = item.node else { return }
        if selection.contains(node.id) { selection.remove(node.id) } else { select(node) }
    }

    private func select(_ node: SizeNode) {
        guard !node.isAggregate, !isProtected(node) else { return }
        selection.insert(node.id)
        known[node.id] = node
    }

    /// Selected nodes that are not inside another selected node, so nothing is counted or removed twice.
    var selectedNodes: [SizeNode] {
        let paths = selection.compactMap { known[$0] }
        let folders = paths.filter(\.isDirectory).map { $0.url.path + "/" }
        return paths.filter { node in !folders.contains { node.url.path.hasPrefix($0) } }
            .sorted { $0.url.path < $1.url.path }
    }

    var selectedSize: Int64 { selectedNodes.reduce(0) { $0 + displayedSize($1) } }

    func reveal() {
        let urls = selectedNodes.map(\.url)
        guard !urls.isEmpty, !env.isDemo else { return }
        NSWorkspace.shared.activateFileViewerSelecting(urls)
    }

    func ignore(_ item: TelescopeItem) {
        guard let url = item.url, item.isSelectable else { return }
        env.ignoreList.add(url)
    }

    // MARK: Removal

    func requestRemoval() {
        guard !selectedNodes.isEmpty else { return }
        confirmingRemoval = true
    }

    func moveToTrash() {
        let nodes = selectedNodes
        guard !nodes.isEmpty, let rootURL = path.first?.url else { return }
        let sizes = Dictionary(nodes.map { ($0.url.path, displayedSize($0)) }, uniquingKeysWith: { first, _ in first })
        let base = env.makeRemover([rootURL])
        showsReport = true
        flow.remove(
            nodes.map(\.url),
            using: ReportingRemover(base: base) { [weak self] report in self?.apply(report, sizes: sizes) })
    }

    func dismissReport() { showsReport = false }

    /// Hides what left the disk, with the size the map showed, without rescanning.
    private func apply(_ report: RemovalReport, sizes: [String: Int64]) {
        let gone = report.trashed.map(\.url) + report.failures.filter { $0.reason == .alreadyGone }.map(\.url)
        for url in gone { removed[url.path] = sizes[url.path] ?? 0 }
        selection = []
        known = [:]
    }
}

private struct ReportingRemover: ItemRemover {
    let base: any ItemRemover
    let onReport: @MainActor @Sendable (RemovalReport) -> Void

    func remove(_ urls: [URL]) async -> RemovalReport {
        let report = await base.remove(urls)
        await onReport(report)
        return report
    }
}
