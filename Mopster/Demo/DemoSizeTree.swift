import Foundation
import MopsterCore

/// A plausible home folder for demo mode and screenshots, built instantly.
struct DemoSizeTree: SizeTreeBuilding {
    static let root = URL(fileURLWithPath: DemoData.demoHome, isDirectory: true)

    func build(root: URL, progress: @escaping @Sendable (ScanProgress) -> Void) async throws -> SizeTreeResult {
        progress(ScanProgress(location: Self.root.path, itemsFound: 60))
        return SizeTreeResult(root: Self.tree(), skipped: [])
    }

    static func tree() -> SizeNode {
        let mb: Int64 = 1_000_000
        let gb: Int64 = 1_000_000_000
        func file(_ parent: URL, _ name: String, _ size: Int64) -> SizeNode {
            SizeNode(url: parent.appendingPathComponent(name), name: name, isDirectory: false, size: size)
        }
        func other(_ parent: URL, _ size: Int64) -> SizeNode {
            SizeNode(url: parent, name: SizeNode.otherFilesName, isDirectory: false, isAggregate: true, size: size)
        }
        func folder(_ parent: URL, _ name: String, _ build: (URL) -> [SizeNode]) -> SizeNode {
            let url = parent.appendingPathComponent(name, isDirectory: true)
            let children = build(url).sorted { $0.size > $1.size }
            return SizeNode(
                url: url, name: name, isDirectory: true, size: children.reduce(0) { $0 + $1.size }, children: children)
        }

        return folder(root.deletingLastPathComponent(), "demo") { home in
            [
                folder(home, "Movies") { dir in
                    [
                        file(dir, "Holiday-2025.mov", 9 * gb), file(dir, "Wedding-highlights.mp4", 3 * gb + 400 * mb),
                        file(dir, "Screen Recording 2026-09-14.mov", 1 * gb + 200 * mb),
                        file(dir, "Family-reunion.mp4", 2 * gb + 100 * mb), other(dir, 600 * mb),
                    ]
                },
                folder(home, "Music") { dir in
                    [
                        folder(dir, "Samples") { sub in
                            [file(sub, "Drum-kit.zip", 900 * mb), file(sub, "Strings.wav", 420 * mb), other(sub, 240 * mb)]
                        },
                        file(dir, "Podcast-archive.mp3", 780 * mb), file(dir, "Mixtape-2024.m4a", 310 * mb),
                        other(dir, 1 * gb + 50 * mb),
                    ]
                },
                folder(home, "Projects") { dir in
                    [
                        folder(dir, "pixel-studio") { project in
                            [
                                folder(project, "node_modules") { sub in
                                    [file(sub, "electron.zip", 210 * mb), other(sub, 1 * gb + 150 * mb)]
                                },
                                folder(project, "build") { sub in
                                    [file(sub, "PixelStudio.app", 640 * mb), other(sub, 180 * mb)]
                                },
                                folder(project, "assets") { sub in
                                    [file(sub, "hero.psd", 480 * mb), file(sub, "icons.png", 36 * mb), other(sub, 90 * mb)]
                                },
                                folder(project, "src") { sub in [file(sub, "main.swift", 2 * mb), other(sub, 28 * mb)] },
                            ]
                        },
                        folder(dir, "ml-experiments") { project in
                            [
                                folder(project, "datasets") { sub in
                                    [file(sub, "images-train.tar.gz", 3 * gb), file(sub, "labels.csv", 140 * mb), other(sub, 800 * mb)]
                                },
                                folder(project, "checkpoints") { sub in
                                    [file(sub, "model-v3.bin", 1 * gb + 300 * mb), file(sub, "model-v2.bin", 1 * gb + 200 * mb), other(sub, 400 * mb)]
                                },
                            ]
                        },
                        folder(dir, "website") { project in
                            [
                                folder(project, "node_modules") { sub in [other(sub, 640 * mb)] },
                                folder(project, "public") { sub in [file(sub, "intro.mp4", 120 * mb), other(sub, 60 * mb)] },
                            ]
                        },
                        folder(dir, "sandbox") { project in [other(project, 210 * mb)] },
                    ]
                },
                folder(home, "Library") { dir in
                    [
                        folder(dir, "Caches") { sub in [file(sub, "com.example.render.cache", 1 * gb + 800 * mb), other(sub, 2 * gb)] },
                        folder(dir, "Application Support") { sub in [other(sub, 3 * gb + 200 * mb)] },
                        folder(dir, "Developer") { sub in [other(sub, 4 * gb + 600 * mb)] },
                    ]
                },
                folder(home, "Downloads") { dir in
                    [
                        file(dir, "Installer-Pro-4.2.dmg", 2 * gb + 100 * mb), file(dir, "backup-2025.zip", 1 * gb + 500 * mb),
                        file(dir, "Quarterly-report.pdf", 38 * mb), other(dir, 700 * mb),
                    ]
                },
                folder(home, "Documents") { dir in [other(dir, 1 * gb + 300 * mb), file(dir, "Scans-2024.pdf", 420 * mb)] },
                folder(home, "Pictures") { dir in
                    [file(dir, "Photos Library.photoslibrary", 6 * gb), file(dir, "Wallpaper.heic", 24 * mb), other(dir, 500 * mb)]
                },
                other(home, 900 * mb),
            ]
        }
    }
}
