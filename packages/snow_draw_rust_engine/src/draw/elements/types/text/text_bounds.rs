#![allow(dead_code)]

use crate::draw::elements::types::text::text_data::{TextData, TextDataPatch};
use crate::draw::elements::types::text::text_layout_constants::resolve_text_layout_horizontal_padding;
use crate::draw::services::text::text_metrics_service::{
    TextLayoutRequest, TextMetrics, TextMetricsService, DEFAULT_TEXT_METRICS_SERVICE,
};
use crate::draw::types::draw_point::DrawPoint;
use crate::draw::types::draw_rect::DrawRect;

/// Clamps a text rectangle to the minimum width and minimum layout height.
pub fn clamp_text_rect_to_layout(
    rect: DrawRect,
    start_rect: DrawRect,
    anchor: DrawPoint,
    data: &TextData,
    text_metrics_service: Option<&dyn TextMetricsService>,
    keep_center: bool,
) -> DrawRect {
    let metrics_service = text_metrics_service.unwrap_or(&DEFAULT_TEXT_METRICS_SERVICE);

    let base_layout = metrics_service.measure(&TextLayoutRequest::new(data, rect.width()));
    let horizontal_padding = resolve_text_layout_horizontal_padding(base_layout.line_height);
    let min_width = resolve_min_width(data, metrics_service) + horizontal_padding * 2.0;
    let should_clamp_width = rect.width() < min_width;

    let mut min_x = rect.min_x;
    let mut max_x = rect.max_x;
    if should_clamp_width {
        if keep_center {
            let half_width = min_width / 2.0;
            min_x = rect.center_x() - half_width;
            max_x = rect.center_x() + half_width;
        } else if anchor.x <= rect.min_x {
            max_x = rect.min_x + min_width;
        } else if anchor.x >= rect.max_x {
            min_x = rect.max_x - min_width;
        } else {
            let ratio = anchor_ratio(anchor.x, start_rect.min_x, start_rect.max_x);
            min_x = anchor.x - min_width * ratio;
            max_x = min_x + min_width;
        }
    }

    let layout = if should_clamp_width {
        metrics_service.measure(&TextLayoutRequest::new(data, min_width))
    } else {
        base_layout
    };
    let min_height = resolve_text_layout_height(&layout);

    DrawRect::new(min_x, rect.min_y, max_x, rect.min_y + min_height)
}

/// Resolves a safe text layout height.
pub fn resolve_text_layout_height(layout: &TextMetrics) -> f64 {
    sanitize_extent(layout.line_height.max(layout.height))
}

/// Fits text font size to a target layout height for a constrained width.
pub fn fit_text_font_size_to_height(
    data: &TextData,
    target_height: f64,
    max_width: f64,
    text_metrics_service: Option<&dyn TextMetricsService>,
    min_font_size: f64,
    max_iterations: usize,
    tolerance: f64,
) -> f64 {
    let metrics_service = text_metrics_service.unwrap_or(&DEFAULT_TEXT_METRICS_SERVICE);

    let safe_width = sanitize_extent(max_width);
    let safe_target_height = sanitize_extent(target_height);
    let safe_min_font_size = sanitize_extent(min_font_size);
    let safe_max_iterations = max_iterations.max(1);
    let safe_tolerance = tolerance.max(0.0);
    let base_font_size = sanitize_extent(data.font_size).max(safe_min_font_size);

    let base_height = resolve_height(data, base_font_size, safe_width, metrics_service);
    if (base_height - safe_target_height).abs() <= safe_tolerance {
        return base_font_size;
    }

    let low_height = resolve_height(data, safe_min_font_size, safe_width, metrics_service);
    if low_height >= safe_target_height {
        return safe_min_font_size;
    }

    let mut low = safe_min_font_size;
    let mut high = if base_font_size < safe_target_height {
        safe_target_height
    } else {
        base_font_size
    };
    let mut high_height = if high == base_font_size {
        base_height
    } else {
        resolve_height(data, high, safe_width, metrics_service)
    };

    if high_height < safe_target_height {
        let mut attempts = 0usize;
        while high_height < safe_target_height && attempts < safe_max_iterations {
            high *= 1.5;
            high_height = resolve_height(data, high, safe_width, metrics_service);
            attempts += 1;
        }
        if high_height < safe_target_height {
            return high;
        }
    }

    let span = high_height - low_height;
    if span > 0.0 {
        let ratio = (safe_target_height - low_height) / span;
        let estimate = low + (high - low) * ratio;
        let estimate_height = resolve_height(data, estimate, safe_width, metrics_service);
        if (estimate_height - safe_target_height).abs() <= safe_tolerance {
            return estimate;
        }
        if estimate_height > safe_target_height {
            high = estimate;
        } else {
            low = estimate;
        }
    }

    for _ in 0..safe_max_iterations {
        let mid = (low + high) / 2.0;
        let height = resolve_height(data, mid, safe_width, metrics_service);
        if (height - safe_target_height).abs() <= safe_tolerance {
            return mid;
        }
        if height > safe_target_height {
            high = mid;
        } else {
            low = mid;
        }
    }

    low
}

fn resolve_min_width(data: &TextData, text_metrics_service: &dyn TextMetricsService) -> f64 {
    let layout = text_metrics_service.measure(&TextLayoutRequest::new(data, 1.0));
    let mut max_line_width = 0.0;
    for line in &layout.lines {
        if line.width > max_line_width {
            max_line_width = line.width;
        }
    }
    if max_line_width <= 0.0 || !max_line_width.is_finite() {
        return sanitize_extent(layout.width);
    }
    sanitize_extent(max_line_width)
}

fn anchor_ratio(anchor: f64, min: f64, max: f64) -> f64 {
    let span = max - min;
    if span <= 0.0 || !span.is_finite() {
        return 0.5;
    }
    let raw = (anchor - min) / span;
    if !raw.is_finite() {
        return 0.5;
    }
    raw.clamp(0.0, 1.0)
}

fn sanitize_extent(value: f64) -> f64 {
    if value.is_finite() && value > 0.0 {
        value
    } else {
        1.0
    }
}

fn resolve_height(
    data: &TextData,
    font_size: f64,
    max_width: f64,
    text_metrics_service: &dyn TextMetricsService,
) -> f64 {
    let adjusted_data = data.copy_with(TextDataPatch {
        font_size: Some(font_size),
        ..TextDataPatch::default()
    });
    let layout = text_metrics_service.measure(&TextLayoutRequest::new(&adjusted_data, max_width));
    resolve_text_layout_height(&layout)
}
