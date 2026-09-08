import XCTest
@testable import Rolecall

final class FreshnessCheckerTests: XCTestCase {

    private let jobURL = URL(string: "https://boards.greenhouse.io/acme/jobs/4567890")!

    override func tearDown() {
        MockURLProtocol.reset()
        super.tearDown()
    }

    private func makeChecker() -> FreshnessChecker {
        .ephemeral(protocolClasses: [MockURLProtocol.self])
    }

    func testLivePostingIsLive() async {
        MockURLProtocol.stub(
            statusCode: 200,
            body: "<html><body><h1>Product Designer</h1><button>Apply for this job</button></body></html>"
        )
        let status = await makeChecker().check(jobURL)
        XCTAssertEqual(status, .liveJustChecked)
    }

    func testNotFoundMayHaveClosed() async {
        MockURLProtocol.stub(statusCode: 404, body: "Not Found")
        let status = await makeChecker().check(jobURL)
        XCTAssertEqual(status, .mayHaveClosed)
    }

    func testGoneMayHaveClosed() async {
        MockURLProtocol.stub(statusCode: 410, body: "Gone")
        let status = await makeChecker().check(jobURL)
        XCTAssertEqual(status, .mayHaveClosed)
    }

    func testRedirectToCareersIndexMayHaveClosed() async {
        // The ATS bounced the pulled role to a bare careers index with no job id.
        MockURLProtocol.stub(
            statusCode: 200,
            finalURL: URL(string: "https://boards.greenhouse.io/acme")!,
            body: "<html><body>Open roles at Acme</body></html>"
        )
        let status = await makeChecker().check(jobURL)
        XCTAssertEqual(status, .mayHaveClosed)
    }

    func testRedirectThatStillHasJobIdIsLive() async {
        // A canonicalising redirect that keeps the posting id is not a closure.
        MockURLProtocol.stub(
            statusCode: 200,
            finalURL: URL(string: "https://job-boards.greenhouse.io/acme/jobs/4567890")!,
            body: "<html><body><h1>Product Designer</h1></body></html>"
        )
        let status = await makeChecker().check(jobURL)
        XCTAssertEqual(status, .liveJustChecked)
    }

    func testClosedBodyTextMayHaveClosed() async {
        MockURLProtocol.stub(
            statusCode: 200,
            body: "<html><body><p>We are no longer accepting applications for this position.</p></body></html>"
        )
        let status = await makeChecker().check(jobURL)
        XCTAssertEqual(status, .mayHaveClosed)
    }

    func testNetworkErrorCouldNotCheck() async {
        MockURLProtocol.handler = { _ in throw URLError(.notConnectedToInternet) }
        let status = await makeChecker().check(jobURL)
        XCTAssertEqual(status, .couldNotCheck)
    }

    // Pure-function classification, no session involved.

    func testClassifyDirect() {
        XCTAssertEqual(
            FreshnessChecker.classify(statusCode: 200, finalURL: jobURL, requestedURL: jobURL,
                                      body: "Apply now"),
            .liveJustChecked)

        XCTAssertEqual(
            FreshnessChecker.classify(statusCode: 404, finalURL: jobURL, requestedURL: jobURL,
                                      body: ""),
            .mayHaveClosed)

        XCTAssertEqual(
            FreshnessChecker.classify(
                statusCode: 200,
                finalURL: URL(string: "https://acme.com/careers")!,
                requestedURL: jobURL,
                body: "careers"),
            .mayHaveClosed)

        XCTAssertEqual(
            FreshnessChecker.classify(statusCode: 200, finalURL: jobURL, requestedURL: jobURL,
                                      body: "This job is no longer available"),
            .mayHaveClosed)
    }
}
