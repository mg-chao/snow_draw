//! WASM adapter for the Snow Draw engine.

use engine_core::{Engine, EngineV2};
use engine_proto::{decode_message, default_engine_config, EngineConfig};
use engine_proto_v2::{decode_message as decode_message_v2, default_init_request};
use wasm_bindgen::prelude::*;

#[wasm_bindgen]
pub struct WasmEngine {
    inner: Engine,
    inner_v2: EngineV2,
}

#[wasm_bindgen]
impl WasmEngine {
    #[wasm_bindgen(constructor)]
    pub fn new(config_bytes: Vec<u8>) -> Result<WasmEngine, JsValue> {
        let config = if config_bytes.is_empty() {
            default_engine_config()
        } else {
            decode_message::<EngineConfig>(&config_bytes)
                .map_err(|error| JsValue::from_str(&error.to_string()))?
        };

        let init = engine_init_from_config(&config);

        Ok(WasmEngine {
            inner: Engine::new(config),
            inner_v2: EngineV2::from_init_request(init),
        })
    }

    pub fn dispatch(&mut self, command_bytes: Vec<u8>) -> Result<(), JsValue> {
        self.inner
            .dispatch_bytes(&command_bytes)
            .map_err(|error| JsValue::from_str(&error.to_string()))
    }

    pub fn get_snapshot(&self) -> Vec<u8> {
        self.inner.get_snapshot_bytes()
    }

    pub fn build_frame_plan(&self, request_bytes: Vec<u8>) -> Result<Vec<u8>, JsValue> {
        self.inner
            .build_frame_plan_bytes(&request_bytes)
            .map_err(|error| JsValue::from_str(&error.to_string()))
    }

    pub fn poll_event(&mut self) -> Option<Vec<u8>> {
        self.inner.poll_event_bytes()
    }

    #[wasm_bindgen(js_name = processInputV2)]
    pub fn process_input_v2(&mut self, input_bytes: Vec<u8>) -> Result<(), JsValue> {
        self.inner_v2
            .process_input_bytes(&input_bytes)
            .map_err(|error| JsValue::from_str(&error.to_string()))
    }

    #[wasm_bindgen(js_name = pollOutputV2)]
    pub fn poll_output_v2(&mut self) -> Option<Vec<u8>> {
        self.inner_v2.poll_output_bytes()
    }

    #[wasm_bindgen(js_name = resetV2)]
    pub fn reset_v2(&mut self, init_bytes: Vec<u8>) -> Result<(), JsValue> {
        let init = if init_bytes.is_empty() {
            default_init_request()
        } else {
            decode_message_v2(&init_bytes).map_err(|error| JsValue::from_str(&error.to_string()))?
        };
        self.inner_v2 = EngineV2::from_init_request(init);
        Ok(())
    }
}

fn engine_init_from_config(config: &EngineConfig) -> engine_proto_v2::EngineInitRequest {
    let mut init = default_init_request();
    init.schema_version = config.schema_version;
    init.locale_tag = config.locale_tag.clone();
    init.scale_factor = config.scale_factor;
    init.requested_capabilities_mask = config.requested_capabilities;
    init.deterministic_seed = config.deterministic_seed;
    init
}

#[cfg(test)]
mod tests {
    use engine_proto::engine_command::Payload;
    use engine_proto::{
        encode_message, CreateElementCommand, DrawPoint, ElementType, EngineCommand,
        EngineCommandKind,
    };
    use engine_proto_v2::engine_input::Payload as V2Payload;
    use engine_proto_v2::{encode_message as encode_v2, CommandEvent, EngineInput};

    use super::WasmEngine;

    #[test]
    fn v2_pipeline_emits_outputs() {
        let mut wasm = WasmEngine::new(Vec::new()).expect("engine");

        // Initial init_ack output.
        assert!(wasm.poll_output_v2().is_some());

        let command = EngineCommand {
            kind: EngineCommandKind::CreateElement as i32,
            payload: Some(Payload::CreateElement(CreateElementCommand {
                element_type: ElementType::Rectangle as i32,
                element_id: "wasm-v2".to_string(),
                position: Some(DrawPoint {
                    x: 4.0,
                    y: 8.0,
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
            payload: Some(V2Payload::CommandEvent(CommandEvent {
                command_bytes: encode_message(&command),
            })),
        };

        wasm.process_input_v2(encode_v2(&input)).expect("process");
        assert!(wasm.poll_output_v2().is_some());
    }
}
