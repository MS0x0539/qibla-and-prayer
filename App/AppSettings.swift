import Adhan
import Foundation

enum PrayerKind: String, CaseIterable, Codable, Identifiable, Sendable {
    case fajr, sunrise, dhuhr, asr, maghrib, isha

    var id: String { rawValue }

    /// Sunrise ends the Fajr time but is not a prayer itself.
    var isPrayer: Bool { self != .sunrise }

    var title: String {
        switch self {
        case .fajr: String(localized: "Fajr", bundle: .app)
        case .sunrise: String(localized: "Sunrise", bundle: .app)
        case .dhuhr: String(localized: "Dhuhr", bundle: .app)
        case .asr: String(localized: "Asr", bundle: .app)
        case .maghrib: String(localized: "Maghrib", bundle: .app)
        case .isha: String(localized: "Isha", bundle: .app)
        }
    }

    /// On Fridays the noon prayer is called Jumu'ah (each mosque sets its own time; Dhuhr's is shown).
    func title(on date: Date, in zone: TimeZone) -> String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = zone
        if self == .dhuhr && calendar.component(.weekday, from: date) == 6 {
            return String(localized: "Jumu'ah", bundle: .app)
        }
        return title
    }
}

/// The calculation methods the user can pick from: Adhan's presets plus a few Adhan doesn't ship.
enum CalcMethod: String, CaseIterable, Codable, Identifiable {
    case muslimWorldLeague, turkey, northAmerica, moonsightingCommittee, egyptian, karachi
    case ummAlQura, dubai, kuwait, qatar, singapore, tehran
    case jafari, morocco, malaysia, indonesia, france

    var id: String { rawValue }

