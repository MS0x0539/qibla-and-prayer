import SwiftUI
import WidgetKit
import UIKit

@main
struct QiblaApp: App {
    @State private var model = AppModel()

    var body: some Scene {
        let model = model
        WindowGroup {
            // A language picked in the app applies to SwiftUI's own text lookups and to layout direction.
            let language = model.settings.language
            RootView()
                .environment(model)
                .environment(\.locale, language.locale)
                .environment(\.layoutDirection, language.isRightToLeft ? .rightToLeft : .leftToRight)
                .preferredColorScheme(.dark)
                .tint(Theme.gold)
        }
        // Tops up the notifications while the app isn't opened (iOS decides when).
        .backgroundTask(.appRefresh(AppModel.refreshTask)) {
            await model.backgroundRefresh()
        }
    }
}

enum AppTab: String, Hashable {
    case times, qibla, quran, ibadah, settings
}

struct RootView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.scenePhase) private var scenePhase
    @AppStorage(WhatsNewView.seenKey) private var whatsNewSeen = ""
    // `-startTab qibla` opens another tab first (used for CI screenshots).
    @State private var tab = AppTab(rawValue: UserDefaults.standard.string(forKey: "startTab") ?? "") ?? .times
    /// Left by a control (Control Center, the Lock Screen, the Action button) that opened the app.
    @AppStorage(OpenScreenIntent.key) private var openScreen = ""
    @AppStorage("ibadahPart") private var ibadahPart = IbadahPart.tasbih

    var body: some View {
        @Bindable var model = model
        TabView(selection: $tab) {
            Tab("Prayer times", systemImage: "clock", value: AppTab.times) {
                PrayerTimesView { tab = .settings }
                    .safeAreaInset(edge: .bottom) { MiniPlayer() }
            }
            Tab("Qibla", systemImage: "safari", value: AppTab.qibla) {
                QiblaView()
                    .safeAreaInset(edge: .bottom) { MiniPlayer() }
            }
            Tab("Qur'an", systemImage: "book", value: AppTab.quran) {
                QuranView()
            }
            Tab("Ibadah", systemImage: "circle.dotted", value: AppTab.ibadah) {
                IbadahView()
                    .safeAreaInset(edge: .bottom) { MiniPlayer() }
            }
            Tab("Settings", systemImage: "gearshape", value: AppTab.settings) {
                SettingsView()
                    .safeAreaInset(edge: .bottom) { MiniPlayer() }
            }
        }
        // Rebuilt when the language changes, so every screen picks up the new text.
        .id(model.settings.language)
        // From the widgets: wajh://page/42 opens a page, wajh://verse/261 a verse.
        .onOpenURL { url in
            guard url.scheme == "wajh", let number = Int(url.lastPathComponent) else { return }
            switch url.host() {
            case "page": SharedStore.defaults.set(number, forKey: QuranProgress.pageKey)
            case "verse": UserDefaults.standard.set(number, forKey: "openVerse")
            default: return
            }
            tab = .quran
        }
        .onChange(of: openScreen, initial: true) {
            guard let screen = AppScreen(rawValue: openScreen) else { return }
            openScreen = ""
            switch screen {
            case .qibla:
                tab = .qibla
            case .tasbih:
                ibadahPart = .tasbih
                tab = .ibadah
            case .quran:
                tab = .quran
            }
        }
        .fullScreenCover(isPresented: .constant(!model.onboarded)) {
            SetupView {
                tab = .times
                // New in this version is new to everyone after the setup.
                whatsNewSeen = WhatsNewView.version
                model.finishSetup()
            }
        }
        // Once after updating, for people who used the app before (not in CI runs, which skip the setup).
        .sheet(isPresented: Binding(
            get: { model.onboarded && whatsNewSeen != WhatsNewView.version
                && !UserDefaults.standard.bool(forKey: "skipOnboarding") },
            set: { if !$0 { whatsNewSeen = WhatsNewView.version } })) {
            WhatsNewView { whatsNewSeen = WhatsNewView.version }
        }
        .alert("Notifications are off", isPresented: $model.showNotificationsOff) {
            Button("Open Settings") { openAppSettings() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Allow notifications for this app in iPhone Settings to get reminders.")
        }
        .task {
            if model.onboarded { model.start() }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active && model.onboarded { model.refresh() }
            if phase == .background {
                model.scheduleBackgroundRefresh()
                // The page read and the khatm, for the Continue reading widget.
                WidgetCenter.shared.reloadTimelines(ofKind: "ContinueReading")
            }
        }
        // Midnight, a new time zone or a clock change: recalculate and reschedule.
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.significantTimeChangeNotification)) { _ in
            if model.onboarded { model.refresh() }
        }
    }
}

@MainActor
func openAppSettings() {
    if let url = URL(string: UIApplication.openSettingsURLString) {
        UIApplication.shared.open(url)
    }
}
