import Foundation
import SwiftUI
import AppKit

/// 从 GitHub Releases 拉到的一个版本信息。
struct ReleaseInfo: Equatable {
    let tag: String          // 原始 tag，如 "v1.0.1"
    let version: String      // 去掉前缀 v 的版本号，如 "1.0.1"
    let name: String         // release 标题
    let body: String         // release notes（markdown）
    let downloadURL: URL     // MarkView.zip 下载地址
    let htmlURL: URL         // release 页面
    let publishedAt: Date?
}

/// 更新器状态机。
enum UpdaterState: Equatable {
    case idle
    case checking
    case upToDate
    case available(ReleaseInfo)
    case downloading(progress: Double)   // 0...1
    case extracting
    case error(String)

    static func == (lhs: UpdaterState, rhs: UpdaterState) -> Bool {
        switch (lhs, rhs) {
        case (.idle, .idle), (.checking, .checking),
             (.upToDate, .upToDate), (.extracting, .extracting):
            return true
        case (.available(let a), .available(let b)):
            return a.tag == b.tag
        case (.downloading(let p1), .downloading(let p2)):
            return abs(p1 - p2) < 0.01
        case (.error(let a), (.error(let b))):
            return a == b
        default:
            return false
        }
    }
}

enum UpdaterError: LocalizedError {
    case noRelease
    case noZipAsset
    case networkError(String)
    case extractFailed(String)

    var errorDescription: String? {
        switch self {
        case .noRelease:        return "还没有发布任何更新版本"
        case .noZipAsset:       return "该版本未提供 MarkView.zip 下载"
        case .networkError(let s): return "网络错误（\(s)）"
        case .extractFailed(let s): return "解压失败（\(s)）"
        }
    }
}

/// 轻量自更新器：查 GitHub Releases -> 下载 zip -> 就地替换 .app -> 重启。
/// 不依赖 Sparkle，适配项目现有的"ditto 打 zip + ad-hoc 签名"发布方式。
@MainActor
final class Updater: ObservableObject {
    static let shared = Updater()

    private static let apiURL = URL(string: "https://api.github.com/repos/qiqiw124/markview/releases/latest")!

    @Published var state: UpdaterState = .idle
    /// 是否弹出更新窗口（菜单检查 + 启动后静默检查都可触发）
    @Published var presentSheet: Bool = false

    /// 启动时自动检查更新（默认开，用户可在更新窗口里关掉）
    @Published var autoCheck: Bool = (UserDefaults.standard.object(forKey: "autoCheckUpdates") as? Bool) ?? true {
        didSet { UserDefaults.standard.set(autoCheck, forKey: "autoCheckUpdates") }
    }

    var currentVersionText: String { currentVersion }

    /// 上次检查时间（持久化在 UserDefaults，用来给启动时的静默检查做节流）
    var lastChecked: Date? {
        let ts = UserDefaults.standard.double(forKey: "lastUpdateCheck")
        return ts > 0 ? Date(timeIntervalSince1970: ts) : nil
    }

    var lastCheckedText: String? {
        guard let date = lastChecked else { return nil }
        let f = DateFormatter()
        f.locale = Locale(identifier: "zh_CN")
        f.dateFormat = "yyyy-MM-dd HH:mm"
        return f.string(from: date)
    }

    private var currentVersion: String {
        (Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String) ?? "0.0.0"
    }

    private init() {}

    // MARK: - 检查更新

    /// 启动后静默检查一次：6 小时内查过就跳过，有新版本才弹窗，失败不打扰。
    func autoCheckIfNeeded() async {
        guard autoCheck else { return }
        if let last = lastChecked, Date().timeIntervalSince(last) < 6 * 3600 { return }
        await checkForUpdates(silent: true)
    }

    /// 拉 GitHub latest release 并比对版本号。
    /// - silent: true 时仅在有新版本时弹窗，失败/已最新都静默回 idle。
    func checkForUpdates(silent: Bool = false) async {
        state = .checking
        do {
            let release = try await fetchLatestRelease()
            UserDefaults.standard.set(Date().timeIntervalSince1970, forKey: "lastUpdateCheck")
            if isVersion(release.version, newerThan: currentVersion) {
                state = .available(release)
                if silent { presentSheet = true }
            } else {
                state = silent ? .idle : .upToDate
            }
        } catch {
            state = silent ? .idle : .error(error.localizedDescription)
        }
    }

