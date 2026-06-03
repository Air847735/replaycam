import SwiftUI
import AVFoundation

// MARK: - Multi-file share sheet

struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]
    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }
    func updateUIViewController(_ vc: UIActivityViewController, context: Context) {}
}

// MARK: - Clip cell

struct ClipCell: View {
    let clip: SavedClip
    var isSelectMode: Bool = false
    var isSelected:   Bool = false

    @ObservedObject private var store = ClipStore.shared
    @State private var thumbnail: UIImage?

    var body: some View {
        ZStack {
            // Thumbnail
            Group {
                if let thumb = thumbnail {
                    Image(uiImage: thumb)
                        .resizable()
                        .scaledToFill()
                } else {
                    Color(.systemGray5)
                        .overlay(ProgressView().scaleEffect(0.7))
                }
            }
            .aspectRatio(9/16, contentMode: .fit)
            .clipped()

            // Blue tint when selected
            if isSelected {
                Color.blue.opacity(0.25)
            }

            // Top-right: checkmark (select mode) or star (normal)
            VStack {
                HStack {
                    Spacer()
                    if isSelectMode {
                        Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                            .font(.system(size: 20, weight: .semibold))
                            .foregroundColor(isSelected ? .blue : .white.opacity(0.85))
                            .shadow(color: .black.opacity(0.4), radius: 3)
                            .padding(6)
                    } else {
                        let fav = store.isFavorite(clip)
                        Button {
                            withAnimation(.spring(response: 0.25, dampingFraction: 0.6)) {
                                store.toggleFavorite(clip)
                            }
                        } label: {
                            Image(systemName: fav ? "star.fill" : "star")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundColor(fav ? .yellow : .white)
                                .padding(7)
                                .background(Color.black.opacity(0.5), in: Circle())
                                .scaleEffect(fav ? 1.15 : 1.0)
                        }
                        .buttonStyle(.plain)
                        .padding(6)
                    }
                }
                Spacer()
            }

            // Bottom-right: time label
            VStack {
                Spacer()
                HStack {
                    Spacer()
                    Text(clip.date.formatted(.dateTime.hour().minute()))
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(.white)
                        .padding(.horizontal, 5).padding(.vertical, 2)
                        .background(Color.black.opacity(0.55),
                                    in: RoundedRectangle(cornerRadius: 3))
                        .padding(5)
                }
            }
        }
        .task { thumbnail = await makeThumbnail(for: clip.url) }
    }

    private func makeThumbnail(for url: URL) async -> UIImage? {
        let asset = AVURLAsset(url: url)
        let gen = AVAssetImageGenerator(asset: asset)
        gen.appliesPreferredTrackTransform = true
        gen.maximumSize = CGSize(width: 300, height: 534)
        let time = CMTime(seconds: 0.1, preferredTimescale: 600)
        return (try? gen.copyCGImage(at: time, actualTime: nil)).map { UIImage(cgImage: $0) }
    }
}
