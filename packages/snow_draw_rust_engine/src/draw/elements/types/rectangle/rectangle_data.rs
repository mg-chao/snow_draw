#![allow(dead_code)]

use crate::draw::config::draw_config::{ConfigDefaults, ElementStyleConfig};
use crate::draw::elements::core::element_data::{DynElementData, ElementData, ElementTypeId};
use crate::draw::elements::core::element_style_configurable_data::ElementStyleConfigurableData;
use crate::draw::elements::core::element_style_updatable_data::ElementStyleUpdatableData;
use crate::draw::types::draw_color::DrawColor;
use crate::draw::types::element_style::{ElementStyleUpdate, FillStyle, StrokeStyle};
use serde_json::{Map, Value};
use thiserror::Error;

/// Immutable rectangle payload translated from Dart `RectangleData`.
#[derive(Clone, Debug, PartialEq)]
pub struct RectangleData {
    pub corner_radius: f64,
    pub fill_color: DrawColor,
    pub color: DrawColor,
    pub stroke_width: f64,
    pub stroke_style: StrokeStyle,
    pub fill_style: FillStyle,
}

/// Patch payload for [`RectangleData::copy_with`].
#[derive(Clone, Debug, Default, PartialEq)]
pub struct RectangleDataPatch {
    pub corner_radius: Option<f64>,
    pub fill_color: Option<DrawColor>,
    pub color: Option<DrawColor>,
    pub stroke_width: Option<f64>,
    pub stroke_style: Option<StrokeStyle>,
    pub fill_style: Option<FillStyle>,
}

impl RectangleData {
    pub const TYPE_ID_TOKEN: &'static str = "rectangle";

    /// Decodes `RectangleData` from JSON.
    pub fn from_json(json: &Map<String, Value>) -> Result<Self, RectangleDataDecodeError> {
        Ok(Self {
            corner_radius: decode_required_f64(json, "cornerRadius")?,
            fill_color: decode_required_color(json, "fillColor")?,
            color: decode_required_color(json, "color")?,
            stroke_width: decode_required_f64(json, "strokeWidth")?,
            stroke_style: decode_required_stroke_style(json, "strokeStyle")?,
            fill_style: decode_required_fill_style(json, "fillStyle")?,
        })
    }

    /// Decodes `RectangleData` from a JSON value.
    pub fn from_json_value(value: &Value) -> Result<Self, RectangleDataDecodeError> {
        let json = value.as_object().ok_or_else(|| {
            RectangleDataDecodeError::invalid_field("rectangle", "expected JSON object payload")
        })?;
        Self::from_json(json)
    }

    /// Returns the strongly typed element id token for rectangle payloads.
    pub fn type_id_token() -> ElementTypeId<RectangleData> {
        ElementTypeId::new(Self::TYPE_ID_TOKEN)
    }

    /// Returns an updated payload while preserving immutability.
    pub fn copy_with(&self, patch: RectangleDataPatch) -> Self {
        Self {
            corner_radius: patch.corner_radius.unwrap_or(self.corner_radius),
            fill_color: patch.fill_color.unwrap_or(self.fill_color),
            color: patch.color.unwrap_or(self.color),
            stroke_width: patch.stroke_width.unwrap_or(self.stroke_width),
            stroke_style: patch.stroke_style.unwrap_or(self.stroke_style),
            fill_style: patch.fill_style.unwrap_or(self.fill_style),
        }
    }

    /// Serializes this payload to JSON.
    pub fn to_json_map(&self) -> Map<String, Value> {
        let mut json = Map::new();
        json.insert(
            "typeId".to_string(),
            Value::String(Self::TYPE_ID_TOKEN.to_string()),
        );
        json.insert("cornerRadius".to_string(), Value::from(self.corner_radius));
        json.insert(
            "fillColor".to_string(),
            Value::from(self.fill_color.to_argb32() as u64),
        );
        json.insert(
            "color".to_string(),
            Value::from(self.color.to_argb32() as u64),
        );
        json.insert("strokeWidth".to_string(), Value::from(self.stroke_width));
        json.insert(
            "strokeStyle".to_string(),
            Value::String(stroke_style_to_name(self.stroke_style).to_string()),
        );
        json.insert(
            "fillStyle".to_string(),
            Value::String(fill_style_to_name(self.fill_style).to_string()),
        );
        json
    }
}

