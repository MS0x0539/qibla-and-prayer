import SwiftUI
import UIKit

/// The Qur'an tab: the Madinah mushaf's 604 pages, turned right to left, with an index of surahs, juz and du'as,
/// and search.
struct QuranView: View {
    // `-quranPage 42` opens another page first (used for CI screenshots); afterwards the last page read.
    @AppStorage("quranPage") private var page = 1
    @AppStorage("quranTextSize") private var textSize = 26.0
    @State private var showingIndex = false
    /// A verse found through the index or search, marked on its page until another page is shown.
    @State private var marked: Int?

    var body: some View {
        NavigationStack {
            TabView(selection: $page) {
                ForEach(1...Quran.pageCount, id: \.self) { number in
                    MushafPage(number: number, textSize: textSize, marked: marked)
                        .tag(number)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            // A mushaf is read right to left: the next page lies to the left.
            .environment(\.layoutDirection, .rightToLeft)
            .background(Theme.background.ignoresSafeArea())
            .navigationBarTitleDisplayMode(.inline)
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
                        .foregroundStyle(Theme.muted)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
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

/// One page of the mushaf: its surah and juz at the top, the verses with their numbers, the page number below.
struct MushafPage: View {
    let number: Int
    let textSize: Double
    let marked: Int?

    var body: some View {
        let quran = Quran.shared
        let verses = quran.verses(onPage: number)
        ScrollView {
            VStack(spacing: 14) {
                if let first = verses.first {
                    HStack {
                        Text(verbatim: "سورة " + quran.surahs[first.surah - 1].name)
                        Spacer()
                        Text(verbatim: "الجزء " + Quran.arabicDigits(quran.juz(ofVerse: first.index)))
                    }
                    .font(Quran.font(size: 17))
                    .foregroundStyle(Theme.gold)
                }
                ForEach(blocks(verses)) { block in
                    switch block.kind {
                    case .header(let surah):
                        SurahHeader(name: quran.surahs[surah - 1].name)
                    case .basmala(let basmala):
                        Text(verbatim: basmala)
                            .font(Quran.font(size: textSize))
                            .foregroundStyle(Theme.ink)
                    case .text(let text):
                        ArabicParagraph(text: text)
                    }
                }
                Text(verbatim: Quran.arabicDigits(number))
                    .font(Quran.font(size: 17))
                    .foregroundStyle(Theme.muted)
                    .padding(.top, 4)
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 16)
            .background(
                RoundedRectangle(cornerRadius: 18)
                    .strokeBorder(Theme.gold.opacity(0.45), lineWidth: 1.5)
            )
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
        }
        .scrollBounceBehavior(.basedOnSize)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(Text("Page \(number)"))
    }

    /// The page's parts in order: a header and basmala where a surah begins, then its verses as one paragraph.
    private func blocks(_ verses: ArraySlice<Quran.Verse>) -> [Block] {
        var blocks: [Block] = []
        var paragraph = NSMutableAttributedString()
        func flush() {
            if paragraph.length > 0 { blocks.append(Block(id: blocks.count, kind: .text(paragraph))) }
            paragraph = NSMutableAttributedString()
        }
        let font = Quran.uiFont(size: textSize)
        let style = NSMutableParagraphStyle()
        style.alignment = .justified
        style.baseWritingDirection = .rightToLeft
        style.lineHeightMultiple = 1.35
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
            // The verse, then its number inside the end-of-verse sign (U+06DD takes the digits after it).
            let run = NSMutableAttributedString(string: text + " \u{06DD}" + Quran.arabicDigits(verse.number) + " ", attributes: [
                .font: font,
                .foregroundColor: UIColor(Theme.ink),
                .paragraphStyle: style,
            ])
            if verse.index == marked {
                run.addAttribute(.backgroundColor, value: UIColor(Theme.gold).withAlphaComponent(0.25),
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

/// The framed name at the start of a surah.
struct SurahHeader: View {
    let name: String

    var body: some View {
        Text(verbatim: "سورة " + name)
            .font(Quran.font(size: 22))
            .foregroundStyle(Theme.gold)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
            .background(Theme.card, in: RoundedRectangle(cornerRadius: 10))
            .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Theme.gold.opacity(0.6), lineWidth: 1))
            .accessibilityAddTraits(.isHeader)
    }
}

/// Arabic text justified from right to left, as in a printed mushaf (SwiftUI's Text can't justify).
struct ArabicParagraph: UIViewRepresentable {
    let text: NSAttributedString

    func makeUIView(context: Context) -> UITextView {
        let view = UITextView()
        view.isEditable = false
        view.isSelectable = false
        view.isScrollEnabled = false
        view.backgroundColor = .clear
        view.textContainerInset = .zero
        view.textContainer.lineFragmentPadding = 0
        view.adjustsFontForContentSizeCategory = true
        view.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        return view
    }

    func updateUIView(_ view: UITextView, context: Context) {
        if !view.attributedText.isEqual(to: text) { view.attributedText = text }
    }

    func sizeThatFits(_ proposal: ProposedViewSize, uiView: UITextView, context: Context) -> CGSize? {
        guard let width = proposal.width, width.isFinite, width > 0 else { return nil }
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
