import ActivityKit
import Foundation

/// The iftar countdown on the Lock Screen and in the Dynamic Island. Shared by the app, which starts
/// it, and the widget extension, which draws it.
struct IftarAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable {
        var iftar: Date
    }

    // Written in the app's language when the countdown starts: the widget extension can't tell which
    // language was picked inside the app.
    var title: String
    var place: String
    var time: String
    var arrived: String
}
