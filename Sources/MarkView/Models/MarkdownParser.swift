import Foundation

/// 轻量级 Markdown → HTML 解析器（零依赖）。
/// 支持：ATX 标题、围栏代码块、行内代码、粗体/斜体、链接、图片、
/// 有序/无序列表、引用、表格、分隔线、段落。
/// 飞书级排版由 markdown.css 负责，这里只产出语义化 HTML。
enum MarkdownParser {

    static func render(_ source: String) -> String {
        let raw = source.replacingOccurrences(of: "\r\n", with: "\n")
        let lines = raw.components(separatedBy: "\n")
        var html: [String] = []
        var i = 0
        var headingCounter = 0

        while i < lines.count {
            let line = lines[i]

            // 空行
            if line.trimmingCharacters(in: .whitespaces).isEmpty {
                i += 1
                continue
            }

            // 围栏代码块
            if let fence = fenceMarker(line) {
                let (block, next) = consumeCodeBlock(lines: lines, start: i, fence: fence)
                html.append(block)
                i = next
                continue
            }

            // 分隔线
            if isHorizontalRule(line) {
                html.append("<hr/>")
                i += 1
                continue
            }

            // ATX 标题
            if let (level, text) = atxHeading(line), !text.isEmpty {
                let id = "h-\(headingCounter)"
                headingCounter += 1
                html.append("<h\(level) id=\"\(id)\">\(inline(text))</h\(level)>")
                i += 1
                continue
            }

            // 引用块
            if line.trimmingCharacters(in: .whitespaces).hasPrefix(">") {
                let (block, next) = consumeBlockquote(lines: lines, start: i)
                html.append(block)
                i = next
                continue
            }

            // 表格（| ... | 行 + 分隔行）
            if isTableStart(lines: lines, at: i) {
                let (block, next) = consumeTable(lines: lines, start: i)
                html.append(block)
                i = next
                continue
            }

            // 无序列表
            if isUnorderedListItem(line) {
                let (block, next) = consumeList(lines: lines, start: i, ordered: false)
                html.append(block)
                i = next
                continue
            }

            // 有序列表
            if isOrderedListItem(line) {
                let (block, next) = consumeList(lines: lines, start: i, ordered: true)
                html.append(block)
                i = next
                continue
            }

            // 段落（连续非空、非块级起始行）
            let (block, next) = consumeParagraph(lines: lines, start: i)
            html.append(block)
            i = next
        }

        return html.joined(separator: "\n")
    }

    // MARK: - Inline

    static func inline(_ text: String) -> String {
        var s = escapeHTML(text)

        // 行内代码先处理（内部不再转义）
        s = replaceInlineCode(s)

        // 图片 ![alt](url)
        s = replaceImages(s)

        // 链接 [text](url)
        s = replaceLinks(s)

        // 粗体 **x** 或 __x__
        s = replaceBold(s)

        // 斜体 *x* 或 _x_
        s = replaceItalic(s)

        // 删除线 ~~x~~
        s = replaceStrikethrough(s)

        return s
    }

    // MARK: - Block helpers

    private static func fenceMarker(_ line: String) -> String? {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        if trimmed.hasPrefix("```") { return "```" }
        if trimmed.hasPrefix("~~~") { return "~~~" }
        return nil
    }

    private static func consumeCodeBlock(lines: [String], start: Int, fence: String) -> (String, Int) {
        let firstLine = lines[start].trimmingCharacters(in: .whitespaces)
        let lang = String(firstLine.dropFirst(fence.count)).trimmingCharacters(in: .whitespaces)
        var content: [String] = []
        var i = start + 1
        while i < lines.count {
            let trimmed = lines[i].trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix(fence) { break }
            content.append(lines[i])
            i += 1
        }
        let code = escapeHTML(content.joined(separator: "\n"))
        let langClass = lang.isEmpty ? "" : " class=\"language-\(escapeAttr(lang))\""
        let block = "<pre><code\(langClass)>\(code)</code></pre>"
        return (block, i + 1)
    }

