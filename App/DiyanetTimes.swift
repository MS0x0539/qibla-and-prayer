import Foundation

/// Diyanet's own prayer times (namazvakitleri.diyanet.gov.tr), rebuilt from its official 2026 tables of 151 places:
/// 99.96% of the times to the minute, all within a minute (see docs/PLAN.md, "How the times were checked").
/// - The sun is taken once per date, at 0h UT, from Meeus' low-accuracy formulas.
/// - The temkin minutes, then a day and a night of at least 5 hours.
/// - In the countries of Diyanet's high-latitude project, the 2021 congress's estimate ("takdir") for İmsak and Yatsı,
///   with 20-minute gradual transitions; elsewhere the real times at 18° and 17°.
/// A line-by-line port of the reference model (diyanet.js); times are minutes after 0h UT of the date.
enum DiyanetTimes {
    private static let deg = Double.pi / 180
    private static let temkinGunes = -7.0
    private static let temkinOgle = 5.0
    private static let temkinIkindi = 4.0
    private static let temkinAksam = 7.0  // İmsak and Yatsı have none
    private static let sunriseAltitude = -0.833
    private static let fajrAltitude = -18.0
    private static let ishaAltitudeNew = -16.0
    private static let ishaAltitudeOld = -17.0
    /// Takdir İmsak: a third of the night "plus 2 degrees" (2/16 of it).
    private static let imsakFactor = 18.0 / 16
    /// Half of the 5-hour minimum day or night, in minutes.
    private static let minHalf = 150.0
    private static let gradual = 20.0
    /// Beyond this latitude the times are held around the anchor day (steps 5a and 5d).
    private static let capLatitude = 60.0
    private static let holdBefore = 92
    private static let holdAfter = 94
    private static let scanBefore = 182
    /// Diyanet's Turkey program, in minutes: every time but Öğle 1.39 s later, İkindi 1.10 s more, Öğle 0.15 s.
    private static let turkeyShift = 1.39 / 60
    private static let turkeyIkindi = 1.10 / 60
    private static let turkeyOgle = 0.15 / 60

    /// Countries with the 2021 congress rules: those of Diyanet's high-latitude project, reaching about 44.5° N.
    private static let newCriteriaCountries: Set<String> = [
        "US", "CA", "GL", "PM", "IS", "GB", "IE", "IM", "GG", "JE", "FO", "FR", "BE", "NL", "LU", "DE", "DK", "NO", "SJ",
        "SE", "FI", "AX", "EE", "LV", "LT", "PL", "CZ", "SK", "AT", "CH", "LI", "IT", "SM", "SI", "HR", "BA", "RS", "HU",
        "RO", "MD", "UA", "BY", "RU", "KZ", "MN", "CN",
    ]

