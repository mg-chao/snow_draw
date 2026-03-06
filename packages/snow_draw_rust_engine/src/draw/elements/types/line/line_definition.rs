use std::sync::LazyLock;

use crate::draw::elements::core::element_data::ElementTypeId;
use crate::draw::elements::core::element_definition::ElementDefinition;
use crate::draw::elements::types::connector::connector_creation_strategy::LineCreationStrategy;

use super::line_data::LineData;
use super::line_hit_tester::LineHitTester;
use super::line_task_encoder::LineTaskEncoder;

/// Typed Rust alias for the Dart `ElementDefinition<LineData>`.
pub type LineDefinition =
    ElementDefinition<LineData, LineHitTester, LineTaskEncoder, LineCreationStrategy>;

/// Shared line element definition, equivalent to Dart `const lineDefinition`.
pub static LINE_DEFINITION: LazyLock<LineDefinition> = LazyLock::new(build_line_definition);

/// Returns the translated line element definition.
pub fn line_definition() -> LineDefinition {
    LINE_DEFINITION.clone()
}

fn build_line_definition() -> LineDefinition {
    ElementDefinition::new(
        ElementTypeId::new(LineData::TYPE_ID_TOKEN),
        "Line",
        LineHitTester,
        LineData::default,
        |json| LineData::from_json(json).unwrap_or_default(),
        LineTaskEncoder,
        Some(LineCreationStrategy::new()),
    )
}

#[cfg(test)]
mod tests {
    use super::*;
    use serde_json::Value;

    #[test]
    fn line_definition_uses_line_type_token() {
        let definition = line_definition();
        assert_eq!(definition.type_id.as_str(), LineData::TYPE_ID_TOKEN);
        assert_eq!(definition.display_name, "Line");
        assert!(definition.creation_strategy.is_some());
    }

    #[test]
    fn line_data_serializes_with_type_id() {
        let data = LineData::default();
        let json = data.to_json_map();
        assert_eq!(
            json.get("typeId"),
            Some(&Value::String(LineData::TYPE_ID_TOKEN.to_owned()))
        );
    }
}
