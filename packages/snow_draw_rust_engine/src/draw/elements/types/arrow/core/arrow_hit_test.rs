#![allow(dead_code)]

use crate::draw::core::coordinates::element_space::ElementSpace;
use crate::draw::types::draw_point::DrawPoint;

use super::arrow_types::{
    canonicalize_bindable_shape, BindableRoundnessType, BindableState, FixedPointBinding,
};
use crate::draw::types::draw_rect::DrawRect;

type Bounds = DrawRect;
type Point = DrawPoint;

pub fn is_bindable_background_opaque(bindable: &BindableState) -> bool {
    bindable.background_opaque.unwrap_or(true)
}

pub fn is_bindable_binding_enabled(bindable: &BindableState) -> bool {
    bindable.binding_enabled.unwrap_or(true)
}

pub fn is_bindable_interior_hit_enabled(bindable: &BindableState) -> bool {
    bindable.interior_hit_enabled.unwrap_or(true)
}

pub fn is_bindable_visible_at_point(point: Point, bindable: &BindableState) -> bool {
    bindable
        .visibility_bounds
        .map(|bounds| {
            point.x >= bounds.min_x
                && point.x <= bounds.max_x
                && point.y >= bounds.min_y
                && point.y <= bounds.max_y
        })
        .unwrap_or(true)
}

pub fn sort_bindables_by_z_index(bindables: &[BindableState]) -> Vec<BindableState> {
    let has_explicit_z_order = bindables
        .iter()
        .any(|bindable| bindable.z_index.is_some_and(f64::is_finite));
    if !has_explicit_z_order {
        return bindables.to_vec();
    }

    let mut sorted = bindables.to_vec();
    sorted.sort_by(|left, right| {
        left.z_index
            .filter(|value| value.is_finite())
            .unwrap_or(0.0)
            .partial_cmp(&right.z_index.filter(|value| value.is_finite()).unwrap_or(0.0))
            .unwrap_or(std::cmp::Ordering::Equal)
    });
    sorted
}

pub fn resolve_binding_hit_threshold(bindable: &BindableState, tolerance: f64) -> f64 {
    if is_bindable_interior_hit_enabled(bindable) {
        tolerance
    } else {
        tolerance.max(1.0)
    }
}

pub fn is_point_in_bindable(point: Point, bindable: &BindableState) -> bool {
    let local_point = unrotate_to_local(point, bindable);
    let rect = bindable.rect();
    match bindable.shape.as_str() {
        "ellipse" => {
            let radius_x = rect.width() / 2.0;
            let radius_y = rect.height() / 2.0;
            if radius_x <= 0.0 || radius_y <= 0.0 {
                return false;
            }
            let center = rect.center();
            let dx = (local_point.x - center.x) / radius_x;
            let dy = (local_point.y - center.y) / radius_y;
            dx * dx + dy * dy <= 1.0
        }
        "diamond" => {
            let center = rect.center();
            let dx = (local_point.x - center.x).abs() / (rect.width() / 2.0).max(f64::EPSILON);
            let dy = (local_point.y - center.y).abs() / (rect.height() / 2.0).max(f64::EPSILON);
            dx + dy <= 1.0
        }
        _ => rect.contains_point(local_point),
    }
}

pub fn distance_to_bindable_outline(point: Point, bindable: &BindableState) -> f64 {
    let local_point = unrotate_to_local(point, bindable);
    let rect = bindable.rect();
    match bindable.shape.as_str() {
        "ellipse" => distance_to_ellipse_outline(local_point, rect),
        "diamond" => distance_to_diamond_outline(local_point, rect),
        _ => distance_to_rectangle_outline(local_point, rect),
    }
}

pub fn is_point_near_bindable_for_binding_hit(
    point: Point,
    bindable: &BindableState,
    tolerance: f64,
) -> bool {
    if !is_bindable_binding_enabled(bindable) {
        return false;
    }
    if !is_bindable_visible_at_point(point, bindable) {
        return false;
    }

    let threshold = resolve_binding_hit_threshold(bindable, tolerance);
    if !is_bindable_interior_hit_enabled(bindable) {
        return distance_to_bindable_outline(point, bindable) <= threshold;
    }

    is_point_in_bindable(point, bindable) || distance_to_bindable_outline(point, bindable) <= threshold
}

