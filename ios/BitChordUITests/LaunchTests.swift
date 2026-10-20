import XCTest

final class LaunchTests: XCTestCase {
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
        let song = app.buttons.containing(.staticText, identifier: "Night Drive").firstMatch
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
        XCTAssertFalse(app.webViews.firstMatch.exists, "WebKit must not expose a web UI")
        capture("Native-Live-Launch")
    }
}
