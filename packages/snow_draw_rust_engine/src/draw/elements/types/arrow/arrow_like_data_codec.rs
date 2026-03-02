#![allow(dead_code)]

use std::error::Error;
use std::fmt;

use crate::draw::types::draw_point::DrawPoint;
use serde_json::{Map, Value};

use super::arrow_binding::ArrowBinding;

/// Temporary compatibility alias for elbow fixed segments.
///
/// The dedicated elbow segment module is still being translated in this
/// workspace, so this codec reuses the translated segment payload type from
/// `arrow_data`.
pub type ElbowFixedSegment = super::arrow_data::ElbowFixedSegment;

/// Update wrapper that mirrors Dart's `ArrowLikeData.unset` sentinel behavior.
///
/// `Unset` keeps the current value, while `Value(T)` applies the provided
/// update payload.
#[derive(Clone, Debug, Default, PartialEq)]
pub enum ArrowLikeUpdate<T> {
    #[default]
    Unset,
    Value(T),
}

impl<T> ArrowLikeUpdate<T> {
    pub const fn unset() -> Self {
        Self::Unset
    }

    pub fn value(value: T) -> Self {
        Self::Value(value)
    }
}

/// Decode/encode failures for [`ArrowLikeDataCodec`] helpers.
#[derive(Clone, Debug, PartialEq, Eq)]
pub struct ArrowLikeDataCodecError {
    message: String,
}

impl ArrowLikeDataCodecError {
    fn new(message: impl Into<String>) -> Self {
        Self {
            message: message.into(),
        }
    }
}

impl fmt::Display for ArrowLikeDataCodecError {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        f.write_str(&self.message)
    }
}

impl Error for ArrowLikeDataCodecError {}

/// Shared serialization helpers for arrow-like data implementations.
pub struct ArrowLikeDataCodec;

impl ArrowLikeDataCodec {
    /// Decodes the required `points` payload.
    pub fn decode_points(
        raw_points: Option<&Value>,
    ) -> Result<Vec<DrawPoint>, ArrowLikeDataCodecError> {
        let raw_points = raw_points
            .ok_or_else(|| ArrowLikeDataCodecError::new("Arrow points must be a JSON array"))?;
        let entries = raw_points
            .as_array()
            .ok_or_else(|| ArrowLikeDataCodecError::new("Arrow points must be a JSON array"))?;

        let mut points = Vec::with_capacity(entries.len());
        for raw_point in entries {
            points.push(decode_point(raw_point, "points entry")?);
        }

        if points.len() < 2 {
            return Err(ArrowLikeDataCodecError::new(
                "Arrow payload must include at least two points",
            ));
        }

        Ok(points)
    }

    /// Decodes an optional endpoint binding payload.
    pub fn decode_binding(
        raw: Option<&Value>,
    ) -> Result<Option<ArrowBinding>, ArrowLikeDataCodecError> {
        let Some(raw) = raw else {
            return Ok(None);
        };
        if raw.is_null() {
            return Ok(None);
        }
        if !raw.is_object() {
            return Err(ArrowLikeDataCodecError::new(
                "Expected a JSON map for binding",
            ));
        }

        ArrowBinding::from_json(raw).map(Some).map_err(|error| {
            ArrowLikeDataCodecError::new(format!("Invalid binding payload: {error}"))
        })
    }

    /// Resolves a nullable binding update from a sentinel-aware payload.
    pub fn resolve_binding_update(
        raw_binding: ArrowLikeUpdate<Option<ArrowBinding>>,
        current_binding: Option<ArrowBinding>,
    ) -> Option<ArrowBinding> {
        Self::resolve_update(raw_binding, current_binding, |raw| raw)
    }

