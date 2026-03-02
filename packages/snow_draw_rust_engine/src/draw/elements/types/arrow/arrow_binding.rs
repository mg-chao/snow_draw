#![allow(dead_code)]

use std::collections::HashSet;

use crate::draw::core::coordinates::element_space::ElementSpace;
use crate::draw::elements::core::element_data::ElementData as CoreElementData;
use crate::draw::elements::types::rectangle::rectangle_data::RectangleData;
use crate::draw::elements::types::serial_number::serial_number_data::SerialNumberData;
use crate::draw::elements::types::serial_number::serial_number_layout::resolve_serial_number_stroke_width;
use crate::draw::elements::types::text::text_data::TextData;
use crate::draw::models::element_state::ElementState as ModelElementState;
use crate::draw::types::draw_point::DrawPoint;
use crate::draw::types::draw_rect::DrawRect;
use serde_json::{Map, Value};

/// Arrow endpoint binding behavior when attached to a target element.
#[derive(Clone, Copy, Debug, PartialEq, Eq, Hash, Default)]
pub enum ArrowBindingMode {
    Inside,
    #[default]
    Orbit,
}

impl ArrowBindingMode {
    pub const fn as_str(self) -> &'static str {
        match self {
            Self::Inside => "inside",
            Self::Orbit => "orbit",
        }
    }

    pub fn from_name(name: &str) -> Option<Self> {
        match name {
            "inside" => Some(Self::Inside),
            "orbit" => Some(Self::Orbit),
            _ => None,
        }
    }
}

/// Binding descriptor stored on an arrow endpoint.
///
/// `anchor` is normalized in the unrotated target rect in the `0..=1` range.
#[derive(Clone, Debug, PartialEq)]
pub struct ArrowBinding {
    pub element_id: String,
    pub anchor: DrawPoint,
    pub mode: ArrowBindingMode,
}

impl ArrowBinding {
    pub fn new(element_id: impl Into<String>, anchor: DrawPoint, mode: ArrowBindingMode) -> Self {
        Self {
            element_id: element_id.into(),
            anchor: DrawPoint::new(clamp01(anchor.x), clamp01(anchor.y)),
            mode,
        }
    }

    pub fn from_json(json: &Value) -> Result<Self, String> {
        let object = json
            .as_object()
            .ok_or_else(|| "ArrowBinding must be a JSON object".to_string())?;

        let element_id = object
            .get("elementId")
            .and_then(Value::as_str)
            .ok_or_else(|| "ArrowBinding.elementId must be a string".to_string())?
            .to_string();

        let anchor = object
            .get("anchor")
            .and_then(Value::as_object)
            .ok_or_else(|| "ArrowBinding.anchor must be an object".to_string())?;

        let anchor_x = anchor
            .get("x")
            .and_then(Value::as_f64)
            .ok_or_else(|| "ArrowBinding.anchor.x must be a number".to_string())?;

        let anchor_y = anchor
            .get("y")
            .and_then(Value::as_f64)
            .ok_or_else(|| "ArrowBinding.anchor.y must be a number".to_string())?;

        let mode = object
            .get("mode")
            .and_then(Value::as_str)
            .and_then(ArrowBindingMode::from_name)
            .ok_or_else(|| "ArrowBinding.mode must be 'inside' or 'orbit'".to_string())?;

        Ok(Self::new(
            element_id,
            DrawPoint::new(anchor_x, anchor_y),
            mode,
        ))
    }

    pub fn copy_with(
        &self,
        element_id: Option<String>,
        anchor: Option<DrawPoint>,
        mode: Option<ArrowBindingMode>,
    ) -> Self {
        Self::new(
            element_id.unwrap_or_else(|| self.element_id.clone()),
            anchor.unwrap_or(self.anchor),
            mode.unwrap_or(self.mode),
        )
    }

    pub fn to_json(&self) -> Value {
        let mut object = Map::new();
        object.insert(
            "elementId".to_string(),
            Value::String(self.element_id.clone()),
        );

        let mut anchor = Map::new();
        anchor.insert("x".to_string(), Value::from(self.anchor.x));
        anchor.insert("y".to_string(), Value::from(self.anchor.y));
        object.insert("anchor".to_string(), Value::Object(anchor));

        object.insert(
            "mode".to_string(),
            Value::String(self.mode.as_str().to_string()),
        );

        Value::Object(object)
    }
}

/// Candidate binding returned during snapping.
#[derive(Clone, Debug, PartialEq)]
pub struct ArrowBindingResult {
    pub binding: ArrowBinding,
    pub snap_point: DrawPoint,
    pub distance: f64,
    pub z_index: i64,
}

/// Canonical element model required by binding utilities.
pub type ElementState = ModelElementState;

/// Utilities for arrow endpoint binding and snapping.
pub struct ArrowBindingUtils;

