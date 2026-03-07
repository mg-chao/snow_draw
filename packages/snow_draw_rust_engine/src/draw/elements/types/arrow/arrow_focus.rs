#![allow(dead_code)]

use crate::draw::elements::types::arrow::arrow_binding::{ArrowBinding, ArrowBindingMode};
use crate::draw::elements::types::arrow::arrow_core::ArrowEndpointEdge;
use crate::draw::elements::types::arrow::arrow_core_bridge::{
    apply_core_arrow_patch_to_element, collect_core_bindable_relations,
};
use crate::draw::elements::types::arrow::arrow_data::ArrowData;
use crate::draw::elements::types::arrow::arrow_data::{
    ArrowBinding as SourceArrowBinding, ArrowBindingMode as SourceArrowBindingMode,
};
use crate::draw::elements::types::arrow::arrow_scene::ArrowScene;
use crate::draw::elements::types::arrow::core::arrow_engine::{
    compute_focus_drag as compute_core_focus_drag,
    finalize_focus_drag as finalize_core_focus_drag,
};
use crate::draw::elements::types::arrow::core::arrow_state_core::apply_engine_result;
use crate::draw::elements::types::arrow::core::arrow_types::{
    ApplyEngineResultInput, ArrowBindingState, BindablePatch,
    BindableState as LifecycleBindableState, EngineContext as LifecycleEngineContext,
    FixedPointBinding,
};
use crate::draw::models::element_state::ElementState;
use crate::draw::types::draw_point::DrawPoint;
use crate::draw::types::element_style::{ArrowType, ArrowheadStyle};

use super::core::arrow_focus_core::{
    resolve_focus_point_hit_with_offset, resolve_visible_focus_points,
};

#[derive(Clone, Copy, Debug, PartialEq, Eq, Hash)]
pub enum ArrowFocusEndpoint {
    Start,
    End,
}

#[derive(Clone, Debug, PartialEq)]
pub struct ArrowFocusPoint {
    pub endpoint: ArrowFocusEndpoint,
    pub point: DrawPoint,
}

#[derive(Clone, Debug, PartialEq)]
pub struct ArrowFocusHit {
    pub endpoint: Option<ArrowFocusEndpoint>,
    pub pointer_offset: DrawPoint,
}

#[derive(Clone, Debug, PartialEq)]
pub struct ArrowFocusDragResult {
    pub element: ElementState,
    pub element_changed: bool,
    pub bindable_patches: Vec<BindablePatch>,
    pub ordered_element_ids: Option<Vec<String>>,
    pub suggested_bindable_id: Option<String>,
}

#[derive(Clone, Debug, Default, PartialEq)]
pub struct ArrowFocusFinalizeResult {
    pub bindable_patches: Vec<BindablePatch>,
}

pub fn list_visible_arrow_focus_points(
    element: &ElementState,
    data: &ArrowData,
) -> Vec<ArrowFocusPoint> {
    if data.arrow_type == ArrowType::Elbow {
        return Vec::new();
    }
    let arrow = to_arrow_state(element, data);
    resolve_visible_focus_points(&arrow)
        .into_iter()
        .map(|descriptor| ArrowFocusPoint {
            endpoint: match descriptor.edge {
                ArrowEndpointEdge::Start => ArrowFocusEndpoint::Start,
                ArrowEndpointEdge::End => ArrowFocusEndpoint::End,
            },
            point: descriptor.point,
        })
        .collect()
}

pub fn pick_arrow_focus_point_with_offset(
    element: &ElementState,
    data: &ArrowData,
    pointer: DrawPoint,
    tolerance: f64,
) -> ArrowFocusHit {
    if data.arrow_type == ArrowType::Elbow {
        return ArrowFocusHit {
            endpoint: None,
            pointer_offset: DrawPoint::ZERO,
        };
    }

    let hit =
        resolve_focus_point_hit_with_offset(&to_arrow_state(element, data), pointer, tolerance);
    ArrowFocusHit {
        endpoint: hit.edge.map(|edge| match edge {
            ArrowEndpointEdge::Start => ArrowFocusEndpoint::Start,
            ArrowEndpointEdge::End => ArrowFocusEndpoint::End,
        }),
        pointer_offset: hit.pointer_offset,
    }
}

