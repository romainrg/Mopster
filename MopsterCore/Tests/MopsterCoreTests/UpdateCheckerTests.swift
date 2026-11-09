import XCTest
@testable import MopsterCore

private final class FakeHTTP: HTTPClient, @unchecked Sendable {
    private let lock = NSLock()
    private var current = 0
    private var _peak = 0
    private var _requested: [URL] = []
    private let handler: @Sendable (URL) async throws -> Data

    init(handler: @escaping @Sendable (URL) async throws -> Data) { self.handler = handler }

    var peak: Int { lock.withLock { _peak } }
    var requested: [URL] { lock.withLock { _requested } }

    func get(_ url: URL, timeout: TimeInterval) async throws -> Data {
        lock.withLock {
            current += 1
            _peak = max(_peak, current)
            _requested.append(url)
        }
        defer { lock.withLock { current -= 1 } }
        return try await handler(url)
    }
}

final class UpdateCheckerTests: XCTestCase {
    private let os = OperatingSystemVersion(majorVersion: 14, minorVersion: 4, patchVersion: 1)

    private func app(
        _ id: String, version: String = "1.0", build: String = "100", store: Bool = false, feed: String? = nil
    ) -> InstalledApp {
        InstalledApp(
            url: URL(fileURLWithPath: "/Applications/\(id).app"), bundleID: id, name: id, version: version,
            build: build, isAppStore: store, sparkleFeed: feed.flatMap(URL.init(string:)), minimumSystemVersion: nil,
            isLocked: false, size: 0, lastUsed: nil)
    }

    private func checker(
        _ http: FakeHTTP, maxConcurrent: Int = 4, system: @escaping @Sendable () async -> [SystemUpdate]? = { [] }
    ) -> UpdateChecker {
        UpdateChecker(http: http, country: "fr", osVersion: os, maxConcurrent: maxConcurrent, systemUpdates: system)
    }

    private func appcast(version: String, short: String? = nil) -> Data {
        let shortAttr = short.map { " sparkle:shortVersionString=\"\($0)\"" } ?? ""
        return Data(
            """
            <rss xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle"><channel><item>
            <enclosure url="https://x.test/a.zip" sparkle:version="\(version)"\(shortAttr)/>
            </item></channel></rss>
            """.utf8)
    }

    func testNeverMoreThanFourRequestsInFlight() async {
        let http = FakeHTTP { _ in
            try await Task.sleep(nanoseconds: 20_000_000)
            return self.appcast(version: "100")
        }
        let apps = (0..<20).map { app("a\($0)", feed: "https://x.test/\($0).xml") }
        let result = await checker(http).check(apps: apps)
        XCTAssertEqual(http.requested.count, 20)
        XCTAssertLessThanOrEqual(http.peak, 4)
        XCTAssertEqual(http.peak, 4)
        XCTAssertEqual(result.unknown.count, 0)
        XCTAssertEqual(result.updates.count, 0)
    }

    func testRespectsCustomMaxConcurrent() async {
        let http = FakeHTTP { _ in
            try await Task.sleep(nanoseconds: 10_000_000)
            return self.appcast(version: "100")
        }
        let apps = (0..<6).map { app("a\($0)", feed: "https://x.test/\($0).xml") }
        _ = await checker(http, maxConcurrent: 2).check(apps: apps)
        XCTAssertEqual(http.peak, 2)
    }

    func testTimeoutOrErrorMakesAppUnknownNotUpToDate() async {
        let http = FakeHTTP { url in
            if url.absoluteString.contains("timeout") { throw URLError(.timedOut) }
            return Data("garbage".utf8)
        }
        let apps = [
            app("t", feed: "https://x.test/timeout.xml"), app("g", feed: "https://x.test/garbage.xml"),
            app("s", store: true),
        ]
        let result = await checker(http).check(apps: apps)
        XCTAssertEqual(Set(result.unknown.map(\.bundleID)), ["t", "g", "s"])
        XCTAssertTrue(result.updates.isEmpty)
    }

