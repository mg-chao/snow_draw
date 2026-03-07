#![allow(dead_code)]

use crate::draw::config::snap_config::SnapConfig;
use crate::draw::elements::types::arrow::arrow_binding::{ArrowBinding, ArrowBindingMode};
use crate::draw::elements::types::arrow::arrow_core::{
    normalize_arrow_from_global_points, EngineContext, BIND_MODE_ORBIT, DEFAULT_MAX_COORDINATE,
};
use crate::draw::elements::types::arrow::arrow_core_bridge::{ArrowBindableState, ArrowCoreState};
use crate::draw::elements::types::arrow::core::arrow_elbow_core::compute_elbow_resize_patch;
use crate::draw::elements::types::arrow::core::arrow_order_core::reordered_element_ids_from_hovered_reorder;
use crate::draw::elements::types::arrow::core::arrow_types::{
    ApplyEngineResultValue, ArrowPatch, FixedPointBinding, FixedSegment,
    ReorderArrowAboveHoveredBindableResult,
};
use crate::draw::types::draw_point::DrawPoint;

const UNSET_ENDPOINT_BINDING_OPTION: u8 = 0;

/// Typed options forwarded into bridge-layer endpoint helpers.
#[derive(Clone, Copy, Debug, Default, PartialEq)]
pub struct ArrowCoreEndpointBindingOptions {
    pub complex_bindings: Option<bool>,
    pub new_arrow: bool,
    pub initial_binding: bool,
    pub finalize: bool,
    pub preserve_opposite_inside_binding: bool,
    pub opposite_orbit_focus_point: Option<DrawPoint>,
    pub angle_locked: bool,
    pub alt_key: bool,
}

impl ArrowCoreEndpointBindingOptions {
    /// Returns whether the options record carries any non-default values.
    pub fn is_empty(self) -> bool {
        self == Self::default()
    }

    /// Returns a copied options record with selectively replaced fields.
    #[allow(clippy::too_many_arguments)]
    pub fn copy_with(
        self,
        complex_bindings: Option<Option<bool>>,
        new_arrow: Option<bool>,
        initial_binding: Option<bool>,
        finalize: Option<bool>,
        preserve_opposite_inside_binding: Option<bool>,
        opposite_orbit_focus_point: Option<Option<DrawPoint>>,
        angle_locked: Option<bool>,
        alt_key: Option<bool>,
    ) -> Self {
        Self {
            complex_bindings: complex_bindings.unwrap_or(self.complex_bindings),
            new_arrow: new_arrow.unwrap_or(self.new_arrow),
            initial_binding: initial_binding.unwrap_or(self.initial_binding),
            finalize: finalize.unwrap_or(self.finalize),
            preserve_opposite_inside_binding: preserve_opposite_inside_binding
                .unwrap_or(self.preserve_opposite_inside_binding),
            opposite_orbit_focus_point: opposite_orbit_focus_point
                .unwrap_or(self.opposite_orbit_focus_point),
            angle_locked: angle_locked.unwrap_or(self.angle_locked),
            alt_key: alt_key.unwrap_or(self.alt_key),
        }
    }
}

/// Normalizes world-space points for core-style connector operations.
pub fn normalize_core_points(points: &[DrawPoint]) -> Vec<DrawPoint> {
    normalize_arrow_from_global_points(points, DEFAULT_MAX_COORDINATE).points
}

/// Resolves the effective binding gap for a projected bindable.
pub fn resolve_core_binding_gap(bindable: &ArrowBindableState, elbowed: bool) -> f64 {
    let base = (bindable.stroke_width.max(1.0) * 2.0).max(6.0);
    if elbowed {
        base.max(8.0)
    } else {
        base
    }
}

/// Resolves the maximum binding distance in world units.
pub fn resolve_core_max_binding_distance(zoom: f64) -> f64 {
    let screen_distance = SnapConfig::DEFAULT_ARROW_BINDING_DISTANCE;
    if zoom <= 0.0 {
        screen_distance
    } else {
        screen_distance / zoom
    }
}

