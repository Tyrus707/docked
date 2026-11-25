import AVFoundation

// A game's theme: a file the player chose, kept short and small on this Mac, and played quietly while the game is chosen. Nothing is loaded or running otherwise.
let soundTypes: Set<String> = ["mp3", "m4a", "aac", "wav", "aif", "aiff", "caf", "flac", "mp4"]
enum Theme {
    static let longest = 90.0
    static func file(_ g: Game) -> URL { Paths.root.appendingPathComponent("Themes/" + g.titleID.replacingOccurrences(of: ":", with: "-").replacingOccurrences(of: "/", with: "-") + ".m4a") }
    static func has(_ g: Game) -> Bool { FileManager.default.fileExists(atPath: file(g).path) }
    static func remove(_ g: Game) { try? FileManager.default.removeItem(at: file(g)) }
    // The first 90 seconds, as a small file of its own. The player's file is only read. Swapped in whole, so a failure leaves the old theme.
    static func keep(_ from: URL, for g: Game, _ done: @escaping (String?) -> Void) {
        let fm = FileManager.default, to = file(g), tmp = to.deletingLastPathComponent().appendingPathComponent(".\(UUID().uuidString).m4a")
        func end(_ e: String?) { DispatchQueue.main.async { try? fm.removeItem(at: tmp); done(e) } }
        guard let n = (try? from.resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey])), n.isRegularFile == true, (n.fileSize ?? 0) < 500_000_000 else { return end("That file couldn't be used.") }
        try? fm.createDirectory(at: to.deletingLastPathComponent(), withIntermediateDirectories: true)
        Task {
            let a = AVURLAsset(url: from)
            guard let tracks = try? await a.loadTracks(withMediaType: .audio), !tracks.isEmpty, let d = try? await a.load(.duration), d.seconds.isFinite, d.seconds >= 1, let x = AVAssetExportSession(asset: a, presetName: AVAssetExportPresetAppleM4A) else { return end("That file has no sound Docked can play. Use MP3, M4A, WAV, AIFF or FLAC.") }
            x.outputURL = tmp; x.outputFileType = .m4a; x.timeRange = CMTimeRange(start: .zero, duration: CMTime(seconds: min(d.seconds, longest), preferredTimescale: 600)); x.metadata = []; x.metadataItemFilter = .forSharing()
            await x.export()
            guard x.status == .completed, (try? AVAudioPlayer(contentsOf: tmp)) != nil else { return end("That file couldn't be used.") }
            if fm.fileExists(atPath: to.path) { guard (try? fm.replaceItemAt(to, withItemAt: tmp)) != nil else { return end("The theme couldn't be saved.") } } else { guard (try? fm.moveItem(at: tmp, to: to)) != nil else { return end("The theme couldn't be saved.") } }
            end(nil)
        }
    }
}
final class ThemePlayer {
    private(set) var player: AVAudioPlayer?, playing: String?
    private var waiting: DispatchWorkItem?
    var level: Float = 0.45
    // A moment after a game is chosen, so moving quickly past games stays quiet
    func play(_ g: Game?, on: Bool, delay: Double = 0.35) {
        waiting?.cancel(); waiting = nil
        guard on, let g, Theme.has(g) else { stop(); return }
        if playing == g.id, player != nil { return }
        stop()
        let w = DispatchWorkItem { [weak self] in
            guard let s = self, let p = try? AVAudioPlayer(contentsOf: Theme.file(g)) else { return }
            p.numberOfLoops = -1; p.volume = 0; guard p.play() else { return }; p.setVolume(s.level, fadeDuration: 0.9); s.player = p; s.playing = g.id
        }
        waiting = w; DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: w)
    }
    func stop(_ fade: Double = 0.5) {
        waiting?.cancel(); waiting = nil; guard let p = player else { return }; player = nil; playing = nil
        p.setVolume(0, fadeDuration: fade); DispatchQueue.main.asyncAfter(deadline: .now() + fade + 0.05) { p.stop() }
    }
}
