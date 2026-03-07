#![allow(dead_code)]

use crate::draw::elements::types::arrow::elbow::elbow_fixed_segment::ElbowFixedSegment;

/// Stores elbow-only routing metadata for an arrow.
///
/// Straight and curved arrows do not need fixed-segment locks or the
/// additional endpoint flags, so this state lives separately from the base
/// arrow payload.
#[derive(Clone, Debug, Default, PartialEq, Hash)]
pub struct ElbowRoutingData {
    pub fixed_segments: Option<Vec<ElbowFixedSegment>>,
    pub start_is_special: Option<bool>,
    pub end_is_special: Option<bool>,
}

impl ElbowRoutingData {
    /// Creates a new elbow-routing metadata snapshot.
    pub fn new(
        fixed_segments: Option<Vec<ElbowFixedSegment>>,
        start_is_special: Option<bool>,
        end_is_special: Option<bool>,
    ) -> Self {
        Self {
            fixed_segments,
            start_is_special,
            end_is_special,
        }
    }

    /// Returns whether the routing payload carries any elbow-only metadata.
    pub fn is_empty(&self) -> bool {
        self.fixed_segments
            .as_ref()
            .is_none_or(|segments| segments.is_empty())
            && self.start_is_special.is_none()
            && self.end_is_special.is_none()
    }
}

#[cfg(test)]
mod tests {
    use std::collections::hash_map::DefaultHasher;
    use std::hash::{Hash, Hasher};

    use crate::draw::types::draw_point::DrawPoint;

    use super::{ElbowFixedSegment, ElbowRoutingData};

    #[test]
    fn is_empty_matches_dart_semantics() {
        assert!(ElbowRoutingData::default().is_empty());
        assert!(ElbowRoutingData::new(Some(Vec::new()), None, None).is_empty());
        assert!(!ElbowRoutingData::new(None, Some(true), None).is_empty());
    }

    #[test]
    fn empty_segments_are_not_normalized_away() {
        let with_null_segments = ElbowRoutingData::default();
        let with_empty_segments = ElbowRoutingData::new(Some(Vec::new()), None, None);

        assert_ne!(with_null_segments, with_empty_segments);
    }

    #[test]
    fn hash_distinguishes_null_and_empty_segment_lists() {
        let with_null_segments = ElbowRoutingData::default();
        let with_empty_segments = ElbowRoutingData::new(Some(Vec::new()), None, None);

        assert_ne!(
            hash_value(&with_null_segments),
            hash_value(&with_empty_segments)
        );
    }

    #[test]
    fn equality_uses_segment_contents() {
        let segment = ElbowFixedSegment::new(1, DrawPoint::new(0.0, 0.0), DrawPoint::new(2.0, 0.0));

        let left = ElbowRoutingData::new(Some(vec![segment]), Some(true), Some(false));
        let right = ElbowRoutingData::new(Some(vec![segment]), Some(true), Some(false));

        assert_eq!(left, right);
    }

    fn hash_value(value: &ElbowRoutingData) -> u64 {
        let mut hasher = DefaultHasher::new();
        value.hash(&mut hasher);
        hasher.finish()
    }
}
