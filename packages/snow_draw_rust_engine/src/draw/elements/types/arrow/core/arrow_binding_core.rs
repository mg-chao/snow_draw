#![allow(dead_code)]

use crate::draw::core::coordinates::element_space::ElementSpace;
use crate::draw::types::draw_point::DrawPoint;

use super::arrow_hit_test::{
    distance_to_bindable_outline, get_bindables_over_point, is_bindable_background_opaque,
    is_bindable_binding_enabled, is_bindable_interior_hit_enabled, is_bindable_visible_at_point,
    is_point_in_bindable, is_point_near_bindable_for_binding_hit, sort_bindables_by_z_index,
};
use super::arrow_types::{
    canonicalize_bindable_shape, ArrowEndpointEdge, ArrowState, BindableState, FixedPointBinding,
};
pub use crate::draw::elements::types::arrow::arrow_binding::*;
pub use crate::draw::elements::types::arrow::arrow_binding_snapper::*;

const DEDUP_THRESHOLD: f64 = 1.0;

pub fn max_binding_distance_simple(zoom: f64) -> f64 {
    const SCREEN_DISTANCE: f64 = 24.0;
    if zoom <= 0.0 {
        SCREEN_DISTANCE
    } else {
        SCREEN_DISTANCE / zoom
    }
}

pub fn calculate_fixed_point_for_binding(point: DrawPoint, bindable: &BindableState) -> DrawPoint {
    let rect = bindable.rect();
    let local = if bindable.angle == 0.0 {
        point
    } else {
        ElementSpace::new(bindable.angle, rect.center()).from_world(point)
    };
    let width = rect.width().abs().max(1e-6);
    let height = rect.height().abs().max(1e-6);
    DrawPoint::new(
        ((local.x - rect.min_x) / width).clamp(0.0, 1.0),
        ((local.y - rect.min_y) / height).clamp(0.0, 1.0),
    )
}

pub fn calculate_fixed_point_for_elbow_binding(
    arrow: &ArrowState,
    bindable: &BindableState,
    edge: ArrowEndpointEdge,
) -> DrawPoint {
    let endpoint =
        endpoint_global_point(arrow, edge).unwrap_or(DrawPoint::new(bindable.x, bindable.y));
    calculate_fixed_point_for_binding(endpoint, bindable)
}

pub fn list_hovered_bindables(
    point: DrawPoint,
    bindables: &[BindableState],
    tolerance: f64,
    stop_at_opaque: bool,
) -> Vec<BindableState> {
    let z_ordered_bindables = sort_bindables_by_z_index(bindables);
    let mut hovered = Vec::new();

    for bindable in z_ordered_bindables.into_iter().rev() {
        if !is_bindable_visible_at_point(point, &bindable)
            || !is_bindable_binding_enabled(&bindable)
            || !is_point_near_bindable_for_binding_hit(point, &bindable, tolerance)
        {
            continue;
        }
        let opaque = is_bindable_background_opaque(&bindable);
        hovered.push(bindable);
        if stop_at_opaque && opaque {
            break;
        }
    }

    hovered
}

pub fn pick_overlapping_bindables(
    point: DrawPoint,
    bindables: &[BindableState],
    tolerance: f64,
) -> Vec<BindableState> {
    get_bindables_over_point(point, bindables, tolerance)
}

pub fn pick_hovered_bindable_for_focus(
    point: DrawPoint,
    arrow: &ArrowState,
    bindables: &[BindableState],
    tolerance: f64,
) -> Option<BindableState> {
    let candidates = list_hovered_bindables(point, bindables, tolerance, false);
    if candidates.is_empty() {
        return None;
    }
    if candidates.len() == 1 {
        return candidates.into_iter().next();
    }

    candidates.into_iter().find(|bindable| {
        distance_to_bindable_outline(point, bindable) <= binding_gap(bindable, arrow.elbowed)
            || (is_bindable_interior_hit_enabled(bindable) && is_point_in_bindable(point, bindable))
    })
}

pub fn get_snap_outline_mid_point(
    point: DrawPoint,
    bindable: &BindableState,
    zoom: f64,
) -> Option<DrawPoint> {
    let threshold = max_binding_distance_simple(zoom) + bindable.stroke_width / 2.0;
    for candidate in snap_outline_mid_point_candidates(bindable) {
        if point.distance(candidate) <= threshold && !is_point_in_bindable(point, bindable) {
            return Some(candidate);
        }
    }
    None
}

