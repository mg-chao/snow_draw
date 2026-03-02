use std::sync::LazyLock;

use crate::draw::elements::core::element_data::ElementTypeId;
use crate::draw::elements::core::element_definition::ElementDefinition;
use crate::draw::elements::core::rect_creation_strategy::RectCreationStrategy;

use super::highlight_data::HighlightData;
use super::highlight_hit_tester::HighlightHitTester;
use super::highlight_task_encoder::HighlightTaskEncoder;

/// Typed Rust alias for the Dart `ElementDefinition<HighlightData>`.
pub type HighlightDefinition = ElementDefinition<
    HighlightData,
    HighlightHitTester,
    HighlightTaskEncoder,
    RectCreationStrategy,
>;

/// Shared highlight element definition, equivalent to Dart
/// `const highlightDefinition`.
pub static HIGHLIGHT_DEFINITION: LazyLock<HighlightDefinition> =
    LazyLock::new(build_highlight_definition);

/// Returns the translated highlight element definition.
pub fn highlight_definition() -> HighlightDefinition {
    HIGHLIGHT_DEFINITION.clone()
}

fn build_highlight_definition() -> HighlightDefinition {
    ElementDefinition::new(
        ElementTypeId::new(HighlightData::TYPE_ID_TOKEN),
        "Highlight",
        HighlightHitTester,
        HighlightData::default,
        |json| HighlightData::from_json(json).unwrap_or_default(),
        HighlightTaskEncoder,
        Some(RectCreationStrategy::new()),
    )
}

#[cfg(test)]
mod tests {
    use super::*;
    use serde_json::Value;

    #[test]
    fn highlight_definition_uses_highlight_type_token() {
        let definition = highlight_definition();
        assert_eq!(definition.type_id.as_str(), HighlightData::TYPE_ID_TOKEN);
        assert_eq!(definition.display_name, "Highlight");
        assert!(definition.creation_strategy.is_some());
    }

    #[test]
    fn highlight_data_round_trips_json_fields() {
        let data = HighlightData::default();
        let json = data.to_json_map();
        let decoded = HighlightData::from_json(&json).expect("highlight data should decode");

        assert_eq!(decoded, data);
        assert_eq!(
            json.get("typeId"),
            Some(&Value::String(HighlightData::TYPE_ID_TOKEN.to_owned()))
        );
    }
}
