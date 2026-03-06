#![allow(dead_code)]

use std::collections::{HashMap, HashSet};
use std::sync::Arc;

use crate::draw::edit::apply::edit_apply::EditApply;
use crate::draw::elements::core::element_data::ElementData as CoreElementData;
use crate::draw::elements::types::arrow::arrow_binding::ArrowBindingUtils;
use crate::draw::elements::types::arrow::arrow_data::{
    ArrowBinding as DomainArrowBinding, ArrowData, ArrowDataPatch,
    NullableField as ArrowNullableField,
};
use crate::draw::elements::types::arrow::arrow_geometry::ArrowGeometry;
use crate::draw::elements::types::arrow::arrow_layout::resolve_arrow_geometry_update;
use crate::draw::elements::types::arrow::arrow_like_data::NullableField as ArrowLikeNullableField;
use crate::draw::elements::types::arrow::elbow::elbow_router::route_elbow_arrow_for_element_points;
use crate::draw::elements::types::line::line_data::LineData;
use crate::draw::elements::types::serial_number::serial_number_dependencies::{
    clear_element_dependencies_for_ids, DependencyFilter,
};
use crate::draw::models::element_state::ElementState;
use crate::draw::types::draw_point::DrawPoint;
use crate::draw::types::element_style::ArrowType;

/// Result of resolving arrow-binding updates for changed bindables.
#[derive(Clone, Debug, Default, PartialEq)]
pub struct ArrowBindingResolutionUpdate {
    pub updated_elements: HashMap<String, ElementState>,
    pub ordered_element_ids: Option<Vec<String>>,
}

/// Resolves bound connector geometry when bindable targets change.
pub fn resolve_arrow_bindings_for_changed_bindables(
    elements: &[ElementState],
    changed_bindable_ids: &HashSet<String>,
    overlay_updates: &HashMap<String, ElementState>,
) -> ArrowBindingResolutionUpdate {
    if elements.is_empty() || changed_bindable_ids.is_empty() {
        return ArrowBindingResolutionUpdate::default();
    }

    let mut elements_by_id = elements
        .iter()
        .cloned()
        .map(|element| (element.id.clone(), element))
        .collect::<HashMap<_, _>>();
    for (id, element) in overlay_updates {
        elements_by_id.insert(id.clone(), element.clone());
    }

    let mut updated_elements = HashMap::<String, ElementState>::new();
    for element in elements {
        let candidate = overlay_updates.get(&element.id).unwrap_or(element);
        if let Some(updated) =
            resolve_bound_element_update(candidate, changed_bindable_ids, &elements_by_id)
        {
            if updated != *candidate {
                updated_elements.insert(updated.id.clone(), updated);
            }
        }
    }

    ArrowBindingResolutionUpdate {
        updated_elements,
        ordered_element_ids: None,
    }
}

/// Applies replacements and optional ordering to an element list.
pub fn apply_element_replacements_and_order(
    elements: Vec<ElementState>,
    replacements_by_id: &HashMap<String, ElementState>,
    ordered_element_ids: Option<&[String]>,
) -> Vec<ElementState> {
    let replaced = EditApply::replace_elements_by_id(elements, replacements_by_id);
    EditApply::reorder_elements_by_id_order(replaced, ordered_element_ids)
}

/// Reorders elements to match an explicit id order when one is available.
pub fn reorder_elements_by_id_order(
    elements: Vec<ElementState>,
    ordered_element_ids: Option<&[String]>,
) -> Vec<ElementState> {
    EditApply::reorder_elements_by_id_order(elements, ordered_element_ids)
}

/// Clears deleted arrow bindings from remaining elements.
pub fn sync_arrow_bindings_after_deletion(
    elements: Vec<ElementState>,
    deleted_ids: &HashSet<String>,
    _deleted_elements_by_id: &HashMap<String, ElementState>,
) -> Vec<ElementState> {
    if elements.is_empty() || deleted_ids.is_empty() {
        return elements;
    }

    let filter = DependencyFilter {
        include_serial_bindings: false,
        include_arrow_bindings: true,
    };

    elements
        .into_iter()
        .map(|element| clear_element_dependencies_for_ids(&element, deleted_ids, filter))
        .collect()
}