pub fn get_hovered_bindable(
    point: Point,
    bindables: &[BindableState],
    tolerance: f64,
) -> Option<BindableState> {
    let bindables = sort_bindables_by_z_index(bindables);
    let mut candidates = Vec::new();
    for bindable in bindables.into_iter().rev() {
        if !is_point_near_bindable_for_binding_hit(point, &bindable, tolerance) {
            continue;
        }

        let opaque = is_bindable_background_opaque(&bindable);
        candidates.push(bindable);
        if opaque {
            break;
        }
    }

    if candidates.is_empty() {
        return None;
    }
    if candidates.len() == 1 {
        return candidates.pop();
    }

    candidates.sort_by(|left, right| {
        let left_size = left.width * left.width + left.height * left.height;
        let right_size = right.width * right.width + right.height * right.height;
        right_size
            .partial_cmp(&left_size)
            .unwrap_or(std::cmp::Ordering::Equal)
    });
    candidates.pop()
}

pub fn get_bindables_over_point(
    point: Point,
    bindables: &[BindableState],
    tolerance: f64,
) -> Vec<BindableState> {
    sort_bindables_by_z_index(bindables)
        .into_iter()
        .filter(|bindable| is_point_near_bindable_for_binding_hit(point, bindable, tolerance))
        .collect()
}

fn unrotate_to_local(point: Point, bindable: &BindableState) -> DrawPoint {
    ElementSpace::new(bindable.angle, bindable.rect().center()).from_world(point)
}

fn distance_to_rectangle_outline(point: Point, rect: Bounds) -> f64 {
    let dx = if point.x < rect.min_x {
        rect.min_x - point.x
    } else if point.x > rect.max_x {
        point.x - rect.max_x
    } else {
        (point.x - rect.min_x).min(rect.max_x - point.x)
    };
    let dy = if point.y < rect.min_y {
        rect.min_y - point.y
    } else if point.y > rect.max_y {
        point.y - rect.max_y
    } else {
        (point.y - rect.min_y).min(rect.max_y - point.y)
    };
    if rect.contains_point(point) {
        dx.min(dy)
    } else {
        (dx * dx + dy * dy).sqrt()
    }
}

fn distance_to_ellipse_outline(point: Point, rect: Bounds) -> f64 {
    let center = rect.center();
    let radius_x = rect.width() / 2.0;
    let radius_y = rect.height() / 2.0;
    if radius_x <= 0.0 || radius_y <= 0.0 {
        return point.distance(center);
    }
    let dx = point.x - center.x;
    let dy = point.y - center.y;
    let angle = dy.atan2(dx);
    let edge = DrawPoint::new(
        center.x + radius_x * angle.cos(),
        center.y + radius_y * angle.sin(),
    );
    point.distance(edge)
}

fn distance_to_diamond_outline(point: Point, rect: Bounds) -> f64 {
    let center = rect.center();
    let top = DrawPoint::new(center.x, rect.min_y);
    let right = DrawPoint::new(rect.max_x, center.y);
    let bottom = DrawPoint::new(center.x, rect.max_y);
    let left = DrawPoint::new(rect.min_x, center.y);
    [(top, right), (right, bottom), (bottom, left), (left, top)]
        .into_iter()
        .map(|(a, b)| point_segment_distance(point, a, b))
        .fold(f64::INFINITY, f64::min)
}

fn point_segment_distance(point: Point, start: Point, end: Point) -> f64 {
    let delta = end - start;
    let length_squared = delta.x * delta.x + delta.y * delta.y;
    if length_squared <= f64::EPSILON {
        return point.distance(start);
    }
    let projected =
        ((point.x - start.x) * delta.x + (point.y - start.y) * delta.y) / length_squared;
    let clamped = projected.clamp(0.0, 1.0);
    let closest = DrawPoint::new(start.x + delta.x * clamped, start.y + delta.y * clamped);
    point.distance(closest)
}

pub fn is_bindable_inside_other_bindable(
    inner_bindable: &BindableState,
    outer_bindable: &BindableState,
) -> bool {
    let offset = -(inner_bindable.width.max(inner_bindable.height)) / 20.0;
    sample_outline_points(inner_bindable, offset)
        .into_iter()
        .all(|sample| is_point_in_bindable(sample, outer_bindable))
}

