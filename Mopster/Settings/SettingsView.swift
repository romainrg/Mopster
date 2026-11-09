import AppKit
import SwiftUI

struct SettingsView: View {
    @Environment(\.appEnvironment) private var env
    @AppStorage("hasSeenOnboarding") private var hasSeenOnboarding = false

    var body: some View {
        let store = env.ignoreList
        Form {
            Section("Ignored items") {
                if store.list.paths.isEmpty {
                    Text("Nothing is ignored.").foregroundStyle(.secondary)
                }
                ForEach(store.list.paths, id: \.self) { path in
                    HStack {
                        Text(path).lineLimit(1).truncationMode(.middle)
                        Spacer()
                        Button("Remove") { store.remove(path) }
                    }
                }
                Button("Add folder…") { pickItems(into: store) }
            }
            Section {
                Button("Show welcome screen again") { hasSeenOnboarding = false }
            }
        }
        .formStyle(.grouped)
        .frame(width: 520, height: 380)
    }

    private func pickItems(into store: IgnoreListStore) {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = true
        guard panel.runModal() == .OK else { return }
        panel.urls.forEach(store.add)
    }
}
