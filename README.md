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

## 构建 + 打包（一条命令）

```bash
./build-scripts/package.sh            # 构建 + 签名 + 出 zip/dmg
./build-scripts/package.sh --install  # 顺便装到 /Applications
```

产出：

| 文件 | 用途 |
| --- | --- |
| `dist/MarkView.app` | 应用本体 |
| `dist/MarkView.zip` | GitHub Releases 用，内置更新器下载的就是它 |
| `dist/MarkView.dmg` | 手动分发用 |

脚本做的事：重新生成 `EmbeddedResources.swift`（CSS/JS/模板编进二进制）→ 构建 arm64 + x86_64 → 组装 bundle → **包体自检** → ad-hoc 签名 → `codesign --verify --deep --strict` 校验 → 打包。

版本号在 `build-scripts/Info.plist` 里改，也可以临时覆盖：

```bash
MARKVIEW_VERSION=1.0.8 MARKVIEW_BUILD=9 ./build-scripts/package.sh
MARKVIEW_ARCHS=arm64 ./build-scripts/package.sh   # 只出 Apple Silicon
```

## 发布新版本（触发用户侧自动更新）

一条命令搞定（提交干净的前提下）：

```bash
GITHUB_TOKEN=ghp_xxx ./build-scripts/publish.sh
```

它会依次：校验 token → 确认 `dist/MarkView.zip` 的版本与 `Info.plist` 一致 → 打 tag `vX.Y.Z` 并推送 → 建 Release → 上传 `MarkView.zip`。

手动发布的话：

1. 改 `build-scripts/Info.plist` 里的 `CFBundleShortVersionString` / `CFBundleVersion`
2. `./build-scripts/package.sh`
3. 在 GitHub 创建 release，tag 用 `v1.0.8`（**必须大于用户当前版本号**才会提示更新），上传 `dist/MarkView.zip` 作为 asset（文件名必须叫 `MarkView.zip`）
4. 用户侧 app 启动后会自己发现新版本，点「立即更新」即可下载替换并重启

> 更新器读的是 `releases/latest`。API 受限（403/限频）时自动退回 `releases.atom`，不需要 token。

## 签名与安装说明（重要）

签名方式为 **ad-hoc**，没有 Apple 开发者证书，也没走公证。所以：

- 直接从浏览器下载 dmg/zip 会被 Gatekeeper 拦一次，报「无法验证开发者」甚至「已损坏」。
- **最省事的安装方式**：把 `MarkView.zip` 和 `dist/install.command` 放同一目录，双击 `install.command`。脚本会解压、清掉会让签名失效的残留文件、验签、装到 `/Applications`、摘掉隔离标记。
- 手动装：拷到 `/Applications` 后执行
  ```bash
  xattr -dr com.apple.quarantine /Applications/MarkView.app
  ```

### 包体完整性约束（别踩）

`Contents/MacOS/` 里**只能有** `Info.plist` 的 `CFBundleExecutable` 声明的那一个可执行文件。
往那儿放过 `MarkView.bak` 之类的文件，会让整个 bundle 的签名校验失败 —— 系统直接报
「MarkView 已损坏，无法打开」。`package.sh` 的第 4 步会硬性拦截这种情况；`install.command`
和内置更新器也都带清理 + 失败回滚。

## 系统要求

- macOS 13.0+（在 macOS 27 / Xcode 27 / Swift 6.4 上构建验证）
- 架构：arm64 + x86_64（universal；Xcode 27 会把 x86_64 标为 deprecated，属预期）

## 手动构建（不用脚本时）

```bash
swift build -c release
python3 build-scripts/embed_resources.py   # 改了 Resources/ 之后需要
```

产物在 `.build/release/MarkView`（新版 SwiftPM 下实际位于 `.build/out/Products/Release/`）。
