#![allow(dead_code)]

use std::any::Any;

use crate::draw::config::draw_config::{CanvasConfig, DrawConfig, SelectionConfig};

use super::draw_actions::DrawAction;
use super::history_coalescing::HistoryCoalescingProvider;
use super::history_policy::{HistoryPolicy, HistoryPolicyProvider};

/// Replaces the entire store configuration snapshot.
#[derive(Clone, Debug, PartialEq)]
pub struct UpdateConfig {
    pub config: DrawConfig,
}

impl UpdateConfig {
    pub const fn new(config: DrawConfig) -> Self {
        Self { config }
    }
}

impl HistoryPolicyProvider for UpdateConfig {
    fn history_policy(&self) -> HistoryPolicy {
        HistoryPolicy::None
    }
}
impl HistoryCoalescingProvider for UpdateConfig {}
impl DrawAction for UpdateConfig {
    fn as_any(&self) -> &dyn Any {
        self
    }
}

/// Convenience action for partial selection config updates.
#[derive(Clone, Debug, PartialEq)]
pub struct UpdateSelectionConfig {
    pub selection: SelectionConfig,
}

impl UpdateSelectionConfig {
    pub const fn new(selection: SelectionConfig) -> Self {
        Self { selection }
    }
}

impl HistoryPolicyProvider for UpdateSelectionConfig {
    fn history_policy(&self) -> HistoryPolicy {
        HistoryPolicy::None
    }
}
impl HistoryCoalescingProvider for UpdateSelectionConfig {}
impl DrawAction for UpdateSelectionConfig {
    fn as_any(&self) -> &dyn Any {
        self
    }
}

/// Convenience action for partial canvas config updates.
#[derive(Clone, Debug, PartialEq)]
pub struct UpdateCanvasConfig {
    pub canvas: CanvasConfig,
}

impl UpdateCanvasConfig {
    pub const fn new(canvas: CanvasConfig) -> Self {
        Self { canvas }
    }
}

impl HistoryPolicyProvider for UpdateCanvasConfig {
    fn history_policy(&self) -> HistoryPolicy {
        HistoryPolicy::None
    }
}
impl HistoryCoalescingProvider for UpdateCanvasConfig {}
impl DrawAction for UpdateCanvasConfig {
    fn as_any(&self) -> &dyn Any {
        self
    }
}
