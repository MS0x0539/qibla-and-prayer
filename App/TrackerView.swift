import SwiftUI

/// The prayers ticked this week, and today's fast and iftar, kept only on this iPhone. (Menu → Prayer tracker)
struct PrayerTrackerView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dynamicTypeSize) private var typeSize
    /// The days fasted, as "2026-11-12" separated by commas.
    @AppStorage("fastingDays") private var fastingDays = ""
    @AppStorage(Prayed.key, store: SharedStore.defaults) private var prayed = ""

    var body: some View {
        // Redrawn every minute, so iftar and midnight ("today") arrive while the page is open.
        TimelineView(.everyMinute) { context in
            form(now: context.date)
        }
        .trackerPage("Prayer tracker")
        .sensoryFeedback(.success, trigger: model.countdownIftar) { _, new in new != nil }
    }

    private func form(now: Date) -> some View {
        let today = dayKey(now)
        return Form {
            if let place = model.place {
                week(place: place, now: now)
            }
            Section {
                Toggle("I'm fasting today", isOn: fasting(on: today))
                if days.contains(today), let place = model.place, let maghrib = model.times(on: now, at: place)?[4].time {
                    LabeledContent("Iftar", value: Formats.time(maghrib, in: place.timeZone))
                    if now < maghrib {
                        Text("Iftar in \(Text(timerInterval: now...maghrib, countsDown: true))")
                            .monospacedDigit()
                            .foregroundStyle(Theme.gold)
                        if model.countdownIftar == maghrib {
                            Label("The countdown is on your Lock Screen", systemImage: "checkmark.circle.fill")
                                .foregroundStyle(Theme.gold)
                        } else if model.canCountDown(to: maghrib, from: now) {
                            Button {
                                model.startIftarCountdown()
                            } label: {
                                Label("Iftar countdown on Lock Screen", systemImage: "lock.iphone")
                            }
                        } else if model.liveActivitiesEnabled {
                            Text("The Lock Screen countdown can start from 8 hours before iftar.")
                                .font(.footnote)
                                .foregroundStyle(Theme.muted)
                        }
                    }
                }
            } header: {
                Text("Today")
            } footer: {
                Text("Days fasted this year: \(Formats.number(days.filter { $0.hasPrefix(today.prefix(4)) }.count))")
            }
            .listRowBackground(Theme.card)
        }
    }

    /// The last seven prayer days, today first, with a circle for each prayer: ticked on Home or Prayer times, or
    /// here afterwards. At the largest text sizes, each day's count instead.
    private func week(place: Place, now: Date) -> some View {
        let calendar = place.calendar
        let today = model.prayerDay(at: now, place: place)
        let days = (0..<7).compactMap { calendar.date(byAdding: .day, value: -$0, to: today) }
        let log = Prayed.parse(prayed)
        let todayTimes = model.times(on: today, at: place) ?? []
        let month = String(Prayed.dayKey(today, in: calendar).prefix(7))
        let thisMonth = log.filter { $0.key.hasPrefix(month) }.values.reduce(0) { $0 + $1.count }
        var style = Date.FormatStyle.dateTime.weekday(.abbreviated).day()
        style.timeZone = place.timeZone
        style.locale = .app
        return Section {
            if !typeSize.isAccessibilitySize {
                HStack(spacing: 0) {
                    Spacer(minLength: 0)
                    ForEach(Prayed.prayers) { kind in
                        Text(verbatim: Self.prayerName(kind))
                            .lineLimit(1)
                            .minimumScaleFactor(0.6)
                            .frame(width: 44)
                    }
                }
                .font(.caption2)
                .foregroundStyle(Theme.muted)
                .accessibilityHidden(true)
            }
            ForEach(days, id: \.self) { day in
                let key = Prayed.dayKey(day, in: calendar)
                let ticked = log[key] ?? []
                let label = day == today ? String(localized: "Today", bundle: .app) : day.formatted(style)
                if typeSize.isAccessibilitySize {
                    LabeledContent(label, value: String(localized: "\(Formats.number(ticked.count)) of \(Formats.number(5))", bundle: .app))
                } else {
                    HStack(spacing: 0) {
                        Text(verbatim: label)
                        Spacer(minLength: 4)
                        ForEach(Prayed.prayers) { kind in
                            // Today's prayers from the moment their time begins.
                            let started = day != today || (todayTimes.first { $0.kind == kind }?.time ?? .distantFuture) <= now
                            Button {
                                prayed = Prayed.setting([kind], on: key, to: !ticked.contains(kind), in: prayed)
                            } label: {
                                Image(systemName: ticked.contains(kind) ? "checkmark.circle.fill" : "circle")
                                    .font(.title3)
                                    .foregroundStyle(ticked.contains(kind) ? Theme.gold
                                        : started ? Theme.ink.opacity(0.6) : Theme.muted.opacity(0.4))
                                    .frame(width: 44, height: 44)
                            }
                            .buttonStyle(.plain)
                            .disabled(!started)
                            .accessibilityLabel(Text(verbatim: "\(label), \(Self.prayerName(kind))"))
                            .accessibilityValue(ticked.contains(kind) ? Text("Prayed") : Text("Not prayed"))
                        }
                    }
                }
            }
        } header: {
            Text("Prayed")
        } footer: {
            Text("Ticked this month: \(Formats.number(thisMonth))")
        }
        .listRowBackground(Theme.card)
    }

    /// The prayer, not the time: Turkish calls Fajr's time İmsak and the prayer Sabah.
    static func prayerName(_ kind: PrayerKind) -> String {
        kind == .fajr ? String(localized: "qada.fajr", defaultValue: "Fajr", bundle: .app) : kind.title
    }

    /// The day in the place the times are for, as stored in `fastingDays` ("2026-11-12").
    private func dayKey(_ date: Date) -> String {
        let calendar = model.place?.calendar ?? Calendar(identifier: .gregorian)
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", parts.year ?? 0, parts.month ?? 0, parts.day ?? 0)
    }

    private var days: Set<String> {
        Set(fastingDays.split(separator: ",").map(String.init))
    }

    /// The toggle for the day it was drawn for, so a tap just after midnight can't change the new day.
    private func fasting(on day: String) -> Binding<Bool> {
        Binding {
            days.contains(day)
        } set: { on in
            var updated = days
            if on { updated.insert(day) } else { updated.remove(day) }
            fastingDays = updated.sorted().joined(separator: ",")
        }
    }
}

