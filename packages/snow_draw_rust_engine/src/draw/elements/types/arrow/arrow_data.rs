#![allow(dead_code)]

use crate::draw::config::draw_config::{ConfigDefaults, ElementStyleConfig};
use crate::draw::elements::core::element_data::{DynElementData, ElementData, ElementTypeId};
use crate::draw::elements::core::element_style_configurable_data::ElementStyleConfigurableData;
use crate::draw::elements::core::element_style_updatable_data::ElementStyleUpdatableData;
use crate::draw::types::draw_color::DrawColor;
use crate::draw::types::draw_point::DrawPoint;
use crate::draw::types::element_style::{
    ArrowType, ArrowheadStyle, ElementStyleUpdate, StrokeStyle,
};
use serde_json::{Map, Value};
use thiserror::Error;

/// Arrow endpoint binding mode.
#[derive(Clone, Copy, Debug, PartialEq, Eq, Hash)]
pub enum ArrowBindingMode {
    Inside,
    Orbit,
}

/// Arrow endpoint binding metadata.
#[derive(Clone, Debug, PartialEq, Hash)]
pub struct ArrowBinding {
    pub element_id: String,
    pub anchor: DrawPoint,
    pub mode: ArrowBindingMode,
}

impl ArrowBinding {
    /// Creates a new binding and clamps anchor coordinates to `[0, 1]`.
    pub fn new(element_id: impl Into<String>, anchor: DrawPoint, mode: ArrowBindingMode) -> Self {
        Self {
            element_id: element_id.into(),
            anchor: DrawPoint::new(clamp01(anchor.x), clamp01(anchor.y)),
            mode,
        }
    }

    /// Decodes a binding from JSON.
    pub fn from_json(json: &Map<String, Value>) -> Result<Self, ArrowDataDecodeError> {
        let element_id = decode_required_string(json, "elementId")?;
        let anchor = decode_required_point(json, "anchor")?;
        let mode = decode_required_binding_mode(json, "mode")?;
        Ok(Self::new(element_id, anchor, mode))
    }

    /// Encodes this binding to JSON.
    pub fn to_json(&self) -> Map<String, Value> {
        let mut json = Map::new();
        json.insert(
            "elementId".to_string(),
            Value::String(self.element_id.clone()),
        );
        json.insert("anchor".to_string(), point_to_json(self.anchor));
        json.insert(
            "mode".to_string(),
            Value::String(binding_mode_to_name(self.mode).to_string()),
        );
        json
    }
}

/// Fixed segment metadata for elbow arrows.
#[derive(Clone, Debug, PartialEq, Hash)]
pub struct ElbowFixedSegment {
    pub index: usize,
    pub start: DrawPoint,
    pub end: DrawPoint,
}

impl ElbowFixedSegment {
    /// Decodes an elbow fixed segment from JSON.
    pub fn from_json(json: &Map<String, Value>) -> Result<Self, ArrowDataDecodeError> {
        let index_raw = decode_required_i64(json, "index")?;
        if index_raw < 0 {
            return Err(ArrowDataDecodeError::invalid_field(
                "index",
                "must be non-negative",
            ));
        }
        let start = decode_required_point(json, "start")?;
        let end = decode_required_point(json, "end")?;
        Ok(Self {
            index: index_raw as usize,
            start,
            end,
        })
    }

    /// Encodes an elbow fixed segment to JSON.
    pub fn to_json(&self) -> Map<String, Value> {
        let mut json = Map::new();
        json.insert("index".to_string(), Value::from(self.index as u64));
        json.insert("start".to_string(), point_to_json(self.start));
        json.insert("end".to_string(), point_to_json(self.end));
        json
    }
}

/// Nullable field update state used by [`ArrowDataPatch`].
///
/// Mirrors Dart's `ArrowLikeData.unset` sentinel:
/// - [`NullableField::Unset`] keeps the current value.
/// - [`NullableField::Null`] clears the nullable field.
/// - [`NullableField::Value`] sets a new value.
#[derive(Clone, Debug, PartialEq)]
pub enum NullableField<T> {
    Unset,
    Null,
    Value(T),
}

impl<T> Default for NullableField<T> {
    fn default() -> Self {
        Self::Unset
    }
}

/// Immutable arrow payload translated from Dart `ArrowData`.
#[derive(Clone, Debug, PartialEq)]
pub struct ArrowData {
    /// Normalized control points in element-local space (`0..1`).
    pub points: Vec<DrawPoint>,
    pub color: DrawColor,
    pub stroke_width: f64,
    pub stroke_style: StrokeStyle,
    pub arrow_type: ArrowType,
    pub start_arrowhead: ArrowheadStyle,
    pub end_arrowhead: ArrowheadStyle,
    pub start_binding: Option<ArrowBinding>,
    pub end_binding: Option<ArrowBinding>,
    pub fixed_segments: Option<Vec<ElbowFixedSegment>>,
    pub start_is_special: Option<bool>,
    pub end_is_special: Option<bool>,
}

