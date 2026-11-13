import XCTest

/// Turning the mushaf's pages: "Go to page", the page bar's buttons, and swiping (right for the next page, as a
/// mushaf turns), on an English and on an Arabic (right-to-left) iPhone.
@MainActor
final class QuranReaderTests: XCTestCase {
    func testTurningPages() {
        turnPages(language: "en", locale: "en_US", typing: "1")
    }

    func testTurningPagesInArabic() {
        turnPages(language: "ar", locale: "ar_SA", typing: "١")
    }

    private func turnPages(language: String, locale: String, typing first: String) {
        let app = XCUIApplication()
        app.launchArguments = ["-AppleLanguages", "(\(language))", "-AppleLocale", locale, "-skipOnboarding", "YES",
                               "-startTab", "quran"]
        app.launch()
        // The location question, if it comes (in the simulator's own language, English, whatever the app's).
        let allow = XCUIApplication(bundleIdentifier: "com.apple.springboard").buttons["Allow While Using App"]
        if allow.waitForExistence(timeout: 3) { allow.tap() }

        // From page 1, whatever page was open last.
        let title = app.buttons["goToPage"]
        XCTAssertTrue(title.waitForExistence(timeout: 10), "The reader's title isn't there")
        title.tap()
        let field = app.textFields["pageField"]
        XCTAssertTrue(field.waitForExistence(timeout: 5), "Go to page didn't open")
        field.tap()
        field.typeText(first)
        app.buttons["openPage"].tap()
        expect(title, toShow: 1)

        app.buttons["nextPage"].tap()
        expect(title, toShow: 2)
        app.swipeRight()
        expect(title, toShow: 3)
        app.swipeLeft()
        expect(title, toShow: 2)
        app.buttons["previousPage"].tap()
        expect(title, toShow: 1)
    }

    private func expect(_ title: XCUIElement, toShow page: Int) {
        // The page number ends the title's label, in Western or Arabic digits ("Page 1", "صفحة ١"), with no digit
        // before it (not "Page 12").
        let western = String(page)
        let arabic = String(String.UnicodeScalarView(western.unicodeScalars.compactMap { Unicode.Scalar($0.value + 0x630) }))
        let shown = NSPredicate(format: "label MATCHES %@", "(?s).*\\D(\(western)|\(arabic))\\p{Cf}*")
        let waiting = XCTNSPredicateExpectation(predicate: shown, object: title)
        XCTAssertEqual(XCTWaiter().wait(for: [waiting], timeout: 6), .completed,
                       "Expected page \(page); the title says \"\(title.label)\"")
    }
}
