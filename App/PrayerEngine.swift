import Adhan
import Foundation

/// How an authority computes its own published timetable, so the app's times match it to the minute.
/// Each method's rules come from comparing the app with a year or more of that authority's official
/// tables (see docs/PLAN.md, "How the times were checked").
struct MethodRules {
    enum Engine {
        /// Adhan's astronomy (Meeus): the authorities that compute with a full ephemeris.
        case adhan
        /// PrayTimes.org's low-precision sun, one pass from fixed guesses (moonsighting.com, Banuri Town).
        case prayTimes
        /// The same low-precision sun, taken once per day (MUIS, Singapore).
        case oncePerDay(daysAfterMidnightUTC: Double)
        /// Diyanet's own reckoning, high-latitude estimates included (see DiyanetTimes).
        case diyanet
    }

    /// Which declination sets the noon shadow that Asr adds to.
    enum AsrShadow {
        /// Adhan's own Asr: the declination at 0h UT and a single correction step.
        case adhan
        /// By definition: the declination at noon, solved exactly.
        case noon
        /// The declination at the moment of Asr itself (JAKIM).
        case atAsr
    }

    enum Rounding { case nearest, up, down }

    var engine = Engine.adhan
    var fajrAngle = 18.0
    var ishaAngle = 17.0
    /// Isha this many minutes after sunset instead of at an angle (0: by angle).
    var ishaInterval = 0
    /// Minutes added to `ishaInterval` in Ramadan (Umm al-Qura).
    var ramadanIshaExtra = 0
    /// Maghrib once the sun is this far below the horizon (Shia methods, Kemenag) instead of at sunset.
    var maghribAngle: Double? = nil
    /// Sunrise shown when the sun is this far below the horizon (Kemenag: 1°) instead of at 50'.
    var sunriseAngle: Double? = nil
    var asrShadow = AsrShadow.noon
    /// Seconds added to each time before rounding (the authority's precaution, "ihtiyat" or "temkin").
    var offsets: [PrayerKind: Double] = [:]
    var rounding = Rounding.nearest
    var sunriseRounding: Rounding? = nil
    /// Round from the exact moment; otherwise from whole seconds, as Adhan does.
    var exactSeconds = false
    /// The Moonsighting Committee's seasonal Fajr and Isha (prayTimes engine only).
    var moonsighting = false
    /// Minutes Maghrib moves in Ramadan (MUIS).
    var ramadanMaghribExtra = 0.0
    /// Sunrise and sunset depression for the low-precision engines (PrayTimes: 0.833°).
    var horizon = 0.833
    /// One published table for the whole country, computed at this point (MUIS).
    var nationalPoint: (country: String, latitude: Double, longitude: Double)? = nil
    /// KACST's own reckoning (Umm al-Qura): Fajr and Asr from one declination per day, the one at 00:00 local time
    /// of the next day, 15° an hour from the exact transit; Dhuhr and Maghrib exact (Adhan's engine only).
    var kacst = false
    /// A perpetual table computed on the sun of this year (Qatar Calendar House: 2006).
    var baseYear: Int? = nil
    /// A perpetual table over these years: the earliest Fajr and sunrise, the latest of the others (Awqaf, UAE).
    var perpetualYears: [Int] = []
    /// Where the times are for (ISO country code): Diyanet uses other rules per country.
    var country: String? = nil
}

