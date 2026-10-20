import SwiftUI
import UIKit

@MainActor
final class MusicModel: ObservableObject {
    let service = CatalogueService()
    @Published var library = LocalLibrary.load()
    @Published var queue: [MusicItem] = []
    @Published var index = 0
    @Published var playing = false
    @Published var loading = false
    @Published var position = 0.0
    @Published var duration = 0.0
    @Published var playbackError: String?
    @Published var showPlayer = false
    @Published var repeatMode = 0 // off, queue, song
    @Published var shuffle = false
    private var activeDeck = 0
    private var prepared: (id: String, deck: Int)?
    private var generation = 0
    private var loadTask: Task<Void, Never>?
    private var preloadTask: Task<Void, Never>?
    private var audio: AudioManager!
    var current: MusicItem? { queue.indices.contains(index) ? queue[index] : nil }
    var fixture: Bool {
        #if DEBUG
        return ProcessInfo.processInfo.arguments.contains("--fixture")
        #else
        return false
        #endif
    }

    init() {
        audio = AudioManager { [weak self] event in self?.receive(event) }
        service.audio = audio
        audio.onNext = { [weak self] in self?.next() }
        audio.onPrevious = { [weak self] in self?.previous() }
        service.onTermination = { [weak self] in
            // AVPlayer continues playing even when the catalogue process restarts.
            self?.prepared = nil
            self?.preloadTask?.cancel()
            if self?.loading == true { self?.playbackError = "The music engine restarted. Tap Retry to continue."; self?.loading = false }
        }
    }
    func start() { service.start() }

    func fetch<T: Decodable>(_ method: String, _ params: [String: Any] = [:], as type: T.Type = T.self) async throws -> T {
        if fixture, let data = FixtureCatalogue.response(method, params) { return try JSONDecoder().decode(type, from: data) }
        return try await service.request(method, params, as: type)
    }

