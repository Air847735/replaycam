import SwiftUI

struct SettingsView: View {
    @AppStorage("defaultDelay") private var defaultDelay: Double = 3.0
    @AppStorage("recordingFPS") private var recordingFPS: Int = 30
    @AppStorage("defaultCamera") private var defaultCamera: String = "back"
    @ObservedObject private var store = ClipStore.shared
    @State private var showDeleteConfirm = false

    private var supportedFPS: [Int] {
        let supports120 = ProcessInfo.processInfo.processorCount >= 6
        return supports120 ? [30, 60, 120] : [30, 60]
    }

    var body: some View {
        ZStack {
            // ── Background: same brand gradient + pattern as HomeView ────
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

            List {
                // ── Recording ────────────────────────────────────────────────
                Section("錄影") {
                    VStack(alignment: .leading, spacing: 10) {
                        HStack {
                            Label("預設延遲", systemImage: "clock")
                            Spacer()
                            Text("\(Int(defaultDelay)) 秒")
                                .font(.system(size: 15, weight: .bold, design: .rounded))
                                .foregroundColor(.blue)
                                .monospacedDigit()
                        }
                        Slider(value: $defaultDelay, in: 1...30, step: 1)
                            .tint(.blue)
                        Text("開啟拍攝時預設的延遲秒數")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    .padding(.vertical, 4)

                    VStack(alignment: .leading, spacing: 10) {
                        Label("錄影幀率", systemImage: "speedometer")
                        Picker("", selection: $recordingFPS) {
                            ForEach(supportedFPS, id: \.self) { fps in
                                Text("\(fps) fps").tag(fps)
                            }
                        }
                        .pickerStyle(.segmented)
                        Text(fpsDescription)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    .padding(.vertical, 4)

                    VStack(alignment: .leading, spacing: 10) {
                        Label("預設鏡頭", systemImage: "camera")
                        Picker("", selection: $defaultCamera) {
                            Text("後鏡頭").tag("back")
                            Text("前鏡頭").tag("front")
                        }
                        .pickerStyle(.segmented)
                        Text("開啟拍攝時預設使用的鏡頭")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    .padding(.vertical, 4)
                }

                // ── Storage ──────────────────────────────────────────────────
                Section("儲存空間") {
                    LabeledContent("片段數量", value: "\(store.clips.count) 個")
                    LabeledContent("佔用空間", value: storageUsed)

                    Button(role: .destructive) {
                        showDeleteConfirm = true
                    } label: {
                        Label("清除所有片段", systemImage: "trash")
                    }
                    .disabled(store.clips.isEmpty)
                }

                // ── About ────────────────────────────────────────────────────
                Section("關於") {
                    LabeledContent("版本", value: appVersion)
                    LabeledContent("建置", value: appBuild)
                }
            }
            .scrollContentBackground(.hidden)
        }
        .navigationTitle("設定")
        .confirmationDialog("確定要刪除所有片段嗎？", isPresented: $showDeleteConfirm, titleVisibility: .visible) {
            Button("刪除全部", role: .destructive) {
                store.clips.forEach { store.delete($0) }
            }
            Button("取消", role: .cancel) {}
        } message: {
            Text("此操作無法還原，相簿中的影片不受影響")
        }
    }

    // MARK: - Helpers

    private var fpsDescription: String {
        switch recordingFPS {
        case 120: return "超高幀率，最多可儲存 20 秒，需 iPhone 13 Pro 以上"
        case 60:  return "高幀率，最多可儲存 30 秒，動作細節更流暢"
        default:  return "標準幀率，最多可儲存 35 秒"
        }
    }

    private var storageUsed: String {
        let fm = FileManager.default
        guard let files = try? fm.contentsOfDirectory(
            at: ClipStore.clipsDirectory,
            includingPropertiesForKeys: [.fileSizeKey]
        ) else { return "0 MB" }

        let bytes = files.compactMap {
            (try? $0.resourceValues(forKeys: [.fileSizeKey]))?.fileSize
        }.reduce(0, +)

        let mb = Double(bytes) / 1_048_576
        return mb < 1 ? String(format: "%.0f KB", mb * 1024)
                      : String(format: "%.1f MB", mb)
    }

    private var appVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "-"
    }

    private var appBuild: String {
        Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "-"
    }
}
