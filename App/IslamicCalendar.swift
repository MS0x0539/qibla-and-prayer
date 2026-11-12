import SwiftUI

/// Special days and nights of the Islamic year.
enum IslamicDay: CaseIterable {
    case newYear, ashura, arbaeen, mawlid, raghaib, israMiraj, mabath, baraah, ramadan, laylatAlQadr, eidAlFitr,
         arafah, eidAlAdha, ghadir

    /// The Hijri month and day(s). Shia (Ja'fari) observance, as in the calendars of Ayatollah Sistani's office:
    /// the Prophet's birthday on 17 Rabi' al-Awwal, 27 Rajab as the Mab'ath (the Mi'raj falls in Ramadan),
    /// Laylat al-Qadr on the nights of 19, 21 and 23 Ramadan, and Arba'een and Ghadir as well.
    /// Regaib Kandili has no fixed date (the first Friday of Rajab); islamicDates places it.
    func hijriDays(shia: Bool) -> [(month: Int, day: Int)] {
        switch self {
        case .newYear: [(1, 1)]
        case .raghaib: []
        case .ashura: [(1, 10)]
        case .arbaeen: shia ? [(2, 20)] : []
        case .mawlid: [(3, shia ? 17 : 12)]
        case .israMiraj: shia ? [] : [(7, 27)]
        case .mabath: shia ? [(7, 27)] : []
        case .baraah: [(8, 15)]
        case .ramadan: [(9, 1)]
        case .laylatAlQadr: shia ? [(9, 19), (9, 21), (9, 23)] : [(9, 27)]
        case .eidAlFitr: [(10, 1)]
        case .arafah: [(12, 9)]
        case .eidAlAdha: [(12, 10)]
        case .ghadir: shia ? [(12, 18)] : []
        }
    }

    /// A night begins at sunset on the evening before its Hijri date. Shia celebrate the Prophet's birthday by day.
    func isNight(shia: Bool) -> Bool {
        switch self {
        case .mawlid: !shia
        case .raghaib, .israMiraj, .baraah, .laylatAlQadr: true
        default: false
        }
    }

    func title(shia: Bool) -> String {
        switch self {
        case .newYear: String(localized: "Islamic New Year", bundle: .app)
        case .ashura: String(localized: "Ashura", bundle: .app)
        case .arbaeen: String(localized: "Arba'een", bundle: .app)
        case .mawlid: shia ? String(localized: "Birth of the Prophet", bundle: .app) : String(localized: "Mawlid", bundle: .app)
        case .raghaib: String(localized: "Laylat al-Raghaib", bundle: .app)
        case .israMiraj: String(localized: "Isra and Mi'raj", bundle: .app)
        case .mabath: String(localized: "Eid al-Mab'ath", bundle: .app)
        case .baraah: String(localized: "Laylat al-Bara'ah", bundle: .app)
        case .ramadan: String(localized: "Ramadan begins", bundle: .app)
        case .laylatAlQadr: String(localized: "Laylat al-Qadr", bundle: .app)
        case .eidAlFitr: String(localized: "Eid al-Fitr", bundle: .app)
        case .arafah: String(localized: "Day of Arafah", bundle: .app)
        case .eidAlAdha: String(localized: "Eid al-Adha", bundle: .app)
        case .ghadir: String(localized: "Eid al-Ghadir", bundle: .app)
        }
    }
}

struct IslamicDate: Identifiable {
    let day: IslamicDay
    /// The Gregorian day; for a night, the day on whose evening it begins.
    let date: Date
    let isNight: Bool
    var id: String { "\(day)-\(date.timeIntervalSince1970)" }
}

struct RamadanDay: Identifiable {
    let hijriDay: Int
    let hijriYear: Int
    let date: Date
    let times: [PrayerTime]?
    var id: Date { date }
}

