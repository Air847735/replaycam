import SwiftUI
import AVKit
import Charts

// AVPlayerViewController wrapper with no playback controls (removes AirPlay button)
private struct AnalysisVideoContainer: UIViewControllerRepresentable {
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

private struct AngleSelection: Identifiable {
    let name: String
    var id: String { name }
}

// MARK: - Analysis result page

struct PoseAnalysisResultView: View {
    let clip: SavedClip

    @Environment(\.dismiss) private var dismiss
    @State private var analyses: [FrameAnalysis] = []
    @State private var progress: Double = 0
    @State private var isAnalyzing = true
    @State private var currentTime: Double = 0
    @State private var player: AVPlayer?
    @State private var timeObserver: Any?
    @State private var selectedAngleName: String?
    @State private var isExporting = false
    @State private var exportProgress: Double = 0
    @State private var exportResult: ExportResultAlert?

    private struct ExportResultAlert: Identifiable {
        let id = UUID()
        let message: String
        let isError: Bool
    }

    private var currentAnalysis: FrameAnalysis? {
        guard !analyses.isEmpty else { return nil }
        return analyses.min(by: { abs($0.time - currentTime) < abs($1.time - currentTime) })
    }

    var body: some View {
        ZStack(alignment: .topLeading) {
            Color.black.ignoresSafeArea()

            if isAnalyzing {
                analyzeProgress
            } else {
                resultContent
            }

            // Back button + export button
            GeometryReader { geo in
                let isPortrait = geo.size.width < geo.size.height
                let topY = geo.safeAreaInsets.top + (isPortrait ? 52 : 30)

                Button {
                    if let obs = timeObserver { player?.removeTimeObserver(obs) }
                    dismiss()
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(.white)
                        .frame(width: 36, height: 36)
                        .background(.ultraThinMaterial, in: Circle())
                }
                .position(x: geo.safeAreaInsets.leading + 38, y: topY)

                if !isAnalyzing {
                    Button {
                        Task { await exportWithSkeleton() }
                    } label: {
                        Image(systemName: "square.and.arrow.down")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundColor(.white)
                            .frame(width: 36, height: 36)
                            .background(.ultraThinMaterial, in: Circle())
                    }
                    .disabled(isExporting)
                    .position(x: geo.size.width - geo.safeAreaInsets.trailing - 38, y: topY)
                }
            }

            // Export progress overlay
            if isExporting {
                VStack(spacing: 12) {
                    ProgressView(value: exportProgress)
                        .tint(.purple)
                        .frame(width: 200)
                    Text("匯出骨架影片… \(Int(exportProgress * 100))%")
                        .font(.caption)
                        .foregroundColor(.white)
                }
                .padding(20)
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16))
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .ignoresSafeArea()
        .alert(item: $exportResult) { result in
            Alert(
                title: Text(result.isError ? "匯出失敗" : "已儲存到相簿"),
                message: Text(result.message),
                dismissButton: .default(Text("好"))
            )
        }
        .task { await runAnalysis() }
    }

    // MARK: - Progress view