/// The six times of a day as each authority computes them; Adhan does the astronomy for most methods.
enum PrayerEngine {
    /// Fajr, sunrise, Dhuhr, Asr, Maghrib and Isha for a local calendar date, rounded like the authority.
    /// nil when any of the six is missing (near the poles), where the JS reference keeps the others; with Adhan's
    /// astronomy also on the last day before polar night, because Adhan needs tomorrow's sunrise. Where the exact
    /// Asr doesn't exist (near polar night) Adhan's own Asr is kept.
    static func times(
        year: Int, month: Int, day: Int, latitude: Double, longitude: Double, rules: MethodRules,
        asrFactor: Double, shafaq: Shafaq, highLatitudeRule: HighLatitudeRule, ramadan: Bool,
        adjustments: [PrayerKind: Int] = [:], timeZone: TimeZone? = nil
    ) -> [Date]? {
        if !rules.perpetualYears.isEmpty {
            // A perpetual table (Awqaf, UAE): the same month-day in each year of the cycle, measured from 0:00 UTC of
            // that date; the earliest Fajr and sunrise and the latest of the others, put on the requested date.
            var inner = rules
            inner.perpetualYears = []
            var cycle: [[Double]] = []
            for cycleYear in rules.perpetualYears where month != 2 || day != 29 || isLeap(cycleYear) {
                guard let cycleMidnight = utcMidnight(year: cycleYear, month: month, day: day),
                      let computed = PrayerEngine.times(
                          year: cycleYear, month: month, day: day, latitude: latitude, longitude: longitude, rules: inner,
                          asrFactor: asrFactor, shafaq: shafaq, highLatitudeRule: highLatitudeRule, ramadan: ramadan,
                          adjustments: adjustments, timeZone: timeZone)
                else { return nil }
                cycle.append(computed.map { $0.timeIntervalSince1970 - cycleMidnight })
            }
            guard !cycle.isEmpty, let midnight = utcMidnight(year: year, month: month, day: day) else { return nil }
            return PrayerKind.allCases.enumerated().map { index, kind in
                let values = cycle.map { $0[index] }
                let picked = kind == .fajr || kind == .sunrise ? values.min() : values.max()
                return Date(timeIntervalSince1970: midnight + (picked ?? 0))
            }
        }
        // A perpetual table on one year's sun (Qatar): the same month-day in that year (Feb 29 as Mar 1 when it has
        // none), moved back to the date by whole days.
        var (sunYear, sunMonth, sunDay) = (year, month, day)
        if let baseYear = rules.baseYear {
            sunYear = baseYear
            if month == 2 && day == 29 && !isLeap(baseYear) { (sunMonth, sunDay) = (3, 1) }
        }
        guard let from = utcMidnight(year: sunYear, month: sunMonth, day: sunDay),
              let to = utcMidnight(year: year, month: month, day: day) else { return nil }
        let unrounded: [Double]?
        switch rules.engine {
        case .adhan:
            // KACST counts from local midnight: the place's offset from UTC, in hours, at noon UTC of the date.
            let utcOffset = timeZone.map { Double($0.secondsFromGMT(for: Date(timeIntervalSince1970: to + 43200))) / 3600 } ?? 0
            unrounded = adhanTimes(
                year: sunYear, month: sunMonth, day: sunDay, latitude: latitude, longitude: longitude, rules: rules,
                asrFactor: asrFactor, highLatitudeRule: highLatitudeRule, ramadan: ramadan, utcOffset: utcOffset)
        case .prayTimes:
            unrounded = lowPrecisionTimes(
                year: sunYear, month: sunMonth, day: sunDay, latitude: latitude, longitude: longitude, rules: rules,
                asrFactor: asrFactor, shafaq: shafaq, sunAt: nil, highLatitudeRule: highLatitudeRule, ramadan: ramadan)
        case .oncePerDay(let days):
            unrounded = lowPrecisionTimes(
                year: sunYear, month: sunMonth, day: sunDay, latitude: latitude, longitude: longitude, rules: rules,
                asrFactor: asrFactor, shafaq: shafaq, sunAt: days, highLatitudeRule: highLatitudeRule, ramadan: ramadan)
        case .diyanet:
            unrounded = DiyanetTimes.times(
                year: sunYear, month: sunMonth, day: sunDay, latitude: latitude, longitude: longitude,
                country: rules.country, asrFactor: asrFactor, timeZone: timeZone)
        }
        guard let unrounded, unrounded.allSatisfy({ $0.isFinite }) else { return nil }
        return zip(PrayerKind.allCases, unrounded).map { kind, seconds in
            let extra = (rules.offsets[kind] ?? 0) + Double((adjustments[kind] ?? 0) * 60)
            let rounding = kind == .sunrise ? rules.sunriseRounding ?? rules.rounding : rules.rounding
            return rounded(seconds + (to - from) + extra, rounding, exactSeconds: rules.exactSeconds)
        }
    }

    /// Seconds since 1970 to a whole minute.
    static func rounded(_ seconds: Double, _ rounding: MethodRules.Rounding, exactSeconds: Bool) -> Date {
        let whole = exactSeconds ? seconds : seconds.rounded(.down)
        let minutes: Double
        switch rounding {
        case .nearest: minutes = (whole / 60 + 0.5).rounded(.down)
        case .up: minutes = (whole / 60).rounded(.up)
        case .down: minutes = (whole / 60).rounded(.down)
        }
        return Date(timeIntervalSince1970: minutes * 60)
    }

