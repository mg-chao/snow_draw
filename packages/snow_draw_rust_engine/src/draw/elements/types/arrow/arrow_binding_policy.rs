#![allow(dead_code)]

use super::arrow_binding::ArrowBindingMode;

/// Returns the default endpoint binding mode used by connector editing flows.
pub const fn default_arrow_binding_mode() -> ArrowBindingMode {
    ArrowBindingMode::Orbit
}

/// Resolves the explicit endpoint binding mode when binding is disabled.
pub const fn resolve_arrow_binding_mode(is_binding_enabled: bool) -> ArrowBindingMode {
    if is_binding_enabled {
        ArrowBindingMode::Orbit
    } else {
        ArrowBindingMode::Skip
    }
}
