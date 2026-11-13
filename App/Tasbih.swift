import AppIntents
import Foundation
import WidgetKit

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

/// The tasbih's count, in the App Group, so the app and its widget count the same beads.
enum TasbihStore {
    static let countKey = "tasbihCount"
    static let totalKey = "tasbihTotal"
    static let targetKey = "tasbihTarget"
    /// One of Dhikr.all, the after-prayer sequence, or "" to count without a phrase.
    static let dhikrKey = "tasbihDhikr"
    static let stepKey = "tasbihStep"
    static let widgetKind = "Tasbih"

    static var defaults: UserDefaults { SharedStore.defaults }

    static var counter: TasbihCounter {
        let stored = defaults
        let afterPrayer = stored.string(forKey: dhikrKey) == Dhikr.afterPrayerID
        return TasbihCounter(
            count: stored.integer(forKey: countKey), total: stored.integer(forKey: totalKey),
            target: stored.object(forKey: targetKey) == nil ? 33 : stored.integer(forKey: targetKey),
            steps: afterPrayer ? Dhikr.afterPrayerCounts : [], step: stored.integer(forKey: stepKey))
    }

    /// The phrase being counted, if one was picked.
    static var current: Dhikr? {
        let id = defaults.string(forKey: dhikrKey) ?? ""
        if id == Dhikr.afterPrayerID { return Dhikr.afterPrayer[counter.step % Dhikr.afterPrayer.count] }
        return Dhikr.all.first { $0.id == id }
    }

    /// Counts one, as a tap on the circle in the app does.
    static func tap() {
        var next = counter
        _ = next.tap()
        defaults.set(next.count, forKey: countKey)
        defaults.set(next.total, forKey: totalKey)
        defaults.set(next.step, forKey: stepKey)
    }

    static let keys = [countKey, totalKey, targetKey, dhikrKey, stepKey]
}

/// A tap on the tasbih widget: counts one without opening the app.
struct CountTasbihIntent: AppIntent {
    static let title: LocalizedStringResource = "Count one"
    static let isDiscoverable = false

    func perform() async throws -> some IntentResult {
        TasbihStore.tap()
        return .result()
    }
}
