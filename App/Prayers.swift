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
        var params = settings.method.parameters
        params.madhab = settings.asr == .hanafi ? .hanafi : .shafi
        // Above 48° twilight can last all night in summer; this is Adhan's recommendation there. France's
        // 12° is reached all year below ~54°N, and Adhan applies the 1/7 rule as a bound even then
        // (Paris, June: Fajr 04:03 would become 04:39), so it starts higher for that method.
        let limit = settings.method == .france ? 54.0 : 48.0
        let rule: HighLatitudeRule = abs(place.latitude) > limit ? .seventhOfTheNight : .middleOfTheNight
        params.highLatitudeRule = rule
        // The user's minutes come on top of the method's own corrections.
        let minutes = settings.adjustments
        params.adjustments.fajr += minutes[.fajr] ?? 0
        params.adjustments.sunrise += minutes[.sunrise] ?? 0
        params.adjustments.dhuhr += minutes[.dhuhr] ?? 0
        params.adjustments.asr += minutes[.asr] ?? 0
        params.adjustments.maghrib += minutes[.maghrib] ?? 0
        params.adjustments.isha += minutes[.isha] ?? 0
        // Diyanet's own timetables outside Turkey use Isha at 16° (17° inside Turkey).
        // shortcut: Diyanet's summer estimates above 45°N (Netherlands, Germany) are not reproduced;
        // its Fajr and Isha there can differ by up to about 30 minutes in summer.
        if settings.method == .turkey, let country = place.countryCode, country != "TR" {
            params.ishaAngle = 16
        }
        // Umm al-Qura puts Isha 30 minutes later in Ramadan (2 hours after Maghrib).
        if settings.method == .ummAlQura,
           Calendar(identifier: .islamicUmmAlQura).dateComponents(in: place.timeZone, from: date).month == 9 {
            params.adjustments.isha += 30
        }
        guard let times = PrayerTimes(coordinates: place.coordinates, date: day, calculationParameters: params) else {
            return nil
        }
        return [
            PrayerTime(kind: .fajr, time: times.fajr),
            PrayerTime(kind: .sunrise, time: times.sunrise),
            PrayerTime(kind: .dhuhr, time: times.dhuhr),
            PrayerTime(kind: .asr, time: times.asr),
            PrayerTime(kind: .maghrib, time: times.maghrib),
            PrayerTime(kind: .isha, time: times.isha),
        ]
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

/// Where the app keeps its settings and place, shared with the widgets through the App Group.
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
