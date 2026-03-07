#![allow(dead_code)]

use crate::draw::types::draw_point::DrawPoint;
use crate::draw::types::draw_rect::DrawRect;
use std::sync::Arc;

/// Geometry resolved for an in-progress text draft.
///
/// Carries both the target `rect` and the measured `layout` so callers can
/// reuse metrics without measuring again in the same frame.
#[derive(Clone, Debug, PartialEq)]
pub struct TextEditingGeometry {
    pub rect: DrawRect,
    pub layout: TextMetrics,
}

impl TextEditingGeometry {
    pub fn new(rect: DrawRect, layout: TextMetrics) -> Self {
        Self { rect, layout }
    }
}

/// Minimal text payload used by text-editing geometry.
///
/// This mirrors the subset of Dart `TextData` required by geometry and fallback
/// metric computation.
#[derive(Clone, Debug, PartialEq)]
pub struct TextData {
    pub text: String,
    pub font_size: f64,
    pub auto_resize: bool,
}

impl Default for TextData {
    fn default() -> Self {
        Self {
            text: String::new(),
            font_size: 14.0,
            auto_resize: true,
        }
    }
}

/// Request payload for text metric measurement.
#[derive(Clone, Debug, PartialEq)]
pub struct TextLayoutRequest<'a> {
    pub data: &'a TextData,
    pub max_width: f64,
    pub min_width: Option<f64>,
    pub locale_tag: Option<&'a str>,
    pub is_resizing: bool,
}

impl<'a> TextLayoutRequest<'a> {
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

/// Per-line metric snapshot.
#[derive(Clone, Copy, Debug, PartialEq)]
pub struct TextLineMetrics {
    pub width: f64,
    pub height: f64,
}

impl TextLineMetrics {
    pub const fn new(width: f64, height: f64) -> Self {
        Self { width, height }
    }
}

/// Metric snapshot consumed by geometry resolvers.
#[derive(Clone, Debug, PartialEq)]
pub struct TextMetrics {
    pub width: f64,
    pub height: f64,
    pub line_height: f64,
    pub lines: Vec<TextLineMetrics>,
}

impl TextMetrics {
    pub fn new(width: f64, height: f64, line_height: f64, lines: Vec<TextLineMetrics>) -> Self {
        Self {
            width,
            height,
            line_height,
            lines,
        }
    }
}

/// Backend-provided text metrics service for geometry calculations.
pub trait TextMetricsService: std::fmt::Debug + Send + Sync {
    fn measure(&self, request: &TextLayoutRequest<'_>) -> TextMetrics;

    fn clear_caches(&self) {}
}

/// Pure-Rust fallback used when no backend text metrics service is provided.
///
/// Prioritizes deterministic geometry over typographic fidelity.
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

        let mut line_metrics: Vec<TextLineMetrics> = Vec::new();
        for line in text.split('\n') {
            append_line_metrics(&mut line_metrics, line, glyph_width, line_height, max_width);
        }
        if line_metrics.is_empty() {
            line_metrics.push(TextLineMetrics::new(glyph_width, line_height));
        }

