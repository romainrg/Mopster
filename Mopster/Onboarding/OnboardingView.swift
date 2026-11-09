import SwiftUI

struct OnboardingView: View {
    let onContinue: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Welcome to Mopster")
                .font(.largeTitle.bold())
            Text("Mopster finds clutter on your Mac and moves it to the Trash, so you stay in control.")
            VStack(alignment: .leading, spacing: 8) {
                Label("Full Disk Access lets Mopster see Mail downloads, Safari caches, the Trash size and some app containers.", systemImage: "lock.open")
                Label("Mopster works without it and tells you what it skipped.", systemImage: "checkmark.circle")
                Label("Builds signed ad hoc need the access granted again after an update or a rebuild.", systemImage: "arrow.triangle.2.circlepath")
            }
            HStack {
                Spacer()
                Button("Open System Settings") { SystemSettings.open(.fullDiskAccess) }
                Button("Continue", action: onContinue)
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(28)
        .frame(width: 520)
    }
}

#Preview {
    OnboardingView(onContinue: {})
}
