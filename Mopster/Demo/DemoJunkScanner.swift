import Foundation
import MopsterCore

/// Plausible junk groups built from the catalog, after a short simulated scan.
struct DemoJunkScanner: JunkScanning {
    func scan(progress: @escaping @Sendable (ScanProgress) -> Void) async throws -> JunkScanResult {
        let rules = JunkCatalog.rules
        for (index, rule) in rules.enumerated() {
            progress(
                ScanProgress(
                    location: rule.locations.first, fraction: Double(index) / Double(rules.count),
                    itemsFound: rules[..<index].flatMap(Self.group(for:)).reduce(0) { $0 + $1.items.count }))
            try await Task.sleep(for: .milliseconds(80))
        }
        return Self.result(rules: rules)
    }

    static func result(rules: [JunkRule] = JunkCatalog.rules) -> JunkScanResult {
        JunkScanResult(
            groups: rules.flatMap(group(for:)),
            skipped: DemoData.junkSkipped.map { URL(fileURLWithPath: "\(DemoData.demoHome)/\($0)") },
            trashSize: DemoData.junkTrashSize)
    }

    private static func group(for rule: JunkRule) -> [CleanupGroup] {
        guard let samples = DemoData.junkSamples[rule.id] else { return [] }
        let items = samples.map { sample in
            let url = URL(fileURLWithPath: "\(DemoData.demoHome)/\(sample.path)")
            return CleanupItem(
                url: url, name: url.lastPathComponent,
                detail: "~/" + url.deletingLastPathComponent().path.dropFirst(DemoData.demoHome.count + 1),
                size: sample.size, risk: rule.risk, isSelectedByDefault: rule.risk == .safe)
        }.sorted { $0.size > $1.size }
        return [
            CleanupGroup(
                id: rule.id, title: rule.title, explanation: rule.explanation, symbol: rule.symbol,
                risk: rule.risk, items: items)
        ]
    }
}
