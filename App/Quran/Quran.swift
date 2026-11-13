import CoreText
import Foundation
import SwiftUI
import UIKit

/// The Qur'an in Arabic: Tanzil's Uthmani text (tanzil.net, kept verbatim as its terms ask) with its metadata,
/// laid out on the 604 pages of the Madinah mushaf. Tanzil's simple text, without diacritics, is used for search.
final class Quran {
    struct Surah: Identifiable, Decodable {
        let n: Int
        let ayahs: Int
        /// Index of its first verse in `verses`.
        let start: Int
        let name: String
        let tname: String
        let ename: String
        let type: String
        var id: Int { n }
        var isMeccan: Bool { type == "Meccan" }
    }

    struct Verse: Identifiable {
        /// Position in the whole Qur'an, 0...6235.
        let index: Int
        let surah: Int
        let number: Int
        let text: String
        var id: Int { index }
    }

    private struct Metadata: Decodable {
        let surahs: [Surah]
        let pages: [[Int]]
        let juz: [[Int]]
        let quarters: [[Int]]
        let sajdas: [[Int]]
    }

    static let shared = Quran()
    static let pageCount = 604
    static let fontName = "AmiriQuran-Regular"

    let surahs: [Surah]
    let verses: [Verse]
    /// Index of the first verse of each page (604) and each juz (30).
    let pageStarts: [Int]
    let juzStarts: [Int]
    /// The quarter of a hizb (0...239) each such verse begins (the ۞ in the text): hizb q / 4 + 1, q % 4 quarters in.
    let quarters: [Int: Int]
    /// Verses of prostration (the ۩ in the text).
    let sajdas: Set<Int>

    private init() {
        guard let metaURL = Bundle.main.url(forResource: "quran-meta", withExtension: "json"),
              let textURL = Bundle.main.url(forResource: "quran-uthmani", withExtension: "txt"),
              let metaData = try? Data(contentsOf: metaURL),
              let meta = try? JSONDecoder().decode(Metadata.self, from: metaData),
              let text = try? String(contentsOf: textURL, encoding: .utf8)
        else {
            surahs = []
            verses = []
            pageStarts = []
            juzStarts = []
            quarters = [:]
            sajdas = []
            return
        }
        surahs = meta.surahs
        verses = Quran.parse(text).enumerated().map { index, line in
            Verse(index: index, surah: line.surah, number: line.number, text: line.text)
        }
        let start = { (pair: [Int]) in meta.surahs[pair[0] - 1].start + pair[1] - 1 }
        pageStarts = meta.pages.map(start)
        juzStarts = meta.juz.map(start)
        quarters = Dictionary(uniqueKeysWithValues: meta.quarters.map(start).enumerated().map { ($1, $0) })
        sajdas = Set(meta.sajdas.map(start))
    }

    /// Tanzil's "surah|verse|text" lines; its copyright block (lines starting with #) is skipped.
    private static func parse(_ text: String) -> [(surah: Int, number: Int, text: String)] {
        text.split(separator: "\n").compactMap { line in
            guard !line.hasPrefix("#") else { return nil }
            let parts = line.split(separator: "|", maxSplits: 2, omittingEmptySubsequences: false)
            guard parts.count == 3, let surah = Int(parts[0]), let number = Int(parts[1]) else { return nil }
            return (surah, number, String(parts[2]))
        }
    }

    // MARK: - Pages

    func index(surah: Int, verse: Int) -> Int { surahs[surah - 1].start + verse - 1 }

    /// The mushaf page (1...604) a verse is on.
    func page(ofVerse index: Int) -> Int { Quran.last(in: pageStarts, atOrBefore: index) + 1 }

    /// The juz (1...30) a verse is in.
    func juz(ofVerse index: Int) -> Int { Quran.last(in: juzStarts, atOrBefore: index) + 1 }

    func verses(onPage page: Int) -> ArraySlice<Verse> {
        guard (1...pageStarts.count).contains(page) else { return [] }
        let end = page < pageStarts.count ? pageStarts[page] : verses.count
        return verses[pageStarts[page - 1]..<end]
    }