/// Prayers and fasts still to make up, kept only on this iPhone. (Menu → Missed prayers)
struct MissedPrayersView: View {
    @Environment(AppModel.self) private var model
    @AppStorage("fastsToMakeUp") private var fastsToMakeUp = 0

    var body: some View {
        Form {
            Section {
                ForEach(PrayerKind.allCases.filter(\.isPrayer)) { kind in
                    // The prayer, not the time: Turkish calls the time İmsak and the prayer Sabah.
                    QadaRow(key: kind.rawValue, title: kind == .fajr
                        ? String(localized: "qada.fajr", defaultValue: "Fajr", bundle: .app) : kind.title)
                }
                // Witr is wajib for Hanafis, so it is made up too.
                if model.settings.school == .hanafi {
                    QadaRow(key: "witr", title: String(localized: "Witr", bundle: .app))
                }
            } footer: {
                Text("Add a prayer you missed, and take it off once you have made it up. All of this stays on your iPhone.")
            }
            .listRowBackground(Theme.card)

            Section {
                Stepper(value: $fastsToMakeUp, in: 0...999) {
                    LabeledContent("Fasts to make up", value: Formats.number(fastsToMakeUp))
                }
            } footer: {
                Text("Days of Ramadan you missed and still have to make up.")
            }
            .listRowBackground(Theme.card)
        }
        .trackerPage("Missed prayers")
    }
}

/// The Qur'an read: today's pages and the khatm. (Menu → Khatm)
struct KhatmView: View {
    @AppStorage(QuranProgress.khatmPagesKey, store: SharedStore.defaults) private var khatmPages = ""
    @AppStorage(QuranProgress.khatmCountKey, store: SharedStore.defaults) private var khatmCount = 0
    @AppStorage(QuranProgress.todayKey, store: SharedStore.defaults) private var quranToday = ""
    @State private var confirmingNewKhatm = false

    var body: some View {
        // Redrawn every minute, so midnight starts a new "today".
        TimelineView(.everyMinute) { context in
            Form {
                Section {
                    let read = QuranProgress.pages(khatmPages).count
                    LabeledContent("Pages read today",
                                   value: Formats.number(QuranProgress.pagesRead(on: context.date, in: quranToday).count))
                    VStack(alignment: .leading, spacing: 8) {
                        LabeledContent("Khatm", value: "\(Formats.number(read)) / \(Formats.number(Quran.pageCount))")
                        ProgressView(value: Double(read), total: Double(Quran.pageCount))
                            .tint(Theme.gold)
                            .accessibilityHidden(true)
                    }
                    if khatmCount > 0 {
                        LabeledContent("Khatms completed", value: Formats.number(khatmCount))
                    }
                    Button("Start a new khatm") { confirmingNewKhatm = true }
                        .disabled(read == 0)
                } footer: {
                    Text("A page counts as read once it has been open for 10 seconds. All 604 pages complete a khatm.")
                }
                .listRowBackground(Theme.card)
            }
        }
        .trackerPage("Khatm")
        .confirmationDialog("Start a new khatm?", isPresented: $confirmingNewKhatm, titleVisibility: .visible) {
            Button("Start a new khatm", role: .destructive) { khatmPages = "" }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("The pages read so far in this khatm are cleared.")
        }
    }
}

private extension View {
    /// One of the tracker's pages: the app's background and its title.
    func trackerPage(_ title: LocalizedStringKey) -> some View {
        scrollContentBackground(.hidden)
            .background(Theme.background.ignoresSafeArea())
            .navigationTitle(title)
    }
}

/// One prayer's count of prayers to make up.
private struct QadaRow: View {
    let title: String
    @AppStorage private var count: Int

    init(key: String, title: String) {
        self.title = title
        _count = AppStorage(wrappedValue: 0, "qada-\(key)")
    }

    var body: some View {
        Stepper(value: $count, in: 0...9999) {
            LabeledContent(title, value: Formats.number(count))
        }
    }
}
