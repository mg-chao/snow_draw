#![allow(dead_code)]

use crate::draw::config::draw_config::{ConfigDefaults, ElementStyleConfig};
use crate::draw::elements::core::element_data::{DynElementData, ElementData, ElementTypeId};
use crate::draw::elements::core::element_style_configurable_data::ElementStyleConfigurableData;
use crate::draw::elements::core::element_style_updatable_data::ElementStyleUpdatableData;
use crate::draw::types::draw_color::DrawColor;
use crate::draw::types::element_style::{
    ElementStyleUpdate, FillStyle, TextHorizontalAlign, TextVerticalAlign,
};
use crate::draw::utils::string_normalization::normalize_optional_trimmed_string;
use serde_json::{Map, Value};
use thiserror::Error;

/// Immutable text payload translated from Dart `TextData`.
#[derive(Clone, Debug, PartialEq)]
pub struct TextData {
    pub text: String,
    pub color: DrawColor,
    pub font_size: f64,
    pub font_family: Option<String>,
    pub horizontal_align: TextHorizontalAlign,
    pub vertical_align: TextVerticalAlign,
    pub fill_color: DrawColor,
    pub fill_style: FillStyle,
    pub stroke_color: DrawColor,
    pub stroke_width: f64,
    pub corner_radius: f64,
    pub auto_resize: bool,
}

/// Patch payload for [`TextData::copy_with`].
///
/// `font_family` is tri-state:
/// - `None` keeps the current value.
/// - `Some(None)` clears the value.
/// - `Some(Some(value))` sets a new value.
#[derive(Clone, Debug, Default, PartialEq)]
pub struct TextDataPatch {
    pub text: Option<String>,
    pub color: Option<DrawColor>,
    pub font_size: Option<f64>,
    pub font_family: Option<Option<String>>,
    pub horizontal_align: Option<TextHorizontalAlign>,
    pub vertical_align: Option<TextVerticalAlign>,
    pub fill_color: Option<DrawColor>,
    pub fill_style: Option<FillStyle>,
    pub stroke_color: Option<DrawColor>,
    pub stroke_width: Option<f64>,
    pub corner_radius: Option<f64>,
    pub auto_resize: Option<bool>,
}

impl TextData {
    pub const TYPE_ID_TOKEN: &'static str = "text";

    /// Decodes `TextData` from JSON.
    pub fn from_json(json: &Map<String, Value>) -> Result<Self, TextDataDecodeError> {
        Ok(Self {
            text: decode_required_string(json, "text")?,
            color: decode_required_color(json, "color")?,
            font_size: decode_required_f64(json, "fontSize")?,
            font_family: normalize_optional_trimmed_string(
                decode_nullable_string(json, "fontFamily")?.as_deref(),
            ),
            horizontal_align: decode_required_horizontal_align(json, "horizontalAlign")?,
            vertical_align: decode_required_vertical_align(json, "verticalAlign")?,
            fill_color: decode_required_color(json, "fillColor")?,
            fill_style: decode_required_fill_style(json, "fillStyle")?,
            stroke_color: decode_required_color(json, "strokeColor")?,
            stroke_width: decode_required_f64(json, "strokeWidth")?,
            corner_radius: decode_required_f64(json, "cornerRadius")?,
            auto_resize: decode_required_bool(json, "autoResize")?,
        })
    }

    /// Decodes `TextData` from a JSON value.
    pub fn from_json_value(value: &Value) -> Result<Self, TextDataDecodeError> {
        let json = value.as_object().ok_or_else(|| {
            TextDataDecodeError::invalid_field("text", "expected JSON object payload")
        })?;
        Self::from_json(json)
    }

    /// Returns the strongly typed element id token for text payloads.
    pub fn type_id_token() -> ElementTypeId<TextData> {
        ElementTypeId::new(Self::TYPE_ID_TOKEN)
    }

    /// Returns an updated payload while preserving immutability.
    pub fn copy_with(&self, patch: TextDataPatch) -> Self {
        Self {
            text: patch.text.unwrap_or_else(|| self.text.clone()),
            color: patch.color.unwrap_or(self.color),
            font_size: patch.font_size.unwrap_or(self.font_size),
            font_family: resolve_font_family_update(patch.font_family, &self.font_family),
            horizontal_align: patch.horizontal_align.unwrap_or(self.horizontal_align),
            vertical_align: patch.vertical_align.unwrap_or(self.vertical_align),
            fill_color: patch.fill_color.unwrap_or(self.fill_color),
            fill_style: patch.fill_style.unwrap_or(self.fill_style),
            stroke_color: patch.stroke_color.unwrap_or(self.stroke_color),
            stroke_width: patch.stroke_width.unwrap_or(self.stroke_width),
            corner_radius: patch.corner_radius.unwrap_or(self.corner_radius),
            auto_resize: patch.auto_resize.unwrap_or(self.auto_resize),
        }
    }

