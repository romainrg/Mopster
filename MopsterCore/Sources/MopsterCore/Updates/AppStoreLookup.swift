import Foundation

public enum AppStoreLookup {
    public static func url(bundleID: String, country: String) -> URL? {
        var components = URLComponents()
        components.scheme = "https"
        components.host = "itunes.apple.com"
        components.path = "/lookup"
        components.queryItems = [
            URLQueryItem(name: "bundleId", value: bundleID), URLQueryItem(name: "country", value: country),
        ]
        return components.url
    }

    public static func parse(_ data: Data) -> (version: String, trackID: Int)? {
        guard let root = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
            let count = root["resultCount"] as? Int, count > 0,
            let results = root["results"] as? [[String: Any]],
            let first = results.first(where: { $0["kind"] as? String == "mac-software" }),
            let version = first["version"] as? String, !version.isEmpty,
            let trackID = first["trackId"] as? Int
        else { return nil }
        return (version, trackID)
    }
}
