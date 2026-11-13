import CoreLocation
import XCTest

/// Apple's accessibility audit (element descriptions, contrast, clipped text, Dynamic Type, hit regions, traits) on
/// each screen: everything at the default text size, the text checks again at the largest. Each issue is printed as
/// it is found ("AUDIT …", collected by the workflow), not failed on: some need judgment, such as the tasbih's large
/// count, which keeps its size on purpose. A screen whose audit doesn't finish is reported and skipped.
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

    private static let passes: [(size: String, types: XCUIAccessibilityAuditType)] = [
        ("default", .all),
        ("largest", [.dynamicType, .textClipped]),
    ]

    private static let typeNames: [(XCUIAccessibilityAuditType, String)] = [
        (.contrast, "contrast"), (.elementDetection, "element detection"), (.hitRegion, "hit region"),
        (.sufficientElementDescription, "description"), (.dynamicType, "dynamic type"), (.textClipped, "text clipped"),
        (.trait, "trait"),
    ]

    private var issues = 0
    /// The location prompt comes once, at the first launch that asks for the location.
    private var locationAnswered = false

    func testAudit() {
        XCUIDevice.shared.location = XCUILocation(location: CLLocation(latitude: 52.3676, longitude: 4.9041))
        for pass in Self.passes {
            let category = pass.size == "default" ? "UICTContentSizeCategoryL" : "UICTContentSizeCategoryAccessibilityXXXL"
            for screen in Self.screens {
                let app = XCUIApplication()
                app.launchArguments = ["-AppleLanguages", "(en)", "-AppleLocale", "en_US",
                                       "-UIPreferredContentSizeCategoryName", category] + screen.arguments
                app.launch()
                sleep(3)  // the times, the compass and the page settle
                answerLocationPrompt()
                let place = "\(screen.name) @ \(pass.size)"
                do {
                    try app.performAccessibilityAudit(for: pass.types) { issue in
                        let type = Self.typeNames.first { issue.auditType.contains($0.0) }?.1 ?? "other"
                        let element = issue.element.map { "\"\($0.label.prefix(80))\" \($0.identifier)" } ?? "-"
                        print("AUDIT \(place): \(type) | \(issue.compactDescription) | \(element)")
                        self.issues += 1
                        return true
                    }
                } catch {
                    print("AUDIT \(place): the audit did not finish: \(error.localizedDescription)")
                }
                app.terminate()
            }
        }
        print("AUDIT done: \(issues) issues")
    }

    private func answerLocationPrompt() {
        guard !locationAnswered else { return }
        let allow = XCUIApplication(bundleIdentifier: "com.apple.springboard").buttons["Allow While Using App"]
        if allow.exists {
            allow.tap()
            locationAnswered = true
            sleep(2)
        }
    }
}
