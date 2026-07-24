import AppKit
import SwiftUI
import UniformTypeIdentifiers

enum ViewMode: String, CaseIterable, Identifiable {
    case split       // 源码 + 预览（默认）
    case preview     // 仅预览
    case source      // 仅源码
    var id: String { rawValue }
    var icon: String {
        switch self {
        case .split:   return "rectangle.split.2x1"
        case .preview: return "eye"
        case .source:  return "text.alignleft"
        }
    }
}

/// ContentView 全局共享的「当前 webview 引用」，让顶栏搜索框能跨 tab 操控激活的 webview。
@MainActor
final class ActiveWebView: ObservableObject {
    @Published var ref: MarkdownWebView.CoordinatorBox?
}

struct ContentView: View {

    @StateObject private var tabManager = TabManager.shared
    @ObservedObject private var recent = RecentFiles.shared
    @StateObject private var activeWebView = ActiveWebView()
    @ObservedObject private var updater = Updater.shared

    @State private var isDarkForced = false
    @State private var columnVisibility: NavigationSplitViewVisibility = .all
    @State private var showRecentPicker: Bool = false
    @State private var viewMode: ViewMode = .split
    @State private var fontScale: Double = 1.0
    @State private var showSearch: Bool = false
    @State private var searchKeyword: String = ""
    @State private var editorSearchFocus: Int = 0
    @State private var isDropTargeted: Bool = false

    private let mdType = UTType(filenameExtension: "md") ?? UTType.plainText

