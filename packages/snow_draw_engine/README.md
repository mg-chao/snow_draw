# Snow Draw Engine (`snow_draw_engine`)

Backend-agnostic drawing engine package for Snow Draw.

Use `package:snow_draw_engine/snow_draw_engine.dart` as the public
entrypoint.

## Rust Rewrite Status

This package now includes a Rust engine workspace in
`packages/snow_draw_engine/rust` and a Dart FFI bridge API:

- `RustCanvasEngine.create(...)`
- `dispatch(...)` / `dispatchBatch(...)`
- `getSnapshotBytes()`
- `buildFramePlanBytes(...)`
- `pollEventBytes()`
- `dispose()`

The current migration mode is strangler-style: existing Dart engine APIs remain
available while Rust ABI integration is introduced incrementally.

## Responsibilities

- Element/domain models and JSON compatibility contracts.
- Actions, reducers, state store, undo/redo history.
- Input/edit pipelines and geometry/hit-testing logic.
- Engine-owned frame render planning and render-task generation.

## Purity Boundary

The engine must not depend on `package:flutter` or `dart:ui`.

- Colors use `DrawColor` (`argb32` storage) instead of Flutter `Color`.
- Geometry uses engine value types (`DrawPoint`, `DrawRect`, etc.).
- Text measurement is abstracted behind `TextMetricsService`.

## Integration Contract

Backends should consume the engine via `DrawContext` and
`DefaultElementRegistry`, then execute frame plans emitted by engine task
encoders and `FrameRenderPlanBuilder`.

Purity and dependency constraints are validated by workspace guard scripts.

## Rust ABI Artifacts

- C header: `packages/snow_draw_engine/include/snow_draw_engine.h`
- protobuf contract file: `packages/snow_draw_engine/rust/proto/engine.proto`
- Rust workspace: `packages/snow_draw_engine/rust`