    /// The position of the last start at or before `index` (binary search).
    private static func last(in starts: [Int], atOrBefore index: Int) -> Int {
        var low = 0
        var high = starts.count - 1
        while low < high {
            let middle = (low + high + 1) / 2
            if starts[middle] <= index { low = middle } else { high = middle - 1 }
        }
        return low
    }

    // MARK: - Search

    struct Results {
        var surahs: [Surah] = []
        var duas: [QuranDua] = []
        var verses: [Verse] = []
        var isEmpty: Bool { surahs.isEmpty && duas.isEmpty && verses.isEmpty }
    }

    /// Surahs by number or by name (Arabic, Tanzil's transliteration, English or Turkish, spelled loosely); du'as by
    /// title or Arabic words; verses by Arabic words, without diacritics.
    func search(_ query: String) -> Results {
        let query = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return Results() }
        var results = Results()
        if let number = Int(query), (1...surahs.count).contains(number) {
            results.surahs = [surahs[number - 1]]
            return results
        }
        if query.unicodeScalars.contains(where: { (0x0600...0x06FF).contains($0.value) }) {
            let words = Quran.plainArabic(query)
            guard words.count >= 2 else { return results }
            let bare = words.hasPrefix("سوره ") ? String(words.dropFirst(5)) : words
            results.surahs = surahs.filter { Quran.plainArabic($0.name).contains(bare) }
            let plain = plainVerses
            results.duas = QuranDua.all.filter { dua in
                (dua.from...dua.to).contains { plain[index(surah: dua.surah, verse: $0)].contains(words) }
            }
            results.verses = verses.filter { plain[$0.index].contains(words) }.prefix(100).map { $0 }
        } else {
            // A spelling found as typed wins; only without one do loose spellings count ("Rabbena" for "Rabbana").
            let latin = Quran.plainLatin(query)
            let skeleton = Quran.skeleton(query)
            let exact = { (names: [String]) in names.contains { Quran.plainLatin($0).contains(latin) } }
            let loose = { (names: [String]) in skeleton.count >= 2 && names.contains { Quran.skeleton($0).contains(skeleton) } }
            let names = { (surah: Surah) in Quran.searchNames(of: surah) }
            results.surahs = surahs.filter { exact(names($0)) }
            if results.surahs.isEmpty { results.surahs = surahs.filter { loose(names($0)) } }
            results.duas = QuranDua.all.filter { exact([$0.title]) }
            if results.duas.isEmpty { results.duas = QuranDua.all.filter { loose([$0.title]) } }
        }
        return results
    }

    /// Tanzil's simple text without diacritics, normalised like the query: loaded at the first Arabic search.
    private lazy var plainVerses: [String] = {
        guard let url = Bundle.main.url(forResource: "quran-simple-clean", withExtension: "txt"),
              let text = try? String(contentsOf: url, encoding: .utf8) else { return verses.map { Quran.plainArabic($0.text) } }
        let lines = Quran.parse(text).map { Quran.plainArabic($0.text) }
        return lines.count == verses.count ? lines : verses.map { Quran.plainArabic($0.text) }
    }()

    /// Arabic without diacritics, Qur'anic marks or tatweel, with the forms of alef, ya and ta marbuta as one.
    static func plainArabic(_ text: String) -> String {
        var scalars = String.UnicodeScalarView()
        for scalar in text.unicodeScalars {
            switch scalar.value {
            case 0x064B...0x065F, 0x0670, 0x06D6...0x06ED, 0x0640: continue
            case 0x0622, 0x0623, 0x0625, 0x0671: scalars.append("ا")
            case 0x0649: scalars.append("ي")
            case 0x0629: scalars.append("ه")
            default: scalars.append(scalar)
            }
        }
        return String(scalars).split(separator: " ").joined(separator: " ")
    }

    /// Lower case, without accents or apostrophes: "Âl-i İmrân" and "al imran" compare equal.
    static func plainLatin(_ text: String) -> String {
        text.replacingOccurrences(of: "ı", with: "i").replacingOccurrences(of: "İ", with: "i")
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "en_US_POSIX"))
            .filter { $0.isLetter || $0.isNumber }
    }

    /// Only the consonants, doubled ones once, q as k and w as v: so "Rabbana", "Rabbenâ" and "Rabana",
    /// or "Baqara" and "Bakara", match.
    static func skeleton(_ text: String) -> String {
        var out = ""
        for character in plainLatin(text) {
            let mapped: Character = character == "q" ? "k" : character == "w" ? "v" : character
            guard !"aeiouy".contains(mapped), mapped != out.last else { continue }
            out.append(mapped)
        }
        return out
    }

    // MARK: - Display

    private static let fontRegistered: Bool = {
        guard let url = Bundle.main.url(forResource: "AmiriQuran", withExtension: "ttf") else { return false }
        return CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil)
    }()

    /// The Amiri Quran font, growing with the text size set on the iPhone.
    /// Scaled with the text size: the one in effect, or the one a view is being drawn for.
    static func uiFont(size: CGFloat, typeSize: DynamicTypeSize? = nil) -> UIFont {
        _ = fontRegistered
        let base = UIFont(name: fontName, size: size) ?? .systemFont(ofSize: size)
        guard let typeSize else { return UIFontMetrics(forTextStyle: .body).scaledFont(for: base) }
        let traits = UITraitCollection(preferredContentSizeCategory: UIContentSizeCategory(typeSize))
        return UIFontMetrics(forTextStyle: .body).scaledFont(for: base, compatibleWith: traits)
    }

    static func font(size: CGFloat) -> Font {
        _ = fontRegistered
        return .custom(fontName, size: size, relativeTo: .body)
    }

    /// A number in Arabic-Indic digits (٤٢), as printed in the mushaf.
    static func arabicDigits(_ number: Int) -> String {
        String(String(number).compactMap { digit in
            digit.wholeNumberValue.flatMap { UnicodeScalar(0x0660 + $0) }.map(Character.init)
        })
    }

    /// The app's language: the one picked in the app, or the one iOS chose for it.
    static var languageCode: String { AppLanguage.code }

    /// The surah's name as people know it in the app's language: Diyanet's spelling in Turkish, the Arabic name in
    /// Arabic, Tanzil's transliteration otherwise.
    static func title(of surah: Surah) -> String {
        switch languageCode {
        case "tr": turkishNames[surah.n - 1].components(separatedBy: " / ").first ?? surah.tname
        case "ar": surah.name
        default: surah.tname
        }
    }

    /// What the name means, in English, Dutch, German or French; nil in Turkish and Arabic, whose names say it.
    static func meaning(of surah: Surah) -> String? {
        switch languageCode {
        case "nl": dutchNames[surah.n - 1]
        case "de": germanNames[surah.n - 1]
        case "fr": frenchNames[surah.n - 1]
        case "tr", "ar": nil
        default: surah.ename
        }
    }

    /// Every name a surah goes by, for search.
    static func searchNames(of surah: Surah) -> [String] {
        [surah.tname, surah.ename, turkishNames[surah.n - 1], dutchNames[surah.n - 1], germanNames[surah.n - 1],
         frenchNames[surah.n - 1]]
    }

    static let dutchNames = [
        "De Opening", "De Koe", "De Familie van Imran", "De Vrouwen", "De Tafel", "Het Vee", "De Hoogten", "De Buit",
        "Het Berouw", "Jonas", "Hud", "Jozef", "De Donder", "Abraham", "De Rots", "De Bij", "De Nachtreis", "De Grot",
        "Maria", "Ta Ha", "De Profeten", "De Bedevaart", "De Gelovigen", "Het Licht", "Het Onderscheid", "De Dichters",
        "De Mier", "De Verhalen", "De Spin", "De Romeinen", "Loeqman", "De Neerknieling", "De Bondgenoten", "Saba",
        "De Schepper", "Ya Sin", "De Rijen", "Sad", "De Groepen", "De Vergever", "Duidelijk Uitgelegd", "Het Overleg",
        "De Pracht", "De Rook", "De Knielende", "De Duinen", "Mohammed", "De Overwinning", "De Vertrekken", "Qaf",
        "De Verstrooiende Winden", "De Berg", "De Ster", "De Maan", "De Barmhartige", "Het Onvermijdelijke", "Het IJzer",
        "De Pleitende Vrouw", "De Verbanning", "De Beproefde", "De Rij", "Vrijdag", "De Huichelaars", "Het Wederzijds Verlies",
        "De Echtscheiding", "Het Verbod", "De Heerschappij", "De Pen", "De Werkelijkheid", "De Opgangen", "Noach", "De Djinn",
        "De Ingewikkelde", "De Bedekte", "De Opstanding", "De Mens", "De Gezondenen", "Het Bericht", "De Wegrukkers",
        "Hij Fronste", "Het Oprollen", "Het Splijten", "De Bedriegers", "Het Openbarsten", "De Sterrenbeelden", "De Nachtster",
        "De Allerhoogste", "Het Overweldigende", "De Dageraad", "De Stad", "De Zon", "De Nacht", "De Ochtend", "De Verruiming",
        "De Vijg", "Het Stolsel", "De Beschikking", "Het Duidelijke Bewijs", "De Aardbeving", "De Renpaarden", "De Rampspoed",
        "De Wedijver", "De Tijd", "De Lasteraar", "De Olifant", "Qoeraisj", "De Kleine Hulp", "De Overvloed", "De Ongelovigen",
        "De Hulp", "De Palmvezel", "De Oprechtheid", "Het Ochtendgloren", "De Mensen",
    ]

    static let germanNames = [
        "Die Eröffnung", "Die Kuh", "Die Sippe Imrans", "Die Frauen", "Der Tisch", "Das Vieh", "Die Höhen", "Die Beute",
        "Die Reue", "Jonas", "Hud", "Josef", "Der Donner", "Abraham", "Der Fels", "Die Biene", "Die Nachtreise", "Die Höhle",
        "Maria", "Ta Ha", "Die Propheten", "Die Pilgerfahrt", "Die Gläubigen", "Das Licht", "Die Unterscheidung", "Die Dichter",
        "Die Ameisen", "Die Geschichte", "Die Spinne", "Die Römer", "Luqman", "Die Niederwerfung", "Die Verbündeten", "Saba",
        "Der Erschaffer", "Ya Sin", "Die sich Reihenden", "Sad", "Die Scharen", "Der Vergebende", "Ausführlich dargelegt",
        "Die Beratung", "Der Prunk", "Der Rauch", "Die Kniende", "Die Dünen", "Muhammad", "Der Sieg", "Die Gemächer", "Qaf",
        "Die Aufwirbelnden", "Der Berg", "Der Stern", "Der Mond", "Der Allerbarmer", "Das Eintreffende", "Das Eisen",
        "Die Streitende", "Die Versammlung", "Die Geprüfte", "Die Reihe", "Der Freitag", "Die Heuchler", "Die Übervorteilung",
        "Die Scheidung", "Das Verbot", "Die Herrschaft", "Das Schreibrohr", "Die fällig Werdende", "Die Aufstiegswege", "Noah",
        "Die Dschinn", "Der Eingehüllte", "Der Zugedeckte", "Die Auferstehung", "Der Mensch", "Die Entsandten", "Die Kunde",
        "Die Entreißenden", "Er runzelte die Stirn", "Das Einrollen", "Das Zerbrechen", "Die das Maß Verkürzenden",
        "Das Zerreißen", "Die Türme", "Der Pochende", "Der Allerhöchste", "Die Bedeckende", "Die Morgendämmerung", "Die Stadt",
        "Die Sonne", "Die Nacht", "Der Vormittag", "Das Weiten", "Die Feige", "Der Embryo", "Die Bestimmung",
        "Der klare Beweis", "Das Beben", "Die Rennenden", "Das Pochende", "Die Vermehrung", "Die Zeit", "Der Verleumder",
        "Der Elefant", "Quraisch", "Die Hilfeleistung", "Der Überfluss", "Die Ungläubigen", "Die Hilfe", "Die Palmfaser",
        "Die Aufrichtigkeit", "Das Frühlicht", "Die Menschen",
    ]

    static let frenchNames = [
        "L’Ouverture", "La Vache", "La Famille d’Imran", "Les Femmes", "La Table servie", "Les Bestiaux", "Les Murailles",
        "Le Butin", "Le Repentir", "Jonas", "Houd", "Joseph", "Le Tonnerre", "Abraham", "Al-Hijr", "Les Abeilles",
        "Le Voyage nocturne", "La Caverne", "Marie", "Ta Ha", "Les Prophètes", "Le Pèlerinage", "Les Croyants", "La Lumière",
        "Le Discernement", "Les Poètes", "Les Fourmis", "Le Récit", "L’Araignée", "Les Romains", "Luqman", "La Prosternation",
        "Les Coalisés", "Saba", "Le Créateur", "Ya Sin", "Les Rangés", "Sad", "Les Groupes", "Le Pardonneur",
        "Les Versets détaillés", "La Consultation", "L’Ornement", "La Fumée", "L’Agenouillée", "Al-Ahqaf", "Muhammad",
        "La Victoire éclatante", "Les Appartements", "Qaf", "Qui éparpillent", "At-Tur", "L’Étoile", "La Lune",
        "Le Tout Miséricordieux", "L’Événement", "Le Fer", "La Discussion", "L’Exode", "L’Éprouvée", "Le Rang", "Le Vendredi",
        "Les Hypocrites", "La Grande Perte", "Le Divorce", "L’Interdiction", "La Royauté", "La Plume", "La Réalité",
        "Les Voies d’ascension", "Noé", "Les Djinns", "L’Enveloppé", "Le Revêtu d’un manteau", "La Résurrection", "L’Homme",
        "Les Envoyés", "La Nouvelle", "Ceux qui arrachent", "Il s’est renfrogné", "L’Obscurcissement", "La Rupture",
        "Les Fraudeurs", "La Déchirure", "Les Constellations", "L’Astre nocturne", "Le Très-Haut", "L’Enveloppante", "L’Aube",
        "La Cité", "Le Soleil", "La Nuit", "Le Jour montant", "La Dilatation", "Le Figuier", "L’Adhérence", "La Destinée",
        "La Preuve", "La Secousse", "Les Coursiers", "Le Fracas", "La Course aux richesses", "Le Temps", "Les Calomniateurs",
        "L’Éléphant", "Quraych", "L’Ustensile", "L’Abondance", "Les Infidèles", "Le Secours", "Les Fibres",
        "Le Monothéisme pur", "L’Aube naissante", "Les Hommes",
    ]

    /// The surah names used in Turkey (Diyanet's spelling; other common names after " / ").
    static let turkishNames = [
        "Fâtiha", "Bakara", "Âl-i İmrân", "Nisâ", "Mâide", "En'âm", "A'râf", "Enfâl", "Tevbe", "Yûnus",
        "Hûd", "Yûsuf", "Ra'd", "İbrâhîm", "Hicr", "Nahl", "İsrâ / Benî İsrâil", "Kehf", "Meryem", "Tâhâ",
        "Enbiyâ", "Hac", "Mü'minûn", "Nûr", "Furkân", "Şuarâ", "Neml", "Kasas", "Ankebût", "Rûm",
        "Lokmân", "Secde", "Ahzâb", "Sebe'", "Fâtır", "Yâsîn", "Sâffât", "Sâd", "Zümer", "Mü'min / Ğâfir",
        "Fussilet", "Şûrâ", "Zuhruf", "Duhân", "Câsiye", "Ahkâf", "Muhammed", "Fetih", "Hucurât", "Kâf",
        "Zâriyât", "Tûr", "Necm", "Kamer", "Rahmân", "Vâkıa", "Hadîd", "Mücâdele", "Haşr", "Mümtehine",
        "Saf", "Cuma", "Münâfikûn", "Teğâbün", "Talâk", "Tahrîm", "Mülk", "Kalem", "Hâkka", "Meâric",
        "Nûh", "Cin", "Müzzemmil", "Müddessir", "Kıyâme", "İnsân / Dehr", "Mürselât", "Nebe'", "Nâziât", "Abese",
        "Tekvîr", "İnfitâr", "Mutaffifîn", "İnşikâk", "Bürûc", "Târık", "A'lâ", "Gâşiye", "Fecr", "Beled",
        "Şems", "Leyl", "Duhâ", "İnşirâh / Şerh", "Tîn", "Alak", "Kadir", "Beyyine", "Zilzâl", "Âdiyât",
        "Kâria", "Tekâsür", "Asr", "Hümeze", "Fîl", "Kureyş", "Mâûn", "Kevser", "Kâfirûn", "Nasr",
        "Tebbet / Mesed", "İhlâs", "Felak", "Nâs",
    ]
}

