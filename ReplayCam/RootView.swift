import SwiftUI

struct RootView: View {
    var body: some View {
        TabView {
            ContentView()
                .tabItem {
                    Label("拍攝", systemImage: "camera.fill")
                }

            LibraryView()
                .tabItem {
                    Label("片段庫", systemImage: "film.stack.fill")
                }
        }
        .tint(.blue)
    }
}
