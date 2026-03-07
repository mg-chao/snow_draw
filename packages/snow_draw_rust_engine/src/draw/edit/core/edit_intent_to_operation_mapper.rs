#![allow(dead_code)]

use std::sync::Arc;

pub use crate::draw::actions::draw_actions::StartEdit;
use crate::draw::config::draw_config::DrawConfig;
pub use crate::draw::edit::core::edit_operation_params::{
    ConnectorPointOperationParams, EditOperationParams, MoveOperationParams, ResizeOperationParams,
    RotateOperationParams,
};
use crate::draw::elements::types::connector::connector_points::ConnectorPointKind;
use crate::draw::types::draw_point::DrawPoint;
use crate::draw::types::edit_operation_id::{EditOperationId, EditOperationIds};
use crate::draw::utils::edit_intent_detector::{
    ConnectorPointKind as IntentConnectorPointKind, EditIntent,
};

/// Resolved operation mapping for an [`EditIntent`].
#[derive(Clone, Debug, PartialEq)]
pub struct EditIntentResolution {
    pub operation_id: EditOperationId,
    pub params: EditOperationParams,
}

/// Resolver function that maps an intent/config pair into operation metadata.
pub type EditIntentResolver =
    dyn Fn(&EditIntent, &DrawConfig) -> Option<EditIntentResolution> + Send + Sync + 'static;

/// Maps input-layer edit intents to domain-layer start-edit actions.
#[derive(Clone)]
pub struct EditIntentToOperationMapper {
    resolver: Arc<EditIntentResolver>,
}

impl std::fmt::Debug for EditIntentToOperationMapper {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        f.debug_struct("EditIntentToOperationMapper")
            .finish_non_exhaustive()
    }
}

impl Default for EditIntentToOperationMapper {
    fn default() -> Self {
        Self::with_defaults()
    }
}

impl EditIntentToOperationMapper {
    /// Creates a mapper using the built-in direct intent matcher.
    pub fn with_defaults() -> Self {
        Self {
            resolver: Arc::new(resolve_default_intent),
        }
    }

    /// Creates a mapper from a custom resolver.
    pub fn custom<R>(resolver: R) -> Self
    where
        R: Fn(&EditIntent, &DrawConfig) -> Option<EditIntentResolution> + Send + Sync + 'static,
    {
        Self {
            resolver: Arc::new(resolver),
        }
    }

    /// Returns a [`StartEdit`] action, or `None` if the intent is not mapped.
    pub fn map_to_start_edit(
        &self,
        intent: &EditIntent,
        position: DrawPoint,
        config: &DrawConfig,
    ) -> Option<StartEdit> {
        let resolved = (self.resolver)(intent, config)?;
        Some(StartEdit::new(
            resolved.operation_id,
            position,
            resolved.params,
        ))
    }
}

/// Default mapping implementation used by [`EditIntentToOperationMapper`].
pub fn resolve_default_intent(
    intent: &EditIntent,
    config: &DrawConfig,
) -> Option<EditIntentResolution> {
    match intent {
        EditIntent::StartConnectorPoint(start) => Some(EditIntentResolution {
            operation_id: EditOperationIds::CONNECTOR_POINT,
            params: ConnectorPointOperationParams::with_options(
                start.element_id.clone(),
                connector_point_kind_from_intent(start.point_kind),
                start.point_index,
                start.is_double_click,
                None,
            )
            .into(),
        }),
        EditIntent::StartRotate(_) => Some(EditIntentResolution {
            operation_id: EditOperationIds::ROTATE,
            params: RotateOperationParams::with_options(
                None,
                config.element.rotation_snap_angle,
                None,
            )
            .into(),
        }),
        EditIntent::StartResize(start) => Some(EditIntentResolution {
            operation_id: EditOperationIds::RESIZE,
            params: ResizeOperationParams::with_options(
                start.mode,
                None,
                start.selection_padding,
                None,
            )
            .into(),
        }),
        EditIntent::StartMove(_) => Some(EditIntentResolution {
            operation_id: EditOperationIds::MOVE,
            params: MoveOperationParams::default().into(),
        }),
        _ => None,
    }
}

