#![allow(dead_code)]

use std::collections::HashMap;
use std::collections::HashSet;
use std::fmt;
use std::sync::{Arc, Mutex};

use crate::draw::config::draw_config::DrawConfig;
use crate::draw::edit::arrow::arrow_point_operation::{
    ArrowBindingCandidate, ArrowPointBindingLookup, ArrowPointBindingRequest,
    ArrowPointEditContext, ArrowPointKind as OperationArrowPointKind, ArrowPointOperation,
    ArrowPointTransform as InternalArrowPointTransform, ArrowPointUpdateOptions,
};
use crate::draw::edit::core::edit_computed_result::EditComputedResult;
use crate::draw::edit::core::edit_operation_params::{
    ArrowPointOperationParams as TypedArrowPointOperationParams,
    MoveOperationParams as TypedMoveOperationParams,
    RotateOperationParams as TypedRotateOperationParams,
};
use crate::draw::edit::core::standard_finish_mixin::build_edit_preview;
use crate::draw::edit::r#move::move_operation::MoveOperation;
use crate::draw::edit::resize::resize_operation::ResizeOperation;
use crate::draw::edit::rotate::rotate_operation::RotateOperation;
use crate::draw::elements::core::element_data::ElementData as CoreElementData;
use crate::draw::elements::types::arrow::arrow_binding::{
    ArrowBinding as CompatArrowBinding, ArrowBindingMode as CompatArrowBindingMode,
    ArrowBindingUtils,
};
use crate::draw::elements::types::arrow::arrow_binding_snapper::{
    ArrowBindingCachePolicy, ArrowBindingResolver as SnapperBindingResolver, ArrowBindingSnapper,
    ArrowBindingTargetCache as SnapperTargetCache,
};
use crate::draw::elements::types::arrow::arrow_data::{
    ArrowBinding as ArrowDataBinding, ArrowBindingMode as ArrowDataBindingMode, ArrowData,
    ArrowDataPatch, ElbowFixedSegment as ArrowDataElbowFixedSegment,
    NullableField as ArrowDataNullableField,
};
use crate::draw::elements::types::arrow::arrow_geometry::ArrowGeometry;
use crate::draw::elements::types::arrow::arrow_layout::resolve_arrow_geometry_update;
use crate::draw::elements::types::arrow::arrow_like_data::NullableField as ArrowLikeNullableField;
use crate::draw::elements::types::arrow::arrow_two_point_layout::compute_arrow_two_point_layout;
use crate::draw::elements::types::arrow::elbow::elbow_editing::{
    compute_elbow_edit, transform_fixed_segments, BindingOverride as ElbowBindingOverride,
};
use crate::draw::elements::types::arrow::elbow::elbow_fixed_segment::ElbowFixedSegment as CompatElbowFixedSegment;
use crate::draw::elements::types::line::line_data::{LineData, LineDataPatch};
use crate::draw::models::draw_state::DrawState;
use crate::draw::models::element_state::ElementState as DomainElementState;
use crate::draw::models::multi_select_lifecycle::MultiSelectOverlayState;
use crate::draw::types::draw_point::DrawPoint;
use crate::draw::types::draw_rect::DrawRect;
use crate::draw::types::edit_context::{EditContext, MoveEditContext, RotateEditContext};
use crate::draw::types::edit_operation_id::{EditOperationId, EditOperationIds};
use crate::draw::types::edit_transform::{ArrowPointTransform, EditTransform};
use crate::draw::types::element_style::{ArrowType, ArrowheadStyle};
use crate::draw::utils::combined_element_lookup::CombinedElementLookup;
use crate::draw::utils::snapping_mode::{resolve_effective_snapping_mode_for_config, SnappingMode};

use super::core::edit_modifiers::EditModifiers;
use super::core::edit_operation::{
    EditOperation, EditOperationParams, EditPreview, EditUpdateResult,
};

/// Shared handle for registered operations.
pub type SharedEditOperation = Arc<dyn EditOperation>;

/// Registry of configured edit operations.
///
/// Mirrors `DefaultEditOperationRegistry` from the Dart engine.
#[derive(Clone)]
pub struct DefaultEditOperationRegistry {
    operations: HashMap<EditOperationId, SharedEditOperation>,
    operation_order: Vec<EditOperationId>,
}

impl DefaultEditOperationRegistry {
    /// Built-in operation ids used by [`Self::with_defaults`].
    pub const DEFAULT_OPERATION_IDS: [EditOperationId; 4] = [
        EditOperationIds::MOVE,
        EditOperationIds::ARROW_POINT,
        EditOperationIds::RESIZE,
        EditOperationIds::ROTATE,
    ];

    fn from_ordered_parts(
        operations: HashMap<EditOperationId, SharedEditOperation>,
        operation_order: Vec<EditOperationId>,
    ) -> Self {
        Self {
            operations,
            operation_order,
        }
    }

    /// Creates a registry with the built-in operation set.
    pub fn with_defaults() -> Self {
        Self::custom(Self::default_operations())
    }

    /// Creates a registry from explicit operation instances.
    ///
    /// For duplicate ids, the last operation wins.
    pub fn custom<I>(operations: I) -> Self
    where
        I: IntoIterator<Item = SharedEditOperation>,
    {
        let mut map = HashMap::new();
        let mut order = Vec::new();
        for operation in operations {
            let operation_id = operation.id();
            if map.insert(operation_id, operation).is_some() {
                if let Some(index) = order.iter().position(|value| *value == operation_id) {
                    order.remove(index);
                }
            }
            order.push(operation_id);
        }
        Self::from_ordered_parts(map, order)
    }

    /// Creates an empty registry.
    pub fn empty() -> Self {
        Self::from_ordered_parts(HashMap::new(), Vec::new())
    }