    // MARK: - Adhan's astronomy

    private static func adhanTimes(
        year: Int, month: Int, day: Int, latitude: Double, longitude: Double, rules: MethodRules,
        asrFactor: Double, highLatitudeRule: HighLatitudeRule, ramadan: Bool, utcOffset: Double
    ) -> [Double]? {
        var params = CalculationMethod.other.params
        params.fajrAngle = rules.fajrAngle
        params.ishaAngle = rules.ishaAngle
        if rules.ishaInterval > 0 {
            params.ishaInterval = rules.ishaInterval + (ramadan ? rules.ramadanIshaExtra : 0)
        }
        params.maghribAngle = rules.maghribAngle
        params.madhab = asrFactor == 2 ? .hanafi : .shafi
        params.highLatitudeRule = highLatitudeRule
        params.rounding = .none
        let coordinates = Coordinates(latitude: latitude, longitude: longitude)
        let date = DateComponents(year: year, month: month, day: day)
        guard let times = PrayerTimes(coordinates: coordinates, date: date, calculationParameters: params) else { return nil }
        var result = [times.fajr, times.sunrise, times.dhuhr, times.asr, times.maghrib, times.isha].map(\.timeIntervalSince1970)
        if ramadan { result[4] += rules.ramadanMaghribExtra * 60 }
        if rules.asrShadow != .adhan,
           let asr = AdhanSun.asr(year: year, month: month, day: day, latitude: latitude, longitude: longitude,
                                  shadowFactor: asrFactor, declinationAtAsr: rules.asrShadow == .atAsr) {
            result[3] = asr.rounded(.down)
        }
        if let angle = rules.sunriseAngle {
            // Adhan's Fajr at that angle is the morning moment the sun is that far below the horizon.
            var morning = params
            morning.fajrAngle = angle
            guard let sunrise = PrayerTimes(coordinates: coordinates, date: date, calculationParameters: morning)?.fajr else {
                return nil
            }
            result[1] = sunrise.timeIntervalSince1970
        }
        if rules.kacst, let kacst = AdhanSun.kacst(
            year: year, month: month, day: day, latitude: latitude, longitude: longitude,
            fajrAngle: rules.fajrAngle, shadowFactor: asrFactor, utcOffset: utcOffset) {
            // Above 48° Adhan's seventh-of-the-night Fajr stays.
            if let fajr = kacst.fajr, abs(latitude) <= 48 { result[0] = fajr }
            if let asr = kacst.asr { result[3] = asr }
            result[2] = kacst.dhuhr
            if let sunset = kacst.sunset {
                result[4] = sunset
                result[5] = sunset + Double(params.ishaInterval * 60)
            }
        }
        return result
    }

    // MARK: - Low-precision sun (PrayTimes.org, US Naval Observatory formulas)

