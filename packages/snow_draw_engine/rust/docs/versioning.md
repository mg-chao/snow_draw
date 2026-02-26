# Engine ABI Versioning Policy

## SemVer layers

- Rust crate versions follow semantic versioning.
- C ABI compatibility is governed by `sd_engine_abi_version()`.
- Protobuf message schema compatibility is governed by `schema_version` fields.

## Compatibility rules

- Backward-compatible C ABI changes (additive functions/flags) do **not** bump
  `sd_engine_abi_version`.
- Removing/changing function signatures, struct layouts, ownership rules, or
  status code semantics **must** bump `sd_engine_abi_version`.
- Adding protobuf fields with new tags is backward compatible.
- Reusing/removing protobuf tags or changing wire types is a breaking change.

## Release gates

- Every release must build `engine_capi` on Linux/macOS/Windows.
- `cargo test` for the Rust workspace must pass.
- ABI header (`include/snow_draw_engine.h`) must match exported symbols.
