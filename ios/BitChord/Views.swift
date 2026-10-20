import SwiftUI
import AVKit
import MediaPlayer

private let accent = Color(red: 0.91, green: 0.13, blue: 0.28)

struct RootView: View {
    @EnvironmentObject private var model: MusicModel
    @AppStorage("bitchord.appearance") private var appearance = "system"
    @State private var settings = false
    var body: some View {
        TabView {
            tab("Home", icon: "house.fill") { FeedView(explore: false) }
            tab("New", icon: "sparkles") { FeedView(explore: true) }
            tab("Library", icon: "square.stack.fill") { LibraryView() }
            tab("Search", icon: "magnifyingglass") { SearchView() }
        }
        .tint(accent)
        .preferredColorScheme(appearance == "dark" ? .dark : appearance == "light" ? .light : nil)
        .sheet(isPresented: $model.showPlayer) { PlayerView() }
        .sheet(isPresented: $settings) { SettingsView() }
    }
    private func tab<Content: View>(_ title: String, icon: String, @ViewBuilder content: () -> Content) -> some View {
        NavigationStack {
            content()
                .navigationTitle(title)
                .toolbar { ToolbarItem(placement: .navigationBarTrailing) {
                    Button { settings = true } label: { Image(systemName: "person.crop.circle").font(.title3) }
                        .accessibilityLabel("Settings")
                } }
                .safeAreaInset(edge: .bottom, spacing: 0) {
                    if model.current != nil { MiniPlayer().padding(.horizontal, 8).padding(.vertical, 6) }
                }
        }
        .tabItem { Label(title, systemImage: icon) }
    }
}

struct Artwork: View {
    let address: String?
    var round = false
    var body: some View {
        GeometryReader { proxy in
            AsyncImage(url: address.flatMap(URL.init(string:))) { image in
                image.resizable().scaledToFill()
            } placeholder: {
                ZStack {
                    LinearGradient(colors: [accent.opacity(0.6), Color.indigo.opacity(0.65), Color.black.opacity(0.7)], startPoint: .topLeading, endPoint: .bottomTrailing)
                    Image(systemName: round ? "person.fill" : "music.note").font(.system(size: max(16, proxy.size.width * 0.25), weight: .light)).foregroundStyle(.white.opacity(0.7))
                }
            }
            .frame(width: proxy.size.width, height: proxy.size.height).clipped()
        }
        .clipShape(RoundedRectangle(cornerRadius: round ? 1000 : 10, style: .continuous))
        .accessibilityHidden(true)
    }
}

struct TrackRow: View {
    @EnvironmentObject private var model: MusicModel
    let item: MusicItem
    var body: some View {
        HStack(spacing: 12) {
            Artwork(address: item.thumbnail, round: item.kind == "artist").frame(width: 50, height: 50)
            VStack(alignment: .leading, spacing: 4) {
                Text(item.title).font(.body).foregroundStyle(model.current?.id == item.id ? accent : .primary).lineLimit(1)
                Text(item.artist).font(.subheadline).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer(minLength: 0)
            if model.current?.id == item.id { Image(systemName: model.playing ? "waveform" : "pause.fill").foregroundStyle(accent) }
        }
        .padding(.vertical, 4).contentShape(Rectangle())
    }
}

struct ItemAction<Content: View>: View {
    @EnvironmentObject private var model: MusicModel
    let item: MusicItem
    let queue: [MusicItem]
    @ViewBuilder let content: () -> Content
    var body: some View {
        Group {
            if item.playable {
                Button { model.play(queue, at: item) } label: { content() }.buttonStyle(.plain)
            } else {
                NavigationLink { DetailView(item: item) } label: { content() }.buttonStyle(.plain)
            }
        }
        .contextMenu {
            Button { model.toggleFavorite(item) } label: { Label(model.favorite(item) ? "Remove from Favorites" : "Add to Favorites", systemImage: model.favorite(item) ? "heart.slash" : "heart") }
            if item.playable {
                Button { model.play(queue, at: item) } label: { Label("Play", systemImage: "play.fill") }
                Button { model.addToQueue(item) } label: { Label("Play Last", systemImage: "text.line.last.and.arrowtriangle.forward") }
            }
        }
    }
}

struct ShelfView: View {
    let shelf: MusicShelf
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    if let strapline = shelf.strapline { Text(strapline.uppercased()).font(.caption.weight(.semibold)).foregroundStyle(.secondary) }
                    Text(shelf.title).font(.title2.bold()).foregroundStyle(.primary)
                }
                Spacer()
                if let link = shelf.seeAll {
                    NavigationLink { DetailView(item: MusicItem(id: link.browseId, kind: "browse", title: shelf.title), params: link.params) } label: { Image(systemName: "chevron.right").font(.subheadline.weight(.semibold)).foregroundStyle(.secondary) }.accessibilityLabel("See all \(shelf.title)")
                }
            }.padding(.horizontal, 20)
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(alignment: .top, spacing: 16) {
                    ForEach(Array(shelf.items.enumerated()), id: \.offset) { _, item in
                        ItemAction(item: item, queue: shelf.items) {
                            VStack(alignment: .leading, spacing: 8) {
                                Artwork(address: item.thumbnail, round: shelf.layout == "circle").frame(width: 158, height: shelf.layout == "video" ? 96 : 158)
                                Text(item.title).font(.subheadline.weight(.medium)).lineLimit(2).foregroundStyle(.primary)
                                Text(item.artist).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                            }.frame(width: 158, alignment: .leading)
                        }
                    }
                }.padding(.horizontal, 20)
            }
        }
    }
}

