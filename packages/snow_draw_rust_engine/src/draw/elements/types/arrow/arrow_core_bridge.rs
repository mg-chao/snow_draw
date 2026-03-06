#![allow(dead_code)]

use std::sync::Arc;

use crate::draw::elements::types::connector::connector_geometry::{
    resolve_connector_geometry_update, resolve_connector_world_points,
};
use crate::draw::models::element_state::ElementState;
use crate::draw::types::draw_point::DrawPoint;

use super::arrow_binding::{ArrowBinding, ArrowBindingMode};
use super::arrow_core::{
    ArrowState, BindableState, EngineContext, BIND_MODE_INSIDE, BIND_MODE_ORBIT, BIND_MODE_SKIP,
};
use super::arrow_data::{
    ArrowBinding as SourceArrowBinding, ArrowBindingMode as SourceArrowBindingMode, ArrowData,
    ElbowFixedSegment,
};
use crate::draw::types::element_style::ArrowType;
use crate::draw::types::element_style::ArrowheadStyle;

pub type ArrowCoreState = ArrowState;
pub type ArrowBindableState = BindableState;
pub type ConnectorSourceData = ArrowData;

/// Converts the local binding mode to the string form used by arrow-core wrappers.
pub const fn to_core_binding_mode(mode: ArrowBindingMode) -> &'static str {
    match mode {
        ArrowBindingMode::Inside => BIND_MODE_INSIDE,
        ArrowBindingMode::Orbit => BIND_MODE_ORBIT,
        ArrowBindingMode::Skip => BIND_MODE_SKIP,
    }
}

/// Converts an arrow-core binding mode string back to the local enum.
pub fn from_core_binding_mode(mode: &str) -> ArrowBindingMode {
    match mode {
        BIND_MODE_INSIDE => ArrowBindingMode::Inside,
        BIND_MODE_SKIP => ArrowBindingMode::Skip,
        _ => ArrowBindingMode::Orbit,
    }
}

pub fn build_core_engine_context(
    zoom: f64,
    is_binding_enabled: bool,
    bind_mode: &'static str,
    max_coordinate: f64,
) -> EngineContext {
    EngineContext::new(zoom, is_binding_enabled, bind_mode, max_coordinate)
}

pub fn to_core_arrow_state(
    element: &ElementState,
    data: &ArrowData,
    local_points_override: Option<&[DrawPoint]>,
    fixed_segments_override: Option<&[ElbowFixedSegment]>,
    start_binding_override: Option<Option<&ArrowBinding>>,
    end_binding_override: Option<Option<&ArrowBinding>>,
    max_coordinate: f64,
) -> ArrowCoreState {
    let world_points = local_points_override
        .map(|points| {
            points
                .iter()
                .map(|point| {
                    DrawPoint::new(point.x + element.rect.min_x, point.y + element.rect.min_y)
                })
                .collect::<Vec<_>>()
        })
        .unwrap_or_else(|| resolve_connector_world_points(element.rect, &data.points));
    let normalized =
        super::arrow_core::normalize_arrow_from_global_points(&world_points, max_coordinate);
    ArrowCoreState {
        id: element.id.clone(),
        x: normalized.x,
        y: normalized.y,
        width: normalized.width,
        height: normalized.height,
        points: normalized.points,
        start_binding: match start_binding_override {
            Some(binding) => binding.cloned(),
            None => data.start_binding.as_ref().map(to_engine_binding),
        },
        end_binding: match end_binding_override {
            Some(binding) => binding.cloned(),
            None => data.end_binding.as_ref().map(to_engine_binding),
        },
        start_arrowhead: Some(arrowhead_name(data.start_arrowhead).to_string()),
        end_arrowhead: Some(arrowhead_name(data.end_arrowhead).to_string()),
        elbowed: data.arrow_type == ArrowType::Elbow,
        fixed_segments: fixed_segments_override
            .map(|segments| segments.to_vec())
            .or_else(|| data.fixed_segments.clone()),
        start_is_special: data.start_is_special,
        end_is_special: data.end_is_special,
    }
}

pub fn core_arrow_world_points(arrow: &ArrowCoreState) -> Vec<DrawPoint> {
    arrow
        .points
        .iter()
        .map(|point| DrawPoint::new(arrow.x + point.x, arrow.y + point.y))
        .collect()
}

pub fn world_to_local_points(element: &ElementState, world_points: &[DrawPoint]) -> Vec<DrawPoint> {
    world_points
        .iter()
        .map(|point| DrawPoint::new(point.x - element.rect.min_x, point.y - element.rect.min_y))
        .collect()
}

pub fn to_local_fixed_segments_from_core_arrow(
    arrow: &ArrowCoreState,
    _element: &ElementState,
) -> Option<Vec<ElbowFixedSegment>> {
    arrow.fixed_segments.clone()
}

