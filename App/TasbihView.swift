import SwiftUI

/// A phrase to count: how it is written, how people say it, and how many times it is usually said.
struct Dhikr: Identifiable {
    let id: String
    let arabic: String
    /// The transliteration (Turkish spelling in Turkish), looked up in the app's language.
    let key: String.LocalizationValue
    let count: Int

    var name: String { String(localized: key, bundle: .app) }

    static let all = [
        Dhikr(id: "subhanAllah", arabic: "سُبْحَانَ اللَّهِ", key: "SubhanAllah", count: 33),
        Dhikr(id: "alhamdulillah", arabic: "الْحَمْدُ لِلَّهِ", key: "Alhamdulillah", count: 33),
        Dhikr(id: "allahuAkbar", arabic: "اللَّهُ أَكْبَرُ", key: "Allahu Akbar", count: 33),
        Dhikr(id: "tahlil", arabic: "لَا إِلَٰهَ إِلَّا اللَّهُ", key: "La ilaha illallah", count: 100),
        Dhikr(id: "istighfar", arabic: "أَسْتَغْفِرُ اللَّهَ", key: "Astaghfirullah", count: 100),
        Dhikr(id: "subhanAllahiWaBihamdihi", arabic: "سُبْحَانَ اللَّهِ وَبِحَمْدِهِ", key: "SubhanAllahi wa bihamdihi", count: 100),
        Dhikr(id: "hawqala", arabic: "لَا حَوْلَ وَلَا قُوَّةَ إِلَّا بِاللَّهِ", key: "La hawla wa la quwwata illa billah", count: 33),
        Dhikr(id: "salawat", arabic: "اللَّهُمَّ صَلِّ عَلَىٰ مُحَمَّدٍ", key: "Salawat", count: 33),
    ]

    /// The tasbihat after each prayer, counted in turn: 33 times SubhanAllah, 33 Alhamdulillah and 34 Allahu Akbar
    /// (Sahih Muslim 596).
    static let afterPrayerID = "afterPrayer"
    static let afterPrayer = Array(all.prefix(3))
    static let afterPrayerCounts = [33, 33, 34]
}

/// The counting behind the tasbih: rounds of 33, 99 or 100, no limit, or a sequence of phrases in turn.
struct TasbihCounter: Equatable {
    var count = 0
    var total = 0
    /// 0 means no limit.
    var target = 33
    /// The rounds of a sequence (after prayer), counted in turn; empty for a single phrase.
    var steps: [Int] = []
    var step = 0

    /// The count that completes the round now being counted.
    var goal: Int { steps.isEmpty ? target : steps[step % steps.count] }

    /// Counts one; true when that completes a round. The next tap starts the next round (the next phrase) at 1.
    mutating func tap() -> Bool {
        if goal > 0 && count >= goal {
            count = 0
            if !steps.isEmpty { step = (step + 1) % steps.count }
        }
        count += 1
        total += 1
        return goal > 0 && count == goal
    }
}

/// A tasbih (dhikr counter): tap the circle for each phrase, the phone taps back.
struct TasbihView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @AppStorage("tasbihCount") private var count = 0
    @AppStorage("tasbihTotal") private var total = 0
    @AppStorage("tasbihTarget") private var target = 33
    /// One of Dhikr.all, the after-prayer sequence, or "" to count without a phrase.
    @AppStorage("tasbihDhikr") private var dhikrID = ""
    @AppStorage("tasbihStep") private var step = 0
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
