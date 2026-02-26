//! C ABI for the Snow Draw Rust canvas engine.

use std::panic::{catch_unwind, AssertUnwindSafe};
use std::slice;

use engine_core::{Engine, EngineCoreError, EngineV2};
use engine_proto::{
    decode_message, default_engine_config, encode_message, EngineConfig, EngineError,
};
use engine_proto_v2::{
    decode_message as decode_message_v2, default_init_request as default_init_request_v2,
    encode_message as encode_message_v2, EngineError as EngineErrorV2, EngineInitRequest,
};

pub const SD_ENGINE_ABI_VERSION: u32 = 2;
pub const SD_CAP_EVENT_STREAM: u64 = 1 << 0;
pub const SD_CAP_FRAME_PLAN: u64 = 1 << 1;
pub const SD_CAP_DISPATCH_BATCH: u64 = 1 << 2;
pub const SD_CAP_V2_INPUT_OUTPUT: u64 = 1 << 3;
pub const SD_CAP_INPUT_PIPELINE: u64 = 1 << 4;
pub const SD_CAP_TEXT_METRICS_HOST: u64 = 1 << 5;

pub const SD_STATUS_OK: u32 = 0;
pub const SD_STATUS_NO_EVENT: u32 = 1;
pub const SD_STATUS_NULL_POINTER: u32 = 2;
pub const SD_STATUS_DECODE_ERROR: u32 = 3;
pub const SD_STATUS_ENGINE_ERROR: u32 = 4;
pub const SD_STATUS_PANIC: u32 = 255;

#[repr(C)]
#[derive(Clone, Copy, Debug, Default)]
pub struct sd_bytes_t {
    pub ptr: *mut u8,
    pub len: usize,
}

#[repr(C)]
pub struct sd_engine_t {
    _private: [u8; 0],
}

struct EngineHandle {
    engine: Engine,
    engine_v2: EngineV2,
}

#[no_mangle]
pub extern "C" fn sd_engine_abi_version() -> u32 {
    SD_ENGINE_ABI_VERSION
}

#[no_mangle]
pub extern "C" fn sd_engine_capabilities() -> u64 {
    SD_CAP_EVENT_STREAM
        | SD_CAP_FRAME_PLAN
        | SD_CAP_DISPATCH_BATCH
        | SD_CAP_V2_INPUT_OUTPUT
        | SD_CAP_INPUT_PIPELINE
        | SD_CAP_TEXT_METRICS_HOST
}

#[no_mangle]
pub unsafe extern "C" fn sd_engine_create(
    config_bytes: sd_bytes_t,
    out_status: *mut u32,
    out_error: *mut sd_bytes_t,
) -> *mut sd_engine_t {
    set_status(out_status, SD_STATUS_OK);
    clear_out_bytes(out_error);

    match catch_unwind(AssertUnwindSafe(|| {
        let config = match parse_config(config_bytes) {
            Ok(config) => config,
            Err(error) => {
                set_status(out_status, SD_STATUS_DECODE_ERROR);
                set_error(out_error, &error);
                return std::ptr::null_mut();
            }
        };

        let handle = Box::new(EngineHandle {
            engine: Engine::new(config.clone()),
            engine_v2: EngineV2::from_init_request(init_request_from_config(&config)),
        });
        Box::into_raw(handle).cast::<sd_engine_t>()
    })) {
        Ok(ptr) => ptr,
        Err(_) => {
            set_status(out_status, SD_STATUS_PANIC);
            set_panic_error(out_error, "sd_engine_create");
            std::ptr::null_mut()
        }
    }
}

