import CoreLocation
import SwiftUI
import UserNotifications

/// The first-run setup, one choice per page. Shown again after "Run setup again" in Settings.
struct SetupView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var done: () -> Void

    private enum Step: Int, CaseIterable {
        case welcome, language, location, method, reminders, lockScreen, ready
    }

    // `-setupStep 3` opens a later page first (used for CI screenshots).
    @State private var step = Step(rawValue: UserDefaults.standard.integer(forKey: "setupStep")) ?? .welcome
    @State private var searchingCity = false
    @AppStorage(AppModel.nextPrayerActivityKey) private var nextPrayerActivity = false

    var body: some View {
        VStack(spacing: 0) {
            topBar
            page
                // A new language rebuilds the page so all its text switches at once.
                .id("\(step.rawValue)-\(model.settings.language.rawValue)")
                .transition(reduceMotion ? .opacity : .opacity.combined(with: .scale(scale: 0.97)))
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .background(Theme.background.ignoresSafeArea())
        .foregroundStyle(Theme.ink)
        .sensoryFeedback(.selection, trigger: step)
        .sheet(isPresented: $searchingCity) {
            NavigationStack { CitySearchView() }
        }
        // "Automatic" (the default) follows the country found and the language picked.
        .onChange(of: model.place, initial: true) { model.applyAutomaticChoices() }
        .onChange(of: model.settings.language) { model.applyAutomaticChoices() }
        .task { model.scheduleNotifications() }  // also reads the current notification permission
    }

    private var topBar: some View {
        HStack {
            Button { go(-1) } label: {
                Image(systemName: "chevron.backward")
                    .font(.title3.weight(.semibold))
                    .frame(width: 44, height: 44)
            }
            .accessibilityLabel(Text("Back"))
            .opacity(step == .welcome ? 0 : 1)
            .disabled(step == .welcome)
            Spacer()
            HStack(spacing: 8) {
                ForEach(Step.allCases, id: \.self) { item in
                    Rectangle()
                        .fill(item.rawValue <= step.rawValue ? Theme.gold : Theme.gold.opacity(0.5))
                        .frame(width: 7, height: 7)
                        .rotationEffect(.degrees(45))
                }
            }
            .frame(minHeight: 44)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(Text("Step \(step.rawValue + 1) of \(Step.allCases.count)"))
            Spacer()
            Color.clear.frame(width: 44, height: 44)
        }
        .foregroundStyle(Theme.gold)
        .padding(.horizontal, 8)
    }

    @ViewBuilder
    private var page: some View {
        switch step {
        case .welcome: welcomePage
        case .language: languagePage
        case .location: locationPage
        case .method: methodPage
        case .reminders: remindersPage
        case .lockScreen: lockScreenPage
        case .ready: readyPage
        }
    }

    private func go(_ delta: Int) {
        guard let next = Step(rawValue: step.rawValue + delta) else { return }
        withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.3)) { step = next }
    }

    // MARK: - Pages

    private var welcomePage: some View {
        ScrollView {
            VStack(spacing: 0) {
                StarMark(turning: !reduceMotion)
                    .frame(width: 140, height: 140)
                    .padding(.top, 24)
                Text(verbatim: Bundle.main.displayName)
                    .font(.system(.largeTitle, design: .serif).weight(.semibold))
                    .multilineTextAlignment(.center)
                    .padding(.top, 28)
                Text("Prayer times and the Qibla, without ads or tracking.")
                    .foregroundStyle(Theme.muted)
                    .multilineTextAlignment(.center)
                    .padding(.top, 6)
                VStack(alignment: .leading, spacing: 18) {
                    Feature(icon: "clock", title: "Prayer times", text: "Today's times, the next prayer and a monthly timetable.")
                    Feature(icon: "safari", title: "Qibla compass", text: "Turn until the Kaaba marker reaches the top.")
                    Feature(icon: "bell", title: "Reminders", text: "A notification when each prayer begins, if you want one.")
                }
                .padding(.top, 32)
            }
            .padding(.horizontal, 24)
        }
        .scrollBounceBehavior(.basedOnSize)
        .safeAreaInset(edge: .bottom) {
            VStack(spacing: 8) {
                Button("Get started") { go(1) }
                    .buttonStyle(PrimaryButtonStyle())
                Text("Takes about a minute.")
                    .font(.footnote)
                    .foregroundStyle(Theme.muted)
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 12)
            .background(Theme.background)
        }
    }

    private var languagePage: some View {
        SetupPage(
            title: "Which language?",
            text: "The app follows the language of your iPhone, unless you choose another one here."
        ) {
            VStack(spacing: 10) {
                ForEach(AppLanguage.allCases) { language in
                    ChoiceCard(
                        icon: language == .system ? "iphone" : nil,
                        title: Text(verbatim: language.nativeName),
                        detail: language.detail.map { Text(verbatim: $0) },
                        selected: model.settings.language == language
                    ) {
                        model.settings.language = language
                    }
                }
            }
            .sensoryFeedback(.selection, trigger: model.settings.language)
        } buttons: {
            Button("Continue") { go(1) }
                .buttonStyle(PrimaryButtonStyle())
        }
    }

    private var locationPage: some View {
        SetupPage(
            title: "Where are you?",
            text: "Prayer times depend on where you are, and the compass needs your location to point to the Qibla. Apart from Apple Maps, which names the place, shows the map and finds mosques nearby, the app shares it with no one."
        ) {
            VStack(spacing: 10) {
                ChoiceCard(
                    icon: "location.fill",
                    title: Text("Use my location"),
                    detail: Text("Stays right when you travel. Recommended."),
                    selected: model.settings.useCurrentLocation && model.currentPlace != nil
                ) {
                    model.useCurrentLocation()
                }
                ChoiceCard(
                    icon: "magnifyingglass",
                    title: Text("Choose a city"),
                    detail: Text("Works without location access."),
                    selected: !model.settings.useCurrentLocation && model.settings.city != nil
                ) {
                    searchingCity = true
                }
                locationStatus
                    .padding(.top, 6)
            }
        } buttons: {
            if model.place == nil && model.location.authorization == .notDetermined {
                // App Review: before the iOS location prompt, one button that always leads to it.
                Button("Continue") { model.useCurrentLocation() }
                    .buttonStyle(PrimaryButtonStyle())
            } else {
                Button("Continue") { go(1) }
                    .buttonStyle(PrimaryButtonStyle())
                    .disabled(model.place == nil)
                if model.place == nil {
                    Button("Skip for now") { go(1) }
                        .buttonStyle(SecondaryButtonStyle())
                }
            }
        }
    }

    @ViewBuilder
    private var locationStatus: some View {
        if let place = model.place {
            Label {
                Text(verbatim: place.displayNameWithCountry)
            } icon: {
                Image(systemName: "checkmark.circle.fill").foregroundStyle(Theme.gold)
            }
            .font(.headline)
            .frame(maxWidth: .infinity, alignment: .leading)
        } else if model.settings.useCurrentLocation && model.location.isAuthorized && !model.location.failed {
            ProgressView("Finding your location")
                .frame(maxWidth: .infinity, alignment: .leading)
        } else if model.location.isDenied {
            VStack(alignment: .leading, spacing: 8) {
                Text("Location access is off for this app. Choose a city instead, or turn it on in Settings.")
                    .foregroundStyle(Theme.muted)
                Button("Open Settings") { openAppSettings() }
                    .foregroundStyle(Theme.gold)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        } else if model.settings.useCurrentLocation && model.location.failed {
            VStack(alignment: .leading, spacing: 8) {
                Text("Your location could not be found.")
                    .foregroundStyle(Theme.muted)
                Button("Try again") { model.refresh() }
                    .foregroundStyle(Theme.gold)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var methodPage: some View {
        SetupPage(
            title: "How are times calculated?",
            text: "Mosques use slightly different rules, mostly for Fajr and Isha. Automatic uses the rules of the mosques in the country you're in, also when you travel. Or pick the one your mosque uses."
        ) {
            MethodChoices(model: model)
        } buttons: {
            Button("Continue") { go(1) }
                .buttonStyle(PrimaryButtonStyle())
        }
    }

    private var remindersPage: some View {
        SetupPage(
            title: "Reminders",
            text: "Get a notification when a prayer begins. Choose which ones; you can change this later with the bell next to each time."
        ) {
            VStack(spacing: 10) {
                ForEach(PrayerKind.allCases.filter(\.isPrayer)) { kind in
                    let on = model.settings.notify.contains(kind)
                    ChoiceCard(
                        icon: on ? "bell.fill" : "bell.slash",
                        title: Text(kind.title),
                        note: todayText(kind),
                        selected: on
                    ) {
                        if on { model.settings.notify.remove(kind) } else { model.settings.notify.insert(kind) }
                    }
                }
                if model.notificationStatus == .denied {
                    Text("Notifications are off for this app. You can turn them on in Settings.")
                        .font(.subheadline)
                        .foregroundStyle(Theme.muted)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Button("Open Settings") { openAppSettings() }
                        .foregroundStyle(Theme.gold)
                }
            }
            .sensoryFeedback(.selection, trigger: model.settings.notify)
        } buttons: {
            if model.settings.notify.isEmpty || model.notificationStatus != .notDetermined {
                Button("Continue") { go(1) }
                    .buttonStyle(PrimaryButtonStyle())
            } else {
                Button("Allow notifications") {
                    Task {
                        await model.requestNotifications()
                        go(1)
                    }
                }
                .buttonStyle(PrimaryButtonStyle())
                Button("Not now") {
                    model.settings.notify = []
                    go(1)
                }
                .buttonStyle(SecondaryButtonStyle())
            }
        }
    }

    private var lockScreenPage: some View {
        SetupPage(
            title: "The next prayer on your Lock Screen?",
            text: "A countdown to the next prayer on the Lock Screen and in the Dynamic Island."
        ) {
            VStack(alignment: .leading, spacing: 14) {
                LockScreenPreview(model: model)
                Text("iOS keeps it for up to 8 hours; opening the app brings it back. For a widget that stays, touch and hold the Lock Screen and tap Customize.")
                    .font(.footnote)
                    .foregroundStyle(Theme.muted)
                if !model.liveActivitiesEnabled {
                    Button("Allow Live Activities in Settings") { openAppSettings() }
                        .foregroundStyle(Theme.gold)
                }
            }
        } buttons: {
            Button("Show on Lock Screen") {
                nextPrayerActivity = true
                model.scheduleNotifications()  // also starts the Live Activity
                go(1)
            }
            .buttonStyle(PrimaryButtonStyle())
            Button("Not now") {
                nextPrayerActivity = false
                model.scheduleNotifications()
                go(1)
            }
            .buttonStyle(SecondaryButtonStyle())
        }
    }

    private var readyPage: some View {
        ScrollView {
            VStack(spacing: 0) {
                StarMark(filled: true)
                    .frame(width: 110, height: 110)
                    .padding(.top, 32)
                Text("All set")
                    .font(.system(.largeTitle, design: .serif).weight(.semibold))
                    .padding(.top, 24)
                Text("You can change all of this any time in Settings.")
                    .foregroundStyle(Theme.muted)
                    .multilineTextAlignment(.center)
                    .padding(.top, 6)
                VStack(spacing: 0) {
                    SummaryRow(label: "Language", value: model.settings.language.nativeName)
                    SummaryRow(label: "Location", value: model.place?.displayNameWithCountry ?? String(localized: "Not set", bundle: .app))
                    SummaryRow(label: "Calculation method", value: model.settings.methodSummary)
                    SummaryRow(label: "Asr calculation", value: model.settings.asrSummary)
                    SummaryRow(label: "Reminders", value: remindersSummary)
                    SummaryRow(label: "Lock Screen", value: lockScreenSummary, last: true)
                }
                .background(Theme.card, in: RoundedRectangle(cornerRadius: 16))
                .padding(.top, 28)
            }
            .padding(.horizontal, 24)
        }
        .scrollBounceBehavior(.basedOnSize)
        .safeAreaInset(edge: .bottom) {
            Button("Start") { done() }
                .buttonStyle(PrimaryButtonStyle())
                .padding(.horizontal, 24)
                .padding(.vertical, 12)
                .background(Theme.background)
        }
    }

    private func todayText(_ kind: PrayerKind) -> Text? {
        guard let place = model.place,
              let item = model.times(on: Date(), at: place)?.first(where: { $0.kind == kind }) else { return nil }
        return Text("Today \(Formats.time(item.time, in: place.timeZone))")
    }

    /// The next prayer's Live Activity, as chosen on the page before (off while iOS has Live Activities off).
    private var lockScreenSummary: String {
        nextPrayerActivity && model.liveActivitiesEnabled
            ? String(localized: "On", bundle: .app) : String(localized: "Off", bundle: .app)
    }

    private var remindersSummary: String {
        let kinds = PrayerKind.allCases.filter { $0.isPrayer && model.settings.notify.contains($0) }
        if kinds.isEmpty || model.notificationStatus == .denied { return String(localized: "Off", bundle: .app) }
        if kinds.count == 5 { return String(localized: "All prayers", bundle: .app) }
        let formatter = ListFormatter()
        formatter.locale = .app
        return formatter.string(from: kinds.map(\.title)) ?? ""
    }
}

// MARK: - Choices (also used in Settings)

/// Every calculation method, where it's used, and today's Fajr and Isha at the user's place,
/// so the choice can be compared with a mosque's timetable.
struct MethodChoices: View {
    let model: AppModel
    var onPick: () -> Void = {}

    var body: some View {
        let suggested = model.suggestion.method
        VStack(spacing: 10) {
            ChoiceCard(
                icon: "location.circle",
                title: Text("Automatic"),
                detail: Text("The rules of the mosques in the country you're in, also when you travel. Now: \(suggested.title)"),
                note: preview(suggested),
                selected: model.settings.automaticMethod
            ) {
                var settings = model.settings
                settings.automaticMethod = true
                model.settings = settings
                model.applyAutomaticChoices()
                onPick()
            }
            ForEach([suggested] + CalcMethod.allCases.filter { $0 != suggested }) { method in
                ChoiceCard(
                    title: Text(method.title),
                    detail: Text(method.usage),
                    note: preview(method),
                    badge: method == suggested ? suggestedBadge : nil,
                    selected: !model.settings.automaticMethod && model.settings.method == method
                ) {
                    // A method picked by hand stays, wherever the user goes.
                    var settings = model.settings
                    settings.method = method
                    settings.automaticMethod = false
                    model.settings = settings
                    onPick()
                }
            }
        }
        .sensoryFeedback(.selection, trigger: model.settings.method)
    }

    // The city reads well after "for" in every language ("Suggested for Amsterdam"); a bare country
    // name doesn't ("for Netherlands" needs "the").
    private var suggestedBadge: Text {
        if let place = model.place, !place.name.isEmpty {
            return Text("Suggested for \(place.name)")
        }
        return Text("Suggested")
    }

    private func preview(_ method: CalcMethod) -> Text? {
        guard let place = model.place else { return nil }
        var settings = model.settings
        settings.method = method
        guard let times = Prayers.compute(on: Date(), place: place, settings: settings) else { return nil }
        let fajr = Formats.time(times[0].time, in: place.timeZone)
        let isha = Formats.time(times[5].time, in: place.timeZone)
        return Text("Fajr \(fajr) · Isha \(isha)")
    }
}

struct AsrChoices: View {
    let model: AppModel
    var onPick: () -> Void = {}

    var body: some View {
        let suggested = model.suggestion.asr
        VStack(spacing: 10) {
            ChoiceCard(
                icon: "location.circle",
                title: Text("Automatic"),
                detail: Text("The Asr of the mosques in the country you're in, also when you travel. Now: \(suggested.shortTitle)"),
                note: preview(suggested),
                selected: model.settings.automaticAsr
            ) {
                var settings = model.settings
                settings.automaticAsr = true
                model.settings = settings
                model.applyAutomaticChoices()
                onPick()
            }
            ForEach(AsrMethod.allCases) { asr in
                ChoiceCard(
                    title: Text(asr.title),
                    detail: Text(asr.explanation),
                    note: preview(asr),
                    badge: asr == suggested ? Text("Suggested") : nil,
                    selected: !model.settings.automaticAsr && model.settings.asr == asr
                ) {
                    var settings = model.settings
                    settings.asr = asr
                    settings.automaticAsr = false
                    model.settings = settings
                    onPick()
                }
            }
        }
        .sensoryFeedback(.selection, trigger: model.settings.asr)
    }

    private func preview(_ asr: AsrMethod) -> Text? {
        guard let place = model.place else { return nil }
        var settings = model.settings
        settings.asr = asr
        guard let times = Prayers.compute(on: Date(), place: place, settings: settings) else { return nil }
        return Text("Asr today: \(Formats.time(times[3].time, in: place.timeZone))")
    }
}

/// A large tappable option with a check mark when selected.
struct ChoiceCard: View {
    var icon: String? = nil
    let title: Text
    var detail: Text? = nil
    var note: Text? = nil
    var badge: Text? = nil
    let selected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 14) {
                if let icon {
                    Image(systemName: icon)
                        .font(.title3)
                        .foregroundStyle(Theme.gold)
                        .frame(width: 28)
                        .accessibilityHidden(true)
                }
                VStack(alignment: .leading, spacing: 3) {
                    if let badge {
                        badge
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(Theme.background)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 2)
                            .background(Theme.gold, in: Capsule())
                    }
                    title
                        .font(.headline)
                        .foregroundStyle(Theme.ink)
                    if let detail {
                        detail
                            .font(.subheadline)
                            .foregroundStyle(Theme.muted)
                    }
                    if let note {
                        note
                            .font(.subheadline.monospacedDigit())
                            .foregroundStyle(Theme.gold)
                    }
                }
                .multilineTextAlignment(.leading)
                .frame(maxWidth: .infinity, alignment: .leading)
                Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .foregroundStyle(selected ? Theme.gold : Theme.muted)
                    .accessibilityHidden(true)
            }
            .padding(16)
            .background(Theme.card, in: RoundedRectangle(cornerRadius: 16))
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .strokeBorder(selected ? Theme.gold : Theme.line, lineWidth: selected ? 2 : 1))
            .contentShape(RoundedRectangle(cornerRadius: 16))
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

// MARK: - Building blocks

/// One setup page: a title and explanation, the choices, and the buttons pinned to the bottom.
private struct SetupPage<Content: View, Buttons: View>: View {
    let title: LocalizedStringKey
    let text: LocalizedStringKey
    @ViewBuilder var content: Content
    @ViewBuilder var buttons: Buttons

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                Text(title)
                    .font(.system(.largeTitle, design: .serif).weight(.semibold))
                Text(text)
                    .foregroundStyle(Theme.muted)
                content
                    .padding(.top, 14)
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 12)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .scrollBounceBehavior(.basedOnSize)
        .safeAreaInset(edge: .bottom) {
            VStack(spacing: 6) { buttons }
                .padding(.horizontal, 24)
                .padding(.vertical, 12)
                .background(Theme.background)
                // Cards scrolling under the buttons fade out instead of being cut off by a hard edge.
                .background(alignment: .top) {
                    LinearGradient(colors: [Theme.background.opacity(0), Theme.background], startPoint: .top, endPoint: .bottom)
                        .frame(height: 28)
                        .offset(y: -28)
                        .allowsHitTesting(false)
                }
        }
    }
}