    /// Without a country code: [latMin, latMax, lonMin, lonMax), half-open. Below 44.5° N a place has the new rules
    /// when it is in a new box and in no old box (old ones first). Approximate near borders.
    private static let newBoxes: [[Double]] = [
        [24.4, 44.5, -125.0, -66.9],   // contiguous USA and southern Canada
        [18.8, 22.3, -160.5, -154.7],  // Hawaii
        [41.3, 44.5, -1.8, 7.5],       // southern France
        [36.6, 44.5, 6.6, 18.6],       // Italy, Corsica
        [42.4, 44.5, 13.4, 19.6],      // Croatia, Bosnia
        [42.2, 44.5, 18.8, 23.0],      // Serbia
        [43.6, 44.5, 22.0, 29.8],      // southern Romania
        [44.3, 44.5, 32.4, 36.7],      // southern Crimea
        [41.1, 44.5, 36.5, 48.6],      // Russian Caucasus
        [40.5, 44.5, 46.4, 87.4],      // southern Kazakhstan
        [18.0, 44.5, 73.4, 135.1],     // China, Mongolia, Russian Primorye
    ]
    private static let oldBoxes: [[Double]] = [
        [19.5, 23.3, -85.0, -74.0],    // Cuba
        [20.9, 27.3, -79.4, -72.7],    // Bahamas
        [40.0, 42.75, -1.8, 2.0],      // Spain: Navarre, Aragon, Catalonia
        [40.0, 42.45, 2.0, 3.4],       // Spain: Girona
        [42.0, 43.25, -1.8, -0.7],     // Spain: Navarre north
        [43.72, 43.76, 7.40, 7.44],    // Monaco
        [42.42, 42.66, 1.40, 1.79],    // Andorra
        [41.89, 41.91, 12.44, 12.46],  // Vatican
        [35.8, 36.1, 14.1, 14.6],      // Malta
        [36.6, 37.6, 8.6, 11.2],       // northern Tunisia
        [39.6, 42.7, 19.0, 21.1],      // Albania
        [41.8, 43.6, 18.4, 20.4],      // Montenegro
        [41.85, 43.3, 20.0, 21.8],     // Kosovo
        [40.8, 42.4, 20.4, 23.0],      // North Macedonia
        [41.2, 44.22, 22.3, 27.3],     // Bulgaria (Danube border)
        [41.2, 43.75, 27.3, 28.7],     // Bulgaria (Dobruja border)
        [41.0, 42.85, 41.4, 46.8],     // Georgia
        [42.6, 43.6, 39.9, 41.4],      // Abkhazia
        [38.3, 41.95, 44.7, 50.9],     // Azerbaijan
        [38.8, 41.3, 43.4, 46.7],      // Armenia
        [37.1, 41.65, 55.9, 73.2],     // Uzbekistan, Turkmenistan, Tajikistan
        [41.65, 45.6, 55.9, 62.0],     // Karakalpakstan
        [41.65, 42.3, 62.0, 68.0],     // Navoiy north
        [36.9, 41.05, 52.4, 66.7],     // Turkmenistan
        [39.1, 40.4, 69.2, 74.0],      // Kyrgyzstan south-west
        [40.4, 41.6, 69.2, 76.5],      // Kyrgyzstan centre
        [41.6, 42.95, 70.9, 80.3],     // Kyrgyzstan north
        [36.7, 39.1, 73.2, 75.2],      // Tajik Pamir
        [8.0, 28.4, 73.4, 97.4],       // India, Nepal, Bhutan, Bangladesh
        [28.4, 30.5, 77.0, 81.0],      // Uttarakhand, western Nepal
        [28.4, 33.3, 73.4, 77.0],      // Punjab, Himachal, Jammu
        [33.3, 37.1, 71.0, 79.5],      // Kashmir, Ladakh, Gilgit-Baltistan
        [9.5, 27.0, 92.2, 97.6],       // Myanmar
        [9.5, 23.5, 97.6, 101.2],      // Myanmar east, northern Thailand
        [8.0, 22.4, 101.2, 108.6],     // Laos, Vietnam
        [37.6, 40.0, 124.2, 128.5],    // North Korea south
        [40.0, 41.6, 124.6, 129.0],    // North Korea centre
        [41.6, 42.4, 128.0, 130.7],    // North Korea north-east
        [33.0, 38.7, 124.5, 131.0],    // South Korea
        [21.8, 25.4, 119.3, 122.1],    // Taiwan
        [22.1, 22.53, 113.8, 114.45],  // Hong Kong
        [30.9, 34.8, 129.4, 135.5],    // Japan: Kyushu, Shikoku, western Honshu
        [33.4, 41.6, 135.5, 142.2],    // Japan: Honshu
        [41.3, 45.6, 139.3, 146.0],    // Japan: Hokkaido
    ]
    /// Mexico: south of this line (longitude, latitude) along the US border keeps the old rules.
    private static let mexicoBorder: [(longitude: Double, latitude: Double)] = [
        (-106.5, 31.78), (-104.4, 29.56), (-103.2, 28.98), (-102.4, 29.75), (-101.0, 29.4),
        (-100.0, 28.2), (-99.5, 27.5), (-98.5, 26.2), (-98.0, 26.05), (-97.5, 25.86), (-97.15, 25.85),
    ]

    /// One date, in minutes after 0h UT.
    private struct Day {
        let year: Int
        let month: Int
        let day: Int
        let declination: Double
        /// The reference of every time but Öğle: the transit, plus the Turkey program's seconds.
        let reference: Double
        let ogle: Double
        var gunes: Double
        var aksam: Double
        var imsak: Double
        var yatsi: Double
        let realImsak: Double
        let realYatsi: Double
        var ikindi: Double
        /// No real İmsak because the night stays light.
        let lightNight: Bool
        /// The printed İkindi differs from Öğle.
        var printedAsr: Bool
    }