#[no_mangle]
pub unsafe extern "C" fn sd_engine_v2_create(
    init_bytes: sd_bytes_t,
    out_status: *mut u32,
    out_error: *mut sd_bytes_t,
) -> *mut sd_engine_t {
    set_status(out_status, SD_STATUS_OK);
    clear_out_bytes(out_error);

    match catch_unwind(AssertUnwindSafe(|| {
        let init = match parse_init_v2(init_bytes) {
            Ok(init) => init,
            Err(error) => {
                set_status(out_status, SD_STATUS_DECODE_ERROR);
                set_error_v2(out_error, &error);
                return std::ptr::null_mut();
            }
        };

        let config = config_from_init_request(&init);
        let handle = Box::new(EngineHandle {
            engine: Engine::new(config),
            engine_v2: EngineV2::from_init_request(init),
        });
        Box::into_raw(handle).cast::<sd_engine_t>()
    })) {
        Ok(ptr) => ptr,
        Err(_) => {
            set_status(out_status, SD_STATUS_PANIC);
            set_panic_error_v2(out_error, "sd_engine_v2_create");
            std::ptr::null_mut()
        }
    }
}

#[no_mangle]
pub unsafe extern "C" fn sd_engine_destroy(engine: *mut sd_engine_t) {
    if engine.is_null() {
        return;
    }

    let _ = catch_unwind(AssertUnwindSafe(|| {
        drop(Box::from_raw(engine.cast::<EngineHandle>()));
    }));
}

#[no_mangle]
pub unsafe extern "C" fn sd_engine_dispatch(
    engine: *mut sd_engine_t,
    command_bytes: sd_bytes_t,
    out_error: *mut sd_bytes_t,
) -> u32 {
    clear_out_bytes(out_error);

    match catch_unwind(AssertUnwindSafe(|| {
        let command = as_vec(command_bytes);
        with_engine_mut(engine, |instance| instance.dispatch_bytes(&command))
    })) {
        Ok(Ok(())) => SD_STATUS_OK,
        Ok(Err(error)) => {
            set_error(out_error, &error);
            SD_STATUS_ENGINE_ERROR
        }
        Err(_) => {
            set_panic_error(out_error, "sd_engine_dispatch");
            SD_STATUS_PANIC
        }
    }
}

#[no_mangle]
pub unsafe extern "C" fn sd_engine_dispatch_batch(
    engine: *mut sd_engine_t,
    command_bytes: *const sd_bytes_t,
    command_count: usize,
    out_error: *mut sd_bytes_t,
) -> u32 {
    clear_out_bytes(out_error);

    if command_count > 0 && command_bytes.is_null() {
        set_error(
            out_error,
            &EngineCoreError::Internal("command_bytes is null".to_string()),
        );
        return SD_STATUS_NULL_POINTER;
    }

    match catch_unwind(AssertUnwindSafe(|| {
        let mut commands = Vec::with_capacity(command_count);
        if command_count > 0 {
            let items = slice::from_raw_parts(command_bytes, command_count);
            for item in items {
                commands.push(as_vec(*item));
            }
        }
        with_engine_mut(engine, |instance| instance.dispatch_batch_bytes(commands))
    })) {
        Ok(Ok(())) => SD_STATUS_OK,
        Ok(Err(error)) => {
            set_error(out_error, &error);
            SD_STATUS_ENGINE_ERROR
        }
        Err(_) => {
            set_panic_error(out_error, "sd_engine_dispatch_batch");
            SD_STATUS_PANIC
        }
    }
}

#[no_mangle]
pub unsafe extern "C" fn sd_engine_get_snapshot(
    engine: *mut sd_engine_t,
    out_snapshot: *mut sd_bytes_t,
    out_error: *mut sd_bytes_t,
) -> u32 {
    clear_out_bytes(out_snapshot);
    clear_out_bytes(out_error);

    match catch_unwind(AssertUnwindSafe(|| {
        with_engine_mut(engine, |instance| Ok(instance.get_snapshot_bytes()))
    })) {
        Ok(Ok(bytes)) => {
            write_out_bytes(out_snapshot, to_sd_bytes(bytes));
            SD_STATUS_OK
        }
        Ok(Err(error)) => {
            set_error(out_error, &error);
            SD_STATUS_ENGINE_ERROR
        }
        Err(_) => {
            set_panic_error(out_error, "sd_engine_get_snapshot");
            SD_STATUS_PANIC
        }
    }
}

