import SwiftUI
import AVFoundation

/// Shared thumbnail cell used by DateLibraryView / DayDetailView.
struct ClipCell: View {
    let clip: SavedClip
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

            // Top-right: share button
            VStack {
                HStack {
                    Spacer()
                    ShareLink(
                        item: clip.url,
                        preview: SharePreview(
                            clip.date.formatted(.dateTime.month().day().hour().minute()),
                            icon: Image(systemName: "film")
                        )
                    ) {
                        Image(systemName: "square.and.arrow.up")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundColor(.white)
                            .padding(7)
                            .background(Color.black.opacity(0.5), in: Circle())
                    }
                    .buttonStyle(.plain)
                    .padding(6)
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
