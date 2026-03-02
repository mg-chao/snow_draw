#![allow(dead_code)]

use crate::draw::types::draw_point::DrawPoint;
use crate::draw::utils::spatial_index::ElementState;

/// Reusable cache for nearby arrow-binding target queries.
///
/// Stores the last spatial query result and reuses it while the pointer stays
/// within a small threshold and the document version remains unchanged.
#[derive(Clone, Debug)]
pub struct ArrowBindingTargetCache<T = ElementState> {
    last_position: Option<DrawPoint>,
    last_distance: f64,
    elements_version: i64,
    targets: Vec<T>,
}

impl<T> Default for ArrowBindingTargetCache<T> {
    fn default() -> Self {
        Self {
            last_position: None,
            last_distance: 0.0,
            elements_version: -1,
            targets: Vec::new(),
        }
    }
}

impl<T> ArrowBindingTargetCache<T> {
    pub fn new() -> Self {
        Self::default()
    }

    pub fn targets(&self) -> &[T] {
        &self.targets
    }

    pub fn is_valid(
        &self,
        position: DrawPoint,
        threshold: f64,
        distance: f64,
        elements_version: i64,
    ) -> bool {
        let Some(last_position) = self.last_position else {
            return false;
        };
        if threshold <= 0.0 {
            return false;
        }
        if self.elements_version != elements_version || self.last_distance != distance {
            return false;
        }

        Self::is_within_threshold(last_position, position, threshold)
    }

    pub fn update(
        &mut self,
        position: DrawPoint,
        distance: f64,
        elements_version: i64,
        targets: Vec<T>,
    ) {
        self.last_position = Some(position);
        self.last_distance = distance;
        self.elements_version = elements_version;
        self.targets = targets;
    }

    pub fn reset(&mut self) {
        self.last_position = None;
        self.last_distance = 0.0;
        self.elements_version = -1;
        self.targets.clear();
    }

    fn is_within_threshold(from: DrawPoint, to: DrawPoint, threshold: f64) -> bool {
        from.distance_squared(to) <= threshold * threshold
    }
}

#[cfg(test)]
mod tests {
    use super::ArrowBindingTargetCache;
    use crate::draw::types::draw_point::DrawPoint;

    #[test]
    fn cache_is_invalid_before_first_update() {
        let cache = ArrowBindingTargetCache::<i32>::new();

        assert!(!cache.is_valid(DrawPoint::new(10.0, 10.0), 4.0, 12.0, 1));
    }

    #[test]
    fn cache_is_valid_for_same_version_distance_and_nearby_position() {
        let mut cache = ArrowBindingTargetCache::new();
        let targets = vec![1, 2, 3];
        cache.update(DrawPoint::new(100.0, 200.0), 40.0, 7, targets.clone());

        assert!(cache.is_valid(DrawPoint::new(103.0, 204.0), 5.0, 40.0, 7));
        assert_eq!(cache.targets(), targets.as_slice());
    }

    #[test]
    fn cache_is_invalid_when_outside_threshold_or_metadata_changes() {
        let mut cache = ArrowBindingTargetCache::<i32>::new();
        cache.update(DrawPoint::new(0.0, 0.0), 20.0, 5, vec![42]);

        assert!(!cache.is_valid(DrawPoint::new(4.0, 0.0), 3.0, 20.0, 5));
        assert!(!cache.is_valid(DrawPoint::new(1.0, 1.0), 3.0, 19.0, 5));
        assert!(!cache.is_valid(DrawPoint::new(1.0, 1.0), 3.0, 20.0, 6));
        assert!(!cache.is_valid(DrawPoint::new(1.0, 1.0), 0.0, 20.0, 5));
    }

    #[test]
    fn reset_clears_cached_state() {
        let mut cache = ArrowBindingTargetCache::<i32>::new();
        cache.update(DrawPoint::new(8.0, 9.0), 10.0, 11, vec![1, 2]);

        cache.reset();

        assert!(!cache.is_valid(DrawPoint::new(8.0, 9.0), 1.0, 10.0, 11));
        assert!(cache.targets().is_empty());
    }
}
