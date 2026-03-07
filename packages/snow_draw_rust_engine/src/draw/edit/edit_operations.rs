#![allow(dead_code)]

use std::collections::HashMap;
use std::collections::HashSet;
use std::fmt;
use std::panic::panic_any;
use std::sync::{Arc, Mutex};

use crate::draw::config::draw_config::DrawConfig;
use crate::draw::edit::arrow::arrow_point_operation::{
    ArrowBindingCandidate, ArrowPointBindingLookup, ArrowPointBindingRequest,
    ArrowPointEditContext, ArrowPointKind as OperationArrowPointKind, ArrowPointOperation,
    ArrowPointTransform as InternalArrowPointTransform, ArrowPointUpdateOptions,
};
use crate::draw::edit::core::edit_computed_result::EditComputedResult;
use crate::draw::edit::core::edit_errors::{
    EditContextTypeMismatchError, EditParamsTypeMismatchError, EditTransformTypeMismatchError,
};
use crate::draw::edit::core::edit_operation_params::{
    ArrowPointOperationParams as TypedArrowPointOperationParams,
    MoveOperationParams as TypedMoveOperationParams,
    RotateOperationParams as TypedRotateOperationParams,
};
use crate::draw::edit::core::standard_finish_mixin::{build_edit_preview, StandardFinishMixin};
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
use crate::draw::elements::types::arrow::arrow_core::DEFAULT_MAX_COORDINATE;
use crate::draw::elements::types::arrow::arrow_core_bridge::{
    apply_core_arrow_patches_to_sources, build_core_engine_context,
    to_core_arrow_state_from_source, ConnectorSourceData,
};
use crate::draw::elements::types::arrow::arrow_core_endpoint_drag::{
    finalize_arrow_core_endpoint_drag_result, finalize_connector_core_endpoint_drag_result,
};
use crate::draw::elements::types::arrow::arrow_core_ops::resolve_endpoint_drag_binding_enabled;
use crate::draw::elements::types::arrow::arrow_data::{
    ArrowBinding as ArrowDataBinding, ArrowBindingMode as ArrowDataBindingMode, ArrowData,
    ArrowDataPatch, ElbowFixedSegment as ArrowDataElbowFixedSegment,
    NullableField as ArrowDataNullableField,
};
use crate::draw::elements::types::arrow::arrow_focus::{
    list_visible_arrow_focus_points, ArrowFocusEndpoint,
};
use crate::draw::elements::types::arrow::arrow_geometry::ArrowGeometry;
use crate::draw::elements::types::arrow::arrow_layout::resolve_arrow_geometry_update;
use crate::draw::elements::types::arrow::arrow_like_data::NullableField as ArrowLikeNullableField;
use crate::draw::elements::types::arrow::arrow_scene::ArrowScene;
use crate::draw::elements::types::arrow::arrow_two_point_layout::compute_arrow_two_point_layout;
use crate::draw::elements::types::arrow::core::arrow_engine::compute_focus_drag;
use crate::draw::elements::types::arrow::core::arrow_order_core::{
    reorder_arrow_above_hovered_bindable, reordered_element_ids_from_hovered_reorder,
};
use crate::draw::elements::types::arrow::core::arrow_types::{
    ArrowEndpointEdge, ArrowStatePatchWithId, ReorderArrowAboveHoveredBindableInput,
};
use crate::draw::elements::types::arrow::elbow::elbow_editing::{
    compute_elbow_edit, transform_fixed_segments, BindingOverride as ElbowBindingOverride,
};
use crate::draw::elements::types::arrow::elbow::elbow_fixed_segment::ElbowFixedSegment as CompatElbowFixedSegment;
use crate::draw::elements::types::connector::connector_points::ConnectorPointUtils;
use crate::draw::elements::types::line::line_data::{LineData, LineDataPatch};
use crate::draw::history::history_metadata::HistoryMetadata;
use crate::draw::models::draw_state::DrawState;
use crate::draw::models::element_state::ElementState as DomainElementState;
use crate::draw::models::multi_select_lifecycle::MultiSelectOverlayState;
use crate::draw::reducers::core::arrow_binding_sync::reorder_elements_by_id_order;
use crate::draw::types::draw_point::DrawPoint;
use crate::draw::types::draw_rect::DrawRect;
use crate::draw::types::edit_context::{EditContext, MoveEditContext, RotateEditContext};
use crate::draw::types::edit_operation_id::{EditOperationId, EditOperationIds};
use crate::draw::types::edit_transform::{ArrowPointTransform, EditTransform};
use crate::draw::types::element_style::{ArrowType, ArrowheadStyle};
use crate::draw::utils::combined_element_lookup::CombinedElementLookup;
use crate::draw::utils::list_equality::{
    fixed_segment_structure_equals_with_tolerance, point_list_equals,
};
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
        EditOperationIds::CONNECTOR_POINT,
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
            let is_new_operation_id = map.insert(operation_id, operation).is_none();
            if is_new_operation_id {
                order.push(operation_id);
            }
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
    selected_ids_at_start_in_order: Vec<String>,
    selection_version: i64,
    elements_version: i64,
}

impl EditContextFingerprint {
    fn from_context(context: &EditContext) -> Self {
        Self {
            start_position: context.start_position,
            start_bounds: context.start_bounds,
            selected_ids_at_start: context.selected_ids_at_start.clone(),
            selected_ids_at_start_in_order: context.selected_ids_at_start_in_order.clone(),
            selection_version: context.selection_version,
            elements_version: context.elements_version,
        }
    }

    fn matches(&self, context: &EditContext) -> bool {
        self.start_position == context.start_position
            && self.start_bounds == context.start_bounds
            && self.selected_ids_at_start == context.selected_ids_at_start
            && self.selected_ids_at_start_in_order == context.selected_ids_at_start_in_order
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

    fn require_context(&self, context: &EditContext, operation_name: &str) -> MoveEditContext {
        let guard = self
            .session
            .lock()
            .unwrap_or_else(|poisoned| poisoned.into_inner());
        if let Some((fingerprint, cached_context)) = guard.as_ref() {
            if fingerprint.matches(context) {
                return cached_context.clone();
            }
        }

        panic_any(EditContextTypeMismatchError::new(
            std::any::type_name::<MoveEditContext>(),
            std::any::type_name::<EditContext>(),
            operation_name.to_owned(),
            Some(format!(
                "startPosition={}, selectedIds={}",
                context.start_position,
                context.selected_ids_at_start.len()
            )),
        ))
    }
}

impl EditOperation for MoveEditOperationAdapter {
    fn id(&self) -> EditOperationId {
        EditOperationIds::MOVE
    }

    fn create_history_metadata(
        &self,
        context: &EditContext,
        transform: &EditTransform,
    ) -> HistoryMetadata {
        let typed_context = self.require_context(context, "MoveOperation.createHistoryMetadata");
        let EditTransform::Move(typed_transform) = transform else {
            panic_any(EditTransformTypeMismatchError::new(
                std::any::type_name::<crate::draw::types::edit_transform::MoveTransform>(),
                match transform {
                    EditTransform::Move(_) => {
                        std::any::type_name::<crate::draw::types::edit_transform::MoveTransform>()
                    }
                    EditTransform::Resize(_) => {
                        std::any::type_name::<crate::draw::types::edit_transform::ResizeTransform>()
                    }
                    EditTransform::Rotate(_) => {
                        std::any::type_name::<crate::draw::types::edit_transform::RotateTransform>()
                    }
                    EditTransform::ArrowPoint(_) => std::any::type_name::<
                        crate::draw::types::edit_transform::ArrowPointTransform,
                    >(),
                },
                "MoveOperation.createHistoryMetadata".to_owned(),
                None,
            ));
        };

        self.operation
            .create_history_metadata(&typed_context, *typed_transform)
    }

    fn create_context(
        &self,
        state: &DrawState,
        position: DrawPoint,
        params: &EditOperationParams,
    ) -> EditContext {
        let typed_params = params.as_move().copied().unwrap_or_else(|| {
            panic_any(EditParamsTypeMismatchError::new(
                std::any::type_name::<TypedMoveOperationParams>(),
                match params {
                    EditOperationParams::Move(_) => {
                        std::any::type_name::<TypedMoveOperationParams>()
                    }
                    EditOperationParams::Resize(_) => {
                        std::any::type_name::<crate::draw::edit::core::edit_operation_params::ResizeOperationParams>()
                    }
                    EditOperationParams::Rotate(_) => {
                        std::any::type_name::<crate::draw::edit::core::edit_operation_params::RotateOperationParams>()
                    }
                    EditOperationParams::ConnectorPoint(_) => {
                        std::any::type_name::<crate::draw::edit::core::edit_operation_params::ConnectorPointOperationParams>()
                    }
                },
                "MoveOperation.createContext".to_owned(),
                None,
            ))
        });
        let typed_context = self.operation.create_context(state, position, typed_params);
        let base = typed_context.base.clone();
        self.replace_session(Some((
            EditContextFingerprint::from_context(&base),
            typed_context,
        )));
        base
    }

    fn initial_transform(
        &self,
        _state: &DrawState,
        _context: &EditContext,
        _start_position: DrawPoint,
    ) -> EditTransform {
        EditTransform::Move(crate::draw::types::edit_transform::MoveTransform::ZERO)
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
        let typed_context = self.require_context(context, "MoveOperation.update");
        let EditTransform::Move(typed_transform) = transform else {
            panic_any(EditTransformTypeMismatchError::new(
                std::any::type_name::<crate::draw::types::edit_transform::MoveTransform>(),
                match transform {
                    EditTransform::Move(_) => {
                        std::any::type_name::<crate::draw::types::edit_transform::MoveTransform>()
                    }
                    EditTransform::Resize(_) => {
                        std::any::type_name::<crate::draw::types::edit_transform::ResizeTransform>()
                    }
                    EditTransform::Rotate(_) => {
                        std::any::type_name::<crate::draw::types::edit_transform::RotateTransform>()
                    }
                    EditTransform::ArrowPoint(_) => std::any::type_name::<
                        crate::draw::types::edit_transform::ArrowPointTransform,
                    >(),
                },
                "MoveOperation.update".to_owned(),
                None,
            ));
        };

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
        let next_state = self.finish_standard(state, context, transform);
        self.replace_session(None);
        next_state
    }