#[allow(clippy::too_many_arguments)]
pub fn drag_arrow_focus_point(
    element: &ElementState,
    data: &ArrowData,
    elements: &[ElementState],
    dragged_endpoint: ArrowFocusEndpoint,
    pointer: DrawPoint,
    engine_context: Option<super::arrow_core::EngineContext>,
    switch_to_inside_binding: bool,
    _grid_size: Option<f64>,
    ordered_element_ids: Option<&[String]>,
) -> ArrowFocusDragResult {
    if data.arrow_type == ArrowType::Elbow {
        return ArrowFocusDragResult {
            element: element.clone(),
            element_changed: false,
            bindable_patches: Vec::new(),
            ordered_element_ids: None,
            suggested_bindable_id: None,
        };
    }

    let session = ArrowScene::from_elements_with_options(
        elements.to_vec(),
        false,
        ordered_element_ids,
        engine_context,
    );
    let arrow = to_arrow_state(element, data);
    let lifecycle_arrow = to_lifecycle_arrow_state(&arrow);
    let lifecycle_bindables = session
        .bindables()
        .iter()
        .map(to_lifecycle_bindable_state)
        .collect::<Vec<_>>();
    let lifecycle_context = to_lifecycle_context(&session.context);
    let result = compute_core_focus_drag(
        &lifecycle_arrow,
        pointer,
        endpoint_to_lifecycle(dragged_endpoint),
        &lifecycle_bindables,
        lifecycle_context,
        switch_to_inside_binding,
    );
    let bindable_patches = result.bindable_patches.clone();
    let suggested_bindable_id = result.suggested_binding.as_ref().and_then(|binding| {
        binding
            .bindable_id
            .clone()
            .or_else(|| (!binding.element.id.is_empty()).then(|| binding.element.id.clone()))
    });

    let applied = apply_engine_result(&ApplyEngineResultInput {
        arrow: lifecycle_arrow,
        bindables: collect_core_bindable_relations(elements),
        result,
        ordered_element_ids: ordered_element_ids.map(|ids| ids.to_vec()),
        anchor_element_ids_by_bindable_id: Some(session.anchor_element_ids_by_bindable_id().clone()),
    });
    let fallback_order = if applied.order_changed.unwrap_or(false) {
        None
    } else {
        suggested_bindable_id.as_ref().and_then(|bindable_id| {
            session.reorder_arrow_above_hovered_bindable(
                &element.id,
                Some(bindable_id.as_str()),
                Some(pointer),
                ordered_element_ids,
                None,
            )
        })
    };
    let next_order = applied.ordered_element_ids.clone().or(fallback_order);
    let patched_element = if applied.arrow == to_lifecycle_arrow_state(&arrow) {
        element.clone()
    } else {
        apply_core_arrow_patch_to_element(element, data, &applied.arrow_to_patch())
    };

    ArrowFocusDragResult {
        element_changed: patched_element != *element,
        element: patched_element,
        bindable_patches,
        ordered_element_ids: next_order,
        suggested_bindable_id,
    }
}

pub fn finalize_arrow_focus_point_drag(
    element: &ElementState,
    data: &ArrowData,
    elements: &[ElementState],
) -> ArrowFocusFinalizeResult {
    if data.arrow_type == ArrowType::Elbow {
        return ArrowFocusFinalizeResult {
            bindable_patches: Vec::new(),
        };
    }

    let result = finalize_core_focus_drag(
        &ArrowBindingState {
            id: element.id.clone(),
            start_binding: data.start_binding.as_ref().map(to_lifecycle_binding_from_source),
            end_binding: data.end_binding.as_ref().map(to_lifecycle_binding_from_source),
        },
        &collect_core_bindable_relations(elements),
    );

    ArrowFocusFinalizeResult {
        bindable_patches: result.bindable_patches,
    }
}