impl ArrowBindingUtils {
    pub const ELBOW_BINDING_GAP_BASE: f64 = ELBOW_BINDING_GAP_BASE;
    pub const ELBOW_ARROWHEAD_GAP_MULTIPLIER: f64 = BINDING_ARROWHEAD_GAP_MULTIPLIER;

    pub fn is_bindable_target(target: &ElementState) -> bool {
        let type_id = target.data.type_id();
        let type_id_value = type_id.as_str();
        type_id_value == RectangleData::TYPE_ID_TOKEN
            || type_id_value == TextData::TYPE_ID_TOKEN
            || type_id_value == SerialNumberData::TYPE_ID_TOKEN
    }

    /// Returns whether either endpoint binding targets any id in `target_ids`.
    pub fn is_bound_to_any_targets(
        start_binding: Option<&ArrowBinding>,
        end_binding: Option<&ArrowBinding>,
        target_ids: &HashSet<String>,
    ) -> bool {
        if target_ids.is_empty() {
            return false;
        }

        if let Some(start) = start_binding {
            if target_ids.contains(start.element_id.as_str()) {
                return true;
            }
        }

        if let Some(end) = end_binding {
            return target_ids.contains(end.element_id.as_str());
        }

        false
    }

    pub fn resolve_binding_gap(target: &ElementState) -> f64 {
        resolve_binding_gap(target)
    }

    pub fn resolve_binding_search_distance(snap_distance: f64) -> f64 {
        snap_distance * (1.0 + BINDING_HIT_TOLERANCE_FACTOR)
    }

    pub fn resolve_binding_candidate<'a, I>(
        world_point: DrawPoint,
        targets: I,
        snap_distance: f64,
        preferred_binding: Option<&ArrowBinding>,
        allow_new_binding: bool,
        reference_point: Option<DrawPoint>,
    ) -> Option<ArrowBindingResult>
    where
        I: IntoIterator<Item = &'a ElementState>,
    {
        resolve_best_binding_candidate(
            targets,
            snap_distance,
            preferred_binding,
            allow_new_binding,
            |target| resolve_binding_on_target(target, world_point, snap_distance, reference_point),
        )
    }

    pub fn resolve_elbow_binding_candidate<'a, I>(
        world_point: DrawPoint,
        targets: I,
        snap_distance: f64,
        has_arrowhead: bool,
        preferred_binding: Option<&ArrowBinding>,
        allow_new_binding: bool,
    ) -> Option<ArrowBindingResult>
    where
        I: IntoIterator<Item = &'a ElementState>,
    {
        resolve_best_binding_candidate(
            targets,
            snap_distance,
            preferred_binding,
            allow_new_binding,
            |target| {
                resolve_elbow_binding_on_target(target, world_point, snap_distance, has_arrowhead)
            },
        )
    }

    /// Resolves a single-target binding candidate without list iteration.
    pub fn resolve_binding_candidate_for_target(
        world_point: DrawPoint,
        target: &ElementState,
        snap_distance: f64,
        reference_point: Option<DrawPoint>,
    ) -> Option<ArrowBindingResult> {
        if snap_distance <= 0.0 || target.opacity <= 0.0 {
            return None;
        }

        resolve_binding_on_target(target, world_point, snap_distance, reference_point)
    }

    /// Resolves a single-target elbow binding candidate without list iteration.
    pub fn resolve_elbow_binding_candidate_for_target(
        world_point: DrawPoint,
        target: &ElementState,
        snap_distance: f64,
        has_arrowhead: bool,
    ) -> Option<ArrowBindingResult> {
        if snap_distance <= 0.0 || target.opacity <= 0.0 {
            return None;
        }

        resolve_elbow_binding_on_target(target, world_point, snap_distance, has_arrowhead)
    }

    pub fn resolve_bound_point(
        binding: &ArrowBinding,
        target: &ElementState,
        reference_point: Option<DrawPoint>,
    ) -> Option<DrawPoint> {
        let rect = target.rect;
        if rect.width() == 0.0 || rect.height() == 0.0 {
            return None;
        }

        let local_anchor = DrawPoint::new(
            rect.min_x + rect.width() * binding.anchor.x,
            rect.min_y + rect.height() * binding.anchor.y,
        );

        let space = ElementSpace::new(target.rotation, rect.center());
        if binding.mode == ArrowBindingMode::Inside {
            return Some(space.to_world(local_anchor));
        }

        let gap = resolve_binding_gap(target);
        let local_reference = reference_point.map(|point| space.from_world(point));

        if is_circular_target(target) {
            let radius = resolve_circle_radius(rect);
            if radius <= 0.0 {
                return None;
            }

            let snap_point = resolve_circle_orbit_snap_point(
                rect.center(),
                radius,
                local_anchor,
                local_reference,
                gap,
                None,
            );
            return Some(space.to_world(snap_point));
        }

        let snap_point = resolve_orbit_snap_point(rect, local_anchor, local_reference, gap, None);
        Some(space.to_world(snap_point))
    }

    pub fn resolve_elbow_bound_point(
        binding: &ArrowBinding,
        target: &ElementState,
        has_arrowhead: bool,
    ) -> Option<DrawPoint> {
        let rect = target.rect;
        if rect.width() == 0.0 || rect.height() == 0.0 {
            return None;
        }

        let local_anchor = DrawPoint::new(
            rect.min_x + rect.width() * binding.anchor.x,
            rect.min_y + rect.height() * binding.anchor.y,
        );

        let space = ElementSpace::new(target.rotation, rect.center());
        if is_circular_target(target) {
            let radius = resolve_circle_radius(rect);
            if radius <= 0.0 {
                return None;
            }

            let anchor_point =
                resolve_circle_elbow_anchor_point(rect.center(), radius, local_anchor);
            let world_anchor = space.to_world(anchor_point);
            let heading = heading_for_vector(
                world_anchor.x - rect.center_x(),
                world_anchor.y - rect.center_y(),
            );
            let gap = resolve_elbow_binding_gap(has_arrowhead);
            return Some(DrawPoint::new(
                world_anchor.x + heading.dx * gap,
                world_anchor.y + heading.dy * gap,
            ));
        }

        let anchor_point = resolve_elbow_anchor_point(rect, local_anchor);
        let world_anchor = space.to_world(anchor_point);
        let heading = heading_for_point_on_bounds(compute_element_world_aabb(target), world_anchor);
        let gap = resolve_elbow_binding_gap(has_arrowhead);
        Some(DrawPoint::new(
            world_anchor.x + heading.dx * gap,
            world_anchor.y + heading.dy * gap,
        ))
    }

    pub fn resolve_elbow_anchor_point(
        binding: &ArrowBinding,
        target: &ElementState,
    ) -> Option<DrawPoint> {
        let rect = target.rect;
        if rect.width() == 0.0 || rect.height() == 0.0 {
            return None;
        }

        let local_anchor = DrawPoint::new(
            rect.min_x + rect.width() * binding.anchor.x,
            rect.min_y + rect.height() * binding.anchor.y,
        );

        let space = ElementSpace::new(target.rotation, rect.center());
        if is_circular_target(target) {
            let radius = resolve_circle_radius(rect);
            if radius <= 0.0 {
                return None;
            }

            let anchor_point =
                resolve_circle_elbow_anchor_point(rect.center(), radius, local_anchor);
            return Some(space.to_world(anchor_point));
        }

        let anchor_point = resolve_elbow_anchor_point(rect, local_anchor);
        Some(space.to_world(anchor_point))
    }

    pub fn binding_from_local_point(
        target: &ElementState,
        local_point: DrawPoint,
        mode: ArrowBindingMode,
    ) -> Option<ArrowBinding> {
        let rect = target.rect;
        if rect.width() == 0.0 || rect.height() == 0.0 {
            return None;
        }

        let normalized = DrawPoint::new(
            (local_point.x - rect.min_x) / rect.width(),
            (local_point.y - rect.min_y) / rect.height(),
        );

        Some(ArrowBinding::new(
            target.id.clone(),
            DrawPoint::new(clamp01(normalized.x), clamp01(normalized.y)),
            mode,
        ))
    }
}

