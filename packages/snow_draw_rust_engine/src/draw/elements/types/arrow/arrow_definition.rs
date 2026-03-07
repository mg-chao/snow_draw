use std::sync::LazyLock;

use crate::draw::elements::core::element_data::ElementTypeId;
use crate::draw::elements::core::element_definition::ElementDefinition;
use crate::draw::elements::types::connector::connector_creation_strategy::ArrowCreationStrategy;
use crate::draw::elements::types::connector::connector_hit_tester::ConnectorHitTester;

use super::arrow_data::ArrowData;
use super::arrow_task_encoder::ArrowTaskEncoder;

/// Typed Rust alias for the Dart `ElementDefinition<ArrowData>`.
pub type ArrowDefinition =
    ElementDefinition<ArrowData, ConnectorHitTester, ArrowTaskEncoder, ArrowCreationStrategy>;

/// Shared arrow element definition, equivalent to Dart `const arrowDefinition`.
pub static ARROW_DEFINITION: LazyLock<ArrowDefinition> = LazyLock::new(build_arrow_definition);

/// Returns the translated arrow element definition.
pub fn arrow_definition() -> ArrowDefinition {
    ARROW_DEFINITION.clone()
}

fn build_arrow_definition() -> ArrowDefinition {
    ElementDefinition::new(
        ElementTypeId::new(ArrowData::TYPE_ID_TOKEN),
        "Arrow",
        ConnectorHitTester::new(),
        ArrowData::default,
        |json| {
            ArrowData::from_json(json)
                .unwrap_or_else(|error| panic!("failed to decode ArrowData: {error}"))
        },
        ArrowTaskEncoder,
        Some(ArrowCreationStrategy::new()),
    )
}

#[cfg(test)]
mod tests {
    use super::*;
    use serde_json::Value;

    #[test]
    fn arrow_definition_uses_arrow_type_token() {
        let definition = arrow_definition();
        assert_eq!(definition.type_id.as_str(), ArrowData::TYPE_ID_TOKEN);
        assert_eq!(definition.display_name, "Arrow");
        assert!(definition.creation_strategy.is_some());
    }

    #[test]
    fn arrow_data_serializes_with_type_id() {
        let data = ArrowData::default();
        let json = data.to_json_map();
        assert_eq!(json.get("typeId"), Some(&Value::String("arrow".to_owned())));
    }
}
