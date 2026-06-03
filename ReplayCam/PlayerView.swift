import SwiftUI
import AVKit
import AVFoundation
import Combine

// MARK: - Player model (ObservableObject ensures closures always see live state)

@MainActor
final class PlayerModel: ObservableObject {
    @Published var currentTime: Double = 0
    @Published var duration:    Double = 1
    @Published var isPlaying:   Bool   = true
    @Published var speed:       Float  = 1.0
    @Published var thumbnails:  [UIImage] = []
    @Published var isScrubbing: Bool   = false

    let player: AVPlayer
    private var timeObserverToken: Any?
    private let thumbnailCount = 30

    init(url: URL) {
        player = AVPlayer(url: url)
    }

    func setup(url: URL) {
        // Duration
        Task { [weak self, url] in
            let asset = AVURLAsset(url: url)
            if let d = try? await asset.load(.duration) {
                self?.duration = max(1, d.seconds)
            }
        }

        // Thumbnails
        Task.detached(priority: .userInitiated) { [weak self, url] in
            guard let self else { return }
            let images = await Self.generateThumbnails(url: url, count: self.thumbnailCount)
            await MainActor.run { self.thumbnails = images }
        }

        // Time observer — safe because self is a class
        let interval = CMTime(value: 1, timescale: 30)
        timeObserverToken = player.addPeriodicTimeObserver(
            forInterval: interval, queue: .main
        ) { [weak self] time in
            guard let self, !self.isScrubbing else { return }
            self.currentTime = time.seconds
        }

        // Playback
        player.play()
        NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime,
            object: player.currentItem, queue: .main
        ) { [weak self] _ in
            guard let self else { return }
            self.player.seek(to: .zero) { [weak self] _ in
                guard let self else { return }
                self.player.rate = self.speed
            }
        }
    }

    func teardown() {
        player.pause()
        if let token = timeObserverToken { player.removeTimeObserver(token) }
    }

    func togglePlayPause() {
        if isPlaying { player.pause() } else { player.rate = speed }
        isPlaying.toggle()
    }

    func seek(to time: Double) {
        // Cancel queued seeks so fast drags don't pile up
        player.currentItem?.cancelPendingSeeks()
        let cmTime = CMTime(seconds: time, preferredTimescale: 600)
        // ±1 frame tolerance — fast enough for live scrubbing, still accurate
        let frameTolerance = CMTime(value: 1, timescale: 30)
        player.seek(to: cmTime,
                    toleranceBefore: frameTolerance,
                    toleranceAfter:  frameTolerance)
    }

    private static func generateThumbnails(url: URL, count: Int) async -> [UIImage] {
        let asset = AVURLAsset(url: url)
        guard let dur = try? await asset.load(.duration), dur.seconds > 0 else { return [] }
        let gen = AVAssetImageGenerator(asset: asset)
        gen.appliesPreferredTrackTransform = true
        gen.maximumSize = CGSize(width: 80, height: 144)
        let tol = CMTime(value: 1, timescale: 10)
        gen.requestedTimeToleranceBefore = tol
        gen.requestedTimeToleranceAfter  = tol

        var images: [UIImage] = []
        images.reserveCapacity(count)
        let total = dur.seconds
        for i in 0..<count {
            let t = total * Double(i) / Double(count - 1)
            if let cg = try? gen.copyCGImage(
                at: CMTime(seconds: t, preferredTimescale: 600), actualTime: nil
            ) { images.append(UIImage(cgImage: cg)) }
        }
        return images
    }
}

// MARK: - Player view

struct PlayerView: View {
    let url: URL
    @StateObject private var model: PlayerModel
    @Environment(\.dismiss) private var dismiss

    init(url: URL) {
        self.url = url
        self._model = StateObject(wrappedValue: PlayerModel(url: url))
    }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            VideoContainer(player: model.player)
                .ignoresSafeArea()
                .onTapGesture { model.togglePlayPause() }