fn resolve_best_binding_candidate<'a, I, F>(
    targets: I,
    snap_distance: f64,
    preferred_binding: Option<&ArrowBinding>,
    allow_new_binding: bool,
    mut resolver: F,
) -> Option<ArrowBindingResult>
where
    I: IntoIterator<Item = &'a ElementState>,
    F: FnMut(&ElementState) -> Option<ArrowBindingResult>,
{
    if snap_distance <= 0.0 {
        return None;
    }

    let preferred_element_id = preferred_binding.map(|binding| binding.element_id.as_str());
    if !allow_new_binding && preferred_element_id.is_none() {
        return None;
    }

    let mut best: Option<ArrowBindingResult> = None;
    let mut best_score = f64::INFINITY;

    for target in targets {
        if target.opacity <= 0.0 {
            continue;
        }

        if !allow_new_binding {
            if let Some(preferred_id) = preferred_element_id {
                if target.id != preferred_id {
                    continue;
                }
            }
        }

        let Some(candidate) = resolver(target) else {
            continue;
        };

        let mut score = candidate.distance;
        if preferred_element_id.is_some_and(|preferred_id| preferred_id == target.id) {
            score = (score - snap_distance * 0.25).max(0.0);
        }

        if is_better_binding_candidate(&candidate, score, best.as_ref(), best_score) {
            best_score = score;
            best = Some(candidate);
        }
    }

    best
}

fn is_better_binding_candidate(
    candidate: &ArrowBindingResult,
    candidate_score: f64,
    current_best: Option<&ArrowBindingResult>,
    current_best_score: f64,
) -> bool {
    if candidate_score < current_best_score {
        return true;
    }
    if candidate_score > current_best_score {
        return false;
    }

    let Some(current_best) = current_best else {
        return true;
    };

    if candidate.z_index > current_best.z_index {
        return true;
    }
    if candidate.z_index < current_best.z_index {
        return false;
    }

    candidate.binding.element_id < current_best.binding.element_id
}

