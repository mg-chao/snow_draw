#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../../.." && pwd)"
PROTO_DIR="$ROOT_DIR/packages/snow_draw_engine/rust/proto"
OUT_DIR="$ROOT_DIR/packages/snow_draw_engine/lib/src/proto"
TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT

if ! command -v protoc >/dev/null 2>&1; then
  echo "error: protoc is required" >&2
  exit 1
fi

if [[ ! -x "$HOME/.pub-cache/bin/protoc-gen-dart" ]]; then
  echo "error: protoc-gen-dart not found at $HOME/.pub-cache/bin/protoc-gen-dart" >&2
  echo "hint: dart pub global activate protoc_plugin" >&2
  exit 1
fi

mkdir -p "$TMP_DIR/proto"
protoc \
  -I="$PROTO_DIR" \
  --plugin="protoc-gen-dart=$HOME/.pub-cache/bin/protoc-gen-dart" \
  --dart_out="$TMP_DIR/proto" \
  "$PROTO_DIR/engine.proto" \
  "$PROTO_DIR/engine_v2.proto"

status=0
for file in engine.pb.dart engine.pbenum.dart engine.pbjson.dart engine_v2.pb.dart engine_v2.pbenum.dart engine_v2.pbjson.dart; do
  if ! diff -u "$OUT_DIR/$file" "$TMP_DIR/proto/$file" >/dev/null; then
    echo "drift detected: $file" >&2
    status=1
  fi
done

if [[ $status -ne 0 ]]; then
  echo "proto codegen drift detected. Run: bash packages/snow_draw_engine/rust/scripts/generate_proto_dart.sh" >&2
  exit $status
fi

echo "proto codegen is up-to-date"
