#![allow(dead_code)]

/// Multiplier used to derive the loop-closing threshold from hit radius.
const ARROW_POINT_LOOP_THRESHOLD_FACTOR: f64 = 1.5;

/// Multiplier used to render arrow-point handles larger than control points.
///
/// Mirrors `ConfigDefaults.arrowPointSizeMultiplier` in the Dart engine.
const ARROW_POINT_SIZE_MULTIPLIER: f64 = 1.25;

/// Resolves the loop-closing threshold for arrow-point interactions.
pub fn resolve_arrow_point_loop_threshold(hit_radius: f64) -> f64 {
    if !hit_radius.is_finite() || hit_radius <= 0.0 {
        return 0.0;
    }
    hit_radius * ARROW_POINT_LOOP_THRESHOLD_FACTOR
}

/// Resolves rendered arrow-point handle size from control-point size.
pub fn resolve_arrow_point_handle_size(control_point_size: f64) -> f64 {
    if !control_point_size.is_finite() || control_point_size <= 0.0 {
        return 0.0;
    }
    control_point_size * ARROW_POINT_SIZE_MULTIPLIER
}

/// Resolves the loop-closing threshold for connector-point interactions.
pub fn resolve_connector_point_loop_threshold(hit_radius: f64) -> f64 {
    resolve_arrow_point_loop_threshold(hit_radius)
}

/// Resolves rendered connector-point handle size from control-point size.
pub fn resolve_connector_point_handle_size(control_point_size: f64) -> f64 {
    resolve_arrow_point_handle_size(control_point_size)
}
