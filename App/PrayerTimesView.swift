import SwiftUI

struct PrayerTimesView: View {
    @Environment(AppModel.self) private var model
    @AppStorage(QuranProgress.pageKey, store: SharedStore.defaults) private var quranPage = 1
    var openSettings: () -> Void = {}
    @ScaledMetric(relativeTo: .largeTitle) private var nameSize: CGFloat = 64

    var body: some View {
        NavigationStack {
            TimelineView(.periodic(from: .now, by: 30)) { context in
                if let place = model.place {
                    if let today = model.times(on: context.date, at: place) {
                        page(place: place, today: today, now: context.date)
                    } else {
                        Text("Prayer times can't be calculated for this place today. This can happen close to the poles.")
                            .multilineTextAlignment(.center)
                            .foregroundStyle(Theme.muted)
                            .padding(32)
                    }
                } else {
                    NoPlaceView()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Theme.background.ignoresSafeArea())
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    // Today's times as a card in the app's colours, with the times as text too.
                    if let place = model.place, let today = model.times(on: .now, at: place) {
                        let zone = place.timeZone
                        let rows = today.map { ($0.kind.title(on: $0.time, in: zone), Formats.time($0.time, in: zone)) }
                        let hijri = Formats.hijriDate(Prayers.hijri(of: .now, place: place, settings: model.settings))
                        let placeAndDate = "\(place.displayName) · \(Formats.weekdayDate(.now, in: zone))"
                        ShareLink(item: CardImage {
                            CardImage.picture(of: TimesCard(hijri: hijri, placeAndDate: placeAndDate, times: rows))
                        }, message: Text(verbatim: ([placeAndDate] + rows.map { "\($0.0) \($0.1)" }).joined(separator: "\n")),
                        preview: SharePreview(Text("Prayer times"))) {
                            Image(systemName: "square.and.arrow.up")
                        }
                        .accessibilityLabel(Text("Share today's times"))
                    }
                }
                ToolbarItemGroup(placement: .topBarTrailing) {
                    NavigationLink {
                        IslamicCalendarView()
                    } label: {
                        Image(systemName: "moon.stars.fill")
                    }
                    .accessibilityLabel(Text("Islamic calendar"))
                    NavigationLink {
                        MonthView()
                    } label: {
                        Image(systemName: "calendar")
                    }
                    .accessibilityLabel(Text("Monthly timetable"))
                }
            }
        }
    }

    private func page(place: Place, today: [PrayerTime], now: Date) -> some View {
        let next = model.next(after: now, at: place)
        let ramadanStart = AppModel.ramadanStart(
            around: now, place: place, hijriOffset: model.settings.hijriOffset, diyanet: model.settings.method == .turkey)
        let hijri = Prayers.hijri(of: now, place: place, settings: model.settings)
        return ScrollView {
            VStack(spacing: 0) {
                header(place: place, next: next, now: now)
                if hijri.month == 9, let start = ramadanStart {
                    RamadanCard(
                        start: start, day: hijri.day ?? 1, today: today, tomorrow: ramadanTomorrow(after: now, at: place),
                        now: now, zone: place.timeZone)
                        .padding(.top, 24)
                }
                VStack(spacing: 0) {
                    ForEach(today) { item in
                        row(item, isNext: item.time == next?.time, zone: place.timeZone)
                    }
                    nightRows(today: today, place: place)
                }
                .overlay(alignment: .top) { Theme.line.frame(height: 1) }
                .padding(.top, 28)
                if hijri.month != 9, let start = ramadanStart {
                    RamadanSoon(start: start, now: now, place: place)
                        .padding(.top, 20)
                }
                // Once the Qur'an has been opened past its first page.
                if quranPage > 1 {
                    ContinueReading(page: quranPage)
                        .padding(.top, hijri.month != 9 && ramadanStart != nil ? 12 : 20)
                }
                Button(action: openSettings) {
                    Text(verbatim: "\(model.settings.method.title) · \(model.settings.asr.shortTitle)")
                        .font(.footnote)
                        .foregroundStyle(Theme.muted)
                        .frame(minHeight: 44)
                }
                .padding(.top, 8)
            }
            .padding(.horizontal, 22)
            .padding(.bottom, 24)
        }
        .scrollBounceBehavior(.basedOnSize)
        .background(SkyBackground(today: today, now: now))
    }

    /// Tomorrow's times while tomorrow is still Ramadan: after iftar, the card turns to tomorrow's suhoor.
    private func ramadanTomorrow(after now: Date, at place: Place) -> [PrayerTime]? {
        guard let tomorrow = place.calendar.date(byAdding: .day, value: 1, to: now),
              Prayers.hijri(of: tomorrow, place: place, settings: model.settings).month == 9 else { return nil }
        return model.times(on: tomorrow, at: place)
    }

    private func header(place: Place, next: PrayerTime?, now: Date) -> some View {
        VStack(spacing: 4) {
            // A small emblem, like the app icon, instead of a large star with lines across the screen.
            EightPointStar()
                .stroke(Theme.gold.opacity(0.6), lineWidth: 1)
                .frame(width: 30, height: 30)
                .padding(.bottom, 8)
                .accessibilityHidden(true)
            Text(verbatim: Formats.hijriDate(Prayers.hijri(of: now, place: place, settings: model.settings)))
                .font(.footnote.weight(.medium))
                .tracking(1)
                .foregroundStyle(Theme.gold)
            // The place name is isolated (U+2068...U+2069) so a Latin city name in Arabic doesn't turn the
            // whole line left to right.
            Text(verbatim: "\u{2068}\(place.displayName)\u{2069} · \(Formats.weekdayDate(now, in: place.timeZone))")
                .font(.subheadline)
                .foregroundStyle(Theme.muted)
            if let next {
                Text("Next prayer")
                    .font(.subheadline)
                    .foregroundStyle(Theme.muted)
                    .padding(.top, 30)
                Text(next.kind.title(on: next.time, in: place.timeZone))
                    .font(.system(size: nameSize, weight: .medium, design: .serif))
                    .foregroundStyle(Theme.ink)
                    .lineLimit(1)
                    .minimumScaleFactor(0.5)
                HStack(spacing: 8) {
                    Text(Formats.time(next.time, in: place.timeZone))
                    Text(verbatim: "·")
                    Text(timerInterval: now...next.time, countsDown: true)
                }
                .font(.body.monospacedDigit())
                .foregroundStyle(Theme.gold)
            }
        }
        .multilineTextAlignment(.center)
        .frame(maxWidth: .infinity)
        .padding(.top, 8)
    }

    /// Midnight and the last third of the night (for tahajjud), counting the night from Maghrib to tomorrow's Fajr.
    @ViewBuilder
    private func nightRows(today: [PrayerTime], place: Place) -> some View {
        if let maghrib = today.first(where: { $0.kind == .maghrib })?.time,
           let tomorrow = place.calendar.date(byAdding: .day, value: 1, to: maghrib),
           let fajr = model.times(on: tomorrow, at: place)?.first(where: { $0.kind == .fajr })?.time, fajr > maghrib {
            let night = fajr.timeIntervalSince(maghrib)
            nightRow("Midnight", maghrib.addingTimeInterval(night / 2), zone: place.timeZone)
            nightRow("Last third of the night", maghrib.addingTimeInterval(night * 2 / 3), zone: place.timeZone)
        }
    }

    private func nightRow(_ title: LocalizedStringKey, _ time: Date, zone: TimeZone) -> some View {
        HStack(spacing: 12) {
            Color.clear.frame(width: 8, height: 8)
            Text(title)
                .font(.system(.body, design: .serif))
            Spacer()
            Text(Formats.time(time, in: zone))
                .font(.subheadline.monospacedDigit())
            Color.clear.frame(width: 44, height: 1)
        }
        .foregroundStyle(Theme.muted)
        .frame(minHeight: 40)
        .overlay(alignment: .bottom) { Theme.line.frame(height: 1) }
        .accessibilityElement(children: .combine)
    }

    private func row(_ item: PrayerTime, isNext: Bool, zone: TimeZone) -> some View {
        let color = item.kind.isPrayer ? (isNext ? Theme.gold : Theme.ink) : Theme.muted
        // Blocked in iPhone Settings: no bell shows as on, and tapping one explains why.
        let blocked = model.notificationStatus == .denied
        let notifying = model.settings.notify.contains(item.kind) && !blocked
        let title = item.kind.title(on: item.time, in: zone)
        return HStack(spacing: 12) {
            Rectangle()
                .fill(isNext ? Theme.gold : Color.clear)
                .frame(width: 8, height: 8)
                .rotationEffect(.degrees(45))
                .accessibilityHidden(true)
            Text(title)
                .font(.system(.title3, design: .serif).weight(isNext ? .semibold : .medium))
            Spacer()
            Text(Formats.time(item.time, in: zone))
                .font(.body.monospacedDigit())
            if item.kind.isPrayer {
                Button {
                    if blocked { model.showNotificationsOff = true } else { model.toggleNotify(item.kind) }
                } label: {
                    Image(systemName: notifying ? "bell" : "bell.slash")
                        .foregroundStyle(notifying ? Theme.gold : Theme.muted)
                        .frame(width: 44, height: 44)
                }
                .accessibilityLabel(Text("\(title) notification"))
                .accessibilityValue(notifying ? Text("On") : Text("Off"))
            } else {
                Color.clear.frame(width: 44, height: 44)
            }
        }
        .foregroundStyle(color)
        .frame(minHeight: 54)
        .overlay(alignment: .bottom) { Theme.line.frame(height: 1) }
    }
}