#[no_mangle]
pub unsafe extern "C" fn sd_engine_build_frame_plan(
    engine: *mut sd_engine_t,
    request_bytes: sd_bytes_t,
    out_plan: *mut sd_bytes_t,
    out_error: *mut sd_bytes_t,
) -> u32 {
    clear_out_bytes(out_plan);
    clear_out_bytes(out_error);

    match catch_unwind(AssertUnwindSafe(|| {
        let request = as_vec(request_bytes);
        with_engine_mut(engine, |instance| instance.build_frame_plan_bytes(&request))
    })) {
        Ok(Ok(bytes)) => {
            write_out_bytes(out_plan, to_sd_bytes(bytes));
            SD_STATUS_OK
        }
        Ok(Err(error)) => {
            set_error(out_error, &error);
            SD_STATUS_ENGINE_ERROR
        }
        Err(_) => {
            set_panic_error(out_error, "sd_engine_build_frame_plan");
            SD_STATUS_PANIC
        }
    }
}

#[no_mangle]
pub unsafe extern "C" fn sd_engine_poll_event(
    engine: *mut sd_engine_t,
    out_event: *mut sd_bytes_t,
    out_error: *mut sd_bytes_t,
) -> u32 {
    clear_out_bytes(out_event);
    clear_out_bytes(out_error);

    match catch_unwind(AssertUnwindSafe(|| {
        with_engine_mut(engine, |instance| Ok(instance.poll_event_bytes()))
    })) {
        Ok(Ok(Some(bytes))) => {
            write_out_bytes(out_event, to_sd_bytes(bytes));
            SD_STATUS_OK
        }
        Ok(Ok(None)) => SD_STATUS_NO_EVENT,
        Ok(Err(error)) => {
            set_error(out_error, &error);
            SD_STATUS_ENGINE_ERROR
        }
        Err(_) => {
            set_panic_error(out_error, "sd_engine_poll_event");
            SD_STATUS_PANIC
        }
    }
}

#[no_mangle]
pub unsafe extern "C" fn sd_engine_v2_process_input(
    engine: *mut sd_engine_t,
    input_bytes: sd_bytes_t,
    out_error: *mut sd_bytes_t,
) -> u32 {
    clear_out_bytes(out_error);

    match catch_unwind(AssertUnwindSafe(|| {
        let input = as_vec(input_bytes);
        with_engine_v2_mut(engine, |instance| instance.process_input_bytes(&input))
    })) {
        Ok(Ok(())) => SD_STATUS_OK,
        Ok(Err(error)) => {
            set_error_v2(out_error, &error);
            SD_STATUS_ENGINE_ERROR
        }
        Err(_) => {
            set_panic_error_v2(out_error, "sd_engine_v2_process_input");
            SD_STATUS_PANIC
        }
    }
}

#[no_mangle]
pub unsafe extern "C" fn sd_engine_v2_poll_output(
    engine: *mut sd_engine_t,
    out_output: *mut sd_bytes_t,
    out_error: *mut sd_bytes_t,
) -> u32 {
    clear_out_bytes(out_output);
    clear_out_bytes(out_error);

    match catch_unwind(AssertUnwindSafe(|| {
        with_engine_v2_mut(engine, |instance| Ok(instance.poll_output_bytes()))
    })) {
        Ok(Ok(Some(bytes))) => {
            write_out_bytes(out_output, to_sd_bytes(bytes));
            SD_STATUS_OK
        }
        Ok(Ok(None)) => SD_STATUS_NO_EVENT,
        Ok(Err(error)) => {
            set_error_v2(out_error, &error);
            SD_STATUS_ENGINE_ERROR
        }
        Err(_) => {
            set_panic_error_v2(out_error, "sd_engine_v2_poll_output");
            SD_STATUS_PANIC
        }
    }
}

#[no_mangle]
pub unsafe extern "C" fn sd_bytes_free(bytes: sd_bytes_t) {
    if bytes.ptr.is_null() {
        return;
    }

    let _ = catch_unwind(AssertUnwindSafe(|| {
        drop(Vec::from_raw_parts(bytes.ptr, bytes.len, bytes.len));
    }));
}

