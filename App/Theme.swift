import SwiftUI
import UIKit

/// The "Geometry" look: deep green-black, warm ink, gold accents, serif display type.
enum Theme {
    static let background = Color(hex: 0x0E1613)
    static let card = Color(hex: 0x16221D)
    static let ink = Color(hex: 0xEFE7D6)
    static let muted = Color(hex: 0xA8A08C)
    static let gold = Color(hex: 0xC9A45C)
    static let line = gold.opacity(0.22)
}

extension Color {
    init(hex: UInt32) {
        self.init(
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255)
    }
}

/// Two overlapping squares: the eight-pointed star used as the app's motif.
struct EightPointStar: Shape {
    func path(in rect: CGRect) -> Path {
        let side = min(rect.width, rect.height) / sqrt(2)
        let square = Path(CGRect(x: rect.midX - side / 2, y: rect.midY - side / 2, width: side, height: side))
        let turn = CGAffineTransform(translationX: rect.midX, y: rect.midY)
            .rotated(by: .pi / 4)
            .translatedBy(x: -rect.midX, y: -rect.midY)
        var path = square
        path.addPath(square, transform: turn)
        return path
    }
}

/// The fixed pointer above the compass dial.
struct Triangle: Shape {
    func path(in rect: CGRect) -> Path {
        Path { path in
            path.move(to: CGPoint(x: rect.minX, y: rect.minY))
            path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
            path.addLine(to: CGPoint(x: rect.midX, y: rect.maxY))
            path.closeSubpath()
        }
    }
}

/// Dates, times and numbers in the app's language, always in the Gregorian calendar (or explicitly
/// Umm al-Qura for the Hijri date), whatever calendar the iPhone itself is set to.
enum Formats {
    private static func gregorian(_ zone: TimeZone) -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = zone
        return calendar
    }

    private static func style(_ zone: TimeZone) -> Date.FormatStyle {
        Date.FormatStyle(locale: .app, calendar: gregorian(zone), timeZone: zone)
    }

    static func time(_ date: Date, in zone: TimeZone) -> String {
        date.formatted(Date.FormatStyle(date: .omitted, time: .shortened, locale: .app, calendar: gregorian(zone), timeZone: zone))
    }

    /// Month grid: the column already names the prayer, so 12-hour clocks drop AM/PM ("4:16", "10:07").
    static func gridTime(_ date: Date, in zone: TimeZone) -> String {
        date.formatted(style(zone).hour(.defaultDigits(amPM: .omitted)).minute(.twoDigits))
    }

    static func weekdayDate(_ date: Date, in zone: TimeZone) -> String {
        date.formatted(style(zone).weekday(.wide).day().month(.wide))
    }

    /// The Umm al-Qura date ("2 Jumada II 1448"), moved by `offset` days to match local moon sighting.
    static func hijriDate(_ date: Date, in zone: TimeZone, offset: Int = 0) -> String {
        let shifted = Calendar(identifier: .gregorian).date(byAdding: .day, value: offset, to: date) ?? date
        let format = Date.VerbatimFormatStyle(
            format: "\(day: .defaultDigits) \(month: .wide) \(year: .defaultDigits)",
            locale: .app, timeZone: zone, calendar: Calendar(identifier: .islamicUmmAlQura))
        return shifted.formatted(format)
    }

    static func monthTitle(_ date: Date, in zone: TimeZone) -> String {
        date.formatted(style(zone).month(.wide).year())
    }

    static func shortDate(_ date: Date, in zone: TimeZone) -> String {
        date.formatted(style(zone).weekday(.abbreviated).day().month(.abbreviated))
    }

    static func dayOfMonth(_ date: Date, in zone: TimeZone) -> String {
        date.formatted(style(zone).day())
    }

    static func number(_ value: Int) -> String {
        // No thousands separator: years read "2026" and "1448", not "2,026" or "1.448".
        value.formatted(.number.grouping(.never).locale(.app))
    }

    static func cardinal(_ degrees: Double) -> String {
        let names: [String.LocalizationValue] = ["N", "NE", "E", "SE", "S", "SW", "W", "NW"]
        let normalized = (degrees.truncatingRemainder(dividingBy: 360) + 360).truncatingRemainder(dividingBy: 360)
        return String(localized: names[Int((normalized / 45).rounded()) % 8], bundle: .app)
    }

    /// "126° SE"
    static func bearing(_ degrees: Double) -> String {
        "\(number(Int(degrees.rounded()) % 360))° \(cardinal(degrees))"
    }

    static func distance(_ kilometres: Double) -> String {
        let formatter = MeasurementFormatter()
        formatter.locale = .app
        formatter.unitOptions = .providedUnit
        formatter.numberFormatter.maximumFractionDigits = 0
        return formatter.string(from: Measurement(value: kilometres, unit: UnitLength.kilometers))
    }
}

extension Bundle {
    var displayName: String {
        object(forInfoDictionaryKey: "CFBundleDisplayName") as? String
            ?? object(forInfoDictionaryKey: "CFBundleName") as? String ?? ""
    }

    var versionText: String {
        let version = infoDictionary?["CFBundleShortVersionString"] as? String ?? "?"
        let build = infoDictionary?["CFBundleVersion"] as? String ?? "?"
        return "\(version) (\(build))"
    }
}

@MainActor
func openAppSettings() {
    if let url = URL(string: UIApplication.openSettingsURLString) {
        UIApplication.shared.open(url)
    }
}

/// Shown instead of times or the compass until there is a place to calculate for.
struct NoPlaceView: View {
    @Environment(AppModel.self) private var model
    @State private var searching = false

    var body: some View {
        VStack(spacing: 16) {
            if model.settings.useCurrentLocation && model.location.isAuthorized && !model.location.failed {
                ProgressView("Finding your location")
            } else {
                Image(systemName: "location.slash")
                    .font(.largeTitle)
                    .foregroundStyle(Theme.gold)
                if model.location.isDenied {
                    Text("Prayer times and the Qibla need your location.")
                        .multilineTextAlignment(.center)
                    placeButton("Allow location access") { openAppSettings() }
                } else if model.settings.useCurrentLocation && model.location.failed {
                    Text("Your location could not be found.")
                        .multilineTextAlignment(.center)
                    placeButton("Try again") { model.refresh() }
                } else {
                    Text("Prayer times and the Qibla need your location.")
                        .multilineTextAlignment(.center)
                    placeButton("Use my location") { model.useCurrentLocation() }
                }
            }
            placeButton("Search for a city") { searching = true }
        }
        .foregroundStyle(Theme.ink)
        .padding(32)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .sheet(isPresented: $searching) {
            NavigationStack { CitySearchView() }
        }
    }

    /// Gold, bordered and full-height: the surrounding views set ink text, which would otherwise
    /// make these buttons look like plain text with a tiny tap area.
    private func placeButton(_ title: LocalizedStringKey, action: @escaping () -> Void) -> some View {
        Button(title, action: action)
            .buttonStyle(.bordered)
            .controlSize(.large)
            .foregroundStyle(Theme.gold)
    }
}
