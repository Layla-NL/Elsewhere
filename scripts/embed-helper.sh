#!/bin/bash
# Xcode 构建阶段：用 cargo 编译内置组件 elsewhere-helper（按 $ARCHS 合成通用版），
# 放进 Contents/Helpers 并签名。
set -euo pipefail
export PATH="$HOME/.cargo/bin:/opt/homebrew/opt/rustup/bin:/opt/homebrew/bin:/usr/local/bin:$PATH"

if ! command -v cargo >/dev/null; then
  echo "error: 需要 Rust 才能编译内置组件。安装：brew install rustup && rustup default stable（或 https://rustup.rs）"
  exit 1
fi

cd "$SRCROOT/helper"

OUT="$TARGET_TEMP_DIR/elsewhere-helper"
SLICES=()
for arch in ${ARCHS:-$(uname -m)}; do
  case "$arch" in
    arm64) triple=aarch64-apple-darwin ;;
    x86_64) triple=x86_64-apple-darwin ;;
    *) echo "error: 不支持的架构 $arch"; exit 1 ;;
  esac
  if command -v rustup >/dev/null && ! rustup target list --installed | grep -qx "$triple"; then
    echo "error: 缺少 Rust 目标 $triple。运行：rustup target add $triple"
    exit 1
  fi
  cargo build --release --locked --quiet --target "$triple"
  SLICES+=("target/$triple/release/elsewhere-helper")
done
mkdir -p "$TARGET_TEMP_DIR"
lipo -create "${SLICES[@]}" -output "$OUT"

DEST="$TARGET_BUILD_DIR/$CONTENTS_FOLDER_PATH/Helpers"
mkdir -p "$DEST"
# 没变就不动，免得破坏 App 已有的签名。
if [[ -f "$OUT.source" && -f "$DEST/elsewhere-helper" ]] && cmp -s "$OUT" "$OUT.source"; then
  exit 0
fi
cp -f "$OUT" "$DEST/elsewhere-helper"

IDENTITY="${EXPANDED_CODE_SIGN_IDENTITY:-}"
if [[ -z "$IDENTITY" || "$IDENTITY" == "-" ]]; then
  codesign --force --sign - "$DEST/elsewhere-helper"
else
  # 公证要求强化运行时和时间戳。
  codesign --force --options runtime --timestamp --sign "$IDENTITY" "$DEST/elsewhere-helper"
fi
cp -f "$OUT" "$OUT.source"