    func testSparkleComparesBuildVersion() async {
        let http = FakeHTTP { _ in self.appcast(version: "121", short: "1.2.1") }
        let result = await checker(http).check(apps: [app("a", version: "1.2", build: "120", feed: "https://x.test/a.xml")])
        XCTAssertEqual(result.updates.count, 1)
        XCTAssertEqual(result.updates[0].available, "1.2.1")
        guard case .sparkle = result.updates[0].source else { return XCTFail("expected sparkle") }
    }

    func testSparkleSameBuildIsUpToDate() async {
        let http = FakeHTTP { _ in self.appcast(version: "120") }
        let result = await checker(http).check(apps: [app("a", build: "120", feed: "https://x.test/a.xml")])
        XCTAssertTrue(result.updates.isEmpty)
        XCTAssertTrue(result.unknown.isEmpty)
    }

    func testSparkleAvailableFallsBackToVersion() async {
        let http = FakeHTTP { _ in self.appcast(version: "121") }
        let result = await checker(http).check(apps: [app("a", build: "120", feed: "https://x.test/a.xml")])
        XCTAssertEqual(result.updates.first?.available, "121")
    }

    func testNoCompatibleItemIsUnknown() async {
        let http = FakeHTTP { _ in
            Data(
                """
                <rss xmlns:sparkle="x"><channel><item><sparkle:version>200</sparkle:version>
                <sparkle:channel>beta</sparkle:channel></item></channel></rss>
                """.utf8)
        }
        let result = await checker(http).check(apps: [app("a", feed: "https://x.test/a.xml")])
        XCTAssertEqual(result.unknown.map(\.bundleID), ["a"])
    }

    func testHttpFeedIsUnknown() async {
        let http = FakeHTTP { _ in self.appcast(version: "999") }
        let result = await checker(http).check(apps: [app("a", feed: "http://x.test/a.xml")])
        XCTAssertEqual(result.unknown.map(\.bundleID), ["a"])
        XCTAssertTrue(http.requested.isEmpty)
    }

    func testAppStoreComparesShortVersion() async {
        let http = FakeHTTP { url in
            XCTAssertEqual(url.absoluteString, "https://itunes.apple.com/lookup?bundleId=com.s.new&country=fr")
            return Data(#"{"resultCount":1,"results":[{"kind":"mac-software","trackId":42,"version":"2.0"}]}"#.utf8)
        }
        let result = await checker(http).check(apps: [
            app("com.s.new", version: "1.9", build: "999", store: true)
        ])
        XCTAssertEqual(result.updates.count, 1)
        XCTAssertEqual(result.updates[0].available, "2.0")
        guard case .appStore(let trackID) = result.updates[0].source else { return XCTFail("expected appStore") }
        XCTAssertEqual(trackID, 42)
    }

    func testAppStoreUpToDate() async {
        let http = FakeHTTP { _ in Data(#"{"resultCount":1,"results":[{"kind":"mac-software","trackId":42,"version":"2.0"}]}"#.utf8) }
        let result = await checker(http).check(apps: [app("a", version: "2.0.0", store: true)])
        XCTAssertTrue(result.updates.isEmpty)
        XCTAssertTrue(result.unknown.isEmpty)
    }

    func testAppsWithoutSourceAreIgnored() async {
        let http = FakeHTTP { _ in Data() }
        let result = await checker(http).check(apps: [app("plain")])
        XCTAssertTrue(result.updates.isEmpty)
        XCTAssertTrue(result.unknown.isEmpty)
        XCTAssertTrue(http.requested.isEmpty)
    }

    func testSystemUpdatesRunConcurrentlyAndFailureIsNil() async {
        let http = FakeHTTP { _ in self.appcast(version: "100") }
        let update = SystemUpdate(label: "L", title: "T", version: "1", recommended: true, restart: false)
        let ok = await checker(http, system: { [update] }).check(apps: [])
        XCTAssertEqual(ok.system, [update])
        let failed = await checker(http, system: { nil }).check(apps: [])
        XCTAssertNil(failed.system)
    }
}

final class URLSessionHTTPClientTests: XCTestCase {
    func testRefusesNonHTTPS() async {
        do {
            _ = try await URLSessionHTTPClient().get(URL(string: "http://example.com/")!, timeout: 2)
            XCTFail("expected a throw")
        } catch let error as URLError {
            XCTAssertEqual(error.code, .unsupportedURL)
        } catch {
            XCTFail("unexpected \(error)")
        }
    }
}
