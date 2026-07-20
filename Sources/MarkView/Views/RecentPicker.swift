import SwiftUI

/// 最近文件弹层（⌘⇧O 弹出）。
struct RecentPicker: View {
    @ObservedObject var recent: RecentFiles
    let onPick: (URL) -> Void
    let onClear: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("最近文件").font(.headline)
                Spacer()
                if !recent.urls.isEmpty {
                    Button("清空", role: .destructive, action: onClear)
                        .buttonStyle(.borderless)
                        .controlSize(.small)
                }
            }
            .padding(.horizontal, 14)
            .padding(.top, 12)
            .padding(.bottom, 8)

            Divider()

            if recent.urls.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "clock.arrow.circlepath")
                        .font(.system(size: 32, weight: .light))
                        .foregroundStyle(.secondary)
                    Text("暂无最近文件")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity)
                .padding(28)
            } else {
                List {
                    ForEach(recent.urls, id: \.self) { url in
                        RecentRow(url: url) {
                            onPick(url)
                        } onRemove: {
                            recent.remove(url)
                        }
                    }
                }
                .listStyle(.plain)
                .frame(width: 380, height: min(CGFloat(recent.urls.count) * 44 + 12, 360))
            }
        }
    }
}

private struct RecentRow: View {
    let url: URL
    let onTap: () -> Void
    let onRemove: () -> Void
    @State private var hovering = false

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "doc.text")
                .foregroundStyle(.tint)
                .frame(width: 18)
            VStack(alignment: .leading, spacing: 2) {
                Text(url.lastPathComponent)
                    .font(.body)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Text(url.deletingLastPathComponent().path)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.head)
            }
            Spacer(minLength: 8)
            if hovering {
                Button(action: onRemove) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.borderless)
                .help("从列表移除")
            }
        }
        .padding(.vertical, 4)
        .padding(.horizontal, 6)
        .contentShape(Rectangle())
        .onTapGesture(perform: onTap)
        .onHover { hovering = $0 }
    }
}