    /// Default operation set (reused by tests and extension points).
    pub fn default_operations() -> Vec<SharedEditOperation> {
        vec![
            Arc::new(MoveEditOperationAdapter::new()),
            Arc::new(ArrowPointEditOperationAdapter::new()),
            Arc::new(ResizeOperation::new()),
            Arc::new(RotateEditOperationAdapter::new()),
        ]
    }

    pub fn get_operation(&self, operation_id: EditOperationId) -> Option<&SharedEditOperation> {
        self.operations.get(&operation_id)
    }

    pub fn all_operations(&self) -> impl Iterator<Item = &SharedEditOperation> {
        self.operation_order
            .iter()
            .filter_map(|operation_id| self.operations.get(operation_id))
    }

    pub fn all_operation_ids(&self) -> impl Iterator<Item = EditOperationId> + '_ {
        self.operation_order.iter().copied()
    }

    pub fn has_operation(&self, operation_id: EditOperationId) -> bool {
        self.operations.contains_key(operation_id)
    }

    pub fn operation_count(&self) -> usize {
        self.operations.len()
    }
}

impl Default for DefaultEditOperationRegistry {
    fn default() -> Self {
        Self::with_defaults()
    }
}

impl fmt::Debug for DefaultEditOperationRegistry {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        let operation_ids = self.operation_order.clone();
        f.debug_struct("DefaultEditOperationRegistry")
            .field("operation_ids", &operation_ids)
            .finish()
    }
}

#[derive(Clone, Debug, PartialEq)]
struct EditContextFingerprint {
    start_position: DrawPoint,
    start_bounds: DrawRect,
    selected_ids_at_start: HashSet<String>,
    selection_version: i64,
    elements_version: i64,
}

impl EditContextFingerprint {
    fn from_context(context: &EditContext) -> Self {
        Self {
            start_position: context.start_position,
            start_bounds: context.start_bounds,
            selected_ids_at_start: context.selected_ids_at_start.clone(),
            selection_version: context.selection_version,
            elements_version: context.elements_version,
        }
    }

    fn matches(&self, context: &EditContext) -> bool {
        self.start_position == context.start_position
            && self.start_bounds == context.start_bounds
            && self.selected_ids_at_start == context.selected_ids_at_start
            && self.selection_version == context.selection_version
            && self.elements_version == context.elements_version
    }
}

#[derive(Debug, Default)]
struct MoveEditOperationAdapter {
    operation: MoveOperation,
    session: Mutex<Option<(EditContextFingerprint, MoveEditContext)>>,
}

impl MoveEditOperationAdapter {
    fn new() -> Self {
        Self::default()
    }

    fn replace_session(&self, session: Option<(EditContextFingerprint, MoveEditContext)>) {
        let mut guard = self
            .session
            .lock()
            .unwrap_or_else(|poisoned| poisoned.into_inner());
        *guard = session;
    }

    fn resolve_context(&self, context: &EditContext) -> MoveEditContext {
        let guard = self
            .session
            .lock()
            .unwrap_or_else(|poisoned| poisoned.into_inner());
        if let Some((fingerprint, cached_context)) = guard.as_ref() {
            if fingerprint.matches(context) {
                return cached_context.clone();
            }
        }
        MoveEditContext::new(context.clone(), HashMap::new())
    }
}

impl EditOperation for MoveEditOperationAdapter {
    fn id(&self) -> EditOperationId {
        EditOperationIds::MOVE
    }

    fn create_context(
        &self,
        state: &DrawState,
        position: DrawPoint,
        params: &EditOperationParams,
    ) -> EditContext {
        let typed_context = self.operation.create_context(
            state,
            position,
            TypedMoveOperationParams::new(params.initial_selection_bounds()),
        );
        let base = typed_context.base.clone();
        self.replace_session(Some((
            EditContextFingerprint::from_context(&base),
            typed_context,
        )));
        base
    }

    fn initial_transform(
        &self,
        state: &DrawState,
        context: &EditContext,
        start_position: DrawPoint,
    ) -> EditTransform {
        let typed_context = self.resolve_context(context);
        EditTransform::Move(
            self.operation
                .initial_transform(state, &typed_context, start_position),
        )
    }

    fn update(
        &self,
        state: &DrawState,
        context: &EditContext,
        transform: &EditTransform,
        current_position: DrawPoint,
        modifiers: EditModifiers,
        config: &DrawConfig,
    ) -> EditUpdateResult<EditTransform> {
        let EditTransform::Move(typed_transform) = transform else {
            return EditUpdateResult::new(transform.clone());
        };

        let typed_context = self.resolve_context(context);
        let updated = self.operation.update(
            state,
            &typed_context,
            *typed_transform,
            current_position,
            modifiers,
            config,
        );
        EditUpdateResult::with_snap_guides(
            EditTransform::Move(updated.transform),
            updated.snap_guides,
        )
    }

    fn finish(
        &self,
        state: &DrawState,
        context: &EditContext,
        transform: &EditTransform,
    ) -> DrawState {
        let EditTransform::Move(typed_transform) = transform else {
            self.replace_session(None);
            return to_idle_state(state);
        };

        let typed_context = self.resolve_context(context);
        let current_elements_by_id = state.domain.document.element_map();
        if let Some(result) = self.operation.compute_result_with_element_map(
            &typed_context,
            *typed_transform,
            &current_elements_by_id,
        ) {
            self.replace_session(None);
            return to_idle_state(&apply_computed_result(state, &result));
        }

        self.replace_session(None);
        to_idle_state(state)
    }

