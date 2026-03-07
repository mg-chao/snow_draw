#![allow(dead_code)]

use crate::draw::elements::types::arrow::arrow_binding::ArrowBindingUtils;
use crate::draw::elements::types::arrow::elbow::elbow_constants::ElbowConstants;
use crate::draw::elements::types::arrow::elbow::elbow_heading::ElbowHeading;
use crate::draw::types::draw_rect::DrawRect;

/// Shared spacing calculations for elbow routing and editing.
///
/// Translated from:
/// `packages/snow_draw_engine/lib/draw/elements/types/arrow/elbow/elbow_spacing.dart`.
pub struct ElbowSpacing;

impl ElbowSpacing {
    /// Gap between a bound anchor and the routed elbow point.
    pub fn binding_gap(has_arrowhead: bool) -> f64 {
        ArrowBindingUtils::ELBOW_BINDING_GAP_BASE
            * if has_arrowhead {
                ArrowBindingUtils::ELBOW_ARROWHEAD_GAP_MULTIPLIER
            } else {
                ElbowConstants::ELBOW_NO_ARROWHEAD_GAP_MULTIPLIER
            }
    }

    /// Padding used when inflating obstacle bounds near the arrowhead side.
    pub fn head_padding(has_arrowhead: bool) -> f64 {
        (ElbowConstants::BASE_PADDING - Self::binding_gap(has_arrowhead)).max(0.0)
    }

    /// Minimum padding when aligning fixed neighbors during editing.
    pub fn fixed_neighbor_padding(has_arrowhead: bool) -> f64 {
        let padding = Self::head_padding(has_arrowhead);
        if !padding.is_finite() || padding <= ElbowConstants::DEDUP_THRESHOLD {
            return ElbowConstants::DIRECTION_FIX_PADDING;
        }

        ElbowConstants::DIRECTION_FIX_PADDING.max(padding)
    }

    /// Minimum spacing between a bound element edge and the routed path.
    ///
    /// This is the base binding gap, scaled by the arrowhead multiplier when
    /// an arrowhead is present.
    pub fn min_binding_spacing(has_arrowhead: bool) -> f64 {
        let base = ArrowBindingUtils::ELBOW_BINDING_GAP_BASE;
        if has_arrowhead {
            base * ArrowBindingUtils::ELBOW_ARROWHEAD_GAP_MULTIPLIER
        } else {
            base
        }
    }

    /// Reads the current spacing between `element_bounds` and `obstacle`
    /// along the exit axis defined by `heading`.
    ///
    /// Returns `None` when spacing is non-finite or at/below epsilon.
    pub fn resolve_obstacle_spacing(
        element_bounds: DrawRect,
        obstacle: DrawRect,
        heading: ElbowHeading,
    ) -> Option<f64> {
        let spacing = match heading {
            ElbowHeading::Up => element_bounds.min_y - obstacle.min_y,
            ElbowHeading::Right => obstacle.max_x - element_bounds.max_x,
            ElbowHeading::Down => obstacle.max_y - element_bounds.max_y,
            ElbowHeading::Left => element_bounds.min_x - obstacle.min_x,
        };

        if spacing.is_finite() && spacing > ElbowConstants::INTERSECTION_EPSILON {
            Some(spacing)
        } else {
            None
        }
    }

    /// Adjusts `obstacle` so that the exit edge along `heading` sits exactly
    /// `spacing` away from `element_bounds`.
    pub fn apply_obstacle_spacing(
        obstacle: DrawRect,
        element_bounds: DrawRect,
        heading: ElbowHeading,
        spacing: f64,
    ) -> DrawRect {
        match heading {
            ElbowHeading::Up => {
                obstacle.copy_with(None, Some(element_bounds.min_y - spacing), None, None)
            }
            ElbowHeading::Right => {
                obstacle.copy_with(None, None, Some(element_bounds.max_x + spacing), None)
            }
            ElbowHeading::Down => {
                obstacle.copy_with(None, None, None, Some(element_bounds.max_y + spacing))
            }
            ElbowHeading::Left => {
                obstacle.copy_with(Some(element_bounds.min_x - spacing), None, None, None)
            }
        }
    }

    /// Resolves a shared spacing value from two endpoint spacings.
    ///
    /// Takes the minimum of the two spacings and clamps it to the minimum
    /// allowed binding spacing for either endpoint. Returns `None` when either
    /// spacing is `None` or when the result is non-finite.
    pub fn resolve_shared_spacing(
        start_spacing: Option<f64>,
        end_spacing: Option<f64>,
        start_has_arrowhead: bool,
        end_has_arrowhead: bool,
    ) -> Option<f64> {
        let (Some(start_spacing), Some(end_spacing)) = (start_spacing, end_spacing) else {
            return None;
        };

        let shared = start_spacing.min(end_spacing);
        if !shared.is_finite() {
            return None;
        }

        let min_allowed = Self::min_binding_spacing(start_has_arrowhead)
            .max(Self::min_binding_spacing(end_has_arrowhead));
        Some(shared.max(min_allowed))
    }
}

/// Gap between a bound anchor and the routed elbow point.
pub fn binding_gap(has_arrowhead: bool) -> f64 {
    ElbowSpacing::binding_gap(has_arrowhead)
}

/// Padding used when inflating obstacle bounds near the arrowhead side.
pub fn head_padding(has_arrowhead: bool) -> f64 {
    ElbowSpacing::head_padding(has_arrowhead)
}

/// Minimum padding when aligning fixed neighbors during editing.
pub fn fixed_neighbor_padding(has_arrowhead: bool) -> f64 {
    ElbowSpacing::fixed_neighbor_padding(has_arrowhead)
}

/// Minimum spacing between a bound element edge and the routed path.
pub fn min_binding_spacing(has_arrowhead: bool) -> f64 {
    ElbowSpacing::min_binding_spacing(has_arrowhead)
}

/// Reads the current spacing between `element_bounds` and `obstacle`.
pub fn resolve_obstacle_spacing(
    element_bounds: DrawRect,
    obstacle: DrawRect,
    heading: ElbowHeading,
) -> Option<f64> {
    ElbowSpacing::resolve_obstacle_spacing(element_bounds, obstacle, heading)
}

/// Adjusts `obstacle` so that the exit edge along `heading` sits exactly
/// `spacing` away from `element_bounds`.
pub fn apply_obstacle_spacing(
    obstacle: DrawRect,
    element_bounds: DrawRect,
    heading: ElbowHeading,
    spacing: f64,
) -> DrawRect {
    ElbowSpacing::apply_obstacle_spacing(obstacle, element_bounds, heading, spacing)
}

/// Resolves a shared spacing value from two endpoint spacings.
pub fn resolve_shared_spacing(
    start_spacing: Option<f64>,
    end_spacing: Option<f64>,
    start_has_arrowhead: bool,
    end_has_arrowhead: bool,
) -> Option<f64> {
    ElbowSpacing::resolve_shared_spacing(
        start_spacing,
        end_spacing,
        start_has_arrowhead,
        end_has_arrowhead,
    )
}
