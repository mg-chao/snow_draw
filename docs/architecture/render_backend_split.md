# Render Backend Split

This document defines the architecture boundary between `snow_draw_core` and
rendering backends.

## Goals

- Keep engine/domain logic portable and testable in pure Dart.
- Support swappable rendering backends without changing reducers/models.
- Preserve strict compatibility for persisted schema and action contracts.

## Package Split

- `packages/snow_draw_core`
  - Domain state/actions/reducers/history/input.
  - Element definitions, creation, hit-testing, scene encoding.
  - Backend-neutral value types and service interfaces.
- `packages/snow_draw_flutter_backend`
  - Scene primitive renderer for Flutter canvas.
  - Text metrics implementation backed by Flutter paragraph/painter APIs.
  - Backend visual registry and icon metadata.
  - Canvas widgets, painters, shader/caching infrastructure.
- `apps/snow_draw`
  - Product UI composition and toolbar/store adapters.
  - Imports backend through package entrypoint only.

## Core -> Backend Contract

### Scene pipeline

- Core element definitions may provide `ElementSceneEncoder<T>`.
- Encoders emit `RenderScene` containing `RenderPrimitive` entries.
- Backend executes primitives to paint the final frame.

### Text metrics

- Core text geometry calls `TextMetricsService`.
- Backends provide concrete implementations and inject via `DrawContext`.

### Color

- Core stores colors as `DrawColor` (`argb32`).
- Backends convert to native color types at the boundary.

## Boundary Rules

### Core purity

- No `package:flutter` imports.
- No `dart:ui` imports.
- No shader/material declarations in core package metadata.

### App/backend import discipline

- App imports backend APIs only through
  `package:snow_draw_flutter_backend/snow_draw_flutter_backend.dart`.
- Deep backend path imports from app are disallowed by guard scripts.

### Legacy namespace policy

- Files in backend `lib/render/legacy/*` are re-export shims only.
- Shims must be explicitly `@Deprecated`.

## Guard Scripts

Run all architecture checks with:

```bash
dart run melos run check:architecture
```

This aggregates:

- `check:core-purity`
- `check:backend-legacy`
- `check:app-backend-import-boundary`

Run compatibility contract checks with:

```bash
dart run melos run check:compatibility-contracts
```

This verifies:

- built-in element JSON roundtrip compatibility
- built-in element type id token stability
- backend visual registration coverage for built-in core elements

## Adding a New Rendering Backend

1. Create a new package (for example `snow_draw_skia_backend`).
2. Depend on `snow_draw_core` only.
3. Implement:
   - scene primitive renderer for `RenderScene`
   - `TextMetricsService` adapter
   - backend-specific visual registry and UI widgets
4. Keep app imports routed through the selected backend package entrypoint.
5. Add boundary guards equivalent to Flutter backend guard coverage.