fn to_arrow_state(element: &ElementState, data: &ArrowData) -> super::arrow_core::ArrowState {
    let world_points =
        crate::draw::elements::types::connector::connector_geometry::resolve_connector_world_points(
            element.rect,
            &data.points,
        );
    let normalized = super::arrow_core::normalize_arrow_from_global_points(
        &world_points,
        super::arrow_core::DEFAULT_MAX_COORDINATE,
    );
    super::arrow_core::ArrowState {
        id: element.id.clone(),
        x: normalized.x,
        y: normalized.y,
        width: normalized.width,
        height: normalized.height,
        points: normalized.points,
        start_binding: data.start_binding.as_ref().map(to_engine_binding),
        end_binding: data.end_binding.as_ref().map(to_engine_binding),
        start_arrowhead: Some(arrowhead_name(data.start_arrowhead).to_string()),
        end_arrowhead: Some(arrowhead_name(data.end_arrowhead).to_string()),
        elbowed: data.arrow_type == ArrowType::Elbow,
        fixed_segments: data.fixed_segments.clone(),
        start_is_special: data.start_is_special,
        end_is_special: data.end_is_special,
    }
}

fn endpoint_to_lifecycle(
    endpoint: ArrowFocusEndpoint,
) -> crate::draw::elements::types::arrow::core::arrow_types::ArrowEndpointEdge {
    match endpoint {
        ArrowFocusEndpoint::Start => {
            crate::draw::elements::types::arrow::core::arrow_types::ArrowEndpointEdge::Start
        }
        ArrowFocusEndpoint::End => {
            crate::draw::elements::types::arrow::core::arrow_types::ArrowEndpointEdge::End
        }
    }
}

fn to_engine_binding(binding: &SourceArrowBinding) -> ArrowBinding {
    ArrowBinding::new(
        binding.element_id.clone(),
        binding.anchor,
        match binding.mode {
            SourceArrowBindingMode::Inside => ArrowBindingMode::Inside,
            SourceArrowBindingMode::Orbit => ArrowBindingMode::Orbit,
            SourceArrowBindingMode::Skip => ArrowBindingMode::Skip,
        },
    )
}

fn to_lifecycle_arrow_state(
    arrow: &super::arrow_core::ArrowState,
) -> crate::draw::elements::types::arrow::core::arrow_types::ArrowState {
    crate::draw::elements::types::arrow::core::arrow_types::ArrowState {
        id: arrow.id.clone(),
        x: arrow.x,
        y: arrow.y,
        width: arrow.width,
        height: arrow.height,
        points: arrow.points.clone(),
        start_binding: arrow.start_binding.as_ref().map(to_lifecycle_binding),
        end_binding: arrow.end_binding.as_ref().map(to_lifecycle_binding),
        start_arrowhead: arrow.start_arrowhead.clone(),
        end_arrowhead: arrow.end_arrowhead.clone(),
        elbowed: arrow.elbowed,
        fixed_segments: arrow.fixed_segments.as_ref().map(|segments| {
            segments
                .iter()
                .copied()
                .map(|segment| crate::draw::elements::types::arrow::core::arrow_types::FixedSegment {
                    start: segment.start,
                    end: segment.end,
                    index: segment.index,
                })
                .collect()
        }),
        start_is_special: arrow.start_is_special,
        end_is_special: arrow.end_is_special,
    }
}

fn to_lifecycle_binding(binding: &ArrowBinding) -> FixedPointBinding {
    FixedPointBinding::new(
        binding.element_id.clone(),
        binding.anchor,
        binding.mode.as_str().to_string(),
    )
}

fn to_lifecycle_binding_from_source(binding: &SourceArrowBinding) -> FixedPointBinding {
    FixedPointBinding::new(
        binding.element_id.clone(),
        binding.anchor,
        match binding.mode {
            SourceArrowBindingMode::Inside => "inside",
            SourceArrowBindingMode::Orbit => "orbit",
            SourceArrowBindingMode::Skip => "skip",
        },
    )
}

