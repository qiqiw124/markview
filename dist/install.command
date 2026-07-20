#!/bin/bash
# MarkView 一键安装
set -e
DIR="$(cd "$(dirname "$0")"; pwd)"

# 找 zip 包
if [ -f "$DIR/MarkView.zip" ]; then
    ZIP="$DIR/MarkView.zip"
elif [ -f "$DIR/MarkView-adhoc.zip" ]; then
    ZIP="$DIR/MarkView-adhoc.zip"
else
    echo "❌ 找不到 MarkView.zip"
    exit 1
fi

echo "📦 解压 $ZIP ..."
TMP=$(mktemp -d)
ditto -x -k "$ZIP" "$TMP"

# 找 app（zip 内可能叫 MarkView.app 或 MarkView-adhoc.app）
APP=$(find "$TMP" -maxdepth 2 -name "*.app" | head -1)
if [ -z "$APP" ]; then
    echo "❌ 解压后找不到 .app"
    rm -rf "$TMP"
    exit 1
fi

echo "🚀 拷到 /Applications/MarkView.app ..."
sudo rm -rf "/Applications/MarkView.app"
sudo cp -R "$APP" "/Applications/MarkView.app"

echo "🔓 摘掉 Gatekeeper 隔离标记 ..."
sudo xattr -dr com.apple.quarantine "/Applications/MarkView.app" 2>/dev/null || true

echo ""
echo "✅ 安装完成！"
echo ""
echo "👉 在 Finder 打开 /Applications，右键 MarkView.app → 打开 → 打开（首次）"
echo "   之后就可以双击了。"
rm -rf "$TMP"