    fn build_preview(
        &self,
        state: &DrawState,
        context: &EditContext,
        transform: &EditTransform,
    ) -> EditPreview {
        self.build_preview_standard(state, context, transform)
    }
}

impl StandardFinishMixin for MoveEditOperationAdapter {
    fn compute_result(
        &self,
        state: &DrawState,
        context: &EditContext,
        transform: &EditTransform,
    ) -> Option<EditComputedResult> {
        let typed_context = self.require_context(context, "MoveOperation.computeResult");
        let EditTransform::Move(typed_transform) = transform else {
            panic_any(EditTransformTypeMismatchError::new(
                std::any::type_name::<crate::draw::types::edit_transform::MoveTransform>(),
                match transform {
                    EditTransform::Move(_) => {
                        std::any::type_name::<crate::draw::types::edit_transform::MoveTransform>()
                    }
                    EditTransform::Resize(_) => {
                        std::any::type_name::<crate::draw::types::edit_transform::ResizeTransform>()
                    }
                    EditTransform::Rotate(_) => {
                        std::any::type_name::<crate::draw::types::edit_transform::RotateTransform>()
                    }
                    EditTransform::ArrowPoint(_) => std::any::type_name::<
                        crate::draw::types::edit_transform::ArrowPointTransform,
                    >(),
                },
                "MoveOperation.computeResult".to_owned(),
                None,
            ));
        };

        let current_elements_by_id = state.domain.document.element_map();
        self.operation.compute_result_with_element_map(
            &typed_context,
            *typed_transform,
            &current_elements_by_id,
        )
    }

    fn update_overlay(
        &self,
        current: crate::draw::models::selection_overlay_state::SelectionOverlayState,
        result: &EditComputedResult,
        context: &EditContext,
    ) -> crate::draw::models::selection_overlay_state::SelectionOverlayState {
        let typed_context = self.require_context(context, "MoveOperation.updateOverlay");
        self.operation
            .update_overlay(current, result, &typed_context)
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
        let next_state = self.finish_standard(state, context, transform);
        self.replace_session(None);
        next_state
    }

    fn build_preview(
        &self,
        state: &DrawState,
        context: &EditContext,
        transform: &EditTransform,
    ) -> EditPreview {
        self.build_preview_standard(state, context, transform)
    }
}

impl StandardFinishMixin for RotateEditOperationAdapter {
    fn compute_result(
        &self,
        state: &DrawState,
        context: &EditContext,
        transform: &EditTransform,
    ) -> Option<EditComputedResult> {
        let EditTransform::Rotate(typed_transform) = transform else {
            return None;
        };

        let typed_context = self.resolve_context(context);
        let current_elements_by_id = state.domain.document.element_map();
        self.operation.compute_result_with_element_map(
            &typed_context,
            *typed_transform,
            &current_elements_by_id,
        )
    }

    fn update_overlay(
        &self,
        current: crate::draw::models::selection_overlay_state::SelectionOverlayState,
        result: &EditComputedResult,
        context: &EditContext,
    ) -> crate::draw::models::selection_overlay_state::SelectionOverlayState {
        let typed_context = self.resolve_context(context);
        self.operation
            .update_overlay(current, result, &typed_context)
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
        EditOperationIds::CONNECTOR_POINT
    }

    fn records_history(&self) -> bool {
        true
    }

    fn create_history_metadata(
        &self,
        context: &EditContext,
        _transform: &EditTransform,
    ) -> HistoryMetadata {
        HistoryMetadata::for_edit(
            "Connector point",
            context.selected_ids_at_start.clone(),
            None,
        )
    }

    fn create_context(
        &self,
        state: &DrawState,
        position: DrawPoint,
        params: &EditOperationParams,
    ) -> EditContext {
        let arrow_params = params.as_connector_point();
        let target = params
            .as_connector_point()
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
        let selected_ids_at_start_in_order =
            state.domain.selection.selected_ids_in_order().to_vec();
        let base = EditContext::new_with_order(
            position,
            start_bounds,
            selected_ids_at_start,
            selected_ids_at_start_in_order,
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
        let allow_binding_on_finalize =
            config.snap.enable_arrow_binding && !modifiers.snap_override;
        let start_binding = typed_transform
            .start_binding
            .clone()
            .or_else(|| typed_context.initial_start_binding.clone());
        let end_binding = typed_transform
            .end_binding
            .clone()
            .or_else(|| typed_context.initial_end_binding.clone());
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
                allow_new_binding: allow_binding_on_finalize,
            },
            &mut binding_lookup,
        );
        if let Some(next_transform) = compute_focus_drag_update_transform(
            state,
            &typed_context,
            typed_transform,
            &updated,
            start_binding,
            end_binding,
            allow_binding_on_finalize,
            modifiers.from_center,
        ) {
            if next_transform == *typed_transform {
                return EditUpdateResult::new(transform.clone());
            }
            return EditUpdateResult::new(EditTransform::ArrowPoint(next_transform));
        }
        let provisional_transform = ArrowPointTransform::with_state(
            updated.current_position,
            updated.points.clone(),
            updated.fixed_segments.clone(),
            updated.start_binding.clone(),
            updated.end_binding.clone(),
            typed_transform.ordered_element_ids.clone(),
            updated.active_index,
            updated.did_insert,
            updated.should_delete,
            updated.has_changes,
            allow_binding_on_finalize,
        );
        let preview_ordered_element_ids = finalize_endpoint_drag_on_finish(
            state,
            &typed_context,
            &provisional_transform,
            provisional_transform.points.as_slice(),
        )
        .map(|result| result.ordered_element_ids)
        .unwrap_or_else(|| typed_transform.ordered_element_ids.clone());
        let next_transform = ArrowPointTransform::with_state(
            updated.current_position,
            updated.points.clone(),
            updated.fixed_segments.clone(),
            updated.start_binding.clone(),
            updated.end_binding.clone(),
            preview_ordered_element_ids,
            updated.active_index,
            updated.did_insert,
            updated.should_delete,
            updated.has_changes,
            allow_binding_on_finalize,
        );

        if next_transform == *typed_transform {
            EditUpdateResult::new(transform.clone())
        } else {
            EditUpdateResult::new(EditTransform::ArrowPoint(next_transform))
        }
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
        let local_points = self
            .operation
            .compute_points_for_result(&into_internal_arrow_transform(typed_transform), true);
        let finalized_endpoint =
            finalize_endpoint_drag_on_finish(state, &typed_context, typed_transform, &local_points);
        let effective_transform = match finalized_endpoint {
            Some(finalized) => typed_transform.copy_with(
                None,
                Some(finalized.points),
                Some(finalized.fixed_segments),
                Some(finalized.start_binding),
                Some(finalized.end_binding),
                Some(finalized.ordered_element_ids),
                None,
                None,
                None,
                Some(true),
                None,
            ),
            None => typed_transform.clone(),
        };
        let internal_transform = into_internal_arrow_transform(&effective_transform);
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
        let next_elements = reorder_elements_by_id_order(
            next_elements,
            effective_transform.ordered_element_ids.as_deref(),
        );
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
    let next_elements =
        reorder_elements_by_id_order(next_elements, result.ordered_element_ids.as_deref());
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
                released.start_binding,
                released.end_binding,
            );
        }
    }

    let (focus_start_handle_position, focus_end_handle_position) = match &target.payload {
        ArrowEditPayload::Arrow(arrow_data) => {
            let mut focus_start_handle_position = None;
            let mut focus_end_handle_position = None;
            for handle in list_visible_arrow_focus_points(
                &target.element,
                arrow_data,
                state.domain.document.elements.as_slice(),
                None,
                false,
            ) {
                match handle.endpoint {
                    ArrowFocusEndpoint::Start => focus_start_handle_position = Some(handle.point),
                    ArrowFocusEndpoint::End => focus_end_handle_position = Some(handle.point),
                }
            }
            (focus_start_handle_position, focus_end_handle_position)
        }
        ArrowEditPayload::Line(_) => {
            let mut focus_start_handle_position = None;
            let mut focus_end_handle_position = None;
            for handle in ConnectorPointUtils::list_visible_focus_points(
                &target.element,
                state.domain.document.elements.as_slice(),
                state.application.view.camera.zoom,
                true,
            ) {
                match handle.kind {
                    crate::draw::elements::types::connector::connector_points::ConnectorPointKind::FocusStart => {
                        focus_start_handle_position = Some(handle.position);
                    }
                    crate::draw::elements::types::connector::connector_points::ConnectorPointKind::FocusEnd => {
                        focus_end_handle_position = Some(handle.position);
                    }
                    _ => {}
                }
            }
            (focus_start_handle_position, focus_end_handle_position)
        }
    };
    context =
        context.with_focus_handle_positions(focus_start_handle_position, focus_end_handle_position);

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
        crate::draw::elements::types::arrow::arrow_points::ArrowPointKind::FocusStart => {
            OperationArrowPointKind::FocusStart
        }
        crate::draw::elements::types::arrow::arrow_points::ArrowPointKind::FocusEnd => {
            OperationArrowPointKind::FocusEnd
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
    state
        .domain
        .document
        .has_arrow_bindable_elements_except(Some(excluded_element_id))
}

#[derive(Clone, Debug, PartialEq)]
struct FinalizeEndpointComputation {
    points: Vec<DrawPoint>,
    start_binding: Option<ArrowDataBinding>,
    end_binding: Option<ArrowDataBinding>,
    fixed_segments: Option<Vec<ArrowDataElbowFixedSegment>>,
    ordered_element_ids: Option<Vec<String>>,
}

