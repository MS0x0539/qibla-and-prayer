import Foundation

/// Bookmarks and reading progress, kept on the iPhone (UserDefaults, read with @AppStorage by the views).
/// A page counts as read once it has been open for 10 seconds; a khatm is complete when all 604 pages are read.
enum QuranProgress {
    /// Bookmarked pages, "42,293".
    static let bookmarksKey = "quranBookmarks"
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

    static func toggleBookmark(_ page: Int, defaults: UserDefaults = .standard) {
        var bookmarks = pages(defaults.string(forKey: bookmarksKey) ?? "")
        if bookmarks.contains(page) { bookmarks.remove(page) } else { bookmarks.insert(page) }
        defaults.set(text(bookmarks), forKey: bookmarksKey)
    }

    /// Counts a page as read today and in the current khatm; the 604th page completes the khatm and starts a new one.
    static func markRead(_ page: Int, on date: Date = .now, defaults: UserDefaults = .standard) {
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
