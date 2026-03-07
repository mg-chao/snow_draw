#![allow(dead_code)]

use std::collections::HashMap;
use std::sync::Arc;

use crate::draw::elements::core::element_data::ElementData as CoreElementData;
use crate::draw::elements::types::arrow::arrow_core::ArrowState as CoreArrowState;
use crate::draw::elements::types::arrow::arrow_core_bridge::{
    apply_core_arrow_patches_to_sources, collect_core_arrow_states_with_sources,
    is_arrow_bindable_element, ConnectorSourceData,
};
use crate::draw::elements::types::arrow::arrow_data::{
    ArrowBinding, ArrowData, ArrowDataPatch, NullableField as ArrowNullableField,
};
use crate::draw::elements::types::arrow::arrow_layout::resolve_arrow_geometry_update;
use crate::draw::elements::types::arrow::arrow_scene::ArrowScene;
use crate::draw::elements::types::arrow::core::arrow_binding_lifecycle::sync_bindings_after_bindable_prune as sync_core_bindings_after_bindable_prune;
use crate::draw::elements::types::arrow::core::arrow_types::{
    ArrowState as LifecycleArrowState, FixedPointBinding, FixedSegment,
};
use crate::draw::elements::types::arrow::elbow::elbow_editing::{
    compute_elbow_edit, transform_fixed_segments, BindingOverride,
};
use crate::draw::models::element_state::ElementState;
use crate::draw::types::element_style::ArrowType;
use crate::draw::utils::combined_element_lookup::CombinedElementLookup;

/// Prunes bindings for transformed arrow-like elements.
///
/// This mirrors Dart `_pruneTransformedArrowBindings(...)`: when an edit
/// transforms both an arrow and one of its bound bindables, the binding is
/// retained. Only bindings that now point outside the transformed bindable set
/// are cleared before the normal binding-recompute pass runs.
pub fn unbind_arrow_like_elements(
    transformed_elements: &HashMap<String, ElementState>,
    base_elements: &HashMap<String, ElementState>,
) -> HashMap<String, ElementState> {
    if transformed_elements.is_empty() {
        return HashMap::new();
    }

    let (transformed_arrows, arrow_sources) = collect_core_arrow_states_with_sources(
        &transformed_elements.values().cloned().collect::<Vec<_>>(),
        true,
    );
    if transformed_arrows.is_empty() {
        return HashMap::new();
    }

    let lookup = CombinedElementLookup::new(base_elements, transformed_elements);
    let retained_bindable_ids = transformed_elements
        .keys()
        .filter(|id| {
            lookup
                .get(id.as_str())
                .is_some_and(is_arrow_bindable_element)
        })
        .cloned()
        .collect::<Vec<_>>();

    let session = ArrowScene::from_elements(lookup.values().cloned().collect::<Vec<_>>(), None);
    let sync_result = sync_core_bindings_after_bindable_prune(
        &transformed_arrows
            .iter()
            .map(to_lifecycle_arrow_state)
            .collect::<Vec<_>>(),
        session.bindable_relations(),
        &retained_bindable_ids,
        true,
        true,
    );
    if sync_result.arrow_patches.is_empty() {
        return HashMap::new();
    }

    let mut patched_by_id =
        apply_core_arrow_patches_to_sources(&sync_result.arrow_patches, &arrow_sources);
    for arrow_patch in &sync_result.arrow_patches {
        let Some((element, ConnectorSourceData::Arrow(data))) = arrow_sources.get(&arrow_patch.id)
        else {
            continue;
        };
        if data.arrow_type != ArrowType::Elbow {
            continue;
        }
        let Some(patched_element) = patched_by_id.get(&arrow_patch.id) else {
            continue;
        };
        let Ok(patched_data) = ArrowData::from_json(&patched_element.data.to_json()) else {
            continue;
        };
        let resolved = recompute_pruned_elbow_arrow(element, data, &patched_data, &lookup);
        patched_by_id.insert(resolved.id.clone(), resolved);
    }

    patched_by_id
}

fn recompute_pruned_elbow_arrow(
    element: &ElementState,
    original_data: &ArrowData,
    pruned_data: &ArrowData,
    lookup: &CombinedElementLookup<'_, ElementState>,
) -> ElementState {
    let elbow_edit = compute_elbow_edit(
        element,
        original_data,
        lookup,
        None,
        None,
        binding_override(
            original_data.start_binding.as_ref(),
            pruned_data.start_binding.as_ref(),
        ),
        binding_override(
            original_data.end_binding.as_ref(),
            pruned_data.end_binding.as_ref(),
        ),
        true,
    );
    let geometry = resolve_arrow_geometry_update(
        &elbow_edit.local_points,
        element.rect,
        element.rotation,
        original_data.arrow_type,
    );
    let transformed_fixed_segments = transform_fixed_segments(
        elbow_edit.fixed_segments.as_deref(),
        element.rect,
        geometry.rect,
        element.rotation,
    );
    let updated_data = original_data.copy_with(ArrowDataPatch {
        points: Some(geometry.normalized_points),
        start_binding: elbow_edit
            .start_binding
            .map(ArrowNullableField::Value)
            .unwrap_or(ArrowNullableField::Null),
        end_binding: elbow_edit
            .end_binding
            .map(ArrowNullableField::Value)
            .unwrap_or(ArrowNullableField::Null),
        fixed_segments: transformed_fixed_segments
            .map(ArrowNullableField::Value)
            .unwrap_or(ArrowNullableField::Null),
        start_is_special: elbow_edit
            .start_is_special
            .map(ArrowNullableField::Value)
            .unwrap_or(ArrowNullableField::Null),
        end_is_special: elbow_edit
            .end_is_special
            .map(ArrowNullableField::Value)
            .unwrap_or(ArrowNullableField::Null),
        ..ArrowDataPatch::default()
    });

    element.copy_with(
        None,
        Some(geometry.rect),
        None,
        None,
        None,
        Some(arc_element_data(updated_data)),
    )
}

