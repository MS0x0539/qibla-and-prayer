import SwiftUI

/// While a recitation plays or is paused, at the bottom of every tab but the Qur'an: the verse and the reciter, play or
/// pause, and stop. A tap on the verse opens the Qur'an at its page.
struct MiniPlayer: View {
    @AppStorage(OpenScreenIntent.key) private var openScreen = ""
    @AppStorage("quranPage") private var quranPage = 1

    var body: some View {
        let recitation = Recitation.shared
        if let verse = recitation.verse {
            let quran = Quran.shared
            let item = quran.verses[verse]
            HStack(spacing: 4) {
                Button {
                    quranPage = quran.page(ofVerse: verse)
                    openScreen = AppScreen.quran.rawValue
                } label: {
                    HStack(spacing: 12) {
                        Image(systemName: "book")
                            .foregroundStyle(Theme.gold)
                            .accessibilityHidden(true)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(verbatim: "\(Quran.title(of: quran.surahs[item.surah - 1])) \(item.surah):\(item.number)")
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(Theme.ink)
                            Text(verbatim: recitation.reciterName)
                                .font(.caption)
                                .foregroundStyle(Theme.muted)
                        }
                        .lineLimit(1)
                        Spacer(minLength: 0)
                    }
                    .frame(minHeight: 44)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityHint(Text("Opens the Qur'an at this verse."))
                Button {
                    if recitation.isPlaying { recitation.pause() } else { recitation.resume() }
                } label: {
                    Image(systemName: recitation.isPlaying ? "pause.fill" : "play.fill")
                        .frame(width: 44, height: 44)
                }
                .accessibilityLabel(recitation.isPlaying ? Text("Pause recitation") : Text("Play recitation"))
                Button {
                    recitation.stop()
                } label: {
                    Image(systemName: "xmark")
                        .frame(width: 44, height: 44)
                }
                .accessibilityLabel(Text("Stop recitation"))
            }
            .foregroundStyle(Theme.gold)
            .padding(.leading, 14)
            .padding(.trailing, 4)
            .padding(.vertical, 4)
            .background(Theme.card, in: RoundedRectangle(cornerRadius: 16))
            .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(Theme.line, lineWidth: 1))
            .padding(.horizontal, 12)
            .padding(.bottom, 6)
        }
    }
}
