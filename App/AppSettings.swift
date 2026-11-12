import Adhan
import Foundation

enum PrayerKind: String, CaseIterable, Codable, Identifiable {
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

    /// Adhan's parameters. For our own methods, their minute corrections are in `adjustments`
    /// (the user's adjustments are added on top in AppModel.compute).
    var parameters: CalculationParameters {
        switch self {
        case .muslimWorldLeague: CalculationMethod.muslimWorldLeague.params
        case .turkey: CalculationMethod.turkey.params
        case .northAmerica: CalculationMethod.northAmerica.params
        case .moonsightingCommittee: CalculationMethod.moonsightingCommittee.params
        case .egyptian: CalculationMethod.egyptian.params
        case .karachi: CalculationMethod.karachi.params
        case .ummAlQura: CalculationMethod.ummAlQura.params
        case .dubai: CalculationMethod.dubai.params
        case .kuwait: CalculationMethod.kuwait.params
        case .qatar: CalculationMethod.qatar.params
        case .singapore: CalculationMethod.singapore.params
        case .tehran: CalculationMethod.tehran.params
        // Leva Institute, Qum: Maghrib once the sun is 4° below the horizon (the redness has gone).
        case .jafari: CalcMethod.custom(fajr: 16, isha: 14, maghribAngle: 4)
        // Ministry of Habous, checked against its 2026 data.
        case .morocco: CalcMethod.custom(fajr: 19, isha: 17, offsets: PrayerAdjustments(dhuhr: 5, maghrib: 5))
        // JAKIM moved Fajr from 20° to 18° in 2019.
        case .malaysia:
            CalcMethod.custom(fajr: 18, isha: 18, offsets: PrayerAdjustments(sunrise: -1, dhuhr: 1), rounding: .up)
        // Kemenag: Maghrib at 1° and a safety margin of about 2 minutes (as in Adhan's upcoming preset).
        case .indonesia:
            CalcMethod.custom(
                fajr: 20, isha: 18, maghribAngle: 1,
                offsets: PrayerAdjustments(fajr: 2, sunrise: -4, dhuhr: 3, asr: 2, maghrib: 2, isha: 2), rounding: .up)
        case .france: CalcMethod.custom(fajr: 12, isha: 12)
        }
    }

    private static func custom(
        fajr: Double, isha: Double, maghribAngle: Double? = nil,
        offsets: PrayerAdjustments = PrayerAdjustments(), rounding: Rounding = .nearest
    ) -> CalculationParameters {
        var params = CalculationMethod.other.params
        params.fajrAngle = fajr
        params.ishaAngle = isha
        params.maghribAngle = maghribAngle
        params.adjustments = offsets
        params.rounding = rounding
        return params
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
    case hanafi, shafii, maliki, hanbali, jafari, unsure

    var id: String { rawValue }

    var title: String {
        switch self {
        case .hanafi: String(localized: "Hanafi", bundle: .app)
        case .shafii: String(localized: "Shafi'i", bundle: .app)
        case .maliki: String(localized: "Maliki", bundle: .app)
        case .hanbali: String(localized: "Hanbali", bundle: .app)
        case .jafari: String(localized: "Ja'fari (Shia)", bundle: .app)
        case .unsure: String(localized: "Not sure", bundle: .app)
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
        self == .system ? .autoupdatingCurrent : Locale(identifier: rawValue)
    }

    var isRightToLeft: Bool { locale.language.characterDirection == .rightToLeft }

    /// The language code text is looked up in, for picking a calculation method.
    var code: String? {
        self == .system ? Locale.current.language.languageCode?.identifier : rawValue
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
    var school = School.unsure

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
    }
}