pub fn get_global_fixed_point_for_bindable_element(
    binding: &FixedPointBinding,
    bindable: &BindableState,
) -> DrawPoint {
    let rect = bindable.rect();
    let local = DrawPoint::new(
        rect.min_x + rect.width() * binding.fixed_point.x,
        rect.min_y + rect.height() * binding.fixed_point.y,
    );
    if bindable.angle == 0.0 {
        return local;
    }
    ElementSpace::new(bindable.angle, rect.center()).to_world(local)
}

pub fn get_global_fixed_points(
    arrow: &ArrowState,
    bindables: &[BindableState],
) -> [Option<DrawPoint>; 2] {
    let start = fixed_or_endpoint_point(arrow, ArrowEndpointEdge::Start, bindables);
    let end = fixed_or_endpoint_point(arrow, ArrowEndpointEdge::End, bindables);
    [start, end]
}

pub fn get_arrow_local_fixed_points(
    arrow: &ArrowState,
    bindables: &[BindableState],
) -> [Option<DrawPoint>; 2] {
    let global = get_global_fixed_points(arrow, bindables);
    [
        global[0].map(|point| to_local_point(arrow, point)),
        global[1].map(|point| to_local_point(arrow, point)),
    ]
}

pub fn project_fixed_point_onto_diagonal(
    arrow: &ArrowState,
    point: DrawPoint,
    bindable: &BindableState,
    edge: ArrowEndpointEdge,
    bindables: &[BindableState],
    zoom: f64,
) -> Option<DrawPoint> {
    if arrow.points.len() < 2 || (arrow.width.abs() < 3.0 && arrow.height.abs() < 3.0) {
        return None;
    }

    if let Some(side_mid_point) = get_snap_outline_mid_point(point, bindable, zoom) {
        return Some(side_mid_point);
    }

    let [diagonal_one, diagonal_two] = diagonal_guide_segments(bindable);
    let mut anchor = point_at_index_global(
        arrow,
        match edge {
            ArrowEndpointEdge::Start => 1,
            ArrowEndpointEdge::End => -2,
        },
    )?;

    if arrow.points.len() == 2 {
        let other_binding = match edge {
            ArrowEndpointEdge::Start => arrow.end_binding.as_ref(),
            ArrowEndpointEdge::End => arrow.start_binding.as_ref(),
        };
        if let Some(other_binding) = other_binding {
            if let Some(other_bindable) = bindables
                .iter()
                .find(|candidate| candidate.id == other_binding.element_id)
            {
                anchor = get_global_fixed_point_for_bindable_element(other_binding, other_bindable);
            }
        }
    }

    let direction = normalize_vector(anchor, point)?;
    let extent =
        distance(diagonal_one[0], diagonal_one[1]).max(distance(diagonal_two[0], diagonal_two[1]));
    let ray_length = 2.0 * distance(anchor, point) + extent;
    let ray_point = DrawPoint::new(
        anchor.x + direction.x * ray_length,
        anchor.y + direction.y * ray_length,
    );

    let p1 = line_intersection(diagonal_one[0], diagonal_one[1], ray_point, anchor);
    let p2 = line_intersection(diagonal_two[0], diagonal_two[1], ray_point, anchor);

    let projection = match (p1, p2) {
        (Some(left), Some(right)) => {
            if distance(anchor, left) <= distance(anchor, right) {
                Some(left)
            } else {
                Some(right)
            }
        }
        (Some(value), None) | (None, Some(value)) => Some(value),
        (None, None) => None,
    }?;

    is_point_in_bindable(projection, bindable).then_some(projection)
}

fn fixed_or_endpoint_point(
    arrow: &ArrowState,
    edge: ArrowEndpointEdge,
    bindables: &[BindableState],
) -> Option<DrawPoint> {
    let binding = match edge {
        ArrowEndpointEdge::Start => arrow.start_binding.as_ref(),
        ArrowEndpointEdge::End => arrow.end_binding.as_ref(),
    };
    if let Some(binding) = binding {
        if let Some(bindable) = bindables
            .iter()
            .find(|candidate| candidate.id == binding.element_id)
        {
            return Some(get_global_fixed_point_for_bindable_element(
                binding, bindable,
            ));
        }
    }
    endpoint_global_point(arrow, edge)
}

fn endpoint_global_point(arrow: &ArrowState, edge: ArrowEndpointEdge) -> Option<DrawPoint> {
    let point = match edge {
        ArrowEndpointEdge::Start => arrow.points.first().copied(),
        ArrowEndpointEdge::End => arrow.points.last().copied(),
    }?;
    Some(DrawPoint::new(arrow.x + point.x, arrow.y + point.y))
}

