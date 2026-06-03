import SwiftUI

struct HomeView: View {
    @ObservedObject private var store = ClipStore.shared
    @State private var showCamera = false

    var body: some View {
        NavigationStack {
            ZStack {
                // Background gradient
                LinearGradient(
                    colors: [Color(white: 0.06), Color(white: 0.02)],
                    startPoint: .top, endPoint: .bottom
                )
                .ignoresSafeArea()

                VStack(alignment: .leading, spacing: 24) {
                    // ── Header ─────────────────────────────────────────────
                    VStack(alignment: .leading, spacing: 4) {
                        Text("ReplayCam")
                            .font(.system(size: 30, weight: .bold, design: .rounded))
                            .foregroundColor(.white)
                        Text("動作延遲回放")
                            .font(.subheadline)
                            .foregroundColor(.white.opacity(0.5))
                    }
                    .padding(.top, 16)

                    // ── Camera card (large) ────────────────────────────────
                    Button { showCamera = true } label: {
                        cameraCard
                    }
                    .buttonStyle(.plain)

                    // ── Library + Settings ─────────────────────────────────
                    HStack(spacing: 16) {
                        NavigationLink(destination: DateLibraryView()) {
                            secondaryCard(
                                icon: "calendar",
                                title: "日期記錄",
                                subtitle: store.clips.isEmpty
                                    ? "尚無片段"
                                    : "\(store.clips.count) 個片段"
                            )
                        }
                        .buttonStyle(.plain)

                        NavigationLink(destination: SettingsView()) {
                            secondaryCard(
                                icon: "gearshape.fill",
                                title: "設定",
                                subtitle: "延遲與偏好"
                            )
                        }
                        .buttonStyle(.plain)
                    }

                    Spacer()
                }
                .padding(.horizontal, 20)
            }
            .toolbar(.hidden, for: .navigationBar)
        }
        .fullScreenCover(isPresented: $showCamera) {
            ContentView()
        }
    }

    // MARK: - Cards

    private var cameraCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            Image(systemName: "camera.fill")
                .font(.system(size: 28))
                .foregroundColor(.white)

            Spacer()

            VStack(alignment: .leading, spacing: 4) {
                Text("延遲錄影")
                    .font(.title2).fontWeight(.bold)
                    .foregroundColor(.white)
                Text("設定延遲秒數，即時觀看動作回放")
                    .font(.caption)
                    .foregroundColor(.white.opacity(0.75))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(24)
        .frame(height: 170)
        .background(
            LinearGradient(
                colors: [Color.blue, Color.blue.opacity(0.65)],
                startPoint: .topLeading, endPoint: .bottomTrailing
            ),
            in: RoundedRectangle(cornerRadius: 22)
        )
    }

    private func secondaryCard(icon: String, title: String, subtitle: String) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Image(systemName: icon)
                .font(.system(size: 22))
                .foregroundColor(.white.opacity(0.85))

            Spacer()

            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.headline)
                    .foregroundColor(.white)
                Text(subtitle)
                    .font(.caption)
                    .foregroundColor(.white.opacity(0.55))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(20)
        .frame(height: 140)
        .background(Color.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 22))
        .overlay(
            RoundedRectangle(cornerRadius: 22)
                .stroke(Color.white.opacity(0.12), lineWidth: 1)
        )
    }
}
