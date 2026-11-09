#!/bin/bash
# 用 Developer ID 签名、提交 Apple 公证，打包成可以直接分发的 zip。
#
#   TEAM_ID=XXXXXXXXXX scripts/release.sh
#
# 需要：付费 Apple 开发者账号，并且已经在 Xcode › 设置 › 账户 里登录。
# Developer ID 证书不存在时，Xcode 会自动生成；公证用的也是 Xcode 里的账号，不需要另外的密码。
set -euo pipefail
cd "$(dirname "$0")/.."

: "${TEAM_ID:?请设置 TEAM_ID，也就是 Apple 开发者团队 ID（10 位）}"

ARCHIVE=build/Elsewhere.xcarchive
EXPORT=build/release
OPTIONS=build/ExportOptions.plist
rm -rf "$ARCHIVE" "$EXPORT"
mkdir -p build

echo "▸ 归档"
xcodebuild archive -project Elsewhere.xcodeproj -scheme Elsewhere -configuration Release \
  -destination 'generic/platform=macOS' -archivePath "$ARCHIVE" -derivedDataPath build \
  DEVELOPMENT_TEAM="$TEAM_ID" CODE_SIGN_STYLE=Automatic CODE_SIGN_IDENTITY="Apple Development" \
  ENABLE_HARDENED_RUNTIME=YES -allowProvisioningUpdates -quiet

cat > "$OPTIONS" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>method</key><string>developer-id</string>
  <key>teamID</key><string>$TEAM_ID</string>
  <key>signingStyle</key><string>automatic</string>
  <key>destination</key><string>upload</string>
</dict>
</plist>
EOF

echo "▸ Developer ID 签名并提交公证"
xcodebuild -exportArchive -archivePath "$ARCHIVE" -exportOptionsPlist "$OPTIONS" \
  -exportPath "$EXPORT" -allowProvisioningUpdates

echo "▸ 等待公证结果（通常几分钟，第一次可能要一小时以上）"
for _ in $(seq 1 ${NOTARY_WAIT_MINUTES:-90}); do
  if xcodebuild -exportNotarizedApp -archivePath "$ARCHIVE" -exportPath "$EXPORT" >/dev/null 2>&1; then
    break
  fi
  sleep 60
done
APP="$EXPORT/Elsewhere.app"
[[ -d "$APP" ]] || { echo "公证还没完成或失败了，稍后再运行：xcodebuild -exportNotarizedApp -archivePath $ARCHIVE -exportPath $EXPORT"; exit 1; }

echo "▸ 检查"
codesign --verify --deep --strict "$APP"
codesign -dv "$APP/Contents/Helpers/elsewhere-helper" 2>&1 | grep -E "Authority=Developer ID Application|flags=.*runtime" \
  || { echo "内置组件没有用 Developer ID 和强化运行时签名"; exit 1; }
spctl --assess --type execute -v "$APP"
xcrun stapler validate "$APP"

VERSION=$(defaults read "$PWD/$APP/Contents/Info.plist" CFBundleShortVersionString)
ZIP="build/Elsewhere-$VERSION.zip"
rm -f "$ZIP"
ditto -c -k --keepParent "$APP" "$ZIP"
echo "已生成：$ZIP"
