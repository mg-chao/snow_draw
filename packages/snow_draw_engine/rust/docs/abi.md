# Snow Draw Engine C ABI

## Versioning

- `sd_engine_abi_version()` currently returns `2`.
- Capability flags are returned by `sd_engine_capabilities()`.

## Ownership

- Any non-empty `sd_bytes_t` returned by the ABI must be released with
  `sd_bytes_free(...)`.
- `sd_engine_t*` handles are released with `sd_engine_destroy(...)`.

## Status Codes

- `SD_STATUS_OK = 0`
- `SD_STATUS_NO_EVENT = 1`
- `SD_STATUS_NULL_POINTER = 2`
- `SD_STATUS_DECODE_ERROR = 3`
- `SD_STATUS_ENGINE_ERROR = 4`
- `SD_STATUS_PANIC = 255`

## Functions

- `sd_engine_create`
- `sd_engine_v2_create`
- `sd_engine_destroy`
- `sd_engine_dispatch`
- `sd_engine_dispatch_batch`
- `sd_engine_get_snapshot`
- `sd_engine_build_frame_plan`
- `sd_engine_poll_event`
- `sd_engine_v2_process_input`
- `sd_engine_v2_poll_output`
- `sd_bytes_free`
- `sd_engine_abi_version`
- `sd_engine_capabilities`