    /// İmsak, Güneş, Öğle, İkindi, Akşam and Yatsı of a local date, in seconds since 1970, before Diyanet's rounding
    /// (half up to the minute). `country` picks the rules (ISO code; without one, coordinate boxes); the time zone
    /// lets İmsak be compared as a clock time. Where Diyanet prints no İmsak or Yatsı (the far south in summer,
    /// near the poles), the seventh of the night stands in, as in the app's other methods there.
    static func times(year: Int, month: Int, day: Int, latitude: Double, longitude: Double, country: String?,
                      asrFactor: Double, timeZone: TimeZone?) -> [Double]? {
        guard latitude.isFinite, longitude.isFinite, abs(latitude) <= 90,
              let midnight = PrayerEngine.utcMidnight(year: year, month: month, day: day) else { return nil }
        let lat = max(-89.9999, min(89.9999, latitude))  // the poles themselves have no meridian
        let lon = wrap180(longitude)
        let rules = criteriaFor(latitude: lat, longitude: lon, country: country)
        let jd = PrayerEngine.julianDay(year: year, month: month, day: day)
        let x: Day
        if rules.new {
            // One season: the calendar year in the north (anchor 21 June), July to June in the south (21 December).
            let date = civilDate(jd)
            let seasonYear = lat >= 0 ? date.year : (date.month >= 7 ? date.year : date.year - 1)
            let startMonth = lat >= 0 ? 1 : 7
            let start = PrayerEngine.julianDay(year: seasonYear, month: startMonth, day: 1)
            let count = Int((PrayerEngine.julianDay(year: seasonYear + 1, month: startMonth, day: 1) - start).rounded())
            var offset: ((Int, Int, Int) -> Double)? = nil
            if let timeZone {
                offset = { y, m, d in
                    let noon = (PrayerEngine.julianDay(year: y, month: m, day: d) - 2440587.5) * 86400 + 43200
                    return Double(timeZone.secondsFromGMT(for: Date(timeIntervalSince1970: noon))) / 60
                }
            }
            let days = season(latitude: lat, longitude: lon, start: start, count: count, offset: offset)
            let index = Int((jd - start).rounded())
            guard days.indices.contains(index) else { return nil }
            x = days[index]
        } else {
            x = baseDay(jd, latitude: lat, longitude: lon, ishaAltitude: ishaAltitudeOld, turkey: rules.turkey)
        }
        let asr = asrFactor == 1 ? x.ikindi : ikindiTime(x, latitude: lat, asrFactor: asrFactor, turkey: rules.turkey)
        var minutes = [x.imsak, x.gunes, x.ogle, asr, x.aksam, x.yatsi]
        let night = x.gunes + 1440 - x.aksam
        if !minutes[0].isFinite { minutes[0] = x.gunes - night / 7 }
        if !minutes[5].isFinite { minutes[5] = x.aksam + night / 7 }
        return minutes.map { midnight + $0 * 60 }
    }

    // MARK: - Calendar

    /// The Gregorian date of a Julian day at 0h UT (Meeus 7.3).
    private static func civilDate(_ jd: Double) -> (year: Int, month: Int, day: Int) {
        let z = (jd + 0.5).rounded(.down)
        let alpha = ((z - 1867216.25) / 36524.25).rounded(.down)
        let a = z + 1 + alpha - (alpha / 4).rounded(.down)
        let b = a + 1524
        let c = ((b - 122.1) / 365.25).rounded(.down)
        let dd = (365.25 * c).rounded(.down)
        let e = ((b - dd) / 30.6001).rounded(.down)
        let day = b - dd - (30.6001 * e).rounded(.down)
        let month = e < 14 ? e - 1 : e - 13
        return (Int(month > 2 ? c - 4716 : c - 4715), Int(month), Int(day))
    }

    // MARK: - Sun (step 1)

    /// Degrees to (-180, 180]; the remainder keeps the sign of x, like JavaScript's %.
    private static func wrap180(_ x: Double) -> Double {
        var r = x.truncatingRemainder(dividingBy: 360)
        if r > 180 { r -= 360 }
        if r <= -180 { r += 360 }
        return r
    }

