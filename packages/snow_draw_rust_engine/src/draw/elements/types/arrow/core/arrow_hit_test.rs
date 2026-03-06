#![allow(dead_code)]

use crate::draw::core::coordinates::element_space::ElementSpace;
use crate::draw::types::draw_point::DrawPoint;

use super::arrow_types::BindableState;
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
    let mut sorted = bindables.to_vec();
    sorted.sort_by(|left, right| {
        left.z_index
            .partial_cmp(&right.z_index)
            .unwrap_or(std::cmp::Ordering::Equal)
    });
    sorted
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
    distance_to_bindable_outline(point, bindable) <= tolerance + bindable.stroke_width / 2.0
}

pub fn get_hovered_bindable(
    point: Point,
    bindables: &[BindableState],
    tolerance: f64,
) -> Option<BindableState> {
    let mut hovered: Option<(f64, BindableState)> = None;
    for bindable in sort_bindables_by_z_index(bindables).into_iter().rev() {
        if !is_bindable_visible_at_point(point, &bindable)
            || !is_bindable_binding_enabled(&bindable)
        {
            continue;
        }
        let distance = distance_to_bindable_outline(point, &bindable);
        if distance > tolerance + bindable.stroke_width / 2.0 {
            continue;
        }
        match &hovered {
            Some((best_distance, _)) if *best_distance <= distance => {}
            _ => hovered = Some((distance, bindable)),
        }
    }
    hovered.map(|(_, bindable)| bindable)
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
