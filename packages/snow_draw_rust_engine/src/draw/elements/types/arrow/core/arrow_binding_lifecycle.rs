#![allow(dead_code)]

use std::collections::{HashMap, HashSet};

use serde_json::{Map, Value};

use super::adapters::apply_arrow_patch;
use super::arrow_binding_core::{
    calculate_fixed_point_for_binding, get_global_fixed_point_for_bindable_element,
};
use super::arrow_elbow_core::update_elbow_arrow_points;
use super::arrow_state_core::{
    apply_arrow_binding_state_patch, apply_bindable_relation_patches,
    reduce_bindable_patches_to_relation_patches,
};
use super::arrow_types::{
    ArrowBindingState, ArrowBindingStatePatch, ArrowEndpointEdge, ArrowEngineEvent, ArrowPatch,
    ArrowState, ArrowStatePatchWithId, BindablePatch, BindableRelationPatch, BindableRelationState,
    BindableState, BindingBrokenEvent, EngineContext, EngineResult, FixedPointBinding,
    LifecycleSyncResult,
};
use crate::draw::types::draw_point::DrawPoint;

pub type PartialBindingArrowPatch = ArrowPatch;

#[derive(Clone, Debug, PartialEq)]
pub struct ResolveBindableRelationPatchesInput {
    pub arrow: ArrowBindingState,
    pub bindables: Vec<BindableRelationState>,
    pub arrow_patch: Option<PartialBindingArrowPatch>,
    pub bindable_patches: Option<Vec<BindablePatch>>,
}

#[derive(Clone, Debug, PartialEq)]
pub struct ResolvedBindableRelationPatches {
    pub bindable_patches: Vec<BindablePatch>,
    pub relation_patches: Vec<BindableRelationPatch>,
}

#[derive(Clone, Debug, PartialEq)]
pub struct EndpointBindingMutationResult {
    pub arrow_patch: ArrowPatch,
    pub bindable_patches: Vec<BindablePatch>,
    pub events: Vec<ArrowEngineEvent>,
}

#[derive(Clone, Debug, PartialEq)]
pub struct EndpointBindingMutationWithRelationsResult {
    pub arrow_patch: ArrowPatch,
    pub bindable_patches: Vec<BindablePatch>,
    pub relation_patches: Vec<BindableRelationPatch>,
    pub events: Vec<ArrowEngineEvent>,
}

pub fn derive_bindable_patches_for_binding_change(
    arrow_id: &str,
    previous: &ArrowBindingState,
    next: &ArrowBindingState,
) -> Vec<BindablePatch> {
    let previous_ids = collect_bound_bindable_ids(previous);
    let next_ids = collect_bound_bindable_ids(next);
    let mut patches = Vec::new();

    for bindable_id in &previous_ids {
        if !next_ids.contains(bindable_id) {
            patches.push(BindablePatch {
                id: bindable_id.clone(),
                add_bound_arrow_id: None,
                remove_bound_arrow_id: Some(arrow_id.to_string()),
            });
        }
    }

    for bindable_id in next_ids {
        if !previous_ids.contains(&bindable_id) {
            patches.push(BindablePatch {
                id: bindable_id,
                add_bound_arrow_id: Some(arrow_id.to_string()),
                remove_bound_arrow_id: None,
            });
        }
    }

    patches
}

pub fn resolve_bindable_relation_patches(
    arrow: &ArrowBindingState,
    bindables: &[BindableRelationState],
    arrow_patch: Option<&ArrowPatch>,
    bindable_patches: Option<&[BindablePatch]>,
) -> ResolvedBindableRelationPatches {
    let next_arrow = arrow_patch
        .map(|patch| apply_arrow_binding_state_patch(arrow, patch))
        .unwrap_or_else(|| arrow.clone());

    let bindable_patches = bindable_patches
        .filter(|patches| !patches.is_empty())
        .map(|patches| patches.to_vec())
        .unwrap_or_else(|| reconcile_bindable_patches_for_arrow(&next_arrow, bindables));

    if bindable_patches.is_empty() {
        return ResolvedBindableRelationPatches {
            bindable_patches,
            relation_patches: Vec::new(),
        };
    }

    ResolvedBindableRelationPatches {
        relation_patches: reduce_bindable_patches_to_relation_patches(bindables, &bindable_patches),
        bindable_patches,
    }
}

pub fn resolve_endpoint_binding_mutation(
    arrow: &ArrowBindingState,
    bindables: &[BindableRelationState],
    mutation: &EndpointBindingMutationResult,
) -> ResolvedBindableRelationPatches {
    resolve_bindable_relation_patches(
        arrow,
        bindables,
        Some(&mutation.arrow_patch),
        Some(&mutation.bindable_patches),
    )
}

