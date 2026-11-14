import SwiftUI

/// The reader's settings in one place instead of a menu: the page (paper or night, text size), the reciter, and the
/// recitation downloaded to listen offline. Speed and the sleep timer are in the player, while a recitation is on.
struct ReaderSettingsView: View {
    let page: Int
    @Binding var night: Bool
    @Binding var autoNight: Bool
    @Binding var textSize: Double
    /// The page as it is on screen, to share.
    var pageImage: UIImage?
    @AppStorage("reciter") private var reciterID = Reciter.all[0].id
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section("Page") {
                    // Automatic: night from Isha until sunrise.
                    Picker("Page", selection: Binding(
                        get: { autoNight ? "automatic" : night ? "night" : "paper" },
                        set: { look in
                            autoNight = look == "automatic"
                            if look != "automatic" { night = look == "night" }
                        })) {
                        Text("Paper").tag("paper")
                        Text("Night").tag("night")
                        Text("Automatic").tag("automatic")
                    }
                    .pickerStyle(.segmented)
                    if let pageImage {
                        let image = Image(uiImage: pageImage)
                        ShareLink(item: image, preview: SharePreview(Text("Page \(page)"), image: image)) {
                            Label("Share this page", systemImage: "square.and.arrow.up")
                        }
                    }
                    Stepper(value: $textSize, in: 18...40, step: 2) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Text size")
                            // A sample at the chosen size; a page uses it when its text fits, a smaller one if not.
                            Text(verbatim: "بِسْمِ ٱللَّهِ ٱلرَّحْمَٰنِ ٱلرَّحِيمِ")
                                .font(Quran.font(size: textSize * 0.8))
                                .foregroundStyle(Theme.muted)
                                .lineLimit(1)
                                .minimumScaleFactor(0.5)
                                .accessibilityHidden(true)
                        }
                    }
                }
                .listRowBackground(Theme.card)

                Section("Reciter") {
                    NavigationLink {
                        ReciterList()
                    } label: {
                        Text(verbatim: Reciter.named(reciterID).displayName)
                            .foregroundStyle(Theme.ink)
                    }
                }
                .listRowBackground(Theme.card)

                OfflineRecitationSection()
            }
            .scrollContentBackground(.hidden)
            .background(Theme.background.ignoresSafeArea())
            .navigationTitle("Page and recitation")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}

/// The ten reciters. The one chosen recites, and is the one downloaded; choosing goes back.
struct ReciterList: View {
    @AppStorage("reciter") private var reciterID = Reciter.all[0].id
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        List {
            ForEach(Reciter.all) { reciter in
                Button {
                    reciterID = reciter.id
                    dismiss()
                } label: {
                    HStack {
                        Text(verbatim: reciter.displayName)
                            .foregroundStyle(Theme.ink)
                        Spacer()
                        if reciter.id == reciterID {
                            Image(systemName: "checkmark")
                                .foregroundStyle(Theme.gold)
                        }
                    }
                }
                .accessibilityAddTraits(reciter.id == reciterID ? .isSelected : [])
            }
            .listRowBackground(Theme.card)
        }
        .scrollContentBackground(.hidden)
        .background(Theme.background.ignoresSafeArea())
        .navigationTitle("Reciter")
        .navigationBarTitleDisplayMode(.inline)
    }
}

/// A surah, a juz or the whole Qur'an to download by one reciter, with the space it takes.
struct RecitationPart: Identifiable {
    let id: String
    let title: String
    let verses: Range<Int>
    let bytes: Int64?

    static func surah(_ number: Int, by reciter: Reciter) -> RecitationPart {
        let surah = Quran.shared.surahs[number - 1]
        return RecitationPart(id: "surah \(number)", title: Quran.title(of: surah),
                              verses: surah.start..<(surah.start + surah.ayahs), bytes: reciter.sizes?.surahs[number - 1])
    }

    static func juz(_ number: Int, by reciter: Reciter) -> RecitationPart {
        let quran = Quran.shared
        let end = number < quran.juzStarts.count ? quran.juzStarts[number] : quran.verses.count
        return RecitationPart(id: "juz \(number)", title: String(localized: "Juz \(number)", bundle: .app),
                              verses: quran.juzStarts[number - 1]..<end, bytes: reciter.sizes?.juz[number - 1])
    }

    static func whole(by reciter: Reciter) -> RecitationPart {
        RecitationPart(id: "all", title: String(localized: "The whole Qur'an", bundle: .app),
                       verses: 0..<Quran.shared.verses.count, bytes: reciter.wholeQuranBytes)
    }
}

/// One part and its size: downloaded, downloading (with a way to cancel), or a Download button.
struct RecitationDownloadRow: View {
    let part: RecitationPart
    let reciter: Reciter
    let downloaded: Bool
    /// The surah's number, in the list of all surahs.
    var number: Int?
    /// Shown instead of the part's title ("Download all" for the whole Qur'an in the lists).
    var label: Text?
    @State private var askingMobileData = false
    /// Above this, a download over mobile data asks first: the whole Qur'an, and the largest juz of some reciters.
    private static let askAbove: Int64 = 100_000_000

