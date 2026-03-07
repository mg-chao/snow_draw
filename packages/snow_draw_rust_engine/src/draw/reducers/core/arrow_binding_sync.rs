#![allow(dead_code)]

use std::collections::{HashMap, HashSet};
use std::sync::Arc;

use crate::draw::edit::apply::edit_apply::EditApply;
use crate::draw::elements::core::element_data::ElementData as CoreElementData;
use crate::draw::elements::types::arrow::arrow_binding::ArrowBindingUtils;
use crate::draw::elements::types::arrow::arrow_core_bridge::is_arrow_bindable_element;
use crate::draw::elements::types::arrow::arrow_data::{
    ArrowBinding as DomainArrowBinding, ArrowData, ArrowDataPatch,
    NullableField as ArrowNullableField,
};
use crate::draw::elements::types::arrow::arrow_geometry::ArrowGeometry;
use crate::draw::elements::types::arrow::arrow_layout::resolve_arrow_geometry_update;
use crate::draw::elements::types::arrow::arrow_like_data::NullableField as ArrowLikeNullableField;
use crate::draw::elements::types::arrow::arrow_scene::ArrowScene;
use crate::draw::elements::types::arrow::core::arrow_binding_lifecycle::{
    sync_bindings_after_deletion as sync_core_bindings_after_deletion,
    sync_bindings_after_duplication as sync_core_bindings_after_duplication,
};
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

    let ordered_element_ids = elements
        .iter()
        .map(|element| element.id.clone())
        .collect::<Vec<_>>();
    let merged_elements = elements
        .iter()
        .map(|element| {
            overlay_updates
                .get(&element.id)
                .cloned()
                .unwrap_or_else(|| element.clone())
        })
        .collect::<Vec<_>>();
    let session = ArrowScene::from_elements_with_options(
        merged_elements,
        true,
        Some(&ordered_element_ids),
        None,
    );

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

    let reordered_element_ids = resolve_reordered_element_ids_for_changed_bindables(
        &session,
        &ordered_element_ids,
        changed_bindable_ids,
    );

    ArrowBindingResolutionUpdate {
        updated_elements,
        ordered_element_ids: reordered_element_ids,
    }
}

