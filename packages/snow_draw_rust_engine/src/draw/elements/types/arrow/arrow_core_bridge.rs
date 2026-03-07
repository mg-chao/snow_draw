#![allow(dead_code)]

use std::collections::{HashMap, HashSet};
use std::sync::Arc;

use crate::draw::core::coordinates::element_space::ElementSpace;
use crate::draw::elements::types::connector::connector_geometry::{
    resolve_connector_geometry_update, resolve_connector_world_points,
};
use crate::draw::elements::types::highlight::highlight_data::HighlightData;
use crate::draw::elements::types::line::line_data::LineData;
use crate::draw::elements::types::rectangle::rectangle_data::RectangleData;
use crate::draw::elements::types::serial_number::serial_number_data::SerialNumberData;
use crate::draw::elements::types::serial_number::serial_number_layout::resolve_serial_number_stroke_width;
use crate::draw::elements::types::text::text_data::TextData;
use crate::draw::models::element_state::ElementState;
use crate::draw::types::draw_point::DrawPoint;
use serde_json::Value;

use super::arrow_binding::{ArrowBinding, ArrowBindingMode};
use super::arrow_core::{
    ArrowState, BindableState, EngineContext, BIND_MODE_INSIDE, BIND_MODE_ORBIT, BIND_MODE_SKIP,
};
use super::arrow_data::{
    ArrowBinding as SourceArrowBinding, ArrowBindingMode as SourceArrowBindingMode, ArrowData,
    ElbowFixedSegment,
};
use super::core::arrow_types::{ArrowPatch, ArrowStatePatchWithId, BindableRelationState};
use crate::draw::types::element_style::ArrowType;
use crate::draw::types::element_style::ArrowheadStyle;

pub type ArrowCoreState = ArrowState;
pub type ArrowBindableState = BindableState;
pub type ConnectorSourceData = ArrowData;

#[derive(Clone, Debug, PartialEq)]
pub struct ArrowCoreDocumentProjection {
    pub bindables: Vec<ArrowBindableState>,
    pub bindable_relations: Vec<BindableRelationState>,
    pub arrows: Vec<ArrowCoreState>,
    pub arrow_sources: HashMap<String, (ElementState, ConnectorSourceData)>,
    pub ordered_element_ids: Vec<String>,
    pub anchor_element_ids_by_bindable_id: HashMap<String, Vec<String>>,
}

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

pub fn is_arrow_bindable_element(element: &ElementState) -> bool {
    let type_id = element.data.type_id();
    let type_id = type_id.as_str();
    type_id == RectangleData::TYPE_ID_TOKEN
        || type_id == TextData::TYPE_ID_TOKEN
        || type_id == SerialNumberData::TYPE_ID_TOKEN
        || type_id == HighlightData::TYPE_ID_TOKEN
}

