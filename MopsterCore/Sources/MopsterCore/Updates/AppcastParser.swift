import Foundation

public struct AppcastItem: Sendable, Equatable {
    public let version: String
    public let shortVersion: String?
    public let minimumSystemVersion: String?
    public let channel: String?

    public init(version: String, shortVersion: String?, minimumSystemVersion: String?, channel: String?) {
        self.version = version
        self.shortVersion = shortVersion
        self.minimumSystemVersion = minimumSystemVersion
        self.channel = channel
    }
}

public enum AppcastParser {
    /// Items of a Sparkle appcast, or nil when the data is not an RSS feed. Items without a version are skipped.
    public static func parse(_ data: Data) -> [AppcastItem]? {
        let parser = XMLParser(data: data)
        let reader = AppcastReader()
        parser.delegate = reader
        parser.shouldProcessNamespaces = false
        parser.shouldResolveExternalEntities = false
        guard parser.parse(), reader.sawFeed else { return nil }
        return reader.items
    }

    /// The highest-versioned item that is on the stable channel and runs on `osVersion`.
    public static func newestCompatible(_ items: [AppcastItem], osVersion: OperatingSystemVersion) -> AppcastItem? {
        let os = AppVersion("\(osVersion.majorVersion).\(osVersion.minorVersion).\(osVersion.patchVersion)")
        return
            items
            .filter { $0.channel == nil && ($0.minimumSystemVersion.map { AppVersion($0) <= os } ?? true) }
            .max { AppVersion($0.version) < AppVersion($1.version) }
    }
}

private final class AppcastReader: NSObject, XMLParserDelegate {
    var items: [AppcastItem] = []
    var sawFeed = false

    private var inItem = false
    private var text = ""
    private var version: String?
    private var shortVersion: String?
    private var minimumSystemVersion: String?
    private var channel: String?

    /// `sparkle:version` -> `version`, whatever the prefix; unprefixed names are not Sparkle's.
    private func sparkleName(_ qualified: String) -> String? {
        guard let colon = qualified.firstIndex(of: ":") else { return nil }
        return String(qualified[qualified.index(after: colon)...])
    }

    private func clean(_ value: String?) -> String? {
        guard let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines), !trimmed.isEmpty else { return nil }
        return trimmed
    }

    func parser(
        _ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?, qualifiedName qName: String?,
        attributes attributeDict: [String: String] = [:]
    ) {
        switch elementName {
        case "rss", "channel":
            sawFeed = true
        case "item":
            inItem = true
            version = nil
            shortVersion = nil
            minimumSystemVersion = nil
            channel = nil
        case "enclosure" where inItem:
            for (key, value) in attributeDict {
                switch sparkleName(key) {
                case "version": version = clean(value) ?? version
                case "shortVersionString": shortVersion = clean(value) ?? shortVersion
                default: break
                }
            }
        default:
            break
        }
        text = ""
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) { text += string }

    func parser(
        _ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?, qualifiedName qName: String?
    ) {
        if elementName == "item" {
            inItem = false
            if let version {
                items.append(
                    AppcastItem(
                        version: version, shortVersion: shortVersion, minimumSystemVersion: minimumSystemVersion,
                        channel: channel))
            }
        } else if inItem, let name = sparkleName(elementName), let value = clean(text) {
            switch name {
            case "version": version = value
            case "shortVersionString": shortVersion = value
            case "minimumSystemVersion": minimumSystemVersion = value
            case "channel": channel = value
            default: break
            }
        }
        text = ""
    }
}
