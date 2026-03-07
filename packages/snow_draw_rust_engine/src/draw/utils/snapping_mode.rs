#![allow(dead_code)]

/// Active snapping policy used by draw/edit operations.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash)]
pub enum SnappingMode {
    None,
    Object,
    Grid,
}

impl Default for SnappingMode {
    fn default() -> Self {
        Self::None
    }
}

/// Minimal config view for resolving snapping mode from configuration.
///
/// This mirrors the Dart `DrawConfig` fields used by snapping resolution:
/// `grid.enabled` and `snap.enabled`.
pub trait SnappingModeConfig {
    fn grid_enabled(&self) -> bool;
    fn object_enabled(&self) -> bool;
}

/// Resolves the persistent snapping mode from toggle states.
///
/// Priority matches Dart behavior: grid snapping takes precedence over object
/// snapping when both are enabled.
pub fn resolve_persistent_snapping_mode(grid_enabled: bool, object_enabled: bool) -> SnappingMode {
    if grid_enabled {
        SnappingMode::Grid
    } else if object_enabled {
        SnappingMode::Object
    } else {
        SnappingMode::None
    }
}

/// Resolves the effective snapping mode with temporary Ctrl-key override.
///
/// When `ctrl_pressed` is `true`:
/// - if any snapping is currently enabled, snapping is temporarily disabled;
/// - if no snapping is enabled, object snapping is temporarily enabled.
pub fn resolve_effective_snapping_mode(
    grid_enabled: bool,
    object_enabled: bool,
    ctrl_pressed: bool,
) -> SnappingMode {
    if ctrl_pressed {
        if grid_enabled || object_enabled {
            SnappingMode::None
        } else {
            SnappingMode::Object
        }
    } else {
        resolve_persistent_snapping_mode(grid_enabled, object_enabled)
    }
}

/// Resolves effective snapping mode from a configuration object and Ctrl state.
pub fn resolve_effective_snapping_mode_for_config(
    config: &impl SnappingModeConfig,
    ctrl_pressed: bool,
) -> SnappingMode {
    resolve_effective_snapping_mode(config.grid_enabled(), config.object_enabled(), ctrl_pressed)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[derive(Debug, Clone, Copy)]
    struct TestConfig {
        grid_enabled: bool,
        object_enabled: bool,
    }

    impl SnappingModeConfig for TestConfig {
        fn grid_enabled(&self) -> bool {
            self.grid_enabled
        }

        fn object_enabled(&self) -> bool {
            self.object_enabled
        }
    }

    #[test]
    fn persistent_mode_prioritizes_grid() {
        assert_eq!(
            resolve_persistent_snapping_mode(true, false),
            SnappingMode::Grid
        );
        assert_eq!(
            resolve_persistent_snapping_mode(true, true),
            SnappingMode::Grid
        );
    }

    #[test]
    fn persistent_mode_uses_object_when_grid_disabled() {
        assert_eq!(
            resolve_persistent_snapping_mode(false, true),
            SnappingMode::Object
        );
        assert_eq!(
            resolve_persistent_snapping_mode(false, false),
            SnappingMode::None
        );
    }

    #[test]
    fn ctrl_temporarily_disables_existing_snapping() {
        assert_eq!(
            resolve_effective_snapping_mode(true, false, true),
            SnappingMode::None
        );
        assert_eq!(
            resolve_effective_snapping_mode(false, true, true),
            SnappingMode::None
        );
    }

    #[test]
    fn ctrl_temporarily_enables_object_when_nothing_is_enabled() {
        assert_eq!(
            resolve_effective_snapping_mode(false, false, true),
            SnappingMode::Object
        );
    }

    #[test]
    fn for_config_matches_primitive_resolver() {
        let config = TestConfig {
            grid_enabled: false,
            object_enabled: true,
        };
        assert_eq!(
            resolve_effective_snapping_mode_for_config(&config, false),
            SnappingMode::Object
        );
    }
}
