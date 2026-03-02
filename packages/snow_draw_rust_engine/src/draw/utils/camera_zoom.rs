#![allow(dead_code)]

/// Returns a safe zoom factor for distance conversions.
///
/// Non-finite or non-positive values fall back to `1.0` so callers can
/// keep distance math stable even when camera data is temporarily invalid.
pub fn resolve_effective_zoom(zoom: f64) -> f64 {
    if zoom.is_finite() && zoom > 0.0 {
        zoom
    } else {
        1.0
    }
}

/// Converts a screen-space distance to world-space distance using `zoom`.
pub fn resolve_zoom_adjusted_distance(distance: f64, zoom: f64) -> f64 {
    distance / resolve_effective_zoom(zoom)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn resolves_effective_zoom_for_positive_finite_values() {
        assert_eq!(resolve_effective_zoom(2.5), 2.5);
    }

    #[test]
    fn resolves_effective_zoom_to_one_for_non_positive_values() {
        assert_eq!(resolve_effective_zoom(0.0), 1.0);
        assert_eq!(resolve_effective_zoom(-2.0), 1.0);
    }

    #[test]
    fn resolves_effective_zoom_to_one_for_non_finite_values() {
        assert_eq!(resolve_effective_zoom(f64::INFINITY), 1.0);
        assert_eq!(resolve_effective_zoom(f64::NEG_INFINITY), 1.0);
        assert_eq!(resolve_effective_zoom(f64::NAN), 1.0);
    }

    #[test]
    fn resolves_zoom_adjusted_distance_using_effective_zoom() {
        assert_eq!(resolve_zoom_adjusted_distance(10.0, 2.0), 5.0);
        assert_eq!(resolve_zoom_adjusted_distance(10.0, 0.0), 10.0);
    }
}
