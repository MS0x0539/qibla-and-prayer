import AVFoundation
import MediaPlayer
import Observation

/// A reciter whose recitation comes verse by verse from Islamic Network's audio service (cdn.islamic.network).
/// Its terms allow streaming for personal use; the recitations remain the reciters' copyright.
struct Reciter: Identifiable, Hashable {
    /// The service's name for the recitation.
    let id: String
    let name: String
    let arabicName: String
    /// The best quality the service has for this reciter, in kbps.
    let bitrate: Int

    var displayName: String { Quran.languageCode == "ar" ? arabicName : name }

    /// The audio of a verse, numbered 1 to 6236 through the whole Qur'an.
    func url(ofVerse number: Int) -> URL {
        URL(string: "https://cdn.islamic.network/quran/audio/\(bitrate)/\(id)/\(number).mp3")!
    }

    static let all = [
        Reciter(id: "ar.alafasy", name: "Mishary Rashid Alafasy", arabicName: "مشاري راشد العفاسي", bitrate: 128),
        Reciter(id: "ar.abdulbasitmurattal", name: "Abdul Basit Abdus-Samad", arabicName: "عبد الباسط عبد الصمد", bitrate: 64),
        Reciter(id: "ar.ahmedajamy", name: "Ahmed al-Ajamy", arabicName: "أحمد بن علي العجمي", bitrate: 128),
        Reciter(id: "ar.hudhaify", name: "Ali al-Hudhaify", arabicName: "علي بن عبد الرحمن الحذيفي", bitrate: 128),
        Reciter(id: "ar.husary", name: "Mahmoud Khalil al-Husary", arabicName: "محمود خليل الحصري", bitrate: 128),
        Reciter(id: "ar.mahermuaiqly", name: "Maher al-Muaiqly", arabicName: "ماهر المعيقلي", bitrate: 128),
        Reciter(id: "ar.minshawi", name: "Mohamed Siddiq al-Minshawi", arabicName: "محمد صديق المنشاوي", bitrate: 128),
        Reciter(id: "ar.muhammadayyoub", name: "Muhammad Ayyoub", arabicName: "محمد أيوب", bitrate: 128),
        Reciter(id: "ar.saoodshuraym", name: "Saud ash-Shuraim", arabicName: "سعود الشريم", bitrate: 64),
        Reciter(id: "ar.abdurrahmaansudais", name: "Abdur-Rahman as-Sudais", arabicName: "عبد الرحمن السديس", bitrate: 64),
    ]

    static func named(_ id: String) -> Reciter { all.first { $0.id == id } ?? all[0] }
}

/// Recites from any verse on, page after page. Each verse is downloaded once and kept in Caches (the service asks
/// apps to cache), and the next few wait in the player's queue, so one verse follows the other without a gap.
/// Keeps playing with the screen locked, with play and pause on the Lock Screen.
@MainActor @Observable
final class Recitation {
    static let shared = Recitation()

    /// The verse being recited (its index in the whole Qur'an), nil when stopped.
    private(set) var verse: Int?
    /// Whether it should be playing: true while a verse downloads too, false when paused.
    private(set) var isPlaying = false
    /// Set when the first verse couldn't be downloaded (no internet); the reader says so.
    var failed = false

    private let player = AVQueuePlayer()
    /// What the player has queued, in order, and the verse each item recites (the basmala before a surah counts
    /// as its first verse).
    @ObservationIgnored private var queue: [(item: AVPlayerItem, verse: Int)] = []
    /// The next verse to download and queue.
    @ObservationIgnored private var next = 0
    @ObservationIgnored private var reciter = Reciter.all[0]
    @ObservationIgnored private var loading: Task<Void, Never>?
    @ObservationIgnored private var observation: NSKeyValueObservation?

