import SwiftUI
import UIKit

/// The Qur'an tab: the Madinah mushaf's 604 pages, turned right to left, with an index of surahs, juz and du'as,
/// and search.
struct QuranView: View {
    // `-quranPage 42` opens another page first (used for CI screenshots); afterwards the last page read.
    @AppStorage("quranPage") private var page = 1
    /// The largest text size; each page uses the largest size up to it at which the page fits the screen.
    @AppStorage("quranTextSize") private var textSize = 26.0
    // `-quranNight YES` for CI screenshots of the night page.
    @AppStorage("quranNight") private var night = false
    @State private var showingIndex = false
    /// A verse found through the index or search, marked on its page until another page is shown.
    @State private var marked: Int?

    var body: some View {
        let style = night ? MushafStyle.dark : MushafStyle.printed
        NavigationStack {
            TabView(selection: $page) {
                ForEach(1...Quran.pageCount, id: \.self) { number in
                    MushafPage(number: number, textSize: textSize, marked: marked, style: style)
                        .tag(number)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            // A mushaf is read right to left: the next page lies to the left.
            .environment(\.layoutDirection, .rightToLeft)
            .background(style.paper.ignoresSafeArea())
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(style.paper, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbarColorScheme(night ? .dark : .light, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button { showingIndex = true } label: {
                        Image(systemName: "list.bullet")
                    }
                    .accessibilityLabel(Text("Index"))
                }
                ToolbarItem(placement: .principal) {
                    Text("Page \(page)")
                        .font(.subheadline.monospacedDigit())
                        .foregroundStyle(style.muted)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Picker("Page", selection: $night) {
                            Label("Paper", systemImage: "sun.max").tag(false)
                            Label("Night", systemImage: "moon").tag(true)
                        }
                        Button("Larger text", systemImage: "textformat.size.larger") { textSize = min(textSize + 2, 40) }
                            .disabled(textSize >= 40)
                        Button("Smaller text", systemImage: "textformat.size.smaller") { textSize = max(textSize - 2, 18) }
                            .disabled(textSize <= 18)
                    } label: {
                        Image(systemName: "textformat.size")
                    }
                    .accessibilityLabel(Text("Text size"))
                }
            }
            .sheet(isPresented: $showingIndex) {
                QuranIndexView { verse in
                    marked = verse
                    page = Quran.shared.page(ofVerse: verse)
                    showingIndex = false
                }
            }
            .onChange(of: page) {
                if let marked, Quran.shared.page(ofVerse: marked) != page { self.marked = nil }
            }
        }
    }
}

/// How a mushaf page looks: printed paper (the default) or dark for reading at night.
struct MushafStyle {
    let paper: Color
    let ink: Color
    /// The gold of the frames and the verse-end signs.
    let ornament: Color
    /// The green of the inner frame lines and the margin notes.
    let accent: Color
    let muted: Color
    /// How dark the fold of the book is.
    let fold: Double

    static let printed = MushafStyle(
        paper: Color(hex: 0xFBF6E8), ink: Color(hex: 0x1E1912), ornament: Color(hex: 0xB0893C),
        accent: Color(hex: 0x2B5A43), muted: Color(hex: 0x7B6B50), fold: 0.16)
    static let dark = MushafStyle(
        paper: Theme.background, ink: Theme.ink, ornament: Theme.gold,
        accent: Color(hex: 0x7FA88E), muted: Theme.muted, fold: 0.5)
}

/// One page of the mushaf, laid out like the printed one: the surah and juz in the top margin, the framed text,
/// the page number in a medallion, and the fold of the book on the inner edge.
struct MushafPage: View {
    let number: Int
    let textSize: Double
    let marked: Int?
    let style: MushafStyle

    private static let smallest = 16.0