fn resolve_reordered_element_ids_for_changed_bindables(
    session: &ArrowScene,
    ordered_element_ids: &[String],
    changed_bindable_ids: &HashSet<String>,
) -> Option<Vec<String>> {
    if session.arrows().is_empty() || changed_bindable_ids.is_empty() {
        return None;
    }

    let order_index_by_id = ordered_element_ids
        .iter()
        .enumerate()
        .map(|(index, id)| (id.as_str(), index))
        .collect::<HashMap<_, _>>();
    let mut sorted_changed_bindable_ids = changed_bindable_ids.iter().cloned().collect::<Vec<_>>();
    sorted_changed_bindable_ids.sort_by(|left, right| {
        let left_index = order_index_by_id
            .get(left.as_str())
            .copied()
            .unwrap_or(usize::MAX);
        let right_index = order_index_by_id
            .get(right.as_str())
            .copied()
            .unwrap_or(usize::MAX);
        left_index.cmp(&right_index).then_with(|| left.cmp(right))
    });

    let mut next_order: Option<Vec<String>> = None;
    for arrow in session.arrows() {
        for bindable_id in &sorted_changed_bindable_ids {
            let affected = arrow
                .start_binding
                .as_ref()
                .is_some_and(|binding| binding.element_id == *bindable_id)
                || arrow
                    .end_binding
                    .as_ref()
                    .is_some_and(|binding| binding.element_id == *bindable_id);
            if !affected {
                continue;
            }

            let current_order = next_order.as_deref().unwrap_or(ordered_element_ids);
            if let Some(reordered) = session.reorder_arrow_above_hovered_bindable(
                &arrow.id,
                Some(bindable_id.as_str()),
                None,
                Some(current_order),
                None,
            ) {
                next_order = Some(reordered);
            }
        }
    }

    next_order.filter(|ids| ids.as_slice() != ordered_element_ids)
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
    deleted_elements_by_id: &HashMap<String, ElementState>,
) -> Vec<ElementState> {
    if elements.is_empty() || deleted_ids.is_empty() {
        return elements;
    }

    let ordered_element_ids = elements
        .iter()
        .map(|element| element.id.clone())
        .collect::<Vec<_>>();
    let session = ArrowScene::from_elements_with_options(
        elements.clone(),
        true,
        Some(&ordered_element_ids),
        None,
    );

    let filter = DependencyFilter {
        include_serial_bindings: false,
        include_arrow_bindings: true,
    };

    let baseline = elements
        .into_iter()
        .map(|element| clear_element_dependencies_for_ids(&element, deleted_ids, filter))
        .collect::<Vec<_>>();
    if !session.has_arrows() {
        return baseline;
    }

    let all_deleted_ids = deleted_ids
        .iter()
        .cloned()
        .chain(deleted_elements_by_id.keys().cloned())
        .collect::<HashSet<_>>();
    let mut deleted_arrow_ids = Vec::new();
    let mut deleted_bindable_ids = Vec::new();
    for deleted_id in all_deleted_ids {
        let Some(deleted_element) = deleted_elements_by_id.get(&deleted_id) else {
            continue;
        };
        if decode_arrow_data(deleted_element.data.as_ref()).is_some() {
            deleted_arrow_ids.push(deleted_id.clone());
        }
        if is_arrow_bindable_element(deleted_element) {
            deleted_bindable_ids.push(deleted_id);
        }
    }

    let sync_result = sync_core_bindings_after_deletion(
        &session
            .arrows()
            .iter()
            .map(to_lifecycle_arrow_state)
            .collect::<Vec<_>>(),
        session.bindable_relations(),
        &session
            .bindables()
            .iter()
            .map(to_lifecycle_bindable_state)
            .collect::<Vec<_>>(),
        &deleted_bindable_ids,
        &deleted_arrow_ids,
        &to_lifecycle_context(&session.context),
    );
    let patched_by_id = session.apply_arrow_patches(&sync_result.arrow_patches);
    if patched_by_id.is_empty() {
        return baseline;
    }

    apply_element_replacements_and_order(baseline, &patched_by_id, None)
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
    if duplicated_ids.is_empty() {
        return elements;
    }

    let duplicated_elements = elements
        .iter()
        .filter(|element| duplicated_ids.contains(element.id.as_str()))
        .cloned()
        .collect::<Vec<_>>();
    let baseline = elements
        .into_iter()
        .map(|element| {
            if !duplicated_ids.contains(element.id.as_str()) {
                return element;
            }
            if let Some(data) = decode_line_data(element.data.as_ref()) {
                let remapped = remap_line_data_bindings(&data, id_map);
                return element.copy_with(None, None, None, None, None, Some(Arc::new(remapped)));
            }
            element
        })
        .collect::<Vec<_>>();
    if duplicated_elements.is_empty() {
        return baseline;
    }

    let ordered_element_ids = duplicated_elements
        .iter()
        .map(|element| element.id.clone())
        .collect::<Vec<_>>();
    let elements_by_id = duplicated_elements
        .iter()
        .cloned()
        .map(|element| (element.id.clone(), element))
        .collect::<HashMap<_, _>>();
    let mut bindable_id_map = HashMap::<String, String>::new();
    let mut arrow_id_map = HashMap::<String, String>::new();
    for (source_id, duplicate_id) in id_map {
        let Some(duplicate) = elements_by_id.get(duplicate_id) else {
            continue;
        };
        if is_arrow_bindable_element(duplicate) {
            bindable_id_map.insert(source_id.clone(), duplicate_id.clone());
            bindable_id_map.insert(duplicate_id.clone(), duplicate_id.clone());
        }
        if decode_arrow_data(duplicate.data.as_ref()).is_some() {
            arrow_id_map.insert(source_id.clone(), duplicate_id.clone());
            arrow_id_map.insert(duplicate_id.clone(), duplicate_id.clone());
        }
    }

    let session = ArrowScene::from_elements_with_options(
        duplicated_elements,
        false,
        Some(&ordered_element_ids),
        None,
    );
    if !session.has_arrows() {
        return baseline;
    }

    let sync_result = sync_core_bindings_after_duplication(
        &session
            .arrows()
            .iter()
            .map(to_lifecycle_arrow_state)
            .collect::<Vec<_>>(),
        session.bindable_relations(),
        &bindable_id_map,
        &arrow_id_map,
        &session
            .bindables()
            .iter()
            .map(to_lifecycle_bindable_state)
            .collect::<Vec<_>>(),
        &to_lifecycle_context(&session.context),
        false,
    );
    let patched_by_id = session.apply_arrow_patches(&sync_result.arrow_patches);
    if patched_by_id.is_empty() {
        return baseline;
    }

    apply_element_replacements_and_order(baseline, &patched_by_id, None)
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

fn to_lifecycle_arrow_state(
    arrow: &crate::draw::elements::types::arrow::arrow_core::ArrowState,
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
                .map(to_lifecycle_fixed_segment)
                .collect()
        }),
        start_is_special: arrow.start_is_special,
        end_is_special: arrow.end_is_special,
    }
}

fn to_lifecycle_binding(
    binding: &crate::draw::elements::types::arrow::arrow_binding::ArrowBinding,
) -> crate::draw::elements::types::arrow::core::arrow_types::FixedPointBinding {
    crate::draw::elements::types::arrow::core::arrow_types::FixedPointBinding::new(
        binding.element_id.clone(),
        binding.anchor,
        binding.mode.as_str().to_string(),
    )
}

fn to_lifecycle_fixed_segment(
    segment: crate::draw::elements::types::arrow::arrow_data::ElbowFixedSegment,
) -> crate::draw::elements::types::arrow::core::arrow_types::FixedSegment {
    crate::draw::elements::types::arrow::core::arrow_types::FixedSegment {
        start: segment.start,
        end: segment.end,
        index: segment.index,
    }
}

fn to_lifecycle_bindable_state(
    bindable: &crate::draw::elements::types::arrow::arrow_core::BindableState,
) -> crate::draw::elements::types::arrow::core::arrow_types::BindableState {
    crate::draw::elements::types::arrow::core::arrow_types::BindableState {
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
    context: &crate::draw::elements::types::arrow::arrow_core::EngineContext,
) -> crate::draw::elements::types::arrow::core::arrow_types::EngineContext {
    crate::draw::elements::types::arrow::core::arrow_types::EngineContext {
        zoom: context.zoom,
        is_binding_enabled: context.is_binding_enabled,
        bind_mode: context.bind_mode,
        max_coordinate: context.max_coordinate,
    }
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
