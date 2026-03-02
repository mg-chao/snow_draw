#![allow(dead_code)]

use crate::draw::elements::types::filter::filter_data::FilterData;
use crate::draw::models::element_state::ElementState;

/// A render segment in the filter pipeline.
///
/// Mirrors Dart's sealed `RenderSegment` hierarchy.
#[derive(Clone, Debug, PartialEq)]
pub enum RenderSegment {
    /// A contiguous batch of non-filter elements.
    ElementBatchSegment(ElementBatchSegment),
    /// A single filter element segment.
    FilterSegment(FilterSegment),
    /// A merged segment containing adjacent same-type filters.
    MergedFilterSegment(MergedFilterSegment),
}

impl RenderSegment {
    /// Creates an element batch segment.
    pub fn element_batch(
        elements: Vec<ElementState>,
        id_fingerprint: Option<u64>,
        identity_fingerprint: Option<u64>,
    ) -> Self {
        Self::ElementBatchSegment(ElementBatchSegment::new(
            elements,
            id_fingerprint,
            identity_fingerprint,
        ))
    }

    /// Creates a single filter segment.
    pub fn filter(filter_element: ElementState, filter_data: FilterData) -> Self {
        Self::FilterSegment(FilterSegment::new(filter_element, filter_data))
    }

    /// Creates a merged filter segment.
    pub fn merged_filters(filters: Vec<FilterSegment>) -> Self {
        Self::MergedFilterSegment(MergedFilterSegment::new(filters))
    }
}

/// A contiguous batch of non-filter elements.
#[derive(Clone, Debug, PartialEq)]
pub struct ElementBatchSegment {
    /// Non-filter elements in z-order.
    pub elements: Vec<ElementState>,
    /// Optional fingerprint of elements based on stable element ids.
    pub id_fingerprint: Option<u64>,
    /// Optional fingerprint of elements based on object identity.
    pub identity_fingerprint: Option<u64>,
}

impl ElementBatchSegment {
    /// Creates a non-filter element batch segment.
    pub fn new(
        elements: Vec<ElementState>,
        id_fingerprint: Option<u64>,
        identity_fingerprint: Option<u64>,
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

impl FilterSegment {
    /// Creates a filter segment.
    pub fn new(filter_element: ElementState, filter_data: FilterData) -> Self {
        Self {
            filter_element,
            filter_data,
        }
    }
}

/// A group of adjacent same-type filter elements merged into one pass.
///
/// This allows downstream rendering to reduce `saveLayer` calls by combining
/// clip regions for filters with the same filter type.
#[derive(Clone, Debug, PartialEq)]
pub struct MergedFilterSegment {
    /// Individual filter entries, all sharing the same filter type.
    pub filters: Vec<FilterSegment>,
}

impl MergedFilterSegment {
    /// Creates a merged filter segment.
    pub fn new(filters: Vec<FilterSegment>) -> Self {
        Self { filters }
    }
}
