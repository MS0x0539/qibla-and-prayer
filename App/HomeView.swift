import SwiftUI

/// Home: the day at a glance. The next prayer and today's five with a circle to tick each one prayed, yesterday's
/// unticked prayers once, then the page last read, the next special day and the tasbih.
struct HomeView: View {
    @Environment(AppModel.self) private var model
    @AppStorage(Prayed.key, store: SharedStore.defaults) private var prayed = ""
    @AppStorage(Prayed.reviewedKey, store: SharedStore.defaults) private var reviewed = ""
    @AppStorage(QuranProgress.pageKey, store: SharedStore.defaults) private var quranPage = 1
    @AppStorage(TasbihStore.totalKey, store: TasbihStore.defaults) private var tasbihTotal = 0
    @State private var changingPlace = false
    @State private var special: IslamicDate?
    /// Opens a page of Menu.
    var openMenu: (MenuPage) -> Void = { _ in }

    var body: some View {
        NavigationStack {
            Group {
                if let place = model.place {
                    // Each minute: a time that has come moves the card on, and midnight starts a new day.
                    TimelineView(.everyMinute) { context in
                        page(place: place, now: context.date)
                    }
                } else {
                    NoPlaceView()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Theme.background.ignoresSafeArea())
            .toolbar(.hidden, for: .navigationBar)
            .sheet(isPresented: $changingPlace) {
                NavigationStack {
                    CitySearchView()
                        .toolbar {
                            if !model.settings.useCurrentLocation {
                                ToolbarItem(placement: .topBarLeading) {
                                    Button("Use my location") {
                                        model.useCurrentLocation()
                                        changingPlace = false
                                    }
                                }
                            }
                        }
                }
            }
        }
    }

    private func page(place: Place, now: Date) -> some View {
        let day = model.prayerDay(at: now, place: place)
        let dayKey = Prayed.dayKey(day, in: place.calendar)
        return ScrollView {
            VStack(spacing: 16) {
                VStack(spacing: 4) {
                    Text(verbatim: Formats.hijriDate(Prayers.hijri(of: now, place: place, settings: model.settings)))
                        .font(.footnote.weight(.medium))
                        .tracking(1)
                        .foregroundStyle(Theme.gold)
                    Text(verbatim: Formats.weekdayDate(now, in: place.timeZone))
                        .font(.subheadline)
                        .foregroundStyle(Theme.muted)
                }
                .multilineTextAlignment(.center)
                .padding(.top, 8)
                PrayerCard(place: place, day: day, dayKey: dayKey, now: now, prayed: $prayed) {
                    changingPlace = true
                }
                if let missing = yesterday(before: day, place: place) {
                    YesterdayCard(missing: missing.prayers) { addToMissed in
                        if addToMissed {
                            Prayed.addToMissed(missing.prayers.map(\.kind))
                        } else {
                            prayed = Prayed.setting(missing.prayers.map(\.kind), on: missing.key, to: true, in: prayed)
                        }
                        reviewed = missing.key
                    }
                }
                if quranPage > 1 {
                    ContinueReading(page: quranPage)
                }
                if let special {
                    Button { openMenu(.calendar) } label: {
                        CardRow(symbol: "moon.stars", title: Text(verbatim: special.day.title(shia: model.settings.school == .jafari)),
                                detail: Text(verbatim: Self.relative(special.date, from: now, in: place.calendar)))
                    }
                    .buttonStyle(.plain)
                }
                Button { openMenu(.tasbih) } label: {
                    CardRow(symbol: "circle.dotted", title: Text("Tasbih"),
                            detail: tasbihTotal > 0 ? Text("Total \(Formats.number(tasbihTotal))") : Text("Start counting"))
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal)
            .padding(.bottom, 24)
        }
        .scrollBounceBehavior(.basedOnSize)
        .task(id: dayKey) { special = nextSpecialDay(place: place, now: now) }
    }

    /// The day before's prayers left unticked, once, and only where ticks were used that day.
    private func yesterday(before day: Date, place: Place) -> (key: String, prayers: [PrayerTime])? {
        guard let previous = place.calendar.date(byAdding: .day, value: -1, to: day) else { return nil }
        let key = Prayed.dayKey(previous, in: place.calendar)
        let ticked = Prayed.parse(prayed)[key] ?? []
        guard reviewed != key, !ticked.isEmpty else { return nil }
        let missing = (model.times(on: previous, at: place) ?? []).filter { $0.kind.isPrayer && !ticked.contains($0.kind) }
        return missing.isEmpty ? nil : (key, missing)
    }

    /// The next special day or night of the Islamic calendar, today included.
    private func nextSpecialDay(place: Place, now: Date) -> IslamicDate? {
        let year = place.calendar.component(.year, from: now)
        let today = place.calendar.startOfDay(for: now)
        let shia = model.settings.school == .jafari
        let diyanet = model.settings.method == .turkey
        return [year, year + 1].lazy
            .flatMap { AppModel.islamicDates(inYear: $0, place: place, hijriOffset: model.settings.hijriOffset,
                                             shia: shia, diyanet: diyanet) }
            .first { $0.date >= today }
    }

    /// "today", "tomorrow", "in 12 days", in the app's language.
    static func relative(_ date: Date, from now: Date, in calendar: Calendar) -> String {
        let days = calendar.dateComponents([.day], from: calendar.startOfDay(for: now), to: calendar.startOfDay(for: date)).day ?? 0
        let formatter = RelativeDateTimeFormatter()
        formatter.locale = .app
        formatter.dateTimeStyle = .named
        return formatter.localizedString(from: DateComponents(day: days))
    }
}

/// The next prayer with its countdown, a line through the day, and the day's five prayers with a circle each to
/// tick once prayed. The day runs from Fajr to the next Fajr.
private struct PrayerCard: View {
    let place: Place
    let day: Date
    let dayKey: String
    let now: Date
    @Binding var prayed: String
    let changePlace: () -> Void
    @Environment(AppModel.self) private var model
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        let list = model.times(on: day, at: place) ?? []
        let next = model.next(after: now, at: place)
        let ticked = Prayed.parse(prayed)[dayKey] ?? []
        let prayers = list.filter(\.kind.isPrayer)
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Label {
                    Text(verbatim: place.displayName)
                } icon: {
                    Image(systemName: model.settings.useCurrentLocation ? "location.fill" : "mappin.and.ellipse")
                        .foregroundStyle(Theme.gold)
                }
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Theme.ink)
                .lineLimit(1)
                Spacer(minLength: 8)
                Button("Change", action: changePlace)
                    .font(.subheadline)
                    .foregroundStyle(Theme.gold)
            }
            if let next {
                ViewThatFits(in: .horizontal) {
                    HStack(alignment: .firstTextBaseline, spacing: 12) { nextName(next); Spacer(minLength: 0); countdown(to: next.time) }
                    VStack(alignment: .leading, spacing: 4) { nextName(next); countdown(to: next.time) }
                }
            }
            DayLine(times: list.map(\.time), now: now)
                .frame(height: 12)
                .accessibilityHidden(true)
            let layout = typeSize.isAccessibilitySize
                ? AnyLayout(VStackLayout(alignment: .leading, spacing: 4))
                : AnyLayout(HStackLayout(alignment: .top, spacing: 0))
            layout {
                ForEach(prayers) { item in
                    PrayerTick(item: item, zone: place.timeZone, isNext: item.time == next?.time, started: item.time <= now,
                               isTicked: ticked.contains(item.kind), wide: typeSize.isAccessibilitySize) {
                        prayed = Prayed.setting([item.kind], on: dayKey, to: !ticked.contains(item.kind), in: prayed)
                    }
                }
            }
            Text("Prayed today: \(Formats.number(ticked.count)) of \(Formats.number(prayers.count))")
                .font(.footnote)
                .foregroundStyle(Theme.muted)
        }
        .padding(18)
        .background(Theme.card, in: RoundedRectangle(cornerRadius: 22))
        .overlay(RoundedRectangle(cornerRadius: 22).strokeBorder(Theme.line, lineWidth: 1))
        .sensoryFeedback(.success, trigger: ticked.count) { old, new in new > old }
    }

    private func nextName(_ next: PrayerTime) -> some View {
        Text(next.kind.title(on: next.time, in: place.timeZone))
            .font(.system(.largeTitle, design: .serif).weight(.medium))
            .foregroundStyle(Theme.gold)
            .lineLimit(1)
            .minimumScaleFactor(0.7)
    }

    private func countdown(to time: Date) -> some View {
        Text("in \(Text(timerInterval: now...max(time, now), countsDown: true))")
            .font(.title3.monospacedDigit())
            .foregroundStyle(Theme.ink)
    }
}

