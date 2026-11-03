#!/bin/bash
#
# MarkView 一键安装（macOS 13 ~ 27）
#
# 用法：把 dist/MarkView.zip 和本脚本放在同一目录，双击本脚本。
#       或终端执行：./install.command
#
set -uo pipefail
DIR="$(cd "$(dirname "$0")" && pwd)"
APP_DST="/Applications/MarkView.app"

echo "════════════════════════════════════════"
echo "  MarkView 安装程序  (macOS $(sw_vers -productVersion))"
echo "════════════════════════════════════════"

# ── 找安装包 ────────────────────────────────────────────────────────────
ZIP=""
for cand in "$DIR/MarkView.zip" "$DIR/MarkView-adhoc.zip"; do
    [ -f "$cand" ] && ZIP="$cand" && break
done

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

if [ -n "$ZIP" ]; then
    echo "📦 解压 $(basename "$ZIP") ..."
    if ! ditto -x -k "$ZIP" "$TMP" 2>/dev/null; then
        echo "❌ 解压失败：压缩包可能没下载完整，请重新下载。"
        exit 1
    fi
    APP_SRC="$(find "$TMP" -maxdepth 2 -name "*.app" -type d | head -1)"
elif [ -d "$DIR/MarkView.app" ]; then
    echo "📦 使用同目录的 MarkView.app ..."
    APP_SRC="$DIR/MarkView.app"
else
    echo "❌ 找不到 MarkView.zip 或 MarkView.app。"
    echo "   请把 MarkView.zip 和本脚本放在同一个文件夹里再运行。"
    exit 1
fi

if [ -z "${APP_SRC:-}" ] || [ ! -d "$APP_SRC" ]; then
    echo "❌ 解压后找不到 MarkView.app"
    exit 1
fi

# ── 清掉会让签名失效的残留文件 ───────────────────────────────────────────
# 旧发布包里有 Contents/MacOS/MarkView.bak，导致整包签名校验失败，
# 系统直接报「MarkView 已损坏，无法打开」。这里先清干净再验签。
find "$APP_SRC" -name "*.bak" -delete 2>/dev/null
find "$APP_SRC" -name "*.old" -delete 2>/dev/null
find "$APP_SRC" -name ".DS_Store" -delete 2>/dev/null
xattr -dr com.apple.quarantine "$APP_SRC" 2>/dev/null

# ── 验签 ────────────────────────────────────────────────────────────────
echo "🔍 校验签名 ..."
if ! codesign --verify --deep --strict "$APP_SRC" >/dev/null 2>&1; then
    echo "⚠️  签名无效，就地重新 ad-hoc 签名 ..."
    codesign --remove-signature "$APP_SRC" 2>/dev/null
    if ! codesign --force --sign - "$APP_SRC" 2>/dev/null \
       || ! codesign --verify --deep --strict "$APP_SRC" >/dev/null 2>&1; then
        echo "❌ 重新签名失败，安装包可能已损坏。"
        exit 1
    fi
fi
echo "✅ 签名有效"

# ── 关掉正在运行的旧版本 ─────────────────────────────────────────────────
if pgrep -x "MarkView" >/dev/null 2>&1; then
    echo "⏹  退出正在运行的 MarkView ..."
    osascript -e 'tell application "MarkView" to quit' 2>/dev/null
    sleep 1
    pgrep -x "MarkView" >/dev/null 2>&1 && killall MarkView 2>/dev/null
    sleep 0.5
fi

# ── 安装 ────────────────────────────────────────────────────────────────
echo "🚀 安装到 $APP_DST ..."
if [ -w /Applications ]; then
    rm -rf "$APP_DST" && cp -R "$APP_SRC" "$APP_DST"
else
    echo "   需要管理员权限："
    sudo rm -rf "$APP_DST" && sudo cp -R "$APP_SRC" "$APP_DST"
fi

if [ ! -d "$APP_DST" ]; then
    echo "❌ 拷贝失败"
    exit 1
fi

# ── 收尾：去隔离 + 刷新注册 + 验签 ───────────────────────────────────────
echo "🔓 摘掉 Gatekeeper 隔离标记 ..."
sudo xattr -dr com.apple.quarantine "$APP_DST" 2>/dev/null || xattr -dr com.apple.quarantine "$APP_DST" 2>/dev/null

/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -f "$APP_DST" 2>/dev/null

if codesign --verify --deep --strict "$APP_DST" >/dev/null 2>&1; then
    echo "✅ 安装完成，签名校验通过"
else
    echo "⚠️  安装完成，但签名校验未通过（应用可能仍能运行）"
fi

echo ""
echo "📌 版本：$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$APP_DST/Contents/Info.plist" 2>/dev/null)  build $(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$APP_DST/Contents/Info.plist" 2>/dev/null)"
echo ""
read -r -p "现在就打开 MarkView 吗？[Y/n] " ans
if [ "${ans:-Y}" != "n" ] && [ "${ans:-Y}" != "N" ]; then
    open "$APP_DST"
fi
echo ""
echo "以后可以从「启动台」或「应用程序」文件夹打开 MarkView。"