struct FeedView: View {
    @EnvironmentObject private var model: MusicModel
    let explore: Bool
    @State private var shelves: [MusicShelf] = []
    @State private var cursor: String?
    @State private var loading = true
    @State private var moreLoading = false
    @State private var error: String?
    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 30) {
                if loading && shelves.isEmpty { LoadingView() }
                if let error { ErrorView(message: error) { Task { await load() } } }
                if !explore && !model.library.recent.isEmpty {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Recently Played").font(.title2.bold())
                        ForEach(Array(model.library.recent.prefix(3))) { item in
                            ItemAction(item: item, queue: model.library.recent) { TrackRow(item: item) }
                        }
                    }.padding(.horizontal, 20)
                }
                ForEach(Array(shelves.enumerated()), id: \.offset) { _, shelf in ShelfView(shelf: shelf) }
                if cursor != nil {
                    Button { Task { await more() } } label: {
                        HStack { Spacer(); if moreLoading { ProgressView() } else { Text("Load More") }; Spacer() }
                    }.disabled(moreLoading).padding()
                }
            }.padding(.top, 12).padding(.bottom, 24)
        }
        .refreshable { await load() }
        .task { if shelves.isEmpty { await load() } }
    }
    private func load() async {
        loading = true; error = nil
        do {
            if explore { shelves = try await model.fetch("explore"); cursor = nil }
            else { let page: PagedItems<MusicShelf> = try await model.fetch("home"); shelves = page.data; cursor = page.cursor }
        } catch { if !Task.isCancelled { self.error = error.localizedDescription } }
        loading = false
    }
    private func more() async {
        guard let cursor else { return }
        moreLoading = true
        do { let page: PagedItems<MusicShelf> = try await model.fetch("more", ["cursor": cursor]); shelves += page.data; self.cursor = page.cursor }
        catch { error = error.localizedDescription }
        moreLoading = false
    }
}

struct SearchView: View {
    @EnvironmentObject private var model: MusicModel
    @State private var query = ""
    @State private var results: SearchResults?
    @State private var loading = false
    @State private var error: String?
    @State private var retry = 0
    var body: some View {
        List {
            if query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                EmptyViewCard(icon: "magnifyingglass", title: "Find your next favorite", message: "Search songs, artists, albums and playlists.").listRowSeparator(.hidden)
            } else if loading { HStack { Spacer(); ProgressView(); Spacer() }.listRowSeparator(.hidden) }
            else if let error { ErrorView(message: error) { retry += 1 }.listRowSeparator(.hidden) }
            else if let results {
                if results.groups.isEmpty { EmptyViewCard(icon: "music.note", title: "No results", message: "Try a different song or artist.").listRowSeparator(.hidden) }
                ForEach(results.groups, id: \.0) { title, items in
                    Section(title) {
                        ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                            ItemAction(item: item, queue: items) { TrackRow(item: item) }
                        }
                    }
                }
            }
        }
        .listStyle(.plain).scrollDismissesKeyboard(.interactively)
        .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always), prompt: "Songs, artists, albums")
        .task(id: query + String(retry)) {
            results = nil; error = nil
            let term = query.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !term.isEmpty else { loading = false; return }
            loading = true
            do {
                try await Task.sleep(nanoseconds: 350_000_000)
                let result: SearchResults = try await model.fetch("search", ["query": term])
                try Task.checkCancellation()
                results = result; loading = false
            } catch { if !Task.isCancelled { self.error = error.localizedDescription; loading = false } }
        }
    }
}

