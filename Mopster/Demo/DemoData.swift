import Foundation
import MopsterCore

/// Built-in sample data for demo mode. Module tasks add their own sample data here.
enum DemoData {
    static let demoHome = "/Users/demo"

    /// Sample junk: rule id → (path relative to the demo home, size in bytes).
    static let junkSamples: [String: [(path: String, size: Int64)]] = [
        "browserCaches": [
            ("Library/Caches/Google/Chrome/Default", 1_240_000_000),
            ("Library/Caches/com.apple.Safari/WebKitCache", 380_000_000),
        ],
        "xcodeCaches": [
            ("Library/Developer/Xcode/DerivedData/Sample-abcdefgh", 2_850_000_000),
            ("Library/Developer/CoreSimulator/Caches", 640_000_000),
        ],
        "developerCaches": [
            ("Library/Caches/Homebrew/downloads", 910_000_000),
            ("Library/Caches/pip", 220_000_000),
            (".npm/_cacache", 480_000_000),
        ],
        "crashReports": [
            ("Library/Logs/DiagnosticReports/Example_2026-10-30.ips", 1_800_000),
            ("Library/Logs/DiagnosticReports/Sample_2026-11-02.ips", 2_400_000),
        ],
        "logs": [
            ("Library/Logs/com.example.helper", 48_000_000),
            ("Library/Logs/Homebrew", 6_500_000),
        ],
        "appCaches": [
            ("Library/Caches/com.example.chat", 760_000_000),
            ("Library/Caches/com.example.player", 410_000_000),
            ("Library/Caches/com.example.editor", 135_000_000),
            ("Library/Caches/com.example.notes", 21_000_000),
        ],
        "savedAppState": [
            ("Library/Saved Application State/com.example.editor.savedState", 14_000_000),
            ("Library/Saved Application State/com.example.chat.savedState", 3_200_000),
        ],
        "installers": [
            ("Downloads/ExampleApp-2.4.dmg", 310_000_000),
            ("Downloads/SampleTool-1.0.pkg", 95_000_000),
        ],
    ]

    static let junkSkipped = ["Library/Mail/V10/MailData/Attachments"]
    static let junkTrashSize: Int64 = 1_350_000_000

    static var sizes: [String: Int64] {
        Dictionary(
            uniqueKeysWithValues: junkSamples.values.flatMap { $0 }.map { ("\(demoHome)/\($0.path)", $0.size) }
        ).merging(DemoAppInventory.sizes) { junk, _ in junk }
        .merging(DemoLargeFileFinder.sizes) { junk, _ in junk }
        .merging(DemoDuplicateFinder.sizes) { junk, _ in junk }
    }
}
