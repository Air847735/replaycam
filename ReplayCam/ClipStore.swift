import Foundation
import Combine

// MARK: - Models

struct SavedClip: Identifiable {
    var id: String { url.lastPathComponent }
    let url: URL
    let date: Date
}

struct ClipFolder: Identifiable, Codable {
    let id: String
    var name: String
    let createdDate: Date
    var parentID: String?   // nil = root level

    init(name: String, parentID: String? = nil) {
        self.id          = UUID().uuidString
        self.name        = name
        self.createdDate = Date()
        self.parentID    = parentID
    }
}

// MARK: - ClipStore

@MainActor
final class ClipStore: ObservableObject {
    static let shared = ClipStore()

    @Published var clips:   [SavedClip]  = []
    @Published var folders: [ClipFolder] = []

    // clipID (filename) → folderID
    @Published private(set) var clipFolderMap: [String: String] = [:]

    private static let favoritesKey    = "favoriteClipIDs"
    private static let foldersKey      = "clipFolders"
    private static let folderMapKey    = "clipFolderMap"

    @Published private(set) var favoriteIDs: Set<String> = []

    // MARK: - Directory

    static nonisolated var clipsDirectory: URL {
        FileManager.default
            .urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("ReplayCamClips", isDirectory: true)
    }

    // MARK: - Init

    private init() {
        loadFavorites()
        loadFolders()
        // Directory creation + scan are both I/O — run off the main thread
        Task.detached(priority: .utility) {
            try? FileManager.default.createDirectory(
                at: ClipStore.clipsDirectory, withIntermediateDirectories: true
            )
            await self.refreshAsync()
        }
    }

    // MARK: - Clips

    func refresh() { Task { await refreshAsync() } }

    func delete(_ clip: SavedClip) {
        try? FileManager.default.removeItem(at: clip.url)
        clips.removeAll { $0.id == clip.id }
        favoriteIDs.remove(clip.id)
        clipFolderMap.removeValue(forKey: clip.id)
        saveFavorites()
        saveFolderMap()
    }

    // MARK: - Favourites

    func isFavorite(_ clip: SavedClip) -> Bool { favoriteIDs.contains(clip.id) }

    func toggleFavorite(_ clip: SavedClip) {
        if favoriteIDs.contains(clip.id) { favoriteIDs.remove(clip.id) }
        else { favoriteIDs.insert(clip.id) }
        saveFavorites()
    }

    // MARK: - Folders

    // MARK: - Folder hierarchy helpers

    var rootFolders: [ClipFolder] { folders.filter { $0.parentID == nil } }

    func subfolders(of folder: ClipFolder) -> [ClipFolder] {
        folders.filter { $0.parentID == folder.id }
    }

    func createFolder(name: String, parentID: String? = nil) {
        let folder = ClipFolder(name: name, parentID: parentID)
        folders.append(folder)
        saveFolders()
    }

    func renameFolder(_ folder: ClipFolder, to name: String) {
        guard let idx = folders.firstIndex(where: { $0.id == folder.id }) else { return }
        folders[idx].name = name
        saveFolders()
    }

    func deleteFolder(_ folder: ClipFolder) {
        // Recursively delete all subfolders first
        for sub in subfolders(of: folder) { deleteFolder(sub) }
        var map = clipFolderMap
        for key in map.keys where map[key] == folder.id {
            map.removeValue(forKey: key)
        }
        clipFolderMap = map   // full reassignment triggers @Published willSet
        folders.removeAll { $0.id == folder.id }
        saveFolders()
        saveFolderMap()
    }

    /// Assign a set of clip IDs to a folder (pass nil to unassign).
    func assignClips(_ clipIDs: Set<String>, to folderID: String?) {
        var map = clipFolderMap
        for id in clipIDs {
            if let folderID { map[id] = folderID }
            else            { map.removeValue(forKey: id) }
        }
        clipFolderMap = map   // full reassignment triggers @Published willSet
        saveFolderMap()
    }

    func folderID(for clip: SavedClip) -> String? { clipFolderMap[clip.id] }

    func clips(in folder: ClipFolder) -> [SavedClip] {
        clips.filter { clipFolderMap[$0.id] == folder.id }
    }

    var unassignedClips: [SavedClip] {
        clips.filter { clipFolderMap[$0.id] == nil }
    }

    // MARK: - Private persistence

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
                    return SavedClip(url: url, date: vals?.creationDate ?? Date())
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

    private func loadFolders() {
        if let data = UserDefaults.standard.data(forKey: Self.foldersKey),
           let decoded = try? JSONDecoder().decode([ClipFolder].self, from: data) {
            folders = decoded
        }
        if let dict = UserDefaults.standard.dictionary(forKey: Self.folderMapKey)
            as? [String: String] {
            clipFolderMap = dict
        }
    }

    private func saveFolders() {
        if let data = try? JSONEncoder().encode(folders) {
            UserDefaults.standard.set(data, forKey: Self.foldersKey)
        }
    }

    private func saveFolderMap() {
        UserDefaults.standard.set(clipFolderMap, forKey: Self.folderMapKey)
    }
}