/// The app's star: turning slowly on the welcome page, filled in on the last page.
private struct StarMark: View {
    var turning = false
    var filled = false
    @State private var angle = 0.0

    var body: some View {
        ZStack {
            EightPointStar()
                .stroke(Theme.gold, lineWidth: 2)
                .rotationEffect(.degrees(angle))
            EightPointStar()
                .fill(Theme.gold)
                .scaleEffect(filled ? 0.62 : 0.3)
        }
        .accessibilityHidden(true)
        .onAppear {
            guard turning else { return }
            withAnimation(.easeInOut(duration: 6).repeatForever(autoreverses: true)) { angle = 45 }
        }
    }
}

private struct Feature: View {
    let icon: String
    let title: LocalizedStringKey
    let text: LocalizedStringKey

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundStyle(Theme.gold)
                .frame(width: 32)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.headline)
                Text(text).font(.subheadline).foregroundStyle(Theme.muted)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// The Live Activity as it shows on the Lock Screen (the same card), with the real next prayer, counting down.
private struct LockScreenPreview: View {
    let model: AppModel

    var body: some View {
        if let place = model.place, let state = model.nextPrayerState(after: .now, at: place) {
            NextPrayerCard(place: place.displayName, state: state, arrived: false)
                .background(Theme.background, in: RoundedRectangle(cornerRadius: 22))
                .overlay(RoundedRectangle(cornerRadius: 22).strokeBorder(Theme.line, lineWidth: 1))
        }
    }
}

private struct SummaryRow: View {
    let label: LocalizedStringKey
    let value: String
    var last = false

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text(label).foregroundStyle(Theme.muted)
            Spacer(minLength: 8)
            Text(value).multilineTextAlignment(.trailing)
        }
        .font(.subheadline)
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .overlay(alignment: .bottom) {
            if !last { Theme.line.frame(height: 1).padding(.leading, 16) }
        }
    }
}

private struct PrimaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        PrimaryLabel(configuration: configuration)
    }

    private struct PrimaryLabel: View {
        let configuration: ButtonStyleConfiguration
        @Environment(\.isEnabled) private var isEnabled

        var body: some View {
            configuration.label
                .font(.headline)
                .foregroundStyle(Theme.background)
                .frame(maxWidth: .infinity, minHeight: 52)
                .background(
                    Theme.gold.opacity(isEnabled ? (configuration.isPressed ? 0.75 : 1) : 0.35),
                    in: RoundedRectangle(cornerRadius: 14))
        }
    }
}

private struct SecondaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.body.weight(.medium))
            .foregroundStyle(Theme.gold.opacity(configuration.isPressed ? 0.6 : 1))
            .frame(maxWidth: .infinity, minHeight: 44)
            .contentShape(Rectangle())
    }
}
