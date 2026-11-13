import SwiftUI
import UIKit

/// The Qur'an tab: the Madinah mushaf's 604 pages, turned right to left, with an index of surahs, juz and du'as,
/// and search.
struct QuranView: View {
    // `-quranPage 42` opens another page first (used for CI screenshots); afterwards the last page read.
    @AppStorage(QuranProgress.pageKey, store: SharedStore.defaults) private var page = 1
    /// The largest text size; each page uses the largest size up to it at which the page fits the screen.
    @AppStorage("quranTextSize") private var textSize = 26.0
    // `-quranNight YES -quranAutoNight NO` for CI screenshots of the night page.
    @AppStorage("quranNight") private var night = false
    /// The page turns to night after Isha and back to paper at sunrise, unless paper or night was picked by hand.
    @AppStorage("quranAutoNight") private var autoNight = true
    @State private var nightNow = false
    @State private var pager = PagerHandle()
    @Environment(AppModel.self) private var model
    @AppStorage(QuranProgress.bookmarksKey, store: SharedStore.defaults) private var bookmarks = ""
    @AppStorage("reciter") private var reciterID = Reciter.all[0].id
    /// A verse to open, from the Verse of the day widget.
    @AppStorage("openVerse") private var openVerse = -1
    @State private var showingIndex = false
    /// A verse found through the index or search, marked on its page until another page is shown.
    @State private var marked: Int?
    /// A verse tapped on the page, shown in a sheet to copy or share.
    @State private var tapped: Int?
    // `-quranSheet settings` or `goto` opens that sheet first (used for CI screenshots).
    @State private var showingSettings = UserDefaults.standard.string(forKey: "quranSheet") == "settings"
    @State private var showingGoTo = UserDefaults.standard.string(forKey: "quranSheet") == "goto"
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// Until the first page turn, a line says which way the pages go.
    @AppStorage("quranTurnHintSeen") private var turnHintSeen = false