    fn build_preview(
        &self,
        state: &DrawState,
        context: &EditContext,
        transform: &EditTransform,
    ) -> EditPreview {
        let EditTransform::Move(typed_transform) = transform else {
            return EditPreview::none();
        };

        let typed_context = self.resolve_context(context);
        let current_elements_by_id = state.domain.document.element_map();
        let Some(result) = self.operation.compute_result_with_element_map(
            &typed_context,
            *typed_transform,
            &current_elements_by_id,
        ) else {
            return EditPreview::none();
        };

        build_edit_preview(
            state,
            context,
            &result.updated_elements,
            result.multi_select_bounds,
            result.multi_select_rotation,
        )
    }
}

#[derive(Debug, Default)]
struct RotateEditOperationAdapter {
    operation: RotateOperation,
    session: Mutex<Option<(EditContextFingerprint, RotateEditContext)>>,
}

impl RotateEditOperationAdapter {
    fn new() -> Self {
        Self::default()
    }

    fn replace_session(&self, session: Option<(EditContextFingerprint, RotateEditContext)>) {
        let mut guard = self
            .session
            .lock()
            .unwrap_or_else(|poisoned| poisoned.into_inner());
        *guard = session;
    }

    fn resolve_context(&self, context: &EditContext) -> RotateEditContext {
        let guard = self
            .session
            .lock()
            .unwrap_or_else(|poisoned| poisoned.into_inner());
        if let Some((fingerprint, cached_context)) = guard.as_ref() {
            if fingerprint.matches(context) {
                return cached_context.clone();
            }
        }

        RotateEditContext::new(context.clone(), 0.0, 0.0, 0.0, HashMap::new())
    }
}

impl EditOperation for RotateEditOperationAdapter {
    fn id(&self) -> EditOperationId {
        EditOperationIds::ROTATE
    }

    fn create_context(
        &self,
        state: &DrawState,
        position: DrawPoint,
        params: &EditOperationParams,
    ) -> EditContext {
        let rotate_params = params.as_rotate().copied().unwrap_or_else(|| {
            TypedRotateOperationParams::with_options(
                None,
                config_rotation_snap_angle_default(),
                params.initial_selection_bounds(),
            )
        });
        let typed_context = self
            .operation
            .create_context(state, position, rotate_params);
        let base = typed_context.base.clone();
        self.replace_session(Some((
            EditContextFingerprint::from_context(&base),
            typed_context,
        )));
        base
    }

    fn initial_transform(
        &self,
        state: &DrawState,
        context: &EditContext,
        start_position: DrawPoint,
    ) -> EditTransform {
        let typed_context = self.resolve_context(context);
        EditTransform::Rotate(self.operation.initial_transform(
            state,
            &typed_context,
            start_position,
        ))
    }

    fn update(
        &self,
        state: &DrawState,
        context: &EditContext,
        transform: &EditTransform,
        current_position: DrawPoint,
        modifiers: EditModifiers,
        config: &DrawConfig,
    ) -> EditUpdateResult<EditTransform> {
        let EditTransform::Rotate(typed_transform) = transform else {
            return EditUpdateResult::new(transform.clone());
        };

        let typed_context = self.resolve_context(context);
        let updated = self.operation.update(
            state,
            &typed_context,
            *typed_transform,
            current_position,
            modifiers,
            config,
        );

        EditUpdateResult::with_snap_guides(
            EditTransform::Rotate(updated.transform),
            updated.snap_guides,
        )
    }

    fn finish(
        &self,
        state: &DrawState,
        context: &EditContext,
        transform: &EditTransform,
    ) -> DrawState {
        let EditTransform::Rotate(typed_transform) = transform else {
            self.replace_session(None);
            return to_idle_state(state);
        };

        let typed_context = self.resolve_context(context);
        let current_elements_by_id = state.domain.document.element_map();
        if let Some(result) = self.operation.compute_result_with_element_map(
            &typed_context,
            *typed_transform,
            &current_elements_by_id,
        ) {
            self.replace_session(None);
            return to_idle_state(&apply_computed_result(state, &result));
        }

        self.replace_session(None);
        to_idle_state(state)
    }

    fn build_preview(
        &self,
        state: &DrawState,
        context: &EditContext,
        transform: &EditTransform,
    ) -> EditPreview {
        let EditTransform::Rotate(typed_transform) = transform else {
            return EditPreview::none();
        };

        let typed_context = self.resolve_context(context);
        let current_elements_by_id = state.domain.document.element_map();
        let Some(result) = self.operation.compute_result_with_element_map(
            &typed_context,
            *typed_transform,
            &current_elements_by_id,
        ) else {
            return EditPreview::none();
        };

        build_edit_preview(
            state,
            context,
            &result.updated_elements,
            result.multi_select_bounds,
            result.multi_select_rotation,
        )
    }
}

#[derive(Debug, Default)]
struct ArrowPointEditOperationAdapter {
    operation: ArrowPointOperation,
    session: Mutex<Option<(EditContextFingerprint, ArrowPointEditContext)>>,
}

impl ArrowPointEditOperationAdapter {
    fn new() -> Self {
        Self::default()
    }

    fn replace_session(&self, session: Option<(EditContextFingerprint, ArrowPointEditContext)>) {
        let mut guard = self
            .session
            .lock()
            .unwrap_or_else(|poisoned| poisoned.into_inner());
        *guard = session;
    }

    fn resolve_context(&self, context: &EditContext) -> Option<ArrowPointEditContext> {
        let guard = self
            .session
            .lock()
            .unwrap_or_else(|poisoned| poisoned.into_inner());
        if let Some((fingerprint, cached_context)) = guard.as_ref() {
            if fingerprint.matches(context) {
                return Some(cached_context.clone());
            }
        }
        None
    }
}

struct DocumentArrowPointBindingLookup<'a> {
    state: &'a DrawState,
    target_cache: SnapperTargetCache<DomainElementState>,
}

