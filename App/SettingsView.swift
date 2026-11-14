import AppIntents
import SwiftUI
import UserNotifications

struct SettingsView: View {
    @Environment(AppModel.self) private var model
    @State private var confirmingReset = false
    @AppStorage("siriTip") private var showingSiriTip = true
    @AppStorage(AppModel.nextPrayerActivityKey) private var nextPrayerActivity = false
    /// nil for the standard icon.
    @State private var icon = UIApplication.shared.alternateIconName

    var body: some View {
        @Bindable var model = model
        NavigationStack {
            Form {
                Section {
                    Toggle("Use current location", isOn: $model.settings.useCurrentLocation)
                    if model.settings.useCurrentLocation {
                        LabeledContent("Current location", value: model.currentPlace?.displayNameWithCountry ?? "—")
                        if model.location.isDenied {
                            Button("Allow location access") { openAppSettings() }
                        }
                    } else {
                        NavigationLink {
                            CitySearchView()
                        } label: {
                            LabeledContent("City", value: model.settings.city?.displayNameWithCountry ?? String(localized: "Choose a city", bundle: .app))
                        }
                    }
                } header: {
                    Text("Location")
                } footer: {
                    Text("Use your location to keep the times right when you travel, or choose a fixed city.")
                }
                .listRowBackground(Theme.card)

                Section {
                    Picker("School (madhab)", selection: Binding(
                        get: { model.settings.school },
                        set: { if let school = $0 { model.chooseSchool(school) } }
                    )) {
                        // Settings from before the school was required have none; without this row it reads blank.
                        if model.settings.school == nil {
                            Text("Not set").tag(School?.none)
                        }
                        ForEach(School.allCases) { school in
                            Text(school.title).tag(Optional(school))
                        }
                    }
                    .pickerStyle(.navigationLink)
                    NavigationLink {
                        MethodSettingsPage()
                    } label: {
                        LabeledContent("Calculation method", value: model.settings.methodSummary)
                    }
                    NavigationLink {
                        AsrSettingsPage()
                    } label: {
                        LabeledContent("Asr calculation", value: model.settings.asrSummary)
                    }
                    NavigationLink("Adjust times") { AdjustmentsView() }
                    // Set by hand, the offset no longer follows the school (see AppModel.chooseSchool).
                    Stepper(value: Binding(
                        get: { model.settings.hijriOffset },
                        set: {
                            model.settings.hijriOffset = $0
                            model.settings.hijriOffsetFromSchool = false
                        }
                    ), in: -2...2) {
                        // The date on its own line: next to the label and the stepper it would wrap.
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Hijri date")
                            let here = model.place ?? Place(name: "", latitude: 0, longitude: 0, timeZoneID: TimeZone.current.identifier)
                            Text(verbatim: Formats.hijriDate(Prayers.hijri(of: Date(), place: here, settings: model.settings)))
                                .font(.subheadline)
                                .foregroundStyle(Theme.muted)
                                .lineLimit(1)
                                .minimumScaleFactor(0.8)
                        }
                    }
                } header: {
                    Text("Prayer times")
                } footer: {
                    Text("Choose the method your mosque uses. You can move each prayer by a few minutes to match its timetable, and the Hijri date by a day or two.")
                }
                .listRowBackground(Theme.card)

                Section {
                    ForEach(PrayerKind.allCases.filter(\.isPrayer)) { kind in
                        Toggle(kind.title, isOn: Binding(
                            get: { model.settings.notify.contains(kind) },
                            set: { on in
                                if on != model.settings.notify.contains(kind) { model.toggleNotify(kind) }
                            }))
                    }
                    Picker("Remind me before", selection: $model.settings.reminderMinutes) {
                        Text("Off").tag(0)
                        ForEach([5, 10, 15, 20, 30], id: \.self) { minutes in
                            Text("\(minutes) min").tag(minutes)
                        }
                    }
                    Toggle("Jumu'ah reminder", isOn: $model.settings.jumuahReminder)
                    Toggle("Suhoor and iftar in Ramadan", isOn: $model.settings.ramadanReminders)
                    if model.notificationStatus == .denied {
                        Button("Allow notifications in Settings") { openAppSettings() }
                    }
                    Button("Send a test notification") { model.sendTestNotification() }
                } header: {
                    Text("Notifications")
                } footer: {
                    Text("“Remind me before” adds a notification a few minutes before each prayer that has its bell on. The Jumu'ah reminder comes an hour before the Friday prayer. In Ramadan you get one 30 minutes before suhoor ends, and one at iftar. Notifications use the standard sound; the test notification arrives after 5 seconds.")
                }
                .listRowBackground(Theme.card)

                Section {
                    Toggle("Next prayer on the Lock Screen", isOn: $nextPrayerActivity)
                        .onChange(of: nextPrayerActivity) { model.scheduleNotifications() }
                    if nextPrayerActivity && !model.liveActivitiesEnabled {
                        Button("Allow Live Activities in Settings") { openAppSettings() }
                    }
                } header: {
                    Text("Lock Screen")
                } footer: {
                    Text("The next prayer and a countdown on the Lock Screen and in the Dynamic Island. iOS keeps it for up to 8 hours; opening the app brings it back and moves it on to the next prayer.")
                }
                .listRowBackground(Theme.card)

                Section {
                    Picker("App icon", selection: $icon) {
                        AppIconChoice(title: "Standard", paper: Theme.background, star: Theme.gold).tag(String?.none)
                        AppIconChoice(title: "Paper", paper: Color(hex: 0xFBF6E8), star: Color(hex: 0x8A672B))
                            .tag(String?.some("AppIcon-Paper"))
                        AppIconChoice(title: "Green", paper: Color(hex: 0x173D2E), star: Color(hex: 0xD4B068))
                            .tag(String?.some("AppIcon-Green"))
                    }
                    .pickerStyle(.inline)
                    .labelsHidden()
                    .onChange(of: icon) {
                        guard UIApplication.shared.alternateIconName != icon else { return }
                        UIApplication.shared.setAlternateIconName(icon) { error in
                            if error != nil { Task { @MainActor in icon = UIApplication.shared.alternateIconName } }
                        }
                    }
                } header: {
                    Text("App icon")
                }
                .listRowBackground(Theme.card)

                Section {
                    if showingSiriTip {
                        SiriTipView(intent: NextPrayerIntent(), isVisible: $showingSiriTip)
                            .listRowInsets(EdgeInsets())
                            .listRowBackground(Color.clear)
                    }
                    ShortcutsLink()
                        .frame(maxWidth: .infinity)
                        .listRowBackground(Color.clear)
                } header: {
                    Text("Siri")
                } footer: {
                    Text("Ask Siri when the next prayer is, or when Maghrib begins, without opening the app.")
                }

                Section {
                    Picker("Language", selection: $model.settings.language) {
                        ForEach(AppLanguage.allCases) { language in
                            Text(verbatim: language.nativeName).tag(language)
                        }
                    }
                    .pickerStyle(.navigationLink)
                } footer: {
                    Text("Changes the language of this app only. Messages from iOS itself, such as permission requests, follow the language of your iPhone.")
                }
                .listRowBackground(Theme.card)

                Section {
                    Button("Run setup again") { confirmingReset = true }
                } header: {
                    Text("Setup")
                } footer: {
                    Text("Choose your location, calculation method and reminders again, step by step.")
                }
                .listRowBackground(Theme.card)

                Section("About") {
                    LabeledContent("Made by", value: "Melih Sivrikaya")
                    LabeledContent("Version", value: Bundle.main.versionText)
                    Link("Privacy policy", destination: model.settings.language.siteURL("privacy"))
                    Link("Support", destination: model.settings.language.siteURL("support"))
                    NavigationLink("Acknowledgements") { AcknowledgementsView() }
                    Text("No ads, no tracking, no account.")
                        .foregroundStyle(Theme.muted)
                }
                .listRowBackground(Theme.card)
            }
            .scrollContentBackground(.hidden)
            .background(Theme.background.ignoresSafeArea())
            .navigationTitle("Settings")
            .onChange(of: model.settings.useCurrentLocation) { _, isOn in
                if isOn { model.location.start() }
                model.applyAutomaticChoices()
            }
            .onChange(of: model.settings.language) { model.applyAutomaticChoices() }
            .onChange(of: model.settings.reminderMinutes) { _, minutes in
                if minutes > 0 { model.notificationsWanted() }
            }
            .onChange(of: model.settings.jumuahReminder) { _, isOn in
                if isOn { model.notificationsWanted() }
            }
            .onChange(of: model.settings.ramadanReminders) { _, isOn in
                if isOn { model.notificationsWanted() }
            }
            .confirmationDialog("Run setup again?", isPresented: $confirmingReset, titleVisibility: .visible) {
                Button("Start setup", role: .destructive) { model.resetSetup() }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("Your settings go back to the suggestions for your region, and the setup starts again.")
            }
        }
    }
}

