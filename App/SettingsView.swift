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

/// Who the app builds on: a name, what it's for and where to find it. The licences' full texts ship inside the app
/// next to what they cover, which is all they ask: App/Adhan-LICENSE.txt (MIT), App/Quran/AmiriQuran-OFL.txt (OFL),
/// and the copyright block of the Qur'an text (Tanzil also asks for its name and a link, which are here).
struct AcknowledgementsView: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                credit("Adhan · Batoul Apps", Text("Calculates the prayer times and the Qibla direction."),
                       site: "github.com/batoulapps/adhan-swift")
                Divider().overlay(Theme.line)
                credit("Tanzil Project", Text("The Qur'an text."), site: "tanzil.net")
                Divider().overlay(Theme.line)
                credit("Islamic Network", Text("The recitations; their reciters keep the copyright."), site: "alquran.cloud")
                Divider().overlay(Theme.line)
                credit("Amiri Project", Text("The Amiri Quran font."), site: "github.com/aliftype/amiri")
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(20)
        }
        .background(Theme.background.ignoresSafeArea())
        .navigationTitle("Acknowledgements")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func credit(_ name: String, _ reason: Text, site: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(verbatim: name)
                .font(.headline)
                .foregroundStyle(Theme.ink)
            reason
                .foregroundStyle(Theme.muted)
            Link(destination: URL(string: "https://\(site)")!) {
                Text(verbatim: site)
            }
        }
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