impl<'a> DocumentArrowPointBindingLookup<'a> {
    fn new(state: &'a DrawState) -> Self {
        Self {
            state,
            target_cache: SnapperTargetCache::default(),
        }
    }
}

#[derive(Clone, Copy, Debug, Default)]
struct DocumentArrowPointBindingResolver;

const DOCUMENT_ARROW_POINT_BINDING_RESOLVER: DocumentArrowPointBindingResolver =
    DocumentArrowPointBindingResolver;

impl SnapperBindingResolver<DomainElementState> for DocumentArrowPointBindingResolver {
    fn is_bindable_target(&self, target: &DomainElementState) -> bool {
        ArrowBindingUtils::is_bindable_target(target)
    }

    fn resolve_binding_search_distance(&self, snap_distance: f64) -> f64 {
        ArrowBindingUtils::resolve_binding_search_distance(snap_distance)
    }

    fn resolve_binding_candidate_for_target(
        &self,
        world_point: DrawPoint,
        target: &DomainElementState,
        snap_distance: f64,
        reference_point: Option<DrawPoint>,
    ) -> Option<crate::draw::elements::types::arrow::arrow_binding::ArrowBindingResult> {
        ArrowBindingUtils::resolve_binding_candidate_for_target(
            world_point,
            target,
            snap_distance,
            reference_point,
        )
    }

    fn resolve_elbow_binding_candidate_for_target(
        &self,
        world_point: DrawPoint,
        target: &DomainElementState,
        snap_distance: f64,
        has_arrowhead: bool,
    ) -> Option<crate::draw::elements::types::arrow::arrow_binding::ArrowBindingResult> {
        ArrowBindingUtils::resolve_elbow_binding_candidate_for_target(
            world_point,
            target,
            snap_distance,
            has_arrowhead,
        )
    }

    fn resolve_binding_candidate(
        &self,
        world_point: DrawPoint,
        targets: &[DomainElementState],
        snap_distance: f64,
        preferred_binding: Option<&CompatArrowBinding>,
        allow_new_binding: bool,
        reference_point: Option<DrawPoint>,
    ) -> Option<crate::draw::elements::types::arrow::arrow_binding::ArrowBindingResult> {
        ArrowBindingUtils::resolve_binding_candidate(
            world_point,
            targets.iter(),
            snap_distance,
            preferred_binding,
            allow_new_binding,
            reference_point,
        )
    }

    fn resolve_elbow_binding_candidate(
        &self,
        world_point: DrawPoint,
        targets: &[DomainElementState],
        snap_distance: f64,
        preferred_binding: Option<&CompatArrowBinding>,
        allow_new_binding: bool,
        has_arrowhead: bool,
    ) -> Option<crate::draw::elements::types::arrow::arrow_binding::ArrowBindingResult> {
        ArrowBindingUtils::resolve_elbow_binding_candidate(
            world_point,
            targets.iter(),
            snap_distance,
            has_arrowhead,
            preferred_binding,
            allow_new_binding,
        )
    }
}

impl ArrowPointBindingLookup for DocumentArrowPointBindingLookup<'_> {
    fn resolve_endpoint_binding_candidate(
        &mut self,
        request: &ArrowPointBindingRequest,
    ) -> Option<ArrowBindingCandidate> {
        if !request.should_lookup_bindings || request.snap_distance <= 0.0 {
            self.target_cache.reset();
            return None;
        }

        let preferred_binding = request
            .existing_binding
            .as_ref()
            .map(internal_binding_to_compat);
        let candidate = ArrowBindingSnapper::resolve_endpoint_binding_candidate(
            self.state,
            request.world_target,
            request.arrow_type,
            if request.has_arrowhead {
                ArrowheadStyle::Standard
            } else {
                ArrowheadStyle::None
            },
            request.should_lookup_bindings,
            request.snap_distance,
            request.allow_new_binding,
            request.has_bindable_targets,
            preferred_binding.as_ref(),
            request.reference_point,
            Some(&mut self.target_cache),
            Some(request.element_id.as_str()),
            ArrowBindingCachePolicy::default(),
            &DOCUMENT_ARROW_POINT_BINDING_RESOLVER,
        );
        let candidate = candidate?;

        Some(ArrowBindingCandidate {
            binding: compat_binding_to_internal(&candidate.binding),
            snap_point: candidate.snap_point,
        })
    }
}

impl EditOperation for ArrowPointEditOperationAdapter {
    fn id(&self) -> EditOperationId {
        EditOperationIds::ARROW_POINT
    }

    fn records_history(&self) -> bool {
        false
    }

    fn create_context(
        &self,
        state: &DrawState,
        position: DrawPoint,
        params: &EditOperationParams,
    ) -> EditContext {
        let arrow_params = params.as_arrow_point();
        let target = params
            .as_arrow_point()
            .and_then(|details| {
                state
                    .domain
                    .document
                    .get_element_by_id(details.element_id.as_str())
                    .cloned()
            })
            .and_then(resolve_arrow_target_for_element)
            .or_else(|| resolve_single_selected_arrow_target(state));
        let selected_ids_at_start = state
            .domain
            .selection
            .selected_ids
            .iter()
            .cloned()
            .collect::<HashSet<_>>();
        let start_bounds = params
            .initial_selection_bounds()
            .or_else(|| target.as_ref().map(|value| value.element.rect))
            .unwrap_or_else(|| DrawRect::from_point(position));
        let base = EditContext::new(
            position,
            start_bounds,
            selected_ids_at_start,
            state.domain.selection.selection_version as i64,
            state.domain.document.elements_version,
        );
        if let Some(target) = target.as_ref() {
            let typed_context = build_arrow_context_from_target(state, &base, target, arrow_params);
            self.replace_session(Some((
                EditContextFingerprint::from_context(&base),
                typed_context,
            )));
        } else {
            self.replace_session(None);
        }
        base
    }

