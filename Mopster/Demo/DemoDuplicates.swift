import Foundation
import MopsterCore

/// Five plausible duplicate groups under the demo home.
struct DemoDuplicateFinder: DuplicateFinding {
    private static let samples: [(id: String, size: Int64, copies: [(path: String, daysAgo: Int)])] = [
        ("c0de01", 310_000_000, [("Movies/Wedding-clip.mp4", 400), ("Downloads/Wedding-clip.mp4", 120)]),
        ("c0de02", 48_000_000, [("Documents/Project-assets.zip", 210), ("Downloads/Project-assets.zip", 60)]),
        (
            "c0de03", 4_200_000,
            [
                ("Pictures/Holiday/IMG_2041.jpg", 330), ("Desktop/IMG_2041.jpg", 90),
                ("Downloads/IMG_2041.jpg", 14),
            ]
        ),
        ("c0de04", 3_100_000, [("Pictures/IMG_1187.heic", 500), ("Documents/Scans/IMG_1187.heic", 45)]),
        ("c0de05", 2_800_000, [("Documents/Contract-2026.pdf", 150), ("Downloads/Contract-2026 (1).pdf", 20)]),
    ]

    static let sizes: [String: Int64] = Dictionary(
        samples.flatMap { sample in
            sample.copies.map { ("\(DemoData.demoHome)/\($0.path)", sample.size) }
        }, uniquingKeysWith: { first, _ in first })

    static func groups(now: Date = .now) -> [DuplicateGroup] {
        samples.map { sample in
            DuplicateGroup(
                id: sample.id, size: sample.size,
                files: sample.copies.map {
                    DuplicateFile(
                        url: URL(fileURLWithPath: "\(DemoData.demoHome)/\($0.path)"),
                        created: now.addingTimeInterval(-Double($0.daysAgo) * 86_400))
                })
        }
    }

    func scan(
        in folders: [URL], minSize: Int64, progress: @escaping @Sendable (ScanProgress) -> Void
    ) async throws -> DuplicateScan {
        progress(ScanProgress(location: DuplicateStage.hashing.rawValue, fraction: 0.5, itemsFound: 0))
        return DuplicateScan(
            groups: Self.groups().filter { $0.size >= minSize }.sorted { $0.wastedSpace > $1.wastedSpace })
    }
}