pub fn bind_arrow_endpoint(
    arrow: &ArrowState,
    edge: ArrowEndpointEdge,
    bindable: &BindableState,
    mode: Option<&str>,
    focus_point: Option<DrawPoint>,
) -> EndpointBindingMutationResult {
    let next_binding = resolve_manual_binding(arrow, edge, bindable, mode, focus_point);
    let previous = to_arrow_binding_state(arrow);
    let next = arrow_binding_state_with_edge(&previous, edge, Some(next_binding.clone()));
    let previous_binding = edge_binding(arrow, edge);

    EndpointBindingMutationResult {
        arrow_patch: patch_for_edge(edge, Some(&next_binding), previous_binding),
        bindable_patches: derive_bindable_patches_for_binding_change(&arrow.id, &previous, &next),
        events: Vec::new(),
    }
}

pub fn unbind_arrow_endpoint(
    arrow: &ArrowState,
    edge: ArrowEndpointEdge,
) -> EndpointBindingMutationResult {
    let previous_binding = edge_binding(arrow, edge).cloned();
    let Some(previous_binding) = previous_binding else {
        return EndpointBindingMutationResult {
            arrow_patch: ArrowPatch::new(),
            bindable_patches: Vec::new(),
            events: Vec::new(),
        };
    };

    let previous = to_arrow_binding_state(arrow);
    let next = arrow_binding_state_with_edge(&previous, edge, None);

    EndpointBindingMutationResult {
        arrow_patch: patch_for_edge(edge, None, Some(&previous_binding)),
        bindable_patches: derive_bindable_patches_for_binding_change(&arrow.id, &previous, &next),
        events: Vec::new(),
    }
}

pub fn bind_arrow_endpoint_with_relations(
    arrow: &ArrowState,
    edge: ArrowEndpointEdge,
    bindable: &BindableState,
    relations: &[BindableRelationState],
    mode: Option<&str>,
    focus_point: Option<DrawPoint>,
) -> EndpointBindingMutationWithRelationsResult {
    resolve_mutation_with_relations(
        arrow,
        relations,
        bind_arrow_endpoint(arrow, edge, bindable, mode, focus_point),
    )
}

pub fn unbind_arrow_endpoint_with_relations(
    arrow: &ArrowState,
    edge: ArrowEndpointEdge,
    relations: &[BindableRelationState],
) -> EndpointBindingMutationWithRelationsResult {
    resolve_mutation_with_relations(arrow, relations, unbind_arrow_endpoint(arrow, edge))
}

pub fn refresh_endpoint_binding(
    arrow: &ArrowState,
    edge: ArrowEndpointEdge,
    bindables: &[BindableState],
) -> EngineResult {
    let Some(previous_binding) = edge_binding(arrow, edge) else {
        return empty_engine_result();
    };
    let Some(bindable) = bindables
        .iter()
        .find(|candidate| candidate.id == previous_binding.element_id)
    else {
        return with_engine_envelope(unbind_arrow_endpoint(arrow, edge));
    };
    let focus_point = endpoint_global_point(arrow, edge);
    with_engine_envelope(bind_arrow_endpoint(
        arrow,
        edge,
        bindable,
        Some(previous_binding.mode.as_str()),
        focus_point,
    ))
}

pub fn prune_arrow_bindings(
    arrow: &ArrowState,
    retained_bindable_ids: &[String],
    prune_start: bool,
    prune_end: bool,
) -> EngineResult {
    let retained = retained_bindable_ids
        .iter()
        .cloned()
        .collect::<HashSet<_>>();
    let previous = to_arrow_binding_state(arrow);
    let mut next = previous.clone();
    let mut patch = ArrowPatch::new();
    let mut events = Vec::new();

    if prune_start {
        if let Some(binding) = previous.start_binding.as_ref() {
            if !retained.contains(&binding.element_id) {
                next.start_binding = None;
                patch.insert("startBinding".to_string(), Value::Null);
                events.push(ArrowEngineEvent::BindingBroken(BindingBrokenEvent {
                    arrow_id: arrow.id.clone(),
                    edge: ArrowEndpointEdge::Start,
                }));
            }
        }
    }
    if prune_end {
        if let Some(binding) = previous.end_binding.as_ref() {
            if !retained.contains(&binding.element_id) {
                next.end_binding = None;
                patch.insert("endBinding".to_string(), Value::Null);
                events.push(ArrowEngineEvent::BindingBroken(BindingBrokenEvent {
                    arrow_id: arrow.id.clone(),
                    edge: ArrowEndpointEdge::End,
                }));
            }
        }
    }

    EngineResult {
        arrow_patch: patch,
        bindable_patches: derive_bindable_patches_for_binding_change(&arrow.id, &previous, &next),
        suggested_binding: None,
        events,
    }
}