/// One prayer of the day: its name and time, and a circle to tick it once prayed (from the moment its time begins).
private struct PrayerTick: View {
    let item: PrayerTime
    let zone: TimeZone
    let isNext: Bool
    let started: Bool
    let isTicked: Bool
    /// The largest text sizes: name, time and circle on one line.
    let wide: Bool
    let toggle: () -> Void

    var body: some View {
        // The prayer, not the time: Turkish calls Fajr's time İmsak and the prayer Sabah.
        let name = item.kind == .fajr
            ? String(localized: "qada.fajr", defaultValue: "Fajr", bundle: .app) : item.kind.title(on: item.time, in: zone)
        let time = Text(Formats.time(item.time, in: zone)).monospacedDigit()
        Group {
            if wide {
                HStack(spacing: 12) {
                    Text(verbatim: name)
                    Spacer(minLength: 8)
                    time
                    circle(name: name)
                }
            } else {
                VStack(spacing: 6) {
                    Text(verbatim: name)
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)
                    time
                        .font(.footnote.monospacedDigit())
                    circle(name: name)
                }
                .frame(maxWidth: .infinity)
            }
        }
        .font(.subheadline.weight(isNext ? .semibold : .regular))
        .foregroundStyle(isNext ? Theme.gold : started ? Theme.ink : Theme.muted)
    }

    private func circle(name: String) -> some View {
        Button(action: toggle) {
            ZStack {
                Circle()
                    .strokeBorder(isTicked ? Theme.gold : started ? Theme.ink.opacity(0.55) : Theme.muted.opacity(0.35),
                                  lineWidth: 1.5)
                if isTicked {
                    Circle().fill(Theme.gold)
                    Image(systemName: "checkmark")
                        .font(.footnote.weight(.bold))
                        .foregroundStyle(Theme.background)
                }
            }
            .frame(width: 28, height: 28)
            .frame(width: 44, height: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!started)
        .accessibilityLabel(Text(verbatim: name))
        .accessibilityValue(isTicked ? Text("Prayed") : Text("Not prayed"))
    }
}

