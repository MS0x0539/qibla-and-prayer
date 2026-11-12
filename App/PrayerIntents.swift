import AppIntents
import Foundation

// Siri and the Shortcuts app: "When is Maghrib in Qibla & Prayer?" Answered from the saved settings
// and place, without opening the app.

extension PrayerKind: AppEnum {
    static let typeDisplayRepresentation: TypeDisplayRepresentation = "Prayer"
    static let caseDisplayRepresentations: [PrayerKind: DisplayRepresentation] = [
        // Other spellings Siri may hear.
        .fajr: DisplayRepresentation(title: "Fajr", synonyms: ["Subh", "Fadjr"]),
        .sunrise: "Sunrise",
        .dhuhr: DisplayRepresentation(title: "Dhuhr", synonyms: ["Zuhr", "Duhr", "Zohr"]),
        .asr: "Asr",
        .maghrib: DisplayRepresentation(title: "Maghrib", synonyms: ["Magrib", "Maghreb"]),
        .isha: DisplayRepresentation(title: "Isha", synonyms: ["Ishaa", "Esha"]),
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

/// Siri's answers, in the iPhone's language: Siri listens and speaks in that one, whatever language
/// is picked inside the app.
@MainActor
enum PrayerAnswers {
    static func next(after now: Date) -> String {
        inSystemLanguage { nextAnswer(after: now) }
    }

    static func time(of kind: PrayerKind, after now: Date) -> String {
        inSystemLanguage { timeAnswer(of: kind, after: now) }
    }

    /// Runs on the main actor like the app's views, so they never see the switched language.
    private static func inSystemLanguage(_ answer: () -> String) -> String {
        let chosen = AppLanguage.current
        AppLanguage.current = .system
        defer { AppLanguage.current = chosen }
        return answer()
    }

    private static func nextAnswer(after now: Date) -> String {
        guard let saved = SharedStore.saved() else { return noPlace }
        guard let next = Prayers.next(after: now, place: saved.place, settings: saved.settings) else {
            return cannotCalculate
        }
        let zone = saved.place.timeZone
        let title = next.kind.title(on: next.time, in: zone)
        let time = Formats.time(next.time, in: zone)
        return String(localized: "The next prayer is \(title), at \(time).", bundle: .app)
    }

    /// The next time this prayer begins: today's, or tomorrow's once today's has passed.
    private static func timeAnswer(of kind: PrayerKind, after now: Date) -> String {
        guard let saved = SharedStore.saved() else { return noPlace }
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
}
