#![allow(dead_code)]

use crate::draw::config::draw_config::{ConfigDefaults, ElementStyleConfig};
use crate::draw::elements::core::element_data::{DynElementData, ElementData, ElementTypeId};
use crate::draw::elements::core::element_style_configurable_data::ElementStyleConfigurableData;
use crate::draw::elements::core::element_style_updatable_data::ElementStyleUpdatableData;
use crate::draw::elements::types::arrow::arrow_binding::ArrowBinding;
use crate::draw::elements::types::arrow::arrow_like_data::{
    ArrowLikeData, ArrowLikeDataPatch, NullableField,
};
use crate::draw::elements::types::arrow::elbow::elbow_fixed_segment::ElbowFixedSegment;
use crate::draw::types::draw_color::DrawColor;
use crate::draw::types::draw_point::DrawPoint;
use crate::draw::types::element_style::{
    ArrowType, ArrowheadStyle, ElementStyleUpdate, FillStyle, StrokeStyle,
};
use serde_json::{Map, Value};
use thiserror::Error;

/// Immutable line payload translated from Dart `LineData`.
///
/// The line element is an arrow-like element with fixed arrow semantics:
/// `arrow_type` is always curved and both arrowheads are always `none`.
#[derive(Clone, Debug, PartialEq)]
pub struct LineData {
    /// Normalized control points in element-local space (`0..1`).
    pub points: Vec<DrawPoint>,
    pub color: DrawColor,
    pub fill_color: DrawColor,
    pub fill_style: FillStyle,
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

/// Patch payload for [`LineData::copy_with`].
#[derive(Clone, Debug, Default, PartialEq)]
pub struct LineDataPatch {
    pub points: Option<Vec<DrawPoint>>,
    pub color: Option<DrawColor>,
    pub fill_color: Option<DrawColor>,
    pub fill_style: Option<FillStyle>,
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

impl LineData {
    pub const TYPE_ID_TOKEN: &'static str = "line";
    pub const DEFAULT_POINTS: [DrawPoint; 2] = [DrawPoint::ZERO, DrawPoint::new(1.0, 1.0)];

    /// Decodes `LineData` from JSON.
    pub fn from_json(json: &Map<String, Value>) -> Result<Self, LineDataDecodeError> {
        Ok(Self {
            points: decode_required_points(json, "points")?,
            color: decode_required_color(json, "color")?,
            fill_color: decode_required_color(json, "fillColor")?,
            fill_style: decode_required_fill_style(json, "fillStyle")?,
            stroke_width: decode_required_f64(json, "strokeWidth")?,
            stroke_style: decode_required_stroke_style(json, "strokeStyle")?,
            arrow_type: ArrowType::Curved,
            start_arrowhead: ArrowheadStyle::None,
            end_arrowhead: ArrowheadStyle::None,
            start_binding: decode_optional_binding(json, "startBinding")?,
            end_binding: decode_optional_binding(json, "endBinding")?,
            fixed_segments: None,
            start_is_special: None,
            end_is_special: None,
        })
    }

    /// Decodes `LineData` from a JSON value.
    pub fn from_json_value(value: &Value) -> Result<Self, LineDataDecodeError> {
        let json = value.as_object().ok_or_else(|| {
            LineDataDecodeError::invalid_field("line", "expected JSON object payload")
        })?;
        Self::from_json(json)
    }

    /// Returns the strongly typed element id token for line payloads.
    pub fn type_id_token() -> ElementTypeId<LineData> {
        ElementTypeId::new(Self::TYPE_ID_TOKEN)
    }

