import SwiftUI

/// Downloads the recitation of the surah or juz on the page, or of the whole Qur'an, to listen without internet. The
/// files stay inside the app until they are removed here.
struct OfflineRecitationView: View {
    let page: Int
    @AppStorage("reciter") private var reciterID = Reciter.all[0].id
    @Environment(\.dismiss) private var dismiss
    /// Which parts are downloaded already, and the space the downloads take; worked out on opening and after a download.
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
        NavigationStack {
            List {
                Section {
                    ForEach(parts(by: reciter), id: \.id) { part in
                        row(part, reciter: reciter, downloads: downloads)
                    }
                } header: {
                    Text(verbatim: reciter.displayName)
                } footer: {
                    Text("Downloads stay in the app until you remove them, and play without internet.")
                }
                .listRowBackground(Theme.card)
                if downloads.missing > 0 {
                    Text("Some verses couldn't be downloaded. Download again to finish.")
                        .foregroundStyle(Theme.muted)
                        .listRowBackground(Theme.card)
                }
                if bytes > 0 {
                    Section {
                        Button(role: .destructive) {
                            downloads.remove(reciter)
                            refresh(reciter)
                        } label: {
                            Text("Remove downloads (\(bytes.formatted(.byteCount(style: .file).locale(.app))))")
                        }
                    }
                    .listRowBackground(Theme.card)
                }
            }
            .scrollContentBackground(.hidden)
            .background(Theme.background.ignoresSafeArea())
            .navigationTitle("Offline recitation")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            // On opening, and each time a download ends.
            .task(id: downloads.current == nil) { refresh(reciter) }
        }
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
                    .labelStyle(.titleAndIcon)
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
        .accessibilityElement(children: .combine)
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
