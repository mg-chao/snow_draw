#![allow(dead_code)]

use crate::draw::types::draw_point::DrawPoint;
use crate::draw::types::draw_rect::DrawRect;
use std::fmt;
use std::hash::{Hash, Hasher};

/// Immutable geometry metadata for the current selection.
///
/// This mirrors the Dart model and enforces the same invariants:
/// when `has_selection` is `false`, optional geometry fields are cleared and
/// `is_multi_select` is forced to `false`.
#[derive(Clone, Copy, Debug, PartialEq)]
pub struct SelectionGeometry {
    pub bounds: Option<DrawRect>,
    pub center: Option<DrawPoint>,
    pub rotation: Option<f64>,
    pub has_selection: bool,
    pub is_multi_select: bool,
}

impl SelectionGeometry {
    /// Equivalent to Dart's `SelectionGeometry.none`.
    pub const NONE: Self = Self {
        bounds: None,
        center: None,
        rotation: None,
        has_selection: false,
        is_multi_select: false,
    };

    /// Creates selection geometry with Dart constructor semantics.
    pub const fn new(
        bounds: Option<DrawRect>,
        center: Option<DrawPoint>,
        rotation: Option<f64>,
        has_selection: bool,
        is_multi_select: bool,
    ) -> Self {
        if has_selection {
            Self {
                bounds,
                center,
                rotation,
                has_selection: true,
                is_multi_select,
            }
        } else {
            Self::NONE
        }
    }

    /// Returns the canonical empty selection.
    pub const fn none() -> Self {
        Self::NONE
    }

    /// Returns whether exactly one element is selected.
    pub const fn is_single_select(self) -> bool {
        self.has_selection && !self.is_multi_select
    }
}

impl Default for SelectionGeometry {
    fn default() -> Self {
        Self::NONE
    }
}

impl Hash for SelectionGeometry {
    fn hash<H: Hasher>(&self, state: &mut H) {
        match self.bounds {
            Some(bounds) => {
                1u8.hash(state);
                bounds.min_x.to_bits().hash(state);
                bounds.min_y.to_bits().hash(state);
                bounds.max_x.to_bits().hash(state);
                bounds.max_y.to_bits().hash(state);
            }
            None => 0u8.hash(state),
        }

        self.center.hash(state);

        match self.rotation {
            Some(rotation) => {
                1u8.hash(state);
                rotation.to_bits().hash(state);
            }
            None => 0u8.hash(state),
        }

        self.has_selection.hash(state);
        self.is_multi_select.hash(state);
    }
}

impl fmt::Display for SelectionGeometry {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        write!(
            f,
            "SelectionGeometry(bounds: {:?}, center: {:?}, rotation: {:?}, hasSelection: {}, isMultiSelect: {})",
            self.bounds, self.center, self.rotation, self.has_selection, self.is_multi_select
        )
    }
}
