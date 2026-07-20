import SwiftUI

/// 更新检查 / 下载 / 安装 窗口。绑定 Updater 的状态机分情况渲染。
struct UpdateView: View {
    @ObservedObject var updater: Updater

    var body: some View {
        VStack(spacing: 16) {
            header
            Divider()
            content
            Spacer(minLength: 0)
            footer
        }
        .padding(20)
        .frame(width: 440, height: 360)
    }

    // MARK: - 顶部图标 + 标题

    @ViewBuilder
    private var header: some View {
        switch updater.state {
        case .available(let info):
            headerView(icon: "arrow.up.circle.fill", color: .accentColor,
                       title: "发现新版本 \(info.version)",
                       subtitle: "当前版本 \(updater.currentVersionText)")
        case .upToDate:
            headerView(icon: "checkmark.circle.fill", color: .green,
                       title: "已是最新版本",
                       subtitle: "版本 \(updater.currentVersionText)")
        case .error:
            headerView(icon: "exclamationmark.triangle.fill", color: .orange,
                       title: "更新失败", subtitle: nil)
        case .downloading, .extracting:
            headerView(icon: "arrow.down.circle.fill", color: .accentColor,
                       title: "正在更新…", subtitle: nil)
        case .idle, .checking:
            headerView(icon: "arrow.triangle.2.circlepath", color: .accentColor,
                       title: "正在检查更新…", subtitle: nil)
        }
    }

    private func headerView(icon: String, color: Color, title: String, subtitle: String?) -> some View {
        VStack(spacing: 4) {
            if case .checking = updater.state {
                ProgressView().controlSize(.large)
            } else if case .idle = updater.state {
                ProgressView().controlSize(.large)
            } else {
                Image(systemName: icon)
                    .font(.system(size: 40))
                    .foregroundStyle(color)
            }
            Text(title).font(.title3.bold())
            if let subtitle { Text(subtitle).font(.caption).foregroundStyle(.secondary) }
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - 中部内容

    @ViewBuilder
    private var content: some View {
        switch updater.state {
        case .available(let info):
            ScrollView {
                if info.body.isEmpty {
                    Text(info.name).font(.body)
                } else {
                    // 基础 markdown 渲染（标题/加粗/链接/代码），够用了
                    if let attr = try? AttributedString(markdown: info.body,
                                                        options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)) {
                        Text(attr).font(.body)
                    } else {
                        Text(info.body).font(.body)
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        case .downloading(let p):
            VStack(spacing: 6) {
                ProgressView(value: p)
                Text("\(Int(p * 100))%").font(.caption).foregroundStyle(.secondary)
            }
        case .extracting:
            ProgressView("正在安装更新…").frame(maxWidth: .infinity)
        case .error(let msg):
            ScrollView {
                Text(msg).font(.body).foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(maxHeight: .infinity)
        case .upToDate:
            if let last = updater.lastCheckedText {
                Text("上次检查：\(last)").font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
        case .idle, .checking:
            Spacer()
        }
    }

    // MARK: - 底部按钮

    private var footer: some View {
        HStack {
            Toggle("启动时自动检查", isOn: $updater.autoCheck)
                .font(.caption)
                .toggleStyle(.checkbox)
            Spacer()
            switch updater.state {
            case .available:
                Button("稍后") { updater.presentSheet = false }
                Button("立即更新") {
                    Task { await updater.downloadAndInstall() }
                }
                .buttonStyle(.borderedProminent)
            case .upToDate, .error:
                Button("关闭") {
                    updater.dismissError()
                    updater.presentSheet = false
                }
                .buttonStyle(.borderedProminent)
            case .downloading, .extracting:
                // 下载/安装中不允许关闭，避免半截文件
                Button("取消") { updater.presentSheet = false }
                    .disabled(true)
                    .opacity(0.4)
            case .idle, .checking:
                Button("取消") { updater.presentSheet = false }
            }
        }
    }
}
