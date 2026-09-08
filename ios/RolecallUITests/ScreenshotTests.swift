import XCTest

/// App Store screenshot capture, per the ASO playbook: authentic functional UI, lead with
/// the real differentiator, five screens. Run against iPhone 17 Pro Max (6.9").
///
///   xcodebuild test -scheme Rolecall \
///     -destination 'platform=iOS Simulator,name=iPhone 17 Pro Max' \
///     -only-testing:RolecallUITests/ScreenshotTests
///
/// then export the attachments from the .xcresult (see web/../tools note).
final class ScreenshotTests: XCTestCase {

    let app = XCUIApplication()

    override func setUpWithError() throws {
        continueAfterFailure = false
        app.launchArguments += ["-uitest-seed", "-uitest-live", "-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        app.launch()
    }

    private func shot(_ name: String) {
        let a = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        a.name = name
        a.lifetime = .keepAlways
        add(a)
    }

    func test_captureAppStoreScreens() {
        // 1 — the board: verified, source-direct, scannable
        XCTAssertTrue(app.staticTexts["Rolecall"].waitForExistence(timeout: 10))
        _ = app.staticTexts.matching(NSPredicate(format: "label CONTAINS 'checked live'")).firstMatch
            .waitForExistence(timeout: 5)
        shot("01-board")

        // 2 — a role, verified live just now
        let firstRole = app.buttons.matching(
            NSPredicate(format: "label CONTAINS 'Staff' OR label CONTAINS 'Senior' OR label CONTAINS 'Product Designer'")
        ).firstMatch
        if firstRole.waitForExistence(timeout: 5) {
            firstRole.tap()
            _ = app.staticTexts["Verified live just now"].waitForExistence(timeout: 8)
            shot("02-verified")
            app.navigationBars.buttons.element(boundBy: 0).tap()
        }

        // 3 — track applications through the stages
        let applied = app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Applied'")).firstMatch
        if applied.waitForExistence(timeout: 5) {
            applied.tap()
            _ = app.staticTexts["Applications"].waitForExistence(timeout: 5)
            shot("03-applications")
            app.buttons["Board"].firstMatch.tap()
        }

        // 4 — filter to your discipline
        let filter = app.navigationBars.buttons["Filter"]
        if filter.waitForExistence(timeout: 5) {
            filter.tap()
            _ = app.staticTexts["Role family"].waitForExistence(timeout: 5)
            shot("04-filter")
            app.buttons["Done"].firstMatch.tap()
        }

        // 5 — no account, no trackers
        let settings = app.navigationBars.buttons["Settings"]
        if settings.waitForExistence(timeout: 5) {
            settings.tap()
            _ = app.staticTexts["Appearance"].waitForExistence(timeout: 5)
            shot("05-privacy")
        }
    }
}
