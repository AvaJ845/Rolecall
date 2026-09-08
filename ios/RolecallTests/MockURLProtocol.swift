import Foundation

/// Answers every request from a test-supplied handler, so `FreshnessChecker` and
/// `BoardStore` can be exercised without touching the network.
final class MockURLProtocol: URLProtocol {

    /// `(request) -> (HTTPURLResponse, body)`. Set `response.url` to a careers-index URL
    /// to simulate a followed redirect. Tests run serially, so unsynchronised access is
    /// fine here.
    nonisolated(unsafe) static var handler: ((URLRequest) throws -> (HTTPURLResponse, Data))?

    /// Requests actually started since the last `reset()` — lets a test assert that a
    /// cache hit or a Wi-Fi-only short-circuit prevented a network call.
    nonisolated(unsafe) static var requestCount = 0

    static func stub(statusCode: Int,
                     finalURL: URL? = nil,
                     headers: [String: String] = [:],
                     body: String = "") {
        handler = { request in
            let url = finalURL ?? request.url!
            let response = HTTPURLResponse(url: url,
                                           statusCode: statusCode,
                                           httpVersion: "HTTP/1.1",
                                           headerFields: headers)!
            return (response, Data(body.utf8))
        }
    }

    static func reset() { handler = nil; requestCount = 0 }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        MockURLProtocol.requestCount += 1
        guard let handler = MockURLProtocol.handler else {
            client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse))
            return
        }
        do {
            let (response, data) = try handler(request)
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}
}
