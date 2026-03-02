#![allow(dead_code)]

use crate::draw::types::draw_point::DrawPoint;

/// Returns a capped, order-preserving sample list for batched pointer updates.
///
/// When pointer dispatch falls behind frame production, a coalesced move event
/// can accumulate many samples. Passing all of them through reducers in one
/// synchronous batch can cause input latency spikes. This helper keeps the
/// first/last samples and uniformly subsamples interior points so each reducer
/// pass stays bounded while preserving stroke continuity.
pub fn resample_pointer_samples(
    sampled_points: &[DrawPoint],
    max_samples: usize,
) -> Vec<DrawPoint> {
    if sampled_points.is_empty() || max_samples == 0 {
        return Vec::new();
    }

    if max_samples == 1 {
        return vec![sampled_points[sampled_points.len() - 1]];
    }

    if sampled_points.len() <= max_samples {
        return sampled_points.to_vec();
    }

    let last_index = sampled_points.len() - 1;
    let stride = last_index as f64 / (max_samples - 1) as f64;

    let mut reduced = Vec::with_capacity(max_samples);
    reduced.push(sampled_points[0]);

    for i in 1..(max_samples - 1) {
        let index = ((i as f64) * stride).round() as usize;
        let point = sampled_points[index];
        if reduced.last().copied() != Some(point) {
            reduced.push(point);
        }
    }

    let last_point = sampled_points[last_index];
    if reduced.last().copied() != Some(last_point) {
        reduced.push(last_point);
    }

    reduced
}

#[cfg(test)]
mod tests {
    use super::resample_pointer_samples;
    use crate::draw::types::draw_point::DrawPoint;

    fn point(x: f64) -> DrawPoint {
        DrawPoint::new(x, 0.0)
    }

    #[test]
    fn returns_empty_when_samples_empty_or_cap_zero() {
        let samples = vec![point(1.0), point(2.0)];

        assert!(resample_pointer_samples(&[], 10).is_empty());
        assert!(resample_pointer_samples(&samples, 0).is_empty());
    }

    #[test]
    fn keeps_only_last_when_cap_is_one() {
        let samples = vec![point(1.0), point(2.0), point(3.0)];

        assert_eq!(resample_pointer_samples(&samples, 1), vec![point(3.0)]);
    }

    #[test]
    fn keeps_original_when_within_cap() {
        let samples = vec![point(1.0), point(2.0), point(3.0)];

        assert_eq!(resample_pointer_samples(&samples, 3), samples);
    }

    #[test]
    fn preserves_endpoints_and_bounds_output_size() {
        let samples = (0..100).map(|v| point(v as f64)).collect::<Vec<_>>();

        let reduced = resample_pointer_samples(&samples, 10);

        assert_eq!(reduced.first().copied(), Some(point(0.0)));
        assert_eq!(reduced.last().copied(), Some(point(99.0)));
        assert!(reduced.len() <= 10);
    }

    #[test]
    fn avoids_duplicate_points_from_rounded_indices() {
        let samples = vec![point(0.0), point(0.0), point(0.0), point(1.0)];

        let reduced = resample_pointer_samples(&samples, 3);

        assert_eq!(reduced, vec![point(0.0), point(1.0)]);
    }
}
