import Foundation
import MopsterCore

/// About fifteen plausible big files under the demo home, with varied sizes and last-opened dates.
struct DemoLargeFileFinder: LargeFileFinding {
    private static let samples: [(path: String, size: Int64, daysAgo: Int)] = [
        ("Movies/Holiday-2025.mov", 9_000_000_000, 310),
        ("Downloads/Installer-Pro-4.2.dmg", 2_100_000_000, 205),
        ("Movies/Wedding-highlights.mp4", 3_400_000_000, 140),
        ("Movies/Family-reunion.mp4", 2_100_000_000, 520),
        ("Downloads/backup-2025.zip", 1_500_000_000, 95),
        ("Downloads/ubuntu-24.04-desktop.iso", 6_200_000_000, 380),
        ("Movies/Screen Recording 2026-09-14.mov", 1_200_000_000, 55),
        ("Music/Samples/Drum-kit.zip", 900_000_000, 430),
        ("Music/Podcast-archive.mp3", 780_000_000, 260),
        ("Documents/Scans-2024.pdf", 420_000_000, 33),
        ("Documents/Thesis-final-v7.pptx", 310_000_000, 600),
        ("Projects/ml-experiments/datasets/images-train.tar.gz", 3_000_000_000, 75),
        ("Downloads/Presentation-recording.mkv", 640_000_000, 12),
        ("Documents/Archive-2019.7z", 270_000_000, 900),
        ("Desktop/Design-handoff.psd", 180_000_000, 8),
    ]

    static let sizes: [String: Int64] = Dictionary(
        uniqueKeysWithValues: samples.map { ("\(DemoData.demoHome)/\($0.path)", $0.size) })

    static func files(now: Date = .now) -> [LargeFile] {
        samples.map { sample in
            let url = URL(fileURLWithPath: "\(DemoData.demoHome)/\(sample.path)")
            return LargeFile(
                url: url, size: sample.size, lastAccess: now.addingTimeInterval(-Double(sample.daysAgo) * 86_400),
                kind: FileKind.of(extension: url.pathExtension))
        }
    }

    func find(_ query: LargeFileQuery, progress: @escaping @Sendable (ScanProgress) -> Void) async throws -> [LargeFile] {
        let now = Date.now
        progress(ScanProgress(location: DemoData.demoHome, itemsFound: Self.samples.count))
        return Self.files(now: now)
            .filter { file in
                file.size >= query.minSize && query.kinds.contains(file.kind)
                    && query.olderThan.map { now.timeIntervalSince(file.lastAccess) >= $0 } != false
            }
            .sorted { $0.size > $1.size }
    }
}