pub fn to_core_bindable_state(
    element: &ElementState,
    z_index: Option<usize>,
    binding_enabled: bool,
    interior_hit_enabled: bool,
    visibility_bounds: Option<crate::draw::types::draw_rect::DrawRect>,
) -> Option<ArrowBindableState> {
    let json = element.data.to_json();
    let type_id = element.data.type_id();
    let type_id = type_id.as_str();

    if type_id == RectangleData::TYPE_ID_TOKEN {
        let data = RectangleData::from_json(&json).ok()?;
        return Some(ArrowBindableState {
            id: element.id.clone(),
            shape: super::arrow_core::BindableShape::Rectangle,
            x: element.rect.min_x,
            y: element.rect.min_y,
            width: element.rect.width(),
            height: element.rect.height(),
            angle: element.rotation,
            stroke_width: data.stroke_width,
            z_index: Some(z_index.unwrap_or(element.z_index as usize) as f64),
            background_opaque: Some(data.fill_color.a() > 0.0),
            binding_enabled: Some(binding_enabled),
            interior_hit_enabled: Some(interior_hit_enabled),
            visibility_bounds,
        });
    }

    if type_id == TextData::TYPE_ID_TOKEN {
        let data = TextData::from_json(&json).ok()?;
        return Some(ArrowBindableState {
            id: element.id.clone(),
            shape: super::arrow_core::BindableShape::Rectangle,
            x: element.rect.min_x,
            y: element.rect.min_y,
            width: element.rect.width(),
            height: element.rect.height(),
            angle: element.rotation,
            stroke_width: data.stroke_width,
            z_index: Some(z_index.unwrap_or(element.z_index as usize) as f64),
            background_opaque: Some(data.fill_color.a() > 0.0),
            binding_enabled: Some(binding_enabled),
            interior_hit_enabled: Some(interior_hit_enabled),
            visibility_bounds,
        });
    }

    if type_id == SerialNumberData::TYPE_ID_TOKEN {
        let data = SerialNumberData::from_json(&json).ok()?;
        return Some(ArrowBindableState {
            id: element.id.clone(),
            shape: super::arrow_core::BindableShape::Ellipse,
            x: element.rect.min_x,
            y: element.rect.min_y,
            width: element.rect.width(),
            height: element.rect.height(),
            angle: element.rotation,
            stroke_width: resolve_serial_number_stroke_width(&data, 0.0),
            z_index: Some(z_index.unwrap_or(element.z_index as usize) as f64),
            background_opaque: Some(data.fill_color.a() > 0.0),
            binding_enabled: Some(binding_enabled),
            interior_hit_enabled: Some(interior_hit_enabled),
            visibility_bounds,
        });
    }

    if type_id == HighlightData::TYPE_ID_TOKEN {
        let data = HighlightData::from_json(&json).ok()?;
        return Some(ArrowBindableState {
            id: element.id.clone(),
            shape: if data.shape == crate::draw::types::element_style::HighlightShape::Ellipse {
                super::arrow_core::BindableShape::Ellipse
            } else {
                super::arrow_core::BindableShape::Rectangle
            },
            x: element.rect.min_x,
            y: element.rect.min_y,
            width: element.rect.width(),
            height: element.rect.height(),
            angle: element.rotation,
            stroke_width: data.stroke_width,
            z_index: Some(z_index.unwrap_or(element.z_index as usize) as f64),
            background_opaque: Some(data.color.a() > 0.0),
            binding_enabled: Some(binding_enabled),
            interior_hit_enabled: Some(interior_hit_enabled),
            visibility_bounds,
        });
    }

    None
}

pub fn collect_core_bindables(elements: &[ElementState]) -> Vec<ArrowBindableState> {
    let mut bindables = Vec::new();
    for (index, element) in elements.iter().enumerate() {
        if let Some(bindable) = to_core_bindable_state(element, Some(index), true, true, None) {
            bindables.push(bindable);
        }
    }
    bindables
}

pub fn collect_core_bindable_relations(elements: &[ElementState]) -> Vec<BindableRelationState> {
    let mut ordered_bindable_ids = Vec::<String>::new();
    let mut bindable_id_set = HashSet::<String>::new();
    let mut bound_arrow_ids_by_bindable = HashMap::<String, Vec<String>>::new();
    let mut seen_arrow_ids_by_bindable = HashMap::<String, HashSet<String>>::new();

    for element in elements {
        if is_arrow_bindable_element(element) && bindable_id_set.insert(element.id.clone()) {
            ordered_bindable_ids.push(element.id.clone());
            bound_arrow_ids_by_bindable.insert(element.id.clone(), Vec::new());
            seen_arrow_ids_by_bindable.insert(element.id.clone(), HashSet::new());
        }
    }

    for element in elements {
        let type_id = element.data.type_id();
        let type_id = type_id.as_str();

        let mut add_arrow_binding = |bindable_id: Option<&str>| {
            let Some(bindable_id) = bindable_id else {
                return;
            };
            if !bindable_id_set.contains(bindable_id) {
                return;
            }
            let Some(bound_arrow_ids) = bound_arrow_ids_by_bindable.get_mut(bindable_id) else {
                return;
            };
            let Some(seen_arrow_ids) = seen_arrow_ids_by_bindable.get_mut(bindable_id) else {
                return;
            };
            if !seen_arrow_ids.insert(element.id.clone()) {
                return;
            }
            bound_arrow_ids.push(element.id.clone());
        };

        if type_id == ArrowData::TYPE_ID_TOKEN {
            if let Ok(data) = ArrowData::from_json(&element.data.to_json()) {
                add_arrow_binding(
                    data.start_binding
                        .as_ref()
                        .map(|value| value.element_id.as_str()),
                );
                add_arrow_binding(
                    data.end_binding
                        .as_ref()
                        .map(|value| value.element_id.as_str()),
                );
            }
            continue;
        }

        if type_id == LineData::TYPE_ID_TOKEN {
            if let Ok(data) = LineData::from_json(&element.data.to_json()) {
                add_arrow_binding(
                    data.start_binding
                        .as_ref()
                        .map(|value| value.element_id.as_str()),
                );
                add_arrow_binding(
                    data.end_binding
                        .as_ref()
                        .map(|value| value.element_id.as_str()),
                );
            }
        }
    }

    ordered_bindable_ids
        .into_iter()
        .map(|bindable_id| BindableRelationState {
            id: bindable_id.clone(),
            bound_arrow_ids: bound_arrow_ids_by_bindable
                .remove(&bindable_id)
                .unwrap_or_default(),
        })
        .collect()
}