/// Calculates a normalized fixed point for a bindable and pointer location.
pub fn calculate_core_fixed_point_for_binding(
    bindable: &ArrowBindableState,
    point: DrawPoint,
) -> DrawPoint {
    let rect = bindable.rect();
    let local = if bindable.angle == 0.0 {
        point
    } else {
        let space = crate::draw::core::coordinates::element_space::ElementSpace::new(
            bindable.angle,
            rect.center(),
        );
        space.from_world(point)
    };

    let width = rect.width().abs().max(1e-6);
    let height = rect.height().abs().max(1e-6);
    DrawPoint::new(
        ((local.x - rect.min_x) / width).clamp(0.0, 1.0),
        ((local.y - rect.min_y) / height).clamp(0.0, 1.0),
    )
}

/// Updates a bound point from a binding and projected bindable.
pub fn update_core_bound_point(
    _arrow: &ArrowCoreState,
    _edge: ArrowEndpointSelector,
    binding: Option<&ArrowBinding>,
    bindable: &ArrowBindableState,
    _dragging: bool,
) -> Option<DrawPoint> {
    let binding = binding?;
    let rect = bindable.rect();
    let local = DrawPoint::new(
        rect.min_x + rect.width() * binding.anchor.x,
        rect.min_y + rect.height() * binding.anchor.y,
    );
    if bindable.angle == 0.0 {
        Some(local)
    } else {
        let space = crate::draw::core::coordinates::element_space::ElementSpace::new(
            bindable.angle,
            rect.center(),
        );
        Some(space.to_world(local))
    }
}

/// Endpoint selector used by core-style binding helpers.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum ArrowEndpointSelector {
    Start,
    End,
}

/// Resolves whether endpoint drag should use binding-enabled semantics.
pub fn resolve_endpoint_drag_binding_enabled(is_binding_enabled: bool) -> &'static str {
    match resolve_arrow_binding_mode(is_binding_enabled) {
        ArrowBindingMode::Inside => "inside",
        ArrowBindingMode::Orbit => "orbit",
        ArrowBindingMode::Skip => "skip",
    }
}

/// Resolves the explicit endpoint binding mode for preview helpers.
pub fn resolve_arrow_binding_mode(is_binding_enabled: bool) -> ArrowBindingMode {
    if is_binding_enabled {
        ArrowBindingMode::Orbit
    } else {
        ArrowBindingMode::Skip
    }
}

/// Creates a default bridge-layer engine context.
pub fn default_engine_context() -> EngineContext {
    EngineContext::new(1.0, true, BIND_MODE_ORBIT, DEFAULT_MAX_COORDINATE)
}

/// Typed wrapper around resize-time elbow binding normalization.
pub fn compute_core_elbow_resize_patch(
    start_binding: Option<&FixedPointBinding>,
    end_binding: Option<&FixedPointBinding>,
    fixed_segments: Option<&[FixedSegment]>,
    points: &[DrawPoint],
    flip_x: bool,
    flip_y: bool,
) -> ArrowPatch {
    compute_elbow_resize_patch(
        start_binding,
        end_binding,
        fixed_segments,
        Some(points),
        flip_x,
        flip_y,
    )
}

/// Returns reordered ids only when hovered-bindable reordering moved the arrow.
pub fn reordered_element_ids_from_core_hovered_reorder(
    result: &ReorderArrowAboveHoveredBindableResult,
) -> Option<Vec<String>> {
    reordered_element_ids_from_hovered_reorder(result)
}

/// Returns `true` when applying an engine result changed element order.
pub fn did_core_engine_result_reorder(value: &ApplyEngineResultValue) -> bool {
    value.order_changed.unwrap_or(false)
}

