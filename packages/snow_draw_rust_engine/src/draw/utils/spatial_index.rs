#![allow(dead_code)]

use std::collections::HashMap;
use std::hash::{Hash, Hasher};

use crate::draw::types::draw_point::DrawPoint;
use crate::draw::types::draw_rect::DrawRect;
use rstar::{RTree, RTreeObject, AABB};

/// Minimal element model required by [`SpatialIndex`].
///
/// This local compatibility shape keeps the module usable while the full
/// `models::element_state` translation is still in progress.
#[derive(Clone, Debug, PartialEq)]
pub struct ElementState {
    pub id: String,
    pub rect: DrawRect,
    pub rotation: f64,
    pub z_index: i64,
}

impl ElementState {
    pub fn new(id: impl Into<String>, rect: DrawRect, rotation: f64, z_index: i64) -> Self {
        Self {
            id: id.into(),
            rect,
            rotation,
            z_index,
        }
    }
}

/// Entry payload returned from spatial queries.
///
/// Equality and hashing follow Dart behavior: entries are identified only by
/// `id`, not by `z_index`.
#[derive(Clone, Debug)]
pub struct SpatialIndexEntry {
    pub id: String,
    pub z_index: i64,
}

impl SpatialIndexEntry {
    pub fn new(id: impl Into<String>, z_index: i64) -> Self {
        Self {
            id: id.into(),
            z_index,
        }
    }
}

impl PartialEq for SpatialIndexEntry {
    fn eq(&self, other: &Self) -> bool {
        self.id == other.id
    }
}

impl Eq for SpatialIndexEntry {}

impl Hash for SpatialIndexEntry {
    fn hash<H: Hasher>(&self, state: &mut H) {
        self.id.hash(state);
    }
}

#[derive(Clone, Debug, PartialEq)]
struct IndexedSpatialEntry {
    envelope: AABB<[f64; 2]>,
    entry: SpatialIndexEntry,
}

impl RTreeObject for IndexedSpatialEntry {
    type Envelope = AABB<[f64; 2]>;

    fn envelope(&self) -> Self::Envelope {
        self.envelope
    }
}

/// 2D spatial index over element AABBs.
///
/// This mirrors Dart `SpatialIndex` behavior using an `rstar::RTree` backend.
/// A side map keyed by id is kept to support remove-by-id semantics.
#[derive(Clone, Debug, Default)]
pub struct SpatialIndex {
    tree: RTree<IndexedSpatialEntry>,
    entries_by_id: HashMap<String, IndexedSpatialEntry>,
}

impl SpatialIndex {
    pub fn new() -> Self {
        Self::default()
    }

    pub fn from_elements(elements: &[ElementState]) -> Self {
        let mut index = Self::new();
        index.bulk_load(elements);
        index
    }

    /// Inserts many elements.
    ///
    /// Dart bulk-load uses list order as `zIndex`; this method preserves that.
    pub fn bulk_load(&mut self, elements: &[ElementState]) {
        if elements.is_empty() {
            return;
        }

        for (z_index, element) in elements.iter().enumerate() {
            let indexed = Self::entry_from_element(element, z_index as i64);
            self.upsert(indexed);
        }
    }

    /// Inserts or replaces one element.
    pub fn insert(&mut self, element: &ElementState) {
        let indexed = Self::entry_from_element(element, element.z_index);
        self.upsert(indexed);
    }

    /// Removes an entry by id.
    ///
    /// The provided element geometry does not need to match the stored one.
    pub fn remove(&mut self, element: &ElementState) {
        self.remove_by_id(&element.id);
    }

    pub fn search_point_entries(&self, point: DrawPoint, tolerance: f64) -> Vec<SpatialIndexEntry> {
        self.search_point_entries_with_options(point, tolerance, true, true)
    }

    pub fn search_point_entries_with_options(
        &self,
        point: DrawPoint,
        tolerance: f64,
        descending: bool,
        sort_by_z: bool,
    ) -> Vec<SpatialIndexEntry> {
        let envelope = AABB::from_corners(
            [point.x - tolerance, point.y - tolerance],
            [point.x + tolerance, point.y + tolerance],
        );
        let mut entries: Vec<SpatialIndexEntry> = self
            .tree
            .locate_in_envelope_intersecting(&envelope)
            .map(|item| item.entry.clone())
            .collect();

        if sort_by_z && entries.len() > 1 {
            if descending {
                entries.sort_by(|a, b| b.z_index.cmp(&a.z_index));
            } else {
                entries.sort_by(|a, b| a.z_index.cmp(&b.z_index));
            }
        }

        entries
    }

    pub fn search_rect_entries(&self, rect: DrawRect) -> Vec<SpatialIndexEntry> {
        self.search_rect_entries_with_options(rect, false, true)
    }