extension AppModel {
    /// Every special day in a Gregorian year, for Sunni or Shia observance, in Diyanet's calendar (with its
    /// Regaib Kandili) or Umm al-Qura's; some years (2030) have two Ramadans.
    static func islamicDates(
        inYear year: Int, place: Place, hijriOffset: Int, shia: Bool = false, diyanet: Bool = false
    ) -> [IslamicDate] {
        let calendar = place.calendar
        // Through 1 January of the next year: a night on that Hijri date begins on the evening of 31 December.
        // The bound is 2 January, because where clocks go forward at midnight (Cairo, Beirut) `day` stays at 01:00.
        guard var day = calendar.date(from: DateComponents(year: year, month: 1, day: 1)),
              let end = calendar.date(from: DateComponents(year: year + 1, month: 1, day: 2)) else { return [] }
        var dates: [IslamicDate] = []
        while day < end {
            let parts = Prayers.hijri(of: day, place: place, offset: hijriOffset, diyanet: diyanet)
            // Regaib Kandili: the night before the first Friday of Rajab.
            if diyanet, parts.month == 7, (parts.day ?? 8) <= 7, calendar.component(.weekday, from: day) == 6,
               let evening = calendar.date(byAdding: .day, value: -1, to: day), calendar.component(.year, from: evening) == year {
                dates.append(IslamicDate(day: .raghaib, date: evening, isNight: true))
            }
            for event in IslamicDay.allCases
            where event.hijriDays(shia: shia).contains(where: { $0.month == parts.month && $0.day == parts.day }) {
                let night = event.isNight(shia: shia)
                let date = night ? (calendar.date(byAdding: .day, value: -1, to: day) ?? day) : day
                if calendar.component(.year, from: date) == year {
                    dates.append(IslamicDate(day: event, date: date, isNight: night))
                }
            }
            guard let next = calendar.date(byAdding: .day, value: 1, to: day) else { break }
            day = next
        }
        return dates.sorted { $0.date < $1.date }
    }

    /// The days of the Ramadan that begins on `start`, with each day's prayer times.
    static func ramadanDays(from start: Date, place: Place, settings: AppSettings) -> [RamadanDay] {
        var days: [RamadanDay] = []
        var day = start
        for _ in 0..<31 {
            let parts = Prayers.hijri(of: day, place: place, settings: settings)
            guard parts.month == 9 else { break }
            days.append(RamadanDay(
                hijriDay: parts.day ?? 0, hijriYear: parts.year ?? 0, date: day,
                times: Prayers.compute(on: day, place: place, settings: settings)))
            guard let next = place.calendar.date(byAdding: .day, value: 1, to: day) else { break }
            day = next
        }
        return days
    }

    /// The first day of the Ramadan under way on `date`, or else of the next one. Computed directly
    /// rather than day by day: the Prayer times screen asks on every refresh.
    static func ramadanStart(around date: Date, place: Place, hijriOffset: Int, diyanet: Bool = false) -> Date? {
        let today = Prayers.hijri(of: date, place: place, offset: hijriOffset, diyanet: diyanet)
        guard let year = today.year, let month = today.month else { return nil }
        let target = month <= 9 ? year : year + 1
        let calendar = place.calendar
        if diyanet, let first = DiyanetCalendar.firstDay(year: target, month: 9),
           let day = calendar.date(from: DateComponents(year: first.year, month: first.month, day: first.day, hour: 12)),
           let local = calendar.date(byAdding: .day, value: -hijriOffset, to: day) {
            return calendar.startOfDay(for: local)
        }
        var islamic = Calendar(identifier: .islamicUmmAlQura)
        islamic.timeZone = place.timeZone
        guard let first = islamic.date(from: DateComponents(year: target, month: 9, day: 1, hour: 12)),
              let local = calendar.date(byAdding: .day, value: -hijriOffset, to: first) else { return nil }
        return calendar.startOfDay(for: local)
    }
}

struct IslamicCalendarView: View {
    @Environment(AppModel.self) private var model
    @State private var year = Calendar(identifier: .gregorian).component(.year, from: Date())

