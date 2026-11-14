import SwiftUI
import UIKit

/// The pages that aren't tabs. `-menuPage tasbih` opens one at launch (for CI screenshots and UI tests).
enum MenuPage: String, Hashable {
    case tasbih, tracker, missed, khatm, calendar, mosques, live, downloads, settings

    var title: LocalizedStringKey {
        switch self {
        case .tasbih: "Tasbih"
        case .tracker: "Prayer tracker"
        case .missed: "Missed prayers"
        case .khatm: "Khatm"
        case .calendar: "Islamic calendar"
        case .mosques: "Mosques nearby"
        case .live: "Makkah live"
        case .downloads: "Downloads"
        case .settings: "Settings"
        }
    }

    /// The tile's own icon, drawn for the app (Assets.xcassets/MenuIcons); nil for the buttons at the top.
    var icon: String? {
        switch self {
        case .tasbih: "icon-tasbih"
        case .tracker: "icon-tracker"
        case .missed: "icon-missed"
        case .khatm: "icon-khatm"
        case .calendar: "icon-calendar"
        case .mosques: "icon-mosques"
        case .live: "icon-live"
        case .downloads, .settings: nil
        }
    }

    /// The system symbol on the buttons at the top, and on a tile without an icon of its own.
    var symbol: String {
        switch self {
        case .tasbih: "circle.dotted"
        case .tracker: "checkmark.circle"
        case .missed: "hourglass"
        case .khatm: "book.closed"
        case .calendar: "moon.stars"
        case .mosques: "map"
        case .live: "video"
        case .downloads: "arrow.down.circle"
        case .settings: "gearshape"
        }
    }
}

/// Menu: everything that isn't a tab, as tiles; feedback and Settings below them.
struct MenuView: View {
    @Binding var path: [MenuPage]
    @Environment(\.dynamicTypeSize) private var typeSize
    @Environment(\.openURL) private var openURL
    @State private var showingAddress = false

    private static let tiles: [MenuPage] = [.tasbih, .tracker, .missed, .khatm, .calendar, .mosques, .live]
    private static let address = "support@qibla.dev"

