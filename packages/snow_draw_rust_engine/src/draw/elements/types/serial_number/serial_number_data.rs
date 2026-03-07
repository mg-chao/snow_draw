#![allow(dead_code)]

use crate::draw::config::draw_config::{ConfigDefaults, ElementStyleConfig};
use crate::draw::elements::core::element_data::{DynElementData, ElementData, ElementTypeId};
use crate::draw::elements::core::element_style_configurable_data::ElementStyleConfigurableData;
use crate::draw::elements::core::element_style_updatable_data::ElementStyleUpdatableData;
use crate::draw::types::draw_color::DrawColor;
use crate::draw::types::element_style::{ElementStyleUpdate, FillStyle, StrokeStyle};
use crate::draw::utils::string_normalization::normalize_optional_trimmed_string;
use serde_json::{Map, Value};
use thiserror::Error;

/// Immutable serial-number payload translated from Dart `SerialNumberData`.
#[derive(Clone, Debug, PartialEq)]
pub struct SerialNumberData {
    pub number: i64,
    pub color: DrawColor,
    pub fill_color: DrawColor,
    pub fill_style: FillStyle,
    pub font_size: f64,
    pub font_family: Option<String>,
    pub stroke_width: f64,
    pub stroke_style: StrokeStyle,
    pub text_element_id: Option<String>,
}

/// Patch payload for [`SerialNumberData::copy_with`].
///
/// `font_family` and `text_element_id` are tri-state:
/// - `None` keeps the current value.
/// - `Some(None)` clears the value.
/// - `Some(Some(value))` sets a new value.
#[derive(Clone, Debug, Default, PartialEq)]
pub struct SerialNumberDataPatch {
    pub number: Option<i64>,
    pub color: Option<DrawColor>,
    pub fill_color: Option<DrawColor>,
    pub fill_style: Option<FillStyle>,
    pub font_size: Option<f64>,
    pub font_family: Option<Option<String>>,
    pub stroke_width: Option<f64>,
    pub stroke_style: Option<StrokeStyle>,
    pub text_element_id: Option<Option<String>>,
}

impl SerialNumberData {
    pub const TYPE_ID_TOKEN: &'static str = "serial_number";

    /// Decodes `SerialNumberData` from JSON.
    pub fn from_json(json: &Map<String, Value>) -> Result<Self, SerialNumberDataDecodeError> {
        Ok(Self {
            number: clamp_non_negative(decode_required_i64(json, "number")?),
            color: decode_required_color(json, "color")?,
            fill_color: decode_required_color(json, "fillColor")?,
            fill_style: decode_required_fill_style(json, "fillStyle")?,
            font_size: decode_required_f64(json, "fontSize")?,
            font_family: normalize_optional_trimmed_string(
                decode_nullable_string(json, "fontFamily")?.as_deref(),
            ),
            stroke_width: decode_required_f64(json, "strokeWidth")?,
            stroke_style: decode_required_stroke_style(json, "strokeStyle")?,
            text_element_id: normalize_optional_trimmed_string(
                decode_nullable_string(json, "textElementId")?.as_deref(),
            ),
        })
    }

    /// Decodes `SerialNumberData` from a JSON value.
    pub fn from_json_value(value: &Value) -> Result<Self, SerialNumberDataDecodeError> {
        let json = value.as_object().ok_or_else(|| {
            SerialNumberDataDecodeError::invalid_field(
                "serialNumber",
                "expected JSON object payload",
            )
        })?;
        Self::from_json(json)
    }

    /// Returns the strongly typed element id token for serial-number payloads.
    pub fn type_id_token() -> ElementTypeId<SerialNumberData> {
        ElementTypeId::new(Self::TYPE_ID_TOKEN)
    }

