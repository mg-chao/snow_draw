#![allow(dead_code)]

use crate::draw::elements::types::arrow::arrow_binding::{
    ArrowBinding as RuntimeArrowBinding, ArrowBindingMode as RuntimeArrowBindingMode,
    ArrowBindingUtils,
};
use crate::draw::elements::types::arrow::arrow_data::{
    ArrowBinding as DataArrowBinding, ArrowBindingMode as DataArrowBindingMode, ArrowData,
};
use crate::draw::elements::types::arrow::arrow_points::ArrowPointUtils;
pub use crate::draw::elements::types::arrow::arrow_points::{
    ArrowFixedSegmentLike as ConnectorFixedSegmentLike,
    ArrowPointDataLike as ConnectorPointDataLike, ArrowPointHandle as ConnectorPointHandle,
    ArrowPointKind as ConnectorPointKind, ArrowPointOverlay as ConnectorPointOverlay,
};
use crate::draw::elements::types::line::line_data::LineData;
use crate::draw::models::element_state::ElementState;
use crate::draw::types::draw_point::DrawPoint;
use crate::draw::types::element_style::ArrowType;

const TURNING_HIT_RADIUS_FACTOR: f64 = 1.11;
const FOCUS_POINT_SIZE: f64 = 10.0 / 1.5;

#[derive(Clone, Debug, PartialEq)]
struct ParsedConnectorData {
    points: Vec<DrawPoint>,
    arrow_type: ArrowType,
    start_binding: Option<RuntimeArrowBinding>,
    end_binding: Option<RuntimeArrowBinding>,
}

pub struct ConnectorPointUtils;

impl ConnectorPointUtils {
    pub fn list_visible_focus_points(
        element: &ElementState,
        elements: &[ElementState],
        zoom: f64,
        is_binding_enabled: bool,
    ) -> Vec<ConnectorPointHandle> {
        let Some(data) = resolve_connector_data(element) else {
            return Vec::new();
        };

        build_focus_points(element, &data, elements, zoom, is_binding_enabled)
    }

    pub fn build_overlay(
        element: &ElementState,
        loop_threshold: f64,
        handle_size: Option<f64>,
    ) -> ConnectorPointOverlay {
        Self::build_overlay_with_options(element, loop_threshold, handle_size, &[], 1.0, true)
    }

    #[allow(clippy::too_many_arguments)]
    pub fn build_overlay_with_options(
        element: &ElementState,
        loop_threshold: f64,
        handle_size: Option<f64>,
        elements: &[ElementState],
        zoom: f64,
        is_binding_enabled: bool,
    ) -> ConnectorPointOverlay {
        let mut overlay = ArrowPointUtils::build_overlay(element, loop_threshold, handle_size);
        let Some(data) = resolve_connector_data(element) else {
            return overlay;
        };

        let focus_points = build_focus_points(element, &data, elements, zoom, is_binding_enabled);
        if focus_points.is_empty() {
            return overlay;
        }

        let has_start_focus = focus_points
            .iter()
            .any(|handle| handle.kind == ConnectorPointKind::FocusStart);
        let has_end_focus = focus_points
            .iter()
            .any(|handle| handle.kind == ConnectorPointKind::FocusEnd);
        let endpoint_count = data.points.len();

        overlay.turning_points.retain(|handle| {
            if handle.kind != ConnectorPointKind::Turning {
                return true;
            }
            if has_start_focus && handle.index == 0 {
                return false;
            }
            if has_end_focus && handle.index + 1 == endpoint_count {
                return false;
            }
            true
        });
        overlay.focus_points = focus_points;
        overlay
    }

    pub fn hit_test(
        element: &ElementState,
        position: DrawPoint,
        hit_radius: f64,
        loop_threshold: f64,
        handle_size: Option<f64>,
    ) -> Option<ConnectorPointHandle> {
        Self::hit_test_with_options(
            element,
            position,
            hit_radius,
            loop_threshold,
            handle_size,
            &[],
            1.0,
            true,
        )
    }

