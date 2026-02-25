# Snow Draw Engine (`snow_draw_core`)

Pure Dart drawing engine and domain package for Snow Draw.

Use `package:snow_draw_core/snow_draw_engine.dart` as the primary public
entrypoint (`snow_draw_core.dart` is kept as a legacy alias).

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
