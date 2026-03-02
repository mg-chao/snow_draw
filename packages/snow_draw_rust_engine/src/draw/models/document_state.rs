#![allow(dead_code)]

use std::collections::{HashMap, HashSet};
use std::fmt;

use crate::draw::config::highlight_config::HighlightMaskConfig;
use crate::draw::config::watermark_config::WatermarkConfig;
use crate::draw::types::draw_point::DrawPoint;
use crate::draw::types::draw_rect::DrawRect;
use crate::draw::utils::spatial_index::{
    ElementState as SpatialIndexElementState, SpatialIndex, SpatialIndexEntry,
};

/// Persistent global elements attached to the document.
///
/// These elements are document-level overlays (for example highlight mask and
/// watermark) and participate in undo/redo like regular elements.
#[derive(Clone, Debug, Default, PartialEq)]
pub struct GlobalElementsState {
    /// Global highlight mask element data.
    pub highlight_mask: HighlightMaskConfig,

    /// Global watermark element data.
    pub watermark: WatermarkConfig,
}

impl GlobalElementsState {
    pub fn copy_with(
        &self,
        highlight_mask: Option<HighlightMaskConfig>,
        watermark: Option<WatermarkConfig>,
    ) -> Self {
        let next = Self {
            highlight_mask: highlight_mask.unwrap_or(self.highlight_mask),
            watermark: watermark.unwrap_or_else(|| self.watermark.clone()),
        };

        if next == *self {
            self.clone()
        } else {
            next
        }
    }
}

/// Binding descriptor stored on an arrow endpoint.
#[derive(Clone, Debug, PartialEq, Eq, Hash)]
pub struct ArrowBinding {
    pub element_id: String,
}

impl ArrowBinding {
    pub fn new(element_id: impl Into<String>) -> Self {
        Self {
            element_id: element_id.into(),
        }
    }
}

/// Shared data for arrow-like elements.
#[derive(Clone, Debug, Default, PartialEq)]
pub struct ArrowLikeData {
    pub start_binding: Option<ArrowBinding>,
    pub end_binding: Option<ArrowBinding>,
}

impl ArrowLikeData {
    pub fn copy_with(
        &self,
        start_binding: Option<Option<ArrowBinding>>,
        end_binding: Option<Option<ArrowBinding>>,
    ) -> Self {
        Self {
            start_binding: start_binding.unwrap_or_else(|| self.start_binding.clone()),
            end_binding: end_binding.unwrap_or_else(|| self.end_binding.clone()),
        }
    }
}

/// Serial-number payload relevant to `DocumentState` cache derivation.
#[derive(Clone, Debug, Default, PartialEq)]
pub struct SerialNumberData {
    pub text_element_id: Option<String>,
}

/// Highlight payload marker relevant to `DocumentState` filtering.
#[derive(Clone, Debug, Default, PartialEq)]
pub struct HighlightData;

/// Lightweight element payload classification used by `DocumentState`.
#[derive(Clone, Debug, Default, PartialEq)]
pub enum ElementData {
    ArrowLike(ArrowLikeData),
    SerialNumber(SerialNumberData),
    Highlight(HighlightData),
    Rectangle,
    Text,
    #[default]
    Other,
}

/// Element state (fully immutable).
#[derive(Clone, Debug, PartialEq)]
pub struct ElementState {
    pub id: String,
    pub rect: DrawRect,
    pub rotation: f64,
    pub opacity: f64,
    pub z_index: i64,
    pub data: ElementData,
}

impl ElementState {
    pub fn new(
        id: impl Into<String>,
        rect: DrawRect,
        rotation: f64,
        opacity: f64,
        z_index: i64,
        data: ElementData,
    ) -> Self {
        Self {
            id: id.into(),
            rect,
            rotation,
            opacity,
            z_index,
            data,
        }
    }
}

/// Patch payload for immutable `DocumentState` updates.
#[derive(Clone, Debug, Default, PartialEq)]
pub struct DocumentStatePatch {
    pub elements: Option<Vec<ElementState>>,
    pub elements_version: Option<i64>,
    pub global_elements: Option<GlobalElementsState>,
}

/// Persistent document data (lowest change frequency).
#[derive(Clone, Debug)]
pub struct DocumentState {
    /// All elements on the canvas, ordered by z-index.
    pub elements: Vec<ElementState>,

    /// Version counter for persisted element changes.
    ///
    /// Includes both regular element-list mutations and global element updates
    /// so downstream scene/event consumers can treat them uniformly.
    pub elements_version: i64,