pub fn collect_core_anchor_element_ids_by_bindable_id(
    elements: &[ElementState],
) -> HashMap<String, Vec<String>> {
    let element_by_id = elements
        .iter()
        .cloned()
        .map(|element| (element.id.clone(), element))
        .collect::<HashMap<_, _>>();
    if element_by_id.is_empty() {
        return HashMap::new();
    }

    let mut anchor_ids_by_bindable_id = HashMap::<String, Vec<String>>::new();
    for element in element_by_id.values() {
        if !is_arrow_bindable_element(element) {
            continue;
        }

        let mut anchor_ids = vec![element.id.clone()];
        if element.data.type_id().as_str() == SerialNumberData::TYPE_ID_TOKEN {
            if let Ok(data) = SerialNumberData::from_json(&element.data.to_json()) {
                if let Some(text_element_id) = data.text_element_id {
                    if !text_element_id.is_empty()
                        && element_by_id.contains_key(text_element_id.as_str())
                        && !anchor_ids.iter().any(|value| value == &text_element_id)
                    {
                        anchor_ids.push(text_element_id);
                    }
                }
            }
        }
        anchor_ids_by_bindable_id.insert(element.id.clone(), anchor_ids);
    }

    anchor_ids_by_bindable_id
}

pub fn collect_core_arrow_states_with_sources(
    elements: &[ElementState],
    only_bound_arrows: bool,
) -> (
    Vec<ArrowCoreState>,
    HashMap<String, (ElementState, ConnectorSourceData)>,
) {
    let mut arrows = Vec::<ArrowCoreState>::new();
    let mut sources = HashMap::<String, (ElementState, ConnectorSourceData)>::new();

    for element in elements {
        if element.data.type_id().as_str() != ArrowData::TYPE_ID_TOKEN {
            continue;
        }
        let Ok(data) = ArrowData::from_json(&element.data.to_json()) else {
            continue;
        };
        if only_bound_arrows && data.start_binding.is_none() && data.end_binding.is_none() {
            continue;
        }
        arrows.push(to_core_arrow_state(
            element,
            &data,
            None,
            None,
            None,
            None,
            crate::draw::elements::types::arrow::arrow_core::DEFAULT_MAX_COORDINATE,
        ));
        sources.insert(element.id.clone(), (element.clone(), data));
    }

    (arrows, sources)
}

