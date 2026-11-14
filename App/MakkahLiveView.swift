import SwiftUI
import WebKit

/// The Masjid al-Haram live, from the Saudi Quran TV channel on YouTube (the Saudi Broadcasting Authority), in YouTube's
/// own player.
struct MakkahLiveView: View {
    /// The channel's 24-hour Makkah stream (youtube.com/@SaudiQuranTv). YouTube's "this channel's live stream" embed says
    /// "video unavailable" for this channel, so the player needs the stream's own ID. qibla.dev/live.json names the
    /// current one, so a new stream needs no app update; this one is used when the site can't be reached.
    static let stream = "IsJTAdC3-Jw"
    @State private var video: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Group {
                if let video {
                    YouTubeLivePlayer(video: video)
                } else {
                    ProgressView()
                        .tint(.white)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
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
        .task { video = await Self.currentStream() }
    }

    /// The stream qibla.dev/live.json names, or the built-in one.
    static func currentStream() async -> String {
        struct Live: Decodable { let makkah: String }
        let request = URLRequest(url: URL(string: "https://qibla.dev/live.json")!,
                                 cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 5)
        // Checked before it goes into the player's page: a YouTube ID is 11 letters, digits, - or _.
        guard let data = try? await URLSession.shared.data(for: request).0,
              let id = try? JSONDecoder().decode(Live.self, from: data).makkah,
              id.range(of: "^[A-Za-z0-9_-]{11}$", options: .regularExpression) != nil else { return stream }
        return id
    }
}

/// YouTube's embedded player for one live stream, in a web view with no other pages to go to.
private struct YouTubeLivePlayer: UIViewRepresentable {
    let video: String

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
        <body><iframe src="https://www.youtube-nocookie.com/embed/\(video)?autoplay=1&playsinline=1"
        allow="autoplay; encrypted-media; picture-in-picture; fullscreen" allowfullscreen
        referrerpolicy="strict-origin-when-cross-origin"></iframe></body></html>
        """
        view.loadHTMLString(html, baseURL: URL(string: "https://qibla.dev"))
        return view
    }

    func updateUIView(_ view: WKWebView, context: Context) {}
}