impl Default for RectangleData {
    fn default() -> Self {
        Self {
            corner_radius: ConfigDefaults::DEFAULT_CORNER_RADIUS,
            fill_color: ConfigDefaults::DEFAULT_FILL_COLOR,
            color: ConfigDefaults::DEFAULT_COLOR,
            stroke_width: ConfigDefaults::DEFAULT_STROKE_WIDTH,
            stroke_style: ConfigDefaults::DEFAULT_STROKE_STYLE,
            fill_style: ConfigDefaults::DEFAULT_FILL_STYLE,
        }
    }
}

impl ElementData for RectangleData {
    fn type_id(&self) -> ElementTypeId<DynElementData> {
        ElementTypeId::new(Self::TYPE_ID_TOKEN)
    }

    fn to_json(&self) -> Map<String, Value> {
        self.to_json_map()
    }
}

impl ElementStyleConfigurableData for RectangleData {
    fn with_element_style(&self, style: ElementStyleConfig) -> Box<DynElementData> {
        Box::new(self.copy_with(RectangleDataPatch {
            corner_radius: Some(style.corner_radius),
            fill_color: Some(style.fill_color),
            color: Some(style.color),
            stroke_width: Some(style.stroke_width),
            stroke_style: Some(style.stroke_style),
            fill_style: Some(style.fill_style),
        }))
    }
}

impl ElementStyleUpdatableData for RectangleData {
    fn with_style_update(&self, update: ElementStyleUpdate) -> Box<DynElementData> {
        Box::new(self.copy_with(RectangleDataPatch {
            corner_radius: update.corner_radius.or(Some(self.corner_radius)),
            fill_color: update.fill_color,
            color: update.color,
            stroke_width: update.stroke_width.or(Some(self.stroke_width)),
            stroke_style: update.stroke_style.or(Some(self.stroke_style)),
            fill_style: update.fill_style.or(Some(self.fill_style)),
        }))
    }
}

/// Decode failures for `RectangleData` JSON payloads.
#[derive(Debug, Error)]
#[error("{message}")]
pub struct RectangleDataDecodeError {
    message: String,
}

impl RectangleDataDecodeError {
    fn invalid_field(field: &str, detail: &str) -> Self {
        Self {
            message: format!("Invalid `{field}`: {detail}"),
        }
    }
}

fn decode_required_f64(
    json: &Map<String, Value>,
    field: &str,
) -> Result<f64, RectangleDataDecodeError> {
    let value = json
        .get(field)
        .ok_or_else(|| RectangleDataDecodeError::invalid_field(field, "field is missing"))?;
    value
        .as_f64()
        .ok_or_else(|| RectangleDataDecodeError::invalid_field(field, "expected numeric value"))
}

fn decode_required_color(
    json: &Map<String, Value>,
    field: &str,
) -> Result<DrawColor, RectangleDataDecodeError> {
    let value = json
        .get(field)
        .ok_or_else(|| RectangleDataDecodeError::invalid_field(field, "field is missing"))?;
    let number = value
        .as_i64()
        .or_else(|| value.as_u64().and_then(|raw| i64::try_from(raw).ok()))
        .ok_or_else(|| RectangleDataDecodeError::invalid_field(field, "expected integer ARGB32"))?;
    Ok(DrawColor::new(number as u32))
}

fn decode_required_stroke_style(
    json: &Map<String, Value>,
    field: &str,
) -> Result<StrokeStyle, RectangleDataDecodeError> {
    let raw = decode_required_string(json, field)?;
    stroke_style_from_name(&raw)
        .ok_or_else(|| RectangleDataDecodeError::invalid_field(field, "unsupported stroke style"))
}

fn decode_required_fill_style(
    json: &Map<String, Value>,
    field: &str,
) -> Result<FillStyle, RectangleDataDecodeError> {
    let raw = decode_required_string(json, field)?;
    fill_style_from_name(&raw)
        .ok_or_else(|| RectangleDataDecodeError::invalid_field(field, "unsupported fill style"))
}

