#![allow(dead_code)]

use crate::draw::elements::types::highlight::highlight_data::HighlightData;
use crate::draw::elements::types::rectangle::rectangle_data::RectangleData;
use crate::draw::elements::types::serial_number::serial_number_data::SerialNumberData;
use crate::draw::elements::types::serial_number::serial_number_layout::resolve_serial_number_stroke_width;
use crate::draw::elements::types::text::text_data::TextData;
use crate::draw::models::element_state::ElementState;
use crate::draw::types::draw_point::DrawPoint;
use std::collections::{HashMap, HashSet};

use super::arrow_binding::ArrowBinding;
use super::arrow_core::{BindableShape, BindableState, EngineContext};
use super::core::arrow_hit_test::is_point_near_bindable_for_binding_hit as is_point_near_core_bindable_for_binding_hit;
use super::core::arrow_types::BindableState as CoreBindableState;

#[derive(Clone, Debug, Default, PartialEq)]
pub struct ArrowBindableCandidates {
    pub elements: Vec<ElementState>,
    pub bindables: Vec<BindableState>,
    pub element_by_id: HashMap<String, ElementState>,
    pub bindable_by_id: HashMap<String, BindableState>,
}

impl ArrowBindableCandidates {
    pub fn empty() -> Self {
        Self::default()
    }

    pub fn is_empty(&self) -> bool {
        self.bindables.is_empty()
    }

    pub fn element_for_id(&self, id: &str) -> Option<&ElementState> {
        self.element_by_id.get(id)
    }

    pub fn bindable_for_id(&self, id: &str) -> Option<&BindableState> {
        self.bindable_by_id.get(id)
    }
}

pub fn project_arrow_bindable_candidates<I>(elements: I) -> ArrowBindableCandidates
where
    I: IntoIterator<Item = ElementState>,
{
    let mut seen_ids = HashSet::<String>::new();
    let mut projected_elements = Vec::new();
    let mut projected_bindables = Vec::new();
    let mut element_by_id = HashMap::new();
    let mut bindable_by_id = HashMap::new();

    for element in elements {
        if !seen_ids.insert(element.id.clone()) {
            continue;
        }
        let Some(bindable) = to_core_bindable_state(&element) else {
            continue;
        };
        element_by_id.insert(element.id.clone(), element.clone());
        bindable_by_id.insert(bindable.id.clone(), bindable.clone());
        projected_elements.push(element);
        projected_bindables.push(bindable);
    }

    ArrowBindableCandidates {
        elements: projected_elements,
        bindables: projected_bindables,
        element_by_id,
        bindable_by_id,
    }
}

pub fn resolve_arrow_bindable_candidates<I>(
    elements: I,
    world_point: DrawPoint,
    distance: f64,
    preferred_binding: Option<&ArrowBinding>,
    opposite_binding: Option<&ArrowBinding>,
    excluded_element_id: Option<&str>,
) -> ArrowBindableCandidates
where
    I: IntoIterator<Item = ElementState>,
{
    let all = project_arrow_bindable_candidates(elements);
    if all.is_empty() {
        return ArrowBindableCandidates::empty();
    }

    let mut candidate_ids = HashSet::<String>::new();
    if let Some(binding) = preferred_binding {
        candidate_ids.insert(binding.element_id.clone());
    }
    if let Some(binding) = opposite_binding {
        candidate_ids.insert(binding.element_id.clone());
    }

    for bindable in &all.bindables {
        if excluded_element_id.is_some_and(|excluded| bindable.id == excluded) {
            continue;
        }
        if is_point_near_bindable_for_binding_hit(world_point, bindable, distance) {
            candidate_ids.insert(bindable.id.clone());
        }
    }

    if candidate_ids.is_empty() {
        return ArrowBindableCandidates::empty();
    }

    project_arrow_bindable_candidates(
        all.elements
            .into_iter()
            .filter(|element| candidate_ids.contains(element.id.as_str())),
    )
}

