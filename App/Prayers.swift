import Adhan
import CoreLocation
import Foundation

/// Where to calculate for: the phone's location or a city the user picked.
struct Place: Codable, Equatable {
    var name: String
    var latitude: Double
    var longitude: Double
    var timeZoneID: String
    /// ISO country code (e.g. "NL"), used to suggest a calculation method.
    var countryCode: String? = nil

    var timeZone: TimeZone { TimeZone(identifier: timeZoneID) ?? .current }
    var displayName: String { name.isEmpty ? String(localized: "Current location", bundle: .app) : name }
    var coordinates: Coordinates { Coordinates(latitude: latitude, longitude: longitude) }
    var coordinate: CLLocationCoordinate2D { CLLocationCoordinate2D(latitude: latitude, longitude: longitude) }

    var displayNameWithCountry: String {
        guard let code = countryCode,
              let country = Locale.app.localizedString(forRegionCode: code),
              country != name else { return displayName }
        // Localized so Arabic gets its own comma ("أمستردام، هولندا").
        return String(localized: "\(displayName), \(country)", bundle: .app)
    }

    /// Degrees clockwise from true north.
    var qibla: Double { Qibla(coordinates: coordinates).direction }

    var kilometresToMecca: Double {
        CLLocation(latitude: latitude, longitude: longitude)
            .distance(from: CLLocation(latitude: Prayers.kaaba.latitude, longitude: Prayers.kaaba.longitude)) / 1000
    }

    /// The Gregorian calendar in this place's time zone, so "today" means today there.
    var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        return calendar
    }
}

struct PrayerTime: Identifiable, Equatable {
    let kind: PrayerKind
    let time: Date
    var id: PrayerKind { kind }
}

struct DayTimes: Identifiable {
    let day: Date
    let times: [PrayerTime]
    var id: Date { day }
}

/// The calculation itself, without the app around it, so Siri (and the tests) can use it too.
enum Prayers {
    /// The Kaaba in Mecca.
    static let kaaba = CLLocationCoordinate2D(latitude: 21.4225, longitude: 39.8262)

    static func compute(on date: Date, place: Place, settings: AppSettings) -> [PrayerTime]? {
        let day = place.calendar.dateComponents([.year, .month, .day], from: date)
        guard let year = day.year, let month = day.month, let dayOfMonth = day.day else { return nil }
        let rules = settings.method.rules(country: place.countryCode)
        // MUIS publishes one table for all of Singapore, computed at one point.
        var latitude = place.latitude
        var longitude = place.longitude
        if let point = rules.nationalPoint, place.countryCode == point.country {
            latitude = point.latitude
            longitude = point.longitude
        }
        // Above 48° twilight can last all night in summer; this is Adhan's recommendation there. France's
        // 12° is reached all year below ~54°N, and Adhan applies the 1/7 rule as a bound even then
        // (Paris, June: Fajr 04:03 would become 04:39), so it starts higher for that method.
        let limit = settings.method == .france ? 54.0 : 48.0
        let rule: HighLatitudeRule = abs(place.latitude) > limit ? .seventhOfTheNight : .middleOfTheNight
        guard let times = PrayerEngine.times(
            year: year, month: month, day: dayOfMonth, latitude: latitude, longitude: longitude, rules: rules,
            asrFactor: settings.asr == .hanafi ? 2 : 1, shafaq: settings.school?.shafaq ?? .general,
            highLatitudeRule: rule, ramadan: hijri(of: date, place: place, settings: settings).month == 9,
            adjustments: settings.adjustments, timeZone: place.timeZone)
        else { return nil }
        return zip(PrayerKind.allCases, times).map { PrayerTime(kind: $0, time: $1) }
    }

    /// The Hijri date (month, day, year) of a Gregorian day, moved by the user's offset: Diyanet's own
    /// calendar for the Diyanet method (in the years it publishes), Umm al-Qura otherwise.
    static func hijri(of day: Date, place: Place, offset: Int, diyanet: Bool = false) -> DateComponents {
        // Noon keeps daylight-saving changes from moving the day.
        let noon = place.calendar.date(bySettingHour: 12, minute: 0, second: 0, of: day) ?? day
        let shifted = place.calendar.date(byAdding: .day, value: offset, to: noon) ?? noon
        if diyanet {
            let parts = place.calendar.dateComponents([.year, .month, .day], from: shifted)
            if let year = parts.year, let month = parts.month, let dayOfMonth = parts.day,
               let date = DiyanetCalendar.hijri(year: year, month: month, day: dayOfMonth) {
                return DateComponents(year: date.year, month: date.month, day: date.day)
            }
        }
        var hijri = Calendar(identifier: .islamicUmmAlQura)
        hijri.timeZone = place.timeZone
        return hijri.dateComponents([.year, .month, .day], from: shifted)
    }

    /// The Hijri date in the calendar that goes with the user's method.
    static func hijri(of day: Date, place: Place, settings: AppSettings) -> DateComponents {
        hijri(of: day, place: place, offset: settings.hijriOffset, diyanet: settings.method == .turkey)
    }

    /// The next prayer after `now` (sunrise skipped); after Isha that is tomorrow's Fajr.
    static func next(after now: Date, place: Place, settings: AppSettings) -> PrayerTime? {
        // From yesterday: far north in summer Isha can fall after midnight (Trondheim, 21 June: 00:07).
        for offset in -1...1 {
            guard let day = place.calendar.date(byAdding: .day, value: offset, to: now),
                  let times = compute(on: day, place: place, settings: settings) else { continue }
            if let next = times.first(where: { $0.kind.isPrayer && $0.time > now }) {
                return next
            }
        }
        return nil
    }
}

/// Where the app keeps its settings, place and tasbih count, shared with the widgets through the App Group.
enum SharedStore {
    static let defaults = UserDefaults(suiteName: "group.org.psbv.qiblaandprayer") ?? .standard

    static func save<Value: Encodable>(_ value: Value?, as key: String) {
        defaults.set(value.flatMap { try? JSONEncoder().encode($0) }, forKey: key)
    }

    static func load<Value: Decodable>(_ type: Value.Type, from key: String) -> Value? {
        // The app's own defaults hold what versions before the widgets saved.
        (defaults.data(forKey: key) ?? UserDefaults.standard.data(forKey: key))
            .flatMap { try? JSONDecoder().decode(type, from: $0) }
    }

    /// The saved settings and the place they apply to; nil until the app has a place.
    static func saved() -> (settings: AppSettings, place: Place)? {
        guard let settings = load(AppSettings.self, from: "settings"),
              let place = settings.useCurrentLocation ? load(Place.self, from: "currentPlace") : settings.city
        else { return nil }
        return (settings, place)
    }
}
