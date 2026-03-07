#![allow(dead_code)]

use crate::draw::config::draw_config::{ConfigDefaults, ElementStyleConfig};
use crate::draw::elements::core::element_data::{DynElementData, ElementData, ElementTypeId};
use crate::draw::elements::core::element_style_configurable_data::ElementStyleConfigurableData;
use crate::draw::elements::core::element_style_updatable_data::ElementStyleUpdatableData;
use crate::draw::types::draw_color::DrawColor;
use crate::draw::types::draw_point::DrawPoint;
use crate::draw::types::element_style::{ElementStyleUpdate, FillStyle, StrokeStyle};
use serde_json::{Map, Value};
use thiserror::Error;

/// Immutable free-draw payload translated from Dart `FreeDrawData`.
#[derive(Clone, Debug, PartialEq)]
pub struct FreeDrawData {
    /// Normalized path points in element-local space (`0..1`).
    pub points: Vec<DrawPoint>,
    pub color: DrawColor,
    pub fill_color: DrawColor,
    pub fill_style: FillStyle,
    pub stroke_width: f64,
    pub stroke_style: StrokeStyle,
}

/// Patch payload for [`FreeDrawData::copy_with`].
#[derive(Clone, Debug, Default, PartialEq)]
pub struct FreeDrawDataPatch {
    pub points: Option<Vec<DrawPoint>>,
    pub color: Option<DrawColor>,
    pub fill_color: Option<DrawColor>,
    pub fill_style: Option<FillStyle>,
    pub stroke_width: Option<f64>,
    pub stroke_style: Option<StrokeStyle>,
}

impl FreeDrawData {
    pub const TYPE_ID_TOKEN: &'static str = "free_draw";
    pub const DEFAULT_POINTS: [DrawPoint; 2] = [DrawPoint::ZERO, DrawPoint::new(1.0, 1.0)];

    /// Decodes `FreeDrawData` from JSON.
    pub fn from_json(json: &Map<String, Value>) -> Result<Self, FreeDrawDataDecodeError> {
        Ok(Self {
            points: decode_points(json.get("points"))?,
            color: decode_required_color(json, "color")?,
            fill_color: decode_required_color(json, "fillColor")?,
            stroke_width: decode_required_f64(json, "strokeWidth")?,
            stroke_style: decode_required_stroke_style(json, "strokeStyle")?,
            fill_style: decode_required_fill_style(json, "fillStyle")?,
        })
    }

    /// Decodes `FreeDrawData` from a JSON value.
    pub fn from_json_value(value: &Value) -> Result<Self, FreeDrawDataDecodeError> {
        let json = value.as_object().ok_or_else(|| {
            FreeDrawDataDecodeError::invalid_field("freeDraw", "expected JSON object payload")
        })?;
        Self::from_json(json)
    }

    /// Returns the strongly typed element id token for free draw payloads.
    pub fn type_id_token() -> ElementTypeId<FreeDrawData> {
        ElementTypeId::new(Self::TYPE_ID_TOKEN)
    }

