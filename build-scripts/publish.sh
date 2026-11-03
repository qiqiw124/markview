#!/bin/bash
#
# MarkView 发布：打 tag → 推代码 → 建 GitHub Release → 上传 MarkView.zip
#
# 用法：
#   GITHUB_TOKEN=ghp_xxx ./build-scripts/publish.sh
#   GITHUB_TOKEN=ghp_xxx ./build-scripts/publish.sh --notes notes.md
#
# token 也可以放在 ~/.markview/github_token（一行）。
# 需要 repo 权限（classic PAT: repo；fine-grained: Contents 读写）。
#
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

REPO="qiqiw124/markview"
APP_NAME="MarkView"
ZIP="$ROOT/dist/MarkView.zip"
PLIST="$ROOT/build-scripts/Info.plist"
NOTES_FILE=""

while [ $# -gt 0 ]; do
    case "$1" in
        --notes) NOTES_FILE="${2:-}"; shift 2 ;;
        *) echo "未知参数：$1"; exit 2 ;;
    esac
done

VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$PLIST")"
BUILD_NUMBER="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$PLIST")"
TAG="v${VERSION}"

TOKEN="${GITHUB_TOKEN:-}"
if [ -z "$TOKEN" ] && [ -f "$HOME/.markview/github_token" ]; then
    TOKEN="$(tr -d '\r\n' < "$HOME/.markview/github_token")"
fi
if [ -z "$TOKEN" ]; then
    echo "✗ 没有 token。请设置 GITHUB_TOKEN=ghp_xxx，或写入 ~/.markview/github_token"
    exit 1
fi

echo "▶ 校验 token"
LOGIN="$(curl -s -H "Authorization: Bearer $TOKEN" https://api.github.com/user \
    | python3 -c 'import sys,json; print(json.load(sys.stdin).get("login") or "")')"
if [ -z "$LOGIN" ]; then
    echo "✗ token 无效或已过期（GitHub 返回 401）。"
    echo "  重新生成：https://github.com/settings/tokens"
    echo "  classic PAT 勾 repo；fine-grained 选 $REPO 并给 Contents 读写。"
    exit 1
fi
echo "  已认证：$LOGIN"

# ── 确保包是最新的 ────────────────────────────────────────────────────────
if [ ! -f "$ZIP" ]; then
    echo "▶ dist/$APP_NAME.zip 不存在，先打包"
    ./build-scripts/package.sh
fi
ZIP_VER="$(ditto -x -k "$ZIP" /tmp/.mv-verify-$$ 2>/dev/null \
    && /usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' \
       "/tmp/.mv-verify-$$/$APP_NAME.app/Contents/Info.plist" 2>/dev/null; true)"
rm -rf "/tmp/.mv-verify-$$"
if [ "${ZIP_VER:-}" != "$VERSION" ]; then
    echo "✗ dist/$APP_NAME.zip 版本(${ZIP_VER:-未知}) 与 Info.plist($VERSION) 不一致，先重新打包"
    exit 1
fi
echo "  包版本：$VERSION ($BUILD_NUMBER)，$(du -h "$ZIP" | cut -f1)"

# ── 提交 + 打 tag + 推送 ─────────────────────────────────────────────────
if [ -n "$(git status --porcelain)" ]; then
    echo "✗ 工作区不干净，先提交或 stash"
    git status --short
    exit 1
fi

echo "▶ 打 tag $TAG 并推送"
git rev-parse "$TAG" >/dev/null 2>&1 && { echo "✗ tag $TAG 已存在"; exit 1; }
git tag -a "$TAG" -m "$APP_NAME $VERSION"
git push origin main
git push origin "$TAG"

# ── 建 release ───────────────────────────────────────────────────────────
echo "▶ 创建 GitHub Release $TAG"
if [ -n "$NOTES_FILE" ] && [ -f "$NOTES_FILE" ]; then
    BODY="$(cat "$NOTES_FILE")"
else
    BODY="$(printf '%s %s\n\n- 适配 macOS 26/27（Xcode 27 / Swift 6.4 构建）\n- 修复 bundle 签名失效导致「已损坏，无法打开」\n- 更新检查在 GitHub API 限频时自动退回 releases.atom\n' "$APP_NAME" "$VERSION")"
fi

PAYLOAD="$(python3 -c '
import json,sys
print(json.dumps({"tag_name":sys.argv[1],"name":sys.argv[1],
                  "body":sys.argv[2],"draft":False,"prerelease":False}))
' "$TAG" "$BODY")"

RELEASE_ID="$(curl -s -X POST \
    -H "Authorization: Bearer $TOKEN" \
    -H "Accept: application/vnd.github+json" \
    "https://api.github.com/repos/$REPO/releases" \
    -d "$PAYLOAD" \
    | python3 -c 'import sys,json; d=json.load(sys.stdin); print(d.get("id") or "")')"

if [ -z "$RELEASE_ID" ]; then
    echo "✗ 创建 release 失败"
    exit 1
fi
echo "  release id=$RELEASE_ID"

# ── 上传 asset（文件名必须是 MarkView.zip，更新器按名字找）───────────────
echo "▶ 上传 $APP_NAME.zip"
HTTP="$(curl -s -o /tmp/.mv-upload-$$.json -w '%{http_code}' -X POST \
    -H "Authorization: Bearer $TOKEN" \
    -H "Content-Type: application/zip" \
    --data-binary "@$ZIP" \
    "https://uploads.github.com/repos/$REPO/releases/$RELEASE_ID/assets?name=$APP_NAME.zip")"

if [ "$HTTP" != "201" ]; then
    echo "✗ 上传失败 HTTP $HTTP"
    cat /tmp/.mv-upload-$$.json
    rm -f /tmp/.mv-upload-$$.json
    exit 1
fi
rm -f /tmp/.mv-upload-$$.json

echo ""
echo "✅ 已发布 $TAG"
echo "   https://github.com/$REPO/releases/tag/$TAG"
echo "   老版本用户下次启动会自动看到更新提示。"