fn point_at_index_global(arrow: &ArrowState, index: isize) -> Option<DrawPoint> {
    let length = arrow.points.len() as isize;
    if length == 0 {
        return None;
    }
    let resolved = if index < 0 { length + index } else { index };
    if resolved < 0 || resolved >= length {
        return None;
    }
    let point = arrow.points[resolved as usize];
    Some(DrawPoint::new(arrow.x + point.x, arrow.y + point.y))
}

fn to_local_point(arrow: &ArrowState, point: DrawPoint) -> DrawPoint {
    DrawPoint::new(point.x - arrow.x, point.y - arrow.y)
}

fn snap_outline_mid_point_candidates(bindable: &BindableState) -> Vec<DrawPoint> {
    let rect = bindable.rect();
    let center = rect.center();

    if canonicalize_bindable_shape(&bindable.shape) == "diamond" {
        let top_x = (bindable.width / 2.0).floor() + 1.0;
        let top_y = 0.0;
        let right_x = bindable.width;
        let right_y = (bindable.height / 2.0).floor() + 1.0;
        let bottom_x = top_x;
        let bottom_y = bindable.height;
        let left_x = 0.0;
        let left_y = right_y;
        let vertical_radius = (top_x - left_x) * 0.01;
        let horizontal_radius = (right_y - top_y) * 0.01;

        let top = DrawPoint::new(bindable.x + top_x, bindable.y + top_y);
        let right = DrawPoint::new(bindable.x + right_x, bindable.y + right_y);
        let bottom = DrawPoint::new(bindable.x + bottom_x, bindable.y + bottom_y);
        let left = DrawPoint::new(bindable.x + left_x, bindable.y + left_y);

        let corners = [
            bezier_at_half(
                DrawPoint::new(right.x - vertical_radius, right.y - horizontal_radius),
                right,
                right,
                DrawPoint::new(right.x - vertical_radius, right.y + horizontal_radius),
            ),
            bezier_at_half(
                DrawPoint::new(bottom.x + vertical_radius, bottom.y - horizontal_radius),
                bottom,
                bottom,
                DrawPoint::new(bottom.x - vertical_radius, bottom.y - horizontal_radius),
            ),
            bezier_at_half(
                DrawPoint::new(left.x + vertical_radius, left.y + horizontal_radius),
                left,
                left,
                DrawPoint::new(left.x + vertical_radius, left.y - horizontal_radius),
            ),
            bezier_at_half(
                DrawPoint::new(top.x - vertical_radius, top.y + horizontal_radius),
                top,
                top,
                DrawPoint::new(top.x + vertical_radius, top.y + horizontal_radius),
            ),
        ];

        return corners
            .into_iter()
            .map(|point| rotate_point(point, center, bindable.angle))
            .collect();
    }

    let right = rotate_point(
        DrawPoint::new(rect.max_x, rect.center().y),
        center,
        bindable.angle,
    );
    let bottom = rotate_point(
        DrawPoint::new(rect.center().x, rect.max_y),
        center,
        bindable.angle,
    );
    let left = rotate_point(
        DrawPoint::new(rect.min_x, rect.center().y),
        center,
        bindable.angle,
    );
    let top = rotate_point(
        DrawPoint::new(rect.center().x, rect.min_y),
        center,
        bindable.angle,
    );
    vec![right, bottom, left, top]
}

fn bezier_at_half(
    first: DrawPoint,
    second: DrawPoint,
    third: DrawPoint,
    fourth: DrawPoint,
) -> DrawPoint {
    let t: f64 = 0.5;
    let one_minus_t: f64 = 1.0 - t;
    let b0 = one_minus_t.powi(3);
    let b1 = 3.0 * t * one_minus_t.powi(2);
    let b2 = 3.0 * t.powi(2) * one_minus_t;
    let b3 = t.powi(3);
    DrawPoint::new(
        b0 * first.x + b1 * second.x + b2 * third.x + b3 * fourth.x,
        b0 * first.y + b1 * second.y + b2 * third.y + b3 * fourth.y,
    )
}

fn diagonal_guide_segments(bindable: &BindableState) -> [[DrawPoint; 2]; 2] {
    let rect = bindable.rect();
    let center = rect.center();
    let top_center = rotate_point(
        DrawPoint::new(rect.center().x, rect.min_y),
        center,
        bindable.angle,
    );
    let bottom_center = rotate_point(
        DrawPoint::new(rect.center().x, rect.max_y),
        center,
        bindable.angle,
    );
    let left_center = rotate_point(
        DrawPoint::new(rect.min_x, rect.center().y),
        center,
        bindable.angle,
    );
    let right_center = rotate_point(
        DrawPoint::new(rect.max_x, rect.center().y),
        center,
        bindable.angle,
    );
    [[top_center, bottom_center], [left_center, right_center]]
}

