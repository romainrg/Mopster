import AppKit
import SwiftUI

struct OnboardingView: View {
    let onContinue: () -> Void

    var body: some View {
        HStack(spacing: 0) {
            welcome.frame(width: 320)
            access
        }
        .frame(width: 780, height: 480)
    }

    private var welcome: some View {
        VStack(alignment: .leading, spacing: 14) {
            Image(nsImage: NSImage(named: "AppIcon") ?? NSApplication.shared.applicationIconImage)
                .resizable()
                .frame(width: 72, height: 72)
                .shadow(color: .black.opacity(0.35), radius: 12, y: 6)
                .accessibilityHidden(true)
            Text("Welcome to Mopster")
                .font(.system(size: 28, weight: .bold, design: .rounded))
                .fixedSize(horizontal: false, vertical: true)
            Text("Mopster finds clutter on your Mac and moves it to the Trash, so you stay in control.")
                .foregroundStyle(Color(hex: 0xCFFAFE))
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 8)
            LazyVGrid(
                columns: [GridItem(.flexible(), alignment: .leading), GridItem(.flexible(), alignment: .leading)],
                spacing: 8
            ) {
                ForEach(SidebarSection.allCases.filter { $0 != .smartSweep }) { section in
                    HStack(spacing: 6) {
                        ModuleIcon(symbol: section.symbol, tint: section.tint, size: 18)
                        Text(section.title).font(.caption).lineLimit(1).minimumScaleFactor(0.8)
                    }
                }
            }
            .accessibilityHidden(true)
        }
        .foregroundStyle(.white)
        .padding(28)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background {
            Rectangle()
                .fill(LinearGradient(stops: Theme.heroStops, startPoint: .topLeading, endPoint: .bottomTrailing))
                .overlay(alignment: .topTrailing) {
                    GlowSpot(color: Color(hex: 0xEC4899), size: 300, opacity: 0.4).offset(x: 120, y: -120)
                }
                .clipped()
        }
    }

    private var access: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("Full Disk Access").font(.system(size: 22, weight: .bold, design: .rounded))
            point(
                "lock.open", tint: .protection,
                "Full Disk Access lets Mopster see Mail downloads, Safari caches, the Trash size and some app containers.")
            point("checkmark", tint: .junk, "Mopster works without it and tells you what it skipped.")
            point(
                "arrow.triangle.2.circlepath", tint: .updater,
                "Builds signed ad hoc need the access granted again after an update or a rebuild.")
            Spacer(minLength: 8)
            HStack {
                Spacer()
                Button("Open System Settings") { SystemSettings.open(.fullDiskAccess) }
                    .buttonStyle(.soft)
                Button("Continue", action: onContinue)
                    .buttonStyle(.gradient)
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(32)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Theme.ground)
    }

    private func point(_ symbol: String, tint: ModuleTint, _ text: LocalizedStringKey) -> some View {
        HStack(alignment: .top, spacing: 12) {
            ModuleIcon(symbol: symbol, tint: tint, size: 30)
            Text(text).fixedSize(horizontal: false, vertical: true)
        }
    }
}

#Preview {
    OnboardingView(onContinue: {})
}