fn finalize_endpoint_drag_on_finish(
    state: &DrawState,
    context: &ArrowPointEditContext,
    transform: &ArrowPointTransform,
    local_points: &[DrawPoint],
) -> Option<FinalizeEndpointComputation> {
    if transform.should_delete || local_points.len() < 2 {
        return None;
    }
    if matches!(
        context.point_kind,
        OperationArrowPointKind::Addable
            | OperationArrowPointKind::FocusStart
            | OperationArrowPointKind::FocusEnd
    ) {
        return None;
    }

    let active_index = transform.active_index?;
    if active_index >= local_points.len() {
        return None;
    }
    if active_index != 0 && active_index + 1 != local_points.len() {
        return None;
    }

    let current_element = state
        .domain
        .document
        .get_element_by_id(context.element_id.as_str())?
        .clone();
    let target = resolve_arrow_target_for_element(current_element.clone())?;
    let source_data = connector_source_data_from_payload(&target.payload);
    let release_local_pointer = transform.current_position + context.drag_offset;
    let world_target = context.to_world(release_local_pointer);
    let ordered_element_ids = transform
        .ordered_element_ids
        .clone()
        .unwrap_or_else(|| current_ordered_element_ids(state));

    if let ConnectorSourceData::Arrow(source_data) = &source_data {
        if source_data.arrow_type == ArrowType::Elbow {
            return finalize_elbow_endpoint_drag_on_finish(
                state,
                context,
                transform,
                &current_element,
                source_data,
                local_points,
                release_local_pointer,
                ordered_element_ids.as_slice(),
            );
        }
    }

    let start_binding = transform
        .start_binding
        .as_ref()
        .map(internal_binding_to_compat);
    let end_binding = transform
        .end_binding
        .as_ref()
        .map(internal_binding_to_compat);
    let drag_result = finalize_connector_core_endpoint_drag_result(
        state,
        &current_element,
        &source_data,
        local_points,
        active_index,
        world_target,
        start_binding.as_ref(),
        end_binding.as_ref(),
        context.element_id.as_str(),
        true,
        transform.allow_binding_on_finalize,
        0.0,
        core_context_for_state(state, transform.allow_binding_on_finalize),
        transform.fixed_segments.as_deref(),
        Some(ordered_element_ids.as_slice()),
        Default::default(),
    )?;
    let next_start_binding = drag_result
        .start_binding
        .as_ref()
        .map(compat_binding_to_internal);
    let next_end_binding = drag_result
        .end_binding
        .as_ref()
        .map(compat_binding_to_internal);

    let points_changed = !point_list_equals(local_points, &drag_result.local_points);
    let bindings_changed =
        next_start_binding != transform.start_binding || next_end_binding != transform.end_binding;
    let segments_changed = !fixed_segment_structure_equals_with_tolerance(
        transform.fixed_segments.as_deref(),
        drag_result.fixed_segments.as_deref(),
        1.0,
    );
    let order_changed = drag_result.ordered_element_ids.is_some();
    if !points_changed && !bindings_changed && !segments_changed && !order_changed {
        return None;
    }

    Some(FinalizeEndpointComputation {
        points: drag_result.local_points,
        start_binding: next_start_binding,
        end_binding: next_end_binding,
        fixed_segments: drag_result.fixed_segments,
        ordered_element_ids: drag_result.ordered_element_ids,
    })
}

fn finalize_elbow_endpoint_drag_on_finish(
    state: &DrawState,
    context: &ArrowPointEditContext,
    transform: &ArrowPointTransform,
    current_element: &DomainElementState,
    source_data: &ArrowData,
    local_points: &[DrawPoint],
    release_local_pointer: DrawPoint,
    ordered_element_ids: &[String],
) -> Option<FinalizeEndpointComputation> {
    let base_points = context.initial_points.as_slice();
    if base_points.len() < 2 {
        return None;
    }

    let active_index = transform.active_index?;
    let dragged_start = active_index == 0;
    let dragged_end = active_index + 1 == local_points.len();
    if !dragged_start && !dragged_end {
        return None;
    }

    let mut next_start_binding = transform.start_binding.clone();
    let mut next_end_binding = transform.end_binding.clone();
    let mut hovered_bindable_id = None;
    let mut reordered_element_ids = None;

    if !transform.allow_binding_on_finalize {
        if dragged_start {
            next_start_binding = None;
        } else {
            next_end_binding = None;
        }
    } else {
        let world_target = context.to_world(release_local_pointer);
        let endpoint_index = if dragged_start {
            0
        } else {
            base_points.len() - 1
        };
        let mut preview_points = base_points.to_vec();
        preview_points[endpoint_index] = release_local_pointer;

        let start_binding = transform
            .start_binding
            .as_ref()
            .map(internal_binding_to_compat);
        let end_binding = transform
            .end_binding
            .as_ref()
            .map(internal_binding_to_compat);
        let drag_result = finalize_arrow_core_endpoint_drag_result(
            state,
            current_element,
            source_data,
            &preview_points,
            endpoint_index,
            world_target,
            start_binding.as_ref(),
            end_binding.as_ref(),
            context.element_id.as_str(),
            true,
            transform.allow_binding_on_finalize,
            0.0,
            core_context_for_state(state, transform.allow_binding_on_finalize),
            if context.initial_fixed_segments.is_empty() {
                None
            } else {
                Some(context.initial_fixed_segments.as_slice())
            },
            Some(ordered_element_ids),
            Default::default(),
        )?;
        next_start_binding = drag_result
            .start_binding
            .as_ref()
            .map(compat_binding_to_internal);
        next_end_binding = drag_result
            .end_binding
            .as_ref()
            .map(compat_binding_to_internal);
        hovered_bindable_id = drag_result.suggested_bindable_id;
    }

    if dragged_start {
        next_end_binding = transform.end_binding.clone();
    } else {
        next_start_binding = transform.start_binding.clone();
    }

    let start_point = if dragged_start {
        release_local_pointer
    } else {
        base_points.first().copied().unwrap_or(DrawPoint::ZERO)
    };
    let end_point = if dragged_end {
        release_local_pointer
    } else {
        base_points.last().copied().unwrap_or(DrawPoint::ZERO)
    };

    let updated_data = source_data.copy_with(ArrowDataPatch {
        start_binding: match next_start_binding.clone() {
            Some(binding) => ArrowDataNullableField::Value(binding),
            None => ArrowDataNullableField::Null,
        },
        end_binding: match next_end_binding.clone() {
            Some(binding) => ArrowDataNullableField::Value(binding),
            None => ArrowDataNullableField::Null,
        },
        ..ArrowDataPatch::default()
    });
    let element_map = state.domain.document.element_map();
    let updates: HashMap<String, DomainElementState> = HashMap::new();
    let lookup = CombinedElementLookup::new(&element_map, &updates);
    let updated = compute_elbow_edit(
        current_element,
        &updated_data,
        &lookup,
        Some(vec![start_point, end_point]),
        Some(context.initial_fixed_segments.clone()),
        ElbowBindingOverride::Unset,
        ElbowBindingOverride::Unset,
        true,
    );

    if let Some(hovered_bindable_id) = hovered_bindable_id {
        let reorder =
            reorder_arrow_above_hovered_bindable(&ReorderArrowAboveHoveredBindableInput {
                ordered_element_ids: ordered_element_ids.to_vec(),
                arrow_id: context.element_id.clone(),
                hovered_bindable_id: Some(hovered_bindable_id),
                point: None,
                bindables: None,
                tolerance: None,
                anchor_element_ids_by_bindable_id: Some(
                    state
                        .domain
                        .document
                        .arrow_anchor_element_ids_by_bindable_id()
                        .clone(),
                ),
            });
        reordered_element_ids = reordered_element_ids_from_hovered_reorder(&reorder);
    }

    let base_fixed_segments = if context.initial_fixed_segments.is_empty() {
        None
    } else {
        Some(context.initial_fixed_segments.as_slice())
    };
    let next_start_binding = updated.start_binding.clone();
    let next_end_binding = updated.end_binding.clone();
    let bindings_changed =
        next_start_binding != transform.start_binding || next_end_binding != transform.end_binding;
    if !bindings_changed
        && reordered_element_ids.is_none()
        && base_fixed_segments.is_some()
        && base_points.len() > 2
    {
        let mut updated_points = base_points.to_vec();
        updated_points[0] = local_points.first().copied().unwrap_or(DrawPoint::ZERO);
        let last_index = updated_points.len() - 1;
        updated_points[last_index] = local_points.last().copied().unwrap_or(DrawPoint::ZERO);
        if point_list_equals(base_points, &updated_points) {
            return None;
        }
        return Some(FinalizeEndpointComputation {
            points: updated_points,
            start_binding: next_start_binding,
            end_binding: next_end_binding,
            fixed_segments: Some(context.initial_fixed_segments.clone()),
            ordered_element_ids: reordered_element_ids,
        });
    }

    let points_changed = !point_list_equals(base_points, &updated.local_points);
    let segments_changed = !fixed_segment_structure_equals_with_tolerance(
        base_fixed_segments,
        updated.fixed_segments.as_deref(),
        1.0,
    );
    let order_changed = reordered_element_ids.is_some();
    if !points_changed && !bindings_changed && !segments_changed && !order_changed {
        return None;
    }

    Some(FinalizeEndpointComputation {
        points: updated.local_points,
        start_binding: next_start_binding,
        end_binding: next_end_binding,
        fixed_segments: updated.fixed_segments,
        ordered_element_ids: reordered_element_ids,
    })
}

fn connector_source_data_from_payload(payload: &ArrowEditPayload) -> ConnectorSourceData {
    match payload {
        ArrowEditPayload::Arrow(data) => ConnectorSourceData::Arrow(data.clone()),
        ArrowEditPayload::Line(data) => {
            ConnectorSourceData::Line(LineData::default().copy_with(LineDataPatch {
                points: Some(data.points.clone()),
                color: Some(data.color),
                fill_color: Some(data.fill_color),
                fill_style: Some(data.fill_style),
                stroke_width: Some(data.stroke_width),
                stroke_style: Some(data.stroke_style),
                start_binding: match data.start_binding.as_ref() {
                    Some(binding) => ArrowLikeNullableField::Value(binding.clone()),
                    None => ArrowLikeNullableField::Null,
                },
                end_binding: match data.end_binding.as_ref() {
                    Some(binding) => ArrowLikeNullableField::Value(binding.clone()),
                    None => ArrowLikeNullableField::Null,
                },
                ..LineDataPatch::default()
            }))
        }
    }
}

