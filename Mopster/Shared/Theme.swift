import AppKit
import SwiftUI

/// Mopster's visual theme: a soft polychrome ground, one gradient tint per module,
/// a dark hero band and a warm call-to-action gradient. Every color adapts to dark mode.
enum Theme {
    /// Window ground: lavender → mint → peach in light mode, night → deep teal → plum in dark mode.
    static let ground = LinearGradient(
        colors: [
            .dynamic(light: Color(hex: 0xEEF2FF), dark: Color(hex: 0x10152A)),
            .dynamic(light: Color(hex: 0xF2FBF9), dark: Color(hex: 0x0C1D21)),
            .dynamic(light: Color(hex: 0xFFF4EC), dark: Color(hex: 0x1D1519)),
        ],
        startPoint: .topLeading, endPoint: .bottomTrailing)

    /// Hero band: night blue → teal, with the health ring and the headline on top.
    static let heroStops: [Gradient.Stop] = [
        .init(color: Color(hex: 0x0F172A), location: 0),
        .init(color: Color(hex: 0x1E3A8A), location: 0.35),
        .init(color: Color(hex: 0x0E7490), location: 0.7),
        .init(color: Color(hex: 0x14B8A6), location: 1),
    ]
    static let hero = LinearGradient(stops: heroStops, startPoint: .leading, endPoint: .trailing)

    /// Primary action: orange → pink, the one gradient no module uses.
    static let action = LinearGradient(
        colors: [Color(hex: 0xF97316), Color(hex: 0xEC4899)], startPoint: .topLeading, endPoint: .bottomTrailing)

    /// Health ring: teal → violet → pink.
    static let health = AngularGradient(
        colors: [Color(hex: 0x5EEAD4), Color(hex: 0xA78BFA), Color(hex: 0xF472B6), Color(hex: 0x5EEAD4)],
        center: .center, startAngle: .degrees(-90), endAngle: .degrees(270))

    static let cardFill = Color.dynamic(light: .white.opacity(0.78), dark: .white.opacity(0.06))
    static let cardStroke = Color.dynamic(light: .white.opacity(0.9), dark: .white.opacity(0.1))
    static let cardShadow = Color.dynamic(light: Color(hex: 0x1F2937).opacity(0.06), dark: .black.opacity(0.3))
    static let cardRadius: CGFloat = 18

    static let softFill = Color.dynamic(light: .white.opacity(0.8), dark: .white.opacity(0.08))
    static let softStroke = Color.dynamic(light: Color(hex: 0x1B1F2A).opacity(0.14), dark: .white.opacity(0.16))
}

/// One gradient per module, used on the sidebar icon, the card icon and the card's glow.
struct ModuleTint: Hashable {
    let start: Color
    let end: Color

    var gradient: LinearGradient {
        LinearGradient(colors: [start, end], startPoint: .topLeading, endPoint: .bottomTrailing)
    }

    static let sweep = ModuleTint(start: Color(hex: 0x14B8A6), end: Color(hex: 0x6366F1))
    static let junk = ModuleTint(start: Color(hex: 0x2DD4BF), end: Color(hex: 0x0D9488))
    static let protection = ModuleTint(start: Color(hex: 0x60A5FA), end: Color(hex: 0x2563EB))
    static let optimization = ModuleTint(start: Color(hex: 0xA78BFA), end: Color(hex: 0x7C3AED))
    static let maintenance = ModuleTint(start: Color(hex: 0xC084FC), end: Color(hex: 0x9333EA))
    static let uninstaller = ModuleTint(start: Color(hex: 0xFB7185), end: Color(hex: 0xE11D48))
    static let updater = ModuleTint(start: Color(hex: 0xFBBF24), end: Color(hex: 0xF97316))
    static let telescope = ModuleTint(start: Color(hex: 0x38BDF8), end: Color(hex: 0x0284C7))
    static let largeFiles = ModuleTint(start: Color(hex: 0x818CF8), end: Color(hex: 0x4F46E5))
    static let duplicates = ModuleTint(start: Color(hex: 0xF472B6), end: Color(hex: 0xDB2777))
}

// MARK: - Shapes and surfaces

/// A rounded gradient square holding a white SF Symbol.
struct ModuleIcon: View {
    let symbol: String
    let tint: ModuleTint
    var size: CGFloat = 22

    var body: some View {
        Image(systemName: symbol)
            .font(.system(size: size * 0.55, weight: .semibold))
            .foregroundStyle(.white)
            .frame(width: size, height: size)
            .background(tint.gradient, in: RoundedRectangle(cornerRadius: size * 0.28, style: .continuous))
            .accessibilityHidden(true)
    }
}

/// A soft colored light: a radial gradient, so it renders the same on screen and offscreen.
struct GlowSpot: View {
    let color: Color
    var size: CGFloat = 220
    var opacity: Double = 0.45

    var body: some View {
        Circle()
            .fill(
                RadialGradient(
                    colors: [color.opacity(opacity), color.opacity(0)], center: .center, startRadius: 0,
                    endRadius: size / 2)
            )
            .frame(width: size, height: size)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }
}

/// Translucent card with a soft shadow and, optionally, a tinted glow in its top-right corner.
struct ThemeCard: ViewModifier {
    var glow: ModuleTint?

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous)
        content
            .clipShape(shape)
            .background {
                shape.fill(Theme.cardFill)
                    .overlay(alignment: .topTrailing) {
                        if let glow { GlowSpot(color: glow.start).offset(x: 70, y: -70) }
                    }
                    .clipShape(shape)
                    .shadow(color: Theme.cardShadow, radius: 16, y: 8)
            }
            .overlay(shape.strokeBorder(Theme.cardStroke))
    }
}