    /// Decodes optional elbow fixed segments.
    pub fn decode_fixed_segments(
        raw: Option<&Value>,
    ) -> Result<Option<Vec<ElbowFixedSegment>>, ArrowLikeDataCodecError> {
        let Some(raw) = raw else {
            return Ok(None);
        };
        if raw.is_null() {
            return Ok(None);
        }

        let entries = raw
            .as_array()
            .ok_or_else(|| ArrowLikeDataCodecError::new("fixedSegments must be a JSON array"))?;

        let mut segments = Vec::with_capacity(entries.len());
        for entry in entries {
            let map = entry.as_object().ok_or_else(|| {
                ArrowLikeDataCodecError::new("Expected a JSON map for fixedSegments entry")
            })?;

            let segment = ElbowFixedSegment::from_json(map).map_err(|error| {
                ArrowLikeDataCodecError::new(format!("Invalid fixedSegments entry: {error}"))
            })?;
            segments.push(segment);
        }

        Ok(Self::normalize_fixed_segments(Some(segments)))
    }

    /// Normalizes optional elbow fixed segments.
    ///
    /// Empty collections are represented as `None` to match Dart behavior.
    pub fn normalize_fixed_segments(
        segments: Option<Vec<ElbowFixedSegment>>,
    ) -> Option<Vec<ElbowFixedSegment>> {
        match segments {
            Some(values) if values.is_empty() => None,
            other => other,
        }
    }

    /// Resolves a fixed-segment update from a sentinel-aware payload.
    pub fn resolve_fixed_segments_update(
        raw_fixed_segments: ArrowLikeUpdate<Option<Vec<ElbowFixedSegment>>>,
        current_fixed_segments: Option<Vec<ElbowFixedSegment>>,
    ) -> Option<Vec<ElbowFixedSegment>> {
        Self::resolve_update(
            raw_fixed_segments,
            current_fixed_segments,
            Self::normalize_fixed_segments,
        )
    }

    /// Resolves a nullable bool update from a sentinel-aware payload.
    pub fn resolve_nullable_bool_update(
        raw_value: ArrowLikeUpdate<Option<bool>>,
        current_value: Option<bool>,
    ) -> Option<bool> {
        Self::resolve_update(raw_value, current_value, |raw| raw)
    }

    /// Encodes points to compact `{x, y}` JSON maps.
    pub fn encode_points(points: &[DrawPoint]) -> Vec<Map<String, Value>> {
        points
            .iter()
            .map(|point| {
                let mut map = Map::new();
                map.insert("x".to_string(), Value::from(point.x));
                map.insert("y".to_string(), Value::from(point.y));
                map
            })
            .collect()
    }

    /// Encodes optional fixed segments to JSON maps.
    pub fn encode_fixed_segments(
        segments: Option<&[ElbowFixedSegment]>,
    ) -> Option<Vec<Map<String, Value>>> {
        let values = segments?;
        if values.is_empty() {
            return None;
        }

        Some(values.iter().map(ElbowFixedSegment::to_json).collect())
    }

    fn resolve_update<T, U, F>(raw_value: ArrowLikeUpdate<U>, current_value: T, decode: F) -> T
    where
        F: FnOnce(U) -> T,
    {
        match raw_value {
            ArrowLikeUpdate::Unset => current_value,
            ArrowLikeUpdate::Value(raw) => decode(raw),
        }
    }
}

fn decode_point(raw: &Value, field_name: &str) -> Result<DrawPoint, ArrowLikeDataCodecError> {
    let map = raw.as_object().ok_or_else(|| {
        ArrowLikeDataCodecError::new(format!("Expected a JSON map for {field_name}"))
    })?;

    let x = map.get("x").and_then(Value::as_f64).ok_or_else(|| {
        ArrowLikeDataCodecError::new(format!("{field_name} must provide numeric x/y"))
    })?;
    let y = map.get("y").and_then(Value::as_f64).ok_or_else(|| {
        ArrowLikeDataCodecError::new(format!("{field_name} must provide numeric x/y"))
    })?;

    Ok(DrawPoint::new(x, y))
}