    /// The sun is taken once per event at a fixed guess of local mean time (PrayTimes' single pass), or,
    /// with `sunAt`, once per day that many days after 0h UT of the date.
    private static func lowPrecisionTimes(
        year: Int, month: Int, day: Int, latitude: Double, longitude: Double, rules: MethodRules,
        asrFactor: Double, shafaq: Shafaq, sunAt: Double?, highLatitudeRule: HighLatitudeRule, ramadan: Bool
    ) -> [Double]? {
        guard let midnight = utcMidnight(year: year, month: month, day: day) else { return nil }
        let jd = julianDay(year: year, month: month, day: day)
        func sun(_ guess: Double) -> (declination: Double, equation: Double) {
            lowPrecisionSun(julianDay: sunAt.map { jd + $0 } ?? jd - longitude / 360 + guess / 24)
        }
        func noon(_ guess: Double) -> Double { normalized(12 - sun(guess).equation, 24) }
        func angleTime(_ angle: Double, _ guess: Double, morning: Bool) -> Double {
            let declination = sun(guess).declination
            let t = acosDegrees((-sinDegrees(angle) - sinDegrees(declination) * sinDegrees(latitude))
                / (cosDegrees(declination) * cosDegrees(latitude))) / 15
            return morning ? noon(guess) - t : noon(guess) + t
        }
        let horizon = rules.horizon
        var fajr = angleTime(rules.fajrAngle, 5, morning: true)
        let sunrise = angleTime(horizon, 6, morning: true)
        let dhuhr = noon(12)
        let asrDeclination = sun(13).declination
        let asr = angleTime(-acotDegrees(asrFactor + tanDegrees(abs(latitude - asrDeclination))), 13, morning: false)
        let sunset = angleTime(horizon, 18, morning: false)
        var isha = angleTime(rules.ishaAngle, 18, morning: false)
        if rules.moonsighting {
            let days = daysSinceSolstice(year: year, month: month, day: day, latitude: latitude)
            var fajrs = [fajr, sunrise - moonsightingFajrMinutes(latitude: latitude, days: days) / 60]
            var ishas = [isha, sunset + moonsightingIshaMinutes(latitude: latitude, days: days, shafaq: shafaq) / 60]
            if abs(latitude) >= 55 {
                let night = normalized(sunrise - sunset, 24)
                fajrs.append(sunrise - night / 7)
                ishas.append(sunset + night / 7)
            }
            fajr = fajrs.filter { !$0.isNaN }.max() ?? .nan
            isha = ishas.filter { !$0.isNaN }.min() ?? .nan
        } else {
            // Where twilight lasts all night (summer, far north), Fajr and Isha are held within a share of the
            // night, as Adhan does for the other methods; at Karachi's and Singapore's latitudes it never applies.
            let night = normalized(sunrise - sunset, 24)
            let portion = highLatitudeRule == .seventhOfTheNight ? 1.0 / 7 : 1.0 / 2
            if fajr.isNaN || fajr < sunrise - portion * night { fajr = sunrise - portion * night }
            if isha.isNaN || isha > sunset + portion * night { isha = sunset + portion * night }
        }
        let maghrib = sunset + (ramadan ? rules.ramadanMaghribExtra : 0) / 60
        let hours = [fajr, sunrise, dhuhr, asr, maghrib, isha]
        return hours.map { midnight + ($0 - longitude / 15) * 3600 }
    }

    private static func lowPrecisionSun(julianDay jd: Double) -> (declination: Double, equation: Double) {
        let n = jd - 2451545.0
        let g = normalized(357.529 + 0.98560028 * n, 360)
        let q = normalized(280.459 + 0.98564736 * n, 360)
        let l = normalized(q + 1.915 * sinDegrees(g) + 0.020 * sinDegrees(2 * g), 360)
        let e = 23.439 - 0.00000036 * n
        let rightAscension = atan2(cosDegrees(e) * sinDegrees(l), cosDegrees(l)) * 180 / .pi / 15
        return (asin(sinDegrees(e) * sinDegrees(l)) * 180 / .pi, q / 15 - normalized(rightAscension, 24))
    }

    /// Moonsighting Committee: days since the winter solstice (Dec 21 north, Jun 21 south), which itself counts as 365/366.
    static func daysSinceSolstice(year: Int, month: Int, day: Int, latitude: Double) -> Double {
        let leap = (year % 4 == 0 && year % 100 != 0) || year % 400 == 0
        let length = leap ? 366 : 365
        let before = [0, 31, 59, 90, 120, 151, 181, 212, 243, 273, 304, 334]
        let dayOfYear = before[month - 1] + day + (month > 2 && leap ? 1 : 0)
        var days = latitude >= 0 ? dayOfYear + 10 : dayOfYear - (leap ? 173 : 172)
        if days > length { days -= length }
        if days <= 0 { days += length }
        return Double(days)
    }

    private static func seasonal(_ a: Double, _ b: Double, _ c: Double, _ d: Double, _ days: Double) -> Double {
        if days < 91 { return a + (b - a) / 91 * days }
        if days < 137 { return b + (c - b) / 46 * (days - 91) }
        if days < 183 { return c + (d - c) / 46 * (days - 137) }
        if days < 229 { return d + (c - d) / 46 * (days - 183) }
        if days < 275 { return c + (b - c) / 46 * (days - 229) }
        return b + (a - b) / 91 * (days - 275)
    }

