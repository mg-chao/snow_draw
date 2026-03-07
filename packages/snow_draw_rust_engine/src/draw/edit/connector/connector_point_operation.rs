#![allow(dead_code)]

use std::fmt;

use crate::draw::config::draw_config::DrawConfig;
use crate::draw::edit::arrow::arrow_point_operation::{
    apply_point_deletion, resolve_point_position, ArrowPointOperation,
};
use crate::draw::edit::core::edit_modifiers::EditModifiers;
use crate::draw::edit::core::edit_operation::{EditOperationParams, EditPreview, EditUpdateResult};
use crate::draw::edit::edit_operations::{DefaultEditOperationRegistry, SharedEditOperation};
use crate::draw::history::history_metadata::HistoryMetadata;
use crate::draw::models::draw_state::DrawState;
use crate::draw::types::draw_point::DrawPoint;
use crate::draw::types::edit_context::EditContext;
use crate::draw::types::edit_operation_id::{EditOperationId, EditOperationIds};
use crate::draw::types::edit_transform::EditTransform;
use crate::draw::types::element_style::ArrowType;

pub use crate::draw::edit::arrow::arrow_point_operation::{
    ArrowBindingCandidate as ConnectorPointBindingCandidate,
    ArrowPointBindingLookup as ConnectorPointBindingLookup,
    ArrowPointBindingRequest as ConnectorPointBindingRequest,
    ArrowPointEditContext as ConnectorPointEditContext, ArrowPointKind as ConnectorPointKind,
    ArrowPointTransform as ConnectorPointTransform,
    ArrowPointUpdateOptions as ConnectorPointUpdateOptions,
};

/// Connector-facing point editing wrapper.
///
/// The translated engine still shares the concrete implementation with the
/// arrow point editor, but the newer connector module has its own public type
/// in Dart. This wrapper now exposes both:
///
/// - the low-level point-transform helpers used by already-ported geometry
///   code, and
/// - the higher-level edit-session facade (`create_edit_context`,
///   `initial_edit_transform`, `update_edit`, `finish_edit`, ...)
///   backed by the shared translated edit-operation pipeline.
///
/// This keeps the connector-facing Rust surface aligned with the Dart module
/// without forking the actual edit implementation.
#[derive(Clone)]
pub struct ConnectorPointOperation {
    delegate: ArrowPointOperation,
    edit_delegate: SharedEditOperation,
}

impl Default for ConnectorPointOperation {
    fn default() -> Self {
        Self::new()
    }
}

impl fmt::Debug for ConnectorPointOperation {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        f.debug_struct("ConnectorPointOperation")
            .field("delegate", &self.delegate)
            .finish_non_exhaustive()
    }
}

impl ConnectorPointOperation {
    pub fn with_defaults() -> Self {
        let registry = DefaultEditOperationRegistry::with_defaults();
        let edit_delegate = registry
            .get_operation(EditOperationIds::CONNECTOR_POINT)
            .expect("default edit registry must register connector point operation")
            .clone();

        Self {
            delegate: ArrowPointOperation::new(),
            edit_delegate,
        }
    }

    pub fn new() -> Self {
        Self::with_defaults()
    }

    /// Stable edit-operation identifier for connector point editing.
    pub fn id(&self) -> EditOperationId {
        EditOperationIds::CONNECTOR_POINT
    }

    /// Whether this operation records history when finishing.
    pub fn records_history(&self) -> bool {
        self.edit_delegate.records_history()
    }

    /// Builds history metadata for the current edit session.
    pub fn create_history_metadata(
        &self,
        context: &EditContext,
        transform: &EditTransform,
    ) -> HistoryMetadata {
        self.edit_delegate
            .create_history_metadata(context, transform)
    }

    /// Creates the immutable edit-session base context.
    pub fn create_edit_context(
        &self,
        state: &DrawState,
        position: DrawPoint,
        params: &EditOperationParams,
    ) -> EditContext {
        self.edit_delegate.create_context(state, position, params)
    }

    /// Resolves the initial edit transform for a new session.
    pub fn initial_edit_transform(
        &self,
        state: &DrawState,
        context: &EditContext,
        start_position: DrawPoint,
    ) -> EditTransform {
        self.edit_delegate
            .initial_transform(state, context, start_position)
    }

    /// Updates the edit-session transform through the shared edit pipeline.
    pub fn update_edit(
        &self,
        state: &DrawState,
        context: &EditContext,
        transform: &EditTransform,
        current_position: DrawPoint,
        modifiers: EditModifiers,
        config: &DrawConfig,
    ) -> EditUpdateResult<EditTransform> {
        self.edit_delegate.update(
            state,
            context,
            transform,
            current_position,
            modifiers,
            config,
        )
    }