/// Patch payload for [`ArrowData::copy_with`].
#[derive(Clone, Debug, Default, PartialEq)]
pub struct ArrowDataPatch {
    pub points: Option<Vec<DrawPoint>>,
    pub color: Option<DrawColor>,
    pub stroke_width: Option<f64>,
    pub stroke_style: Option<StrokeStyle>,
    pub arrow_type: Option<ArrowType>,
    pub start_arrowhead: Option<ArrowheadStyle>,
    pub end_arrowhead: Option<ArrowheadStyle>,
    pub start_binding: NullableField<ArrowBinding>,
    pub end_binding: NullableField<ArrowBinding>,
    pub fixed_segments: NullableField<Vec<ElbowFixedSegment>>,
    pub start_is_special: NullableField<bool>,
    pub end_is_special: NullableField<bool>,
}

impl ArrowData {
    pub const TYPE_ID_TOKEN: &'static str = "arrow";
    pub const DEFAULT_POINTS: [DrawPoint; 2] = [DrawPoint::ZERO, DrawPoint::new(1.0, 1.0)];

    /// Decodes `ArrowData` from JSON.
    pub fn from_json(json: &Map<String, Value>) -> Result<Self, ArrowDataDecodeError> {
        Ok(Self {
            points: decode_required_points(json, "points")?,
            color: decode_required_color(json, "color")?,
            stroke_width: decode_required_f64(json, "strokeWidth")?,
            stroke_style: decode_required_stroke_style(json, "strokeStyle")?,
            arrow_type: decode_required_arrow_type(json, "arrowType")?,
            start_arrowhead: decode_required_arrowhead_style(json, "startArrowhead")?,
            end_arrowhead: decode_required_arrowhead_style(json, "endArrowhead")?,
            start_binding: decode_optional_binding(json, "startBinding")?,
            end_binding: decode_optional_binding(json, "endBinding")?,
            fixed_segments: decode_optional_fixed_segments(json, "fixedSegments")?,
            start_is_special: decode_optional_bool(json, "startIsSpecial")?,
            end_is_special: decode_optional_bool(json, "endIsSpecial")?,
        })
    }

    /// Decodes `ArrowData` from a JSON value.
    pub fn from_json_value(value: &Value) -> Result<Self, ArrowDataDecodeError> {
        let json = value.as_object().ok_or_else(|| {
            ArrowDataDecodeError::invalid_field("arrow", "expected JSON object payload")
        })?;
        Self::from_json(json)
    }

    /// Returns the strongly typed element id token for arrow payloads.
    pub fn type_id_token() -> ElementTypeId<ArrowData> {
        ElementTypeId::new(Self::TYPE_ID_TOKEN)
    }

