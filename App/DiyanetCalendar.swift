import Foundation

/// Diyanet's Hijri calendar as it publishes it in its yearly lists of religious days ("Dini Günler",
/// vakithesaplama.diyanet.gov.tr), 1440-1457 AH (September 2018 to December 2035). Diyanet starts a month
/// once the crescent can be seen anywhere on Earth (8° elongation, 5° altitude, the 2016 Istanbul congress),
/// so it differs from Umm al-Qura by a day in 37 of these 215 months (Ramadan 1447 began on 19 February 2026,
/// not 18). Outside these years the app uses Umm al-Qura.
enum DiyanetCalendar {
    /// Each Hijri year: its 1 Muharram and its months' lengths (1 = 30 days, 0 = 29). 1457 is published up to
    /// 1 Dhu al-Qadah (31 December 2035).
    private static let years: [(year: Int, firstDay: (Int, Int, Int), lengths: String)] = [
        (1440, (2018, 9, 11), "010111010100"),
        (1441, (2019, 8, 31), "101011011010"),
        (1442, (2020, 8, 20), "010101011010"),
        (1443, (2021, 8, 9), "101010101011"),
        (1444, (2022, 7, 30), "011001010101"),
        (1445, (2023, 7, 19), "011010101001"),
        (1446, (2024, 7, 7), "011101100100"),
        (1447, (2025, 6, 26), "101101110010"),
        (1448, (2026, 6, 16), "010101110101"),
        (1449, (2027, 6, 6), "001010110110"),
        (1450, (2028, 5, 25), "100101010110"),
        (1451, (2029, 5, 14), "110010101010"),
        (1452, (2030, 5, 3), "111001010011"),
        (1453, (2031, 4, 23), "011010101010"),
        (1454, (2032, 4, 11), "101011010101"),
        (1455, (2033, 4, 1), "010011011010"),
        (1456, (2034, 3, 21), "100101011101"),
        (1457, (2035, 3, 11), "0100101011"),
    ]

    /// Every published month as (Hijri year, month, first day as days since 1970), plus where the table ends.
    private static let months: (starts: [(year: Int, month: Int, day: Int)], end: Int) = {
        var starts: [(year: Int, month: Int, day: Int)] = []
        var end = 0
        for entry in years {
            var day = daysSince1970(entry.firstDay.0, entry.firstDay.1, entry.firstDay.2)
            for (index, length) in entry.lengths.enumerated() {
                starts.append((entry.year, index + 1, day))
                day += length == "1" ? 30 : 29
            }
            end = day
        }
        return (starts, end)
    }()

    /// The Hijri year, month and day of a Gregorian date, or nil outside the published years.
    static func hijri(year: Int, month: Int, day: Int) -> (year: Int, month: Int, day: Int)? {
        let target = daysSince1970(year, month, day)
        guard let first = months.starts.first, target >= first.day, target < months.end,
              let current = months.starts.last(where: { $0.day <= target }) else { return nil }
        return (current.year, current.month, target - current.day + 1)
    }

    /// The Gregorian date of the first day of a Hijri month, or nil outside the published years.
    static func firstDay(year: Int, month: Int) -> (year: Int, month: Int, day: Int)? {
        months.starts.first { $0.year == year && $0.month == month }.map { gregorian($0.day) }
    }

    /// Days since 1970-01-01 of a Gregorian date (Howard Hinnant's days_from_civil).
    static func daysSince1970(_ year: Int, _ month: Int, _ day: Int) -> Int {
        let y = month <= 2 ? year - 1 : year
        let era = (y >= 0 ? y : y - 399) / 400
        let yearOfEra = y - era * 400
        let dayOfYear = (153 * ((month + 9) % 12) + 2) / 5 + day - 1
        let dayOfEra = yearOfEra * 365 + yearOfEra / 4 - yearOfEra / 100 + dayOfYear
        return era * 146097 + dayOfEra - 719468
    }

    /// The Gregorian date of a day count since 1970-01-01 (civil_from_days).
    static func gregorian(_ days: Int) -> (year: Int, month: Int, day: Int) {
        let z = days + 719468
        let era = (z >= 0 ? z : z - 146096) / 146097
        let dayOfEra = z - era * 146097
        let yearOfEra = (dayOfEra - dayOfEra / 1460 + dayOfEra / 36524 - dayOfEra / 146096) / 365
        let dayOfYear = dayOfEra - (365 * yearOfEra + yearOfEra / 4 - yearOfEra / 100)
        let mp = (5 * dayOfYear + 2) / 153
        let day = dayOfYear - (153 * mp + 2) / 5 + 1
        let month = mp < 10 ? mp + 3 : mp - 9
        return (yearOfEra + era * 400 + (month <= 2 ? 1 : 0), month, day)
    }
}
