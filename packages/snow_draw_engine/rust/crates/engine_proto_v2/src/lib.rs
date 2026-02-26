//! Generated protobuf contracts for the Snow Draw Rust engine V2 ABI.

use prost::Message;
use thiserror::Error;

pub const ENGINE_V2_SCHEMA_VERSION: u32 = 2;

#[derive(Debug, Error)]
pub enum ProtoError {
    #[error("decode failed: {0}")]
    Decode(#[from] prost::DecodeError),
}

pub fn encode_message<T: Message>(message: &T) -> Vec<u8> {
    message.encode_to_vec()
}

pub fn decode_message<T: Message + Default>(bytes: &[u8]) -> Result<T, ProtoError> {
    Ok(T::decode(bytes)?)
}

include!(concat!(env!("OUT_DIR"), "/snowdraw.engine.v2.rs"));

pub fn default_init_request() -> EngineInitRequest {
    EngineInitRequest {
        requested_abi_version: 2,
        schema_version: ENGINE_V2_SCHEMA_VERSION,
        locale_tag: "en-US".to_string(),
        scale_factor: 1.0,
        requested_capabilities_mask: 0,
        deterministic_seed: 0,
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn roundtrip_init_ack() {
        let ack = EngineInitAck {
            abi_version: 2,
            schema_version: ENGINE_V2_SCHEMA_VERSION,
            granted_capabilities_mask: 0,
            message: "ok".to_string(),
        };
        let encoded = encode_message(&ack);
        let decoded: EngineInitAck = decode_message(&encoded).expect("decode");
        assert_eq!(decoded.abi_version, 2);
        assert_eq!(decoded.schema_version, ENGINE_V2_SCHEMA_VERSION);
    }
}
