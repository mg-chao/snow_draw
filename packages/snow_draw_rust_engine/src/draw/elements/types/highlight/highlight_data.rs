#![allow(dead_code)]

use crate::draw::config::draw_config::{ConfigDefaults, ElementStyleConfig};
use crate::draw::elements::core::element_data::{DynElementData, ElementData, ElementTypeId};
use crate::draw::elements::core::element_style_configurable_data::ElementStyleConfigurableData;
use crate::draw::elements::core::element_style_updatable_data::ElementStyleUpdatableData;
use crate::draw::types::draw_color::DrawColor;
use crate::draw::types::element_style::{ElementStyleUpdate, HighlightShape};
use serde_json::{Map, Value};
use thiserror::Error;

/// Immutable highlight payload translated from Dart `HighlightData`.
#[derive(Clone, Debug, PartialEq)]
pub struct HighlightData {
    pub shape: HighlightShape,
    pub color: DrawColor,
    pub stroke_color: DrawColor,
    pub stroke_width: f64,
}

/// Patch payload for [`HighlightData::copy_with`].
#[derive(Clone, Debug, Default, PartialEq)]
pub struct HighlightDataPatch {
    pub shape: Option<HighlightShape>,
    pub color: Option<DrawColor>,
    pub stroke_color: Option<DrawColor>,
    pub stroke_width: Option<f64>,
}

impl HighlightData {
    pub const TYPE_ID_TOKEN: &'static str = "highlight";

    /// Decodes `HighlightData` from JSON.
    pub fn from_json(json: &Map<String, Value>) -> Result<Self, HighlightDataDecodeError> {
        Ok(Self {
            shape: decode_required_highlight_shape(json, "shape")?,
            color: decode_required_color(json, "color")?,
            stroke_color: decode_required_color(json, "strokeColor")?,
            stroke_width: decode_required_f64(json, "strokeWidth")?,
        })
    }

    /// Decodes `HighlightData` from a JSON value.
    pub fn from_json_value(value: &Value) -> Result<Self, HighlightDataDecodeError> {
        let json = value.as_object().ok_or_else(|| {
            HighlightDataDecodeError::invalid_field("highlight", "expected JSON object payload")
        })?;
        Self::from_json(json)
    }

    /// Returns the strongly typed element id token for highlight payloads.
    pub fn type_id_token() -> ElementTypeId<HighlightData> {
        ElementTypeId::new(Self::TYPE_ID_TOKEN)
    }

    /// Returns an updated payload while preserving immutability.
    pub fn copy_with(&self, patch: HighlightDataPatch) -> Self {
        Self {
            shape: patch.shape.unwrap_or(self.shape),
            color: patch.color.unwrap_or(self.color),
            stroke_color: patch.stroke_color.unwrap_or(self.stroke_color),
            stroke_width: patch.stroke_width.unwrap_or(self.stroke_width),
        }
    }

    /// Serializes this payload to JSON.
    pub fn to_json_map(&self) -> Map<String, Value> {
        let mut json = Map::new();
        json.insert(
            "typeId".to_string(),
            Value::String(Self::TYPE_ID_TOKEN.to_string()),
        );
        json.insert(
            "shape".to_string(),
            Value::String(highlight_shape_to_name(self.shape).to_string()),
        );
        json.insert(
            "color".to_string(),
            Value::from(self.color.to_argb32() as u64),
        );
        json.insert(
            "strokeColor".to_string(),
            Value::from(self.stroke_color.to_argb32() as u64),
        );
        json.insert("strokeWidth".to_string(), Value::from(self.stroke_width));
        json
    }
}

impl Default for HighlightData {
    fn default() -> Self {
        Self {
            shape: ConfigDefaults::DEFAULT_HIGHLIGHT_SHAPE,
            color: ConfigDefaults::DEFAULT_HIGHLIGHT_COLOR,
            stroke_color: ConfigDefaults::DEFAULT_HIGHLIGHT_STROKE_COLOR,
            stroke_width: 0.0,
        }
    }
}

impl ElementData for HighlightData {
    fn type_id(&self) -> ElementTypeId<DynElementData> {
        ElementTypeId::new(Self::TYPE_ID_TOKEN)
    }

    fn to_json(&self) -> Map<String, Value> {
        self.to_json_map()
    }
}

impl ElementStyleConfigurableData for HighlightData {
    fn with_element_style(&self, style: ElementStyleConfig) -> Box<DynElementData> {
        Box::new(self.copy_with(HighlightDataPatch {
            color: Some(style.color),
            stroke_color: Some(style.text_stroke_color),
            stroke_width: Some(style.text_stroke_width),
            shape: Some(style.highlight_shape),
        }))
    }
}

impl ElementStyleUpdatableData for HighlightData {
    fn with_style_update(&self, update: ElementStyleUpdate) -> Box<DynElementData> {
        Box::new(self.copy_with(HighlightDataPatch {
            color: update.color,
            stroke_color: update.text_stroke_color,
            stroke_width: update.text_stroke_width.or(Some(self.stroke_width)),
            shape: update.highlight_shape.or(Some(self.shape)),
        }))
    }
}