fn to_lifecycle_bindable_state(bindable: &super::arrow_core::BindableState) -> LifecycleBindableState {
    LifecycleBindableState {
        id: bindable.id.clone(),
        shape: bindable.shape.as_str().to_string(),
        x: bindable.x,
        y: bindable.y,
        width: bindable.width,
        height: bindable.height,
        angle: bindable.angle,
        stroke_width: bindable.stroke_width,
        roundness: None,
        z_index: bindable.z_index,
        background_opaque: bindable.background_opaque,
        binding_enabled: bindable.binding_enabled,
        interior_hit_enabled: bindable.interior_hit_enabled,
        visibility_bounds: bindable.visibility_bounds,
    }
}

fn to_lifecycle_context(
    context: &super::arrow_core::EngineContext,
) -> LifecycleEngineContext {
    LifecycleEngineContext {
        zoom: context.zoom,
        is_binding_enabled: context.is_binding_enabled,
        bind_mode: context.bind_mode,
        max_coordinate: context.max_coordinate,
    }
}

fn lifecycle_arrow_to_patch(
    arrow: &crate::draw::elements::types::arrow::core::arrow_types::ArrowState,
) -> serde_json::Map<String, serde_json::Value> {
    use serde_json::Value;

    let mut patch = serde_json::Map::new();
    patch.insert("x".to_owned(), Value::from(arrow.x));
    patch.insert("y".to_owned(), Value::from(arrow.y));
    patch.insert("width".to_owned(), Value::from(arrow.width));
    patch.insert("height".to_owned(), Value::from(arrow.height));
    patch.insert(
        "points".to_owned(),
        Value::Array(
            arrow.points
                .iter()
                .map(|point| Value::Array(vec![Value::from(point.x), Value::from(point.y)]))
                .collect(),
        ),
    );
    patch.insert(
        "startBinding".to_owned(),
        lifecycle_binding_to_value(arrow.start_binding.as_ref()),
    );
    patch.insert(
        "endBinding".to_owned(),
        lifecycle_binding_to_value(arrow.end_binding.as_ref()),
    );
    if let Some(fixed_segments) = arrow.fixed_segments.as_ref() {
        patch.insert(
            "fixedSegments".to_owned(),
            Value::Array(
                fixed_segments
                    .iter()
                    .map(|segment| {
                        let mut value = serde_json::Map::new();
                        value.insert("index".to_owned(), Value::from(segment.index));
                        value.insert(
                            "start".to_owned(),
                            Value::Array(vec![Value::from(segment.start.x), Value::from(segment.start.y)]),
                        );
                        value.insert(
                            "end".to_owned(),
                            Value::Array(vec![Value::from(segment.end.x), Value::from(segment.end.y)]),
                        );
                        Value::Object(value)
                    })
                    .collect(),
            ),
        );
    }
    if let Some(start_is_special) = arrow.start_is_special {
        patch.insert("startIsSpecial".to_owned(), Value::from(start_is_special));
    }
    if let Some(end_is_special) = arrow.end_is_special {
        patch.insert("endIsSpecial".to_owned(), Value::from(end_is_special));
    }
    patch
}

fn lifecycle_binding_to_value(binding: Option<&FixedPointBinding>) -> serde_json::Value {
    use serde_json::Value;

    let Some(binding) = binding else {
        return Value::Null;
    };

    let mut value = serde_json::Map::new();
    value.insert("elementId".to_owned(), Value::String(binding.element_id.clone()));
    value.insert(
        "fixedPoint".to_owned(),
        Value::Array(vec![
            Value::from(binding.fixed_point.x),
            Value::from(binding.fixed_point.y),
        ]),
    );
    value.insert("mode".to_owned(), Value::String(binding.mode.clone()));
    Value::Object(value)
}

