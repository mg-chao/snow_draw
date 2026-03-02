#![allow(dead_code)]

use crate::draw::core::coordinates::element_space::ElementSpace;
use crate::draw::types::draw_point::DrawPoint;
use crate::draw::types::draw_rect::DrawRect;
use crate::draw::types::element_style::ArrowType;

/// Result of computing a new rect and adjusted local points for an arrow.
#[derive(Clone, Debug, PartialEq)]
pub struct ArrowRectAndPoints {
    pub rect: DrawRect,
    pub local_points: Vec<DrawPoint>,
}

impl ArrowRectAndPoints {
    pub fn new(rect: DrawRect, local_points: Vec<DrawPoint>) -> Self {
        Self { rect, local_points }
    }
}

/// Result of recomputing element geometry from edited arrow points.
#[derive(Clone, Debug, PartialEq)]
pub struct ArrowGeometryUpdate {
    pub rect: DrawRect,
    pub normalized_points: Vec<DrawPoint>,
}

/// Computes the new rect and transforms points to preserve world-space
/// positions.
///
/// When a control point is dragged outside the current bounding rect, the rect
/// must be recalculated. If the element is rotated, simply recalculating the
/// rect would change the rotation pivot (rect center), causing other points to
/// shift in world space.
///
/// This function finds the optimal rect center `C` such that when world points
/// are transformed to local space using `C`, the bounding box of local points
/// has center `C`. This keeps points stable in world space.
pub fn compute_arrow_rect_and_points(
    local_points: &[DrawPoint],
    old_rect: DrawRect,
    rotation: f64,
    arrow_type: ArrowType,
) -> ArrowRectAndPoints {
    if rotation == 0.0 {
        let rect = calculate_path_bounds(local_points, arrow_type);
        return ArrowRectAndPoints::new(rect, local_points.to_vec());
    }

    let old_space = ElementSpace::new(rotation, old_rect.center());
    let world_points: Vec<DrawPoint> = local_points
        .iter()
        .copied()
        .map(|point| old_space.to_world(point))
        .collect();

    let cos_theta = rotation.cos();
    let sin_theta = rotation.sin();
    let rotated_points: Vec<DrawPoint> = world_points
        .iter()
        .copied()
        .map(|point| {
            DrawPoint::new(
                point.x * cos_theta + point.y * sin_theta,
                -point.x * sin_theta + point.y * cos_theta,
            )
        })
        .collect();
    let rotated_bounds = calculate_path_bounds(&rotated_points, arrow_type);
    let rotated_center = rotated_bounds.center();

    let new_center = DrawPoint::new(
        rotated_center.x * cos_theta - rotated_center.y * sin_theta,
        rotated_center.x * sin_theta + rotated_center.y * cos_theta,
    );

    let new_space = ElementSpace::new(rotation, new_center);
    let new_local_points: Vec<DrawPoint> = world_points
        .iter()
        .copied()
        .map(|point| new_space.from_world(point))
        .collect();
    let new_rect = calculate_path_bounds(&new_local_points, arrow_type);

    ArrowRectAndPoints::new(new_rect, new_local_points)
}

/// Recomputes rect and normalized points after arrow local points changed.
pub fn resolve_arrow_geometry_update(
    local_points: &[DrawPoint],
    old_rect: DrawRect,
    rotation: f64,
    arrow_type: ArrowType,
) -> ArrowGeometryUpdate {
    let result = compute_arrow_rect_and_points(local_points, old_rect, rotation, arrow_type);
    ArrowGeometryUpdate {
        rect: result.rect,
        normalized_points: normalize_points(&result.local_points, result.rect),
    }
}

fn calculate_path_bounds(points: &[DrawPoint], arrow_type: ArrowType) -> DrawRect {
    // `arrow_type` is kept in the signature so this module remains API-compatible
    // with the Dart version and can delegate to specialized geometry later.
    let _ = arrow_type;
    if points.is_empty() {
        return DrawRect::default();
    }
    DrawRect::from_point_cloud(points.iter().copied())
}

fn normalize_points(world_points: &[DrawPoint], rect: DrawRect) -> Vec<DrawPoint> {
    let points = ensure_min_points(world_points);
    let width = rect.width();
    let height = rect.height();
    points
        .into_iter()
        .map(|point| {
            let x = if width == 0.0 {
                0.0
            } else {
                (point.x - rect.min_x) / width
            };
            let y = if height == 0.0 {
                0.0
            } else {
                (point.y - rect.min_y) / height
            };

            DrawPoint {
                x: clamp01(x),
                y: clamp01(y),
                pressure: point.pressure,
                timestamp: point.timestamp,
            }
        })
        .collect()
}

fn ensure_min_points(points: &[DrawPoint]) -> Vec<DrawPoint> {
    if points.len() >= 2 {
        return points.to_vec();
    }

    if points.is_empty() {
        return vec![DrawPoint::ZERO, DrawPoint::new(1.0, 1.0)];
    }

    vec![points[0], points[0]]
}

fn clamp01(value: f64) -> f64 {
    if !value.is_finite() {
        return 0.0;
    }
    value.clamp(0.0, 1.0)
}