fn decode_required_string(
    json: &Map<String, Value>,
    field: &str,
) -> Result<String, RectangleDataDecodeError> {
    let value = json
        .get(field)
        .ok_or_else(|| RectangleDataDecodeError::invalid_field(field, "field is missing"))?;
    value
        .as_str()
        .map(str::to_owned)
        .ok_or_else(|| RectangleDataDecodeError::invalid_field(field, "expected string value"))
}

fn stroke_style_to_name(style: StrokeStyle) -> &'static str {
    match style {
        StrokeStyle::Solid => "solid",
        StrokeStyle::Dashed => "dashed",
        StrokeStyle::Dotted => "dotted",
    }
}

fn stroke_style_from_name(raw: &str) -> Option<StrokeStyle> {
    match raw {
        "solid" => Some(StrokeStyle::Solid),
        "dashed" => Some(StrokeStyle::Dashed),
        "dotted" => Some(StrokeStyle::Dotted),
        _ => None,
    }
}

fn fill_style_to_name(style: FillStyle) -> &'static str {
    match style {
        FillStyle::Solid => "solid",
        FillStyle::Line => "line",
        FillStyle::CrossLine => "crossLine",
    }
}

fn fill_style_from_name(raw: &str) -> Option<FillStyle> {
    match raw {
        "solid" => Some(FillStyle::Solid),
        "line" => Some(FillStyle::Line),
        "crossLine" => Some(FillStyle::CrossLine),
        _ => None,
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn default_matches_dart_defaults() {
        let data = RectangleData::default();
        assert_eq!(data.corner_radius, ConfigDefaults::DEFAULT_CORNER_RADIUS);
        assert_eq!(data.fill_color, ConfigDefaults::DEFAULT_FILL_COLOR);
        assert_eq!(data.color, ConfigDefaults::DEFAULT_COLOR);
        assert_eq!(data.stroke_width, ConfigDefaults::DEFAULT_STROKE_WIDTH);
        assert_eq!(data.stroke_style, ConfigDefaults::DEFAULT_STROKE_STYLE);
        assert_eq!(data.fill_style, ConfigDefaults::DEFAULT_FILL_STYLE);
    }

    #[test]
    fn to_json_uses_dart_keys_and_enum_names() {
        let data = RectangleData {
            corner_radius: 6.5,
            fill_color: DrawColor::new(0xFF12_3456),
            color: DrawColor::new(0xFF65_4321),
            stroke_width: 2.25,
            stroke_style: StrokeStyle::Dotted,
            fill_style: FillStyle::CrossLine,
        };

        let json = data.to_json_map();

        assert_eq!(
            json.get("typeId"),
            Some(&Value::String("rectangle".to_string()))
        );
        assert_eq!(json.get("cornerRadius"), Some(&Value::from(6.5)));
        assert_eq!(json.get("fillColor"), Some(&Value::from(0xFF12_3456_u64)));
        assert_eq!(json.get("color"), Some(&Value::from(0xFF65_4321_u64)));
        assert_eq!(json.get("strokeWidth"), Some(&Value::from(2.25)));
        assert_eq!(
            json.get("strokeStyle"),
            Some(&Value::String("dotted".to_string()))
        );
        assert_eq!(
            json.get("fillStyle"),
            Some(&Value::String("crossLine".to_string()))
        );
    }

    #[test]
    fn from_json_decodes_all_fields() {
        let mut json = Map::new();
        json.insert("cornerRadius".to_string(), Value::from(8.0));
        json.insert("fillColor".to_string(), Value::from(0xFF01_0203_u64));
        json.insert("color".to_string(), Value::from(0xFF04_0506_u64));
        json.insert("strokeWidth".to_string(), Value::from(3.5));
        json.insert(
            "strokeStyle".to_string(),
            Value::String("dashed".to_string()),
        );
        json.insert("fillStyle".to_string(), Value::String("line".to_string()));

        let data = RectangleData::from_json(&json).expect("rectangle data should decode");
        assert_eq!(data.corner_radius, 8.0);
        assert_eq!(data.fill_color, DrawColor::new(0xFF01_0203));
        assert_eq!(data.color, DrawColor::new(0xFF04_0506));
        assert_eq!(data.stroke_width, 3.5);
        assert_eq!(data.stroke_style, StrokeStyle::Dashed);
        assert_eq!(data.fill_style, FillStyle::Line);
    }
}
