import Foundation
import SwiftUI

/// 当前打开的文档状态。
@MainActor
final class DocumentStore: ObservableObject, Identifiable {

    let id = UUID()
    @Published var fileURL: URL?
    @Published var source: String = ""
    @Published var outline: [OutlineItem] = []
    @Published var activeHeadingID: String?
    @Published var scrollToAnchor: String?
    /// 用户的 in-memory 编辑是否相对磁盘更新（true 时不自动重载以免覆盖）
    @Published var isDirty: Bool = false
    /// 最近一次「确认无修改」时的 source（用于 onChange 判断"是用户编辑还是程序加载"）
    @Published private(set) var lastSavedSource: String = ""

    private var lastReloadedMTime: Date?
    private var fileSource: DispatchSourceFileSystemObject?
    private var watchedFD: CInt = -1

    var displayName: String {
        fileURL?.deletingPathExtension().lastPathComponent ?? "未打开文档"
    }

    init() {
        // 环境变量 MARKVIEW_AUTO_OPEN=/path/to/file.md 时启动自动打开（用于演示/调试）
        if let path = ProcessInfo.processInfo.environment["MARKVIEW_AUTO_OPEN"],
           FileManager.default.fileExists(atPath: path) {
            let url = URL(fileURLWithPath: path)
            if let err = openFromDrop(url: url) {
                print("MARKVIEW_AUTO_OPEN failed: \(err)")
            }
        }
    }

    func open(url: URL) throws {
        // 注意：本应用未沙盒（sandbox=false），不需要 startAccessingSecurityScopedResource
        let data = try Data(contentsOf: url)
        let text = String(data: data, encoding: .utf8) ?? ""
        fileURL = url
        source = text
        lastSavedSource = text
        isDirty = false
        lastReloadedMTime = mtime(of: url)
        startWatching(url: url)
    }

    /// 从拖拽 URL 安全打开。容错版本：不会因文件问题崩溃，最坏情况返回 nil。
    @discardableResult
    func openFromDrop(url: URL) -> String? {
        let attrs = try? FileManager.default.attributesOfItem(atPath: url.path)
        if let size = attrs?[.size] as? Int, size > 10 * 1024 * 1024 {
            return "文件太大（\(size / 1024 / 1024) MB），暂不支持超过 10MB"
        }
        guard FileManager.default.isReadableFile(atPath: url.path) else {
            return "文件不可读（路径：\(url.path)）"
        }
        do {
            let data = try Data(contentsOf: url)
            let text = String(data: data, encoding: .utf8) ?? ""
            fileURL = url
            source = text
            lastSavedSource = text
            isDirty = false
            lastReloadedMTime = mtime(of: url)
            startWatching(url: url)
            return nil
        } catch {
            return "读取失败：\(error.localizedDescription)"
        }
    }

    /// 外部修改文件后自动重载。仅在不脏时生效，避免覆盖用户编辑。
    func reloadIfChanged() {
        guard let url = fileURL, !isDirty else { return }
        let current = mtime(of: url)
        guard let current, current != lastReloadedMTime else { return }
        if let data = try? Data(contentsOf: url),
           let text = String(data: data, encoding: .utf8) {
            source = text
            lastSavedSource = text
            lastReloadedMTime = current
            startWatching(url: url)
        }
    }

    func clear() {
        stopWatching()
        fileURL = nil
        source = ""
        lastSavedSource = ""
        outline = []
        activeHeadingID = nil
        scrollToAnchor = nil
        isDirty = false
        lastReloadedMTime = nil
    }

    /// 把指定内容写到指定 URL（用于保存/另存为）。
    func save(source: String, to url: URL) throws {
        try source.data(using: .utf8)?.write(to: url, options: .atomic)
        if url == fileURL { self.source = source }
        else { fileURL = url }
        self.lastSavedSource = source
        isDirty = false
        lastReloadedMTime = mtime(of: url)
        startWatching(url: url)
    }

    // MARK: - 文件监视

    private func mtime(of url: URL) -> Date? {
        (try? FileManager.default.attributesOfItem(atPath: url.path))?[.modificationDate] as? Date
    }

    private func startWatching(url: URL) {
        stopWatching()
        let fd = Darwin.open(url.path, O_EVTONLY)
        guard fd >= 0 else { return }
        watchedFD = fd
        let src = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fd,
            eventMask: [.write, .extend, .delete, .rename],
            queue: .main
        )
        src.setEventHandler { [weak self] in
            self?.reloadIfChanged()
        }
        src.setCancelHandler { [weak self] in
            guard let self else { return }
            if self.watchedFD >= 0 { close(self.watchedFD); self.watchedFD = -1 }
        }
        src.resume()
        fileSource = src
    }

    private func stopWatching() {
        fileSource?.cancel()
        fileSource = nil
    }

    deinit {
        if watchedFD >= 0 { close(watchedFD) }
    }
}
