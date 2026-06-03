import SwiftUI
import AVKit
import AVFoundation

// MARK: - Player view

struct PlayerView: View {
    let url: URL
    @Environment(\.dismiss) private var dismiss

    @State private var player: AVPlayer
    @State private var speed: Float = 1.0
    @State private var isPlaying = true
    @State private var currentTime: Double = 0
    @State private var duration: Double = 1
    @State private var thumbnails: [UIImage] = []
    @State private var isScrubbing = false
    @State private var timeObserverToken: Any?

    private let thumbnailCount = 30

    init(url: URL) {
        self.url = url
        self._player = State(wrappedValue: AVPlayer(url: url))
    }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            // Video — no native controls (we build our own)
            VideoContainer(player: player)
                .ignoresSafeArea()
                .onTapGesture { togglePlayPause() }

            overlayControls
        }
        .onAppear  { setupPlayer() }
        .onDisappear { teardownPlayer() }
    }

    // MARK: - Overlay

    private var overlayControls: some View {
        VStack {
            topBar
            Spacer()
            bottomControls
        }
    }

    // Close (left) + Export (right)
    private var topBar: some View {
        HStack {
            Button {
                player.pause()
                dismiss()
            } label: {
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
                    Image(systemName: "square.and.arrow.up")
                        .font(.system(size: 13, weight: .semibold))
                    Text("匯出")
                        .font(.system(size: 14, weight: .semibold))
                }
                .foregroundColor(.white)
                .padding(.horizontal, 14).padding(.vertical, 8)
                .background(.ultraThinMaterial, in: Capsule())
                .shadow(color: .black.opacity(0.3), radius: 4)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 16)
        .padding(.top, 56)
    }

    private var bottomControls: some View {
        VStack(spacing: 14) {

            // Time labels
            HStack {
                Text(formatTime(currentTime))
                Spacer()
                Text(formatTime(duration))
            }
            .font(.system(size: 12, weight: .medium, design: .monospaced))
            .foregroundColor(.white.opacity(0.75))
            .padding(.horizontal, 4)

            // Thumbnail scrubber
            Group {
                if thumbnails.isEmpty {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color.white.opacity(0.08))
                        .overlay(ProgressView().tint(.white).scaleEffect(0.8))
                } else {
                    ThumbnailScrubber(
                        thumbnails: thumbnails,
                        currentTime: $currentTime,
                        duration: duration,
                        onScrubStart: {
                            isScrubbing = true
                            player.pause()
                        },
                        onScrubChange: { time in
                            player.seek(
                                to: CMTime(seconds: time, preferredTimescale: 600),
                                toleranceBefore: .zero,
                                toleranceAfter:  .zero
                            )
                        },
                        onScrubEnd: {
                            isScrubbing = false
                            if isPlaying { player.rate = speed }
                        }
                    )
                }
            }
            .frame(height: 64)

            // Play/pause  +  speed picker
            HStack(spacing: 0) {
                Button { togglePlayPause() } label: {
                    Image(systemName: isPlaying ? "pause.fill" : "play.fill")
                        .font(.system(size: 20))
                        .foregroundColor(.white)
                        .frame(width: 48, height: 48)
                        .background(.ultraThinMaterial, in: Circle())
                }
                .buttonStyle(.plain)

                Spacer()

                speedPicker
            }
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 52)
    }

    private var speedPicker: some View {
        let options: [(String, Float)] = [("¼×", 0.25), ("½×", 0.5), ("1×", 1.0)]
        return HStack(spacing: 6) {
            ForEach(options, id: \.1) { label, value in
                let selected = speed == value
                Button {
                    speed = value
                    if isPlaying { player.rate = value }
                } label: {
                    Text(label)
                        .font(.system(size: 14, weight: selected ? .bold : .regular))
                        .foregroundColor(selected ? .black : .white)
                        .padding(.horizontal, 14).padding(.vertical, 7)
                        .background(Capsule().fill(selected ? Color.white : Color.white.opacity(0.2)))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 12).padding(.vertical, 8)
        .background(.ultraThinMaterial, in: Capsule())
    }

    // MARK: - Controls

    private func togglePlayPause() {
        isPlaying ? player.pause() : { player.rate = speed }()
        isPlaying.toggle()
    }

    private func formatTime(_ s: Double) -> String {
        let t = max(0, Int(s))
        return String(format: "%d:%02d", t / 60, t % 60)
    }

    // MARK: - Setup / teardown

    private func setupPlayer() {
        // Load duration
        Task {
            let asset = AVURLAsset(url: url)
            if let d = try? await asset.load(.duration) { duration = max(1, d.seconds) }
        }

        // Generate thumbnails in background
        Task.detached(priority: .userInitiated) { [url] in
            let images = await Self.generateThumbnails(url: url, count: thumbnailCount)
            await MainActor.run { thumbnails = images }
        }

        // Periodic time observer (30 fps)
        let interval = CMTime(value: 1, timescale: 30)
        timeObserverToken = player.addPeriodicTimeObserver(forInterval: interval, queue: .main) { time in
            guard !isScrubbing else { return }
            currentTime = time.seconds
        }

        // Start playing + loop
        player.play()
        NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime,
            object: player.currentItem,
            queue: .main
        ) { [weak player] _ in
            player?.seek(to: .zero) { _ in player?.rate = speed }
        }
    }

    private func teardownPlayer() {
        player.pause()
        if let token = timeObserverToken { player.removeTimeObserver(token) }
    }

    private static func generateThumbnails(url: URL, count: Int) async -> [UIImage] {
        let asset = AVURLAsset(url: url)
        guard let dur = try? await asset.load(.duration), dur.seconds > 0 else { return [] }

        let gen = AVAssetImageGenerator(asset: asset)
        gen.appliesPreferredTrackTransform = true
        gen.maximumSize = CGSize(width: 80, height: 144)
        // Slightly loose tolerance for faster generation
        let tol = CMTime(value: 1, timescale: 10)
        gen.requestedTimeToleranceBefore = tol
        gen.requestedTimeToleranceAfter  = tol

        let total = dur.seconds
        var images: [UIImage] = []
        images.reserveCapacity(count)
        for i in 0..<count {
            let t = total * Double(i) / Double(count - 1)
            let time = CMTime(seconds: t, preferredTimescale: 600)
            if let cg = try? gen.copyCGImage(at: time, actualTime: nil) {
                images.append(UIImage(cgImage: cg))
            }
        }
        return images
    }
}