    private static func isHorizontalRule(_ line: String) -> Bool {
        let t = line.trimmingCharacters(in: .whitespaces)
        if t.count < 3 { return false }
        let c = t.first
        guard c == "-" || c == "*" || c == "_" else { return false }
        return t.allSatisfy { $0 == c || $0 == " " }
    }

    private static func atxHeading(_ line: String) -> (level: Int, text: String)? {
        let t = line.trimmingCharacters(in: .whitespaces)
        var level = 0
        for ch in t {
            if ch == "#" { level += 1 } else { break }
        }
        guard level >= 1 && level <= 6 else { return nil }
        let rest = t.dropFirst(level)
        guard rest.first == " " || rest.isEmpty else { return nil }
        let text = String(rest).trimmingCharacters(in: .whitespaces).trimmingCharacters(in: CharacterSet(charactersIn: "#"))
        return (level, text)
    }

    private static func consumeBlockquote(lines: [String], start: Int) -> (String, Int) {
        var inner: [String] = []
        var i = start
        while i < lines.count {
            let t = lines[i].trimmingCharacters(in: .whitespaces)
            if t.hasPrefix(">") {
                inner.append(String(t.dropFirst()).trimmingCharacters(in: .whitespaces))
                i += 1
            } else if t.isEmpty {
                break
            } else {
                break
            }
        }
        return ("<blockquote>\(render(inner.joined(separator: "\n")))</blockquote>", i)
    }

    private static func isTableStart(lines: [String], at i: Int) -> Bool {
        guard i + 1 < lines.count else { return false }
        let row = lines[i].trimmingCharacters(in: .whitespaces)
        let sep = lines[i + 1].trimmingCharacters(in: .whitespaces)
        guard row.contains("|"), sep.contains("|") else { return false }
        // 分隔行形如 | --- | :---: | ---: |
        let cells = sep.components(separatedBy: "|").filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
        return cells.allSatisfy { c in
            let t = c.trimmingCharacters(in: .whitespaces)
            return t.allSatisfy { $0 == "-" || $0 == ":" }
        }
    }

    private static func consumeTable(lines: [String], start: Int) -> (String, Int) {
        let headerCells = splitTableRow(lines[start])
        var rows: [[String]] = []
        var i = start + 2
        while i < lines.count {
            let t = lines[i].trimmingCharacters(in: .whitespaces)
            if t.isEmpty || !t.contains("|") { break }
            rows.append(splitTableRow(lines[i]))
            i += 1
        }
        var html = "<table><thead><tr>"
        for cell in headerCells {
            html.append("<th>\(inline(cell))</th>")
        }
        html.append("</tr></thead><tbody>")
        for row in rows {
            html.append("<tr>")
            for cell in row {
                html.append("<td>\(inline(cell))</td>")
            }
            html.append("</tr>")
        }
        html.append("</tbody></table>")
        return (html, i)
    }

    private static func splitTableRow(_ line: String) -> [String] {
        var s = line.trimmingCharacters(in: .whitespaces)
        if s.hasPrefix("|") { s.removeFirst() }
        if s.hasSuffix("|") { s.removeLast() }
        return s.components(separatedBy: "|").map { $0.trimmingCharacters(in: .whitespaces) }
    }

    private static func isUnorderedListItem(_ line: String) -> Bool {
        let t = line.trimmingCharacters(in: .whitespaces)
        guard let first = t.first else { return false }
        guard "-*+".contains(first) else { return false }
        let rest = t.dropFirst()
        return rest.first == " "
    }

    private static func isOrderedListItem(_ line: String) -> Bool {
        let t = line.trimmingCharacters(in: .whitespaces)
        var digits = ""
        for ch in t {
            if ch.isNumber { digits.append(ch) }
            else { break }
        }
        guard !digits.isEmpty else { return false }
        let rest = t.dropFirst(digits.count)
        return rest.hasPrefix(".") || rest.hasPrefix(")")
    }