    /// How the method's authority computes its own timetable, checked day by day against a year or more
    /// of its official tables (see MethodRules). `country` is where the times are for.
    func rules(country: String?) -> MethodRules {
        var rules = MethodRules()
        switch self {
        case .muslimWorldLeague:
            rules.fajrAngle = 18
            rules.ishaAngle = 17
            rules.offsets = [.dhuhr: 60]
        case .northAmerica:
            rules.fajrAngle = 15
            rules.ishaAngle = 15
            rules.offsets = [.dhuhr: 60]
        case .egyptian:
            // ESA's tables: the sun's centre at 19.5° and 17.5°, Dhuhr at noon, no added minutes.
            rules.fajrAngle = 19.5
            rules.ishaAngle = 17.5
        case .karachi:
            // Jamia Uloom-ul-Islamia Banuri Town (the University of Islamic Sciences) computes its Karachi
            // tables with PrayTimes.org: 18°/18°, Dhuhr at zawal.
            rules.engine = .prayTimes
            rules.fajrAngle = 18
            rules.ishaAngle = 18
            rules.exactSeconds = true
        case .ummAlQura:
            // KACST's own service (ummulqura.org.sa): one declination per day for Fajr and Asr, everything rounded
            // up but sunrise, which is rounded down a second after the exact sunrise; Isha 90 minutes (120 in Ramadan).
            rules.fajrAngle = 18.5
            rules.ishaInterval = 90
            rules.ramadanIshaExtra = 30
            rules.kacst = true
            rules.rounding = .up
            rules.sunriseRounding = .down
            rules.exactSeconds = true
            rules.offsets = [.sunrise: 1]
        case .dubai:
            // Awqaf (awqaf.gov.ae): a perpetual table over 2020-2023, the earliest Fajr and sunrise and the latest
            // of the others; sunrise and sunset at 1.35°, 18°/18°, fitted to its 2025-2027 Dubai tables.
            rules.fajrAngle = 18
            rules.ishaAngle = 18
            rules.sunriseAngle = 1.35
            rules.maghribAngle = 1.35
            rules.offsets = [.fajr: -47, .sunrise: -54, .dhuhr: 168, .asr: 56, .maghrib: 56, .isha: 49]
            rules.perpetualYears = [2020, 2021, 2022, 2023]
        case .kuwait:
            rules.fajrAngle = 18
            rules.ishaAngle = 17.5
        case .qatar:
            // Qatar Calendar House: one perpetual table on the sun of 2006. Fajr 18° minus a minute, Dhuhr and Asr a
            // minute later (since 1447), Maghrib 2 minutes after sunset (3 in Ramadan), Isha 90 minutes after it.
            rules.fajrAngle = 18
            rules.ishaInterval = 90
            rules.ramadanIshaExtra = 1
            rules.ramadanMaghribExtra = 1
            rules.offsets = [.fajr: -60, .dhuhr: 60, .asr: 60, .maghrib: 120, .isha: 120]
            rules.baseYear = 2006
        case .singapore:
            // MUIS: one table for the whole country, the sun taken once a day (the next day at about
            // 13:17), Zohor 64 s after noon, Maghrib a minute later in Ramadan, everything rounded up.
            // shortcut: MUIS's 2024, 2026 and 2027 tables use the next day's sun, 2025's the previous day's;
            // check each new year's table (data.gov.sg) before relying on it.
            // shortcut: the Ramadan minute follows the user's Hijri calendar; MUIS's own Ramadan can start or end a
            // day apart from it (2026: 19 Feb-20 Mar against Umm al-Qura's 18 Feb-19 Mar), so Maghrib can be a minute
            // off on that day. Set the Hijri date a day back in Settings to follow MUIS when it does.
            rules.engine = .oncePerDay(daysAfterMidnightUTC: 1.22)
            rules.fajrAngle = 20
            rules.ishaAngle = 18
            rules.horizon = 50.0 / 60
            rules.offsets = [.dhuhr: 64]
            rules.ramadanMaghribExtra = 1
            rules.rounding = .up
            rules.exactSeconds = true
            rules.nationalPoint = (country: "SG", latitude: 1.2677, longitude: 103.8162)
        case .tehran:
            // The Institute of Geophysics' tables (Tehran 1386-1404 SH): 17.7°, Maghrib at 4.5°.
            rules.fajrAngle = 17.7
            rules.ishaAngle = 14
            rules.maghribAngle = 4.5
        case .jafari:
            // Leva Institute, Qum: Maghrib once the sun is 4° below the horizon (the redness has gone).
            rules.fajrAngle = 16
            rules.ishaAngle = 14
            rules.maghribAngle = 4
        case .morocco:
            rules.fajrAngle = 19
            rules.ishaAngle = 17
            rules.offsets = [.dhuhr: 300, .maghrib: 300]
        case .malaysia:
            // JAKIM: 18° since 2019, Zohor 64 s after noon (the sun's half-disc), Asar with the declination
            // at Asar, everything rounded up; Syuruk with its seconds dropped.
            rules.fajrAngle = 18
            rules.ishaAngle = 18
            rules.asrShadow = .atAsr
            rules.offsets = [.sunrise: -60, .dhuhr: 64]
            rules.rounding = .up
        case .indonesia:
            // Kemenag (SIHAT): 20°/18°, Maghrib at 1°, 2 minutes' ihtiyat (Dzuhur 3), rounded up; Terbit at 1°
            // minus 2 minutes with its seconds dropped; Ashar like Adhan's.
            rules.fajrAngle = 20
            rules.ishaAngle = 18
            rules.maghribAngle = 1
            rules.sunriseAngle = 1
            rules.asrShadow = .adhan
            rules.offsets = [.fajr: 120, .sunrise: -180, .dhuhr: 180, .asr: 120, .maghrib: 120, .isha: 120]
            rules.rounding = .up
        case .france:
            rules.fajrAngle = 12
            rules.ishaAngle = 12
        case .moonsightingCommittee:
            // moonsighting.com's own tables: PrayTimes.org's sun, Dhuhr 0.083 h after noon, Maghrib 3 minutes
            // after sunset, Khalid Shaukat's seasonal Fajr and Isha (bounded by the sun at 18°).
            rules.engine = .prayTimes
            rules.moonsighting = true
            rules.fajrAngle = 18
            rules.ishaAngle = 18
            rules.offsets = [.dhuhr: 0.083 * 3600, .maghrib: 180]
            rules.exactSeconds = true
        case .turkey:
            // Diyanet's own reckoning (namazvakitleri.diyanet.gov.tr): its temkin, 17° or 16° for Yatsı by country,
            // and its high-latitude estimates; rounded half up to the minute.
            rules.engine = .diyanet
            rules.country = country
            rules.exactSeconds = true
        }
        return rules
    }

