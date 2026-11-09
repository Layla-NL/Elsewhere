#!/bin/bash
# Xcode 构建阶段：用 cargo 编译内置组件 elsewhere-helper，放进 Contents/Helpers 并签名。
set -euo pipefail
export PATH="$HOME/.cargo/bin:/opt/homebrew/bin:/usr/local/bin:$PATH"

if ! command -v cargo >/dev/null; then
  echo "error: 需要 Rust 才能编译内置组件。安装：brew install rust（或 https://rustup.rs）"
  exit 1
fi

cd "$SRCROOT/helper"
cargo build --release --locked --quiet

DEST="$TARGET_BUILD_DIR/$CONTENTS_FOLDER_PATH/Helpers"
mkdir -p "$DEST"
# 没变就不动，免得破坏 App 已有的签名。
if [[ -f "$TARGET_TEMP_DIR/elsewhere-helper.source" ]] && cmp -s target/release/elsewhere-helper "$TARGET_TEMP_DIR/elsewhere-helper.source" && [[ -f "$DEST/elsewhere-helper" ]]; then
  exit 0
fi
cp -f target/release/elsewhere-helper "$DEST/elsewhere-helper"

IDENTITY="${EXPANDED_CODE_SIGN_IDENTITY:-}"
if [[ -z "$IDENTITY" || "$IDENTITY" == "-" ]]; then
  codesign --force --sign - "$DEST/elsewhere-helper"
else
  # 公证要求强化运行时和时间戳。
  codesign --force --options runtime --timestamp --sign "$IDENTITY" "$DEST/elsewhere-helper"
fi
cp -f target/release/elsewhere-helper "$TARGET_TEMP_DIR/elsewhere-helper.source"
