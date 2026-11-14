import ActivityKit
import Foundation
import SwiftUI

/// The next prayer with a countdown on the Lock Screen and in the Dynamic Island. Shared by the app, which starts it
/// and moves it on to the prayer that is next whenever it runs, and the widget extension, which draws it.
struct NextPrayerAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable {
        var time: Date
        // Written in the app's language: the widget extension can't tell which language was picked in the app.
        var name: String
        var timeText: String
        /// Shown once the time has come: "Time for Maghrib."
        var arrived: String
        /// The prayer after it, "Isha · 18:43", shown once this one has come.
        var following: String
        // Optional, so an activity started by an older version still reads.
        /// The day's six times, sunrise among them, the next one among them.
        var day: [Row]? = nil
        /// The time before the next one: where the line that fills up towards it starts.
        var since: Date? = nil
        /// "until Maghrib", under the countdown.
        var until: String? = nil
    }

    struct Row: Codable, Hashable {
        var name: String
        var time: String
        var date: Date
    }

    var place: String
}

/// The next prayer as the Lock Screen shows it: the place, the countdown, a line filling up from the time before, and
/// the day's times with the next one marked. Drawn by the Live Activity, and by setup as its preview.
struct NextPrayerCard: View {
    let place: String
    let state: NextPrayerAttributes.ContentState
    /// Once the time has come (the activity goes stale): "Time for Maghrib." instead of the countdown.
    let arrived: Bool

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            VStack(alignment: .leading, spacing: 0) {
                Text(verbatim: place)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Theme.muted)
                    .lineLimit(1)
                if arrived {
                    Text(verbatim: state.arrived)
                        .font(.system(.title2, design: .serif).weight(.medium))
                        .foregroundStyle(Theme.gold)
                        .minimumScaleFactor(0.7)
                        .padding(.top, 6)
                } else {
                    Text(timerInterval: Date.now...max(state.time, .now), countsDown: true)
                        .font(.system(size: 40, weight: .medium, design: .serif).monospacedDigit())
                        .foregroundStyle(Theme.ink)
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                    Text(verbatim: state.until ?? state.name)
                        .font(.subheadline)
                        .foregroundStyle(Theme.muted)
                        .lineLimit(1)
                }
                Spacer(minLength: 10)
                if !arrived, let since = state.since, since < state.time {
                    ProgressView(timerInterval: since...state.time, countsDown: false) {
                        EmptyView()
                    } currentValueLabel: {
                        EmptyView()
                    }
                    .progressViewStyle(.linear)
                    .tint(Theme.gold)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
            if let day = state.day, !day.isEmpty {
                VStack(spacing: 1) {
                    ForEach(day, id: \.self) { row in
                        let next = row.date == state.time
                        HStack(spacing: 8) {
                            Text(verbatim: row.name)
                            Spacer(minLength: 6)
                            Text(verbatim: row.time)
                                .monospacedDigit()
                        }
                        .font(.footnote.weight(next ? .semibold : .regular))
                        .foregroundStyle(next ? Theme.gold : row.date < state.time ? Theme.muted : Theme.ink)
                        .lineLimit(1)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 2)
                        .background(next ? Theme.gold.opacity(0.16) : .clear, in: RoundedRectangle(cornerRadius: 6))
                    }
                }
                .padding(5)
                .background(Theme.card, in: RoundedRectangle(cornerRadius: 12))
                .frame(width: 168)
            }
        }
        .padding(14)
    }
}
