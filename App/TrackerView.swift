import SwiftUI

/// Fasts and missed (qada) prayers, kept only on this iPhone.
struct TrackerView: View {
    @Environment(AppModel.self) private var model
    /// The days fasted, as "2026-11-12" separated by commas.
    @AppStorage("fastingDays") private var fastingDays = ""
    @AppStorage("fastsToMakeUp") private var fastsToMakeUp = 0

    var body: some View {
        NavigationStack {
            // Redrawn every minute, so iftar and midnight ("today") arrive while the tab is open.
            TimelineView(.everyMinute) { context in
                form(now: context.date)
            }
        }
    }

    private func form(now: Date) -> some View {
        let today = dayKey(now)
        return Form {
            Section {
                Toggle("I'm fasting today", isOn: fasting(on: today))
                if days.contains(today), let place = model.place, let maghrib = model.times(on: now, at: place)?[4].time {
                    LabeledContent("Iftar", value: Formats.time(maghrib, in: place.timeZone))
                    if now < maghrib {
                        Text("Iftar in \(Text(timerInterval: now...maghrib, countsDown: true))")
                            .monospacedDigit()
                            .foregroundStyle(Theme.gold)
                        if model.canCountDown(to: maghrib, from: now) {
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

            Section {
                Stepper(value: $fastsToMakeUp, in: 0...999) {
                    LabeledContent("Fasts to make up", value: Formats.number(fastsToMakeUp))
                }
            } footer: {
                Text("Days of Ramadan you missed and still have to make up.")
            }
            .listRowBackground(Theme.card)

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
            } header: {
                Text("Missed prayers (qada)")
            } footer: {
                Text("Add a prayer you missed, and take it off once you have made it up. All of this stays on your iPhone.")
            }
            .listRowBackground(Theme.card)
        }
        .scrollContentBackground(.hidden)
        .background(Theme.background.ignoresSafeArea())
        .navigationTitle("Tracker")
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
