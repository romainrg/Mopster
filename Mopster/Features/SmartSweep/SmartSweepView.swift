import MopsterCore
import SwiftUI

struct SmartSweepView: View {
    let model: SmartSweepViewModel

    @ViewBuilder var body: some View {
        switch model.phase {
        case .intro:
            FeatureIntro(
                symbol: "sparkles", tint: .sweep, title: "Smart Sweep",
                promise: "A quick look at every area of your Mac.",
                scope:
                    "Runs the quick scans in parallel and shows one card per area. Run only moves the pre-selected safe junk to the Trash; Review opens the matching tool.",
                action: model.start)
        case .sweeping, .results:
            dashboard
        case .removing:
            ProgressView("Moving to the Trash…").frame(maxWidth: .infinity, maxHeight: .infinity)
        case .done(let report):
            FeatureDone(report: report, onDone: model.reset)
        }
    }

    private var dashboard: some View {
        VStack(spacing: 0) {
            header
            ScrollView {
                VStack(spacing: 16) {
                    hero
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 280), spacing: 14, alignment: .top)], spacing: 14) {
                        junkCard
                        protectionCard
                        performanceCard
                        updatesCard
                        largeFilesCard
                    }
                    Text("Run only moves the safe junk to the Trash.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 24)
            }
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

    // MARK: Header and hero

    private var header: some View {
        ModuleHeader(.smartSweep, subtitle: Text("A quick scan of every area of your Mac.")) {
            Button("Scan again", action: model.start).buttonStyle(.soft).disabled(!model.isSettled)
            Button(runTitle, action: model.requestRun).buttonStyle(.gradient).disabled(!model.canRun)
        }
    }

    private var runTitle: LocalizedStringKey {
        if let bytes = model.junk.value?.safeBytes, bytes > 0 {
            "Run cleanup · \(Formatting.bytes(bytes))"
        } else {
            "Run cleanup"
        }
    }

