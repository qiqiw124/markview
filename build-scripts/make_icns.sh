#!/bin/bash
set -e
DIR="$(cd "$(dirname "$0")"; pwd)"
PNG="$DIR/AppIcon.png"
ICONSET="$DIR/AppIcon.iconset"
ICNS="$DIR/AppIcon.icns"

echo "🎨 生成 1024x1024 源图标..."
swift "$DIR/make_icon.swift" "$PNG"

echo "🔄 生成多尺寸 iconset..."
rm -rf "$ICONSET"
mkdir "$ICONSET"

# macOS 标准 icon 尺寸
sips -z 16 16   "$PNG" --out "$ICONSET/icon_16x16.png" >/dev/null
sips -z 32 32   "$PNG" --out "$ICONSET/icon_16x16@2x.png" >/dev/null
sips -z 32 32   "$PNG" --out "$ICONSET/icon_32x32.png" >/dev/null
sips -z 64 64   "$PNG" --out "$ICONSET/icon_32x32@2x.png" >/dev/null
sips -z 128 128 "$PNG" --out "$ICONSET/icon_128x128.png" >/dev/null
sips -z 256 256 "$PNG" --out "$ICONSET/icon_128x128@2x.png" >/dev/null
sips -z 256 256 "$PNG" --out "$ICONSET/icon_256x256.png" >/dev/null
sips -z 512 512 "$PNG" --out "$ICONSET/icon_256x256@2x.png" >/dev/null
sips -z 512 512 "$PNG" --out "$ICONSET/icon_512x512.png" >/dev/null
sips -z 1024 1024 "$PNG" --out "$ICONSET/icon_512x512@2x.png" >/dev/null

echo "📦 打包 .icns..."
iconutil -c icns "$ICONSET" -o "$ICNS"

# 嵌入到 .app
APP_DIR="$DIR/../dist/MarkView.app/Contents/Resources"
mkdir -p "$APP_DIR"
cp "$ICNS" "$APP_DIR/AppIcon.icns"
echo "✅ AppIcon.icns → $APP_DIR/AppIcon.icns"

# 更新 Info.plist
PLIST="$DIR/../dist/MarkView-adhoc.app/Contents/Info.plist"
if grep -q CFBundleIconFile "$PLIST" 2>/dev/null; then
    echo "ℹ️  Info.plist 已有 CFBundleIconFile"
else
    # 在 CFBundleVersion 之后插入
    /usr/libexec/PlistBuddy -c "Add :CFBundleIconFile string AppIcon" "$PLIST" 2>/dev/null || true
    /usr/libexec/PlistBuddy -c "Add :CFBundleIconName string AppIcon" "$PLIST" 2>/dev/null || true
    echo "✅ Info.plist 已更新 CFBundleIcon*"
fi

# 清理
rm -rf "$ICONSET" "$PNG"
echo "🧹 清理完成"
