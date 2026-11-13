import ActivityKit
import Foundation

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
    }

    var place: String
}