    #[allow(clippy::too_many_arguments)]
    pub fn hit_test_with_options(
        element: &ElementState,
        position: DrawPoint,
        hit_radius: f64,
        loop_threshold: f64,
        handle_size: Option<f64>,
        elements: &[ElementState],
        zoom: f64,
        is_binding_enabled: bool,
    ) -> Option<ConnectorPointHandle> {
        let focus_points = build_focus_points(
            element,
            &resolve_connector_data(element)?,
            elements,
            zoom,
            is_binding_enabled,
        );
        if !focus_points.is_empty() {
            let hit_radius = max_radius(
                hit_radius * TURNING_HIT_RADIUS_FACTOR,
                resolve_visual_radius(handle_size, 0.5),
            );
            let hit_radius_sq = hit_radius * hit_radius;
            let local_position = to_local_position(element, position);
            let mut nearest: Option<ConnectorPointHandle> = None;
            let mut nearest_distance_sq = f64::INFINITY;
            for handle in focus_points {
                let distance_sq = local_position.distance_squared(handle.position);
                if distance_sq <= hit_radius_sq && distance_sq < nearest_distance_sq {
                    nearest_distance_sq = distance_sq;
                    nearest = Some(handle);
                }
            }
            if nearest.is_some() {
                return nearest;
            }
        }

        ArrowPointUtils::hit_test(element, position, hit_radius, loop_threshold, handle_size)
    }
}

fn build_focus_points(
    element: &ElementState,
    data: &ParsedConnectorData,
    elements: &[ElementState],
    zoom: f64,
    is_binding_enabled: bool,
) -> Vec<ConnectorPointHandle> {
    if !is_binding_enabled || data.arrow_type == ArrowType::Elbow {
        return Vec::new();
    }

    let world_points =
        crate::draw::elements::types::connector::connector_geometry::resolve_connector_world_points(
            element.rect,
            &data.points,
        );
    if world_points.len() != 2 {
        return Vec::new();
    }

    let threshold = focus_hit_threshold(zoom);
    let mut handles = Vec::new();

    if let Some(binding) = data.start_binding.as_ref() {
        if let Some(handle) = build_focus_handle(
            element,
            elements,
            binding,
            ConnectorPointKind::FocusStart,
            0,
            world_points[0],
            threshold,
        ) {
            handles.push(handle);
        }
    }

    if let Some(binding) = data.end_binding.as_ref() {
        if let Some(handle) = build_focus_handle(
            element,
            elements,
            binding,
            ConnectorPointKind::FocusEnd,
            world_points.len() - 1,
            world_points[world_points.len() - 1],
            threshold,
        ) {
            handles.push(handle);
        }
    }

    handles
}

fn build_focus_handle(
    element: &ElementState,
    elements: &[ElementState],
    binding: &RuntimeArrowBinding,
    kind: ConnectorPointKind,
    index: usize,
    endpoint: DrawPoint,
    threshold: f64,
) -> Option<ConnectorPointHandle> {
    let target = elements
        .iter()
        .find(|candidate| candidate.id == binding.element_id)?;
    if !ArrowBindingUtils::is_bindable_target(target) {
        return None;
    }

    let focus_point = ArrowBindingUtils::resolve_bound_point(binding, target, Some(endpoint))?;
    if focus_point.distance(endpoint) < threshold {
        return None;
    }

    Some(ConnectorPointHandle::new(
        element.id.clone(),
        kind,
        index,
        focus_point,
    ))
}

fn resolve_connector_data(element: &ElementState) -> Option<ParsedConnectorData> {
    let payload = element.data.to_json_value();
    match element.type_id().as_str() {
        ArrowData::TYPE_ID_TOKEN => {
            ArrowData::from_json_value(&payload)
                .ok()
                .map(|data| ParsedConnectorData {
                    points: data.points,
                    arrow_type: data.arrow_type,
                    start_binding: data.start_binding.as_ref().map(data_binding_to_runtime),
                    end_binding: data.end_binding.as_ref().map(data_binding_to_runtime),
                })
        }
        LineData::TYPE_ID_TOKEN => {
            LineData::from_json_value(&payload)
                .ok()
                .map(|data| ParsedConnectorData {
                    points: data.points,
                    arrow_type: data.arrow_type,
                    start_binding: data.start_binding,
                    end_binding: data.end_binding,
                })
        }
        _ => None,
    }
}

fn data_binding_to_runtime(binding: &DataArrowBinding) -> RuntimeArrowBinding {
    RuntimeArrowBinding::new(
        binding.element_id.clone(),
        binding.anchor,
        match binding.mode {
            DataArrowBindingMode::Inside => RuntimeArrowBindingMode::Inside,
            DataArrowBindingMode::Orbit => RuntimeArrowBindingMode::Orbit,
            DataArrowBindingMode::Skip => RuntimeArrowBindingMode::Skip,
        },
    )
}

fn focus_hit_threshold(zoom: f64) -> f64 {
    (FOCUS_POINT_SIZE * 1.5) / zoom.max(1e-6)
}

fn resolve_visual_radius(handle_size: Option<f64>, multiplier: f64) -> f64 {
    let Some(handle_size) = handle_size else {
        return 0.0;
    };
    if handle_size <= 0.0 {
        return 0.0;
    }
    handle_size * multiplier
}