    /// Persistent global document elements.
    pub global_elements: GlobalElementsState,

    element_map: HashMap<String, ElementState>,
    order_index: HashMap<String, usize>,
    spatial_index: SpatialIndex,
    arrow_bindable_elements: Vec<ElementState>,
    arrow_bindable_spatial_index: SpatialIndex,

    /// Cached set of text element IDs bound to serial numbers.
    pub bound_text_ids: HashSet<String>,

    /// Cached set of element IDs currently used by bound arrow endpoints.
    pub bound_arrow_target_ids: HashSet<String>,

    /// Whether the document currently contains any bindable arrow targets.
    pub has_arrow_bindable_elements: bool,

    /// Cached highlight elements in document z-order.
    pub highlight_elements: Vec<ElementState>,
}

impl DocumentState {
    pub fn new(
        elements: Vec<ElementState>,
        elements_version: i64,
        global_elements: GlobalElementsState,
    ) -> Self {
        let element_map = elements
            .iter()
            .cloned()
            .map(|element| (element.id.clone(), element))
            .collect::<HashMap<_, _>>();

        let order_index = elements
            .iter()
            .enumerate()
            .map(|(index, element)| (element.id.clone(), index))
            .collect::<HashMap<_, _>>();

        let spatial_index = SpatialIndex::from_elements(&to_spatial_index_elements(&elements));

        let arrow_bindable_elements = Self::build_arrow_bindable_elements(&elements);
        let arrow_bindable_spatial_index =
            SpatialIndex::from_elements(&to_spatial_index_elements(&arrow_bindable_elements));

        let bound_text_ids = Self::build_bound_text_ids(&elements);
        let bound_arrow_target_ids = Self::build_bound_arrow_target_ids(&elements);
        let has_arrow_bindable_elements = !arrow_bindable_elements.is_empty();
        let highlight_elements = Self::build_highlight_elements(&elements);

        Self {
            elements,
            elements_version,
            global_elements,
            element_map,
            order_index,
            spatial_index,
            arrow_bindable_elements,
            arrow_bindable_spatial_index,
            bound_text_ids,
            bound_arrow_target_ids,
            has_arrow_bindable_elements,
            highlight_elements,
        }
    }

    pub fn element_map(&self) -> &HashMap<String, ElementState> {
        &self.element_map
    }

    pub fn get_element_by_id(&self, id: &str) -> Option<&ElementState> {
        self.element_map.get(id)
    }

    pub fn get_order_index(&self, id: &str) -> Option<usize> {
        self.order_index.get(id).copied()
    }

    pub fn spatial_index(&self) -> &SpatialIndex {
        &self.spatial_index
    }

    pub fn arrow_bindable_elements(&self) -> &[ElementState] {
        &self.arrow_bindable_elements
    }

    /// Visits bindable arrow targets in arbitrary order.
    ///
    /// This uses the bindable-only spatial index to avoid scanning unrelated
    /// elements during endpoint binding lookups.
    pub fn visit_arrow_bindable_elements_at_point<F>(
        &self,
        point: DrawPoint,
        tolerance: f64,
        excluded_element_id: Option<&str>,
        mut visitor: F,
    ) where
        F: FnMut(&ElementState) -> bool,
    {
        if !self.has_arrow_bindable_elements {
            return;
        }

        let entries = self
            .arrow_bindable_spatial_index
            .search_point_entries_with_options(point, tolerance, true, false);

        for entry in entries {
            if excluded_element_id.is_some_and(|excluded| entry.id == excluded) {
                continue;
            }

            let Some(element) = self.element_for_entry(&entry) else {
                continue;
            };

            if !visitor(element) {
                return;
            }
        }
    }

    /// Touches cached indexes eagerly to avoid interactive stalls.
    pub fn warm_caches(&self) -> usize {
        self.element_map.len()
            + self.order_index.len()
            + self.spatial_index.size()
            + self.arrow_bindable_spatial_index.size()
            + self.bound_arrow_target_ids.len()
            + self.highlight_elements.len()
    }

    /// Returns `true` when any element in `element_ids` has bound arrow
    /// endpoints.
    pub fn has_arrow_bound_to_any<I, S>(&self, element_ids: I) -> bool
    where
        I: IntoIterator<Item = S>,
        S: AsRef<str>,
    {
        !self.bound_arrow_target_ids.is_empty()
            && element_ids
                .into_iter()
                .any(|id| self.bound_arrow_target_ids.contains(id.as_ref()))
    }