    var body: some View {
        let downloads = RecitationDownloads.shared
        HStack(spacing: 12) {
            if let number {
                Text(verbatim: Formats.number(number))
                    .font(.subheadline.monospacedDigit())
                    .foregroundStyle(Theme.muted)
                    .frame(minWidth: 28, alignment: .leading)
            }
            VStack(alignment: .leading, spacing: 2) {
                (label ?? Text(verbatim: part.title))
                    .foregroundStyle(Theme.ink)
                if let bytes = part.bytes {
                    Text(verbatim: bytes.formatted(.byteCount(style: .file).locale(.app)))
                        .font(.subheadline)
                        .foregroundStyle(Theme.muted)
                }
            }
            Spacer()
            if downloaded {
                // A tap on the check mark offers to remove it (and a swipe does, below).
                Menu {
                    Button(role: .destructive) { downloads.remove(part.verses, by: reciter) } label: {
                        Label("Remove", systemImage: "trash")
                    }
                } label: {
                    Label("Downloaded", systemImage: "checkmark.circle.fill")
                        .font(.subheadline)
                        .foregroundStyle(Theme.gold)
                }
            } else if let current = downloads.current, current.title == part.title {
                ProgressView(value: current.progress)
                    .frame(width: 80)
                    .tint(Theme.gold)
                Button {
                    downloads.cancel()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                }
                .accessibilityLabel(Text("Cancel"))
                .foregroundStyle(Theme.muted)
            } else {
                Button("Download") {
                    if downloads.onMobileData && (part.bytes ?? 0) > Self.askAbove {
                        askingMobileData = true
                    } else {
                        downloads.download(part.verses, by: reciter, title: part.title)
                    }
                }
                .buttonStyle(.bordered)
                .disabled(downloads.current != nil)
            }
        }
        .alert("Use mobile data?", isPresented: $askingMobileData) {
            Button("Download") { downloads.download(part.verses, by: reciter, title: part.title) }
            Button("Cancel", role: .cancel) {}
        } message: {
            let size = (part.bytes ?? 0).formatted(.byteCount(style: .file).locale(.app))
            Text("\(part.title) is \(size). You're not on Wi-Fi, so this download uses your mobile data.")
        }
        // A downloaded part can go on its own (VoiceOver offers it as an action).
        .swipeActions {
            if downloaded {
                Button(role: .destructive) { downloads.remove(part.verses, by: reciter) } label: { Text("Remove") }
            }
        }
    }
}

/// Every surah or every juz, each with its size by the chosen reciter, to download one at a time.
struct RecitationDownloadList: View {
    let juz: Bool
    @AppStorage("reciter") private var reciterID = Reciter.all[0].id
    @State private var downloaded: Set<String> = []

    var body: some View {
        let reciter = Reciter.named(reciterID)
        let parts = juz ? (1...30).map { RecitationPart.juz($0, by: reciter) }
                        : (1...114).map { RecitationPart.surah($0, by: reciter) }
        let whole = RecitationPart.whole(by: reciter)
        let downloads = RecitationDownloads.shared
        List {
            // Whose recitation the list downloads, and everything at once.
            Section {
                NavigationLink { ReciterList() } label: {
                    LabeledContent("Reciter", value: reciter.displayName)
                }
                RecitationDownloadRow(part: whole, reciter: reciter, downloaded: downloaded.contains(whole.id),
                                      label: Text("Download all"))
            } footer: {
                if downloads.current != nil {
                    Text("Keep the app open while it downloads: the screen stays on until it's done.")
                }
            }
            .listRowBackground(Theme.card)
            Section {
                ForEach(Array(parts.enumerated()), id: \.element.id) { offset, part in
                    RecitationDownloadRow(part: part, reciter: reciter, downloaded: downloaded.contains(part.id),
                                          number: juz ? nil : offset + 1)
                }
            }
            .listRowBackground(Theme.card)
        }
        .scrollContentBackground(.hidden)
        .background(Theme.background.ignoresSafeArea())
        .navigationTitle(juz ? Text("All juz") : Text("All surahs"))
        .navigationBarTitleDisplayMode(.inline)
        // On opening, when files come or go, and for another reciter.
        .task(id: "\(reciterID) \(downloads.changes) \(downloads.current == nil)") {
            downloaded = Set((parts + [whole]).filter { RecitationDownloads.isDownloaded($0.verses, by: reciter) }.map(\.id))
        }
    }
}

/// Downloads the whole Qur'an, or any surah or juz from the lists, by the chosen reciter, to listen without internet.
/// Each verse is one file shared by every part that holds it, so nothing downloads twice and a part shows as
/// downloaded once all its verses are there. The files stay inside the app until they are removed here.
struct OfflineRecitationSection: View {
    @AppStorage("reciter") private var reciterID = Reciter.all[0].id
    /// Whether the whole Qur'an is downloaded, and the space all recitation audio takes; worked out on opening and
    /// whenever files come or go.
    @State private var wholeDownloaded = false
    @State private var bytes: Int64 = 0
    @State private var confirmingRemoval = false

