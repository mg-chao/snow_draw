# Snow Draw Core

Pure Dart drawing engine and domain package for Snow Draw.

## Responsibilities

- Element/domain models and JSON compatibility contracts.
- Actions, reducers, state store, undo/redo history.
- Input/edit pipelines and geometry/hit-testing logic.
- Core-owned frame render planning and render-task generation.

## Purity Boundary

Core must not depend on `package:flutter` or `dart:ui`.

- Colors use `DrawColor` (`argb32` storage) instead of Flutter `Color`.
- Geometry uses core value types (`DrawPoint`, `DrawRect`, etc.).
- Text measurement is abstracted behind `TextMetricsService`.

## Integration Contract

Backends should consume core via `DrawContext` and `ElementRegistry`, then
execute frame plans emitted by core task encoders and `FrameRenderPlanBuilder`.

Purity and dependency constraints are validated by workspace guard scripts.
