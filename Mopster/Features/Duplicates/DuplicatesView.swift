import AppKit
import MopsterCore
import QuickLookThumbnailing
import SwiftUI
import UniformTypeIdentifiers

struct DuplicatesView: View {
    @Bindable var model: DuplicatesViewModel
    @State private var highlightedFolders: Set<String> = []

    @ViewBuilder var body: some View {
        switch model.flow.phase {
        case .intro:
            setup
        case .scanning(let progress):
            FeatureScanning(progress: progress, tint: .duplicates, cancel: model.flow.cancel)
        case .results:
            results
        case .removing:
            ProgressView("Moving to the Trash…").frame(maxWidth: .infinity, maxHeight: .infinity)
        case .done(let report):
            FeatureDone(report: report, onDone: model.flow.reset)
        case .failed(let message):
            FeatureFailed(message: message, retry: model.start)
        }
    }

    // MARK: Setup

    private var setup: some View {
        VStack(spacing: 14) {
            ModuleIcon(symbol: "square.on.square", tint: .duplicates, size: 84)
                .shadow(color: ModuleTint.duplicates.end.opacity(0.35), radius: 18, y: 10)
            Text("Duplicates").font(.largeTitle.bold())
            Text("Find identical files and keep one copy.").font(.title3)
            Text("Compares file contents in the folders below. Nothing is changed until you move copies to the Trash.")
                .foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 6) {
                List(selection: $highlightedFolders) {
                    ForEach(model.folders, id: \.path) { folder in
                        Label { Text(verbatim: model.display(folder)) } icon: { Image(systemName: "folder") }
                            .tag(folder.path)
                    }
                }
                .scrollContentBackground(.hidden)
                .frame(height: 130)
                .themeCard()
                .overlay {
                    if model.folders.isEmpty {
                        Text("Add a folder to scan.").foregroundStyle(.secondary)
                    }
                }
                HStack {
                    Button("Add folder", systemImage: "plus", action: addFolder)
                    Button("Remove", systemImage: "minus") {
                        model.removeFolders(highlightedFolders)
                        highlightedFolders = []
                    }
                    .disabled(highlightedFolders.isEmpty)
                    Spacer()
                    Picker("Minimum size", selection: $model.minSize) {
                        ForEach(DuplicateMinSize.allCases) { Text(verbatim: Formatting.bytes($0.rawValue)).tag($0) }
                    }
                    .fixedSize()
                }
            }
            .frame(maxWidth: 480)
            Button("Scan", action: model.start)
                .buttonStyle(.gradient)
                .keyboardShortcut(.defaultAction)
                .disabled(model.folders.isEmpty)
                .padding(.top, 8)
        }
        .multilineTextAlignment(.center)
        .padding(32)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func addFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = true
        guard panel.runModal() == .OK else { return }
        panel.urls.forEach(model.addFolder)
    }

    // MARK: Results

    private var results: some View {
        VStack(spacing: 0) {
            toolbar
            if model.groups.isEmpty {
                Text("No duplicates found.")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .themeCard()
                    .padding(.horizontal, 24)
            } else {
                List {
                    ForEach(model.groups) { group in
                        Section {
                            ForEach(group.files, id: \.url) { file in row(file, in: group) }
                            if model.refusedGroup == group.id {
                                Label("Keep at least one copy.", systemImage: "exclamationmark.triangle.fill")
                                    .font(.callout)
                                    .foregroundStyle(.orange)
                            }
                        } header: {
                            header(group)
                        }
                    }
                }
                .themePanel()
            }
            if model.skippedCloudOnly > 0 {
                Text("\(model.skippedCloudOnly) cloud-only files skipped")
                    .font(.callout).foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 24).padding(.top, 10)
            }
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
        let count = model.selectedFiles.count
        let total = Formatting.bytes(model.selectedSize)
        return "Move \(count) copies (\(total)) to the Trash?"
    }

    private var toolbar: some View {
        ModuleHeader(
            .duplicates, subtitle: Text("\(model.groups.count) groups, \(Formatting.bytes(model.totalWasted)) wasted")
        ) {
            Button("Change folders", action: model.changeFolders).buttonStyle(.soft)
            Button("Clear", action: model.clearSelection).buttonStyle(.soft).disabled(model.selection.isEmpty)
            Button("Auto-select", action: model.autoSelect).buttonStyle(.soft)
        }
    }

    private func header(_ group: DuplicateGroup) -> some View {
        HStack {
            Text("\(Formatting.bytes(group.size)) each, \(group.files.count) copies")
                .font(.headline).foregroundStyle(.primary)
            Spacer()
            Text("\(Formatting.bytes(group.wastedSpace)) wasted")
                .foregroundStyle(.secondary).monospacedDigit()
        }
    }

    private func row(_ file: DuplicateFile, in group: DuplicateGroup) -> some View {
        HStack(spacing: 10) {
            Toggle(
                isOn: Binding(
                    get: { model.isChecked(file) }, set: { model.setChecked(file, in: group, $0) })
            ) { Text(verbatim: file.url.lastPathComponent) }
            .toggleStyle(.checkbox)
            .labelsHidden()
            .disabled(model.isProtected(file))
            DuplicateThumbnail(url: file.url, demo: model.isDemo)
            VStack(alignment: .leading, spacing: 2) {
                Text(verbatim: file.url.lastPathComponent).lineLimit(1).truncationMode(.middle)
                Text(verbatim: model.folder(of: file))
                    .font(.caption).foregroundStyle(.secondary).lineLimit(1).truncationMode(.head)
            }
            Spacer(minLength: 8)
            if let created = file.created {
                Text(created, format: .dateTime.year().month().day())
                    .foregroundStyle(.secondary).monospacedDigit()
            }
        }
        .contentShape(Rectangle())
        .help(model.isProtected(file) ? Text("Mopster won’t move this folder to the Trash.") : Text(verbatim: ""))
        .contextMenu {
            Button("Quick Look") { QuickLook.shared.preview(file.url) }
            Button("Reveal in Finder") { model.reveal(file) }
            Divider()
            Button("Always ignore") { model.ignore(file) }
        }
    }

    // MARK: Footer

    private var footer: some View {
        ModuleFooter {
            if model.selection.isEmpty {
                Text("Nothing selected").foregroundStyle(.secondary)
            } else {
                Text("\(Formatting.bytes(model.selectedSize)) selected").monospacedDigit()
            }
        } actions: {
            Button("Move to Trash", action: model.requestRemoval)
                .buttonStyle(.gradient)
                .disabled(model.selection.isEmpty)
        }
    }
}

