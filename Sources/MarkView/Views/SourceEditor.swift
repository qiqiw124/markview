import SwiftUI

/// 源码编辑器：纯 TextEditor + 等宽字体。
struct SourceEditor: View {
    @Binding var text: String
    @Binding var isDirty: Bool

    var body: some View {
        TextEditor(text: $text)
            .font(.system(size: 13, design: .monospaced))
            .scrollContentBackground(.hidden)
            .background(Color(nsColor: .textBackgroundColor))
            .onChange(of: text) { _ in isDirty = true }
    }
}