    private static func moonsightingFajrMinutes(latitude: Double, days: Double) -> Double {
        let l = abs(latitude)
        return seasonal(75 + 28.65 / 55 * l, 75 + 19.44 / 55 * l, 75 + 32.74 / 55 * l, 75 + 48.10 / 55 * l, days)
    }

    private static func moonsightingIshaMinutes(latitude: Double, days: Double, shafaq: Shafaq) -> Double {
        let l = abs(latitude)
        switch shafaq {
        case .ahmer: return seasonal(62 + 17.40 / 55 * l, 62 - 7.16 / 55 * l, 62 + 5.12 / 55 * l, 62 + 19.44 / 55 * l, days)
        case .abyad: return seasonal(75 + 25.60 / 55 * l, 75 + 7.16 / 55 * l, 75 + 36.84 / 55 * l, 75 + 81.84 / 55 * l, days)
        case .general: return seasonal(75 + 25.60 / 55 * l, 75 + 2.050 / 55 * l, 75 - 9.210 / 55 * l, 75 + 6.140 / 55 * l, days)
        }
    }

    // MARK: - Shared helpers

    /// Seconds since 1970 at 0:00 UTC of the calendar date.
    static func utcMidnight(year: Int, month: Int, day: Int) -> Double? {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC") ?? .gmt
        return calendar.date(from: DateComponents(year: year, month: month, day: day))?.timeIntervalSince1970
    }

    /// Julian day at 0h UT (Meeus; the same formula as Adhan and PrayTimes).
    static func julianDay(year: Int, month: Int, day: Int) -> Double {
        let y = month > 2 ? year : year - 1
        let m = month > 2 ? month : month + 12
        let a = y / 100
        let b = 2 - a + a / 4
        return Double(Int(365.25 * Double(y + 4716))) + Double(Int(30.6001 * Double(m + 1))) + Double(day) + Double(b) - 1524.5
    }

    static func isLeap(_ year: Int) -> Bool { (year % 4 == 0 && year % 100 != 0) || year % 400 == 0 }
    static func normalized(_ value: Double, _ scale: Double) -> Double { value - scale * (value / scale).rounded(.down) }
    static func sinDegrees(_ x: Double) -> Double { sin(x * .pi / 180) }
    static func cosDegrees(_ x: Double) -> Double { cos(x * .pi / 180) }
    static func tanDegrees(_ x: Double) -> Double { tan(x * .pi / 180) }
    /// NaN outside -1...1: the sun never reaches that altitude that day.
    static func acosDegrees(_ x: Double) -> Double { acos(x) * 180 / .pi }
    static func acotDegrees(_ x: Double) -> Double { atan(1 / x) * 180 / .pi }
}

/// Adhan's sun (Meeus, "Astronomical Algorithms"), copied from Adhan 1.5 where it isn't public, to solve Asr
/// exactly: Adhan takes the declination at 0h UT for the noon shadow and corrects the hour angle with one step
/// of the horizon formula, which leaves Asr up to a minute off.
/// Adhan: Copyright (c) 2016 Batoul Apps, MIT License (full text in Settings → Acknowledgements).
enum AdhanSun {
    private struct Position {
        let declination: Double
        let rightAscension: Double
        let siderealTime: Double

