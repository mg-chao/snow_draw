use std::sync::LazyLock;

use crate::draw::elements::core::element_data::ElementTypeId;
use crate::draw::elements::core::element_definition::ElementDefinition;
use crate::draw::elements::core::rect_creation_strategy::RectCreationStrategy;

use super::filter_data::FilterData;
use super::filter_hit_tester::FilterHitTester;
use super::filter_task_encoder::FilterTaskEncoder;

/// Typed Rust alias for the Dart `ElementDefinition<FilterData>`.
pub type FilterDefinition =
    ElementDefinition<FilterData, FilterHitTester, FilterTaskEncoder, RectCreationStrategy>;

/// Shared filter element definition, equivalent to Dart `const filterDefinition`.
pub static FILTER_DEFINITION: LazyLock<FilterDefinition> = LazyLock::new(build_filter_definition);

/// Returns the translated filter element definition.
pub fn filter_definition() -> FilterDefinition {
    FILTER_DEFINITION.clone()
}

fn build_filter_definition() -> FilterDefinition {
    ElementDefinition::new(
        ElementTypeId::new(FilterData::TYPE_ID_TOKEN),
        "Filter",
        FilterHitTester,
        FilterData::default,
        |json| FilterData::from_json(json).unwrap_or_default(),
        FilterTaskEncoder,
        Some(RectCreationStrategy::new()),
    )
}

#[cfg(test)]
mod tests {
    use super::*;
    use serde_json::Value;

    #[test]
    fn filter_definition_uses_filter_type_token() {
        let definition = filter_definition();
        assert_eq!(definition.type_id.as_str(), FilterData::TYPE_ID_TOKEN);
        assert_eq!(definition.display_name, "Filter");
        assert!(definition.creation_strategy.is_some());
    }

    #[test]
    fn filter_data_serializes_with_type_id() {
        let data = FilterData::default();
        let json = data.to_json_map();
        assert_eq!(
            json.get("typeId"),
            Some(&Value::String(FilterData::TYPE_ID_TOKEN.to_owned()))
        );
    }
}
