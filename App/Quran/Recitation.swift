import AVFoundation
import MediaPlayer
import Observation
import SwiftUI

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

    /// Verses downloaded to listen offline, per reciter: Application Support, kept until removed, not backed up.
    static var downloads: URL { URL.applicationSupportDirectory.appending(path: "Recitation", directoryHint: .isDirectory) }

    func downloaded(_ number: Int) -> URL { Self.downloads.appending(path: "\(id)/\(number).mp3") }

    /// Verses played before: Caches, which iOS may clear when it needs space.
    func cached(_ number: Int) -> URL { URL.cachesDirectory.appending(path: "Recitation/\(id)/\(number).mp3") }

    /// About the size of the whole Qur'an by this reciter: some 30 hours of recitation at its bitrate.
    var wholeQuranBytes: Int64 { Int64(bitrate) * 1000 / 8 * 30 * 3600 }
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

    enum SleepTimer: Hashable {
        case off, minutes(Int), endOfSurah
    }

    /// Pauses after a while, or stops at the end of the surah.
    private(set) var sleepTimer = SleepTimer.off
    @ObservationIgnored private var sleepTask: Task<Void, Never>?
    /// The surah the recitation stops after, with the timer at "end of surah".
    @ObservationIgnored private var lastSurah: Int?
    /// No more verses are queued: the recitation stops when the queued ones end.
    @ObservationIgnored private var reachedLastSurah = false

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
        // Recitation is audio: no AirPlay as video to a TV, which made iOS suggest the TV ("Tap to AirPlay").
        // AirPlay speakers can still be picked in Control Center.
        player.allowsExternalPlayback = false
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
                if self.isPlaying { self.pause() } else { self.resume() }
            }
            return .success
        }
    }

    func play(from verse: Int, reciter: Reciter) {
        stop()
        self.reciter = reciter
        self.verse = verse
        next = verse
        if sleepTimer == .endOfSurah { lastSurah = Quran.shared.verses[verse].surah }
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
        // Paused, the app no longer counts as playing (resume() takes the audio session back).
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    func resume() {
        guard verse != nil else { return }
        isPlaying = true
        try? AVAudioSession.sharedInstance().setActive(true)
        player.play()
        load()
    }

    func setSleepTimer(_ timer: SleepTimer) {
        sleepTask?.cancel()
        sleepTask = nil
        sleepTimer = timer
        lastSurah = nil
        reachedLastSurah = false
        // Queue past the end of the surah again if the timer no longer stops there.
        defer { if verse != nil { load() } }
        switch timer {
        case .off:
            break
        case .minutes(let minutes):
            sleepTask = Task {
                try? await Task.sleep(for: .seconds(minutes * 60))
                guard !Task.isCancelled else { return }
                pause()
                sleepTimer = .off
            }
        case .endOfSurah:
            lastSurah = verse.map { Quran.shared.verses[$0].surah }
        }
    }

    func stop() {
        loading?.cancel()
        loading = nil
        reachedLastSurah = false
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
        } else if loading == nil && (next >= Quran.shared.verses.count || reachedLastSurah) {
            // The end of the Qur'an, or of the surah the sleep timer stops after.
            if reachedLastSurah { setSleepTimer(.off) }
            stop()
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
                if sleepTimer == .endOfSurah {
                    if lastSurah == nil { lastSurah = upcoming.surah }
                    if upcoming.surah != lastSurah {
                        reachedLastSurah = true
                        break
                    }
                }
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

    /// The verse's audio: downloaded for offline, played before, or downloaded now into the cache.
    private func file(ofVerse number: Int) async throws -> URL {
        let manager = FileManager.default
        let downloaded = reciter.downloaded(number)
        if manager.fileExists(atPath: downloaded.path(percentEncoded: false)) { return downloaded }
        let file = reciter.cached(number)
        if manager.fileExists(atPath: file.path(percentEncoded: false)) { return file }
        let (download, response) = try await URLSession.shared.download(from: reciter.url(ofVerse: number))
        guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw URLError(.badServerResponse) }
        try manager.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? manager.removeItem(at: file)
        try manager.moveItem(at: download, to: file)
        return file
    }

    /// The reciter of the recitation playing, for the mini player.
    var reciterName: String { reciter.displayName }

    private func showNowPlaying() {
        guard let verse else { return }
        let quran = Quran.shared
        let item = quran.verses[verse]
        MPNowPlayingInfoCenter.default().nowPlayingInfo = [
            MPMediaItemPropertyTitle: "\(Quran.title(of: quran.surahs[item.surah - 1])) \(item.surah):\(item.number)",
            MPMediaItemPropertyArtist: artistLine,
            MPMediaItemPropertyArtwork: Self.artwork,
        ]
    }

    /// The reciter and the next prayer. While the app's recitation plays, iOS shows its player on the Lock Screen and
    /// hides the app's own Live Activity (the next prayer), so the player says when the next prayer is.
    private var artistLine: String {
        guard let saved = SharedStore.saved(),
              let next = Prayers.next(after: .now, place: saved.place, settings: saved.settings) else {
            return reciter.displayName
        }
        let zone = saved.place.timeZone
        return "\(reciter.displayName) · \(next.kind.title(on: next.time, in: zone)) \(Formats.time(next.time, in: zone))"
    }

    /// The app's star in gold on its dark green, as the player's artwork.
    private static let artwork: MPMediaItemArtwork = {
        let size = CGSize(width: 600, height: 600)
        let image = UIGraphicsImageRenderer(size: size).image { context in
            UIColor(Theme.background).setFill()
            context.fill(CGRect(origin: .zero, size: size))
            let star = UIBezierPath(cgPath: EightPointStar().path(in: CGRect(x: 150, y: 150, width: 300, height: 300)).cgPath)
            star.lineWidth = 16
            UIColor(Theme.gold).setStroke()
            star.stroke()
        }
        return MPMediaItemArtwork(boundsSize: size) { _ in image }
    }()
}

