import Foundation
import SwiftUI

/// 最近文件列表（持久化到 UserDefaults，最多 10 个）。
@MainActor
final class RecentFiles: ObservableObject {
    static let shared = RecentFiles()

    @Published private(set) var urls: [URL] = []

    private let key = "MarkView.RecentFiles"
    private let max = 10

    private init() {
        load()
    }

    func add(_ url: URL) {
        // 标准化（解析 symlink）
        let resolved = url.resolvingSymlinksInPath()
        // 去重（去前 + 推前）
        urls.removeAll { $0.resolvingSymlinksInPath().path == resolved.path }
        urls.insert(resolved, at: 0)
        if urls.count > max { urls = Array(urls.prefix(max)) }
        save()
    }

    /// 从列表移除（不删文件）。
    func remove(_ url: URL) {
        let resolved = url.resolvingSymlinksInPath()
        urls.removeAll { $0.resolvingSymlinksInPath().path == resolved.path }
        save()
    }

    func clear() {
        urls.removeAll()
        save()
    }

    /// 清理掉已不存在的文件引用
    func prune() {
        let alive = urls.filter { FileManager.default.fileExists(atPath: $0.path) }
        if alive.count != urls.count {
            urls = alive
            save()
        }
    }

    private func load() {
        let arr = UserDefaults.standard.array(forKey: key) as? [String] ?? []
        urls = arr.map { URL(fileURLWithPath: $0) }
        prune()
    }

    private func save() {
        let arr = urls.map(\.path)
        UserDefaults.standard.set(arr, forKey: key)
    }
}
