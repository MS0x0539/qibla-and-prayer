import ActivityKit
import SwiftUI
import WidgetKit

@main
struct PrayerWidgets: WidgetBundle {
    var body: some Widget {
        NextPrayerWidget()
        IftarLiveActivity()
    }
}

// MARK: - Next prayer (Home Screen and Lock Screen)

struct PrayerEntry: TimelineEntry {
    let date: Date
    /// nil until the app has saved a place.
    let next: PrayerTime?
    let placeName: String
    let zone: TimeZone
    let locale: Locale
}

struct PrayerProvider: TimelineProvider {
    func placeholder(in context: Context) -> PrayerEntry {
        PrayerEntry(
            date: .now, next: PrayerTime(kind: .maghrib, time: .now.addingTimeInterval(4_500)),
            placeName: "", zone: .current, locale: .current)
    }

    func getSnapshot(in context: Context, completion: @escaping (PrayerEntry) -> Void) {
        completion(entries(from: .now).first ?? placeholder(in: context))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<PrayerEntry>) -> Void) {
        let now = Date.now
        let entries = entries(from: now)
        // Without a place, look again in an hour; otherwise a new timeline after the last prayer in it.
        let policy: TimelineReloadPolicy = entries.first?.next == nil ? .after(now.addingTimeInterval(3_600)) : .atEnd
        completion(Timeline(entries: entries, policy: policy))
    }

    /// Now, and again at each prayer time for about a day: each entry shows the prayer after it.
    private func entries(from now: Date) -> [PrayerEntry] {
        guard let saved = SharedStore.saved() else {
            return [PrayerEntry(date: now, next: nil, placeName: "", zone: .current, locale: .current)]
        }
        AppLanguage.current = saved.settings.language
        let place = saved.place
        var entries: [PrayerEntry] = []
        var date = now
        while entries.count < 6, let next = Prayers.next(after: date, place: place, settings: saved.settings) {
            entries.append(PrayerEntry(
                date: date, next: next, placeName: place.displayName, zone: place.timeZone,
                locale: saved.settings.language.locale))
            date = next.time
        }
        if entries.isEmpty {
            entries.append(PrayerEntry(date: now, next: nil, placeName: place.displayName, zone: place.timeZone, locale: .current))
        }
        return entries
    }
}

struct NextPrayerWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "NextPrayer", provider: PrayerProvider()) { entry in
            NextPrayerView(entry: entry)
        }
        .configurationDisplayName("Next prayer")
        .description("The next prayer, its time and a countdown.")
        .supportedFamilies([.systemSmall, .accessoryRectangular, .accessoryInline])
    }
}

struct NextPrayerView: View {
    @Environment(\.widgetFamily) private var family
    let entry: PrayerEntry

    var body: some View {
        Group {
            if let next = entry.next {
                let title = next.kind.title(on: next.time, in: entry.zone)
                let time = Formats.time(next.time, in: entry.zone)
                switch family {
                case .accessoryInline:
                    Text(verbatim: "\(title) \(time)")
                case .accessoryRectangular:
                    VStack(alignment: .leading, spacing: 0) {
                        Text(verbatim: "\(title) \(time)")
                            .font(.headline)
                            .widgetAccentable()
                        Text(timerInterval: entry.date...next.time, countsDown: true)
                            .font(.body.monospacedDigit())
                        Text(verbatim: entry.placeName)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                default:
                    small(title: title, time: time, next: next)
                }
            } else {
                Text("Open the app first, so it knows where you are.")
                    .font(.footnote)
                    .foregroundStyle(Theme.muted)
            }
        }
        .environment(\.locale, entry.locale)
        .containerBackground(for: .widget) { Theme.background }
    }

    private func small(title: String, time: String, next: PrayerTime) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 6) {
                EightPointStar()
                    .stroke(Theme.gold, lineWidth: 1)
                    .frame(width: 14, height: 14)
                Text(verbatim: entry.placeName)
                    .font(.caption2)
                    .foregroundStyle(Theme.muted)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
            Text("Next prayer")
                .font(.caption)
                .foregroundStyle(Theme.muted)
            Text(verbatim: title)
                .font(.system(.title, design: .serif).weight(.medium))
                .foregroundStyle(Theme.ink)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
            Text(verbatim: time)
                .font(.headline.monospacedDigit())
                .foregroundStyle(Theme.gold)
            Text(timerInterval: entry.date...next.time, countsDown: true)
                .font(.subheadline.monospacedDigit())
                .foregroundStyle(Theme.muted)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    }
}

// MARK: - Iftar countdown (Live Activity)

struct IftarLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: IftarAttributes.self) { context in
            IftarLockScreen(context: context)
                .activityBackgroundTint(Theme.background)
                .activitySystemActionForegroundColor(Theme.gold)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    Label(context.attributes.title, systemImage: "moon.stars.fill")
                        .font(.headline)
                        .foregroundStyle(Theme.gold)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    IftarCountdown(context: context)
                        .font(.title3.monospacedDigit())
                        .foregroundStyle(Theme.gold)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    Text(verbatim: "\(context.attributes.place) · \(context.attributes.time)")
                        .font(.caption)
                        .foregroundStyle(Theme.muted)
                }
            } compactLeading: {
                Image(systemName: "moon.stars.fill")
                    .foregroundStyle(Theme.gold)
            } compactTrailing: {
                IftarCountdown(context: context)
                    .monospacedDigit()
                    .foregroundStyle(Theme.gold)
                    .frame(maxWidth: 56)
            } minimal: {
                Image(systemName: "moon.stars.fill")
                    .foregroundStyle(Theme.gold)
            }
        }
    }
}

private struct IftarLockScreen: View {
    let context: ActivityViewContext<IftarAttributes>

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: "moon.stars.fill")
                .font(.title2)
                .foregroundStyle(Theme.gold)
            VStack(alignment: .leading, spacing: 2) {
                Text(verbatim: context.attributes.title)
                    .font(.headline)
                    .foregroundStyle(Theme.ink)
                Text(verbatim: "\(context.attributes.place) · \(context.attributes.time)")
                    .font(.subheadline)
                    .foregroundStyle(Theme.muted)
            }
            Spacer()
            IftarCountdown(context: context)
                .font(.system(.title, design: .serif).monospacedDigit())
                .foregroundStyle(Theme.gold)
        }
        .padding(16)
    }
}

/// Counts down to iftar; once it's time (or the activity went stale), says so instead.
private struct IftarCountdown: View {
    let context: ActivityViewContext<IftarAttributes>

    var body: some View {
        let now = Date.now
        let iftar = context.state.iftar
        if context.isStale || iftar <= now {
            Text(verbatim: context.attributes.arrived)
                .multilineTextAlignment(.trailing)
        } else {
            Text(timerInterval: now...iftar, countsDown: true)
                .multilineTextAlignment(.trailing)
        }
    }
}