unsafe fn with_engine_mut<T>(
    engine: *mut sd_engine_t,
    f: impl FnOnce(&mut Engine) -> Result<T, EngineCoreError>,
) -> Result<T, EngineCoreError> {
    if engine.is_null() {
        return Err(EngineCoreError::Internal(
            "engine handle is null".to_string(),
        ));
    }

    let handle = &mut *engine.cast::<EngineHandle>();
    f(&mut handle.engine)
}

unsafe fn with_engine_v2_mut<T>(
    engine: *mut sd_engine_t,
    f: impl FnOnce(&mut EngineV2) -> Result<T, EngineCoreError>,
) -> Result<T, EngineCoreError> {
    if engine.is_null() {
        return Err(EngineCoreError::Internal(
            "engine handle is null".to_string(),
        ));
    }

    let handle = &mut *engine.cast::<EngineHandle>();
    f(&mut handle.engine_v2)
}

unsafe fn parse_config(bytes: sd_bytes_t) -> Result<EngineConfig, EngineCoreError> {
    if bytes.ptr.is_null() || bytes.len == 0 {
        return Ok(default_engine_config());
    }

    let config_bytes = as_vec(bytes);
    decode_message(&config_bytes).map_err(|error| EngineCoreError::Decode(error.to_string()))
}

unsafe fn parse_init_v2(bytes: sd_bytes_t) -> Result<EngineInitRequest, EngineCoreError> {
    if bytes.ptr.is_null() || bytes.len == 0 {
        return Ok(default_init_request_v2());
    }

    let init_bytes = as_vec(bytes);
    decode_message_v2(&init_bytes).map_err(|error| EngineCoreError::Decode(error.to_string()))
}

fn init_request_from_config(config: &EngineConfig) -> EngineInitRequest {
    EngineInitRequest {
        requested_abi_version: SD_ENGINE_ABI_VERSION,
        schema_version: config.schema_version,
        locale_tag: config.locale_tag.clone(),
        scale_factor: config.scale_factor,
        requested_capabilities_mask: config.requested_capabilities,
        deterministic_seed: config.deterministic_seed,
    }
}

fn config_from_init_request(init: &EngineInitRequest) -> EngineConfig {
    let mut config = default_engine_config();
    if init.schema_version > 0 {
        config.schema_version = init.schema_version;
    }
    if !init.locale_tag.trim().is_empty() {
        config.locale_tag = init.locale_tag.clone();
    }
    if init.scale_factor.is_finite() && init.scale_factor > 0.0 {
        config.scale_factor = init.scale_factor;
    }
    config.requested_capabilities = init.requested_capabilities_mask;
    config.deterministic_seed = init.deterministic_seed;
    config
}

unsafe fn set_status(ptr: *mut u32, status: u32) {
    if !ptr.is_null() {
        *ptr = status;
    }
}

unsafe fn as_vec(bytes: sd_bytes_t) -> Vec<u8> {
    if bytes.ptr.is_null() || bytes.len == 0 {
        return Vec::new();
    }
    slice::from_raw_parts(bytes.ptr.cast_const(), bytes.len).to_vec()
}

fn to_sd_bytes(mut bytes: Vec<u8>) -> sd_bytes_t {
    if bytes.is_empty() {
        return sd_bytes_t::default();
    }

    bytes.shrink_to_fit();
    let len = bytes.len();
    let ptr = bytes.as_mut_ptr();
    std::mem::forget(bytes);
    sd_bytes_t { ptr, len }
}

unsafe fn write_out_bytes(out: *mut sd_bytes_t, value: sd_bytes_t) {
    if out.is_null() {
        return;
    }
    *out = value;
}

unsafe fn clear_out_bytes(out: *mut sd_bytes_t) {
    if out.is_null() {
        return;
    }
    *out = sd_bytes_t::default();
}

unsafe fn set_error(out_error: *mut sd_bytes_t, error: &EngineCoreError) {
    if out_error.is_null() {
        return;
    }
    let message = error.to_proto();
    *out_error = to_sd_bytes(encode_message(&message));
}

