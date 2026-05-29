import SwiftUI

struct ContentView: View {
    @StateObject private var camera = CameraManager()
    @State private var selectedDelay: Double = 3.0
    @State private var showSaveOptions = false

    // Draggable preview: base position (nil = default bottom-right)
    @State private var previewBase: CGPoint? = nil
    // Live translation while finger is down; auto-resets to .zero on release
    @GestureState private var dragTranslation: CGSize = .zero

    private let delayOptions = [1.0, 3.0, 5.0, 10.0, 15.0, 30.0]
    private let saveOptions = [5.0, 10.0, 15.0, 30.0]

    var body: some View {
        GeometryReader { geo in
            ZStack {
                delayedBackground(size: geo.size)
                controls
                let base = previewBase ?? defaultPreviewPos(in: geo.size)
                let livePos = clampPreview(
                    CGPoint(x: base.x + dragTranslation.width,
                            y: base.y + dragTranslation.height),
                    in: geo.size
                )
                realtimePreview
                    .position(livePos)
                    .gesture(
                        DragGesture()
                            .updating($dragTranslation) { value, state, _ in
                                state = value.translation
                            }
                            .onEnded { value in
                                previewBase = clampPreview(
                                    CGPoint(x: base.x + value.translation.width,
                                            y: base.y + value.translation.height),
                                    in: geo.size
                                )
                            }
                    )
                    .onChange(of: geo.size) { _, newSize in
                        // Re-clamp after device rotation
                        if let current = previewBase {
                            previewBase = clampPreview(current, in: newSize)
                        }
                    }
            }
        }
        .ignoresSafeArea()
        .onAppear {
            camera.setDelay(selectedDelay)
            camera.checkPermissions()
        }
        .confirmationDialog("選擇要儲存的長度", isPresented: $showSaveOptions, titleVisibility: .visible) {
            ForEach(saveOptions, id: \.self) { duration in
                Button("最近 \(Int(duration)) 秒") { camera.saveRecentFrames(duration: duration) }
            }
            Button("取消", role: .cancel) {}
        } message: {
            Text("選擇要儲存的影片長度")
        }
        .alert("儲存成功", isPresented: $camera.showSuccess) {
            Button("確定", role: .cancel) {}
        } message: {
            Text("影片已成功儲存到相簿")
        }
    }

    // MARK: - Preview positioning

    /// Default centre position: bottom-right corner, clear of the control panel.
    private func defaultPreviewPos(in size: CGSize) -> CGPoint {
        CGPoint(x: size.width - 130, y: size.height - 210)
    }

    /// Keep the preview centre at least 80 pt from every edge.
    private func clampPreview(_ point: CGPoint, in size: CGSize) -> CGPoint {
        CGPoint(
            x: min(max(point.x, 80), size.width  - 80),
            y: min(max(point.y, 80), size.height - 80)
        )
    }

    // MARK: - Subviews

    @ViewBuilder
    private func delayedBackground(size: CGSize) -> some View {
        Group {
            if let img = camera.delayedImage {
                Image(uiImage: img)
                    .resizable()
                    .scaledToFill()
            } else {
                cameraPlaceholder
            }
        }
        .frame(width: size.width, height: size.height)
        .clipped()
        .ignoresSafeArea()
    }

    private var cameraPlaceholder: some View {
        Color.black.overlay(
            VStack(spacing: 16) {
                if camera.isRunning {
                    ProgressView().scaleEffect(2).tint(.white)
                    Text("載入中...").foregroundColor(.white)
                } else {
                    Text("相機未啟動").foregroundColor(.white)
                    if !camera.errorMessage.isEmpty {
                        Text(camera.errorMessage)
                            .foregroundColor(.red).font(.caption).multilineTextAlignment(.center)
                            .padding(.horizontal)
                    }
                }
            }
        )
    }

    /// 底部控制列（不含即時視窗）
    private var controls: some View {
        VStack {
            Spacer()
            controlPanel
        }
    }

    /// 可拖曳的即時視窗（獨立在 ZStack 中，預設右下角）
    private var realtimePreview: some View {
        VStack(spacing: 8) {
            Group {
                if let img = camera.realtimeImage {
                    let portrait = img.size.height > img.size.width
                    Image(uiImage: img)
                        .resizable()
                        .scaledToFill()
                        .frame(width:  portrait ? 112 : 200,
                               height: portrait ? 200 : 150)
                        .clipped()
                } else {
                    Color.gray.overlay(ProgressView().tint(.white))
                        .frame(width: 200, height: 150)
                }
            }
            .cornerRadius(12)
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.yellow, lineWidth: 3))
            .shadow(color: .black.opacity(0.5), radius: 10)

            Text("即時畫面")
                .font(.caption).fontWeight(.bold).foregroundColor(.white)
                .padding(.horizontal, 12).padding(.vertical, 4)
                .background(Color.red).cornerRadius(8)
        }
        .padding(20)
    }

    private var controlPanel: some View {
        VStack(spacing: 15) {
            HStack(spacing: 20) {
                delayPicker
                bufferStatus
            }
            saveButton
        }
        .padding(.bottom, 30)
    }

    private var delayPicker: some View {
        Menu {
            ForEach(delayOptions, id: \.self) { delay in
                Button {
                    selectedDelay = delay
                    camera.setDelay(delay)
                } label: {
                    HStack {
                        Text("\(Int(delay)) 秒")
                        if delay == selectedDelay { Image(systemName: "checkmark") }
                    }
                }
            }
        } label: {
            Label("延遲: \(Int(selectedDelay))秒", systemImage: "clock")
                .padding()
                .background(Color.black.opacity(0.7))
                .foregroundColor(.white)
                .cornerRadius(10)
        }
    }

    private var bufferStatus: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("緩衝: \(String(format: "%.1f", camera.bufferDuration))秒")
            Text("幀數: \(camera.bufferFrameCount)")
            if camera.isSaving { Text("儲存中...").foregroundColor(.green) }
        }
        .font(.caption).foregroundColor(.white)
        .padding(8).background(Color.black.opacity(0.7)).cornerRadius(8)
    }

    private var saveButton: some View {
        let ready = camera.bufferFrameCount >= 10 && !camera.isSaving
        return Button { showSaveOptions = true } label: {
            HStack(spacing: 12) {
                Image(systemName: "arrow.down.circle.fill").font(.system(size: 20))
                Text("儲存影片 (\(camera.bufferFrameCount)幀)")
                    .font(.system(size: 16, weight: .semibold))
            }
            .foregroundColor(.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .background(camera.isSaving ? Color.orange : ready ? Color.blue : Color.gray)
            .cornerRadius(12)
            .shadow(color: .black.opacity(0.3), radius: 5, y: 3)
        }
        .disabled(!ready)
        .buttonStyle(.plain)
        .padding(.horizontal, 20)
    }
}