/// Returns reordered ids only when the engine explicitly moved elements.
pub fn reordered_element_ids_from_core_result(
    value: &ApplyEngineResultValue,
) -> Option<Vec<String>> {
    did_core_engine_result_reorder(value)
        .then(|| value.ordered_element_ids.clone())
        .flatten()
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::draw::elements::types::arrow::core::arrow_types::{
        ArrowState, BindableRelationState,
    };
    use serde_json::{Map, Value};

    #[test]
    fn compute_core_elbow_resize_patch_mirrors_binding_points() {
        let start_binding = FixedPointBinding::new("start", DrawPoint::new(0.25, 0.75), "orbit");
        let end_binding = FixedPointBinding::new("end", DrawPoint::new(0.75, 0.25), "inside");

        let patch = compute_core_elbow_resize_patch(
            Some(&start_binding),
            Some(&end_binding),
            None,
            &[DrawPoint::ZERO, DrawPoint::new(100.0, 0.0)],
            true,
            false,
        );

        let mirrored_start = patch
            .get("startBinding")
            .and_then(Value::as_object)
            .and_then(|binding: &Map<String, Value>| binding.get("fixedPoint"))
            .and_then(Value::as_array)
            .expect("mirrored start binding");
        let mirrored_end = patch
            .get("endBinding")
            .and_then(Value::as_object)
            .and_then(|binding: &Map<String, Value>| binding.get("fixedPoint"))
            .and_then(Value::as_array)
            .expect("mirrored end binding");

        assert_eq!(mirrored_start[0].as_f64(), Some(0.75));
        assert_eq!(mirrored_start[1].as_f64(), Some(0.75));
        assert_eq!(mirrored_end[0].as_f64(), Some(0.25));
        assert_eq!(mirrored_end[1].as_f64(), Some(0.25));
    }

    #[test]
    fn did_core_engine_result_reorder_reads_optional_flag() {
        let value = ApplyEngineResultValue {
            arrow: ArrowState {
                id: "arrow".to_owned(),
                x: 0.0,
                y: 0.0,
                width: 0.0,
                height: 0.0,
                points: vec![DrawPoint::ZERO, DrawPoint::new(10.0, 0.0)],
                start_binding: None,
                end_binding: None,
                start_arrowhead: None,
                end_arrowhead: None,
                elbowed: false,
                fixed_segments: None,
                start_is_special: None,
                end_is_special: None,
            },
            bindables: Vec::<BindableRelationState>::new(),
            relation_patches: Vec::new(),
            ordered_element_ids: Some(vec!["a".to_owned(), "b".to_owned()]),
            order_changed: Some(true),
            reorder_operations: None,
            binding_broken_events: None,
        };

        assert!(did_core_engine_result_reorder(&value));
        assert_eq!(
            reordered_element_ids_from_core_result(&value),
            Some(vec!["a".to_owned(), "b".to_owned()])
        );
    }

    #[test]
    fn reordered_element_ids_from_core_result_ignores_unchanged_order() {
        let value = ApplyEngineResultValue {
            arrow: ArrowState {
                id: "arrow".to_owned(),
                x: 0.0,
                y: 0.0,
                width: 0.0,
                height: 0.0,
                points: vec![DrawPoint::ZERO, DrawPoint::new(10.0, 0.0)],
                start_binding: None,
                end_binding: None,
                start_arrowhead: None,
                end_arrowhead: None,
                elbowed: false,
                fixed_segments: None,
                start_is_special: None,
                end_is_special: None,
            },
            bindables: Vec::<BindableRelationState>::new(),
            relation_patches: Vec::new(),
            ordered_element_ids: Some(vec!["a".to_owned(), "b".to_owned()]),
            order_changed: Some(false),
            reorder_operations: None,
            binding_broken_events: None,
        };

        assert!(!did_core_engine_result_reorder(&value));
        assert_eq!(reordered_element_ids_from_core_result(&value), None);
    }
}
