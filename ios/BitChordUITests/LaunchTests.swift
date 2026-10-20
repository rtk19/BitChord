import XCTest

final class LaunchTests: XCTestCase {
    override func setUpWithError() throws { continueAfterFailure = false }
    private func capture(_ name: String) {
        let screenshot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        screenshot.name = name; screenshot.lifetime = .keepAlways; add(screenshot)
    }
    func testNativeNavigationPlayerAndLibrary() {
        let app = XCUIApplication()
        app.launchArguments = ["--fixture", "--reset-library"]
        app.launch()
        XCTAssertTrue(app.tabBars.buttons["Home"].waitForExistence(timeout: 15))
        XCTAssertTrue(app.staticTexts["Made for your day"].waitForExistence(timeout: 15))
        capture("Native-Home")
        app.tabBars.buttons["Search"].tap()
        let search = app.searchFields.firstMatch
        XCTAssertTrue(search.waitForExistence(timeout: 5))
        search.tap(); search.typeText("Night")
        let song = app.buttons["track-test-night"].firstMatch
        XCTAssertTrue(song.waitForExistence(timeout: 10))
        capture("Native-Search")
        song.tap()
        let mini = app.buttons["Open Now Playing"]
        XCTAssertTrue(mini.waitForExistence(timeout: 5))
        mini.tap()
        XCTAssertTrue(app.navigationBars["Now Playing"].waitForExistence(timeout: 5))
        capture("Native-NowPlaying")
        app.buttons["Pause"].tap()
        XCTAssertTrue(app.buttons["Play"].exists)
        app.buttons["Favorite"].tap()
        app.buttons["Playing Next"].tap()
        XCTAssertTrue(app.navigationBars["Playing Next"].waitForExistence(timeout: 5))
        capture("Native-Queue")
        app.buttons["Done"].tap()
        app.buttons["Next Track"].tap()
        XCTAssertTrue(app.staticTexts["Blue Horizon"].waitForExistence(timeout: 5))
        app.buttons["Close Now Playing"].tap()
        app.tabBars.buttons["Library"].tap()
        app.buttons["Favorites"].tap()
        XCTAssertTrue(app.staticTexts["Night Drive"].waitForExistence(timeout: 5))
        capture("Native-Favorites")
        app.terminate(); app.launchArguments = ["--fixture"]; app.launch()
        app.tabBars.buttons["Library"].tap(); app.buttons["Favorites"].tap()
        XCTAssertTrue(app.staticTexts["Night Drive"].waitForExistence(timeout: 5), "Favorites must survive relaunch")
    }

    func testNormalLaunchHasNativeTabs() {
        let app = XCUIApplication(); app.launch()
        XCTAssertTrue(app.tabBars.buttons["Home"].waitForExistence(timeout: 15))
        app.tabBars.buttons["Search"].tap()
        XCTAssertTrue(app.searchFields.firstMatch.waitForExistence(timeout: 5))
        XCTAssertFalse(app.webViews.firstMatch.isHittable, "The engine must not expose an interactive web UI")
        capture("Native-Live-Launch")
    }

    func testLiveCatalogueAndLongPlayback() throws {
        // Real network/AVPlayer probe, separate from the deterministic UI test.
        // A blocked catalogue is recorded as skipped, never counted as playback proof.
        let app = XCUIApplication(); app.launch()
        app.tabBars.buttons["Search"].tap()
        let search = app.searchFields.firstMatch
        XCTAssertTrue(search.waitForExistence(timeout: 5))
        search.tap(); search.typeText("Daft Punk Get Lucky")
        let track = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "track-")).firstMatch
        guard track.waitForExistence(timeout: 60) else {
            capture("Live-Catalogue-Unavailable")
            let tree = XCTAttachment(string: app.debugDescription); tree.lifetime = .keepAlways; add(tree)
            throw XCTSkip("The external catalogue was unavailable on this runner; physical-device streaming remains unverified.")
        }
        capture("Live-Search-Results")
        track.tap(); app.buttons["Open Now Playing"].tap()
        let ready = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            app.buttons["Pause"].exists || app.staticTexts["load-error"].exists
        }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [ready], timeout: 70), .completed)
        let error = app.staticTexts["load-error"]
        if error.exists && error.label.contains("YouTube requested verification") {
            capture("Live-YouTube-Verification-Required")
            throw XCTSkip("YouTube requested verification from the runner's network. This is not a successful playback test; device validation remains required.")
        }
        XCTAssertTrue(app.buttons["Pause"].exists, error.exists ? error.label : "AVPlayer did not become ready")
        let elapsed = app.staticTexts["elapsed-time"]
        let advanced = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            let parts = elapsed.label.split(separator: ":").compactMap { Int($0) }
            return parts.count == 2 && parts[0] * 60 + parts[1] >= 95
        }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [advanced], timeout: 110), .completed, "Playback must advance beyond the common 70-second stream cutoff")
        capture("Live-Playback-95-Seconds")
    }

    func testDarkAppearance() {
        let app = XCUIApplication()
        app.launchArguments = ["--fixture", "-bitchord.appearance", "dark"]
        app.launch()
        XCTAssertTrue(app.staticTexts["Made for your day"].waitForExistence(timeout: 10))
        capture("Native-Home-Dark")
    }
}
