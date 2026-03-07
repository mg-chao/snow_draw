#![allow(dead_code)]

use crate::draw::types::draw_point::DrawPoint;

use crate::draw::elements::types::arrow::arrow_core::{ArrowEndpointEdge, ArrowState};

#[derive(Clone, Debug, PartialEq)]
pub struct FocusPointDescriptor {
    pub edge: ArrowEndpointEdge,
    pub point: DrawPoint,
}

#[derive(Clone, Debug, PartialEq)]
pub struct FocusPointHit {
    pub edge: Option<ArrowEndpointEdge>,
    pub pointer_offset: DrawPoint,
}

pub fn is_focus_point_visible(arrow: &ArrowState, edge: ArrowEndpointEdge) -> bool {
    if arrow.elbowed {
        return false;
    }

    match edge {
        ArrowEndpointEdge::Start => arrow.start_binding.is_some(),
        ArrowEndpointEdge::End => arrow.end_binding.is_some(),
    }
}

pub fn resolve_visible_focus_points(arrow: &ArrowState) -> Vec<FocusPointDescriptor> {
    let mut points = Vec::new();
    if is_focus_point_visible(arrow, ArrowEndpointEdge::Start) {
        if let Some(start) = arrow.points.first().copied() {
            points.push(FocusPointDescriptor {
                edge: ArrowEndpointEdge::Start,
                point: DrawPoint::new(arrow.x + start.x, arrow.y + start.y),
            });
        }
    }
    if is_focus_point_visible(arrow, ArrowEndpointEdge::End) {
        if let Some(end) = arrow.points.last().copied() {
            points.push(FocusPointDescriptor {
                edge: ArrowEndpointEdge::End,
                point: DrawPoint::new(arrow.x + end.x, arrow.y + end.y),
            });
        }
    }
    points
}

pub fn list_visible_focus_points(arrow: &ArrowState) -> Vec<FocusPointDescriptor> {
    resolve_visible_focus_points(arrow)
}

pub fn resolve_focus_point_hit(
    arrow: &ArrowState,
    pointer: DrawPoint,
    tolerance: f64,
) -> Option<ArrowEndpointEdge> {
    resolve_focus_point_hit_with_offset(arrow, pointer, tolerance).edge
}

pub fn pick_focus_point(
    arrow: &ArrowState,
    pointer: DrawPoint,
    tolerance: f64,
) -> Option<ArrowEndpointEdge> {
    resolve_focus_point_hit(arrow, pointer, tolerance)
}

pub fn resolve_focus_point_hit_with_offset(
    arrow: &ArrowState,
    pointer: DrawPoint,
    tolerance: f64,
) -> FocusPointHit {
    let mut best: Option<(f64, FocusPointHit)> = None;
    for descriptor in resolve_visible_focus_points(arrow) {
        let distance = descriptor.point.distance(pointer);
        if distance > tolerance {
            continue;
        }
        let hit = FocusPointHit {
            edge: Some(descriptor.edge),
            pointer_offset: DrawPoint::new(
                pointer.x - descriptor.point.x,
                pointer.y - descriptor.point.y,
            ),
        };
        match &best {
            Some((best_distance, _)) if *best_distance <= distance => {}
            _ => best = Some((distance, hit)),
        }
    }
    best.map(|(_, hit)| hit).unwrap_or(FocusPointHit {
        edge: None,
        pointer_offset: DrawPoint::ZERO,
    })
}

pub fn pick_focus_point_with_offset(
    arrow: &ArrowState,
    pointer: DrawPoint,
    tolerance: f64,
) -> FocusPointHit {
    resolve_focus_point_hit_with_offset(arrow, pointer, tolerance)
}
