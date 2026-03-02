use std::sync::LazyLock;

use crate::draw::elements::core::element_data::ElementTypeId;
use crate::draw::elements::core::element_definition::ElementDefinition;

use super::free_draw_creation_strategy::FreeDrawCreationStrategy;
use super::free_draw_data::FreeDrawData;
use super::free_draw_hit_tester::FreeDrawHitTester;
use super::free_draw_task_encoder::FreeDrawTaskEncoder;

/// Typed Rust alias for the Dart `ElementDefinition<FreeDrawData>`.
pub type FreeDrawDefinition = ElementDefinition<
    FreeDrawData,
    FreeDrawHitTester,
    FreeDrawTaskEncoder,
    FreeDrawCreationStrategy,
>;

/// Shared free-draw element definition, equivalent to Dart
/// `const freeDrawDefinition`.
pub static FREE_DRAW_DEFINITION: LazyLock<FreeDrawDefinition> =
    LazyLock::new(build_free_draw_definition);

/// Returns the translated free-draw element definition.
pub fn free_draw_definition() -> FreeDrawDefinition {
    FREE_DRAW_DEFINITION.clone()
}

fn build_free_draw_definition() -> FreeDrawDefinition {
    ElementDefinition::new(
        ElementTypeId::new(FreeDrawData::TYPE_ID_TOKEN),
        "Free Draw",
        FreeDrawHitTester,
        FreeDrawData::default,
        |json| FreeDrawData::from_json(json).unwrap_or_default(),
        FreeDrawTaskEncoder,
        Some(FreeDrawCreationStrategy::new()),
    )
}

#[cfg(test)]
mod tests {
    use super::*;
    use serde_json::Value;

    #[test]
    fn free_draw_definition_uses_free_draw_type_token() {
        let definition = free_draw_definition();
        assert_eq!(definition.type_id.as_str(), FreeDrawData::TYPE_ID_TOKEN);
        assert_eq!(definition.display_name, "Free Draw");
        assert!(definition.creation_strategy.is_some());
    }

    #[test]
    fn free_draw_data_serializes_with_type_id() {
        let data = FreeDrawData::default();
        let json = data.to_json_map();
        assert_eq!(
            json.get("typeId"),
            Some(&Value::String(FreeDrawData::TYPE_ID_TOKEN.to_owned()))
        );
    }
}