pub fn is_bindable_element_inside_other_bindable(
    inner_bindable: &BindableState,
    outer_bindable: &BindableState,
) -> bool {
    is_bindable_inside_other_bindable(inner_bindable, outer_bindable)
}

pub fn get_binding_side_mid_point(
    binding: &FixedPointBinding,
    bindable: &BindableState,
) -> DrawPoint {
    let shape = canonicalize_bindable_shape(&bindable.shape);
    let side = binding_side(normalize_fixed_point(binding.fixed_point), &shape);
    let center = bindable.rect().center();
    let offset = 0.01;
    let offset_diagonal = offset * 0.707;

    let local_point = match shape.as_str() {
        "ellipse" => ellipse_side_mid_point(bindable, side, offset, offset_diagonal),
        "diamond" => diamond_side_mid_point(bindable, side, offset, offset_diagonal),
        _ => rectangle_side_mid_point(bindable, side, offset, offset_diagonal),
    };

    rotate_point(local_point, center, bindable.angle)
}

fn sample_outline_points(bindable: &BindableState, offset: f64) -> Vec<DrawPoint> {
    let shape = canonicalize_bindable_shape(&bindable.shape);
    let center = bindable.rect().center();

    match shape.as_str() {
        "diamond" => {
            let top = DrawPoint::new(bindable.x + bindable.width / 2.0, bindable.y - offset);
            let right = DrawPoint::new(
                bindable.x + bindable.width + offset,
                bindable.y + bindable.height / 2.0,
            );
            let bottom = DrawPoint::new(
                bindable.x + bindable.width / 2.0,
                bindable.y + bindable.height + offset,
            );
            let left = DrawPoint::new(bindable.x - offset, bindable.y + bindable.height / 2.0);
            vec![
                rotate_point(top, center, bindable.angle),
                rotate_point(right, center, bindable.angle),
                rotate_point(bottom, center, bindable.angle),
                rotate_point(left, center, bindable.angle),
            ]
        }
        "ellipse" => {
            let cx = bindable.x + bindable.width / 2.0;
            let cy = bindable.y + bindable.height / 2.0;
            let rx = bindable.width / 2.0;
            let ry = bindable.height / 2.0;
            vec![
                rotate_point(DrawPoint::new(cx, cy - ry - offset), center, bindable.angle),
                rotate_point(DrawPoint::new(cx + rx + offset, cy), center, bindable.angle),
                rotate_point(DrawPoint::new(cx, cy + ry + offset), center, bindable.angle),
                rotate_point(DrawPoint::new(cx - rx - offset, cy), center, bindable.angle),
            ]
        }
        _ => {
            let rect = bindable.rect();
            vec![
                rotate_point(
                    DrawPoint::new(rect.min_x - offset, rect.min_y - offset),
                    center,
                    bindable.angle,
                ),
                rotate_point(
                    DrawPoint::new(rect.max_x + offset, rect.min_y - offset),
                    center,
                    bindable.angle,
                ),
                rotate_point(
                    DrawPoint::new(rect.max_x + offset, rect.max_y + offset),
                    center,
                    bindable.angle,
                ),
                rotate_point(
                    DrawPoint::new(rect.min_x - offset, rect.max_y + offset),
                    center,
                    bindable.angle,
                ),
            ]
        }
    }
}

fn normalize_fixed_point(point: DrawPoint) -> DrawPoint {
    DrawPoint::new(point.x.clamp(0.0, 1.0), point.y.clamp(0.0, 1.0))
}