struct LibraryView: View {
    @EnvironmentObject private var model: MusicModel
    var body: some View {
        List {
            Section {
                NavigationLink { SavedItemsView(title: "Favorites", recent: false) } label: { Label("Favorites", systemImage: "heart.fill").foregroundStyle(accent).padding(.vertical, 8) }
                NavigationLink { SavedItemsView(title: "Recently Played", recent: true) } label: { Label("Recently Played", systemImage: "clock.fill").foregroundStyle(accent).padding(.vertical, 8) }
            }
            if model.library.recent.isEmpty && model.library.favorites.isEmpty {
                EmptyViewCard(icon: "square.stack", title: "Your music starts here", message: "Keep your favorites close. Touch and hold a song or album to save it.").listRowSeparator(.hidden)
            } else {
                Section("Recently Played") {
                    ForEach(Array(model.library.recent.prefix(12))) { item in ItemAction(item: item, queue: model.library.recent) { TrackRow(item: item) } }
                }
            }
        }.listStyle(.plain)
    }
}

struct SavedItemsView: View {
    @EnvironmentObject private var model: MusicModel
    let title: String
    let recent: Bool
    private var items: [MusicItem] { recent ? model.library.recent : model.library.favorites }
    var body: some View {
        List {
            if items.isEmpty { EmptyViewCard(icon: recent ? "clock" : "heart", title: "Nothing here yet", message: recent ? "The songs you play will appear here." : "Save music from a song's menu.").listRowSeparator(.hidden) }
            ForEach(items) { item in ItemAction(item: item, queue: items) { TrackRow(item: item) } }
        }.listStyle(.plain).navigationTitle(title)
    }
}

struct DetailView: View {
    @EnvironmentObject private var model: MusicModel
    let item: MusicItem
    var params: String? = nil
    @State private var page: CataloguePage?
    @State private var error: String?
    @State private var loading = true
    @State private var moreLoading = false
    private var tracks: [MusicItem] { page?.tracks ?? page?.topSongs ?? [] }
    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 22) {
                if loading { LoadingView() }
                if let error { ErrorView(message: error) { Task { await load() } } }
                if let page {
                    VStack(alignment: .leading, spacing: 16) {
                        Artwork(address: page.thumbnail ?? page.heroImage ?? item.thumbnail, round: item.kind == "artist")
                            .frame(width: 230, height: 230).frame(maxWidth: .infinity).padding(.top, 12)
                        Text(page.title ?? page.name ?? item.title).font(.title.bold())
                        if let subtitle = page.subtitle { Text(subtitle).foregroundStyle(.secondary) }
                        if !tracks.isEmpty {
                            HStack {
                                Button { model.play(tracks, at: tracks[0]) } label: { Label("Play", systemImage: "play.fill").frame(maxWidth: .infinity) }
                                Button { let shuffled = tracks.shuffled(); if let first = shuffled.first { model.play(shuffled, at: first) } } label: { Label("Shuffle", systemImage: "shuffle").frame(maxWidth: .infinity) }
                            }.buttonStyle(.bordered).controlSize(.large)
                        }
                        if let description = page.description, !description.isEmpty { Text(description).font(.subheadline).foregroundStyle(.secondary).lineLimit(5) }
                        ForEach(Array(tracks.enumerated()), id: \.offset) { _, track in
                            ItemAction(item: track, queue: tracks) { TrackRow(item: track) }
                            Divider()
                        }
                        if page.cursor != nil {
                            Button(moreLoading ? "Loading…" : "Load More Songs") { Task { await more() } }.disabled(moreLoading)
                        }
                        if let grid = page.grid {
                            ForEach(Array(grid.enumerated()), id: \.offset) { _, row in ItemAction(item: row, queue: grid) { TrackRow(item: row) } }
                        }
                    }.padding(.horizontal, 20)
                    ForEach(Array((page.shelves ?? page.more ?? []).enumerated()), id: \.offset) { _, shelf in ShelfView(shelf: shelf) }
                }
            }.padding(.bottom, 24)
        }
        .navigationTitle(item.title).navigationBarTitleDisplayMode(.inline)
        .toolbar { Button { model.toggleFavorite(item) } label: { Image(systemName: model.favorite(item) ? "heart.fill" : "heart") }.accessibilityLabel("Favorite") }
        .task { await load() }.refreshable { await load() }
    }
    private func load() async {
        loading = page == nil; error = nil
        do {
            let method = ["album", "artist", "playlist"].contains(item.kind) ? item.kind : "browse"
            var args: [String: Any] = ["id": item.id]; if let params { args["params"] = params }
            page = try await model.fetch(method, args)
        } catch { if !Task.isCancelled { self.error = error.localizedDescription } }
        loading = false
    }
    private func more() async {
        guard let cursor = page?.cursor else { return }
        moreLoading = true
        do { let next: PagedItems<MusicItem> = try await model.fetch("more", ["cursor": cursor]); page?.tracks = tracks + next.data; page?.cursor = next.cursor }
        catch { error = error.localizedDescription }
        moreLoading = false
    }
}

