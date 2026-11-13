import XCTest

/// Turning the mushaf's pages: "Go to page", the page bar's buttons, and swiping (right for the next page, as a
/// mushaf turns).
@MainActor
final class QuranReaderTests: XCTestCase {
    func testTurningPages() {
        let app = XCUIApplication()
        app.launchArguments = ["-AppleLanguages", "(en)", "-AppleLocale", "en_US", "-skipOnboarding", "YES",
                               "-startTab", "quran"]
        app.launch()
        let allow = XCUIApplication(bundleIdentifier: "com.apple.springboard").buttons["Allow While Using App"]
        if allow.waitForExistence(timeout: 3) { allow.tap() }

        // From page 1, whatever page was open last.
        let title = app.buttons["goToPage"]
        XCTAssertTrue(title.waitForExistence(timeout: 10), "The reader's title isn't there")
        title.tap()
        let field = app.textFields["pageField"]
        XCTAssertTrue(field.waitForExistence(timeout: 5), "Go to page didn't open")
        field.tap()
        field.typeText("1")
        app.buttons["openPage"].tap()
        expect(title, toShow: "Page 1")

        app.buttons["nextPage"].tap()
        expect(title, toShow: "Page 2")
        app.swipeRight()
        expect(title, toShow: "Page 3")
        app.swipeLeft()
        expect(title, toShow: "Page 2")
        app.buttons["previousPage"].tap()
        expect(title, toShow: "Page 1")
    }

    private func expect(_ title: XCUIElement, toShow page: String) {
        // "Page 1" but not "Page 12": the page is the end of the title's label.
        let shown = NSPredicate(format: "label ENDSWITH %@", page)
        let waiting = XCTNSPredicateExpectation(predicate: shown, object: title)
        XCTAssertEqual(XCTWaiter().wait(for: [waiting], timeout: 6), .completed,
                       "Expected \(page); the title says \"\(title.label)\"")
    }
}
