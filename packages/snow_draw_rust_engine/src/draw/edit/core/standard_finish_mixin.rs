#![allow(dead_code)]

use std::collections::HashMap;

use crate::draw::edit::apply::edit_apply::EditApply;
use crate::draw::edit::preview::edit_preview::{build_selection_preview, EditPreview};
use crate::draw::models::application_state::SelectionOverlayState;
use crate::draw::models::draw_state::{DomainState, DrawState};
use crate::draw::models::element_state::ElementState;
use crate::draw::types::edit_context::EditContext;
use crate::draw::types::edit_transform::EditTransform;

use super::edit_computed_result::EditComputedResult;
use super::edit_operation::EditOperation;

/// Shared finish/preview behavior for standard edit operations.
///
/// Rust does not support Dart-style mixins, so this trait provides the same
/// reusable workflow that operations can delegate to from their
/// [`EditOperation::finish`] and [`EditOperation::build_preview`] implementations.
pub trait StandardFinishMixin: EditOperation {
    /// Computes the geometry result for this operation.
    ///
    /// Returns `None` when the transform is identity or validation fails.
    fn compute_result(
        &self,
        state: &DrawState,
        context: &EditContext,
        transform: &EditTransform,
    ) -> Option<EditComputedResult>;

    /// Computes the geometry result specifically for commit.
    ///
    /// Override when commit output differs from preview output.
    fn compute_finish_result(
        &self,
        state: &DrawState,
        context: &EditContext,
        transform: &EditTransform,
    ) -> Option<EditComputedResult> {
        self.compute_result(state, context, transform)
    }

    /// Returns the updated overlay after committing.
    ///
    /// Called only for multi-select contexts.
    fn update_overlay(
        &self,
        current: SelectionOverlayState,
        result: &EditComputedResult,
        context: &EditContext,
    ) -> SelectionOverlayState;

    /// Applies computed element updates to domain state.
    fn apply_result_to_domain(
        &self,
        state: &DrawState,
        result: &EditComputedResult,
    ) -> DomainState {
        if result.updated_elements.is_empty() {
            return state.domain.clone();
        }

        let next_elements = EditApply::replace_elements_by_id(
            state.domain.document.elements.clone(),
            &result.updated_elements,
        );
        let next_elements = EditApply::reorder_elements_by_id_order(
            next_elements,
            result.ordered_element_ids.as_deref(),
        );
        let next_document = state
            .domain
            .document
            .copy_with(Some(next_elements), None, None);
        state.domain.copy_with(Some(next_document), None)
    }

    /// Shared commit flow equivalent to Dart `StandardFinishMixin.finish`.
    fn finish_standard(
        &self,
        state: &DrawState,
        context: &EditContext,
        transform: &EditTransform,
    ) -> DrawState {
        let application = state.application.to_idle();
        let result = self.compute_finish_result(state, context, transform);

        let Some(result) = result else {
            return state.copy_with(None, Some(application));
        };

        let overlay = if context.is_multi_select() {
            self.update_overlay(application.selection_overlay.clone(), &result, context)
        } else {
            application.selection_overlay.clone()
        };

        let domain = self.apply_result_to_domain(state, &result);
        let application = application.copy_with(None, None, Some(overlay));

        state.copy_with(Some(domain), Some(application))
    }

    /// Shared preview flow equivalent to Dart `StandardFinishMixin.buildPreview`.
    fn build_preview_standard(
        &self,
        state: &DrawState,
        context: &EditContext,
        transform: &EditTransform,
    ) -> EditPreview {
        let result = self.compute_result(state, context, transform);

        let Some(result) = result else {
            return EditPreview::default();
        };

        self.build_preview_from_result(state, context, &result)
    }

    /// Converts a computed result into an `EditPreview`.
    ///
    /// Override this when the concrete preview type is fully translated.
    fn build_preview_from_result(
        &self,
        state: &DrawState,
        context: &EditContext,
        result: &EditComputedResult,
    ) -> EditPreview {
        build_edit_preview(
            state,
            context,
            &result.updated_elements,
            result.multi_select_bounds,
            result.multi_select_rotation,
        )
    }
}

/// Builds an `EditPreview` from computed preview inputs.
pub fn build_edit_preview(
    state: &DrawState,
    context: &EditContext,
    preview_elements_by_id: &HashMap<String, ElementState>,
    multi_select_bounds: Option<crate::draw::types::draw_rect::DrawRect>,
    multi_select_rotation: Option<f64>,
) -> EditPreview {
    let selection_preview = build_selection_preview(
        state,
        context,
        preview_elements_by_id,
        multi_select_bounds,
        multi_select_rotation,
    );

    EditPreview::new(preview_elements_by_id.clone(), selection_preview)
}
