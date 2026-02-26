# Parity Corpus

This folder stores deterministic interaction traces for Rust engine parity
gates.

## Format

- One case per JSON file in `parity/corpus/`.
- `commands` are replayed in order against a fresh engine.
- `expected` contains canonical outputs:
  - snapshot versions and selected IDs
  - canonical element list (`id`, `element_type`, `z_index`)
  - frame task kind sequence
  - emitted event kind sequence

The corpus is validated by:

- `cargo test --manifest-path crates/engine_core/Cargo.toml --test parity_corpus`

## Notes

- Canonical ordering is deterministic: z-index then element ID.
- All enum names in corpus files use lower_snake_case.
- Payload bytes can be provided as `payload_hex` without separators.
