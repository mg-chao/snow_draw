#![allow(dead_code)]

use crate::draw::elements::types::filter::filter_data::FilterData;
use crate::draw::models::element_state::ElementState;

/// A render segment in the filter pipeline.
#[derive(Clone, Debug, PartialEq)]
pub enum RenderSegment {
    /// A contiguous batch of non-filter elements.
    ElementBatch(ElementBatchSegment),
    /// A single filter element.
    Filter(FilterSegment),
    /// Adjacent same-type filters merged into one pass.
    MergedFilter(MergedFilterSegment),
}

/// A contiguous batch of non-filter elements.
#[derive(Clone, Debug, PartialEq)]
pub struct ElementBatchSegment {
    /// Non-filter elements in z-order.
    pub elements: Vec<ElementState>,
    /// Fingerprint of [`Self::elements`] derived from stable element ids.
    pub id_fingerprint: Option<u32>,
    /// Fingerprint of [`Self::elements`] derived from element identity.
    pub identity_fingerprint: Option<u32>,
}

impl ElementBatchSegment {
    pub fn new(
        elements: Vec<ElementState>,
        id_fingerprint: Option<u32>,
        identity_fingerprint: Option<u32>,
    ) -> Self {
        Self {
            elements,
            id_fingerprint,
            identity_fingerprint,
        }
    }
}

/// A filter element segment.
#[derive(Clone, Debug, PartialEq)]
pub struct FilterSegment {
    /// Filter element in z-order.
    pub filter_element: ElementState,
    /// Filter data payload.
    pub filter_data: FilterData,
}

/// A group of adjacent same-type filter elements merged into one pass.
#[derive(Clone, Debug, PartialEq)]
pub struct MergedFilterSegment {
    /// Individual filters, all sharing the same filter type.
    pub filters: Vec<FilterSegment>,
}

/// Builds render segments from z-ordered elements.
///
/// Contiguous non-filter elements are collapsed into a single batch segment.
/// Adjacent filters of the same type are merged into a [`MergedFilterSegment`]
/// so the renderer can apply them in a single pass.
#[derive(Clone, Copy, Debug, Default, PartialEq, Eq)]
pub struct FilterSegmentBuilder;

impl FilterSegmentBuilder {
    const ID_FINGERPRINT_SEED: u32 = 17;
    const IDENTITY_FINGERPRINT_SEED: u32 = 23;
    const HASH_MASK: u32 = 0x1fff_ffff;

    pub const fn new() -> Self {
        Self
    }

    /// Builds alternating element-batch and filter segments.
    pub fn build(&self, elements: &[ElementState]) -> Vec<RenderSegment> {
        if elements.is_empty() {
            return Vec::new();
        }

        let mut segments = Vec::new();
        let mut current_batch: Vec<ElementState> = Vec::new();
        let mut current_batch_fingerprint = Self::ID_FINGERPRINT_SEED;
        let mut current_batch_identity_fingerprint = Self::IDENTITY_FINGERPRINT_SEED;

        for element in elements {
            if let Some(filter_data) = decode_filter_data(element) {
                Self::flush_batch(
                    &mut segments,
                    &mut current_batch,
                    &mut current_batch_fingerprint,
                    &mut current_batch_identity_fingerprint,
                );
                segments.push(RenderSegment::Filter(FilterSegment {
                    filter_element: element.clone(),
                    filter_data,
                }));
                continue;
            }

            current_batch.push(element.clone());
            current_batch_fingerprint =
                append_fingerprint(current_batch_fingerprint, stable_string_hash(&element.id));
            current_batch_identity_fingerprint = append_fingerprint(
                current_batch_identity_fingerprint,
                element_identity_hash(element),
            );
        }

        Self::flush_batch(
            &mut segments,
            &mut current_batch,
            &mut current_batch_fingerprint,
            &mut current_batch_identity_fingerprint,
        );

        self.merge_adjacent_filters(segments)
    }

    /// Collapses runs of adjacent [`RenderSegment::Filter`] values that share
    /// the same filter type into one [`RenderSegment::MergedFilter`] entry.
    fn merge_adjacent_filters(&self, segments: Vec<RenderSegment>) -> Vec<RenderSegment> {
        if segments.len() < 2 {
            return segments;
        }

        let mut merged = Vec::with_capacity(segments.len());
        let mut pending_filters: Vec<FilterSegment> = Vec::new();

        for segment in segments {
            match segment {
                RenderSegment::Filter(filter_segment) => {
                    if pending_filters.last().is_some_and(|last| {
                        last.filter_data.filter_type != filter_segment.filter_data.filter_type
                    }) {
                        flush_filters(&mut merged, &mut pending_filters);
                    }
                    pending_filters.push(filter_segment);
                }
                other => {
                    flush_filters(&mut merged, &mut pending_filters);
                    merged.push(other);
                }
            }
        }

        flush_filters(&mut merged, &mut pending_filters);
        merged
    }

