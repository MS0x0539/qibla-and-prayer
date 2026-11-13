import AppIntents
import SwiftUI
import WidgetKit

/// The tasbih on the Home Screen, in StandBy and on the Lock Screen: a tap counts one, as in the app, which counts on
/// from the same number (the App Group).
struct TasbihWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: TasbihStore.widgetKind, provider: TasbihProvider()) { entry in
            TasbihWidgetView(entry: entry)
                .containerBackground(Theme.background, for: .widget)
        }
        .configurationDisplayName("Tasbih")
        .description("Count with a tap, without opening the app.")
        .supportedFamilies([.systemSmall, .accessoryCircular])
    }
}

struct TasbihEntry: TimelineEntry {
    let date: Date
    let counter: TasbihCounter
    /// The phrase being counted, in the app's language; nil when counting freely.
    let name: String?
}

struct TasbihProvider: TimelineProvider {
    func placeholder(in context: Context) -> TasbihEntry {
        TasbihEntry(date: .now, counter: TasbihCounter(count: 12), name: nil)
    }

    func getSnapshot(in context: Context, completion: @escaping (TasbihEntry) -> Void) {
        completion(entry())
    }

    /// Redrawn after each tap (the system reloads it when the intent finishes) and when the app counted.
    func getTimeline(in context: Context, completion: @escaping (Timeline<TasbihEntry>) -> Void) {
        completion(Timeline(entries: [entry()], policy: .never))
    }

    private func entry() -> TasbihEntry {
        if let settings = SharedStore.load(AppSettings.self, from: "settings") {
            AppLanguage.current = settings.language
        }
        return TasbihEntry(date: .now, counter: TasbihStore.counter, name: TasbihStore.current?.name)
    }
}

struct TasbihWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: TasbihEntry

    var body: some View {
        let counter = entry.counter
        let progress = counter.goal > 0 ? min(1, Double(counter.count) / Double(counter.goal)) : 0
        Button(intent: CountTasbihIntent()) {
            if family == .accessoryCircular {
                Gauge(value: progress) {
                    Text("Tasbih")
                } currentValueLabel: {
                    Text(verbatim: Formats.number(counter.count))
                }
                .gaugeStyle(.accessoryCircularCapacity)
            } else {
                VStack(spacing: 8) {
                    Text(verbatim: entry.name ?? String(localized: "Tasbih", bundle: .app))
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Theme.gold)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                    ZStack {
                        Circle()
                            .stroke(Theme.line, lineWidth: 5)
                        Circle()
                            .trim(from: 0, to: progress)
                            .stroke(Theme.gold, style: StrokeStyle(lineWidth: 5, lineCap: .round))
                            .rotationEffect(.degrees(-90))
                        Text(verbatim: Formats.number(counter.count))
                            .font(.system(size: 36, weight: .medium, design: .serif).monospacedDigit())
                            .foregroundStyle(Theme.ink)
                            .minimumScaleFactor(0.5)
                            .lineLimit(1)
                            .padding(12)
                    }
                    .frame(width: 98, height: 98)
                }
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(verbatim: entry.name ?? String(localized: "Tasbih", bundle: .app)))
        .accessibilityValue(Text(verbatim: Formats.number(counter.count)))
        .accessibilityHint(Text("Double-tap to count one."))
    }
}
