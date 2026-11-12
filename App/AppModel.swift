import ActivityKit
import BackgroundTasks
import CoreLocation
import Foundation
import Observation
import UserNotifications
import WidgetKit

/// One notification to schedule: a prayer, a reminder before one, Jumu'ah, suhoor or iftar.
struct PlannedNotification: Equatable {
    let id: String
    let date: Date
    let title: String
    let body: String
}

@Observable
final class AppModel {
    var settings: AppSettings {
        didSet {
            AppLanguage.current = settings.language
            SharedStore.save(settings, as: "settings")
            // The saved city name is in the old language: look it up again.
            if oldValue.language != settings.language { location.lookUpAgain() }
            scheduleNotifications()
            if oldValue != settings { WidgetCenter.shared.reloadAllTimelines() }
        }
    }

    /// The last place found by GPS, kept so the app also works offline and right at launch.
    var currentPlace: Place? {
        didSet {
            SharedStore.save(currentPlace, as: "currentPlace")
            scheduleNotifications()
            if oldValue != currentPlace { WidgetCenter.shared.reloadAllTimelines() }
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

    /// The background task that tops up the notifications; also listed in Info.plist.
    static let refreshTask = "org.psbv.qiblaandprayer.refresh"

    init() {
        settings = SharedStore.load(AppSettings.self, from: "settings") ?? .suggested()
        currentPlace = SharedStore.load(Place.self, from: "currentPlace")
        // CI screenshots: `-skipOnboarding YES` treats the setup as done, `-appLanguage ar` picks a language.
        onboarded = UserDefaults.standard.bool(forKey: "onboarded")
            || UserDefaults.standard.bool(forKey: "skipOnboarding")
        if let forced = UserDefaults.standard.string(forKey: "appLanguage").flatMap(AppLanguage.init(rawValue:)) {
            settings.language = forced
        }
        AppLanguage.current = settings.language
        location.onPlace = { [weak self] place in
            guard let self else { return }
            // A failed lookup (offline, rate-limited) has no name, country or time zone. Near the last
            // place keep those, so the name and Diyanet's Isha rule abroad don't change while offline.
            var place = place
            if place.countryCode == nil, let previous = self.currentPlace,
               CLLocation(latitude: previous.latitude, longitude: previous.longitude)
                   .distance(from: CLLocation(latitude: place.latitude, longitude: place.longitude)) < 50_000 {
                place.name = previous.name
                place.timeZoneID = previous.timeZoneID
                place.countryCode = previous.countryCode
            }
            self.currentPlace = place
        }
        UNUserNotificationCenter.current().delegate = presenter
    }

    var place: Place? { settings.useCurrentLocation ? currentPlace : settings.city }

    /// The Qibla is measured from where the phone is: the GPS place whenever location is allowed,
    /// also when the prayer times are for a chosen city.
    var qiblaPlace: Place? { location.isAuthorized ? currentPlace ?? place : place }

    /// The method and Asr suggested for the country the user is in (or the phone's region),
    /// their language and their school.
    var suggestion: AppSettings {
        let region = place?.countryCode ?? Locale.current.region?.identifier
        var suggestion = AppSettings.suggested(region: region, language: settings.language.code)
        switch settings.school {
        case .jafari?:
            suggestion.method = region == "IR" ? .tehran : .jafari
            suggestion.asr = .standard
        // Diyanet's timetable uses the earlier Asr even though Turkey is Hanafi.
        case .hanafi?: suggestion.asr = suggestion.method == .turkey ? .standard : .hanafi
        case .shafii?, .maliki?, .hanbali?: suggestion.asr = .standard
        case nil: break
        }
        return suggestion
    }

    /// Sets the school and the Asr time that goes with it.
    func chooseSchool(_ school: School) {
        settings.school = school
        switch school {
        case .hanafi: settings.asr = settings.method == .turkey ? .standard : .hanafi
        case .shafii, .maliki, .hanbali, .jafari: settings.asr = .standard
        }
    }

    func start() {
        // Someone who chose a city ("Works without location access") is not asked for location;
        // turning on "Use current location" asks then (useCurrentLocation() / Settings onChange).
        if settings.useCurrentLocation { location.start() } else { location.refresh() }
        scheduleNotifications()
    }

    func refresh() {
        location.refresh()
        scheduleNotifications()
        endPastCountdowns()
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
        } else {
            settings.notify.insert(kind)
            notificationsWanted()
        }
    }

    /// After switching a reminder on: ask for permission, or explain that it's blocked in Settings.
    func notificationsWanted() {
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

    // MARK: - Iftar countdown (Live Activity)

    var liveActivitiesEnabled: Bool { ActivityAuthorizationInfo().areActivitiesEnabled }

    /// Today's iftar (Maghrib) as a countdown on the Lock Screen and in the Dynamic Island.
    func startIftarCountdown() {
        guard let place, let maghrib = times(on: .now, at: place)?[4].time, maghrib > .now else { return }
        let attributes = IftarAttributes(
            title: String(localized: "Iftar", bundle: .app),
            place: place.displayName,
            time: Formats.time(maghrib, in: place.timeZone),
            arrived: String(localized: "Time for iftar.", bundle: .app))
        Task {
            // One countdown at a time.
            for activity in Activity<IftarAttributes>.activities {
                await activity.end(nil, dismissalPolicy: .immediate)
            }
            _ = try? Activity.request(
                attributes: attributes,
                content: ActivityContent(state: IftarAttributes.ContentState(iftar: maghrib), staleDate: maghrib),
                pushType: nil)
        }
    }

    /// Clears countdowns whose iftar is more than half an hour ago, when the app comes back.
    private func endPastCountdowns() {
        Task {
            for activity in Activity<IftarAttributes>.activities
            where activity.content.state.iftar < Date.now.addingTimeInterval(-1_800) {
                await activity.end(nil, dismissalPolicy: .immediate)
            }
        }
    }

    func times(on date: Date, at place: Place) -> [PrayerTime]? {
        Prayers.compute(on: date, place: place, settings: settings)
    }

    func next(after now: Date, at place: Place) -> PrayerTime? {
        Prayers.next(after: now, place: place, settings: settings)
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

    // MARK: - Notifications

    /// Everything to notify about, soonest first, within iOS's limit of 64 pending notifications.
    static func planned(from now: Date, place: Place, settings: AppSettings) -> [PlannedNotification] {
        let zone = place.timeZone
        let calendar = place.calendar
        let before = settings.reminderMinutes
        var items: [PlannedNotification] = []
        // From yesterday: far north Isha can fall after midnight. The limit cuts the list, not the days.
        for offset in -1...30 {
            guard let day = calendar.date(byAdding: .day, value: offset, to: now),
                  let times = Prayers.compute(on: day, place: place, settings: settings) else { continue }
            let ramadan = settings.ramadanReminders
                && hijri(of: day, place: place, offset: settings.hijriOffset).month == 9
            for item in times where item.kind.isPrayer {
                let title = item.kind.title(on: item.time, in: zone)
                let time = Formats.time(item.time, in: zone)
                let stamp = Int(item.time.timeIntervalSince1970)
                func add(_ kind: String, _ date: Date, _ title: String, _ body: String) {
                    items.append(PlannedNotification(id: "\(kind)-\(stamp)", date: date, title: title, body: body))
                }
                if settings.notify.contains(item.kind) {
                    add(item.kind.rawValue, item.time, title, ramadan && item.kind == .maghrib
                        ? String(localized: "Time for \(title) and iftar.", bundle: .app)
                        : String(localized: "Time for \(title).", bundle: .app))
                    if before > 0 {
                        add("before-\(item.kind.rawValue)", item.time.addingTimeInterval(Double(-before * 60)), title,
                            String(localized: "\(title) begins in \(before) minutes, at \(time).", bundle: .app))
                    }
                }
                if settings.jumuahReminder && item.kind == .dhuhr && calendar.component(.weekday, from: item.time) == 6 {
                    add("jumuah", item.time.addingTimeInterval(-3600), title,
                        String(localized: "Jumu'ah is in an hour, at \(time).", bundle: .app))
                }
                if ramadan && item.kind == .fajr {
                    add("suhoor", item.time.addingTimeInterval(-30 * 60), String(localized: "Suhoor", bundle: .app),
                        String(localized: "Suhoor ends in 30 minutes, at \(time).", bundle: .app))
                }
                if ramadan && item.kind == .maghrib && !settings.notify.contains(.maghrib) {
                    add("iftar", item.time, String(localized: "Iftar", bundle: .app),
                        String(localized: "Time for iftar.", bundle: .app))
                }
            }
        }
        return Array(items.filter { $0.date > now }.sorted { $0.date < $1.date }.prefix(64))
    }

    func scheduleNotifications() {
        Task { await rescheduleNotifications() }
    }

    /// Replaces the pending notifications with the planned ones. A newer call takes over from an older one.
    @MainActor
    func rescheduleNotifications() async {
        scheduleRun += 1
        let run = scheduleRun
        let settings = settings
        let place = place
        let center = UNUserNotificationCenter.current()
        let status = await center.notificationSettings().authorizationStatus
        notificationStatus = status
        guard status == .authorized || status == .provisional, run == scheduleRun else { return }
        // Keep a pending test notification; everything else is rebuilt below.
        let pending = await center.pendingNotificationRequests().map(\.identifier)
        guard run == scheduleRun else { return }
        center.removePendingNotificationRequests(withIdentifiers: pending.filter { $0 != "test" })
        guard let place else { return }
        let now = Date()
        for item in AppModel.planned(from: now, place: place, settings: settings) {
            // A newer run (settings changed meanwhile) takes over.
            guard run == scheduleRun else { return }
            let content = UNMutableNotificationContent()
            content.title = item.title
            content.body = item.body
            content.sound = .default
            let trigger = UNTimeIntervalNotificationTrigger(
                timeInterval: max(1, item.date.timeIntervalSince(now)), repeats: false)
            try? await center.add(UNNotificationRequest(identifier: item.id, content: content, trigger: trigger))
        }
    }

    /// Asks iOS to wake the app now and then, so notifications keep coming for people who mostly
    /// use Siri or rarely open the app: at most 64 can wait, about a week's worth with reminders on.
    func scheduleBackgroundRefresh() {
        let request = BGAppRefreshTaskRequest(identifier: AppModel.refreshTask)
        request.earliestBeginDate = Date(timeIntervalSinceNow: 12 * 3600)
        try? BGTaskScheduler.shared.submit(request)
    }

    func backgroundRefresh() async {
        scheduleBackgroundRefresh()
        await rescheduleNotifications()
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
