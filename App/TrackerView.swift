import SwiftUI

/// Fasts and missed (qada) prayers, kept only on this iPhone.
struct TrackerView: View {
    @Environment(AppModel.self) private var model
    /// The days fasted, as "2026-11-12" separated by commas.
    @AppStorage("fastingDays") private var fastingDays = ""
    @AppStorage("fastsToMakeUp") private var fastsToMakeUp = 0

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    // One "now" for the check and the range: a second Date.now could be past iftar.
                    let now = Date.now
                    Toggle("I'm fasting today", isOn: fastingToday)
                    if fastingToday.wrappedValue, let place = model.place, let maghrib = model.times(on: now, at: place)?[4].time {
                        LabeledContent("Iftar", value: Formats.time(maghrib, in: place.timeZone))
                        if now < maghrib {
                            Text("Iftar in \(Text(timerInterval: now...maghrib, countsDown: true))")
                                .monospacedDigit()
                                .foregroundStyle(Theme.gold)
                            if model.liveActivitiesEnabled {
                                Button {
                                    model.startIftarCountdown()
                                } label: {
                                    Label("Iftar countdown on Lock Screen", systemImage: "lock.iphone")
                                }
                            }
                        }
                    }
                } header: {
                    Text("Today")
                } footer: {
                    Text("Days fasted this year: \(Formats.number(fastedThisYear))")
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
                        QadaRow(key: kind.rawValue, title: kind.title)
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
    }

    /// Today in the place the times are for, as stored in `fastingDays`.
    private var todayKey: String {
        let calendar = model.place?.calendar ?? Calendar(identifier: .gregorian)
        let parts = calendar.dateComponents([.year, .month, .day], from: .now)
        return String(format: "%04d-%02d-%02d", parts.year ?? 0, parts.month ?? 0, parts.day ?? 0)
    }

    private var days: Set<String> {
        Set(fastingDays.split(separator: ",").map(String.init))
    }

    private var fastingToday: Binding<Bool> {
        Binding {
            days.contains(todayKey)
        } set: { on in
            var updated = days
            if on { updated.insert(todayKey) } else { updated.remove(todayKey) }
            fastingDays = updated.sorted().joined(separator: ",")
        }
    }

    private var fastedThisYear: Int {
        let year = String(todayKey.prefix(4))
        return days.filter { $0.hasPrefix(year) }.count
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