fn arrowhead_name(style: ArrowheadStyle) -> &'static str {
    match style {
        ArrowheadStyle::None => "none",
        ArrowheadStyle::Standard => "standard",
        ArrowheadStyle::Triangle => "triangle",
        ArrowheadStyle::TriangleOutline => "triangleOutline",
        ArrowheadStyle::Square => "square",
        ArrowheadStyle::Dot => "dot",
        ArrowheadStyle::Circle => "circle",
        ArrowheadStyle::CircleOutline => "circleOutline",
        ArrowheadStyle::Diamond => "diamond",
        ArrowheadStyle::DiamondOutline => "diamondOutline",
        ArrowheadStyle::CrowfootOne => "crowfootOne",
        ArrowheadStyle::CrowfootMany => "crowfootMany",
        ArrowheadStyle::CrowfootOneOrMany => "crowfootOneOrMany",
        ArrowheadStyle::InvertedTriangle => "invertedTriangle",
        ArrowheadStyle::VerticalLine => "verticalLine",
    }
}

trait ApplyEngineResultValueExt {
    fn arrow_to_patch(&self) -> serde_json::Map<String, serde_json::Value>;
}

impl ApplyEngineResultValueExt
    for crate::draw::elements::types::arrow::core::arrow_types::ApplyEngineResultValue
{
    fn arrow_to_patch(&self) -> serde_json::Map<String, serde_json::Value> {
        lifecycle_arrow_to_patch(&self.arrow)
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::draw::elements::types::arrow::arrow_data::ArrowDataPatch;
    use crate::draw::elements::types::rectangle::rectangle_data::RectangleData;
    use crate::draw::types::draw_rect::DrawRect;
    use std::sync::Arc;

    fn arrow_element() -> (ElementState, ArrowData) {
        let data = ArrowData::default().copy_with(ArrowDataPatch {
            points: Some(vec![DrawPoint::ZERO, DrawPoint::new(100.0, 20.0)]),
            ..ArrowDataPatch::default()
        });
        let element = ElementState::new(
            "arrow-1",
            DrawRect::new(10.0, 10.0, 110.0, 30.0),
            0.0,
            1.0,
            1,
            Arc::new(data.clone()),
        );
        (element, data)
    }

    fn rect_element(id: &str, z_index: i64) -> ElementState {
        ElementState::new(
            id,
            DrawRect::new(20.0, 30.0, 120.0, 110.0),
            0.0,
            1.0,
            z_index,
            Arc::new(RectangleData::default()),
        )
    }

    #[test]
    fn drag_focus_point_reports_bindable_patches_and_order_fallback() {
        let (arrow_element, arrow_data) = arrow_element();
        let rect = rect_element("rect-1", 2);
        let ordered = vec![arrow_element.id.clone(), rect.id.clone()];

        let result = drag_arrow_focus_point(
            &arrow_element,
            &arrow_data,
            &[arrow_element.clone(), rect],
            ArrowFocusEndpoint::Start,
            DrawPoint::new(20.0, 60.0),
            None,
            false,
            None,
            Some(&ordered),
        );

        assert_eq!(result.suggested_bindable_id.as_deref(), Some("rect-1"));
        assert!(!result.bindable_patches.is_empty());
        assert_eq!(
            result.ordered_element_ids,
            Some(vec!["rect-1".to_owned(), "arrow-1".to_owned()])
        );
    }

    #[test]
    fn finalize_focus_point_drag_returns_relation_patches() {
        let (arrow_element, mut arrow_data) = arrow_element();
        arrow_data.start_binding = Some(SourceArrowBinding {
            element_id: "rect-1".to_owned(),
            anchor: DrawPoint::new(0.5, 0.5),
            mode: SourceArrowBindingMode::Orbit,
        });
        let rect = rect_element("rect-1", 2);

        let result = finalize_arrow_focus_point_drag(
            &arrow_element,
            &arrow_data,
            &[arrow_element.clone(), rect],
        );

        assert_eq!(result.bindable_patches.len(), 1);
        assert_eq!(
            result.bindable_patches[0].add_bound_arrow_id.as_deref(),
            Some("arrow-1")
        );
    }
}
