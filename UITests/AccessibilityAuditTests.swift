import CoreLocation
import XCTest

/// Apple's accessibility audit (element descriptions, contrast, clipped text, Dynamic Type, hit regions, traits) on
/// each screen, at the default text size and the largest. The issues are listed in the log ("AUDIT …") and attached
/// to the test, not failed on: some need judgment, such as the tasbih's large count, which keeps its size on purpose.
@MainActor
final class AccessibilityAuditTests: XCTestCase {
    private static let screens: [(name: String, arguments: [String])] = [
        ("setup-location", ["-setupStep", "2"]),
        ("setup-method", ["-setupStep", "3"]),
        ("times", ["-skipOnboarding", "YES", "-startTab", "times"]),
        ("qibla", ["-skipOnboarding", "YES", "-startTab", "qibla", "-demoHeading", "100"]),
        ("quran", ["-skipOnboarding", "YES", "-startTab", "quran", "-quranPage", "42"]),
        ("quran-night", ["-skipOnboarding", "YES", "-startTab", "quran", "-quranPage", "42", "-quranNight", "YES"]),
        ("tasbih", ["-skipOnboarding", "YES", "-startTab", "ibadah", "-ibadahPart", "tasbih"]),
        ("tracker", ["-skipOnboarding", "YES", "-startTab", "ibadah", "-ibadahPart", "tracker"]),
        ("settings", ["-skipOnboarding", "YES", "-startTab", "settings"]),
    ]

    private static let types: [(XCUIAccessibilityAuditType, String)] = [
        (.contrast, "contrast"), (.elementDetection, "element detection"), (.hitRegion, "hit region"),
        (.sufficientElementDescription, "description"), (.dynamicType, "dynamic type"), (.textClipped, "text clipped"),
        (.trait, "trait"), (.action, "action"), (.parentChild, "parent/child"),
    ]

    private var report: [String] = []

    func testAudit() throws {
        XCUIDevice.shared.location = XCUILocation(location: CLLocation(latitude: 52.3676, longitude: 4.9041))
        for size in ["UICTContentSizeCategoryL", "UICTContentSizeCategoryAccessibilityXXXL"] {
            for screen in Self.screens {
                let app = XCUIApplication()
                app.launchArguments = ["-AppleLanguages", "(en)", "-AppleLocale", "en_US",
                                       "-UIPreferredContentSizeCategoryName", size] + screen.arguments
                app.launch()
                allowLocation()
                sleep(3)  // the times, the compass and the page settle
                try app.performAccessibilityAudit { issue in
                    let type = Self.types.first { issue.auditType.contains($0.0) }?.1 ?? "other"
                    let element = issue.element.map { "\"\($0.label)\" \($0.identifier)" } ?? "-"
                    self.report.append("\(screen.name) @ \(size): \(type) | \(issue.compactDescription) | \(element)")
                    return true
                }
                app.terminate()
            }
        }
        let attachment = XCTAttachment(string: report.joined(separator: "\n"))
        attachment.name = "Accessibility audit"
        attachment.lifetime = .keepAlways
        add(attachment)
        print("ACCESSIBILITY AUDIT: \(report.count) issues")
        for line in report { print("AUDIT " + line) }
    }

    /// Answers the location prompt, the first time the app asks.
    private func allowLocation() {
        let allow = XCUIApplication(bundleIdentifier: "com.apple.springboard").buttons["Allow While Using App"]
        if allow.waitForExistence(timeout: 3) { allow.tap() }
    }
}
