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

    /// Adhan's own check against Diyanet's published Istanbul timetable of 16 April 2020.
    @Test func istanbulMatchesDiyanet() throws {
        let istanbul = Place(
            name: "Istanbul", latitude: 41.005616, longitude: 28.976380, timeZoneID: "Europe/Istanbul", countryCode: "TR")
        let day = istanbul.calendar.date(from: DateComponents(year: 2020, month: 4, day: 16, hour: 12))!
        let times = try #require(Prayers.compute(on: day, place: istanbul, settings: AppSettings(method: .turkey, asr: .standard)))
        let expected = [(4, 44), (6, 16), (13, 9), (16, 53), (19, 52), (21, 19)]
        for (item, (hour, minute)) in zip(times, expected) {
            let target = istanbul.calendar.date(bySettingHour: hour, minute: minute, second: 0, of: day)!
            #expect(abs(item.time.timeIntervalSince(target)) <= 60, "\(item.kind)")
        }
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
