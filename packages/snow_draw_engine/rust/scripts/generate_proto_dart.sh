#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../../.." && pwd)"
PROTO_DIR="$ROOT_DIR/packages/snow_draw_engine/rust/proto"
OUT_DIR="$ROOT_DIR/packages/snow_draw_engine/lib/src/proto"

if ! command -v protoc >/dev/null 2>&1; then
  echo "error: protoc is required" >&2
  exit 1
fi

if [[ ! -x "$HOME/.pub-cache/bin/protoc-gen-dart" ]]; then
  echo "error: protoc-gen-dart not found at $HOME/.pub-cache/bin/protoc-gen-dart" >&2
  echo "hint: dart pub global activate protoc_plugin" >&2
  exit 1
fi

mkdir -p "$OUT_DIR"
protoc \
  -I="$PROTO_DIR" \
  --plugin="protoc-gen-dart=$HOME/.pub-cache/bin/protoc-gen-dart" \
  --dart_out="$OUT_DIR" \
  "$PROTO_DIR/engine.proto" \
  "$PROTO_DIR/engine_v2.proto"

echo "Generated Dart protobuf bindings in $OUT_DIR"
