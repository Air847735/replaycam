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

// MARK: - Date group model

struct DateGroup: Identifiable {
    let id: String
    let displayDate: String
    let date: Date
    let clips: [SavedClip]
}

func makeDateGroups(from clips: [SavedClip]) -> [DateGroup] {
    let cal = Calendar.current
    let dict = Dictionary(grouping: clips) { clip in
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

// MARK: - Date library (top level)

enum LibraryDisplayMode: String, CaseIterable {
    case folder = "資料夾"
    case date   = "日期"
}

struct DateLibraryView: View {
    var onSelectClip: ((SavedClip) -> Void)? = nil   // nil = normal PlayerView navigation
    var navigationTitle: String = "日期記錄"

    @ObservedObject private var store = ClipStore.shared
    @State private var displayMode: LibraryDisplayMode = .folder
    @State private var durations: [String: Double] = [:]
    @State private var showCreateFolder = false
    @State private var newFolderName    = ""

    private var unassignedGroups: [DateGroup] { makeDateGroups(from: store.unassignedClips) }
    private var allGroups:        [DateGroup] { makeDateGroups(from: store.clips) }

    var body: some View {
        ZStack {
            TISSBackground()

            VStack(spacing: 0) {
                // Mode picker
                Picker("顯示方式", selection: $displayMode) {
                    ForEach(LibraryDisplayMode.allCases, id: \.self) { mode in
                        Text(mode.rawValue).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal, 16)
                .padding(.vertical, 10)

                if displayMode == .folder {
                    folderView
                } else {
                    dateView
                }
            }
        }
        .navigationTitle(navigationTitle)
        .navigationBarTitleDisplayMode(.inline)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
        .toolbarBackground(Color(red: 0.04, green: 0.16, blue: 0.30), for: .navigationBar)
        .toolbar {
            if displayMode == .folder {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        newFolderName = ""
                        showCreateFolder = true
                    } label: {
                        Image(systemName: "folder.badge.plus")
                            .foregroundColor(.white)
                    }
                }
            }
        }
        .alert("新增資料夾", isPresented: $showCreateFolder) {
            TextField("資料夾名稱", text: $newFolderName)
            Button("新增") {
                let name = newFolderName.trimmingCharacters(in: .whitespaces)
                if !name.isEmpty { store.createFolder(name: name) }
            }
            Button("取消", role: .cancel) {}
        }
        .task(id: store.clips.count) {
            let groups = displayMode == .folder ? unassignedGroups : allGroups
            for group in groups where durations[group.id] == nil {
                let total = await sumDuration(of: group.clips)
                durations[group.id] = total
            }
        }
    }

    // MARK: - Folder mode

    private var folderView: some View {
        List {
            Section {
                ForEach(store.rootFolders) { folder in
                    NavigationLink(destination: FolderDetailView(folder: folder, onSelectClip: onSelectClip)) {
                        FolderRow(folder: folder)
                    }
                    .listRowBackground(Color.white.opacity(0.08))
                    .listRowSeparatorTint(Color.white.opacity(0.15))
                    .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                        Button(role: .destructive) {
                            store.deleteFolder(folder)
                        } label: { Label("刪除", systemImage: "trash") }
                    }
                }

                Button {
                    newFolderName = ""
                    showCreateFolder = true
                } label: {
                    Label("新增資料夾", systemImage: "folder.badge.plus")
                        .foregroundColor(.white.opacity(0.75))
                }
                .listRowBackground(Color.white.opacity(0.05))
            } header: {
                Text("資料夾")
                    .foregroundColor(.white.opacity(0.5))
                    .font(.caption).textCase(nil)
            }

            if !unassignedGroups.isEmpty {
                Section {
                    ForEach(unassignedGroups) { group in
                        NavigationLink(destination: DayDetailView(group: group, onSelectClip: onSelectClip)) {
                            DateGroupRow(group: group, totalDuration: durations[group.id])
                        }
                        .listRowBackground(Color.white.opacity(0.08))
                        .listRowSeparatorTint(Color.white.opacity(0.15))
                    }
                } header: {
                    Text("未分類")
                        .foregroundColor(.white.opacity(0.5))
                        .font(.caption).textCase(nil)
                }
            }

            if store.rootFolders.isEmpty && store.clips.isEmpty { emptyState.listRowBackground(Color.clear) }
        }
        .scrollContentBackground(.hidden)
        .listStyle(.insetGrouped)
    }

    // MARK: - Date mode

    private var dateView: some View {
        Group {
            if allGroups.isEmpty {
                emptyState
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List(allGroups) { group in
                    NavigationLink(destination: DayDetailView(group: group, showAllClips: true, onSelectClip: onSelectClip)) {
                        DateGroupRow(group: group, totalDuration: durations[group.id])
                    }
                    .listRowBackground(Color.white.opacity(0.08))
                    .listRowSeparatorTint(Color.white.opacity(0.15))
                }
                .scrollContentBackground(.hidden)
                .listStyle(.insetGrouped)
            }
        }
    }

    // MARK: - Helpers

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
        .frame(maxWidth: .infinity)
        .padding(.vertical, 40)
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

// MARK: - Folder row

private struct FolderRow: View {
    @ObservedObject private var store = ClipStore.shared
    let folder: ClipFolder

    var body: some View {
        let count = store.clips(in: folder).count
        HStack(spacing: 12) {
            Image(systemName: "folder.fill")
                .font(.system(size: 24))
                .foregroundColor(.yellow.opacity(0.85))
                .frame(width: 32)
            VStack(alignment: .leading, spacing: 3) {
                Text(folder.name)
                    .font(.headline)
                    .foregroundColor(.white)
                Text("\(count) 個片段")
                    .font(.caption)
                    .foregroundColor(.white.opacity(0.6))
            }
        }
        .padding(.vertical, 4)
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

// MARK: - Folder detail (clips in folder grouped by date)

struct FolderDetailView: View {
    let folder: ClipFolder
    var depth: Int = 1
    var onSelectClip: ((SavedClip) -> Void)? = nil
    @ObservedObject private var store = ClipStore.shared
    @State private var durations: [String: Double] = [:]
    @State private var showRename       = false
    @State private var newName          = ""
    @State private var showCreateSub    = false
    @State private var newSubFolderName = ""
    @Environment(\.dismiss) private var dismiss

    private var subfolders: [ClipFolder] { store.subfolders(of: folder) }
    private var groups: [DateGroup]      { makeDateGroups(from: store.clips(in: folder)) }
    private var isEmpty: Bool            { subfolders.isEmpty && groups.isEmpty }

    var body: some View {
        ZStack {
            TISSBackground()

            if isEmpty {
                VStack(spacing: 14) {
                    Image(systemName: "folder")
                        .font(.system(size: 52))
                        .foregroundColor(.white.opacity(0.4))
                    Text("資料夾是空的")
                        .font(.headline).foregroundColor(.white)
                    Text("可新增子資料夾，或在片段選取模式中移入片段")
                        .font(.caption).foregroundColor(.white.opacity(0.6))
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 40)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List {
                    // ── Subfolders ──────────────────────────────────────
                    if !subfolders.isEmpty {
                        Section {
                            ForEach(subfolders) { sub in
                                NavigationLink(destination: FolderDetailView(folder: sub, depth: depth + 1, onSelectClip: onSelectClip)) {
                                    FolderRow(folder: sub)
                                }
                                .listRowBackground(Color.white.opacity(0.08))
                                .listRowSeparatorTint(Color.white.opacity(0.15))
                                .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                                    Button(role: .destructive) {
                                        store.deleteFolder(sub)
                                    } label: { Label("刪除", systemImage: "trash") }
                                }
                            }
                        } header: {
                            Text("子資料夾")
                                .foregroundColor(.white.opacity(0.5))
                                .font(.caption).textCase(nil)
                        }
                    }

                    // ── Clips by date ────────────────────────────────────
                    if !groups.isEmpty {
                        Section {
                            ForEach(groups) { group in
                                NavigationLink(destination: DayDetailView(group: group, folderID: folder.id, onSelectClip: onSelectClip)) {
                                    DateGroupRow(group: group, totalDuration: durations[group.id])
                                }
                                .listRowBackground(Color.white.opacity(0.08))
                                .listRowSeparatorTint(Color.white.opacity(0.15))
                            }
                        } header: {
                            Text("片段")
                                .foregroundColor(.white.opacity(0.5))
                                .font(.caption).textCase(nil)
                        }
                    }
                }
                .scrollContentBackground(.hidden)
                .listStyle(.insetGrouped)
            }
        }
        .navigationTitle(folder.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
        .toolbarBackground(Color(red: 0.04, green: 0.16, blue: 0.30), for: .navigationBar)
        .toolbar {
            if depth < 5 {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        newSubFolderName = ""
                        showCreateSub = true
                    } label: {
                        Image(systemName: "folder.badge.plus")
                            .foregroundColor(.white)
                    }
                }
            }
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button {
                        newName = folder.name
                        showRename = true
                    } label: { Label("重新命名", systemImage: "pencil") }

                    Button(role: .destructive) {
                        store.deleteFolder(folder)
                        dismiss()
                    } label: { Label("刪除資料夾", systemImage: "trash") }
                } label: {
                    Image(systemName: "ellipsis.circle")
                        .foregroundColor(.white)
                }
            }
        }
        .alert("新增子資料夾", isPresented: $showCreateSub) {
            TextField("資料夾名稱", text: $newSubFolderName)
            Button("新增") {
                let name = newSubFolderName.trimmingCharacters(in: .whitespaces)
                if !name.isEmpty { store.createFolder(name: name, parentID: folder.id) }
            }
            Button("取消", role: .cancel) {}
        }
        .alert("重新命名", isPresented: $showRename) {
            TextField("資料夾名稱", text: $newName)
            Button("確定") {
                let name = newName.trimmingCharacters(in: .whitespaces)
                if !name.isEmpty { store.renameFolder(folder, to: name) }
            }
            Button("取消", role: .cancel) {}
        }
        .task(id: store.clips.count) {
            for group in groups where durations[group.id] == nil {
                let total = await sumDuration(of: group.clips)
                durations[group.id] = total
            }
        }
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

// MARK: - Day detail

struct DayDetailView: View {
    let group: DateGroup
    var folderID: String?    = nil
    var showAllClips: Bool   = false
    var onSelectClip: ((SavedClip) -> Void)? = nil   // override default PlayerView navigation

    @ObservedObject private var store = ClipStore.shared

    @State private var selectedClip: SavedClip?
    @State private var columnCount:  Int = 3
    @GestureState private var pinchScale: CGFloat = 1.0
    @State private var isSelecting   = false
    @State private var selectedIDs:  Set<String> = []
    @State private var showShareSheet    = false
    @State private var showDeleteConfirm = false
    @State private var showMoveToFolder  = false

    private var liveColumnCount: Int {
        Int((CGFloat(columnCount) / pinchScale).rounded()).clamped(to: 2...5)
    }
    private var columns: [GridItem] {
        Array(repeating: GridItem(.flexible(), spacing: 2), count: liveColumnCount)
    }
    private var currentClips: [SavedClip] {
        let cal = Calendar.current
        let byDate = store.clips.filter { cal.isDate($0.date, inSameDayAs: group.date) }
        let base: [SavedClip]
        if showAllClips {
            base = byDate
        } else if let folderID {
            base = byDate.filter { store.clipFolderMap[$0.id] == folderID }
        } else {
            base = byDate.filter { store.clipFolderMap[$0.id] == nil }
        }
        return base.sorted { a, b in
            let fa = store.isFavorite(a), fb = store.isFavorite(b)
            if fa != fb { return fa }
            return a.date > b.date
        }
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
                ScrollViewReader { proxy in
                ScrollView {
                    Color.clear.frame(height: 0).id("top")
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
                                } else if let handler = onSelectClip {
                                    handler(clip)
                                } else {
                                    selectedClip = clip
                                }
                            }
                            .contextMenu {
                                if !isSelecting {
                                    let title = clip.date.formatted(.dateTime.month().day().hour().minute())
                                    let preview = SharePreview(title, icon: Image(systemName: "film"))
                                    ShareLink(item: clip.url, preview: preview) {
                                        Label("匯出影片", systemImage: "square.and.arrow.up")
                                    }
                                    Divider()
                                    Button(role: .destructive) { store.delete(clip) } label: {
                                        Label("刪除", systemImage: "trash")
                                    }
                                }
                            }
                        }
                    }
                    .padding(.bottom, isSelecting ? 80 : 0)
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
                .onChange(of: store.favoriteIDs) { _ in
                    withAnimation(.easeOut(duration: 0.3)) { proxy.scrollTo("top", anchor: .top) }
                }
                } // ScrollViewReader
            }

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
        .sheet(isPresented: $showMoveToFolder) {
            MoveToFolderSheet(clipIDs: selectedIDs) {
                selectedIDs.removeAll()
                isSelecting = false
            }
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

    private var selectionActionBar: some View {
        HStack(spacing: 0) {
            // Export
            actionButton(icon: "square.and.arrow.up", label: "匯出",
                         disabled: selectedIDs.isEmpty) {
                showShareSheet = true
            }

            divider

            // Move to folder
            actionButton(icon: "folder.badge.plus", label: "移至資料夾",
                         disabled: selectedIDs.isEmpty) {
                showMoveToFolder = true
            }

            divider

            // Select all
            actionButton(
                icon: selectedIDs.count == currentClips.count
                    ? "checkmark.circle.fill" : "checkmark.circle",
                label: selectedIDs.count == currentClips.count ? "取消全選" : "全選",
                disabled: false
            ) {
                withAnimation {
                    if selectedIDs.count == currentClips.count { selectedIDs.removeAll() }
                    else { selectedIDs = Set(currentClips.map(\.id)) }
                }
            }

            divider

            // Delete
            actionButton(icon: "trash", label: "刪除",
                         disabled: selectedIDs.isEmpty, destructive: true) {
                showDeleteConfirm = true
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 12)
        .background(.ultraThinMaterial)
        .overlay(Divider(), alignment: .top)
        .overlay(
            Text(selectedIDs.isEmpty ? "尚未選取" : "已選取 \(selectedIDs.count) 個")
                .font(.caption)
                .foregroundColor(.white.opacity(0.7))
                .padding(.top, 6),
            alignment: .top
        )
    }

    private var divider: some View {
        Divider().frame(height: 36).background(Color.white.opacity(0.2))
    }

    private func actionButton(
        icon: String, label: String, disabled: Bool,
        destructive: Bool = false, action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            VStack(spacing: 4) {
                Image(systemName: icon).font(.system(size: 20))
                Text(label).font(.caption2)
            }
            .foregroundColor(
                disabled ? .white.opacity(0.35) :
                destructive ? .red : .white
            )
            .frame(maxWidth: .infinity)
        }
        .disabled(disabled)
    }
}

