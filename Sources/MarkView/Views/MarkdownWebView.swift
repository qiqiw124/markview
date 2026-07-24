import AppKit
import SwiftUI
import WebKit

/// 用 WKWebView 渲染 Markdown HTML，负责侧目录、搜索、打印/导出。
struct MarkdownWebView: NSViewRepresentable {

    let source: String
    let isDarkForced: Bool
    let fontScale: Double
    let onOutline: ([OutlineItem]) -> Void
    let onActiveChange: (String) -> Void
    /// 拖入文件 URL 时的回调（用于多文件拖入打开）。从 decidePolicyFor 触发。
    var onDrop: (([URL]) -> Void)?

    @Binding var scrollToAnchor: String?
    @Binding var coordinatorBox: CoordinatorBox?

    /// 包装 Coordinator 用于外部调用（搜索/打印/导出）
    final class CoordinatorBox {
        weak var coordinator: Coordinator?

        func search(keyword: String, forward: Bool) {
            coordinator?.search(keyword: keyword, forward: forward)
        }
        func clearSearch() {
            coordinator?.clearSearch()
        }
        func print() {
            coordinator?.print()
        }
        func exportPDF(to url: URL) {
            coordinator?.exportPDF(to: url)
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(onOutline: onOutline, onActiveChange: onActiveChange, onDrop: onDrop)
    }

    func makeNSView(context: Context) -> WKWebView {
        let cfg = WKWebViewConfiguration()
        let userContent = WKUserContentController()
        userContent.add(context.coordinator, name: "outline")
        userContent.add(context.coordinator, name: "spy")
        userContent.add(context.coordinator, name: "search")
        cfg.userContentController = userContent
        cfg.defaultWebpagePreferences.allowsContentJavaScript = true

        let webView = DroppableWebView(frame: .zero, configuration: cfg)
        webView.navigationDelegate = context.coordinator
        webView.setValue(false, forKey: "drawsBackground")
        webView.onDropURLs = onDrop
        context.coordinator.webView = webView
        context.coordinator.onDrop = onDrop
        context.coordinator.fontScale = fontScale
        DispatchQueue.main.async { context.coordinator.fontScale = self.fontScale }
        render(into: webView, coordinator: context.coordinator)
        // 创建 CoordinatorBox 并设置 coordinator，同步给 activeWebView.ref（用于搜索等外部调用）
        let box = CoordinatorBox()
        box.coordinator = context.coordinator
        self.coordinatorBox = box
        return webView
    }

    func updateNSView(_ webView: WKWebView, context: Context) {
        if let droppable = webView as? DroppableWebView {
            droppable.onDropURLs = onDrop
        }
        context.coordinator.onDrop = onDrop
        if context.coordinator.lastSource != source {
            context.coordinator.lastSource = source
            context.coordinator.debounceWork?.cancel()
            let work = DispatchWorkItem {
                guard let wv = context.coordinator.webView else { return }
                self.render(into: wv, coordinator: context.coordinator)
            }
            context.coordinator.debounceWork = work
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2, execute: work)
        }
        if context.coordinator.fontScale != fontScale {
            context.coordinator.fontScale = fontScale
            webView.evaluateJavaScript("document.documentElement.style.setProperty('--base-font-size', '\(15 * fontScale)px');")
        }
        if let anchor = scrollToAnchor, anchor != context.coordinator.lastAnchor {
            context.coordinator.lastAnchor = anchor
            if webView.isLoading {
                // 页面还在加载（典型：刚切 tab，webview 重建中），等 didFinish 兜底
                context.coordinator.pendingAnchor = anchor
            } else {
                webView.evaluateJavaScript("window.__markview.scrollToAnchor(\(jsString(anchor)));")
            }
        }
    }