    private func fetchLatestRelease() async throws -> ReleaseInfo {
        var req = URLRequest(url: Self.apiURL)
        req.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        req.setValue("MarkView/\(currentVersion)", forHTTPHeaderField: "User-Agent")
        req.timeoutInterval = 15
        let (data, resp) = try await URLSession.shared.data(for: req)
        if let http = resp as? HTTPURLResponse {
            if http.statusCode == 404 { throw UpdaterError.noRelease }
            if !(200..<300).contains(http.statusCode) {
                throw UpdaterError.networkError("HTTP \(http.statusCode)")
            }
        }
        return try parseRelease(data)
    }

    private func parseRelease(_ data: Data) throws -> ReleaseInfo {
        struct JSON: Decodable {
            let tag_name: String
            let name: String?
            let body: String?
            let html_url: String
            let published_at: String?
            let assets: [Asset]
            struct Asset: Decodable {
                let name: String
                let browser_download_url: String
            }
        }
        let json = try JSONDecoder().decode(JSON.self, from: data)
        // 优先找 MarkView.zip，否则取第一个 .zip asset
        let asset = json.assets.first { $0.name.lowercased() == "markview.zip" }
            ?? json.assets.first { $0.name.lowercased().hasSuffix(".zip") }
        guard let asset, let url = URL(string: asset.browser_download_url) else {
            throw UpdaterError.noZipAsset
        }
        let tag = json.tag_name
        let version = tag.hasPrefix("v") ? String(tag.dropFirst()) : tag
        let htmlURL = URL(string: json.html_url) ?? Self.apiURL
        let pubDate = json.published_at.flatMap { ISO8601DateFormatter().date(from: $0) }
        return ReleaseInfo(
            tag: tag, version: version,
            name: json.name ?? tag, body: json.body ?? "",
            downloadURL: url, htmlURL: htmlURL, publishedAt: pubDate
        )
    }

    /// 版本号比较：把 "1.2.3" 拆成 [1, 2, 3] 逐段比，缺位补 0。
    private func isVersion(_ a: String, newerThan b: String) -> Bool {
        let pa = a.split(separator: ".").compactMap { Int($0) }
        let pb = b.split(separator: ".").compactMap { Int($0) }
        let n = max(pa.count, pb.count)
        for i in 0..<n {
            let x = i < pa.count ? pa[i] : 0
            let y = i < pb.count ? pb[i] : 0
            if x != y { return x > y }
        }
        return false
    }

    // MARK: - 下载并安装

    func downloadAndInstall() async {
        guard case .available(let release) = state else { return }

        // 当前 .app 所在目录可写？从 DMG / 只读位置运行时直接报错
        let appURL = Bundle.main.bundleURL
        let parent = appURL.deletingLastPathComponent()
        guard FileManager.default.isWritableFile(atPath: parent.path) else {
            state = .error("当前应用所在目录不可写。请把 MarkView 拖到「应用程序」文件夹后再更新。")
            return
        }

        // 1. 下载 zip 到临时目录
        let tmpDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("markview-update-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: tmpDir, withIntermediateDirectories: true)
        let zipURL = tmpDir.appendingPathComponent("MarkView.zip")

        do {
            try await download(url: release.downloadURL, to: zipURL) { p in
                self.state = .downloading(progress: p)
            }
        } catch {
            state = .error("下载失败：\(error.localizedDescription)")
            return
        }

        // 2. ditto 解压
        state = .extracting
        do {
            try extractZip(at: zipURL, to: tmpDir)
        } catch {
            state = .error(error.localizedDescription)
            return
        }
        guard let newAppURL = findAppBundle(in: tmpDir) else {
            state = .error("压缩包内未找到 MarkView.app")
            return
        }

        // 3. 写替换脚本：等旧进程退出 -> swap -> 去隔离 + 重签 -> 重启 -> 清理
        let processName = ProcessInfo.processInfo.processName
        let scriptURL = tmpDir.appendingPathComponent("update.sh")
        let script = """
        #!/bin/bash
        APP_PATH="\(appURL.path)"
        NEW_APP="\(newAppURL.path)"
        OLD_APP="$APP_PATH.old"
        PROC_NAME="\(processName)"

        # 等旧进程退出（最多 30s）
        i=0
        while [ $i -lt 150 ]; do
          if ! pgrep -x "$PROC_NAME" > /dev/null 2>&1; then break; fi
          sleep 0.2
          i=$((i + 1))
        done
        sleep 0.3

        # swap：旧的先挪到 .old，新的就位，再删 .old；新就位失败则回滚
        rm -rf "$OLD_APP"
        mv "$APP_PATH" "$OLD_APP" || exit 1
        if ! mv "$NEW_APP" "$APP_PATH"; then
          mv "$OLD_APP" "$APP_PATH"
          exit 1
        fi
        rm -rf "$OLD_APP"

        # 去隔离 + ad-hoc 重签
        xattr -dr com.apple.quarantine "$APP_PATH" 2>/dev/null || true
        codesign --force --deep --sign - "$APP_PATH" 2>/dev/null || true

        # 重启
        open "$APP_PATH"

        # 清理临时目录
        rm -rf "\(tmpDir.path)"
        """
        do {
            try script.write(to: scriptURL, atomically: true, encoding: .utf8)
            try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: scriptURL.path)
        } catch {
            state = .error("无法创建更新脚本：\(error.localizedDescription)")
            return
        }

        // 4. 启动脚本，然后退出当前 app
        do {
            let proc = Process()
            proc.executableURL = scriptURL
            try proc.run()
        } catch {
            state = .error("无法启动更新脚本：\(error.localizedDescription)")
            return
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            NSApp.terminate(nil)
        }
    }

