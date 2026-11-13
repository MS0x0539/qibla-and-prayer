import SwiftUI
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
                model.finishSetup()
            }
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
            if phase == .background { model.scheduleBackgroundRefresh() }
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