unsafe fn set_error_v2(out_error: *mut sd_bytes_t, error: &EngineCoreError) {
    if out_error.is_null() {
        return;
    }
    let message = EngineErrorV2 {
        code: error.code(),
        message: error.to_string(),
        details: format!("{error:?}"),
    };
    *out_error = to_sd_bytes(encode_message_v2(&message));
}

unsafe fn set_panic_error(out_error: *mut sd_bytes_t, operation: &str) {
    if out_error.is_null() {
        return;
    }

    let message = EngineError {
        code: 9000,
        message: format!("panic caught in {operation}"),
        details: operation.to_string(),
    };
    *out_error = to_sd_bytes(encode_message(&message));
}

unsafe fn set_panic_error_v2(out_error: *mut sd_bytes_t, operation: &str) {
    if out_error.is_null() {
        return;
    }

    let message = EngineErrorV2 {
        code: 9000,
        message: format!("panic caught in {operation}"),
        details: operation.to_string(),
    };
    *out_error = to_sd_bytes(encode_message_v2(&message));
}

#[cfg(test)]
mod tests {
    use super::*;
    use engine_proto::engine_command::Payload as CommandPayload;
    use engine_proto::{
        decode_message, encode_message, CreateElementCommand, DrawPoint, ElementType,
        EngineCommand, EngineCommandKind, EngineError, EngineSnapshot,
    };
    use engine_proto_v2::engine_input::Payload as V2InputPayload;
    use engine_proto_v2::engine_output::Payload as V2OutputPayload;
    use engine_proto_v2::{
        decode_message as decode_message_v2, default_init_request,
        encode_message as encode_message_v2, CommandEvent, EngineInput, EngineOutput,
        EngineSnapshot as EngineSnapshotV2,
    };

    fn as_input_bytes(bytes: &mut Vec<u8>) -> sd_bytes_t {
        if bytes.is_empty() {
            return sd_bytes_t::default();
        }
        sd_bytes_t {
            ptr: bytes.as_mut_ptr(),
            len: bytes.len(),
        }
    }

    unsafe fn copy_and_free(bytes: sd_bytes_t) -> Vec<u8> {
        if bytes.ptr.is_null() || bytes.len == 0 {
            return Vec::new();
        }
        let copied = std::slice::from_raw_parts(bytes.ptr.cast_const(), bytes.len).to_vec();
        sd_bytes_free(bytes);
        copied
    }

    unsafe fn create_engine() -> *mut sd_engine_t {
        let mut status = 0u32;
        let mut error = sd_bytes_t::default();
        let handle = sd_engine_create(sd_bytes_t::default(), &mut status, &mut error);
        assert_eq!(status, SD_STATUS_OK);
        assert!(!handle.is_null());
        assert!(copy_and_free(error).is_empty());
        handle
    }

    unsafe fn create_engine_v2() -> *mut sd_engine_t {
        let mut status = 0u32;
        let mut error = sd_bytes_t::default();
        let mut init = encode_message_v2(&default_init_request());
        let handle = sd_engine_v2_create(as_input_bytes(&mut init), &mut status, &mut error);
        assert_eq!(status, SD_STATUS_OK);
        assert!(!handle.is_null());
        assert!(copy_and_free(error).is_empty());
        handle
    }

    #[test]
    fn abi_surface_is_exposed() {
        assert_eq!(sd_engine_abi_version(), SD_ENGINE_ABI_VERSION);
        let caps = sd_engine_capabilities();
        assert_ne!(caps & SD_CAP_EVENT_STREAM, 0);
        assert_ne!(caps & SD_CAP_FRAME_PLAN, 0);
        assert_ne!(caps & SD_CAP_DISPATCH_BATCH, 0);
        assert_ne!(caps & SD_CAP_V2_INPUT_OUTPUT, 0);
        assert_ne!(caps & SD_CAP_INPUT_PIPELINE, 0);
        assert_ne!(caps & SD_CAP_TEXT_METRICS_HOST, 0);
    }

