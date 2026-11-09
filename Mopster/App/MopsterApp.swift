import SwiftUI

@main
struct MopsterApp: App {
    @State private var environment = AppEnvironment.current()
    @State private var fullDiskAccess: FullDiskAccess

    init() {
        let isDemo = CommandLine.arguments.contains("--demo")
        _fullDiskAccess = State(initialValue: FullDiskAccess(isDemo: isDemo))
    }

    var body: some Scene {
        Window("Mopster", id: "main") {
            ContentView()
                .frame(minWidth: 980, minHeight: 640)
                .environment(\.appEnvironment, environment)
                .environment(fullDiskAccess)
        }
        .windowResizability(.contentMinSize)

        Settings {
            SettingsView()
                .environment(\.appEnvironment, environment)
        }
    }
}
