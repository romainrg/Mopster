import SwiftUI

/// One area of the Smart Sweep: a headline, a few facts and a Review button that opens its module.
struct SweepCard<Content: View>: View {
    let symbol: String
    let title: LocalizedStringKey
    let isLoading: Bool
    let onReview: () -> Void
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: symbol).foregroundStyle(.tint).frame(width: 22)
                Text(title).font(.headline)
                Spacer()
            }
            if isLoading {
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text("Checking…").foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, minHeight: 76, alignment: .leading)
            } else {
                VStack(alignment: .leading, spacing: 6) { content }
                    .frame(maxWidth: .infinity, minHeight: 76, alignment: .topLeading)
            }
            HStack {
                Spacer()
                Button("Review…", action: onReview).controlSize(.small)
            }
        }
        .padding(16)
        .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 12))
        .accessibilityElement(children: .contain)
    }
}

struct SweepHeadline: View {
    let text: LocalizedStringKey
    var hint = false

    var body: some View {
        HStack(spacing: 6) {
            if hint { Circle().fill(.orange).frame(width: 8, height: 8) }
            Text(text).font(.title3.weight(.semibold))
        }
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
