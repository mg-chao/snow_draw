#![allow(dead_code)]

use crate::draw::config::highlight_config::HighlightMaskConfig;

/// Returns whether highlight-mask pixels should be rendered.
pub fn is_highlight_mask_visible(has_highlights: bool, config: HighlightMaskConfig) -> bool {
    has_highlights && config.mask_opacity > 0.0
}
