//! WASM adapter for the Snow Draw engine.

use engine_core::Engine;
use engine_proto::{decode_message, default_engine_config, EngineConfig};
use wasm_bindgen::prelude::*;

#[wasm_bindgen]
pub struct WasmEngine {
    inner: Engine,
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

        Ok(WasmEngine {
            inner: Engine::new(config),
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
}
