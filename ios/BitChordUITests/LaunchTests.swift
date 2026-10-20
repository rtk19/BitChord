import XCTest
import UIKit

final class LaunchTests: XCTestCase {
    func testBundledInterfaceLoadsWithoutAnExtension() {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing"]
        app.launch()
        let menu = app.webViews.buttons["Open menu"]
        XCTAssertTrue(menu.waitForExistence(timeout: 30), "The bundled React interface must render inside WKWebView")
        XCTAssertTrue(menu.isHittable, app.debugDescription)
        XCTAssertFalse(app.staticTexts["BitChord is better in the app."].exists, "Native builds must not show the Android download banner")
        let screen = XCUIScreen.main.screenshot()
        let screenshot = XCTAttachment(screenshot: screen)
        screenshot.name = "BitChord-iOS-launch"
        screenshot.lifetime = .keepAlways
        add(screenshot)
        XCTAssertTrue(hasPaintedContent(screen), "The app must paint visible content, not only expose accessibility elements")
        menu.tap()
        let search = app.webViews.links["Search"]
        XCTAssertTrue(search.waitForExistence(timeout: 5))
        XCTAssertTrue(search.isHittable)
        search.tap()
        XCTAssertTrue(app.webViews.searchFields.firstMatch.waitForExistence(timeout: 10) || app.webViews.textFields.firstMatch.waitForExistence(timeout: 10), "Navigation must reach the Search page")
        let hierarchy = XCTAttachment(string: app.debugDescription)
        hierarchy.name = "BitChord-accessibility-tree"
        hierarchy.lifetime = .keepAlways
        add(hierarchy)
    }

    private func hasPaintedContent(_ screenshot: XCUIScreenshot) -> Bool {
        guard let image = screenshot.image.cgImage else { return false }
        let width = image.width, height = image.height
        var pixels = [UInt8](repeating: 255, count: width * height * 4)
        return pixels.withUnsafeMutableBytes { buffer in
            guard let context = CGContext(data: buffer.baseAddress, width: width, height: height,
                                          bitsPerComponent: 8, bytesPerRow: width * 4,
                                          space: CGColorSpaceCreateDeviceRGB(),
                                          bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return false }
            context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
            let bytes = buffer.bindMemory(to: UInt8.self)
            var painted = 0
            // Exclude the status bar and home indicator; inspect the app's area.
            for y in stride(from: height / 10, to: height * 9 / 10, by: 4) {
                for x in stride(from: 0, to: width, by: 4) {
                    let index = (y * width + x) * 4
                    if min(bytes[index], bytes[index + 1], bytes[index + 2]) < 230 { painted += 1 }
                }
            }
            return painted > 100
        }
    }
}
