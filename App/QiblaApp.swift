import SwiftUI
import TipKit
import WidgetKit
import UIKit

@main
struct QiblaApp: App {
    @State private var model = AppModel()

    init() {
        // CI screenshots and UI tests: `-tips hide` shows no tips, `-tips reset` shows them as on a first visit,
        // `-tips day` goes straight to the Qur'an's second tip (the paper page).
        let testing = UserDefaults.standard.string(forKey: "tips")
        if testing == "hide" { Tips.hideAllTipsForTesting() }
        if testing == "reset" || testing == "day" { try? Tips.resetDatastore() }
        try? Tips.configure()
        if testing == "day" { TurnPageTip().invalidate(reason: .actionPerformed) }
    }

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
    case home, times, qibla, quran, menu
}

struct RootView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.scenePhase) private var scenePhase
    @AppStorage(WhatsNewView.seenKey) private var whatsNewSeen = ""
    // `-startTab qibla` opens another tab first, `-menuPage tasbih` a page of Menu (used for CI screenshots).
    @State private var tab = AppTab(rawValue: UserDefaults.standard.string(forKey: "startTab") ?? "") ?? .home
    @State private var menuPath: [MenuPage] = UserDefaults.standard.string(forKey: "menuPage")
        .flatMap { MenuPage(rawValue: $0) }.map { [$0] } ?? []
    /// Left by a control (Control Center, the Lock Screen, the Action button) that opened the app.
    @AppStorage(OpenScreenIntent.key) private var openScreen = ""

    var body: some View {
        @Bindable var model = model
        TabView(selection: $tab) {
            Tab("Home", systemImage: "house", value: AppTab.home) {
                HomeView()
                    .safeAreaInset(edge: .bottom) { MiniPlayer() }
            }
            Tab("Prayer times", systemImage: "clock", value: AppTab.times) {
                PrayerTimesView { open(.settings) }
                    .safeAreaInset(edge: .bottom) { MiniPlayer() }
            }
            Tab("Qibla", systemImage: "safari", value: AppTab.qibla) {
                QiblaView()
                    .safeAreaInset(edge: .bottom) { MiniPlayer() }
            }
            Tab("Qur'an", systemImage: "book", value: AppTab.quran) {
                QuranView()
            }
            Tab("Menu", systemImage: "square.grid.2x2", value: AppTab.menu) {
                MenuView(path: $menuPath)
                    .safeAreaInset(edge: .bottom) { MiniPlayer() }
            }
        }
        // Rebuilt when the language changes, so every screen picks up the new text.
        .id(model.settings.language)
        // From the widgets: wajh://page/42 opens a page, wajh://verse/261 a verse.
        .onOpenURL { url in
            guard url.scheme == "wajh", let number = Int(url.lastPathComponent) else { return }
            // Any app can open such a link: only real pages and verses are taken.
            switch url.host() {
            case "page" where (1...Quran.pageCount).contains(number):
                SharedStore.defaults.set(number, forKey: QuranProgress.pageKey)
            case "verse" where Quran.shared.verses.indices.contains(number):
                UserDefaults.standard.set(number, forKey: "openVerse")
            default:
                return
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
                open(.tasbih)
            case .quran:
                tab = .quran
            }
        }
        .fullScreenCover(isPresented: .constant(!model.onboarded)) {
            SetupView {
                tab = .home
                menuPath = []
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

    /// Menu, opened on one of its pages.
    private func open(_ page: MenuPage) {
        menuPath = [page]
        tab = .menu
    }
}

@MainActor
func openAppSettings() {
    if let url = URL(string: UIApplication.openSettingsURLString) {
        UIApplication.shared.open(url)
    }
}
