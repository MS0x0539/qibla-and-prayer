import Foundation
import Testing
@testable import QiblaAndPrayer

struct QuranTests {
    let quran = Quran.shared

    /// Night unless Paper is picked; Automatic needs a saved place, so it is checked in the app.
    @Test func lookIsNightByDefault() {
        let defaults = UserDefaults(suiteName: "QuranLookTests")!
        defaults.removePersistentDomain(forName: "QuranLookTests")
        #expect(QuranLook.isNight(at: .now, defaults: defaults))
        defaults.set(false, forKey: QuranLook.nightKey)
        #expect(!QuranLook.isNight(at: .now, defaults: defaults))
        defaults.set(true, forKey: QuranLook.nightKey)
        #expect(QuranLook.isNight(at: .now, defaults: defaults))
        #expect(QuranLook.changes(after: .now, before: .distantFuture, defaults: defaults).isEmpty)
    }

    @Test func wholeTextLoads() {
        #expect(quran.surahs.count == 114)
        #expect(quran.verses.count == 6236)
        #expect(quran.pageStarts.count == 604)
        #expect(quran.juzStarts.count == 30)
        #expect(quran.verses.last.map { "\($0.surah):\($0.number)" } == "114:6")
        // Every surah's verses are numbered 1...n in order.
        for surah in quran.surahs {
            #expect(quran.verses[surah.start].surah == surah.n && quran.verses[surah.start].number == 1)
            #expect(quran.verses[surah.start + surah.ayahs - 1].number == surah.ayahs)
        }
    }

    /// Where well-known verses are in the printed Madinah mushaf.
    @Test func madinahPages() {
        #expect(quran.page(ofVerse: quran.index(surah: 2, verse: 255)) == 42)
        #expect(quran.page(ofVerse: quran.index(surah: 18, verse: 1)) == 293)
        #expect(quran.page(ofVerse: quran.index(surah: 36, verse: 1)) == 440)
        #expect(quran.page(ofVerse: quran.index(surah: 67, verse: 1)) == 562)
        #expect(quran.page(ofVerse: quran.index(surah: 114, verse: 6)) == 604)
        #expect(quran.verses(onPage: 1).count == 7)
        #expect(quran.verses(onPage: 604).first.map { "\($0.surah):\($0.number)" } == "112:1")
        #expect(quran.juz(ofVerse: quran.index(surah: 2, verse: 142)) == 2)
        #expect(quran.juz(ofVerse: quran.index(surah: 78, verse: 1)) == 30)
    }

    @Test func duasAreWhereTheySay() {
        for dua in QuranDua.all {
            let surah = quran.surahs[dua.surah - 1]
            #expect(dua.from >= 1 && dua.from <= dua.to && dua.to <= surah.ayahs, "\(dua.title)")
            guard dua.title.hasPrefix("Rabbana") else { continue }
            let text = (dua.from...dua.to)
                .map { Quran.plainArabic(quran.verses[quran.index(surah: dua.surah, verse: $0)].text) }
                .joined(separator: " ")
            #expect(text.contains("ربنا"), "\(dua.title)")
        }
    }

    @Test func search() {
        #expect(quran.search("36").surahs.map(\.n) == [36])
        #expect(quran.search("yasin").surahs.map(\.n) == [36])
        #expect(quran.search("Bakara").surahs.map(\.n) == [2])
        #expect(quran.search("De Koe").surahs.map(\.n) == [2])
        #expect(quran.search("البقرة").surahs.map(\.n) == [2])
        #expect(quran.search("Rabbena atina").duas.contains { $0.surah == 2 && $0.from == 201 })
        // Arabic words in today's spelling find the Uthmani verses.
        #expect(quran.search("وسع كرسيه").verses.contains { $0.surah == 2 && $0.number == 255 })
        #expect(quran.search("الصلاة").verses.count > 10)
        #expect(quran.search("   ").isEmpty)
    }

    @Test func arabicDigits() {
        #expect(Quran.arabicDigits(604) == "٦٠٤")
    }

    @Test func automaticOnlyForNewSettings() throws {
        #expect(AppSettings.suggested().automaticMethod && AppSettings.suggested().automaticAsr)
        // Settings saved before "Automatic" keep the method that was picked.
        let old = try JSONDecoder().decode(AppSettings.self, from: Data(#"{"method":"turkey","asr":"standard"}"#.utf8))
        #expect(old.method == .turkey)
        #expect(!old.automaticMethod && !old.automaticAsr)
    }
}
