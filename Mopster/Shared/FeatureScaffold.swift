import AppKit
import MopsterCore
import SwiftUI

struct FeatureIntro: View {
    let symbol: String
    let title: LocalizedStringResource
    let promise: LocalizedStringResource
    let scope: LocalizedStringResource
    var actionTitle: LocalizedStringKey = "Scan"
    let action: () -> Void

    var body: some View {
        VStack(spacing: 14) {
            Image(systemName: symbol)
                .font(.system(size: 56))
                .foregroundStyle(.tint)
            Text(title).font(.largeTitle.bold())
            Text(promise).font(.title3)
            Text(scope).foregroundStyle(.secondary)
            Button(actionTitle, action: action)
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .keyboardShortcut(.defaultAction)
                .padding(.top, 8)
        }
        .multilineTextAlignment(.center)
        .padding(32)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct FeatureScanning: View {
    let progress: ScanProgress
    let cancel: () -> Void

    var body: some View {
        VStack(spacing: 14) {
            if let fraction = progress.fraction {
                ProgressView(value: fraction).frame(maxWidth: 320)
            } else {
                ProgressView().controlSize(.large)
            }
            Text("Scanning…").font(.title3)
            if let location = progress.location {
                Text(location)
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .frame(maxWidth: 480)
            }
            Text("\(progress.itemsFound) items found")
                .foregroundStyle(.secondary)
                .monospacedDigit()
            Button("Cancel", action: cancel).keyboardShortcut(.cancelAction)
        }
        .padding(32)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct FeatureDone: View {
    let report: RemovalReport
    var onDone: () -> Void = {}

    var body: some View {
        VStack(spacing: 14) {
            Image(systemName: "trash.circle.fill")
                .font(.system(size: 56))
                .foregroundStyle(.tint)
            Text("Moved \(Formatting.bytes(report.trashedBytes)) to the Trash")
                .font(.title2.bold())
            Text("The space is freed once you empty the Trash.")
                .foregroundStyle(.secondary)
            List {
                Section("Moved to the Trash (\(report.trashed.count))") {
                    ForEach(report.trashed, id: \.url) { item in
                        HStack {
                            Text(item.url.lastPathComponent).lineLimit(1).truncationMode(.middle)
                            Spacer()
                            Text(Formatting.bytes(item.size)).foregroundStyle(.secondary).monospacedDigit()
                        }
                        .help(item.url.path)
                    }
                }
                if !report.failures.isEmpty {
                    DisclosureGroup("Not removed (\(report.failures.count))") {
                        ForEach(report.failures, id: \.url) { failure in
                            VStack(alignment: .leading) {
                                Text(failure.url.lastPathComponent).lineLimit(1).truncationMode(.middle)
                                Text(Self.phrase(for: failure.reason)).font(.caption).foregroundStyle(.secondary)
                            }
                            .help(failure.url.path)
                        }
                    }
                }
            }
            .frame(maxWidth: 560)
            HStack {
                Button("Open Trash") {
                    NSWorkspace.shared.open(FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".Trash"))
                }
                Button("Done", action: onDone).buttonStyle(.borderedProminent).keyboardShortcut(.defaultAction)
            }
        }
        .padding(32)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    static func phrase(for reason: RemovalFailure.Reason) -> LocalizedStringResource {
        switch reason {
        case .refused(.outsideAllowedRoots): "Outside the folders Mopster may clean"
        case .refused(.protectedSystemPath): "Protected system location"
        case .refused(.insideAppBundle): "Inside an application"
        case .refused(.structuralFolder): "Essential folder"
        case .refused(.secretStore): "Holds passwords or keys"
        case .refused(.mopsterItself): "Part of Mopster itself"
        case .refused(.unresolvable): "Location could not be verified"
        case .alreadyGone: "Already gone"
        case .failed(let message): "Failed: \(message)"
        }
    }
}

#Preview("Done") {
    FeatureDone(
        report: RemovalReport(
            trashed: [TrashedItem(url: URL(fileURLWithPath: "/tmp/Cache"), size: 12_000_000)],
            failures: [RemovalFailure(url: URL(fileURLWithPath: "/tmp/Gone"), reason: .alreadyGone)],
            trashedBytes: 12_000_000))
}
