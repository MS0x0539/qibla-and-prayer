import Adhan
import CoreLocation
import Foundation
import Observation
import UserNotifications

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

    var displayNameWithCountry: String {
        guard let code = countryCode,
              let country = Locale.app.localizedString(forRegionCode: code),
              country != name else { return displayName }
        return "\(displayName), \(country)"
    }

    /// Degrees clockwise from true north.
    var qibla: Double { Qibla(coordinates: coordinates).direction }

    var kilometresToMecca: Double {
        CLLocation(latitude: latitude, longitude: longitude)
            .distance(from: CLLocation(latitude: 21.4225, longitude: 39.8262)) / 1000
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

@Observable
final class AppModel {
    var settings: AppSettings {
        didSet {
            AppLanguage.current = settings.language
            AppModel.save(settings, as: "settings")
            scheduleNotifications()
        }
    }

    /// The last place found by GPS, kept so the app also works offline and right at launch.
    var currentPlace: Place? {
        didSet {
            AppModel.save(currentPlace, as: "currentPlace")
            scheduleNotifications()
        }
    }

    /// Whether the first-run setup is done; "Run setup again" in Settings clears it.
    var onboarded: Bool {
        didSet { UserDefaults.standard.set(onboarded, forKey: "onboarded") }
    }

    var notificationStatus: UNAuthorizationStatus = .notDetermined
    /// Set when the user turns on a reminder while notifications are blocked in iPhone Settings.
    var showNotificationsOff = false
    let location = LocationService()
    @ObservationIgnored private var scheduleRun = 0
    @ObservationIgnored private let presenter = NotificationPresenter()

    init() {
        settings = AppModel.load(AppSettings.self, from: "settings") ?? .suggested()
        currentPlace = AppModel.load(Place.self, from: "currentPlace")
        // CI screenshots: `-skipOnboarding YES` treats the setup as done, `-appLanguage ar` picks a language.
        onboarded = UserDefaults.standard.bool(forKey: "onboarded")
            || UserDefaults.standard.bool(forKey: "skipOnboarding")
        if let forced = UserDefaults.standard.string(forKey: "appLanguage").flatMap(AppLanguage.init(rawValue:)) {
            settings.language = forced
        }
        AppLanguage.current = settings.language
        location.onPlace = { [weak self] place in
            self?.currentPlace = place
        }
        UNUserNotificationCenter.current().delegate = presenter
    }

    var place: Place? { settings.useCurrentLocation ? currentPlace : settings.city }

    /// The method and Asr suggested for the country the user is in (or the phone's region),
    /// their language and their school.
    var suggestion: AppSettings {
        let region = place?.countryCode ?? Locale.current.region?.identifier
        var suggestion = AppSettings.suggested(region: region, language: settings.language.code)
        switch settings.school {
        case .jafari:
            suggestion.method = region == "IR" ? .tehran : .jafari
            suggestion.asr = .standard
        // Diyanet's timetable uses the earlier Asr even though Turkey is Hanafi.
        case .hanafi: suggestion.asr = suggestion.method == .turkey ? .standard : .hanafi
        case .shafii, .maliki, .hanbali: suggestion.asr = .standard
        case .unsure: break
        }
        return suggestion
    }

    /// Sets the school and the Asr time that goes with it.
    func chooseSchool(_ school: School) {
        settings.school = school
        switch school {
        case .hanafi: settings.asr = settings.method == .turkey ? .standard : .hanafi
        case .shafii, .maliki, .hanbali, .jafari: settings.asr = .standard
        case .unsure: settings.asr = suggestion.asr
        }
    }

    func start() {
        location.start()
        scheduleNotifications()
    }

    func refresh() {
        location.refresh()
        scheduleNotifications()
    }

    func finishSetup() {
        onboarded = true
        start()
    }

    /// Back to the suggested settings (keeping the language), and the setup is shown again.
    func resetSetup() {
        var fresh = AppSettings.suggested(language: settings.language.code)
        fresh.language = settings.language
        settings = fresh
        onboarded = false
    }

    func useCurrentLocation() {
        settings.useCurrentLocation = true
        location.start()
    }

    func chooseCity(_ city: Place) {
        settings.city = city
        settings.useCurrentLocation = false
    }

    func toggleNotify(_ kind: PrayerKind) {
        if settings.notify.contains(kind) {
            settings.notify.remove(kind)
            return
        }
        settings.notify.insert(kind)
        switch notificationStatus {
        case .notDetermined: Task { await requestNotifications() }
        case .denied: showNotificationsOff = true
        default: break
        }
    }

    func requestNotifications() async {
        _ = try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound])
        scheduleNotifications()
    }

    /// A sample notification after 5 seconds, so people (and App Review) can see what to expect.
    func sendTestNotification() {
        Task { @MainActor in
            let center = UNUserNotificationCenter.current()
            if await center.notificationSettings().authorizationStatus == .notDetermined {
                _ = try? await center.requestAuthorization(options: [.alert, .sound])
            }
            let status = await center.notificationSettings().authorizationStatus
            self.notificationStatus = status
            guard status == .authorized || status == .provisional else {
                self.showNotificationsOff = true
                return
            }
            let content = UNMutableNotificationContent()
            content.title = String(localized: "Test notification", bundle: .app)
            content.body = String(localized: "Prayer notifications will look like this.", bundle: .app)
            content.sound = .default
            let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 5, repeats: false)
            try? await center.add(UNNotificationRequest(identifier: "test", content: content, trigger: trigger))
        }
    }

    func times(on date: Date, at place: Place) -> [PrayerTime]? {
        AppModel.compute(on: date, place: place, settings: settings)
    }

    func next(after now: Date, at place: Place) -> PrayerTime? {
        AppModel.next(after: now, place: place, settings: settings)
    }

    func month(containing date: Date, at place: Place) -> [DayTimes] {
        let calendar = place.calendar
        guard let month = calendar.dateInterval(of: .month, for: date) else { return [] }
        var days: [DayTimes] = []
        var day = month.start
        while day < month.end {
            if let times = times(on: day, at: place) {
                days.append(DayTimes(day: day, times: times))
            }
            guard let following = calendar.date(byAdding: .day, value: 1, to: day) else { break }
            day = following
        }
        return days
    }

    // MARK: - Calculation (static, so the tests can call it without a model)

    static func compute(on date: Date, place: Place, settings: AppSettings) -> [PrayerTime]? {
        let day = place.calendar.dateComponents([.year, .month, .day], from: date)
        var params = settings.method.parameters
        params.madhab = settings.asr == .hanafi ? .hanafi : .shafi
        // Above 48° twilight can last all night in summer; this is Adhan's recommendation there.
        let rule: HighLatitudeRule = abs(place.latitude) > 48 ? .seventhOfTheNight : .middleOfTheNight
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
        for offset in 0...1 {
            guard let day = place.calendar.date(byAdding: .day, value: offset, to: now),
                  let times = compute(on: day, place: place, settings: settings) else { continue }
            if let next = times.first(where: { $0.kind.isPrayer && $0.time > now }) {
                return next
            }
        }
        return nil
    }

    /// The prayers to notify about, soonest first, within iOS's limit of 64 pending notifications.
    static func upcoming(from now: Date, place: Place, settings: AppSettings) -> [PrayerTime] {
        let enabled = settings.notify.filter(\.isPrayer)
        guard !enabled.isEmpty else { return [] }
        // shortcut: covers the next 12+ days and is redone whenever the app opens; add a background
        // refresh task if people who rarely open the app report missing notifications.
        let days = min(30, 64 / enabled.count)
        var items: [PrayerTime] = []
        for offset in 0...days {
            guard let day = place.calendar.date(byAdding: .day, value: offset, to: now),
                  let times = compute(on: day, place: place, settings: settings) else { continue }
            items += times.filter { enabled.contains($0.kind) && $0.time > now }
        }
        return Array(items.prefix(64))
    }

    // MARK: - Notifications

    func scheduleNotifications() {
        scheduleRun += 1
        let run = scheduleRun
        let settings = settings
        let place = place
        Task { @MainActor in
            let center = UNUserNotificationCenter.current()
            let status = await center.notificationSettings().authorizationStatus
            self.notificationStatus = status
            guard status == .authorized || status == .provisional, run == self.scheduleRun else { return }
            center.removeAllPendingNotificationRequests()
            guard let place else { return }
            let now = Date()
            for item in AppModel.upcoming(from: now, place: place, settings: settings) {
                // A newer run (settings changed meanwhile) takes over.
                guard run == self.scheduleRun else { return }
                let title = item.kind.title(on: item.time, in: place.timeZone)
                let content = UNMutableNotificationContent()
                content.title = title
                content.body = String(localized: "Time for \(title).", bundle: .app)
                content.sound = .default
                let trigger = UNTimeIntervalNotificationTrigger(
                    timeInterval: max(1, item.time.timeIntervalSince(now)), repeats: false)
                let id = "\(item.kind.rawValue)-\(Int(item.time.timeIntervalSince1970))"
                try? await center.add(UNNotificationRequest(identifier: id, content: content, trigger: trigger))
            }
        }
    }

    // MARK: - Storage

    private static func save<Value: Encodable>(_ value: Value?, as key: String) {
        UserDefaults.standard.set(value.flatMap { try? JSONEncoder().encode($0) }, forKey: key)
    }

    private static func load<Value: Decodable>(_ type: Value.Type, from key: String) -> Value? {
        UserDefaults.standard.data(forKey: key).flatMap { try? JSONDecoder().decode(type, from: $0) }
    }
}

/// Shows prayer notifications as banners while the app is open, too (iOS hides them by default).
final class NotificationPresenter: NSObject, UNUserNotificationCenterDelegate {
    func userNotificationCenter(
        _ center: UNUserNotificationCenter, willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        [.banner, .list, .sound]
    }
}