    private var analyzeProgress: some View {
        VStack(spacing: 24) {
            RunningFigureView()
                .frame(width: 120, height: 120)

            Text("分析中...")
                .font(.title2.bold())
                .foregroundColor(.white)

            ProgressView(value: progress)
                .tint(.purple)
                .frame(width: 240)

            Text("\(Int(progress * 100))%")
                .font(.caption)
                .foregroundColor(.white.opacity(0.5))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Results

    private var resultContent: some View {
        GeometryReader { geo in
            if geo.size.width > geo.size.height {
                // Landscape: video left, right panel switches between grid and chart
                HStack(spacing: 0) {
                    if let player {
                        AnalysisVideoContainer(player: player)
                            .overlay(skeletonOverlay, alignment: .center)
                            .frame(width: geo.size.width * 0.58)
                    }
                    ZStack(alignment: .top) {
                        landscapeGradient
                        // Grid always underneath
                        angleGrid(currentAnalysis?.angles ?? [], columns: 4)
                            .padding(12)

                        // Chart panel slides over the grid; drag down reveals grid behind
                        if let name = selectedAngleName {
                            LandscapeChartPanel(
                                name: name,
                                onDismiss: {
                                    withAnimation(.easeInOut(duration: 0.2)) { selectedAngleName = nil }
                                }
                            ) {
                                AngleChartContent(
                                    angleName: name,
                                    analyses: analyses,
                                    currentTime: currentTime,
                                    onSeek: { time in
                                        player?.pause()
                                        player?.seek(to: CMTime(seconds: time, preferredTimescale: 600),
                                                     toleranceBefore: .zero, toleranceAfter: .zero)
                                    }
                                )
                                .padding(.horizontal, 12)
                                .padding(.bottom, 12)
                            }
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                            .transition(.move(edge: .bottom).combined(with: .opacity))
                        }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .clipped()
                }
            } else {
                // Portrait: video top, grid fills remaining space; chart via sheet
                VStack(spacing: 0) {
                    if let player {
                        AnalysisVideoContainer(player: player)
                            .aspectRatio(9/16, contentMode: .fit)
                            .overlay(skeletonOverlay, alignment: .center)
                    }
                    angleGrid(currentAnalysis?.angles ?? [], columns: 2)
                        .padding(12)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .background(landscapeGradient)
                }
                .sheet(item: Binding(
                    get: { selectedAngleName.map { AngleSelection(name: $0) } },
                    set: { selectedAngleName = $0?.name }
                )) { selection in
                    AngleChartSheet(
                        angleName: selection.name,
                        analyses: analyses,
                        currentTime: currentTime,
                        onSeek: { time in
                            player?.pause()
                            player?.seek(to: CMTime(seconds: time, preferredTimescale: 600),
                                         toleranceBefore: .zero, toleranceAfter: .zero)
                        }
                    )
                    .presentationDetents([.medium, .large])
                    .presentationDragIndicator(.visible)
                }
            }
        }
    }

    private var landscapeGradient: some View {
        LinearGradient(
            colors: [
                Color(red: 0.06, green: 0.04, blue: 0.14),
                Color(red: 0.04, green: 0.08, blue: 0.18),
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
        .ignoresSafeArea()
    }

    // MARK: - Skeleton overlay

    @ViewBuilder
    private var skeletonOverlay: some View {
        if let frame = currentAnalysis,
           let pose = frame.poses.first {
            PoseOverlayView(poses: [pose], imageSize: frame.imageSize)
                .allowsHitTesting(false)
        }
    }

    @ViewBuilder
    private func angleCard(name: String, degrees: Double?, valid: Bool) -> some View {
        VStack(spacing: 4) {
            Text(name)
                .font(.caption)
                .foregroundColor(.white.opacity(0.55))
            if let deg = degrees {
                Text("\(Int(deg))°")
                    .font(.system(size: 28, weight: .bold, design: .rounded))
                    .foregroundColor(color(for: deg))
                Image(systemName: "chart.xyaxis.line")
                    .font(.system(size: 10))
                    .foregroundColor(.white.opacity(0.3))
            } else {
                Text("未辨識到")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(.white.opacity(0.25))
                    .padding(.vertical, 4)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.white.opacity(valid ? 0.06 : 0.03),
                    in: RoundedRectangle(cornerRadius: 12))
    }

    private func color(for degrees: Double) -> Color {
        switch degrees {
        case ..<90:  return .red
        case ..<120: return .orange
        case ..<160: return .green
        default:     return .blue
        }
    }

    // MARK: - No pose placeholder

    private var noPoseView: some View {
        VStack(spacing: 8) {
            Image(systemName: "person.slash")
                .font(.system(size: 32))
                .foregroundColor(.white.opacity(0.25))
            Text("未偵測到人體")
                .font(.subheadline)
                .foregroundColor(.white.opacity(0.4))
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 32)
    }

    // MARK: - Angle grid

    // Fixed 8-slot grid — always shown; invalid slots display "未辨識到"
    private static let allJointNames = ["左肘","右肘","左膝","右膝","左髖","右髖","左肩","右肩"]

    @ViewBuilder
    private func angleGrid(_ angles: [JointAngle], columns: Int = 2) -> some View {
        let byName = Dictionary(uniqueKeysWithValues: angles.map { ($0.name, $0) })
        let names = Self.allJointNames
        let rowCount = (names.count + columns - 1) / columns
        let rows = (0..<rowCount).map { r in
            Array(names[(r * columns)..<min((r + 1) * columns, names.count)])
        }
        Grid(horizontalSpacing: 8, verticalSpacing: 8) {
            ForEach(Array(rows.enumerated()), id: \.offset) { _, rowNames in
                GridRow {
                    ForEach(rowNames, id: \.self) { name in
                        let angle = byName[name]
                        let isValid = angle?.isValid == true
                        Button { selectedAngleName = name } label: {
                            angleCard(name: name, degrees: isValid ? angle?.degrees : nil, valid: isValid)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    // MARK: - Export with skeleton

    private func exportWithSkeleton() async {
        guard !analyses.isEmpty else { return }
        isExporting = true
        exportProgress = 0
        do {
            let outURL = try await SkeletonVideoExporter.export(url: clip.url, analyses: analyses) { p in
                Task { @MainActor in exportProgress = p }
            }
            try await SkeletonVideoExporter.saveToPhotoLibrary(url: outURL)
            exportResult = ExportResultAlert(message: "含骨架的影片已儲存到相簿", isError: false)
        } catch {
            exportResult = ExportResultAlert(message: error.localizedDescription, isError: true)
        }
        isExporting = false
    }

    // MARK: - Analysis task

    private func runAnalysis() async {
        let analyzer = VideoAnalyzer()
        analyses = await analyzer.analyze(url: clip.url) { p in
            Task { @MainActor in progress = p }
        }

        let p = AVPlayer(url: clip.url)
        let interval = CMTime(seconds: 1.0 / 30.0, preferredTimescale: 600)
        let obs = p.addPeriodicTimeObserver(forInterval: interval, queue: .main) { [weak p] time in
            guard p != nil else { return }
            currentTime = time.seconds
        }
        timeObserver = obs
        player = p
        isAnalyzing = false
        p.play()
    }
}

// MARK: - Landscape chart panel wrapper (swipe-down to dismiss, like a sheet)

private struct LandscapeChartPanel<Content: View>: View {
    let name: String
    let onDismiss: () -> Void
    @ViewBuilder let content: () -> Content

    @State private var dragOffset: CGFloat = 0

    private let bg = LinearGradient(
        colors: [Color(red: 0.06, green: 0.04, blue: 0.14),
                 Color(red: 0.04, green: 0.08, blue: 0.18)],
        startPoint: .topLeading, endPoint: .bottomTrailing
    )

    private let topInset: CGFloat = 44  // gap showing grid behind

    var body: some View {
        GeometryReader { geo in
            let visibleH = geo.size.height - topInset
            ZStack(alignment: .top) {
                // Background extends below visible area so no gap appears during drag
                bg
                    .frame(width: geo.size.width, height: visibleH + 300)
                    .clipShape(UnevenRoundedRectangle(topLeadingRadius: 16, bottomLeadingRadius: 0,
                                                      bottomTrailingRadius: 0, topTrailingRadius: 16))

                // Content constrained to visible height
                VStack(spacing: 0) {
                    VStack(spacing: 6) {
                        RoundedRectangle(cornerRadius: 3)
                            .fill(Color.white.opacity(0.3))
                            .frame(width: 36, height: 4)
                        Text(name)
                            .font(.system(size: 14, weight: .bold))
                            .foregroundColor(.white)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)

                    content()
                }
                .frame(width: geo.size.width, height: visibleH)
            }
            .offset(y: topInset + max(0, dragOffset))
            .gesture(
                DragGesture()
                    .onChanged { v in dragOffset = v.translation.height }
                    .onEnded { v in
                        if v.translation.height > 60 {
                            onDismiss()
                        } else {
                            withAnimation(.spring(response: 0.3)) { dragOffset = 0 }
                        }
                    }
            )
        }
    }
}

// MARK: - Shared chart content (used both inline in landscape and in sheet for portrait)

struct AngleChartContent: View {
    let angleName: String
    let analyses: [FrameAnalysis]
    let currentTime: Double
    var onSeek: ((Double) -> Void)? = nil

    @State private var isDragging = false
    @State private var dragTime: Double? = nil

    private struct DataPoint: Identifiable {
        let id = UUID()
        let time: Double
        let degrees: Double
        let segment: Int
    }

    private var dataPoints: [DataPoint] {
        var result: [DataPoint] = []
        var seg = 0
        var prevWasValid = false
        for frame in analyses {
            let valid = frame.angles.first(where: { $0.name == angleName })?.isValid == true
            if valid {
                if !prevWasValid && !result.isEmpty { seg += 1 }
                let deg = frame.angles.first(where: { $0.name == angleName })!.degrees
                result.append(DataPoint(time: frame.time, degrees: deg, segment: seg))
            }
            prevWasValid = valid
        }
        return result
    }

    private var stats: (min: Double, max: Double, avg: Double)? {
        let vals = dataPoints.map(\.degrees)
        guard !vals.isEmpty else { return nil }
        return (vals.min()!, vals.max()!, vals.reduce(0, +) / Double(vals.count))
    }

    var body: some View {
        VStack(spacing: 12) {
            // Stats row
            if let s = stats {
                HStack(spacing: 0) {
                    Button {
                        if let t = dataPoints.min(by: { $0.degrees < $1.degrees })?.time { onSeek?(t) }
                    } label: {
                        statCell(label: "最小", value: "\(Int(s.min))°", color: .red, tappable: true)
                    }.buttonStyle(.plain)
                    Divider().frame(height: 32).background(Color.white.opacity(0.15))
                    statCell(label: "平均", value: "\(Int(s.avg))°", color: .white)
                    Divider().frame(height: 32).background(Color.white.opacity(0.15))
                    Button {
                        if let t = dataPoints.max(by: { $0.degrees < $1.degrees })?.time { onSeek?(t) }
                    } label: {
                        statCell(label: "最大", value: "\(Int(s.max))°", color: .blue, tappable: true)
                    }.buttonStyle(.plain)
                }
            }

            // Chart
            Chart {
                ForEach(dataPoints) { pt in
                    LineMark(
                        x: .value("時間", pt.time),
                        y: .value("角度", pt.degrees),
                        series: .value("s", pt.segment)
                    )
                    .foregroundStyle(Color.purple)
                    .lineStyle(StrokeStyle(lineWidth: 2))

                    AreaMark(
                        x: .value("時間", pt.time),
                        y: .value("角度", pt.degrees)
                    )
                    .foregroundStyle(
                        LinearGradient(colors: [.purple.opacity(0.25), .clear],
                                       startPoint: .top, endPoint: .bottom)
                    )
                }
                let markerTime = dragTime ?? currentTime
                RuleMark(x: .value("現在", markerTime))
                    .foregroundStyle(isDragging ? Color.yellow.opacity(0.9) : Color.white.opacity(0.6))
                    .lineStyle(StrokeStyle(lineWidth: isDragging ? 2 : 1.5, dash: [4, 3]))
                    .annotation(position: .top, alignment: .center) {
                        if let cur = dataPoints.min(by: { abs($0.time - markerTime) < abs($1.time - markerTime) }) {
                            Text("\(Int(cur.degrees))°")
                                .font(.system(size: 12, weight: .bold, design: .rounded))
                                .foregroundColor(isDragging ? .yellow : .white)
                                .padding(.horizontal, 6).padding(.vertical, 2)
                                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 6))
                        }
                    }
            }
            .chartOverlay { proxy in
                GeometryReader { geo in
                    Rectangle().fill(.clear).contentShape(Rectangle())
                        .gesture(
                            DragGesture(minimumDistance: 0)
                                .onChanged { value in
                                    isDragging = true
                                    let plotOriginX = geo[proxy.plotAreaFrame].origin.x
                                    let x = value.location.x - plotOriginX
                                    if let t: Double = proxy.value(atX: x) {
                                        let clamped = max(0, min(t, dataPoints.last?.time ?? t))
                                        dragTime = clamped
                                        onSeek?(clamped)
                                    }
                                }
                                .onEnded { _ in
                                    isDragging = false
                                    dragTime = nil
                                }
                        )
                }
            }
            .chartXAxis {
                AxisMarks(values: .automatic(desiredCount: 5)) { val in
                    AxisValueLabel {
                        if let t = val.as(Double.self) {
                            Text(String(format: "%.1fs", t)).font(.caption2).foregroundColor(.white.opacity(0.5))
                        }
                    }
                    AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5)).foregroundStyle(Color.white.opacity(0.1))
                }
            }
            .chartYAxis {
                AxisMarks(values: .automatic(desiredCount: 4)) { val in
                    AxisValueLabel {
                        if let d = val.as(Double.self) {
                            Text("\(Int(d))°").font(.caption2).foregroundColor(.white.opacity(0.5))
                        }
                    }
                    AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5)).foregroundStyle(Color.white.opacity(0.1))
                }
            }
            .frame(maxHeight: .infinity)
        }
    }

    func statCell(label: String, value: String, color: Color, tappable: Bool = false) -> some View {
        VStack(spacing: 2) {
            Text(label).font(.caption2).foregroundColor(.white.opacity(0.45))
            Text(value)
                .font(.system(size: 20, weight: .bold, design: .rounded))
                .foregroundColor(color)
                .underline(tappable, color: color.opacity(0.4))
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
        .background(Color.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 10))
    }
}

// MARK: - Angle chart sheet (portrait)

struct AngleChartSheet: View {
    let angleName: String
    let analyses: [FrameAnalysis]
    let currentTime: Double
    var onSeek: ((Double) -> Void)? = nil

    var body: some View {
        NavigationStack {
            ZStack {
                Color(white: 0.08).ignoresSafeArea()
                AngleChartContent(
                    angleName: angleName,
                    analyses: analyses,
                    currentTime: currentTime,
                    onSeek: onSeek
                )
                .padding(16)
            }
            .navigationTitle(angleName)
            .navigationBarTitleDisplayMode(.inline)
            .toolbarColorScheme(.dark, for: .navigationBar)
        }
    }
}
