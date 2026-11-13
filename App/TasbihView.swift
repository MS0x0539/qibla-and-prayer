import SwiftUI
import WidgetKit

/// A tasbih (dhikr counter): tap the circle for each phrase, the phone taps back.
struct TasbihView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase
    // In the App Group, shared with the Tasbih widget.
    @AppStorage(TasbihStore.countKey, store: TasbihStore.defaults) private var count = 0
    @AppStorage(TasbihStore.totalKey, store: TasbihStore.defaults) private var total = 0
    @AppStorage(TasbihStore.targetKey, store: TasbihStore.defaults) private var target = 33
    /// One of Dhikr.all, the after-prayer sequence, or "" to count without a phrase.
    @AppStorage(TasbihStore.dhikrKey, store: TasbihStore.defaults) private var dhikrID = ""
    @AppStorage(TasbihStore.stepKey, store: TasbihStore.defaults) private var step = 0
    /// The count grows with the text size; it shrinks again to stay inside the circle.
    @ScaledMetric(relativeTo: .largeTitle) private var countSize: CGFloat = 88
    @State private var taps = 0
    @State private var roundDone = false
    @State private var confirmingReset = false

    private var afterPrayer: Bool { dhikrID == Dhikr.afterPrayerID }

    private var counter: TasbihCounter {
        TasbihCounter(count: count, total: total, target: target,
                      steps: afterPrayer ? Dhikr.afterPrayerCounts : [], step: step)
    }

    /// The phrase being counted, if one was picked.
    private var current: Dhikr? {
        afterPrayer ? Dhikr.afterPrayer[step % Dhikr.afterPrayer.count] : Dhikr.all.first { $0.id == dhikrID }
    }

    var body: some View {
        Group {
            // Scrolls only when it doesn't fit (large text sizes, small iPhones).
            ViewThatFits(in: .vertical) {
                content
                ScrollView { content }
                    .scrollBounceBehavior(.basedOnSize)
            }
            .foregroundStyle(Theme.ink)
            .background(Theme.background.ignoresSafeArea())
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Reset") { confirmingReset = true }
                        .disabled(total == 0)
                }
            }
            .confirmationDialog("Reset the count?", isPresented: $confirmingReset, titleVisibility: .visible) {
                Button("Reset", role: .destructive) {
                    count = 0
                    total = 0
                    step = 0
                }
                Button("Cancel", role: .cancel) {}
            }
            .sensoryFeedback(trigger: taps) { _, _ in roundDone ? .success : .impact(weight: .light) }
            .onChange(of: scenePhase) { _, phase in
                if phase == .active {
                    // Counted on the widget meanwhile.
                    let stored = TasbihStore.counter
                    if stored.count != count || stored.total != total || stored.step != step {
                        count = stored.count
                        total = stored.total
                        step = stored.step
                    }
                } else {
                    WidgetCenter.shared.reloadTimelines(ofKind: TasbihStore.widgetKind)
                }
            }
        }
    }

    private var content: some View {
        VStack(spacing: 0) {
            Text("Tasbih")
                .font(.system(.largeTitle, design: .serif).weight(.semibold))
            Picker("Dhikr", selection: $dhikrID) {
                Text("Free count").tag("")
                Text("After prayer").tag(Dhikr.afterPrayerID)
                Section {
                    ForEach(Dhikr.all) { dhikr in
                        Text(verbatim: dhikr.name).tag(dhikr.id)
                    }
                }
            }
            .pickerStyle(.menu)
            .tint(Theme.gold)
            .padding(.top, 8)
            // A new phrase starts at 0, with its usual count.
            .onChange(of: dhikrID) {
                count = 0
                step = 0
                if let dhikr = Dhikr.all.first(where: { $0.id == dhikrID }) { target = dhikr.count }
            }
            if let current {
                Text(verbatim: current.arabic)
                    .font(Quran.font(size: 36))
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .minimumScaleFactor(0.5)
                    .padding(.top, 8)
                if Quran.languageCode != "ar" && !afterPrayer {
                    Text(verbatim: current.name)
                        .font(.subheadline)
                        .foregroundStyle(Theme.muted)
                }
            }
            if afterPrayer {
                // The three phrases in order, the one being counted in full colour.
                HStack(spacing: 14) {
                    ForEach(Array(Dhikr.afterPrayer.enumerated()), id: \.offset) { index, dhikr in
                        Text(verbatim: "\(dhikr.name) \(Formats.number(Dhikr.afterPrayerCounts[index]))")
                            .fontWeight(index == step % Dhikr.afterPrayer.count ? .semibold : .regular)
                            .foregroundStyle(index == step % Dhikr.afterPrayer.count ? Theme.ink : Theme.muted)
                    }
                }
                .font(.footnote)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .accessibilityElement(children: .combine)
                .padding(.top, 6)
            } else {
                Picker("Count to", selection: $target) {
                    Text(verbatim: Formats.number(33)).tag(33)
                    Text(verbatim: Formats.number(99)).tag(99)
                    Text(verbatim: Formats.number(100)).tag(100)
                    Text("No limit").tag(0)
                }
                .pickerStyle(.segmented)
                .padding(.top, 16)
                // A count past the new target (150 with no limit, then 33) starts a fresh round.
                .onChange(of: target) { if target > 0 && count > target { count = 0 } }
            }
            Spacer(minLength: 24)
            Button(action: tap) {
                ZStack {
                    Circle()
                        .stroke(Theme.line, lineWidth: 6)
                    Circle()
                        .trim(from: 0, to: counter.goal > 0 ? min(1, Double(count) / Double(counter.goal)) : 0)
                        .stroke(Theme.gold, style: StrokeStyle(lineWidth: 6, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                    EightPointStar()
                        .stroke(Theme.gold.opacity(0.25), lineWidth: 1)
                        .padding(44)
                    Text(verbatim: Formats.number(count))
                        .font(.system(size: countSize, weight: .medium, design: .serif).monospacedDigit())
                        .foregroundStyle(Theme.ink)
                        .contentTransition(.numericText())
                        .minimumScaleFactor(0.5)
                        .lineLimit(1)
                        .padding(.horizontal, 36)
                }
                .frame(width: 280, height: 280)
                .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(current.map { Text(verbatim: $0.name) } ?? Text("Count"))
            .accessibilityValue(Text(verbatim: Formats.number(count)))
            .accessibilityHint(Text("Double-tap to count one."))
            Text("Total \(Formats.number(total))")
                .font(.subheadline.monospacedDigit())
                .foregroundStyle(Theme.muted)
                .padding(.top, 20)
            Spacer(minLength: 24)
            Text("Tap the circle for each phrase. Your iPhone taps back, and more firmly at the end of each round.")
                .font(.footnote)
                .foregroundStyle(Theme.muted)
                .multilineTextAlignment(.center)
        }
        .padding(.horizontal, 22)
        .padding(.bottom, 16)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func tap() {
        var next = counter
        roundDone = next.tap()
        withAnimation(reduceMotion ? nil : .snappy(duration: 0.15)) {
            count = next.count
            total = next.total
            step = next.step
        }
        taps += 1
    }
}