#[derive(Clone, Copy, Debug)]
struct BindingHit {
    anchor_point: DrawPoint,
    snap_point: DrawPoint,
    mode: ArrowBindingMode,
    distance: f64,
}

const BINDING_GAP_BASE: f64 = 6.0;
const ELBOW_BINDING_GAP_BASE: f64 = 5.0;
const BINDING_HIT_TOLERANCE_FACTOR: f64 = 0.4;
const BINDING_ARROWHEAD_GAP_MULTIPLIER: f64 = BINDING_GAP_BASE / ELBOW_BINDING_GAP_BASE;
const INTERSECTION_EPSILON: f64 = 1e-6;
const INSIDE_EPSILON: f64 = 1e-6;

fn resolve_inside_binding_threshold(rect: DrawRect, snap_distance: f64) -> f64 {
    let max_depth = rect.width().abs().min(rect.height().abs()) / 2.0;
    snap_distance.max(0.0).min(max_depth.max(0.0))
}

fn resolve_inside_depth(rect: DrawRect, point: DrawPoint) -> f64 {
    let left = (point.x - rect.min_x).abs();
    let right = (rect.max_x - point.x).abs();
    let top = (point.y - rect.min_y).abs();
    let bottom = (rect.max_y - point.y).abs();
    left.min(right).min(top.min(bottom))
}

fn resolve_circle_inside_binding_threshold(radius: f64, snap_distance: f64) -> f64 {
    snap_distance.max(0.0).min(radius.max(0.0))
}

fn resolve_circle_inside_depth(center: DrawPoint, radius: f64, point: DrawPoint) -> f64 {
    let dx = point.x - center.x;
    let dy = point.y - center.y;
    let distance = (dx * dx + dy * dy).sqrt();
    radius - distance
}

fn nearest_point_on_rect_boundary(rect: DrawRect, point: DrawPoint) -> DrawPoint {
    let clamped_x = clamp(point.x, rect.min_x, rect.max_x);
    let clamped_y = clamp(point.y, rect.min_y, rect.max_y);

    let inside = point.x >= rect.min_x
        && point.x <= rect.max_x
        && point.y >= rect.min_y
        && point.y <= rect.max_y;

    if !inside {
        return DrawPoint::new(clamped_x, clamped_y);
    }

    let left = (point.x - rect.min_x).abs();
    let right = (rect.max_x - point.x).abs();
    let top = (point.y - rect.min_y).abs();
    let bottom = (rect.max_y - point.y).abs();

    let min_distance = left.min(right).min(top.min(bottom));
    if min_distance == left {
        return DrawPoint::new(rect.min_x, point.y);
    }
    if min_distance == right {
        return DrawPoint::new(rect.max_x, point.y);
    }
    if min_distance == top {
        return DrawPoint::new(point.x, rect.min_y);
    }

    DrawPoint::new(point.x, rect.max_y)
}

fn nearest_point_on_circle_boundary(center: DrawPoint, radius: f64, point: DrawPoint) -> DrawPoint {
    if radius <= 0.0 {
        return center;
    }

    let dx = point.x - center.x;
    let dy = point.y - center.y;
    let length = (dx * dx + dy * dy).sqrt();
    if length <= INTERSECTION_EPSILON {
        return DrawPoint::new(center.x + radius, center.y);
    }

    let scale = radius / length;
    DrawPoint::new(center.x + dx * scale, center.y + dy * scale)
}

fn resolve_binding_gap(target: &ElementState) -> f64 {
    let data = target.data.as_ref();
    let stroke_width = if let Some(rectangle_data) = decode_rectangle_data(data) {
        rectangle_data.stroke_width
    } else if let Some(text_data) = decode_text_data(data) {
        text_data.stroke_width
    } else if let Some(serial_data) = decode_serial_number_data(data) {
        resolve_serial_number_stroke_width(&serial_data, 0.0)
    } else {
        0.0
    };

    BINDING_GAP_BASE + stroke_width / 2.0
}

fn resolve_elbow_binding_gap(has_arrowhead: bool) -> f64 {
    if has_arrowhead {
        ELBOW_BINDING_GAP_BASE * BINDING_ARROWHEAD_GAP_MULTIPLIER
    } else {
        ELBOW_BINDING_GAP_BASE
    }
}

fn is_circular_target(target: &ElementState) -> bool {
    target.data.type_id().as_str() == SerialNumberData::TYPE_ID_TOKEN
}

fn resolve_circle_radius(rect: DrawRect) -> f64 {
    rect.width().abs().min(rect.height().abs()) / 2.0
}