    /// Returns an updated payload while preserving immutability.
    pub fn copy_with(&self, patch: ArrowDataPatch) -> Self {
        Self {
            points: patch.points.unwrap_or_else(|| self.points.clone()),
            color: patch.color.unwrap_or(self.color),
            stroke_width: patch.stroke_width.unwrap_or(self.stroke_width),
            stroke_style: patch.stroke_style.unwrap_or(self.stroke_style),
            arrow_type: patch.arrow_type.unwrap_or(self.arrow_type),
            start_arrowhead: patch.start_arrowhead.unwrap_or(self.start_arrowhead),
            end_arrowhead: patch.end_arrowhead.unwrap_or(self.end_arrowhead),
            start_binding: resolve_nullable_update(patch.start_binding, &self.start_binding),
            end_binding: resolve_nullable_update(patch.end_binding, &self.end_binding),
            fixed_segments: normalize_fixed_segments(resolve_nullable_update(
                patch.fixed_segments,
                &self.fixed_segments,
            )),
            start_is_special: resolve_nullable_update(
                patch.start_is_special,
                &self.start_is_special,
            ),
            end_is_special: resolve_nullable_update(patch.end_is_special, &self.end_is_special),
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
        json.insert("strokeWidth".to_string(), Value::from(self.stroke_width));
        json.insert(
            "strokeStyle".to_string(),
            Value::String(stroke_style_to_name(self.stroke_style).to_string()),
        );
        json.insert(
            "arrowType".to_string(),
            Value::String(arrow_type_to_name(self.arrow_type).to_string()),
        );
        json.insert(
            "startArrowhead".to_string(),
            Value::String(arrowhead_style_to_name(self.start_arrowhead).to_string()),
        );
        json.insert(
            "endArrowhead".to_string(),
            Value::String(arrowhead_style_to_name(self.end_arrowhead).to_string()),
        );
        json.insert(
            "startBinding".to_string(),
            option_binding_to_json(self.start_binding.as_ref()),
        );
        json.insert(
            "endBinding".to_string(),
            option_binding_to_json(self.end_binding.as_ref()),
        );
        json.insert(
            "fixedSegments".to_string(),
            option_fixed_segments_to_json(self.fixed_segments.as_deref()),
        );
        json.insert(
            "startIsSpecial".to_string(),
            option_bool_to_json(self.start_is_special),
        );
        json.insert(
            "endIsSpecial".to_string(),
            option_bool_to_json(self.end_is_special),
        );
        json
    }
}

impl Default for ArrowData {
    fn default() -> Self {
        Self {
            points: Self::DEFAULT_POINTS.to_vec(),
            color: ConfigDefaults::DEFAULT_COLOR,
            stroke_width: ConfigDefaults::DEFAULT_STROKE_WIDTH,
            stroke_style: ConfigDefaults::DEFAULT_STROKE_STYLE,
            arrow_type: ConfigDefaults::DEFAULT_ARROW_TYPE,
            start_arrowhead: ConfigDefaults::DEFAULT_START_ARROWHEAD,
            end_arrowhead: ConfigDefaults::DEFAULT_END_ARROWHEAD,
            start_binding: None,
            end_binding: None,
            fixed_segments: None,
            start_is_special: None,
            end_is_special: None,
        }
    }
}

impl ElementData for ArrowData {
    fn type_id(&self) -> ElementTypeId<DynElementData> {
        ElementTypeId::new(Self::TYPE_ID_TOKEN)
    }

