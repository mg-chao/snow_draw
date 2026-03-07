use std::sync::LazyLock;

use crate::draw::elements::core::element_data::ElementTypeId;
use crate::draw::elements::core::element_definition::ElementDefinition;
use crate::draw::elements::core::rect_creation_strategy::RectCreationStrategy;

use super::rectangle_data::RectangleData;
use super::rectangle_hit_tester::RectangleHitTester;
use super::rectangle_task_encoder::RectangleTaskEncoder;

/// Typed Rust alias for the Dart `ElementDefinition<RectangleData>`.
pub type RectangleDefinition = ElementDefinition<
    RectangleData,
    RectangleHitTester,
    RectangleTaskEncoder,
    RectCreationStrategy,
>;

/// Shared rectangle element definition, equivalent to Dart
/// `const rectangleDefinition`.
pub static RECTANGLE_DEFINITION: LazyLock<RectangleDefinition> =
    LazyLock::new(build_rectangle_definition);

/// Returns the translated rectangle element definition.
pub fn rectangle_definition() -> RectangleDefinition {
    RECTANGLE_DEFINITION.clone()
}

fn build_rectangle_definition() -> RectangleDefinition {
    ElementDefinition::new(
        ElementTypeId::new(RectangleData::TYPE_ID_TOKEN),
        "Rectangle",
        RectangleHitTester,
        RectangleData::default,
        |json| RectangleData::from_json(json).unwrap_or_default(),
        RectangleTaskEncoder,
        Some(RectCreationStrategy::new()),
    )
}

#[cfg(test)]
mod tests {
    use super::*;
    use serde_json::Value;

    #[test]
    fn rectangle_definition_uses_rectangle_type_token() {
        let definition = rectangle_definition();
        assert_eq!(definition.type_id.as_str(), RectangleData::TYPE_ID_TOKEN);
        assert_eq!(definition.display_name, "Rectangle");
        assert!(definition.creation_strategy.is_some());
    }

    #[test]
    fn rectangle_data_serializes_with_type_id() {
        let data = RectangleData::default();
        let json = data.to_json_map();
        assert_eq!(
            json.get("typeId"),
            Some(&Value::String(RectangleData::TYPE_ID_TOKEN.to_owned()))
        );
    }
}