struct MiniPlayer: View {
    @EnvironmentObject private var model: MusicModel
    var body: some View {
        if let item = model.current {
            HStack(spacing: 12) {
                Button { model.showPlayer = true } label: {
                    HStack(spacing: 12) {
                        Artwork(address: item.thumbnail).frame(width: 42, height: 42)
                        VStack(alignment: .leading, spacing: 3) {
                            Text(item.title).font(.subheadline.weight(.semibold)).lineLimit(1)
                            Text(model.playbackError != nil ? "Playback failed · Tap to retry" : item.artist).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                        }
                        Spacer(minLength: 0)
                    }.contentShape(Rectangle())
                }.buttonStyle(.plain).accessibilityLabel("Open Now Playing")
                if model.loading { ProgressView().frame(width: 36) }
                else { Button { model.togglePlayback() } label: { Image(systemName: model.playing ? "pause.fill" : "play.fill").font(.title3).frame(width: 36, height: 44) }.accessibilityLabel(model.playing ? "Pause" : "Play") }
                Button { model.next() } label: { Image(systemName: "forward.fill").font(.title3).frame(width: 32, height: 44) }.accessibilityLabel("Next Track")
            }
            .padding(8).foregroundStyle(.primary)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 18).stroke(.primary.opacity(0.06)))
        }
    }
}

struct PlayerView: View {
    @EnvironmentObject private var model: MusicModel
    @Environment(\.dismiss) private var dismiss
    @State private var queueVisible = false
    @State private var scrub: Double?
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 28) {
                    Artwork(address: model.current?.thumbnail)
                        .aspectRatio(1, contentMode: .fit).shadow(color: .black.opacity(0.2), radius: 22, y: 14)
                        .scaleEffect(model.playing ? 1 : 0.92).animation(.spring(response: 0.45, dampingFraction: 0.8), value: model.playing)
                        .padding(.top, 12)
                    HStack(alignment: .center) {
                        VStack(alignment: .leading, spacing: 6) {
                            Text(model.current?.title ?? "Not Playing").font(.title2.bold()).lineLimit(2)
                            Text(model.current?.artist ?? "").font(.title3).foregroundStyle(.secondary).lineLimit(1)
                        }
                        Spacer()
                        if let item = model.current { Button { model.toggleFavorite(item) } label: { Image(systemName: model.favorite(item) ? "heart.fill" : "heart").font(.title2) }.accessibilityLabel("Favorite") }
                    }
                    VStack(spacing: 3) {
                        Slider(value: Binding(get: { scrub ?? model.position }, set: { scrub = $0 }), in: 0...max(1, model.duration), onEditingChanged: { editing in
                            if !editing, let scrub { model.seek(scrub); self.scrub = nil }
                        }).accessibilityLabel("Playback position")
                        HStack { Text(time(scrub ?? model.position)); Spacer(); Text("−" + time(max(0, model.duration - (scrub ?? model.position)))) }.font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                    }
                    HStack(spacing: 40) {
                        Button { model.previous() } label: { Image(systemName: "backward.fill").font(.system(size: 30)) }.accessibilityLabel("Previous Track")
                        Button { model.togglePlayback() } label: {
                            Group { if model.loading { ProgressView().scaleEffect(1.4) } else { Image(systemName: model.playing ? "pause.fill" : "play.fill").font(.system(size: 48)) } }.frame(width: 70, height: 70)
                        }.accessibilityLabel(model.playing ? "Pause" : "Play")
                        Button { model.next() } label: { Image(systemName: "forward.fill").font(.system(size: 30)) }.accessibilityLabel("Next Track")
                    }.foregroundStyle(.primary)
                    if let error = model.playbackError { ErrorView(message: error) { model.togglePlayback() } }
                    HStack {
                        Button { model.toggleShuffle() } label: { Image(systemName: "shuffle").foregroundStyle(model.shuffle ? accent : .secondary) }.accessibilityLabel("Shuffle").accessibilityValue(model.shuffle ? "On" : "Off")
                        Spacer()
                        AirPlayButton().frame(width: 42, height: 42).accessibilityLabel("AirPlay")
                        Spacer()
                        Button { model.toggleRepeat() } label: { Image(systemName: model.repeatMode == 2 ? "repeat.1" : "repeat").foregroundStyle(model.repeatMode == 0 ? .secondary : accent) }.accessibilityLabel("Repeat").accessibilityValue(["Off", "Queue", "Song"][model.repeatMode])
                        Spacer()
                        Button { queueVisible = true } label: { Image(systemName: "list.bullet") }.accessibilityLabel("Playing Next")
                    }.font(.title3)
                    VolumeSlider().frame(height: 30)
                }.padding(.horizontal, 30).padding(.bottom, 30)
            }
            .background(LinearGradient(colors: [accent.opacity(0.13), Color(uiColor: .systemBackground)], startPoint: .topLeading, endPoint: .bottomTrailing).ignoresSafeArea())
            .navigationTitle("Now Playing").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .navigationBarLeading) { Button { dismiss() } label: { Image(systemName: "chevron.down") }.accessibilityLabel("Close Now Playing") } }
            .sheet(isPresented: $queueVisible) { QueueView() }
        }.presentationDragIndicator(.visible)
    }
    private func time(_ seconds: Double) -> String { let s = Int(max(0, seconds)); return String(format: "%d:%02d", s / 60, s % 60) }
}

