import AppIntents
import SwiftUI
import WidgetKit

// Buttons for Control Center, the Lock Screen and the Action button, each opening the app on one screen.

struct QiblaControl: ControlWidget {
    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: "QiblaControl") {
            ControlWidgetButton(action: OpenScreenIntent(target: .qibla)) {
                Label("Qibla", systemImage: "safari")
            }
        }
        .displayName("Qibla")
        .description("Opens the Qibla compass.")
    }
}

struct TasbihControl: ControlWidget {
    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: "TasbihControl") {
            ControlWidgetButton(action: OpenScreenIntent(target: .tasbih)) {
                Label("Tasbih", systemImage: "circle.dotted")
            }
        }
        .displayName("Tasbih")
        .description("Opens the tasbih.")
    }
}