    /// Declination (degrees) and equation of time (minutes) at the Julian day jd (0h UT of the date).
    private static func sun(_ jd: Double) -> (declination: Double, equationOfTime: Double) {
        let t = (jd - 2451545.0) / 36525.0
        let meanLongitude = 280.46646 + t * (36000.76983 + t * 0.0003032)  // not reduced
        let anomaly = 357.52911 + t * (35999.05029 - t * 0.0001537)
        let center1 = sin(anomaly * deg) * (1.914602 - t * (0.004817 + t * 0.000014))
        let center2 = sin(2 * anomaly * deg) * (0.019993 - t * 0.000101)
        let center3 = sin(3 * anomaly * deg) * 0.000289
        let lambda = meanLongitude + center1 + center2 + center3  // true geometric longitude
        let omega = 125.04 - 1934.136 * t
        let seconds = 21.448 - t * (46.815 + t * (0.00059 - t * 0.001813))
        let epsilon = 23 + (26 + seconds / 60) / 60 + 0.00256 * cos(omega * deg)  // true obliquity
        let declination = asin(sin(epsilon * deg) * sin(lambda * deg)) / deg
        let rightAscension = atan2(cos(epsilon * deg) * sin(lambda * deg), cos(lambda * deg)) / deg
        return (declination, 4 * wrap180(meanLongitude - rightAscension))
    }

    /// Half the day arc (minutes) from transit to the sun at altitude h; NaN if the sun never reaches h that day.
    private static func semiArc(_ h: Double, _ latitude: Double, _ declination: Double) -> Double {
        let c = (sin(h * deg) - sin(latitude * deg) * sin(declination * deg)) / (cos(latitude * deg) * cos(declination * deg))
        guard c >= -1 && c <= 1 else { return .nan }
        return 4 * acos(c) / deg
    }

    // MARK: - One date (steps 2 and 3)

    private static func baseDay(_ jd: Double, latitude: Double, longitude: Double, ishaAltitude: Double, turkey: Bool) -> Day {
        let s = sun(jd)
        let transit = 720 - 4 * longitude - s.equationOfTime
        let reference = turkey ? transit + turkeyShift : transit
        let ogle0 = transit + temkinOgle  // Öğle before the Turkey seconds
        let ogle = turkey ? ogle0 + turkeyOgle : ogle0
        let midnightAltitude = abs(latitude + s.declination) - 90  // the sun at lower culmination
        let h = semiArc(sunriseAltitude, latitude, s.declination)
        var gunes = reference - h + temkinGunes
        var aksam = reference + h + temkinAksam
        if !(h >= 0) {  // no sunrise or no sunset at all
            if midnightAltitude > sunriseAltitude {
                gunes = ogle0 - 720 + minHalf
                aksam = ogle0 + 720 - minHalf
            } else {
                gunes = ogle0 - minHalf
                aksam = ogle0 + minHalf
            }
        }
        // The night at least 5 hours, centred on Öğle + 12 h; the day at least 5 hours, centred on Öğle.
        if gunes < ogle0 - 720 + minHalf { gunes = ogle0 - 720 + minHalf }
        if aksam > ogle0 + 720 - minHalf { aksam = ogle0 + 720 - minHalf }
        if gunes > ogle0 - minHalf { gunes = ogle0 - minHalf }
        if aksam < ogle0 + minHalf { aksam = ogle0 + minHalf }
        let imsak = reference - semiArc(fajrAltitude, latitude, s.declination)
        let yatsi = reference + semiArc(ishaAltitude, latitude, s.declination)
        let date = civilDate(jd)
        var day = Day(
            year: date.year, month: date.month, day: date.day, declination: s.declination, reference: reference,
            ogle: ogle, gunes: gunes, aksam: aksam, imsak: imsak, yatsi: yatsi, realImsak: imsak, realYatsi: yatsi,
            ikindi: ogle, lightNight: midnightAltitude > fajrAltitude, printedAsr: false)
        day.ikindi = ikindiTime(day, latitude: latitude, asrFactor: 1, turkey: turkey)
        day.printedAsr = (day.ikindi + 0.5).rounded(.down) > (day.ogle + 0.5).rounded(.down)
        return day
    }

