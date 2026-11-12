import SwiftUI

/// The counting behind the tasbih: rounds of 33 or 99, or no limit.
struct TasbihCounter: Equatable {
    var count = 0
    var total = 0
    /// 0 means no limit.
    var target = 33

    /// Counts one; true when that completes a round. The next tap starts the next round at 1.
    mutating func tap() -> Bool {
        if target > 0 && count >= target { count = 0 }
        count += 1
        total += 1
        return target > 0 && count == target
    }
}

/// A tasbih (dhikr counter): tap the circle for each phrase, the phone taps back.
struct TasbihView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @AppStorage("tasbihCount") private var count = 0
    @AppStorage("tasbihTotal") private var total = 0
    @AppStorage("tasbihTarget") private var target = 33
    @State private var taps = 0
    @State private var roundDone = false
    @State private var confirmingReset = false

    var body: some View {
        NavigationStack {
            // Scrolls only when it doesn't fit (large text sizes, small iPhones).
            ViewThatFits(in: .vertical) {
                counter
                ScrollView { counter }
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
                }
                Button("Cancel", role: .cancel) {}
            }
            .sensoryFeedback(trigger: taps) { _, _ in roundDone ? .success : .impact(weight: .light) }
        }
    }

    private var counter: some View {
        VStack(spacing: 0) {
            Text("Tasbih")
                .font(.system(.largeTitle, design: .serif).weight(.semibold))
            Picker("Count to", selection: $target) {
                Text(verbatim: Formats.number(33)).tag(33)
                Text(verbatim: Formats.number(99)).tag(99)
                Text("No limit").tag(0)
            }
            .pickerStyle(.segmented)
            .padding(.top, 20)
            // A count past the new target (150 with no limit, then 33) starts a fresh round.
            .onChange(of: target) { if target > 0 && count > target { count = 0 } }
            Spacer(minLength: 24)
            Button(action: tap) {
                ZStack {
                    Circle()
                        .stroke(Theme.line, lineWidth: 6)
                    Circle()
                        .trim(from: 0, to: target > 0 ? min(1, Double(count) / Double(target)) : 0)
                        .stroke(Theme.gold, style: StrokeStyle(lineWidth: 6, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                    EightPointStar()
                        .stroke(Theme.gold.opacity(0.25), lineWidth: 1)
                        .padding(44)
                    Text(verbatim: Formats.number(count))
                        .font(.system(size: 88, weight: .medium, design: .serif).monospacedDigit())
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
            .accessibilityLabel(Text("Count"))
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
        var next = TasbihCounter(count: count, total: total, target: target)
        roundDone = next.tap()
        withAnimation(reduceMotion ? nil : .snappy(duration: 0.15)) {
            count = next.count
            total = next.total
        }
        taps += 1
    }
}
