import SwiftUI

struct HomeView: View {
    @ObservedObject private var store = ClipStore.shared
    @State private var showCamera = false

    var body: some View {
        NavigationStack {
            ZStack {
                // ── Background: TISS brand gradient + pattern overlay ───────
                LinearGradient(
                    colors: [
                        Color(red: 0.04, green: 0.16, blue: 0.30),  // deep navy
                        Color(red: 0.02, green: 0.22, blue: 0.22)   // deep teal
                    ],
                    startPoint: .topLeading, endPoint: .bottomTrailing
                )
                .ignoresSafeArea()

                Image("tiss_pattern")
                    .resizable(resizingMode: .tile)
                    .ignoresSafeArea()
                    .opacity(0.13)

                // ── Content ─────────────────────────────────────────────────
                VStack(alignment: .leading, spacing: 24) {

                    // ── App name ───────────────────────────────────────────
                    Text("ReplayCam")
                        .font(.system(size: 30, weight: .bold, design: .rounded))
                        .foregroundColor(.white)
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

                    // ── TISS Logo footer ───────────────────────────────────
                    HStack {
                        Spacer()
                        Image("tiss_logo")
                            .resizable()
                            .scaledToFit()
                            .frame(height: 36)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 8)
                            .background(Color.white.opacity(0.95),
                                        in: RoundedRectangle(cornerRadius: 8))
                        Spacer()
                    }
                    .padding(.bottom, 12)
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
        ZStack(alignment: .bottomLeading) {
            // Pattern accent in card
            Image("tiss_pattern")
                .resizable(resizingMode: .tile)
                .opacity(0.12)
                .clipShape(RoundedRectangle(cornerRadius: 22))

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
        }
        .frame(maxWidth: .infinity)
        .frame(height: 170)
        .background(
            LinearGradient(
                colors: [Color(red: 0.1, green: 0.45, blue: 0.8),
                         Color(red: 0.05, green: 0.6, blue: 0.5)],
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