    var body: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            SidebarView(tabManager: tabManager, onAdd: { openFiles() })
                .navigationSplitViewColumnWidth(min: 200, ideal: 260, max: 380)
                .background(.regularMaterial)
        } detail: {
            VStack(spacing: 0) {
                ZStack(alignment: .top) {
                    if let store = tabManager.currentStore {
                        TabDetailView(
                            store: store,
                            viewMode: $viewMode,
                            fontScale: $fontScale,
                            isDarkForced: $isDarkForced,
                            showSearch: $showSearch,
                            searchKeyword: $searchKeyword,
                            editorSearchFocus: $editorSearchFocus,
                            activeWebView: activeWebView,
                            onDropURLs: handleDropURLs,
                            onOpen: { openFile() }
                        )
                        .id(store.id)  // 切换 tab 时强制重建，让 webview 拿到新 source
                    } else {
                        EmptyStateView { openFile() }
                    }
                    if showSearch, let _ = tabManager.currentStore {
                        SearchBar(
                            keyword: $searchKeyword,
                            onClose: {
                                showSearch = false
                                activeWebView.ref?.clearSearch()
                            }
                        ) { next in
                            activeWebView.ref?.search(keyword: searchKeyword, forward: next)
                            // 同步更新编辑器搜索焦点
                            if next { editorSearchFocus += 1 }
                            else { editorSearchFocus = max(0, editorSearchFocus - 1) }
                        }
                        .padding(8)
                        .transition(.move(edge: .top).combined(with: .opacity))
                    }
                }
                .animation(.easeInOut(duration: 0.15), value: showSearch)
            }
        }
        // 拖拽支持放在顶层：sidebar 和 detail 都能接收。isTargeted 用 dropZone
        // 区分高亮位置（sidebar | detail | full）。
        .onDrop(of: [.fileURL], isTargeted: $isDropTargeted, perform: handleDrop)
        .overlay {
            if isDropTargeted {
                ZStack {
                    Color.accentColor.opacity(0.12)
                    VStack(spacing: 12) {
                        Image(systemName: "arrow.down.doc.fill")
                            .font(.system(size: 56, weight: .light))
                        Text("拖入 .md 文件（支持多选）")
                            .font(.title2.weight(.medium))
                    }
                    .foregroundStyle(.tint)
                }
                .allowsHitTesting(false)
                .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.15), value: isDropTargeted)
        .toolbar { toolbarContent }
        .navigationTitle(navTitle)
        .frame(minWidth: 880, minHeight: 600)
        .onAppear {
            // 让 File > Open Recent 菜单项的点击能转回到 ContentView 打开
            MarkViewApp.openURLCallback = { url in self.openURL(url) }
            TabManager.openURLHandler = { url in self.openURL(url) }
        }
        .sheet(isPresented: $updater.presentSheet) {
            UpdateView(updater: updater)
        }
    }

    private var navTitle: String {
        guard let store = tabManager.currentStore else { return "MarkView" }
        return store.fileURL == nil ? "未命名" : store.displayName + (store.isDirty ? " •" : "")
    }

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItemGroup(placement: .primaryAction) {
            Button { openFile() } label: { Label("打开", systemImage: "folder") }
                .keyboardShortcut("o", modifiers: .command)

            Button { showRecentPicker = true } label: { Label("最近", systemImage: "clock.arrow.circlepath") }
                .keyboardShortcut("o", modifiers: [.command, .shift])
                .help("最近文件（⌘⇧O）")
                .popover(isPresented: $showRecentPicker, arrowEdge: .bottom) {
                    RecentPicker(
                        recent: recent,
                        onPick: { url in
                            showRecentPicker = false
                            openURL(url)
                        },
                        onClear: { recent.clear() }
                    )
                }

            Button { saveFile() } label: { Label("保存", systemImage: "square.and.arrow.down") }
                .keyboardShortcut("s", modifiers: .command)
                .disabled(!(tabManager.currentStore?.isDirty ?? false))
                .help("保存（⌘S）")

            Button { saveAsFile() } label: { Label("另存为", systemImage: "square.and.arrow.down.on.square") }
                .keyboardShortcut("s", modifiers: [.command, .shift])
                .help("另存为（⌘⇧S）")

            Divider()

            Picker("视图", selection: $viewMode) {
                ForEach(ViewMode.allCases) { mode in
                    Image(systemName: mode.icon).tag(mode)
                }
            }
            .pickerStyle(.segmented)
            .frame(width: 120)
            .help("源码/预览切换")

            Divider()

            Button { showSearch = true } label: { Label("搜索", systemImage: "magnifyingglass") }
                .keyboardShortcut("f", modifiers: .command)
                .help("搜索（⌘F）")

            Menu {
                Button("打印…") { activeWebView.ref?.print() }
                    .keyboardShortcut("p", modifiers: .command)
                Button("导出 PDF…") { exportPDF() }
                    .keyboardShortcut("e", modifiers: [.command, .shift])
            } label: { Label("更多", systemImage: "printer") }
            .help("打印与导出")

            Divider()

            Menu {
                Button("小   (85%)") { fontScale = 0.85 }
                Button("中 (100%)") { fontScale = 1.0 }
                Button("大 (120%)") { fontScale = 1.2 }
                Button("超大 (150%)") { fontScale = 1.5 }
            } label: {
                Label("字号", systemImage: "textformat.size")
            }
            .help("字号")

            Toggle(isOn: Binding(
                get: { columnVisibility != .detailOnly },
                set: { columnVisibility = $0 ? .all : .detailOnly }
            )) { Label("侧边栏", systemImage: "sidebar.left") }
            .toggleStyle(.button)
            .help("显示/隐藏侧边栏")

            Toggle(isOn: $isDarkForced) { Label("深色", systemImage: "moon.fill") }
                .toggleStyle(.button)
                .help("深色模式")

            // 隐藏的 ⌘T 新建 tab、⌘W 关闭 tab（macOS 标准快捷键）
            Button { tabManager.newTab() } label: { Label("新建 tab", systemImage: "plus.rectangle") }
                .keyboardShortcut("t", modifiers: .command)
                .hidden()
            Button { tabManager.closeCurrent() } label: { Label("关闭 tab", systemImage: "xmark.rectangle") }
                .keyboardShortcut("w", modifiers: .command)
                .hidden()
        }
    }

    // MARK: - 文件操作

    private func openFile() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [mdType, UTType.plainText]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        openURL(url)
    }

    /// 多选打开（侧边栏 + 按钮用）
    private func openFiles() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [mdType, UTType.plainText]
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        guard panel.runModal() == .OK else { return }
        handleDropURLs(panel.urls)
    }

    /// 统一从 URL 打开（NSOpenPanel、拖拽、最近文件 共用）。
    private func openURL(_ url: URL) {
        if let err = tabManager.openFromDrop(url: url) {
            presentDropError(err)
        }
    }

    /// 来自 WKWebView 子类的拖拽回调（多文件），逐个 openFromDrop。
    private func handleDropURLs(_ urls: [URL]) {
        var lastError: String?
        for url in urls {
            if let err = tabManager.openFromDrop(url: url) {
                lastError = err
            }
        }
        if let err = lastError {
            presentDropError(err)
        }
    }

    private func saveFile() {
        guard let store = tabManager.currentStore else { return }
        if let url = store.fileURL {
            do {
                try store.save(source: store.source, to: url)
                recent.add(url)
            } catch { print("保存失败：\(error)") }
        } else {
            saveAsFile()
        }
    }

    private func saveAsFile() {
        guard let store = tabManager.currentStore else { return }
        let panel = NSSavePanel()
        panel.allowedContentTypes = [mdType]
        panel.nameFieldStringValue = store.fileURL?.lastPathComponent ?? "untitled.md"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try store.save(source: store.source, to: url)
            recent.add(url)
        } catch { print("另存失败：\(error)") }
    }

    private func exportPDF() {
        guard let store = tabManager.currentStore else { return }
        let panel = NSSavePanel()
        panel.allowedContentTypes = [UTType.pdf]
        panel.nameFieldStringValue = (store.fileURL?.deletingPathExtension().lastPathComponent ?? "untitled") + ".pdf"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        activeWebView.ref?.exportPDF(to: url)
    }

    private func handleDrop(providers: [NSItemProvider]) -> Bool {
        // 过滤出 fileURL 类型的 provider，支持一次拖入多个文件
        let urlProviders = providers.filter {
            $0.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier)
        }
        guard !urlProviders.isEmpty else { return false }

        let logFile = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("markview-drop.log")
        func dropLog(_ msg: String) {
            let line = "[\(Date())] \(msg)\n"
            if let data = line.data(using: .utf8) {
                if let h = try? FileHandle(forWritingTo: logFile) {
                    h.seekToEndOfFile()
                    try? h.write(contentsOf: data)
                    try? h.close()
                } else {
                    try? data.write(to: logFile)
                }
            }
        }
        dropLog("--- drop begin, providers=\(providers.count), urlProviders=\(urlProviders.count) ---")

        var lastError: String?
        let group = DispatchGroup()
        for provider in urlProviders {
            group.enter()
            provider.loadDataRepresentation(forTypeIdentifier: UTType.fileURL.identifier) { data, error in
                if let error {
                    dropLog("load error: \(error.localizedDescription)")
                    lastError = "读取拖入内容失败：\(error.localizedDescription)"
                    group.leave()
                    return
                }
                guard let data else {
                    dropLog("data nil")
                    lastError = "拖入内容为空"
                    group.leave()
                    return
                }
                guard let url = URL(dataRepresentation: data, relativeTo: nil) else {
                    dropLog("URL parse failed, raw=\(String(data: data, encoding: .utf8) ?? "<binary>")")
                    lastError = "无法识别拖入的文件路径"
                    group.leave()
                    return
                }
                dropLog("URL parsed: \(url.absoluteString)")
                DispatchQueue.main.async {
                    dropLog("opening: \(url.path)")
                    if let err = self.tabManager.openFromDrop(url: url) {
                        lastError = err
                    }
                    group.leave()
                }
            }
        }
        group.notify(queue: .main) {
            if let err = lastError {
                self.presentDropError(err)
            }
        }
        return true
    }

    private func presentDropError(_ msg: String) {
        let alert = NSAlert()
        alert.messageText = "打开失败"
        alert.informativeText = msg + "\n\n详情：/tmp/markview-drop.log"
        alert.alertStyle = .warning
        alert.addButton(withTitle: "好")
        alert.runModal()
    }
}

