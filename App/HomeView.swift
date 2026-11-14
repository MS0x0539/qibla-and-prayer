import SwiftUI

/// Home: the day at a glance, starting with the next prayer as the Lock Screen shows it.
struct HomeView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        NavigationStack {
            Group {
                if let place = model.place {
                    ScrollView {
                        // Moves on to the prayer after once a time has come.
                        TimelineView(.everyMinute) { context in
                            if let state = model.nextPrayerState(after: context.date, at: place) {
                                NextPrayerCard(place: place.displayName, state: state, arrived: false)
                                    // The columns as tall as each other, as on the Lock Screen.
                                    .fixedSize(horizontal: false, vertical: true)
                                    .background(Theme.background, in: RoundedRectangle(cornerRadius: 22))
                                    .overlay(RoundedRectangle(cornerRadius: 22).strokeBorder(Theme.line, lineWidth: 1))
                            }
                        }
                        .padding(.horizontal)
                        .padding(.top, 8)
                    }
                } else {
                    NoPlaceView()
                }
            }
            .background(Theme.background.ignoresSafeArea())
            .navigationTitle("Home")
        }
    }
}