    var body: some View {
        let isNight = autoNight ? nightNow : night
        let style = isNight ? MushafStyle.dark : MushafStyle.printed
        let recitation = Recitation.shared
        let surah = Quran.shared.verses(onPage: page).first.map { Quran.shared.surahs[$0.surah - 1] }
        NavigationStack {
            // Turned like paper; a slide with Reduce Motion.
            MushafPager(page: $page, curl: !reduceMotion, handle: pager) { number in
                // The verse being recited is marked; otherwise one found through the index.
                AnyView(
                    MushafPage(number: number, textSize: textSize, marked: recitation.verse ?? marked, style: style) {
                        tapped = $0
                    }
                    // A mushaf is read right to left.
                    .environment(\.layoutDirection, .rightToLeft))
            }
            .id(reduceMotion)
            .background(style.paper.ignoresSafeArea())
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(style.paper, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbarColorScheme(isNight ? .dark : .light, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button { showingIndex = true } label: {
                        Image(systemName: "list.bullet")
                    }
                    .accessibilityLabel(Text("Index"))
                }
                ToolbarItem(placement: .principal) {
                    // The surah and the page; a tap opens "Go to page".
                    Button { showingGoTo = true } label: {
                        VStack(spacing: 1) {
                            if let surah {
                                Text(verbatim: Quran.title(of: surah))
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(style.ink)
                            }
                            Text("Page \(page)")
                                .font(.caption.monospacedDigit())
                                .foregroundStyle(style.muted)
                            // A recitation downloading for offline, from the settings sheet.
                            if let download = RecitationDownloads.shared.current {
                                ProgressView(value: download.progress)
                                    .frame(width: 70)
                                    .tint(style.ornament)
                                    .accessibilityLabel(Text(verbatim: download.title))
                            }
                        }
                    }
                    .accessibilityHint(Text("Go to page"))
                    .accessibilityIdentifier("goToPage")
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
                    Button { showingSettings = true } label: {
                        Image(systemName: "slider.horizontal.3")
                    }
                    .accessibilityLabel(Text("Page and recitation"))
                }
            }
            // Under the page: the next page on the left, the previous on the right, the page number between.
            .safeAreaInset(edge: .bottom, spacing: 0) {
                VStack(spacing: 0) {
                    if !turnHintSeen {
                        TurnHint(style: style) { turnHintSeen = true }
                    }
                    PageBar(page: page, style: style, turn: turn) { showingGoTo = true }
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
            .sheet(isPresented: $showingGoTo) {
                GoToPageView(page: page) { number in
                    page = number
                    showingGoTo = false
                }
            }
            .sheet(isPresented: $showingSettings) {
                ReaderSettingsView(page: page, night: $night, autoNight: $autoNight, textSize: $textSize,
                                   pageImage: pager.snapshot())
            }
            // A page open for 10 seconds counts as read, for the khatm in Ibadah; leafing through doesn't.
            .task(id: page) {
                try? await Task.sleep(for: .seconds(QuranProgress.readingSeconds))
                guard !Task.isCancelled else { return }
                QuranProgress.markRead(page)
            }
            .onChange(of: page) {
                if let marked, Quran.shared.page(ofVerse: marked) != page { self.marked = nil }
                turnHintSeen = true
            }
            .task(id: autoNight) {
                if autoNight { await followTheNight() }
            }
            .onChange(of: openVerse, initial: true) {
                guard Quran.shared.verses.indices.contains(openVerse) else { return }
                marked = openVerse
                page = Quran.shared.page(ofVerse: openVerse)
                openVerse = -1
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

    /// Night from Isha until sunrise, checked again at each of the two (and at least every quarter of an hour).
    private func followTheNight() async {
        while !Task.isCancelled {
            let now = Date.now
            guard let place = model.place, let today = model.times(on: now, at: place),
                  let sunrise = today.first(where: { $0.kind == .sunrise })?.time,
                  let isha = today.first(where: { $0.kind == .isha })?.time else { return }
            nightNow = now >= isha || now < sunrise
            let next = [sunrise, isha].filter { $0 > now }.min() ?? now.addingTimeInterval(900)
            try? await Task.sleep(for: .seconds(min(900, max(30, next.timeIntervalSince(now)))))
        }
    }

    private func turn(to number: Int) {
        guard (1...Quran.pageCount).contains(number) else { return }
        withAnimation(reduceMotion ? nil : .smooth) { page = number }
    }
}

/// Shown until the first page turn: which way the pages of a mushaf go.
private struct TurnHint: View {
    let style: MushafStyle
    let close: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "hand.draw")
                .accessibilityHidden(true)
            Text("Swipe right or tap ‹ for the next page, as in a mushaf.")
                .font(.footnote)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
            Button(action: close) {
                Image(systemName: "xmark")
                    .frame(width: 44, height: 44)
            }
            .accessibilityLabel(Text("Close"))
        }
        .foregroundStyle(style.accent)
        .padding(.leading, 16)
        .padding(.trailing, 4)
        .background(style.paper)
        .overlay(alignment: .top) { style.ornament.opacity(0.5).frame(height: 1) }
    }
}

/// Under the page: the next page on the left and the previous one on the right, as a mushaf turns, with the page
/// number in its medallion between them, which opens "Go to page".
private struct PageBar: View {
    let page: Int
    let style: MushafStyle
    let turn: (Int) -> Void
    let goTo: () -> Void

    var body: some View {
        HStack(spacing: 0) {
            Button { turn(page + 1) } label: {
                HStack(spacing: 6) {
                    Image(systemName: "chevron.left")
                    Text(verbatim: Formats.number(page + 1))
                }
                .frame(minWidth: 88, minHeight: 44, alignment: .leading)
                .contentShape(Rectangle())
            }
            .opacity(page < Quran.pageCount ? 1 : 0)
            .disabled(page >= Quran.pageCount)
            .accessibilityLabel(Text("Next page"))
            .accessibilityIdentifier("nextPage")
            Spacer(minLength: 8)
            Button(action: goTo) {
                Text(verbatim: Quran.arabicDigits(page))
                    .font(Quran.font(size: 15))
                    .foregroundStyle(style.ink)
                    .frame(minWidth: 38, minHeight: 38)
                    .background(Circle().strokeBorder(style.ornament, lineWidth: 1.5))
                    .overlay(Circle().strokeBorder(style.accent.opacity(0.6), lineWidth: 0.8).padding(3))
                    .frame(minWidth: 44, minHeight: 44)
            }
            .accessibilityLabel(Text("Go to page"))
            .accessibilityValue(Text("Page \(page)"))
            Spacer(minLength: 8)
            Button { turn(page - 1) } label: {
                HStack(spacing: 6) {
                    Text(verbatim: Formats.number(page - 1))
                    Image(systemName: "chevron.right")
                }
                .frame(minWidth: 88, minHeight: 44, alignment: .trailing)
                .contentShape(Rectangle())
            }
            .opacity(page > 1 ? 1 : 0)
            .disabled(page <= 1)
            .accessibilityLabel(Text("Previous page"))
            .accessibilityIdentifier("previousPage")
        }
        .font(.subheadline.weight(.semibold).monospacedDigit())
        .foregroundStyle(style.accent)
        .padding(.horizontal, 12)
        .background(style.paper)
        // The next page lies to the left, as in a mushaf, whatever the app's language.
        .environment(\.layoutDirection, .leftToRight)
    }
}

/// How a mushaf page looks: printed paper (the default) or dark for reading at night.
struct MushafStyle {
    let paper: Color
    let ink: Color
    /// The gold of the frames.
    let ornament: Color
    /// The verse-end signs and their numbers: text, so at least 4.5:1 against the paper (WCAG), also when marked.
    let number: Color
    /// The green of the inner frame lines and the margin notes.
    let accent: Color
    let muted: Color
    /// How dark the fold of the book is.
    let fold: Double

    static let printed = MushafStyle(
        paper: Color(hex: 0xFBF6E8), ink: Color(hex: 0x1E1912), ornament: Color(hex: 0xB0893C),
        number: Color(hex: 0x735418), accent: Color(hex: 0x2B5A43), muted: Color(hex: 0x65573F), fold: 0.16)
    static let dark = MushafStyle(
        paper: Theme.background, ink: Theme.ink, ornament: Theme.gold,
        number: Theme.gold, accent: Color(hex: 0x7FA88E), muted: Theme.muted, fold: 0.5)
}

/// One page of the mushaf, laid out like the printed one: the surah and juz in the top margin, the framed text, and
/// the fold of the book on the inner edge. Its number is in the page bar under it.
struct MushafPage: View {
    let number: Int
    let textSize: Double
    let marked: Int?
    let style: MushafStyle
    var onTapVerse: (Int) -> Void = { _ in }
    @Environment(\.accessibilityDifferentiateWithoutColor) private var differentiateWithoutColor
    @Environment(\.dynamicTypeSize) private var typeSize

    private static let smallest = 14.0
    /// The outer margin, wider for the hizb and sajda notes, and the inner one at the fold.
    private static let outer = 28.0
    private static let inner = 8.0
    /// Between the frame and the text.
    private static let inset = 14.0

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
        }
        // Pages are laid out right to left, so leading is the right edge: the outer one on a right-hand (odd) page.
        .padding(.leading, number % 2 == 1 ? Self.outer : Self.inner)
        .padding(.trailing, number % 2 == 1 ? Self.inner : Self.outer)
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
                    // The notes go in the middle of the outer margin, outside the frame.
                    ArabicParagraph(text: text, notesOnRight: number % 2 == 1, notesOffset: Self.inset + Self.outer / 2,
                                    notesWidth: Self.outer - 4, noteColor: UIColor(style.number), onTapVerse: onTapVerse)
                }
            }
        }
        .padding(.horizontal, Self.inset)
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
        let font = Quran.uiFont(size: size, typeSize: typeSize)
        let paragraphStyle = NSMutableParagraphStyle()
        // Al-Fatiha and the start of Al-Baqarah are centred, as printed; the other pages are justified.
        paragraphStyle.alignment = number <= 2 ? .center : .justified
        paragraphStyle.baseWritingDirection = .rightToLeft
        // Amiri Quran's own line height (2.45 em) is for its tallest stacked marks; 2.1 em between lines fits a
        // page's 15 lines on an iPhone, as in print, without the marks of two lines meeting.
        paragraphStyle.minimumLineHeight = font.pointSize * 2.1
        paragraphStyle.maximumLineHeight = font.pointSize * 2.1
        let ink = UIColor(style.ink)
        let ornament = UIColor(style.ornament)
        let number = UIColor(style.number)
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
                .font: font, .foregroundColor: number, .paragraphStyle: paragraphStyle, .quranVerse: verse.index,
            ]))
            // Notes in the margin beside the line, as in print: where a quarter of a hizb begins, and a sajda.
            if let quarter = Quran.shared.quarters[verse.index] {
                run.addAttribute(.mushafNote, value: Self.quarterNote(quarter), range: NSRange(location: 0, length: 1))
            }
            if Quran.shared.sajdas.contains(verse.index) {
                run.addAttribute(.mushafNote, value: "\u{06E9}\nسجدة",
                                 range: NSRange(location: (text + " ").utf16.count, length: 1))
            }
            if verse.index == marked {
                let whole = NSRange(location: 0, length: run.length)
                run.addAttribute(.backgroundColor, value: ornament.withAlphaComponent(0.2), range: whole)
                // On the highlight the number in ink keeps every text above 6.3:1, as the accessibility page says.
                run.addAttribute(.foregroundColor, value: ink, range: whole)
                // Differentiate Without Color: underlined as well.
                if differentiateWithoutColor {
                    run.addAttribute(.underlineStyle, value: NSUnderlineStyle.single.rawValue, range: whole)
                }
            }
            paragraph.append(run)
        }
        flush()
        return blocks
    }

    /// Word under word, as in print: "ربع / الحزب / ٥" where the second quarter of the fifth hizb begins.
    static func quarterNote(_ quarter: Int) -> String {
        let hizb = Quran.arabicDigits(quarter / 4 + 1)
        switch quarter % 4 {
        case 1: return "ربع\nالحزب\n" + hizb
        case 2: return "نصف\nالحزب\n" + hizb
        case 3: return "ثلاثة\nأرباع\nالحزب\n" + hizb
        default: return "الحزب\n" + hizb
        }
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
    var notesOnRight = true
    /// From the edge of the text to the middle of the margin the notes are in, and how wide they may be.
    var notesOffset = 0.0
    var notesWidth = 24.0
    var noteColor = UIColor.label
    var onTapVerse: (Int) -> Void = { _ in }

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIView(context: Context) -> MushafLabel {
        let label = MushafLabel()
        label.numberOfLines = 0
        label.lineBreakMode = .byWordWrapping
        label.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        label.setContentHuggingPriority(.defaultLow, for: .horizontal)
        label.isUserInteractionEnabled = true
        label.addGestureRecognizer(UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.tapped(_:))))
        // VoiceOver reads it with an Arabic voice.
        label.accessibilityLanguage = "ar"
        return label
    }

    func updateUIView(_ label: MushafLabel, context: Context) {
        context.coordinator.onTapVerse = onTapVerse
        if label.notesOnRight != notesOnRight || label.notesOffset != notesOffset || label.notesWidth != notesWidth
            || label.noteColor != noteColor {
            label.notesOnRight = notesOnRight
            label.notesOffset = notesOffset
            label.notesWidth = notesWidth
            label.noteColor = noteColor
            label.setNeedsLayout()
        }
        guard label.attributedText?.isEqual(to: text) != true else { return }
        label.attributedText = text
        label.setNeedsLayout()
        // VoiceOver and Voice Control can't aim at one verse in the text, so each verse is also an action that
        // opens it, as a tap does.
        var verses: [Int] = []
        text.enumerateAttribute(.quranVerse, in: NSRange(location: 0, length: text.length)) { value, _, _ in
            if let verse = value as? Int, verses.last != verse { verses.append(verse) }
        }
        let coordinator = context.coordinator
        label.accessibilityCustomActions = verses.map { index in
            let verse = Quran.shared.verses[index]
            let reference = "\(Quran.title(of: Quran.shared.surahs[verse.surah - 1])) \(verse.surah):\(verse.number)"
            return UIAccessibilityCustomAction(name: String(localized: "Verse \(reference)", bundle: .app)) { _ in
                coordinator.onTapVerse(index)
                return true
            }
        }
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

    func sizeThatFits(_ proposal: ProposedViewSize, uiView: MushafLabel, context: Context) -> CGSize? {
        guard let width = proposal.width, width.isFinite, width > 0 else { return nil }
        uiView.preferredMaxLayoutWidth = width
        let height = uiView.sizeThatFits(CGSize(width: width, height: .greatestFiniteMagnitude)).height
        return CGSize(width: width, height: ceil(height))
    }
}