fn inflate_rect(rect: DrawRect, delta: f64) -> DrawRect {
    DrawRect::new(
        rect.min_x - delta,
        rect.min_y - delta,
        rect.max_x + delta,
        rect.max_y + delta,
    )
}

fn resolve_binding_hit(
    rect: DrawRect,
    local_point: DrawPoint,
    local_reference: Option<DrawPoint>,
    snap_distance: f64,
    gap: f64,
) -> Option<BindingHit> {
    if is_strictly_inside_rect(rect, local_point) {
        let reference_inside =
            local_reference.is_some_and(|reference| is_strictly_inside_rect(rect, reference));

        let mut allow_inside = local_reference.is_none() || reference_inside;
        if !allow_inside {
            let inside_depth = resolve_inside_depth(rect, local_point);
            let inside_threshold = resolve_inside_binding_threshold(rect, snap_distance);
            allow_inside = inside_depth >= inside_threshold;
        }

        if allow_inside {
            return Some(BindingHit {
                anchor_point: local_point,
                snap_point: local_point,
                mode: ArrowBindingMode::Inside,
                distance: 0.0,
            });
        }

        let anchor_point = resolve_orbit_anchor_point(rect, local_point, local_reference);
        let snap_point =
            resolve_orbit_snap_point(rect, anchor_point, local_reference, gap, Some(local_point));
        return Some(BindingHit {
            anchor_point,
            snap_point,
            mode: ArrowBindingMode::Orbit,
            distance: 0.0,
        });
    }

    let anchor_point = resolve_orbit_anchor_point(rect, local_point, local_reference);
    let distance = local_point.distance(anchor_point);
    if distance > snap_distance * (1.0 + BINDING_HIT_TOLERANCE_FACTOR) {
        return None;
    }

    let snap_point =
        resolve_orbit_snap_point(rect, anchor_point, local_reference, gap, Some(local_point));

    Some(BindingHit {
        anchor_point,
        snap_point,
        mode: ArrowBindingMode::Orbit,
        distance,
    })
}

fn resolve_circle_binding_hit(
    rect: DrawRect,
    local_point: DrawPoint,
    local_reference: Option<DrawPoint>,
    snap_distance: f64,
    gap: f64,
) -> Option<BindingHit> {
    let radius = resolve_circle_radius(rect);
    if radius <= 0.0 {
        return None;
    }

    let center = rect.center();
    if is_strictly_inside_circle(center, radius, local_point) {
        let reference_inside = local_reference
            .is_some_and(|reference| is_strictly_inside_circle(center, radius, reference));

        let mut allow_inside = local_reference.is_none() || reference_inside;
        if !allow_inside {
            let inside_depth = resolve_circle_inside_depth(center, radius, local_point);
            let inside_threshold = resolve_circle_inside_binding_threshold(radius, snap_distance);
            allow_inside = inside_depth >= inside_threshold;
        }

        if allow_inside {
            return Some(BindingHit {
                anchor_point: local_point,
                snap_point: local_point,
                mode: ArrowBindingMode::Inside,
                distance: 0.0,
            });
        }

        let anchor_point =
            resolve_circle_orbit_anchor_point(center, radius, local_point, local_reference);
        let snap_point = resolve_circle_orbit_snap_point(
            center,
            radius,
            anchor_point,
            local_reference,
            gap,
            Some(local_point),
        );
        return Some(BindingHit {
            anchor_point,
            snap_point,
            mode: ArrowBindingMode::Orbit,
            distance: 0.0,
        });
    }

    let anchor_point =
        resolve_circle_orbit_anchor_point(center, radius, local_point, local_reference);
    let distance = local_point.distance(anchor_point);
    if distance > snap_distance * (1.0 + BINDING_HIT_TOLERANCE_FACTOR) {
        return None;
    }

    let snap_point = resolve_circle_orbit_snap_point(
        center,
        radius,
        anchor_point,
        local_reference,
        gap,
        Some(local_point),
    );

    Some(BindingHit {
        anchor_point,
        snap_point,
        mode: ArrowBindingMode::Orbit,
        distance,
    })
}

fn resolve_binding_on_target(
    target: &ElementState,
    world_point: DrawPoint,
    snap_distance: f64,
    reference_point: Option<DrawPoint>,
) -> Option<ArrowBindingResult> {
    let rect = target.rect;
    if rect.width() == 0.0 || rect.height() == 0.0 {
        return None;
    }

    let space = ElementSpace::new(target.rotation, rect.center());
    let local_point = space.from_world(world_point);
    let local_reference = reference_point.map(|point| space.from_world(point));
    let gap = resolve_binding_gap(target);

    let hit = if is_circular_target(target) {
        resolve_circle_binding_hit(rect, local_point, local_reference, snap_distance, gap)
    } else {
        resolve_binding_hit(rect, local_point, local_reference, snap_distance, gap)
    }?;

    let binding = ArrowBindingUtils::binding_from_local_point(target, hit.anchor_point, hit.mode)?;

    Some(ArrowBindingResult {
        binding,
        snap_point: space.to_world(hit.snap_point),
        distance: hit.distance,
        z_index: target.z_index,
    })
}

