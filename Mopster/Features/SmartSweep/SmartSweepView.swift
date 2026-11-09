import MopsterCore
import SwiftUI

struct SmartSweepView: View {
    let model: SmartSweepViewModel

    @ViewBuilder var body: some View {
        switch model.phase {
        case .intro:
            FeatureIntro(
                symbol: "sparkles", title: "Smart Sweep",
                promise: "A quick look at every area of your Mac.",
                scope:
                    "Runs the quick scans in parallel and shows one card per area. Run only moves the pre-selected safe junk to the Trash; Review opens the matching tool.",
                action: model.start)
        case .sweeping, .results:
            cards
        case .removing:
            ProgressView("Moving to the Trash…").frame(maxWidth: .infinity, maxHeight: .infinity)
        case .done(let report):
            FeatureDone(report: report, onDone: model.reset)
        }
    }

    private var cards: some View {
        VStack(spacing: 0) {
            ScrollView {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 300), spacing: 16, alignment: .top)], spacing: 16) {
                    junkCard
                    protectionCard
                    performanceCard
                    updatesCard
                    largeFilesCard
                }
                .padding(20)
            }
            Divider()
            footer
        }
        .confirmationDialog(
            confirmationTitle, isPresented: Bindable(model).confirmingRun, titleVisibility: .visible
        ) {
            Button("Move to Trash", role: .destructive, action: model.run)
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("You can restore them from the Trash until you empty it.")
        }
    }

    private var confirmationTitle: LocalizedStringKey {
        "Move \(Formatting.bytes(model.junk.value?.safeBytes ?? 0)) of junk to the Trash?"
    }

    private var footer: some View {
        HStack {
            Text("Run only moves the safe junk to the Trash.")
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer()
            Button("Scan again", action: model.start).disabled(!model.isSettled)
            Button("Run", action: model.requestRun)
                .buttonStyle(.borderedProminent)
                .disabled(!model.canRun)
        }
        .padding(12)
    }

    // MARK: Cards

    private var junkCard: some View {
        SweepCard(symbol: "trash", title: "System Junk", isLoading: model.junk.isLoading) {
            model.review(.systemJunk)
        } content: {
            switch model.junk {
            case .loading: EmptyView()
            case .failed: SweepHeadline(text: "Couldn't scan")
            case .ready(let summary):
                if summary.safeURLs.isEmpty {
                    SweepHeadline(text: "Nothing to clean")
                } else {
                    SweepFact(label: "Safe to clean", value: Text(Formatting.bytes(summary.safeBytes)))
                    Text("\(summary.safeURLs.count) safe items").font(.caption).foregroundStyle(.secondary)
                }
                if summary.reviewBytes > 0 {
                    SweepFact(label: "To review yourself", value: Text(Formatting.bytes(summary.reviewBytes)))
                }
            }
        }
    }

    private var protectionCard: some View {
        SweepCard(symbol: "shield.lefthalf.filled", title: "Protection", isLoading: model.protection.isLoading) {
            model.review(.protection)
        } content: {
            switch model.protection {
            case .loading: EmptyView()
            case .failed: SweepHeadline(text: "Couldn't check")
            case .ready(let summary):
                if summary.total == 0 {
                    SweepHeadline(text: "Nothing to review")
                } else {
                    SweepHeadline(text: itemsToReview(summary.total), hint: true)
                    SweepFact(label: "Security settings", value: Text(summary.warnings, format: .number))
                    SweepFact(label: "Background items", value: Text(summary.flaggedItems, format: .number))
                }
            }
        }
    }

    private func itemsToReview(_ count: Int) -> LocalizedStringKey {
        "\(count) items to review"
    }

    private var performanceCard: some View {
        SweepCard(symbol: "gauge.with.dots.needle.67percent", title: "Performance", isLoading: model.performance.isLoading) {
            model.review(.optimization)
        } content: {
            switch model.performance {
            case .loading: EmptyView()
            case .failed: SweepHeadline(text: "Couldn't check")
            case .ready(let summary):
                SweepFact(label: "Memory pressure", value: Text(pressureName(summary.memoryPressure)))
                if let name = summary.topProcessName {
                    SweepFact(
                        label: "Busiest process",
                        value: Text(verbatim: "\(name) · \(cpuText(summary.topProcessCPU))"))
                }
                SweepFact(label: "Broken background items", value: Text(summary.brokenItems, format: .number))
            }
        }
    }

    private func cpuText(_ percent: Double) -> String {
        (percent / 100).formatted(.percent.precision(.fractionLength(1)))
    }

    private func pressureName(_ pressure: MemoryPressure) -> LocalizedStringKey {
        switch pressure {
        case .normal: "Normal"
        case .warning: "Warning"
        case .critical: "Critical"
        }
    }

    private var updatesCard: some View {
        SweepCard(symbol: "arrow.down.app", title: "Updates", isLoading: model.updates.isLoading) {
            model.review(.updater)
        } content: {
            switch model.updates {
            case .loading: EmptyView()
            case .failed: SweepHeadline(text: "Couldn't check")
            case .ready(let summary):
                if summary.total == 0 {
                    SweepHeadline(text: "Up to date")
                } else {
                    SweepHeadline(text: updatesAvailable(summary.total), hint: true)
                    SweepFact(label: "App updates", value: Text(summary.appUpdates, format: .number))
                    SweepFact(label: "macOS updates", value: Text(summary.macOSUpdates, format: .number))
                }
            }
        }
    }

    private func updatesAvailable(_ count: Int) -> LocalizedStringKey {
        "\(count) updates available"
    }

    private var largeFilesCard: some View {
        SweepCard(symbol: "doc.text.magnifyingglass", title: "Large & Old Files", isLoading: model.largeFiles.isLoading) {
            model.review(.largeFiles)
        } content: {
            switch model.largeFiles {
            case .loading: EmptyView()
            case .failed: SweepHeadline(text: "Couldn't scan")
            case .ready(let summary):
                if summary.count == 0 {
                    SweepHeadline(text: "Nothing found")
                } else {
                    SweepHeadline(text: "\(Formatting.bytes(summary.bytes)) in old, large files")
                    SweepFact(label: "Over 50 MB, not opened in a year", value: Text(summary.count, format: .number))
                }
            }
        }
    }
}
