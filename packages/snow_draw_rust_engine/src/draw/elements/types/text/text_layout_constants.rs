#![allow(dead_code)]

/// Shared text-caret width in logical pixels.
pub const TEXT_CURSOR_WIDTH: f64 = 1.2;

/// Shared caret-to-glyph gap in logical pixels.
pub const TEXT_CARET_GAP: f64 = 1.0;

/// Shared margin reserved for caret rendering in text editors.
pub const TEXT_CARET_MARGIN: f64 = TEXT_CURSOR_WIDTH + TEXT_CARET_GAP;

const TEXT_LAYOUT_HORIZONTAL_PADDING_FACTOR: f64 = 0.01;
const TEXT_BACKGROUND_HORIZONTAL_PADDING_FACTOR: f64 = 0.32;
const TEXT_BACKGROUND_VERTICAL_PADDING_FACTOR: f64 = 0.1;

/// Resolves horizontal background padding from line height.
pub fn resolve_text_background_horizontal_padding(line_height: f64) -> f64 {
    sanitize_padding(line_height * TEXT_BACKGROUND_HORIZONTAL_PADDING_FACTOR)
}

/// Resolves vertical background padding from line height.
pub fn resolve_text_background_vertical_padding(line_height: f64) -> f64 {
    sanitize_padding(line_height * TEXT_BACKGROUND_VERTICAL_PADDING_FACTOR)
}

/// Resolves horizontal layout padding from line height.
pub fn resolve_text_layout_horizontal_padding(line_height: f64) -> f64 {
    sanitize_padding(line_height * TEXT_LAYOUT_HORIZONTAL_PADDING_FACTOR)
}

fn sanitize_padding(value: f64) -> f64 {
    if value.is_finite() {
        value
    } else {
        0.0
    }
}