    var body: some View {
        Group {
            if let place = model.place {
                let diyanet = model.settings.method == .turkey
                // Diyanet's table covers September 2018 to December 2035; other years follow Umm al-Qura.
                let diyanetYear = diyanet && DiyanetCalendar.hijri(year: year, month: 1, day: 1) != nil
                    && DiyanetCalendar.hijri(year: year, month: 12, day: 30) != nil
                let dates = AppModel.islamicDates(
                    inYear: year, place: place, hijriOffset: model.settings.hijriOffset, shia: model.settings.school == .jafari,
                    diyanet: diyanet)
                let today = place.calendar.startOfDay(for: Date())
                let upcoming = dates.first { $0.date >= today }?.id
                List {
                    Section {
                        ForEach(dates) { item in
                            row(item, place: place, isNext: item.id == upcoming)
                                .listRowBackground(Theme.background)
                        }
                    } footer: {
                        if diyanetYear {
                            Text("Dates follow Diyanet's calendar. You can adjust the Hijri date in Settings.")
                        } else {
                            Text("Dates follow the Umm al-Qura calendar. Moon sighting where you live can move them by a day; you can adjust the Hijri date in Settings.")
                        }
                    }
                }
                .scrollContentBackground(.hidden)
            } else {
                NoPlaceView()
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.background.ignoresSafeArea())
        .navigationTitle(Text("Islamic calendar \(Formats.number(year))"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                Button { year -= 1 } label: { Image(systemName: "chevron.backward") }
                    .accessibilityLabel(Text("Previous year"))
                Button { year += 1 } label: { Image(systemName: "chevron.forward") }
                    .accessibilityLabel(Text("Next year"))
            }
        }
    }

    @ViewBuilder
    private func row(_ item: IslamicDate, place: Place, isNext: Bool) -> some View {
        let weekday = Formats.weekdayDate(item.date, in: place.timeZone)
        let hijriDay = item.isNight ? (place.calendar.date(byAdding: .day, value: 1, to: item.date) ?? item.date) : item.date
        let content = VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 8) {
                // The same diamond as the next prayer, so the next day doesn't stand out by colour alone.
                if isNext {
                    Rectangle()
                        .fill(Theme.gold)
                        .frame(width: 8, height: 8)
                        .rotationEffect(.degrees(45))
                        .accessibilityHidden(true)
                }
                Text(item.day.title(shia: model.settings.school == .jafari))
                    .font(.system(.headline, design: .serif))
                    .foregroundStyle(isNext ? Theme.gold : Theme.ink)
            }
            (item.isNight ? Text("Evening of \(weekday)") : Text(verbatim: weekday))
                .font(.subheadline)
                .foregroundStyle(Theme.ink)
            Text(verbatim: Formats.hijriDate(Prayers.hijri(of: hijriDay, place: place, settings: model.settings)))
                .font(.footnote)
                .foregroundStyle(Theme.muted)
        }
        .padding(.vertical, 4)
        if item.day == .ramadan {
            NavigationLink {
                RamadanView(start: item.date)
            } label: {
                content
            }
        } else {
            content
        }
    }
}

/// Suhoor and iftar times for every day of one Ramadan (in Turkish: the imsakiye).
struct RamadanView: View {
    @Environment(AppModel.self) private var model
    let start: Date

    var body: some View {
        Group {
            if let place = model.place {
                let days = AppModel.ramadanDays(from: start, place: place, settings: model.settings)
                ScrollView {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Suhoor ends at Fajr. Iftar is at Maghrib.")
                            .foregroundStyle(Theme.muted)
                        Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 0) {
                            GridRow {
                                Text("Day")
                                Color.clear.gridCellUnsizedAxes([.horizontal, .vertical])
                                Text("Suhoor ends")
                                Text("Iftar")
                            }
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(Theme.gold)
                            .padding(.vertical, 8)
                            ForEach(days) { day in
                                Divider().overlay(Theme.line)
                                GridRow {
                                    Text(verbatim: Formats.number(day.hijriDay))
                                    Text(verbatim: Formats.shortDate(day.date, in: place.timeZone))
                                    Text(verbatim: day.times.map { Formats.time($0[0].time, in: place.timeZone) } ?? "—")
                                    Text(verbatim: day.times.map { Formats.time($0[4].time, in: place.timeZone) } ?? "—")
                                }
                                .font(.footnote.monospacedDigit())
                                .fontWeight(place.calendar.isDateInToday(day.date) ? .bold : .regular)
                                .foregroundStyle(place.calendar.isDateInToday(day.date) ? Theme.gold : Theme.ink)
                                .padding(.vertical, 8)
                            }
                        }
                    }
                    .padding(16)
                }
                .navigationTitle(Text("Ramadan \(Formats.number(days.first?.hijriYear ?? 0))"))
            } else {
                NoPlaceView()
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.background.ignoresSafeArea())
        .navigationBarTitleDisplayMode(.inline)
    }
}
