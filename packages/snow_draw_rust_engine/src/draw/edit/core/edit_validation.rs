#![allow(dead_code)]

use crate::draw::types::draw_rect::DrawRect;
use crate::draw::types::edit_context::EditContextLike;
use crate::draw::types::edit_transform::EditTransform;

/// Shared validation rules for edit operations.
///
/// Keeping this logic centralized reduces duplication and avoids subtle
/// inconsistencies across operations.
pub struct EditValidation;

impl EditValidation {
    /// Returns true when the edit context is usable for compute.
    pub fn is_valid_context<C>(context: &C) -> bool
    where
        C: EditContextLike + ?Sized,
    {
        !context.base().selected_ids_at_start.is_empty() && context.has_snapshots()
    }

    /// Returns true when selection bounds have non-zero area.
    pub fn is_valid_bounds(bounds: DrawRect) -> bool {
        bounds.width() > 0.0 && bounds.height() > 0.0
    }

    /// Whether the compute pipeline should short-circuit and return `None`.
    ///
    /// Combines context/bounds validation with the identity-transform check
    /// that standard edit operations typically perform.
    pub fn should_skip_compute<C>(
        context: &C,
        transform: &EditTransform,
        require_valid_bounds: bool,
    ) -> bool
    where
        C: EditContextLike + ?Sized,
    {
        !Self::is_valid_context(context)
            || (require_valid_bounds && !Self::is_valid_bounds(context.base().start_bounds))
            || transform.is_identity()
    }

    /// Convenience variant of [`Self::should_skip_compute`] with
    /// `require_valid_bounds = true`.
    pub fn should_skip_compute_with_default_bounds<C>(
        context: &C,
        transform: &EditTransform,
    ) -> bool
    where
        C: EditContextLike + ?Sized,
    {
        Self::should_skip_compute(context, transform, true)
    }
}