// MARK: - Video container (no native playback controls)

private struct VideoContainer: UIViewControllerRepresentable {
    let player: AVPlayer

    func makeUIViewController(context: Context) -> AVPlayerViewController {
        let vc = AVPlayerViewController()
        vc.player = player
        vc.showsPlaybackControls = false
        vc.videoGravity = .resizeAspect
        return vc
    }

    func updateUIViewController(_ vc: AVPlayerViewController, context: Context) {
        vc.player = player
    }
}

// MARK: - Thumbnail scrubber

struct ThumbnailScrubber: View {
    let thumbnails: [UIImage]
    @Binding var currentTime: Double
    let duration: Double
    let onScrubStart:  () -> Void
    let onScrubChange: (Double) -> Void
    let onScrubEnd:    () -> Void

    @State private var isDragging = false

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {

                // ── Film strip ──────────────────────────────────────────────
                HStack(spacing: 0) {
                    ForEach(thumbnails.indices, id: \.self) { i in
                        Image(uiImage: thumbnails[i])
                            .resizable()
                            .scaledToFill()
                            .frame(
                                width:  geo.size.width / CGFloat(thumbnails.count),
                                height: geo.size.height
                            )
                            .clipped()
                    }
                }
                .cornerRadius(8)
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(Color.white.opacity(0.25), lineWidth: 1)
                )

                // ── Position indicator ──────────────────────────────────────
                let progress = duration > 0 ? currentTime / duration : 0
                let xPos = (CGFloat(progress) * geo.size.width).clamped(to: 0...(geo.size.width - 3))

                ZStack {
                    // Glow
                    Capsule()
                        .fill(Color.white.opacity(0.35))
                        .frame(width: 7, height: geo.size.height + 16)
                        .blur(radius: 3)
                    // Bar
                    Capsule()
                        .fill(Color.white)
                        .frame(width: 3, height: geo.size.height + 12)
                        .shadow(color: .black.opacity(0.4), radius: 2)
                }
                .offset(x: xPos - 1.5)
                .animation(isDragging ? nil : .easeOut(duration: 0.08), value: currentTime)
            }
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        if !isDragging {
                            isDragging = true
                            onScrubStart()
                        }
                        let progress = (value.location.x / geo.size.width)
                            .clamped(to: 0...1)
                        let time = progress * duration
                        currentTime = time
                        onScrubChange(time)
                    }
                    .onEnded { _ in
                        isDragging = false
                        onScrubEnd()
                    }
            )
        }
    }
}