fn resolve_elbow_binding_on_target(
    target: &ElementState,
    world_point: DrawPoint,
    snap_distance: f64,
    has_arrowhead: bool,
) -> Option<ArrowBindingResult> {
    let rect = target.rect;
    if rect.width() == 0.0 || rect.height() == 0.0 {
        return None;
    }

    let space = ElementSpace::new(target.rotation, rect.center());
    let local_point = space.from_world(world_point);

    if is_circular_target(target) {
        let radius = resolve_circle_radius(rect);
        if radius <= 0.0 {
            return None;
        }

        let anchor_point = resolve_circle_elbow_anchor_point(rect.center(), radius, local_point);

        let distance = if is_strictly_inside_circle(rect.center(), radius, local_point) {
            0.0
        } else {
            local_point.distance(anchor_point)
        };

        if distance > snap_distance * (1.0 + BINDING_HIT_TOLERANCE_FACTOR) {
            return None;
        }

        let binding = ArrowBindingUtils::binding_from_local_point(
            target,
            anchor_point,
            ArrowBindingMode::Orbit,
        )?;

        let world_anchor = space.to_world(anchor_point);
        let heading = heading_for_vector(
            world_anchor.x - rect.center_x(),
            world_anchor.y - rect.center_y(),
        );
        let gap = resolve_elbow_binding_gap(has_arrowhead);
        let snap_point = DrawPoint::new(
            world_anchor.x + heading.dx * gap,
            world_anchor.y + heading.dy * gap,
        );

        return Some(ArrowBindingResult {
            binding,
            snap_point,
            distance,
            z_index: target.z_index,
        });
    }

    let anchor_point = resolve_elbow_anchor_point(rect, local_point);
    let distance = if is_strictly_inside_rect(rect, local_point) {
        0.0
    } else {
        local_point.distance(anchor_point)
    };

    if distance > snap_distance * (1.0 + BINDING_HIT_TOLERANCE_FACTOR) {
        return None;
    }

    let binding =
        ArrowBindingUtils::binding_from_local_point(target, anchor_point, ArrowBindingMode::Orbit)?;

    let world_anchor = space.to_world(anchor_point);
    let heading = heading_for_point_on_bounds(compute_element_world_aabb(target), world_anchor);
    let gap = resolve_elbow_binding_gap(has_arrowhead);
    let snap_point = DrawPoint::new(
        world_anchor.x + heading.dx * gap,
        world_anchor.y + heading.dy * gap,
    );

    Some(ArrowBindingResult {
        binding,
        snap_point,
        distance,
        z_index: target.z_index,
    })
}

fn resolve_orbit_anchor_point(
    rect: DrawRect,
    local_point: DrawPoint,
    local_reference: Option<DrawPoint>,
) -> DrawPoint {
    if let Some(reference) = local_reference {
        if let Some(intersection) =
            intersect_rect_along_line(rect, reference, local_point, Some(local_point), false)
        {
            return intersection;
        }
    }

    nearest_point_on_rect_boundary(rect, local_point)
}

fn resolve_elbow_anchor_point(rect: DrawRect, point: DrawPoint) -> DrawPoint {
    let center = rect.center();
    intersect_rect_along_line(rect, center, point, None, true)
        .unwrap_or_else(|| nearest_point_on_rect_boundary(rect, point))
}

fn resolve_orbit_snap_point(
    rect: DrawRect,
    anchor_point: DrawPoint,
    local_reference: Option<DrawPoint>,
    gap: f64,
    target_point: Option<DrawPoint>,
) -> DrawPoint {
    let snap_rect = if gap <= 0.0 {
        rect
    } else {
        inflate_rect(rect, gap)
    };
    let direction_point = target_point.unwrap_or(anchor_point);

    if let Some(reference) = local_reference {
        if let Some(intersection) =
            intersect_rect_along_line(snap_rect, reference, direction_point, None, true)
        {
            return intersection;
        }
    }

    nearest_point_on_rect_boundary(snap_rect, direction_point)
}

fn resolve_circle_orbit_anchor_point(
    center: DrawPoint,
    radius: f64,
    local_point: DrawPoint,
    local_reference: Option<DrawPoint>,
) -> DrawPoint {
    if let Some(reference) = local_reference {
        if let Some(intersection) = intersect_circle_along_line(
            center,
            radius,
            reference,
            local_point,
            Some(local_point),
            false,
        ) {
            return intersection;
        }
    }

    nearest_point_on_circle_boundary(center, radius, local_point)
}

fn resolve_circle_elbow_anchor_point(
    center: DrawPoint,
    radius: f64,
    point: DrawPoint,
) -> DrawPoint {
    let dx = point.x - center.x;
    let dy = point.y - center.y;
    let length = (dx * dx + dy * dy).sqrt();

    if length <= INTERSECTION_EPSILON {
        return DrawPoint::new(center.x + radius, center.y);
    }

    let scale = radius / length;
    DrawPoint::new(center.x + dx * scale, center.y + dy * scale)
}