    private func render(into webView: WKWebView, coordinator: Coordinator) {
        let html = MarkdownParser.render(source)
        let css = ResourceLoader.css()
        var template = ResourceLoader.htmlTemplate()
        let darkClass = isDarkForced ? "dark" : ""
        template = template
            .replacingOccurrences(of: "__DARK_CLASS__", with: darkClass)
            .replacingOccurrences(of: "__CSS__", with: css)
            .replacingOccurrences(of: "__HL_CSS__", with: ResourceLoader.hlCSS())
            .replacingOccurrences(of: "__CONTENT__", with: html)
            .replacingOccurrences(of: "__BASE_FONT_SIZE__", with: "\(15 * fontScale)")
        webView.loadHTMLString(template, baseURL: nil)
    }

    private func jsString(_ s: String) -> String {
        let escaped = s
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "'", with: "\\'")
        return "'\(escaped)'"
    }

    // MARK: - Coordinator

    final class Coordinator: NSObject, WKNavigationDelegate, WKScriptMessageHandler {
        weak var webView: WKWebView?
        var lastSource: String?
        var lastAnchor: String?
        var fontScale: Double = 1.0
        var debounceWork: DispatchWorkItem?
        private let onOutline: ([OutlineItem]) -> Void
        private let onActiveChange: (String) -> Void
        var onDrop: (([URL]) -> Void)?
        private var lastOutlineIDs: [String] = []
        private var searchMatches: [Int] = []
        private var searchCursor: Int = 0
        private var lastSearchKeyword: String = ""
        /// scrollToAnchor 已被设置但 webview 尚未加载完时暂存，didFinish 时再滚一次
        var pendingAnchor: String?

        init(onOutline: @escaping ([OutlineItem]) -> Void,
             onActiveChange: @escaping (String) -> Void,
             onDrop: (([URL]) -> Void)? = nil) {
            self.onOutline = onOutline
            self.onActiveChange = onActiveChange
            self.onDrop = onDrop
        }

        // MARK: 消息

        func userContentController(_ uc: WKUserContentController,
                                   didReceive message: WKScriptMessage) {
            switch message.name {
            case "outline":
                if let text = message.body as? String {
                    let items = Outline.parse(text)
                    if items.map(\.id) == lastOutlineIDs { return }
                    lastOutlineIDs = items.map(\.id)
                    onOutline(items)
                }
            case "spy":
                if let id = message.body as? String { onActiveChange(id) }
            case "search":
                if let info = message.body as? [String: Any],
                   let count = info["count"] as? Int,
                   let first = info["firstIndex"] as? Int {
                    searchMatches = (0..<count).map { $0 }
                    searchCursor = first
                }
            default: break
            }
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            webView.evaluateJavaScript("document.documentElement.style.setProperty('--base-font-size', '\(15 * fontScale)px');")
            webView.evaluateJavaScript("window.__markview.collectOutline();")
            // 如果 webview 重建前 store 已经设过 scrollToAnchor，updateNSView 那次 evaluateJavaScript
            // 会失败（页面还没加载完）。这里在 didFinish 兜底再滚一次。
            if let pending = self.pendingAnchor {
                self.pendingAnchor = nil
                self.lastAnchor = pending
                webView.evaluateJavaScript("window.__markview.scrollToAnchor(\(Self.jsString(pending)));")
            }
            webView.evaluateJavaScript("""
                (function(){
                    var headings = Array.from(document.querySelectorAll('#doc h1, #doc h2, #doc h3, #doc h4, #doc h5, #doc h6'));
                    if (headings.length === 0) return;
                    function update() {
                        var current = headings[0];
                        var offset = 80;
                        for (var i = 0; i < headings.length; i++) {
                            if (headings[i].getBoundingClientRect().top - offset <= 0) current = headings[i];
                            else break;
                        }
                        headings.forEach(function(h){h.classList.remove('outline-active')});
                        if (current) {
                            current.classList.add('outline-active');
                            if (window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers.spy) {
                                window.webkit.messageHandlers.spy.postMessage(current.id);
                            }
                        }
                    }
                    window.addEventListener('scroll', update, {passive: true});
                    update();
                })();
            """)
            // 按需懒加载：只在检测到代码块/mermaid 时才注入对应 JS
            let hljs = ResourceLoader.highlightJS()
            let mermaid = ResourceLoader.mermaidJS()
            let lazyJS = """
            (function(){
                var hasCode = document.querySelector('pre code');
                var hasMermaid = document.querySelector('code.language-mermaid');
                if (hasCode) { eval(\(Self.jsString(hljs))); try { hljs.highlightAll(); } catch(e){} }
                if (hasMermaid) {
                    document.querySelectorAll('code.language-mermaid').forEach(function(c){
                        var p = c.parentNode;
                        var d = document.createElement('div');
                        d.className = 'mermaid';
                        d.textContent = c.textContent;
                        p.parentNode.replaceChild(d, p);
                    });
                    eval(\(Self.jsString(mermaid)));
                    try { mermaid.run({querySelector:'.mermaid'}); } catch(e){}
                }
            })();
            """
            webView.evaluateJavaScript(lazyJS)
        }

        func webView(_ webView: WKWebView,
                     decidePolicyFor navigationAction: WKNavigationAction,
                     decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
            // 用户点击链接（外部）→ 走系统默认浏览器；不要让 WebView 自己跳
            if navigationAction.navigationType == .linkActivated,
               let url = navigationAction.request.url {
                NSWorkspace.shared.open(url)
                decisionHandler(.cancel); return
            }
            decisionHandler(.allow)
        }

        // MARK: 外部命令

        func search(keyword: String, forward: Bool) {
            guard let webView else { return }
            let kw = Self.jsString(keyword)
            if keyword == lastSearchKeyword && !searchMatches.isEmpty {
                searchCursor = forward
                    ? (searchCursor + 1) % max(searchMatches.count, 1)
                    : (searchCursor - 1 + searchMatches.count) % max(searchMatches.count, 1)
                let idx = searchMatches[searchCursor]
                webView.evaluateJavaScript("window.__markview.jumpTo(\(idx));")
            } else {
                lastSearchKeyword = keyword
                webView.evaluateJavaScript("window.__markview.runSearch(\(kw));")
            }
        }

        func clearSearch() {
            guard let webView else { return }
            webView.evaluateJavaScript("window.__markview.clearSearch();")
            searchMatches = []
            searchCursor = 0
            lastSearchKeyword = ""
        }

        func print() {
            guard let webView else { return }
            let info = NSPrintInfo.shared
            let op = webView.printOperation(with: info)
            op.runModal(for: NSApp.keyWindow ?? NSWindow(),
                        delegate: nil,
                        didRun: nil,
                        contextInfo: nil)
        }

        func exportPDF(to url: URL) {
            guard let webView else { return }
            let config = WKPDFConfiguration()
            config.rect = webView.bounds
            webView.createPDF(configuration: config) { result in
                if case .success(let data) = result {
                    try? data.write(to: url)
                }
            }
        }

        static func jsString(_ s: String) -> String {
            let escaped = s
                .replacingOccurrences(of: "\\", with: "\\\\")
                .replacingOccurrences(of: "'", with: "\\'")
            return "'\(escaped)'"
        }
    }
}

/// 读取 SPM 资源。CSS / HTML / highlight.js / Mermaid 全部嵌入二进制（避免 Bundle.module 在 translocation 下崩）。
enum ResourceLoader {
    static func css() -> String { embeddedMarkdownCSS }
    static func htmlTemplate() -> String { embeddedHTMLTemplate }
    static func highlightJS() -> String { embeddedHighlightJS }
    static func hlCSS() -> String { embeddedHLCSS }
    static func mermaidJS() -> String { embeddedMermaidJS }
}

/// WKWebView 子类：明确拒绝 drop，让上层 SwiftUI 的 .onDrop 接管。
/// WKWebView 内部实际处理 drag 的 view 是私有的，子类化后 override draggingEntered
/// 不会被调用（drag 仍被 WebKit 内部吞）。所以这里只声明意图，不做拦截。
final class DroppableWebView: WKWebView {
    /// 保留字段（暂未用，作为后续 JS 桥接 drop 的占位）
    var onDropURLs: (([URL]) -> Void)?
}