    private init() {
        observation = player.observe(\.currentItem) { [weak self] _, _ in
            Task { @MainActor in self?.advanced() }
        }
        // A call, or headphones taken out, pauses the player; show it as paused.
        let center = NotificationCenter.default
        center.addObserver(forName: AVAudioSession.interruptionNotification, object: nil, queue: .main) { [weak self] note in
            let type = note.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt
            if type == AVAudioSession.InterruptionType.began.rawValue { Task { @MainActor in self?.pause() } }
        }
        center.addObserver(forName: AVAudioSession.routeChangeNotification, object: nil, queue: .main) { [weak self] note in
            let reason = note.userInfo?[AVAudioSessionRouteChangeReasonKey] as? UInt
            if reason == AVAudioSession.RouteChangeReason.oldDeviceUnavailable.rawValue {
                Task { @MainActor in self?.pause() }
            }
        }
        let commands = MPRemoteCommandCenter.shared()
        commands.playCommand.addTarget { [weak self] _ in
            Task { @MainActor in self?.resume() }
            return .success
        }
        commands.pauseCommand.addTarget { [weak self] _ in
            Task { @MainActor in self?.pause() }
            return .success
        }
        commands.togglePlayPauseCommand.addTarget { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                if isPlaying { pause() } else { resume() }
            }
            return .success
        }
    }

    func play(from verse: Int, reciter: Reciter) {
        stop()
        self.reciter = reciter
        self.verse = verse
        next = verse
        failed = false
        isPlaying = true
        let session = AVAudioSession.sharedInstance()
        try? session.setCategory(.playback, mode: .spokenAudio)
        try? session.setActive(true)
        load()
    }

    func pause() {
        isPlaying = false
        player.pause()
    }

    func resume() {
        guard verse != nil else { return }
        isPlaying = true
        try? AVAudioSession.sharedInstance().setActive(true)
        player.play()
        load()
    }

    func stop() {
        loading?.cancel()
        loading = nil
        isPlaying = false
        verse = nil
        queue = []
        player.removeAllItems()
        MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    /// The player moved on (or ran out while a verse was still downloading): show its verse and queue more.
    private func advanced() {
        while let first = queue.first, first.item !== player.currentItem { queue.removeFirst() }
        guard verse != nil else { return }
        if let first = queue.first {
            verse = first.verse
            showNowPlaying()
        } else if loading == nil && next >= Quran.shared.verses.count {
            stop()  // the end of the Qur'an
            return
        }
        load()
    }

    /// Downloads and queues verses until three are waiting.
    private func load() {
        guard loading == nil, verse != nil else { return }
        loading = Task {
            while queue.count < 3, next < Quran.shared.verses.count {
                let index = next
                let upcoming = Quran.shared.verses[index]
                do {
                    // Every surah but At-Tawbah opens with the basmala, which is Al-Fatiha's first verse.
                    if upcoming.number == 1 && upcoming.surah != 1 && upcoming.surah != 9 {
                        let basmala = try await file(ofVerse: 1)
                        guard !Task.isCancelled else { return }
                        enqueue(basmala, verse: index)
                    }
                    let audio = try await file(ofVerse: index + 1)
                    guard !Task.isCancelled else { return }
                    enqueue(audio, verse: index)
                    next = index + 1
                } catch {
                    guard !Task.isCancelled else { return }
                    loading = nil
                    // Nothing left to play: stop and say so. Otherwise the next try comes when the queue runs low.
                    if queue.isEmpty {
                        stop()
                        failed = true
                    }
                    return
                }
            }
            loading = nil
        }
    }

    private func enqueue(_ file: URL, verse: Int) {
        let item = AVPlayerItem(url: file)
        queue.append((item, verse))
        player.insert(item, after: nil)
        if isPlaying { player.play() }
    }

    /// The verse's audio from the cache, downloaded first if it isn't there yet.
    private func file(ofVerse number: Int) async throws -> URL {
        let folder = URL.cachesDirectory.appending(path: "Recitation/\(reciter.id)", directoryHint: .isDirectory)
        let file = folder.appending(path: "\(number).mp3")
        if FileManager.default.fileExists(atPath: file.path(percentEncoded: false)) { return file }
        let (download, response) = try await URLSession.shared.download(from: reciter.url(ofVerse: number))
        guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw URLError(.badServerResponse) }
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try? FileManager.default.removeItem(at: file)
        try FileManager.default.moveItem(at: download, to: file)
        return file
    }

    private func showNowPlaying() {
        guard let verse else { return }
        let quran = Quran.shared
        let item = quran.verses[verse]
        MPNowPlayingInfoCenter.default().nowPlayingInfo = [
            MPMediaItemPropertyTitle: "\(Quran.title(of: quran.surahs[item.surah - 1])) \(item.surah):\(item.number)",
            MPMediaItemPropertyArtist: reciter.displayName,
        ]
    }
}
