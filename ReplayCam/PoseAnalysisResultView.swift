import SwiftUI
import AVKit
import Charts

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

            // Back button
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
            .padding(.top, 56)
            .padding(.leading, 20)
        }
        .ignoresSafeArea()
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
                // Landscape: video left, angle panel right
                HStack(spacing: 0) {
                    if let player {
                        VideoPlayer(player: player)
                            .overlay(skeletonOverlay, alignment: .center)
                            .frame(width: geo.size.width * 0.58)
                    }
                    ScrollView {
                        angleGrid(currentAnalysis?.angles ?? [], columns: 2)
                            .padding(12)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(landscapeGradient)
                }
            } else {
                // Portrait: video top, 2-column grid below
                VStack(spacing: 0) {
                    if let player {
                        VideoPlayer(player: player)
                            .aspectRatio(9/16, contentMode: .fit)
                            .overlay(skeletonOverlay, alignment: .center)
                    }
                    ScrollView {
                        angleGrid(currentAnalysis?.angles ?? [], columns: 4)
                            .padding(12)
                    }
                    .frame(maxWidth: .infinity)
                    .background(landscapeGradient)
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
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
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
        let cols = Array(repeating: GridItem(.flexible(), spacing: 8), count: columns)
        return LazyVGrid(columns: cols, spacing: 8) {
            ForEach(Self.allJointNames, id: \.self) { name in
                let angle = byName[name]
                let isValid = angle?.isValid == true
                Group {
                    if isValid, let angle {
                        Button { selectedAngleName = angle.name } label: {
                            angleCard(name: angle.name, degrees: angle.degrees, valid: true)
                        }
                        .buttonStyle(.plain)
                    } else {
                        angleCard(name: name, degrees: nil, valid: false)
                    }
                }
            }
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

// MARK: - Angle chart sheet

struct AngleChartSheet: View {
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
    }

    private var dataPoints: [DataPoint] {
        analyses.compactMap { frame in
            guard let angle = frame.angles.first(where: { $0.name == angleName }),
                  angle.isValid else { return nil }
            return DataPoint(time: frame.time, degrees: angle.degrees)
        }
    }

    private var stats: (min: Double, max: Double, avg: Double)? {
        let vals = dataPoints.map(\.degrees)
        guard !vals.isEmpty else { return nil }
        return (vals.min()!, vals.max()!, vals.reduce(0, +) / Double(vals.count))
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Color(white: 0.08).ignoresSafeArea()

                VStack(spacing: 20) {
                    // Stats row
                    if let s = stats {
                        HStack(spacing: 0) {
                            statCell(label: "最小", value: "\(Int(s.min))°", color: .red)
                            Divider().frame(height: 36).background(Color.white.opacity(0.15))
                            statCell(label: "平均", value: "\(Int(s.avg))°", color: .white)
                            Divider().frame(height: 36).background(Color.white.opacity(0.15))
                            statCell(label: "最大", value: "\(Int(s.max))°", color: .blue)
                        }
                        .padding(.horizontal)
                    }

                    // Chart
                    Chart {
                        ForEach(dataPoints) { pt in
                            LineMark(
                                x: .value("時間", pt.time),
                                y: .value("角度", pt.degrees)
                            )
                            .foregroundStyle(
                                LinearGradient(
                                    colors: [.purple, .blue],
                                    startPoint: .leading, endPoint: .trailing
                                )
                            )
                            .lineStyle(StrokeStyle(lineWidth: 2))

                            AreaMark(
                                x: .value("時間", pt.time),
                                y: .value("角度", pt.degrees)
                            )
                            .foregroundStyle(
                                LinearGradient(
                                    colors: [.purple.opacity(0.3), .clear],
                                    startPoint: .top, endPoint: .bottom
                                )
                            )
                        }

                        // Current time marker (or drag position)
                        let markerTime = dragTime ?? currentTime
                        RuleMark(x: .value("現在", markerTime))
                            .foregroundStyle(isDragging ? Color.yellow.opacity(0.9) : Color.white.opacity(0.6))
                            .lineStyle(StrokeStyle(lineWidth: isDragging ? 2 : 1.5, dash: [4, 3]))
                            .annotation(position: .top, alignment: .center) {
                                if let cur = dataPoints.min(by: {
                                    abs($0.time - markerTime) < abs($1.time - markerTime)
                                }) {
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
                                    DragGesture(minimumDistance: 4)
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
                                    Text(String(format: "%.1fs", t))
                                        .font(.caption2)
                                        .foregroundColor(.white.opacity(0.5))
                                }
                            }
                            AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5))
                                .foregroundStyle(Color.white.opacity(0.1))
                        }
                    }
                    .chartYAxis {
                        AxisMarks(values: .automatic(desiredCount: 4)) { val in
                            AxisValueLabel {
                                if let d = val.as(Double.self) {
                                    Text("\(Int(d))°")
                                        .font(.caption2)
                                        .foregroundColor(.white.opacity(0.5))
                                }
                            }
                            AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5))
                                .foregroundStyle(Color.white.opacity(0.1))
                        }
                    }
                    .frame(height: 220)
                    .padding(.horizontal)

                    Spacer()
                }
                .padding(.top, 16)
            }
            .navigationTitle(angleName)
            .navigationBarTitleDisplayMode(.inline)
            .toolbarColorScheme(.dark, for: .navigationBar)
        }
    }

    private func statCell(label: String, value: String, color: Color) -> some View {
        VStack(spacing: 2) {
            Text(label)
                .font(.caption2)
                .foregroundColor(.white.opacity(0.45))
            Text(value)
                .font(.system(size: 22, weight: .bold, design: .rounded))
                .foregroundColor(color)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 10)
        .background(Color.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 10))
    }
}