    fn flush_batch(
        segments: &mut Vec<RenderSegment>,
        current_batch: &mut Vec<ElementState>,
        current_batch_fingerprint: &mut u32,
        current_batch_identity_fingerprint: &mut u32,
    ) {
        if current_batch.is_empty() {
            return;
        }

        segments.push(RenderSegment::ElementBatch(ElementBatchSegment::new(
            std::mem::take(current_batch),
            Some(*current_batch_fingerprint),
            Some(*current_batch_identity_fingerprint),
        )));

        *current_batch_fingerprint = Self::ID_FINGERPRINT_SEED;
        *current_batch_identity_fingerprint = Self::IDENTITY_FINGERPRINT_SEED;
    }
}

fn decode_filter_data(element: &ElementState) -> Option<FilterData> {
    if element.type_id().as_str() != FilterData::TYPE_ID_TOKEN {
        return None;
    }
    FilterData::from_json(&element.data.to_json()).ok()
}

fn flush_filters(merged: &mut Vec<RenderSegment>, pending_filters: &mut Vec<FilterSegment>) {
    if pending_filters.is_empty() {
        return;
    }

    if pending_filters.len() == 1 {
        let only = pending_filters
            .pop()
            .expect("single filter should exist when len() == 1");
        merged.push(RenderSegment::Filter(only));
        return;
    }

    merged.push(RenderSegment::MergedFilter(MergedFilterSegment {
        filters: std::mem::take(pending_filters),
    }));
}

fn append_fingerprint(current: u32, value: u64) -> u32 {
    let next = u64::from(current).wrapping_mul(31).wrapping_add(value);
    (next as u32) & FilterSegmentBuilder::HASH_MASK
}

fn stable_string_hash(value: &str) -> u64 {
    value.chars().fold(0_u64, |current, ch| {
        current
            .wrapping_mul(31)
            .wrapping_add(u64::from(u32::from(ch)))
    })
}

fn element_identity_hash(element: &ElementState) -> u64 {
    element as *const ElementState as usize as u64
}

#[cfg(test)]
mod tests {
    use std::sync::Arc;

    use serde_json::{Map, Value};

    use super::*;
    use crate::draw::elements::core::element_data::{DynElementData, ElementData, ElementTypeId};
    use crate::draw::types::draw_rect::DrawRect;
    use crate::draw::types::element_style::CanvasFilterType;

    #[derive(Clone, Debug)]
    struct NonFilterData;

    impl ElementData for NonFilterData {
        fn type_id(&self) -> ElementTypeId<DynElementData> {
            ElementTypeId::new("rect")
        }

        fn to_json(&self) -> Map<String, Value> {
            Map::new()
        }
    }

    fn make_non_filter(id: &str) -> ElementState {
        ElementState::new(
            id,
            DrawRect::new(0.0, 0.0, 10.0, 10.0),
            0.0,
            1.0,
            0,
            Arc::new(NonFilterData),
        )
    }

    fn make_filter(id: &str, filter_type: CanvasFilterType) -> ElementState {
        ElementState::new(
            id,
            DrawRect::new(0.0, 0.0, 10.0, 10.0),
            0.0,
            1.0,
            0,
            Arc::new(FilterData::new(filter_type, 0.7)),
        )
    }

    #[test]
    fn build_returns_empty_for_empty_input() {
        let builder = FilterSegmentBuilder::new();
        let segments = builder.build(&[]);
        assert!(segments.is_empty());
    }

    #[test]
    fn build_batches_non_filters_and_merges_same_type_filters() {
        let builder = FilterSegmentBuilder::new();
        let elements = vec![
            make_non_filter("a"),
            make_non_filter("b"),
            make_filter("f1", CanvasFilterType::Mosaic),
            make_filter("f2", CanvasFilterType::Mosaic),
            make_non_filter("c"),
            make_filter("f3", CanvasFilterType::Inversion),
            make_filter("f4", CanvasFilterType::Grayscale),
        ];

        let segments = builder.build(&elements);
        assert_eq!(segments.len(), 5);

        match &segments[0] {
            RenderSegment::ElementBatch(batch) => {
                assert_eq!(batch.elements.len(), 2);
                assert!(batch.id_fingerprint.is_some());
                assert!(batch.identity_fingerprint.is_some());
            }
            other => panic!("expected first segment to be element batch, got {other:?}"),
        }

        match &segments[1] {
            RenderSegment::MergedFilter(merged) => {
                assert_eq!(merged.filters.len(), 2);
                assert_eq!(
                    merged.filters[0].filter_data.filter_type,
                    CanvasFilterType::Mosaic
                );
                assert_eq!(
                    merged.filters[1].filter_data.filter_type,
                    CanvasFilterType::Mosaic
                );
            }
            other => panic!("expected second segment to be merged filter, got {other:?}"),
        }

        match &segments[2] {
            RenderSegment::ElementBatch(batch) => assert_eq!(batch.elements.len(), 1),
            other => panic!("expected third segment to be element batch, got {other:?}"),
        }

        assert!(matches!(segments[3], RenderSegment::Filter(_)));
        assert!(matches!(segments[4], RenderSegment::Filter(_)));
    }
}
