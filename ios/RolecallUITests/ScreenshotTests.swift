import XCTest

/// App Store screenshot capture, per the ASO playbook: authentic functional UI, lead with
/// the real differentiator. Run against iPhone 17 Pro Max (6.9") and iPad Pro 13".
///
///   xcodebuild test -scheme Rolecall \
///     -destination 'platform=iOS Simulator,name=iPhone 17 Pro Max' \
///     -only-testing:RolecallUITests/ScreenshotTests
///
/// then export the attachments from the .xcresult (see ios/AppStore/capture.sh, which
/// also applies a clean 9:41 status bar so the raw frames have no stray clock / battery).
final class ScreenshotTests: XCTestCase {

    let app = XCUIApplication()

    override func setUpWithError() throws {
        continueAfterFailure = false
        app.launchArguments += ["-uitest-seed", "-uitest-live", "-AppleLanguages", "(en)", "-AppleLocale", "en_US"]

        // The paywall review screenshot renders the two Rolecall Plus plans from a
        // fixed offline stand-in — StoreKit product loading is not reachable under
        // `xcodebuild test` in the simulator.
        if name.contains("Paywall") {
            app.launchArguments.append("-uitest-paywall")
        }

        app.launch()
    }

    private func shot(_ name: String) {
        // Let scroll indicators and any settle animation fade before the frame.
        Thread.sleep(forTimeInterval: 1.0)
        let a = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        a.name = name
        a.lifetime = .keepAlways
        add(a)
    }

    /// Scroll a scroll view up until `element` is on screen and hittable, or we give up.
    @discardableResult
    private func scrollUp(to element: XCUIElement, maxSwipes: Int = 10) -> Bool {
        var tries = 0
        while !element.isHittable && tries < maxSwipes {
            app.swipeUp()
            tries += 1
        }
        return element.isHittable
    }

    /// App Store Connect requires a review screenshot for every in-app subscription,
    /// showing where the customer reaches and buys it. One capture of the paywall covers
    /// both products in the "Rolecall Plus" group.
    func test_capturePaywallForSubscriptionReview() {
        XCTAssertTrue(app.staticTexts["Rolecall"].waitForExistence(timeout: 10))

        let settings = app.navigationBars.buttons["Settings"]
        XCTAssertTrue(settings.waitForExistence(timeout: 5))
        settings.tap()

        let plusRow = app.buttons.matching(
            NSPredicate(format: "label CONTAINS 'Rolecall Plus'")
        ).firstMatch
        XCTAssertTrue(plusRow.waitForExistence(timeout: 5))
        plusRow.tap()

        XCTAssertTrue(
            app.buttons["Start 7 days free"].waitForExistence(timeout: 10),
            "the paywall should show the trial buy bar"
        )
        _ = app.staticTexts["Run a serious search."].waitForExistence(timeout: 5)
        shot("06-paywall")
    }

    func test_captureAppStoreScreens() {
        // 01 — the board: verified, source-direct, scannable
        XCTAssertTrue(app.staticTexts["Rolecall"].waitForExistence(timeout: 10))
        _ = app.staticTexts.matching(NSPredicate(format: "label CONTAINS 'checked live'")).firstMatch
            .waitForExistence(timeout: 5)
        shot("01-board")

        // 02 — a role's verified-live proof card. Opened from the Saved list so the exact
        // role is drawn from the curated screenshot seed (never a competitor, never a
        // stray non-design posting off the top of the board).
        let savedTab = app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Saved'")).firstMatch
        if savedTab.waitForExistence(timeout: 5) {
            savedTab.tap()
            let savedRole = app.buttons.matching(
                NSPredicate(format: "label CONTAINS[c] 'design' AND NOT (label BEGINSWITH 'Saved')")
            ).firstMatch
            if savedRole.waitForExistence(timeout: 5) {
                savedRole.tap()
                _ = app.staticTexts["Verified live just now"].waitForExistence(timeout: 8)
                shot("02-verified")
                app.navigationBars.buttons.element(boundBy: 0).tap()
            }
            // back to the board tab for the next shot
            app.buttons["Board"].firstMatch.tap()
        }

        // 03 — track applications through the stages
        let applied = app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Applied'")).firstMatch
        if applied.waitForExistence(timeout: 5) {
            applied.tap()
            _ = app.staticTexts["Applications"].waitForExistence(timeout: 5)
            shot("03-applications")
            app.buttons["Board"].firstMatch.tap()
        }

        // 04 — filter to your discipline (the toolbar control is a menu)
        let filterMenu = app.navigationBars.buttons["Filter and searches"]
        if filterMenu.waitForExistence(timeout: 5) {
            filterMenu.tap()
            let filterItem = app.buttons["Filter"].firstMatch
            if filterItem.waitForExistence(timeout: 3) { filterItem.tap() }
            _ = app.buttons["Done"].waitForExistence(timeout: 5)   // the filter sheet is up
            _ = app.staticTexts["US & remote only"].waitForExistence(timeout: 3)
            shot("04-filter")
            app.buttons["Done"].firstMatch.tap()
        }

        // 05 — the icon variants are composited in frame.py from the shipped 1024s;
        // nothing to capture here.

        // 06 — no account, no trackers: scroll the Settings sheet so the Privacy section
        // (its "everything stays on this device" card) sits at the top of the frame.
        let settings = app.navigationBars.buttons["Settings"]
        if settings.waitForExistence(timeout: 5) {
            settings.tap()
            _ = app.staticTexts["Appearance"].waitForExistence(timeout: 5)
            // Scroll to the very bottom so the Privacy section settles at a fixed offset
            // (its header ~40% down); frame.py's per-shot crop then trims to that header,
            // so the frame opens cleanly on the "everything stays on this device" card.
            scrollUp(to: app.staticTexts.matching(
                NSPredicate(format: "label CONTAINS 'straight from the source'")).firstMatch)
            shot("06-privacy")
        }
    }
}
