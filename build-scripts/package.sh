#!/bin/bash
#
# MarkView 一键构建 + 打包（macOS 26/27 · Xcode 27 适配）
#
# 用法：
#   ./build-scripts/package.sh              # 构建 + 签名 + 出 zip/dmg
#   ./build-scripts/package.sh --install    # 额外装到 /Applications
#   MARKVIEW_VERSION=1.0.8 ./build-scripts/package.sh
#
# 产物：dist/MarkView.app、dist/MarkView.zip（GitHub Releases 用）、dist/MarkView.dmg
#
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

APP_NAME="MarkView"
DIST="$ROOT/dist"
APP="$DIST/$APP_NAME.app"
ZIP="$DIST/$APP_NAME.zip"
DMG="$DIST/$APP_NAME.dmg"
PLIST_SRC="$ROOT/build-scripts/Info.plist"
ICNS_SRC="$ROOT/build-scripts/AppIcon.icns"
ENTITLEMENTS="$ROOT/.entitlements/MarkView.entitlements"
INSTALL=0

for arg in "$@"; do
    case "$arg" in
        --install) INSTALL=1 ;;
        *) echo "未知参数：$arg"; exit 2 ;;
    esac
done

VERSION="${MARKVIEW_VERSION:-$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$PLIST_SRC")}"
BUILD_NUMBER="${MARKVIEW_BUILD:-$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$PLIST_SRC")}"

echo "▶ MarkView ${VERSION} (build ${BUILD_NUMBER})"
echo "  SDK: $(xcrun --show-sdk-version --sdk macosx) / Swift: $(swift --version 2>/dev/null | head -1)"

# ── 1. 重新生成嵌入资源（CSS/JS/HTML 都编进二进制）─────────────────────────
echo "▶ 1/6 生成嵌入资源 EmbeddedResources.swift"
python3 "$ROOT/build-scripts/embed_resources.py" >/dev/null
echo "  ok"

# ── 2. 构建 universal 二进制 ─────────────────────────────────────────────
echo "▶ 2/6 构建 arm64 + x86_64"
# Xcode 27 对 x86_64 会告警「已废弃」，属于预期；保留 x86_64 是为了让
# macOS 13~26 的 Intel 机器也能跑。只想出 arm64 时：MARKVIEW_ARCHS=arm64
ARCHS="${MARKVIEW_ARCHS:-arm64 x86_64}"
# shellcheck disable=SC2086
swift build -c release $(for a in $ARCHS; do printf -- '--arch %s ' "$a"; done) 2>&1 \
    | grep -vE "^\[[0-9]+ ?/ ?[0-9]+\]|^Building|^Build complete" || true

BIN="$(find .build -path "*Products/Release/MarkView" -type f -perm -u+x 2>/dev/null | head -1)"
[ -n "$BIN" ] || { echo "✗ 构建产物未找到"; exit 1; }
echo "  $(lipo -archs "$BIN")  $(du -h "$BIN" | cut -f1)"

# ── 3. 组装 .app ─────────────────────────────────────────────────────────
echo "▶ 3/6 组装 $APP_NAME.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/$APP_NAME"
cp "$PLIST_SRC" "$APP/Contents/Info.plist"
cp "$ICNS_SRC" "$APP/Contents/Resources/AppIcon.icns"
printf 'APPL????' > "$APP/Contents/PkgInfo"
chmod +x "$APP/Contents/MacOS/$APP_NAME"

# 版本号可被环境变量覆盖（不改模板也能发测试版）
/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $VERSION" "$APP/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleVersion $BUILD_NUMBER" "$APP/Contents/Info.plist"
plutil -lint "$APP/Contents/Info.plist" >/dev/null

# ── 4. 完整性自检 ────────────────────────────────────────────────────────
echo "▶ 4/6 包体自检"
# macOS 26+ 对 bundle 内容严格校验：Contents/MacOS 只允许有 Info.plist 声明的
# 可执行文件。历史上混进过 MarkView.bak，导致 codesign 校验整包失败
# （用户侧报「已损坏，无法打开」）。这里硬性拦截。
EXPECTED_EXEC="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleExecutable' "$APP/Contents/Info.plist")"
find "$APP" -name ".DS_Store" -delete 2>/dev/null || true
STRAY="$(ls -A "$APP/Contents/MacOS" | grep -vx "$EXPECTED_EXEC" || true)"
if [ -n "$STRAY" ]; then
    echo "✗ Contents/MacOS 内有多余文件（会破坏签名）：$STRAY"
    exit 1
fi
MISSING=0
for f in Info.plist "Resources/AppIcon.icns" "MacOS/$EXPECTED_EXEC"; do
    [ -f "$APP/Contents/$f" ] || { echo "✗ 缺少 $f"; MISSING=1; }
done
[ "$MISSING" -eq 0 ] || exit 1
echo "  ok"

# ── 5. ad-hoc 签名（先清旧签名 → 再签 → 严格校验）─────────────────────────
echo "▶ 5/6 ad-hoc 签名 + 校验"
# 注意：新版 codesign 的 --deep 已废弃，且 --deep 签名会漏掉部分内容。
# 本 bundle 无嵌套 framework/bundle，直接整体签名即可。
codesign --remove-signature "$APP" 2>/dev/null || true
codesign --force --timestamp=none --sign - \
         --entitlements "$ENTITLEMENTS" \
         "$APP" 2>/dev/null \
  || codesign --force --timestamp=none --sign - "$APP"

if ! codesign --verify --deep --strict --verbose=2 "$APP" 2>&1 | sed 's/^/  /'; then
    echo "✗ 签名校验失败"; exit 1
fi
codesign -d --entitlements - "$APP" 2>/dev/null | grep -q "com.apple.security.cs" \
    && echo "  entitlements ok"
echo "  $(codesign -dv "$APP" 2>&1 | grep -E '^Identifier|^Signature' | tr '\n' ' ')"

# ── 6. 打包 ──────────────────────────────────────────────────────────────
echo "▶ 6/6 打包 zip / dmg"
rm -f "$ZIP" "$DMG"
# --norsrc 去掉 ._ 资源分支文件，避免解压后多出垃圾文件破坏签名
ditto -c -k --norsrc --keepParent "$APP" "$ZIP"
hdiutil create -quiet -volname "$APP_NAME" -srcfolder "$APP" \
        -fs HFS+ -format UDZO -ov "$DMG"

echo ""
echo "✅ 完成  ${VERSION} (${BUILD_NUMBER})"
echo "   $(du -h "$ZIP" | cut -f1)  dist/$APP_NAME.zip"
echo "   $(du -h "$DMG" | cut -f1)  dist/$APP_NAME.dmg"

# ── 可选安装 ─────────────────────────────────────────────────────────────
if [ "$INSTALL" -eq 1 ]; then
    echo ""
    echo "▶ 安装到 /Applications"
    rm -rf "/Applications/$APP_NAME.app"
    cp -R "$APP" "/Applications/$APP_NAME.app"
    xattr -dr com.apple.quarantine "/Applications/$APP_NAME.app" 2>/dev/null || true
    codesign --verify --strict "/Applications/$APP_NAME.app" && echo "  已安装并通过签名校验"
fi