fn rotate_point(point: DrawPoint, center: DrawPoint, angle: f64) -> DrawPoint {
    if angle == 0.0 {
        return point;
    }
    let sin = angle.sin();
    let cos = angle.cos();
    let translated_x = point.x - center.x;
    let translated_y = point.y - center.y;
    DrawPoint::new(
        center.x + translated_x * cos - translated_y * sin,
        center.y + translated_x * sin + translated_y * cos,
    )
}

fn normalize_vector(from: DrawPoint, to: DrawPoint) -> Option<DrawPoint> {
    let delta = to - from;
    let length = (delta.x * delta.x + delta.y * delta.y).sqrt();
    (length > DEDUP_THRESHOLD).then_some(delta / length)
}

fn line_intersection(
    first_start: DrawPoint,
    first_end: DrawPoint,
    second_start: DrawPoint,
    second_end: DrawPoint,
) -> Option<DrawPoint> {
    let denominator = (first_start.x - first_end.x) * (second_start.y - second_end.y)
        - (first_start.y - first_end.y) * (second_start.x - second_end.x);
    if denominator.abs() <= f64::EPSILON {
        return None;
    }

    let determinant_first = first_start.x * first_end.y - first_start.y * first_end.x;
    let determinant_second = second_start.x * second_end.y - second_start.y * second_end.x;

    Some(DrawPoint::new(
        (determinant_first * (second_start.x - second_end.x)
            - (first_start.x - first_end.x) * determinant_second)
            / denominator,
        (determinant_first * (second_start.y - second_end.y)
            - (first_start.y - first_end.y) * determinant_second)
            / denominator,
    ))
}

fn distance(first: DrawPoint, second: DrawPoint) -> f64 {
    first.distance(second)
}

fn binding_gap(bindable: &BindableState, elbowed: bool) -> f64 {
    let base = (bindable.stroke_width.max(1.0) * 2.0).max(6.0);
    if elbowed {
        base.max(8.0)
    } else {
        base
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn sample_bindable(id: &str, x: f64, y: f64) -> BindableState {
        BindableState {
            id: id.to_string(),
            shape: "rectangle".to_string(),
            x,
            y,
            width: 100.0,
            height: 60.0,
            angle: 0.0,
            stroke_width: 2.0,
            roundness: None,
            z_index: Some(1.0),
            background_opaque: Some(true),
            binding_enabled: Some(true),
            interior_hit_enabled: Some(true),
            visibility_bounds: None,
        }
    }

    fn sample_arrow() -> ArrowState {
        ArrowState {
            id: "arrow-1".to_string(),
            x: 10.0,
            y: 20.0,
            width: 120.0,
            height: 40.0,
            points: vec![DrawPoint::new(0.0, 0.0), DrawPoint::new(120.0, 40.0)],
            start_binding: None,
            end_binding: None,
            start_arrowhead: None,
            end_arrowhead: None,
            elbowed: false,
            fixed_segments: None,
            start_is_special: None,
            end_is_special: None,
        }
    }

    #[test]
    fn get_global_fixed_points_falls_back_to_arrow_endpoints() {
        let arrow = sample_arrow();
        let points = get_global_fixed_points(&arrow, &[]);

        assert_eq!(points[0], Some(DrawPoint::new(10.0, 20.0)));
        assert_eq!(points[1], Some(DrawPoint::new(130.0, 60.0)));
    }

    #[test]
    fn get_global_fixed_point_for_bindable_element_denormalizes_binding() {
        let bindable = sample_bindable("rect-1", 20.0, 40.0);
        let binding = FixedPointBinding::new("rect-1", DrawPoint::new(0.25, 0.5), "orbit");

        assert_eq!(
            get_global_fixed_point_for_bindable_element(&binding, &bindable),
            DrawPoint::new(45.0, 70.0)
        );
    }

    #[test]
    fn list_hovered_bindables_returns_topmost_hits() {
        let mut bottom = sample_bindable("bottom", 0.0, 0.0);
        bottom.z_index = Some(1.0);
        let mut top = sample_bindable("top", 0.0, 0.0);
        top.z_index = Some(2.0);

        let hovered = list_hovered_bindables(
            DrawPoint::new(1.0, 30.0),
            &[bottom, top.clone()],
            0.0,
            false,
        );

        assert_eq!(
            hovered.first().map(|bindable| bindable.id.as_str()),
            Some("top")
        );
        assert_eq!(hovered.len(), 2);
    }
}