pub fn apply_core_arrow_state_to_element(
    element: &ElementState,
    data: &ArrowData,
    next_arrow: &ArrowCoreState,
) -> ElementState {
    let next_world_points = core_arrow_world_points(next_arrow);
    let local_points = world_to_local_points(element, &next_world_points);
    let geometry = resolve_connector_geometry_update(
        &local_points,
        element.rect,
        element.rotation,
        if next_arrow.elbowed {
            ArrowType::Elbow
        } else {
            data.arrow_type
        },
    );
    let next_data = data.copy_with(super::arrow_data::ArrowDataPatch {
        points: Some(geometry.normalized_points),
        arrow_type: Some(if next_arrow.elbowed {
            ArrowType::Elbow
        } else {
            data.arrow_type
        }),
        start_binding: match &next_arrow.start_binding {
            Some(binding) => super::arrow_data::NullableField::Value(to_source_binding(binding)),
            None => super::arrow_data::NullableField::Null,
        },
        end_binding: match &next_arrow.end_binding {
            Some(binding) => super::arrow_data::NullableField::Value(to_source_binding(binding)),
            None => super::arrow_data::NullableField::Null,
        },
        fixed_segments: match &next_arrow.fixed_segments {
            Some(segments) => super::arrow_data::NullableField::Value(segments.clone()),
            None => super::arrow_data::NullableField::Null,
        },
        start_is_special: match next_arrow.start_is_special {
            Some(value) => super::arrow_data::NullableField::Value(value),
            None => super::arrow_data::NullableField::Null,
        },
        end_is_special: match next_arrow.end_is_special {
            Some(value) => super::arrow_data::NullableField::Value(value),
            None => super::arrow_data::NullableField::Null,
        },
        ..Default::default()
    });
    element.copy_with(
        None,
        Some(geometry.rect),
        None,
        None,
        None,
        Some(Arc::new(next_data)),
    )
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

fn to_source_binding(binding: &ArrowBinding) -> SourceArrowBinding {
    SourceArrowBinding::new(
        binding.element_id.clone(),
        binding.anchor,
        match binding.mode {
            ArrowBindingMode::Inside => SourceArrowBindingMode::Inside,
            ArrowBindingMode::Orbit => SourceArrowBindingMode::Orbit,
            ArrowBindingMode::Skip => SourceArrowBindingMode::Skip,
        },
    )
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

#[cfg(test)]
mod tests {
    use std::sync::Arc;

    use super::{apply_core_arrow_state_to_element, ArrowCoreState};
    use crate::draw::elements::types::arrow::arrow_binding::{ArrowBinding, ArrowBindingMode};
    use crate::draw::elements::types::arrow::arrow_data::{
        ArrowBinding as DataArrowBinding, ArrowBindingMode as DataArrowBindingMode, ArrowData,
        ElbowFixedSegment,
    };
    use crate::draw::models::element_state::ElementState;
    use crate::draw::types::draw_point::DrawPoint;
    use crate::draw::types::draw_rect::DrawRect;

    fn binding(id: &str) -> ArrowBinding {
        ArrowBinding::new(
            id.to_owned(),
            DrawPoint::new(0.4, 0.6),
            ArrowBindingMode::Orbit,
        )
    }

    fn to_data_binding(binding: ArrowBinding) -> DataArrowBinding {
        DataArrowBinding::new(
            binding.element_id,
            binding.anchor,
            match binding.mode {
                ArrowBindingMode::Inside => DataArrowBindingMode::Inside,
                ArrowBindingMode::Orbit => DataArrowBindingMode::Orbit,
                ArrowBindingMode::Skip => DataArrowBindingMode::Skip,
            },
        )
    }

    #[test]
    fn apply_core_arrow_state_to_element_preserves_binding_and_elbow_metadata() {
        let element = ElementState::new(
            "arrow",
            DrawRect::new(0.0, 0.0, 10.0, 10.0),
            0.0,
            1.0,
            1,
            Arc::new(ArrowData::default()),
        );
        let data = ArrowData::default();
        let next_arrow = ArrowCoreState {
            id: "arrow".to_owned(),
            x: 4.0,
            y: 5.0,
            width: 20.0,
            height: 10.0,
            points: vec![DrawPoint::ZERO, DrawPoint::new(20.0, 10.0)],
            start_binding: Some(binding("box-a")),
            end_binding: Some(binding("box-b")),
            start_arrowhead: Some("none".to_owned()),
            end_arrowhead: Some("standard".to_owned()),
            elbowed: true,
            fixed_segments: Some(vec![ElbowFixedSegment {
                index: 1,
                start: DrawPoint::new(3.0, 4.0),
                end: DrawPoint::new(5.0, 6.0),
            }]),
            start_is_special: Some(true),
            end_is_special: Some(false),
        };

        let patched = apply_core_arrow_state_to_element(&element, &data, &next_arrow);
        let patched_data = ArrowData::from_json(&patched.data.to_json()).expect("arrow data");

        assert_eq!(
            patched_data.start_binding,
            next_arrow.start_binding.clone().map(to_data_binding)
        );
        assert_eq!(
            patched_data.end_binding,
            next_arrow.end_binding.clone().map(to_data_binding)
        );
        assert_eq!(patched_data.fixed_segments, next_arrow.fixed_segments);
        assert_eq!(patched_data.start_is_special, next_arrow.start_is_special);
        assert_eq!(patched_data.end_is_special, next_arrow.end_is_special);
    }
}
