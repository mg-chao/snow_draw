#![allow(dead_code)]

use super::arrow_binding::ArrowBindingMode;
use super::arrow_core::{BIND_MODE_INSIDE, BIND_MODE_ORBIT, BIND_MODE_SKIP};

/// Converts the local binding mode to the string form used by arrow-core wrappers.
pub const fn to_core_binding_mode(mode: ArrowBindingMode) -> &'static str {
    match mode {
        ArrowBindingMode::Inside => BIND_MODE_INSIDE,
        ArrowBindingMode::Orbit => BIND_MODE_ORBIT,
        ArrowBindingMode::Skip => BIND_MODE_SKIP,
    }
}

/// Converts an arrow-core binding mode string back to the local enum.
pub fn from_core_binding_mode(mode: &str) -> ArrowBindingMode {
    match mode {
        BIND_MODE_INSIDE => ArrowBindingMode::Inside,
        BIND_MODE_SKIP => ArrowBindingMode::Skip,
        _ => ArrowBindingMode::Orbit,
    }
}
