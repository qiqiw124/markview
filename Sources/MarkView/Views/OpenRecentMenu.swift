import SwiftUI

/// File > Open Recent 子菜单项（从 .commands 注入菜单栏）。
struct OpenRecentMenu: View {
    @ObservedObject var recent: RecentFiles
    let onOpen: (URL) -> Void

    var body: some View {
        Menu("打开最近的文件") {
            if recent.urls.isEmpty {
                Text("暂无")
            } else {
                ForEach(Array(recent.urls.prefix(10).enumerated()), id: \.element) { idx, url in
                    Button(action: { onOpen(url) }) {
                        Text("\(idx + 1). \(url.lastPathComponent)")
                        Text(url.deletingLastPathComponent().path)
                    }
                }
                Divider()
                Button("清除最近文件") { recent.clear() }
            }
        }
        .disabled(recent.urls.isEmpty)
    }
}