fn binding_side(fixed_point: DrawPoint, shape: &str) -> &'static str {
    let centered_x = fixed_point.x - 0.5;
    let centered_y = fixed_point.y - 0.5;
    let degrees = normalize_degrees(centered_y.atan2(centered_x).to_degrees());
    let sectors = match shape {
        "rectangle" => RECTANGLE_SECTORS.as_slice(),
        "diamond" => DIAMOND_SECTORS.as_slice(),
        _ => ELLIPSE_SECTORS.as_slice(),
    };

    let mut nearest = sectors[0];
    let mut nearest_distance = f64::INFINITY;
    for sector in sectors {
        let half = sector.width / 2.0;
        let start = normalize_degrees(sector.center - half);
        let end = normalize_degrees(sector.center + half);
        let in_range = if start <= end {
            degrees >= start && degrees <= end
        } else {
            degrees >= start || degrees <= end
        };
        if in_range {
            return sector.side;
        }

        let mut distance = (degrees - sector.center).abs();
        if distance > 180.0 {
            distance = 360.0 - distance;
        }
        if distance < nearest_distance {
            nearest_distance = distance;
            nearest = *sector;
        }
    }
    nearest.side
}

fn normalize_degrees(degrees: f64) -> f64 {
    ((degrees % 360.0) + 360.0) % 360.0
}

fn rectangle_side_mid_point(
    bindable: &BindableState,
    side: &str,
    offset: f64,
    offset_diagonal: f64,
) -> DrawPoint {
    let radius = corner_radius(bindable).max(0.01);
    let top = [
        DrawPoint::new(bindable.x + radius, bindable.y),
        DrawPoint::new(bindable.x + bindable.width - radius, bindable.y),
    ];
    let right = [
        DrawPoint::new(bindable.x + bindable.width, bindable.y + radius),
        DrawPoint::new(bindable.x + bindable.width, bindable.y + bindable.height - radius),
    ];
    let bottom = [
        DrawPoint::new(bindable.x + radius, bindable.y + bindable.height),
        DrawPoint::new(bindable.x + bindable.width - radius, bindable.y + bindable.height),
    ];
    let left = [
        DrawPoint::new(bindable.x, bindable.y + bindable.height - radius),
        DrawPoint::new(bindable.x, bindable.y + radius),
    ];

    match side {
        "top" => midpoint(top[0], top[1]) + DrawPoint::new(0.0, -offset),
        "right" => midpoint(right[0], right[1]) + DrawPoint::new(offset, 0.0),
        "bottom" => midpoint(bottom[0], bottom[1]) + DrawPoint::new(0.0, offset),
        "left" => midpoint(left[0], left[1]) + DrawPoint::new(-offset, 0.0),
        "top-left" => midpoint(left[1], top[0]) + DrawPoint::new(-offset_diagonal, -offset_diagonal),
        "top-right" => midpoint(top[1], right[0]) + DrawPoint::new(offset_diagonal, -offset_diagonal),
        "bottom-right" => midpoint(right[1], bottom[1]) + DrawPoint::new(offset_diagonal, offset_diagonal),
        _ => midpoint(bottom[0], left[0]) + DrawPoint::new(-offset_diagonal, offset_diagonal),
    }
}

fn ellipse_side_mid_point(
    bindable: &BindableState,
    side: &str,
    offset: f64,
    offset_diagonal: f64,
) -> DrawPoint {
    let cx = bindable.x + bindable.width / 2.0;
    let cy = bindable.y + bindable.height / 2.0;
    let rx = bindable.width / 2.0;
    let ry = bindable.height / 2.0;
    match side {
        "top" => DrawPoint::new(cx, cy - ry - offset),
        "right" => DrawPoint::new(cx + rx + offset, cy),
        "bottom" => DrawPoint::new(cx, cy + ry + offset),
        "left" => DrawPoint::new(cx - rx - offset, cy),
        "top-right" => {
            let angle = -std::f64::consts::FRAC_PI_4;
            DrawPoint::new(
                cx + rx * angle.cos() + offset_diagonal,
                cy + ry * angle.sin() - offset_diagonal,
            )
        }
        "bottom-right" => {
            let angle = std::f64::consts::FRAC_PI_4;
            DrawPoint::new(
                cx + rx * angle.cos() + offset_diagonal,
                cy + ry * angle.sin() + offset_diagonal,
            )
        }
        "bottom-left" => {
            let angle = 3.0 * std::f64::consts::FRAC_PI_4;
            DrawPoint::new(
                cx + rx * angle.cos() - offset_diagonal,
                cy + ry * angle.sin() + offset_diagonal,
            )
        }
        _ => {
            let angle = -3.0 * std::f64::consts::FRAC_PI_4;
            DrawPoint::new(
                cx + rx * angle.cos() - offset_diagonal,
                cy + ry * angle.sin() - offset_diagonal,
            )
        }
    }
}