    #[test]
    fn v2_replay_smoke_trace() {
        unsafe {
            let engine = create_engine_v2();

            let mut init_output = sd_bytes_t::default();
            let mut init_error = sd_bytes_t::default();
            let init_status = sd_engine_v2_poll_output(engine, &mut init_output, &mut init_error);
            assert_eq!(init_status, SD_STATUS_OK);
            assert!(copy_and_free(init_error).is_empty());
            let decoded_init: EngineOutput =
                decode_message_v2(&copy_and_free(init_output)).expect("decode init output");
            assert!(matches!(
                decoded_init.payload,
                Some(V2OutputPayload::InitAck(_))
            ));

            let command = EngineCommand {
                kind: EngineCommandKind::CreateElement as i32,
                payload: Some(CommandPayload::CreateElement(CreateElementCommand {
                    element_type: ElementType::Rectangle as i32,
                    element_id: "ffi-v2".to_string(),
                    position: Some(DrawPoint {
                        x: 32.0,
                        y: 48.0,
                        pressure: 0.0,
                        timestamp_us: 0,
                    }),
                    initial_payload: Vec::new(),
                    maintain_aspect_ratio: false,
                    create_from_center: false,
                    snap_override: false,
                })),
            };

            let input = EngineInput {
                sequence: 1,
                payload: Some(V2InputPayload::CommandEvent(CommandEvent {
                    command_bytes: encode_message(&command),
                })),
            };
            let mut input_bytes = encode_message_v2(&input);
            let mut process_error = sd_bytes_t::default();
            let process_status = sd_engine_v2_process_input(
                engine,
                as_input_bytes(&mut input_bytes),
                &mut process_error,
            );
            assert_eq!(process_status, SD_STATUS_OK);
            assert!(copy_and_free(process_error).is_empty());

            let mut saw_snapshot = false;
            loop {
                let mut output = sd_bytes_t::default();
                let mut output_error = sd_bytes_t::default();
                let status = sd_engine_v2_poll_output(engine, &mut output, &mut output_error);
                assert!(copy_and_free(output_error).is_empty());
                if status == SD_STATUS_NO_EVENT {
                    break;
                }
                assert_eq!(status, SD_STATUS_OK);
                let decoded: EngineOutput =
                    decode_message_v2(&copy_and_free(output)).expect("decode output");
                if let Some(V2OutputPayload::Snapshot(snapshot)) = decoded.payload {
                    let snapshot: EngineSnapshotV2 = snapshot;
                    saw_snapshot = snapshot
                        .elements
                        .iter()
                        .any(|element| element.id == "ffi-v2");
                }
            }

            assert!(saw_snapshot);
            sd_engine_destroy(engine);
        }
    }

    #[test]
    fn create_dispatch_snapshot_roundtrip() {
        unsafe {
            let engine = create_engine();

            let command = EngineCommand {
                kind: EngineCommandKind::CreateElement as i32,
                payload: Some(CommandPayload::CreateElement(CreateElementCommand {
                    element_type: ElementType::Rectangle as i32,
                    element_id: "ffi-rect".to_string(),
                    position: Some(DrawPoint {
                        x: 12.0,
                        y: 24.0,
                        pressure: 0.0,
                        timestamp_us: 0,
                    }),
                    initial_payload: vec![7, 8, 9],
                    maintain_aspect_ratio: false,
                    create_from_center: false,
                    snap_override: false,
                })),
            };
            let mut command_bytes = encode_message(&command);
            let mut dispatch_error = sd_bytes_t::default();

            let dispatch_status = sd_engine_dispatch(
                engine,
                as_input_bytes(&mut command_bytes),
                &mut dispatch_error,
            );
            assert_eq!(dispatch_status, SD_STATUS_OK);
            assert!(copy_and_free(dispatch_error).is_empty());

            let mut snapshot = sd_bytes_t::default();
            let mut snapshot_error = sd_bytes_t::default();
            let snapshot_status =
                sd_engine_get_snapshot(engine, &mut snapshot, &mut snapshot_error);
            assert_eq!(snapshot_status, SD_STATUS_OK);
            assert!(copy_and_free(snapshot_error).is_empty());

            let decoded: EngineSnapshot =
                decode_message(&copy_and_free(snapshot)).expect("decode snapshot");
            assert_eq!(decoded.elements.len(), 1);
            assert_eq!(decoded.elements[0].id, "ffi-rect");

            sd_engine_destroy(engine);
        }
    }

