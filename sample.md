# MarkView 飞书风排版演示

> 一个 **干净、轻量、专注阅读** 的 Mac Markdown 查看器。本文档覆盖所有支持的排版元素。

## 快速开始

- 按下 ⌘O 打开 `.md` 文件
- 工具栏右侧切换 **深色模式** 与 **侧目录**
- 点击侧目录标题可快速跳转

## 支持的语法

行内样式：**粗体**、*斜/Users/wangqiqi/Downloads/cr-prompt-ios.md体*、~~删除线~~、`行内代码`、[外链示例](https://github.com)/Users/wangqiqi/Downloads/aicli-mr-review-prompt.md

### 列表

无序列表：
- 第一项
- 第二项
  - 嵌套项
  - 嵌套项二
- 第三项

有序列表：
1. 阶段 0：需求审核
2. 阶段 1：技术方案
3. 阶段 2：开发

### 引用

> "好的文档工具，不应该让用户思考排版，而应该让排版消失。"
>
> —— 飞书文档产品理念

### 代码块

```swift
struct MarkViewApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}
```/Users/wangqiqi/Desktop/亚朵生活iOS_对外通用能力梳理_三端对齐.md

```bash
swift build && swift run MarkView
```

### 表格

| 阶段 | 产物 | 状态 |
|------|------|------|
| 需求审核 | checklist.md | ✅ |
| 技术方案 | proposal.md | ✅ |
| 代码开发 | src/* | ✅ |
| 真机验证 | xcodebuild | ✅ |

### 分隔线

---

## 结语

MarkView 用 **SwiftUI 外壳 + WKWebView 内核** 混合架构，实现了原生侧目录体验 + 飞书级排版控制力。