/// Remaps duplicated arrow bindings onto duplicated targets.
pub fn sync_arrow_bindings_after_duplication(
    elements: Vec<ElementState>,
    id_map: &HashMap<String, String>,
) -> Vec<ElementState> {
    if elements.is_empty() || id_map.is_empty() {
        return elements;
    }

    let duplicated_ids = id_map.values().cloned().collect::<HashSet<_>>();
    elements
        .into_iter()
        .map(|element| {
            if !duplicated_ids.contains(element.id.as_str()) {
                return element;
            }
            if let Some(data) = decode_arrow_data(element.data.as_ref()) {
                let remapped = remap_arrow_data_bindings(&data, id_map);
                return element.copy_with(None, None, None, None, None, Some(Arc::new(remapped)));
            }
            if let Some(data) = decode_line_data(element.data.as_ref()) {
                let remapped = remap_line_data_bindings(&data, id_map);
                return element.copy_with(None, None, None, None, None, Some(Arc::new(remapped)));
            }
            element
        })
        .collect()
}

fn resolve_bound_element_update(
    element: &ElementState,
    changed_bindable_ids: &HashSet<String>,
    elements_by_id: &HashMap<String, ElementState>,
) -> Option<ElementState> {
    if let Some(data) = decode_arrow_data(element.data.as_ref()) {
        return resolve_bound_arrow_update(element, &data, changed_bindable_ids, elements_by_id);
    }
    if let Some(data) = decode_line_data(element.data.as_ref()) {
        return resolve_bound_line_update(element, &data, changed_bindable_ids, elements_by_id);
    }
    None
}

fn resolve_bound_arrow_update(
    element: &ElementState,
    data: &ArrowData,
    changed_bindable_ids: &HashSet<String>,
    elements_by_id: &HashMap<String, ElementState>,
) -> Option<ElementState> {
    let world_points = ArrowGeometry::resolve_world_points(element.rect, &data.points);
    if world_points.len() < 2 {
        return None;
    }

    let mut next_world_points = world_points.clone();
    let mut changed = false;
    let start_reference = world_points.get(1).copied();
    let end_reference = world_points
        .get(world_points.len().saturating_sub(2))
        .copied();

    if let Some(binding) = data.start_binding.as_ref() {
        if changed_bindable_ids.contains(binding.element_id.as_str()) {
            if let Some(target) = elements_by_id.get(&binding.element_id) {
                let resolved = if data.arrow_type == ArrowType::Elbow {
                    ArrowBindingUtils::resolve_elbow_bound_point(
                        &to_local_binding(binding),
                        target,
                        data.start_arrowhead
                            != crate::draw::types::element_style::ArrowheadStyle::None,
                    )
                } else {
                    ArrowBindingUtils::resolve_bound_point(
                        &to_local_binding(binding),
                        target,
                        start_reference,
                    )
                };
                if let Some(point) = resolved {
                    next_world_points[0] = point;
                    changed = true;
                }
            }
        }
    }

    if let Some(binding) = data.end_binding.as_ref() {
        if changed_bindable_ids.contains(binding.element_id.as_str()) {
            if let Some(target) = elements_by_id.get(&binding.element_id) {
                let resolved = if data.arrow_type == ArrowType::Elbow {
                    ArrowBindingUtils::resolve_elbow_bound_point(
                        &to_local_binding(binding),
                        target,
                        data.end_arrowhead
                            != crate::draw::types::element_style::ArrowheadStyle::None,
                    )
                } else {
                    ArrowBindingUtils::resolve_bound_point(
                        &to_local_binding(binding),
                        target,
                        end_reference,
                    )
                };
                if let Some(point) = resolved {
                    let last_index = next_world_points.len() - 1;
                    next_world_points[last_index] = point;
                    changed = true;
                }
            }
        }
    }

    if !changed {
        return None;
    }

    if data.arrow_type == ArrowType::Elbow {
        let routed = route_elbow_arrow_for_element_points(
            element,
            next_world_points
                .first()
                .copied()
                .unwrap_or(DrawPoint::ZERO),
            next_world_points.last().copied().unwrap_or(DrawPoint::ZERO),
            elements_by_id,
            data.start_binding.as_ref(),
            data.end_binding.as_ref(),
            data.start_arrowhead,
            data.end_arrowhead,
        );
        let geometry = resolve_arrow_geometry_update(
            &routed.local_points,
            element.rect,
            element.rotation,
            data.arrow_type,
        );
        let next_data = data.copy_with(ArrowDataPatch {
            points: Some(geometry.normalized_points),
            ..ArrowDataPatch::default()
        });
        return Some(element.copy_with(
            None,
            Some(geometry.rect),
            None,
            None,
            None,
            Some(Arc::new(next_data)),
        ));
    }

    let rect = ArrowGeometry::calculate_path_bounds(&next_world_points, data.arrow_type);
    let normalized_points = ArrowGeometry::normalize_points(&next_world_points, rect);
    let next_data = data.copy_with(ArrowDataPatch {
        points: Some(normalized_points),
        ..ArrowDataPatch::default()
    });
    Some(element.copy_with(
        None,
        Some(rect),
        None,
        None,
        None,
        Some(Arc::new(next_data)),
    ))
}

