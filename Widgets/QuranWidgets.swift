import SwiftUI
import WidgetKit

// The Qur'an on the Home Screen and the Lock Screen: a verse each day, and the page you were reading.

// The reader's paper and night pages (MushafStyle in the app).
private let paper = Color(hex: 0xFBF6E8)
private let ink = Color(hex: 0x1E1912)
private let green = Color(hex: 0x2B5A43)
private let nightGreen = Color(hex: 0x7FA88E)

/// Read in the app's language (the surah names), as the app saved it.
private func useAppLanguage() {
    if let settings = SharedStore.load(AppSettings.self, from: "settings") {
        AppLanguage.current = settings.language
    }
}

// MARK: - Verse of the day

struct VerseOfTheDayWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "VerseOfTheDay", provider: VerseProvider()) { entry in
            VerseWidgetView(entry: entry)
                .containerBackground(entry.night ? Theme.background : paper, for: .widget)
                .widgetURL(URL(string: "wajh://verse/\(entry.verse)"))
        }
        .configurationDisplayName("Verse of the day")
        .description("A verse of the Qur'an each day; a tap opens it on its page.")
        .supportedFamilies([.systemMedium, .systemLarge])
    }
}

struct VerseEntry: TimelineEntry {
    let date: Date
    /// Its index in the whole Qur'an.
    let verse: Int
    /// Dark like the reader's night page, or on paper.
    var night = QuranLook.isNight(at: .now)
}

struct VerseProvider: TimelineProvider {
    func placeholder(in context: Context) -> VerseEntry {
        VerseEntry(date: .now, verse: VerseOfTheDay.index(on: .now))
    }

    func getSnapshot(in context: Context, completion: @escaping (VerseEntry) -> Void) {
        useAppLanguage()
        completion(placeholder(in: context))
    }

    /// Today's verse in the reader's look (on Automatic again at sunrise and Isha), and the next one just after
    /// midnight.
    func getTimeline(in context: Context, completion: @escaping (Timeline<VerseEntry>) -> Void) {
        useAppLanguage()
        let now = Date.now
        let calendar = Calendar.current
        let tomorrow = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: now)) ?? now.addingTimeInterval(86_400)
        let entries = ([now] + QuranLook.changes(after: now, before: tomorrow)).map {
            VerseEntry(date: $0, verse: VerseOfTheDay.index(on: $0), night: QuranLook.isNight(at: $0))
        }
        completion(Timeline(entries: entries, policy: .after(tomorrow.addingTimeInterval(60))))
    }
}

struct VerseWidgetView: View {
    let entry: VerseEntry

    var body: some View {
        let quran = Quran.shared
        if quran.verses.indices.contains(entry.verse) {
            let verse = quran.verses[entry.verse]
            VStack(spacing: 8) {
                Text(verbatim: verse.text + " \u{06DD}" + Quran.arabicDigits(verse.number))
                    .font(Quran.font(size: 22))
                    .foregroundStyle(entry.night ? Theme.ink : ink)
                    .multilineTextAlignment(.center)
                    .minimumScaleFactor(0.4)
                    .environment(\.layoutDirection, .rightToLeft)
                Text(verbatim: "\(Quran.title(of: quran.surahs[verse.surah - 1])) \(verse.surah):\(verse.number)")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(entry.night ? nightGreen : green)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}

// MARK: - Continue reading

struct ContinueReadingWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "ContinueReading", provider: ReadingProvider()) { entry in
            ReadingWidgetView(entry: entry)
                .containerBackground(Theme.background, for: .widget)
                .widgetURL(URL(string: "wajh://page/\(entry.page)"))
        }
        .configurationDisplayName("Continue reading")
        .description("The page you were reading and your khatm; a tap opens the Qur'an there.")
        .supportedFamilies([.systemSmall, .accessoryCircular])
    }
}

struct ReadingEntry: TimelineEntry {
    let date: Date
    let page: Int
    /// Pages read in the current khatm.
    let read: Int
}

struct ReadingProvider: TimelineProvider {
    func placeholder(in context: Context) -> ReadingEntry {
        ReadingEntry(date: .now, page: 42, read: 42)
    }

    func getSnapshot(in context: Context, completion: @escaping (ReadingEntry) -> Void) {
        completion(entry())
    }

    /// Redrawn when the app goes to the background after reading.
    func getTimeline(in context: Context, completion: @escaping (Timeline<ReadingEntry>) -> Void) {
        completion(Timeline(entries: [entry()], policy: .never))
    }

    private func entry() -> ReadingEntry {
        useAppLanguage()
        let stored = SharedStore.defaults
        let page = min(max(stored.integer(forKey: "quranPage"), 1), Quran.pageCount)
        let read = QuranProgress.pages(stored.string(forKey: QuranProgress.khatmPagesKey) ?? "").count
        return ReadingEntry(date: .now, page: page, read: read)
    }
}

struct ReadingWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: ReadingEntry

    var body: some View {
        let quran = Quran.shared
        let surah = quran.verses(onPage: entry.page).first.map { quran.surahs[$0.surah - 1] }
        let progress = Double(entry.read) / Double(Quran.pageCount)
        if family == .accessoryCircular {
            Gauge(value: progress) {
                Image(systemName: "book")
            } currentValueLabel: {
                Text(verbatim: Formats.number(entry.page))
            }
            .gaugeStyle(.accessoryCircular)
            .accessibilityLabel(Text("Continue reading"))
            .accessibilityValue(Text("Page \(entry.page)"))
        } else {
            VStack(alignment: .leading, spacing: 4) {
                Label("Continue reading", systemImage: "book")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Theme.gold)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                Spacer(minLength: 0)
                if let surah {
                    Text(verbatim: Quran.title(of: surah))
                        .font(.system(.title3, design: .serif).weight(.medium))
                        .foregroundStyle(Theme.ink)
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                }
                Text("Page \(entry.page)")
                    .font(.subheadline.monospacedDigit())
                    .foregroundStyle(Theme.muted)
                ProgressView(value: progress)
                    .tint(Theme.gold)
                    .accessibilityHidden(true)
                Text(verbatim: "\(Formats.number(entry.read)) / \(Formats.number(Quran.pageCount))")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(Theme.muted)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        }
    }
}