    /// İkindi: the shadow asrFactor times the object plus its noon shadow; Öğle when that time doesn't exist or isn't later.
    private static func ikindiTime(_ day: Day, latitude: Double, asrFactor: Double, turkey: Bool) -> Double {
        let noonZenith = abs(latitude - day.declination)
        guard noonZenith < 90 else { return day.ogle }  // the sun stays below the horizon at noon
        let h = atan(1 / (asrFactor + tan(noonZenith * deg))) / deg
        let asr = day.reference + semiArc(h, latitude, day.declination) + temkinIkindi + (turkey ? turkeyIkindi : 0)
        return asr > day.ogle ? asr : day.ogle  // NaN > x is false
    }

    // MARK: - Criteria (step 4)

    private static func inBox(_ latitude: Double, _ longitude: Double, _ box: [Double]) -> Bool {
        latitude >= box[0] && latitude < box[1] && longitude >= box[2] && longitude < box[3]
    }

    private static func southOfMexicoBorder(_ latitude: Double, _ longitude: Double) -> Bool {
        if latitude < 14.5 || longitude < -118.5 || longitude >= -86.7 { return false }
        if longitude < -114.8 { return latitude < 32.6 }
        if longitude < -106.5 { return latitude < 31.33 }
        if longitude < -97.15 {
            for i in 1..<mexicoBorder.count {
                let (x0, y0) = mexicoBorder[i - 1]
                let (x1, y1) = mexicoBorder[i]
                if longitude < x1 { return latitude < y0 + (y1 - y0) * (longitude - x0) / (x1 - x0) }
            }
        }
        return latitude < 25.85
    }

    /// The 2021 congress rules ("new") or the real times ("old"), and whether Diyanet's Turkey program applies.
    private static func criteriaFor(latitude: Double, longitude: Double, country: String?) -> (new: Bool, turkey: Bool) {
        let code = country?.uppercased() ?? ""
        if code == "TR" || code == "CY" { return (false, true) }
        if code.count == 2 { return (newCriteriaCountries.contains(code), false) }
        if latitude < 0 { return (false, false) }
        if latitude >= 44.5 {
            if latitude < 45.6 && longitude >= 139.3 && longitude < 146 { return (false, false) }  // northern Hokkaido
            return (true, false)
        }
        if southOfMexicoBorder(latitude, longitude) { return (false, false) }
        if oldBoxes.contains(where: { inBox(latitude, longitude, $0) }) { return (false, false) }
        if newBoxes.contains(where: { inBox(latitude, longitude, $0) }) { return (true, false) }
        return (false, false)
    }

    // MARK: - The new criteria: one season (step 5)