extension View {
    func themeCard(glow: ModuleTint? = nil) -> some View { modifier(ThemeCard(glow: glow)) }

    /// A list or table shown as a card on the window ground.
    func themePanel() -> some View {
        scrollContentBackground(.hidden)
            .themeCard()
            .padding(.horizontal, 24)
    }
}

/// The dark hero band behind Smart Sweep's health ring, with two colored lights clipped to it.
struct HeroBackground: View {
    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 22, style: .continuous)
        shape.fill(Theme.hero)
            .overlay(alignment: .topTrailing) {
                GlowSpot(color: Color(hex: 0xEC4899), size: 380, opacity: 0.5).offset(x: 90, y: -150)
            }
            .overlay(alignment: .bottomLeading) {
                GlowSpot(color: Color(hex: 0xA78BFA), size: 320, opacity: 0.45).offset(x: 280, y: 160)
            }
            .clipShape(shape)
            .shadow(color: Color(hex: 0x1E3A8A).opacity(0.25), radius: 24, y: 14)
    }
}

// MARK: - Module chrome

/// The title row of a module screen: tinted icon, title, a summary line and the screen's actions.
struct ModuleHeader<Actions: View>: View {
    let section: SidebarSection
    var subtitle: Text?
    @ViewBuilder var actions: Actions

    init(_ section: SidebarSection, subtitle: Text? = nil, @ViewBuilder actions: () -> Actions = { EmptyView() }) {
        self.section = section
        self.subtitle = subtitle
        self.actions = actions()
    }

    var body: some View {
        HStack(spacing: 12) {
            ModuleIcon(symbol: section.symbol, tint: section.tint, size: 36)
                .shadow(color: section.tint.end.opacity(0.3), radius: 6, y: 3)
            VStack(alignment: .leading, spacing: 2) {
                Text(section.title).font(.system(size: 22, weight: .bold, design: .rounded))
                if let subtitle {
                    subtitle.font(.callout).foregroundStyle(.secondary).monospacedDigit().lineLimit(1)
                }
            }
            Spacer(minLength: 12)
            HStack(spacing: 8) { actions }
        }
        .padding(.horizontal, 24)
        .padding(.top, 18)
        .padding(.bottom, 14)
    }
}

/// The bottom row of a module screen: a status on the left, the actions on the right.
struct ModuleFooter<Status: View, Actions: View>: View {
    @ViewBuilder var status: Status
    @ViewBuilder var actions: Actions

    var body: some View {
        HStack(spacing: 10) {
            status
            Spacer(minLength: 12)
            actions
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 14)
    }
}

// MARK: - Buttons

/// Filled gradient button for the one primary action of a screen. `.controlSize(.small)` makes it compact.
struct GradientButtonStyle: ButtonStyle {
    var fill: LinearGradient = Theme.action
    var shadow: Color = Color(hex: 0xEC4899)

    func makeBody(configuration: Configuration) -> some View {
        GradientButton(configuration: configuration, fill: fill, shadow: shadow)
    }
}

private struct GradientButton: View {
    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.controlSize) private var controlSize
    let configuration: ButtonStyleConfiguration
    let fill: LinearGradient
    let shadow: Color

    var body: some View {
        let compact = controlSize == .small || controlSize == .mini
        let shape = RoundedRectangle(cornerRadius: compact ? 9 : 10, style: .continuous)
        configuration.label
            .font(.system(size: compact ? 12 : 13, weight: .semibold))
            .foregroundStyle(.white)
            .lineLimit(1)
            .padding(.horizontal, compact ? 12 : 16)
            .frame(height: compact ? 30 : 34)
            .background(fill, in: shape)
            .saturation(isEnabled ? 1 : 0.35)
            .opacity(isEnabled ? (configuration.isPressed ? 0.85 : 1) : 0.5)
            .shadow(color: shadow.opacity(isEnabled ? 0.28 : 0), radius: 8, y: 4)
            .contentShape(shape)
    }
}

/// Secondary button: translucent, bordered. `.controlSize(.small)` makes it compact.
struct SoftButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        SoftButton(configuration: configuration)
    }
}

private struct SoftButton: View {
    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.controlSize) private var controlSize
    let configuration: ButtonStyleConfiguration

    var body: some View {
        let compact = controlSize == .small || controlSize == .mini
        let shape = RoundedRectangle(cornerRadius: compact ? 9 : 10, style: .continuous)
        configuration.label
            .font(.system(size: compact ? 12 : 13, weight: .semibold))
            .foregroundStyle(.primary)
            .lineLimit(1)
            .padding(.horizontal, compact ? 12 : 16)
            .frame(height: compact ? 30 : 34)
            .background(Theme.softFill, in: shape)
            .overlay(shape.strokeBorder(Theme.softStroke))
            .opacity(isEnabled ? (configuration.isPressed ? 0.7 : 1) : 0.45)
            .contentShape(shape)
    }
}

extension ButtonStyle where Self == GradientButtonStyle {
    static var gradient: GradientButtonStyle { GradientButtonStyle() }
    static func gradient(_ tint: ModuleTint) -> GradientButtonStyle {
        GradientButtonStyle(fill: tint.gradient, shadow: tint.end)
    }
}

extension ButtonStyle where Self == SoftButtonStyle {
    static var soft: SoftButtonStyle { SoftButtonStyle() }
}

// MARK: - Colors

extension Color {
    init(hex: UInt32) {
        self.init(
            red: Double((hex >> 16) & 0xFF) / 255, green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255)
    }

    /// A color that follows the window's appearance.
    static func dynamic(light: Color, dark: Color) -> Color {
        let light = NSColor(light)
        let dark = NSColor(dark)
        return Color(
            nsColor: NSColor(name: nil) { appearance in
                appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua ? dark : light
            })
    }
}