    var body: some View {
        NavigationStack(path: $path) {
            ScrollView {
                VStack(spacing: 28) {
                    tileGrid
                    more
                }
                .padding(.horizontal)
                .padding(.vertical, 8)
            }
            .background(Theme.background.ignoresSafeArea())
            .navigationTitle("Menu")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    NavigationLink(value: MenuPage.downloads) { Image(systemName: MenuPage.downloads.symbol) }
                        .accessibilityLabel(Text("Downloads"))
                }
                ToolbarItem(placement: .topBarTrailing) {
                    NavigationLink(value: MenuPage.settings) { Image(systemName: MenuPage.settings.symbol) }
                        .accessibilityLabel(Text("Settings"))
                }
            }
            .navigationDestination(for: MenuPage.self) { page in
                destination(page)
            }
            .alert(Text(verbatim: Self.address), isPresented: $showingAddress) {
                Button("Copy") { UIPasteboard.general.string = Self.address }
                Button("OK", role: .cancel) {}
            } message: {
                Text("Mail isn't set up on this iPhone. Copy the address to write from another app.")
            }
        }
    }

    /// Three tiles a row, two at the largest text sizes; the tiles of a row as tall as each other.
    private var tileGrid: some View {
        let columns = typeSize.isAccessibilitySize ? 2 : 3
        let rows = stride(from: 0, to: Self.tiles.count, by: columns).map {
            Array(Self.tiles[$0..<min($0 + columns, Self.tiles.count)])
        }
        return Grid(horizontalSpacing: 12, verticalSpacing: 12) {
            ForEach(rows, id: \.self) { row in
                GridRow {
                    ForEach(row, id: \.self) { page in
                        NavigationLink(value: page) { MenuTile(page: page) }
                            .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    /// Feedback and Settings, under a quiet heading.
    private var more: some View {
        let layout = typeSize.isAccessibilitySize ? AnyLayout(VStackLayout(spacing: 12)) : AnyLayout(HStackLayout(spacing: 12))
        return VStack(spacing: 14) {
            HStack(spacing: 12) {
                Theme.line.frame(height: 1)
                Text("More")
                    .font(.subheadline)
                    .foregroundStyle(Theme.muted)
                    .accessibilityAddTraits(.isHeader)
                Theme.line.frame(height: 1)
            }
            layout {
                Button {
                    openURL(feedbackMail) { accepted in
                        if !accepted { showingAddress = true }
                    }
                } label: {
                    MoreLabel(title: "Feedback", symbol: "envelope")
                }
                NavigationLink(value: MenuPage.settings) {
                    MoreLabel(title: "Settings", symbol: MenuPage.settings.symbol)
                }
            }
            .buttonStyle(.plain)
        }
    }

    /// A new email to support, ending with the app's and iOS's versions to help answer it.
    private var feedbackMail: URL {
        let info = Bundle.main.infoDictionary ?? [:]
        let version = "\(info["CFBundleShortVersionString"] as? String ?? "") (\(info["CFBundleVersion"] as? String ?? ""))"
        var mail = URLComponents()
        mail.scheme = "mailto"
        mail.path = Self.address
        mail.queryItems = [
            URLQueryItem(name: "subject", value: "Wajh feedback"),
            URLQueryItem(name: "body", value: "\n\n—\nWajh \(version) · iOS \(UIDevice.current.systemVersion)"),
        ]
        return mail.url ?? URL(string: "mailto:\(Self.address)")!
    }

    @ViewBuilder
    private func destination(_ page: MenuPage) -> some View {
        switch page {
        case .tasbih:
            TasbihView()
                .navigationTitle(page.title)
                .navigationBarTitleDisplayMode(.inline)
        case .tracker: PrayerTrackerView()
        case .missed: MissedPrayersView()
        case .khatm: KhatmView()
        case .calendar: IslamicCalendarView()
        case .mosques: QiblaMapView()
        case .live: MakkahLiveView()
        case .downloads: DownloadsView()
        case .settings: SettingsView()
        }
    }
}

/// A tile: its gold icon over its name.
private struct MenuTile: View {
    let page: MenuPage
    /// The icon grows with the text size.
    @ScaledMetric(relativeTo: .title) private var iconSize: CGFloat = 36

    var body: some View {
        VStack(spacing: 10) {
            Spacer(minLength: 0)
            Group {
                if let icon = page.icon {
                    Image(icon)
                        .resizable()
                        .scaledToFit()
                        .frame(width: iconSize, height: iconSize)
                } else {
                    Image(systemName: page.symbol)
                        .font(.title)
                }
            }
            .foregroundStyle(Theme.gold)
            .accessibilityHidden(true)
            Spacer(minLength: 0)
            Text(page.title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Theme.ink)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 14)
        .frame(maxWidth: .infinity, minHeight: 116, maxHeight: .infinity)
        .background(Theme.card, in: RoundedRectangle(cornerRadius: 18))
        .overlay(RoundedRectangle(cornerRadius: 18).strokeBorder(Theme.line, lineWidth: 1))
        .contentShape(RoundedRectangle(cornerRadius: 18))
    }
}

/// One of the two wide buttons under the tiles.
private struct MoreLabel: View {
    let title: LocalizedStringKey
    let symbol: String

    var body: some View {
        Label {
            Text(title)
        } icon: {
            Image(systemName: symbol)
                .foregroundStyle(Theme.gold)
        }
        .font(.body.weight(.semibold))
        .foregroundStyle(Theme.ink)
        .padding(.horizontal, 12)
        .frame(maxWidth: .infinity, minHeight: 52)
        .background(Theme.card, in: RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(Theme.line, lineWidth: 1))
        .contentShape(RoundedRectangle(cornerRadius: 16))
    }
}

/// The recitations saved to listen offline, and the reciter they are for: as in the reader's settings.
struct DownloadsView: View {
    @AppStorage("reciter") private var reciterID = Reciter.all[0].id

    var body: some View {
        List {
            Section("Reciter") {
                NavigationLink {
                    ReciterList()
                } label: {
                    Text(verbatim: Reciter.named(reciterID).displayName)
                        .foregroundStyle(Theme.ink)
                }
            }
            .listRowBackground(Theme.card)

            OfflineRecitationSection()
        }
        .scrollContentBackground(.hidden)
        .background(Theme.background.ignoresSafeArea())
        .navigationTitle("Downloads")
    }
}