fn resolve_bound_line_update(
    element: &ElementState,
    data: &LineData,
    changed_bindable_ids: &HashSet<String>,
    elements_by_id: &HashMap<String, ElementState>,
) -> Option<ElementState> {
    let world_points = ArrowGeometry::resolve_world_points(element.rect, &data.points);
    if world_points.len() < 2 {
        return None;
    }

    let mut next_world_points = world_points.clone();
    let mut changed = false;
    let start_reference = world_points.get(1).copied();
    let end_reference = world_points
        .get(world_points.len().saturating_sub(2))
        .copied();

    if let Some(binding) = data.start_binding.as_ref() {
        if changed_bindable_ids.contains(binding.element_id.as_str()) {
            if let Some(target) = elements_by_id.get(&binding.element_id) {
                if let Some(point) =
                    ArrowBindingUtils::resolve_bound_point(binding, target, start_reference)
                {
                    next_world_points[0] = point;
                    changed = true;
                }
            }
        }
    }

    if let Some(binding) = data.end_binding.as_ref() {
        if changed_bindable_ids.contains(binding.element_id.as_str()) {
            if let Some(target) = elements_by_id.get(&binding.element_id) {
                if let Some(point) =
                    ArrowBindingUtils::resolve_bound_point(binding, target, end_reference)
                {
                    let last_index = next_world_points.len() - 1;
                    next_world_points[last_index] = point;
                    changed = true;
                }
            }
        }
    }

    if !changed {
        return None;
    }

    let rect = ArrowGeometry::calculate_path_bounds(&next_world_points, data.arrow_type);
    let normalized_points = ArrowGeometry::normalize_points(&next_world_points, rect);
    let next_data = data.copy_with(
        crate::draw::elements::types::line::line_data::LineDataPatch {
            points: Some(normalized_points),
            ..crate::draw::elements::types::line::line_data::LineDataPatch::default()
        },
    );
    Some(element.copy_with(
        None,
        Some(rect),
        None,
        None,
        None,
        Some(Arc::new(next_data)),
    ))
}

fn to_local_binding(
    binding: &DomainArrowBinding,
) -> crate::draw::elements::types::arrow::arrow_binding::ArrowBinding {
    crate::draw::elements::types::arrow::arrow_binding::ArrowBinding::new(
        binding.element_id.clone(),
        binding.anchor,
        match binding.mode {
            crate::draw::elements::types::arrow::arrow_data::ArrowBindingMode::Inside => {
                crate::draw::elements::types::arrow::arrow_binding::ArrowBindingMode::Inside
            }
            crate::draw::elements::types::arrow::arrow_data::ArrowBindingMode::Orbit
            | crate::draw::elements::types::arrow::arrow_data::ArrowBindingMode::Skip => {
                crate::draw::elements::types::arrow::arrow_binding::ArrowBindingMode::Orbit
            }
        },
    )
}