fn connector_point_kind_from_intent(kind: IntentConnectorPointKind) -> ConnectorPointKind {
    match kind {
        IntentConnectorPointKind::Turning => ConnectorPointKind::Turning,
        IntentConnectorPointKind::Addable => ConnectorPointKind::Addable,
        IntentConnectorPointKind::LoopStart => ConnectorPointKind::LoopStart,
        IntentConnectorPointKind::LoopEnd => ConnectorPointKind::LoopEnd,
        IntentConnectorPointKind::FocusStart => ConnectorPointKind::FocusStart,
        IntentConnectorPointKind::FocusEnd => ConnectorPointKind::FocusEnd,
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::draw::types::resize_mode::ResizeMode;
    use crate::draw::utils::edit_intent_detector::{
        ConnectorPointKind as IntentConnectorPointKind, StartConnectorPointIntent, StartMoveIntent,
        StartResizeIntent, StartRotateIntent,
    };

    #[test]
    fn default_mapper_maps_move_intent() {
        let mapper = EditIntentToOperationMapper::with_defaults();
        let intent = EditIntent::StartMove(StartMoveIntent {
            element_id: "e-1".to_owned(),
            add_to_selection: false,
        });

        let start = mapper
            .map_to_start_edit(&intent, DrawPoint::new(10.0, 20.0), &DrawConfig::default())
            .expect("start edit should be mapped");

        assert_eq!(start.operation_id, EditOperationIds::MOVE);
        assert!(matches!(start.params, EditOperationParams::Move(_)));
    }

    #[test]
    fn default_mapper_maps_resize_intent_with_padding() {
        let mapper = EditIntentToOperationMapper::with_defaults();
        let intent = EditIntent::StartResize(StartResizeIntent {
            mode: ResizeMode::BottomRight,
            selection_padding: 12.0,
        });

        let start = mapper
            .map_to_start_edit(&intent, DrawPoint::ZERO, &DrawConfig::default())
            .expect("start edit should be mapped");

        assert_eq!(start.operation_id, EditOperationIds::RESIZE);
        assert_eq!(
            start.params,
            EditOperationParams::Resize(ResizeOperationParams::with_options(
                ResizeMode::BottomRight,
                None,
                12.0,
                None,
            ))
        );
    }

    #[test]
    fn default_mapper_maps_rotate_intent_with_config_snap_angle() {
        let mapper = EditIntentToOperationMapper::with_defaults();
        let intent = EditIntent::StartRotate(StartRotateIntent);
        let mut config = DrawConfig::default();
        config.element.rotation_snap_angle = 0.25;

        let start = mapper
            .map_to_start_edit(&intent, DrawPoint::ZERO, &config)
            .expect("start edit should be mapped");

        assert_eq!(start.operation_id, EditOperationIds::ROTATE);
        assert_eq!(
            start.params,
            EditOperationParams::Rotate(RotateOperationParams::with_options(None, 0.25, None))
        );
    }

    #[test]
    fn default_mapper_maps_connector_point_intent() {
        let mapper = EditIntentToOperationMapper::with_defaults();
        let intent = EditIntent::StartConnectorPoint(StartConnectorPointIntent {
            element_id: "arrow-1".to_owned(),
            point_kind: IntentConnectorPointKind::Turning,
            point_index: 2,
            is_double_click: true,
        });

        let start = mapper
            .map_to_start_edit(&intent, DrawPoint::ZERO, &DrawConfig::default())
            .expect("start edit should be mapped");

        assert_eq!(start.operation_id, EditOperationIds::CONNECTOR_POINT);
        assert_eq!(
            start.params,
            EditOperationParams::ConnectorPoint(ConnectorPointOperationParams::with_options(
                "arrow-1",
                ConnectorPointKind::Turning,
                2,
                true,
                None,
            ))
        );
    }
}
