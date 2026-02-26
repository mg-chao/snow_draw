# Parity V2 Corpus

Deterministic traces for the Engine V2 input/output protocol.

- One case per JSON file in `parity_v2/corpus/`.
- Commands are expressed as high-level actions and wrapped into `EngineInput.command_event`.
- Expected section validates final snapshot and canonical output payload sequence.