/// The prayer day from Fajr to Isha as a line: gold up to now, a dot at each time, a larger one at now.
private struct DayLine: View {
    let times: [Date]
    let now: Date

    var body: some View {
        GeometryReader { geometry in
            let start = times.first ?? now
            let span = max((times.last ?? now).timeIntervalSince(start), 1)
            let width = max(geometry.size.width - 12, 0)
            let x = { (date: Date) -> CGFloat in 6 + width * CGFloat(min(max(date.timeIntervalSince(start) / span, 0), 1)) }
            ZStack(alignment: .leading) {
                Capsule().fill(Theme.line)
                    .frame(width: width, height: 3)
                    .offset(x: 6)
                Capsule().fill(Theme.gold)
                    .frame(width: max(x(now) - 6, 0), height: 3)
                    .offset(x: 6)
                ForEach(times, id: \.self) { time in
                    Circle()
                        .fill(time <= now ? Theme.gold : Theme.card)
                        .overlay(Circle().strokeBorder(Theme.gold, lineWidth: 1.5))
                        .frame(width: 8, height: 8)
                        .offset(x: x(time) - 4)
                }
                Circle()
                    .fill(Theme.ink)
                    .frame(width: 12, height: 12)
                    .offset(x: x(now) - 6)
            }
            .frame(width: geometry.size.width, height: geometry.size.height, alignment: .leading)
        }
        // Time runs the way the text does: right to left in Arabic.
        .flipsForRightToLeftLayoutDirection(true)
    }
}

/// Yesterday's prayers that were not ticked: ticked now, or added to the missed prayers.
private struct YesterdayCard: View {
    let missing: [PrayerTime]
    /// True: add them to the missed prayers; false: they were prayed.
    let resolve: (Bool) -> Void

    var body: some View {
        let names = missing.map { $0.kind == .fajr
            ? String(localized: "qada.fajr", defaultValue: "Fajr", bundle: .app) : $0.kind.title }
        VStack(alignment: .leading, spacing: 12) {
            Text("Yesterday")
                .font(.headline)
                .foregroundStyle(Theme.ink)
            Text("Not ticked: \(names.formatted(.list(type: .and).locale(.app))).")
                .font(.subheadline)
                .foregroundStyle(Theme.muted)
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 10) { buttons }
                VStack(alignment: .leading, spacing: 10) { buttons }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(18)
        .background(Theme.card, in: RoundedRectangle(cornerRadius: 22))
        .overlay(RoundedRectangle(cornerRadius: 22).strokeBorder(Theme.line, lineWidth: 1))
    }

    @ViewBuilder private var buttons: some View {
        Button("I prayed them") { resolve(false) }
            .buttonStyle(.bordered)
        Button("Add to missed prayers") { resolve(true) }
            .buttonStyle(.borderedProminent)
            .foregroundStyle(Theme.background)
    }
}

/// A row that opens another part of the app: a gold symbol, a title and a detail.
struct CardRow: View {
    let symbol: String
    let title: Text
    let detail: Text

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: symbol)
                .font(.title3)
                .foregroundStyle(Theme.gold)
                .frame(width: 28)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                title
                    .foregroundStyle(Theme.ink)
                detail
                    .font(.subheadline)
                    .foregroundStyle(Theme.muted)
            }
            Spacer(minLength: 8)
            Image(systemName: "chevron.forward")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(Theme.muted)
                .accessibilityHidden(true)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.card, in: RoundedRectangle(cornerRadius: 16))
        .contentShape(RoundedRectangle(cornerRadius: 16))
    }
}

/// Back to the page last read in the Qur'an tab.
struct ContinueReading: View {
    let page: Int
    @AppStorage(OpenScreenIntent.key) private var openScreen = ""

    var body: some View {
        let quran = Quran.shared
        let surah = quran.verses(onPage: page).first.map { quran.surahs[$0.surah - 1] }
        Button {
            openScreen = AppScreen.quran.rawValue
        } label: {
            CardRow(symbol: "book", title: Text("Continue reading"),
                    detail: Text(verbatim: (surah.map { Quran.title(of: $0) + " · " } ?? ""))
                        + Text("Page \(page)"))
        }
        .buttonStyle(.plain)
    }
}
