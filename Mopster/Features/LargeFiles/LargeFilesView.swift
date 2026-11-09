import AppKit
import MopsterCore
import SwiftUI
import UniformTypeIdentifiers

struct LargeFilesView: View {
    @Bindable var model: LargeFilesViewModel
    @State private var highlighted: Set<LargeFile.ID> = []

    @ViewBuilder var body: some View {
        switch model.flow.phase {
        case .intro:
            FeatureIntro(
                symbol: "doc.text.magnifyingglass", title: "Large & Old Files",
                promise: "Find the big files you forgot about.",
                scope: "Scans your home folder for large files, then filters them by size, age and kind. Nothing is changed until you move files to the Trash.",
                action: model.start)
        case .scanning(let progress):
            FeatureScanning(progress: progress, cancel: model.flow.cancel)
        case .results:
            results
        case .removing:
            ProgressView("Moving to the Trash…").frame(maxWidth: .infinity, maxHeight: .infinity)
        case .done(let report):
            FeatureDone(report: report, onDone: model.flow.reset)
        case .failed(let message):
            VStack(spacing: 14) {
                Image(systemName: "exclamationmark.triangle").font(.system(size: 48)).foregroundStyle(.orange)
                Text("The scan failed").font(.title2.bold())
                Text(message).foregroundStyle(.secondary)
                Button("Retry", action: model.start).buttonStyle(.borderedProminent)
            }
            .padding(32)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private var results: some View {
        let files = model.visible
        return VStack(spacing: 0) {
            filterBar(count: files.count, total: files.reduce(0) { $0 + $1.size })
            Divider()
            if files.isEmpty {
                Text("No files match these filters.")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                table(files)
            }
            Divider()
            footer
        }
        .confirmationDialog(confirmationTitle, isPresented: $model.confirmingRemoval, titleVisibility: .visible) {
            Button("Move to Trash", role: .destructive, action: model.moveToTrash)
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("You can restore them from the Trash until you empty it.")
        }
    }

    private var confirmationTitle: LocalizedStringKey {
        let files = model.selectedFiles
        let total = Formatting.bytes(model.selectedSize)
        if files.count == 1, let file = files.first {
            return "Move “\(file.url.lastPathComponent)” (\(total)) to the Trash?"
        }
        return "Move \(files.count) files (\(total)) to the Trash?"
    }

    // MARK: Filters

    private func filterBar(count: Int, total: Int64) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 16) {
                Picker("Larger than", selection: $model.minSize) {
                    ForEach(SizeThreshold.allCases) { Text(verbatim: Formatting.bytes($0.rawValue)).tag($0) }
                }
                .fixedSize()
                Picker("Last opened", selection: $model.age) {
                    ForEach(AgeFilter.allCases) { Text($0.title).tag($0) }
                }
                .fixedSize()
                Spacer(minLength: 8)
                Toggle(
                    "Include Library and hidden folders",
                    isOn: Binding(
                        get: { model.includeLibraryAndHidden }, set: model.setIncludeLibraryAndHidden))
                    .toggleStyle(.checkbox)
            }
            HStack(spacing: 6) {
                ForEach(FileKind.allCases, id: \.self) { kind in
                    Toggle(
                        isOn: Binding(get: { model.kinds.contains(kind) }, set: { _ in model.toggleKind(kind) })
                    ) {
                        Label { Text(kind.title) } icon: { Image(systemName: kind.symbol) }
                    }
                    .toggleStyle(.button)
                    .controlSize(.small)
                }
                Spacer(minLength: 8)
                Text("\(count) files, \(Formatting.bytes(total))")
                    .font(.callout).foregroundStyle(.secondary).monospacedDigit()
            }
        }
        .padding(12)
    }

    // MARK: Table

    private func table(_ files: [LargeFile]) -> some View {
        Table(files, selection: $highlighted, sortOrder: $model.sortOrder) {
            TableColumn(String()) { file in
                Toggle(
                    isOn: Binding(get: { model.isChecked(file) }, set: { model.setChecked(file, $0) })
                ) { Text(verbatim: file.url.lastPathComponent) }
                .toggleStyle(.checkbox)
                .labelsHidden()
            }
            .width(24)
            TableColumn("Name") { file in
                HStack(spacing: 6) {
                    Image(nsImage: Self.icon(for: file)).resizable().frame(width: 18, height: 18)
                    Text(verbatim: file.url.lastPathComponent).lineLimit(1).truncationMode(.middle)
                }
            }
            .width(min: 160, ideal: 240)
            TableColumn("Folder") { file in
                Text(verbatim: model.folder(of: file))
                    .foregroundStyle(.secondary).lineLimit(1).truncationMode(.head)
            }
            .width(min: 120, ideal: 200)
            TableColumn("Kind") { file in Text(file.kind.title).foregroundStyle(.secondary) }
                .width(min: 70, ideal: 90)
            TableColumn("Last opened", value: \.lastAccess) { file in
                Text(file.lastAccess, format: .relative(presentation: .numeric, unitsStyle: .wide))
                    .foregroundStyle(.secondary).lineLimit(1)
            }
            .width(min: 100, ideal: 130)
            TableColumn("Size", value: \.size) { file in
                Text(verbatim: Formatting.bytes(file.size)).monospacedDigit().frame(maxWidth: .infinity, alignment: .trailing)
            }
            .width(min: 70, ideal: 90)
        }
        .contextMenu(forSelectionType: LargeFile.ID.self) { ids in
            if let file = files.first(where: { ids.contains($0.id) }) {
                Button("Quick Look") { QuickLook.shared.preview(file.url) }
                Button("Reveal in Finder") { reveal(file) }
                Divider()
                Button("Always ignore") { model.ignore(file) }
            }
        }
    }

    private func reveal(_ file: LargeFile) {
        NSWorkspace.shared.activateFileViewerSelecting([file.url])
    }

    private static func icon(for file: LargeFile) -> NSImage {
        if FileManager.default.fileExists(atPath: file.url.path) { return NSWorkspace.shared.icon(forFile: file.url.path) }
        return NSWorkspace.shared.icon(for: UTType(filenameExtension: file.url.pathExtension) ?? .data)
    }

    // MARK: Footer

    private var footer: some View {
        HStack {
            if model.selectedFiles.isEmpty {
                Text("Nothing selected").foregroundStyle(.secondary)
            } else {
                Text("\(Formatting.bytes(model.selectedSize)) selected").monospacedDigit()
            }
            Spacer()
            Button("Reveal in Finder", action: model.reveal).disabled(model.selectedFiles.isEmpty)
            Button("Move to Trash", action: model.requestRemoval)
                .buttonStyle(.borderedProminent)
                .disabled(model.selectedFiles.isEmpty)
        }
        .padding(12)
    }
}

extension AgeFilter {
    var title: LocalizedStringKey {
        switch self {
        case .any: "Any time"
        case .month: "Over 1 month ago"
        case .sixMonths: "Over 6 months ago"
        case .year: "Over 1 year ago"
        }
    }
}