#[derive(Clone, Debug, PartialEq)]
pub struct ArrowAppliedResult {
    pub ordered_element_ids: Option<Vec<String>>,
}

#[derive(Clone, Debug, PartialEq)]
pub struct ArrowScene {
    pub candidates: ArrowBindableCandidates,
    pub context: EngineContext,
}

impl ArrowScene {
    pub fn from_elements<I>(elements: I, context: Option<EngineContext>) -> Self
    where
        I: IntoIterator<Item = ElementState>,
    {
        Self {
            candidates: project_arrow_bindable_candidates(elements),
            context: context.unwrap_or_else(|| {
                EngineContext::new(1.0, true, super::arrow_core::BIND_MODE_ORBIT, 1e6)
            }),
        }
    }

    pub fn bindables(&self) -> &[BindableState] {
        &self.candidates.bindables
    }
}

fn to_core_bindable_state(element: &ElementState) -> Option<BindableState> {
    let json = element.data.to_json();
    if element.data.type_id().as_str() == RectangleData::TYPE_ID_TOKEN {
        let data = RectangleData::from_json(&json).ok()?;
        return Some(BindableState {
            id: element.id.clone(),
            shape: BindableShape::Rectangle,
            x: element.rect.min_x,
            y: element.rect.min_y,
            width: element.rect.width(),
            height: element.rect.height(),
            angle: element.rotation,
            stroke_width: data.stroke_width,
            z_index: Some(element.z_index as f64),
            background_opaque: Some(true),
            binding_enabled: Some(true),
            interior_hit_enabled: Some(true),
            visibility_bounds: Some(element.rect),
        });
    }
    if element.data.type_id().as_str() == TextData::TYPE_ID_TOKEN {
        let data = TextData::from_json(&json).ok()?;
        return Some(BindableState {
            id: element.id.clone(),
            shape: BindableShape::Rectangle,
            x: element.rect.min_x,
            y: element.rect.min_y,
            width: element.rect.width(),
            height: element.rect.height(),
            angle: element.rotation,
            stroke_width: data.stroke_width,
            z_index: Some(element.z_index as f64),
            background_opaque: Some(true),
            binding_enabled: Some(true),
            interior_hit_enabled: Some(true),
            visibility_bounds: Some(element.rect),
        });
    }
    if element.data.type_id().as_str() == SerialNumberData::TYPE_ID_TOKEN {
        let data = SerialNumberData::from_json(&json).ok()?;
        return Some(BindableState {
            id: element.id.clone(),
            shape: BindableShape::Ellipse,
            x: element.rect.min_x,
            y: element.rect.min_y,
            width: element.rect.width(),
            height: element.rect.height(),
            angle: element.rotation,
            stroke_width: resolve_serial_number_stroke_width(&data, 0.0),
            z_index: Some(element.z_index as f64),
            background_opaque: Some(true),
            binding_enabled: Some(true),
            interior_hit_enabled: Some(true),
            visibility_bounds: Some(element.rect),
        });
    }
    if element.data.type_id().as_str() == HighlightData::TYPE_ID_TOKEN {
        let data = HighlightData::from_json(&json).ok()?;
        return Some(BindableState {
            id: element.id.clone(),
            shape: BindableShape::Rectangle,
            x: element.rect.min_x,
            y: element.rect.min_y,
            width: element.rect.width(),
            height: element.rect.height(),
            angle: element.rotation,
            stroke_width: data.stroke_width,
            z_index: Some(element.z_index as f64),
            background_opaque: Some(true),
            binding_enabled: Some(true),
            interior_hit_enabled: Some(true),
            visibility_bounds: Some(element.rect),
        });
    }
    None
}

fn is_point_near_bindable_for_binding_hit(
    point: DrawPoint,
    bindable: &BindableState,
    tolerance: f64,
) -> bool {
    let core_bindable = CoreBindableState {
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
    };
    is_point_near_core_bindable_for_binding_hit(point, &core_bindable, tolerance)
}