    /// Serializes this payload to JSON.
    pub fn to_json_map(&self) -> Map<String, Value> {
        let mut json = Map::new();
        json.insert(
            "typeId".to_string(),
            Value::String(Self::TYPE_ID_TOKEN.to_string()),
        );
        json.insert("text".to_string(), Value::String(self.text.clone()));
        json.insert(
            "color".to_string(),
            Value::from(self.color.to_argb32() as u64),
        );
        json.insert("fontSize".to_string(), Value::from(self.font_size));
        json.insert(
            "fontFamily".to_string(),
            Value::String(self.font_family.clone().unwrap_or_default()),
        );
        json.insert(
            "horizontalAlign".to_string(),
            Value::String(text_horizontal_align_to_name(self.horizontal_align).to_string()),
        );
        json.insert(
            "verticalAlign".to_string(),
            Value::String(text_vertical_align_to_name(self.vertical_align).to_string()),
        );
        json.insert(
            "fillColor".to_string(),
            Value::from(self.fill_color.to_argb32() as u64),
        );
        json.insert(
            "fillStyle".to_string(),
            Value::String(fill_style_to_name(self.fill_style).to_string()),
        );
        json.insert(
            "strokeColor".to_string(),
            Value::from(self.stroke_color.to_argb32() as u64),
        );
        json.insert("strokeWidth".to_string(), Value::from(self.stroke_width));
        json.insert("cornerRadius".to_string(), Value::from(self.corner_radius));
        json.insert("autoResize".to_string(), Value::Bool(self.auto_resize));
        json
    }
}

impl Default for TextData {
    fn default() -> Self {
        Self {
            text: String::new(),
            color: ConfigDefaults::DEFAULT_COLOR,
            font_size: ConfigDefaults::DEFAULT_TEXT_FONT_SIZE,
            font_family: ConfigDefaults::DEFAULT_TEXT_FONT_FAMILY.map(str::to_owned),
            horizontal_align: ConfigDefaults::DEFAULT_TEXT_HORIZONTAL_ALIGN,
            vertical_align: ConfigDefaults::DEFAULT_TEXT_VERTICAL_ALIGN,
            fill_color: ConfigDefaults::DEFAULT_FILL_COLOR,
            fill_style: ConfigDefaults::DEFAULT_FILL_STYLE,
            stroke_color: ConfigDefaults::DEFAULT_TEXT_STROKE_COLOR,
            stroke_width: ConfigDefaults::DEFAULT_TEXT_STROKE_WIDTH,
            corner_radius: ConfigDefaults::DEFAULT_TEXT_CORNER_RADIUS,
            auto_resize: ConfigDefaults::DEFAULT_TEXT_AUTO_RESIZE,
        }
    }
}

impl ElementData for TextData {
    fn type_id(&self) -> ElementTypeId<DynElementData> {
        ElementTypeId::new(Self::TYPE_ID_TOKEN)
    }

    fn to_json(&self) -> Map<String, Value> {
        self.to_json_map()
    }
}

impl ElementStyleConfigurableData for TextData {
    fn with_element_style(&self, style: ElementStyleConfig) -> Box<DynElementData> {
        Box::new(self.copy_with(TextDataPatch {
            color: Some(style.color),
            font_size: Some(style.font_size),
            font_family: Some(style.font_family),
            horizontal_align: Some(style.text_align),
            vertical_align: Some(style.vertical_align),
            fill_color: Some(style.fill_color),
            fill_style: Some(style.fill_style),
            stroke_color: Some(style.text_stroke_color),
            stroke_width: Some(style.text_stroke_width),
            corner_radius: Some(style.corner_radius),
            ..TextDataPatch::default()
        }))
    }
}

impl ElementStyleUpdatableData for TextData {
    fn with_style_update(&self, update: ElementStyleUpdate) -> Box<DynElementData> {
        Box::new(self.copy_with(TextDataPatch {
            color: update.color,
            font_size: update.font_size,
            font_family: update.font_family.map(Some),
            horizontal_align: update.text_align,
            vertical_align: update.vertical_align,
            fill_color: update.fill_color,
            fill_style: update.fill_style,
            stroke_color: update.text_stroke_color,
            stroke_width: update.text_stroke_width,
            corner_radius: update.corner_radius,
            ..TextDataPatch::default()
        }))
    }
}