pub fn project_core_document(
    elements: &[ElementState],
    only_bound_arrows: bool,
    ordered_element_ids: Option<&[String]>,
) -> ArrowCoreDocumentProjection {
    let materialized = elements.to_vec();
    let element_by_id = materialized
        .iter()
        .cloned()
        .map(|element| (element.id.clone(), element))
        .collect::<HashMap<_, _>>();

    let mut ordered_materialized = Vec::<ElementState>::new();
    if let Some(ordered_element_ids) = ordered_element_ids.filter(|value| !value.is_empty()) {
        let mut ordered_id_set = HashSet::<String>::new();
        for id in ordered_element_ids {
            let Some(element) = element_by_id.get(id) else {
                continue;
            };
            if !ordered_id_set.insert(id.clone()) {
                continue;
            }
            ordered_materialized.push(element.clone());
        }
        for element in &materialized {
            if !ordered_id_set.insert(element.id.clone()) {
                continue;
            }
            ordered_materialized.push(element.clone());
        }
    } else {
        ordered_materialized = materialized;
    }

    let (arrows, arrow_sources) =
        collect_core_arrow_states_with_sources(&ordered_materialized, only_bound_arrows);

    ArrowCoreDocumentProjection {
        bindables: collect_core_bindables(&ordered_materialized),
        bindable_relations: collect_core_bindable_relations(&ordered_materialized),
        arrows,
        arrow_sources,
        ordered_element_ids: ordered_materialized
            .iter()
            .map(|element| element.id.clone())
            .collect(),
        anchor_element_ids_by_bindable_id: collect_core_anchor_element_ids_by_bindable_id(
            &ordered_materialized,
        ),
    }
}

