# Snow Draw Rust Engine Workspace

This workspace contains the Rust rewrite foundation for `snow_draw_engine`.

## Crates

- `engine_proto`: protobuf message contracts shared by all Rust targets.
- `engine_proto_v2`: generated protobuf contracts for the V2 protocol boundary.
- `engine_core`: headless deterministic canvas engine core (state, commands, frame plans, events).
- `engine_capi`: stable C ABI (`cdylib` + `staticlib`) for host integration.
- `engine_wasm`: wasm adapter for future web embedding.
- `engine_bench`: criterion benchmarks for command dispatch performance.

## ABI Header

C consumers should include:

- `include/snow_draw_engine.h`
- `docs/abi.md` for status codes and ownership rules
- `docs/versioning.md` for ABI/schema compatibility guarantees
- `docs/rewrite_matrix.md` for command/frame-task parity coverage status

## Desktop Build Scripts

- macOS/Linux: `rust/scripts/build_desktop.sh`
- Windows (PowerShell): `rust/scripts/build_desktop.ps1`

## Build

```bash
cd packages/snow_draw_engine/rust
cargo test
cargo build -p engine_capi --release
```

## Parity Corpus

- Corpus cases: `rust/parity/corpus/*.json`
- Harness test: `cargo test -p engine_core --test parity_corpus`
- V2 corpus: `rust/parity_v2/corpus/*.json`
- V2 harness test: `cargo test -p engine_core --test parity_v2_corpus`

## Proto Codegen

- Generate Dart bindings:
  `bash packages/snow_draw_engine/rust/scripts/generate_proto_dart.sh`
- Verify drift in CI/local:
  `bash packages/snow_draw_engine/rust/scripts/check_proto_codegen_drift.sh`

The generated dynamic library target names are platform dependent:

- macOS: `libsnow_draw_engine_capi.dylib`
- Linux/Android: `libsnow_draw_engine_capi.so`
- Windows: `snow_draw_engine_capi.dll`

## Contract Notes

- Payload transport uses protobuf bytes over `sd_bytes_t`.
- Event delivery is pull-based via `sd_engine_poll_event`.
- `sd_bytes_free` must be used for every non-empty buffer returned by the ABI.
