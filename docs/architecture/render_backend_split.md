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
  - Prefer importing shared core APIs via `package:snow_draw_core/snow_draw_core.dart`.

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
- No `package:flutter` or `dart:ui` imports under `lib/draw`.
- Core package entrypoint (`lib/snow_draw_core.dart`) exports pure-Dart APIs
  only.
- No reachable Flutter SDK packages in the core dependency graph.
- No reachable backend/app workspace packages in the core dependency graph.
- No shader/material declarations in core package metadata.

### App/backend import discipline

- App imports/exports backend APIs only through
  `package:snow_draw_flutter_backend/snow_draw_flutter_backend.dart`.
- Deep backend path imports from app are disallowed by guard scripts.
- For core APIs, prefer `package:snow_draw_core/snow_draw_core.dart` over
  deep package paths when the entrypoint exposes the needed symbols.
- App deep core path imports are disallowed by guard scripts in both
  `apps/snow_draw/lib` and `apps/snow_draw/test`.

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
- `check:core-draw-purity`
- `check:core-ui-boundary`
- `check:core-entrypoint`
- `check:backend-legacy`
- `check:backend-app-import-boundary`
- `check:backend-pubspec-boundary`
- `check:backend-dependency-graph`
- `check:backend-entrypoint`
- `check:ci-workflow`
- `check:app-backend-import-boundary`
- `check:app-core-import-boundary`
- `check:app-pubspec-backend`
- `check:app-dependency-graph`

Run compatibility contract checks with:

```bash
dart run melos run check:compatibility-contracts
```

This verifies:

- built-in element JSON roundtrip compatibility
- built-in element default JSON snapshot compatibility
- built-in element type id token stability
- built-in core scene encoder coverage in element registry
- draw config default primitive contract stability
- action payload immutability contract for collection-backed actions
- `DrawColor` ARGB32 channel/update behavior stability
- fallback text metrics behavior and DTO invariants in pure Dart core
- `DrawContext` text metrics injection/preservation behavior
- scene encoder slice contracts for built-in elements (A-D)
- backend visual registration coverage for built-in core elements
- backend built-in icon mapping compatibility
- backend package entrypoint export contract for app boundary usage
- backend entrypoint `flutterTextMetricsService` export behavior
- backend coordinate adapter (`DrawPoint` <-> `Offset`) invertibility
- built-in scene encoder routing coverage through backend scene rendering

## Adding a New Rendering Backend

1. Create a new package (for example `snow_draw_skia_backend`).
2. Depend on `snow_draw_core` only.
3. Implement:
   - scene primitive renderer for `RenderScene`
   - `TextMetricsService` adapter
   - backend-specific visual registry and UI widgets
4. Keep app imports routed through the selected backend package entrypoint.
5. Add boundary guards equivalent to Flutter backend guard coverage.
