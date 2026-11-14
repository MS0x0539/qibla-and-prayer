import Foundation

/// The prayers ticked as prayed, per day, kept only on this iPhone (in the App Group, for a widget later).
/// Stored as "2026-11-14:fajr,dhuhr;2026-11-15:fajr", oldest first; a little over a year is kept.
enum Prayed {
    static let key = "prayedDays"
    /// The last day whose unticked prayers Home asked about ("2026-11-14"), so it asks once.
    static let reviewedKey = "prayedReviewed"
    static let prayers = PrayerKind.allCases.filter(\.isPrayer)

    static func parse(_ text: String) -> [String: Set<PrayerKind>] {
        var days: [String: Set<PrayerKind>] = [:]
        for entry in text.split(separator: ";") {
            let parts = entry.split(separator: ":", maxSplits: 1)
            guard parts.count == 2 else { continue }
            let kinds = parts[1].split(separator: ",").compactMap { PrayerKind(rawValue: String($0)) }.filter(\.isPrayer)
            if !kinds.isEmpty { days[String(parts[0]), default: []].formUnion(kinds) }
        }
        return days
    }

    static func format(_ days: [String: Set<PrayerKind>]) -> String {
        days.compactMap { day, kinds -> (day: String, names: String)? in
            let names = prayers.filter(kinds.contains).map(\.rawValue)
            return names.isEmpty ? nil : (day, names.joined(separator: ","))
        }
        .sorted { $0.day < $1.day }
        .suffix(400)
        .map { "\($0.day):\($0.names)" }
        .joined(separator: ";")
    }

    /// `text` with these prayers of one day ticked, or unticked.
    static func setting(_ kinds: [PrayerKind], on day: String, to prayed: Bool, in text: String) -> String {
        var days = parse(text)
        if prayed { days[day, default: []].formUnion(kinds) } else { days[day]?.subtract(kinds) }
        return format(days)
    }

    /// "2026-11-14": a day in the place's own calendar.
    static func dayKey(_ date: Date, in calendar: Calendar) -> String {
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", parts.year ?? 0, parts.month ?? 0, parts.day ?? 0)
    }

    /// Adds these prayers to the missed (qada) prayers kept in Menu → Missed prayers.
    static func addToMissed(_ kinds: [PrayerKind]) {
        for kind in kinds {
            let key = "qada-\(kind.rawValue)"
            UserDefaults.standard.set(UserDefaults.standard.integer(forKey: key) + 1, forKey: key)
        }
    }
}

extension AppModel {
    /// The day whose prayers are prayed now: from its Fajr until the next day's, so an Isha prayed after midnight
    /// (in summer, far north) still counts for the day it belongs to.
    func prayerDay(at now: Date, place: Place) -> Date {
        let calendar = place.calendar
        let today = calendar.startOfDay(for: now)
        if let fajr = times(on: now, at: place)?.first(where: { $0.kind == .fajr })?.time, now < fajr,
           let yesterday = calendar.date(byAdding: .day, value: -1, to: today) {
            return yesterday
        }
        return today
    }
}
