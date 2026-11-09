import SwiftUI

/// One area of the Smart Sweep: a tinted icon, a headline, a few facts and the buttons that open its module.
struct SweepCard<Content: View, Actions: View>: View {
    let symbol: String
    let tint: ModuleTint
    let title: LocalizedStringKey
    let isLoading: Bool
    @ViewBuilder let content: Content
    @ViewBuilder let actions: Actions

    init(
        symbol: String, tint: ModuleTint, title: LocalizedStringKey, isLoading: Bool,
        @ViewBuilder content: () -> Content, @ViewBuilder actions: () -> Actions
    ) {
        self.symbol = symbol
        self.tint = tint
        self.title = title
        self.isLoading = isLoading
        self.content = content()
        self.actions = actions()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 9) {
                ModuleIcon(symbol: symbol, tint: tint, size: 28)
                Text(title).font(.system(size: 13.5, weight: .semibold))
                Spacer()
            }
            if isLoading {
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text("Checking…").foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, minHeight: 84, alignment: .leading)
            } else {
                VStack(alignment: .leading, spacing: 6) { content }
                    .frame(maxWidth: .infinity, minHeight: 84, alignment: .topLeading)
            }
            HStack(spacing: 8) { actions }.controlSize(.small)
        }
        .padding(18)
        .themeCard(glow: tint)
        .accessibilityElement(children: .contain)
    }
}

/// The card's big number, optionally followed by a smaller caption on the same line.
struct SweepHeadline: View {
    let text: LocalizedStringKey
    var caption: LocalizedStringKey? = nil
    var hint = false

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(text)
                .font(.system(size: 28, weight: .bold, design: .rounded))
                .foregroundStyle(hint ? AnyShapeStyle(Theme.action) : AnyShapeStyle(HierarchicalShapeStyle.primary))
                .monospacedDigit()
            if let caption {
                Text(caption).font(.callout).foregroundStyle(.secondary)
            }
        }
        .lineLimit(1)
        .minimumScaleFactor(0.7)
    }
}

/// A tinted progress bar under the headline.
struct SweepBar: View {
    let fraction: Double
    let tint: ModuleTint

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(Color.primary.opacity(0.08))
                Capsule().fill(tint.gradient).frame(width: geo.size.width * min(max(fraction, 0), 1))
            }
        }
        .frame(height: 6)
        .accessibilityHidden(true)
    }
}

struct SweepFact: View {
    let label: LocalizedStringKey
    let value: Text

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(label).foregroundStyle(.secondary)
            Spacer(minLength: 8)
            value.monospacedDigit().lineLimit(1).truncationMode(.tail)
        }
        .font(.callout)
    }
}
