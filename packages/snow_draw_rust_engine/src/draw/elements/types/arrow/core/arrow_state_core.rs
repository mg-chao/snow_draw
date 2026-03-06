#![allow(dead_code)]

use std::collections::HashMap;

use serde_json::Value;

use super::adapters::apply_arrow_patch;
use super::arrow_order_core::reorder_arrow_above_elements;
use super::arrow_types::{
    ApplyEngineResultInput, ApplyEngineResultValue, ArrowBindingState, ArrowBindingStatePatch,
    ArrowEngineEvent, BindablePatch, BindableRelationPatch, BindableRelationState,
    BindingBrokenEvent, ReduceArrowEngineEventsToOrderInput, ReduceArrowEngineEventsToOrderResult,
    ReorderArrowAboveElementsInput,
};

pub fn apply_arrow_binding_state_patch(
    arrow: &ArrowBindingState,
    patch: &ArrowBindingStatePatch,
) -> ArrowBindingState {
    let mut next = arrow.clone();
    if patch.contains_key("startBinding") {
        next.start_binding = patch
            .get("startBinding")
            .and_then(read_binding_state_binding);
    }
    if patch.contains_key("endBinding") {
        next.end_binding = patch.get("endBinding").and_then(read_binding_state_binding);
    }
    next
}

pub fn apply_bindable_relation_patch(
    bindable: &BindableRelationState,
    patch: &BindableRelationPatch,
) -> BindableRelationState {
    BindableRelationState {
        id: bindable.id.clone(),
        bound_arrow_ids: patch.bound_arrow_ids.clone(),
    }
}

pub fn apply_bindable_relation_patches(
    bindables: &[BindableRelationState],
    patches: &[BindableRelationPatch],
) -> Vec<BindableRelationState> {
    if patches.is_empty() {
        return bindables.to_vec();
    }

    let mut next = bindables.to_vec();
    let mut index_by_id = next
        .iter()
        .enumerate()
        .map(|(index, bindable)| (bindable.id.clone(), index))
        .collect::<HashMap<_, _>>();

    for patch in patches {
        let normalized = BindableRelationState {
            id: patch.id.clone(),
            bound_arrow_ids: patch.bound_arrow_ids.clone(),
        };
        match index_by_id.get(&patch.id).copied() {
            Some(index) => next[index] = normalized,
            None => {
                index_by_id.insert(patch.id.clone(), next.len());
                next.push(normalized);
            }
        }
    }

    next
}

pub fn reduce_bindable_patches_to_relation_patches(
    bindables: &[BindableRelationState],
    patches: &[BindablePatch],
) -> Vec<BindableRelationPatch> {
    if patches.is_empty() {
        return Vec::new();
    }

    let original_by_id = bindables
        .iter()
        .map(|bindable| (bindable.id.clone(), bindable.bound_arrow_ids.clone()))
        .collect::<HashMap<_, _>>();
    let mut next_by_id = HashMap::<String, Vec<String>>::new();

    for patch in patches {
        let mut current = next_by_id
            .remove(&patch.id)
            .unwrap_or_else(|| original_by_id.get(&patch.id).cloned().unwrap_or_default());
        if let Some(remove) = &patch.remove_bound_arrow_id {
            current.retain(|arrow_id| arrow_id != remove);
        }
        if let Some(add) = &patch.add_bound_arrow_id {
            if !current.iter().any(|arrow_id| arrow_id == add) {
                current.push(add.clone());
            }
        }
        next_by_id.insert(patch.id.clone(), current);
    }

    next_by_id
        .into_iter()
        .filter_map(|(id, bound_arrow_ids)| {
            let previous = original_by_id.get(&id).cloned().unwrap_or_default();
            (previous != bound_arrow_ids).then_some(BindableRelationPatch {
                id,
                bound_arrow_ids,
            })
        })
        .collect()
}

pub fn reduce_arrow_engine_events_to_order(
    input: &ReduceArrowEngineEventsToOrderInput,
) -> ReduceArrowEngineEventsToOrderResult {
    let mut reorder_operations = Vec::new();
    let mut binding_broken_events = Vec::new();
    let mut ordered_element_ids = input.ordered_element_ids.clone();

    for event in &input.events {
        match event {
            ArrowEngineEvent::BindingBroken(event) => binding_broken_events.push(event.clone()),
            ArrowEngineEvent::ReorderArrow(event) => {
                let anchor_lookup = input
                    .anchor_element_ids_by_bindable_id
                    .clone()
                    .unwrap_or_default();
                let anchor_element_ids = anchor_lookup
                    .get(&event.bindable_id)
                    .cloned()
                    .unwrap_or_else(|| vec![event.bindable_id.clone()]);
                let reorder = reorder_arrow_above_elements(&ReorderArrowAboveElementsInput {
                    ordered_element_ids: ordered_element_ids.clone(),
                    arrow_id: event.arrow_id.clone(),
                    anchor_element_ids,
                });
                ordered_element_ids = reorder.ordered_element_ids.clone();
                reorder_operations.push(reorder);
            }
        }
    }

    let moved = reorder_operations.iter().any(|result| result.moved);
    ReduceArrowEngineEventsToOrderResult {
        ordered_element_ids,
        moved,
        reorder_operations,
        binding_broken_events,
    }
}

pub fn apply_engine_result(input: &ApplyEngineResultInput) -> ApplyEngineResultValue {
    let arrow = apply_arrow_patch(&input.arrow, &input.result.arrow_patch);
    let relation_patches = reduce_bindable_patches_to_relation_patches(
        &input.bindables,
        &input.result.bindable_patches,
    );
    let bindables = apply_bindable_relation_patches(&input.bindables, &relation_patches);
    let order = input
        .ordered_element_ids
        .as_ref()
        .and_then(|ordered_element_ids| {
            let reduced =
                reduce_arrow_engine_events_to_order(&ReduceArrowEngineEventsToOrderInput {
                    ordered_element_ids: ordered_element_ids.clone(),
                    events: input.result.events.clone(),
                    anchor_element_ids_by_bindable_id: input
                        .anchor_element_ids_by_bindable_id
                        .clone(),
                });
            reduced.moved.then_some(reduced)
        });

    ApplyEngineResultValue {
        arrow,
        bindables,
        relation_patches,
        ordered_element_ids: order
            .as_ref()
            .map(|value| value.ordered_element_ids.clone()),
        order_changed: order.as_ref().map(|value| value.moved),
        reorder_operations: order.as_ref().map(|value| value.reorder_operations.clone()),
        binding_broken_events: order
            .as_ref()
            .map(|value| value.binding_broken_events.clone()),
    }
}

fn read_binding_state_binding(value: &Value) -> Option<super::arrow_types::FixedPointBinding> {
    let value = value.as_object()?;
    let fixed_point = value.get("fixedPoint")?.as_array()?;
    Some(super::arrow_types::FixedPointBinding {
        element_id: value.get("elementId")?.as_str()?.to_string(),
        fixed_point: crate::draw::types::draw_point::DrawPoint::new(
            fixed_point.first().and_then(Value::as_f64)?,
            fixed_point.get(1).and_then(Value::as_f64)?,
        ),
        mode: value
            .get("mode")
            .and_then(Value::as_str)
            .unwrap_or("orbit")
            .to_string(),
    })
}