fn resolve_circle_orbit_snap_point(
    center: DrawPoint,
    radius: f64,
    anchor_point: DrawPoint,
    local_reference: Option<DrawPoint>,
    gap: f64,
    target_point: Option<DrawPoint>,
) -> DrawPoint {
    let snap_radius = radius + gap;
    let direction_point = target_point.unwrap_or(anchor_point);

    if let Some(reference) = local_reference {
        if let Some(intersection) =
            intersect_circle_along_line(center, snap_radius, reference, direction_point, None, true)
        {
            return intersection;
        }
    }

    nearest_point_on_circle_boundary(center, snap_radius, direction_point)
}

fn is_strictly_inside_rect(rect: DrawRect, point: DrawPoint) -> bool {
    point.x > rect.min_x + INSIDE_EPSILON
        && point.x < rect.max_x - INSIDE_EPSILON
        && point.y > rect.min_y + INSIDE_EPSILON
        && point.y < rect.max_y - INSIDE_EPSILON
}

fn is_strictly_inside_circle(center: DrawPoint, radius: f64, point: DrawPoint) -> bool {
    if radius <= INSIDE_EPSILON {
        return false;
    }

    let dx = point.x - center.x;
    let dy = point.y - center.y;
    let distance_squared = dx * dx + dy * dy;
    let threshold = radius - INSIDE_EPSILON;
    distance_squared < threshold * threshold
}

fn intersect_rect_along_line(
    rect: DrawRect,
    reference: DrawPoint,
    target: DrawPoint,
    prefer_point: Option<DrawPoint>,
    prefer_ray: bool,
) -> Option<DrawPoint> {
    let dx = target.x - reference.x;
    let dy = target.y - reference.y;
    let length = (dx * dx + dy * dy).sqrt();
    if length <= INTERSECTION_EPSILON {
        return None;
    }

    let dir_x = dx / length;
    let dir_y = dy / length;
    let max_dim = rect.width().abs().max(rect.height().abs());
    let extend = length + max_dim + BINDING_GAP_BASE * 2.0;

    let start = DrawPoint::new(reference.x - dir_x * extend, reference.y - dir_y * extend);
    let end = DrawPoint::new(reference.x + dir_x * extend, reference.y + dir_y * extend);

    let mut intersections = segment_rect_intersections(rect, start, end);
    if intersections.is_empty() {
        return None;
    }

    if prefer_ray {
        let mut best: Option<DrawPoint> = None;
        let mut best_t = f64::INFINITY;

        for intersection in intersections {
            let t = (intersection.x - reference.x) * dir_x + (intersection.y - reference.y) * dir_y;
            if t < -INTERSECTION_EPSILON {
                continue;
            }
            if t < best_t {
                best_t = t;
                best = Some(intersection);
            }
        }

        return best;
    }

    let sort_point = prefer_point.unwrap_or(reference);
    intersections.sort_by(|a, b| {
        sort_point
            .distance_squared(*a)
            .total_cmp(&sort_point.distance_squared(*b))
    });

    intersections.into_iter().next()
}

fn intersect_circle_along_line(
    center: DrawPoint,
    radius: f64,
    reference: DrawPoint,
    target: DrawPoint,
    prefer_point: Option<DrawPoint>,
    prefer_ray: bool,
) -> Option<DrawPoint> {
    if radius <= 0.0 {
        return None;
    }

    let dx = target.x - reference.x;
    let dy = target.y - reference.y;
    let a = dx * dx + dy * dy;
    if a <= INTERSECTION_EPSILON {
        return None;
    }

    let ox = reference.x - center.x;
    let oy = reference.y - center.y;
    let b = 2.0 * (dx * ox + dy * oy);
    let c = ox * ox + oy * oy - radius * radius;
    let discriminant = b * b - 4.0 * a * c;
    if discriminant < 0.0 {
        return None;
    }

    let sqrt_d = discriminant.sqrt();
    let t1 = (-b - sqrt_d) / (2.0 * a);
    let t2 = (-b + sqrt_d) / (2.0 * a);
    let candidates = [t1, t2];

    if prefer_ray {
        let mut best_t: Option<f64> = None;
        for t in candidates {
            if t < -INTERSECTION_EPSILON {
                continue;
            }
            if best_t.map_or(true, |current| t < current) {
                best_t = Some(t);
            }
        }

        let best_t = best_t?;
        return Some(DrawPoint::new(
            reference.x + dx * best_t,
            reference.y + dy * best_t,
        ));
    }

    let sort_point = prefer_point.unwrap_or(reference);
    let mut best: Option<DrawPoint> = None;
    let mut best_distance = f64::INFINITY;

    for t in candidates {
        let point = DrawPoint::new(reference.x + dx * t, reference.y + dy * t);
        let distance = sort_point.distance_squared(point);
        if distance < best_distance {
            best_distance = distance;
            best = Some(point);
        }
    }

    best
}