// MARK: - Move to folder sheet

private struct MoveToFolderSheet: View {
    let clipIDs: Set<String>
    let onDone: () -> Void

    @ObservedObject private var store = ClipStore.shared
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Button {
                    store.assignClips(clipIDs, to: nil)
                    onDone(); dismiss()
                } label: {
                    Label("移出資料夾（未分類）", systemImage: "xmark.circle")
                        .foregroundColor(.primary)
                }

                if store.folders.isEmpty {
                    Text("尚未建立任何資料夾\n請先在日期記錄頁面新增資料夾")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 20)
                } else {
                    FolderPickerRows(folders: store.rootFolders, indent: 0) { folder in
                        store.assignClips(clipIDs, to: folder.id)
                        onDone(); dismiss()
                    }
                }
            }
            .navigationTitle("移至資料夾")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("取消") { dismiss() }
                }
            }
        }
    }
}

// Recursive folder rows with indent
private struct FolderPickerRows: View {
    let folders: [ClipFolder]
    let indent: Int
    let onSelect: (ClipFolder) -> Void

    @ObservedObject private var store = ClipStore.shared

    var body: some View {
        ForEach(folders) { folder in
            Button {
                onSelect(folder)
            } label: {
                HStack(spacing: 6) {
                    if indent > 0 {
                        Color.clear.frame(width: CGFloat(indent) * 20)
                        Image(systemName: "arrow.turn.down.right")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    Label(folder.name, systemImage: "folder.fill")
                        .foregroundColor(.primary)
                }
            }
            FolderPickerRows(
                folders: store.subfolders(of: folder),
                indent: indent + 1,
                onSelect: onSelect
            )
        }
    }
}