pub fn reconcile_bindable_patches_for_arrow(
    arrow: &ArrowBindingState,
    bindables: &[BindableRelationState],
) -> Vec<BindablePatch> {
    let bound_bindable_ids = collect_bound_bindable_ids(arrow);
    let mut seen_bindable_ids = HashSet::<String>::new();
    let mut patches = Vec::new();

    for bindable in bindables {
        seen_bindable_ids.insert(bindable.id.clone());
        let has_arrow = bindable
            .bound_arrow_ids
            .iter()
            .any(|arrow_id| arrow_id == &arrow.id);
        let should_contain_arrow = bound_bindable_ids.contains(&bindable.id);

        if has_arrow && !should_contain_arrow {
            patches.push(BindablePatch {
                id: bindable.id.clone(),
                add_bound_arrow_id: None,
                remove_bound_arrow_id: Some(arrow.id.clone()),
            });
            continue;
        }
        if !has_arrow && should_contain_arrow {
            patches.push(BindablePatch {
                id: bindable.id.clone(),
                add_bound_arrow_id: Some(arrow.id.clone()),
                remove_bound_arrow_id: None,
            });
        }
    }

    for bindable_id in bound_bindable_ids {
        if seen_bindable_ids.contains(&bindable_id) {
            continue;
        }
        patches.push(BindablePatch {
            id: bindable_id,
            add_bound_arrow_id: Some(arrow.id.clone()),
            remove_bound_arrow_id: None,
        });
    }

    patches
}

pub fn remap_arrow_bindings_after_duplication(
    arrows: &[ArrowBindingState],
    bindable_id_map: &HashMap<String, String>,
    preserve_unmapped: bool,
) -> Vec<ArrowBindingStatePatch> {
    let mut patches = Vec::new();

    for arrow in arrows {
        let start_binding = remap_binding(
            arrow.start_binding.as_ref(),
            bindable_id_map,
            preserve_unmapped,
        );
        let end_binding = remap_binding(
            arrow.end_binding.as_ref(),
            bindable_id_map,
            preserve_unmapped,
        );
        if binding_equal(start_binding.as_ref(), arrow.start_binding.as_ref())
            && binding_equal(end_binding.as_ref(), arrow.end_binding.as_ref())
        {
            continue;
        }

        let mut patch = ArrowBindingStatePatch::new();
        patch.insert("id".to_string(), Value::String(arrow.id.clone()));
        patch.insert(
            "startBinding".to_string(),
            binding_to_value(start_binding.as_ref()),
        );
        patch.insert(
            "endBinding".to_string(),
            binding_to_value(end_binding.as_ref()),
        );
        patches.push(patch);
    }

    patches
}

pub fn remap_bindable_relations_after_duplication(
    bindables: &[BindableRelationState],
    arrow_id_map: &HashMap<String, String>,
    preserve_unmapped: bool,
) -> Vec<BindableRelationPatch> {
    let mut patches = Vec::new();

    for bindable in bindables {
        let next = bindable
            .bound_arrow_ids
            .iter()
            .filter_map(|arrow_id| {
                arrow_id_map
                    .get(arrow_id)
                    .cloned()
                    .or_else(|| preserve_unmapped.then_some(arrow_id.clone()))
            })
            .collect::<Vec<_>>();
        if next != bindable.bound_arrow_ids {
            patches.push(BindableRelationPatch {
                id: bindable.id.clone(),
                bound_arrow_ids: next,
            });
        }
    }

    patches
}

