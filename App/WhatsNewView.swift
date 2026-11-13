import SwiftUI

/// Shown once after updating, to people who used the app before: what this version adds.
struct WhatsNewView: View {
    static let version = "1.1"
    static let seenKey = "whatsNewSeen"

    let close: () -> Void

    private struct Item: Identifiable {
        let symbol: String
        let title: LocalizedStringKey
        let text: LocalizedStringKey
        var id: String { symbol }
    }

    private let items = [
        Item(symbol: "book", title: "The Qur'an",
             text: "The whole mushaf, turned like paper, with recitation by ten reciters you can also download."),
        Item(symbol: "circle.dotted", title: "Ibadah",
             text: "The tasbih with the tasbihat after prayer, and the tracker with your khatm."),
        Item(symbol: "location.circle", title: "Automatic",
             text: "Times as the mosques in your country calculate them, also when you travel."),
        Item(symbol: "rectangle.stack", title: "Widgets",
             text: "The next prayer and today's times, a tasbih, the verse of the day and the page you were reading."),
        Item(symbol: "lock.iphone", title: "Lock Screen",
             text: "The next prayer with a countdown, and Qibla and Tasbih in Control Center."),
    ]

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 26) {
                    VStack(spacing: 10) {
                        EightPointStar()
                            .stroke(Theme.gold, lineWidth: 1.5)
                            .frame(width: 40, height: 40)
                            .accessibilityHidden(true)
                        Text("New in this version")
                            .font(.system(.largeTitle, design: .serif).weight(.semibold))
                            .multilineTextAlignment(.center)
                            .accessibilityAddTraits(.isHeader)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.top, 40)
                    ForEach(items) { item in
                        HStack(alignment: .top, spacing: 16) {
                            Image(systemName: item.symbol)
                                .font(.title2)
                                .foregroundStyle(Theme.gold)
                                .frame(width: 36)
                                .accessibilityHidden(true)
                            VStack(alignment: .leading, spacing: 3) {
                                Text(item.title)
                                    .font(.headline)
                                Text(item.text)
                                    .foregroundStyle(Theme.muted)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                        .accessibilityElement(children: .combine)
                    }
                }
                .padding(.horizontal, 28)
            }
            Button(action: close) {
                Text("Continue")
                    .font(.headline)
                    .foregroundStyle(Theme.background)
                    .frame(maxWidth: .infinity, minHeight: 52)
                    .background(Theme.gold, in: RoundedRectangle(cornerRadius: 14))
            }
            .padding(24)
        }
        .foregroundStyle(Theme.ink)
        .background(Theme.background.ignoresSafeArea())
    }
}