    private static func consumeList(lines: [String], start: Int, ordered: Bool) -> (String, Int) {
        var items: [String] = []
        var i = start
        let indentUnit = "  "
        while i < lines.count {
            let line = lines[i]
            if line.trimmingCharacters(in: .whitespaces).isEmpty { i += 1; continue }
            let isItem = ordered ? isOrderedListItem(line) : isUnorderedListItem(line)
            if isItem {
                let t = line.trimmingCharacters(in: .whitespaces)
                var text = t
                // 去掉标记
                if ordered {
                    var d = ""
                    for ch in text { if ch.isNumber { d.append(ch) } else { break } }
                    text = String(text.dropFirst(d.count))
                    if text.hasPrefix(".") || text.hasPrefix(")") { text.removeFirst() }
                } else {
                    text.removeFirst()
                }
                text = text.trimmingCharacters(in: .whitespaces)
                items.append(text)
                i += 1
                // 续行（缩进）
                while i < lines.count {
                    let next = lines[i]
                    if next.trimmingCharacters(in: .whitespaces).isEmpty { break }
                    if next.hasPrefix(indentUnit) || next.hasPrefix("\t") {
                        items[items.count - 1] += "\n" + next.trimmingCharacters(in: .whitespaces)
                        i += 1
                    } else {
                        break
                    }
                }
            } else {
                break
            }
        }
        let tag = ordered ? "ol" : "ul"
        let body = items.map { "<li>\(inline($0).replacingOccurrences(of: "\n", with: "<br/>"))</li>" }.joined()
        return ("<\(tag)>\(body)</\(tag)>", i)
    }

    private static func consumeParagraph(lines: [String], start: Int) -> (String, Int) {
        var parts: [String] = []
        var i = start
        while i < lines.count {
            let line = lines[i]
            if line.trimmingCharacters(in: .whitespaces).isEmpty { break }
            if fenceMarker(line) != nil { break }
            if atxHeading(line) != nil { break }
            if isHorizontalRule(line) { break }
            if line.trimmingCharacters(in: .whitespaces).hasPrefix(">") { break }
            if isUnorderedListItem(line) || isOrderedListItem(line) { break }
            if isTableStart(lines: lines, at: i) { break }
            parts.append(line.trimmingCharacters(in: .whitespaces))
            i += 1
        }
        return ("<p>\(inline(parts.joined(separator: " ")))</p>", i)
    }

    // MARK: - Inline replacements

    private static func replaceInlineCode(_ s: String) -> String {
        var out = ""
        var i = s.startIndex
        while i < s.endIndex {
            if s[i] == "`" {
                if let end = s.range(of: "`", range: s.index(after: i)..<s.endIndex) {
                    let code = String(s[s.index(after: i)..<end.lowerBound])
                    out.append("<code>\(escapeHTML(code))</code>")
                    i = end.upperBound
                    continue
                }
            }
            out.append(s[i])
            i = s.index(after: i)
        }
        return out
    }

    private static func replaceImages(_ s: String) -> String {
        // ![alt](url)
        var result = ""
        var idx = s.startIndex
        while idx < s.endIndex {
            if out_isNotEscape(s, idx) && s[idx] == "!", let after = s.index(idx, offsetBy: 1, limitedBy: s.endIndex), after < s.endIndex, s[after] == "[" {
                if let close = s.range(of: "](", range: after..<s.endIndex),
                   let end = s.range(of: ")", range: close.upperBound..<s.endIndex) {
                    let alt = String(s[s.index(idx, offsetBy: 2)..<close.lowerBound])
                    let url = String(s[close.upperBound..<end.lowerBound])
                    result.append("<img src=\"\(escapeAttr(url))\" alt=\"\(escapeAttr(alt))\"/>")
                    idx = end.upperBound
                    continue
                }
            }
            result.append(s[idx])
            idx = s.index(after: idx)
        }
        return result
    }