    pub fn has_element_at_point(&self, point: DrawPoint, tolerance: f64) -> bool {
        !self
            .spatial_index
            .search_point_entries_with_options(point, tolerance, true, false)
            .is_empty()
    }

    /// Queries elements intersecting `rect`, sorted by ascending z-order.
    pub fn query_elements_in_rect_ordered(&self, rect: DrawRect) -> Vec<ElementState> {
        self.spatial_index
            .search_rect_entries_with_options(rect, true, true)
            .into_iter()
            .filter_map(|entry| self.element_for_entry(&entry).cloned())
            .collect()
    }

    /// Queries point candidates sorted from top-most to bottom-most.
    pub fn query_elements_at_point_top_down(
        &self,
        point: DrawPoint,
        tolerance: f64,
    ) -> Vec<ElementState> {
        let mut result = Vec::new();
        self.visit_elements_at_point_top_down(point, tolerance, |element| {
            result.push(element.clone());
            true
        });
        result
    }

    /// Visits point candidates from top-most to bottom-most z-order.
    ///
    /// Returning `false` from `visitor` stops iteration early.
    pub fn visit_elements_at_point_top_down<F>(
        &self,
        point: DrawPoint,
        tolerance: f64,
        mut visitor: F,
    ) where
        F: FnMut(&ElementState) -> bool,
    {
        let entries = self.spatial_index.search_point_entries(point, tolerance);
        self.visit_entries(entries, &mut visitor);
    }

    /// Visits point candidates in arbitrary order.
    pub fn visit_elements_at_point<F>(&self, point: DrawPoint, tolerance: f64, mut visitor: F)
    where
        F: FnMut(&ElementState) -> bool,
    {
        let entries = self
            .spatial_index
            .search_point_entries_with_options(point, tolerance, true, false);
        self.visit_entries(entries, &mut visitor);
    }

    /// Visits rect-intersecting candidates in arbitrary order.
    pub fn visit_elements_in_rect<F>(&self, rect: DrawRect, mut visitor: F)
    where
        F: FnMut(&ElementState) -> bool,
    {
        let entries = self
            .spatial_index
            .search_rect_entries_with_options(rect, false, false);
        self.visit_entries(entries, &mut visitor);
    }

    pub fn copy_with(&self, patch: DocumentStatePatch) -> Self {
        let has_elements_changed = patch.elements.is_some();

        let next_elements = patch.elements.unwrap_or_else(|| self.elements.clone());
        let next_global_elements = patch
            .global_elements
            .unwrap_or_else(|| self.global_elements.clone());
        let has_global_elements_changed = next_global_elements != self.global_elements;

        let next_version = patch.elements_version.unwrap_or_else(|| {
            if has_elements_changed || has_global_elements_changed {
                self.elements_version + 1
            } else {
                self.elements_version
            }
        });

        Self::new(next_elements, next_version, next_global_elements)
    }

    fn element_for_entry(&self, entry: &SpatialIndexEntry) -> Option<&ElementState> {
        self.element_map.get(&entry.id)
    }

    fn visit_entries<F, I>(&self, entries: I, visitor: &mut F)
    where
        F: FnMut(&ElementState) -> bool,
        I: IntoIterator<Item = SpatialIndexEntry>,
    {
        for entry in entries {
            let Some(element) = self.element_for_entry(&entry) else {
                continue;
            };

            if !visitor(element) {
                return;
            }
        }
    }

    fn build_bound_text_ids(elements: &[ElementState]) -> HashSet<String> {
        let mut ids = HashSet::new();

        for element in elements {
            if let ElementData::SerialNumber(data) = &element.data {
                if let Some(text_element_id) = data.text_element_id.as_ref() {
                    ids.insert(text_element_id.clone());
                }
            }
        }

        ids
    }

    fn build_bound_arrow_target_ids(elements: &[ElementState]) -> HashSet<String> {
        let mut ids = HashSet::new();

        for element in elements {
            let ElementData::ArrowLike(data) = &element.data else {
                continue;
            };

            if let Some(binding) = data.start_binding.as_ref() {
                ids.insert(binding.element_id.clone());
            }

            if let Some(binding) = data.end_binding.as_ref() {
                ids.insert(binding.element_id.clone());
            }
        }

        ids
    }

    fn build_arrow_bindable_elements(elements: &[ElementState]) -> Vec<ElementState> {
        elements
            .iter()
            .filter(|element| element.opacity > 0.0 && is_bindable_target(element))
            .cloned()
            .collect()
    }

