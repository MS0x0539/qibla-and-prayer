import Foundation

/// Reading progress, kept on the iPhone (UserDefaults, read with @AppStorage by the views).
/// A page counts as read once it has been open for 10 seconds; a khatm is complete when all 604 pages are read.
enum QuranProgress {
    /// Pages read in the current khatm, "1,2,3".
    static let khatmPagesKey = "khatmPages"
    /// Khatms completed.
    static let khatmCountKey = "khatmCount"
    /// The pages read today, "2026-11-13:1,2,3".
    static let todayKey = "quranToday"
    /// Seconds a page must be open to count as read.
    static let readingSeconds = 10

    static func pages(_ text: String) -> Set<Int> {
        Set(text.split(separator: ",").compactMap { Int($0) })
    }

    static func text(_ pages: Set<Int>) -> String {
        pages.sorted().map(String.init).joined(separator: ",")
    }

    /// The page open in the reader.
    static let pageKey = "quranPage"
    /// All of them, and the page's look, in the App Group with the widgets.
    static let keys = [pageKey, khatmPagesKey, khatmCountKey, todayKey, QuranLook.nightKey, QuranLook.automaticKey]

    /// Counts a page as read today and in the current khatm; the 604th page completes the khatm and starts a new one.
    static func markRead(_ page: Int, on date: Date = .now, defaults: UserDefaults = SharedStore.defaults) {
        guard (1...Quran.pageCount).contains(page) else { return }
        var khatm = pages(defaults.string(forKey: khatmPagesKey) ?? "")
        khatm.insert(page)
        if khatm.count >= Quran.pageCount {
            defaults.set(defaults.integer(forKey: khatmCountKey) + 1, forKey: khatmCountKey)
            khatm = []
        }
        defaults.set(text(khatm), forKey: khatmPagesKey)
        let day = dayKey(date)
        var today = pagesRead(on: date, in: defaults.string(forKey: todayKey) ?? "")
        today.insert(page)
        defaults.set(day + ":" + text(today), forKey: todayKey)
    }

    /// The pages read on a day, from the stored "day:pages" (a value from another day counts as none).
    static func pagesRead(on date: Date, in stored: String) -> Set<Int> {
        let prefix = dayKey(date) + ":"
        return stored.hasPrefix(prefix) ? pages(String(stored.dropFirst(prefix.count))) : []
    }

    /// "2026-11-13" in the iPhone's calendar.
    static func dayKey(_ date: Date) -> String {
        let parts = Calendar(identifier: .gregorian).dateComponents(in: .current, from: date)
        return String(format: "%04d-%02d-%02d", parts.year ?? 0, parts.month ?? 0, parts.day ?? 0)
    }
}

/// The page's look: Night (the default), Paper, or Automatic (paper by day, night from Isha until sunrise). In the
/// App Group, so the Verse of the day widget looks like the reader.
enum QuranLook {
    static let nightKey = "quranNight"
    static let automaticKey = "quranAutoNight"

    /// Sunrise and Isha on a day at a place: where Automatic turns the page to paper, and to night.
    static func dayAndNight(on date: Date, place: Place, settings: AppSettings) -> (sunrise: Date, isha: Date)? {
        guard let times = Prayers.compute(on: date, place: place, settings: settings),
              let sunrise = times.first(where: { $0.kind == .sunrise })?.time,
              let isha = times.first(where: { $0.kind == .isha })?.time else { return nil }
        return (sunrise, isha)
    }

    /// Whether the page is dark at a moment; on Automatic without a place yet, it's paper.
    static func isNight(at date: Date, defaults: UserDefaults = SharedStore.defaults) -> Bool {
        guard defaults.bool(forKey: automaticKey) else { return defaults.object(forKey: nightKey) as? Bool ?? true }
        guard let saved = SharedStore.saved(),
              let day = dayAndNight(on: date, place: saved.place, settings: saved.settings) else { return false }
        return date >= day.isha || date < day.sunrise
    }

    /// The moments after `date` and before `end` when Automatic turns the page: today's sunrise and Isha to come.
    static func changes(after date: Date, before end: Date, defaults: UserDefaults = SharedStore.defaults) -> [Date] {
        guard defaults.bool(forKey: automaticKey), let saved = SharedStore.saved(),
              let day = dayAndNight(on: date, place: saved.place, settings: saved.settings) else { return [] }
        return [day.sunrise, day.isha].filter { $0 > date && $0 < end }.sorted()
    }
}
