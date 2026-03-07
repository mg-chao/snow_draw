#![allow(dead_code)]

use crate::draw::config::highlight_config::HighlightMaskConfig;
use crate::draw::config::watermark_config::WatermarkConfig;
use serde::{Deserialize, Serialize};
use std::fmt;

/// Persistent global elements attached to the document.
///
/// These elements are document-level overlays (for example highlight mask and
/// watermark) and participate in undo/redo like regular elements.
#[derive(Clone, Debug, PartialEq, Serialize, Deserialize)]
pub struct GlobalElementsState {
    /// Global highlight mask element data.
    pub highlight_mask: HighlightMaskConfig,

    /// Global watermark element data.
    pub watermark: WatermarkConfig,
}

impl GlobalElementsState {
    pub fn new(highlight_mask: HighlightMaskConfig, watermark: WatermarkConfig) -> Self {
        Self {
            highlight_mask,
            watermark,
        }
    }

    /// Returns a copied state with selected fields replaced.
    pub fn copy_with(
        &self,
        highlight_mask: Option<HighlightMaskConfig>,
        watermark: Option<WatermarkConfig>,
    ) -> Self {
        let next = Self {
            highlight_mask: highlight_mask.unwrap_or(self.highlight_mask),
            watermark: watermark.unwrap_or_else(|| self.watermark.clone()),
        };

        if next == *self {
            self.clone()
        } else {
            next
        }
    }
}

impl Default for GlobalElementsState {
    fn default() -> Self {
        Self::new(HighlightMaskConfig::default(), WatermarkConfig::default())
    }
}

impl fmt::Display for GlobalElementsState {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        write!(
            f,
            "GlobalElementsState(highlightMask: {}, watermark: {})",
            self.highlight_mask, self.watermark
        )
    }
}