    #[test]
    fn null_handle_returns_engine_error() {
        unsafe {
            let mut error = sd_bytes_t::default();
            let status =
                sd_engine_dispatch(std::ptr::null_mut(), sd_bytes_t::default(), &mut error);
            assert_eq!(status, SD_STATUS_ENGINE_ERROR);
            let decoded: EngineError = decode_message(&copy_and_free(error)).expect("decode error");
            assert!(decoded.message.contains("engine handle is null"));
        }
    }

    #[test]
    fn poll_event_none_returns_no_event() {
        unsafe {
            let engine = create_engine();
            let mut event = sd_bytes_t::default();
            let mut error = sd_bytes_t::default();
            let status = sd_engine_poll_event(engine, &mut event, &mut error);
            assert_eq!(status, SD_STATUS_NO_EVENT);
            assert!(copy_and_free(event).is_empty());
            assert!(copy_and_free(error).is_empty());
            sd_engine_destroy(engine);
        }
    }

    #[test]
    fn multi_engine_isolation() {
        unsafe {
            let engine_a = create_engine();
            let engine_b = create_engine();

            let command_a = EngineCommand {
                kind: EngineCommandKind::CreateElement as i32,
                payload: Some(CommandPayload::CreateElement(CreateElementCommand {
                    element_type: ElementType::Text as i32,
                    element_id: "engine-a".to_string(),
                    position: None,
                    initial_payload: Vec::new(),
                    maintain_aspect_ratio: false,
                    create_from_center: false,
                    snap_override: false,
                })),
            };
            let command_b = EngineCommand {
                kind: EngineCommandKind::CreateElement as i32,
                payload: Some(CommandPayload::CreateElement(CreateElementCommand {
                    element_type: ElementType::Arrow as i32,
                    element_id: "engine-b".to_string(),
                    position: None,
                    initial_payload: Vec::new(),
                    maintain_aspect_ratio: false,
                    create_from_center: false,
                    snap_override: false,
                })),
            };

            let mut command_a_bytes = encode_message(&command_a);
            let mut command_b_bytes = encode_message(&command_b);
            let mut error = sd_bytes_t::default();

            assert_eq!(
                sd_engine_dispatch(engine_a, as_input_bytes(&mut command_a_bytes), &mut error),
                SD_STATUS_OK
            );
            assert!(copy_and_free(error).is_empty());

            assert_eq!(
                sd_engine_dispatch(engine_b, as_input_bytes(&mut command_b_bytes), &mut error),
                SD_STATUS_OK
            );
            assert!(copy_and_free(error).is_empty());

            let mut snapshot_a = sd_bytes_t::default();
            let mut snapshot_b = sd_bytes_t::default();
            let mut snapshot_error = sd_bytes_t::default();

            assert_eq!(
                sd_engine_get_snapshot(engine_a, &mut snapshot_a, &mut snapshot_error),
                SD_STATUS_OK
            );
            assert!(copy_and_free(snapshot_error).is_empty());

            assert_eq!(
                sd_engine_get_snapshot(engine_b, &mut snapshot_b, &mut snapshot_error),
                SD_STATUS_OK
            );
            assert!(copy_and_free(snapshot_error).is_empty());

            let decoded_a: EngineSnapshot =
                decode_message(&copy_and_free(snapshot_a)).expect("decode a");
            let decoded_b: EngineSnapshot =
                decode_message(&copy_and_free(snapshot_b)).expect("decode b");

            assert_eq!(decoded_a.elements[0].id, "engine-a");
            assert_eq!(decoded_b.elements[0].id, "engine-b");

            sd_engine_destroy(engine_a);
            sd_engine_destroy(engine_b);
        }
    }
}
