import AppKit
import SwiftUI

/// 源码编辑器：NSTextView 封装，支持搜索。
struct SourceEditor: NSViewRepresentable {

    @Binding var text: String
    @Binding var isDirty: Bool
    /// 搜索关键字（可选），设置后高亮所有匹配
    var searchKeyword: Binding<String>?
    /// 搜索焦点（可选），触发滚动到第 N 个匹配（0-indexed）
    var searchFocus: Binding<Int>?

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSTextView.scrollableTextView()
        guard let textView = scrollView.documentView as? NSTextView else {
            return scrollView
        }

        textView.delegate = context.coordinator
        textView.font = NSFont.monospacedSystemFont(ofSize: 13, weight: .regular)
        textView.backgroundColor = NSColor.textBackgroundColor
        textView.isEditable = true
        textView.isSelectable = true
        textView.autoresizingMask = [.width]
        textView.textContainerInset = NSSize(width: 4, height: 0)

        scrollView.drawsBackground = false
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.borderType = .noBorder

        context.coordinator.scrollView = scrollView
        context.coordinator.textView = textView

        if !text.isEmpty {
            textView.string = text
        }

        return scrollView
    }

    func updateNSView(_ nsView: NSScrollView, context: Context) {
        guard let textView = nsView.documentView as? NSTextView else { return }

        // 同步文本内容（仅在外部变化时更新）
        if textView.string != text {
            let selectedRange = textView.selectedRange
            textView.string = text
            let clampedLoc = min(selectedRange.location, (text as NSString).length)
            textView.setSelectedRange(NSRange(location: clampedLoc, length: 0))
        }

        // 处理搜索
        if let kwBinding = searchKeyword, let focusBinding = searchFocus {
            let keyword = kwBinding.wrappedValue
            let focus = focusBinding.wrappedValue
            if !keyword.isEmpty {
                performSearch(textView: textView, keyword: keyword, focus: focus, coordinator: context.coordinator)
            } else {
                clearSearchHighlights(textView: textView, coordinator: context.coordinator)
            }
        }

        context.coordinator.parent = self
    }

    // MARK: - Search

    private func performSearch(textView: NSTextView, keyword: String, focus: Int, coordinator: Coordinator) {
        let nsText = textView.string as NSString
        let textStorage = textView.textStorage

        // 清除旧高亮
        textStorage?.removeAttribute(.backgroundColor, range: NSRange(location: 0, length: nsText.length))

        // 找出所有匹配
        var ranges: [NSRange] = []
        var searchRange = NSRange(location: 0, length: nsText.length)
        while searchRange.location < nsText.length {
            let found = nsText.range(of: keyword, options: [.caseInsensitive, .diacriticInsensitive], range: searchRange)
            if found.location != NSNotFound {
                ranges.append(found)
                let nextStart = found.location + found.length
                searchRange = NSRange(location: nextStart, length: nsText.length - nextStart)
            } else {
                break
            }
        }

        coordinator.searchRanges = ranges

        // 高亮所有匹配
        let highlightColor = NSColor.systemYellow.withAlphaComponent(0.35)
        for (index, range) in ranges.enumerated() {
            if index == focus {
                textStorage?.addAttribute(.backgroundColor, value: NSColor.systemYellow.withAlphaComponent(0.55), range: range)
            } else {
                textStorage?.addAttribute(.backgroundColor, value: highlightColor, range: range)
            }
        }

        // 滚动到焦点匹配
        if focus >= 0 && focus < ranges.count {
            let range = ranges[focus]
            textView.scrollRangeToVisible(range)
            textView.showFindIndicator(for: range)
        }
    }

    private func clearSearchHighlights(textView: NSTextView, coordinator: Coordinator) {
        let nsText = textView.string as NSString
        textView.textStorage?.removeAttribute(.backgroundColor, range: NSRange(location: 0, length: nsText.length))
        coordinator.searchRanges = []
    }

    // MARK: - Coordinator

    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: SourceEditor
        weak var textView: NSTextView?
        weak var scrollView: NSScrollView?
        var searchRanges: [NSRange] = []

        init(_ parent: SourceEditor) {
            self.parent = parent
        }

        func textDidChange(_ notification: Notification) {
            guard let textView = textView else { return }
            parent.text = textView.string
            parent.isDirty = true
        }
    }
}
