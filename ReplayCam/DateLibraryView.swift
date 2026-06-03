import SwiftUI
import AVFoundation

// MARK: - Data model

struct DateGroup: Identifiable {
    let id: String          // ISO date string, used as stable key
    let displayDate: String // "今天" / "昨天" / "6月3日"
    let date: Date
    let clips: [SavedClip]
}

// MARK: - Date library (date list)

struct DateLibraryView: View {
    @ObservedObject private var store = ClipStore.shared
    @State private var durations: [String: Double] = [:]   // groupID → total seconds

    private var groups: [DateGroup] {
        let cal = Calendar.current
        let dict = Dictionary(grouping: store.clips) { clip in
            cal.startOfDay(for: clip.date)
                .formatted(.dateTime.year().month(.twoDigits).day(.twoDigits))
        }
        return dict.map { key, clips in
            let date = clips.first!.date
            let display: String
            if cal.isDateInToday(date)     { display = "今天" }
            else if cal.isDateInYesterday(date) { display = "昨天" }
            else { display = date.formatted(.dateTime.month().day()) }
            return DateGroup(id: key, displayDate: display, date: date, clips: clips)
        }
        .sorted { $0.date > $1.date }
    }

    var body: some View {
        Group {
            if groups.isEmpty {
                emptyState
            } else {
                List(groups) { group in
                    NavigationLink(destination: DayDetailView(group: group)) {
                        DateGroupRow(
                            group: group,
                            totalDuration: durations[group.id]
                        )
                    }
                }
                .listStyle(.insetGrouped)
            }
        }
        .navigationTitle("日期記錄")
        .task(id: store.clips.count) {
            // Compute total duration per group (async, runs on change)
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
                .foregroundColor(.secondary)
            Text("還沒有錄製記錄")
                .font(.headline).foregroundColor(.secondary)
            Text("去拍攝頁面開始錄製並儲存片段")
                .font(.caption).foregroundColor(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func sumDuration(of clips: [SavedClip]) async -> Double {
        var total = 0.0
        for clip in clips {
            let asset = AVURLAsset(url: clip.url)
            if let d = try? await asset.load(.duration) {
                total += d.seconds
            }
        }
        return total
    }
}

// MARK: - Row

struct DateGroupRow: View {
    let group: DateGroup
    let totalDuration: Double?

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(group.displayDate)
                .font(.headline)

            HStack(spacing: 6) {
                Label("\(group.clips.count) 個片段", systemImage: "film.stack")
                    .font(.caption)
                    .foregroundColor(.secondary)

                if let dur = totalDuration, dur > 0 {
                    Text("·").foregroundColor(.secondary).font(.caption)
                    Label(formatDuration(dur), systemImage: "clock")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
        }
        .padding(.vertical, 4)
    }

    private func formatDuration(_ seconds: Double) -> String {
        let s = Int(seconds.rounded())
        if s >= 60 { return "\(s / 60) 分 \(s % 60) 秒" }
        return "\(s) 秒"
    }
}

// MARK: - Day detail (grid of clips)

struct DayDetailView: View {
    let group: DateGroup
    @ObservedObject private var store = ClipStore.shared
    @State private var selectedClip: SavedClip?

    private let columns = [
        GridItem(.flexible(), spacing: 2),
        GridItem(.flexible(), spacing: 2),
        GridItem(.flexible(), spacing: 2)
    ]

    // Re-read from store in case clips were deleted
    private var currentClips: [SavedClip] {
        let cal = Calendar.current
        return store.clips.filter { cal.isDate($0.date, inSameDayAs: group.date) }
    }

    var body: some View {
        Group {
            if currentClips.isEmpty {
                Text("這天的片段已全部刪除")
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVGrid(columns: columns, spacing: 2) {
                        ForEach(currentClips) { clip in
                            ClipCell(clip: clip)
                                .onTapGesture { selectedClip = clip }
                                .contextMenu {
                                    Button(role: .destructive) {
                                        store.delete(clip)
                                    } label: {
                                        Label("刪除", systemImage: "trash")
                                    }
                                }
                        }
                    }
                }
            }
        }
        .navigationTitle(group.displayDate)
        .navigationBarTitleDisplayMode(.inline)
        .fullScreenCover(item: $selectedClip) { clip in
            PlayerView(url: clip.url)
        }
    }
}
