#![allow(dead_code)]

use crate::draw::config::draw_config::SnapConfig;

use super::arrow_binding::ArrowBindingMode;

/// Returns whether arrow-binding interactions should run for the current snap state.
pub fn should_attempt_arrow_binding(snap_config: &SnapConfig, snap_override_active: bool) -> bool {
    !snap_override_active && snap_config.enable_arrow_binding
}

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

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn should_attempt_arrow_binding_matches_dart_policy() {
        let mut snap = SnapConfig::default();
        snap.enable_arrow_binding = true;
        assert!(should_attempt_arrow_binding(&snap, false));
        assert!(!should_attempt_arrow_binding(&snap, true));

        snap.enable_arrow_binding = false;
        assert!(!should_attempt_arrow_binding(&snap, false));
    }
}
