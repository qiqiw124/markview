import SwiftUI

/// 左侧边栏：多文档列表 + 选中态 + 可展开/收起目录 + 关闭按钮
struct SidebarView: View {
    @ObservedObject var tabManager: TabManager
    let onAdd: () -> Void   // 工具栏 + 按钮的回调

    var body: some View {
        VStack(spacing: 0) {
            // 用 ScrollView + LazyVStack 代替 List，List 的行选中绑定会吞掉
            // chevron/close 的点击事件。LazyVStack 让命中测试完全由我们自己控制。
            HStack {
                Text("文档 (\(tabManager.tabs.count))")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
                Spacer()
                Image(systemName: "plus")
                    .font(.system(size: 11, weight: .semibold))
                    .frame(width: 18, height: 18)
                    .contentShape(Rectangle())
                    .onTapGesture { onAdd() }
                    .help("添加 Markdown 文件 (⌘O)")
            }
            .padding(.horizontal, 10)
            .padding(.top, 8)
            .padding(.bottom, 4)

            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(tabManager.tabs) { store in
                        SidebarDocumentRow(
                            store: store,
                            isActive: tabManager.activeID == store.id,
                            onSelect: { tabManager.selectTab(store.id) },
                            onClose: { tabManager.closeTab(store.id) }
                        )
                    }
                }
            }
        }
    }
}

/// 单个文档行：箭头 + 图标 + 名称 + 脏标记 + 关闭按钮；展开后显示目录项
private struct SidebarDocumentRow: View {
    @ObservedObject var store: DocumentStore
    let isActive: Bool
    let onSelect: () -> Void
    let onClose: () -> Void
    @State private var isExpanded: Bool = false

    private var title: String {
        if let url = store.fileURL {
            return url.deletingPathExtension().lastPathComponent
        }
        return "未命名"
    }

    private var iconName: String {
        store.fileURL == nil ? "doc" : "doc.text"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            HStack(spacing: 4) {
                // 展开/收起箭头 — 用 .onTapGesture 而不是 Button，避免被 List 行选中吃掉点击
                Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .frame(width: 18, height: 18)
                    .contentShape(Rectangle())
                    .onTapGesture { isExpanded.toggle() }
                    .help(isExpanded ? "收起目录" : "展开目录")

                // 文档图标 + 名称（整行已有 onTapGesture）
                HStack(spacing: 5) {
                    Image(systemName: iconName)
                        .foregroundStyle(isActive ? Color.accentColor : .secondary)
                        .frame(width: 16)
                    Text(title)
                        .font(.system(size: 13, weight: isActive ? .medium : .regular))
                        .foregroundStyle(isActive ? Color.primary : .primary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    if store.isDirty {
                        Circle()
                            .fill(.orange)
                            .frame(width: 6, height: 6)
                            .help("有未保存的修改")
                    }
                }

                Spacer(minLength: 4)

                // 关闭按钮 — 用 onTapGesture 避免被 List 行选中吃掉
                Image(systemName: "xmark")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(.secondary)
                    .frame(width: 18, height: 18)
                    .contentShape(Rectangle())
                    .onTapGesture { onClose() }
                    .help("关闭")
            }
            .padding(.vertical, 3)
            .padding(.horizontal, 4)
            .background(
                RoundedRectangle(cornerRadius: 5)
                    .fill(isActive ? Color.accentColor.opacity(0.18) : Color.clear)
            )
            // 整行点击 = 选中 tab（chevron/close 各自的 onTapGesture 会优先于它）
            .contentShape(Rectangle())
            .onTapGesture(perform: onSelect)

            // 展开后的目录
            if isExpanded {
                if store.outline.isEmpty {
                    Text("  暂无目录")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .padding(.leading, 30)
                        .padding(.vertical, 2)
                } else {
                    ForEach(store.outline) { item in
                        SidebarOutlineRow(
                            item: item,
                            isActive: item.id == store.activeHeadingID
                        ) {
                            store.scrollToAnchor = item.id
                            onSelect()
                        }
                    }
                }
            }
        }
        .padding(.vertical, 1)
    }
}

/// 目录条目
private struct SidebarOutlineRow: View {
    let item: OutlineItem
    let isActive: Bool
    let onTap: () -> Void
    @State private var hovering = false

    var body: some View {
        HStack(spacing: 4) {
            // 占位 + 缩进
            Spacer().frame(width: CGFloat(max(0, item.level - 1)) * 12 + 22)
            Image(systemName: "heading")
                .font(.system(size: 9))
                .foregroundStyle(isActive ? Color.accentColor : Color.gray.opacity(0.5))
                .frame(width: 12)
            Text(item.text)
                .font(.system(size: 12))
                .foregroundStyle(isActive ? Color.accentColor : .primary)
                .lineLimit(1)
                .truncationMode(.tail)
            Spacer(minLength: 0)
        }
        .padding(.vertical, 2)
        .padding(.horizontal, 4)
        .background(
            RoundedRectangle(cornerRadius: 4)
                .fill(isActive ? Color.accentColor.opacity(0.18) : (hovering ? Color.gray.opacity(0.10) : Color.clear))
        )
        .contentShape(Rectangle())
        .onTapGesture(perform: onTap)
        .onHover { hovering = $0 }
    }
}
