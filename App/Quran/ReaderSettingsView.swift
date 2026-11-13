import SwiftUI

/// The reader's settings in one place instead of a menu: the page (paper or night, text size), the reciter, the sleep
/// timer, and the recitation downloaded to listen offline.
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
        let recitation = Recitation.shared
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
                    ForEach(Reciter.all) { reciter in
                        Button { reciterID = reciter.id } label: {
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
                }
                .listRowBackground(Theme.card)

                Section("Sleep timer") {
                    Picker("Sleep timer", selection: Binding(get: { recitation.sleepTimer },
                                                             set: { recitation.setSleepTimer($0) })) {
                        Text("Off").tag(Recitation.SleepTimer.off)
                        ForEach([15, 30, 60], id: \.self) { minutes in
                            Text("\(minutes) min").tag(Recitation.SleepTimer.minutes(minutes))
                        }
                        Text("End of surah").tag(Recitation.SleepTimer.endOfSurah)
                    }
                    .pickerStyle(.inline)
                    .labelsHidden()
                }
                .listRowBackground(Theme.card)

                OfflineRecitationSection(page: page)
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

/// Downloads the recitation of the surah or juz on the page, or of the whole Qur'an, by the chosen reciter, to listen
/// without internet. The files stay inside the app until they are removed here.
struct OfflineRecitationSection: View {
    let page: Int
    @AppStorage("reciter") private var reciterID = Reciter.all[0].id
    /// Which parts are downloaded, and the space the downloads take; worked out on opening and after a download.
    @State private var downloaded: Set<String> = []
    @State private var bytes: Int64 = 0

    private struct Part {
        let id: String
        let title: String
        let verses: Range<Int>
        var note: String?
    }

    var body: some View {
        let reciter = Reciter.named(reciterID)
        let downloads = RecitationDownloads.shared
        Section {
            ForEach(parts(by: reciter), id: \.id) { part in
                row(part, reciter: reciter, downloads: downloads)
            }
            if downloads.missing > 0 {
                Text("Some verses couldn't be downloaded. Download again to finish.")
                    .foregroundStyle(Theme.muted)
            }
            if bytes > 0 {
                Button(role: .destructive) {
                    downloads.remove(reciter)
                    refresh(reciter)
                } label: {
                    Text("Remove downloads (\(bytes.formatted(.byteCount(style: .file).locale(.app))))")
                }
            }
        } header: {
            Text("Offline recitation")
        } footer: {
            Text("Downloads stay in the app until you remove them, and play without internet.")
        }
        .listRowBackground(Theme.card)
        // On opening, after a download, and for another reciter.
        .task(id: "\(reciterID) \(downloads.current == nil)") { refresh(reciter) }
    }

    private func row(_ part: Part, reciter: Reciter, downloads: RecitationDownloads) -> some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(verbatim: part.title)
                    .foregroundStyle(Theme.ink)
                if let note = part.note {
                    Text(verbatim: note)
                        .font(.subheadline)
                        .foregroundStyle(Theme.muted)
                }
            }
            Spacer()
            if downloaded.contains(part.id) {
                Label("Downloaded", systemImage: "checkmark.circle.fill")
                    .font(.subheadline)
                    .foregroundStyle(Theme.gold)
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
                Button("Download") { downloads.download(part.verses, by: reciter, title: part.title) }
                    .buttonStyle(.bordered)
                    .disabled(downloads.current != nil)
            }
        }
    }

    /// The surah and the juz the page begins with, and the whole Qur'an.
    private func parts(by reciter: Reciter) -> [Part] {
        let quran = Quran.shared
        guard let first = quran.verses(onPage: page).first else { return [] }
        let surah = quran.surahs[first.surah - 1]
        let juz = quran.juz(ofVerse: first.index)
        let juzEnd = juz < quran.juzStarts.count ? quran.juzStarts[juz] : quran.verses.count
        let size = reciter.wholeQuranBytes.formatted(.byteCount(style: .file).locale(.app))
        return [
            Part(id: "surah", title: Quran.title(of: surah), verses: surah.start..<(surah.start + surah.ayahs)),
            Part(id: "juz", title: String(localized: "Juz \(juz)", bundle: .app),
                 verses: quran.juzStarts[juz - 1]..<juzEnd),
            Part(id: "all", title: String(localized: "The whole Qur'an", bundle: .app), verses: 0..<quran.verses.count,
                 note: String(localized: "About \(size)", bundle: .app)),
        ]
    }

    private func refresh(_ reciter: Reciter) {
        downloaded = Set(parts(by: reciter).filter { RecitationDownloads.isDownloaded($0.verses, by: reciter) }.map(\.id))
        bytes = RecitationDownloads.bytes(of: reciter)
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
