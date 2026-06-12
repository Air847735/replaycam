import SwiftUI

struct HomeView: View {
    @ObservedObject private var store = ClipStore.shared
    @State private var showCamera = false

    var body: some View {
        NavigationStack {
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

                GeometryReader { geo in
                    if geo.size.width > geo.size.height {
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

    // MARK: - Portrait

    private var portraitLayout: some View {
        VStack(alignment: .leading, spacing: 14) {
            // Title
            Text("ReplayCam")
                .font(.system(size: 28, weight: .bold, design: .rounded))
                .foregroundColor(.white)
                .padding(.top, 8)

            // 延遲錄影
            Button { showCamera = true } label: {
                mainCard(
                    icon: "camera.fill",
                    title: "延遲錄影",
                    subtitle: "設定延遲秒數，即時觀看動作回放",
                    gradient: LinearGradient(
                        colors: [Color(red: 0.1, green: 0.45, blue: 0.8),
                                 Color(red: 0.05, green: 0.6, blue: 0.5)],
                        startPoint: .topLeading, endPoint: .bottomTrailing
                    )
                )
            }
            .buttonStyle(.plain)

            // 骨架分析 — same size
            NavigationLink(destination: PoseAnalysisView()) {
                mainCard(
                    icon: "figure.run",
                    title: "骨架分析",
                    subtitle: "選取影片，分析關節角度與動作數據",
                    gradient: LinearGradient(
                        colors: [Color(red: 0.4, green: 0.15, blue: 0.7),
                                 Color(red: 0.2, green: 0.1, blue: 0.5)],
                        startPoint: .topLeading, endPoint: .bottomTrailing
                    )
                )
            }
            .buttonStyle(.plain)

            // 日期記錄 + 設定
            HStack(spacing: 14) {
                NavigationLink(destination: DateLibraryView()) {
                    tinyCard(
                        icon: "calendar",
                        title: "日期記錄",
                        subtitle: store.clips.isEmpty ? "尚無片段" : "\(store.clips.count) 個片段"
                    )
                }.buttonStyle(.plain)

                NavigationLink(destination: SettingsView()) {
                    tinyCard(icon: "gearshape.fill", title: "設定", subtitle: "延遲與偏好")
                }.buttonStyle(.plain)
            }
            .frame(height: 100)

            Spacer(minLength: 0)

            // Logo
            Image("tiss_logo")
                .resizable()
                .scaledToFit()
                .frame(height: 44)
                .padding(.horizontal, 20)
                .padding(.vertical, 12)
                .frame(maxWidth: .infinity)
                .background(Color.white.opacity(0.94), in: RoundedRectangle(cornerRadius: 16))
                .padding(.bottom, 4)
        }
        .padding(.horizontal, 20)
        .safeAreaPadding(.all)
    }

    // MARK: - Landscape

    private var landscapeLayout: some View {
        VStack(spacing: 12) {
            // Title row
            HStack {
                Text("ReplayCam")
                    .font(.system(size: 22, weight: .bold, design: .rounded))
                    .foregroundColor(.white)
                Spacer()
                Image("tiss_logo")
                    .resizable()
                    .scaledToFit()
                    .frame(height: 26)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(Color.white.opacity(0.94), in: RoundedRectangle(cornerRadius: 9))
            }

            // Cards: camera left, pose+row right — both fill remaining height
            HStack(spacing: 12) {
                // Left: camera fills full height
                Button { showCamera = true } label: {
                    landscapeMainCard(
                        icon: "camera.fill",
                        title: "延遲錄影",
                        subtitle: "設定延遲秒數，即時觀看動作回放",
                        gradient: LinearGradient(
                            colors: [Color(red: 0.1, green: 0.45, blue: 0.8),
                                     Color(red: 0.05, green: 0.6, blue: 0.5)],
                            startPoint: .topLeading, endPoint: .bottomTrailing
                        )
                    )
                }
                .buttonStyle(.plain)
                .frame(maxWidth: .infinity, maxHeight: .infinity)

                // Right: pose (top, bigger) + library | settings (bottom row)
                VStack(spacing: 12) {
                    NavigationLink(destination: PoseAnalysisView()) {
                        landscapeMainCard(
                            icon: "figure.run",
                            title: "骨架分析",
                            subtitle: "分析關節角度與動作數據",
                            gradient: LinearGradient(
                                colors: [Color(red: 0.4, green: 0.15, blue: 0.7),
                                         Color(red: 0.2, green: 0.1, blue: 0.5)],
                                startPoint: .topLeading, endPoint: .bottomTrailing
                            )
                        )
                    }
                    .buttonStyle(.plain)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)

                    HStack(spacing: 12) {
                        NavigationLink(destination: DateLibraryView()) {
                            tinyCard(
                                icon: "calendar",
                                title: "日期記錄",
                                subtitle: store.clips.isEmpty ? "尚無片段" : "\(store.clips.count) 個片段"
                            )
                        }.buttonStyle(.plain)

                        NavigationLink(destination: SettingsView()) {
                            tinyCard(icon: "gearshape.fill", title: "設定", subtitle: "延遲與偏好")
                        }.buttonStyle(.plain)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .frame(maxHeight: .infinity)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 10)
        .safeAreaPadding(.all)
    }

    // MARK: - Card components

    /// Fluid card for landscape — fills its container height
    private func landscapeMainCard(icon: String, title: String, subtitle: String,
                                   gradient: LinearGradient) -> some View {
        ZStack(alignment: .bottomLeading) {
            Image("tiss_pattern")
                .resizable(resizingMode: .tile)
                .opacity(0.12)
                .clipShape(RoundedRectangle(cornerRadius: 18))

            VStack(alignment: .leading, spacing: 0) {
                Image(systemName: icon)
                    .font(.system(size: 22))
                    .foregroundColor(.white)
                Spacer()
                VStack(alignment: .leading, spacing: 3) {
                    Text(title)
                        .font(.headline.bold())
                        .foregroundColor(.white)
                    Text(subtitle)
                        .font(.caption)
                        .foregroundColor(.white.opacity(0.75))
                }
            }
            .padding(16)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(gradient, in: RoundedRectangle(cornerRadius: 18))
    }

    /// Large card with tiss_pattern overlay, icon top-left, text bottom-left
    private func mainCard(icon: String, title: String, subtitle: String,
                          gradient: LinearGradient) -> some View {
        ZStack(alignment: .bottomLeading) {
            Image("tiss_pattern")
                .resizable(resizingMode: .tile)
                .opacity(0.12)
                .clipShape(RoundedRectangle(cornerRadius: 22))

            VStack(alignment: .leading, spacing: 0) {
                Image(systemName: icon)
                    .font(.system(size: 28))
                    .foregroundColor(.white)
                Spacer()
                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(.title2.bold())
                        .foregroundColor(.white)
                    Text(subtitle)
                        .font(.caption)
                        .foregroundColor(.white.opacity(0.75))
                }
            }
            .padding(22)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxWidth: .infinity)
        .frame(height: 180)
        .background(gradient, in: RoundedRectangle(cornerRadius: 22))
    }

    /// Medium card — same icon-top / text-bottom style, no pattern
    private func smallCard(icon: String, title: String, subtitle: String,
                           gradient: LinearGradient) -> some View {
        ZStack(alignment: .bottomLeading) {
            VStack(alignment: .leading, spacing: 0) {
                Image(systemName: icon)
                    .font(.system(size: 22))
                    .foregroundColor(.white)
                Spacer()
                VStack(alignment: .leading, spacing: 3) {
                    Text(title)
                        .font(.headline)
                        .foregroundColor(.white)
                    Text(subtitle)
                        .font(.caption)
                        .foregroundColor(.white.opacity(0.7))
                }
            }
            .padding(18)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(gradient, in: RoundedRectangle(cornerRadius: 18))
    }

    /// Small plain card — icon top, text bottom, glass style
    private func tinyCard(icon: String, title: String, subtitle: String) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Image(systemName: icon)
                .font(.system(size: 20))
                .foregroundColor(.white.opacity(0.85))
            Spacer()
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.subheadline.bold())
                    .foregroundColor(.white)
                Text(subtitle)
                    .font(.caption)
                    .foregroundColor(.white.opacity(0.55))
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .background(Color.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 18))
        .overlay(RoundedRectangle(cornerRadius: 18).stroke(Color.white.opacity(0.12), lineWidth: 1))
    }
}