    fn initial_transform(
        &self,
        _state: &DrawState,
        context: &EditContext,
        start_position: DrawPoint,
    ) -> EditTransform {
        let Some(typed_context) = self.resolve_context(context) else {
            return EditTransform::ArrowPoint(ArrowPointTransform::new(start_position, Vec::new()));
        };
        let internal_transform = self
            .operation
            .initial_transform(&typed_context, start_position);
        EditTransform::ArrowPoint(into_public_arrow_transform(&internal_transform))
    }

    fn update(
        &self,
        state: &DrawState,
        context: &EditContext,
        transform: &EditTransform,
        current_position: DrawPoint,
        modifiers: EditModifiers,
        config: &DrawConfig,
    ) -> EditUpdateResult<EditTransform> {
        let EditTransform::ArrowPoint(typed_transform) = transform else {
            return EditUpdateResult::new(transform.clone());
        };

        let Some(typed_context) = self.resolve_context(context) else {
            return EditUpdateResult::new(transform.clone());
        };
        let snapping_mode =
            resolve_effective_snapping_mode_for_config(config, modifiers.snap_override);
        let mut binding_lookup = DocumentArrowPointBindingLookup::new(state);
        let should_lookup_bindings = config.snap.enable_arrow_binding
            || typed_transform.start_binding.is_some()
            || typed_transform.end_binding.is_some();
        let updated = self.operation.update(
            &typed_context,
            &into_internal_arrow_transform(typed_transform),
            current_position,
            ArrowPointUpdateOptions {
                handle_tolerance: config.selection.interaction.handle_tolerance,
                view_zoom: state.application.view.camera.zoom,
                snap_to_grid: snapping_mode == SnappingMode::Grid,
                grid_size: config.grid.size,
                should_lookup_bindings,
                binding_distance: if should_lookup_bindings {
                    ArrowBindingSnapper::resolve_binding_distance(state, &config.snap)
                } else {
                    0.0
                },
                allow_new_binding: config.snap.enable_arrow_binding
                    && !modifiers.snap_override
                    && snapping_mode != SnappingMode::Grid,
            },
            &mut binding_lookup,
        );

        EditUpdateResult::new(EditTransform::ArrowPoint(into_public_arrow_transform(
            &updated,
        )))
    }

    fn finish(
        &self,
        state: &DrawState,
        context: &EditContext,
        transform: &EditTransform,
    ) -> DrawState {
        let EditTransform::ArrowPoint(typed_transform) = transform else {
            self.replace_session(None);
            return to_idle_state(state);
        };

        let Some(typed_context) = self.resolve_context(context) else {
            self.replace_session(None);
            return to_idle_state(state);
        };
        let internal_transform = into_internal_arrow_transform(typed_transform);
        let Some(updated_element) = compute_updated_arrow_element(
            &self.operation,
            state,
            &typed_context,
            &internal_transform,
            true,
            true,
        ) else {
            self.replace_session(None);
            return to_idle_state(state);
        };

        let next_elements = state
            .domain
            .document
            .elements
            .iter()
            .map(|element| {
                if element.id == updated_element.id {
                    updated_element.clone()
                } else {
                    element.clone()
                }
            })
            .collect::<Vec<_>>();
        let next_document = state
            .domain
            .document
            .copy_with(Some(next_elements), None, None);
        let next_domain = state.domain.copy_with(Some(next_document), None);

        self.replace_session(None);
        to_idle_state(&state.copy_with(Some(next_domain), None))
    }

    fn build_preview(
        &self,
        state: &DrawState,
        context: &EditContext,
        transform: &EditTransform,
    ) -> EditPreview {
        let EditTransform::ArrowPoint(typed_transform) = transform else {
            return EditPreview::none();
        };

        let Some(typed_context) = self.resolve_context(context) else {
            return EditPreview::none();
        };
        let internal_transform = into_internal_arrow_transform(typed_transform);
        let Some(updated_element) = compute_updated_arrow_element(
            &self.operation,
            state,
            &typed_context,
            &internal_transform,
            false,
            false,
        ) else {
            return EditPreview::none();
        };

        let mut preview_elements = HashMap::new();
        preview_elements.insert(updated_element.id.clone(), updated_element);
        build_edit_preview(state, context, &preview_elements, None, None)
    }
}

fn config_rotation_snap_angle_default() -> f64 {
    DrawConfig::default().element.rotation_snap_angle
}

fn to_idle_state(state: &DrawState) -> DrawState {
    state.copy_with(None, Some(state.application.to_idle()))
}

fn apply_computed_result(state: &DrawState, result: &EditComputedResult) -> DrawState {
    if result.updated_elements.is_empty() {
        return state.clone();
    }

    let next_elements = state
        .domain
        .document
        .elements
        .iter()
        .map(|element| {
            result
                .updated_elements
                .get(&element.id)
                .cloned()
                .unwrap_or_else(|| element.clone())
        })
        .collect::<Vec<_>>();
    let next_document = state
        .domain
        .document
        .copy_with(Some(next_elements), None, None);
    let next_domain = state.domain.copy_with(Some(next_document), None);

    let next_overlay = if state.domain.selection.is_multi_select() {
        if let Some(bounds) = result.multi_select_bounds {
            Some(
                crate::draw::models::selection_overlay_state::SelectionOverlayState {
                    multi_select_overlay: Some(MultiSelectOverlayState::with_rotation(
                        bounds,
                        result.multi_select_rotation.unwrap_or_else(|| {
                            state
                                .application
                                .selection_overlay
                                .multi_select_overlay
                                .map(|overlay| overlay.rotation)
                                .unwrap_or(0.0)
                        }),
                    )),
                },
            )
        } else {
            None
        }
    } else {
        None
    };

    let next_application = match next_overlay {
        Some(overlay) => state.application.copy_with(None, None, Some(overlay)),
        None => state.application.clone(),
    };

    state.copy_with(Some(next_domain), Some(next_application))
}

