import SwiftUI
import UserNotifications

struct SettingsView: View {
    @Environment(AppModel.self) private var model
    @State private var confirmingReset = false

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
                        ForEach(School.allCases) { school in
                            Text(school.title).tag(Optional(school))
                        }
                    }
                    .pickerStyle(.navigationLink)
                    NavigationLink {
                        MethodSettingsPage()
                    } label: {
                        LabeledContent("Calculation method", value: model.settings.method.title)
                    }
                    NavigationLink {
                        AsrSettingsPage()
                    } label: {
                        LabeledContent("Asr calculation", value: model.settings.asr.shortTitle)
                    }
                    NavigationLink("Adjust times") { AdjustmentsView() }
                    Stepper(value: $model.settings.hijriOffset, in: -2...2) {
                        // The date on its own line: next to the label and the stepper it would wrap.
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Hijri date")
                            Text(verbatim: Formats.hijriDate(Date(), in: model.place?.timeZone ?? .current, offset: model.settings.hijriOffset))
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
                    if model.notificationStatus == .denied {
                        Button("Allow notifications in Settings") { openAppSettings() }
                    }
                    Button("Send a test notification") { model.sendTestNotification() }
                } header: {
                    Text("Notifications")
                } footer: {
                    Text("Notifications use the standard sound. The test notification arrives after 5 seconds.")
                }
                .listRowBackground(Theme.card)

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

                // To fill in later: who made the app, contact, credits.
                Section("About") {
                    LabeledContent("Made by", value: "—")
                    LabeledContent("Version", value: Bundle.main.versionText)
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