pub fn repair_arrow_bindings_after_bindable_deletion(
    arrows: &[ArrowBindingState],
    deleted_bindable_ids: &[String],
) -> Vec<ArrowBindingStatePatch> {
    if deleted_bindable_ids.is_empty() {
        return Vec::new();
    }

    let deleted = deleted_bindable_ids.iter().cloned().collect::<HashSet<_>>();
    let mut patches = Vec::new();

    for arrow in arrows {
        let next_start = arrow
            .start_binding
            .as_ref()
            .filter(|binding| !deleted.contains(&binding.element_id))
            .cloned();
        let next_end = arrow
            .end_binding
            .as_ref()
            .filter(|binding| !deleted.contains(&binding.element_id))
            .cloned();

        if binding_equal(next_start.as_ref(), arrow.start_binding.as_ref())
            && binding_equal(next_end.as_ref(), arrow.end_binding.as_ref())
        {
            continue;
        }

        let mut patch = ArrowBindingStatePatch::new();
        patch.insert("id".to_string(), Value::String(arrow.id.clone()));
        patch.insert(
            "startBinding".to_string(),
            binding_to_value(next_start.as_ref()),
        );
        patch.insert(
            "endBinding".to_string(),
            binding_to_value(next_end.as_ref()),
        );
        patches.push(patch);
    }

    patches
}

pub fn repair_bindable_relations_after_arrow_deletion(
    bindables: &[BindableRelationState],
    deleted_arrow_ids: &[String],
) -> Vec<BindableRelationPatch> {
    if deleted_arrow_ids.is_empty() {
        return Vec::new();
    }

    let deleted = deleted_arrow_ids.iter().cloned().collect::<HashSet<_>>();
    let mut patches = Vec::new();
    for bindable in bindables {
        let next = bindable
            .bound_arrow_ids
            .iter()
            .filter(|arrow_id| !deleted.contains(*arrow_id))
            .cloned()
            .collect::<Vec<_>>();
        if next != bindable.bound_arrow_ids {
            patches.push(BindableRelationPatch {
                id: bindable.id.clone(),
                bound_arrow_ids: next,
            });
        }
    }
    patches
}

pub fn sync_bindings_after_bindable_prune(
    arrows: &[ArrowState],
    bindables: &[BindableRelationState],
    retained_bindable_ids: &[String],
    prune_start: bool,
    prune_end: bool,
) -> LifecycleSyncResult {
    let mut relation_patch_by_id = HashMap::<String, BindableRelationPatch>::new();
    let mut arrow_patches = Vec::new();
    let mut events = Vec::new();
    let mut next_bindables = bindables.to_vec();

    let next_arrows = arrows
        .iter()
        .map(|arrow| {
            let prune_result =
                prune_arrow_bindings(arrow, retained_bindable_ids, prune_start, prune_end);
            events.extend(prune_result.events.clone());

            if !prune_result.arrow_patch.is_empty() {
                arrow_patches.push(ArrowStatePatchWithId {
                    id: arrow.id.clone(),
                    patch: prune_result.arrow_patch.clone(),
                });
            }

            if !prune_result.bindable_patches.is_empty() {
                let relation_patches = reduce_bindable_patches_to_relation_patches(
                    &next_bindables,
                    &prune_result.bindable_patches,
                );
                if !relation_patches.is_empty() {
                    next_bindables =
                        apply_bindable_relation_patches(&next_bindables, &relation_patches);
                    for relation_patch in relation_patches {
                        relation_patch_by_id.insert(relation_patch.id.clone(), relation_patch);
                    }
                }
            }

            apply_arrow_patch(arrow, &prune_result.arrow_patch)
        })
        .collect::<Vec<_>>();

    LifecycleSyncResult {
        arrows: next_arrows,
        bindables: next_bindables,
        arrow_patches,
        relation_patches: relation_patch_by_id.into_values().collect(),
        events,
    }
}

pub fn sync_bindings_after_duplication(
    arrows: &[ArrowState],
    bindables: &[BindableRelationState],
    bindable_id_map: &HashMap<String, String>,
    arrow_id_map: &HashMap<String, String>,
    geometry_bindables: &[BindableState],
    context: &EngineContext,
    preserve_unmapped: bool,
) -> LifecycleSyncResult {
    let arrow_binding_patches = remap_arrow_bindings_after_duplication(
        &arrows
            .iter()
            .map(to_arrow_binding_state)
            .collect::<Vec<_>>(),
        bindable_id_map,
        preserve_unmapped,
    );
    let relation_patches =
        remap_bindable_relations_after_duplication(bindables, arrow_id_map, preserve_unmapped);
    apply_lifecycle_patches(
        arrows,
        bindables,
        &arrow_binding_patches,
        &relation_patches,
        geometry_bindables,
        context,
        true,
    )
}

