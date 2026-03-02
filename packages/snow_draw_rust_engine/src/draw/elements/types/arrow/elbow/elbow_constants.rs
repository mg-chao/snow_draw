#![allow(dead_code)]

/// Shared geometry constants for elbow arrow routing and editing.
///
/// Translated from:
/// `packages/snow_draw_engine/lib/draw/elements/types/arrow/elbow/elbow_constants.dart`.
pub struct ElbowConstants;

impl ElbowConstants {
    /// Threshold used when deduplicating nearby points.
    pub const DEDUP_THRESHOLD: f64 = 1.0;

    /// Epsilon used for robust floating-point intersection checks.
    pub const INTERSECTION_EPSILON: f64 = 1e-6;

    /// Minimum arrow length accepted by elbow routing.
    pub const MIN_ARROW_LENGTH: f64 = 8.0;

    /// Clamp bound for very large coordinates.
    pub const MAX_POSITION: f64 = 1_000_000.0;

    /// Baseline padding used in elbow routing calculations.
    pub const BASE_PADDING: f64 = 42.0;

    /// Extra padding around endpoint exits.
    pub const EXIT_POINT_PADDING: f64 = 2.0;

    /// Gap multiplier applied when there is no arrowhead.
    pub const ELBOW_NO_ARROWHEAD_GAP_MULTIPLIER: f64 = 2.0;

    /// Padding from element edges while routing.
    pub const ELEMENT_SIDE_PADDING: f64 = 8.0;

    /// Padding used to stabilize direction fixes.
    pub const DIRECTION_FIX_PADDING: f64 = 12.0;
}
