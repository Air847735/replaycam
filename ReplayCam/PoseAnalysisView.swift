import SwiftUI
import AVKit

// MARK: - Video selection page

struct PoseAnalysisView: View {
    @ObservedObject private var store = ClipStore.shared
    @State private var selectedClip: SavedClip?

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 2), count: 3)

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color(red: 0.04, green: 0.16, blue: 0.30),
                    Color(red: 0.02, green: 0.22, blue: 0.22)
                ],
                startPoint: .topLeading, endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            Image("tiss_pattern")
                .resizable(resizingMode: .tile)
                .ignoresSafeArea()
                .opacity(0.13)

            if store.clips.isEmpty {
                VStack(spacing: 16) {
                    Image(systemName: "film.stack")
                        .font(.system(size: 48))
                        .foregroundColor(.white.opacity(0.4))
                    Text("尚無影片可分析")
                        .foregroundColor(.white.opacity(0.5))
                }
            } else {
                ScrollView {
                    LazyVGrid(columns: columns, spacing: 2) {
                        ForEach(store.clips) { clip in
                            AnalysisThumbnailCell(clip: clip)
                                .onTapGesture { selectedClip = clip }
                        }
                    }
                }
            }
        }
        .navigationTitle("選擇分析影片")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
        .toolbarBackground(Color(red: 0.04, green: 0.16, blue: 0.30), for: .navigationBar)
        .fullScreenCover(item: $selectedClip) { clip in
            PoseAnalysisResultView(clip: clip)
        }
    }
}

// MARK: - Thumbnail cell

struct AnalysisThumbnailCell: View {
    let clip: SavedClip
    @State private var thumbnail: UIImage?

    var body: some View {
        Color.black
            .aspectRatio(1, contentMode: .fit)
            .overlay(
                Group {
                    if let thumb = thumbnail {
                        Image(uiImage: thumb)
                            .resizable()
                            .scaledToFit()
                    } else {
                        ProgressView().scaleEffect(0.7).tint(.white)
                    }
                }
            )
            .clipped()
            .contentShape(Rectangle())
            .task {
                guard thumbnail == nil else { return }
                let gen = AVAssetImageGenerator(asset: AVURLAsset(url: clip.url))
                gen.appliesPreferredTrackTransform = true
                gen.maximumSize = CGSize(width: 300, height: 300)
                if let cg = try? gen.copyCGImage(at: .zero, actualTime: nil) {
                    thumbnail = UIImage(cgImage: cg)
                }
            }
    }
}
