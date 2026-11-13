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
    @AppStorage(QuranProgress.bookmarksKey) private var bookmarks = ""
    @AppStorage("reciter") private var reciterID = Reciter.all[0].id
    @State private var showingIndex = false
    /// A verse found through the index or search, marked on its page until another page is shown.
    @State private var marked: Int?
    /// A verse tapped on the page, shown in a sheet to copy or share.
    @State private var tapped: Int?

    var body: some View {
        let style = night ? MushafStyle.dark : MushafStyle.printed
        let recitation = Recitation.shared
        NavigationStack {
            TabView(selection: $page) {
                ForEach(1...Quran.pageCount, id: \.self) { number in
                    // The verse being recited is marked; otherwise one found through the index.
                    MushafPage(number: number, textSize: textSize, marked: recitation.verse ?? marked, style: style) {
                        tapped = $0
                    }
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
                    Button {
                        if recitation.isPlaying {
                            recitation.pause()
                        } else if let verse = recitation.verse, Quran.shared.page(ofVerse: verse) == page {
                            recitation.resume()
                        } else {
                            // From a verse found on this page, or from the top of the page.
                            let first = Quran.shared.verses(onPage: page).first?.index ?? 0
                            recitation.play(from: marked ?? first, reciter: .named(reciterID))
                        }
                    } label: {
                        Image(systemName: recitation.isPlaying ? "pause.fill" : "play.fill")
                    }
                    .accessibilityLabel(recitation.isPlaying ? Text("Pause recitation") : Text("Play recitation"))
                }
                ToolbarItem(placement: .topBarTrailing) {
                    let bookmarked = QuranProgress.pages(bookmarks).contains(page)
                    Button { QuranProgress.toggleBookmark(page) } label: {
                        Image(systemName: bookmarked ? "bookmark.fill" : "bookmark")
                    }
                    .accessibilityLabel(bookmarked ? Text("Remove bookmark") : Text("Bookmark"))
                    .sensoryFeedback(.selection, trigger: bookmarked)
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
                        Picker("Reciter", selection: $reciterID) {
                            ForEach(Reciter.all) { reciter in
                                Text(verbatim: reciter.displayName).tag(reciter.id)
                            }
                        }
                        .pickerStyle(.menu)
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                    .accessibilityLabel(Text("Page and recitation"))
                }
            }
            .sheet(isPresented: $showingIndex) {
                QuranIndexView { verse in
                    marked = verse
                    page = Quran.shared.page(ofVerse: verse)
                    showingIndex = false
                } openPage: { number in
                    page = number
                    showingIndex = false
                }
            }
            .sheet(isPresented: Binding(get: { tapped != nil }, set: { if !$0 { tapped = nil } })) {
                if let tapped { VerseSheet(verse: Quran.shared.verses[tapped]) }
            }
            // A page open for 10 seconds counts as read, for the khatm in Ibadah; leafing through doesn't.
            .task(id: page) {
                try? await Task.sleep(for: .seconds(QuranProgress.readingSeconds))
                guard !Task.isCancelled else { return }
                QuranProgress.markRead(page)
            }
            .onChange(of: page) {
                if let marked, Quran.shared.page(ofVerse: marked) != page { self.marked = nil }
            }
            // The page turns with the recitation.
            .onChange(of: recitation.verse) { old, new in
                guard let old, let new, Quran.shared.page(ofVerse: new) != Quran.shared.page(ofVerse: old) else { return }
                page = Quran.shared.page(ofVerse: new)
            }
            // Another reciter takes over at the same verse.
            .onChange(of: reciterID) {
                if recitation.isPlaying, let verse = recitation.verse {
                    recitation.play(from: verse, reciter: .named(reciterID))
                } else {
                    recitation.stop()
                }
            }
            .alert("The recitation can't be loaded", isPresented: Bindable(recitation).failed) {
                Button("OK", role: .cancel) {}
            } message: {
                Text("Check your internet connection and try again.")
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
    var onTapVerse: (Int) -> Void = { _ in }

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
                    ArabicParagraph(text: text, onTapVerse: onTapVerse)
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
                .font: font, .foregroundColor: ink, .paragraphStyle: paragraphStyle, .quranVerse: verse.index,
            ])
            run.append(NSAttributedString(string: "\u{06DD}" + Quran.arabicDigits(verse.number) + " ", attributes: [
                .font: font, .foregroundColor: ornament, .paragraphStyle: paragraphStyle, .quranVerse: verse.index,
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
    var onTapVerse: (Int) -> Void = { _ in }

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIView(context: Context) -> UILabel {
        let label = UILabel()
        label.numberOfLines = 0
        label.lineBreakMode = .byWordWrapping
        label.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        label.setContentHuggingPriority(.defaultLow, for: .horizontal)
        label.isUserInteractionEnabled = true
        label.addGestureRecognizer(UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.tapped(_:))))
        return label
    }

    func updateUIView(_ label: UILabel, context: Context) {
        context.coordinator.onTapVerse = onTapVerse
        if label.attributedText?.isEqual(to: text) != true { label.attributedText = text }
    }

    /// Finds the verse under the finger: the text laid out as the label lays it out, then the verse it carries.
    final class Coordinator: NSObject {
        var onTapVerse: (Int) -> Void = { _ in }

        @objc func tapped(_ gesture: UITapGestureRecognizer) {
            guard let label = gesture.view as? UILabel, let text = label.attributedText, text.length > 0 else { return }
            let storage = NSTextStorage(attributedString: text)
            let layout = NSLayoutManager()
            let container = NSTextContainer(size: label.bounds.size)
            container.lineFragmentPadding = 0
            container.lineBreakMode = label.lineBreakMode
            container.maximumNumberOfLines = label.numberOfLines
            layout.addTextContainer(container)
            storage.addLayoutManager(layout)
            let index = layout.characterIndex(for: gesture.location(in: label), in: container,
                                              fractionOfDistanceBetweenInsertionPoints: nil)
            guard index < storage.length, let verse = storage.attribute(.quranVerse, at: index, effectiveRange: nil) as? Int
            else { return }
            onTapVerse(verse)
        }
    }

    func sizeThatFits(_ proposal: ProposedViewSize, uiView: UILabel, context: Context) -> CGSize? {
        guard let width = proposal.width, width.isFinite, width > 0 else { return nil }
        uiView.preferredMaxLayoutWidth = width
        let height = uiView.sizeThatFits(CGSize(width: width, height: .greatestFiniteMagnitude)).height
        return CGSize(width: width, height: ceil(height))
    }
}

extension NSAttributedString.Key {
    /// The verse a run of mushaf text belongs to (its index in the whole Qur'an), for taps.
    static let quranVerse = NSAttributedString.Key("quranVerse")
}

/// A verse tapped on the page: its surah and number, and the Arabic to copy or share.
struct VerseSheet: View {
    let verse: Quran.Verse
    @Environment(\.dismiss) private var dismiss
    @AppStorage("reciter") private var reciterID = Reciter.all[0].id
    @State private var copied = false

    var body: some View {
        let surah = Quran.shared.surahs[verse.surah - 1]
        let reference = "\(Quran.title(of: surah)) \(verse.surah):\(verse.number)"
        // Tanzil's terms: copies of its text name the source.
        let shared = verse.text + "\n\n" + reference + " · tanzil.net"
        NavigationStack {
            ScrollView {
                Text(verbatim: verse.text)
                    .font(Quran.font(size: 26))
                    .foregroundStyle(Theme.ink)
                    .lineSpacing(8)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .environment(\.layoutDirection, .rightToLeft)
                    .padding(20)
            }
            .background(Theme.background.ignoresSafeArea())
            .safeAreaInset(edge: .bottom) {
                HStack(spacing: 12) {
                    Button {
                        Recitation.shared.play(from: verse.index, reciter: .named(reciterID))
                        dismiss()
                    } label: {
                        Label("Play", systemImage: "play.fill")
                            .frame(maxWidth: .infinity)
                    }
                    Button {
                        UIPasteboard.general.string = shared
                        copied = true
                    } label: {
                        Label(copied ? LocalizedStringKey("Copied") : LocalizedStringKey("Copy"),
                              systemImage: copied ? "checkmark" : "doc.on.doc")
                            .frame(maxWidth: .infinity)
                    }
                    ShareLink(item: shared) {
                        Label("Share", systemImage: "square.and.arrow.up")
                            .frame(maxWidth: .infinity)
                    }
                }
                .buttonStyle(.bordered)
                .controlSize(.large)
                .padding(16)
                .background(Theme.background)
            }
            .navigationTitle(Text(verbatim: reference))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .sensoryFeedback(.success, trigger: copied) { _, new in new }
        }
        .presentationDetents([.medium, .large])
    }
}

/// The index: bookmarks, surahs, juz and du'as, and a search across them and the verses.
struct QuranIndexView: View {
    let open: (Int) -> Void
    let openPage: (Int) -> Void
    @Environment(\.dismiss) private var dismiss
    @AppStorage(QuranProgress.bookmarksKey) private var bookmarks = ""
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
                    let bookmarked = QuranProgress.pages(bookmarks).sorted()
                    if !bookmarked.isEmpty {
                        Section("Bookmarks") {
                            ForEach(bookmarked, id: \.self) { number in
                                Button { openPage(number) } label: { BookmarkRow(page: number) }
                            }
                            .onDelete { offsets in
                                for offset in offsets { QuranProgress.toggleBookmark(bookmarked[offset]) }
                            }
                        }
                    }
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

private struct BookmarkRow: View {
    let page: Int

    var body: some View {
        let quran = Quran.shared
        let first = quran.verses(onPage: page).first
        HStack(spacing: 14) {
            Image(systemName: "bookmark.fill")
                .foregroundStyle(Theme.gold)
                .frame(minWidth: 28)
            VStack(alignment: .leading, spacing: 2) {
                Text("Page \(page)")
                    .font(.headline)
                    .foregroundStyle(Theme.ink)
                if let first {
                    Text(verbatim: "\(Quran.title(of: quran.surahs[first.surah - 1])) \(first.surah):\(first.number)")
                        .font(.subheadline)
                        .foregroundStyle(Theme.muted)
                }
            }
            Spacer()
        }
        .contentShape(Rectangle())
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
