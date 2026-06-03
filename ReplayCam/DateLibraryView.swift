import SwiftUI
import AVFoundation

// MARK: - Shared background

private struct TISSBackground: View {
    var body: some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color(red: 0.04, green: 0.16, blue: 0.30),
                    Color(red: 0.02, green: 0.22, blue: 0.22)
                ],
                startPoint: .topLeading, endPoint: .bottomTrailing
            )
            Image("tiss_pattern")
                .resizable(resizingMode: .tile)
                .opacity(0.13)
        }
        .ignoresSafeArea()
    }
}

// MARK: - Data model

struct DateGroup: Identifiable {
    let id: String
    let displayDate: String
    let date: Date
    let clips: [SavedClip]
}

// MARK: - Date library

struct DateLibraryView: View {
    @ObservedObject private var store = ClipStore.shared
    @State private var durations: [String: Double] = [:]

    private var groups: [DateGroup] {
        let cal = Calendar.current
        let dict = Dictionary(grouping: store.clips) { clip in
            cal.startOfDay(for: clip.date)
                .formatted(.dateTime.year().month(.twoDigits).day(.twoDigits))
        }
        return dict.map { key, clips in
            let date = clips.first!.date
            let display: String
            if cal.isDateInToday(date)          { display = "今天" }
            else if cal.isDateInYesterday(date) { display = "昨天" }
            else { display = date.formatted(.dateTime.month().day()) }
            return DateGroup(id: key, displayDate: display, date: date, clips: clips)
        }
        .sorted { $0.date > $1.date }
    }

    var body: some View {
        ZStack {
            TISSBackground()

            if groups.isEmpty {
                emptyState
            } else {
                List(groups) { group in
                    NavigationLink(destination: DayDetailView(group: group)) {
                        DateGroupRow(group: group, totalDuration: durations[group.id])
                    }
                    .listRowBackground(Color.white.opacity(0.08))
                    .listRowSeparatorTint(Color.white.opacity(0.15))
                }
                .scrollContentBackground(.hidden)
                .listStyle(.insetGrouped)
            }
        }
        .navigationTitle("日期記錄")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
        .toolbarBackground(
            Color(red: 0.04, green: 0.16, blue: 0.30),
            for: .navigationBar
        )
        .task(id: store.clips.count) {
            for group in groups where durations[group.id] == nil {
                let total = await sumDuration(of: group.clips)
                durations[group.id] = total
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 14) {
            Image(systemName: "calendar.badge.clock")
                .font(.system(size: 52))
                .foregroundColor(.white.opacity(0.4))
            Text("還沒有錄製記錄")
                .font(.headline).foregroundColor(.white)
            Text("去拍攝頁面開始錄製並儲存片段")
                .font(.caption).foregroundColor(.white.opacity(0.6))
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func sumDuration(of clips: [SavedClip]) async -> Double {
        var total = 0.0
        for clip in clips {
            let asset = AVURLAsset(url: clip.url)
            if let d = try? await asset.load(.duration) { total += d.seconds }
        }
        return total
    }
}

// MARK: - Date group row

struct DateGroupRow: View {
    let group: DateGroup
    let totalDuration: Double?

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(group.displayDate)
                .font(.headline)
                .foregroundColor(.white)

            HStack(spacing: 6) {
                Label("\(group.clips.count) 個片段", systemImage: "film.stack")
                    .font(.caption)
                    .foregroundColor(.white.opacity(0.65))

                if let dur = totalDuration, dur > 0 {
                    Text("·").foregroundColor(.white.opacity(0.4)).font(.caption)
                    Label(formatDuration(dur), systemImage: "clock")
                        .font(.caption)
                        .foregroundColor(.white.opacity(0.65))
                }
            }
        }
        .padding(.vertical, 4)
    }

    private func formatDuration(_ s: Double) -> String {
        let t = Int(s.rounded())
        return t >= 60 ? "\(t / 60) 分 \(t % 60) 秒" : "\(t) 秒"
    }
}

// MARK: - Day detail

struct DayDetailView: View {
    let group: DateGroup
    @ObservedObject private var store = ClipStore.shared
    @State private var selectedClip: SavedClip?
    @State private var columnCount: Int = 3
    @GestureState private var pinchScale: CGFloat = 1.0

    private var columns: [GridItem] {
        Array(repeating: GridItem(.flexible(), spacing: 2), count: columnCount)
    }

    private var currentClips: [SavedClip] {
        let cal = Calendar.current
        return store.clips.filter { cal.isDate($0.date, inSameDayAs: group.date) }
    }

    var body: some View {
        ZStack {
            TISSBackground()

            if currentClips.isEmpty {
                Text("這天的片段已全部刪除")
                    .foregroundColor(.white.opacity(0.6))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVGrid(columns: columns, spacing: 2) {
                        ForEach(currentClips) { clip in
                            ClipCell(clip: clip)
                                .onTapGesture { selectedClip = clip }
                                .contextMenu {
                                    // Export
                                    ShareLink(
                                        item: clip.url,
                                        preview: SharePreview(
                                            clip.date.formatted(.dateTime.month().day().hour().minute()),
                                            icon: Image(systemName: "film")
                                        )
                                    ) {
                                        Label("匯出影片", systemImage: "square.and.arrow.up")
                                    }
                                    Divider()
                                    Button(role: .destructive) {
                                        store.delete(clip)
                                    } label: {
                                        Label("刪除", systemImage: "trash")
                                    }
                                }
                        }
                    }
                }
                // Pinch to change grid density (2–5 columns)
                .gesture(
                    MagnificationGesture()
                        .updating($pinchScale) { value, state, _ in state = value }
                        .onEnded { value in
                            withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                                if value > 1.25 {
                                    columnCount = max(2, columnCount - 1)  // spread → fewer, bigger
                                } else if value < 0.8 {
                                    columnCount = min(5, columnCount + 1)  // pinch → more, smaller
                                }
                            }
                        }
                )
            }
        }
        .navigationTitle(group.displayDate)
        .navigationBarTitleDisplayMode(.inline)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
        .toolbarBackground(
            Color(red: 0.04, green: 0.16, blue: 0.30),
            for: .navigationBar
        )
        .fullScreenCover(item: $selectedClip) { clip in
            PlayerView(url: clip.url)
        }
    }
}