    var title: String {
        switch self {
        case .muslimWorldLeague: String(localized: "Muslim World League", bundle: .app)
        case .turkey: String(localized: "Diyanet (Turkey)", bundle: .app)
        case .northAmerica: String(localized: "ISNA (North America)", bundle: .app)
        case .moonsightingCommittee: String(localized: "Moonsighting Committee", bundle: .app)
        case .egyptian: String(localized: "Egyptian General Authority of Survey", bundle: .app)
        case .karachi: String(localized: "University of Islamic Sciences, Karachi", bundle: .app)
        case .ummAlQura: String(localized: "Umm al-Qura University, Makkah", bundle: .app)
        case .dubai: String(localized: "Dubai", bundle: .app)
        case .kuwait: String(localized: "Kuwait", bundle: .app)
        case .qatar: String(localized: "Qatar", bundle: .app)
        case .singapore: String(localized: "Singapore", bundle: .app)
        case .tehran: String(localized: "Institute of Geophysics, Tehran", bundle: .app)
        case .jafari: String(localized: "Shia Ithna Ashari (Leva Institute, Qum)", bundle: .app)
        case .morocco: String(localized: "Morocco (Ministry of Habous)", bundle: .app)
        case .malaysia: String(localized: "Malaysia (JAKIM)", bundle: .app)
        case .indonesia: String(localized: "Indonesia (Kemenag)", bundle: .app)
        case .france: String(localized: "France (12°)", bundle: .app)
        }
    }

    /// Where the method is used, so people can recognise theirs.
    var usage: String {
        switch self {
        case .muslimWorldLeague: String(localized: "Common in Europe, the Far East and parts of the Americas.", bundle: .app)
        case .turkey: String(localized: "Turkey's Diyanet, used by Turkish mosques worldwide.", bundle: .app)
        case .northAmerica: String(localized: "Islamic Society of North America, used in the US and Canada.", bundle: .app)
        case .moonsightingCommittee: String(localized: "Adjusts Fajr and Isha by season. Used in the UK and North America.", bundle: .app)
        case .egyptian: String(localized: "Used in Egypt and in much of Africa, Syria and Lebanon.", bundle: .app)
        case .karachi: String(localized: "Used in Pakistan, India, Bangladesh and Afghanistan.", bundle: .app)
        case .ummAlQura: String(localized: "Used in Saudi Arabia. Isha is 90 minutes after Maghrib.", bundle: .app)
        case .dubai: String(localized: "Used in the United Arab Emirates.", bundle: .app)
        case .kuwait: String(localized: "Used in Kuwait.", bundle: .app)
        case .qatar: String(localized: "Used in Qatar. Isha is 90 minutes after Maghrib.", bundle: .app)
        case .singapore: String(localized: "Used in Singapore.", bundle: .app)
        case .tehran: String(localized: "Institute of Geophysics, University of Tehran. Used in Iran.", bundle: .app)
        case .jafari: String(localized: "Used by Shia (Ja'fari) communities. Maghrib is when the redness in the eastern sky has gone.", bundle: .app)
        case .morocco: String(localized: "Used in Morocco.", bundle: .app)
        case .malaysia: String(localized: "Used in Malaysia.", bundle: .app)
        case .indonesia: String(localized: "Used in Indonesia.", bundle: .app)
        case .france: String(localized: "Used by many mosques in France. Fajr and Isha at 12°.", bundle: .app)
        }
    }
}

/// The school of law (madhab): it sets when Asr begins, and Shia timetables differ more.
enum School: String, CaseIterable, Codable, Identifiable {
    case hanafi, shafii, maliki, hanbali, jafari

    var id: String { rawValue }

    var title: String {
        switch self {
        case .hanafi: String(localized: "Hanafi", bundle: .app)
        case .shafii: String(localized: "Shafi'i", bundle: .app)
        case .maliki: String(localized: "Maliki", bundle: .app)
        case .hanbali: String(localized: "Hanbali", bundle: .app)
        case .jafari: String(localized: "Ja'fari (Shia)", bundle: .app)
        }
    }

