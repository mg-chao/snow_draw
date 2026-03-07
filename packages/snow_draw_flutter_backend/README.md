# Snow Draw Flutter Backend

Flutter rendering backend and canvas UI layer for Snow Draw.

## Responsibilities

- Single-canvas `CustomPainter` scene rendering and compositing.
- Render task execution for engine-generated frame plans/tasks.
- Flutter text layout and rendering caches.
- Shader-based effects and backend-specific visual caches.
- `createFlutterDrawContext` bootstrap helper for app/backend wiring.

## Dependency Direction

- Depends on: `snow_draw_engine` (engine package).
- Used by: `apps/snow_draw`.

App code should import this package through
`package:snow_draw_flutter_backend/snow_draw_flutter_backend.dart`.

## Notes

Legacy renderer namespaces are removed. New backend render behavior must route
through engine task plans and backend task executors.