fn decode_arrow_data(data: &dyn CoreElementData) -> Option<ArrowData> {
    if data.type_id().as_str() != ArrowData::TYPE_ID_TOKEN {
        return None;
    }
    ArrowData::from_json(&data.to_json()).ok()
}

fn decode_line_data(data: &dyn CoreElementData) -> Option<LineData> {
    if data.type_id().as_str() != LineData::TYPE_ID_TOKEN {
        return None;
    }
    LineData::from_json(&data.to_json()).ok()
}

fn remap_arrow_data_bindings(data: &ArrowData, id_map: &HashMap<String, String>) -> ArrowData {
    let start_binding = remap_domain_arrow_binding(data.start_binding.as_ref(), id_map);
    let end_binding = remap_domain_arrow_binding(data.end_binding.as_ref(), id_map);
    let clear_start_special = data.start_binding.is_some() && start_binding.is_none();
    let clear_end_special = data.end_binding.is_some() && end_binding.is_none();

    data.copy_with(ArrowDataPatch {
        start_binding: match start_binding {
            Some(value) => ArrowNullableField::Value(value),
            None => ArrowNullableField::Null,
        },
        end_binding: match end_binding {
            Some(value) => ArrowNullableField::Value(value),
            None => ArrowNullableField::Null,
        },
        start_is_special: if clear_start_special {
            ArrowNullableField::Null
        } else {
            ArrowNullableField::Unset
        },
        end_is_special: if clear_end_special {
            ArrowNullableField::Null
        } else {
            ArrowNullableField::Unset
        },
        ..ArrowDataPatch::default()
    })
}

fn remap_line_data_bindings(data: &LineData, id_map: &HashMap<String, String>) -> LineData {
    let start_binding = remap_line_binding(data.start_binding.as_ref(), id_map);
    let end_binding = remap_line_binding(data.end_binding.as_ref(), id_map);
    let clear_start_special = data.start_binding.is_some() && start_binding.is_none();
    let clear_end_special = data.end_binding.is_some() && end_binding.is_none();

    data.copy_with(
        crate::draw::elements::types::line::line_data::LineDataPatch {
            start_binding: match start_binding {
                Some(value) => ArrowLikeNullableField::Value(value),
                None => ArrowLikeNullableField::Null,
            },
            end_binding: match end_binding {
                Some(value) => ArrowLikeNullableField::Value(value),
                None => ArrowLikeNullableField::Null,
            },
            start_is_special: if clear_start_special {
                ArrowLikeNullableField::Null
            } else {
                ArrowLikeNullableField::Unset
            },
            end_is_special: if clear_end_special {
                ArrowLikeNullableField::Null
            } else {
                ArrowLikeNullableField::Unset
            },
            ..crate::draw::elements::types::line::line_data::LineDataPatch::default()
        },
    )
}

fn remap_domain_arrow_binding(
    binding: Option<&DomainArrowBinding>,
    id_map: &HashMap<String, String>,
) -> Option<DomainArrowBinding> {
    let binding = binding?;
    let target_id = id_map.get(binding.element_id.as_str())?;
    Some(DomainArrowBinding::new(
        target_id.clone(),
        binding.anchor,
        binding.mode,
    ))
}

fn remap_line_binding(
    binding: Option<&crate::draw::elements::types::arrow::arrow_binding::ArrowBinding>,
    id_map: &HashMap<String, String>,
) -> Option<crate::draw::elements::types::arrow::arrow_binding::ArrowBinding> {
    let binding = binding?;
    let target_id = id_map.get(binding.element_id.as_str())?;
    Some(
        crate::draw::elements::types::arrow::arrow_binding::ArrowBinding::new(
            target_id.clone(),
            binding.anchor,
            binding.mode,
        ),
    )
}