/// In Ramadan, above today's times: suhoor and iftar, with a countdown to the next of the two.
private struct RamadanCard: View {
    let start: Date
    let day: Int
    let today: [PrayerTime]
    /// nil on the last day of Ramadan.
    let tomorrow: [PrayerTime]?
    let now: Date
    let zone: TimeZone
    @Environment(AppModel.self) private var model

    var body: some View {
        // The next suhoor end and the next iftar: today's, or once passed, tomorrow's.
        let suhoor = today[0].time > now ? today[0].time : tomorrow?[0].time
        let iftar = today[4].time > now ? today[4].time : tomorrow?[4].time
        VStack(spacing: 10) {
            NavigationLink {
                RamadanView(start: start)
            } label: {
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Label {
                            Text("Day \(Formats.number(day)) of Ramadan")
                        } icon: {
                            Image(systemName: "moon.stars.fill")
                        }
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Theme.gold)
                        Spacer()
                        Image(systemName: "chevron.forward")
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(Theme.muted)
                    }
                    HStack(alignment: .firstTextBaseline) {
                        moment("Suhoor ends", suhoor, alignment: .leading)
                        Spacer()
                        moment("Iftar", iftar, alignment: .trailing)
                    }
                    Group {
                        if let suhoor, suhoor < iftar ?? .distantFuture {
                            Text("Suhoor ends in \(Text(timerInterval: now...suhoor, countsDown: true))")
                        } else if let iftar {
                            Text("Iftar in \(Text(timerInterval: now...iftar, countsDown: true))")
                        }
                    }
                    .font(.subheadline.monospacedDigit())
                    .foregroundStyle(Theme.gold)
                }
                .padding(16)
                .background(Theme.card, in: RoundedRectangle(cornerRadius: 16))
            }
            .buttonStyle(.plain)
            if let iftar, model.countdownIftar == iftar {
                Label("The countdown is on your Lock Screen", systemImage: "checkmark.circle.fill")
                    .font(.subheadline)
                    .foregroundStyle(Theme.gold)
                    .frame(maxWidth: .infinity, minHeight: 44)
            } else if let iftar, model.canCountDown(to: iftar, from: now) {
                Button { model.startIftarCountdown() } label: {
                    Label("Iftar countdown on Lock Screen", systemImage: "lock.iphone")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .controlSize(.large)
                .foregroundStyle(Theme.gold)
            } else if today[4].time > now && model.liveActivitiesEnabled {
                Text("The Lock Screen countdown can start from 8 hours before iftar.")
                    .font(.footnote)
                    .foregroundStyle(Theme.muted)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .sensoryFeedback(.success, trigger: model.countdownIftar) { _, new in new != nil }
    }

    private func moment(_ title: LocalizedStringKey, _ time: Date?, alignment: HorizontalAlignment) -> some View {
        VStack(alignment: alignment, spacing: 2) {
            Text(title)
                .font(.caption)
                .foregroundStyle(Theme.muted)
            Text(verbatim: time.map { Formats.time($0, in: zone) } ?? "—")
                .font(.system(.title2, design: .serif).monospacedDigit())
                .foregroundStyle(Theme.ink)
        }
    }
}

