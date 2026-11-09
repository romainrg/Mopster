import Foundation
import XCTest

enum TestSupport {
    /// Creates files of the given byte sizes (keys ending in `/` are folders) in a fresh temp dir.
    static func makeTree(_ spec: [String: Int]) throws -> URL {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("MopsterTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        for (path, size) in spec {
            let url = root.appendingPathComponent(path)
            if path.hasSuffix("/") {
                try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
            } else {
                try FileManager.default.createDirectory(
                    at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
                try Data(count: size).write(to: url)
            }
        }
        return root
    }

    /// Restores owner permissions on every entry (unreadable folders included), then removes the tree.
    static func destroyTree(_ root: URL) {
        func restore(_ url: URL) {
            let fm = FileManager.default
            guard let type = try? fm.attributesOfItem(atPath: url.path)[.type] as? FileAttributeType,
                type == .typeDirectory
            else { return }
            try? fm.setAttributes([.posixPermissions: 0o700], ofItemAtPath: url.path)
            for name in (try? fm.contentsOfDirectory(atPath: url.path)) ?? [] {
                restore(url.appendingPathComponent(name))
            }
        }
        restore(root)
        try? FileManager.default.removeItem(at: root)
    }

    /// `Mopster/Resources/Localizable.xcstrings`, located relative to this file.
    static let catalogURL = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()  // MopsterCoreTests
        .deletingLastPathComponent()  // Tests
        .deletingLastPathComponent()  // MopsterCore
        .deletingLastPathComponent()  // repository root
        .appendingPathComponent("Mopster/Resources/Localizable.xcstrings")
}

struct StringCatalog: Decodable {
    struct Entry: Decodable {
        struct Localization: Decodable {
            struct Unit: Decodable { let state: String; let value: String }
            struct Variant: Decodable {
                let stringUnit: Unit?
                let variations: [String: [String: Variant]]?
            }
            struct Substitution: Decodable { let variations: [String: [String: Variant]]? }
            let stringUnit: Unit?
            let variations: [String: [String: Variant]]?
            let substitutions: [String: Substitution]?

            /// Every string unit: the plain one, then those of plural variations and substitutions.
            var allUnits: [Unit] {
                func walk(_ variations: [String: [String: Variant]]?) -> [Unit] {
                    (variations ?? [:]).values.flatMap { $0.values }.flatMap { variant in
                        (variant.stringUnit.map { [$0] } ?? []) + walk(variant.variations)
                    }
                }
                return (stringUnit.map { [$0] } ?? []) + walk(variations)
                    + (substitutions ?? [:]).values.flatMap { walk($0.variations) }
            }
        }
        let localizations: [String: Localization]?
    }
    let strings: [String: Entry]

    static func load() throws -> StringCatalog {
        try JSONDecoder().decode(StringCatalog.self, from: Data(contentsOf: TestSupport.catalogURL))
    }
}

func assertCatalogContains(
    _ resources: [LocalizedStringResource], file: StaticString = #filePath, line: UInt = #line
) throws {
    let catalog = try StringCatalog.load()
    for resource in resources {
        let key = resource.key
        guard let entry = catalog.strings[key] else {
            XCTFail("Missing catalog key: \(key)", file: file, line: line)
            continue
        }
        assertTranslated(key: key, entry: entry, file: file, line: line)
    }
}

func assertTranslated(key: String, entry: StringCatalog.Entry, file: StaticString = #filePath, line: UInt = #line) {
    let units = entry.localizations?["fr"]?.allUnits ?? []
    XCTAssertFalse(units.isEmpty, "fr value for \(key)", file: file, line: line)
    for unit in units {
        XCTAssertEqual(unit.state, "translated", "fr state for \(key)", file: file, line: line)
        XCTAssertFalse(unit.value.isEmpty, "fr value for \(key)", file: file, line: line)
    }
}

extension XCTestCase {
    /// Like `TestSupport.makeTree`, and removes the tree (restoring permissions first) when the test ends.
    func makeTemporaryTree(_ spec: [String: Int]) throws -> URL {
        let root = try TestSupport.makeTree(spec)
        addTeardownBlock { TestSupport.destroyTree(root) }
        return root
    }
}
