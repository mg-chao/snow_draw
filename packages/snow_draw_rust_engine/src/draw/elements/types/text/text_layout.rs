#![allow(dead_code)]

use crate::draw::types::element_style::TextHorizontalAlign;

use super::text_data::TextData;
use super::text_editing_geometry::{
    FallbackTextMetricsService, TextData as GeometryTextData, TextLayoutRequest, TextLineMetrics,
    TextMetricsService,
};

/// Lightweight text size snapshot in logical pixels.
#[derive(Clone, Copy, Debug, PartialEq)]
pub struct TextLayoutSize {
    /// Width in logical pixels.
    pub width: f64,
    /// Height in logical pixels.
    pub height: f64,
}

/// Lightweight background box snapshot in local text coordinates.
#[derive(Clone, Copy, Debug, PartialEq)]
pub struct TextRangeBox {
    /// Left edge in local text coordinates.
    pub left: f64,
    /// Top edge in local text coordinates.
    pub top: f64,
    /// Right edge in local text coordinates.
    pub right: f64,
    /// Bottom edge in local text coordinates.
    pub bottom: f64,
}

/// Engine layout snapshot used by scene encoding and reducer tests.
#[derive(Clone, Debug, PartialEq)]
pub struct TextLayoutMetrics {
    /// Total text bounds in logical pixels.
    pub size: TextLayoutSize,
    /// Effective line height in logical pixels.
    pub line_height: f64,
    /// Per-line metrics.
    pub line_metrics: Vec<TextLineMetrics>,
    /// Layout max width used during measurement.
    pub max_width: f64,
    /// Horizontal text alignment.
    pub horizontal_align: TextHorizontalAlign,
    /// Measured text (empty text is normalized to a single space).
    pub text: String,
}

/// Clears any backend-provided text measurement caches.
pub fn clear_text_layout_caches() {
    let fallback = FallbackTextMetricsService;
    fallback.clear_caches();
}

/// Scene-focused text layout helper with fixed-width behavior.
pub fn layout_scene_text(
    data: &TextData,
    width: f64,
    locale_tag: Option<&str>,
    text_metrics_service: Option<&dyn TextMetricsService>,
) -> TextLayoutMetrics {
    layout_text(
        data,
        width,
        Some(width),
        locale_tag,
        false,
        text_metrics_service,
    )
}

/// Measures text with backend-agnostic `TextMetricsService`.
pub fn layout_text(
    data: &TextData,
    max_width: f64,
    min_width: Option<f64>,
    locale_tag: Option<&str>,
    is_resizing: bool,
    text_metrics_service: Option<&dyn TextMetricsService>,
) -> TextLayoutMetrics {
    let safe_max_width = resolve_text_max_width(max_width);
    let safe_min_width = resolve_min_width(min_width, safe_max_width);

    let metrics_data = GeometryTextData {
        text: data.text.clone(),
        font_size: data.font_size,
        auto_resize: data.auto_resize,
    };
    let request = TextLayoutRequest {
        data: &metrics_data,
        max_width: safe_max_width,
        min_width: Some(safe_min_width),
        locale_tag,
        is_resizing,
    };

    let fallback = FallbackTextMetricsService;
    let service = text_metrics_service.unwrap_or(&fallback);
    let metrics = service.measure(&request);

    let line_height = sanitize_positive_extent(metrics.line_height, 1.0);
    let width_fallback = if safe_min_width > 0.0 {
        safe_min_width
    } else {
        1.0
    };
    let width = sanitize_positive_extent(metrics.width, width_fallback);
    let height = sanitize_positive_extent(metrics.height, line_height);

    let line_metrics = if metrics.lines.is_empty() {
        vec![TextLineMetrics::new(width, line_height)]
    } else {
        metrics
            .lines
            .iter()
            .map(|line| {
                TextLineMetrics::new(
                    sanitize_positive_extent(line.width, width),
                    sanitize_positive_extent(line.height, line_height),
                )
            })
            .collect()
    };

    TextLayoutMetrics {
        size: TextLayoutSize { width, height },
        line_height,
        line_metrics,
        max_width: safe_max_width,
        horizontal_align: data.horizontal_align,
        text: if data.text.is_empty() {
            " ".to_owned()
        } else {
            data.text.clone()
        },
    }
}