        init(julianDay: Double) {
            let t = (julianDay - 2451545.0) / 36525
            let l0 = AdhanSun.unwound(280.4664567 + 36000.76983 * t + 0.0003032 * t * t)
            let lp = AdhanSun.unwound(218.3165 + 481267.8813 * t)
            let node = AdhanSun.unwound(125.04452 - 1934.136261 * t + 0.0020708 * t * t + t * t * t / 450000)
            let anomaly = AdhanSun.unwound(357.52911 + 35999.05029 * t - 0.0001537 * t * t)
            let center = (1.914602 - 0.004817 * t - 0.000014 * t * t) * PrayerEngine.sinDegrees(anomaly)
                + (0.019993 - 0.000101 * t) * PrayerEngine.sinDegrees(2 * anomaly) + 0.000289 * PrayerEngine.sinDegrees(3 * anomaly)
            let omega = 125.04 - 1934.136 * t
            let lambda = AdhanSun.unwound(l0 + center - 0.00569 - 0.00478 * PrayerEngine.sinDegrees(omega))
            let days = (t * 36525 + 2451545.0) - 2451545  // Adhan's JD - 2451545, bit for bit
            let mean = AdhanSun.unwound(280.46061837 + 360.98564736629 * days + 0.000387933 * t * t - t * t * t / 38710000)
            let nutationLongitude = (-17.2 / 3600) * PrayerEngine.sinDegrees(node) - (1.32 / 3600) * PrayerEngine.sinDegrees(2 * l0)
                - (0.23 / 3600) * PrayerEngine.sinDegrees(2 * lp) + (0.21 / 3600) * PrayerEngine.sinDegrees(2 * node)
            let nutationObliquity = (9.2 / 3600) * PrayerEngine.cosDegrees(node) + (0.57 / 3600) * PrayerEngine.cosDegrees(2 * l0)
                + (0.10 / 3600) * PrayerEngine.cosDegrees(2 * lp) - (0.09 / 3600) * PrayerEngine.cosDegrees(2 * node)
            let meanObliquity = 23.439291 - 0.013004167 * t - 0.0000001639 * t * t + 0.0000005036 * t * t * t
            let obliquity = meanObliquity + 0.00256 * PrayerEngine.cosDegrees(omega)
            declination = asin(PrayerEngine.sinDegrees(obliquity) * PrayerEngine.sinDegrees(lambda)) * 180 / .pi
            rightAscension = AdhanSun.unwound(atan2(
                PrayerEngine.cosDegrees(obliquity) * PrayerEngine.sinDegrees(lambda), PrayerEngine.cosDegrees(lambda)) * 180 / .pi)
            siderealTime = mean + nutationLongitude * 3600 * PrayerEngine.cosDegrees(meanObliquity + nutationObliquity) / 3600
        }
    }

    /// Adhan's sun for one date: the positions at 0h UT the day before, of and after, and its transit.
    private struct SolarDay {
        let midnight: Double
        let today: Position
        let yesterday: Position
        let tomorrow: Position
        /// Adhan's approximate and corrected transit, as fractions of the day.
        let approximateTransit: Double
        let transit: Double

        init?(year: Int, month: Int, day: Int, longitude: Double) {
            guard let midnight = PrayerEngine.utcMidnight(year: year, month: month, day: day) else { return nil }
            let jd = PrayerEngine.julianDay(year: year, month: month, day: day)
            let today = Position(julianDay: jd)
            let yesterday = Position(julianDay: jd - 1)
            let tomorrow = Position(julianDay: jd + 1)
            var m0 = PrayerEngine.normalized((today.rightAscension - longitude - today.siderealTime) / 360, 1)
            let expected = PrayerEngine.normalized((12 - longitude / 15) / 24, 1)
            if m0 - expected > 0.5 { m0 -= 1 } else if expected - m0 > 0.5 { m0 += 1 }
            let theta = AdhanSun.unwound(today.siderealTime + 360.985647 * m0)
            let alpha = AdhanSun.unwound(
                AdhanSun.interpolateAngles(today.rightAscension, yesterday.rightAscension, tomorrow.rightAscension, m0))
            var hourAngle = theta + longitude - alpha
            if hourAngle < -180 || hourAngle > 180 { hourAngle -= 360 * (hourAngle / 360).rounded() }
            self.midnight = midnight
            self.today = today
            self.yesterday = yesterday
            self.tomorrow = tomorrow
            approximateTransit = m0
            transit = m0 - hourAngle / 360
        }

        /// The declination at a fraction of the day, interpolated as Adhan does.
        func declination(_ fraction: Double) -> Double {
            AdhanSun.interpolate(today.declination, yesterday.declination, tomorrow.declination, fraction)
        }

