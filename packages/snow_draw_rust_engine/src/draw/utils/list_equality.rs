#![allow(dead_code)]

use crate::draw::types::draw_point::DrawPoint;
use crate::draw::types::edit_transform::ElbowFixedSegment;
use std::collections::HashMap;
use std::hash::{BuildHasher, Hash, Hasher};

/// Returns `true` when two slices are equal element-by-element using
/// `element_equals`.
pub fn list_equals_by<T, F>(a: &[T], b: &[T], mut element_equals: F) -> bool
where
    F: FnMut(&T, &T) -> bool,
{
    if std::ptr::eq(a, b) {
        return true;
    }

    if a.len() != b.len() {
        return false;
    }

    a.iter()
        .zip(b.iter())
        .all(|(left, right)| element_equals(left, right))
}

/// Returns `true` when two slices are equal using `PartialEq`.
pub fn list_equals<T>(a: &[T], b: &[T]) -> bool
where
    T: PartialEq,
{
    list_equals_by(a, b, |left, right| left == right)
}

/// Computes a positional hash for a slice.
pub fn list_hash<T>(values: &[T]) -> u64
where
    T: Hash,
{
    hash_all(values.iter().map(hash_value))
}

/// Nullable variant of [`list_equals_by`].
pub fn nullable_list_equals_by<T, F>(a: Option<&[T]>, b: Option<&[T]>, element_equals: F) -> bool
where
    F: FnMut(&T, &T) -> bool,
{
    match (a, b) {
        (None, None) => true,
        (Some(left), Some(right)) => list_equals_by(left, right, element_equals),
        _ => false,
    }
}

/// Nullable variant of [`list_equals`].
pub fn nullable_list_equals<T>(a: Option<&[T]>, b: Option<&[T]>) -> bool
where
    T: PartialEq,
{
    nullable_list_equals_by(a, b, |left, right| left == right)
}

/// Computes a deterministic hash for a map by sorting keys by their string
/// representation before hashing entries.
pub fn map_hash<K, V, S>(map: &HashMap<K, V, S>) -> u64
where
    K: Eq + Hash + ToString,
    V: Hash,
    S: BuildHasher,
{
    if map.is_empty() {
        return 0;
    }

    let mut sorted_entries: Vec<(&K, &V)> = map.iter().collect();
    sorted_entries
        .sort_by(|(left_key, _), (right_key, _)| left_key.to_string().cmp(&right_key.to_string()));

    hash_all(sorted_entries.into_iter().map(|(key, value)| {
        let mut hasher = std::collections::hash_map::DefaultHasher::new();
        key.hash(&mut hasher);
        value.hash(&mut hasher);
        hasher.finish()
    }))
}

/// Returns `true` when two maps are equal using `value_equals` for values.
pub fn map_equals_by<K, V, SA, SB, F>(
    a: &HashMap<K, V, SA>,
    b: &HashMap<K, V, SB>,
    mut value_equals: F,
) -> bool
where
    K: Eq + Hash,
    SA: BuildHasher,
    SB: BuildHasher,
    F: FnMut(&V, &V) -> bool,
{
    if a.len() != b.len() {
        return false;
    }

    for (key, left_value) in a {
        let Some(right_value) = b.get(key) else {
            return false;
        };

        if !value_equals(left_value, right_value) {
            return false;
        }
    }

    true
}

/// Returns `true` when two maps are equal using value `PartialEq`.
pub fn map_equals<K, V, SA, SB>(a: &HashMap<K, V, SA>, b: &HashMap<K, V, SB>) -> bool
where
    K: Eq + Hash,
    V: PartialEq,
    SA: BuildHasher,
    SB: BuildHasher,
{
    map_equals_by(a, b, |left, right| left == right)
}

/// Returns `true` when two `DrawPoint` lists are equal.
pub fn point_list_equals(a: &[DrawPoint], b: &[DrawPoint]) -> bool {
    list_equals(a, b)
}

/// Returns `true` when two optional fixed-segment lists are equal.
pub fn fixed_segment_list_equals(
    a: Option<&[ElbowFixedSegment]>,
    b: Option<&[ElbowFixedSegment]>,
) -> bool {
    nullable_list_equals(a, b)
}

/// Returns whether the segment formed by `a` and `b` is horizontal.
pub fn segment_is_horizontal(a: DrawPoint, b: DrawPoint) -> bool {
    (a.y - b.y).abs() <= (a.x - b.x).abs()
}

/// Returns structural equality for optional fixed-segment lists.
///
/// The current Rust `ElbowFixedSegment` type is still a placeholder in this
/// crate, so this falls back to strict item equality for now.
pub fn fixed_segment_structure_equals(
    a: Option<&[ElbowFixedSegment]>,
    b: Option<&[ElbowFixedSegment]>,
) -> bool {
    nullable_list_equals_by(a, b, |left, right| {
        fixed_segment_structure_item_equals(left, right, None)
    })
}

/// Returns structural equality for optional fixed-segment lists with tolerance.
///
/// The current Rust `ElbowFixedSegment` type is still a placeholder in this
/// crate, so this falls back to strict item equality for now.
pub fn fixed_segment_structure_equals_with_tolerance(
    a: Option<&[ElbowFixedSegment]>,
    b: Option<&[ElbowFixedSegment]>,
    tolerance: f64,
) -> bool {
    assert!(tolerance >= 0.0, "tolerance must be non-negative.");

    nullable_list_equals_by(a, b, |left, right| {
        fixed_segment_structure_item_equals(left, right, Some(tolerance))
    })
}

fn fixed_segment_structure_item_equals(
    a: &ElbowFixedSegment,
    b: &ElbowFixedSegment,
    _tolerance: Option<f64>,
) -> bool {
    a == b
}

fn hash_value<T>(value: &T) -> u64
where
    T: Hash,
{
    let mut hasher = std::collections::hash_map::DefaultHasher::new();
    value.hash(&mut hasher);
    hasher.finish()
}

fn hash_all(values: impl IntoIterator<Item = u64>) -> u64 {
    values
        .into_iter()
        .fold(0_u64, |acc, value| acc.wrapping_mul(31).wrapping_add(value))
}
