#![allow(dead_code)]

use std::any::{type_name, Any};
use std::collections::{HashMap, HashSet};

use crate::draw::edit::core::edit_errors::{
    EditContextTypeMismatchError, EditMissingDataError, EditParamsTypeMismatchError,
    EditTransformTypeMismatchError,
};
use crate::draw::models::draw_state::DrawState;
use crate::draw::models::element_state::ElementState;
use crate::draw::models::selection_derived_data::SelectionDerivedData;
use crate::draw::types::draw_point::DrawPoint;
use crate::draw::types::draw_rect::DrawRect;
use crate::draw::types::edit_context::{
    EditContext, MoveEditContext, ResizeEditContext, RotateEditContext,
};
use crate::draw::types::edit_transform::{
    ArrowPointTransform, EditTransform, MoveTransform, ResizeTransform, RotateTransform,
};
use crate::draw::types::element_geometry::{
    ElementMoveSnapshot, ElementResizeSnapshot, ElementRotateSnapshot,
};
use crate::draw::utils::visible_elements::resolve_visible_elements;

/// Lightweight preview of selection geometry during an edit session.
#[derive(Clone, Debug, PartialEq)]
pub struct SelectionPreview {
    pub bounds: DrawRect,
    pub center: DrawPoint,
    pub rotation: Option<f64>,
}

/// Preview payload produced by edit operations.
#[derive(Clone, Debug, Default, PartialEq)]
pub struct EditPreview {
    pub preview_elements_by_id: HashMap<String, ElementState>,
    pub selection_preview: Option<SelectionPreview>,
}

impl EditPreview {
    /// Returns an empty preview payload.
    pub fn none() -> Self {
        Self::default()
    }
}

/// Common operation-parameter marker.
///
/// The dedicated operation-params module is translated separately; this trait
/// keeps helper APIs usable in the meantime.
pub trait EditOperationParams: Any {
    fn initial_selection_bounds(&self) -> Option<DrawRect> {
        None
    }
}

/// Returns a snapshot of selected elements.
pub fn snapshot_selected_elements(state: &DrawState) -> Vec<ElementState> {
    state
        .domain
        .selection
        .selected_ids
        .iter()
        .filter_map(|id| state.domain.document.get_element_by_id(id).cloned())
        .collect()
}

/// Resolves required selection bounds for an operation.
pub fn require_selection_bounds(
    selection_data: &SelectionDerivedData,
    operation_name: &str,
    initial_selection_bounds: Option<DrawRect>,
) -> Result<DrawRect, EditMissingDataError> {
    initial_selection_bounds
        .or(selection_data.overlay_bounds)
        .or(selection_data.selection_bounds)
        .ok_or_else(|| {
            EditMissingDataError::new("selection bounds", Some(operation_name.to_owned()))
        })
}

/// Builds the full edit preview payload.
pub fn build_edit_preview(
    state: &DrawState,
    context: &EditContext,
    preview_elements_by_id: HashMap<String, ElementState>,
    multi_select_bounds: Option<DrawRect>,
    multi_select_rotation: Option<f64>,
) -> EditPreview {
    let selection_preview = build_selection_preview(
        state,
        context,
        &preview_elements_by_id,
        multi_select_bounds,
        multi_select_rotation,
    );

    EditPreview {
        preview_elements_by_id,
        selection_preview,
    }
}

/// Builds selection-preview geometry from preview element overrides.
pub fn build_selection_preview(
    _state: &DrawState,
    context: &EditContext,
    preview_elements_by_id: &HashMap<String, ElementState>,
    multi_select_bounds: Option<DrawRect>,
    multi_select_rotation: Option<f64>,
) -> Option<SelectionPreview> {
    if context.selected_ids_at_start.is_empty() {
        return None;
    }

    let selected_preview_elements = context
        .selected_ids_at_start
        .iter()
        .filter_map(|id| preview_elements_by_id.get(id))
        .collect::<Vec<_>>();

    if selected_preview_elements.is_empty() {
        let bounds = multi_select_bounds.unwrap_or(context.start_bounds);
        return Some(SelectionPreview {
            bounds,
            center: bounds.center(),
            rotation: multi_select_rotation,
        });
    }

    let computed_bounds = merge_element_world_bounds(&selected_preview_elements)?;
    let bounds = multi_select_bounds.unwrap_or(computed_bounds);
    let rotation = multi_select_rotation.or_else(|| {
        if selected_preview_elements.len() == 1 {
            Some(selected_preview_elements[0].rotation)
        } else {
            None
        }
    });

    Some(SelectionPreview {
        bounds,
        center: bounds.center(),
        rotation,
    })
}

