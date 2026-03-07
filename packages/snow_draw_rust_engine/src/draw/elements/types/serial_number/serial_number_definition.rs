use std::sync::LazyLock;

use crate::draw::elements::core::element_data::ElementTypeId;
use crate::draw::elements::core::element_definition::ElementDefinition;

use super::serial_number_creation_strategy::SerialNumberCreationStrategy;
use super::serial_number_data::SerialNumberData;
use super::serial_number_hit_tester::SerialNumberHitTester;
use super::serial_number_task_encoder::SerialNumberTaskEncoder;

/// Typed Rust alias for the Dart `ElementDefinition<SerialNumberData>`.
pub type SerialNumberDefinition = ElementDefinition<
    SerialNumberData,
    SerialNumberHitTester,
    SerialNumberTaskEncoder,
    SerialNumberCreationStrategy,
>;

/// Shared serial-number element definition, equivalent to Dart
/// `const serialNumberDefinition`.
pub static SERIAL_NUMBER_DEFINITION: LazyLock<SerialNumberDefinition> =
    LazyLock::new(build_serial_number_definition);

/// Returns the translated serial-number element definition.
pub fn serial_number_definition() -> SerialNumberDefinition {
    SERIAL_NUMBER_DEFINITION.clone()
}

fn build_serial_number_definition() -> SerialNumberDefinition {
    ElementDefinition::new(
        ElementTypeId::new(SerialNumberData::TYPE_ID_TOKEN),
        "Serial Number",
        SerialNumberHitTester,
        SerialNumberData::default,
        |json| SerialNumberData::from_json(json).unwrap_or_default(),
        SerialNumberTaskEncoder,
        Some(SerialNumberCreationStrategy::new()),
    )
}

#[cfg(test)]
mod tests {
    use super::*;
    use serde_json::Value;

    #[test]
    fn serial_number_definition_uses_serial_number_type_token() {
        let definition = serial_number_definition();
        assert_eq!(definition.type_id.as_str(), SerialNumberData::TYPE_ID_TOKEN);
        assert_eq!(definition.display_name, "Serial Number");
        assert!(definition.creation_strategy.is_some());
    }

    #[test]
    fn serial_number_data_round_trips_json_fields() {
        let data = SerialNumberData::default();
        let json = data.to_json_map();
        let decoded = SerialNumberData::from_json(&json).expect("serial number should decode");

        assert_eq!(decoded, data);
        assert_eq!(
            json.get("typeId"),
            Some(&Value::String(SerialNumberData::TYPE_ID_TOKEN.to_owned()))
        );
    }
}