    /// Returns an updated payload while preserving immutability.
    ///
    /// Like Dart, line payloads accept `arrow_type`/arrowhead fields in the
    /// patch API, but only support `ArrowType::Curved` and `ArrowheadStyle::None`.
    pub fn copy_with(&self, patch: LineDataPatch) -> Self {
        let next_arrow_type = patch.arrow_type.unwrap_or(self.arrow_type);
        let next_start_arrowhead = patch.start_arrowhead.unwrap_or(self.start_arrowhead);
        let next_end_arrowhead = patch.end_arrowhead.unwrap_or(self.end_arrowhead);

        debug_assert!(
            next_arrow_type == ArrowType::Curved,
            "LineData only supports curved arrow type"
        );
        debug_assert!(
            next_start_arrowhead == ArrowheadStyle::None,
            "LineData does not support start arrowheads"
        );
        debug_assert!(
            next_end_arrowhead == ArrowheadStyle::None,
            "LineData does not support end arrowheads"
        );

        Self {
            points: patch.points.unwrap_or_else(|| self.points.clone()),
            color: patch.color.unwrap_or(self.color),
            fill_color: patch.fill_color.unwrap_or(self.fill_color),
            fill_style: patch.fill_style.unwrap_or(self.fill_style),
            stroke_width: patch.stroke_width.unwrap_or(self.stroke_width),
            stroke_style: patch.stroke_style.unwrap_or(self.stroke_style),
            arrow_type: ArrowType::Curved,
            start_arrowhead: ArrowheadStyle::None,
            end_arrowhead: ArrowheadStyle::None,
            start_binding: resolve_nullable_update(patch.start_binding, &self.start_binding),
            end_binding: resolve_nullable_update(patch.end_binding, &self.end_binding),
            fixed_segments: None,
            start_is_special: None,
            end_is_special: None,
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
        json
    }
}

impl Default for LineData {
    fn default() -> Self {
        Self {
            points: Self::DEFAULT_POINTS.to_vec(),
            color: ConfigDefaults::DEFAULT_COLOR,
            fill_color: ConfigDefaults::DEFAULT_FILL_COLOR,
            fill_style: ConfigDefaults::DEFAULT_FILL_STYLE,
            stroke_width: ConfigDefaults::DEFAULT_STROKE_WIDTH,
            stroke_style: ConfigDefaults::DEFAULT_STROKE_STYLE,
            arrow_type: ArrowType::Curved,
            start_arrowhead: ArrowheadStyle::None,
            end_arrowhead: ArrowheadStyle::None,
            start_binding: None,
            end_binding: None,
            fixed_segments: None,
            start_is_special: None,
            end_is_special: None,
        }
    }
}

impl ElementData for LineData {
    fn type_id(&self) -> ElementTypeId<DynElementData> {
        ElementTypeId::new(Self::TYPE_ID_TOKEN)
    }

    fn to_json(&self) -> Map<String, Value> {
        self.to_json_map()
    }
}

impl ArrowLikeData for LineData {
    type ArrowBinding = ArrowBinding;
    type ElbowFixedSegment = ElbowFixedSegment;

    fn points(&self) -> &[DrawPoint] {
        &self.points
    }

    fn stroke_width(&self) -> f64 {
        self.stroke_width
    }

    fn stroke_style(&self) -> StrokeStyle {
        self.stroke_style
    }

    fn arrow_type(&self) -> ArrowType {
        self.arrow_type
    }

    fn start_arrowhead(&self) -> ArrowheadStyle {
        self.start_arrowhead
    }

    fn end_arrowhead(&self) -> ArrowheadStyle {
        self.end_arrowhead
    }

    fn start_binding(&self) -> Option<&Self::ArrowBinding> {
        self.start_binding.as_ref()
    }

    fn end_binding(&self) -> Option<&Self::ArrowBinding> {
        self.end_binding.as_ref()
    }

    fn fixed_segments(&self) -> Option<&[Self::ElbowFixedSegment]> {
        None
    }

    fn start_is_special(&self) -> Option<bool> {
        None
    }

    fn end_is_special(&self) -> Option<bool> {
        None
    }

