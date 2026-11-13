import SwiftUI
import WebKit

/// The Masjid al-Haram live, from the Saudi Quran TV channel on YouTube (the Saudi Broadcasting Authority). The
/// player is YouTube's own, embedded by channel, so it always shows the stream that is on now.
struct MakkahLiveView: View {
    /// Saudi Quran TV, youtube.com/@SaudiQuranTv.
    static let channel = "UCos52azQNBgW63_9uDJoPDA"

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            YouTubeLivePlayer(channel: Self.channel)
                .aspectRatio(16 / 9, contentMode: .fit)
                .background(Color.black)
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .accessibilityLabel(Text("Makkah live"))
            Text("Live from the Masjid al-Haram, on the Saudi Quran TV channel on YouTube.")
                .foregroundStyle(Theme.ink)
            Text("The stream comes from YouTube, which receives your IP address while you watch, under Google's own privacy policy.")
                .font(.footnote)
                .foregroundStyle(Theme.muted)
            Spacer()
        }
        .padding(16)
        .background(Theme.background.ignoresSafeArea())
        .navigationTitle("Makkah live")
        .navigationBarTitleDisplayMode(.inline)
    }
}

/// YouTube's embedded player for a channel's live stream, in a web view with no other pages to go to.
private struct YouTubeLivePlayer: UIViewRepresentable {
    let channel: String

    func makeUIView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.allowsInlineMediaPlayback = true
        configuration.mediaTypesRequiringUserActionForPlayback = []
        let view = WKWebView(frame: .zero, configuration: configuration)
        view.isOpaque = false
        view.backgroundColor = .black
        view.scrollView.isScrollEnabled = false
        // YouTube's player wants to know which site embeds it: the app's own, qibla.dev.
        let html = """
        <!doctype html><html><head><meta name="viewport" content="width=device-width,initial-scale=1">
        <style>html,body{margin:0;height:100%;background:#000}iframe{border:0;width:100%;height:100%}</style></head>
        <body><iframe src="https://www.youtube-nocookie.com/embed/live_stream?channel=\(channel)&autoplay=1&playsinline=1"
        allow="autoplay; encrypted-media; picture-in-picture; fullscreen" allowfullscreen
        referrerpolicy="strict-origin-when-cross-origin"></iframe></body></html>
        """
        view.loadHTMLString(html, baseURL: URL(string: "https://qibla.dev"))
        return view
    }

    func updateUIView(_ view: WKWebView, context: Context) {}
}