    var body: some View {
        let reciter = Reciter.named(reciterID)
        let whole = RecitationPart.whole(by: reciter)
        let downloads = RecitationDownloads.shared
        Section {
            RecitationDownloadRow(part: whole, reciter: reciter, downloaded: wholeDownloaded)
            NavigationLink { RecitationDownloadList(juz: false) } label: {
                Text("All surahs")
                    .foregroundStyle(Theme.ink)
            }
            NavigationLink { RecitationDownloadList(juz: true) } label: {
                Text("All juz")
                    .foregroundStyle(Theme.ink)
            }
            if downloads.missing > 0 {
                Text("Some verses couldn't be downloaded. Download again to finish.")
                    .foregroundStyle(Theme.muted)
            }
            // Everything at once, every reciter: so nobody has to delete the app to get the space back.
            if bytes > 0 {
                Button(role: .destructive) {
                    confirmingRemoval = true
                } label: {
                    Text("Remove all downloads (\(bytes.formatted(.byteCount(style: .file).locale(.app))))")
                }
                .confirmationDialog("Remove all downloads?", isPresented: $confirmingRemoval, titleVisibility: .visible) {
                    Button("Remove", role: .destructive) { downloads.removeAll() }
                    Button("Cancel", role: .cancel) {}
                } message: {
                    Text("Every recitation downloaded on this iPhone, by every reciter, is removed. You can download them again anytime.")
                }
            }
        } header: {
            Text("Offline recitation")
        } footer: {
            if downloads.current != nil {
                Text("Keep the app open while it downloads: the screen stays on until it's done.")
            } else {
                Text("Downloads stay in the app until you remove them, and play without internet.")
            }
        }
        .listRowBackground(Theme.card)
        // On opening, when files come or go, and for another reciter.
        .task(id: "\(reciterID) \(downloads.changes) \(downloads.current == nil)") {
            wholeDownloaded = RecitationDownloads.isDownloaded(whole.verses, by: reciter)
            bytes = RecitationDownloads.totalBytes()
        }
    }
}

/// Go to a page by its number, or by sliding through the mushaf with the surah and juz of each page shown.
struct GoToPageView: View {
    let open: (Int) -> Void
    @State private var target: Int
    @State private var typed = ""
    @Environment(\.dismiss) private var dismiss

    init(page: Int, open: @escaping (Int) -> Void) {
        self.open = open
        _target = State(initialValue: page)
    }

    var body: some View {
        let quran = Quran.shared
        let first = quran.verses(onPage: target).first
        NavigationStack {
            VStack(spacing: 18) {
                Text(verbatim: Formats.number(target))
                    .font(.system(size: 56, weight: .medium, design: .serif).monospacedDigit())
                    .foregroundStyle(Theme.ink)
                    .contentTransition(.numericText())
                    .accessibilityHidden(true)
                if let first {
                    HStack(spacing: 0) {
                        Text(verbatim: Quran.title(of: quran.surahs[first.surah - 1]) + " · ")
                        Text("Juz \(quran.juz(ofVerse: first.index))")
                    }
                    .font(.subheadline)
                    .foregroundStyle(Theme.muted)
                }
                HStack(spacing: 14) {
                    Button { change(to: target - 1) } label: {
                        Image(systemName: "minus")
                            .frame(width: 44, height: 44)
                    }
                    .accessibilityLabel(Text("Previous page"))
                    .disabled(target <= 1)
                    Slider(value: Binding(get: { Double(target) }, set: { change(to: Int($0.rounded())) }),
                           in: 1...Double(Quran.pageCount), step: 1)
                        .tint(Theme.gold)
                        .accessibilityLabel(Text("Page"))
                        .accessibilityValue(Text(verbatim: Formats.number(target)))
                    Button { change(to: target + 1) } label: {
                        Image(systemName: "plus")
                            .frame(width: 44, height: 44)
                    }
                    .accessibilityLabel(Text("Next page"))
                    .disabled(target >= Quran.pageCount)
                }
                .foregroundStyle(Theme.gold)
                TextField("Page number", text: $typed)
                    .keyboardType(.numberPad)
                    .multilineTextAlignment(.center)
                    .padding(.vertical, 10)
                    .background(Theme.card, in: RoundedRectangle(cornerRadius: 10))
                    .frame(maxWidth: 220)
                    .accessibilityIdentifier("pageField")
                    .onChange(of: typed) {
                        if let number = Self.page(from: typed) { target = number }
                    }
            }
            .padding(24)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .background(Theme.background.ignoresSafeArea())
            .navigationTitle("Go to page")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Open") { open(target) }
                        .accessibilityIdentifier("openPage")
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    private func change(to page: Int) {
        target = min(max(page, 1), Quran.pageCount)
        typed = ""
    }

    /// The page typed, in any script's digits (an Arabic keypad types ١٢٣, which Int() can't read), if there is one.
    static func page(from typed: String) -> Int? {
        let digits = typed.compactMap(\.wholeNumberValue)
        guard (1...3).contains(digits.count) else { return nil }
        let number = digits.reduce(0) { $0 * 10 + $1 }
        return (1...Quran.pageCount).contains(number) ? number : nil
    }
}
