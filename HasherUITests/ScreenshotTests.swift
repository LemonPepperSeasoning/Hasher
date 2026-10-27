import XCTest

/// App Store screenshots: a 64-bit GPU search in progress, settings, and a 40-bit collision.

final class ScreenshotTests: XCTestCase {
    /// Where tools/screenshots.sh asks for the shots; set through TEST_RUNNER_SHOTS_DIR.
    var directory: URL!

    override func setUpWithError() throws {
        let path = ProcessInfo.processInfo.environment["SHOTS_DIR"]
        try XCTSkipIf(path == nil, "Run through tools/screenshots.sh")
        directory = URL(fileURLWithPath: path!)
    }

    func shot(_ app: XCUIApplication, _ name: String) {
        let data = app.windows.firstMatch.screenshot().pngRepresentation
        let device = ProcessInfo.processInfo.environment["SIMULATOR_DEVICE_NAME"] ?? "device"
        try? data.write(to: directory.appendingPathComponent("\(device)-\(name).png"))
    }

    func configure(_ app: XCUIApplication, bits: String, gpu: Bool, seed: String) {
        app.buttons["Settings"].tap()
        app.buttons[bits].tap()
        if app.buttons["GPU"].exists { app.buttons[gpu ? "GPU" : "CPU"].tap() }
        let field = app.textFields.firstMatch
        field.tap()
        field.press(forDuration: 1.0)
        if app.menuItems["Select All"].waitForExistence(timeout: 1) { app.menuItems["Select All"].tap() }
        field.typeText(XCUIKeyboardKey.delete.rawValue)
        field.typeText(seed + "\n")
    }

    func testScreenshots() throws {
        let app = XCUIApplication()
        app.launch()
        XCUIDevice.shared.orientation = .portrait
        configure(app, bits: "64", gpu: true, seed: "quiet-river-2048")
        shot(app, "2-settings")
        app.buttons["Done"].tap()
        app.buttons["Start"].tap()
        sleep(8)
        shot(app, "1-home")
        app.buttons["Pause"].tap()
        configure(app, bits: "40", gpu: false, seed: "hasha")
        app.buttons["Done"].tap()
        app.buttons["Start"].tap()
        XCTAssert(app.buttons["New search"].waitForExistence(timeout: 120))
        sleep(1)
        shot(app, "3-collision")
    }
}
