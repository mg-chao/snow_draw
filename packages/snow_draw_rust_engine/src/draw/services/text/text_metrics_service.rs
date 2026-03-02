#![allow(dead_code)]

use crate::draw::elements::types::text::text_data::TextData;
use std::fmt::Debug;
use std::sync::Arc;

/// Request payload for text metric computation.
#[derive(Clone, Debug, PartialEq)]
pub struct TextLayoutRequest<'a> {
    /// Text style and content to measure.
    pub data: &'a TextData,
    /// Maximum layout width in logical pixels.
    pub max_width: f64,
    /// Optional minimum layout width in logical pixels.
    pub min_width: Option<f64>,
    /// Optional BCP-47 locale tag.
    pub locale_tag: Option<&'a str>,
    /// Whether measurement is part of a live resize operation.
    pub is_resizing: bool,
}

impl<'a> TextLayoutRequest<'a> {
    /// Creates a text layout request.
    pub fn new(data: &'a TextData, max_width: f64) -> Self {
        Self {
            data,
            max_width,
            min_width: None,
            locale_tag: None,
            is_resizing: false,
        }
    }
}

/// Per-line text metric snapshot.
#[derive(Clone, Copy, Debug, PartialEq)]
pub struct TextLineMetrics {
    /// Line width in logical pixels.
    pub width: f64,
    /// Line height in logical pixels.
    pub height: f64,
}

impl TextLineMetrics {
    /// Creates text line metrics.
    pub const fn new(width: f64, height: f64) -> Self {
        Self { width, height }
    }
}

/// Text metric snapshot used by engine geometry logic.
#[derive(Clone, Debug, PartialEq)]
pub struct TextMetrics {
    /// Total laid out width in logical pixels.
    pub width: f64,
    /// Total laid out height in logical pixels.
    pub height: f64,
    /// Effective single-line height in logical pixels.
    pub line_height: f64,
    /// Per-line metrics.
    pub lines: Vec<TextLineMetrics>,
}

impl TextMetrics {
    /// Creates text metrics.
    pub fn new(width: f64, height: f64, line_height: f64, lines: Vec<TextLineMetrics>) -> Self {
        Self {
            width,
            height,
            line_height,
            lines,
        }
    }
}

/// Backend-provided text metrics service for geometry-only calculations.
pub trait TextMetricsService: Debug + Send + Sync {
    /// Resolves text metrics for the given request.
    fn measure(&self, request: &TextLayoutRequest<'_>) -> TextMetrics;

    /// Clears cached internal state, if any.
    fn clear_caches(&self) {}
}

/// Pure-Rust fallback used when no backend text metrics service is injected.
///
/// This implementation prioritizes deterministic geometry over typographic
/// fidelity so reducers and tests can run without platform text APIs.
#[derive(Clone, Copy, Debug, Default)]
pub struct FallbackTextMetricsService;

impl FallbackTextMetricsService {
    const DEFAULT_FONT_SIZE: f64 = 14.0;
    const LINE_HEIGHT_FACTOR: f64 = 1.2;
    const GLYPH_WIDTH_FACTOR: f64 = 0.6;
}

impl TextMetricsService for FallbackTextMetricsService {
    fn measure(&self, request: &TextLayoutRequest<'_>) -> TextMetrics {
        let font_size = sanitize_positive_extent(request.data.font_size, Self::DEFAULT_FONT_SIZE);
        let line_height = font_size * Self::LINE_HEIGHT_FACTOR;
        let glyph_width = (font_size * Self::GLYPH_WIDTH_FACTOR).max(1.0);
        let text = if request.data.text.is_empty() {
            " "
        } else {
            request.data.text.as_str()
        };
        let max_width = resolve_text_max_width(request.max_width);

        let mut line_metrics = Vec::new();
        for line in text.split('\n') {
            append_line_metrics(&mut line_metrics, line, glyph_width, line_height, max_width);
        }
        if line_metrics.is_empty() {
            line_metrics.push(TextLineMetrics::new(glyph_width, line_height));
        }

        let mut width = line_metrics
            .iter()
            .fold(0.0_f64, |current_max, line| current_max.max(line.width));

        if let Some(min_width) = request.min_width {
            if min_width.is_finite() && min_width > 0.0 {
                let capped_min_width = if max_width.is_finite() {
                    min_width.min(max_width)
                } else {
                    min_width
                };
                if width < capped_min_width {
                    width = capped_min_width;
                }
            }
        }

        width = sanitize_positive_extent(width, glyph_width);
        let height = sanitize_positive_extent(line_height * line_metrics.len() as f64, line_height);

        TextMetrics::new(width, height, line_height, line_metrics)
    }
}

/// Shared default text metrics service used by engine reducers.
pub const DEFAULT_TEXT_METRICS_SERVICE: FallbackTextMetricsService = FallbackTextMetricsService;

/// Returns a heap-backed default service for APIs expecting a trait object.
pub fn default_text_metrics_service() -> Arc<dyn TextMetricsService> {
    Arc::new(FallbackTextMetricsService)
}

fn append_line_metrics(
    line_metrics: &mut Vec<TextLineMetrics>,
    line: &str,
    glyph_width: f64,
    line_height: f64,
    max_width: f64,
) {
    let grapheme_count = if line.is_empty() {
        1.0
    } else {
        line.chars().count() as f64
    };
    let raw_width = sanitize_positive_extent(grapheme_count * glyph_width, glyph_width);

    if !max_width.is_finite() {
        line_metrics.push(TextLineMetrics::new(raw_width, line_height));
        return;
    }

    let wraps = (raw_width / max_width).ceil().max(1.0) as usize;
    for index in 0..wraps {
        let remaining = raw_width - (max_width * index as f64);
        let line_width = if index + 1 == wraps {
            sanitize_positive_extent(remaining, raw_width.min(max_width))
        } else {
            max_width
        };
        line_metrics.push(TextLineMetrics::new(line_width, line_height));
    }
}

fn resolve_text_max_width(max_width: f64) -> f64 {
    if !max_width.is_finite() {
        return f64::INFINITY;
    }
    if max_width <= 0.0 {
        return 1.0;
    }
    max_width
}

fn sanitize_positive_extent(value: f64, fallback: f64) -> f64 {
    if value.is_finite() && value > 0.0 {
        value
    } else {
        fallback
    }
}