    private static func season(latitude: Double, longitude: Double, start: Double, count: Int,
                               offset: ((Int, Int, Int) -> Double)?) -> [Day] {
        var days = (0..<count).map {
            baseDay(start + Double($0), latitude: latitude, longitude: longitude, ishaAltitude: ishaAltitudeNew, turkey: false)
        }
        let anchorMonth = latitude >= 0 ? 6 : 12
        var anchor = 0
        while anchor < count - 1 && !(days[anchor].month == anchorMonth && days[anchor].day == 21) { anchor += 1 }
        let lo = max(0, anchor - holdBefore)
        let hi = min(count - 1, anchor + holdAfter)
        let capped = abs(latitude) > capLatitude

        // 5a. Holds on Güneş and Akşam, used by the takdir.
        if capped {
            for i in stride(from: anchor - 1, through: lo, by: -1) where days[i].gunes < days[i + 1].gunes {
                days[i].gunes = days[i + 1].gunes
            }
            for i in stride(from: lo + 1, through: anchor, by: 1) where days[i].aksam < days[i - 1].aksam {
                days[i].aksam = days[i - 1].aksam
            }
            for i in stride(from: anchor + 1, through: hi, by: 1) {
                if days[i].gunes < days[anchor].gunes { days[i].gunes = days[anchor].gunes }
                if days[i].aksam > days[anchor].aksam { days[i].aksam = days[anchor].aksam }
            }
        }

        // 5b. The core days.
        var c0 = anchor
        var c1 = anchor
        if !days[anchor].realImsak.isFinite && days[anchor].lightNight {
            while c0 > 0 && !days[c0 - 1].realImsak.isFinite && days[c0 - 1].lightNight { c0 -= 1 }
            while c1 < count - 1 && !days[c1 + 1].realImsak.isFinite && days[c1 + 1].lightNight { c1 += 1 }
            if c0 == 0 || !days[c0 - 1].realImsak.isFinite { return days }  // no dawn to take the ratio from (pole)
            let last = days[c0 - 1]
            let ratio = ((last.realImsak + 1440 - last.aksam) / 3) / (last.gunes + 1440 - last.aksam)
            for i in stride(from: c0, through: c1, by: 1) {
                let night = days[i].gunes + 1440 - days[i].aksam
                days[i].yatsi = days[i].aksam + ratio * night
                days[i].imsak = days[i].gunes - ratio * night * imsakFactor
            }
        } else {
            let third = (days[anchor].realImsak + 1440 - days[anchor].aksam) / 3
            if !(days[anchor].realYatsi > days[anchor].aksam + third) { return days }  // no takdir (south of ~44.39° N)
            days[anchor].yatsi = days[anchor].aksam + third
            days[anchor].imsak = days[anchor].gunes - third * imsakFactor
        }

        // 5c. Gradual transitions, Yatsı then İmsak.
        let scanFrom = max(0, anchor - scanBefore)
        for isYatsi in [true, false] {
            let e0 = isYatsi ? days[c0].yatsi : days[c0].imsak  // the first core value
            let e1 = isYatsi ? days[c1].yatsi : days[c1].imsak  // the last core value
            let threshold0 = isYatsi ? e0 - gradual : e0 + gradual
            let threshold1 = isYatsi ? e1 - gradual : e1 + gradual
            if c0 == c1 && !beyond(days[c0], threshold0, isYatsi: isYatsi, offset: offset) {
                // Dawn all year and not needed: the real time.
                if isYatsi { days[c0].yatsi = days[c0].realYatsi } else { days[c0].imsak = days[c0].realImsak }
                continue
            }
            var s0 = scanFrom
            while s0 < c0 && !beyond(days[s0], threshold0, isYatsi: isYatsi, offset: offset) { s0 += 1 }
            var s1 = c1
            while s1 < count - 1 && beyond(days[s1 + 1], threshold1, isYatsi: isYatsi, offset: offset) && days[s1 + 1].printedAsr {
                s1 += 1
            }
            if s0 == c0 { assign(&days[c0], isYatsi: isYatsi, threshold0) }
            for i in stride(from: s0, to: c0, by: 1) {
                assign(&days[i], isYatsi: isYatsi, threshold0 + (e0 - threshold0) * Double(i - s0) / Double(c0 - s0))
            }
            if s1 == c1 { assign(&days[c1], isYatsi: isYatsi, threshold1) }
            for i in stride(from: c1 + 1, through: s1, by: 1) {
                assign(&days[i], isYatsi: isYatsi, e1 + (threshold1 - e1) * Double(i - c1) / Double(s1 - c1))
            }
        }

        // 5d. Holds on the printed times.
        if capped {
            for i in stride(from: anchor + 1, through: hi, by: 1) {
                if days[i].gunes < days[i - 1].gunes { days[i].gunes = days[i - 1].gunes }
                if days[i].aksam > days[i - 1].aksam { days[i].aksam = days[i - 1].aksam }
                if days[i].imsak < days[i - 1].imsak { days[i].imsak = days[i - 1].imsak }
                if days[i].yatsi > days[i - 1].yatsi { days[i].yatsi = days[i - 1].yatsi }
            }
            for i in stride(from: anchor - 1, through: lo, by: -1) {
                if days[i].imsak < days[i + 1].imsak { days[i].imsak = days[i + 1].imsak }
                if days[i].yatsi > days[i + 1].yatsi { days[i].yatsi = days[i + 1].yatsi }
            }
        }
        return days
    }

    /// Whether the takdir is needed on a day: its real Yatsı later than the threshold, or its real İmsak earlier
    /// (İmsak as a clock time: just before local midnight it counts as late; step 6).
    private static func beyond(_ day: Day, _ threshold: Double, isYatsi: Bool, offset: ((Int, Int, Int) -> Double)?) -> Bool {
        var value = isYatsi ? day.realYatsi : day.realImsak
        guard value.isFinite else { return day.lightNight }  // no real time: only a light night counts
        if !isYatsi, let offset, value + offset(day.year, day.month, day.day) < 0 { value += 1440 }
        return isYatsi ? value > threshold : value < threshold
    }

    private static func assign(_ day: inout Day, isYatsi: Bool, _ value: Double) {
        if isYatsi { day.yatsi = value } else { day.imsak = value }
    }
}
