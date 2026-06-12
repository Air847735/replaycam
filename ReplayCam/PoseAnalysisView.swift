import SwiftUI

struct PoseAnalysisView: View {
    @State private var selectedClip: SavedClip?

    var body: some View {
        DateLibraryView(
            onSelectClip: { clip in selectedClip = clip },
            navigationTitle: "骨架分析"
        )
        .fullScreenCover(item: $selectedClip) { clip in
            PoseAnalysisResultView(clip: clip)
        }
    }
}
