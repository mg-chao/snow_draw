#![allow(dead_code)]

use std::collections::HashMap;

use super::arrow_hit_test::get_hovered_bindable;
use super::arrow_types::{
    BindableState, ReorderArrowAboveElementsInput, ReorderArrowAboveElementsResult,
    ReorderArrowAboveHoveredBindableInput, ReorderArrowAboveHoveredBindableResult,
};

fn unchanged_result(ordered_element_ids: &[String]) -> ReorderArrowAboveElementsResult {
    ReorderArrowAboveElementsResult {
        ordered_element_ids: ordered_element_ids.to_vec(),
        moved: false,
        from_index: -1,
        to_index: -1,
    }
}

fn hovered_unchanged_result(
    ordered_element_ids: &[String],
    hovered_bindable_id: Option<String>,
    anchor_element_ids: Vec<String>,
) -> ReorderArrowAboveHoveredBindableResult {
    ReorderArrowAboveHoveredBindableResult {
        ordered_element_ids: ordered_element_ids.to_vec(),
        moved: false,
        from_index: -1,
        to_index: -1,
        hovered_bindable_id,
        anchor_element_ids,
    }
}

pub fn reorder_arrow_above_elements(
    input: &ReorderArrowAboveElementsInput,
) -> ReorderArrowAboveElementsResult {
    if input.ordered_element_ids.is_empty() || input.anchor_element_ids.is_empty() {
        return unchanged_result(&input.ordered_element_ids);
    }

    let Some(from_index) = input
        .ordered_element_ids
        .iter()
        .position(|id| id == &input.arrow_id)
    else {
        return unchanged_result(&input.ordered_element_ids);
    };

    let Some(to_index) = input
        .ordered_element_ids
        .iter()
        .position(|id| input.anchor_element_ids.iter().any(|anchor| anchor == id))
    else {
        return unchanged_result(&input.ordered_element_ids);
    };

    if from_index >= to_index {
        return unchanged_result(&input.ordered_element_ids);
    }

    let mut ordered = input.ordered_element_ids.clone();
    let arrow_id = ordered.remove(from_index);
    ordered.insert(to_index, arrow_id);

    ReorderArrowAboveElementsResult {
        ordered_element_ids: ordered,
        moved: true,
        from_index: from_index as isize,
        to_index: to_index as isize,
    }
}

pub fn reorder_arrow_above_hovered_bindable(
    input: &ReorderArrowAboveHoveredBindableInput,
) -> ReorderArrowAboveHoveredBindableResult {
    let hovered_bindable_id = input.hovered_bindable_id.clone().or_else(|| {
        input.point.and_then(|point| {
            input.bindables.as_ref().and_then(|bindables| {
                get_hovered_bindable(point, bindables, input.tolerance.unwrap_or(0.0))
                    .map(|bindable| bindable.id.clone())
            })
        })
    });

    let Some(hovered_bindable_id) = hovered_bindable_id else {
        return hovered_unchanged_result(&input.ordered_element_ids, None, Vec::new());
    };

    let anchor_lookup = input
        .anchor_element_ids_by_bindable_id
        .clone()
        .unwrap_or_else(HashMap::new);
    let anchor_element_ids = anchor_lookup
        .get(&hovered_bindable_id)
        .cloned()
        .unwrap_or_else(|| vec![hovered_bindable_id.clone()]);

    let reorder = reorder_arrow_above_elements(&ReorderArrowAboveElementsInput {
        ordered_element_ids: input.ordered_element_ids.clone(),
        arrow_id: input.arrow_id.clone(),
        anchor_element_ids: anchor_element_ids.clone(),
    });

    ReorderArrowAboveHoveredBindableResult {
        ordered_element_ids: reorder.ordered_element_ids,
        moved: reorder.moved,
        from_index: reorder.from_index,
        to_index: reorder.to_index,
        hovered_bindable_id: Some(hovered_bindable_id),
        anchor_element_ids,
    }
}

pub fn reordered_element_ids_from_hovered_reorder(
    result: &ReorderArrowAboveHoveredBindableResult,
) -> Option<Vec<String>> {
    result.moved.then(|| result.ordered_element_ids.clone())
}

pub fn did_engine_result_reorder(order_changed: Option<bool>) -> bool {
    order_changed.unwrap_or(false)
}

pub fn sort_bindables_by_z_index(bindables: &[BindableState]) -> Vec<BindableState> {
    let mut sorted = bindables.to_vec();
    sorted.sort_by(|left, right| {
        left.z_index
            .partial_cmp(&right.z_index)
            .unwrap_or(std::cmp::Ordering::Equal)
    });
    sorted
}