pub fn local_to_world_points(element: &ElementState, local: &[DrawPoint]) -> Vec<DrawPoint> {
    if element.rotation == 0.0 {
        return local.to_vec();
    }
    let space = ElementSpace::new(element.rotation, element.rect.center());
    local.iter().map(|point| space.to_world(*point)).collect()
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
    let local_points = local_points_override
        .map(|points| points.to_vec())
        .unwrap_or_else(|| resolve_connector_world_points(element.rect, &data.points));
    let world_points = local_to_world_points(element, &local_points);
    let normalized =
        super::arrow_core::normalize_arrow_from_global_points(&world_points, max_coordinate);
    ArrowCoreState {
        id: element.id.clone(),
        x: normalized.x,
        y: normalized.y,
        width: normalized.width,
        height: normalized.height,
        points: normalized.points.clone(),
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
        fixed_segments: to_core_fixed_segments(
            element,
            fixed_segments_override.or(data.fixed_segments.as_deref()),
            &normalized,
        ),
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

pub fn core_arrow_world_fixed_segments(arrow: &ArrowCoreState) -> Option<Vec<ElbowFixedSegment>> {
    let segments = arrow.fixed_segments.as_ref()?;
    if segments.is_empty() {
        return None;
    }
    Some(
        segments
            .iter()
            .map(|segment| ElbowFixedSegment {
                index: segment.index,
                start: DrawPoint::new(arrow.x + segment.start.x, arrow.y + segment.start.y),
                end: DrawPoint::new(arrow.x + segment.end.x, arrow.y + segment.end.y),
            })
            .collect(),
    )
}

pub fn world_to_local_points(element: &ElementState, world_points: &[DrawPoint]) -> Vec<DrawPoint> {
    if element.rotation == 0.0 {
        return world_points.to_vec();
    }
    let space = ElementSpace::new(element.rotation, element.rect.center());
    world_points
        .iter()
        .map(|point| space.from_world(*point))
        .collect()
}

pub fn to_local_fixed_segments_from_core_arrow(
    arrow: &ArrowCoreState,
    element: &ElementState,
) -> Option<Vec<ElbowFixedSegment>> {
    let segments = arrow.fixed_segments.as_ref()?;
    if segments.is_empty() {
        return None;
    }
    let space = ElementSpace::new(element.rotation, element.rect.center());
    Some(
        segments
            .iter()
            .map(|segment| {
                let world_start =
                    DrawPoint::new(arrow.x + segment.start.x, arrow.y + segment.start.y);
                let world_end = DrawPoint::new(arrow.x + segment.end.x, arrow.y + segment.end.y);
                ElbowFixedSegment {
                    index: segment.index,
                    start: space.from_world(world_start),
                    end: space.from_world(world_end),
                }
            })
            .collect(),
    )
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
    let fixed_segments_in_old_frame = to_local_fixed_segments_from_core_arrow(next_arrow, element);
    let transformed_fixed_segments = transform_arrow_local_fixed_segments(
        fixed_segments_in_old_frame.as_deref(),
        element.rect,
        geometry.rect,
        element.rotation,
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
        fixed_segments: match transformed_fixed_segments {
            Some(segments) => super::arrow_data::NullableField::Value(segments),
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

pub fn apply_core_arrow_patch_to_element(
    element: &ElementState,
    data: &ArrowData,
    patch: &ArrowPatch,
) -> ElementState {
    if patch.is_empty() {
        return element.clone();
    }
    if !patch_touches_geometry(patch) {
        let next_data = apply_non_geometry_patch(element, data, patch);
        if next_data == *data {
            return element.clone();
        }
        return element.copy_with(None, None, None, None, None, Some(Arc::new(next_data)));
    }

    let current_arrow = to_core_arrow_state(
        element,
        data,
        None,
        None,
        None,
        None,
        crate::draw::elements::types::arrow::arrow_core::DEFAULT_MAX_COORDINATE,
    );
    let next_arrow = apply_arrow_patch(&current_arrow, patch);
    apply_core_arrow_state_to_element(element, data, &next_arrow)
}

pub fn apply_core_arrow_patches_to_sources(
    patches: &[ArrowStatePatchWithId],
    sources: &HashMap<String, (ElementState, ConnectorSourceData)>,
) -> HashMap<String, ElementState> {
    let mut patched_by_id = HashMap::<String, ElementState>::new();
    for arrow_patch in patches {
        let Some((element, data)) = sources.get(&arrow_patch.id) else {
            continue;
        };
        let patched = apply_core_arrow_patch_to_element(element, data, &arrow_patch.patch);
        if patched != *element {
            patched_by_id.insert(patched.id.clone(), patched);
        }
    }
    patched_by_id
}

pub fn transform_arrow_local_fixed_segments(
    segments: Option<&[ElbowFixedSegment]>,
    old_rect: crate::draw::types::draw_rect::DrawRect,
    new_rect: crate::draw::types::draw_rect::DrawRect,
    rotation: f64,
) -> Option<Vec<ElbowFixedSegment>> {
    let segments = segments?;
    if segments.is_empty() {
        return None;
    }
    let old_space = ElementSpace::new(rotation, old_rect.center());
    let new_space = ElementSpace::new(rotation, new_rect.center());
    Some(
        segments
            .iter()
            .map(|segment| ElbowFixedSegment {
                index: segment.index,
                start: new_space.from_world(old_space.to_world(segment.start)),
                end: new_space.from_world(old_space.to_world(segment.end)),
            })
            .collect(),
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

fn to_core_fixed_segments(
    element: &ElementState,
    segments: Option<&[ElbowFixedSegment]>,
    normalized: &super::arrow_core::NormalizedArrowGeometry,
) -> Option<Vec<ElbowFixedSegment>> {
    let segments = segments?;
    if segments.is_empty() {
        return None;
    }
    let space = ElementSpace::new(element.rotation, element.rect.center());
    Some(
        segments
            .iter()
            .map(|segment| {
                let world_start = space.to_world(segment.start);
                let world_end = space.to_world(segment.end);
                ElbowFixedSegment {
                    index: segment.index,
                    start: DrawPoint::new(
                        world_start.x - normalized.x,
                        world_start.y - normalized.y,
                    ),
                    end: DrawPoint::new(world_end.x - normalized.x, world_end.y - normalized.y),
                }
            })
            .collect(),
    )
}

fn patch_touches_geometry(patch: &ArrowPatch) -> bool {
    patch.contains_key("x")
        || patch.contains_key("y")
        || patch.contains_key("width")
        || patch.contains_key("height")
        || patch.contains_key("points")
}

fn apply_non_geometry_patch(
    element: &ElementState,
    data: &ArrowData,
    patch: &ArrowPatch,
) -> ArrowData {
    let start_binding = if patch.contains_key("startBinding") {
        decode_core_binding_patch_value(patch.get("startBinding"))
    } else {
        None
    };
    let end_binding = if patch.contains_key("endBinding") {
        decode_core_binding_patch_value(patch.get("endBinding"))
    } else {
        None
    };
    let fixed_segments = if patch.contains_key("fixedSegments") {
        decode_core_fixed_segments_patch_value(element, data, patch)
    } else {
        None
    };
    let start_is_special = if patch.contains_key("startIsSpecial") {
        decode_nullable_bool_patch_value(patch.get("startIsSpecial"))
    } else {
        None
    };
    let end_is_special = if patch.contains_key("endIsSpecial") {
        decode_nullable_bool_patch_value(patch.get("endIsSpecial"))
    } else {
        None
    };

    data.copy_with(super::arrow_data::ArrowDataPatch {
        start_binding: match patch.contains_key("startBinding") {
            true => match start_binding {
                Some(binding) => {
                    super::arrow_data::NullableField::Value(to_source_binding(&binding))
                }
                None => super::arrow_data::NullableField::Null,
            },
            false => super::arrow_data::NullableField::Unset,
        },
        end_binding: match patch.contains_key("endBinding") {
            true => match end_binding {
                Some(binding) => {
                    super::arrow_data::NullableField::Value(to_source_binding(&binding))
                }
                None => super::arrow_data::NullableField::Null,
            },
            false => super::arrow_data::NullableField::Unset,
        },
        fixed_segments: match patch.contains_key("fixedSegments") {
            true => match fixed_segments {
                Some(segments) => super::arrow_data::NullableField::Value(segments),
                None => super::arrow_data::NullableField::Null,
            },
            false => super::arrow_data::NullableField::Unset,
        },
        start_is_special: match patch.contains_key("startIsSpecial") {
            true => match start_is_special {
                Some(value) => super::arrow_data::NullableField::Value(value),
                None => super::arrow_data::NullableField::Null,
            },
            false => super::arrow_data::NullableField::Unset,
        },
        end_is_special: match patch.contains_key("endIsSpecial") {
            true => match end_is_special {
                Some(value) => super::arrow_data::NullableField::Value(value),
                None => super::arrow_data::NullableField::Null,
            },
            false => super::arrow_data::NullableField::Unset,
        },
        ..Default::default()
    })
}

fn decode_core_fixed_segments_patch_value(
    element: &ElementState,
    data: &ArrowData,
    patch: &ArrowPatch,
) -> Option<Vec<ElbowFixedSegment>> {
    if let Some(Value::Array(raw_segments)) = patch.get("fixedSegments") {
        if let Some(parsed_segments) = decode_core_fixed_segments_patch_segments(raw_segments) {
            let mut fixed_segments_patch = ArrowPatch::new();
            fixed_segments_patch.insert(
                "fixedSegments".to_string(),
                Value::Array(
                    parsed_segments
                        .iter()
                        .map(|segment| fixed_segment_to_value(segment))
                        .collect(),
                ),
            );
            let patched_arrow = apply_arrow_patch(
                &to_core_arrow_state(
                    element,
                    data,
                    None,
                    None,
                    None,
                    None,
                    crate::draw::elements::types::arrow::arrow_core::DEFAULT_MAX_COORDINATE,
                ),
                &fixed_segments_patch,
            );
            return to_local_fixed_segments_from_core_arrow(&patched_arrow, element);
        }
    }

    let patched_arrow = apply_arrow_patch(
        &to_core_arrow_state(
            element,
            data,
            None,
            None,
            None,
            None,
            crate::draw::elements::types::arrow::arrow_core::DEFAULT_MAX_COORDINATE,
        ),
        patch,
    );
    to_local_fixed_segments_from_core_arrow(&patched_arrow, element)
}

fn decode_core_fixed_segments_patch_segments(
    raw_segments: &[Value],
) -> Option<Vec<ElbowFixedSegment>> {
    if raw_segments.is_empty() {
        return Some(Vec::new());
    }

    let mut decoded = Vec::<ElbowFixedSegment>::new();
    for raw_segment in raw_segments {
        let segment = raw_segment.as_object()?;
        let index = segment.get("index")?.as_u64()? as usize;
        let start = decode_core_point_array(segment.get("start")?)?;
        let end = decode_core_point_array(segment.get("end")?)?;
        decoded.push(ElbowFixedSegment {
            index,
            start: DrawPoint::new(start[0], start[1]),
            end: DrawPoint::new(end[0], end[1]),
        });
    }
    Some(decoded)
}

fn decode_core_point_array(raw: &Value) -> Option<[f64; 2]> {
    let raw = raw.as_array()?;
    if raw.len() != 2 {
        return None;
    }
    let x = raw.first()?.as_f64()?;
    let y = raw.get(1)?.as_f64()?;
    Some([x, y])
}

fn decode_core_binding_patch_value(raw: Option<&Value>) -> Option<ArrowBinding> {
    let raw = raw?;
    if raw.is_null() {
        return None;
    }
    let json = raw.as_object()?;
    let element_id = json.get("elementId")?.as_str()?.to_string();
    let fixed_point = decode_core_point_array(json.get("fixedPoint")?)?;
    let mode = json
        .get("mode")
        .and_then(Value::as_str)
        .unwrap_or(BIND_MODE_ORBIT);
    Some(ArrowBinding::new(
        element_id,
        DrawPoint::new(fixed_point[0], fixed_point[1]),
        from_core_binding_mode(mode),
    ))
}

fn decode_nullable_bool_patch_value(raw: Option<&Value>) -> Option<bool> {
    raw.and_then(Value::as_bool)
}

fn fixed_segment_to_value(segment: &ElbowFixedSegment) -> Value {
    let mut json = serde_json::Map::new();
    json.insert("index".to_string(), Value::from(segment.index as u64));
    json.insert(
        "start".to_string(),
        Value::Array(vec![
            Value::from(segment.start.x),
            Value::from(segment.start.y),
        ]),
    );
    json.insert(
        "end".to_string(),
        Value::Array(vec![Value::from(segment.end.x), Value::from(segment.end.y)]),
    );
    Value::Object(json)
}

fn apply_arrow_patch(arrow: &ArrowCoreState, patch: &ArrowPatch) -> ArrowCoreState {
    let mut next = arrow.clone();
    if let Some(value) = patch.get("x").and_then(Value::as_f64) {
        next.x = value;
    }
    if let Some(value) = patch.get("y").and_then(Value::as_f64) {
        next.y = value;
    }
    if let Some(value) = patch.get("width").and_then(Value::as_f64) {
        next.width = value;
    }
    if let Some(value) = patch.get("height").and_then(Value::as_f64) {
        next.height = value;
    }
    if let Some(Value::Array(points)) = patch.get("points") {
        next.points = points
            .iter()
            .filter_map(decode_core_point_array)
            .map(|point| DrawPoint::new(point[0], point[1]))
            .collect();
    }
    if patch.contains_key("startBinding") {
        next.start_binding = decode_core_binding_patch_value(patch.get("startBinding"));
    }
    if patch.contains_key("endBinding") {
        next.end_binding = decode_core_binding_patch_value(patch.get("endBinding"));
    }
    if patch.contains_key("fixedSegments") {
        next.fixed_segments = patch
            .get("fixedSegments")
            .and_then(Value::as_array)
            .and_then(|segments| decode_core_fixed_segments_patch_segments(segments));
    }
    if patch.contains_key("startIsSpecial") {
        next.start_is_special = patch.get("startIsSpecial").and_then(Value::as_bool);
    }
    if patch.contains_key("endIsSpecial") {
        next.end_is_special = patch.get("endIsSpecial").and_then(Value::as_bool);
    }
    next
}

#[cfg(test)]
mod tests {
    use std::sync::Arc;

    use super::{
        apply_core_arrow_state_to_element, to_local_fixed_segments_from_core_arrow,
        transform_arrow_local_fixed_segments, ArrowCoreState,
    };
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
        let fixed_segments_in_old_frame =
            to_local_fixed_segments_from_core_arrow(&next_arrow, &element);
        let expected_fixed_segments = transform_arrow_local_fixed_segments(
            fixed_segments_in_old_frame.as_deref(),
            element.rect,
            patched.rect,
            element.rotation,
        );

        assert_eq!(
            patched_data.start_binding,
            next_arrow.start_binding.clone().map(to_data_binding)
        );
        assert_eq!(
            patched_data.end_binding,
            next_arrow.end_binding.clone().map(to_data_binding)
        );
        assert_eq!(patched_data.fixed_segments, expected_fixed_segments);
        assert_eq!(patched_data.start_is_special, next_arrow.start_is_special);
        assert_eq!(patched_data.end_is_special, next_arrow.end_is_special);
    }
}