        /// The afternoon moment (a fraction of the day) the sun is at altitude h0, Newton steps until they converge.
        func moment(_ h0: Double, latitude: Double, longitude: Double) -> Double? {
            let cosH0 = (PrayerEngine.sinDegrees(h0) - PrayerEngine.sinDegrees(latitude) * PrayerEngine.sinDegrees(today.declination))
                / (PrayerEngine.cosDegrees(latitude) * PrayerEngine.cosDegrees(today.declination))
            guard cosH0 >= -1 && cosH0 <= 1 else { return nil }
            var m = approximateTransit + acos(cosH0) * 180 / .pi / 360
            for _ in 0..<10 {
                let theta = AdhanSun.unwound(today.siderealTime + 360.985647 * m)
                let alpha = AdhanSun.unwound(
                    AdhanSun.interpolateAngles(today.rightAscension, yesterday.rightAscension, tomorrow.rightAscension, m))
                let delta = declination(m)
                let hour = theta + longitude - alpha
                let h = asin(PrayerEngine.sinDegrees(latitude) * PrayerEngine.sinDegrees(delta)
                    + PrayerEngine.cosDegrees(latitude) * PrayerEngine.cosDegrees(delta) * PrayerEngine.cosDegrees(hour)) * 180 / .pi
                let step = (h - h0) * PrayerEngine.cosDegrees(h)
                    / (360 * PrayerEngine.cosDegrees(delta) * PrayerEngine.cosDegrees(latitude) * PrayerEngine.sinDegrees(hour))
                m += step
                if abs(step) < 1e-10 { break }
            }
            return m
        }
    }

    /// Asr in seconds since 1970: the shadow `shadowFactor` times the object plus its noon shadow, with the
    /// declination at noon (or at Asr itself) and the hour angle solved to convergence. nil if it doesn't occur.
    static func asr(year: Int, month: Int, day: Int, latitude: Double, longitude: Double,
                    shadowFactor: Double, declinationAtAsr: Bool) -> Double? {
        guard let solar = SolarDay(year: year, month: month, day: day, longitude: longitude) else { return nil }
        func target(_ delta: Double) -> Double {
            PrayerEngine.acotDegrees(shadowFactor + PrayerEngine.tanDegrees(abs(latitude - delta)))
        }
        guard var m = solar.moment(target(solar.declination(solar.transit)), latitude: latitude, longitude: longitude)
        else { return nil }
        if declinationAtAsr {
            for _ in 0..<3 {
                guard let next = solar.moment(target(solar.declination(m)), latitude: latitude, longitude: longitude)
                else { return nil }
                m = next
            }
        }
        return solar.midnight + m * 86400
    }

    /// KACST's Umm al-Qura times in seconds since 1970: Fajr and Asr from the declination at 00:00 local time of
    /// the next day, 15° an hour from the exact transit, which is Dhuhr; Maghrib at the exact sunset (50').
    /// A time is nil where the sun doesn't reach it that day; utcOffset is in hours east of UTC.
    static func kacst(year: Int, month: Int, day: Int, latitude: Double, longitude: Double,
                      fajrAngle: Double, shadowFactor: Double, utcOffset: Double)
        -> (fajr: Double?, dhuhr: Double, asr: Double?, sunset: Double?)? {
        guard let solar = SolarDay(year: year, month: month, day: day, longitude: longitude) else { return nil }
        let delta = solar.declination(1 - utcOffset / 24)
        func hourAngle(_ h0: Double) -> Double? {
            let cosH = (PrayerEngine.sinDegrees(h0) - PrayerEngine.sinDegrees(latitude) * PrayerEngine.sinDegrees(delta))
                / (PrayerEngine.cosDegrees(latitude) * PrayerEngine.cosDegrees(delta))
            return cosH >= -1 && cosH <= 1 ? acos(cosH) * 180 / .pi : nil
        }
        let noon = solar.midnight + solar.transit * 86400
        let asrAltitude = PrayerEngine.acotDegrees(shadowFactor + PrayerEngine.tanDegrees(abs(latitude - delta)))
        let sunset = solar.moment(-50.0 / 60, latitude: latitude, longitude: longitude).map { solar.midnight + $0 * 86400 }
        return (hourAngle(-fajrAngle).map { noon - $0 * 240 }, noon, hourAngle(asrAltitude).map { noon + $0 * 240 }, sunset)
    }

    private static func unwound(_ degrees: Double) -> Double { PrayerEngine.normalized(degrees, 360) }

    private static func interpolate(_ y2: Double, _ y1: Double, _ y3: Double, _ n: Double) -> Double {
        let a = y2 - y1
        let b = y3 - y2
        return y2 + n / 2 * (a + b + n * (b - a))
    }

    private static func interpolateAngles(_ y2: Double, _ y1: Double, _ y3: Double, _ n: Double) -> Double {
        let a = unwound(y2 - y1)
        let b = unwound(y3 - y2)
        return y2 + n / 2 * (a + b + n * (b - a))
    }
}