    /// Returns an updated payload while preserving immutability.
    pub fn copy_with(&self, patch: SerialNumberDataPatch) -> Self {
        Self {
            number: clamp_non_negative(patch.number.unwrap_or(self.number)),
            color: patch.color.unwrap_or(self.color),
            fill_color: patch.fill_color.unwrap_or(self.fill_color),
            fill_style: patch.fill_style.unwrap_or(self.fill_style),
            font_size: patch.font_size.unwrap_or(self.font_size),
            font_family: resolve_font_family_update(patch.font_family, &self.font_family),
            stroke_width: patch.stroke_width.unwrap_or(self.stroke_width),
            stroke_style: patch.stroke_style.unwrap_or(self.stroke_style),
            text_element_id: patch
                .text_element_id
                .unwrap_or_else(|| self.text_element_id.clone()),
        }
    }

    /// Serializes this payload to JSON.
    pub fn to_json_map(&self) -> Map<String, Value> {
        let mut json = Map::new();
        json.insert(
            "typeId".to_string(),
            Value::String(Self::TYPE_ID_TOKEN.to_string()),
        );
        json.insert("number".to_string(), Value::from(self.number));
        json.insert(
            "color".to_string(),
            Value::from(self.color.to_argb32() as u64),
        );
        json.insert(
            "fillColor".to_string(),
            Value::from(self.fill_color.to_argb32() as u64),
        );
        json.insert(
            "fillStyle".to_string(),
            Value::String(fill_style_to_name(self.fill_style).to_string()),
        );
        json.insert("fontSize".to_string(), Value::from(self.font_size));
        json.insert(
            "fontFamily".to_string(),
            Value::String(self.font_family.clone().unwrap_or_default()),
        );
        json.insert("strokeWidth".to_string(), Value::from(self.stroke_width));
        json.insert(
            "strokeStyle".to_string(),
            Value::String(stroke_style_to_name(self.stroke_style).to_string()),
        );
        json.insert(
            "textElementId".to_string(),
            Value::String(self.text_element_id.clone().unwrap_or_default()),
        );
        json
    }
}

impl Default for SerialNumberData {
    fn default() -> Self {
        Self {
            number: ConfigDefaults::DEFAULT_SERIAL_NUMBER,
            color: ConfigDefaults::DEFAULT_COLOR,
            fill_color: ConfigDefaults::DEFAULT_FILL_COLOR,
            fill_style: ConfigDefaults::DEFAULT_FILL_STYLE,
            font_size: ConfigDefaults::DEFAULT_SERIAL_NUMBER_FONT_SIZE,
            font_family: ConfigDefaults::DEFAULT_TEXT_FONT_FAMILY.map(str::to_owned),
            stroke_width: ConfigDefaults::DEFAULT_STROKE_WIDTH,
            stroke_style: ConfigDefaults::DEFAULT_STROKE_STYLE,
            text_element_id: None,
        }
    }
}

impl ElementData for SerialNumberData {
    fn type_id(&self) -> ElementTypeId<DynElementData> {
        ElementTypeId::new(Self::TYPE_ID_TOKEN)
    }

    fn to_json(&self) -> Map<String, Value> {
        self.to_json_map()
    }
}

impl ElementStyleConfigurableData for SerialNumberData {
    fn with_element_style(&self, style: ElementStyleConfig) -> Box<DynElementData> {
        Box::new(self.copy_with(SerialNumberDataPatch {
            number: Some(style.serial_number),
            color: Some(style.color),
            fill_color: Some(style.fill_color),
            fill_style: Some(style.fill_style),
            font_size: Some(style.font_size),
            font_family: Some(style.font_family),
            stroke_width: Some(style.stroke_width),
            stroke_style: Some(style.stroke_style),
            ..SerialNumberDataPatch::default()
        }))
    }
}

impl ElementStyleUpdatableData for SerialNumberData {
    fn with_style_update(&self, update: ElementStyleUpdate) -> Box<DynElementData> {
        Box::new(self.copy_with(SerialNumberDataPatch {
            number: update.serial_number,
            color: update.color,
            fill_color: update.fill_color,
            fill_style: update.fill_style,
            font_size: update.font_size,
            font_family: update.font_family.map(Some),
            stroke_width: update.stroke_width,
            stroke_style: update.stroke_style,
            ..SerialNumberDataPatch::default()
        }))
    }
}

