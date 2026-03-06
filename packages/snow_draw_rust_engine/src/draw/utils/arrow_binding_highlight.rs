#![allow(dead_code)]

use serde_json::Value;

use crate::draw::edit::arrow::arrow_point_operation::{ArrowPointEditContext, ArrowPointKind};
use crate::draw::edit::connector::connector_point_operation::ConnectorPointEditContext;
use crate::draw::elements::core::element_data::ElementData;
use crate::draw::elements::types::arrow::arrow_data::{ArrowBinding, ArrowBindingMode, ArrowData};
use crate::draw::elements::types::line::line_data::LineData;
use crate::draw::types::draw_point::DrawPoint;
use crate::draw::types::edit_transform::EditTransform;

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
enum ArrowEndpoint {
    Start,
    End,
}

/// Lightweight endpoint-binding pair used by highlight resolution.
#[derive(Clone, Debug, Default, PartialEq)]
pub struct ArrowBindingPair {
    pub start_binding: Option<ArrowBinding>,
    pub end_binding: Option<ArrowBinding>,
}

/// Resolves the binding to highlight during arrow-point editing.
///
/// Mirrors Dart `resolveArrowPointEditHighlightBinding`:
/// 1) resolve edited endpoint from arrow-point context;
/// 2) prefer in-flight transform binding;
/// 3) fallback to current element data binding.
pub fn resolve_arrow_point_edit_highlight_binding(
    context: &ArrowPointEditContext,
    bindings: &ArrowBindingPair,
    transform: Option<&EditTransform>,
) -> Option<ArrowBinding> {
    let endpoint = resolve_endpoint_for_context(context)?;

    if let Some(binding) = binding_from_transform(endpoint, transform) {
        return Some(binding);
    }

    match endpoint {
        ArrowEndpoint::Start => bindings.start_binding.clone(),
        ArrowEndpoint::End => bindings.end_binding.clone(),
    }
}

/// Resolves the binding to highlight during connector-point editing.
pub fn resolve_connector_point_edit_highlight_binding(
    context: &ConnectorPointEditContext,
    bindings: &ArrowBindingPair,
    transform: Option<&EditTransform>,
) -> Option<ArrowBinding> {
    resolve_arrow_point_edit_highlight_binding(context, bindings, transform)
}

/// Fallback endpoint-binding resolver when only active index is available.
///
/// This is used by view layers where operation-specific typed context is not
/// persisted in interaction state.
pub fn resolve_arrow_point_highlight_binding_from_active_index(
    points_len: usize,
    active_index: Option<usize>,
    bindings: &ArrowBindingPair,
    transform: Option<&EditTransform>,
) -> Option<ArrowBinding> {
    let active_index = active_index?;
    if points_len < 2 {
        return None;
    }

    let endpoint = if active_index == 0 {
        ArrowEndpoint::Start
    } else if active_index + 1 == points_len {
        ArrowEndpoint::End
    } else {
        return None;
    };

    if let Some(binding) = binding_from_transform(endpoint, transform) {
        return Some(binding);
    }

    match endpoint {
        ArrowEndpoint::Start => bindings.start_binding.clone(),
        ArrowEndpoint::End => bindings.end_binding.clone(),
    }
}

/// Fallback endpoint-binding resolver for connector-point overlays.
pub fn resolve_connector_point_highlight_binding_from_active_index(
    points_len: usize,
    active_index: Option<usize>,
    bindings: &ArrowBindingPair,
    transform: Option<&EditTransform>,
) -> Option<ArrowBinding> {
    resolve_arrow_point_highlight_binding_from_active_index(
        points_len,
        active_index,
        bindings,
        transform,
    )
}

/// Extracts endpoint bindings from a runtime element payload.
pub fn resolve_arrow_binding_pair(data: &dyn ElementData) -> Option<ArrowBindingPair> {
    let type_id = data.type_id();
    let type_id = type_id.as_str();
    if type_id != ArrowData::TYPE_ID_TOKEN && type_id != LineData::TYPE_ID_TOKEN {
        return None;
    }

    let payload = data.to_json_value();
    let json = payload.as_object()?;
    Some(ArrowBindingPair {
        start_binding: parse_binding(json.get("startBinding"))?,
        end_binding: parse_binding(json.get("endBinding"))?,
    })
}

fn resolve_endpoint_for_context(context: &ArrowPointEditContext) -> Option<ArrowEndpoint> {
    match context.point_kind {
        ArrowPointKind::LoopStart => Some(ArrowEndpoint::Start),
        ArrowPointKind::LoopEnd => Some(ArrowEndpoint::End),
        ArrowPointKind::FocusStart => Some(ArrowEndpoint::Start),
        ArrowPointKind::FocusEnd => Some(ArrowEndpoint::End),
        ArrowPointKind::Turning => {
            let last_index = context.initial_points.len().checked_sub(1)?;
            if context.point_index == 0 {
                Some(ArrowEndpoint::Start)
            } else if context.point_index == last_index {
                Some(ArrowEndpoint::End)
            } else {
                None
            }
        }
        ArrowPointKind::Addable => None,
    }
}

fn binding_from_transform(
    endpoint: ArrowEndpoint,
    transform: Option<&EditTransform>,
) -> Option<ArrowBinding> {
    let EditTransform::ArrowPoint(arrow_transform) = transform? else {
        return None;
    };

    match endpoint {
        ArrowEndpoint::Start => arrow_transform.start_binding.clone(),
        ArrowEndpoint::End => arrow_transform.end_binding.clone(),
    }
}

fn parse_binding(raw: Option<&Value>) -> Option<Option<ArrowBinding>> {
    let raw = match raw {
        Some(raw) => raw,
        None => return Some(None),
    };
    if raw.is_null() {
        return Some(None);
    }
    let json = raw.as_object()?;
    let element_id = json.get("elementId").and_then(Value::as_str)?.to_owned();
    let anchor_json = json.get("anchor")?.as_object()?;
    let anchor_x = anchor_json.get("x").and_then(Value::as_f64)?;
    let anchor_y = anchor_json.get("y").and_then(Value::as_f64)?;
    let mode = json
        .get("mode")
        .and_then(Value::as_str)
        .and_then(parse_binding_mode)
        .unwrap_or(ArrowBindingMode::Orbit);

    Some(Some(ArrowBinding::new(
        element_id,
        DrawPoint::new(anchor_x, anchor_y),
        mode,
    )))
}

fn parse_binding_mode(raw: &str) -> Option<ArrowBindingMode> {
    match raw {
        "inside" => Some(ArrowBindingMode::Inside),
        "orbit" => Some(ArrowBindingMode::Orbit),
        "skip" => Some(ArrowBindingMode::Skip),
        _ => None,
    }
}