extension NSAttributedString.Key {
    /// The verse a run of mushaf text belongs to (its index in the whole Qur'an), for taps.
    static let quranVerse = NSAttributedString.Key("quranVerse")
    /// A note for the margin beside the line this character is on.
    static let mushafNote = NSAttributedString.Key("mushafNote")
}

/// The mushaf text, with its notes in the outer margin beside their lines, laid out as the label lays out the text.
final class MushafLabel: UILabel {
    var notesOnRight = true
    var notesOffset = 0.0
    var notesWidth = 24.0
    var noteColor = UIColor.label
    private var notes: [UILabel] = []

    override func layoutSubviews() {
        super.layoutSubviews()
        notes.forEach { $0.removeFromSuperview() }
        notes = []
        guard let text = attributedText, text.length > 0, bounds.width > 0 else { return }
        let storage = NSTextStorage(attributedString: text)
        let layout = NSLayoutManager()
        let container = NSTextContainer(size: CGSize(width: bounds.width, height: .greatestFiniteMagnitude))
        container.lineFragmentPadding = 0
        layout.addTextContainer(container)
        storage.addLayoutManager(layout)
        let style = NSMutableParagraphStyle()
        style.alignment = .center
        style.minimumLineHeight = 13
        style.maximumLineHeight = 13
        let font = UIFont(name: Quran.fontName, size: 10) ?? .systemFont(ofSize: 10)
        var bottom = -CGFloat.greatestFiniteMagnitude
        text.enumerateAttribute(.mushafNote, in: NSRange(location: 0, length: text.length)) { value, range, _ in
            guard let note = value as? String else { return }
            let line = layout.lineFragmentRect(forGlyphAt: layout.glyphIndexForCharacter(at: range.location),
                                               effectiveRange: nil)
            let label = UILabel()
            label.numberOfLines = 0
            let fit = CGSize(width: 80, height: CGFloat.greatestFiniteMagnitude)
            label.attributedText = NSAttributedString(string: note, attributes: [
                .font: font, .foregroundColor: noteColor, .paragraphStyle: style,
            ])
            var size = label.sizeThatFits(fit)
            // Within the margin: a smaller size when the longest word is wider than it.
            if size.width > notesWidth {
                let smaller = font.withSize(max(7, font.pointSize * notesWidth / size.width))
                label.attributedText = NSAttributedString(string: note, attributes: [
                    .font: smaller, .foregroundColor: noteColor, .paragraphStyle: style,
                ])
                size = label.sizeThatFits(fit)
            }
            // Beside its line; below the note before if two lines are close.
            let y = max(line.midY - size.height / 2, bottom + 4)
            let middle = notesOnRight ? bounds.maxX + notesOffset : bounds.minX - notesOffset
            label.frame = CGRect(x: middle - size.width / 2, y: y, width: size.width, height: size.height)
            // VoiceOver reads the ۞ and ۩ in the text itself.
            label.isAccessibilityElement = false
            addSubview(label)
            notes.append(label)
            bottom = y + size.height
        }
    }
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
                    // The verse as a card on the mushaf's paper, with the text itself as the message.
                    ShareLink(item: CardImage { CardImage.picture(of: VerseCard(verse: verse)) },
                              message: Text(verbatim: shared), preview: SharePreview(Text(verbatim: reference))) {
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
    @AppStorage(QuranProgress.bookmarksKey, store: SharedStore.defaults) private var bookmarks = ""
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
                HStack(spacing: 0) {
                    if surah.isMeccan {
                        Text("Meccan · \(surah.ayahs) verses")
                    } else {
                        Text("Medinan · \(surah.ayahs) verses")
                    }
                    Text(verbatim: " · ")
                    Text("Page \(Quran.shared.page(ofVerse: surah.start))")
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
