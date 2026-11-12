import SwiftUI

struct PrayerTimesView: View {
    @Environment(AppModel.self) private var model
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
                ToolbarItemGroup(placement: .topBarTrailing) {
                    NavigationLink {
                        IslamicCalendarView()
                    } label: {
                        Image(systemName: "moon.stars")
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
        return ScrollView {
            VStack(spacing: 0) {
                header(place: place, next: next, now: now)
                VStack(spacing: 0) {
                    ForEach(today) { item in
                        row(item, isNext: item.time == next?.time, zone: place.timeZone)
                    }
                }
                .overlay(alignment: .top) { Theme.line.frame(height: 1) }
                .padding(.top, 28)
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
    }

    private func header(place: Place, next: PrayerTime?, now: Date) -> some View {
        VStack(spacing: 4) {
            Text(Formats.hijriDate(now, in: place.timeZone, offset: model.settings.hijriOffset))
                .font(.footnote.weight(.medium))
                .tracking(1)
                .foregroundStyle(Theme.gold)
            Text(verbatim: "\(place.displayName) · \(Formats.weekdayDate(now, in: place.timeZone))")
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
        // The star sits above the header text: only its lower points show, without lines through the words.
        .background(alignment: .top) {
            EightPointStar()
                .stroke(Theme.gold.opacity(0.12), lineWidth: 1)
                .frame(width: 520, height: 520)
                .offset(y: -510)
                .accessibilityHidden(true)
        }
    }

    private func row(_ item: PrayerTime, isNext: Bool, zone: TimeZone) -> some View {
        let color = item.kind.isPrayer ? (isNext ? Theme.gold : Theme.ink) : Theme.muted
        let notifying = model.settings.notify.contains(item.kind)
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
                    model.toggleNotify(item.kind)
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

struct MonthView: View {
    @Environment(AppModel.self) private var model
    @State private var anchor = Date()

    var body: some View {
        Group {
            if let place = model.place {
                let calendar = place.calendar
                ScrollView {
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
                                    Text(Formats.time(item.time, in: place.timeZone))
                                }
                            }
                            .font(.footnote.monospacedDigit())
                            .foregroundStyle(calendar.isDateInToday(day.day) ? Theme.gold : Theme.ink)
                            .padding(.vertical, 8)
                        }
                    }
                    .padding(.horizontal, 16)
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
        anchor = Calendar.current.date(byAdding: .month, value: months, to: anchor) ?? anchor
    }
}