/// The top of the screen tinted like the sky at this hour: dawn, day, afternoon and dusk, and plain at night. Dark
/// enough that every text keeps at least 6.3:1; plain with Increase Contrast.
private struct SkyBackground: View {
    let today: [PrayerTime]
    let now: Date
    @Environment(\.colorSchemeContrast) private var contrast

    var body: some View {
        let tint = contrast == .increased ? Theme.background : Self.tint(today: today, now: now)
        LinearGradient(colors: [tint, Theme.background], startPoint: .top, endPoint: .center)
            .ignoresSafeArea()
            .animation(.easeInOut(duration: 3), value: tint)
            .accessibilityHidden(true)
    }

    static func tint(today: [PrayerTime], now: Date) -> Color {
        func time(_ kind: PrayerKind) -> Date? { today.first { $0.kind == kind }?.time }
        guard let fajr = time(.fajr), let sunrise = time(.sunrise), let asr = time(.asr), let maghrib = time(.maghrib),
              let isha = time(.isha) else { return Theme.background }
        if now >= fajr && now < sunrise { return Color(hex: 0x161D36) }  // dawn
        if now >= sunrise && now < asr { return Color(hex: 0x0A2220) }  // day
        if now >= asr && now < maghrib { return Color(hex: 0x221D0E) }  // afternoon
        if now >= maghrib && now < isha { return Color(hex: 0x2A1826) }  // dusk
        return Theme.background  // night
    }
}