pub fn sync_bindings_after_deletion(
    arrows: &[ArrowState],
    bindables: &[BindableRelationState],
    geometry_bindables: &[BindableState],
    deleted_bindable_ids: &[String],
    deleted_arrow_ids: &[String],
    context: &EngineContext,
) -> LifecycleSyncResult {
    let arrow_binding_patches = repair_arrow_bindings_after_bindable_deletion(
        &arrows
            .iter()
            .map(to_arrow_binding_state)
            .collect::<Vec<_>>(),
        deleted_bindable_ids,
    );
    let relation_patches =
        repair_bindable_relations_after_arrow_deletion(bindables, deleted_arrow_ids);
    apply_lifecycle_patches(
        arrows,
        bindables,
        &arrow_binding_patches,
        &relation_patches,
        geometry_bindables,
        context,
        false,
    )
}

fn apply_lifecycle_patches(
    arrows: &[ArrowState],
    bindables: &[BindableRelationState],
    arrow_binding_patches: &[ArrowBindingStatePatch],
    relation_patches: &[BindableRelationPatch],
    geometry_bindables: &[BindableState],
    context: &EngineContext,
    recompute_all_elbows: bool,
) -> LifecycleSyncResult {
    let mut patch_by_id = HashMap::<String, ArrowPatch>::new();
    for binding_patch in arrow_binding_patches {
        let Some(id) = binding_patch.get("id").and_then(Value::as_str) else {
            continue;
        };
        let patch = to_arrow_patch_from_binding_patch(binding_patch);
        if !patch.is_empty() {
            patch_by_id.insert(id.to_string(), patch);
        }
    }

    let geometry_bindables_value = Value::Array(
        geometry_bindables
            .iter()
            .map(bindable_state_to_value)
            .collect(),
    );
    let context_value = engine_context_to_value(context);

    let next_arrows = arrows
        .iter()
        .map(|arrow| {
            let base_patch = patch_by_id.get(&arrow.id).cloned().unwrap_or_default();
            let with_bindings = if base_patch.is_empty() {
                arrow.clone()
            } else {
                apply_arrow_patch(arrow, &base_patch)
            };
            let should_recompute_elbow =
                arrow.elbowed && (recompute_all_elbows || !base_patch.is_empty());
            if !should_recompute_elbow {
                return with_bindings;
            }

            let elbow_patch = lifecycle_elbow_patch(
                &with_bindings,
                &geometry_bindables_value,
                &context_value,
                recompute_all_elbows,
            );
            if elbow_patch.is_empty() {
                return with_bindings;
            }

            let mut merged_patch = base_patch.clone();
            merged_patch.extend(elbow_patch.clone());
            patch_by_id.insert(arrow.id.clone(), merged_patch);

            apply_arrow_patch(&with_bindings, &elbow_patch)
        })
        .collect::<Vec<_>>();
    let next_bindables = apply_bindable_relation_patches(bindables, relation_patches);
    let arrow_patches = arrows
        .iter()
        .filter_map(|arrow| {
            patch_by_id
                .get(&arrow.id)
                .map(|patch| ArrowStatePatchWithId {
                    id: arrow.id.clone(),
                    patch: patch.clone(),
                })
        })
        .collect::<Vec<_>>();

    LifecycleSyncResult {
        arrows: next_arrows,
        bindables: next_bindables,
        arrow_patches,
        relation_patches: relation_patches.to_vec(),
        events: Vec::new(),
    }
}

fn resolve_mutation_with_relations(
    arrow: &ArrowState,
    relations: &[BindableRelationState],
    mutation: EndpointBindingMutationResult,
) -> EndpointBindingMutationWithRelationsResult {
    let resolved =
        resolve_endpoint_binding_mutation(&to_arrow_binding_state(arrow), relations, &mutation);
    EndpointBindingMutationWithRelationsResult {
        arrow_patch: mutation.arrow_patch,
        bindable_patches: resolved.bindable_patches,
        relation_patches: resolved.relation_patches,
        events: mutation.events,
    }
}

fn to_arrow_binding_state(arrow: &ArrowState) -> ArrowBindingState {
    ArrowBindingState {
        id: arrow.id.clone(),
        start_binding: arrow.start_binding.clone(),
        end_binding: arrow.end_binding.clone(),
    }
}

fn arrow_binding_state_with_edge(
    state: &ArrowBindingState,
    edge: ArrowEndpointEdge,
    binding: Option<FixedPointBinding>,
) -> ArrowBindingState {
    let mut next = state.clone();
    match edge {
        ArrowEndpointEdge::Start => next.start_binding = binding,
        ArrowEndpointEdge::End => next.end_binding = binding,
    }
    next
}

fn edge_binding<'a>(
    arrow: &'a ArrowState,
    edge: ArrowEndpointEdge,
) -> Option<&'a FixedPointBinding> {
    match edge {
        ArrowEndpointEdge::Start => arrow.start_binding.as_ref(),
        ArrowEndpointEdge::End => arrow.end_binding.as_ref(),
    }
}