fn connector_source_data_with_bindings(
    source_data: &ConnectorSourceData,
    start_binding: Option<&ArrowDataBinding>,
    end_binding: Option<&ArrowDataBinding>,
) -> ConnectorSourceData {
    match source_data {
        ConnectorSourceData::Arrow(data) => {
            ConnectorSourceData::Arrow(data.copy_with(ArrowDataPatch {
                start_binding: match start_binding {
                    Some(binding) => ArrowDataNullableField::Value(binding.clone()),
                    None => ArrowDataNullableField::Null,
                },
                end_binding: match end_binding {
                    Some(binding) => ArrowDataNullableField::Value(binding.clone()),
                    None => ArrowDataNullableField::Null,
                },
                ..ArrowDataPatch::default()
            }))
        }
        ConnectorSourceData::Line(data) => {
            ConnectorSourceData::Line(data.copy_with(LineDataPatch {
                start_binding: match start_binding {
                    Some(binding) => {
                        ArrowLikeNullableField::Value(internal_binding_to_compat(binding))
                    }
                    None => ArrowLikeNullableField::Null,
                },
                end_binding: match end_binding {
                    Some(binding) => {
                        ArrowLikeNullableField::Value(internal_binding_to_compat(binding))
                    }
                    None => ArrowLikeNullableField::Null,
                },
                ..LineDataPatch::default()
            }))
        }
    }
}

fn element_with_connector_source_data(
    element: &DomainElementState,
    source_data: &ConnectorSourceData,
) -> DomainElementState {
    match source_data {
        ConnectorSourceData::Arrow(data) => {
            element.copy_with(None, None, None, None, None, Some(Arc::new(data.clone())))
        }
        ConnectorSourceData::Line(data) => {
            element.copy_with(None, None, None, None, None, Some(Arc::new(data.clone())))
        }
    }
}

fn resolve_focus_dragged_edge(kind: OperationArrowPointKind) -> Option<ArrowEndpointEdge> {
    match kind {
        OperationArrowPointKind::FocusStart => Some(ArrowEndpointEdge::Start),
        OperationArrowPointKind::FocusEnd => Some(ArrowEndpointEdge::End),
        _ => None,
    }
}

fn to_lifecycle_focus_arrow_state(
    arrow: &crate::draw::elements::types::arrow::arrow_core::ArrowState,
) -> crate::draw::elements::types::arrow::core::arrow_types::ArrowState {
    crate::draw::elements::types::arrow::core::arrow_types::ArrowState {
        id: arrow.id.clone(),
        x: arrow.x,
        y: arrow.y,
        width: arrow.width,
        height: arrow.height,
        points: arrow.points.clone(),
        start_binding: arrow.start_binding.as_ref().map(to_lifecycle_focus_binding),
        end_binding: arrow.end_binding.as_ref().map(to_lifecycle_focus_binding),
        start_arrowhead: arrow.start_arrowhead.clone(),
        end_arrowhead: arrow.end_arrowhead.clone(),
        elbowed: arrow.elbowed,
        fixed_segments: arrow.fixed_segments.as_ref().map(|segments| {
            segments
                .iter()
                .copied()
                .map(|segment| {
                    crate::draw::elements::types::arrow::core::arrow_types::FixedSegment {
                        start: segment.start,
                        end: segment.end,
                        index: segment.index,
                    }
                })
                .collect()
        }),
        start_is_special: arrow.start_is_special,
        end_is_special: arrow.end_is_special,
    }
}

fn to_lifecycle_focus_binding(
    binding: &CompatArrowBinding,
) -> crate::draw::elements::types::arrow::core::arrow_types::FixedPointBinding {
    crate::draw::elements::types::arrow::core::arrow_types::FixedPointBinding::new(
        binding.element_id.clone(),
        binding.anchor,
        binding.mode.as_str().to_string(),
    )
}

