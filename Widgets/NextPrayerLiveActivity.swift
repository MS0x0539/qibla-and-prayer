import ActivityKit
import SwiftUI
import WidgetKit

/// The next prayer on the Lock Screen and in the Dynamic Island, counting down; once its time has come (the activity
/// goes stale then), it says so and shows the prayer after it until the app moves it on.
struct NextPrayerLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: NextPrayerAttributes.self) { context in
            NextPrayerLockScreen(context: context)
                .activityBackgroundTint(Theme.background)
                .activitySystemActionForegroundColor(Theme.gold)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    Label(context.state.name, systemImage: "clock")
                        .font(.headline)
                        .foregroundStyle(Theme.gold)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    NextPrayerCountdown(context: context)
                        .font(.title3.monospacedDigit())
                        .foregroundStyle(Theme.gold)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    Text(verbatim: NextPrayerLockScreen.detail(context))
                        .font(.caption)
                        .foregroundStyle(Theme.muted)
                }
            } compactLeading: {
                Image(systemName: "clock")
                    .foregroundStyle(Theme.gold)
            } compactTrailing: {
                NextPrayerCountdown(context: context, compact: true)
                    .monospacedDigit()
                    .foregroundStyle(Theme.gold)
                    .frame(maxWidth: 56)
            } minimal: {
                Image(systemName: "clock")
                    .foregroundStyle(Theme.gold)
            }
        }
    }
}

private struct NextPrayerLockScreen: View {
    let context: ActivityViewContext<NextPrayerAttributes>

    /// "Amsterdam · 17:02" while counting down, the prayer after it once the time has come.
    static func detail(_ context: ActivityViewContext<NextPrayerAttributes>) -> String {
        arrived(context) ? context.state.following : "\(context.attributes.place) · \(context.state.timeText)"
    }

    static func arrived(_ context: ActivityViewContext<NextPrayerAttributes>) -> Bool {
        context.isStale || context.state.time <= .now
    }

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: "clock")
                .font(.title2)
                .foregroundStyle(Theme.gold)
            VStack(alignment: .leading, spacing: 2) {
                Text(verbatim: Self.arrived(context) ? context.state.arrived : context.state.name)
                    .font(.headline)
                    .foregroundStyle(Theme.ink)
                Text(verbatim: Self.detail(context))
                    .font(.subheadline)
                    .foregroundStyle(Theme.muted)
            }
            Spacer()
            if !Self.arrived(context) {
                NextPrayerCountdown(context: context)
                    .font(.system(.title, design: .serif).monospacedDigit())
                    .foregroundStyle(Theme.gold)
            }
        }
        .padding(16)
    }
}

/// Counts down to the prayer; once it's time, says so, or in the narrow Dynamic Island shows a tick.
private struct NextPrayerCountdown: View {
    let context: ActivityViewContext<NextPrayerAttributes>
    var compact = false

    var body: some View {
        let now = Date.now
        let time = context.state.time
        if (context.isStale || time <= now) && compact {
            Image(systemName: "checkmark.circle.fill")
        } else if context.isStale || time <= now {
            Text(verbatim: context.state.arrived)
                .multilineTextAlignment(.trailing)
        } else {
            Text(timerInterval: now...time, countsDown: true)
                .multilineTextAlignment(.trailing)
        }
    }
}