struct MethodSettingsPage: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("Mosques use slightly different rules, mostly for Fajr and Isha. Compare the times below with the timetable of your mosque.")
                    .foregroundStyle(Theme.muted)
                MethodChoices(model: model)
            }
            .padding(20)
        }
        .background(Theme.background.ignoresSafeArea())
        .navigationTitle("Calculation method")
        .navigationBarTitleDisplayMode(.inline)
    }
}

struct AsrSettingsPage: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("Most timetables, Diyanet's included, use the standard Asr time. Some Hanafi mosques use a later one. Pick the one your mosque uses.")
                    .foregroundStyle(Theme.muted)
                AsrChoices(model: model)
            }
            .padding(20)
        }
        .background(Theme.background.ignoresSafeArea())
        .navigationTitle("Asr calculation")
        .navigationBarTitleDisplayMode(.inline)
    }
}

/// The open-source code, text and font in the app, with the licences their authors ask to keep with every copy.
/// An icon to pick: its colours on a small tile with the star, and its name.
private struct AppIconChoice: View {
    let title: LocalizedStringKey
    let paper: Color
    let star: Color

    var body: some View {
        HStack(spacing: 14) {
            RoundedRectangle(cornerRadius: 9)
                .fill(paper)
                .frame(width: 40, height: 40)
                .overlay(EightPointStar().stroke(star, lineWidth: 2).padding(9))
                .overlay(RoundedRectangle(cornerRadius: 9).strokeBorder(Theme.line, lineWidth: 1))
                .accessibilityHidden(true)
            Text(title)
        }
    }
}