    var body: some View {
        let quran = Quran.shared
        let verses = quran.verses(onPage: number)
        VStack(spacing: 8) {
            if let first = verses.first {
                HStack {
                    Text(verbatim: "سورة " + quran.surahs[first.surah - 1].name)
                    Spacer()
                    Text(verbatim: "الجزء " + Quran.arabicDigits(quran.juz(ofVerse: first.index)))
                }
                .font(Quran.font(size: 15))
                .foregroundStyle(style.accent)
                .padding(.horizontal, 10)
            }
            // The largest size up to the reader's at which the page fits the screen, as on paper; it scrolls only
            // when even the smallest doesn't fit (very large text sizes).
            ViewThatFits(in: .vertical) {
                ForEach(stride(from: max(textSize, Self.smallest), through: Self.smallest, by: -2).map { $0 }, id: \.self) { size in
                    framedText(verses, size: size)
                }
                ScrollView { framedText(verses, size: Self.smallest) }
                    .scrollBounceBehavior(.basedOnSize)
            }
            Text(verbatim: Quran.arabicDigits(number))
                .font(Quran.font(size: 15))
                .foregroundStyle(style.ink)
                .frame(minWidth: 36, minHeight: 36)
                .background(Circle().strokeBorder(style.ornament, lineWidth: 1.5))
                .overlay(Circle().strokeBorder(style.accent.opacity(0.6), lineWidth: 0.8).padding(3))
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(style.paper)
        .overlay { fold }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(Text("Page \(number)"))
    }

    private func framedText(_ verses: ArraySlice<Quran.Verse>, size: Double) -> some View {
        VStack(spacing: 10) {
            ForEach(blocks(verses, size: size)) { block in
                switch block.kind {
                case .header(let surah):
                    SurahHeader(name: Quran.shared.surahs[surah - 1].name, style: style)
                case .basmala(let basmala):
                    Text(verbatim: basmala)
                        .font(Quran.font(size: size))
                        .foregroundStyle(style.ink)
                case .text(let text):
                    ArabicParagraph(text: text)
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 18)
        .frame(maxWidth: .infinity)
        .background(MushafFrame(style: style))
    }

    /// The fold of the book: shade on the left of a right-hand (odd) page, on the right of a left-hand (even) one.
    private var fold: some View {
        HStack(spacing: 0) {
            if number % 2 == 1 {
                LinearGradient(colors: [.black.opacity(style.fold), .clear], startPoint: .leading, endPoint: .trailing)
                    .frame(width: 22)
                Spacer(minLength: 0)
            } else {
                Spacer(minLength: 0)
                LinearGradient(colors: [.clear, .black.opacity(style.fold)], startPoint: .leading, endPoint: .trailing)
                    .frame(width: 22)
            }
        }
        .environment(\.layoutDirection, .leftToRight)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    /// The page's parts in order: a header and basmala where a surah begins, then its verses as one paragraph.
    private func blocks(_ verses: ArraySlice<Quran.Verse>, size: Double) -> [Block] {
        var blocks: [Block] = []
        var paragraph = NSMutableAttributedString()
        func flush() {
            if paragraph.length > 0 { blocks.append(Block(id: blocks.count, kind: .text(paragraph))) }
            paragraph = NSMutableAttributedString()
        }
        let font = Quran.uiFont(size: size)
        let paragraphStyle = NSMutableParagraphStyle()
        // Al-Fatiha and the start of Al-Baqarah are centred, as printed; the other pages are justified.
        paragraphStyle.alignment = number <= 2 ? .center : .justified
        paragraphStyle.baseWritingDirection = .rightToLeft
        paragraphStyle.lineHeightMultiple = 1.3
        let ink = UIColor(style.ink)
        let ornament = UIColor(style.ornament)
        for verse in verses {
            var text = verse.text
            if verse.number == 1 && verse.surah != 1 {
                flush()
                blocks.append(Block(id: blocks.count, kind: .header(verse.surah)))
                // Tanzil writes the basmala as the first four words of the first verse (At-Tawbah has none; in 95
                // and 97 its first letter carries a shadda), so it is split off as written, on a line of its own.
                let words = text.split(separator: " ", maxSplits: 4)
                if verse.surah != 9, words.count == 5,
                   Quran.plainArabic(words[0..<4].joined(separator: " ")) == "بسم الله الرحمن الرحيم" {
                    blocks.append(Block(id: blocks.count, kind: .basmala(words[0..<4].joined(separator: " "))))
                    text = String(words[4])
                }
            } else if verse.number == 1 {
                blocks.append(Block(id: blocks.count, kind: .header(verse.surah)))
            }
            // The verse, then its number inside the end-of-verse sign in gold (U+06DD takes the digits after it).
            let run = NSMutableAttributedString(string: text + " ", attributes: [
                .font: font, .foregroundColor: ink, .paragraphStyle: paragraphStyle,
            ])
            run.append(NSAttributedString(string: "\u{06DD}" + Quran.arabicDigits(verse.number) + " ", attributes: [
                .font: font, .foregroundColor: ornament, .paragraphStyle: paragraphStyle,
            ]))
            if verse.index == marked {
                run.addAttribute(.backgroundColor, value: ornament.withAlphaComponent(0.25),
                                 range: NSRange(location: 0, length: run.length))
            }
            paragraph.append(run)
        }
        flush()
        return blocks
    }

    private struct Block: Identifiable {
        enum Kind {
            case header(Int)
            case basmala(String)
            case text(NSAttributedString)
        }
        let id: Int
        let kind: Kind
    }
}

/// The frame around the text, as in a printed mushaf: a gold line, a thin green one inside it, stars in the corners.
struct MushafFrame: View {
    let style: MushafStyle

    var body: some View {
        RoundedRectangle(cornerRadius: 4)
            .strokeBorder(style.ornament, lineWidth: 2.5)
            .overlay(RoundedRectangle(cornerRadius: 2).strokeBorder(style.accent.opacity(0.65), lineWidth: 1).padding(5))
            .overlay(alignment: .topLeading) { corner.offset(x: -7, y: -7) }
            .overlay(alignment: .topTrailing) { corner.offset(x: 7, y: -7) }
            .overlay(alignment: .bottomLeading) { corner.offset(x: -7, y: 7) }
            .overlay(alignment: .bottomTrailing) { corner.offset(x: 7, y: 7) }
            .environment(\.layoutDirection, .leftToRight)
            .accessibilityHidden(true)
    }

    private var corner: some View {
        EightPointStar()
            .fill(style.ornament)
            .frame(width: 14, height: 14)
            .background(Circle().fill(style.paper).frame(width: 12, height: 12))
    }
}

/// The framed name at the start of a surah, between two stars, as in a printed mushaf.
struct SurahHeader: View {
    let name: String
    let style: MushafStyle

    var body: some View {
        HStack(spacing: 12) {
            EightPointStar().fill(style.ornament).frame(width: 11, height: 11)
            Text(verbatim: "سورة " + name)
                .font(Quran.font(size: 21))
                .foregroundStyle(style.ink)
            EightPointStar().fill(style.ornament).frame(width: 11, height: 11)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 6)
        .background(style.ornament.opacity(0.14), in: RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(style.ornament, lineWidth: 1.5))
        .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(style.accent.opacity(0.55), lineWidth: 0.8).padding(3))
        .accessibilityAddTraits(.isHeader)
    }
}

/// Arabic text justified from right to left, as in a printed mushaf (SwiftUI's Text can't justify).
struct ArabicParagraph: UIViewRepresentable {
    let text: NSAttributedString

    func makeUIView(context: Context) -> UILabel {
        let label = UILabel()
        label.numberOfLines = 0
        label.lineBreakMode = .byWordWrapping
        label.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        label.setContentHuggingPriority(.defaultLow, for: .horizontal)
        return label
    }

    func updateUIView(_ label: UILabel, context: Context) {
        if label.attributedText?.isEqual(to: text) != true { label.attributedText = text }
    }

    func sizeThatFits(_ proposal: ProposedViewSize, uiView: UILabel, context: Context) -> CGSize? {
        guard let width = proposal.width, width.isFinite, width > 0 else { return nil }
        uiView.preferredMaxLayoutWidth = width
        let height = uiView.sizeThatFits(CGSize(width: width, height: .greatestFiniteMagnitude)).height
        return CGSize(width: width, height: ceil(height))
    }
}

/// The index: surahs, juz and du'as, and a search across them and the verses.
struct QuranIndexView: View {
    let open: (Int) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var query = ""
    @AppStorage("quranIndexPart") private var part = Part.surahs

    enum Part: String {
        case surahs, juz, duas
    }

    var body: some View {
        let quran = Quran.shared
        NavigationStack {
            List {
                if query.trimmingCharacters(in: .whitespaces).isEmpty {
                    Picker("Index", selection: $part) {
                        Text("Surahs").tag(Part.surahs)
                        Text("Juz").tag(Part.juz)
                        Text("Du'as").tag(Part.duas)
                    }
                    .pickerStyle(.segmented)
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets(top: 4, leading: 0, bottom: 4, trailing: 0))
                    switch part {
                    case .surahs:
                        ForEach(quran.surahs) { surah in
                            Button { open(surah.start) } label: { SurahRow(surah: surah) }
                        }
                    case .juz:
                        ForEach(Array(quran.juzStarts.enumerated()), id: \.offset) { offset, start in
                            Button { open(start) } label: { JuzRow(juz: offset + 1, start: start) }
                        }
                    case .duas:
                        ForEach(QuranDua.all) { dua in
                            Button { open(quran.index(surah: dua.surah, verse: dua.from)) } label: { DuaRow(dua: dua) }
                        }
                    }
                } else {
                    let results = quran.search(query)
                    if results.isEmpty {
                        Text("No results")
                            .foregroundStyle(Theme.muted)
                    }
                    if !results.surahs.isEmpty {
                        Section("Surahs") {
                            ForEach(results.surahs) { surah in
                                Button { open(surah.start) } label: { SurahRow(surah: surah) }
                            }
                        }
                    }
                    if !results.duas.isEmpty {
                        Section("Du'as") {
                            ForEach(results.duas) { dua in
                                Button { open(quran.index(surah: dua.surah, verse: dua.from)) } label: { DuaRow(dua: dua) }
                            }
                        }
                    }
                    if !results.verses.isEmpty {
                        Section("Verses") {
                            ForEach(results.verses) { verse in
                                Button { open(verse.index) } label: { VerseRow(verse: verse) }
                            }
                        }
                    }
                }
                Section {
                    Link(destination: URL(string: "https://tanzil.net")!) {
                        Text("Qur'an text: Tanzil Project (tanzil.net)")
                            .font(.footnote)
                    }
                }
                .listRowBackground(Color.clear)
            }
            .listStyle(.insetGrouped)
            .scrollContentBackground(.hidden)
            .background(Theme.background.ignoresSafeArea())
            .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always),
                        prompt: Text("Search surahs, du'as and verses"))
            .navigationTitle("Qur'an")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}

private struct SurahRow: View {
    let surah: Quran.Surah

    var body: some View {
        HStack(spacing: 14) {
            Text(verbatim: Formats.number(surah.n))
                .font(.subheadline.monospacedDigit())
                .foregroundStyle(Theme.gold)
                .frame(minWidth: 28)
            VStack(alignment: .leading, spacing: 2) {
                Text(verbatim: Quran.title(of: surah))
                    .font(.headline)
                    .foregroundStyle(Theme.ink)
                if let meaning = Quran.meaning(of: surah) {
                    Text(verbatim: meaning)
                        .font(.subheadline)
                        .foregroundStyle(Theme.ink.opacity(0.8))
                }
                Group {
                    if surah.isMeccan {
                        Text("Meccan · \(surah.ayahs) verses")
                    } else {
                        Text("Medinan · \(surah.ayahs) verses")
                    }
                }
                .font(.footnote)
                .foregroundStyle(Theme.muted)
            }
            Spacer()
            // In Arabic the title already is the Arabic name.
            if Quran.languageCode != "ar" {
                Text(verbatim: surah.name)
                    .font(Quran.font(size: 22))
                    .foregroundStyle(Theme.ink)
            }
        }
        .contentShape(Rectangle())
    }
}

private struct JuzRow: View {
    let juz: Int
    let start: Int

    var body: some View {
        let quran = Quran.shared
        let verse = quran.verses[start]
        HStack(spacing: 14) {
            Text(verbatim: Formats.number(juz))
                .font(.subheadline.monospacedDigit())
                .foregroundStyle(Theme.gold)
                .frame(minWidth: 28)
            VStack(alignment: .leading, spacing: 2) {
                Text("Juz \(juz)")
                    .font(.headline)
                    .foregroundStyle(Theme.ink)
                Text(verbatim: "\(Quran.title(of: quran.surahs[verse.surah - 1])) \(verse.surah):\(verse.number)")
                    .font(.subheadline)
                    .foregroundStyle(Theme.muted)
            }
            Spacer()
            Text("Page \(quran.page(ofVerse: start))")
                .font(.subheadline.monospacedDigit())
                .foregroundStyle(Theme.muted)
        }
        .contentShape(Rectangle())
    }
}

private struct DuaRow: View {
    let dua: QuranDua

    var body: some View {
        let quran = Quran.shared
        let verse = quran.verses[quran.index(surah: dua.surah, verse: dua.from)]
        VStack(alignment: .leading, spacing: 4) {
            // Arabic sits on the right in any app language: leading is the right edge from right to left.
            Text(verbatim: verse.text)
                .font(Quran.font(size: 20))
                .foregroundStyle(Theme.ink)
                .lineLimit(2)
                .frame(maxWidth: .infinity, alignment: .leading)
                .environment(\.layoutDirection, .rightToLeft)
            Text(verbatim: dua.title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Theme.gold)
            Text(verbatim: reference)
                .font(.footnote)
                .foregroundStyle(Theme.muted)
        }
        .contentShape(Rectangle())
    }

    private var reference: String {
        let name = Quran.title(of: Quran.shared.surahs[dua.surah - 1])
        return dua.from == dua.to ? "\(name) \(dua.surah):\(dua.from)" : "\(name) \(dua.surah):\(dua.from)-\(dua.to)"
    }
}

private struct VerseRow: View {
    let verse: Quran.Verse

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(verbatim: verse.text)
                .font(Quran.font(size: 20))
                .foregroundStyle(Theme.ink)
                .lineLimit(3)
                .frame(maxWidth: .infinity, alignment: .leading)
                .environment(\.layoutDirection, .rightToLeft)
            Text(verbatim: "\(Quran.title(of: Quran.shared.surahs[verse.surah - 1])) \(verse.surah):\(verse.number)")
                .font(.footnote)
                .foregroundStyle(Theme.muted)
        }
        .contentShape(Rectangle())
    }
}