fn endpoint_global_point(arrow: &ArrowState, edge: ArrowEndpointEdge) -> Option<DrawPoint> {
    let point = match edge {
        ArrowEndpointEdge::Start => arrow.points.first().copied(),
        ArrowEndpointEdge::End => arrow.points.last().copied(),
    }?;
    Some(DrawPoint::new(arrow.x + point.x, arrow.y + point.y))
}

fn resolve_manual_binding(
    arrow: &ArrowState,
    edge: ArrowEndpointEdge,
    bindable: &BindableState,
    mode: Option<&str>,
    focus_point: Option<DrawPoint>,
) -> FixedPointBinding {
    let target_point = focus_point
        .or_else(|| endpoint_global_point(arrow, edge))
        .unwrap_or(DrawPoint::ZERO);
    let fixed_point = if arrow.elbowed {
        calculate_fixed_point_for_binding(
            get_global_fixed_point_for_bindable_element(
                &FixedPointBinding::new(
                    bindable.id.clone(),
                    calculate_fixed_point_for_binding(target_point, bindable),
                    mode.unwrap_or("orbit"),
                ),
                bindable,
            ),
            bindable,
        )
    } else {
        calculate_fixed_point_for_binding(target_point, bindable)
    };
    FixedPointBinding::new(bindable.id.clone(), fixed_point, mode.unwrap_or("orbit"))
}

fn collect_bound_bindable_ids(state: &ArrowBindingState) -> HashSet<String> {
    let mut ids = HashSet::new();
    if let Some(binding) = state.start_binding.as_ref() {
        ids.insert(binding.element_id.clone());
    }
    if let Some(binding) = state.end_binding.as_ref() {
        ids.insert(binding.element_id.clone());
    }
    ids
}

fn binding_equal(left: Option<&FixedPointBinding>, right: Option<&FixedPointBinding>) -> bool {
    match (left, right) {
        (Some(left), Some(right)) => {
            left.element_id == right.element_id
                && left.mode == right.mode
                && fixed_point_equal(left.fixed_point, right.fixed_point)
        }
        (None, None) => true,
        _ => false,
    }
}

fn fixed_point_equal(left: DrawPoint, right: DrawPoint) -> bool {
    left.x == right.x && left.y == right.y
}

fn patch_for_edge(
    edge: ArrowEndpointEdge,
    next: Option<&FixedPointBinding>,
    previous: Option<&FixedPointBinding>,
) -> ArrowPatch {
    if binding_equal(next, previous) {
        return ArrowPatch::new();
    }
    let mut patch = ArrowPatch::new();
    patch.insert(
        match edge {
            ArrowEndpointEdge::Start => "startBinding".to_string(),
            ArrowEndpointEdge::End => "endBinding".to_string(),
        },
        binding_to_value(next),
    );
    patch
}

fn binding_to_value(binding: Option<&FixedPointBinding>) -> Value {
    let Some(binding) = binding else {
        return Value::Null;
    };
    let mut object = Map::new();
    object.insert(
        "elementId".to_string(),
        Value::String(binding.element_id.clone()),
    );
    object.insert(
        "fixedPoint".to_string(),
        Value::Array(vec![
            Value::from(binding.fixed_point.x),
            Value::from(binding.fixed_point.y),
        ]),
    );
    object.insert("mode".to_string(), Value::String(binding.mode.clone()));
    Value::Object(object)
}

fn lifecycle_elbow_patch(
    arrow: &ArrowState,
    geometry_bindables: &Value,
    context: &Value,
    recompute_all_elbows: bool,
) -> ArrowPatch {
    let mut input = ArrowPatch::new();
    input.insert("arrow".to_string(), arrow_state_to_value(arrow));
    input.insert("bindables".to_string(), geometry_bindables.clone());
    input.insert("context".to_string(), context.clone());

    if recompute_all_elbows {
        let mut updates = Map::new();
        if let (Some(start), Some(end)) = (arrow.points.first(), arrow.points.last()) {
            updates.insert(
                "points".to_string(),
                Value::Array(vec![point_to_value(start), point_to_value(end)]),
            );
        }
        input.insert("updates".to_string(), Value::Object(updates));
        input.insert(
            "options".to_string(),
            Value::Object(Map::from_iter([(
                "isDragging".to_string(),
                Value::Bool(false),
            )])),
        );
    }

    update_elbow_arrow_points(input)
}