    /// The Moonsighting Committee's Isha: when the redness has gone (ahmer) for Shafi'i, Maliki and Hanbali,
    /// its "general" twilight otherwise, as on moonsighting.com.
    var shafaq: Shafaq {
        switch self {
        case .shafii, .maliki, .hanbali: .ahmer
        case .hanafi, .jafari: .general
        }
    }
}

enum AsrMethod: String, CaseIterable, Codable, Identifiable {
    case standard, hanafi

    var id: String { rawValue }

    // Diyanet (a Hanafi institution) uses the standard time too, so the labels steer by timetable, not school.
    var title: String {
        self == .hanafi ? String(localized: "Hanafi (later)", bundle: .app) : String(localized: "Standard", bundle: .app)
    }

    var shortTitle: String {
        self == .hanafi ? String(localized: "Hanafi Asr", bundle: .app) : String(localized: "Standard Asr", bundle: .app)
    }

    var explanation: String {
        self == .hanafi
            ? String(localized: "Asr begins when a shadow is twice as long as the object, about an hour later. Some Hanafi mosques use this.", bundle: .app)
            : String(localized: "Asr begins when a shadow is as long as the object. Most timetables use this, including Diyanet's.", bundle: .app)
    }
}

/// The app's language: the iPhone's, or one picked in the app (shown at once, without a restart).
enum AppLanguage: String, CaseIterable, Codable, Identifiable {
    case system, en, nl, de, fr, tr, ar

    var id: String { rawValue }

    /// The language shown now; kept in step with the settings by AppModel.
    static var current = AppLanguage.system

    /// Each language in its own words, so people find theirs whatever the app shows now.
    var nativeName: String {
        switch self {
        case .system: String(localized: "Same as iPhone", bundle: .app)
        case .en: "English"
        case .nl: "Nederlands"
        case .de: "Deutsch"
        case .fr: "Français"
        case .tr: "Türkçe"
        case .ar: "العربية"
        }
    }

    /// For "Same as iPhone": the language that means for this app; otherwise the name in the current language.
    var detail: String? {
        if self == .system {
            let code = Bundle.main.preferredLocalizations.first ?? "en"
            return Locale(identifier: code).localizedString(forLanguageCode: code)
        }
        let name = Locale.app.localizedString(forLanguageCode: rawValue)
        return name == nativeName ? nil : name
    }

    var locale: Locale {
        guard self != .system else { return .autoupdatingCurrent }
        // Keep the iPhone's region, as iOS's own per-app language does: English on a Dutch iPhone
        // becomes en_NL (16:16, "Thursday 12 November"), not en_US (4:16 PM).
        guard let region = Locale.current.region?.identifier else { return Locale(identifier: rawValue) }
        return Locale(identifier: "\(rawValue)_\(region)")
    }

    var isRightToLeft: Bool { locale.language.characterDirection == .rightToLeft }

    /// The language code text is looked up in, for picking a calculation method.
    var code: String? {
        self == .system ? Locale.current.language.languageCode?.identifier : rawValue
    }

    /// This app's page on qibla.dev ("privacy", "support") in the language shown now; English is at the root.
    func siteURL(_ page: String) -> URL {
        let shown = self == .system ? Bundle.main.preferredLocalizations.first ?? "en" : rawValue
        let folder = ["nl", "de", "fr", "tr", "ar"].contains(shown) ? "\(shown)/" : ""
        return URL(string: "https://qibla.dev/\(folder)\(page)")!
    }

    var bundle: Bundle {
        guard self != .system,
              let path = Bundle.main.path(forResource: rawValue, ofType: "lproj"),
              let bundle = Bundle(path: path) else { return .main }
        return bundle
    }
}

extension Bundle {
    /// Where text is looked up: the language chosen in the app, or the iPhone's.
    static var app: Bundle { AppLanguage.current.bundle }
}

extension Locale {
    /// Formats dates and numbers in the app's language.
    static var app: Locale { AppLanguage.current.locale }
}