    private var hero: some View {
        HStack(spacing: 28) {
            HealthRing(score: model.isSettled ? health.score : nil)
            VStack(alignment: .leading, spacing: 6) {
                Text(model.isSettled ? health.title : "Checking your Mac…")
                    .font(.system(size: 26, weight: .bold, design: .rounded))
                Text(model.isSettled ? health.detail : "Every area is being scanned in parallel; results appear as they come in.")
                    .font(.callout)
                    .foregroundStyle(Color(hex: 0xCFFAFE))
                    .lineLimit(3)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            vitals
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 28)
        .padding(.vertical, 24)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(HeroBackground())
        .accessibilityElement(children: .combine)
    }

    /// Disk, memory and Trash at a glance, on the right of the hero.
    @ViewBuilder private var vitals: some View {
        let disk = model.disk
        let pressure = model.performance.value?.memoryPressure
        let trash = model.junk.value?.trashBytes
        if disk != nil || pressure != nil || trash != nil {
            VStack(alignment: .leading, spacing: 10) {
                if let disk {
                    vital("Disk", value: Text(verbatim: "\(Formatting.bytes(disk.used)) / \(Formatting.bytes(disk.total))"))
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            Capsule().fill(.white.opacity(0.15))
                            Capsule()
                                .fill(LinearGradient(colors: [Color(hex: 0x5EEAD4), Color(hex: 0xFBBF24), Color(hex: 0xF97316)], startPoint: .leading, endPoint: .trailing))
                                .frame(width: geo.size.width * min(max(disk.usedFraction, 0), 1))
                        }
                    }
                    .frame(height: 6)
                    .accessibilityHidden(true)
                }
                if let pressure { vital("Memory", value: Text(pressureName(pressure))) }
                if let trash { vital("Trash", value: Text(Formatting.bytes(trash))) }
            }
            .frame(width: 200)
            .padding(.leading, 24)
            .overlay(alignment: .leading) { Rectangle().fill(.white.opacity(0.18)).frame(width: 1) }
        }
    }

    private func vital(_ label: LocalizedStringKey, value: Text) -> some View {
        HStack {
            Text(label).foregroundStyle(Color(hex: 0xCFFAFE))
            Spacer(minLength: 8)
            value.fontWeight(.semibold).monospacedDigit().lineLimit(1)
        }
        .font(.callout)
    }

    private var health: HealthSummary {
        HealthSummary(
            junk: model.junk.value, protection: model.protection.value, performance: model.performance.value,
            updates: model.updates.value, disk: model.disk)
    }

    // MARK: Cards

    private var junkCard: some View {
        SweepCard(symbol: "trash", tint: .junk, title: "System Junk", isLoading: model.junk.isLoading) {
            switch model.junk {
            case .loading: EmptyView()
            case .failed: SweepHeadline(text: "Couldn't scan")
            case .ready(let summary):
                if summary.safeURLs.isEmpty {
                    SweepHeadline(text: "Nothing to clean")
                } else {
                    SweepHeadline(
                        text: "\(Formatting.bytes(summary.safeBytes))", caption: safeItems(summary.safeURLs.count))
                    SweepBar(fraction: Self.share(summary.safeBytes, of: summary.safeBytes + summary.reviewBytes), tint: .junk)
                }
                if summary.reviewBytes > 0 {
                    SweepFact(label: "To review yourself", value: Text(Formatting.bytes(summary.reviewBytes)))
                }
            }
        } actions: {
            Button("Run", action: model.requestRun).buttonStyle(.gradient(.junk)).disabled(!model.canRun)
            Button("Review…") { model.review(.systemJunk) }.buttonStyle(.soft)
        }
    }

    private func safeItems(_ count: Int) -> LocalizedStringKey {
        "safe · \(count) items"
    }

    private static func share(_ part: Int64, of total: Int64) -> Double {
        total > 0 ? Double(part) / Double(total) : 0
    }

    private var protectionCard: some View {
        SweepCard(
            symbol: "shield.lefthalf.filled", tint: .protection, title: "Protection", isLoading: model.protection.isLoading
        ) {
            switch model.protection {
            case .loading: EmptyView()
            case .failed: SweepHeadline(text: "Couldn't check")
            case .ready(let summary):
                if summary.total == 0 {
                    SweepHeadline(text: "Nothing to review")
                } else {
                    SweepHeadline(text: "\(summary.total)", caption: "to review", hint: true)
                    SweepFact(label: "Security settings", value: Text(summary.warnings, format: .number))
                    SweepFact(label: "Background items", value: Text(summary.flaggedItems, format: .number))
                }
            }
        } actions: {
            Button("Review…") { model.review(.protection) }.buttonStyle(.soft)
        }
    }

    private var performanceCard: some View {
        SweepCard(
            symbol: "gauge.with.dots.needle.67percent", tint: .optimization, title: "Performance",
            isLoading: model.performance.isLoading
        ) {
            switch model.performance {
            case .loading: EmptyView()
            case .failed: SweepHeadline(text: "Couldn't check")
            case .ready(let summary):
                if let name = summary.topProcessName {
                    SweepHeadline(text: "\(cpuText(summary.topProcessCPU))", caption: "\(name)")
                    SweepBar(fraction: summary.topProcessCPU / 100, tint: .optimization)
                } else {
                    SweepHeadline(text: pressureName(summary.memoryPressure))
                }
                SweepFact(label: "Memory pressure", value: Text(pressureName(summary.memoryPressure)))
                SweepFact(label: "Broken background items", value: Text(summary.brokenItems, format: .number))
            }
        } actions: {
            Button("Review…") { model.review(.optimization) }.buttonStyle(.soft)
        }
    }

    private func cpuText(_ percent: Double) -> String {
        (percent / 100).formatted(.percent.precision(.fractionLength(0)))
    }

    private func pressureName(_ pressure: MemoryPressure) -> LocalizedStringKey {
        switch pressure {
        case .normal: "Normal"
        case .warning: "Warning"
        case .critical: "Critical"
        }
    }

    private var updatesCard: some View {
        SweepCard(symbol: "arrow.down.app", tint: .updater, title: "Updates", isLoading: model.updates.isLoading) {
            switch model.updates {
            case .loading: EmptyView()
            case .failed: SweepHeadline(text: "Couldn't check")
            case .ready(let summary):
                if summary.total == 0 {
                    SweepHeadline(text: "Up to date")
                } else {
                    SweepHeadline(text: "\(summary.total)", caption: "available", hint: true)
                    SweepFact(label: "App updates", value: Text(summary.appUpdates, format: .number))
                    SweepFact(label: "macOS updates", value: Text(summary.macOSUpdates, format: .number))
                }
            }
        } actions: {
            Button("Review…") { model.review(.updater) }.buttonStyle(.soft)
        }
    }

    private var largeFilesCard: some View {
        SweepCard(
            symbol: "doc.text.magnifyingglass", tint: .largeFiles, title: "Large & Old Files",
            isLoading: model.largeFiles.isLoading
        ) {
            switch model.largeFiles {
            case .loading: EmptyView()
            case .failed: SweepHeadline(text: "Couldn't scan")
            case .ready(let summary):
                if summary.count == 0 {
                    SweepHeadline(text: "Nothing found")
                } else {
                    SweepHeadline(text: "\(Formatting.bytes(summary.bytes))", caption: "in old, large files")
                    SweepBar(fraction: 1, tint: .largeFiles)
                    SweepFact(label: "Over 50 MB, not opened in a year", value: Text(summary.count, format: .number))
                }
            }
        } actions: {
            Button("Review…") { model.review(.largeFiles) }.buttonStyle(.soft)
        }
    }
}