    /// Returns an updated payload while preserving immutability.
    pub fn copy_with(&self, patch: FreeDrawDataPatch) -> Self {
        Self {
            points: patch.points.unwrap_or_else(|| self.points.clone()),
            color: patch.color.unwrap_or(self.color),
            fill_color: patch.fill_color.unwrap_or(self.fill_color),
            fill_style: patch.fill_style.unwrap_or(self.fill_style),
            stroke_width: patch.stroke_width.unwrap_or(self.stroke_width),
            stroke_style: patch.stroke_style.unwrap_or(self.stroke_style),
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
            "points".to_string(),
            Value::Array(self.points.iter().copied().map(point_to_json).collect()),
        );
        json.insert(
            "color".to_string(),
            Value::from(self.color.to_argb32() as u64),
        );
        json.insert(
            "fillColor".to_string(),
            Value::from(self.fill_color.to_argb32() as u64),
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

impl Default for FreeDrawData {
    fn default() -> Self {
        Self {
            points: Self::DEFAULT_POINTS.to_vec(),
            color: ConfigDefaults::DEFAULT_COLOR,
            fill_color: ConfigDefaults::DEFAULT_FILL_COLOR,
            fill_style: ConfigDefaults::DEFAULT_FILL_STYLE,
            stroke_width: ConfigDefaults::DEFAULT_STROKE_WIDTH,
            stroke_style: ConfigDefaults::DEFAULT_STROKE_STYLE,
        }
    }
}

impl ElementData for FreeDrawData {
    fn type_id(&self) -> ElementTypeId<DynElementData> {
        ElementTypeId::new(Self::TYPE_ID_TOKEN)
    }

    fn to_json(&self) -> Map<String, Value> {
        self.to_json_map()
    }
}

impl ElementStyleConfigurableData for FreeDrawData {
    fn with_element_style(&self, style: ElementStyleConfig) -> Box<DynElementData> {
        Box::new(self.copy_with(FreeDrawDataPatch {
            color: Some(style.color),
            fill_color: Some(style.fill_color),
            fill_style: Some(style.fill_style),
            stroke_width: Some(style.stroke_width),
            stroke_style: Some(style.stroke_style),
            ..FreeDrawDataPatch::default()
        }))
    }
}

impl ElementStyleUpdatableData for FreeDrawData {
    fn with_style_update(&self, update: ElementStyleUpdate) -> Box<DynElementData> {
        Box::new(self.copy_with(FreeDrawDataPatch {
            color: update.color,
            fill_color: update.fill_color,
            fill_style: update.fill_style,
            stroke_width: update.stroke_width,
            stroke_style: update.stroke_style,
            ..FreeDrawDataPatch::default()
        }))
    }
}

/// Decode failures for `FreeDrawData` JSON payloads.
#[derive(Debug, Error)]
#[error("{message}")]
pub struct FreeDrawDataDecodeError {
    message: String,
}

impl FreeDrawDataDecodeError {
    fn invalid_field(field: &str, detail: &str) -> Self {
        Self {
            message: format!("Invalid `{field}`: {detail}"),
        }
    }
}

fn decode_points(raw: Option<&Value>) -> Result<Vec<DrawPoint>, FreeDrawDataDecodeError> {
    let raw_points = raw.ok_or_else(|| {
        FreeDrawDataDecodeError::invalid_field("points", "free draw points must be provided")
    })?;

    let array = raw_points.as_array().ok_or_else(|| {
        FreeDrawDataDecodeError::invalid_field("points", "Free draw points must be a JSON array")
    })?;

    let mut points = Vec::with_capacity(array.len());
    for raw_point in array {
        points.push(decode_point(raw_point)?);
    }

    if points.len() < 2 {
        return Err(FreeDrawDataDecodeError::invalid_field(
            "points",
            "Free draw payload must include at least two points",
        ));
    }

    Ok(points)
}

fn decode_point(raw: &Value) -> Result<DrawPoint, FreeDrawDataDecodeError> {
    let map = raw.as_object().ok_or_else(|| {
        FreeDrawDataDecodeError::invalid_field("free draw point", "expected JSON map")
    })?;

    let x = map.get("x").and_then(Value::as_f64).ok_or_else(|| {
        FreeDrawDataDecodeError::invalid_field("free draw point", "must provide numeric x/y")
    })?;
    let y = map.get("y").and_then(Value::as_f64).ok_or_else(|| {
        FreeDrawDataDecodeError::invalid_field("free draw point", "must provide numeric x/y")
    })?;

    let pressure = match map.get("p") {
        Some(Value::Number(number)) => number.as_f64().ok_or_else(|| {
            FreeDrawDataDecodeError::invalid_field(
                "free draw point",
                "p must be numeric when provided",
            )
        })?,
        Some(_) => {
            return Err(FreeDrawDataDecodeError::invalid_field(
                "free draw point",
                "p must be numeric when provided",
            ))
        }
        None => 0.0,
    };

    Ok(DrawPoint::with_pressure_and_timestamp(x, y, pressure, 0))
}

fn decode_required_color(
    json: &Map<String, Value>,
    field: &str,
) -> Result<DrawColor, FreeDrawDataDecodeError> {
    let value = json
        .get(field)
        .ok_or_else(|| FreeDrawDataDecodeError::invalid_field(field, "field is missing"))?;
    let number = value
        .as_i64()
        .or_else(|| value.as_u64().and_then(|raw| i64::try_from(raw).ok()))
        .ok_or_else(|| FreeDrawDataDecodeError::invalid_field(field, "expected integer ARGB32"))?;
    Ok(DrawColor::new(number as u32))
}

fn decode_required_f64(
    json: &Map<String, Value>,
    field: &str,
) -> Result<f64, FreeDrawDataDecodeError> {
    let value = json
        .get(field)
        .ok_or_else(|| FreeDrawDataDecodeError::invalid_field(field, "field is missing"))?;
    value
        .as_f64()
        .ok_or_else(|| FreeDrawDataDecodeError::invalid_field(field, "expected numeric value"))
}

fn decode_required_stroke_style(
    json: &Map<String, Value>,
    field: &str,
) -> Result<StrokeStyle, FreeDrawDataDecodeError> {
    let raw = decode_required_string(json, field)?;
    stroke_style_from_name(&raw)
        .ok_or_else(|| FreeDrawDataDecodeError::invalid_field(field, "unsupported stroke style"))
}

fn decode_required_fill_style(
    json: &Map<String, Value>,
    field: &str,
) -> Result<FillStyle, FreeDrawDataDecodeError> {
    let raw = decode_required_string(json, field)?;
    fill_style_from_name(&raw)
        .ok_or_else(|| FreeDrawDataDecodeError::invalid_field(field, "unsupported fill style"))
}

fn decode_required_string(
    json: &Map<String, Value>,
    field: &str,
) -> Result<String, FreeDrawDataDecodeError> {
    let value = json
        .get(field)
        .ok_or_else(|| FreeDrawDataDecodeError::invalid_field(field, "field is missing"))?;
    value
        .as_str()
        .map(str::to_owned)
        .ok_or_else(|| FreeDrawDataDecodeError::invalid_field(field, "expected string value"))
}

fn point_to_json(point: DrawPoint) -> Value {
    let mut json = Map::new();
    json.insert("x".to_string(), Value::from(point.x));
    json.insert("y".to_string(), Value::from(point.y));
    if point.has_pressure() {
        json.insert("p".to_string(), Value::from(point.pressure));
    }
    Value::Object(json)
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