    private static func replaceLinks(_ s: String) -> String {
        var result = ""
        var idx = s.startIndex
        while idx < s.endIndex {
            if out_isNotEscape(s, idx) && s[idx] == "[" {
                if let close = s.range(of: "](", range: s.index(after: idx)..<s.endIndex),
                   let end = s.range(of: ")", range: close.upperBound..<s.endIndex) {
                    let text = String(s[s.index(after: idx)..<close.lowerBound])
                    let url = String(s[close.upperBound..<end.lowerBound])
                    result.append("<a href=\"\(escapeAttr(url))\" target=\"_blank\" rel=\"noopener\">\(text)</a>")
                    idx = end.upperBound
                    continue
                }
            }
            result.append(s[idx])
            idx = s.index(after: idx)
        }
        return result
    }

    private static func replaceBold(_ s: String) -> String {
        var out = s
        out = replacePair(out, marker: "**", tag: "strong")
        out = replacePair(out, marker: "__", tag: "strong")
        return out
    }

    private static func replaceItalic(_ s: String) -> String {
        var out = s
        out = replacePair(out, marker: "*", tag: "em")
        out = replaceWordBoundaryItalic(out)
        return out
    }

    /// 只处理单词边界的 `_` 斜体（避免匹配 `map_hotel` 等标识符中的下划线）。
    private static func replaceWordBoundaryItalic(_ s: String) -> String {
        var out = ""
        var idx = s.startIndex
        while idx < s.endIndex {
            if s[idx] == "_" {
                let beforeOk = idx == s.startIndex || !isWordChar(s[s.index(before: idx)])
                if beforeOk {
                    let contentStart = s.index(after: idx)
                    if let closeIdx = s[contentStart..<s.endIndex].firstIndex(of: "_") {
                        let afterOk = s.index(after: closeIdx) == s.endIndex || !isWordChar(s[s.index(after: closeIdx)])
                        if afterOk {
                            out.append("<em>")
                            out.append(contentsOf: s[contentStart..<closeIdx])
                            out.append("</em>")
                            idx = s.index(after: closeIdx)
                            continue
                        }
                    }
                }
            }
            out.append(s[idx])
            idx = s.index(after: idx)
        }
        return out
    }

    private static func isWordChar(_ c: Character) -> Bool {
        c.isLetter || c.isNumber || c == "_"
    }

    private static func replaceStrikethrough(_ s: String) -> String {
        return replacePair(s, marker: "~~", tag: "del")
    }

    private static func replacePair(_ s: String, marker: String, tag: String) -> String {
        var out = ""
        var idx = s.startIndex
        var open = true
        while idx < s.endIndex {
            if let r = s.range(of: marker, range: idx..<s.endIndex) {
                out.append(contentsOf: s[idx..<r.lowerBound])
                out.append(open ? "<\(tag)>" : "</\(tag)>")
                open.toggle()
                idx = r.upperBound
            } else {
                out.append(contentsOf: s[idx..<s.endIndex])
                break
            }
        }
        return out
    }

    // MARK: - Escaping & helpers

    private static func out_isNotEscape(_ s: String, _ idx: String.Index) -> Bool {
        // 简化：链接 `[` 不考虑反斜杠转义
        return true
    }

    static func escapeHTML(_ s: String) -> String {
        var out = s
        out = out.replacingOccurrences(of: "&", with: "&amp;")
        out = out.replacingOccurrences(of: "<", with: "&lt;")
        out = out.replacingOccurrences(of: ">", with: "&gt;")
        return out
    }

    private static func escapeAttr(_ s: String) -> String {
        escapeHTML(s).replacingOccurrences(of: "\"", with: "&quot;")
    }

    static func slug(_ s: String) -> String {
        var out = s.lowercased()
            .replacingOccurrences(of: " ", with: "-")
            .replacingOccurrences(of: "\t", with: "-")
        out = out.unicodeScalars.filter { scalar in
            CharacterSet.urlPathAllowed.contains(scalar)
                || scalar == "-"
        }.map { String($0) }.joined()
        if out.isEmpty { out = "section" }
        return out
    }
}
