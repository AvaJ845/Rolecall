import XCTest
@testable import Rolecall

@MainActor
final class TrackerProTests: XCTestCase {

    private var defaults: UserDefaults!
    private var store: TrackedRoles!

    override func setUp() {
        super.setUp()
        defaults = UserDefaults(suiteName: "TrackerPro-\(UUID().uuidString)")
        store = TrackedRoles(defaults: defaults)
    }
    override func tearDown() {
        defaults.removePersistentDomain(forName: defaults.description)
        super.tearDown()
    }

    private func role(_ url: String, company: String = "Acme", title: String = "Product Designer") -> Role {
        Role(company: company, title: title, family: .design, location: nil, remote: nil,
             url: URL(string: url)!, firstSeen: Date(), lastVerified: nil)
    }

    func testApplicationDecodesWithoutFollowUpKey() throws {
        let legacy = #"{"appliedOn":700000000,"stage":"applied","updatedOn":700000000,"note":"hi"}"#
        let app = try JSONDecoder().decode(Application.self, from: Data(legacy.utf8))
        XCTAssertNil(app.followUpAt)
        XCTAssertEqual(app.note, "hi")
    }

    func testSetFollowUpAndTerminalStageClearsIt() {
        let r = role("https://x/1")
        store.markApplied(r)
        store.setFollowUp(Date(timeIntervalSinceNow: 3 * 86_400), for: r)
        XCTAssertNotNil(store.application(for: r)?.followUpAt)

        store.updateApplication(for: r) { $0.stage = .rejected }
        XCTAssertNil(store.application(for: r)?.followUpAt, "a closed application drops its reminder")
    }

    func testSetNoteDoesNotBumpUpdatedOn() {
        let r = role("https://x/2")
        let t0 = Date(timeIntervalSince1970: 1_000_000)
        store.markApplied(r, on: t0)
        store.setNote("phone screen went well", for: r)
        XCTAssertEqual(store.application(for: r)?.updatedOn, t0)
        XCTAssertEqual(store.application(for: r)?.note, "phone screen went well")
    }

    func testExportMarkdownAndCSV() {
        let entries: [(role: Role, application: Application)] = [
            (role("https://x/1", company: "Figma", title: "Brand Designer"),
             { var a = Application(appliedOn: Date(timeIntervalSince1970: 1_700_000_000)); a.stage = .hiringManager; a.note = "recruiter: Sam"; return a }()),
            (role("https://x/2", company: "Ramp, Inc.", title: "Staff Designer"),
             { var a = Application(); a.stage = .offer; return a }()),
        ]
        let md = ApplicationExport.markdown(entries)
        XCTAssertTrue(md.contains("| Figma | Brand Designer | Hiring manager"))
        XCTAssertTrue(md.contains("> recruiter: Sam"))

        let csv = ApplicationExport.csv(entries)
        XCTAssertEqual(csv.split(separator: "\n").first, "company,role,stage,applied,updated,note,url")
        XCTAssertTrue(csv.contains("\"Ramp, Inc.\""), "a comma in a field is quoted")
    }
}