    fn copy_with(
        &self,
        patch: ArrowLikeDataPatch<Self::ArrowBinding, Self::ElbowFixedSegment>,
    ) -> Self {
        Self::copy_with(
            self,
            LineDataPatch {
                points: patch.points,
                stroke_width: patch.stroke_width,
                stroke_style: patch.stroke_style,
                arrow_type: patch.arrow_type,
                start_arrowhead: patch.start_arrowhead,
                end_arrowhead: patch.end_arrowhead,
                start_binding: patch.start_binding,
                end_binding: patch.end_binding,
                fixed_segments: patch.fixed_segments,
                start_is_special: patch.start_is_special,
                end_is_special: patch.end_is_special,
                ..LineDataPatch::default()
            },
        )
    }
}

impl ElementStyleConfigurableData for LineData {
    fn with_element_style(&self, style: ElementStyleConfig) -> Box<DynElementData> {
        Box::new(self.copy_with(LineDataPatch {
            color: Some(style.color),
            fill_color: Some(style.fill_color),
            fill_style: Some(style.fill_style),
            stroke_width: Some(style.stroke_width),
            stroke_style: Some(style.stroke_style),
            ..LineDataPatch::default()
        }))
    }
}

impl ElementStyleUpdatableData for LineData {
    fn with_style_update(&self, update: ElementStyleUpdate) -> Box<DynElementData> {
        Box::new(self.copy_with(LineDataPatch {
            color: update.color,
            fill_color: update.fill_color,
            fill_style: update.fill_style.or(Some(self.fill_style)),
            stroke_width: Some(update.stroke_width.unwrap_or(self.stroke_width)),
            stroke_style: Some(update.stroke_style.unwrap_or(self.stroke_style)),
            ..LineDataPatch::default()
        }))
    }
}

/// Decode failures for `LineData` JSON payloads.
#[derive(Debug, Error)]
#[error("{message}")]
pub struct LineDataDecodeError {
    message: String,
}

impl LineDataDecodeError {
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
) -> Result<Vec<DrawPoint>, LineDataDecodeError> {
    let value = json
        .get(field)
        .ok_or_else(|| LineDataDecodeError::invalid_field(field, "field is missing"))?;
    let array = value
        .as_array()
        .ok_or_else(|| LineDataDecodeError::invalid_field(field, "expected JSON array"))?;

    let mut points = Vec::with_capacity(array.len());
    for entry in array {
        let map = entry.as_object().ok_or_else(|| {
            LineDataDecodeError::invalid_field(field, "point entry must be object")
        })?;
        let x = decode_required_f64(map, "x")?;
        let y = decode_required_f64(map, "y")?;
        points.push(DrawPoint::new(x, y));
    }

    if points.len() < 2 {
        return Err(LineDataDecodeError::invalid_field(
            field,
            "must include at least two points",
        ));
    }

    Ok(points)
}

fn decode_required_color(
    json: &Map<String, Value>,
    field: &str,
) -> Result<DrawColor, LineDataDecodeError> {
    let value = json
        .get(field)
        .ok_or_else(|| LineDataDecodeError::invalid_field(field, "field is missing"))?;
    let number = value
        .as_i64()
        .or_else(|| value.as_u64().and_then(|raw| i64::try_from(raw).ok()))
        .ok_or_else(|| LineDataDecodeError::invalid_field(field, "expected integer ARGB32"))?;
    Ok(DrawColor::new(number as u32))
}

fn decode_required_f64(json: &Map<String, Value>, field: &str) -> Result<f64, LineDataDecodeError> {
    let value = json
        .get(field)
        .ok_or_else(|| LineDataDecodeError::invalid_field(field, "field is missing"))?;
    value
        .as_f64()
        .ok_or_else(|| LineDataDecodeError::invalid_field(field, "expected numeric value"))
}

fn decode_optional_bool(
    json: &Map<String, Value>,
    field: &str,
) -> Result<Option<bool>, LineDataDecodeError> {
    let Some(value) = json.get(field) else {
        return Ok(None);
    };

    if value.is_null() {
        return Ok(None);
    }

    let flag = value
        .as_bool()
        .ok_or_else(|| LineDataDecodeError::invalid_field(field, "expected bool or null"))?;
    Ok(Some(flag))
}

fn decode_optional_binding(
    json: &Map<String, Value>,
    field: &str,
) -> Result<Option<ArrowBinding>, LineDataDecodeError> {
    let Some(value) = json.get(field) else {
        return Ok(None);
    };

    if value.is_null() {
        return Ok(None);
    }

    ArrowBinding::from_json(value).map(Some).map_err(|error| {
        LineDataDecodeError::invalid_field(field, &format!("invalid binding payload: {error}"))
    })
}

fn decode_optional_fixed_segments(
    json: &Map<String, Value>,
    field: &str,
) -> Result<Option<Vec<ElbowFixedSegment>>, LineDataDecodeError> {
    let Some(value) = json.get(field) else {
        return Ok(None);
    };

    if value.is_null() {
        return Ok(None);
    }

    let array = value
        .as_array()
        .ok_or_else(|| LineDataDecodeError::invalid_field(field, "expected array or null"))?;
    let mut segments = Vec::with_capacity(array.len());
    for entry in array {
        let map = entry.as_object().ok_or_else(|| {
            LineDataDecodeError::invalid_field(field, "segment entry must be object")
        })?;
        let segment = ElbowFixedSegment::from_json(map)
            .map_err(|_| LineDataDecodeError::invalid_field(field, "segment entry is invalid"))?;
        segments.push(segment);
    }

    Ok(normalize_fixed_segments(Some(segments)))
}

fn decode_required_stroke_style(
    json: &Map<String, Value>,
    field: &str,
) -> Result<StrokeStyle, LineDataDecodeError> {
    let raw = decode_required_string(json, field)?;
    stroke_style_from_name(&raw)
        .ok_or_else(|| LineDataDecodeError::invalid_field(field, "unsupported stroke style value"))
}

fn decode_required_fill_style(
    json: &Map<String, Value>,
    field: &str,
) -> Result<FillStyle, LineDataDecodeError> {
    let raw = decode_required_string(json, field)?;
    fill_style_from_name(&raw)
        .ok_or_else(|| LineDataDecodeError::invalid_field(field, "unsupported fill style value"))
}

fn decode_required_string(
    json: &Map<String, Value>,
    field: &str,
) -> Result<String, LineDataDecodeError> {
    let value = json
        .get(field)
        .ok_or_else(|| LineDataDecodeError::invalid_field(field, "field is missing"))?;
    value
        .as_str()
        .map(str::to_owned)
        .ok_or_else(|| LineDataDecodeError::invalid_field(field, "expected string value"))
}

fn point_to_json(point: DrawPoint) -> Value {
    let mut json = Map::new();
    json.insert("x".to_string(), Value::from(point.x));
    json.insert("y".to_string(), Value::from(point.y));
    Value::Object(json)
}

fn option_binding_to_json(binding: Option<&ArrowBinding>) -> Value {
    binding.map(ArrowBinding::to_json).unwrap_or(Value::Null)
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
            .map(|segment| Value::Object((*segment).to_json()))
            .collect(),
    )
}

fn option_bool_to_json(value: Option<bool>) -> Value {
    value.map(Value::Bool).unwrap_or(Value::Null)
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

fn arrow_type_to_name(arrow_type: ArrowType) -> &'static str {
    match arrow_type {
        ArrowType::Straight => "straight",
        ArrowType::Curved => "curved",
        ArrowType::Elbow => "elbow",
    }
}

fn arrowhead_style_to_name(style: ArrowheadStyle) -> &'static str {
    match style {
        ArrowheadStyle::None => "none",
        ArrowheadStyle::Standard => "standard",
        ArrowheadStyle::Triangle => "triangle",
        ArrowheadStyle::TriangleOutline => "triangleOutline",
        ArrowheadStyle::Square => "square",
        ArrowheadStyle::Dot => "dot",
        ArrowheadStyle::Circle => "circle",
        ArrowheadStyle::CircleOutline => "circleOutline",
        ArrowheadStyle::Diamond => "diamond",
        ArrowheadStyle::DiamondOutline => "diamondOutline",
        ArrowheadStyle::CrowfootOne => "crowfootOne",
        ArrowheadStyle::CrowfootMany => "crowfootMany",
        ArrowheadStyle::CrowfootOneOrMany => "crowfootOneOrMany",
        ArrowheadStyle::InvertedTriangle => "invertedTriangle",
        ArrowheadStyle::VerticalLine => "verticalLine",
    }
}
