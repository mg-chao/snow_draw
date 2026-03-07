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

pub fn apply_arrow_binding_state_patches(
    arrows: &[ArrowBindingState],
    patches: &[ArrowBindingStatePatch],
) -> Vec<ArrowBindingState> {
    if patches.is_empty() || arrows.is_empty() {
        return arrows.to_vec();
    }

    let patch_by_id = patches
        .iter()
        .filter_map(|patch| {
            patch
                .get("id")
                .and_then(Value::as_str)
                .map(|id| (id.to_owned(), patch))
        })
        .collect::<HashMap<_, _>>();

    arrows
        .iter()
        .map(|arrow| {
            patch_by_id
                .get(&arrow.id)
                .map(|patch| apply_arrow_binding_state_patch(arrow, patch))
                .unwrap_or_else(|| arrow.clone())
        })
        .collect()
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
    let anchor_lookup = input
        .anchor_element_ids_by_bindable_id
        .clone()
        .unwrap_or_default();

    for event in &input.events {
        match event {
            ArrowEngineEvent::BindingBroken(event) => binding_broken_events.push(event.clone()),
            ArrowEngineEvent::ReorderArrow(event) => {
                let anchor_element_ids = anchor_lookup
                    .get(&event.bindable_id)
                    .cloned()
                    .unwrap_or_else(|| vec![event.bindable_id.clone()]);
                let reorder = reorder_arrow_above_elements(&ReorderArrowAboveElementsInput {
                    ordered_element_ids: ordered_element_ids.clone(),
                    arrow_id: event.arrow_id.clone(),
                    anchor_element_ids,
                });
                if reorder.moved {
                    ordered_element_ids = reorder.ordered_element_ids.clone();
                    reorder_operations.push(reorder);
                }
            }
        }
    }

    ReduceArrowEngineEventsToOrderResult {
        ordered_element_ids,
        moved: !reorder_operations.is_empty(),
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
        .map(|ordered_element_ids| {
            reduce_arrow_engine_events_to_order(&ReduceArrowEngineEventsToOrderInput {
                ordered_element_ids: ordered_element_ids.clone(),
                events: input.result.events.clone(),
                anchor_element_ids_by_bindable_id: input.anchor_element_ids_by_bindable_id.clone(),
            })
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

#[cfg(test)]
mod tests {
    use super::*;
    use crate::draw::elements::types::arrow::core::arrow_types::{
        ArrowEndpointEdge, ArrowPatch, ArrowState, EngineResult, FixedPointBinding,
    };
    use crate::draw::types::draw_point::DrawPoint;

    fn arrow_state(id: &str) -> ArrowState {
        ArrowState {
            id: id.to_owned(),
            x: 0.0,
            y: 0.0,
            width: 10.0,
            height: 10.0,
            points: vec![DrawPoint::ZERO, DrawPoint::new(10.0, 10.0)],
            start_binding: None,
            end_binding: None,
            start_arrowhead: Some("none".to_owned()),
            end_arrowhead: Some("none".to_owned()),
            elbowed: false,
            fixed_segments: None,
            start_is_special: None,
            end_is_special: None,
        }
    }

    #[test]
    fn apply_arrow_binding_state_patches_updates_matching_arrows() {
        let arrows = vec![
            ArrowBindingState {
                id: "arrow-1".to_owned(),
                start_binding: None,
                end_binding: None,
            },
            ArrowBindingState {
                id: "arrow-2".to_owned(),
                start_binding: None,
                end_binding: None,
            },
        ];
        let mut patch = ArrowBindingStatePatch::new();
        patch.insert("id".to_owned(), Value::from("arrow-2"));
        patch.insert(
            "startBinding".to_owned(),
            Value::Object(serde_json::Map::from_iter([
                ("elementId".to_owned(), Value::from("rect-1")),
                (
                    "fixedPoint".to_owned(),
                    Value::Array(vec![Value::from(0.25), Value::from(0.75)]),
                ),
                ("mode".to_owned(), Value::from("orbit")),
            ])),
        );

        let updated = apply_arrow_binding_state_patches(&arrows, &[patch]);

        assert_eq!(updated[0], arrows[0]);
        assert_eq!(
            updated[1].start_binding,
            Some(FixedPointBinding {
                element_id: "rect-1".to_owned(),
                fixed_point: DrawPoint::new(0.25, 0.75),
                mode: "orbit".to_owned(),
            })
        );
    }

    #[test]
    fn reduce_arrow_engine_events_to_order_skips_noop_reorders() {
        let result = reduce_arrow_engine_events_to_order(&ReduceArrowEngineEventsToOrderInput {
            ordered_element_ids: vec!["rect-1".to_owned(), "arrow-1".to_owned()],
            events: vec![ArrowEngineEvent::ReorderArrow(
                super::super::arrow_types::ReorderArrowEvent {
                    arrow_id: "arrow-1".to_owned(),
                    bindable_id: "rect-1".to_owned(),
                },
            )],
            anchor_element_ids_by_bindable_id: None,
        });

        assert!(!result.moved);
        assert!(result.reorder_operations.is_empty());
        assert_eq!(
            result.ordered_element_ids,
            vec!["rect-1".to_owned(), "arrow-1".to_owned()]
        );
    }

    #[test]
    fn apply_engine_result_preserves_order_metadata_without_reorder_move() {
        let broken = BindingBrokenEvent {
            arrow_id: "arrow-1".to_owned(),
            edge: ArrowEndpointEdge::Start,
        };
        let result = apply_engine_result(&ApplyEngineResultInput {
            arrow: arrow_state("arrow-1"),
            bindables: Vec::new(),
            result: EngineResult {
                arrow_patch: ArrowPatch::new(),
                bindable_patches: Vec::new(),
                suggested_binding: None,
                events: vec![ArrowEngineEvent::BindingBroken(broken.clone())],
            },
            ordered_element_ids: Some(vec!["rect-1".to_owned(), "arrow-1".to_owned()]),
            anchor_element_ids_by_bindable_id: None,
        });

        assert_eq!(
            result.ordered_element_ids,
            Some(vec!["rect-1".to_owned(), "arrow-1".to_owned()])
        );
        assert_eq!(result.order_changed, Some(false));
        assert_eq!(result.reorder_operations, Some(Vec::new()));
        assert_eq!(result.binding_broken_events, Some(vec![broken]));
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
