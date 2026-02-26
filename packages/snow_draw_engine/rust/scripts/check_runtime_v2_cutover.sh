#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../../.." && pwd)"
PLUGIN_CANVAS="$ROOT_DIR/packages/snow_draw_flutter_backend/lib/ui/canvas/plugin_draw_canvas.dart"
APP_MAIN="$ROOT_DIR/apps/snow_draw/lib/main.dart"
STORE_FACTORY="$ROOT_DIR/packages/snow_draw_engine/lib/draw/store/draw_store_factory.dart"

search() {
  local pattern="$1"
  local file="$2"
  if command -v rg >/dev/null 2>&1; then
    rg -n "$pattern" "$file" >/dev/null
  else
    grep -nE "$pattern" "$file" >/dev/null
  fi
}

count_matches() {
  local pattern="$1"
  local file="$2"
  if command -v rg >/dev/null 2>&1; then
    rg -n "$pattern" "$file" | wc -l | tr -d '[:space:]'
  else
    grep -nE "$pattern" "$file" | wc -l | tr -d '[:space:]'
  fi
}

first_line() {
  local pattern="$1"
  local file="$2"
  if command -v rg >/dev/null 2>&1; then
    rg -n "$pattern" "$file" | head -n 1 | cut -d: -f1
  else
    grep -nE "$pattern" "$file" | head -n 1 | cut -d: -f1
  fi
}

if search "DefaultDrawStore" "$APP_MAIN"; then
  echo "legacy runtime reference detected in app main: DefaultDrawStore" >&2
  exit 1
fi

if ! search "if \(widget\.store case final RustDrawStore rustStore\)" "$PLUGIN_CANVAS"; then
  echo "missing RustDrawStore runtime guard in plugin_draw_canvas" >&2
  exit 1
fi

if ! search "return rustStore\.latestFramePlan;" "$PLUGIN_CANVAS"; then
  echo "runtime frame plan is not sourced from RustDrawStore" >&2
  exit 1
fi

if search "_frameRenderPlanBuilder\.build\(" "$PLUGIN_CANVAS"; then
  echo "legacy FrameRenderPlanBuilder runtime call detected" >&2
  exit 1
fi

if search "FrameRenderPlanBuilder\(\)\.build\(" "$PLUGIN_CANVAS"; then
  echo "inline FrameRenderPlanBuilder runtime call detected" >&2
  exit 1
fi

legacy_fallback_count="$(count_matches "return _legacyFrameRenderPlanBuilder\.build\(" "$PLUGIN_CANVAS")"
if [[ "$legacy_fallback_count" -ne 1 ]]; then
  echo "unexpected plugin_draw_canvas fallback shape: expected exactly one legacy frame-plan fallback return" >&2
  exit 1
fi

rust_return_line="$(first_line "return rustStore\.latestFramePlan;" "$PLUGIN_CANVAS")"
legacy_return_line="$(first_line "return _legacyFrameRenderPlanBuilder\.build\(" "$PLUGIN_CANVAS")"
if [[ -z "$rust_return_line" || -z "$legacy_return_line" || "$rust_return_line" -ge "$legacy_return_line" ]]; then
  echo "plugin_draw_canvas frame-plan guard ordering is invalid (Rust return must appear before legacy fallback return)" >&2
  exit 1
fi

if ! search "DrawStoreBackend\.rust" "$STORE_FACTORY"; then
  echo "draw_store_factory is missing Rust backend enforcement" >&2
  exit 1
fi

echo "runtime V2 cutover guard checks passed"