/// Builds snapshots keyed by element id.
pub fn build_snapshots<S, F>(elements: &[ElementState], mut to_snapshot: F) -> HashMap<String, S>
where
    F: FnMut(&ElementState) -> S,
{
    elements
        .iter()
        .map(|element| (element.id.clone(), to_snapshot(element)))
        .collect()
}

/// Builds move snapshots keyed by element id.
pub fn build_move_snapshots(elements: &[ElementState]) -> HashMap<String, ElementMoveSnapshot> {
    build_snapshots(elements, |element| ElementMoveSnapshot {
        center: element.rect.center(),
    })
}

/// Builds resize snapshots keyed by element id.
pub fn build_resize_snapshots(elements: &[ElementState]) -> HashMap<String, ElementResizeSnapshot> {
    build_snapshots(elements, |element| ElementResizeSnapshot {
        rect: element.rect,
        rotation: element.rotation,
    })
}

/// Builds rotate snapshots keyed by element id.
pub fn build_rotate_snapshots(elements: &[ElementState]) -> HashMap<String, ElementRotateSnapshot> {
    build_snapshots(elements, |element| ElementRotateSnapshot {
        center: element.rect.center(),
        rotation: element.rotation,
    })
}

/// Requires and downcasts `context` to `C`.
pub fn require_context<'a, C: 'static, A: Any>(
    context: &'a A,
    operation_name: &str,
) -> Result<&'a C, EditContextTypeMismatchError> {
    let context_any = context as &dyn Any;
    context_any.downcast_ref::<C>().ok_or_else(|| {
        EditContextTypeMismatchError::new(
            type_name::<C>(),
            context_type_name(context_any),
            operation_name.to_owned(),
            context_additional_info(context_any),
        )
    })
}

