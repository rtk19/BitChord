import Foundation

struct ArtistCredit: Codable, Hashable { let name: String; let id: String? }

struct MusicItem: Codable, Hashable, Identifiable {
    let id: String
    let kind: String
    let title: String
    let subtitle: String
    let thumbnail: String?
    let durationSec: Double?
    let artists: [ArtistCredit]
    var playable: Bool { ["song", "video", "episode"].contains(kind) }
    var artist: String { artists.isEmpty ? subtitle : artists.map(\.name).joined(separator: ", ") }
    init(id: String, kind: String = "song", title: String, subtitle: String = "", thumbnail: String? = nil, durationSec: Double? = nil, artists: [ArtistCredit] = []) {
        self.id = id; self.kind = kind; self.title = title; self.subtitle = subtitle
        self.thumbnail = thumbnail; self.durationSec = durationSec; self.artists = artists
    }
    enum CodingKeys: String, CodingKey { case id, videoId, kind, title, subtitle, thumbnail, durationSec, artists }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(String.self, forKey: .id) ?? c.decode(String.self, forKey: .videoId)
        kind = try c.decodeIfPresent(String.self, forKey: .kind) ?? "song"
        title = try c.decode(String.self, forKey: .title)
        subtitle = try c.decodeIfPresent(String.self, forKey: .subtitle) ?? ""
        thumbnail = try c.decodeIfPresent(String.self, forKey: .thumbnail)
        durationSec = try c.decodeIfPresent(Double.self, forKey: .durationSec)
        artists = try c.decodeIfPresent([ArtistCredit].self, forKey: .artists) ?? []
    }
    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id); try c.encode(kind, forKey: .kind)
        try c.encode(title, forKey: .title); try c.encode(subtitle, forKey: .subtitle)
        try c.encodeIfPresent(thumbnail, forKey: .thumbnail); try c.encodeIfPresent(durationSec, forKey: .durationSec)
        try c.encode(artists, forKey: .artists)
    }
}
struct BrowseLink: Decodable { let browseId: String; let params: String? }
struct MusicShelf: Decodable {
    let title: String; let strapline: String?; let layout: String
    let items: [MusicItem]; let seeAll: BrowseLink?
}
struct CataloguePage: Decodable {
    var title: String?; var name: String?; var subtitle: String?; var description: String?
    var thumbnail: String?; var heroImage: String?
    var tracks: [MusicItem]?; var topSongs: [MusicItem]?; var shelves: [MusicShelf]?
    var more: [MusicShelf]?; var grid: [MusicItem]?; var cursor: String?
}
struct PagedItems<T: Decodable>: Decodable { let data: [T]; let cursor: String? }
struct SearchResults: Decodable {
    let top: [MusicItem]; let songs: [MusicItem]; let artists: [MusicItem]
    let albums: [MusicItem]; let playlists: [MusicItem]; let videos: [MusicItem]
    var groups: [(String, [MusicItem])] { [("Top results", top), ("Songs", songs), ("Artists", artists), ("Albums", albums), ("Playlists", playlists), ("Videos", videos)].filter { !$0.1.isEmpty } }
}
struct EmptyResponse: Decodable {}
struct LocalLibrary: Codable {
    var favorites: [MusicItem] = []
    var recent: [MusicItem] = []
    static let key = "bitchord.native.library.v1"
    static func load() -> LocalLibrary {
        guard let data = UserDefaults.standard.data(forKey: key), let library = try? JSONDecoder().decode(Self.self, from: data) else { return Self() }
        return library
    }
    func save() { if let data = try? JSONEncoder().encode(self) { UserDefaults.standard.set(data, forKey: Self.key) } }
}