    func dismissError() {
        if case .error = state { state = .idle }
    }

    // MARK: - 下载（带进度）

    private func download(url: URL, to dest: URL, progress: @escaping (Double) -> Void) async throws {
        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
            let handler = DownloadHandler(
                dest: dest,
                progress: { p in Task { @MainActor in progress(p) } },
                completion: { result in
                    switch result {
                    case .success: cont.resume()
                    case .failure(let e): cont.resume(throwing: e)
                    }
                }
            )
            let session = URLSession(configuration: .default, delegate: handler, delegateQueue: nil)
            handler.retainSession = session
            session.downloadTask(with: url).resume()
        }
    }

    // MARK: - 解压

    private func extractZip(at zipURL: URL, to destDir: URL) throws {
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
        proc.arguments = ["-x", "-k", zipURL.path, destDir.path]
        let pipe = Pipe()
        proc.standardError = pipe
        try proc.run()
        proc.waitUntilExit()
        if proc.terminationStatus != 0 {
            let errData = try pipe.fileHandleForReading.readToEnd()
            let msg = String(data: errData ?? Data(), encoding: .utf8) ?? "unknown"
            throw UpdaterError.extractFailed(msg)
        }
    }

    /// 解压后在目录里找 .app：先找一级，再找二级。
    private func findAppBundle(in dir: URL) -> URL? {
        let fm = FileManager.default
        guard let contents = try? fm.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil) else { return nil }
        if let app = contents.first(where: { $0.pathExtension == "app" }) { return app }
        for sub in contents {
            var isDir: ObjCBool = false
            if fm.fileExists(atPath: sub.path, isDirectory: &isDir), isDir.boolValue {
                if let subs = try? fm.contentsOfDirectory(at: sub, includingPropertiesForKeys: nil),
                   let app = subs.first(where: { $0.pathExtension == "app" }) {
                    return app
                }
            }
        }
        return nil
    }
}

// MARK: - 下载 delegate

private final class DownloadHandler: NSObject, URLSessionDownloadDelegate {
    let dest: URL
    let progress: (Double) -> Void
    let completion: (Result<Void, Error>) -> Void
    var retainSession: URLSession?
    private var done = false

    init(dest: URL, progress: @escaping (Double) -> Void, completion: @escaping (Result<Void, Error>) -> Void) {
        self.dest = dest
        self.progress = progress
        self.completion = completion
    }

    private func finish(_ result: Result<Void, Error>) {
        guard !done else { return }
        done = true
        completion(result)
        retainSession?.invalidateAndCancel()
        retainSession = nil
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask,
                    didWriteData bytesWritten: Int64, totalBytesWritten: Int64, totalBytesExpectedToWrite: Int64) {
        guard totalBytesExpectedToWrite > 0 else { return }
        progress(Double(totalBytesWritten) / Double(totalBytesExpectedToWrite))
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {
        do {
            if FileManager.default.fileExists(atPath: dest.path) {
                try FileManager.default.removeItem(at: dest)
            }
            try FileManager.default.moveItem(at: location, to: dest)
            finish(.success(()))
        } catch {
            finish(.failure(error))
        }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        if let error { finish(.failure(error)) }
    }
}