/// Back to the page last read in the Qur'an tab.
private struct ContinueReading: View {
    let page: Int
    @AppStorage(OpenScreenIntent.key) private var openScreen = ""

    var body: some View {
        let quran = Quran.shared
        let surah = quran.verses(onPage: page).first.map { quran.surahs[$0.surah - 1] }
        Button {
            openScreen = AppScreen.quran.rawValue
        } label: {
            HStack(spacing: 12) {
                Image(systemName: "book")
                    .font(.title3)
                    .foregroundStyle(Theme.gold)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Continue reading")
                        .foregroundStyle(Theme.ink)
                    HStack(spacing: 0) {
                        if let surah { Text(verbatim: Quran.title(of: surah) + " · ") }
                        Text("Page \(page)")
                    }
                    .font(.subheadline)
                    .foregroundStyle(Theme.muted)
                }
                Spacer()
                Image(systemName: "chevron.forward")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(Theme.muted)
            }
            .padding(16)
            .background(Theme.card, in: RoundedRectangle(cornerRadius: 16))
        }
        .buttonStyle(.plain)
    }
}

/// Outside Ramadan, under today's times: when the next one begins, with its timetable behind it.
private struct RamadanSoon: View {
    let start: Date
    let now: Date
    let place: Place

    var body: some View {
        let calendar = place.calendar
        let days = calendar.dateComponents([.day], from: calendar.startOfDay(for: now), to: start).day ?? 0
        NavigationLink {
            RamadanView(start: start)
        } label: {
            HStack(spacing: 12) {
                Image(systemName: "moon.stars")
                    .font(.title3)
                    .foregroundStyle(Theme.gold)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Ramadan begins in \(Formats.days(days))")
                        .foregroundStyle(Theme.ink)
                    Text(verbatim: Formats.weekdayDate(start, in: place.timeZone))
                        .font(.subheadline)
                        .foregroundStyle(Theme.muted)
                }
                Spacer()
                Image(systemName: "chevron.forward")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(Theme.muted)
            }
            .padding(16)
            .background(Theme.card, in: RoundedRectangle(cornerRadius: 16))
        }
        .buttonStyle(.plain)
    }
}

