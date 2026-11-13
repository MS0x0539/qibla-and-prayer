import AppIntents
import Foundation

/// The screens the controls open, from Control Center, the Lock Screen or the Action button.
enum AppScreen: String, AppEnum {
    case qibla, tasbih, quran

    static let typeDisplayRepresentation: TypeDisplayRepresentation = "Screen"
    static let caseDisplayRepresentations: [AppScreen: DisplayRepresentation] = [
        .qibla: "Qibla",
        .tasbih: "Tasbih",
        .quran: "Qur'an",
    ]
}

/// Opens the app on a screen. Controls that open the app need the intent in both the app and the widgets;
/// it runs in the app, whose RootView switches to the screen left under `key`.
struct OpenScreenIntent: OpenIntent {
    static let title: LocalizedStringResource = "Open"
    static let key = "openScreen"

    @Parameter(title: "Screen")
    var target: AppScreen

    init() {}

    init(target: AppScreen) {
        self.target = target
    }

    @MainActor
    func perform() async throws -> some IntentResult {
        UserDefaults.standard.set(target.rawValue, forKey: Self.key)
        return .result()
    }
}