/// Resolves range boxes as pure geometry values.
///
/// Partial selections are approximated by proportional glyph widths per line.
pub fn resolve_text_range_boxes(
    layout: &TextLayoutMetrics,
    start: i32,
    end: i32,
) -> Vec<TextRangeBox> {
    if end <= start {
        return Vec::new();
    }
    if layout.line_metrics.is_empty() {
        return Vec::new();
    }

    let text_length = layout.text.chars().count();
    if text_length == 0 {
        return build_full_line_boxes(layout);
    }

    let clamped_start = start.clamp(0, text_length as i32) as usize;
    let clamped_end = end.clamp(0, text_length as i32) as usize;
    if clamped_end <= clamped_start {
        return Vec::new();
    }

    if clamped_start == 0 && clamped_end == text_length {
        return build_full_line_boxes(layout);
    }

    let segments = build_line_segments(&layout.text, layout.line_metrics.len());
    let mut boxes = Vec::new();
    let mut top = 0.0;

    for (line, segment) in layout.line_metrics.iter().zip(segments.iter()) {
        let line_height = sanitize_positive_extent(line.height, layout.line_height);
        let overlap_start = clamped_start.max(segment.start);
        let overlap_end = clamped_end.min(segment.end);

        if overlap_end > overlap_start {
            let char_count = (segment.end.saturating_sub(segment.start)).max(1);
            let glyph_width = line.width / char_count as f64;
            let line_left = resolve_aligned_line_x(layout, line.width);
            let left = line_left + (overlap_start - segment.start) as f64 * glyph_width;
            let right = line_left + (overlap_end - segment.start) as f64 * glyph_width;
            boxes.push(TextRangeBox {
                left,
                top,
                right,
                bottom: top + line_height,
            });
        }

        top += line_height;
    }

    boxes
}

fn build_full_line_boxes(layout: &TextLayoutMetrics) -> Vec<TextRangeBox> {
    let mut boxes = Vec::new();
    let mut top = 0.0;

    for line in &layout.line_metrics {
        let line_width = sanitize_positive_extent(line.width, layout.size.width);
        let line_height = sanitize_positive_extent(line.height, layout.line_height);
        let left = resolve_aligned_line_x(layout, line_width);
        boxes.push(TextRangeBox {
            left,
            top,
            right: left + line_width,
            bottom: top + line_height,
        });
        top += line_height;
    }

    boxes
}

fn build_line_segments(text: &str, visual_line_count: usize) -> Vec<LineSegment> {
    if visual_line_count == 0 {
        return Vec::new();
    }

    let mut segments = Vec::new();
    let mut cursor = 0_usize;

    let lines: Vec<&str> = text.split('\n').collect();
    for (index, line) in lines.iter().enumerate() {
        let start = cursor;
        let end = cursor + line.chars().count();
        segments.push(LineSegment { start, end });
        cursor = end;
        if index + 1 < lines.len() {
            cursor += 1;
        }
    }

    if segments.is_empty() {
        segments.push(LineSegment { start: 0, end: 1 });
    }

    if segments.len() >= visual_line_count {
        return segments.into_iter().take(visual_line_count).collect();
    }

    let fallback = *segments
        .last()
        .expect("segments contains at least one item");
    while segments.len() < visual_line_count {
        segments.push(fallback);
    }
    segments
}

fn resolve_aligned_line_x(layout: &TextLayoutMetrics, line_width: f64) -> f64 {
    if !layout.max_width.is_finite() {
        return 0.0;
    }

    let delta = layout.max_width - line_width;
    if !delta.is_finite() || delta <= 0.0 {
        return 0.0;
    }

    match layout.horizontal_align {
        TextHorizontalAlign::Left => 0.0,
        TextHorizontalAlign::Center => delta / 2.0,
        TextHorizontalAlign::Right => delta,
    }
}

fn resolve_min_width(min_width: Option<f64>, max_width: f64) -> f64 {
    let Some(min_width) = min_width else {
        return 0.0;
    };

    if min_width <= 0.0 || min_width.is_nan() || min_width.is_infinite() {
        return 0.0;
    }
    if max_width.is_finite() && min_width > max_width {
        return max_width;
    }
    min_width
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

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
struct LineSegment {
    start: usize,
    end: usize,
}
