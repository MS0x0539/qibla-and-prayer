import Foundation
import Testing
@testable import QiblaAndPrayer

struct PrayerTimeTests {
    let amsterdam = Place(name: "Amsterdam", latitude: 52.3676, longitude: 4.9041, timeZoneID: "Europe/Amsterdam")

    private func date(_ year: Int, _ month: Int, _ day: Int, _ hour: Int = 12, _ minute: Int = 0) -> Date {
        amsterdam.calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour, minute: minute))!
    }

    @Test func qiblaDirectionAndDistance() {
        let newYork = Place(name: "New York", latitude: 40.7128, longitude: -74.0059, timeZoneID: "America/New_York")
        #expect(abs(newYork.qibla - 58.48) < 0.05)
        #expect(abs(amsterdam.qibla - 125.6) < 0.5)
        #expect(abs(amsterdam.kilometresToMecca - 4_550) < 60)
    }

    @Test(arguments: CalcMethod.allCases)
    func timesAreInOrderAllYear(method: CalcMethod) throws {
        let settings = AppSettings(method: method, asr: .standard)
        for month in 1...12 {
            let times = try #require(Prayers.compute(on: date(2026, month, 21), place: amsterdam, settings: settings))
            #expect(times.map(\.kind) == PrayerKind.allCases)
            let instants = times.map(\.time)
            #expect(instants == instants.sorted(), "month \(month)")
            #expect(Set(instants).count == instants.count, "month \(month)")
        }
    }

    @Test func nextPrayerAfterIshaIsTomorrowsFajr() throws {
        let settings = AppSettings(method: .muslimWorldLeague, asr: .standard)
        // The evening before the clocks go forward, when adding 24 hours would skip a day.
        let late = date(2027, 3, 27, 23, 30)
        let next = try #require(Prayers.next(after: late, place: amsterdam, settings: settings))
        #expect(next.kind == .fajr)
        #expect(amsterdam.calendar.component(.day, from: next.time) == 28)
    }

    @Test func notificationsStayWithinTheLimit() {
        var settings = AppSettings(method: .muslimWorldLeague, asr: .standard)
        let now = date(2026, 11, 12, 13, 0)
        let plain = AppModel.planned(from: now, place: amsterdam, settings: settings)
        #expect(plain.count == 64)
        #expect(plain.allSatisfy { $0.date > now })
        #expect(plain.map(\.date) == plain.map(\.date).sorted())
        #expect(Set(plain.map(\.id)).count == plain.count)
        // With every reminder on the list still stops at 64, now covering fewer days.
        settings.reminderMinutes = 10
        settings.jumuahReminder = true
        settings.ramadanReminders = true
        let full = AppModel.planned(from: now, place: amsterdam, settings: settings)
        #expect(full.count == 64)
        #expect(full.last!.date < plain.last!.date)
        settings.notify = []
        settings.reminderMinutes = 0
        settings.jumuahReminder = false
        #expect(AppModel.planned(from: now, place: amsterdam, settings: settings).isEmpty)  // not Ramadan
    }

    @Test func remindersComeBeforeThePrayer() throws {
        var settings = AppSettings(method: .muslimWorldLeague, asr: .standard)
        settings.notify = [.asr]
        settings.reminderMinutes = 15
        settings.jumuahReminder = true
        let now = date(2026, 11, 12, 13, 0)  // Thursday
        let items = AppModel.planned(from: now, place: amsterdam, settings: settings)
        let asr = try #require(Prayers.compute(on: now, place: amsterdam, settings: settings))[3].time
        #expect(items[0].date == asr.addingTimeInterval(-15 * 60))
        #expect(items[1].date == asr)
        let friday = try #require(Prayers.compute(on: date(2026, 11, 13), place: amsterdam, settings: settings))[2].time
        #expect(items.contains { $0.id.hasPrefix("jumuah") && $0.date == friday.addingTimeInterval(-3600) })
        let jumuah = items.filter { $0.id.hasPrefix("jumuah") }
        #expect(jumuah.count >= 4)
        #expect(jumuah.allSatisfy { amsterdam.calendar.component(.weekday, from: $0.date) == 6 })
    }

    @Test func suhoorAndIftarOnlyInRamadan() throws {
        var settings = AppSettings(method: .muslimWorldLeague, asr: .standard)
        settings.notify = []
        settings.ramadanReminders = true
        let ramadan = AppModel.planned(from: date(2027, 2, 20), place: amsterdam, settings: settings)
        #expect(ramadan.contains { $0.id.hasPrefix("suhoor") })
        #expect(ramadan.contains { $0.id.hasPrefix("iftar") })
        let fajr = try #require(Prayers.compute(on: date(2027, 2, 21), place: amsterdam, settings: settings))[0].time
        #expect(ramadan.contains { $0.id.hasPrefix("suhoor") && $0.date == fajr.addingTimeInterval(-30 * 60) })
        // With Maghrib's own notification on, that one mentions iftar instead of a second notification.
        settings.notify = [.maghrib]
        let withMaghrib = AppModel.planned(from: date(2027, 2, 20), place: amsterdam, settings: settings)
        #expect(!withMaghrib.contains { $0.id.hasPrefix("iftar") })
        #expect(AppModel.planned(from: date(2027, 5, 20), place: amsterdam, settings: settings)
            .allSatisfy { !$0.id.hasPrefix("suhoor") })
        // A 30-minute early Fajr reminder would land on the suhoor one: only one of them comes.
        settings.notify = [.fajr]
        settings.reminderMinutes = 30
        let early = AppModel.planned(from: date(2027, 2, 20), place: amsterdam, settings: settings)
        let suhoorTimes = Set(early.filter { $0.id.hasPrefix("suhoor") }.map(\.date))
        #expect(!suhoorTimes.isEmpty)
        #expect(!early.contains { $0.id.hasPrefix("before-fajr") && suhoorTimes.contains($0.date) })
        #expect(early.contains { $0.id.hasPrefix("before-fajr") })  // after Ramadan they come back
    }

    @Test func ramadanStartFromBeforeAndDuring() throws {
        let before = try #require(AppModel.ramadanStart(around: date(2026, 11, 12), place: amsterdam, hijriOffset: 0))
        let during = try #require(AppModel.ramadanStart(around: date(2027, 2, 20), place: amsterdam, hijriOffset: 0))
        #expect(before == during)
        #expect(Prayers.hijri(of: before, place: amsterdam, offset: 0).day == 1)
        #expect(Prayers.hijri(of: before, place: amsterdam, offset: 0).month == 9)
        let previous = try #require(amsterdam.calendar.date(byAdding: .day, value: -1, to: before))
        #expect(Prayers.hijri(of: previous, place: amsterdam, offset: 0).month == 8)
    }

    @Test func tasbihRounds() {
        var counter = TasbihCounter(target: 3)
        let rounds = (1...4).map { _ in counter.tap() }
        #expect(rounds == [false, false, true, false])  // the fourth tap starts the next round at 1
        #expect(counter.count == 1)
        #expect(counter.total == 4)
        var endless = TasbihCounter(target: 0)
        let endlessRounds = (1...150).map { _ in endless.tap() }
        #expect(!endlessRounds.contains(true))
        #expect(endless.count == 150)
    }

    @Test func adjustmentsMoveOnlyThatPrayer() throws {
        var settings = AppSettings(method: .muslimWorldLeague, asr: .standard)
        let before = try #require(Prayers.compute(on: date(2026, 11, 12), place: amsterdam, settings: settings))
        settings.adjustments[.isha] = 5
        let after = try #require(Prayers.compute(on: date(2026, 11, 12), place: amsterdam, settings: settings))
        #expect(after[5].time.timeIntervalSince(before[5].time) == 300)
        #expect(after[0].time == before[0].time)
    }

    @Test func suggestedMethods() {
        #expect(AppSettings.suggested(region: "NL", language: "tr").method == .turkey)
        // Diyanet's Ikindi is the standard (first-shadow) Asr.
        #expect(AppSettings.suggested(region: "TR", language: "en").asr == .standard)
        #expect(AppSettings.suggested(region: "PK", language: "ur").asr == .hanafi)
        #expect(AppSettings.suggested(region: "GB", language: "en").method == .moonsightingCommittee)
        #expect(AppSettings.suggested(region: "MA", language: "ar").method == .morocco)
        #expect(AppSettings.suggested(region: "NL", language: "nl").method == .muslimWorldLeague)
        #expect(AppSettings.suggested(region: nil, language: nil).method == .muslimWorldLeague)
    }

    @Test func diyanetAbroadUsesIsha16() throws {
        let settings = AppSettings(method: .turkey, asr: .standard)
        var inTurkey = amsterdam
        inTurkey.countryCode = "TR"
        var abroad = amsterdam
        abroad.countryCode = "NL"
        let a = try #require(Prayers.compute(on: date(2026, 12, 1), place: abroad, settings: settings))
        let b = try #require(Prayers.compute(on: date(2026, 12, 1), place: inTurkey, settings: settings))
        #expect(a[5].time < b[5].time)
    }

    @Test func ummAlQuraIshaIsLaterInRamadan() throws {
        let mecca = Place(name: "Mecca", latitude: 21.4225, longitude: 39.8262, timeZoneID: "Asia/Riyadh", countryCode: "SA")
        let settings = AppSettings(method: .ummAlQura, asr: .standard)
        func gap(_ month: Int, _ day: Int) throws -> TimeInterval {
            let when = mecca.calendar.date(from: DateComponents(year: 2026, month: month, day: day, hour: 12))!
            let times = try #require(Prayers.compute(on: when, place: mecca, settings: settings))
            return times[5].time.timeIntervalSince(times[4].time)
        }
        #expect(try gap(3, 1) == 120 * 60)  // Ramadan 1447
        #expect(try gap(5, 1) == 90 * 60)
    }

    @Test func ramadanOnceIn2027AndTwiceIn2030() {
        let in2027 = AppModel.islamicDates(inYear: 2027, place: amsterdam, hijriOffset: 0).filter { $0.day == .ramadan }
        let in2030 = AppModel.islamicDates(inYear: 2030, place: amsterdam, hijriOffset: 0).filter { $0.day == .ramadan }
        #expect(in2027.count == 1)
        #expect(in2030.count == 2)
        if let start = in2027.first?.date {
            let days = AppModel.ramadanDays(from: start, place: amsterdam, settings: AppSettings(method: .muslimWorldLeague, asr: .standard))
            #expect((29...30).contains(days.count))
            #expect(days.first?.hijriDay == 1)
        }
    }

    /// Shia observance: the Prophet's birthday on 17 Rabi' al-Awwal (by day), the Mab'ath instead of the Mi'raj,
    /// three Laylat al-Qadr nights, Ghadir and Arba'een. Dates from the Umm al-Qura calendar, offset 0.
    @Test func shiaCalendarHasItsOwnDays() throws {
        let shia = AppModel.islamicDates(inYear: 2026, place: amsterdam, hijriOffset: 0, shia: true)
        let sunni = AppModel.islamicDates(inYear: 2026, place: amsterdam, hijriOffset: 0)
        #expect(shia.filter { $0.day == .laylatAlQadr }.count == 3)
        #expect(sunni.filter { $0.day == .laylatAlQadr }.count == 1)
        #expect(shia.contains { $0.day == .ghadir } && !sunni.contains { $0.day == .ghadir })
        #expect(shia.contains { $0.day == .arbaeen } && !sunni.contains { $0.day == .arbaeen })
        #expect(shia.contains { $0.day == .mabath } && !shia.contains { $0.day == .israMiraj })
        let birth = try #require(shia.first { $0.day == .mawlid })
        #expect(!birth.isNight)
        #expect(amsterdam.calendar.component(.month, from: birth.date) == 8)
        #expect(amsterdam.calendar.component(.day, from: birth.date) == 30)
        let mawlid = try #require(sunni.first { $0.day == .mawlid })
        #expect(mawlid.isNight)
        #expect(amsterdam.calendar.component(.day, from: mawlid.date) == 24)
    }

    /// Days from each authority's own published timetable that the method must reproduce to the minute
    /// (Fajr, sunrise, Dhuhr, Asr, Maghrib, Isha; nil where the authority publishes no such time).
    @Test func officialTimetables() throws {
        struct Day {
            let place: Place
            let date: (Int, Int, Int)
            let method: CalcMethod
            var school: School? = nil
            var asr = AsrMethod.standard
            let times: [String?]
        }
        let london = Place(name: "London", latitude: 51.5074, longitude: -0.1278, timeZoneID: "Europe/London", countryCode: "GB")
        let newYork = Place(name: "New York", latitude: 40.7128, longitude: -74.006, timeZoneID: "America/New_York", countryCode: "US")
        // Kemenag's own point for Kota Jakarta (SIHAT); ESA's and Banuri Town's points fitted to their tables.
        let jakarta = Place(name: "Jakarta", latitude: -6.170089, longitude: 106.83105, timeZoneID: "Asia/Jakarta", countryCode: "ID")
        let singapore = Place(name: "Singapore", latitude: 1.3521, longitude: 103.8198, timeZoneID: "Asia/Singapore", countryCode: "SG")
        let cairo = Place(name: "Cairo", latitude: 30.075, longitude: 31.275, timeZoneID: "Africa/Cairo", countryCode: "EG")
        let karachi = Place(name: "Karachi", latitude: 24.866667, longitude: 67.05, timeZoneID: "Asia/Karachi", countryCode: "PK")
        let tehran = Place(name: "Tehran", latitude: 35.70, longitude: 51.42, timeZoneID: "Asia/Tehran", countryCode: "IR")
        // KACST's own Makkah point; Doha's and Dubai's points fitted to their authorities' tables.
        let makkah = Place(name: "Makkah", latitude: 21.426666, longitude: 39.831666, timeZoneID: "Asia/Riyadh", countryCode: "SA")
        let doha = Place(name: "Doha", latitude: 25.283333, longitude: 51.533333, timeZoneID: "Asia/Qatar", countryCode: "QA")
        let dubai = Place(name: "Dubai", latitude: 25.105, longitude: 55.31, timeZoneID: "Asia/Dubai", countryCode: "AE")
        // Diyanet's points for its Istanbul, Amsterdam and Oslo tables, fitted to them.
        let istanbul = Place(name: "Istanbul", latitude: 41.01197, longitude: 28.97396, timeZoneID: "Europe/Istanbul", countryCode: "TR")
        let amsterdamDiyanet = Place(name: "Amsterdam", latitude: 52.36986, longitude: 4.88398, timeZoneID: "Europe/Amsterdam", countryCode: "NL")
        let oslo = Place(name: "Oslo", latitude: 59.90962, longitude: 10.76456, timeZoneID: "Europe/Oslo", countryCode: "NO")
        let days = [
            // moonsighting.com's tables: "general" Isha, and the Shafi'i (ahmer) one.
            Day(place: london, date: (2026, 11, 12), method: .moonsightingCommittee, times: ["05:35", "07:13", "11:50", "13:52", "16:18", "17:45"]),
            Day(place: london, date: (2026, 11, 12), method: .moonsightingCommittee, school: .shafii, times: ["05:35", "07:13", "11:50", "13:52", "16:18", "17:24"]),
            Day(place: london, date: (2026, 11, 12), method: .moonsightingCommittee, asr: .hanafi, times: [nil, nil, nil, "14:27", nil, nil]),
            Day(place: london, date: (2026, 6, 21), method: .moonsightingCommittee, times: ["02:43", "04:43", "13:07", "17:25", "21:25", "22:42"]),
            Day(place: newYork, date: (2026, 3, 20), method: .moonsightingCommittee, times: ["05:30", "06:59", "13:08", "16:29", "19:11", "20:25"]),
            // Near the equator the 18° Isha comes before the seasonal one.
            Day(place: Place(name: "Jakarta", latitude: -6.2088, longitude: 106.8456, timeZoneID: "Asia/Jakarta", countryCode: "ID"),
                date: (2026, 11, 12), method: .moonsightingCommittee, times: ["04:12", "05:25", "11:42", "14:58", "17:51", "19:01"]),
            // Kemenag (bimasislam.kemenag.go.id).
            Day(place: jakarta, date: (2026, 11, 12), method: .indonesia, times: ["04:06", "05:22", "11:40", "15:00", "17:51", "19:04"]),
            Day(place: jakarta, date: (2026, 6, 21), method: .indonesia, times: ["04:40", "05:58", "11:58", "15:19", "17:51", "19:05"]),
            // MUIS (data.gov.sg): one table for all of Singapore.
            Day(place: singapore, date: (2026, 11, 12), method: .singapore, times: ["05:27", "06:48", "12:51", "16:12", "18:51", "20:04"]),
            Day(place: singapore, date: (2026, 6, 21), method: .singapore, times: ["05:37", "07:01", "13:08", "16:33", "19:13", "20:28"]),
            // Egyptian General Authority of Survey (esa.gov.eg); June is summer time.
            Day(place: cairo, date: (2026, 11, 12), method: .egyptian, times: ["04:48", "06:17", "11:39", "14:39", "17:00", "18:20"]),
            Day(place: cairo, date: (2026, 6, 21), method: .egyptian, times: ["04:08", "05:54", "12:57", "16:32", "19:59", "21:33"]),
            // Jamia Uloom-ul-Islamia Banuri Town (banuri.edu.pk): Dhuhr is its zawal.
            Day(place: karachi, date: (2026, 11, 12), method: .karachi, times: ["05:27", "06:46", "12:16", "15:24", "17:46", "19:04"]),
            Day(place: karachi, date: (2026, 11, 12), method: .karachi, asr: .hanafi, times: [nil, nil, nil, "16:10", nil, nil]),
            // Institute of Geophysics, University of Tehran (no Asr or Isha published).
            Day(place: tehran, date: (2026, 1, 15), method: .tehran, times: ["05:45", "07:14", "12:14", nil, "17:34", nil]),
            // KACST's Umm al-Qura service (ummulqura.org.sa); 25 February is in Ramadan (Isha 120 minutes).
            Day(place: makkah, date: (2026, 11, 12), method: .ummAlQura, times: ["05:12", "06:29", "12:05", "15:17", "17:40", "19:10"]),
            Day(place: makkah, date: (2026, 6, 21), method: .ummAlQura, times: ["04:12", "05:39", "12:23", "15:43", "19:06", "20:36"]),
            Day(place: makkah, date: (2026, 2, 25), method: .ummAlQura, times: ["05:28", "06:44", "12:34", "15:55", "18:24", "20:24"]),
            // Qatar Calendar House (qatarch.com); 1 March is in Ramadan (Maghrib a minute later).
            Day(place: doha, date: (2026, 11, 12), method: .qatar, times: ["04:29", "05:49", "11:19", "14:26", "16:49", "18:19"]),
            Day(place: doha, date: (2026, 6, 21), method: .qatar, times: ["03:13", "04:44", "11:37", "14:59", "18:29", "19:59"]),
            Day(place: doha, date: (2026, 3, 1), method: .qatar, times: ["04:40", "05:57", "11:47", "15:08", "17:39", "19:09"]),
            // General Authority of Islamic Affairs and Endowments, UAE (awqaf.gov.ae), Dubai.
            Day(place: dubai, date: (2026, 11, 12), method: .dubai, times: ["05:14", "06:30", "12:06", "15:11", "17:36", "18:52"]),
            Day(place: dubai, date: (2026, 6, 21), method: .dubai, times: ["03:59", "05:26", "12:23", "15:44", "19:15", "20:42"]),
            Day(place: dubai, date: (2026, 3, 1), method: .dubai, times: ["05:25", "06:38", "12:34", "15:53", "18:24", "19:38"]),
            // Diyanet (namazvakitleri.diyanet.gov.tr): Turkey's program; Amsterdam's summer estimate (takdir) and its
            // spring transition; Oslo near 60° N.
            Day(place: istanbul, date: (2026, 11, 12), method: .turkey, times: ["06:13", "07:41", "12:53", "15:31", "17:56", "19:18"]),
            Day(place: istanbul, date: (2026, 6, 21), method: .turkey, times: ["03:24", "05:25", "13:11", "17:11", "20:47", "22:38"]),
            Day(place: amsterdamDiyanet, date: (2026, 11, 12), method: .turkey, times: ["05:57", "07:49", "12:30", "14:33", "17:00", "18:39"]),
            Day(place: amsterdamDiyanet, date: (2026, 6, 21), method: .turkey, times: ["03:46", "05:11", "13:47", "18:11", "22:13", "23:29"]),
            Day(place: amsterdamDiyanet, date: (2026, 5, 1), method: .turkey, times: ["04:09", "06:03", "13:43", "17:45", "21:12", "22:53"]),
            Day(place: oslo, date: (2026, 6, 21), method: .turkey, times: ["02:50", "03:54", "13:24", "18:04", "22:51", "23:47"]),
            Day(place: oslo, date: (2026, 8, 1), method: .turkey, times: ["03:23", "04:51", "13:28", "17:49", "21:56", "23:14"]),
        ]
        for day in days {
            var settings = AppSettings(method: day.method, asr: day.asr)
            settings.school = day.school
            let (year, month, dayOfMonth) = day.date
            let date = day.place.calendar.date(from: DateComponents(year: year, month: month, day: dayOfMonth, hour: 12))!
            let times = try #require(Prayers.compute(on: date, place: day.place, settings: settings))
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.timeZone = day.place.timeZone
            formatter.dateFormat = "HH:mm"
            for (item, expected) in zip(times, day.times) {
                guard let expected else { continue }
                #expect(formatter.string(from: item.time) == expected, "\(day.method) \(day.place.name) \(day.date) \(item.kind)")
            }
        }
    }

    /// Diyanet's own Hijri calendar: today is 3 Cemaziyelahir 1448 for Diyanet, 2 Jumada II in Umm al-Qura.
    @Test func diyanetCalendar() throws {
        let today = try #require(DiyanetCalendar.hijri(year: 2026, month: 11, day: 12))
        #expect(today.year == 1448 && today.month == 6 && today.day == 3)
        let ramadan = try #require(DiyanetCalendar.firstDay(year: 1447, month: 9))
        #expect(ramadan.year == 2026 && ramadan.month == 2 && ramadan.day == 19)
        #expect(DiyanetCalendar.hijri(year: 2040, month: 1, day: 1) == nil)
        var settings = AppSettings(method: .turkey, asr: .standard)
        #expect(Prayers.hijri(of: date(2026, 11, 12), place: amsterdam, settings: settings).day == 3)
        settings.method = .muslimWorldLeague
        #expect(Prayers.hijri(of: date(2026, 11, 12), place: amsterdam, settings: settings).day == 2)
        // Regaib Kandili, the night before the first Friday of Rajab: Thursday 10 December 2026.
        let regaib = try #require(AppModel.islamicDates(inYear: 2026, place: amsterdam, hijriOffset: 0, diyanet: true)
            .first { $0.day == .raghaib })
        #expect(amsterdam.calendar.component(.month, from: regaib.date) == 12)
        #expect(amsterdam.calendar.component(.day, from: regaib.date) == 10)
    }

    @Test func addedMethodsGiveTimesInOrder() throws {
        let cases: [(CalcMethod, Place)] = [
            (.morocco, Place(name: "Rabat", latitude: 34.0209, longitude: -6.8416, timeZoneID: "Africa/Casablanca", countryCode: "MA")),
            (.malaysia, Place(name: "Kuala Lumpur", latitude: 3.139, longitude: 101.6869, timeZoneID: "Asia/Kuala_Lumpur", countryCode: "MY")),
            (.indonesia, Place(name: "Jakarta", latitude: -6.2088, longitude: 106.8456, timeZoneID: "Asia/Jakarta", countryCode: "ID")),
            (.france, Place(name: "Paris", latitude: 48.8566, longitude: 2.3522, timeZoneID: "Europe/Paris", countryCode: "FR")),
            (.jafari, Place(name: "Qom", latitude: 34.6399, longitude: 50.8759, timeZoneID: "Asia/Tehran", countryCode: "IR")),
        ]
        for (method, place) in cases {
            for month in [1, 6] {
                let when = place.calendar.date(from: DateComponents(year: 2026, month: month, day: 15, hour: 12))!
                let times = try #require(Prayers.compute(on: when, place: place, settings: AppSettings(method: method, asr: .standard)))
                let instants = times.map(\.time)
                #expect(instants == instants.sorted(), "\(method) \(month)")
            }
        }
    }

    /// Adhan applies the 1/7 rule as a bound even where 12° is reached; France must not get it in Paris.
    @Test func franceKeepsTwelveDegreesInParis() throws {
        let paris = Place(name: "Paris", latitude: 48.8566, longitude: 2.3522, timeZoneID: "Europe/Paris", countryCode: "FR")
        let day = paris.calendar.date(from: DateComponents(year: 2026, month: 6, day: 21, hour: 12))!
        let times = try #require(Prayers.compute(on: day, place: paris, settings: AppSettings(method: .france, asr: .standard)))
        #expect(times[0].time < paris.calendar.date(bySettingHour: 4, minute: 15, second: 0, of: day)!)
    }

    @Test func yearsHaveNoThousandsSeparator() {
        #expect(Formats.number(2026) == "2026")
        #expect(Formats.number(1448) == "1448")
    }

    @Test func fridayNoonIsJumuah() {
        let friday = date(2026, 11, 13)
        #expect(PrayerKind.dhuhr.title(on: friday, in: amsterdam.timeZone) != PrayerKind.dhuhr.title)
        #expect(PrayerKind.dhuhr.title(on: date(2026, 11, 12), in: amsterdam.timeZone) == PrayerKind.dhuhr.title)
    }

    @Test func turnDirection() {
        #expect(QiblaView.signedOffset(125.6 - 100) > 0)
        #expect(QiblaView.signedOffset(10 - 350) == 20)
        #expect(QiblaView.signedOffset(350 - 10) == -20)
    }
}