    func favorite(_ item: MusicItem) -> Bool { library.favorites.contains { $0.id == item.id } }
    func toggleFavorite(_ item: MusicItem) {
        if favorite(item) { library.favorites.removeAll { $0.id == item.id } }
        else { library.favorites.insert(item, at: 0) }
        library.save(); UISelectionFeedbackGenerator().selectionChanged()
    }
    func play(_ items: [MusicItem], at item: MusicItem) {
        let playable = items.filter(\.playable)
        guard let position = playable.firstIndex(where: { $0.id == item.id }) else { return }
        queue = playable; index = position; selectCurrent()
    }
    func addToQueue(_ item: MusicItem) {
        if current == nil { play([item], at: item) }
        else { queue.append(item); if index == queue.count - 2 { prefetchNext() } }
    }
    func select(_ queueIndex: Int) {
        guard queue.indices.contains(queueIndex) else { return }
        index = queueIndex; selectCurrent()
    }
    private func selectCurrent() {
        guard let item = current else { return }
        generation += 1
        let token = generation
        loadTask?.cancel(); preloadTask?.cancel()
        command("audio.pause", deck: activeDeck)
        loading = true; playing = false; position = 0; duration = item.durationSec ?? 0; playbackError = nil
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        if fixture { loading = false; playing = true; remember(item); return }
        if let prepared, prepared.id == item.id {
            self.prepared = nil
            activate(item, deck: prepared.deck)
            return
        }
        prepared = nil
        let deck = 1 - activeDeck
        loadTask = Task { [weak self] in
            guard let self else { return }
            let background = UIApplication.shared.beginBackgroundTask(withName: "Resolve song", expirationHandler: nil)
            defer { if background != .invalid { UIApplication.shared.endBackgroundTask(background) } }
            do {
                // Invalidate pending preloads before reusing a deck.
                let _: EmptyResponse = try await service.request("cancel", ["deck": deck])
                guard generation == token else { return }
                let _: EmptyResponse = try await service.request("resolve", ["id": item.id, "deck": deck])
                guard generation == token, !Task.isCancelled else { return }
                activate(item, deck: deck)
            } catch {
                guard generation == token, !Task.isCancelled else { return }
                loading = false; playbackError = error.localizedDescription
            }
        }
    }
    private func activate(_ item: MusicItem, deck: Int) {
        activeDeck = deck
        command("audio.metadata", extra: ["title": item.title, "artist": item.artist, "artwork": item.thumbnail ?? ""])
        command("audio.play", deck: deck)
        loading = false; playing = true
        remember(item)
        prefetchNext()
    }
    private func remember(_ item: MusicItem) {
        library.recent.removeAll { $0.id == item.id }
        library.recent.insert(item, at: 0)
        library.recent = Array(library.recent.prefix(100))
        library.save()
    }
    private func prefetchNext() {
        guard !fixture, let upcoming = nextIndex else { return }
        let item = queue[upcoming], deck = 1 - activeDeck, token = generation
        preloadTask = Task { [weak self] in
            guard let self else { return }
            let background = UIApplication.shared.beginBackgroundTask(withName: "Prepare next song", expirationHandler: nil)
            defer { if background != .invalid { UIApplication.shared.endBackgroundTask(background) } }
            do {
                let _: EmptyResponse = try await service.request("resolve", ["id": item.id, "deck": deck])
                guard generation == token, !Task.isCancelled else { return }
                prepared = (item.id, deck)
            } catch { /* Current playback is independent of prefetch failures. */ }
        }
    }
    private var nextIndex: Int? {
        guard !queue.isEmpty else { return nil }
        if index + 1 < queue.count { return index + 1 }
        return repeatMode == 1 ? 0 : nil
    }
    func next() {
        guard let upcoming = nextIndex else { playing = false; command("audio.pause", deck: activeDeck); return }
        index = upcoming; selectCurrent()
    }
    func previous() {
        if position > 3 { seek(0) }
        else if index > 0 { index -= 1; selectCurrent() }
        else { seek(0) }
    }
    func togglePlayback() {
        if playbackError != nil { selectCurrent(); return }
        guard current != nil, !loading else { return }
        if !playing, duration > 0, position >= duration - 0.3 { seek(0) }
        let shouldPlay = !playing
        command(shouldPlay ? "audio.play" : "audio.pause", deck: activeDeck)
        playing = shouldPlay
    }
    func seek(_ seconds: Double) { position = max(0, seconds); command("audio.seek", deck: activeDeck, extra: ["seconds": position]) }
    func toggleShuffle() {
        shuffle.toggle()
        if shuffle, index + 1 < queue.count { queue.replaceSubrange((index + 1)..., with: queue[(index + 1)...].shuffled()) }
        preloadTask?.cancel(); prepared = nil; prefetchNext()
    }
    func toggleRepeat() { repeatMode = (repeatMode + 1) % 3; preloadTask?.cancel(); prepared = nil; prefetchNext() }
    private func command(_ method: String, deck: Int = 0, extra: [String: Any] = [:]) {
        var params = extra; params["id"] = deck
        if !fixture { audio.handle(method, params: params) { _, _ in } }
    }
    private func receive(_ event: [String: Any]) {
        guard event["id"] as? Int == activeDeck else { return }
        position = event["position"] as? Double ?? position
        let length = event["duration"] as? Double ?? 0
        if length > 0 { duration = length }
        let name = event["event"] as? String
        if name == "playing" || name == "play" { playing = true; loading = false }
        if name == "pause" { playing = false }
        if name == "error" { playing = false; loading = false; playbackError = event["error"] as? String ?? "Playback stopped. Please try again." }
        if name == "ended" {
            if repeatMode == 2 { seek(0); command("audio.play", deck: activeDeck) }
            else { next() }
        }
    }
}

// Deterministic UI-test data, never selected by normal launches or Release builds.
enum FixtureCatalogue {
    static let items = [
        MusicItem(id: "test-night", title: "Night Drive", subtitle: "The Midnight", durationSec: 240),
        MusicItem(id: "test-blue", title: "Blue Horizon", subtitle: "Daydream", durationSec: 185),
        MusicItem(id: "test-light", title: "First Light", subtitle: "Coastal", durationSec: 216)
    ]
    static func response(_ method: String, _ params: [String: Any]) -> Data? {
        let encoded = try! JSONEncoder().encode(items)
        let rows = try! JSONSerialization.jsonObject(with: encoded)
        let shelf: [String: Any] = ["title": "Made for your day", "layout": "square", "items": rows]
        let object: Any
        switch method {
        case "home": object = ["data": [shelf]]
        case "explore": object = [shelf]
        case "search": object = ["top": rows, "songs": rows, "artists": [], "albums": [], "playlists": [], "videos": []]
        default: return nil
        }
        return try? JSONSerialization.data(withJSONObject: object)
    }
}