/// A du'a from the Qur'an: where it is and the opening words as they are usually said. The Arabic is the verse itself.
struct QuranDua: Identifiable {
    let surah: Int
    let from: Int
    let to: Int
    let title: String
    var id: String { "\(surah):\(from)" }

    /// The du'as of the Qur'an: the "Rabbana" du'as and those of the prophets, each checked against the text.
    static let all: [QuranDua] = [
        QuranDua(surah: 1, from: 1, to: 7, title: "Al-Fatiha"),
        QuranDua(surah: 2, from: 127, to: 127, title: "Rabbana taqabbal minna"),
        QuranDua(surah: 2, from: 128, to: 128, title: "Rabbana waj'alna muslimayni laka"),
        QuranDua(surah: 2, from: 201, to: 201, title: "Rabbana atina fid-dunya hasanah"),
        QuranDua(surah: 2, from: 250, to: 250, title: "Rabbana afrigh 'alayna sabran"),
        QuranDua(surah: 2, from: 286, to: 286, title: "Rabbana la tu'akhidhna"),
        QuranDua(surah: 3, from: 8, to: 8, title: "Rabbana la tuzigh qulubana"),
        QuranDua(surah: 3, from: 9, to: 9, title: "Rabbana innaka jami'un-nas"),
        QuranDua(surah: 3, from: 16, to: 16, title: "Rabbana innana amanna"),
        QuranDua(surah: 3, from: 53, to: 53, title: "Rabbana amanna bima anzalta"),
        QuranDua(surah: 3, from: 147, to: 147, title: "Rabbanaghfir lana dhunubana"),
        QuranDua(surah: 3, from: 191, to: 194, title: "Rabbana ma khalaqta hadha batila"),
        QuranDua(surah: 4, from: 75, to: 75, title: "Rabbana akhrijna min hadhihil-qarya"),
        QuranDua(surah: 5, from: 83, to: 83, title: "Rabbana amanna faktubna ma'ash-shahidin"),
        QuranDua(surah: 5, from: 114, to: 114, title: "Allahumma Rabbana anzil 'alayna ma'idah"),
        QuranDua(surah: 7, from: 23, to: 23, title: "Rabbana zalamna anfusana"),
        QuranDua(surah: 7, from: 47, to: 47, title: "Rabbana la taj'alna ma'al-qawmiz-zalimin"),
        QuranDua(surah: 7, from: 89, to: 89, title: "Rabbanaftah baynana"),
        QuranDua(surah: 7, from: 126, to: 126, title: "Rabbana afrigh 'alayna sabran wa tawaffana muslimin"),
        QuranDua(surah: 10, from: 85, to: 86, title: "Rabbana la taj'alna fitnatan"),
        QuranDua(surah: 14, from: 38, to: 38, title: "Rabbana innaka ta'lamu ma nukhfi"),
        QuranDua(surah: 14, from: 40, to: 41, title: "Rabbij'alni muqimas-salah"),
        QuranDua(surah: 18, from: 10, to: 10, title: "Rabbana atina min ladunka rahmah"),
        QuranDua(surah: 20, from: 45, to: 45, title: "Rabbana innana nakhafu"),
        QuranDua(surah: 23, from: 109, to: 109, title: "Rabbana amanna faghfir lana warhamna"),
        QuranDua(surah: 25, from: 65, to: 66, title: "Rabbanasrif 'anna 'adhaba jahannam"),
        QuranDua(surah: 25, from: 74, to: 74, title: "Rabbana hab lana min azwajina"),
        QuranDua(surah: 40, from: 7, to: 9, title: "Rabbana wasi'ta kulla shay'in rahmatan"),
        QuranDua(surah: 59, from: 10, to: 10, title: "Rabbanaghfir lana wa li-ikhwanina"),
        QuranDua(surah: 60, from: 4, to: 5, title: "Rabbana 'alayka tawakkalna"),
        QuranDua(surah: 66, from: 8, to: 8, title: "Rabbana atmim lana nurana"),
        QuranDua(surah: 2, from: 126, to: 126, title: "Rabbij'al hadha baladan amina"),
        QuranDua(surah: 3, from: 38, to: 38, title: "Rabbi hab li min ladunka dhurriyyatan tayyibah"),
        QuranDua(surah: 7, from: 151, to: 151, title: "Rabbighfir li wa li-akhi"),
        QuranDua(surah: 11, from: 47, to: 47, title: "Rabbi inni a'udhu bika"),
        QuranDua(surah: 12, from: 101, to: 101, title: "Fatiras-samawati wal-ard"),
        QuranDua(surah: 17, from: 24, to: 24, title: "Rabbirhamhuma kama rabbayani saghira"),
        QuranDua(surah: 17, from: 80, to: 80, title: "Rabbi adkhilni mudkhala sidq"),
        QuranDua(surah: 20, from: 25, to: 28, title: "Rabbishrah li sadri"),
        QuranDua(surah: 20, from: 114, to: 114, title: "Rabbi zidni 'ilma"),
        QuranDua(surah: 21, from: 83, to: 83, title: "Anni massaniyad-durr"),
        QuranDua(surah: 21, from: 87, to: 87, title: "La ilaha illa anta subhanaka"),
        QuranDua(surah: 21, from: 89, to: 89, title: "Rabbi la tadharni fardan"),
        QuranDua(surah: 23, from: 29, to: 29, title: "Rabbi anzilni munzalan mubaraka"),
        QuranDua(surah: 23, from: 97, to: 98, title: "Rabbi a'udhu bika min hamazatish-shayatin"),
        QuranDua(surah: 23, from: 118, to: 118, title: "Rabbighfir warham"),
        QuranDua(surah: 26, from: 83, to: 85, title: "Rabbi hab li hukman"),
        QuranDua(surah: 27, from: 19, to: 19, title: "Rabbi awzi'ni an ashkura ni'mataka"),
        QuranDua(surah: 28, from: 16, to: 16, title: "Rabbi inni zalamtu nafsi"),
        QuranDua(surah: 28, from: 24, to: 24, title: "Rabbi inni lima anzalta ilayya min khayrin faqir"),
        QuranDua(surah: 37, from: 100, to: 100, title: "Rabbi hab li minas-salihin"),
        QuranDua(surah: 46, from: 15, to: 15, title: "Rabbi awzi'ni an ashkura"),
        QuranDua(surah: 71, from: 28, to: 28, title: "Rabbighfir li wa liwalidayya"),
        QuranDua(surah: 113, from: 1, to: 5, title: "Al-Falaq"),
        QuranDua(surah: 114, from: 1, to: 6, title: "An-Nas"),
    ]
}
