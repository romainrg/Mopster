import MopsterCore
import SwiftUI

struct UpdaterView: View {
    @Bindable var model: UpdaterViewModel

    @ViewBuilder var body: some View {
        switch model.flow.phase {
        case .intro:
            FeatureIntro(
                symbol: "arrow.down.app", title: "Updater",
                promise: "Find out which apps and macOS have an update waiting.",
                scope: "Asks the App Store and each app's own update feed. Mopster installs nothing.",
                actionTitle: "Check for updates", action: model.check)
        case .scanning, .removing:
            VStack(spacing: 14) {
                ProgressView().controlSize(.large)
                Text("Checking for updates…").font(.title3)
                Button("Cancel", action: model.flow.cancel).keyboardShortcut(.cancelAction)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        case .results, .done:
            if let result = model.result { results(result) }
        case .failed(let message):
            VStack(spacing: 14) {
                Image(systemName: "exclamationmark.triangle").font(.system(size: 48)).foregroundStyle(.orange)
                Text("The scan failed").font(.title2.bold())
                Text(message).foregroundStyle(.secondary)
                Button("Retry", action: model.check).buttonStyle(.borderedProminent)
            }
            .padding(32)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private func results(_ result: UpdateCheckResult) -> some View {
        VStack(spacing: 0) {
            HStack {
                summary(result)
                Spacer()
            }
            .padding([.horizontal, .top], 12)
            .padding(.bottom, 8)
            List {
                Section("macOS updates") { systemRows(result.system) }
                Section("App updates") {
                    if result.updates.isEmpty {
                        Text("All the apps we could check are up to date.").foregroundStyle(.secondary)
                    }
                    ForEach(result.updates) { update in
                        AppUpdateRow(update: update) { model.update(update) }
                    }
                }
                if !result.unknown.isEmpty {
                    Section {
                        DisclosureGroup(isExpanded: $model.unknownExpanded) {
                            ForEach(result.unknown) { app in
                                HStack(spacing: 10) {
                                    AppIcon(url: app.url, size: 24)
                                    Text(verbatim: app.name).lineLimit(1)
                                    Spacer()
                                    Text(verbatim: app.version).foregroundStyle(.secondary).monospacedDigit()
                                }
                            }
                        } label: {
                            Text("Couldn't check (\(result.unknown.count))")
                        }
                    }
                }
            }
            Divider()
            HStack {
                Text("Mopster only contacts Apple's App Store lookup and the apps' own update feeds.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Check again", action: model.check).controlSize(.small)
            }
            .padding(12)
        }
    }

    @ViewBuilder private func summary(_ result: UpdateCheckResult) -> some View {
        let count = result.updates.count + (result.system?.count ?? 0)
        if count == 0 {
            Text("Everything is up to date").font(.headline)
        } else {
            Text("\(count) updates available").font(.headline).monospacedDigit()
        }
    }

    @ViewBuilder private func systemRows(_ system: [SystemUpdate]?) -> some View {
        if let system {
            if system.isEmpty {
                Text("macOS is up to date.").foregroundStyle(.secondary)
            }
            ForEach(system, id: \.label) { update in
                HStack(spacing: 10) {
                    Image(systemName: "desktopcomputer").font(.title3).frame(width: 32)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(verbatim: update.title)
                        if !update.version.isEmpty, !update.title.contains(update.version) {
                            Text(verbatim: update.version).font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    if update.restart { Chip(text: "Restart required", tinted: true) }
                    Spacer()
                    Button("Update…", action: model.openSystemSettings).controlSize(.small)
                }
            }
        } else {
            Text("Couldn't check for macOS updates.").foregroundStyle(.secondary)
        }
    }
}

private struct AppUpdateRow: View {
    let update: AppUpdate
    let action: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            AppIcon(url: update.app.url, size: 32)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(verbatim: update.app.name).lineLimit(1)
                    Chip(text: isAppStore ? "App Store" : "Developer")
                }
                Text(verbatim: "\(update.app.version) → \(update.available)")
                    .font(.caption).foregroundStyle(.secondary).monospacedDigit()
            }
            Spacer(minLength: 8)
            if !isAppStore {
                Text("Opens the app, which offers its own update.")
                    .font(.caption).foregroundStyle(.secondary)
                    .lineLimit(2).multilineTextAlignment(.trailing).frame(maxWidth: 200, alignment: .trailing)
            }
            Button("Update", action: action).controlSize(.small)
        }
        .padding(.vertical, 2)
    }

    private var isAppStore: Bool {
        if case .appStore = update.source { true } else { false }
    }
}
