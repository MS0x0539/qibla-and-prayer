import AppIntents
import Foundation

// Siri and the Shortcuts app: "When is Maghrib in Qibla & Prayer?" Answered from the saved settings
// and place, without opening the app.

extension PrayerKind: AppEnum {
    static let typeDisplayRepresentation: TypeDisplayRepresentation = "Prayer"
    static let caseDisplayRepresentations: [PrayerKind: DisplayRepresentation] = [
        .fajr: "Fajr",
        .sunrise: "Sunrise",
        .dhuhr: "Dhuhr",
        .asr: "Asr",
        .maghrib: "Maghrib",
        .isha: "Isha",
    ]
}

struct NextPrayerIntent: AppIntent {
    static let title: LocalizedStringResource = "Next prayer"

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        .result(dialog: "\(PrayerAnswers.next(after: .now))")
    }
}

struct PrayerTimeIntent: AppIntent {
    static let title: LocalizedStringResource = "Prayer time"

    @Parameter(title: "Prayer")
    var prayer: PrayerKind

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        .result(dialog: "\(PrayerAnswers.time(of: prayer, after: .now))")
    }
}

struct PrayerShortcuts: AppShortcutsProvider {
    // Other languages: <language>.lproj/AppShortcuts.strings, written by the strings script.
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: NextPrayerIntent(),
            phrases: [
                "When is the next prayer in \(.applicationName)",
                "Next prayer in \(.applicationName)",
            ],
            shortTitle: "Next prayer",
            systemImageName: "clock")
        AppShortcut(
            intent: PrayerTimeIntent(),
            phrases: [
                "When is \(\.$prayer) in \(.applicationName)",
                "\(\.$prayer) time in \(.applicationName)",
            ],
            shortTitle: "Prayer time",
            systemImageName: "sun.horizon")
    }
}

/// Siri's answers, in the app's language like the rest of the app.
@MainActor
enum PrayerAnswers {
    static func next(after now: Date) -> String {
        guard let saved = load() else { return noPlace }
        guard let next = Prayers.next(after: now, place: saved.place, settings: saved.settings) else {
            return cannotCalculate
        }
        let zone = saved.place.timeZone
        let title = next.kind.title(on: next.time, in: zone)
        let time = Formats.time(next.time, in: zone)
        return String(localized: "The next prayer is \(title), at \(time).", bundle: .app)
    }

    /// The next time this prayer begins: today's, or tomorrow's once today's has passed.
    static func time(of kind: PrayerKind, after now: Date) -> String {
        guard let saved = load() else { return noPlace }
        let place = saved.place
        for offset in 0...1 {
            guard let day = place.calendar.date(byAdding: .day, value: offset, to: now),
                  let item = Prayers.compute(on: day, place: place, settings: saved.settings)?.first(where: { $0.kind == kind }),
                  item.time > now else { continue }
            let title = item.kind.title(on: item.time, in: place.timeZone)
            let time = Formats.time(item.time, in: place.timeZone)
            return offset == 0
                ? String(localized: "\(title) is at \(time) today.", bundle: .app)
                : String(localized: "\(title) is at \(time) tomorrow.", bundle: .app)
        }
        return cannotCalculate
    }

    private static var noPlace: String {
        String(localized: "Open the app first, so it knows where you are.", bundle: .app)
    }

    private static var cannotCalculate: String {
        String(localized: "Prayer times can't be calculated for this place today. This can happen close to the poles.", bundle: .app)
    }

    /// The saved settings and place, with the text switched to the app's language as the app does.
    private static func load() -> (settings: AppSettings, place: Place)? {
        if let settings = SharedStore.load(AppSettings.self, from: "settings") {
            AppLanguage.current = settings.language
        }
        return SharedStore.saved()
    }
}
