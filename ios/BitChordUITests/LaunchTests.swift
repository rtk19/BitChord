import XCTest

final class LaunchTests: XCTestCase {
    func testBundledInterfaceLoadsWithoutAnExtension() {
        let app = XCUIApplication()
        app.launch()
        let menu = app.webViews.buttons["Open menu"]
        XCTAssertTrue(menu.waitForExistence(timeout: 30), "The bundled React interface must render inside WKWebView")
        XCTAssertFalse(app.staticTexts["BitChord is better in the app."].exists, "Native builds must not show the Android download banner")
        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = "BitChord-iOS-launch"
        screenshot.lifetime = .keepAlways
        add(screenshot)
        menu.tap()
        XCTAssertTrue(app.webViews.links["Search"].waitForExistence(timeout: 5), "The shared navigation must respond to taps")
    }
}