struct AcknowledgementsView: View {
    /// The font's licence (OFL 1.1), bundled next to it.
    private static let amiriLicense = Bundle.main.url(forResource: "AmiriQuran-OFL", withExtension: "txt")
        .flatMap { try? String(contentsOf: $0, encoding: .utf8) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("This app uses Adhan, by Batoul Apps, under the MIT License.")
                    .foregroundStyle(Theme.muted)
                // Licence text stays in English, as published.
                Text(verbatim: """
                    The MIT License (MIT)

                    Copyright (c) 2016 Batoul Apps

                    Permission is hereby granted, free of charge, to any person obtaining a copy of this software and \
                    associated documentation files (the "Software"), to deal in the Software without restriction, \
                    including without limitation the rights to use, copy, modify, merge, publish, distribute, \
                    sublicense, and/or sell copies of the Software, and to permit persons to whom the Software is \
                    furnished to do so, subject to the following conditions:

                    The above copyright notice and this permission notice shall be included in all copies or \
                    substantial portions of the Software.

                    THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT \
                    NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND \
                    NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, \
                    DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT \
                    OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.
                    """)
                    .font(.footnote)
                    .environment(\.layoutDirection, .leftToRight)
                    .textSelection(.enabled)
                Divider().overlay(Theme.line)
                // Tanzil's terms: the text unchanged, its source named and linked.
                Text("The Qur'an text is the Uthmani text of the Tanzil Project, used unchanged under its terms (Creative Commons Attribution 3.0).")
                    .foregroundStyle(Theme.muted)
                Link(destination: URL(string: "https://tanzil.net")!) {
                    Text(verbatim: "tanzil.net")
                }
                Divider().overlay(Theme.line)
                Text("The recitations come from Islamic Network (alquran.cloud); the app plays them from its own copy. They remain the copyright of their reciters.")
                    .foregroundStyle(Theme.muted)
                Link(destination: URL(string: "https://alquran.cloud")!) {
                    Text(verbatim: "alquran.cloud")
                }
                Divider().overlay(Theme.line)
                Text("The Qur'an is shown in the Amiri Quran font by the Amiri Project, under the SIL Open Font License.")
                    .foregroundStyle(Theme.muted)
                if let license = Self.amiriLicense {
                    Text(verbatim: license)
                        .font(.footnote)
                        .environment(\.layoutDirection, .leftToRight)
                        .textSelection(.enabled)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(20)
        }
        .background(Theme.background.ignoresSafeArea())
        .navigationTitle("Acknowledgements")
        .navigationBarTitleDisplayMode(.inline)
    }
}

struct AdjustmentsView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        Form {
            Section {
                ForEach(PrayerKind.allCases.filter(\.isPrayer)) { kind in
                    let minutes = model.settings.adjustments[kind] ?? 0
                    let signed = minutes > 0 ? "+\(minutes)" : "\(minutes)"
                    Stepper(value: Binding(
                        get: { minutes },
                        set: { model.settings.adjustments[kind] = $0 == 0 ? nil : $0 }
                    ), in: -30...30) {
                        LabeledContent(kind.title, value: String(localized: "\(signed) min", bundle: .app))
                    }
                }
            } footer: {
                Text("Minutes added to the calculated time, to match the timetable of your mosque.")
            }
            .listRowBackground(Theme.card)
        }
        .scrollContentBackground(.hidden)
        .background(Theme.background.ignoresSafeArea())
        .navigationTitle("Adjust times")
    }
}
