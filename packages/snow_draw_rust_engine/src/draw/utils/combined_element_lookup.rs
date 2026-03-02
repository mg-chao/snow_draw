#![allow(dead_code)]

use std::collections::HashMap;

/// A read-only view that combines a base element map with overlay updates.
///
/// This avoids allocating a new map when code needs to query both document
/// elements and preview/updated elements. Lookups always check the overlay
/// first and then fall back to the base map.
#[derive(Clone, Copy, Debug)]
pub struct CombinedElementLookup<'a, T> {
    /// The base element map (typically `document.element_map`).
    pub base: &'a HashMap<String, T>,
    /// The overlay map (typically updated or preview elements).
    pub overlay: &'a HashMap<String, T>,
}

impl<'a, T> CombinedElementLookup<'a, T> {
    /// Creates a lookup view backed by `base` and `overlay`.
    pub fn new(base: &'a HashMap<String, T>, overlay: &'a HashMap<String, T>) -> Self {
        Self { base, overlay }
    }

    /// Looks up an element by id, checking the overlay first.
    pub fn get(&self, id: &str) -> Option<&T> {
        self.overlay.get(id).or_else(|| self.base.get(id))
    }

    /// Returns `true` if the element exists in either map.
    pub fn contains_key(&self, id: &str) -> bool {
        self.get(id).is_some()
    }

    /// Returns an iterator of all keys from both maps.
    ///
    /// Overlay keys are yielded first. Base keys that are shadowed by overlay
    /// entries are skipped.
    pub fn keys(&self) -> impl Iterator<Item = &String> + '_ {
        self.overlay.keys().chain(
            self.base
                .keys()
                .filter(|key| !self.overlay.contains_key(*key)),
        )
    }

    /// Returns an iterator of all values from both maps.
    ///
    /// Overlay values are yielded first. Base values whose keys are present in
    /// overlay are skipped.
    pub fn values(&self) -> impl Iterator<Item = &T> + '_ {
        self.overlay.values().chain(
            self.base
                .iter()
                .filter(|(key, _)| !self.overlay.contains_key(*key))
                .map(|(_, value)| value),
        )
    }

    /// Creates a concrete merged map from this lookup view.
    ///
    /// Use sparingly and prefer lookup access when possible.
    pub fn to_map(&self) -> HashMap<String, T>
    where
        T: Clone,
    {
        let mut merged = self.base.clone();
        merged.extend(
            self.overlay
                .iter()
                .map(|(key, value)| (key.clone(), value.clone())),
        );
        merged
    }
}

impl<'a, T> From<(&'a HashMap<String, T>, &'a HashMap<String, T>)>
    for CombinedElementLookup<'a, T>
{
    fn from((base, overlay): (&'a HashMap<String, T>, &'a HashMap<String, T>)) -> Self {
        Self::new(base, overlay)
    }
}
