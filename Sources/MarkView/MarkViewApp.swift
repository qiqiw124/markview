import SwiftUI
import AppKit

/// 拦截窗口关闭事件：红 X → 隐藏窗口而非退出；⌘W → 关闭当前 tab。
final class MainWindowDelegate: NSObject, NSWindowDelegate {
    static let shared = MainWindowDelegate()

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        // 红 X 点击：隐藏窗口，不退出应用
        sender.orderOut(nil)
        return false
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        // 让从终端直接启动的 executable 也能拿到前台 + Dock 图标
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)

        // 启动后延迟几秒静默检查更新（有新版本才弹窗，失败不打扰）
        DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
            Task { await Updater.shared.autoCheckIfNeeded() }
        }

        // 等 SwiftUI 创建窗口后，注入自定义行为
        DispatchQueue.main.async {
            guard let window = NSApp.windows.first else { return }
            window.delegate = MainWindowDelegate.shared

            // ⌘W → 关闭当前 tab。系统菜单的 Close (⌘W) 会触发 performClose:，
            // 所以先找到菜单项把它的 action 清掉，再用 keyDown monitor 拦截。
            for menu in NSApp.mainMenu?.items ?? [] {
                guard let sub = menu.submenu else { continue }
                for item in sub.items {
                    if item.keyEquivalent == "w",
                       item.keyEquivalentModifierMask == .command {
                        item.keyEquivalent = ""        // 取消快捷键
                    }
                }
            }
            NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
                if event.charactersIgnoringModifiers == "w",
                   event.modifierFlags.contains(.command),
                   !event.modifierFlags.contains(.shift) {
                    TabManager.shared.closeCurrent()
                    return nil
                }
                return event
            }
        }
    }

    /// Finder 双击 / `open file.md` / Dock 拖入 → 把 URL 转给 ContentView
    /// 对称 reopen：文件打开事件不会自动恢复最小化/隐藏的窗口，
    /// 这里显式 deminiaturize + makeKeyAndOrderFront + activate，把窗口和文件一起带到屏幕上。
    func application(_ application: NSApplication, open urls: [URL]) {
        for window in application.windows {
            if window.isMiniaturized {
                window.deminiaturize(nil)
            }
            if !window.isVisible {
                window.makeKeyAndOrderFront(nil)
            }
        }
        NSApp.activate(ignoringOtherApps: true)
        for url in urls {
            MarkViewApp.openURLCallback?(url)
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false  // 红 X 隐藏窗口后不退出，保持 Dock 图标存活
    }

    /// 点击 Dock 图标 / ⌘Tab 切回时，把最小化或隐藏的窗口重新显示到屏幕上
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        // 不依赖 hasVisibleWindows：最小化的窗口在不同 macOS 版本里对 flag 的判定不一致，
        // 直接读 isMiniaturized / isVisible 最可靠。两条 if 独立（非 else if）：deminiaturize
        // 是异步的，isVisible 可能还没刷新，第二条 if 兜底把窗口顶上来，对已可见窗口也无害。
        for window in sender.windows {
            if window.isMiniaturized {
                window.deminiaturize(nil)        // ⌘M 最小化到 Dock 的窗口：展开
            }
            if !window.isVisible {
                window.makeKeyAndOrderFront(nil) // 红 X 隐藏(orderOut)的窗口：显示
            }
        }
        NSApp.activate(ignoringOtherApps: true)
        return true
    }
}

@main
struct MarkViewApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @ObservedObject private var recent = RecentFiles.shared

    /// 全局"打开指定 URL"的回调，由 ContentView 注册。
    @MainActor static var openURLCallback: ((URL) -> Void)?

    var body: some Scene {
        // 用 Window（单窗口）而不是 WindowGroup，避免 application(_:open:) 触发时
        // 系统自动新建一个窗口。所有文件打开都走 AppDelegate → ContentView → TabManager。
        Window("MarkView", id: "main") {
            ContentView()
        }
        .defaultSize(width: 1100, height: 720)
        .commands {
            CommandGroup(after: .newItem) {
                OpenRecentMenu(recent: recent) { url in
                    Self.openURLCallback?(url)
                }
            }
            // App 菜单里「关于 MarkView」下方加「检查更新…」
            CommandGroup(after: .appInfo) {
                Button("检查更新…") {
                    Updater.shared.presentSheet = true
                    Task { await Updater.shared.checkForUpdates() }
                }
                .keyboardShortcut("u", modifiers: .command)
            }
        }
    }
}