fn arrow_state_to_value(arrow: &ArrowState) -> Value {
    let mut object = Map::new();
    object.insert("id".to_string(), Value::String(arrow.id.clone()));
    object.insert("x".to_string(), Value::from(arrow.x));
    object.insert("y".to_string(), Value::from(arrow.y));
    object.insert("width".to_string(), Value::from(arrow.width));
    object.insert("height".to_string(), Value::from(arrow.height));
    object.insert(
        "points".to_string(),
        Value::Array(arrow.points.iter().map(point_to_value).collect()),
    );
    object.insert(
        "startBinding".to_string(),
        binding_to_value(arrow.start_binding.as_ref()),
    );
    object.insert(
        "endBinding".to_string(),
        binding_to_value(arrow.end_binding.as_ref()),
    );
    object.insert(
        "startArrowhead".to_string(),
        arrow
            .start_arrowhead
            .as_ref()
            .map(|value| Value::String(value.clone()))
            .unwrap_or(Value::Null),
    );
    object.insert(
        "endArrowhead".to_string(),
        arrow
            .end_arrowhead
            .as_ref()
            .map(|value| Value::String(value.clone()))
            .unwrap_or(Value::Null),
    );
    object.insert("elbowed".to_string(), Value::Bool(arrow.elbowed));
    object.insert(
        "fixedSegments".to_string(),
        arrow
            .fixed_segments
            .as_ref()
            .map_or(Value::Null, |segments| {
                Value::Array(segments.iter().map(fixed_segment_to_value).collect())
            }),
    );
    object.insert(
        "startIsSpecial".to_string(),
        arrow
            .start_is_special
            .map(Value::Bool)
            .unwrap_or(Value::Null),
    );
    object.insert(
        "endIsSpecial".to_string(),
        arrow.end_is_special.map(Value::Bool).unwrap_or(Value::Null),
    );
    Value::Object(object)
}

fn bindable_state_to_value(bindable: &BindableState) -> Value {
    let mut object = Map::new();
    object.insert("id".to_string(), Value::String(bindable.id.clone()));
    object.insert("shape".to_string(), Value::String(bindable.shape.clone()));
    object.insert("x".to_string(), Value::from(bindable.x));
    object.insert("y".to_string(), Value::from(bindable.y));
    object.insert("width".to_string(), Value::from(bindable.width));
    object.insert("height".to_string(), Value::from(bindable.height));
    object.insert("angle".to_string(), Value::from(bindable.angle));
    object.insert(
        "strokeWidth".to_string(),
        Value::from(bindable.stroke_width),
    );
    Value::Object(object)
}

fn engine_context_to_value(context: &EngineContext) -> Value {
    let mut object = Map::new();
    object.insert("zoom".to_string(), Value::from(context.zoom));
    object.insert(
        "isBindingEnabled".to_string(),
        Value::Bool(context.is_binding_enabled),
    );
    object.insert(
        "maxCoordinate".to_string(),
        Value::from(context.max_coordinate),
    );
    Value::Object(object)
}

fn point_to_value(point: &DrawPoint) -> Value {
    Value::Array(vec![Value::from(point.x), Value::from(point.y)])
}

fn fixed_segment_to_value(segment: &super::arrow_types::FixedSegment) -> Value {
    let mut object = Map::new();
    object.insert("start".to_string(), point_to_value(&segment.start));
    object.insert("end".to_string(), point_to_value(&segment.end));
    object.insert("index".to_string(), Value::from(segment.index));
    Value::Object(object)
}

fn to_arrow_patch_from_binding_patch(binding_patch: &ArrowBindingStatePatch) -> ArrowPatch {
    let mut mapped = ArrowPatch::new();
    if binding_patch.contains_key("startBinding") {
        mapped.insert(
            "startBinding".to_string(),
            binding_patch
                .get("startBinding")
                .cloned()
                .unwrap_or(Value::Null),
        );
    }
    if binding_patch.contains_key("endBinding") {
        mapped.insert(
            "endBinding".to_string(),
            binding_patch
                .get("endBinding")
                .cloned()
                .unwrap_or(Value::Null),
        );
    }
    mapped
}

fn remap_binding(
    binding: Option<&FixedPointBinding>,
    id_map: &HashMap<String, String>,
    preserve_unmapped: bool,
) -> Option<FixedPointBinding> {
    let binding = binding?;
    if let Some(next_id) = id_map.get(&binding.element_id) {
        return Some(FixedPointBinding::new(
            next_id.clone(),
            binding.fixed_point,
            binding.mode.clone(),
        ));
    }
    preserve_unmapped.then_some(binding.clone())
}