fn max_radius(a: f64, b: f64) -> f64 {
    if a > b {
        a
    } else {
        b
    }
}

fn to_local_position(element: &ElementState, position: DrawPoint) -> DrawPoint {
    if element.rotation == 0.0 {
        return position;
    }
    let space = crate::draw::core::coordinates::element_space::ElementSpace::new(
        element.rotation,
        element.rect.center(),
    );
    space.from_world(position)
}

#[cfg(test)]
mod tests {
    use std::sync::Arc;

    use super::*;
    use crate::draw::elements::types::arrow::arrow_data::{
        ArrowBinding as DataArrowBinding, ArrowBindingMode as DataArrowBindingMode, ArrowData,
    };
    use crate::draw::elements::types::rectangle::rectangle_data::RectangleData;
    use crate::draw::types::draw_rect::DrawRect;

    #[test]
    fn build_overlay_exposes_focus_handles_for_bound_endpoints() {
        let bindable = bindable_element();
        let arrow = bound_arrow_element();
        let elements = vec![bindable.clone(), arrow.clone()];

        let overlay = ConnectorPointUtils::build_overlay_with_options(
            &arrow,
            16.0,
            Some(10.0),
            &elements,
            1.0,
            true,
        );

        assert_eq!(overlay.focus_points.len(), 1);
        assert_eq!(overlay.focus_points[0].kind, ConnectorPointKind::FocusStart);
        assert!(!overlay
            .turning_points
            .iter()
            .any(|handle| handle.index == 0));
    }

    #[test]
    fn hit_test_resolves_focus_handle_under_pointer() {
        let bindable = bindable_element();
        let arrow = bound_arrow_element();
        let elements = vec![bindable.clone(), arrow.clone()];
        let overlay = ConnectorPointUtils::build_overlay_with_options(
            &arrow,
            16.0,
            Some(10.0),
            &elements,
            1.0,
            true,
        );
        let focus_point = overlay.focus_points[0].position;

        let hit = ConnectorPointUtils::hit_test_with_options(
            &arrow,
            focus_point,
            12.0,
            16.0,
            Some(10.0),
            &elements,
            1.0,
            true,
        );

        assert!(hit.is_some());
        let hit = hit.unwrap();
        assert_eq!(hit.kind, ConnectorPointKind::FocusStart);
        assert_eq!(hit.index, 0);
    }

    #[test]
    fn build_overlay_hides_focus_handles_when_binding_disabled() {
        let bindable = bindable_element();
        let arrow = bound_arrow_element();
        let elements = vec![bindable.clone(), arrow.clone()];

        let overlay = ConnectorPointUtils::build_overlay_with_options(
            &arrow,
            16.0,
            Some(10.0),
            &elements,
            1.0,
            false,
        );

        assert!(overlay.focus_points.is_empty());
        assert!(overlay
            .turning_points
            .iter()
            .any(|handle| handle.index == 0));
    }

    #[test]
    fn hit_test_ignores_focus_handles_when_binding_disabled() {
        let bindable = bindable_element();
        let arrow = bound_arrow_element();
        let elements = vec![bindable.clone(), arrow.clone()];
        let overlay = ConnectorPointUtils::build_overlay_with_options(
            &arrow,
            16.0,
            Some(10.0),
            &elements,
            1.0,
            true,
        );
        let focus_point = overlay.focus_points[0].position;

        let hit = ConnectorPointUtils::hit_test_with_options(
            &arrow,
            focus_point,
            12.0,
            16.0,
            Some(10.0),
            &elements,
            1.0,
            false,
        );

        assert!(hit.is_none());
    }

    fn bindable_element() -> ElementState {
        ElementState::new(
            "bindable-focus",
            DrawRect::new(0.0, 0.0, 100.0, 100.0),
            0.0,
            1.0,
            0,
            Arc::new(RectangleData::default()),
        )
    }

    fn bound_arrow_element() -> ElementState {
        let mut data = ArrowData::default();
        data.points = vec![DrawPoint::new(0.0, 0.5), DrawPoint::new(1.0, 0.5)];
        data.start_binding = Some(DataArrowBinding::new(
            "bindable-focus",
            DrawPoint::new(1.0, 0.5),
            DataArrowBindingMode::Orbit,
        ));

        ElementState::new(
            "arrow-focus",
            DrawRect::new(120.0, 20.0, 320.0, 21.0),
            0.0,
            1.0,
            1,
            Arc::new(data),
        )
    }
}
