import Foundation
import SwiftUI
import AppKit
import UniformTypeIdentifiers

/// 持有多个 DocumentStore（一个 tab 一个），管理 active tab 与打开/关闭。
@MainActor
final class TabManager: ObservableObject {

    static let shared = TabManager()

    @Published private(set) var tabs: [DocumentStore] = []
    @Published var activeID: UUID?

    /// 用于 File > Open Recent 菜单在 ContentView 不可见时也能找到回调
    static var openURLHandler: ((URL) -> Void)?

    private init() {
        // 启动时建一个空 tab
        newTab()
    }

    // MARK: - 查询

    var currentStore: DocumentStore? {
        guard let id = activeID else { return nil }
        return tabs.first(where: { $0.id == id })
    }

    // MARK: - 生命周期

    @discardableResult
    func newTab() -> DocumentStore {
        let store = DocumentStore()
        tabs.append(store)
        activeID = store.id
        return store
    }

    func closeTab(_ id: UUID, force: Bool = false) {
        guard let idx = tabs.firstIndex(where: { $0.id == id }) else { return }
        let store = tabs[idx]
        if store.isDirty && !force {
            // 弹确认框（同步 modal 在 main 线程可执行）
            let alert = NSAlert()
            alert.messageText = "「\(store.displayName)」有未保存的修改"
            alert.informativeText = "关闭前是否保存？"
            alert.alertStyle = .warning
            alert.addButton(withTitle: "保存")
            alert.addButton(withTitle: "放弃")
            alert.addButton(withTitle: "取消")
            let resp = alert.runModal()
            switch resp {
            case .alertFirstButtonReturn:
                if let url = store.fileURL {
                    do { try store.save(source: store.source, to: url) }
                    catch { print("保存失败：\(error)"); return }
                } else {
                    // 没有 fileURL，调 saveAsFile 的逻辑要传入回调
                    let panel = NSSavePanel()
                    panel.allowedContentTypes = [UTType(filenameExtension: "md") ?? UTType.plainText]
                    panel.nameFieldStringValue = "untitled.md"
                    guard panel.runModal() == .OK, let url = panel.url else { return }
                    do { try store.save(source: store.source, to: url) }
                    catch { print("保存失败：\(error)"); return }
                    RecentFiles.shared.add(url)
                }
            case .alertSecondButtonReturn:
                break
            default:
                return
            }
        }
        store.clear()
        tabs.remove(at: idx)
        if activeID == id {
            if tabs.isEmpty {
                let placeholder = newTab()
                activeID = placeholder.id
            } else {
                let newIdx = min(idx, tabs.count - 1)
                activeID = tabs[newIdx].id
            }
        }
    }

    func closeCurrent() {
        if let id = activeID { closeTab(id) }
    }

    func selectTab(_ id: UUID) {
        if tabs.contains(where: { $0.id == id }) {
            activeID = id
        }
    }

    // MARK: - 查询

    /// 根据 URL 查找已打开的 tab（解析 symlink 后比较）。
    func tabForURL(_ url: URL) -> DocumentStore? {
        let resolved = url.resolvingSymlinksInPath().standardizedFileURL
        return tabs.first {
            guard let f = $0.fileURL else { return false }
            return f.resolvingSymlinksInPath().standardizedFileURL == resolved
        }
    }

    // MARK: - 打开

    /// 拖拽/最近文件统一入口：已打开则切过去，否则新建 tab。返回错误信息（nil=成功）。
    @discardableResult
    func openFromDrop(url: URL) -> String? {
        if let existing = tabForURL(url) {
            selectTab(existing.id)
            return nil
        }
        return openInNewTab(url)
    }

    /// 在当前 tab 打开（无 tab 时新建一个）。返回错误信息（nil=成功）。
    @discardableResult
    func openInCurrentTab(_ url: URL) -> String? {
        // 已打开则切过去
        if let existing = tabForURL(url) {
            selectTab(existing.id)
            return nil
        }
        let store: DocumentStore
        if let cur = currentStore, cur.fileURL == nil && !cur.isDirty {
            // 当前 tab 是空的，复用它
            store = cur
        } else {
            store = newTab()
        }
        activeID = store.id
        if let err = store.openFromDrop(url: url) {
            // 打开失败 → 关掉这个新建的空白 tab（保留旧 tab）
            if tabs.firstIndex(where: { $0.id == store.id }) != nil,
               tabs.filter({ $0.id != store.id }).isEmpty == false {
                // 当前 tab 是新建的，且不是唯一 tab，移除它
                tabs.removeAll { $0.id == store.id }
            }
            return err
        }
        RecentFiles.shared.add(url)
        RecentFiles.shared.prune()
        return nil
    }

    /// 在新 tab 打开
    @discardableResult
    func openInNewTab(_ url: URL) -> String? {
        let store = newTab()
        if let err = store.openFromDrop(url: url) {
            closeTab(store.id, force: true)
            return err
        }
        RecentFiles.shared.add(url)
        RecentFiles.shared.prune()
        return nil
    }
}
