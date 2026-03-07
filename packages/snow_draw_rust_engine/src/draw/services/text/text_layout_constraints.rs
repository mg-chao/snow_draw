#![allow(dead_code)]

/// Ensures text max-width constraints are finite and positive.
///
/// Non-finite values are treated as unconstrained width (`f64::INFINITY`),
/// and non-positive values are clamped to `1.0`.
pub fn resolve_text_max_width(max_width: f64) -> f64 {
    if !max_width.is_finite() {
        f64::INFINITY
    } else if max_width <= 0.0 {
        1.0
    } else {
        max_width
    }
}

/// Returns `value` when it is finite and positive, otherwise `fallback`.
pub fn sanitize_positive_extent(value: f64, fallback: f64) -> f64 {
    if value.is_finite() && value > 0.0 {
        value
    } else {
        fallback
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn resolves_text_max_width_for_finite_positive_values() {
        assert_eq!(resolve_text_max_width(240.0), 240.0);
    }

    #[test]
    fn resolves_text_max_width_to_one_for_non_positive_values() {
        assert_eq!(resolve_text_max_width(0.0), 1.0);
        assert_eq!(resolve_text_max_width(-12.0), 1.0);
    }

    #[test]
    fn resolves_text_max_width_to_infinity_for_non_finite_values() {
        assert_eq!(resolve_text_max_width(f64::INFINITY), f64::INFINITY);
        assert_eq!(resolve_text_max_width(f64::NEG_INFINITY), f64::INFINITY);
        assert_eq!(resolve_text_max_width(f64::NAN), f64::INFINITY);
    }

    #[test]
    fn sanitizes_extent_with_fallback_for_invalid_values() {
        assert_eq!(sanitize_positive_extent(32.0, 8.0), 32.0);
        assert_eq!(sanitize_positive_extent(0.0, 8.0), 8.0);
        assert_eq!(sanitize_positive_extent(-4.0, 8.0), 8.0);
        assert_eq!(sanitize_positive_extent(f64::INFINITY, 8.0), 8.0);
        assert_eq!(sanitize_positive_extent(f64::NAN, 8.0), 8.0);
    }
}
