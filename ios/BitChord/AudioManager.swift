import AVFoundation
import MediaPlayer
import UIKit

final class AudioManager {
    typealias Reply = (Any?, String?) -> Void
    private var decks: [Int: AudioDeck] = [:]
    private var activeID: Int?
    private let emit: ([String: Any]) -> Void
    private var metadata: [String: Any] = [:]
    private var artworkAddress: String?
    private var interrupted = false

    init(emit: @escaping ([String: Any]) -> Void) {
        self.emit = emit
        let commands = MPRemoteCommandCenter.shared()
        commands.playCommand.addTarget { [weak self] _ in
            DispatchQueue.main.async { self?.active?.play() }; return .success
        }
        commands.pauseCommand.addTarget { [weak self] _ in
            DispatchQueue.main.async { self?.active?.pause() }; return .success
        }
        commands.togglePlayPauseCommand.addTarget { [weak self] _ in
            DispatchQueue.main.async {
                guard let deck = self?.active else { return }
                deck.player.rate == 0 ? deck.play() : deck.pause()
            }
            return .success
        }
        commands.changePlaybackPositionCommand.addTarget { [weak self] event in
            guard let seek = event as? MPChangePlaybackPositionCommandEvent else { return .commandFailed }
            DispatchQueue.main.async { self?.active?.seek(seek.positionTime) }; return .success
        }
        // Queue resolution still lives in the shared UI. Do not expose remote
        // next/previous until the background queue is owned by the native host.
        commands.nextTrackCommand.isEnabled = false
        commands.previousTrackCommand.isEnabled = false
        NotificationCenter.default.addObserver(self, selector: #selector(interruption), name: AVAudioSession.interruptionNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(routeChanged), name: AVAudioSession.routeChangeNotification, object: nil)
    }

    private var active: AudioDeck? { activeID.flatMap { decks[$0] } }

    func refresh() { decks.values.forEach { $0.send("timeupdate") } }

    private func deck(_ id: Int) -> AudioDeck {
        if let existing = decks[id] { return existing }
        let result = AudioDeck(id: id) { [weak self] state in
            self?.emit(state)
            if self?.activeID == id { self?.updateNowPlaying() }
        }
        decks[id] = result
        return result
    }

    func handle(_ method: String, params: [String: Any], reply: @escaping Reply) {
        if method == "audio.metadata" { setMetadata(params); reply([:], nil); return }
        guard let id = params["id"] as? Int, (0...1).contains(id) else { reply(nil, "Invalid audio deck"); return }
        let deck = deck(id)
        switch method {
        case "audio.load":
            guard let address = params["url"] as? String, let url = URL(string: address), url.scheme == "https",
                  let host = url.host, host.hasSuffix(".googlevideo.com") else { reply(nil, "Invalid media URL"); return }
            do {
                try AVAudioSession.sharedInstance().setCategory(.playback, mode: .default, options: [.allowAirPlay])
                try AVAudioSession.sharedInstance().setActive(true)
            } catch { reply(nil, error.localizedDescription); return }
            let autoplay = params["autoplay"] as? Bool ?? true
            if autoplay { activeID = id; setMetadata(params) }
            deck.load(url, start: params["startSec"] as? Double ?? 0, autoplay: autoplay, reply: reply)
            return
        case "audio.play": activeID = id; deck.play()
        case "audio.pause": deck.pause()
        case "audio.stop": deck.stop()
        case "audio.seek": deck.seek(params["seconds"] as? Double ?? 0)
        case "audio.rate": deck.rate = Float(params["rate"] as? Double ?? 1); if deck.player.rate != 0 { deck.play() }
        case "audio.volume": deck.player.volume = Float(max(0, min(1, params["volume"] as? Double ?? 1)))
        default: reply(nil, "Unsupported native method: \(method)"); return
        }
        reply([:], nil)
    }

    private func setMetadata(_ params: [String: Any]) {
        metadata[MPMediaItemPropertyTitle] = params["title"] as? String ?? "BitChord"
        metadata[MPMediaItemPropertyArtist] = params["artist"] as? String ?? ""
        let address = params["artwork"] as? String
        if address != artworkAddress {
            artworkAddress = address
            metadata.removeValue(forKey: MPMediaItemPropertyArtwork)
            if let address, let url = URL(string: address), url.scheme == "https" {
                URLSession.shared.dataTask(with: url) { [weak self] data, _, _ in
                    guard let data, let image = UIImage(data: data) else { return }
                    DispatchQueue.main.async {
                        guard self?.artworkAddress == address else { return }
                        self?.metadata[MPMediaItemPropertyArtwork] = MPMediaItemArtwork(boundsSize: image.size) { _ in image }
                        self?.updateNowPlaying()
                    }
                }.resume()
            }
        }
        updateNowPlaying()
    }

    private func updateNowPlaying() {
        guard let active else { return }
        metadata[MPNowPlayingInfoPropertyElapsedPlaybackTime] = active.position
        metadata[MPMediaItemPropertyPlaybackDuration] = active.duration
        metadata[MPNowPlayingInfoPropertyPlaybackRate] = active.player.rate
        MPNowPlayingInfoCenter.default().nowPlayingInfo = metadata
    }

    @objc private func interruption(_ notification: Notification) {
        guard let raw = notification.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt,
              let type = AVAudioSession.InterruptionType(rawValue: raw) else { return }
        if type == .began {
            interrupted = active?.player.rate != 0
            decks.values.forEach { $0.pause() }
        } else {
            let options = AVAudioSession.InterruptionOptions(rawValue: notification.userInfo?[AVAudioSessionInterruptionOptionKey] as? UInt ?? 0)
            if interrupted && options.contains(.shouldResume) {
                try? AVAudioSession.sharedInstance().setActive(true)
                active?.play()
            }
            interrupted = false
        }
    }

    @objc private func routeChanged(_ notification: Notification) {
        if notification.userInfo?[AVAudioSessionRouteChangeReasonKey] as? UInt == AVAudioSession.RouteChangeReason.oldDeviceUnavailable.rawValue {
            decks.values.forEach { $0.pause() }
        }
    }
}

private final class AudioDeck {
    let player = AVPlayer()
    var rate: Float = 1
    private let id: Int
    private let emit: ([String: Any]) -> Void
    private var status: NSKeyValueObservation?
    private var timeControl: NSKeyValueObservation?
    private var timer: Any?
    private var endedObserver: NSObjectProtocol?
    private var pending: AudioManager.Reply?
    private var timeout: DispatchWorkItem?
    private var ended = false
    private var generation = 0

