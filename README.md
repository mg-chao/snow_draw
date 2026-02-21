# Snow Draw

Snow Draw is a whiteboard application focused on fast interaction,
predictable editing behavior, and backend-agnostic rendering architecture.

## About

The workspace is organized so drawing domain logic is independent from
Flutter rendering details. This keeps the core portable and allows adding
new rendering backends without rewriting reducers, element models, history,
or input behavior.

## Try It Online

- [Launch Snow Draw Web App](https://mg-chao.github.io/snow_draw/)

## Workspace Architecture

- `packages/snow_draw_core`: pure Dart engine (state/actions/reducers,
  geometry, scene contracts, serialization).
- `packages/snow_draw_flutter_backend`: Flutter backend (painters,
  scene primitive renderer, text/shader caches, canvas widgets).
- `apps/snow_draw`: app composition layer (toolbars, adapters,
  `DefaultDrawStore`, `ToolController`).

## Rendering Architecture

Rendering follows an explicit engine/backend split:

1. Core compiles document state into backend-agnostic scene primitives.
2. Backend renders those primitives with platform APIs.
3. App imports backend via package entrypoints only.

This mirrors modern draw-list pipelines (similar in spirit to egui/iced):
core owns intent and geometry, backend owns paint execution.

## Architecture Guards

Boundary checks are enforced with Melos scripts:

- `dart run melos run check:core-purity`
- `dart run melos run check:backend-legacy`
- `dart run melos run check:backend-entrypoint`
- `dart run melos run check:ci-workflow`
- `dart run melos run check:app-backend-import-boundary`
- `dart run melos run check:architecture`
- `dart run melos run check:compatibility-contracts`

`check:compatibility-contracts` runs focused schema/type/visual compatibility
tests to protect persisted data and backend binding contracts.

See `docs/architecture/render_backend_split.md` for detailed contracts and
extension guidance.