fn segment_rect_intersections(rect: DrawRect, start: DrawPoint, end: DrawPoint) -> Vec<DrawPoint> {
    let mut intersections = Vec::<DrawPoint>::new();
    let dx = end.x - start.x;
    let dy = end.y - start.y;

    let mut add_if_valid = |t: f64, x: f64, y: f64| {
        if t < -INTERSECTION_EPSILON || t > 1.0 + INTERSECTION_EPSILON {
            return;
        }

        if x < rect.min_x - INTERSECTION_EPSILON
            || x > rect.max_x + INTERSECTION_EPSILON
            || y < rect.min_y - INTERSECTION_EPSILON
            || y > rect.max_y + INTERSECTION_EPSILON
        {
            return;
        }

        let point = DrawPoint::new(x, y);
        for existing in &intersections {
            if existing.distance_squared(point) <= INTERSECTION_EPSILON * INTERSECTION_EPSILON {
                return;
            }
        }

        intersections.push(point);
    };

    if dx.abs() > INTERSECTION_EPSILON {
        let mut t = (rect.min_x - start.x) / dx;
        let mut y = start.y + t * dy;
        add_if_valid(t, rect.min_x, y);

        t = (rect.max_x - start.x) / dx;
        y = start.y + t * dy;
        add_if_valid(t, rect.max_x, y);
    }

    if dy.abs() > INTERSECTION_EPSILON {
        let mut t = (rect.min_y - start.y) / dy;
        let mut x = start.x + t * dx;
        add_if_valid(t, x, rect.min_y);

        t = (rect.max_y - start.y) / dy;
        x = start.x + t * dx;
        add_if_valid(t, x, rect.max_y);
    }

    intersections
}

#[derive(Clone, Copy, Debug)]
struct Heading {
    dx: f64,
    dy: f64,
}

fn heading_for_vector(dx: f64, dy: f64) -> Heading {
    let length = (dx * dx + dy * dy).sqrt();
    if length <= INTERSECTION_EPSILON {
        return Heading { dx: 1.0, dy: 0.0 };
    }

    Heading {
        dx: dx / length,
        dy: dy / length,
    }
}

fn heading_for_point_on_bounds(bounds: DrawRect, point: DrawPoint) -> Heading {
    let left = (point.x - bounds.min_x).abs();
    let right = (bounds.max_x - point.x).abs();
    let top = (point.y - bounds.min_y).abs();
    let bottom = (bounds.max_y - point.y).abs();

    let min_distance = left.min(right).min(top.min(bottom));
    if (min_distance - left).abs() <= INTERSECTION_EPSILON {
        return Heading { dx: -1.0, dy: 0.0 };
    }
    if (min_distance - right).abs() <= INTERSECTION_EPSILON {
        return Heading { dx: 1.0, dy: 0.0 };
    }
    if (min_distance - top).abs() <= INTERSECTION_EPSILON {
        return Heading { dx: 0.0, dy: -1.0 };
    }

    Heading { dx: 0.0, dy: 1.0 }
}

fn compute_element_world_aabb(element: &ElementState) -> DrawRect {
    let rect = element.rect;
    let rotation = element.rotation;
    if rotation == 0.0 {
        return rect;
    }

    let center = rect.center();
    let half_width = rect.width().abs() / 2.0;
    let half_height = rect.height().abs() / 2.0;
    let cos_theta = rotation.cos().abs();
    let sin_theta = rotation.sin().abs();
    let x_extent = half_width * cos_theta + half_height * sin_theta;
    let y_extent = half_width * sin_theta + half_height * cos_theta;

    DrawRect::new(
        center.x - x_extent,
        center.y - y_extent,
        center.x + x_extent,
        center.y + y_extent,
    )
}

fn decode_rectangle_data(data: &dyn CoreElementData) -> Option<RectangleData> {
    if data.type_id().as_str() != RectangleData::TYPE_ID_TOKEN {
        return None;
    }
    RectangleData::from_json(&data.to_json()).ok()
}

fn decode_text_data(data: &dyn CoreElementData) -> Option<TextData> {
    if data.type_id().as_str() != TextData::TYPE_ID_TOKEN {
        return None;
    }
    TextData::from_json(&data.to_json()).ok()
}

fn decode_serial_number_data(data: &dyn CoreElementData) -> Option<SerialNumberData> {
    if data.type_id().as_str() != SerialNumberData::TYPE_ID_TOKEN {
        return None;
    }
    SerialNumberData::from_json(&data.to_json()).ok()
}

fn clamp(value: f64, min: f64, max: f64) -> f64 {
    value.max(min).min(max)
}

fn clamp01(value: f64) -> f64 {
    clamp(value, 0.0, 1.0)
}
