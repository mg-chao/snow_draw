use std::sync::LazyLock;

use crate::draw::elements::core::element_data::ElementTypeId;
use crate::draw::elements::core::element_definition::ElementDefinition;
use crate::draw::elements::core::rect_creation_strategy::RectCreationStrategy;

use super::text_data::TextData;
use super::text_hit_tester::TextHitTester;
use super::text_task_encoder::TextTaskEncoder;

/// Typed Rust alias for the Dart `ElementDefinition<TextData>`.
pub type TextDefinition =
    ElementDefinition<TextData, TextHitTester, TextTaskEncoder, RectCreationStrategy>;

/// Shared text element definition, equivalent to Dart `const textDefinition`.
pub static TEXT_DEFINITION: LazyLock<TextDefinition> = LazyLock::new(build_text_definition);

/// Returns the translated text element definition.
pub fn text_definition() -> TextDefinition {
    TEXT_DEFINITION.clone()
}

fn build_text_definition() -> TextDefinition {
    ElementDefinition::new(
        ElementTypeId::new(TextData::TYPE_ID_TOKEN),
        "Text",
        TextHitTester,
        TextData::default,
        |json| TextData::from_json(json).unwrap_or_default(),
        TextTaskEncoder,
        Some(RectCreationStrategy::new()),
    )
}

#[cfg(test)]
mod tests {
    use super::*;
    use serde_json::{Map, Value};

    #[test]
    fn text_definition_uses_text_type_token() {
        let definition = text_definition();
        assert_eq!(definition.type_id.as_str(), TextData::TYPE_ID_TOKEN);
        assert_eq!(definition.display_name, "Text");
        assert!(definition.creation_strategy.is_some());
    }

    #[test]
    fn text_data_round_trips_text_field() {
        let mut json = Map::new();
        json.insert("text".to_owned(), Value::String("Hello".to_owned()));
        json.insert("color".to_owned(), Value::from(0xFF00_0000_u64));
        json.insert("fontSize".to_owned(), Value::from(14.0));
        json.insert("fontFamily".to_owned(), Value::String("".to_owned()));
        json.insert(
            "horizontalAlign".to_owned(),
            Value::String("left".to_owned()),
        );
        json.insert("verticalAlign".to_owned(), Value::String("top".to_owned()));
        json.insert("fillColor".to_owned(), Value::from(0x0000_0000_u64));
        json.insert("fillStyle".to_owned(), Value::String("solid".to_owned()));
        json.insert("strokeColor".to_owned(), Value::from(0x0000_0000_u64));
        json.insert("strokeWidth".to_owned(), Value::from(0.0));
        json.insert("cornerRadius".to_owned(), Value::from(0.0));
        json.insert("autoResize".to_owned(), Value::Bool(true));

        let decoded = TextData::from_json(&json).expect("text payload should decode");
        assert_eq!(decoded.text, "Hello");

        let encoded = decoded.to_json_map();
        assert_eq!(
            encoded.get("text"),
            Some(&Value::String("Hello".to_owned()))
        );
        assert_eq!(
            encoded.get("typeId"),
            Some(&Value::String(TextData::TYPE_ID_TOKEN.to_owned()))
        );
    }
}