#[derive(Clone, Debug)]
enum ArrowEditPayload {
    Arrow(ArrowData),
    Line(LineData),
}

#[derive(Clone, Debug)]
struct ArrowEditTarget {
    element: DomainElementState,
    payload: ArrowEditPayload,
}

impl ArrowEditTarget {
    fn points(&self) -> &[DrawPoint] {
        match &self.payload {
            ArrowEditPayload::Arrow(data) => &data.points,
            ArrowEditPayload::Line(data) => &data.points,
        }
    }

    fn arrow_type(&self) -> ArrowType {
        match &self.payload {
            ArrowEditPayload::Arrow(data) => data.arrow_type,
            ArrowEditPayload::Line(data) => data.arrow_type,
        }
    }

    fn start_arrowhead(&self) -> ArrowheadStyle {
        match &self.payload {
            ArrowEditPayload::Arrow(data) => data.start_arrowhead,
            ArrowEditPayload::Line(data) => data.start_arrowhead,
        }
    }

    fn end_arrowhead(&self) -> ArrowheadStyle {
        match &self.payload {
            ArrowEditPayload::Arrow(data) => data.end_arrowhead,
            ArrowEditPayload::Line(data) => data.end_arrowhead,
        }
    }

    fn start_binding(&self) -> Option<ArrowDataBinding> {
        match &self.payload {
            ArrowEditPayload::Arrow(data) => data.start_binding.clone(),
            ArrowEditPayload::Line(data) => {
                data.start_binding.as_ref().map(compat_binding_to_internal)
            }
        }
    }

    fn end_binding(&self) -> Option<ArrowDataBinding> {
        match &self.payload {
            ArrowEditPayload::Arrow(data) => data.end_binding.clone(),
            ArrowEditPayload::Line(data) => {
                data.end_binding.as_ref().map(compat_binding_to_internal)
            }
        }
    }

    fn fixed_segments(&self) -> Vec<ArrowDataElbowFixedSegment> {
        match &self.payload {
            ArrowEditPayload::Arrow(data) => data.fixed_segments.clone().unwrap_or_default(),
            ArrowEditPayload::Line(data) => data
                .fixed_segments
                .clone()
                .unwrap_or_default()
                .iter()
                .copied()
                .map(compat_fixed_segment_to_internal)
                .collect(),
        }
    }
}

fn resolve_single_selected_arrow_target(state: &DrawState) -> Option<ArrowEditTarget> {
    if state.domain.selection.selected_ids.len() != 1 {
        return None;
    }

    let selected_id = state.domain.selection.selected_ids.iter().next()?;
    let element = state
        .domain
        .document
        .get_element_by_id(selected_id)?
        .clone();
    resolve_arrow_target_for_element(element)
}

fn resolve_arrow_target_for_element(element: DomainElementState) -> Option<ArrowEditTarget> {
    let payload_json = element.data.to_json_value();
    let payload = match element.data.type_id().as_str() {
        ArrowData::TYPE_ID_TOKEN => ArrowData::from_json_value(&payload_json)
            .ok()
            .map(ArrowEditPayload::Arrow)?,
        LineData::TYPE_ID_TOKEN => LineData::from_json_value(&payload_json)
            .ok()
            .map(ArrowEditPayload::Line)?,
        _ => return None,
    };

    Some(ArrowEditTarget { element, payload })
}

fn build_arrow_context_from_target(
    state: &DrawState,
    base: &EditContext,
    target: &ArrowEditTarget,
    details: Option<&TypedArrowPointOperationParams>,
) -> ArrowPointEditContext {
    let initial_points = ArrowGeometry::resolve_world_points(target.element.rect, target.points());
    let (point_kind, point_index, is_double_click) = if let Some(details) = details {
        (
            map_operation_arrow_point_kind(details.point_kind),
            details.point_index,
            details.is_double_click,
        )
    } else {
        let (point_kind, point_index) =
            resolve_closest_arrow_point(base.start_position, &initial_points, target.arrow_type());
        (point_kind, point_index, false)
    };
    let fixed_segments = target.fixed_segments();
    let release_fixed_segment = is_double_click
        && point_kind == OperationArrowPointKind::Addable
        && target.arrow_type() == ArrowType::Elbow
        && fixed_segments
            .iter()
            .any(|segment| segment.index == point_index.saturating_add(1));
    let delete_point_on_start = is_double_click
        && !release_fixed_segment
        && point_kind == OperationArrowPointKind::Turning
        && point_index > 0
        && point_index < initial_points.len().saturating_sub(1);

    let mut context = ArrowPointEditContext::from_start_position(
        target.element.id.clone(),
        target.element.rect,
        target.element.rotation,
        base.start_position,
        initial_points,
        fixed_segments,
        target.arrow_type(),
        point_kind,
        point_index,
        release_fixed_segment,
        delete_point_on_start,
        target.start_arrowhead(),
        target.end_arrowhead(),
        target.start_binding(),
        target.end_binding(),
        has_bindable_targets(state, target.element.id.as_str()),
    );

    if release_fixed_segment && target.arrow_type() == ArrowType::Elbow {
        if let ArrowEditPayload::Arrow(arrow_data) = &target.payload {
            let segment_index = point_index + 1;
            let updated_fixed =
                fixed_segments_without_index(&context.initial_fixed_segments, segment_index);
            let element_map = state.domain.document.element_map();
            let updates = HashMap::new();
            let lookup = CombinedElementLookup::new(&element_map, &updates);
            let released = compute_elbow_edit(
                &target.element,
                arrow_data,
                &lookup,
                Some(context.initial_points.clone()),
                Some(updated_fixed),
                ElbowBindingOverride::Unset,
                ElbowBindingOverride::Unset,
                false,
            );
            context = context.with_released_state(
                Some(released.local_points),
                Some(released.fixed_segments.unwrap_or_default()),
            );
        }
    }

    context
}

