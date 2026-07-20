# MarkView

飞书风 macOS Markdown 查看器。原生 SwiftPM + SwiftUI/AppKit，零外部依赖。

## 功能

- 实时预览：源码 / 预览 / 分屏三档切换
- 代码高亮（highlight.js）、表格、引用、列表完整渲染
- 自动跟随系统深浅色，可手动强制深色
- 大纲（TOC）侧边栏，点击跳转
- 文件拖入、最近文件、多 tab
- 自动保存、外部修改重载
- 内置搜索、打印、导出 PDF
- **自动更新**：启动后静默检查 GitHub Releases，菜单「检查更新…」（⌘U）手动触发

## 构建

```bash
swift build -c release
```

产物在 `.build/release/MarkView`。若改了 `Sources/MarkView/Resources/` 里的 CSS/JS/模板，需先重新生成嵌入资源：

```bash
python3 build-scripts/embed_resources.py
```

## 打包成 .app

```bash
# 1. 拷二进制进 bundle
cp .build/release/MarkView dist/MarkView.app/Contents/MacOS/MarkView

# 2. ad-hoc 签名
codesign --force --deep --sign - dist/MarkView.app

# 3. 打 zip（用于 GitHub Releases，自动更新器会下载它）
ditto -c -k --keepParent dist/MarkView.app dist/MarkView.zip

# 4. 打 dmg（可选）
hdiutil create -volname MarkView -srcfolder dist/MarkView.app -ov -format UDZO dist/MarkView.dmg
```

装到 /Applications：

```bash
rm -rf /Applications/MarkView.app
cp -R dist/MarkView.app /Applications/MarkView.app
codesign --force --deep --sign - /Applications/MarkView.app
xattr -dr com.apple.quarantine /Applications/MarkView.app
```

或直接双击 `dist/install.command`。

## 发布新版本（触发用户侧自动更新）

1. 改 `dist/MarkView.app/Contents/Info.plist` 里的 `CFBundleShortVersionString`（如 `1.0.1`）
2. 按上面流程构建 + 打包
3. 在 GitHub 创建 release，tag 用 `v1.0.1`（必须大于当前版本号才会提示更新），上传 `dist/MarkView.zip` 作为 asset
4. 用户侧 app 启动后会自动发现新版本，点「立即更新」即可下载替换并重启

> 签名方式为 ad-hoc，未走 Apple 公证。用户首次打开需在 Finder 右键 → 打开 → 打开。

## 系统要求

macOS 13.0+
