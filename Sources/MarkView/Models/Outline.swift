import Foundation

/// 文档大纲节点（对应一个标题）。
struct OutlineItem: Identifiable, Equatable {
    let id: String          // DOM 锚点 id
    let level: Int          // 1~6
    let text: String
}

enum Outline {
    /// 从 WebView 回传的 JSON 数组解析大纲。
    static func parse(_ json: String) -> [OutlineItem] {
        guard let data = json.data(using: .utf8),
              let array = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]]
        else { return [] }
        return array.compactMap { item in
            guard let id = item["id"] as? String,
                  let level = item["level"] as? Int,
                  let text = item["text"] as? String
            else { return nil }
            return OutlineItem(id: id, level: level, text: text)
        }
    }
}
