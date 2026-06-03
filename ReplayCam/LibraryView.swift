import SwiftUI
import AVFoundation

// MARK: - Date filter

enum DateFilter: String, CaseIterable, Identifiable {
    case all   = "全部"
    case today = "今天"
    case week  = "本週"
    case month = "本月"

    var id: String { rawValue }

    func matches(_ date: Date) -> Bool {
        let cal = Calendar.current
        switch self {
        case .all:   return true
        case .today: return cal.isDateInToday(date)
        case .week:  return cal.isDate(date, equalTo: Date(), toGranularity: .weekOfYear)
        case .month: return cal.isDate(date, equalTo: Date(), toGranularity: .month)
        }
    }
}

// MARK: - Library view

struct LibraryView: View {
    @ObservedObject private var store = ClipStore.shared
    @State private var selectedFilter: DateFilter = .all
    @State private var selectedClip: SavedClip?

    private let columns = [
        GridItem(.flexible(), spacing: 2),
        GridItem(.flexible(), spacing: 2),
        GridItem(.flexible(), spacing: 2)
    ]

    // Clips matching the current filter
    private var filteredClips: [SavedClip] {
        store.clips.filter { selectedFilter.matches($0.date) }
    }

    // Group filtered clips by calendar day
    private var groupedClips: [(header: String, clips: [SavedClip])] {
        let cal = Calendar.current
        let dict = Dictionary(grouping: filteredClips) { clip -> String in
            if cal.isDateInToday(clip.date)     { return "今天" }
            if cal.isDateInYesterday(clip.date) { return "昨天" }
            return clip.date.formatted(.dateTime.year().month(.abbreviated).day())
        }
        // Sort sections newest first using the first clip in each group
        return dict
            .map { (header: $0.key, clips: $0.value) }
            .sorted { a, b in
                (a.clips.first?.date ?? .distantPast) > (b.clips.first?.date ?? .distantPast)
            }
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                filterChips
                    .padding(.vertical, 10)

                Divider()

                if filteredClips.isEmpty {
                    emptyState
                } else {
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 0, pinnedViews: .sectionHeaders) {
                            ForEach(groupedClips, id: \.header) { group in
                                Section {
                                    LazyVGrid(columns: columns, spacing: 2) {
                                        ForEach(group.clips) { clip in
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
                                } header: {
                                    Text(group.header)
                                        .font(.system(size: 13, weight: .semibold))
                                        .foregroundColor(.secondary)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                        .padding(.horizontal, 14)
                                        .padding(.vertical, 8)
                                        .background(.regularMaterial)
                                }
                            }
                        }
                    }
                }
            }
            .navigationTitle("片段庫")
            .navigationBarTitleDisplayMode(.inline)
        }
        .fullScreenCover(item: $selectedClip) { clip in
            PlayerView(url: clip.url)
        }
    }

    // MARK: - Filter chips

    private var filterChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(DateFilter.allCases) { filter in
                    let selected = filter == selectedFilter
                    Button {
                        withAnimation(.easeInOut(duration: 0.15)) {
                            selectedFilter = filter
                        }
                    } label: {
                        Text(filter.rawValue)
                            .font(.system(size: 13, weight: selected ? .bold : .regular))
                            .foregroundColor(selected ? .white : .primary)
                            .padding(.horizontal, 14).padding(.vertical, 6)
                            .background(
                                Capsule()
                                    .fill(selected ? Color.blue : Color(.systemGray5))
                            )
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 16)
        }
    }

    // MARK: - Empty state

    private var emptyState: some View {
        VStack(spacing: 14) {
            Image(systemName: "film.stack")
                .font(.system(size: 52))
                .foregroundColor(.secondary)
            Text(selectedFilter == .all ? "還沒有儲存的片段" : "這個時間範圍沒有片段")
                .font(.headline)
                .foregroundColor(.secondary)
            if selectedFilter == .all {
                Text("錄製後按「儲存影片」，片段就會出現在這裡")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 40)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Clip cell

struct ClipCell: View {
    let clip: SavedClip
    @State private var thumbnail: UIImage?

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            Group {
                if let thumb = thumbnail {
                    Image(uiImage: thumb)
                        .resizable()
                        .scaledToFill()
                } else {
                    Color(.systemGray5)
                        .overlay(ProgressView().scaleEffect(0.7))
                }
            }
            .aspectRatio(9/16, contentMode: .fit)
            .clipped()

            // Time label
            Text(clip.date.formatted(.dateTime.hour().minute()))
                .font(.system(size: 10, weight: .medium))
                .foregroundColor(.white)
                .padding(.horizontal, 5).padding(.vertical, 2)
                .background(Color.black.opacity(0.55), in: RoundedRectangle(cornerRadius: 3))
                .padding(5)
        }
        .task { thumbnail = await makeThumbnail(for: clip.url) }
    }

    private func makeThumbnail(for url: URL) async -> UIImage? {
        let asset = AVURLAsset(url: url)
        let gen = AVAssetImageGenerator(asset: asset)
        gen.appliesPreferredTrackTransform = true
        gen.maximumSize = CGSize(width: 300, height: 534)
        let time = CMTime(seconds: 0.1, preferredTimescale: 600)
        if let cg = try? gen.copyCGImage(at: time, actualTime: nil) {
            return UIImage(cgImage: cg)
        }
        return nil
    }
}