/// Recitations downloaded ahead, to listen without internet: a surah, a juz or the whole Qur'an by one reciter. The
/// files stay inside the app until removed there; a verse played before is moved over instead of downloaded again.
@MainActor @Observable
final class RecitationDownloads {
    static let shared = RecitationDownloads()

    /// What is downloading, and how far (0...1); nil when nothing is.
    private(set) var current: (title: String, progress: Double)?
    /// Verses that failed in the last download (no internet); downloading again fetches only those.
    private(set) var missing = 0
    @ObservationIgnored private var task: Task<Void, Never>?

    /// The verse numbers (1...6236) that some verses need, with the basmala if a surah in them begins with it.
    nonisolated static func numbers(for verses: Range<Int>) -> [Int] {
        var numbers = Set(verses.map { $0 + 1 })
        let quran = Quran.shared
        if verses.contains(where: { quran.verses[$0].number == 1 && ![1, 9].contains(quran.verses[$0].surah) }) {
            numbers.insert(1)
        }
        return numbers.sorted()
    }

    nonisolated static func isDownloaded(_ verses: Range<Int>, by reciter: Reciter) -> Bool {
        numbers(for: verses).allSatisfy {
            FileManager.default.fileExists(atPath: reciter.downloaded($0).path(percentEncoded: false))
        }
    }

    /// The space the downloads of a reciter take.
    nonisolated static func bytes(of reciter: Reciter) -> Int64 {
        let folder = Reciter.downloads.appending(path: reciter.id, directoryHint: .isDirectory)
        let files = (try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: [.fileSizeKey])) ?? []
        return files.reduce(0) { $0 + Int64((try? $1.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0) }
    }

    func download(_ verses: Range<Int>, by reciter: Reciter, title: String) {
        cancel()
        let numbers = Self.numbers(for: verses)
        current = (title, 0)
        missing = 0
        task = Task {
            var folder = Reciter.downloads
            try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            var values = URLResourceValues()
            values.isExcludedFromBackup = true
            try? folder.setResourceValues(values)
            var done = 0
            var failed = 0
            // Four at a time.
            await withTaskGroup(of: Bool.self) { group in
                var pending = numbers[...]
                for _ in 0..<4 {
                    guard let number = pending.popFirst() else { break }
                    group.addTask { await Self.fetch(number, by: reciter) }
                }
                while let ok = await group.next() {
                    done += 1
                    if !ok { failed += 1 }
                    if Task.isCancelled { continue }
                    self.current = (title, Double(done) / Double(numbers.count))
                    if let number = pending.popFirst() {
                        group.addTask { await Self.fetch(number, by: reciter) }
                    }
                }
            }
            guard !Task.isCancelled else { return }
            missing = failed
            current = nil
            task = nil
        }
    }

    func cancel() {
        task?.cancel()
        task = nil
        current = nil
    }

    func remove(_ reciter: Reciter) {
        cancel()
        try? FileManager.default.removeItem(at: Reciter.downloads.appending(path: reciter.id, directoryHint: .isDirectory))
    }

    /// One verse, unless it is here already; one played before is copied from the cache.
    nonisolated private static func fetch(_ number: Int, by reciter: Reciter) async -> Bool {
        let manager = FileManager.default
        let target = reciter.downloaded(number)
        if manager.fileExists(atPath: target.path(percentEncoded: false)) { return true }
        do {
            try manager.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
            let cached = reciter.cached(number)
            if manager.fileExists(atPath: cached.path(percentEncoded: false)) {
                try manager.copyItem(at: cached, to: target)
                return true
            }
            let (download, response) = try await URLSession.shared.download(from: reciter.url(ofVerse: number))
            guard (response as? HTTPURLResponse)?.statusCode == 200 else { return false }
            try? manager.removeItem(at: target)
            try manager.moveItem(at: download, to: target)
            return true
        } catch {
            return false
        }
    }
}