    fn build_highlight_elements(elements: &[ElementState]) -> Vec<ElementState> {
        elements
            .iter()
            .filter(|element| matches!(element.data, ElementData::Highlight(_)))
            .cloned()
            .collect()
    }
}

impl Default for DocumentState {
    fn default() -> Self {
        Self::new(Vec::new(), 0, GlobalElementsState::default())
    }
}

impl PartialEq for DocumentState {
    fn eq(&self, other: &Self) -> bool {
        self.elements == other.elements
            && self.elements_version == other.elements_version
            && self.global_elements == other.global_elements
    }
}

impl fmt::Display for DocumentState {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        write!(
            f,
            "DocumentState(elements: {}, version: {}, globalElements: {:?})",
            self.elements.len(),
            self.elements_version,
            self.global_elements
        )
    }
}

fn is_bindable_target(element: &ElementState) -> bool {
    matches!(
        element.data,
        ElementData::Rectangle | ElementData::Text | ElementData::SerialNumber(_)
    )
}

fn to_spatial_index_elements(elements: &[ElementState]) -> Vec<SpatialIndexElementState> {
    elements
        .iter()
        .map(|element| {
            SpatialIndexElementState::new(
                element.id.clone(),
                element.rect,
                element.rotation,
                element.z_index,
            )
        })
        .collect()
}

#[cfg(test)]
mod tests {
    use super::{
        ArrowBinding, ArrowLikeData, DocumentState, DocumentStatePatch, ElementData, ElementState,
        HighlightData, SerialNumberData,
    };
    use crate::draw::types::draw_point::DrawPoint;
    use crate::draw::types::draw_rect::DrawRect;

    fn rect(min_x: f64, min_y: f64, max_x: f64, max_y: f64) -> DrawRect {
        DrawRect::new(min_x, min_y, max_x, max_y)
    }

    fn element(id: &str, z_index: i64, data: ElementData) -> ElementState {
        ElementState::new(id, rect(0.0, 0.0, 10.0, 10.0), 0.0, 1.0, z_index, data)
    }

    #[test]
    fn computes_bound_text_ids_and_arrow_target_ids() {
        let state = DocumentState::new(
            vec![
                element(
                    "serial",
                    1,
                    ElementData::SerialNumber(SerialNumberData {
                        text_element_id: Some("text-1".to_string()),
                    }),
                ),
                element(
                    "arrow",
                    2,
                    ElementData::ArrowLike(ArrowLikeData {
                        start_binding: Some(ArrowBinding::new("target-a")),
                        end_binding: Some(ArrowBinding::new("target-b")),
                    }),
                ),
            ],
            0,
            Default::default(),
        );

        assert!(state.bound_text_ids.contains("text-1"));
        assert!(state.bound_arrow_target_ids.contains("target-a"));
        assert!(state.bound_arrow_target_ids.contains("target-b"));
    }

    #[test]
    fn query_point_top_down_uses_highest_z_first() {
        let mut low = element("low", 1, ElementData::Rectangle);
        let mut high = element("high", 2, ElementData::Rectangle);
        low.rect = rect(0.0, 0.0, 10.0, 10.0);
        high.rect = rect(0.0, 0.0, 10.0, 10.0);

        let state = DocumentState::new(vec![low, high], 0, Default::default());
        let hits = state.query_elements_at_point_top_down(DrawPoint::new(5.0, 5.0), 0.0);

        assert_eq!(hits.len(), 2);
        assert_eq!(hits[0].id, "high");
        assert_eq!(hits[1].id, "low");
    }

    #[test]
    fn highlight_cache_contains_only_highlight_elements() {
        let state = DocumentState::new(
            vec![
                element("a", 1, ElementData::Rectangle),
                element("h", 2, ElementData::Highlight(HighlightData)),
            ],
            0,
            Default::default(),
        );

        assert_eq!(state.highlight_elements.len(), 1);
        assert_eq!(state.highlight_elements[0].id, "h");
    }

    #[test]
    fn copy_with_increments_version_when_data_changes() {
        let state = DocumentState::new(
            vec![element("a", 1, ElementData::Rectangle)],
            5,
            Default::default(),
        );

        let next = state.copy_with(DocumentStatePatch {
            elements: Some(vec![element("b", 1, ElementData::Rectangle)]),
            ..DocumentStatePatch::default()
        });

        assert_eq!(next.elements_version, 6);
        assert_eq!(next.elements[0].id, "b");
    }
}
