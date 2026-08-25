#!/bin/bash
# 一键发布脚本：Release 构建 → Developer ID 签名 → DMG → 公证 → Staple → GitHub Release
# 用法: ./Scripts/release_dmg.sh [--skip-notarize] [--skip-gh]
set -euo pipefail
cd "$(dirname "$0")/.."

APP_NAME="文件魔法棒"
BUNDLE_ID="com.eastlakestudio.aifiles"
VERSION=$(grep -m1 'MARKETING_VERSION' project.yml | awk -F'"' '{print $2}')
BUILD_DIR="build/release"
DMG_PATH="${BUILD_DIR}/${APP_NAME}-${VERSION}-arm64.dmg"
SIGN_IDENTITY="Developer ID Application"

SKIP_NOTARIZE="${1:-}"
SKIP_GH="${2:-}"

echo "==> [1/7] Xcode Release 构建"
xcodegen generate >/dev/null
xcodebuild -project AIFileAssistant.xcodeproj -scheme AIFileApp \
  -configuration Release -destination 'generic/platform=macOS' \
  -derivedDataPath "${BUILD_DIR}/DerivedData" \
  CODE_SIGN_IDENTITY="-" CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=YES \
  build >/dev/null
APP_PATH="$(find "${BUILD_DIR}/DerivedData/Build/Products/Release" -maxdepth 1 -name '*.app')"
[ -z "$APP_PATH" ] && { echo "构建失败：未找到 .app"; exit 1; }
echo "    ${APP_PATH}"

# 确保双语语言包就位（xcstrings 编译可能缺失时兜底）
python3 Scripts/gen_lproj.py "${APP_PATH}/Contents/Resources" >/dev/null

echo "==> [2/7] 代码签名"
if security find-identity -v -p codesigning 2>/dev/null | grep -q "${SIGN_IDENTITY}"; then
    codesign --force --deep --options runtime --timestamp \
        --entitlements Support/AIFileApp.entitlements \
        --sign "${SIGN_IDENTITY}" "$APP_PATH"
    SIGNED="developer-id"
    echo "    Developer ID 签名完成"
else
    codesign --force --deep --sign - "$APP_PATH"
    SIGNED="ad-hoc"
    echo "    ⚠️ 未找到 Developer ID Application 证书，使用 ad-hoc 签名（外网分发将触发 Gatekeeper 警告）"
fi

echo "==> [3/7] 制作 DMG"
rm -rf "${BUILD_DIR}/dmgroot"
mkdir -p "${BUILD_DIR}/dmgroot"
cp -R "$APP_PATH" "${BUILD_DIR}/dmgroot/"
ln -s /Applications "${BUILD_DIR}/dmgroot/Applications"
mkdir -p "${BUILD_DIR}"
rm -f "$DMG_PATH"
create-dmg --volname "$APP_NAME" --volicon "${APP_PATH}/Contents/Resources/AppIcon.icns" \
  --window-pos 200 120 --window-size 560 360 --icon-size 120 \
  --icon "$APP_NAME" 140 180 --app-drop-link 420 180 \
  --no-internet-enable "$DMG_PATH" "${BUILD_DIR}/dmgroot" || \
  hdiutil create -volname "$APP_NAME" -srcfolder "${BUILD_DIR}/dmgroot}" -ov -format UDZO "$DMG_PATH"

echo "==> [4/7] 公证 (Notarization)"
NOTARY_PROFILE="notarytool-key"
if [ "$SKIP_NOTARIZE" = "--skip-notarize" ]; then
    echo "    跳过（参数指定）"
elif [ "$SIGNED" != "developer-id" ]; then
    echo "    ⚠️ 跳过：ad-hoc 签名无法公证（需要 Developer ID 签名）"
elif ! xcrun notarytool history --keychain-profile "$NOTARY_PROFILE" >/dev/null 2>&1; then
    echo "    ⚠️ 跳过：未找到公证凭据 ${NOTARY_PROFILE}"
    echo "    请执行: xcrun notarytool store-credentials ${NOTARY_PROFILE} --apple-id <AppleID> --team-id J4RT98GF7B --password <App专用密码>"
else
    xcrun notarytool submit "$DMG_PATH" --keychain-profile "$NOTARY_PROFILE" --wait
    echo "==> [5/7] Staple 公证票据"
    xcrun stapler staple "$DMG_PATH"
    spctl -assess -t open --context context:primary-signature -v "$DMG_PATH" || true
fi

echo "==> [6/7] 校验产物"
codesign --verify --deep --strict "$APP_PATH" && echo "    签名校验: OK"
du -h "$DMG_PATH"

echo "==> [7/7] GitHub Release"
if [ "$SKIP_GH" = "--skip-gh" ]; then
    echo "    跳过（参数指定）"
elif command -v gh >/dev/null && gh auth status >/dev/null 2>&1; then
    gh release create "v${VERSION}" "$DMG_PATH" \
        --title "${APP_NAME} v${VERSION}" \
        --generate-notes
else
    echo "    ⚠️ gh CLI 未安装或未登录，手动上传："
    echo "    gh release create v${VERSION} '${DMG_PATH}' --title '${APP_NAME} v${VERSION}' --generate-notes"
fi

echo "✅ 完成: $DMG_PATH (签名: $SIGNED)"