fn empty_engine_result() -> EngineResult {
    EngineResult {
        arrow_patch: ArrowPatch::new(),
        bindable_patches: Vec::new(),
        suggested_binding: None,
        events: Vec::new(),
    }
}

fn with_engine_envelope(mutation: EndpointBindingMutationResult) -> EngineResult {
    EngineResult {
        arrow_patch: mutation.arrow_patch,
        bindable_patches: mutation.bindable_patches,
        suggested_binding: None,
        events: mutation.events,
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn sample_arrow() -> ArrowState {
        ArrowState {
            id: "arrow-1".to_string(),
            x: 0.0,
            y: 0.0,
            width: 100.0,
            height: 20.0,
            points: vec![DrawPoint::new(0.0, 0.0), DrawPoint::new(100.0, 20.0)],
            start_binding: None,
            end_binding: None,
            start_arrowhead: None,
            end_arrowhead: None,
            elbowed: false,
            fixed_segments: None,
            start_is_special: None,
            end_is_special: None,
        }
    }

    fn sample_bindable(id: &str) -> BindableState {
        BindableState {
            id: id.to_string(),
            shape: "rectangle".to_string(),
            x: 20.0,
            y: 40.0,
            width: 100.0,
            height: 80.0,
            angle: 0.0,
            stroke_width: 2.0,
            roundness: None,
            z_index: Some(1.0),
            background_opaque: Some(true),
            binding_enabled: Some(true),
            interior_hit_enabled: Some(true),
            visibility_bounds: None,
        }
    }

    #[test]
    fn bind_arrow_endpoint_adds_relation_patch_inputs() {
        let arrow = sample_arrow();
        let bindable = sample_bindable("rect-1");

        let result = bind_arrow_endpoint(
            &arrow,
            ArrowEndpointEdge::Start,
            &bindable,
            Some("orbit"),
            Some(DrawPoint::new(30.0, 50.0)),
        );

        assert!(result.arrow_patch.contains_key("startBinding"));
        assert_eq!(result.bindable_patches.len(), 1);
        assert_eq!(result.bindable_patches[0].id, "rect-1");
        assert_eq!(
            result.bindable_patches[0].add_bound_arrow_id.as_deref(),
            Some("arrow-1")
        );
    }

    #[test]
    fn resolve_bindable_relation_patches_reconciles_missing_relation_membership() {
        let arrow = ArrowBindingState {
            id: "arrow-1".to_string(),
            start_binding: Some(FixedPointBinding::new(
                "rect-1",
                DrawPoint::new(0.2, 0.5),
                "orbit",
            )),
            end_binding: None,
        };
        let bindables = vec![BindableRelationState {
            id: "rect-1".to_string(),
            bound_arrow_ids: Vec::new(),
        }];

        let resolved = resolve_bindable_relation_patches(&arrow, &bindables, None, None);

        assert_eq!(resolved.bindable_patches.len(), 1);
        assert_eq!(resolved.relation_patches.len(), 1);
        assert_eq!(
            resolved.relation_patches[0].bound_arrow_ids,
            vec!["arrow-1".to_string()]
        );
    }

    #[test]
    fn remap_arrow_bindings_after_duplication_updates_target_ids() {
        let arrows = vec![ArrowBindingState {
            id: "arrow-1".to_string(),
            start_binding: Some(FixedPointBinding::new(
                "rect-1",
                DrawPoint::new(0.2, 0.5),
                "orbit",
            )),
            end_binding: None,
        }];
        let id_map = HashMap::from([(String::from("rect-1"), String::from("rect-2"))]);

        let patches = remap_arrow_bindings_after_duplication(&arrows, &id_map, false);

        assert_eq!(patches.len(), 1);
        let start_binding = patches[0]
            .get("startBinding")
            .and_then(Value::as_object)
            .and_then(|binding| binding.get("elementId"))
            .and_then(Value::as_str);
        assert_eq!(start_binding, Some("rect-2"));
    }

    #[test]
    fn repair_bindable_relations_after_arrow_deletion_removes_deleted_ids() {
        let bindables = vec![BindableRelationState {
            id: "rect-1".to_string(),
            bound_arrow_ids: vec!["arrow-1".to_string(), "arrow-2".to_string()],
        }];

        let patches =
            repair_bindable_relations_after_arrow_deletion(&bindables, &[String::from("arrow-1")]);

        assert_eq!(patches.len(), 1);
        assert_eq!(patches[0].bound_arrow_ids, vec!["arrow-2".to_string()]);
    }
}