struct QueueView: View {
    @EnvironmentObject private var model: MusicModel
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        NavigationStack {
            List(Array(model.queue.enumerated()), id: \.offset) { index, item in
                Button { model.select(index) } label: { TrackRow(item: item) }.buttonStyle(.plain)
            }.listStyle(.plain).navigationTitle("Playing Next").navigationBarTitleDisplayMode(.inline)
                .toolbar { Button("Done") { dismiss() } }
        }
    }
}

struct AirPlayButton: UIViewRepresentable {
    func makeUIView(context: Context) -> AVRoutePickerView { let view = AVRoutePickerView(); view.activeTintColor = .systemPink; view.prioritizesVideoDevices = false; return view }
    func updateUIView(_ uiView: AVRoutePickerView, context: Context) {}
}
struct VolumeSlider: UIViewRepresentable {
    func makeUIView(context: Context) -> MPVolumeView { let view = MPVolumeView(); view.showsRouteButton = false; return view }
    func updateUIView(_ uiView: MPVolumeView, context: Context) {}
}

struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @AppStorage("bitchord.appearance") private var appearance = "system"
    var body: some View {
        NavigationStack {
            Form {
                Section("Appearance") {
                    Picker("Theme", selection: $appearance) { Text("System").tag("system"); Text("Light").tag("light"); Text("Dark").tag("dark") }
                }
                Section {
                    Label("Favorites and history are saved on this device.", systemImage: "iphone")
                    Text("YouTube account sync and offline downloads are not available in this test version.").foregroundStyle(.secondary)
                } header: { Text("Library") }
                Section("About") {
                    LabeledContent("Version", value: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0")
                    Link("BitChord for iOS", destination: URL(string: "https://github.com/rtk19/BitChord")!)
                    Link("Original project", destination: URL(string: "https://github.com/kushagrasinghx/BitChord")!)
                }
            }.navigationTitle("Settings").navigationBarTitleDisplayMode(.inline).toolbar { Button("Done") { dismiss() } }
        }
    }
}

struct LoadingView: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack { ProgressView(); Text("Finding your music…").foregroundStyle(.secondary) }
            HStack(spacing: 16) { ForEach(0..<2) { _ in RoundedRectangle(cornerRadius: 12).fill(.quaternary).frame(height: 180) } }.accessibilityHidden(true)
            RoundedRectangle(cornerRadius: 6).fill(.quaternary).frame(width: 180, height: 20).accessibilityHidden(true)
        }.padding(20)
    }
}
struct EmptyViewCard: View {
    let icon: String; let title: String; let message: String
    var body: some View {
        VStack(spacing: 15) {
            Image(systemName: icon).font(.system(size: 46, weight: .light)).foregroundStyle(accent).padding(.bottom, 4)
            Text(title).font(.title2.bold())
            Text(message).font(.body).foregroundStyle(.secondary).multilineTextAlignment(.center)
        }.frame(maxWidth: .infinity).padding(.horizontal, 20).padding(.vertical, 50)
    }
}
struct ErrorView: View {
    let message: String; let retry: () -> Void
    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "wifi.exclamationmark").font(.title).foregroundStyle(.secondary)
            Text("Couldn't load music").font(.headline)
            Text(message).font(.footnote).foregroundStyle(.secondary).multilineTextAlignment(.center).lineLimit(4)
            Button("Try Again", action: retry).buttonStyle(.bordered)
        }.frame(maxWidth: .infinity).padding(24)
    }
}
