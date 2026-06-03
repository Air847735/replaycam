import Foundation
import Combine

/// A single saved video clip stored in the app's Documents directory.
struct SavedClip: Identifiable {
    let id: UUID
    let url: URL
    let date: Date
}

/// Manages the list of clips saved inside the app (Documents/ReplayCamClips/).
@MainActor
final class ClipStore: ObservableObject {
    static let shared = ClipStore()

    @Published var clips: [SavedClip] = []
    @Published private(set) var favoriteIDs: Set<String> = []

    private static let favoritesKey = "favoriteClipIDs"

    // MARK: - Directory

    /// `nonisolated` so VideoExporter can read this from a background thread
    /// without hopping to MainActor.
    static nonisolated var clipsDirectory: URL {
        FileManager.default
            .urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("ReplayCamClips", isDirectory: true)
    }

    // MARK: - Init

    private init() {
        // Create directory synchronously (cheap, only metadata).
        try? FileManager.default.createDirectory(
            at: Self.clipsDirectory,
            withIntermediateDirectories: true
        )
        loadFavorites()
        // Scan on a background thread so init doesn't block MainActor.
        Task { await refreshAsync() }
    }

    // MARK: - Public API

    /// Rescans the clips directory in the background, then publishes results.
    func refresh() {
        Task { await refreshAsync() }
    }

    func delete(_ clip: SavedClip) {
        try? FileManager.default.removeItem(at: clip.url)
        clips.removeAll { $0.id == clip.id }
        favoriteIDs.remove(clip.url.lastPathComponent)
        saveFavorites()
    }

    // MARK: - Favourites

    func isFavorite(_ clip: SavedClip) -> Bool {
        favoriteIDs.contains(clip.url.lastPathComponent)
    }

    func toggleFavorite(_ clip: SavedClip) {
        let key = clip.url.lastPathComponent
        if favoriteIDs.contains(key) { favoriteIDs.remove(key) }
        else { favoriteIDs.insert(key) }
        saveFavorites()
    }

    // MARK: - Private

    /// Filesystem scan runs on a background thread; only the final assignment
    /// to `clips` touches the MainActor.
    private func refreshAsync() async {
        let dir = Self.clipsDirectory
        let newClips: [SavedClip] = await Task.detached(priority: .utility) {
            let fm = FileManager.default
            guard let files = try? fm.contentsOfDirectory(
                at: dir,
                includingPropertiesForKeys: [.creationDateKey],
                options: .skipsHiddenFiles
            ) else { return [] }

            return files
                .filter { $0.pathExtension == "mp4" }
                .compactMap { url -> SavedClip? in
                    let vals = try? url.resourceValues(forKeys: [.creationDateKey])
                    return SavedClip(
                        id: UUID(),
                        url: url,
                        date: vals?.creationDate ?? Date()
                    )
                }
                .sorted { $0.date > $1.date }
        }.value

        self.clips = newClips
    }

    private func loadFavorites() {
        let saved = UserDefaults.standard.stringArray(forKey: Self.favoritesKey) ?? []
        favoriteIDs = Set(saved)
    }

    private func saveFavorites() {
        UserDefaults.standard.set(Array(favoriteIDs), forKey: Self.favoritesKey)
    }
}