/// Decode failures for `HighlightData` JSON payloads.
#[derive(Debug, Error)]
#[error("{message}")]
pub struct HighlightDataDecodeError {
    message: String,
}

impl HighlightDataDecodeError {
    fn invalid_field(field: &str, detail: &str) -> Self {
        Self {
            message: format!("Invalid `{field}`: {detail}"),
        }
    }
}

fn decode_required_highlight_shape(
    json: &Map<String, Value>,
    field: &str,
) -> Result<HighlightShape, HighlightDataDecodeError> {
    let raw = decode_required_string(json, field)?;
    highlight_shape_from_name(&raw).ok_or_else(|| {
        HighlightDataDecodeError::invalid_field(field, "unsupported highlight shape value")
    })
}

fn decode_required_color(
    json: &Map<String, Value>,
    field: &str,
) -> Result<DrawColor, HighlightDataDecodeError> {
    let value = json
        .get(field)
        .ok_or_else(|| HighlightDataDecodeError::invalid_field(field, "field is missing"))?;
    let number = value
        .as_i64()
        .or_else(|| value.as_u64().and_then(|raw| i64::try_from(raw).ok()))
        .ok_or_else(|| HighlightDataDecodeError::invalid_field(field, "expected integer ARGB32"))?;
    Ok(DrawColor::new(number as u32))
}

fn decode_required_f64(
    json: &Map<String, Value>,
    field: &str,
) -> Result<f64, HighlightDataDecodeError> {
    let value = json
        .get(field)
        .ok_or_else(|| HighlightDataDecodeError::invalid_field(field, "field is missing"))?;
    value
        .as_f64()
        .ok_or_else(|| HighlightDataDecodeError::invalid_field(field, "expected numeric value"))
}

fn decode_required_string(
    json: &Map<String, Value>,
    field: &str,
) -> Result<String, HighlightDataDecodeError> {
    let value = json
        .get(field)
        .ok_or_else(|| HighlightDataDecodeError::invalid_field(field, "field is missing"))?;
    value
        .as_str()
        .map(str::to_owned)
        .ok_or_else(|| HighlightDataDecodeError::invalid_field(field, "expected string value"))
}

fn highlight_shape_to_name(shape: HighlightShape) -> &'static str {
    match shape {
        HighlightShape::Rectangle => "rectangle",
        HighlightShape::Ellipse => "ellipse",
    }
}

fn highlight_shape_from_name(raw: &str) -> Option<HighlightShape> {
    match raw {
        "rectangle" => Some(HighlightShape::Rectangle),
        "ellipse" => Some(HighlightShape::Ellipse),
        _ => None,
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn default_matches_dart_defaults() {
        let data = HighlightData::default();
        assert_eq!(data.shape, ConfigDefaults::DEFAULT_HIGHLIGHT_SHAPE);
        assert_eq!(data.color, ConfigDefaults::DEFAULT_HIGHLIGHT_COLOR);
        assert_eq!(
            data.stroke_color,
            ConfigDefaults::DEFAULT_HIGHLIGHT_STROKE_COLOR
        );
        assert_eq!(data.stroke_width, 0.0);
    }

    #[test]
    fn to_json_uses_dart_enum_name_and_keys() {
        let data = HighlightData {
            shape: HighlightShape::Ellipse,
            color: DrawColor::new(0xFF12_3456),
            stroke_color: DrawColor::new(0xFF65_4321),
            stroke_width: 2.5,
        };
        let json = data.to_json_map();

        assert_eq!(
            json.get("typeId"),
            Some(&Value::String("highlight".to_string()))
        );
        assert_eq!(
            json.get("shape"),
            Some(&Value::String("ellipse".to_string()))
        );
        assert_eq!(json.get("color"), Some(&Value::from(0xFF12_3456_u64)));
        assert_eq!(json.get("strokeColor"), Some(&Value::from(0xFF65_4321_u64)));
        assert_eq!(json.get("strokeWidth"), Some(&Value::from(2.5)));
    }

    #[test]
    fn from_json_decodes_all_required_fields() {
        let mut json = Map::new();
        json.insert("shape".to_string(), Value::String("rectangle".to_string()));
        json.insert("color".to_string(), Value::from(0xFFA1_A2A3_u64));
        json.insert("strokeColor".to_string(), Value::from(0xFFB1_B2B3_u64));
        json.insert("strokeWidth".to_string(), Value::from(1.75));

        let data = HighlightData::from_json(&json).expect("highlight data should decode");
        assert_eq!(data.shape, HighlightShape::Rectangle);
        assert_eq!(data.color, DrawColor::new(0xFFA1_A2A3));
        assert_eq!(data.stroke_color, DrawColor::new(0xFFB1_B2B3));
        assert_eq!(data.stroke_width, 1.75);
    }
}
