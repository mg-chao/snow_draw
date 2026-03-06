#![allow(dead_code)]

use crate::draw::types::draw_point::DrawPoint;

use super::arrow_binding::ArrowBinding;
use super::arrow_binding_policy::resolve_arrow_binding_mode;

/// Result of resolving a core endpoint drag step.
#[derive(Clone, Debug, Default, PartialEq)]
pub struct ArrowCoreEndpointDragResult {
    pub world_point: Option<DrawPoint>,
    pub binding: Option<ArrowBinding>,
}

/// Resolves the explicit endpoint binding mode for drag/finalize flows.
pub fn resolve_endpoint_drag_binding_enabled(is_binding_enabled: bool) -> &'static str {
    match resolve_arrow_binding_mode(is_binding_enabled) {
        super::arrow_binding::ArrowBindingMode::Inside => "inside",
        super::arrow_binding::ArrowBindingMode::Orbit => "orbit",
        super::arrow_binding::ArrowBindingMode::Skip => "skip",
    }
}