struct AppSettings: Codable, Equatable {
    var method: CalcMethod
    var asr: AsrMethod
    /// Minutes added to each calculated time, to match a local mosque.
    var adjustments: [PrayerKind: Int] = [:]
    var notify: Set<PrayerKind> = [.fajr, .dhuhr, .asr, .maghrib, .isha]
    var useCurrentLocation = true
    var city: Place?
    var language = AppLanguage.system
    /// Days added to the Hijri date (-2...2): the Umm al-Qura calendar and local moon sighting can differ.
    var hijriOffset = 0
    /// Chosen in the setup; nil until then.
    var school: School?
    /// Minutes before each prayer with its bell on for an early reminder; 0 is off.
    var reminderMinutes = 0
    /// A reminder an hour before the Friday prayer.
    var jumuahReminder = false
    /// In Ramadan: a reminder 30 minutes before suhoor ends, and one at iftar.
    var ramadanReminders = false
    /// Whether choosing the Ja'fari school set `hijriOffset` (so changing school may undo it, but not a hand-set one).
    var hijriOffsetFromSchool = false

    /// What most people in the region use: only a starting point, the user picks.
    static func suggested(
        region: String? = Locale.current.region?.identifier,
        language: String? = Locale.current.language.languageCode?.identifier
    ) -> AppSettings {
        // Turkish usually means a Diyanet mosque, also in the Netherlands or Germany. Diyanet's
        // Ikindi is the standard (first-shadow) Asr, so Hanafi is not the default here.
        if region == "TR" || language == "tr" {
            return AppSettings(method: .turkey, asr: .standard)
        }
        switch region ?? "" {
        case "GB", "US", "CA": return AppSettings(method: .moonsightingCommittee, asr: .standard)
        case "SA": return AppSettings(method: .ummAlQura, asr: .standard)
        case "AE": return AppSettings(method: .dubai, asr: .standard)
        case "KW": return AppSettings(method: .kuwait, asr: .standard)
        case "QA": return AppSettings(method: .qatar, asr: .standard)
        case "EG": return AppSettings(method: .egyptian, asr: .standard)
        case "PK", "IN", "BD", "AF": return AppSettings(method: .karachi, asr: .hanafi)
        case "IR": return AppSettings(method: .tehran, asr: .standard)
        case "MA": return AppSettings(method: .morocco, asr: .standard)
        case "MY": return AppSettings(method: .malaysia, asr: .standard)
        case "ID": return AppSettings(method: .indonesia, asr: .standard)
        case "SG", "BN": return AppSettings(method: .singapore, asr: .standard)
        default: return AppSettings(method: .muslimWorldLeague, asr: .standard)
        }
    }
}

extension AppSettings {
    /// Reads whatever it can, so settings saved by an older version survive new fields.
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self = .suggested()
        if let value = try? container.decode(CalcMethod.self, forKey: .method) { method = value }
        if let value = try? container.decode(AsrMethod.self, forKey: .asr) { asr = value }
        if let value = try? container.decode([PrayerKind: Int].self, forKey: .adjustments) { adjustments = value }
        if let value = try? container.decode(Set<PrayerKind>.self, forKey: .notify) { notify = value }
        if let value = try? container.decode(Bool.self, forKey: .useCurrentLocation) { useCurrentLocation = value }
        if let value = try? container.decode(Place.self, forKey: .city) { city = value }
        if let value = try? container.decode(AppLanguage.self, forKey: .language) { language = value }
        if let value = try? container.decode(Int.self, forKey: .hijriOffset) { hijriOffset = value }
        if let value = try? container.decode(School.self, forKey: .school) { school = value }
        if let value = try? container.decode(Int.self, forKey: .reminderMinutes) { reminderMinutes = value }
        if let value = try? container.decode(Bool.self, forKey: .jumuahReminder) { jumuahReminder = value }
        if let value = try? container.decode(Bool.self, forKey: .ramadanReminders) { ramadanReminders = value }
        if let value = try? container.decode(Bool.self, forKey: .hijriOffsetFromSchool) { hijriOffsetFromSchool = value }
    }
}