// MARK: - 单 tab 详情视图

struct TabDetailView: View {
    @ObservedObject var store: DocumentStore
    @Binding var viewMode: ViewMode
    @Binding var fontScale: Double
    @Binding var isDarkForced: Bool
    @Binding var showSearch: Bool
    @Binding var searchKeyword: String
    @Binding var editorSearchFocus: Int
    let activeWebView: ActiveWebView
    let onDropURLs: ([URL]) -> Void
    let onOpen: () -> Void

    @State private var webViewRef: MarkdownWebView.CoordinatorBox?
    @State private var autoSaveTask: DispatchWorkItem?

    var body: some View {
        Group {
            if store.fileURL == nil {
                EmptyStateView(onOpen: onOpen)
            } else {
                // 始终保持 SourceEditor 和 webView 在视图树中，
                // 通过 GeometryReader + frame(width:) 控制宽度，
                // 避免 NSTextView/WKWebView 被重建
                GeometryReader { geo in
                    HStack(spacing: viewMode == .split ? 4 : 0) {
                        SourceEditor(
                            text: $store.source,
                            isDirty: $store.isDirty,
                            searchKeyword: $searchKeyword,
                            searchFocus: $editorSearchFocus
                        )
                        .frame(width: editorWidth(total: geo.size.width))
                        .opacity(viewMode == .preview ? 0 : 1)
                        .allowsHitTesting(viewMode != .preview)
                        .clipped()

                        if viewMode == .split {
                            Divider()
                        }

                        webView
                            .frame(width: previewWidth(total: geo.size.width))
                            .opacity(viewMode == .source ? 0 : 1)
                            .allowsHitTesting(viewMode != .source)
                            .clipped()
                    }
                }
            }
        }
        .onChange(of: store.source) { newSource in
            if newSource != store.lastSavedSource {
                store.isDirty = true
            }
            scheduleAutoSave(source: newSource)
        }
        .onChange(of: searchKeyword) { _ in
            editorSearchFocus = 0
        }
    }