/// Variant-ref extraction for concrete transform types.
pub trait TransformRef<'a>: Sized + 'static {
    fn from_edit_transform(transform: &'a EditTransform) -> Option<&'a Self>;
}

impl<'a> TransformRef<'a> for MoveTransform {
    fn from_edit_transform(transform: &'a EditTransform) -> Option<&'a Self> {
        if let EditTransform::Move(value) = transform {
            Some(value)
        } else {
            None
        }
    }
}

impl<'a> TransformRef<'a> for ResizeTransform {
    fn from_edit_transform(transform: &'a EditTransform) -> Option<&'a Self> {
        if let EditTransform::Resize(value) = transform {
            Some(value)
        } else {
            None
        }
    }
}

impl<'a> TransformRef<'a> for RotateTransform {
    fn from_edit_transform(transform: &'a EditTransform) -> Option<&'a Self> {
        if let EditTransform::Rotate(value) = transform {
            Some(value)
        } else {
            None
        }
    }
}

impl<'a> TransformRef<'a> for ArrowPointTransform {
    fn from_edit_transform(transform: &'a EditTransform) -> Option<&'a Self> {
        if let EditTransform::ArrowPoint(value) = transform {
            Some(value)
        } else {
            None
        }
    }
}

/// Requires and extracts the concrete transform variant.
pub fn require_transform<'a, T>(
    transform: &'a EditTransform,
    operation_name: &str,
) -> Result<&'a T, EditTransformTypeMismatchError>
where
    T: TransformRef<'a> + 'static,
{
    T::from_edit_transform(transform).ok_or_else(|| {
        EditTransformTypeMismatchError::new(
            type_name::<T>(),
            transform_type_name(transform),
            operation_name.to_owned(),
            None,
        )
    })
}

/// Requires and downcasts params to `P`.
pub fn require_params<'a, P: 'static, A: Any>(
    params: &'a A,
    operation_name: &str,
) -> Result<&'a P, EditParamsTypeMismatchError> {
    let params_any = params as &dyn Any;
    params_any.downcast_ref::<P>().ok_or_else(|| {
        EditParamsTypeMismatchError::new(
            type_name::<P>(),
            type_name::<A>(),
            operation_name.to_owned(),
            None,
        )
    })
}

/// Returns visible reference elements outside the active selection.
pub fn resolve_reference_elements(
    state: &DrawState,
    selected_ids: &HashSet<String>,
) -> Vec<ElementState> {
    resolve_visible_elements(
        state.domain.document.elements.iter().cloned(),
        Some(selected_ids),
    )
}

/// Common context-creation payload shared by move/resize/rotate operations.
#[derive(Clone, Debug)]
pub struct StandardContextData<S> {
    pub start_bounds: DrawRect,
    pub selected_ids: HashSet<String>,
    pub selection_version: i64,
    pub elements_version: i64,
    pub selected_elements: Vec<ElementState>,
    pub element_snapshots: HashMap<String, S>,
}

/// Gathers common context creation data for standard edit operations.
pub fn gather_standard_context_data<S, F>(
    state: &DrawState,
    operation_name: &str,
    mut to_snapshot: F,
    initial_selection_bounds: Option<DrawRect>,
    selection_data: Option<SelectionDerivedData>,
) -> Result<StandardContextData<S>, EditMissingDataError>
where
    F: FnMut(&ElementState) -> S,
{
    let resolved_selection_data =
        selection_data.unwrap_or_else(|| compute_selection_data_fallback(state));
    let selected_elements = snapshot_selected_elements(state);
    let selected_ids = state
        .domain
        .selection
        .selected_ids
        .iter()
        .cloned()
        .collect::<HashSet<_>>();
    let start_bounds = require_selection_bounds(
        &resolved_selection_data,
        operation_name,
        initial_selection_bounds,
    )?;
    let element_snapshots = selected_elements
        .iter()
        .map(|element| (element.id.clone(), to_snapshot(element)))
        .collect::<HashMap<_, _>>();

    Ok(StandardContextData {
        start_bounds,
        selected_ids,
        selection_version: state.domain.selection.selection_version as i64,
        elements_version: state.domain.document.elements_version,
        selected_elements,
        element_snapshots,
    })
}

fn compute_selection_data_fallback(state: &DrawState) -> SelectionDerivedData {
    let selected_elements = snapshot_selected_elements(state);
    let selection_bounds =
        merge_element_world_bounds(&selected_elements.iter().collect::<Vec<_>>());

    let (selection_rotation, selection_center) = if selected_elements.len() == 1 {
        let element = &selected_elements[0];
        (Some(element.rotation), Some(element.rect.center()))
    } else {
        (None, selection_bounds.map(DrawRect::center))
    };

    SelectionDerivedData::new(
        selected_elements,
        selection_bounds,
        selection_bounds,
        selection_rotation,
        selection_center,
        selection_rotation,
        selection_center,
    )
}

fn merge_element_world_bounds(elements: &[&ElementState]) -> Option<DrawRect> {
    let mut iter = elements.iter();
    let first = iter.next()?;
    let mut bounds = world_aabb_for_element(first);

    for element in iter {
        let aabb = world_aabb_for_element(element);
        bounds = DrawRect::new(
            bounds.min_x.min(aabb.min_x),
            bounds.min_y.min(aabb.min_y),
            bounds.max_x.max(aabb.max_x),
            bounds.max_y.max(aabb.max_y),
        );
    }

    Some(bounds)
}

fn world_aabb_for_element(element: &ElementState) -> DrawRect {
    if element.rotation == 0.0 {
        return element.rect;
    }

    let rect = element.rect;
    let center = rect.center();
    let half_width = rect.width().abs() / 2.0;
    let half_height = rect.height().abs() / 2.0;
    let cos_theta = element.rotation.cos().abs();
    let sin_theta = element.rotation.sin().abs();
    let x_extent = half_width * cos_theta + half_height * sin_theta;
    let y_extent = half_width * sin_theta + half_height * cos_theta;

    DrawRect::new(
        center.x - x_extent,
        center.y - y_extent,
        center.x + x_extent,
        center.y + y_extent,
    )
}

fn context_type_name(context: &dyn Any) -> &'static str {
    if context.is::<EditContext>() {
        type_name::<EditContext>()
    } else if context.is::<MoveEditContext>() {
        type_name::<MoveEditContext>()
    } else if context.is::<ResizeEditContext>() {
        type_name::<ResizeEditContext>()
    } else if context.is::<RotateEditContext>() {
        type_name::<RotateEditContext>()
    } else {
        "unknown_context"
    }
}

fn context_additional_info(context: &dyn Any) -> Option<String> {
    if let Some(value) = context.downcast_ref::<EditContext>() {
        return Some(format_context_info(value));
    }
    if let Some(value) = context.downcast_ref::<MoveEditContext>() {
        return Some(format_context_info(&value.base));
    }
    if let Some(value) = context.downcast_ref::<ResizeEditContext>() {
        return Some(format_context_info(&value.base));
    }
    if let Some(value) = context.downcast_ref::<RotateEditContext>() {
        return Some(format_context_info(&value.base));
    }
    None
}

fn format_context_info(context: &EditContext) -> String {
    format!(
        "startPosition={}, selectedIds={}",
        context.start_position,
        context.selected_ids_at_start.len()
    )
}

fn transform_type_name(transform: &EditTransform) -> &'static str {
    match transform {
        EditTransform::Move(_) => type_name::<MoveTransform>(),
        EditTransform::Resize(_) => type_name::<ResizeTransform>(),
        EditTransform::Rotate(_) => type_name::<RotateTransform>(),
        EditTransform::ArrowPoint(_) => type_name::<ArrowPointTransform>(),
    }
}