/// Decode failures for `TextData` JSON payloads.
#[derive(Debug, Error)]
#[error("{message}")]
pub struct TextDataDecodeError {
    message: String,
}

impl TextDataDecodeError {
    fn invalid_field(field: &str, detail: &str) -> Self {
        Self {
            message: format!("Invalid `{field}`: {detail}"),
        }
    }
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
) -> Result<DrawColor, TextDataDecodeError> {
    let value = json
        .get(field)
        .ok_or_else(|| TextDataDecodeError::invalid_field(field, "field is missing"))?;
    let number = value
        .as_i64()
        .or_else(|| value.as_u64().and_then(|raw| i64::try_from(raw).ok()))
        .ok_or_else(|| TextDataDecodeError::invalid_field(field, "expected integer ARGB32"))?;
    Ok(DrawColor::new(number as u32))
}

fn decode_required_f64(json: &Map<String, Value>, field: &str) -> Result<f64, TextDataDecodeError> {
    let value = json
        .get(field)
        .ok_or_else(|| TextDataDecodeError::invalid_field(field, "field is missing"))?;
    value
        .as_f64()
        .ok_or_else(|| TextDataDecodeError::invalid_field(field, "expected numeric value"))
}

fn decode_required_bool(
    json: &Map<String, Value>,
    field: &str,
) -> Result<bool, TextDataDecodeError> {
    let value = json
        .get(field)
        .ok_or_else(|| TextDataDecodeError::invalid_field(field, "field is missing"))?;
    value
        .as_bool()
        .ok_or_else(|| TextDataDecodeError::invalid_field(field, "expected bool value"))
}

fn decode_required_string(
    json: &Map<String, Value>,
    field: &str,
) -> Result<String, TextDataDecodeError> {
    let value = json
        .get(field)
        .ok_or_else(|| TextDataDecodeError::invalid_field(field, "field is missing"))?;
    value
        .as_str()
        .map(str::to_owned)
        .ok_or_else(|| TextDataDecodeError::invalid_field(field, "expected string value"))
}

fn decode_nullable_string(
    json: &Map<String, Value>,
    field: &str,
) -> Result<Option<String>, TextDataDecodeError> {
    let Some(value) = json.get(field) else {
        return Ok(None);
    };

    if value.is_null() {
        return Ok(None);
    }

    let text = value
        .as_str()
        .ok_or_else(|| TextDataDecodeError::invalid_field(field, "expected string value"))?;
    Ok(Some(text.to_owned()))
}

fn decode_required_fill_style(
    json: &Map<String, Value>,
    field: &str,
) -> Result<FillStyle, TextDataDecodeError> {
    let raw = decode_required_string(json, field)?;
    fill_style_from_name(&raw)
        .ok_or_else(|| TextDataDecodeError::invalid_field(field, "unsupported fill style"))
}

fn decode_required_horizontal_align(
    json: &Map<String, Value>,
    field: &str,
) -> Result<TextHorizontalAlign, TextDataDecodeError> {
    let raw = decode_required_string(json, field)?;
    text_horizontal_align_from_name(&raw)
        .ok_or_else(|| TextDataDecodeError::invalid_field(field, "unsupported text alignment"))
}

fn decode_required_vertical_align(
    json: &Map<String, Value>,
    field: &str,
) -> Result<TextVerticalAlign, TextDataDecodeError> {
    let raw = decode_required_string(json, field)?;
    text_vertical_align_from_name(&raw)
        .ok_or_else(|| TextDataDecodeError::invalid_field(field, "unsupported vertical alignment"))
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

fn text_horizontal_align_to_name(align: TextHorizontalAlign) -> &'static str {
    match align {
        TextHorizontalAlign::Left => "left",
        TextHorizontalAlign::Center => "center",
        TextHorizontalAlign::Right => "right",
    }
}

fn text_horizontal_align_from_name(raw: &str) -> Option<TextHorizontalAlign> {
    match raw {
        "left" => Some(TextHorizontalAlign::Left),
        "center" => Some(TextHorizontalAlign::Center),
        "right" => Some(TextHorizontalAlign::Right),
        _ => None,
    }
}

fn text_vertical_align_to_name(align: TextVerticalAlign) -> &'static str {
    match align {
        TextVerticalAlign::Top => "top",
        TextVerticalAlign::Center => "center",
        TextVerticalAlign::Bottom => "bottom",
    }
}

fn text_vertical_align_from_name(raw: &str) -> Option<TextVerticalAlign> {
    match raw {
        "top" => Some(TextVerticalAlign::Top),
        "center" => Some(TextVerticalAlign::Center),
        "bottom" => Some(TextVerticalAlign::Bottom),
        _ => None,
    }
}
