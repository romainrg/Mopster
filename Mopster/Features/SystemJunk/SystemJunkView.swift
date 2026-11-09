import MopsterCore
import SwiftUI

struct SystemJunkView: View {
    @Environment(FullDiskAccess.self) private var fullDiskAccess
    let model: SystemJunkViewModel

    @ViewBuilder var body: some View {
        switch model.flow.phase {
        case .intro:
            FeatureIntro(
                symbol: "trash", title: "System Junk",
                promise: "Clear caches, logs and leftovers that apps rebuild on their own.",
                scope: "Scans app and browser caches, logs, developer files, saved app state and installers in Downloads.",
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
        VStack(spacing: 0) {
            HStack {
                Text("\(Formatting.bytes(model.totalFound)) found").font(.headline).monospacedDigit()
                Spacer()
            }
            .padding([.horizontal, .top], 12)
            .padding(.bottom, 8)
            CleanupResultsView(
                groups: model.groups, selection: Bindable(model).selection, onRemove: model.clean,
                onIgnore: { model.ignore($0.url) })
            footnotes
        }
    }

    @ViewBuilder private var footnotes: some View {
        if !model.skipped.isEmpty || model.trashSize != nil {
            Divider()
            VStack(alignment: .leading, spacing: 4) {
                if !model.skipped.isEmpty {
                    HStack {
                        Text("Some locations couldn't be read.")
                        if !fullDiskAccess.isGranted {
                            Text("Grant Full Disk Access to include them.")
                            Button("Open Settings") { SystemSettings.open(.fullDiskAccess) }
                                .controlSize(.small)
                        }
                    }
                    DisclosureGroup("Skipped locations") {
                        VStack(alignment: .leading, spacing: 2) {
                            ForEach(model.skippedPaths, id: \.self) { Text(verbatim: $0).textSelection(.enabled) }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.top, 2)
                    }
                }
                if let trashSize = model.trashSize {
                    Text("Your Trash currently holds \(Formatting.bytes(trashSize)).")
                }
            }
            .font(.caption)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(12)
        }
    }
}