/// The hero's score, headline and one-line explanation, from the cards that are ready.
struct HealthSummary {
    let score: Int
    let title: LocalizedStringKey
    let detail: LocalizedStringKey

    init(
        junk: JunkSummary?, protection: ProtectionSummary?, performance: PerformanceSummary?,
        updates: UpdatesSummary?, disk: VolumeCapacity?
    ) {
        let health = HealthScore(
            safeJunkBytes: junk?.safeBytes, securityWarnings: protection?.warnings,
            flaggedItems: protection?.flaggedItems, memoryPressure: performance?.memoryPressure,
            brokenItems: performance?.brokenItems, pendingUpdates: updates?.total,
            diskUsedFraction: disk?.usedFraction)
        score = health.value
        switch health.level {
        case .good: title = "Your Mac is in good shape"
        case .fair: title = "Your Mac could use a cleanup"
        case .poor: title = "Your Mac needs some attention"
        }

        let safe = junk.map { Formatting.bytes($0.safeBytes) } ?? Formatting.bytes(0)
        let toReview = protection?.total ?? 0
        let pending = updates?.total ?? 0
        detail = "\(safe) of safe junk can go to the Trash. \(toReview) protection items and \(pending) updates deserve a look."
    }
}

/// The gradient ring of the hero; `nil` shows an indeterminate ring while the sweep runs.
struct HealthRing: View {
    let score: Int?

    var body: some View {
        ZStack {
            Circle().stroke(Color.white.opacity(0.14), lineWidth: 12)
            Circle()
                .trim(from: 0, to: score.map { Double($0) / 100 } ?? 0.25)
                .stroke(Theme.health, style: StrokeStyle(lineWidth: 12, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .shadow(color: Color(hex: 0xA78BFA).opacity(0.7), radius: 8)
                .animation(.easeOut(duration: 0.8), value: score)
            VStack(spacing: 2) {
                if let score {
                    Text(score, format: .number)
                        .font(.system(size: 40, weight: .bold, design: .rounded))
                        .monospacedDigit()
                } else {
                    ProgressView().tint(.white)
                }
                Text("Health")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Color(hex: 0xA5F3FC))
                    .textCase(.uppercase)
            }
        }
        .frame(width: 136, height: 136)
        .accessibilityLabel(score.map { Text("Health score \($0) out of 100") } ?? Text("Checking…"))
    }
}
