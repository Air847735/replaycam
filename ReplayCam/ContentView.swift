import AVFoundation
import SwiftUI

struct ContentView: View {
    @StateObject private var camera = CameraManager()
    @AppStorage("defaultDelay") private var defaultDelay: Double = 3.0
    @AppStorage("recordingFPS") private var recordingFPS: Int = 30
    @AppStorage("defaultCamera") private var defaultCamera: String = "back"
    @State private var selectedDelay: Double = 3.0   // local copy, does not write back to AppStorage
    @State private var saveDuration: Double = 10.0
    @State private var isMirrored: Bool = false
    @State private var poseEnabled: Bool = false

    @State private var controlsVisible = true
    @Environment(\.dismiss) private var dismiss

    // Draggable + resizable preview
    @State private var previewBase: CGPoint? = nil
    @GestureState private var dragTranslation: CGSize = .zero
    @State private var previewScale: CGFloat = 1.0
    @GestureState private var pinchDelta: CGFloat = 1.0

    private let previewScaleRange: ClosedRange<CGFloat> = 0.8...3.0

    private var saveRange: ClosedRange<Double> {
        switch recordingFPS {
        case 120: return 3...20
        case 60:  return 3...30
        default:  return 3...35
        }
    }

    var body: some View {
        GeometryReader { geo in
            let insets = geo.safeAreaInsets
            ZStack {
                // ── Delayed feed ────────────────────────────────────────────
                delayedBackground(size: geo.size)
                    .contentShape(Rectangle())
                    .onTapGesture {
                        withAnimation(.easeInOut(duration: 0.22)) {
                            controlsVisible.toggle()
                        }
                    }

                // ── Back button (top-left, shown with controls) ─────────────
                if controlsVisible {
                    VStack {
                        HStack {
                            Button { dismiss() } label: {
                                Image(systemName: "chevron.left")
                                    .font(.system(size: 19, weight: .semibold))
                                    .foregroundColor(.white)
                                    .frame(width: 48, height: 48)
                                    .background(.ultraThinMaterial, in: Circle())
                                    .shadow(color: .black.opacity(0.3), radius: 4)
                            }
                            .padding(.leading, max(insets.leading + 12, 20))
                            .padding(.top, max(insets.top + 20, 28))
                            Spacer()
                        }
                        Spacer()
                    }
                }

                // ── Pose overlay on delayed feed ────────────────────────────
                if poseEnabled && !camera.poseResults.isEmpty {
                    PoseOverlayView(poses: camera.poseResults,
                                    imageSize: camera.poseFrameSize)
                        .ignoresSafeArea()
                        .allowsHitTesting(false)
                }

                // ── Collapsed hint ──────────────────────────────────────────
                if !controlsVisible {
                    VStack {
                        Spacer()
                        Text("⏱ \(Int(selectedDelay))s")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundColor(.white)
                            .padding(.horizontal, 14).padding(.vertical, 7)
                            .background(.ultraThinMaterial, in: Capsule())
                            .padding(.bottom, 20)
                    }
                    .transition(.opacity)
                }

                // ── Control panel ───────────────────────────────────────────
                if controlsVisible {
                    VStack {
                        Spacer()
                        controlPanel(safeAreaInsets: insets)
                    }
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                }

                // ── Draggable realtime preview ──────────────────────────────
                let base = previewBase ?? defaultPreviewPos(in: geo.size)
                let livePos = clampPreview(
                    CGPoint(x: base.x + dragTranslation.width,
                            y: base.y + dragTranslation.height),
                    in: geo.size
                )
                let liveScale = (previewScale * pinchDelta)
                    .clamped(to: previewScaleRange)
                realtimePreview(scale: liveScale)
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
                        .simultaneously(with:
                            MagnificationGesture()
                                .updating($pinchDelta) { value, state, _ in
                                    state = value
                                }
                                .onEnded { value in
                                    previewScale = (previewScale * value)
                                        .clamped(to: previewScaleRange)
                                }
                        )
                    )
                    .onChange(of: geo.size) { _, newSize in
                        if let current = previewBase {
                            previewBase = clampPreview(current, in: newSize)
                        }
                    }
            }
        }
        .ignoresSafeArea()
        .onAppear {
            selectedDelay = defaultDelay
            camera.setDelay(selectedDelay)
            camera.applyFPSSetting(recordingFPS)
            camera.cameraPosition = (defaultCamera == "front") ? .front : .back
            isMirrored = false
            camera.checkPermissions()
            saveDuration = min(saveDuration, saveRange.upperBound)
        }
        .onChange(of: camera.currentPosition) { _, _ in
            isMirrored = false
        }
        .alert("儲存成功", isPresented: $camera.showSuccess) {
            Button("確定", role: .cancel) {}
        } message: {
            Text("影片已成功儲存到相簿")
        }
    }

    // MARK: - Preview positioning

    private func defaultPreviewPos(in size: CGSize) -> CGPoint {
        CGPoint(x: size.width * 0.85, y: size.height * 0.60)
    }

    private func clampPreview(_ point: CGPoint, in size: CGSize) -> CGPoint {
        CGPoint(
            x: min(max(point.x, 80), size.width  - 80),
            y: min(max(point.y, 80), size.height - 80)
        )
    }

    // MARK: - Delayed background

    @ViewBuilder
    private func delayedBackground(size: CGSize) -> some View {
        Group {
            if let img = camera.delayedImage {
                Image(uiImage: img)
                    .resizable()
                    .scaledToFill()
                    .scaleEffect(x: isMirrored ? -1 : 1, y: 1)
            } else {
                cameraPlaceholder
            }
        }
        .frame(width: size.width, height: size.height)
        .clipped()
        .ignoresSafeArea()
    }

    /// Seconds still needed before the buffer contains a frame old enough to show.
    private var waitSeconds: Int {
        guard camera.isRunning else { return 0 }
        return max(0, Int(ceil(selectedDelay - camera.bufferDuration)))
    }

    private var cameraPlaceholder: some View {
        Color.black.overlay(
            VStack(spacing: 16) {
                if !camera.isRunning {
                    // Camera not yet set up
                    ProgressView().scaleEffect(2).tint(.white)
                    Text("相機啟動中...").foregroundColor(.white)
                    if !camera.errorMessage.isEmpty {
                        Text(camera.errorMessage)
                            .foregroundColor(.red).font(.caption)
                            .multilineTextAlignment(.center).padding(.horizontal)
                    }
                } else if waitSeconds > 0 {
                    // Countdown until buffer has enough history
                    Text("\(waitSeconds)")
                        .font(.system(size: 96, weight: .bold, design: .rounded))
                        .foregroundColor(.white)
                        .monospacedDigit()
                        .contentTransition(.numericText(countsDown: true))
                        .animation(.easeInOut(duration: 0.35), value: waitSeconds)
                    Text("秒後顯示延遲畫面")
                        .font(.subheadline)
                        .foregroundColor(.white.opacity(0.65))
                } else {
                    // Buffer ready but first frame not decoded yet
                    ProgressView().scaleEffect(1.5).tint(.white)
                }
            }
        )
    }

    // MARK: - Realtime preview

    private func realtimePreview(scale: CGFloat) -> some View {
        // Base dimensions before scaling
        let baseW: CGFloat
        let baseH: CGFloat
        if let img = camera.realtimeImage {
            let portrait = img.size.height > img.size.width
            baseW = portrait ? 90  : 160
            baseH = portrait ? 160 : 100
        } else {
            baseW = 160; baseH = 100
        }
        let w = baseW * scale
        let h = baseH * scale

        return ZStack(alignment: .topLeading) {
            Group {
                if let img = camera.realtimeImage {
                    Image(uiImage: img)
                        .resizable()
                        .scaledToFill()
                        .scaleEffect(x: isMirrored ? -1 : 1, y: 1)
                        .frame(width: w, height: h)
                        .clipped()
                } else {
                    Color.black.opacity(0.5)
                        .overlay(ProgressView().tint(.white))
                        .frame(width: w, height: h)
                }
            }
            .cornerRadius(10)
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(Color.white.opacity(0.5), lineWidth: 1.5)
            )
            .shadow(color: .black.opacity(0.45), radius: 8, y: 2)

            // LIVE badge
            HStack(spacing: 4) {
                Circle().fill(Color.red).frame(width: 6, height: 6)
                Text("LIVE")
                    .font(.system(size: 9, weight: .bold, design: .rounded))
                    .foregroundColor(.white)
            }
            .padding(.horizontal, 6).padding(.vertical, 3)
            .background(Color.black.opacity(0.55), in: RoundedRectangle(cornerRadius: 4))
            .padding(6)
        }
    }

    // MARK: - Control panel

    private func controlPanel(safeAreaInsets: EdgeInsets) -> some View {
        let isLandscape = UIScreen.main.bounds.width > UIScreen.main.bounds.height
        let bottomPad   = max(safeAreaInsets.bottom, 12)
        let sidePad     = max(safeAreaInsets.leading, 20)

        return HStack(alignment: .center, spacing: 14) {
            // Camera switch + mirror buttons
            if isLandscape {
                HStack(spacing: 8) { cameraButton; mirrorButton; poseButton }
            } else {
                VStack(spacing: 8) { cameraButton; mirrorButton; poseButton }
            }

            // Sliders
            VStack(spacing: isLandscape ? 8 : 12) {
                delaySlider
                saveDurationSlider
            }

            saveButton
        }
        .padding(.horizontal, sidePad)
        .padding(.top, isLandscape ? 10 : 14)
        .padding(.bottom, isLandscape ? max(bottomPad, 8) : bottomPad + 8)
        .background(
            Rectangle()
                .fill(.ultraThinMaterial)
                .ignoresSafeArea(edges: .bottom)
        )
    }

    private var cameraButton: some View {
        Button { camera.switchCamera() } label: {
            Image(systemName: "arrow.triangle.2.circlepath.camera")
                .font(.system(size: 18, weight: .medium))
                .foregroundColor(.white)
                .frame(width: 40, height: 40)
                .background(.ultraThinMaterial, in: Circle())
        }
        .buttonStyle(.plain)
    }

    private var mirrorButton: some View {
        Button { isMirrored.toggle() } label: {
            Image(systemName: "arrow.left.and.right.righttriangle.left.righttriangle.right")
                .font(.system(size: 15, weight: .medium))
                .foregroundColor(isMirrored ? .yellow : .white)
                .frame(width: 40, height: 40)
                .background(.ultraThinMaterial, in: Circle())
        }
        .buttonStyle(.plain)
    }

    private var poseButton: some View {
        Button {
            poseEnabled.toggle()
            camera.poseEnabled = poseEnabled
            if !poseEnabled { camera.poseResults = [] }
        } label: {
            Image(systemName: "figure.stand")
                .font(.system(size: 17, weight: .medium))
                .foregroundColor(poseEnabled ? .green : .white)
                .frame(width: 40, height: 40)
                .background(.ultraThinMaterial, in: Circle())
        }
        .buttonStyle(.plain)
    }

    // MARK: - Shared slider row

    /// Single-line layout: [icon label]  [━━●━━━━━]  [value]
    private func sliderRow(
        icon: String,
        label: String,
        valueText: String,
        slider: some View
    ) -> some View {
        HStack(spacing: 10) {
            Label(label, systemImage: icon)
                .font(.system(size: 13))
                .foregroundColor(.white.opacity(0.7))
                .fixedSize()

            slider

            Text(valueText)
                .font(.system(size: 14, weight: .bold, design: .rounded))
                .foregroundColor(.white)
                .monospacedDigit()
                .frame(width: 34, alignment: .trailing)
        }
    }

    // MARK: - Delay slider

    private var delaySlider: some View {
        sliderRow(
            icon: "clock",
            label: "延遲",
            valueText: "\(Int(selectedDelay))s",
            slider: Slider(value: $selectedDelay, in: 1...30, step: 1)
                .tint(.white)
                .onChange(of: selectedDelay) { _, newVal in camera.setDelay(newVal) }
        )
    }

    // MARK: - Save duration slider

    private var saveDurationSlider: some View {
        sliderRow(
            icon: "clock.arrow.circlepath",
            label: "儲存長度",
            valueText: "\(Int(saveDuration))s",
            slider: Slider(value: $saveDuration, in: saveRange, step: 1)
                .tint(.white)
        )
    }

    // MARK: - Save button (compact vertical, sits beside sliders)

    private var saveButton: some View {
        let ready = camera.bufferFrameCount >= 10 && !camera.isSaving
        return Button {
            let duration = min(saveDuration, camera.bufferDuration)
            camera.saveRecentFrames(duration: duration)
        } label: {
            VStack(spacing: 7) {
                if camera.isSaving {
                    ProgressView().scaleEffect(0.85).tint(.white)
                        .frame(width: 24, height: 24)
                } else {
                    Image(systemName: "arrow.down.circle.fill")
                        .font(.system(size: 24))
                }
                Text(camera.isSaving ? "儲存中" : ready ? "儲存" : "準備中")
                    .font(.system(size: 11, weight: .semibold))
                    .lineLimit(1)
            }
            .foregroundColor(.white)
            .frame(width: 62)
            .padding(.vertical, 14)
            .background(
                RoundedRectangle(cornerRadius: 14)
                    .fill(camera.isSaving ? Color.orange : ready ? Color.blue : Color.gray.opacity(0.4))
            )
        }
        .disabled(!ready)
        .buttonStyle(.plain)
    }
}

// MARK: - Helpers

extension Comparable {
    func clamped(to range: ClosedRange<Self>) -> Self {
        min(max(self, range.lowerBound), range.upperBound)
    }
}