    /// Commits the edit-session transform into persistent draw state.
    pub fn finish_edit(
        &self,
        state: &DrawState,
        context: &EditContext,
        transform: &EditTransform,
    ) -> DrawState {
        self.edit_delegate.finish(state, context, transform)
    }

    /// Cancels the current edit session.
    pub fn cancel_edit(&self, state: &DrawState) -> DrawState {
        self.edit_delegate.cancel(state)
    }

    /// Builds the live preview used by rendering while editing.
    pub fn build_edit_preview(
        &self,
        state: &DrawState,
        context: &EditContext,
        transform: &EditTransform,
    ) -> EditPreview {
        self.edit_delegate.build_preview(state, context, transform)
    }

    pub fn initial_transform(
        &self,
        context: &ConnectorPointEditContext,
        start_position: DrawPoint,
    ) -> ConnectorPointTransform {
        self.delegate.initial_transform(context, start_position)
    }

    pub fn update(
        &self,
        context: &ConnectorPointEditContext,
        transform: &ConnectorPointTransform,
        current_position: DrawPoint,
        options: ConnectorPointUpdateOptions,
        binding_lookup: &mut dyn ConnectorPointBindingLookup,
    ) -> ConnectorPointTransform {
        self.delegate.update(
            context,
            transform,
            current_position,
            options,
            binding_lookup,
        )
    }

    pub fn compute_points_for_result(
        &self,
        transform: &ConnectorPointTransform,
        apply_deletion: bool,
    ) -> Vec<DrawPoint> {
        self.delegate
            .compute_points_for_result(transform, apply_deletion)
    }
}

/// Resolves the effective local point position for a connector handle.
pub fn resolve_connector_point_position(
    points: &[DrawPoint],
    kind: ConnectorPointKind,
    index: usize,
    arrow_type: ArrowType,
) -> DrawPoint {
    resolve_point_position(points, kind, index, arrow_type)
}

/// Applies connector point deletion rules to a working transform.
pub fn apply_connector_point_deletion(transform: &ConnectorPointTransform) -> Vec<DrawPoint> {
    apply_point_deletion(transform)
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::draw::edit::core::edit_operation::EditOperationParams;
    use crate::draw::edit::core::edit_operation_params::ConnectorPointOperationParams;
    use crate::draw::models::application_state::ApplicationState;
    use crate::draw::models::draw_state::{DomainDocumentState, DomainState, DrawState};
    use crate::draw::models::element_state::ElementState;
    use crate::draw::types::draw_rect::DrawRect;
    use std::sync::Arc;

    use crate::draw::elements::types::arrow::arrow_data::ArrowData;
    use crate::draw::elements::types::connector::connector_geometry::normalize_connector_points;
    use crate::draw::elements::types::connector::connector_points::ConnectorPointKind;

    #[test]
    fn connector_operation_wraps_arrow_operation() {
        let operation = ConnectorPointOperation::new();
        let debug_name = format!("{:?}", operation);

        assert_eq!(
            debug_name,
            "ConnectorPointOperation { delegate: ArrowPointOperation, .. }"
        );
        assert_eq!(operation.id(), EditOperationIds::CONNECTOR_POINT);
        assert!(operation.records_history());
    }

    #[test]
    fn connector_operation_exposes_shared_edit_facade() {
        let operation = ConnectorPointOperation::new();
        let rect = DrawRect::new(20.0, 20.0, 140.0, 80.0);
        let world_points = vec![DrawPoint::new(20.0, 20.0), DrawPoint::new(140.0, 80.0)];
        let arrow = ArrowData::default().copy_with(
            crate::draw::elements::types::arrow::arrow_data::ArrowDataPatch {
                points: Some(normalize_connector_points(&world_points, rect)),
                ..Default::default()
            },
        );
        let element = ElementState::new("arrow".to_owned(), rect, 0.0, 1.0, 0, Arc::new(arrow));
        let domain = DomainState::new(
            DomainDocumentState::new(vec![element], 1, Default::default()),
            Default::default(),
        );
        let state = DrawState::new(Some(domain), Some(ApplicationState::initial(None)));
        let params =
            EditOperationParams::ConnectorPoint(ConnectorPointOperationParams::with_options(
                "arrow".to_owned(),
                ConnectorPointKind::Turning,
                1,
                false,
                Some(DrawRect::new(20.0, 20.0, 140.0, 80.0)),
            ));
        let context = operation.create_edit_context(&state, DrawPoint::new(140.0, 80.0), &params);
        let transform =
            operation.initial_edit_transform(&state, &context, DrawPoint::new(140.0, 80.0));

        assert_eq!(operation.id(), EditOperationIds::CONNECTOR_POINT);
        assert!(matches!(transform, EditTransform::ArrowPoint(_)));
    }
}
