# Snow Draw Flutter Backend

Flutter rendering backend and canvas UI layer for Snow Draw.

## Responsibilities

- `CustomPainter` canvas rendering and layer composition.
- Scene primitive execution for core-generated render scenes.
- Flutter text layout and rendering caches.
- Shader-based effects and backend-specific visual caches.
- Visual metadata (`ElementVisualDefinition`) such as tool icons.

## Dependency Direction

- Depends on: `snow_draw_core`.
- Used by: `apps/snow_draw`.

App code should import this package through
`package:snow_draw_flutter_backend/snow_draw_flutter_backend.dart`.

## Notes

Legacy namespace files under `lib/render/legacy/` are compatibility shims only.
Architecture guard scripts enforce shim-only behavior.