/// Decode failures for `SerialNumberData` JSON payloads.
#[derive(Debug, Error)]
#[error("{message}")]
pub struct SerialNumberDataDecodeError {
    message: String,
}

impl SerialNumberDataDecodeError {
    fn invalid_field(field: &str, detail: &str) -> Self {
        Self {
            message: format!("Invalid `{field}`: {detail}"),
        }
    }
}

fn clamp_non_negative(value: i64) -> i64 {
    value.max(0)
}

fn resolve_font_family_update(
    update: Option<Option<String>>,
    current: &Option<String>,
) -> Option<String> {
    match update {
        None => current.clone(),
        Some(None) => None,
        Some(Some(value)) => normalize_optional_trimmed_string(Some(value.as_str())),
    }
}

fn decode_required_color(
    json: &Map<String, Value>,
    field: &str,
) -> Result<DrawColor, SerialNumberDataDecodeError> {
    let value = json
        .get(field)
        .ok_or_else(|| SerialNumberDataDecodeError::invalid_field(field, "field is missing"))?;
    let number = value
        .as_i64()
        .or_else(|| value.as_u64().and_then(|raw| i64::try_from(raw).ok()))
        .ok_or_else(|| {
            SerialNumberDataDecodeError::invalid_field(field, "expected integer ARGB32")
        })?;
    Ok(DrawColor::new(number as u32))
}

fn decode_required_i64(
    json: &Map<String, Value>,
    field: &str,
) -> Result<i64, SerialNumberDataDecodeError> {
    let value = json
        .get(field)
        .ok_or_else(|| SerialNumberDataDecodeError::invalid_field(field, "field is missing"))?;
    value
        .as_i64()
        .or_else(|| value.as_u64().and_then(|raw| i64::try_from(raw).ok()))
        .ok_or_else(|| SerialNumberDataDecodeError::invalid_field(field, "expected integer value"))
}

fn decode_required_f64(
    json: &Map<String, Value>,
    field: &str,
) -> Result<f64, SerialNumberDataDecodeError> {
    let value = json
        .get(field)
        .ok_or_else(|| SerialNumberDataDecodeError::invalid_field(field, "field is missing"))?;
    value
        .as_f64()
        .ok_or_else(|| SerialNumberDataDecodeError::invalid_field(field, "expected numeric value"))
}

fn decode_nullable_string(
    json: &Map<String, Value>,
    field: &str,
) -> Result<Option<String>, SerialNumberDataDecodeError> {
    let Some(value) = json.get(field) else {
        return Ok(None);
    };

    if value.is_null() {
        return Ok(None);
    }

    let text = value
        .as_str()
        .ok_or_else(|| SerialNumberDataDecodeError::invalid_field(field, "expected string"))?;
    Ok(Some(text.to_owned()))
}

fn decode_required_stroke_style(
    json: &Map<String, Value>,
    field: &str,
) -> Result<StrokeStyle, SerialNumberDataDecodeError> {
    let raw = decode_required_string(json, field)?;
    stroke_style_from_name(&raw).ok_or_else(|| {
        SerialNumberDataDecodeError::invalid_field(field, "unsupported stroke style")
    })
}

fn decode_required_fill_style(
    json: &Map<String, Value>,
    field: &str,
) -> Result<FillStyle, SerialNumberDataDecodeError> {
    let raw = decode_required_string(json, field)?;
    fill_style_from_name(&raw)
        .ok_or_else(|| SerialNumberDataDecodeError::invalid_field(field, "unsupported fill style"))
}

fn decode_required_string(
    json: &Map<String, Value>,
    field: &str,
) -> Result<String, SerialNumberDataDecodeError> {
    let value = json
        .get(field)
        .ok_or_else(|| SerialNumberDataDecodeError::invalid_field(field, "field is missing"))?;
    value
        .as_str()
        .map(str::to_owned)
        .ok_or_else(|| SerialNumberDataDecodeError::invalid_field(field, "expected string value"))
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