    private func editorWidth(total: CGFloat) -> CGFloat {
        switch viewMode {
        case .preview: return 0
        case .source:  return total
        case .split:   return (total - 4) * 0.5
        }
    }

    private func previewWidth(total: CGFloat) -> CGFloat {
        switch viewMode {
        case .preview: return total
        case .source:  return 0
        case .split:   return (total - 4) * 0.5
        }
    }

    private var webView: some View {
        MarkdownWebView(
            source: store.source,
            isDarkForced: isDarkForced,
            fontScale: fontScale,
            onOutline: { store.outline = $0 },
            onActiveChange: { store.activeHeadingID = $0 },
            onDrop: onDropURLs,
            scrollToAnchor: $store.scrollToAnchor,
            coordinatorBox: Binding(
                get: { webViewRef },
                set: {
                    webViewRef = $0
                    activeWebView.ref = $0
                }
            )
        )
    }

    private func scheduleAutoSave(source: String) {
        guard let url = store.fileURL else { return }
        autoSaveTask?.cancel()
        let task = DispatchWorkItem { [weak store] in
            guard let store, store.isDirty else { return }
            do {
                try store.save(source: store.source, to: url)
            } catch {
                print("自动保存失败：\(error)")
            }
        }
        autoSaveTask = task
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5, execute: task)
    }
}

// MARK: - 搜索栏

struct SearchBar: View {
    @Binding var keyword: String
    let onClose: () -> Void
    let onNext: (Bool) -> Void     // true=next, false=prev
    @FocusState private var focused: Bool

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
            TextField("搜索关键字", text: $keyword)
                .textFieldStyle(.plain)
                .focused($focused)
                .onSubmit { onNext(true) }
            Button { onNext(false) } label: { Image(systemName: "chevron.up") }
                .buttonStyle(.borderless)
            Button { onNext(true) } label: { Image(systemName: "chevron.down") }
                .buttonStyle(.borderless)
            Button(action: onClose) { Image(systemName: "xmark.circle.fill") }
                .buttonStyle(.borderless)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(.separator))
        .frame(maxWidth: 480)
        .onAppear { focused = true }
    }
}

/// 空状态引导页。
struct EmptyStateView: View {
    let onOpen: () -> Void
    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "doc.richtext")
                .font(.system(size: 56, weight: .light))
                .foregroundStyle(.tint)
            Text("MarkView").font(.title2.bold())
            Text("飞书风 Markdown 查看器").foregroundStyle(.secondary)
            Button("打开 Markdown 文件 (⌘O)", action: onOpen)
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.regularMaterial)
    }
}
