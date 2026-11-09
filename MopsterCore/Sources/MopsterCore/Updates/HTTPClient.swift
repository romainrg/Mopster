import Foundation

public protocol HTTPClient: Sendable {
    func get(_ url: URL, timeout: TimeInterval) async throws -> Data
}

/// Plain HTTPS GET: no cookies, no cache, nothing stored, https only (redirects included).
public struct URLSessionHTTPClient: HTTPClient {
    private static let maxBytes = 10_000_000
    private let session: URLSession
    private let userAgent: String

    public init() {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.httpCookieAcceptPolicy = .never
        configuration.httpShouldSetCookies = false
        configuration.urlCache = nil
        configuration.waitsForConnectivity = false
        session = URLSession(configuration: configuration)
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0.1"
        userAgent = "Mopster/\(version) (+https://github.com/romainrg/mopster)"
    }

    public func get(_ url: URL, timeout: TimeInterval) async throws -> Data {
        guard url.scheme?.lowercased() == "https" else { throw URLError(.unsupportedURL) }
        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: timeout)
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        request.httpShouldHandleCookies = false

        return try await withThrowingTaskGroup(of: Data.self) { group in
            group.addTask { try await fetch(request) }
            group.addTask {
                try await Task.sleep(nanoseconds: UInt64(max(timeout, 0) * 1_000_000_000))
                throw URLError(.timedOut)
            }
            defer { group.cancelAll() }
            guard let data = try await group.next() else { throw URLError(.unknown) }
            return data
        }
    }

    private func fetch(_ request: URLRequest) async throws -> Data {
        let (bytes, response) = try await session.bytes(for: request, delegate: HTTPSOnlyRedirects())
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw URLError(.badServerResponse)
        }
        guard http.expectedContentLength <= Int64(Self.maxBytes) else { throw URLError(.dataLengthExceedsMaximum) }
        return try await Self.collect(bytes, limit: Self.maxBytes)
    }

    /// Accumulates at most `limit` bytes; throws as soon as one more arrives, so memory stays bounded.
    static func collect<S: AsyncSequence>(_ bytes: S, limit: Int) async throws -> Data where S.Element == UInt8 {
        var data = Data()
        for try await byte in bytes {
            guard data.count < limit else { throw URLError(.dataLengthExceedsMaximum) }
            data.append(byte)
        }
        return data
    }
}

private final class HTTPSOnlyRedirects: NSObject, URLSessionTaskDelegate {
    func urlSession(
        _ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
        newRequest request: URLRequest
    ) async -> URLRequest? {
        request.url?.scheme?.lowercased() == "https" ? request : nil
    }
}