    pub fn search_rect_entries_with_options(
        &self,
        rect: DrawRect,
        ascending: bool,
        sort_by_z: bool,
    ) -> Vec<SpatialIndexEntry> {
        let envelope = Self::aabb_from_rect(rect);
        let mut entries: Vec<SpatialIndexEntry> = self
            .tree
            .locate_in_envelope_intersecting(&envelope)
            .map(|item| item.entry.clone())
            .collect();

        if sort_by_z && entries.len() > 1 {
            if ascending {
                entries.sort_by(|a, b| a.z_index.cmp(&b.z_index));
            } else {
                entries.sort_by(|a, b| b.z_index.cmp(&a.z_index));
            }
        }

        entries
    }

    pub fn search_point(&self, point: DrawPoint, tolerance: f64) -> Vec<String> {
        self.search_point_entries(point, tolerance)
            .into_iter()
            .map(|entry| entry.id)
            .collect()
    }

    pub fn search_rect(&self, rect: DrawRect) -> Vec<String> {
        self.search_rect_entries(rect)
            .into_iter()
            .map(|entry| entry.id)
            .collect()
    }

    pub fn get_all_ids(&self) -> Vec<String> {
        self.tree.iter().map(|item| item.entry.id.clone()).collect()
    }

    pub fn size(&self) -> usize {
        self.entries_by_id.len()
    }

    pub fn clear(&mut self) {
        self.tree = RTree::new();
        self.entries_by_id.clear();
    }

    fn upsert(&mut self, indexed: IndexedSpatialEntry) {
        if let Some(previous) = self
            .entries_by_id
            .insert(indexed.entry.id.clone(), indexed.clone())
        {
            self.tree.remove(&previous);
        }
        self.tree.insert(indexed);
    }

    fn remove_by_id(&mut self, id: &str) -> Option<IndexedSpatialEntry> {
        let previous = self.entries_by_id.remove(id)?;
        self.tree.remove(&previous);
        Some(previous)
    }

    fn entry_from_element(element: &ElementState, z_index: i64) -> IndexedSpatialEntry {
        let rect = Self::aabb_from_element(element);
        IndexedSpatialEntry {
            envelope: Self::aabb_from_rect(rect),
            entry: SpatialIndexEntry::new(element.id.clone(), z_index),
        }
    }

    fn aabb_from_rect(rect: DrawRect) -> AABB<[f64; 2]> {
        AABB::from_corners([rect.min_x, rect.min_y], [rect.max_x, rect.max_y])
    }

    fn aabb_from_element(element: &ElementState) -> DrawRect {
        let rect = element.rect;
        let rotation = element.rotation;
        if rotation == 0.0 {
            return rect;
        }

        let center = rect.center();
        let half_width = rect.width().abs() / 2.0;
        let half_height = rect.height().abs() / 2.0;
        let cos_theta = rotation.cos().abs();
        let sin_theta = rotation.sin().abs();
        let extent_x = cos_theta * half_width + sin_theta * half_height;
        let extent_y = sin_theta * half_width + cos_theta * half_height;

        DrawRect::new(
            center.x - extent_x,
            center.y - extent_y,
            center.x + extent_x,
            center.y + extent_y,
        )
    }
}

#[cfg(test)]
mod tests {
    use std::f64::consts::FRAC_PI_2;

    use super::{ElementState, SpatialIndex};
    use crate::draw::types::draw_point::DrawPoint;
    use crate::draw::types::draw_rect::DrawRect;

    #[test]
    fn bulk_load_uses_list_order_for_z_index() {
        let elements = vec![
            ElementState::new("a", DrawRect::new(0.0, 0.0, 10.0, 10.0), 0.0, 100),
            ElementState::new("b", DrawRect::new(0.0, 0.0, 10.0, 10.0), 0.0, 200),
        ];

        let mut index = SpatialIndex::new();
        index.bulk_load(&elements);

        let ids = index.search_point(DrawPoint::new(5.0, 5.0), 0.0);
        assert_eq!(ids, vec!["b".to_string(), "a".to_string()]);
    }

    #[test]
    fn remove_matches_by_id() {
        let mut index = SpatialIndex::new();
        index.insert(&ElementState::new(
            "target",
            DrawRect::new(0.0, 0.0, 10.0, 10.0),
            0.0,
            7,
        ));

        index.remove(&ElementState::new(
            "target",
            DrawRect::new(100.0, 100.0, 200.0, 200.0),
            FRAC_PI_2,
            1,
        ));

        assert!(index.search_point(DrawPoint::new(5.0, 5.0), 0.0).is_empty());
        assert_eq!(index.size(), 0);
    }

    #[test]
    fn rotated_aabb_is_searchable() {
        let mut index = SpatialIndex::new();
        index.insert(&ElementState::new(
            "rotated",
            DrawRect::new(0.0, 0.0, 4.0, 2.0),
            FRAC_PI_2,
            1,
        ));

        let hits = index.search_rect(DrawRect::new(1.0, -1.0, 3.0, 3.0));
        assert_eq!(hits, vec!["rotated".to_string()]);
    }
}
