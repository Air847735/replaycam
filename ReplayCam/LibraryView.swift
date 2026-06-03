import SwiftUI
import AVFoundation

struct LibraryView: View {
    @ObservedObject private var store = ClipStore.shared
    @State private var selectedClip: SavedClip?
    @Environment(\.dismiss) private var dismiss

    private let columns = [GridItem(.flexible(), spacing: 2), GridItem(.flexible(), spacing: 2), GridItem(.flexible(), spacing: 2)]

    var body: some View {
        NavigationStack {
            Group {
                if store.clips.isEmpty {
                    emptyState
                } else {
                    ScrollView {
                        LazyVGrid(columns: columns, spacing: 2) {
                            ForEach(store.clips) { clip in
                                ClipCell(clip: clip)
                                    .onTapGesture { selectedClip = clip }
                                    .contextMenu {
                                        Button(role: .destructive) {
                                            store.delete(clip)
                                        } label: {
                                            Label("刪除", systemImage: "trash")
                                        }
                                    }
                            }
                        }
                    }
                }
            }
            .navigationTitle("片段庫")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("完成") { dismiss() }
                }
            }
        }
        .fullScreenCover(item: $selectedClip) { clip in
            PlayerView(url: clip.url)
        }
    }

    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "film.stack")
                .font(.system(size: 56))
                .foregroundColor(.secondary)
            Text("還沒有儲存的片段")
                .font(.headline)
                .foregroundColor(.secondary)
            Text("錄製完成後按「儲存影片」，片段就會出現在這裡")
                .font(.caption)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Clip cell

struct ClipCell: View {
    let clip: SavedClip
    @State private var thumbnail: UIImage?

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            // Thumbnail
            Group {
                if let thumb = thumbnail {
                    Image(uiImage: thumb)
                        .resizable()
                        .scaledToFill()
                } else {
                    Color(.systemGray5)
                        .overlay(ProgressView())
                }
            }
            .aspectRatio(9/16, contentMode: .fit)
            .clipped()

            // Date label
            Text(clip.date.formatted(.dateTime.month(.abbreviated).day().hour().minute()))
                .font(.system(size: 10, weight: .medium))
                .foregroundColor(.white)
                .padding(.horizontal, 6).padding(.vertical, 3)
                .background(Color.black.opacity(0.55), in: RoundedRectangle(cornerRadius: 4))
                .padding(6)
        }
        .task { thumbnail = await makeThumbnail(for: clip.url) }
    }

    private func makeThumbnail(for url: URL) async -> UIImage? {
        let asset = AVURLAsset(url: url)
        let gen = AVAssetImageGenerator(asset: asset)
        gen.appliesPreferredTrackTransform = true
        gen.maximumSize = CGSize(width: 300, height: 534)
        let time = CMTime(seconds: 0.1, preferredTimescale: 600)
        if let cg = try? gen.copyCGImage(at: time, actualTime: nil) {
            return UIImage(cgImage: cg)
        }
        return nil
    }
}
