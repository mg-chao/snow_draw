#![allow(dead_code)]

use std::fmt;

use crate::draw::types::draw_point::DrawPoint;
use serde_json::{Map, Value};
use thiserror::Error;

use super::elbow_constants::ElbowConstants;

/// Internal axis tagging for elbow paths.
#[derive(Clone, Copy, Debug, PartialEq, Eq, Hash)]
pub enum ElbowAxis {
    Horizontal,
    Vertical,
}

impl ElbowAxis {
    /// Whether this axis is horizontal.
    pub const fn is_horizontal(self) -> bool {
        matches!(self, Self::Horizontal)
    }

    /// Whether this axis is vertical.
    pub const fn is_vertical(self) -> bool {
        matches!(self, Self::Vertical)
    }
}

/// Decode failure for [`ElbowFixedSegment::from_json`].
#[derive(Clone, Copy, Debug, Error, PartialEq, Eq)]
#[error("Invalid ElbowFixedSegment payload")]
pub struct ElbowFixedSegmentDecodeError;

/// A fixed (pinned) segment of an elbow path whose direction and axis are
/// preserved.
///
/// `index` refers to the segment end point in the path list
/// (`segment spans points[index - 1] -> points[index]`).
#[derive(Clone, Copy, Debug, PartialEq, Hash)]
pub struct ElbowFixedSegment {
    pub index: usize,
    pub start: DrawPoint,
    pub end: DrawPoint,
}

impl ElbowFixedSegment {
    pub const fn new(index: usize, start: DrawPoint, end: DrawPoint) -> Self {
        Self { index, start, end }
    }

    /// Decodes a fixed segment from a JSON object payload.
    pub fn from_json(json: &Map<String, Value>) -> Result<Self, ElbowFixedSegmentDecodeError> {
        let Some(index) = decode_index(json.get("index")) else {
            return Err(ElbowFixedSegmentDecodeError);
        };
        let Some(start) = decode_point(json.get("start")) else {
            return Err(ElbowFixedSegmentDecodeError);
        };
        let Some(end) = decode_point(json.get("end")) else {
            return Err(ElbowFixedSegmentDecodeError);
        };

        Ok(Self::new(index, start, end))
    }

    /// The [`ElbowAxis`] of this segment.
    pub fn axis(self) -> ElbowAxis {
        axis_for_segment(self.start, self.end, ElbowConstants::INTERSECTION_EPSILON)
    }

    /// Whether this segment runs horizontally.
    pub fn is_horizontal(self) -> bool {
        self.axis().is_horizontal()
    }

    /// The shared coordinate along the perpendicular axis.
    ///
    /// For a horizontal segment this is the Y midpoint; for vertical, the X.
    pub fn axis_value(self) -> f64 {
        axis_value(self.start, self.end, self.axis())
    }

    /// Manhattan length of this segment.
    pub fn length(self) -> f64 {
        manhattan_distance(self.start, self.end)
    }

    /// Whether this segment has meaningful length.
    pub fn is_significant(self) -> bool {
        self.length() > ElbowConstants::DEDUP_THRESHOLD
    }

    pub fn copy_with(
        self,
        index: Option<usize>,
        start: Option<DrawPoint>,
        end: Option<DrawPoint>,
    ) -> Self {
        Self {
            index: index.unwrap_or(self.index),
            start: start.unwrap_or(self.start),
            end: end.unwrap_or(self.end),
        }
    }

    /// Encodes this fixed segment to a JSON object payload.
    pub fn to_json(self) -> Map<String, Value> {
        let mut json = Map::new();
        json.insert("index".to_string(), Value::from(self.index as u64));
        json.insert("start".to_string(), encode_point(self.start));
        json.insert("end".to_string(), encode_point(self.end));
        json
    }
}

impl fmt::Display for ElbowFixedSegment {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        write!(
            f,
            "ElbowFixedSegment(index: {}, start: {}, end: {})",
            self.index, self.start, self.end
        )
    }
}

fn decode_index(raw: Option<&Value>) -> Option<usize> {
    let raw = raw?;

    if let Some(value) = raw.as_u64() {
        return usize::try_from(value).ok();
    }
    if let Some(value) = raw.as_i64() {
        return usize::try_from(value).ok();
    }
    if let Some(value) = raw.as_f64() {
        if !value.is_finite() {
            return None;
        }
        let value = value.trunc();
        if value < 0.0 || value > usize::MAX as f64 {
            return None;
        }
        return Some(value as usize);
    }

    None
}

fn decode_point(raw: Option<&Value>) -> Option<DrawPoint> {
    let raw = raw?.as_object()?;
    let x = raw.get("x")?.as_f64()?;
    let y = raw.get("y")?.as_f64()?;
    Some(DrawPoint::new(x, y))
}

fn encode_point(point: DrawPoint) -> Value {
    let mut map = Map::new();
    map.insert("x".to_string(), Value::from(point.x));
    map.insert("y".to_string(), Value::from(point.y));
    Value::Object(map)
}

fn manhattan_distance(a: DrawPoint, b: DrawPoint) -> f64 {
    (a.x - b.x).abs() + (a.y - b.y).abs()
}

fn is_horizontal(a: DrawPoint, b: DrawPoint) -> bool {
    (a.y - b.y).abs() <= (a.x - b.x).abs()
}

fn axis_aligned_for_segment(a: DrawPoint, b: DrawPoint, epsilon: f64) -> Option<ElbowAxis> {
    let dx = (a.x - b.x).abs();
    let dy = (a.y - b.y).abs();

    if dx <= epsilon && dy <= epsilon {
        return None;
    }
    if dy <= epsilon {
        return Some(ElbowAxis::Horizontal);
    }
    if dx <= epsilon {
        return Some(ElbowAxis::Vertical);
    }

    None
}

fn axis_for_segment(a: DrawPoint, b: DrawPoint, epsilon: f64) -> ElbowAxis {
    axis_aligned_for_segment(a, b, epsilon).unwrap_or_else(|| {
        if is_horizontal(a, b) {
            ElbowAxis::Horizontal
        } else {
            ElbowAxis::Vertical
        }
    })
}

fn axis_value(start: DrawPoint, end: DrawPoint, axis: ElbowAxis) -> f64 {
    if axis.is_horizontal() {
        (start.y + end.y) / 2.0
    } else {
        (start.x + end.x) / 2.0
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn axis_falls_back_to_dominant_direction_for_non_axis_aligned_short_segments() {
        let segment = ElbowFixedSegment::new(1, DrawPoint::new(0.0, 0.0), DrawPoint::new(0.5, 0.8));

        assert_eq!(segment.axis(), ElbowAxis::Vertical);
    }
}
