#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TARGET_DIR="$ROOT_DIR/target/release"
OUTPUT_DIR="$ROOT_DIR/../native"

cargo build --manifest-path "$ROOT_DIR/Cargo.toml" -p engine_capi --release

mkdir -p "$OUTPUT_DIR/linux-x64" "$OUTPUT_DIR/macos-arm64"

if [[ -f "$TARGET_DIR/libsnow_draw_engine_capi.so" ]]; then
  cp "$TARGET_DIR/libsnow_draw_engine_capi.so" "$OUTPUT_DIR/linux-x64/"
fi

if [[ -f "$TARGET_DIR/libsnow_draw_engine_capi.dylib" ]]; then
  cp "$TARGET_DIR/libsnow_draw_engine_capi.dylib" "$OUTPUT_DIR/macos-arm64/"
fi

if [[ -f "$TARGET_DIR/libsnow_draw_engine_capi.a" ]]; then
  cp "$TARGET_DIR/libsnow_draw_engine_capi.a" "$OUTPUT_DIR/linux-x64/"
  cp "$TARGET_DIR/libsnow_draw_engine_capi.a" "$OUTPUT_DIR/macos-arm64/"
fi

cp "$ROOT_DIR/include/snow_draw_engine.h" "$OUTPUT_DIR/"

echo "Rust desktop ABI artifacts copied to: $OUTPUT_DIR"
