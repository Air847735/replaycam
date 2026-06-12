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
                GeometryReader { geo in
                    let isLandscape = geo.size.width > geo.size.height
                    if isLandscape {
                        landscapeLayout
                    } else {
                        portraitLayout
                    }
                }
            }
            .toolbar(.hidden, for: .navigationBar)
        }
        .fullScreenCover(isPresented: $showCamera) {
            ContentView()
        }
    }

    // MARK: - Layouts

    private var portraitLayout: some View {
        VStack(alignment: .leading, spacing: 24) {
            Text("ReplayCam")
                .font(.system(size: 30, weight: .bold, design: .rounded))
                .foregroundColor(.white)
                .padding(.top, 16)

            Button { showCamera = true } label: { cameraCard }
                .buttonStyle(.plain)

            HStack(spacing: 16) {
                NavigationLink(destination: DateLibraryView()) {
                    secondaryCard(icon: "calendar", title: "日期記錄",
                                  subtitle: store.clips.isEmpty ? "尚無片段" : "\(store.clips.count) 個片段")
                }.buttonStyle(.plain)
                NavigationLink(destination: SettingsView()) {
                    secondaryCard(icon: "gearshape.fill", title: "設定", subtitle: "延遲與偏好")
                }.buttonStyle(.plain)
            }

            NavigationLink(destination: PoseAnalysisView()) {
                poseAnalysisCard
            }.buttonStyle(.plain)

            Spacer()
            logoFooter.padding(.bottom, 12)
        }
        .padding(.horizontal, 20)
        .safeAreaPadding(.all)
    }

    private var landscapeLayout: some View {
        VStack(alignment: .leading, spacing: 20) {
            // Title row: ReplayCam ←→ logo
            HStack(alignment: .center) {
                Text("ReplayCam")
                    .font(.system(size: 26, weight: .bold, design: .rounded))
                    .foregroundColor(.white)
                Spacer()
                Image("tiss_logo")
                    .resizable()
                    .scaledToFit()
                    .frame(height: 32)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .background(Color.white.opacity(0.94), in: RoundedRectangle(cornerRadius: 12))
            }

            Button { showCamera = true } label: { cameraCard }
                .buttonStyle(.plain)

            HStack(spacing: 16) {
                NavigationLink(destination: DateLibraryView()) {
                    secondaryCard(icon: "calendar", title: "日期記錄",
                                  subtitle: store.clips.isEmpty ? "尚無片段" : "\(store.clips.count) 個片段")
                }.buttonStyle(.plain)
                NavigationLink(destination: SettingsView()) {
                    secondaryCard(icon: "gearshape.fill", title: "設定", subtitle: "延遲與偏好")
                }.buttonStyle(.plain)
                NavigationLink(destination: PoseAnalysisView()) {
                    secondaryCard(icon: "figure.run", title: "骨架分析", subtitle: "關節角度分析")
                }.buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .safeAreaPadding(.all)
    }

    private var poseAnalysisCard: some View {
        HStack(spacing: 16) {
            Image(systemName: "figure.run")
                .font(.system(size: 28))
                .foregroundColor(.white)
                .frame(width: 44)
            VStack(alignment: .leading, spacing: 4) {
                Text("骨架分析")
                    .font(.headline).foregroundColor(.white)
                Text("選取影片，分析關節角度與動作數據")
                    .font(.caption).foregroundColor(.white.opacity(0.7))
            }
            Spacer()
            Image(systemName: "chevron.right")
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(.white.opacity(0.5))
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 16)
        .background(
            LinearGradient(
                colors: [Color(red: 0.4, green: 0.15, blue: 0.7),
                         Color(red: 0.2, green: 0.1, blue: 0.5)],
                startPoint: .leading, endPoint: .trailing
            ),
            in: RoundedRectangle(cornerRadius: 18)
        )
    }

    private var logoFooter: some View {
        Image("tiss_logo")
            .resizable()
            .scaledToFit()
            .frame(height: 44)
            .padding(.horizontal, 24)
            .padding(.vertical, 12)
            .frame(maxWidth: .infinity)
            .background(Color.white.opacity(0.94), in: RoundedRectangle(cornerRadius: 16))
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