        let mut width = line_metrics
            .iter()
            .fold(0.0_f64, |acc, line| acc.max(line.width));

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

/// Returns the shared default text metrics service.
pub fn default_text_metrics_service() -> Arc<dyn TextMetricsService> {
    Arc::new(FallbackTextMetricsService)
}

/// Resolves the initial text editing rect for a newly created text element.
pub fn resolve_initial_text_editing_rect(
    position: DrawPoint,
    data: &TextData,
    text_metrics_service: Option<&dyn TextMetricsService>,
    locale_tag: Option<&str>,
) -> DrawRect {
    resolve_initial_text_editing_geometry(position, data, text_metrics_service, locale_tag).rect
}

/// Resolves geometry for the initial text editing rect of a newly created text
/// element.
pub fn resolve_initial_text_editing_geometry(
    position: DrawPoint,
    data: &TextData,
    text_metrics_service: Option<&dyn TextMetricsService>,
    locale_tag: Option<&str>,
) -> TextEditingGeometry {
    resolve_content_sized_text_editing_geometry(position, data, text_metrics_service, locale_tag)
}

/// Resolves the text editing rect for the next draft payload.
///
/// Width auto-resizes when `TextData.auto_resize` is enabled. Height is clamped
/// to fit actual text content and optionally shrinks when
/// `allow_shrink_height` is true.
pub fn resolve_text_editing_rect(
    origin: DrawPoint,
    current_rect: DrawRect,
    data: &TextData,
    text_metrics_service: Option<&dyn TextMetricsService>,
    allow_shrink_height: bool,
    locale_tag: Option<&str>,
) -> DrawRect {
    resolve_text_editing_geometry(
        origin,
        current_rect,
        data,
        text_metrics_service,
        allow_shrink_height,
        locale_tag,
    )
    .rect
}

/// Resolves geometry for an in-progress text edit draft.
///
/// The returned `TextEditingGeometry.layout` can be reused by callers that need
/// text metrics in addition to the resulting `TextEditingGeometry.rect`.
pub fn resolve_text_editing_geometry(
    origin: DrawPoint,
    current_rect: DrawRect,
    data: &TextData,
    text_metrics_service: Option<&dyn TextMetricsService>,
    allow_shrink_height: bool,
    locale_tag: Option<&str>,
) -> TextEditingGeometry {
    if data.auto_resize {
        return resolve_content_sized_text_editing_geometry(
            origin,
            data,
            text_metrics_service,
            locale_tag,
        );
    }

    let fallback = FallbackTextMetricsService;
    let service = text_metrics_service.unwrap_or(&fallback);

    let layout = service.measure(&TextLayoutRequest {
        data,
        max_width: current_rect.width(),
        min_width: None,
        locale_tag,
        is_resizing: false,
    });

    let content_height = resolve_content_height(&layout);
    let next_height = if allow_shrink_height {
        content_height
    } else {
        current_rect.height().max(content_height)
    };

    build_text_editing_geometry(origin, current_rect.width(), next_height, layout)
}

/// Resolves rect for auto-resizing text when font metrics change.
pub fn resolve_auto_resize_text_editing_rect(
    origin: DrawPoint,
    data: &TextData,
    text_metrics_service: Option<&dyn TextMetricsService>,
    locale_tag: Option<&str>,
) -> DrawRect {
    resolve_auto_resize_text_editing_geometry(origin, data, text_metrics_service, locale_tag).rect
}

/// Resolves geometry for auto-resizing text when font metrics change.
pub fn resolve_auto_resize_text_editing_geometry(
    origin: DrawPoint,
    data: &TextData,
    text_metrics_service: Option<&dyn TextMetricsService>,
    locale_tag: Option<&str>,
) -> TextEditingGeometry {
    resolve_content_sized_text_editing_geometry(origin, data, text_metrics_service, locale_tag)
}

fn resolve_content_sized_text_editing_geometry(
    origin: DrawPoint,
    data: &TextData,
    text_metrics_service: Option<&dyn TextMetricsService>,
    locale_tag: Option<&str>,
) -> TextEditingGeometry {
    let fallback = FallbackTextMetricsService;
    let service = text_metrics_service.unwrap_or(&fallback);

    let layout = service.measure(&TextLayoutRequest {
        data,
        max_width: f64::INFINITY,
        min_width: None,
        locale_tag,
        is_resizing: false,
    });

    build_text_editing_geometry(
        origin,
        resolve_content_width(&layout),
        resolve_content_height(&layout),
        layout,
    )
}

fn build_text_editing_geometry(
    origin: DrawPoint,
    width: f64,
    height: f64,
    layout: TextMetrics,
) -> TextEditingGeometry {
    TextEditingGeometry::new(
        DrawRect::new(origin.x, origin.y, origin.x + width, origin.y + height),
        layout,
    )
}

fn resolve_content_width(layout: &TextMetrics) -> f64 {
    let horizontal_padding = resolve_text_layout_horizontal_padding(layout.line_height);
    layout.width + (horizontal_padding * 2.0)
}

fn resolve_content_height(layout: &TextMetrics) -> f64 {
    layout.height.max(layout.line_height)
}

const TEXT_LAYOUT_HORIZONTAL_PADDING_FACTOR: f64 = 0.01;

/// Resolves horizontal layout padding from line height.
pub fn resolve_text_layout_horizontal_padding(line_height: f64) -> f64 {
    let padding = line_height * TEXT_LAYOUT_HORIZONTAL_PADDING_FACTOR;
    if padding.is_nan() || padding.is_infinite() {
        0.0
    } else {
        padding
    }
}

fn resolve_text_max_width(max_width: f64) -> f64 {
    if max_width.is_finite() && max_width > 0.0 {
        max_width
    } else {
        f64::INFINITY
    }
}

fn sanitize_positive_extent(value: f64, fallback: f64) -> f64 {
    if value.is_finite() && value > 0.0 {
        value
    } else {
        fallback
    }
}

fn append_line_metrics(
    line_metrics: &mut Vec<TextLineMetrics>,
    line: &str,
    glyph_width: f64,
    line_height: f64,
    max_width: f64,
) {
    let grapheme_count = line.chars().count().max(1) as f64;
    let raw_width = sanitize_positive_extent(grapheme_count * glyph_width, glyph_width);

    if !max_width.is_finite() {
        line_metrics.push(TextLineMetrics::new(raw_width, line_height));
        return;
    }

    let wraps = (raw_width / max_width).ceil().max(1.0) as usize;
    for i in 0..wraps {
        let remaining = raw_width - (max_width * i as f64);
        let line_width = if i == wraps - 1 {
            sanitize_positive_extent(remaining, raw_width.min(max_width))
        } else {
            max_width
        };
        line_metrics.push(TextLineMetrics::new(line_width, line_height));
    }
}