fn map_operation_arrow_point_kind(
    kind: crate::draw::elements::types::arrow::arrow_points::ArrowPointKind,
) -> OperationArrowPointKind {
    match kind {
        crate::draw::elements::types::arrow::arrow_points::ArrowPointKind::Turning => {
            OperationArrowPointKind::Turning
        }
        crate::draw::elements::types::arrow::arrow_points::ArrowPointKind::Addable => {
            OperationArrowPointKind::Addable
        }
        crate::draw::elements::types::arrow::arrow_points::ArrowPointKind::LoopStart => {
            OperationArrowPointKind::LoopStart
        }
        crate::draw::elements::types::arrow::arrow_points::ArrowPointKind::LoopEnd => {
            OperationArrowPointKind::LoopEnd
        }
    }
}

fn fixed_segments_without_index(
    segments: &[ArrowDataElbowFixedSegment],
    segment_index: usize,
) -> Vec<ArrowDataElbowFixedSegment> {
    segments
        .iter()
        .filter(|segment| segment.index != segment_index)
        .cloned()
        .collect()
}

fn resolve_closest_arrow_point(
    position: DrawPoint,
    points: &[DrawPoint],
    arrow_type: ArrowType,
) -> (OperationArrowPointKind, usize) {
    if points.is_empty() {
        return (OperationArrowPointKind::Turning, 0);
    }

    let mut best_kind = OperationArrowPointKind::Turning;
    let mut best_index = 0_usize;
    let mut best_distance = f64::INFINITY;

    for (index, point) in points.iter().copied().enumerate() {
        let distance = point.distance_squared(position);
        if distance < best_distance {
            best_distance = distance;
            best_kind = OperationArrowPointKind::Turning;
            best_index = index;
        }
    }

    if points.len() >= 2 {
        for segment_index in 0..(points.len() - 1) {
            let midpoint = if arrow_type == ArrowType::Curved && points.len() >= 3 {
                ArrowGeometry::calculate_curve_draw_point(points, segment_index, 0.5)
                    .unwrap_or_else(|| {
                        DrawPoint::new(
                            (points[segment_index].x + points[segment_index + 1].x) / 2.0,
                            (points[segment_index].y + points[segment_index + 1].y) / 2.0,
                        )
                    })
            } else {
                DrawPoint::new(
                    (points[segment_index].x + points[segment_index + 1].x) / 2.0,
                    (points[segment_index].y + points[segment_index + 1].y) / 2.0,
                )
            };
            let distance = midpoint.distance_squared(position);
            if distance < best_distance {
                best_distance = distance;
                best_kind = OperationArrowPointKind::Addable;
                best_index = segment_index;
            }
        }
    }

    (best_kind, best_index)
}

fn has_bindable_targets(state: &DrawState, excluded_element_id: &str) -> bool {
    state.domain.document.elements.iter().any(|element| {
        element.id != excluded_element_id && element.opacity > 0.0 && is_bindable_target(element)
    })
}

fn is_bindable_target(element: &DomainElementState) -> bool {
    ArrowBindingUtils::is_bindable_target(element)
}

