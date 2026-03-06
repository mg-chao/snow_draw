#![allow(dead_code)]

use crate::draw::edit::arrow::arrow_point_operation::{
    apply_point_deletion, resolve_point_position, ArrowPointOperation,
};
use crate::draw::types::draw_point::DrawPoint;
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
/// in Dart. This wrapper keeps the Rust API aligned without duplicating logic.
#[derive(Clone, Copy, Debug, Default, PartialEq, Eq)]
pub struct ConnectorPointOperation {
    delegate: ArrowPointOperation,
}

impl ConnectorPointOperation {
    pub const fn new() -> Self {
        Self {
            delegate: ArrowPointOperation::new(),
        }
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

    #[test]
    fn connector_operation_wraps_arrow_operation() {
        let operation = ConnectorPointOperation::new();
        let debug_name = format!("{:?}", operation);

        assert_eq!(
            debug_name,
            "ConnectorPointOperation { delegate: ArrowPointOperation }"
        );
    }
}
