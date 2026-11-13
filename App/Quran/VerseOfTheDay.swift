import Foundation

/// A verse for each day, the same for everyone on that day: well-known verses that stand on their own, in turn.
enum VerseOfTheDay {
    /// Surah and verse.
    static let references: [(Int, Int)] = [
        (1, 2), (2, 45), (2, 115), (2, 152), (2, 153), (2, 156), (2, 186), (2, 201), (3, 8), (3, 139), (3, 190),
        (6, 162), (7, 23), (9, 51), (13, 28), (14, 7), (15, 9), (16, 128), (17, 80), (18, 10), (20, 25), (20, 46),
        (21, 83), (21, 87), (23, 118), (25, 74), (29, 69), (33, 41), (39, 53), (40, 60), (49, 10), (50, 16),
        (51, 56), (55, 13), (55, 26), (59, 22), (67, 1), (93, 3), (93, 5), (94, 5), (94, 6), (103, 2), (112, 1),
    ]

    /// The verse's index in the whole Qur'an for a day.
    static func index(on date: Date, calendar: Calendar = .current) -> Int {
        let day = calendar.ordinality(of: .day, in: .era, for: date) ?? 0
        let (surah, verse) = references[day % references.count]
        return Quran.shared.index(surah: surah, verse: verse)
    }
}
