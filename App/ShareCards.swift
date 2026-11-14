import SwiftUI
import UIKit
import UniformTypeIdentifiers

/// An image to share, drawn only when it is shared (not each time the screen is drawn).
struct CardImage: Transferable {
    let render: @MainActor @Sendable () -> UIImage?

    static var transferRepresentation: some TransferRepresentation {
        DataRepresentation(exportedContentType: .png) { card in
            await MainActor.run { card.render()?.pngData() } ?? Data()
        }
    }

    /// A SwiftUI card as a picture, three pixels to the point.
    @MainActor
    static func picture(of view: some View) -> UIImage? {
        let renderer = ImageRenderer(content: view)
        renderer.scale = 3
        return renderer.uiImage
    }
}

/// A verse on the mushaf's paper in its frame, with the surah and number under it, to share as an image.
struct VerseCard: View {
    let verse: Quran.Verse

    var body: some View {
        let style = MushafStyle.printed
        let surah = Quran.shared.surahs[verse.surah - 1]
        VStack(spacing: 18) {
            EightPointStar()
                .fill(style.ornament)
                .frame(width: 16, height: 16)
            Text(verbatim: verse.text + " \u{06DD}" + Quran.arabicDigits(verse.number))
                .font(Quran.font(size: 28))
                .foregroundStyle(style.ink)
                .multilineTextAlignment(.center)
                .lineSpacing(6)
                .environment(\.layoutDirection, .rightToLeft)
            Text(verbatim: "سورة \(surah.name) · \(Quran.title(of: surah)) \(verse.surah):\(verse.number)")
                .font(.system(size: 14, weight: .medium, design: .serif))
                .foregroundStyle(style.accent)
            Text(verbatim: "Wajh: Qibla & Prayer Times")
                .font(.system(size: 10))
                .foregroundStyle(style.muted)
        }
        .padding(.horizontal, 34)
        .padding(.vertical, 36)
        .frame(width: 400)
        .background(style.paper)
        .overlay { MushafFrame(style: style).padding(12) }
    }
}

/// Today's prayer times in the app's colours, to share as an image.
struct TimesCard: View {
    let hijri: String
    let placeAndDate: String
    /// Name and time of each.
    let times: [(String, String)]

    var body: some View {
        VStack(spacing: 6) {
            EightPointStar()
                .stroke(Theme.gold.opacity(0.7), lineWidth: 1.2)
                .frame(width: 28, height: 28)
                .padding(.bottom, 6)
            Text(verbatim: hijri)
                .font(.footnote.weight(.medium))
                .foregroundStyle(Theme.gold)
            Text(verbatim: placeAndDate)
                .font(.subheadline)
                .foregroundStyle(Theme.muted)
                .padding(.bottom, 14)
            VStack(spacing: 0) {
                ForEach(times.indices, id: \.self) { index in
                    HStack {
                        Text(verbatim: times[index].0)
                            .font(.system(.title3, design: .serif).weight(.medium))
                        Spacer()
                        Text(verbatim: times[index].1)
                            .font(.title3.monospacedDigit())
                    }
                    .foregroundStyle(Theme.ink)
                    .padding(.vertical, 10)
                    .overlay(alignment: .top) { Theme.line.frame(height: 1) }
                }
            }
            Text(verbatim: "Wajh: Qibla & Prayer Times")
                .font(.caption2)
                .foregroundStyle(Theme.muted)
                .padding(.top, 14)
        }
        .padding(28)
        .frame(width: 380)
        .background(Theme.background)
    }
}

/// A way to the pager's page on screen, to share it as it is shown.
final class PagerHandle {
    weak var controller: UIPageViewController?

    @MainActor
    func snapshot() -> UIImage? {
        guard let view = controller?.viewControllers?.first?.view, view.bounds.width > 0 else { return nil }
        return UIGraphicsImageRenderer(bounds: view.bounds).image { _ in
            view.drawHierarchy(in: view.bounds, afterScreenUpdates: false)
        }
    }
}