fn to_lifecycle_focus_bindable_state(
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

fn to_lifecycle_focus_context(
    context: &crate::draw::elements::types::arrow::arrow_core::EngineContext,
) -> crate::draw::elements::types::arrow::core::arrow_types::EngineContext {
    crate::draw::elements::types::arrow::core::arrow_types::EngineContext {
        zoom: context.zoom,
        is_binding_enabled: context.is_binding_enabled,
        bind_mode: context.bind_mode,
        max_coordinate: context.max_coordinate,
    }
}

#[allow(clippy::too_many_arguments)]
fn compute_focus_drag_update_transform(
    state: &DrawState,
    context: &ArrowPointEditContext,
    previous_transform: &ArrowPointTransform,
    updated: &InternalArrowPointTransform,
    start_binding: Option<ArrowDataBinding>,
    end_binding: Option<ArrowDataBinding>,
    allow_binding_on_finalize: bool,
    switch_to_inside_binding: bool,
) -> Option<ArrowPointTransform> {
    let dragged_edge = resolve_focus_dragged_edge(context.point_kind)?;
    if updated.points.len() < 2 {
        return None;
    }

    let active_index = match dragged_edge {
        ArrowEndpointEdge::Start => 0,
        ArrowEndpointEdge::End => updated.points.len().checked_sub(1)?,
    };
    let current_element = state
        .domain
        .document
        .get_element_by_id(context.element_id.as_str())?
        .clone();
    let target = resolve_arrow_target_for_element(current_element.clone())?;
    let source_data = connector_source_data_from_payload(&target.payload);
    if source_data.arrow_type() == ArrowType::Elbow {
        return None;
    }

    let drag_source_data = connector_source_data_with_bindings(
        &source_data,
        start_binding.as_ref(),
        end_binding.as_ref(),
    );
    let drag_source_element =
        element_with_connector_source_data(&current_element, &drag_source_data);
    let ordered_element_ids = previous_transform
        .ordered_element_ids
        .clone()
        .unwrap_or_else(|| current_ordered_element_ids(state));
    let pointer = context.to_world(updated.points[active_index]);
    let session = ArrowScene::from_elements_with_options(
        state.domain.document.elements.clone(),
        false,
        Some(ordered_element_ids.as_slice()),
        Some(core_context_for_state(state, allow_binding_on_finalize)),
    );
    let arrow = to_core_arrow_state_from_source(
        &drag_source_element,
        &drag_source_data,
        None,
        None,
        None,
        None,
        session.context.max_coordinate,
    );
    let lifecycle_arrow = to_lifecycle_focus_arrow_state(&arrow);
    let lifecycle_bindables = session
        .bindables()
        .iter()
        .map(to_lifecycle_focus_bindable_state)
        .collect::<Vec<_>>();
    let result = compute_focus_drag(
        &lifecycle_arrow,
        pointer,
        dragged_edge,
        &lifecycle_bindables,
        to_lifecycle_focus_context(&session.context),
        switch_to_inside_binding,
    );
    let suggested_bindable_id = result.suggested_binding.as_ref().and_then(|binding| {
        binding
            .bindable_id
            .clone()
            .or_else(|| (!binding.element.id.is_empty()).then(|| binding.element.id.clone()))
    });
    let applied = session.apply_engine_result_with_order_fallback(
        &arrow,
        &result,
        suggested_bindable_id.as_deref(),
        Some(pointer),
        Some(ordered_element_ids.as_slice()),
        None,
    );

    let patched_elements = apply_core_arrow_patches_to_sources(
        &[ArrowStatePatchWithId {
            id: drag_source_element.id.clone(),
            patch: result.arrow_patch.clone(),
        }],
        &HashMap::from([(
            drag_source_element.id.clone(),
            (drag_source_element.clone(), drag_source_data),
        )]),
    );
    let patched_element = patched_elements
        .get(&drag_source_element.id)
        .cloned()
        .unwrap_or(drag_source_element.clone());
    let patched_target = resolve_arrow_target_for_element(patched_element.clone())?;
    let next_points =
        ArrowGeometry::resolve_world_points(patched_target.element.rect, patched_target.points());
    if next_points.len() < 2 {
        return None;
    }

    let next_start_binding = patched_target.start_binding();
    let next_end_binding = patched_target.end_binding();
    let next_fixed_segments = {
        let segments = patched_target.fixed_segments();
        (!segments.is_empty()).then_some(segments)
    };
    let base_fixed_segments = (!context.initial_fixed_segments.is_empty())
        .then_some(context.initial_fixed_segments.clone());
    let points_changed = !point_list_equals(&context.initial_points, &next_points);
    let bindings_changed = next_start_binding != start_binding || next_end_binding != end_binding;
    let segments_changed = !fixed_segment_structure_equals_with_tolerance(
        base_fixed_segments.as_deref(),
        next_fixed_segments.as_deref(),
        1.0,
    );
    let drag_result_has_changes = patched_element != drag_source_element
        || !result.bindable_patches.is_empty()
        || applied.ordered_element_ids.is_some();

    Some(ArrowPointTransform::with_state(
        updated.current_position,
        next_points,
        next_fixed_segments,
        next_start_binding,
        next_end_binding,
        applied.ordered_element_ids,
        Some(active_index),
        false,
        false,
        drag_result_has_changes || points_changed || bindings_changed || segments_changed,
        allow_binding_on_finalize,
    ))
}

fn current_ordered_element_ids(state: &DrawState) -> Vec<String> {
    state
        .domain
        .document
        .elements
        .iter()
        .map(|element| element.id.clone())
        .collect()
}

fn core_context_for_state(
    state: &DrawState,
    is_binding_enabled: bool,
) -> crate::draw::elements::types::arrow::arrow_core::EngineContext {
    build_core_engine_context(
        state.application.view.camera.zoom,
        is_binding_enabled,
        resolve_endpoint_drag_binding_enabled(is_binding_enabled),
        DEFAULT_MAX_COORDINATE,
    )
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
                let has_finalized_endpoint_path = finalize
                    && context.point_kind == OperationArrowPointKind::Turning
                    && transform
                        .active_index
                        .is_some_and(|index| index >= next_world_points.len())
                    && transform.fixed_segments.is_some();
                if has_finalized_endpoint_path {
                    let geometry = resolve_arrow_geometry_update(
                        &next_world_points,
                        context.element_rect,
                        context.rotation,
                        data.arrow_type,
                    );
                    let transformed_fixed_segments = transform_fixed_segments(
                        transform.fixed_segments.as_deref(),
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
                        ..ArrowDataPatch::default()
                    });
                    return Some(DomainElementState::new(
                        current_element.id.clone(),
                        geometry.rect,
                        current_element.rotation,
                        current_element.opacity,
                        current_element.z_index,
                        Arc::new(updated_data),
                    ));
                }

                let element_map = state.domain.document.element_map();
                let updates = HashMap::new();
                let lookup = CombinedElementLookup::new(&element_map, &updates);
                let active_index = transform.active_index;
                let is_endpoint_turning_drag = context.point_kind
                    == OperationArrowPointKind::Turning
                    && active_index
                        .is_some_and(|index| index == 0 || index + 1 == next_world_points.len());
                let is_fixed_segment_editing =
                    context.point_kind == OperationArrowPointKind::Addable;
                let should_release_fixed_segment =
                    is_fixed_segment_editing && context.release_fixed_segment;
                let elbow_points_override = if should_release_fixed_segment {
                    None
                } else if is_endpoint_turning_drag {
                    Some(vec![
                        next_world_points
                            .first()
                            .copied()
                            .unwrap_or(DrawPoint::ZERO),
                        next_world_points.last().copied().unwrap_or(DrawPoint::ZERO),
                    ])
                } else {
                    Some(next_world_points.clone())
                };
                let fixed_segments_override = if is_fixed_segment_editing {
                    if should_release_fixed_segment {
                        Some(transform.fixed_segments.clone().unwrap_or_default())
                    } else {
                        transform.fixed_segments.clone()
                    }
                } else {
                    None
                };
                let updated = compute_elbow_edit(
                    &current_element,
                    &data_with_bindings,
                    &lookup,
                    elbow_points_override,
                    fixed_segments_override,
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
                let mut resolved_start_binding = updated.start_binding.clone();
                let mut resolved_end_binding = updated.end_binding.clone();
                if is_endpoint_turning_drag {
                    if active_index == Some(0) {
                        resolved_end_binding = transform.end_binding.clone();
                    } else {
                        resolved_start_binding = transform.start_binding.clone();
                    }
                }
                let updated_data = data_with_bindings.copy_with(ArrowDataPatch {
                    points: Some(geometry.normalized_points),
                    start_binding: match resolved_start_binding {
                        Some(binding) => ArrowDataNullableField::Value(binding),
                        None => ArrowDataNullableField::Null,
                    },
                    end_binding: match resolved_end_binding {
                        Some(binding) => ArrowDataNullableField::Value(binding),
                        None => ArrowDataNullableField::Null,
                    },
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
        None,
        transform.active_index,
        transform.did_insert,
        transform.should_delete,
        transform.has_changes,
        true,
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

#[cfg(test)]
mod tests {
    use super::*;

    use std::collections::BTreeSet;

    use crate::draw::config::draw_config::DrawConfig;
    use crate::draw::elements::core::creation_strategy::{
        CreatingState, CreationStrategy, ElementState as CreatingElementState,
    };
    use crate::draw::elements::types::arrow::arrow_creation_strategy::ArrowCreationStrategy;
    use crate::draw::elements::types::connector::connector_points::ConnectorPointKind as EditConnectorPointKind;
    use crate::draw::elements::types::rectangle::rectangle_data::RectangleData;
    use crate::draw::elements::types::serial_number::serial_number_data::{
        SerialNumberData, SerialNumberDataPatch,
    };
    use crate::draw::elements::types::text::text_data::TextData;
    use crate::draw::history::history_metadata::HistoryRecordType;
    use crate::draw::models::application_state::ApplicationState;
    use crate::draw::models::draw_state::{DomainDocumentState, DomainState, DrawState};
    use crate::draw::models::selection_state::SelectionState;

    fn arrow_element(
        id: &str,
        rect: DrawRect,
        data: ArrowData,
        z_index: i64,
    ) -> DomainElementState {
        DomainElementState::new(id.to_owned(), rect, 0.0, 1.0, z_index, Arc::new(data))
    }

    fn rectangle_element(id: &str, rect: DrawRect, z_index: i64) -> DomainElementState {
        DomainElementState::new(
            id.to_owned(),
            rect,
            0.0,
            1.0,
            z_index,
            Arc::new(RectangleData::default()),
        )
    }

    fn text_element(id: &str, rect: DrawRect, z_index: i64) -> DomainElementState {
        DomainElementState::new(
            id.to_owned(),
            rect,
            0.0,
            1.0,
            z_index,
            Arc::new(TextData::default()),
        )
    }

    fn serial_number_element(
        id: &str,
        rect: DrawRect,
        z_index: i64,
        text_element_id: &str,
    ) -> DomainElementState {
        let data = SerialNumberData::default().copy_with(SerialNumberDataPatch {
            text_element_id: Some(Some(text_element_id.to_owned())),
            ..SerialNumberDataPatch::default()
        });
        DomainElementState::new(id.to_owned(), rect, 0.0, 1.0, z_index, Arc::new(data))
    }

    fn draw_state(elements: Vec<DomainElementState>) -> DrawState {
        let domain = DomainState::new(
            DomainDocumentState::new(elements, 1, Default::default()),
            Default::default(),
        );
        DrawState::new(Some(domain), Some(ApplicationState::initial(None)))
    }

    #[test]
    fn custom_registry_preserves_first_insertion_order_for_duplicate_ids() {
        let registry = DefaultEditOperationRegistry::custom(vec![
            Arc::new(MoveEditOperationAdapter::new()) as SharedEditOperation,
            Arc::new(RotateEditOperationAdapter::new()) as SharedEditOperation,
            Arc::new(MoveEditOperationAdapter::new()) as SharedEditOperation,
        ]);

        let operation_ids = registry.all_operation_ids().collect::<Vec<_>>();

        assert_eq!(
            operation_ids,
            vec![EditOperationIds::MOVE, EditOperationIds::ROTATE]
        );
    }

    fn draw_state_with_selection(
        elements: Vec<DomainElementState>,
        selected_ids: &[&str],
    ) -> DrawState {
        let selected_ids = selected_ids
            .iter()
            .map(|id| (*id).to_owned())
            .collect::<BTreeSet<_>>();
        let domain = DomainState::new(
            DomainDocumentState::new(elements, 1, Default::default()),
            SelectionState::new(selected_ids, 1),
        );
        DrawState::new(Some(domain), Some(ApplicationState::initial(None)))
    }

    fn elbow_arrow_element(
        id: &str,
        points: &[DrawPoint],
        z_index: i64,
        fixed_segments: Option<Vec<ArrowDataElbowFixedSegment>>,
        start_binding: Option<ArrowDataBinding>,
        end_binding: Option<ArrowDataBinding>,
    ) -> DomainElementState {
        let rect = DrawRect::from_point_cloud(points.iter().copied());
        let normalized_points = ArrowGeometry::normalize_points(points, rect);
        let data = ArrowData::default().copy_with(ArrowDataPatch {
            points: Some(normalized_points),
            arrow_type: Some(ArrowType::Elbow),
            start_binding: match start_binding {
                Some(binding) => ArrowDataNullableField::Value(binding),
                None => ArrowDataNullableField::Null,
            },
            end_binding: match end_binding {
                Some(binding) => ArrowDataNullableField::Value(binding),
                None => ArrowDataNullableField::Null,
            },
            fixed_segments: match fixed_segments {
                Some(segments) => ArrowDataNullableField::Value(segments),
                None => ArrowDataNullableField::Unset,
            },
            ..ArrowDataPatch::default()
        });
        arrow_element(id, rect, data, z_index)
    }

    fn drag_arrow_handle_session(
        state: &DrawState,
        element_id: &str,
        point_kind: EditConnectorPointKind,
        point_index: usize,
        start_position: DrawPoint,
        current_position: DrawPoint,
    ) -> (
        ArrowPointEditOperationAdapter,
        EditContext,
        ArrowPointTransform,
    ) {
        drag_arrow_handle_session_with_modifiers(
            state,
            element_id,
            point_kind,
            point_index,
            start_position,
            current_position,
            EditModifiers::default(),
        )
    }

    fn drag_arrow_handle_session_with_modifiers(
        state: &DrawState,
        element_id: &str,
        point_kind: EditConnectorPointKind,
        point_index: usize,
        start_position: DrawPoint,
        current_position: DrawPoint,
        modifiers: EditModifiers,
    ) -> (
        ArrowPointEditOperationAdapter,
        EditContext,
        ArrowPointTransform,
    ) {
        let operation = ArrowPointEditOperationAdapter::new();
        let context = operation.create_context(
            state,
            start_position,
            &EditOperationParams::from(TypedArrowPointOperationParams::new(
                element_id,
                point_kind,
                point_index,
            )),
        );
        let initial = operation.initial_transform(state, &context, start_position);
        let update = operation.update(
            state,
            &context,
            &initial,
            current_position,
            modifiers,
            DrawConfig::default_config(),
        );
        let EditTransform::ArrowPoint(transform) = update.transform else {
            panic!("expected arrow-point transform");
        };

        (operation, context, transform)
    }

    fn create_elbow_arrow_via_creation(
        state: &DrawState,
        id: &str,
        start_position: DrawPoint,
        mid_position: DrawPoint,
        end_position: DrawPoint,
        z_index: i64,
    ) -> DomainElementState {
        let strategy = ArrowCreationStrategy::new();
        let start = strategy.start(
            Arc::new(ArrowData::default().copy_with(ArrowDataPatch {
                arrow_type: Some(ArrowType::Elbow),
                ..ArrowDataPatch::default()
            })),
            start_position,
            None,
        );

        let mut creating = CreatingState {
            element: CreatingElementState {
                id: format!("draft-{id}"),
                type_id_value: ArrowData::TYPE_ID_TOKEN.to_owned(),
                rect: start.rect,
                rotation: 0.0,
                opacity: 1.0,
                z_index,
                data: start.data,
            },
            start_position,
            current_rect: start.rect,
            snap_guides: Vec::new(),
            creation_mode: start.creation_mode,
        };

        let first_update = strategy.update(
            state,
            DrawConfig::default_config(),
            &creating,
            mid_position,
            false,
            false,
            SnappingMode::None,
            false,
            None,
        );
        creating = creating.copy_with(
            Some(creating.element.copy_with(
                None,
                Some(first_update.rect),
                None,
                None,
                None,
                Some(first_update.data),
            )),
            None,
            Some(first_update.rect),
            Some(first_update.snap_guides),
            Some(first_update.creation_mode),
        );

        let second_update = strategy.update(
            state,
            DrawConfig::default_config(),
            &creating,
            end_position,
            false,
            false,
            SnappingMode::None,
            false,
            None,
        );
        creating = creating.copy_with(
            Some(creating.element.copy_with(
                None,
                Some(second_update.rect),
                None,
                None,
                None,
                Some(second_update.data),
            )),
            None,
            Some(second_update.rect),
            Some(second_update.snap_guides),
            Some(second_update.creation_mode),
        );

        let finish = strategy.finish(state, DrawConfig::default_config(), &creating, None);
        assert!(finish.should_commit, "expected elbow creation to commit");
        let data = finish
            .data
            .as_ref()
            .as_any()
            .downcast_ref::<ArrowData>()
            .expect("created elbow arrow data")
            .clone();

        DomainElementState::new(
            id.to_owned(),
            finish.rect,
            0.0,
            1.0,
            z_index,
            Arc::new(data),
        )
    }

    #[test]
    fn finalize_elbow_endpoint_drag_updates_binding_and_order() {
        let arrow_data = ArrowData::default().copy_with(ArrowDataPatch {
            arrow_type: Some(ArrowType::Elbow),
            end_arrowhead: Some(ArrowheadStyle::Standard),
            ..ArrowDataPatch::default()
        });
        let arrow = arrow_element(
            "arrow",
            DrawRect::new(0.0, 0.0, 80.0, 60.0),
            arrow_data.clone(),
            0,
        );
        let target = rectangle_element("box", DrawRect::new(90.0, 90.0, 130.0, 130.0), 1);
        let state = draw_state(vec![arrow.clone(), target]);
        let local_points = vec![
            DrawPoint::new(0.0, 0.0),
            DrawPoint::new(20.0, 0.0),
            DrawPoint::new(20.0, 20.0),
            DrawPoint::new(110.0, 110.0),
        ];
        let context = ArrowPointEditContext::from_start_position(
            arrow.id.clone(),
            arrow.rect,
            arrow.rotation,
            DrawPoint::new(110.0, 110.0),
            local_points.clone(),
            Vec::new(),
            ArrowType::Elbow,
            OperationArrowPointKind::Turning,
            local_points.len() - 1,
            false,
            false,
            ArrowheadStyle::None,
            ArrowheadStyle::Standard,
            None,
            None,
            true,
        );
        let transform = ArrowPointTransform::with_state(
            DrawPoint::new(110.0, 110.0),
            local_points.clone(),
            None,
            None,
            None,
            None,
            Some(local_points.len() - 1),
            false,
            false,
            true,
            true,
        );

        let finalized =
            finalize_endpoint_drag_on_finish(&state, &context, &transform, &local_points)
                .expect("finalized elbow endpoint drag");

        assert_eq!(
            finalized
                .end_binding
                .as_ref()
                .map(|binding| binding.element_id.as_str()),
            Some("box")
        );
        assert_eq!(finalized.start_binding, None);
        assert_eq!(
            finalized.points.first().copied(),
            Some(DrawPoint::new(0.0, 0.0))
        );
        assert_eq!(
            finalized.points.last().copied(),
            Some(DrawPoint::new(84.0, 110.0))
        );
        assert_eq!(
            finalized.ordered_element_ids,
            Some(vec!["box".to_owned(), "arrow".to_owned()])
        );
    }

    #[test]
    fn finalize_elbow_endpoint_drag_reroutes_from_endpoints_only() {
        let fixed_segments = vec![
            ArrowDataElbowFixedSegment::new(
                2,
                DrawPoint::new(20.0, 0.0),
                DrawPoint::new(20.0, 20.0),
            ),
            ArrowDataElbowFixedSegment::new(
                4,
                DrawPoint::new(40.0, 20.0),
                DrawPoint::new(40.0, 40.0),
            ),
        ];
        let initial_points = vec![
            DrawPoint::new(0.0, 0.0),
            DrawPoint::new(20.0, 0.0),
            DrawPoint::new(20.0, 20.0),
            DrawPoint::new(40.0, 20.0),
            DrawPoint::new(40.0, 40.0),
            DrawPoint::new(60.0, 40.0),
            DrawPoint::new(60.0, 60.0),
            DrawPoint::new(80.0, 60.0),
        ];
        let preview_points = vec![
            DrawPoint::new(0.0, 10.0),
            DrawPoint::new(20.0, 0.0),
            DrawPoint::new(20.0, 20.0),
            DrawPoint::new(40.0, 20.0),
            DrawPoint::new(40.0, 40.0),
            DrawPoint::new(60.0, 40.0),
            DrawPoint::new(60.0, 60.0),
            DrawPoint::new(80.0, 60.0),
            DrawPoint::new(80.0, 90.0),
        ];
        let arrow_data = ArrowData::default().copy_with(ArrowDataPatch {
            arrow_type: Some(ArrowType::Elbow),
            points: Some(initial_points.clone()),
            fixed_segments: ArrowDataNullableField::Value(fixed_segments.clone()),
            end_arrowhead: Some(ArrowheadStyle::Standard),
            ..ArrowDataPatch::default()
        });
        let arrow = arrow_element("arrow", DrawRect::new(0.0, 0.0, 80.0, 60.0), arrow_data, 0);
        let state = draw_state(vec![arrow.clone()]);
        let context = ArrowPointEditContext::from_start_position(
            arrow.id.clone(),
            arrow.rect,
            arrow.rotation,
            DrawPoint::new(80.0, 60.0),
            initial_points,
            fixed_segments,
            ArrowType::Elbow,
            OperationArrowPointKind::Turning,
            7,
            false,
            false,
            ArrowheadStyle::None,
            ArrowheadStyle::Standard,
            None,
            None,
            false,
        );
        let transform = ArrowPointTransform::with_state(
            DrawPoint::new(80.0, 90.0),
            preview_points.clone(),
            Some(vec![
                ArrowDataElbowFixedSegment::new(
                    2,
                    DrawPoint::new(20.0, 0.0),
                    DrawPoint::new(20.0, 20.0),
                ),
                ArrowDataElbowFixedSegment::new(
                    4,
                    DrawPoint::new(40.0, 20.0),
                    DrawPoint::new(40.0, 40.0),
                ),
            ]),
            None,
            None,
            None,
            Some(preview_points.len() - 1),
            false,
            false,
            true,
            true,
        );

        let finalized =
            finalize_endpoint_drag_on_finish(&state, &context, &transform, &preview_points)
                .expect("finalized elbow endpoint reroute");
        assert_eq!(finalized.points.len(), 8);
        assert_eq!(finalized.fixed_segments.as_ref().map(Vec::len), Some(2));
        let effective_transform = transform.copy_with(
            None,
            Some(finalized.points),
            Some(finalized.fixed_segments),
            Some(finalized.start_binding),
            Some(finalized.end_binding),
            Some(finalized.ordered_element_ids),
            None,
            None,
            None,
            Some(true),
            None,
        );
        let updated_element = compute_updated_arrow_element(
            &ArrowPointOperation::new(),
            &state,
            &context,
            &into_internal_arrow_transform(&effective_transform),
            true,
            true,
        )
        .expect("updated elbow element");
        let updated_target =
            resolve_arrow_target_for_element(updated_element.clone()).expect("arrow target");
        let updated_data = match updated_target.payload {
            ArrowEditPayload::Arrow(data) => data,
            ArrowEditPayload::Line(_) => panic!("expected arrow payload"),
        };
        let updated_points =
            ArrowGeometry::resolve_world_points(updated_target.element.rect, &updated_data.points);

        assert_eq!(updated_points.len(), 8);
        assert_eq!(
            updated_points.first().copied(),
            Some(DrawPoint::new(0.0, 10.0))
        );
        assert_eq!(
            updated_points.last().copied(),
            Some(DrawPoint::new(80.0, 90.0))
        );
        assert_eq!(updated_data.fixed_segments.as_ref().map(Vec::len), Some(2));
    }

    #[test]
    fn finalize_elbow_endpoint_drag_reorders_above_serial_text_anchor_group() {
        let arrow_data = ArrowData::default().copy_with(ArrowDataPatch {
            arrow_type: Some(ArrowType::Elbow),
            end_arrowhead: Some(ArrowheadStyle::Standard),
            ..ArrowDataPatch::default()
        });
        let arrow = arrow_element("arrow", DrawRect::new(0.0, 0.0, 80.0, 60.0), arrow_data, 0);
        let serial = serial_number_element(
            "serial",
            DrawRect::new(90.0, 90.0, 130.0, 130.0),
            2,
            "serial-text",
        );
        let text = text_element("serial-text", DrawRect::new(140.0, 90.0, 190.0, 130.0), 1);
        let state = draw_state(vec![arrow.clone(), text, serial]);
        let local_points = vec![
            DrawPoint::new(0.0, 0.0),
            DrawPoint::new(20.0, 0.0),
            DrawPoint::new(20.0, 20.0),
            DrawPoint::new(110.0, 110.0),
        ];
        let context = ArrowPointEditContext::from_start_position(
            arrow.id.clone(),
            arrow.rect,
            arrow.rotation,
            DrawPoint::new(110.0, 110.0),
            local_points.clone(),
            Vec::new(),
            ArrowType::Elbow,
            OperationArrowPointKind::Turning,
            local_points.len() - 1,
            false,
            false,
            ArrowheadStyle::None,
            ArrowheadStyle::Standard,
            None,
            None,
            true,
        );
        let transform = ArrowPointTransform::with_state(
            DrawPoint::new(110.0, 110.0),
            local_points.clone(),
            None,
            None,
            None,
            None,
            Some(local_points.len() - 1),
            false,
            false,
            true,
            true,
        );

        let finalized =
            finalize_endpoint_drag_on_finish(&state, &context, &transform, &local_points)
                .expect("finalized elbow endpoint drag");

        assert_eq!(
            finalized.ordered_element_ids,
            Some(vec![
                "serial-text".to_owned(),
                "arrow".to_owned(),
                "serial".to_owned(),
            ])
        );
    }

    #[test]
    fn dragging_elbow_end_endpoint_keeps_existing_start_binding_element() {
        let start_target = rectangle_element(
            "elbow-start-target",
            DrawRect::new(40.0, 40.0, 140.0, 140.0),
            1,
        );
        let end_target = rectangle_element(
            "elbow-end-target",
            DrawRect::new(320.0, 40.0, 420.0, 140.0),
            2,
        );
        let arrow = elbow_arrow_element(
            "elbow-bound-end-drag",
            &[DrawPoint::new(130.0, 60.0), DrawPoint::new(260.0, 90.0)],
            3,
            None,
            Some(ArrowDataBinding::new(
                "elbow-start-target",
                DrawPoint::new(0.9, 0.2),
                ArrowDataBindingMode::Orbit,
            )),
            None,
        );
        let state = draw_state_with_selection(
            vec![start_target.clone(), end_target.clone(), arrow.clone()],
            &[arrow.id.as_str()],
        );

        let (operation, context, transform) = drag_arrow_handle_session(
            &state,
            &arrow.id,
            EditConnectorPointKind::Turning,
            1,
            DrawPoint::new(260.0, 90.0),
            DrawPoint::new(330.0, 90.0),
        );
        let next = operation.finish(&state, &context, &EditTransform::ArrowPoint(transform));
        let updated_arrow = next
            .domain
            .document
            .get_element_by_id(&arrow.id)
            .expect("updated arrow")
            .clone();
        let updated_target = resolve_arrow_target_for_element(updated_arrow).expect("arrow target");
        let updated_data = match updated_target.payload {
            ArrowEditPayload::Arrow(data) => data,
            ArrowEditPayload::Line(_) => panic!("expected arrow payload"),
        };

        let start_binding = updated_data.start_binding.as_ref().expect("start binding");
        let end_binding = updated_data.end_binding.as_ref().expect("end binding");
        assert_eq!(start_binding.element_id, start_target.id);
        assert!((start_binding.anchor.x - 0.9).abs() < 1e-6);
        assert!((start_binding.anchor.y - 0.2).abs() < 1e-6);
        assert_eq!(end_binding.element_id, end_target.id);
    }

    #[test]
    fn finish_keeps_endpoint_unbound_when_snap_override_is_active() {
        let initial_target = rectangle_element(
            "rect-initial-finish",
            DrawRect::new(180.0, 0.0, 260.0, 120.0),
            1,
        );
        let next_target = rectangle_element(
            "rect-next-finish",
            DrawRect::new(340.0, 0.0, 440.0, 120.0),
            2,
        );
        let arrow_data = ArrowData::default().copy_with(ArrowDataPatch {
            points: Some(ArrowGeometry::normalize_points(
                &[DrawPoint::new(80.0, 60.0), DrawPoint::new(220.0, 60.0)],
                DrawRect::new(80.0, 60.0, 220.0, 60.0),
            )),
            end_binding: ArrowDataNullableField::Value(ArrowDataBinding::new(
                "rect-initial-finish",
                DrawPoint::new(0.0, 0.5),
                ArrowDataBindingMode::Orbit,
            )),
            ..ArrowDataPatch::default()
        });
        let arrow = arrow_element(
            "arrow-snap-finish",
            DrawRect::new(80.0, 60.0, 220.0, 60.0),
            arrow_data,
            3,
        );
        let state = draw_state_with_selection(
            vec![initial_target, next_target, arrow.clone()],
            &[arrow.id.as_str()],
        );

        let (operation, context, transform) = drag_arrow_handle_session_with_modifiers(
            &state,
            &arrow.id,
            EditConnectorPointKind::Turning,
            1,
            DrawPoint::new(220.0, 60.0),
            DrawPoint::new(360.0, 60.0),
            EditModifiers {
                snap_override: true,
                ..EditModifiers::default()
            },
        );
        let next = operation.finish(&state, &context, &EditTransform::ArrowPoint(transform));
        let updated_arrow = next
            .domain
            .document
            .get_element_by_id(&arrow.id)
            .expect("updated arrow")
            .clone();
        let updated_target = resolve_arrow_target_for_element(updated_arrow).expect("arrow target");
        let updated_data = match updated_target.payload {
            ArrowEditPayload::Arrow(data) => data,
            ArrowEditPayload::Line(_) => panic!("expected arrow payload"),
        };

        assert_eq!(updated_data.end_binding, None);
    }

    #[test]
    fn snap_override_prevents_reorder_fallback_while_dragging_endpoint() {
        let bind_target = rectangle_element(
            "rect-snap-reorder",
            DrawRect::new(220.0, 0.0, 320.0, 120.0),
            1,
        );
        let arrow_data = ArrowData::default().copy_with(ArrowDataPatch {
            points: Some(ArrowGeometry::normalize_points(
                &[DrawPoint::new(60.0, 60.0), DrawPoint::new(160.0, 60.0)],
                DrawRect::new(60.0, 60.0, 160.0, 60.0),
            )),
            ..ArrowDataPatch::default()
        });
        let arrow = arrow_element(
            "arrow-snap-reorder",
            DrawRect::new(60.0, 60.0, 160.0, 60.0),
            arrow_data,
            0,
        );
        let state =
            draw_state_with_selection(vec![arrow.clone(), bind_target], &[arrow.id.as_str()]);

        let (operation, context, transform) = drag_arrow_handle_session_with_modifiers(
            &state,
            &arrow.id,
            EditConnectorPointKind::Turning,
            1,
            DrawPoint::new(160.0, 60.0),
            DrawPoint::new(240.0, 60.0),
            EditModifiers {
                snap_override: true,
                ..EditModifiers::default()
            },
        );
        assert_eq!(transform.end_binding, None);
        assert_eq!(transform.ordered_element_ids, None);

        let next = operation.finish(&state, &context, &EditTransform::ArrowPoint(transform));
        let ordered_ids = next
            .domain
            .document
            .elements
            .iter()
            .map(|element| element.id.clone())
            .collect::<Vec<_>>();

        assert_eq!(
            ordered_ids,
            vec![arrow.id.clone(), "rect-snap-reorder".to_owned()]
        );
    }

    #[test]
    fn finish_finalizes_endpoint_drag_with_core_default_same_target_behavior() {
        let bind_target =
            rectangle_element("rect-shared", DrawRect::new(0.0, 0.0, 120.0, 120.0), 1);
        let arrow_data = ArrowData::default().copy_with(ArrowDataPatch {
            points: Some(ArrowGeometry::normalize_points(
                &[DrawPoint::new(100.0, 60.0), DrawPoint::new(80.0, 60.0)],
                DrawRect::new(80.0, 60.0, 100.0, 60.0),
            )),
            start_binding: ArrowDataNullableField::Value(ArrowDataBinding::new(
                "rect-shared",
                DrawPoint::new(1.0, 0.5),
                ArrowDataBindingMode::Orbit,
            )),
            end_binding: ArrowDataNullableField::Value(ArrowDataBinding::new(
                "rect-shared",
                DrawPoint::new(0.8, 0.5),
                ArrowDataBindingMode::Orbit,
            )),
            ..ArrowDataPatch::default()
        });
        let arrow = arrow_element(
            "arrow-shared",
            DrawRect::new(80.0, 60.0, 100.0, 60.0),
            arrow_data,
            2,
        );
        let state = draw_state_with_selection(
            vec![bind_target.clone(), arrow.clone()],
            &[arrow.id.as_str()],
        );

        let (operation, context, transform) = drag_arrow_handle_session(
            &state,
            &arrow.id,
            EditConnectorPointKind::Turning,
            0,
            DrawPoint::new(100.0, 60.0),
            DrawPoint::new(92.0, 60.0),
        );
        assert!(transform.start_binding.is_some());
        assert!(transform.end_binding.is_some());

        let next = operation.finish(&state, &context, &EditTransform::ArrowPoint(transform));
        let updated_arrow = next
            .domain
            .document
            .get_element_by_id(&arrow.id)
            .expect("updated arrow")
            .clone();
        let updated_target = resolve_arrow_target_for_element(updated_arrow).expect("arrow target");
        let updated_data = match updated_target.payload {
            ArrowEditPayload::Arrow(data) => data,
            ArrowEditPayload::Line(_) => panic!("expected arrow payload"),
        };

        let start_binding = updated_data.start_binding.as_ref().expect("start binding");
        let end_binding = updated_data.end_binding.as_ref().expect("end binding");
        assert_eq!(start_binding.element_id, bind_target.id);
        assert_eq!(start_binding.mode, ArrowDataBindingMode::Inside);
        assert_eq!(end_binding.element_id, bind_target.id);
        assert_eq!(end_binding.mode, ArrowDataBindingMode::Inside);
    }

    #[test]
    fn dragging_endpoint_with_from_center_requests_inside_binding_mode() {
        let bind_target =
            rectangle_element("rect-target", DrawRect::new(220.0, 0.0, 320.0, 120.0), 1);
        let arrow_data = ArrowData::default().copy_with(ArrowDataPatch {
            points: Some(ArrowGeometry::normalize_points(
                &[DrawPoint::new(60.0, 60.0), DrawPoint::new(160.0, 60.0)],
                DrawRect::new(60.0, 60.0, 160.0, 60.0),
            )),
            ..ArrowDataPatch::default()
        });
        let arrow = arrow_element(
            "arrow-inside",
            DrawRect::new(60.0, 60.0, 160.0, 60.0),
            arrow_data,
            2,
        );
        let state = draw_state_with_selection(
            vec![bind_target.clone(), arrow.clone()],
            &[arrow.id.as_str()],
        );

        let (_operation, _context, transform) = drag_arrow_handle_session_with_modifiers(
            &state,
            &arrow.id,
            EditConnectorPointKind::Turning,
            1,
            DrawPoint::new(160.0, 60.0),
            DrawPoint::new(240.0, 60.0),
            EditModifiers {
                from_center: true,
                ..EditModifiers::default()
            },
        );

        let end_binding = transform.end_binding.expect("end binding");
        assert_eq!(end_binding.element_id, bind_target.id);
        assert_eq!(end_binding.mode, ArrowDataBindingMode::Inside);
    }

    #[test]
    fn focus_drag_update_rebinds_with_order_and_inside_mode() {
        let initial_target = rectangle_element(
            "focus-initial-target",
            DrawRect::new(20.0, 20.0, 120.0, 120.0),
            1,
        );
        let next_target = rectangle_element(
            "focus-next-target",
            DrawRect::new(220.0, 0.0, 320.0, 120.0),
            2,
        );
        let arrow_data = ArrowData::default().copy_with(ArrowDataPatch {
            points: Some(ArrowGeometry::normalize_points(
                &[DrawPoint::new(60.0, 60.0), DrawPoint::new(180.0, 60.0)],
                DrawRect::new(60.0, 60.0, 180.0, 60.0),
            )),
            start_binding: ArrowDataNullableField::Value(ArrowDataBinding::new(
                initial_target.id.clone(),
                DrawPoint::new(0.5, 0.5),
                ArrowDataBindingMode::Orbit,
            )),
            ..ArrowDataPatch::default()
        });
        let arrow = arrow_element(
            "arrow-focus-drag",
            DrawRect::new(60.0, 60.0, 180.0, 60.0),
            arrow_data.clone(),
            0,
        );
        let state = draw_state_with_selection(
            vec![arrow.clone(), initial_target.clone(), next_target.clone()],
            &[arrow.id.as_str()],
        );
        let focus_handle = list_visible_arrow_focus_points(
            &arrow,
            &arrow_data,
            state.domain.document.elements.as_slice(),
            None,
            false,
        )
        .into_iter()
        .find(|handle| handle.endpoint == ArrowFocusEndpoint::Start)
        .expect("start focus handle");

        let (_operation, _context, transform) = drag_arrow_handle_session_with_modifiers(
            &state,
            &arrow.id,
            EditConnectorPointKind::FocusStart,
            0,
            focus_handle.point,
            DrawPoint::new(260.0, 60.0),
            EditModifiers {
                from_center: true,
                ..EditModifiers::default()
            },
        );

        let start_binding = transform.start_binding.expect("start binding");
        assert_eq!(start_binding.element_id, next_target.id);
        assert_eq!(start_binding.mode, ArrowDataBindingMode::Inside);
        assert_eq!(
            transform.ordered_element_ids,
            Some(vec![
                initial_target.id.clone(),
                next_target.id.clone(),
                arrow.id.clone(),
            ])
        );
        assert!(transform.has_changes);
    }

    #[test]
    fn rebinding_endpoint_after_dual_bound_elbow_creation_avoids_zig_zag_route() {
        let start_target = rectangle_element(
            "rebind-start-target",
            DrawRect::new(100.0, 100.0, 240.0, 220.0),
            1,
        );
        let current_end_target = rectangle_element(
            "rebind-current-end-target",
            DrawRect::new(420.0, 120.0, 560.0, 260.0),
            2,
        );
        let next_end_target = rectangle_element(
            "rebind-next-end-target",
            DrawRect::new(700.0, 80.0, 860.0, 240.0),
            3,
        );
        let creation_state = draw_state(vec![
            start_target.clone(),
            current_end_target.clone(),
            next_end_target.clone(),
        ]);
        let created_arrow = create_elbow_arrow_via_creation(
            &creation_state,
            "elbow-created-rebind",
            DrawPoint::new(240.0, 160.0),
            DrawPoint::new(320.0, 160.0),
            DrawPoint::new(420.0, 190.0),
            4,
        );
        let created_target =
            resolve_arrow_target_for_element(created_arrow.clone()).expect("created arrow target");
        let created_data = match created_target.payload {
            ArrowEditPayload::Arrow(data) => data,
            ArrowEditPayload::Line(_) => panic!("expected arrow payload"),
        };
        let created_points =
            ArrowGeometry::resolve_world_points(created_target.element.rect, &created_data.points);
        let rebinding_state = draw_state_with_selection(
            vec![
                start_target.clone(),
                current_end_target.clone(),
                next_end_target.clone(),
                created_arrow.clone(),
            ],
            &[created_arrow.id.as_str()],
        );

        let (operation, context, transform) = drag_arrow_handle_session(
            &rebinding_state,
            &created_arrow.id,
            EditConnectorPointKind::Turning,
            created_points.len() - 1,
            *created_points.last().expect("created end point"),
            DrawPoint::new(700.0, 160.0),
        );
        let next = operation.finish(
            &rebinding_state,
            &context,
            &EditTransform::ArrowPoint(transform),
        );
        let updated_arrow = next
            .domain
            .document
            .get_element_by_id(&created_arrow.id)
            .expect("updated rebound arrow")
            .clone();
        let updated_target =
            resolve_arrow_target_for_element(updated_arrow).expect("updated arrow target");
        let updated_data = match updated_target.payload {
            ArrowEditPayload::Arrow(data) => data,
            ArrowEditPayload::Line(_) => panic!("expected arrow payload"),
        };
        let updated_points =
            ArrowGeometry::resolve_world_points(updated_target.element.rect, &updated_data.points);

        assert_eq!(
            updated_data
                .start_binding
                .as_ref()
                .map(|binding| binding.element_id.as_str()),
            Some(start_target.id.as_str())
        );
        assert_eq!(
            updated_data
                .end_binding
                .as_ref()
                .map(|binding| binding.element_id.as_str()),
            Some(next_end_target.id.as_str())
        );

        for index in 1..updated_points.len() {
            let dx = (updated_points[index].x - updated_points[index - 1].x).abs();
            let dy = (updated_points[index].y - updated_points[index - 1].y).abs();
            assert!(
                dx <= 1e-6 || dy <= 1e-6,
                "segment {index} must stay orthogonal"
            );
        }

        for index in 2..updated_points.len() {
            let prev_dx = updated_points[index - 1].x - updated_points[index - 2].x;
            let prev_dy = updated_points[index - 1].y - updated_points[index - 2].y;
            let next_dx = updated_points[index].x - updated_points[index - 1].x;
            let next_dy = updated_points[index].y - updated_points[index - 1].y;
            let prev_vertical = prev_dx.abs() <= 1e-6 && prev_dy.abs() > 1e-6;
            let next_vertical = next_dx.abs() <= 1e-6 && next_dy.abs() > 1e-6;
            let prev_horizontal = prev_dy.abs() <= 1e-6 && prev_dx.abs() > 1e-6;
            let next_horizontal = next_dy.abs() <= 1e-6 && next_dx.abs() > 1e-6;

            if prev_vertical && next_vertical {
                assert!(
                    prev_dy * next_dy >= 0.0,
                    "vertical segments must not zig-zag"
                );
            }
            if prev_horizontal && next_horizontal {
                assert!(
                    prev_dx * next_dx >= 0.0,
                    "horizontal segments must not zig-zag"
                );
            }
        }
    }

    #[test]
    fn move_initial_transform_returns_zero_without_cached_context() {
        let operation = MoveEditOperationAdapter::new();
        let state = draw_state(vec![]);
        let context = EditContext::new(
            DrawPoint::new(1.0, 2.0),
            DrawRect::new(0.0, 0.0, 10.0, 10.0),
            HashSet::new(),
            0,
            0,
        );

        let initial = operation.initial_transform(&state, &context, DrawPoint::new(5.0, 6.0));

        assert_eq!(
            initial,
            EditTransform::Move(crate::draw::types::edit_transform::MoveTransform::ZERO)
        );
    }

    #[test]
    fn move_create_history_metadata_checks_context_before_transform() {
        let operation = MoveEditOperationAdapter::new();
        let context = EditContext::new(
            DrawPoint::new(1.0, 2.0),
            DrawRect::new(0.0, 0.0, 10.0, 10.0),
            HashSet::new(),
            0,
            0,
        );

        let panic = std::panic::catch_unwind(std::panic::AssertUnwindSafe(|| {
            let _ = operation.create_history_metadata(
                &context,
                &EditTransform::Resize(
                    crate::draw::types::edit_transform::ResizeTransform::incomplete(
                        DrawPoint::ZERO,
                    ),
                ),
            );
        }))
        .expect_err("expected panic");

        let error = panic
            .downcast_ref::<EditContextTypeMismatchError>()
            .expect("expected context mismatch panic");
        assert_eq!(error.operation_name, "MoveOperation.createHistoryMetadata");
    }

    #[test]
    fn move_update_checks_context_before_transform() {
        let operation = MoveEditOperationAdapter::new();
        let state = draw_state(vec![]);
        let context = EditContext::new(
            DrawPoint::new(1.0, 2.0),
            DrawRect::new(0.0, 0.0, 10.0, 10.0),
            HashSet::new(),
            0,
            0,
        );

        let panic = std::panic::catch_unwind(std::panic::AssertUnwindSafe(|| {
            let _ = operation.update(
                &state,
                &context,
                &EditTransform::Resize(
                    crate::draw::types::edit_transform::ResizeTransform::incomplete(
                        DrawPoint::ZERO,
                    ),
                ),
                DrawPoint::new(4.0, 5.0),
                EditModifiers::default(),
                &DrawConfig::default(),
            );
        }))
        .expect_err("expected panic");

        let error = panic
            .downcast_ref::<EditContextTypeMismatchError>()
            .expect("expected context mismatch panic");
        assert_eq!(error.operation_name, "MoveOperation.update");
    }

    #[test]
    fn move_compute_result_checks_context_before_transform() {
        let operation = MoveEditOperationAdapter::new();
        let state = draw_state(vec![]);
        let context = EditContext::new(
            DrawPoint::new(1.0, 2.0),
            DrawRect::new(0.0, 0.0, 10.0, 10.0),
            HashSet::new(),
            0,
            0,
        );

        let panic = std::panic::catch_unwind(std::panic::AssertUnwindSafe(|| {
            let _ = StandardFinishMixin::compute_result(
                &operation,
                &state,
                &context,
                &EditTransform::Resize(
                    crate::draw::types::edit_transform::ResizeTransform::incomplete(
                        DrawPoint::ZERO,
                    ),
                ),
            );
        }))
        .expect_err("expected panic");

        let error = panic
            .downcast_ref::<EditContextTypeMismatchError>()
            .expect("expected context mismatch panic");
        assert_eq!(error.operation_name, "MoveOperation.computeResult");
    }

    #[test]
    fn connector_point_operation_records_connector_history() {
        let operation = ArrowPointEditOperationAdapter::new();
        let context = EditContext::new(
            DrawPoint::new(10.0, 20.0),
            DrawRect::new(0.0, 0.0, 40.0, 40.0),
            ["arrow-1".to_owned()].into_iter().collect(),
            3,
            5,
        );
        let metadata = operation.create_history_metadata(
            &context,
            &EditTransform::ArrowPoint(ArrowPointTransform::new(
                DrawPoint::new(10.0, 20.0),
                vec![],
            )),
        );

        assert!(operation.records_history());
        assert_eq!(metadata.record_type(), HistoryRecordType::Edit);
        assert_eq!(metadata.description(), "Connector point 1 element");
        assert_eq!(
            metadata.affected_element_ids(),
            &context.selected_ids_at_start
        );
    }
}
