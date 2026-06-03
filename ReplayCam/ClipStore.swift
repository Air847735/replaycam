import Foundation
import Combine

/// A single saved video clip stored in the app's Documents directory.
struct SavedClip: Identifiable {
    let id: UUID
    let url: URL
    let date: Date
}

/// Manages the list of clips saved inside the app (Documents/ReplayCamClips/).
/// Scans the directory on launch — no separate database needed.
@MainActor
final class ClipStore: ObservableObject {
    static let shared = ClipStore()

    @Published var clips: [SavedClip] = []
    @Published private(set) var favoriteIDs: Set<String> = []

    private static let favoritesKey = "favoriteClipIDs"

    // MARK: - Directory

    static var clipsDirectory: URL {
        FileManager.default
            .urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("ReplayCamClips", isDirectory: true)
    }

    // MARK: - Init

    private init() {
        createDirectoryIfNeeded()
        refresh()
        loadFavorites()
    }

    // MARK: - Public API

    /// Call after a new clip has been written to `clipsDirectory`.
    func refresh() {
        let fm = FileManager.default
        guard let files = try? fm.contentsOfDirectory(
            at: Self.clipsDirectory,
            includingPropertiesForKeys: [.creationDateKey],
            options: .skipsHiddenFiles
        ) else { return }

        clips = files
            .filter { $0.pathExtension == "mp4" }
            .compactMap { url -> SavedClip? in
                let vals = try? url.resourceValues(forKeys: [.creationDateKey])
                return SavedClip(
                    id: UUID(),
                    url: url,
                    date: vals?.creationDate ?? Date()
                )
            }
            .sorted { $0.date > $1.date }   // newest first
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

    private func loadFavorites() {
        let saved = UserDefaults.standard.stringArray(forKey: Self.favoritesKey) ?? []
        favoriteIDs = Set(saved)
    }

    private func saveFavorites() {
        UserDefaults.standard.set(Array(favoriteIDs), forKey: Self.favoritesKey)
    }

    // MARK: - Private

    private func createDirectoryIfNeeded() {
        try? FileManager.default.createDirectory(
            at: Self.clipsDirectory,
            withIntermediateDirectories: true
        )
    }
}