fn diamond_side_mid_point(
    bindable: &BindableState,
    side: &str,
    offset: f64,
    offset_diagonal: f64,
) -> DrawPoint {
    let top = DrawPoint::new(bindable.x + bindable.width / 2.0, bindable.y);
    let right = DrawPoint::new(bindable.x + bindable.width, bindable.y + bindable.height / 2.0);
    let bottom = DrawPoint::new(bindable.x + bindable.width / 2.0, bindable.y + bindable.height);
    let left = DrawPoint::new(bindable.x, bindable.y + bindable.height / 2.0);

    match side {
        "top" => top + DrawPoint::new(0.0, -offset),
        "right" => right + DrawPoint::new(offset, 0.0),
        "bottom" => bottom + DrawPoint::new(0.0, offset),
        "left" => left + DrawPoint::new(-offset, 0.0),
        "top-right" => midpoint(top, right) + DrawPoint::new(offset_diagonal, -offset_diagonal),
        "bottom-right" => midpoint(right, bottom) + DrawPoint::new(offset_diagonal, offset_diagonal),
        "bottom-left" => midpoint(bottom, left) + DrawPoint::new(-offset_diagonal, offset_diagonal),
        _ => midpoint(left, top) + DrawPoint::new(-offset_diagonal, -offset_diagonal),
    }
}

fn corner_radius(bindable: &BindableState) -> f64 {
    let Some(roundness) = bindable.roundness.as_ref() else {
        return 0.0;
    };
    let size = bindable.width.min(bindable.height);
    match roundness.kind {
        BindableRoundnessType::Legacy | BindableRoundnessType::Proportional => size * 0.25,
        BindableRoundnessType::Adaptive => {
            let fixed_radius = roundness.value.unwrap_or(32.0);
            let cutoff_size = fixed_radius / 0.25;
            if size <= cutoff_size {
                size * 0.25
            } else {
                fixed_radius
            }
        }
    }
}

fn midpoint(first: DrawPoint, second: DrawPoint) -> DrawPoint {
    DrawPoint::new((first.x + second.x) / 2.0, (first.y + second.y) / 2.0)
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

#[derive(Clone, Copy)]
struct Sector {
    center: f64,
    width: f64,
    side: &'static str,
}

const RECTANGLE_SECTORS: [Sector; 8] = [
    Sector { center: 0.0, width: 75.0, side: "right" },
    Sector { center: 45.0, width: 15.0, side: "bottom-right" },
    Sector { center: 90.0, width: 75.0, side: "bottom" },
    Sector { center: 135.0, width: 15.0, side: "bottom-left" },
    Sector { center: 180.0, width: 75.0, side: "left" },
    Sector { center: 225.0, width: 15.0, side: "top-left" },
    Sector { center: 270.0, width: 75.0, side: "top" },
    Sector { center: 315.0, width: 15.0, side: "top-right" },
];

const DIAMOND_SECTORS: [Sector; 8] = [
    Sector { center: 0.0, width: 15.0, side: "right" },
    Sector { center: 45.0, width: 75.0, side: "bottom-right" },
    Sector { center: 90.0, width: 15.0, side: "bottom" },
    Sector { center: 135.0, width: 75.0, side: "bottom-left" },
    Sector { center: 180.0, width: 15.0, side: "left" },
    Sector { center: 225.0, width: 75.0, side: "top-left" },
    Sector { center: 270.0, width: 15.0, side: "top" },
    Sector { center: 315.0, width: 75.0, side: "top-right" },
];

const ELLIPSE_SECTORS: [Sector; 8] = [
    Sector { center: 0.0, width: 15.0, side: "right" },
    Sector { center: 45.0, width: 75.0, side: "bottom-right" },
    Sector { center: 90.0, width: 15.0, side: "bottom" },
    Sector { center: 135.0, width: 75.0, side: "bottom-left" },
    Sector { center: 180.0, width: 15.0, side: "left" },
    Sector { center: 225.0, width: 75.0, side: "top-left" },
    Sector { center: 270.0, width: 15.0, side: "top" },
    Sector { center: 315.0, width: 75.0, side: "top-right" },
];