    var position: Double { finite(player.currentTime().seconds) }
    var duration: Double { finite(player.currentItem?.duration.seconds ?? 0) }
    private func finite(_ value: Double) -> Double { value.isFinite ? max(0, value) : 0 }

    init(id: Int, emit: @escaping ([String: Any]) -> Void) {
        self.id = id
        self.emit = emit
        timer = player.addPeriodicTimeObserver(forInterval: CMTime(seconds: 0.25, preferredTimescale: 600), queue: .main) { [weak self] _ in self?.send("timeupdate") }
        timeControl = player.observe(\.timeControlStatus, options: [.new]) { [weak self] player, _ in
            DispatchQueue.main.async {
                let event = player.timeControlStatus == .playing ? "playing" : player.timeControlStatus == .waitingToPlayAtSpecifiedRate ? "waiting" : "pause"
                self?.send(event)
            }
        }
    }

    func send(_ event: String) {
        emit(["id": id, "event": event, "position": position, "duration": duration,
              "paused": player.rate == 0, "ended": ended, "rate": Double(rate)])
    }

    func load(_ url: URL, start: Double, autoplay: Bool, reply: @escaping AudioManager.Reply) {
        stop()
        let token = generation
        pending = reply
        ended = false
        let item = AVPlayerItem(url: url)
        player.replaceCurrentItem(with: item)
        let ready: () -> Void = { [weak self, weak item] in
            guard let self, let item, token == self.generation, self.pending != nil else { return }
            if item.status == .failed {
                self.finish(item.error?.localizedDescription ?? "AVPlayer could not open the stream")
                return
            }
            guard item.status == .readyToPlay else { return }
            self.status = nil
            self.player.seek(to: CMTime(seconds: max(0, start), preferredTimescale: 600)) { [weak self] _ in
                DispatchQueue.main.async {
                    guard let self, token == self.generation, self.pending != nil else { return }
                    self.send("durationchange")
                    self.send("canplay")
                    if autoplay { self.play() }
                    self.finish(nil)
                }
            }
        }
        status = item.observe(\.status, options: [.new]) { _, _ in DispatchQueue.main.async(execute: ready) }
        endedObserver = NotificationCenter.default.addObserver(forName: .AVPlayerItemDidPlayToEndTime, object: item, queue: .main) { [weak self] _ in
            self?.ended = true
            self?.send("ended")
        }
        let timeout = DispatchWorkItem { [weak self] in
            guard let self, token == self.generation, self.pending != nil else { return }
            self.player.pause()
            self.finish("No audio stream became ready within 20 seconds")
        }
        self.timeout = timeout
        DispatchQueue.main.asyncAfter(deadline: .now() + 20, execute: timeout)
        ready()
    }

    private func finish(_ error: String?) {
        timeout?.cancel()
        timeout = nil
        let callback = pending
        pending = nil
        callback?(error == nil ? [:] : nil, error)
    }

    func play() { ended = false; player.playImmediately(atRate: rate); send("play") }
    func pause() { player.pause(); send("pause") }
    func seek(_ seconds: Double) {
        player.seek(to: CMTime(seconds: finite(seconds), preferredTimescale: 600)) { [weak self] _ in
            DispatchQueue.main.async { self?.send("seeked") }
        }
    }
    func stop() {
        generation += 1
        finish("Superseded by another track")
        status = nil
        if let endedObserver { NotificationCenter.default.removeObserver(endedObserver) }
        endedObserver = nil
        player.pause()
        player.replaceCurrentItem(with: nil)
        ended = false
    }
    deinit {
        if let timer { player.removeTimeObserver(timer) }
        if let endedObserver { NotificationCenter.default.removeObserver(endedObserver) }
    }
}