struct MonthView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dynamicTypeSize) private var typeSize
    @State private var anchor = Date()

    var body: some View {
        Group {
            if let place = model.place {
                let calendar = place.calendar
                ScrollView {
                    if typeSize.isAccessibilitySize {
                        // Seven columns don't fit at the largest text sizes: each day lists its times instead.
                        LazyVStack(alignment: .leading, spacing: 22) {
                            ForEach(model.month(containing: anchor, at: place)) { day in
                                let today = calendar.isDateInToday(day.day)
                                VStack(alignment: .leading, spacing: 6) {
                                    Text(verbatim: Formats.weekdayDate(day.day, in: place.timeZone))
                                        .font(.headline)
                                        // Today in bold as well as gold: not by colour alone.
                                        .foregroundStyle(today ? Theme.gold : Theme.ink)
                                        .accessibilityAddTraits(.isHeader)
                                    ForEach(day.times) { item in
                                        ViewThatFits(in: .horizontal) {
                                            HStack(alignment: .firstTextBaseline) {
                                                Text(item.kind.title)
                                                Spacer(minLength: 12)
                                                Text(Formats.gridTime(item.time, in: place.timeZone))
                                            }
                                            VStack(alignment: .leading) {
                                                Text(item.kind.title)
                                                Text(Formats.gridTime(item.time, in: place.timeZone))
                                            }
                                        }
                                        .accessibilityElement(children: .combine)
                                    }
                                }
                                .fontWeight(today ? .bold : .regular)
                                .foregroundStyle(Theme.ink)
                            }
                        }
                        .padding(16)
                    } else {
                        Grid(horizontalSpacing: 6, verticalSpacing: 0) {
                            GridRow {
                                Color.clear.gridCellUnsizedAxes([.horizontal, .vertical])
                                ForEach(PrayerKind.allCases) { kind in
                                    Group {
                                        if kind == .sunrise {
                                            Image(systemName: "sunrise").accessibilityLabel(Text(kind.title))
                                        } else {
                                            Text(kind.title)
                                        }
                                    }
                                    .lineLimit(1)
                                    .minimumScaleFactor(0.7)
                                }
                            }
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(Theme.gold)
                            .padding(.vertical, 10)
                            ForEach(model.month(containing: anchor, at: place)) { day in
                                Divider().overlay(Theme.line)
                                GridRow {
                                    Text(verbatim: Formats.dayOfMonth(day.day, in: place.timeZone))
                                        .gridColumnAlignment(.leading)
                                    ForEach(day.times) { item in
                                        Text(Formats.gridTime(item.time, in: place.timeZone))
                                    }
                                }
                                .font(.footnote.monospacedDigit())
                                // Today in bold as well as gold: not by colour alone.
                                .fontWeight(calendar.isDateInToday(day.day) ? .bold : .regular)
                                .foregroundStyle(calendar.isDateInToday(day.day) ? Theme.gold : Theme.ink)
                                .padding(.vertical, 8)
                            }
                        }
                        .padding(.horizontal, 16)
                        // Seven columns fit up to this text size; at the accessibility sizes the list above takes over.
                        .dynamicTypeSize(...DynamicTypeSize.xxLarge)
                    }
                }
                .navigationTitle(Formats.monthTitle(anchor, in: place.timeZone))
            } else {
                NoPlaceView()
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.background.ignoresSafeArea())
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                Button { shift(-1) } label: { Image(systemName: "chevron.backward") }
                    .accessibilityLabel(Text("Previous month"))
                Button { shift(1) } label: { Image(systemName: "chevron.forward") }
                    .accessibilityLabel(Text("Next month"))
            }
        }
    }

    private func shift(_ months: Int) {
        // Gregorian months, also on an iPhone set to the Islamic or Persian calendar.
        let calendar = model.place?.calendar ?? Calendar(identifier: .gregorian)
        anchor = calendar.date(byAdding: .month, value: months, to: anchor) ?? anchor
    }
}
