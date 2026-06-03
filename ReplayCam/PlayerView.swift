import SwiftUI
import AVKit

struct PlayerView: View {
    let url: URL
    @Environment(\.dismiss) private var dismiss

    @State private var player: AVPlayer
    @State private var speed: Float = 1.0
    @State private var isPlaying = true

    private let speeds: [(label: String, value: Float)] = [
        ("¼×", 0.25), ("½×", 0.5), ("1×", 1.0)
    ]

    init(url: URL) {
        self.url = url
        self._player = State(wrappedValue: AVPlayer(url: url))
    }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            VideoPlayer(player: player)
                .ignoresSafeArea()

            overlayControls
        }
        .onAppear  { startPlayback() }
        .onDisappear { player.pause() }
    }

    // MARK: - Overlay

    private var overlayControls: some View {
        VStack {
            // Top: close (left) + export (right)
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
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(.ultraThinMaterial, in: Capsule())
                    .shadow(color: .black.opacity(0.3), radius: 4)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 16)
            .padding(.top, 56)

            Spacer()

            // Bottom: speed picker only
            speedPicker
                .padding(.bottom, 48)
        }
    }

    private var speedPicker: some View {
        HStack(spacing: 8) {
            ForEach(speeds, id: \.value) { option in
                let selected = speed == option.value
                Button {
                    speed = option.value
                    // Seek back to start when switching speed for clearer preview
                    if option.value < 1.0 && player.currentItem?.duration == player.currentTime() {
                        player.seek(to: .zero)
                    }
                    player.rate = option.value
                } label: {
                    Text(option.label)
                        .font(.system(size: 15, weight: selected ? .bold : .regular))
                        .foregroundColor(selected ? .black : .white)
                        .padding(.horizontal, 18).padding(.vertical, 9)
                        .background(
                            Capsule()
                                .fill(selected ? Color.white : Color.white.opacity(0.2))
                        )
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 20).padding(.vertical, 12)
        .background(.ultraThinMaterial, in: Capsule())
    }

    // MARK: - Helpers

    private func startPlayback() {
        player.play()
        // Loop to beginning when clip ends
        NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime,
            object: player.currentItem,
            queue: .main
        ) { [weak player] _ in
            guard let player else { return }
            player.seek(to: .zero) { _ in
                player.rate = self.speed
            }
        }
    }
}