private struct DuplicateThumbnail: View {
    let url: URL
    let demo: Bool
    @State private var image: NSImage?

    var body: some View {
        Group {
            if demo {
                Image(systemName: Self.symbol(for: url)).resizable().scaledToFit().padding(6).foregroundStyle(.secondary)
            } else if let image {
                Image(nsImage: image).resizable().scaledToFit()
            } else {
                Image(systemName: "doc").resizable().scaledToFit().padding(6).foregroundStyle(.tertiary)
            }
        }
        .frame(width: 32, height: 32)
        .task(id: url) {
            guard !demo else { return }
            image = await ThumbnailCache.shared.thumbnail(for: url)
        }
    }

    private static func symbol(for url: URL) -> String {
        switch FileKind.of(extension: url.pathExtension) {
        case .video: "film"
        case .archive: "doc.zipper"
        case .document: "doc.richtext"
        case .audio: "music.note"
        case .diskImage: "opticaldisc"
        case .other: ["jpg", "jpeg", "png", "heic", "gif", "tiff"].contains(url.pathExtension.lowercased()) ? "photo" : "doc"
        }
    }
}

@MainActor
private final class ThumbnailCache {
    static let shared = ThumbnailCache()
    private let cache = NSCache<NSURL, NSImage>()

    func thumbnail(for url: URL) async -> NSImage? {
        if let cached = cache.object(forKey: url as NSURL) { return cached }
        let scale = NSScreen.main?.backingScaleFactor ?? 2
        let request = QLThumbnailGenerator.Request(
            fileAt: url, size: CGSize(width: 32, height: 32), scale: scale, representationTypes: .all)
        guard let representation = try? await QLThumbnailGenerator.shared.generateBestRepresentation(for: request)
        else { return nil }
        let image = representation.nsImage
        cache.setObject(image, forKey: url as NSURL)
        return image
    }
}
