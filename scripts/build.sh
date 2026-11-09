#!/bin/bash
# 编译 Release 版：scripts/build.sh
# 编译并安装到 /Applications：scripts/build.sh --install
set -euo pipefail
cd "$(dirname "$0")/.."

xcodebuild -project Elsewhere.xcodeproj -scheme Elsewhere -configuration Release -destination 'generic/platform=macOS' \
  -derivedDataPath build -quiet build

APP="build/Build/Products/Release/Elsewhere.app"
echo "已编译：$APP"

if [[ "${1:-}" == "--install" ]]; then
  pkill -x Elsewhere 2>/dev/null || true
  rm -rf /Applications/Elsewhere.app
  cp -R "$APP" /Applications/
  echo "已安装到 /Applications/Elsewhere.app"
  open /Applications/Elsewhere.app
fi