    fn to_json(&self) -> Map<String, Value> {
        self.to_json_map()
    }
}

impl ElementStyleConfigurableData for ArrowData {
    fn with_element_style(&self, style: ElementStyleConfig) -> Box<DynElementData> {
        Box::new(self.copy_with(ArrowDataPatch {
            color: Some(style.color),
            stroke_width: Some(style.stroke_width),
            stroke_style: Some(style.stroke_style),
            arrow_type: Some(style.arrow_type),
            start_arrowhead: Some(style.start_arrowhead),
            end_arrowhead: Some(style.end_arrowhead),
            ..ArrowDataPatch::default()
        }))
    }
}

impl ElementStyleUpdatableData for ArrowData {
    fn with_style_update(&self, update: ElementStyleUpdate) -> Box<DynElementData> {
        Box::new(self.copy_with(ArrowDataPatch {
            color: update.color,
            stroke_width: Some(update.stroke_width.unwrap_or(self.stroke_width)),
            stroke_style: update.stroke_style,
            arrow_type: update.arrow_type,
            start_arrowhead: update.start_arrowhead,
            end_arrowhead: update.end_arrowhead,
            ..ArrowDataPatch::default()
        }))
    }
}

/// Decode failures for `ArrowData` JSON payloads.
#[derive(Debug, Error)]
#[error("{message}")]
pub struct ArrowDataDecodeError {
    message: String,
}

impl ArrowDataDecodeError {
    fn invalid_field(field: &str, detail: &str) -> Self {
        Self {
            message: format!("Invalid `{field}`: {detail}"),
        }
    }
}

fn resolve_nullable_update<T: Clone>(update: NullableField<T>, current: &Option<T>) -> Option<T> {
    match update {
        NullableField::Unset => current.clone(),
        NullableField::Null => None,
        NullableField::Value(value) => Some(value),
    }
}

fn normalize_fixed_segments(
    segments: Option<Vec<ElbowFixedSegment>>,
) -> Option<Vec<ElbowFixedSegment>> {
    match segments {
        Some(values) if values.is_empty() => None,
        other => other,
    }
}

fn decode_required_points(
    json: &Map<String, Value>,
    field: &str,
) -> Result<Vec<DrawPoint>, ArrowDataDecodeError> {
    let value = json
        .get(field)
        .ok_or_else(|| ArrowDataDecodeError::invalid_field(field, "field is missing"))?;
    let array = value
        .as_array()
        .ok_or_else(|| ArrowDataDecodeError::invalid_field(field, "expected JSON array"))?;
    let mut points = Vec::with_capacity(array.len());
    for entry in array {
        let map = entry.as_object().ok_or_else(|| {
            ArrowDataDecodeError::invalid_field(field, "point entry must be object")
        })?;
        let x = decode_required_f64(map, "x")?;
        let y = decode_required_f64(map, "y")?;
        points.push(DrawPoint::new(x, y));
    }
    if points.len() < 2 {
        return Err(ArrowDataDecodeError::invalid_field(
            field,
            "must include at least two points",
        ));
    }
    Ok(points)
}

fn decode_required_color(
    json: &Map<String, Value>,
    field: &str,
) -> Result<DrawColor, ArrowDataDecodeError> {
    let value = json
        .get(field)
        .ok_or_else(|| ArrowDataDecodeError::invalid_field(field, "field is missing"))?;
    let number = value
        .as_i64()
        .or_else(|| value.as_u64().and_then(|raw| i64::try_from(raw).ok()))
        .ok_or_else(|| ArrowDataDecodeError::invalid_field(field, "expected integer ARGB32"))?;
    Ok(DrawColor::new(number as u32))
}

fn decode_required_f64(
    json: &Map<String, Value>,
    field: &str,
) -> Result<f64, ArrowDataDecodeError> {
    let value = json
        .get(field)
        .ok_or_else(|| ArrowDataDecodeError::invalid_field(field, "field is missing"))?;
    value
        .as_f64()
        .ok_or_else(|| ArrowDataDecodeError::invalid_field(field, "expected numeric value"))
}

fn decode_required_i64(
    json: &Map<String, Value>,
    field: &str,
) -> Result<i64, ArrowDataDecodeError> {
    let value = json
        .get(field)
        .ok_or_else(|| ArrowDataDecodeError::invalid_field(field, "field is missing"))?;
    value
        .as_i64()
        .ok_or_else(|| ArrowDataDecodeError::invalid_field(field, "expected integer value"))
}

fn decode_required_string(
    json: &Map<String, Value>,
    field: &str,
) -> Result<String, ArrowDataDecodeError> {
    let value = json
        .get(field)
        .ok_or_else(|| ArrowDataDecodeError::invalid_field(field, "field is missing"))?;
    value
        .as_str()
        .map(str::to_owned)
        .ok_or_else(|| ArrowDataDecodeError::invalid_field(field, "expected string value"))
}

fn decode_required_point(
    json: &Map<String, Value>,
    field: &str,
) -> Result<DrawPoint, ArrowDataDecodeError> {
    let value = json
        .get(field)
        .ok_or_else(|| ArrowDataDecodeError::invalid_field(field, "field is missing"))?;
    let point = value
        .as_object()
        .ok_or_else(|| ArrowDataDecodeError::invalid_field(field, "expected point object"))?;
    let x = decode_required_f64(point, "x")?;
    let y = decode_required_f64(point, "y")?;
    Ok(DrawPoint::new(x, y))
}

fn decode_optional_bool(
    json: &Map<String, Value>,
    field: &str,
) -> Result<Option<bool>, ArrowDataDecodeError> {
    let Some(value) = json.get(field) else {
        return Ok(None);
    };
    if value.is_null() {
        return Ok(None);
    }
    let flag = value
        .as_bool()
        .ok_or_else(|| ArrowDataDecodeError::invalid_field(field, "expected bool or null"))?;
    Ok(Some(flag))
}

fn decode_optional_binding(
    json: &Map<String, Value>,
    field: &str,
) -> Result<Option<ArrowBinding>, ArrowDataDecodeError> {
    let Some(value) = json.get(field) else {
        return Ok(None);
    };
    if value.is_null() {
        return Ok(None);
    }
    let map = value
        .as_object()
        .ok_or_else(|| ArrowDataDecodeError::invalid_field(field, "expected object or null"))?;
    Ok(Some(ArrowBinding::from_json(map)?))
}

fn decode_optional_fixed_segments(
    json: &Map<String, Value>,
    field: &str,
) -> Result<Option<Vec<ElbowFixedSegment>>, ArrowDataDecodeError> {
    let Some(value) = json.get(field) else {
        return Ok(None);
    };
    if value.is_null() {
        return Ok(None);
    }
    let array = value
        .as_array()
        .ok_or_else(|| ArrowDataDecodeError::invalid_field(field, "expected array or null"))?;
    let mut segments = Vec::with_capacity(array.len());
    for entry in array {
        let map = entry.as_object().ok_or_else(|| {
            ArrowDataDecodeError::invalid_field(field, "segment entry must be object")
        })?;
        segments.push(ElbowFixedSegment::from_json(map)?);
    }
    Ok(normalize_fixed_segments(Some(segments)))
}

fn decode_required_stroke_style(
    json: &Map<String, Value>,
    field: &str,
) -> Result<StrokeStyle, ArrowDataDecodeError> {
    let raw = decode_required_string(json, field)?;
    stroke_style_from_name(&raw)
        .ok_or_else(|| ArrowDataDecodeError::invalid_field(field, "unsupported stroke style value"))
}

fn decode_required_arrow_type(
    json: &Map<String, Value>,
    field: &str,
) -> Result<ArrowType, ArrowDataDecodeError> {
    let raw = decode_required_string(json, field)?;
    arrow_type_from_name(&raw)
        .ok_or_else(|| ArrowDataDecodeError::invalid_field(field, "unsupported arrow type value"))
}

fn decode_required_arrowhead_style(
    json: &Map<String, Value>,
    field: &str,
) -> Result<ArrowheadStyle, ArrowDataDecodeError> {
    let raw = decode_required_string(json, field)?;
    arrowhead_style_from_name(&raw).ok_or_else(|| {
        ArrowDataDecodeError::invalid_field(field, "unsupported arrowhead style value")
    })
}

fn decode_required_binding_mode(
    json: &Map<String, Value>,
    field: &str,
) -> Result<ArrowBindingMode, ArrowDataDecodeError> {
    let raw = decode_required_string(json, field)?;
    binding_mode_from_name(&raw)
        .ok_or_else(|| ArrowDataDecodeError::invalid_field(field, "unsupported binding mode value"))
}

fn point_to_json(point: DrawPoint) -> Value {
    let mut json = Map::new();
    json.insert("x".to_string(), Value::from(point.x));
    json.insert("y".to_string(), Value::from(point.y));
    Value::Object(json)
}

fn option_binding_to_json(binding: Option<&ArrowBinding>) -> Value {
    binding
        .map(|value| Value::Object(value.to_json()))
        .unwrap_or(Value::Null)
}

fn option_fixed_segments_to_json(segments: Option<&[ElbowFixedSegment]>) -> Value {
    let Some(values) = segments else {
        return Value::Null;
    };
    if values.is_empty() {
        return Value::Null;
    }
    Value::Array(
        values
            .iter()
            .map(|segment| Value::Object(segment.to_json()))
            .collect(),
    )
}

fn option_bool_to_json(value: Option<bool>) -> Value {
    value.map(Value::Bool).unwrap_or(Value::Null)
}

fn clamp01(value: f64) -> f64 {
    value.clamp(0.0, 1.0)
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

fn arrow_type_to_name(arrow_type: ArrowType) -> &'static str {
    match arrow_type {
        ArrowType::Straight => "straight",
        ArrowType::Curved => "curved",
        ArrowType::Elbow => "elbow",
    }
}

fn arrow_type_from_name(raw: &str) -> Option<ArrowType> {
    match raw {
        "straight" => Some(ArrowType::Straight),
        "curved" => Some(ArrowType::Curved),
        "elbow" => Some(ArrowType::Elbow),
        _ => None,
    }
}

fn arrowhead_style_to_name(style: ArrowheadStyle) -> &'static str {
    match style {
        ArrowheadStyle::None => "none",
        ArrowheadStyle::Standard => "standard",
        ArrowheadStyle::Triangle => "triangle",
        ArrowheadStyle::Square => "square",
        ArrowheadStyle::Circle => "circle",
        ArrowheadStyle::Diamond => "diamond",
        ArrowheadStyle::InvertedTriangle => "invertedTriangle",
        ArrowheadStyle::VerticalLine => "verticalLine",
    }
}

fn arrowhead_style_from_name(raw: &str) -> Option<ArrowheadStyle> {
    match raw {
        "none" => Some(ArrowheadStyle::None),
        "standard" => Some(ArrowheadStyle::Standard),
        "triangle" => Some(ArrowheadStyle::Triangle),
        "square" => Some(ArrowheadStyle::Square),
        "circle" => Some(ArrowheadStyle::Circle),
        "diamond" => Some(ArrowheadStyle::Diamond),
        "invertedTriangle" => Some(ArrowheadStyle::InvertedTriangle),
        "verticalLine" => Some(ArrowheadStyle::VerticalLine),
        _ => None,
    }
}

fn binding_mode_to_name(mode: ArrowBindingMode) -> &'static str {
    match mode {
        ArrowBindingMode::Inside => "inside",
        ArrowBindingMode::Orbit => "orbit",
    }
}

fn binding_mode_from_name(raw: &str) -> Option<ArrowBindingMode> {
    match raw {
        "inside" => Some(ArrowBindingMode::Inside),
        "orbit" => Some(ArrowBindingMode::Orbit),
        _ => None,
    }
}