fn binding_override(
    previous_binding: Option<&ArrowBinding>,
    next_binding: Option<&ArrowBinding>,
) -> BindingOverride<ArrowBinding> {
    match next_binding {
        Some(binding) if previous_binding != Some(binding) => {
            BindingOverride::Value(binding.clone())
        }
        None if previous_binding.is_some() => BindingOverride::Clear,
        _ => BindingOverride::Unset,
    }
}

fn arc_element_data<T>(data: T) -> Arc<dyn CoreElementData>
where
    T: CoreElementData + 'static,
{
    Arc::new(data)
}

fn to_lifecycle_arrow_state(arrow: &CoreArrowState) -> LifecycleArrowState {
    LifecycleArrowState {
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
) -> FixedPointBinding {
    FixedPointBinding::new(
        binding.element_id.clone(),
        binding.anchor,
        binding.mode.as_str().to_string(),
    )
}

fn to_lifecycle_fixed_segment(
    segment: crate::draw::elements::types::arrow::arrow_data::ElbowFixedSegment,
) -> FixedSegment {
    FixedSegment {
        start: segment.start,
        end: segment.end,
        index: segment.index,
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::draw::elements::types::arrow::arrow_data::{
        ArrowBinding, ArrowBindingMode, ArrowData, ArrowDataPatch, NullableField,
    };
    use crate::draw::elements::types::rectangle::rectangle_data::RectangleData;
    use crate::draw::types::draw_point::DrawPoint;
    use crate::draw::types::draw_rect::DrawRect;
    use std::sync::Arc;

    fn rectangle_element(id: &str, rect: DrawRect, z_index: i64) -> ElementState {
        ElementState::new(
            id.to_owned(),
            rect,
            0.0,
            1.0,
            z_index,
            Arc::new(RectangleData::default()),
        )
    }

    fn arrow_element(id: &str, rect: DrawRect, binding_id: &str, z_index: i64) -> ElementState {
        let data = ArrowData::default().copy_with(ArrowDataPatch {
            start_binding: NullableField::Value(ArrowBinding::new(
                binding_id,
                DrawPoint::new(0.0, 0.0),
                ArrowBindingMode::Orbit,
            )),
            ..ArrowDataPatch::default()
        });
        ElementState::new(id.to_owned(), rect, 0.0, 1.0, z_index, Arc::new(data))
    }

    fn decode_arrow_data(element: &ElementState) -> ArrowData {
        ArrowData::from_json(&element.data.to_json()).expect("arrow data should decode")
    }

    #[test]
    fn keeps_binding_when_transformed_bindable_is_retained() {
        let bindable = rectangle_element("rect", DrawRect::new(0.0, 0.0, 100.0, 100.0), 0);
        let arrow = arrow_element("arrow", DrawRect::new(10.0, 10.0, 80.0, 20.0), "rect", 1);

        let mut base = HashMap::new();
        base.insert(bindable.id.clone(), bindable.clone());
        base.insert(arrow.id.clone(), arrow.clone());

        let moved_bindable = bindable.copy_with(
            None,
            Some(DrawRect::new(20.0, 20.0, 120.0, 120.0)),
            None,
            None,
            None,
            None,
        );

        let mut transformed = HashMap::new();
        transformed.insert(moved_bindable.id.clone(), moved_bindable);
        transformed.insert(arrow.id.clone(), arrow);

        let updates = unbind_arrow_like_elements(&transformed, &base);

        assert!(updates.is_empty());
    }

    #[test]
    fn clears_binding_when_transformed_arrow_target_is_not_retained() {
        let bindable = rectangle_element("rect", DrawRect::new(0.0, 0.0, 100.0, 100.0), 0);
        let arrow = arrow_element("arrow", DrawRect::new(10.0, 10.0, 80.0, 20.0), "rect", 1);

        let mut base = HashMap::new();
        base.insert(bindable.id.clone(), bindable);
        base.insert(arrow.id.clone(), arrow.clone());

        let mut transformed = HashMap::new();
        transformed.insert(arrow.id.clone(), arrow);

        let updates = unbind_arrow_like_elements(&transformed, &base);
        let updated_arrow = updates
            .get("arrow")
            .expect("transformed arrow should receive a prune update");
        let data = decode_arrow_data(updated_arrow);

        assert!(data.start_binding.is_none());
    }
}
