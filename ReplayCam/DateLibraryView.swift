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

    // Playback
    @State private var selectedClip: SavedClip?

    // Grid zoom
    @State private var columnCount: Int = 3
    @GestureState private var pinchScale: CGFloat = 1.0

    // Multi-select
    @State private var isSelecting = false
    @State private var selectedIDs: Set<UUID> = []
    @State private var showShareSheet = false
    @State private var showDeleteConfirm = false

    private var liveColumnCount: Int {
        Int((CGFloat(columnCount) / pinchScale).rounded()).clamped(to: 2...5)
    }
    private var columns: [GridItem] {
        Array(repeating: GridItem(.flexible(), spacing: 2), count: liveColumnCount)
    }
    private var currentClips: [SavedClip] {
        let cal = Calendar.current
        return store.clips.filter { cal.isDate($0.date, inSameDayAs: group.date) }
    }
    private var selectedClips: [SavedClip] {
        currentClips.filter { selectedIDs.contains($0.id) }
    }

    var body: some View {
        ZStack(alignment: .bottom) {
            TISSBackground()

            if currentClips.isEmpty {
                Text("這天的片段已全部刪除")
                    .foregroundColor(.white.opacity(0.6))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVGrid(columns: columns, spacing: 2) {
                        ForEach(currentClips) { clip in
                            ClipCell(
                                clip: clip,
                                isSelectMode: isSelecting,
                                isSelected: selectedIDs.contains(clip.id)
                            )
                            .onTapGesture {
                                if isSelecting {
                                    withAnimation(.easeInOut(duration: 0.15)) {
                                        if selectedIDs.contains(clip.id) { selectedIDs.remove(clip.id) }
                                        else { selectedIDs.insert(clip.id) }
                                    }
                                } else {
                                    selectedClip = clip
                                }
                            }
                            .contextMenu {
                                if !isSelecting {
                                    ShareLink(
                                        item: clip.url,
                                        preview: SharePreview(
                                            clip.date.formatted(.dateTime.month().day().hour().minute()),
                                            icon: Image(systemName: "film")
                                        )
                                    ) { Label("匯出影片", systemImage: "square.and.arrow.up") }
                                    Divider()
                                    Button(role: .destructive) { store.delete(clip) } label: {
                                        Label("刪除", systemImage: "trash")
                                    }
                                }
                            }
                        }
                    }
                    .padding(.bottom, isSelecting ? 80 : 0)   // room for action bar
                }
                .simultaneousGesture(
                    MagnificationGesture()
                        .updating($pinchScale) { value, state, _ in state = value }
                        .onEnded { finalScale in
                            columnCount = Int((CGFloat(columnCount) / finalScale).rounded())
                                .clamped(to: 2...5)
                        }
                )
                .animation(.spring(response: 0.2, dampingFraction: 0.75), value: liveColumnCount)
            }

            // ── Multi-select action bar ──────────────────────────────────
            if isSelecting {
                selectionActionBar
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .navigationTitle(group.displayDate)
        .navigationBarTitleDisplayMode(.inline)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
        .toolbarBackground(Color(red: 0.04, green: 0.16, blue: 0.30), for: .navigationBar)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button(isSelecting ? "取消" : "選取") {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        isSelecting.toggle()
                        selectedIDs.removeAll()
                    }
                }
                .foregroundColor(.white)
            }
        }
        .fullScreenCover(item: $selectedClip) { clip in PlayerView(url: clip.url) }
        .sheet(isPresented: $showShareSheet) {
            ShareSheet(items: selectedClips.map { $0.url as Any })
        }
        .confirmationDialog(
            "確定刪除 \(selectedIDs.count) 個片段？",
            isPresented: $showDeleteConfirm,
            titleVisibility: .visible
        ) {
            Button("刪除", role: .destructive) {
                selectedClips.forEach { store.delete($0) }
                selectedIDs.removeAll()
                isSelecting = false
            }
            Button("取消", role: .cancel) {}
        }
    }

    // Bottom action bar shown in select mode
    private var selectionActionBar: some View {
        HStack(spacing: 16) {
            // Export
            Button {
                guard !selectedIDs.isEmpty else { return }
                showShareSheet = true
            } label: {
                VStack(spacing: 4) {
                    Image(systemName: "square.and.arrow.up")
                        .font(.system(size: 20))
                    Text("匯出").font(.caption2)
                }
                .foregroundColor(selectedIDs.isEmpty ? .white.opacity(0.35) : .white)
                .frame(maxWidth: .infinity)
            }
            .disabled(selectedIDs.isEmpty)

            Divider().frame(height: 36).background(Color.white.opacity(0.2))

            // Select all / deselect
            Button {
                withAnimation {
                    if selectedIDs.count == currentClips.count {
                        selectedIDs.removeAll()
                    } else {
                        selectedIDs = Set(currentClips.map(\.id))
                    }
                }
            } label: {
                VStack(spacing: 4) {
                    Image(systemName: selectedIDs.count == currentClips.count
                          ? "checkmark.circle.fill" : "checkmark.circle")
                        .font(.system(size: 20))
                    Text(selectedIDs.count == currentClips.count ? "取消全選" : "全選")
                        .font(.caption2)
                }
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
            }

            Divider().frame(height: 36).background(Color.white.opacity(0.2))

            // Delete
            Button {
                guard !selectedIDs.isEmpty else { return }
                showDeleteConfirm = true
            } label: {
                VStack(spacing: 4) {
                    Image(systemName: "trash")
                        .font(.system(size: 20))
                    Text("刪除").font(.caption2)
                }
                .foregroundColor(selectedIDs.isEmpty ? .white.opacity(0.35) : .red)
                .frame(maxWidth: .infinity)
            }
            .disabled(selectedIDs.isEmpty)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .background(.ultraThinMaterial)
        .overlay(Divider(), alignment: .top)
        .overlay(
            // Selection count badge
            Text(selectedIDs.isEmpty ? "尚未選取" : "已選取 \(selectedIDs.count) 個")
                .font(.caption)
                .foregroundColor(.white.opacity(0.7))
                .padding(.top, 6),
            alignment: .top
        )
    }
}