            overlayControls
        }
        .onAppear  { model.setup(url: url) }
        .onDisappear { model.teardown() }
    }

    // MARK: - Overlay

    private var overlayControls: some View {
        VStack {
            topBar
            Spacer()
            bottomControls
        }
    }

    private var topBar: some View {
        HStack {
            Button { model.player.pause(); dismiss() } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 30))
                    .foregroundStyle(.white, Color.black.opacity(0.4))
                    .shadow(color: .black.opacity(0.4), radius: 4)
            }
            Spacer()
            ShareLink(
                item: url,
                preview: SharePreview("影片片段", icon: Image(systemName: "film"))
            ) {
                HStack(spacing: 6) {
                    Image(systemName: "square.and.arrow.up").font(.system(size: 13, weight: .semibold))
                    Text("匯出").font(.system(size: 14, weight: .semibold))
                }
                .foregroundColor(.white)
                .padding(.horizontal, 14).padding(.vertical, 8)
                .background(.ultraThinMaterial, in: Capsule())
                .shadow(color: .black.opacity(0.3), radius: 4)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 16).padding(.top, 56)
    }

    private var bottomControls: some View {
        VStack(spacing: 14) {
            // Time labels
            HStack {
                Text(formatTime(model.currentTime))
                Spacer()
                Text(formatTime(model.duration))
            }
            .font(.system(size: 12, weight: .medium, design: .monospaced))
            .foregroundColor(.white.opacity(0.75))
            .padding(.horizontal, 4)

            // Scrubber
            Group {
                if model.thumbnails.isEmpty {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color.white.opacity(0.08))
                        .overlay(ProgressView().tint(.white).scaleEffect(0.8))
                } else {
                    ThumbnailScrubber(model: model)
                }
            }
            .frame(height: 64)

            // Play/pause + speed
            HStack {
                Button { model.togglePlayPause() } label: {
                    Image(systemName: model.isPlaying ? "pause.fill" : "play.fill")
                        .font(.system(size: 20))
                        .foregroundColor(.white)
                        .frame(width: 48, height: 48)
                        .background(.ultraThinMaterial, in: Circle())
                        .contentTransition(.symbolEffect(.replace))
                }
                .buttonStyle(.plain)
                Spacer()
                speedPicker
            }
        }
        .padding(.horizontal, 16).padding(.bottom, 52)
    }

    private var speedPicker: some View {
        HStack(spacing: 6) {
            ForEach([("¼×", Float(0.25)), ("½×", Float(0.5)), ("1×", Float(1.0))], id: \.1) { label, value in
                let selected = model.speed == value
                Button {
                    model.speed = value
                    if model.isPlaying { model.player.rate = value }
                } label: {
                    Text(label)
                        .font(.system(size: 14, weight: selected ? .bold : .regular))
                        .foregroundColor(selected ? .black : .white)
                        .padding(.horizontal, 14).padding(.vertical, 7)
                        .background(Capsule().fill(selected ? Color.white : Color.white.opacity(0.2)))
                        .animation(.easeInOut(duration: 0.15), value: selected)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 12).padding(.vertical, 8)
        .background(.ultraThinMaterial, in: Capsule())
    }

    private func formatTime(_ s: Double) -> String {
        let t = max(0, Int(s))
        return String(format: "%d:%02d", t / 60, t % 60)
    }
}

// MARK: - Thumbnail scrubber

struct ThumbnailScrubber: View {
    @ObservedObject var model: PlayerModel
    @State private var isDragging = false
    @State private var dragX: CGFloat = 0

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .bottom) {
                // Frame preview popup (shown while dragging)
                if isDragging, let preview = previewImage {
                    Image(uiImage: preview)
                        .resizable()
                        .scaledToFit()
                        .frame(height: 96)
                        .cornerRadius(8)
                        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.white.opacity(0.4), lineWidth: 1))
                        .shadow(color: .black.opacity(0.6), radius: 8)
                        .offset(x: previewOffsetX(in: geo.size.width))
                        .offset(y: -80)
                        .transition(.scale(scale: 0.85).combined(with: .opacity))
                }

                // Film strip + indicator
                ZStack(alignment: .leading) {
                    // Thumbnails
                    HStack(spacing: 0) {
                        ForEach(model.thumbnails.indices, id: \.self) { i in
                            Image(uiImage: model.thumbnails[i])
                                .resizable().scaledToFill()
                                .frame(width: geo.size.width / CGFloat(model.thumbnails.count),
                                       height: geo.size.height)
                                .clipped()
                        }
                    }
                    .cornerRadius(8)
                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.white.opacity(0.2), lineWidth: 1))
                    // Dim unplayed area
                    .overlay(
                        GeometryReader { g in
                            let p = model.duration > 0 ? model.currentTime / model.duration : 0
                            Rectangle()
                                .fill(Color.black.opacity(0.35))
                                .frame(width: g.size.width * CGFloat(1 - p))
                                .frame(maxWidth: .infinity, alignment: .trailing)
                                .cornerRadius(8)
                                .animation(.linear(duration: 0.05), value: model.currentTime)
                        }
                    )

                    // Position indicator
                    let progress = model.duration > 0 ? model.currentTime / model.duration : 0
                    let xPos = (CGFloat(progress) * geo.size.width).clamped(to: 0...(geo.size.width - 3))

                    ZStack {
                        Capsule()
                            .fill(Color.white.opacity(isDragging ? 0.5 : 0.2))
                            .frame(width: isDragging ? 11 : 7, height: geo.size.height + (isDragging ? 20 : 12))
                            .blur(radius: 4)
                        Capsule()
                            .fill(Color.white)
                            .frame(width: isDragging ? 4 : 3, height: geo.size.height + (isDragging ? 16 : 10))
                            .shadow(color: .black.opacity(0.5), radius: 2)
                    }
                    .offset(x: xPos - 2)
                    .animation(isDragging ? .none : .linear(duration: 0.05), value: model.currentTime)
                    .animation(.spring(response: 0.2), value: isDragging)
                }
                .contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { value in
                            if !isDragging {
                                withAnimation(.spring(response: 0.2)) { isDragging = true }
                                model.isScrubbing = true
                                model.player.pause()
                            }
                            dragX = value.location.x
                            let progress = (value.location.x / geo.size.width).clamped(to: 0...1)
                            let time = progress * model.duration
                            model.currentTime = time
                            model.seek(to: time)
                        }
                        .onEnded { _ in
                            withAnimation(.spring(response: 0.2)) { isDragging = false }
                            model.isScrubbing = false
                            if model.isPlaying { model.player.rate = model.speed }
                        }
                )
            }
        }
    }

    // Nearest pre-generated thumbnail for the current drag position
    private var previewImage: UIImage? {
        guard !model.thumbnails.isEmpty, model.duration > 0 else { return nil }
        let progress = (model.currentTime / model.duration).clamped(to: 0...1)
        let idx = Int(progress * Double(model.thumbnails.count - 1))
        return model.thumbnails[idx.clamped(to: 0...(model.thumbnails.count - 1))]
    }

    // Keep the popup inside screen bounds
    private func previewOffsetX(in width: CGFloat) -> CGFloat {
        let progress = model.duration > 0 ? model.currentTime / model.duration : 0
        let center = CGFloat(progress) * width
        let popupHalf: CGFloat = 44
        return (center - popupHalf).clamped(to: 0...(width - popupHalf * 2))
    }
}

// MARK: - AVPlayerViewController wrapper (no native controls)

private struct VideoContainer: UIViewControllerRepresentable {
    let player: AVPlayer
    func makeUIViewController(context: Context) -> AVPlayerViewController {
        let vc = AVPlayerViewController()
        vc.player = player
        vc.showsPlaybackControls = false
        vc.videoGravity = .resizeAspect
        return vc
    }
    func updateUIViewController(_ vc: AVPlayerViewController, context: Context) {}
}