fn compute_updated_arrow_element(
    operation: &ArrowPointOperation,
    state: &DrawState,
    context: &ArrowPointEditContext,
    transform: &InternalArrowPointTransform,
    apply_deletion: bool,
    finalize: bool,
) -> Option<DomainElementState> {
    let current_element = state
        .domain
        .document
        .get_element_by_id(context.element_id.as_str())?
        .clone();
    let target = resolve_arrow_target_for_element(current_element.clone())?;

    let next_world_points = operation.compute_points_for_result(transform, apply_deletion);
    if next_world_points.len() < 2 {
        return None;
    }

    let next_data_and_rect: Option<(Arc<dyn CoreElementData>, DrawRect)> = match target.payload {
        ArrowEditPayload::Arrow(data) => {
            let data_with_bindings = data.copy_with(ArrowDataPatch {
                start_binding: match transform.start_binding.clone() {
                    Some(binding) => ArrowDataNullableField::Value(binding),
                    None => ArrowDataNullableField::Null,
                },
                end_binding: match transform.end_binding.clone() {
                    Some(binding) => ArrowDataNullableField::Value(binding),
                    None => ArrowDataNullableField::Null,
                },
                ..ArrowDataPatch::default()
            });

            if data.arrow_type != ArrowType::Elbow
                && context.rotation == 0.0
                && next_world_points.len() == 2
            {
                let layout = compute_arrow_two_point_layout(
                    next_world_points[0],
                    next_world_points[next_world_points.len() - 1],
                );
                let updated_data = data_with_bindings.copy_with(ArrowDataPatch {
                    points: Some(layout.normalized_points),
                    ..ArrowDataPatch::default()
                });
                Some((Arc::new(updated_data), layout.rect))
            } else if data.arrow_type == ArrowType::Elbow {
                let fixed_segments = transform.fixed_segments.clone().unwrap_or_default();
                let element_map = state.domain.document.element_map();
                let updates = HashMap::new();
                let lookup = CombinedElementLookup::new(&element_map, &updates);
                let updated = compute_elbow_edit(
                    &current_element,
                    &data_with_bindings,
                    &lookup,
                    Some(next_world_points.clone()),
                    Some(fixed_segments),
                    ElbowBindingOverride::Unset,
                    ElbowBindingOverride::Unset,
                    finalize,
                );

                let geometry = resolve_arrow_geometry_update(
                    &updated.local_points,
                    context.element_rect,
                    context.rotation,
                    data.arrow_type,
                );
                let transformed_fixed_segments = transform_fixed_segments(
                    updated.fixed_segments.as_deref(),
                    context.element_rect,
                    geometry.rect,
                    context.rotation,
                );
                let updated_data = data_with_bindings.copy_with(ArrowDataPatch {
                    points: Some(geometry.normalized_points),
                    fixed_segments: match transformed_fixed_segments {
                        Some(segments) => ArrowDataNullableField::Value(segments),
                        None => ArrowDataNullableField::Null,
                    },
                    start_is_special: match updated.start_is_special {
                        Some(value) => ArrowDataNullableField::Value(value),
                        None => ArrowDataNullableField::Null,
                    },
                    end_is_special: match updated.end_is_special {
                        Some(value) => ArrowDataNullableField::Value(value),
                        None => ArrowDataNullableField::Null,
                    },
                    ..ArrowDataPatch::default()
                });
                Some((Arc::new(updated_data), geometry.rect))
            } else {
                let geometry = resolve_arrow_geometry_update(
                    &next_world_points,
                    context.element_rect,
                    context.rotation,
                    data.arrow_type,
                );
                let updated_data = data_with_bindings.copy_with(ArrowDataPatch {
                    points: Some(geometry.normalized_points),
                    ..ArrowDataPatch::default()
                });
                Some((Arc::new(updated_data), geometry.rect))
            }
        }
        ArrowEditPayload::Line(data) => {
            let data_with_bindings = data.copy_with(LineDataPatch {
                start_binding: match transform.start_binding.as_ref() {
                    Some(binding) => {
                        ArrowLikeNullableField::Value(internal_binding_to_compat(binding))
                    }
                    None => ArrowLikeNullableField::Null,
                },
                end_binding: match transform.end_binding.as_ref() {
                    Some(binding) => {
                        ArrowLikeNullableField::Value(internal_binding_to_compat(binding))
                    }
                    None => ArrowLikeNullableField::Null,
                },
                ..LineDataPatch::default()
            });

            if context.rotation == 0.0 && next_world_points.len() == 2 {
                let layout = compute_arrow_two_point_layout(
                    next_world_points[0],
                    next_world_points[next_world_points.len() - 1],
                );
                let updated_data = data_with_bindings.copy_with(LineDataPatch {
                    points: Some(layout.normalized_points),
                    ..LineDataPatch::default()
                });
                Some((Arc::new(updated_data), layout.rect))
            } else {
                let geometry = resolve_arrow_geometry_update(
                    &next_world_points,
                    context.element_rect,
                    context.rotation,
                    data.arrow_type,
                );
                let updated_data = data_with_bindings.copy_with(LineDataPatch {
                    points: Some(geometry.normalized_points),
                    ..LineDataPatch::default()
                });
                Some((Arc::new(updated_data), geometry.rect))
            }
        }
    };
    let (next_data, next_rect) = next_data_and_rect?;

    let updated =
        current_element.copy_with(None, Some(next_rect), None, None, None, Some(next_data));
    if updated == current_element {
        None
    } else {
        Some(updated)
    }
}

fn into_public_arrow_transform(transform: &InternalArrowPointTransform) -> ArrowPointTransform {
    ArrowPointTransform::with_state(
        transform.current_position,
        transform.points.clone(),
        transform.fixed_segments.clone(),
        transform.start_binding.clone(),
        transform.end_binding.clone(),
        transform.active_index,
        transform.did_insert,
        transform.should_delete,
        transform.has_changes,
    )
}

fn into_internal_arrow_transform(transform: &ArrowPointTransform) -> InternalArrowPointTransform {
    InternalArrowPointTransform {
        current_position: transform.current_position,
        points: transform.points.clone(),
        fixed_segments: transform.fixed_segments.clone(),
        start_binding: transform.start_binding.clone(),
        end_binding: transform.end_binding.clone(),
        active_index: transform.active_index,
        did_insert: transform.did_insert,
        should_delete: transform.should_delete,
        has_changes: transform.has_changes,
    }
}

fn compat_binding_to_internal(binding: &CompatArrowBinding) -> ArrowDataBinding {
    ArrowDataBinding::new(
        binding.element_id.clone(),
        binding.anchor,
        match binding.mode {
            CompatArrowBindingMode::Inside => ArrowDataBindingMode::Inside,
            CompatArrowBindingMode::Orbit => ArrowDataBindingMode::Orbit,
            CompatArrowBindingMode::Skip => ArrowDataBindingMode::Skip,
        },
    )
}

fn internal_binding_to_compat(binding: &ArrowDataBinding) -> CompatArrowBinding {
    CompatArrowBinding::new(
        binding.element_id.clone(),
        binding.anchor,
        match binding.mode {
            ArrowDataBindingMode::Inside => CompatArrowBindingMode::Inside,
            ArrowDataBindingMode::Orbit => CompatArrowBindingMode::Orbit,
            ArrowDataBindingMode::Skip => CompatArrowBindingMode::Skip,
        },
    )
}

fn compat_fixed_segment_to_internal(
    segment: CompatElbowFixedSegment,
) -> ArrowDataElbowFixedSegment {
    ArrowDataElbowFixedSegment {
        index: segment.index,
        start: segment.start,
        end: segment.end,
    }
}

fn internal_fixed_segment_to_compat(
    segment: &ArrowDataElbowFixedSegment,
) -> CompatElbowFixedSegment {
    CompatElbowFixedSegment {
        index: segment.index,
        start: segment.start,
        end: segment.end,
    }
}
