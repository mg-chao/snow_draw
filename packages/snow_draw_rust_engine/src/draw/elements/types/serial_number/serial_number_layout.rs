#![allow(dead_code)]

use std::collections::{HashMap, VecDeque};
use std::hash::Hash;
use std::sync::atomic::{AtomicU64, AtomicUsize, Ordering};
use std::sync::{Mutex, OnceLock};

use crate::draw::config::draw_config::ConfigDefaults;
use crate::draw::types::draw_point::DrawPoint;
use crate::draw::types::draw_rect::DrawRect;
use crate::draw::types::edit_context::TextMetricsService;
use crate::draw::utils::string_normalization::normalize_optional_trimmed_string;

use super::serial_number_data::SerialNumberData;

const SERIAL_NUMBER_PADDING_FACTOR: f64 = 0.26;
const TEXT_GEOMETRY_CACHE_MAX_ENTRIES: usize = 64;
const TEXT_PAINTER_CACHE_MAX_ENTRIES: usize = 192;
const CANONICAL_SERIAL_NUMBER_FONT_SIZE: f64 = ConfigDefaults::DEFAULT_SERIAL_NUMBER_FONT_SIZE;
const DEFAULT_LINE_HEIGHT_FACTOR: f64 = 1.2;
const DEFAULT_GLYPH_WIDTH_FACTOR: f64 = 0.6;

/// Lightweight serial-number text size snapshot.
#[derive(Clone, Copy, Debug, PartialEq)]
pub struct SerialNumberLayoutSize {
    pub width: f64,
    pub height: f64,
}

/// Lightweight visual bounds snapshot in local text coordinates.
#[derive(Clone, Copy, Debug, PartialEq)]
pub struct SerialNumberVisualBounds {
    pub left: f64,
    pub top: f64,
    pub right: f64,
    pub bottom: f64,
}

impl SerialNumberVisualBounds {
    /// Horizontal center in local coordinates.
    pub fn center_x(self) -> f64 {
        (self.left + self.right) / 2.0
    }

    /// Vertical center in local coordinates.
    pub fn center_y(self) -> f64 {
        (self.top + self.bottom) / 2.0
    }
}

/// Stable layout token used for cache identity checks.
#[derive(Clone, Copy, Debug, PartialEq, Eq, Hash)]
pub struct SerialNumberPainterToken(u64);

impl SerialNumberPainterToken {
    pub const fn raw(self) -> u64 {
        self.0
    }
}

/// Serial-number text layout metrics.
#[derive(Clone, Debug, PartialEq)]
pub struct SerialNumberTextLayout {
    pub painter: SerialNumberPainterToken,
    pub size: SerialNumberLayoutSize,
    pub line_height: f64,
    pub visual_bounds: Option<SerialNumberVisualBounds>,
    pub paint_scale: f64,
}

/// Cache diagnostics for serial-number text layout.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub struct SerialNumberLayoutCacheStats {
    /// Number of geometry cache misses.
    pub geometry_build_count: usize,
    /// Number of painter-token cache misses.
    pub painter_build_count: usize,
    /// Number of geometry cache entries.
    pub geometry_cache_entries: usize,
    /// Number of painter-token cache entries.
    pub painter_cache_entries: usize,
}

#[derive(Clone, Debug, PartialEq, Eq, Hash)]
struct TextGeometryKey {
    number: i64,
    font_family: Option<String>,
    locale_tag: Option<String>,
}

#[derive(Clone, Debug, PartialEq, Eq, Hash)]
struct TextPainterKey {
    geometry_key: TextGeometryKey,
    color_argb: u32,
}

#[derive(Clone, Debug, PartialEq)]
struct TextGeometry {
    size: SerialNumberLayoutSize,
    line_height: f64,
    visual_bounds: Option<SerialNumberVisualBounds>,
}

#[derive(Clone, Copy, Debug, PartialEq)]
struct ApproxTextMetrics {
    width: f64,
    height: f64,
    line_height: f64,
}

static TEXT_GEOMETRY_BUILD_COUNT: AtomicUsize = AtomicUsize::new(0);
static TEXT_PAINTER_BUILD_COUNT: AtomicUsize = AtomicUsize::new(0);
static NEXT_PAINTER_TOKEN: AtomicU64 = AtomicU64::new(1);

fn text_geometry_cache() -> &'static Mutex<LocalLruCache<TextGeometryKey, TextGeometry>> {
    static CACHE: OnceLock<Mutex<LocalLruCache<TextGeometryKey, TextGeometry>>> = OnceLock::new();
    CACHE.get_or_init(|| Mutex::new(LocalLruCache::new(TEXT_GEOMETRY_CACHE_MAX_ENTRIES)))
}

fn text_painter_cache() -> &'static Mutex<LocalLruCache<TextPainterKey, SerialNumberPainterToken>> {
    static CACHE: OnceLock<Mutex<LocalLruCache<TextPainterKey, SerialNumberPainterToken>>> =
        OnceLock::new();
    CACHE.get_or_init(|| Mutex::new(LocalLruCache::new(TEXT_PAINTER_CACHE_MAX_ENTRIES)))
}

/// Clears cached serial-number text layouts.
pub fn clear_serial_number_text_layout_cache() {
    let mut geometry_cache = text_geometry_cache()
        .lock()
        .expect("serial-number text-geometry cache mutex poisoned");
    geometry_cache.clear();
    drop(geometry_cache);

    let mut painter_cache = text_painter_cache()
        .lock()
        .expect("serial-number text-painter cache mutex poisoned");
    painter_cache.clear();

    TEXT_GEOMETRY_BUILD_COUNT.store(0, Ordering::Relaxed);
    TEXT_PAINTER_BUILD_COUNT.store(0, Ordering::Relaxed);
}

/// Returns cache diagnostics for serial-number text layout.
pub fn debug_serial_number_layout_cache_stats() -> SerialNumberLayoutCacheStats {
    let geometry_cache_entries = text_geometry_cache()
        .lock()
        .expect("serial-number text-geometry cache mutex poisoned")
        .len();
    let painter_cache_entries = text_painter_cache()
        .lock()
        .expect("serial-number text-painter cache mutex poisoned")
        .len();

    SerialNumberLayoutCacheStats {
        geometry_build_count: TEXT_GEOMETRY_BUILD_COUNT.load(Ordering::Relaxed),
        painter_build_count: TEXT_PAINTER_BUILD_COUNT.load(Ordering::Relaxed),
        geometry_cache_entries,
        painter_cache_entries,
    }
}

/// Resets cache-miss counters without clearing cache entries.
pub fn reset_serial_number_layout_cache_stats() {
    TEXT_GEOMETRY_BUILD_COUNT.store(0, Ordering::Relaxed);
    TEXT_PAINTER_BUILD_COUNT.store(0, Ordering::Relaxed);
}

/// Measures serial-number text with backend-agnostic metrics.
pub fn layout_serial_number_text(
    data: &SerialNumberData,
    color_argb_override: Option<u32>,
    locale_tag: Option<&str>,
    text_metrics_service: Option<&dyn TextMetricsService>,
) -> SerialNumberTextLayout {
    let sanitized_family = normalize_optional_trimmed_string(data.font_family.as_deref());
    let resolved_locale_tag = normalize_optional_trimmed_string(locale_tag);
    let font_scale = resolve_serial_number_font_scale(data.font_size);

    let geometry_key = TextGeometryKey {
        number: data.number,
        font_family: sanitized_family.clone(),
        locale_tag: resolved_locale_tag.clone(),
    };
    let color_argb = color_argb_override.unwrap_or_else(|| data.color.to_argb32());
    let painter_key = TextPainterKey {
        geometry_key: geometry_key.clone(),
        color_argb,
    };

    let painter_token = resolve_painter_token(painter_key);
    let geometry = resolve_text_geometry(geometry_key, || {
        build_text_geometry(
            data,
            sanitized_family.as_deref(),
            resolved_locale_tag.as_deref(),
            text_metrics_service,
        )
    });

    build_scaled_text_layout(painter_token, &geometry, font_scale)
}

/// Scene-focused serial-number text layout helper.
pub fn layout_serial_number_text_for_scene(
    data: &SerialNumberData,
    color_argb: u32,
    locale_tag: Option<&str>,
    text_metrics_service: Option<&dyn TextMetricsService>,
) -> SerialNumberTextLayout {
    layout_serial_number_text(data, Some(color_argb), locale_tag, text_metrics_service)
}

/// Resolves the visual center of the laid-out serial-number glyphs.
pub fn resolve_serial_number_visual_center(layout: &SerialNumberTextLayout) -> DrawPoint {
    match layout.visual_bounds {
        Some(bounds) => DrawPoint::new(bounds.center_x(), bounds.center_y()),
        None => DrawPoint::new(layout.size.width / 2.0, layout.size.height / 2.0),
    }
}

/// Resolves the serial-number circle diameter needed to fit text and padding.
pub fn resolve_serial_number_diameter(
    data: &SerialNumberData,
    min_diameter: f64,
    text_metrics_service: Option<&dyn TextMetricsService>,
) -> f64 {
    let layout = layout_serial_number_text(data, None, None, text_metrics_service);
    let text_height = layout.size.height.max(layout.line_height);
    let base_size = layout.size.width.max(text_height);
    let padding = layout.line_height * SERIAL_NUMBER_PADDING_FACTOR;
    let diameter = base_size + padding * 2.0;

    if diameter.is_nan() || diameter.is_infinite() {
        return min_diameter;
    }

    if diameter >= min_diameter {
        diameter
    } else {
        min_diameter
    }
}

/// Resolves stroke width scaled relative to serial-number font size.
pub fn resolve_serial_number_stroke_width(data: &SerialNumberData, min_stroke_width: f64) -> f64 {
    let base_size = CANONICAL_SERIAL_NUMBER_FONT_SIZE;
    if base_size <= 0.0 {
        return if data.stroke_width >= min_stroke_width {
            data.stroke_width
        } else {
            min_stroke_width
        };
    }

    let scaled = data.stroke_width * (data.font_size / base_size);
    if scaled.is_nan() || scaled.is_infinite() {
        return min_stroke_width;
    }

    if scaled >= min_stroke_width {
        scaled
    } else {
        min_stroke_width
    }
}

/// Resolves the serial-number world rectangle from top-left origin.
pub fn resolve_serial_number_rect(
    origin: DrawPoint,
    data: &SerialNumberData,
    min_diameter: f64,
    text_metrics_service: Option<&dyn TextMetricsService>,
) -> DrawRect {
    let diameter = resolve_serial_number_diameter(data, min_diameter, text_metrics_service);
    DrawRect::new(origin.x, origin.y, origin.x + diameter, origin.y + diameter)
}

fn resolve_painter_token(key: TextPainterKey) -> SerialNumberPainterToken {
    let mut cache = text_painter_cache()
        .lock()
        .expect("serial-number text-painter cache mutex poisoned");

    if let Some(token) = cache.get(&key).copied() {
        return token;
    }

    let token = SerialNumberPainterToken(NEXT_PAINTER_TOKEN.fetch_add(1, Ordering::Relaxed));
    cache.put(key, token);
    TEXT_PAINTER_BUILD_COUNT.fetch_add(1, Ordering::Relaxed);
    token
}

fn resolve_text_geometry<F>(key: TextGeometryKey, builder: F) -> TextGeometry
where
    F: FnOnce() -> TextGeometry,
{
    let mut cache = text_geometry_cache()
        .lock()
        .expect("serial-number text-geometry cache mutex poisoned");

    if let Some(geometry) = cache.get(&key).cloned() {
        return geometry;
    }

    let geometry = builder();
    cache.put(key, geometry.clone());
    TEXT_GEOMETRY_BUILD_COUNT.fetch_add(1, Ordering::Relaxed);
    geometry
}

fn build_scaled_text_layout(
    painter_token: SerialNumberPainterToken,
    geometry: &TextGeometry,
    font_scale: f64,
) -> SerialNumberTextLayout {
    if double_equals(font_scale, 1.0) {
        return SerialNumberTextLayout {
            painter: painter_token,
            size: geometry.size,
            line_height: geometry.line_height,
            visual_bounds: geometry.visual_bounds,
            paint_scale: 1.0,
        };
    }

    SerialNumberTextLayout {
        painter: painter_token,
        size: scale_size(geometry.size, font_scale),
        line_height: geometry.line_height * font_scale,
        visual_bounds: scale_visual_bounds(geometry.visual_bounds, font_scale),
        paint_scale: font_scale,
    }
}

fn scale_size(size: SerialNumberLayoutSize, scale: f64) -> SerialNumberLayoutSize {
    SerialNumberLayoutSize {
        width: size.width * scale,
        height: size.height * scale,
    }
}

fn scale_visual_bounds(
    bounds: Option<SerialNumberVisualBounds>,
    scale: f64,
) -> Option<SerialNumberVisualBounds> {
    bounds.map(|value| SerialNumberVisualBounds {
        left: value.left * scale,
        top: value.top * scale,
        right: value.right * scale,
        bottom: value.bottom * scale,
    })
}

fn build_text_geometry(
    data: &SerialNumberData,
    _font_family: Option<&str>,
    _locale_tag: Option<&str>,
    _text_metrics_service: Option<&dyn TextMetricsService>,
) -> TextGeometry {
    // The current crate-level `TextMetricsService` is a marker trait.
    // Use the same deterministic fallback strategy as the Dart fallback service.
    let metrics = measure_fallback_text_metrics(&data.number.to_string());
    let width = sanitize_positive_extent(metrics.width, 1.0);
    let line_height = sanitize_positive_extent(metrics.line_height, 1.0);
    let height = sanitize_positive_extent(metrics.height, line_height);

    TextGeometry {
        size: SerialNumberLayoutSize { width, height },
        line_height,
        visual_bounds: Some(SerialNumberVisualBounds {
            left: 0.0,
            top: 0.0,
            right: width,
            bottom: height,
        }),
    }
}

fn measure_fallback_text_metrics(text: &str) -> ApproxTextMetrics {
    let font_size = sanitize_positive_extent(CANONICAL_SERIAL_NUMBER_FONT_SIZE, 14.0);
    let line_height = sanitize_positive_extent(font_size * DEFAULT_LINE_HEIGHT_FACTOR, 1.0);
    let glyph_width = (font_size * DEFAULT_GLYPH_WIDTH_FACTOR).max(1.0);
    let content = if text.is_empty() { " " } else { text };

    let mut max_width = 0.0;
    let mut line_count = 0usize;
    for line in content.split('\n') {
        line_count += 1;
        let grapheme_count = line.chars().count().max(1) as f64;
        let raw_width = sanitize_positive_extent(grapheme_count * glyph_width, glyph_width);
        if raw_width > max_width {
            max_width = raw_width;
        }
    }

    if line_count == 0 {
        line_count = 1;
    }

    ApproxTextMetrics {
        width: sanitize_positive_extent(max_width, glyph_width),
        height: sanitize_positive_extent(line_height * line_count as f64, line_height),
        line_height,
    }
}

fn resolve_serial_number_font_scale(font_size: f64) -> f64 {
    let base_size = CANONICAL_SERIAL_NUMBER_FONT_SIZE;
    if base_size <= 0.0 || !base_size.is_finite() {
        return 1.0;
    }

    if !font_size.is_finite() || font_size <= 0.0 {
        return 0.0;
    }

    font_size / base_size
}

fn double_equals(a: f64, b: f64) -> bool {
    (a - b).abs() <= 0.0001
}

fn sanitize_positive_extent(value: f64, fallback: f64) -> f64 {
    if value.is_finite() && value > 0.0 {
        return value;
    }
    fallback
}

struct LocalLruCache<K, V>
where
    K: Eq + Hash + Clone,
{
    max_entries: usize,
    entries: HashMap<K, V>,
    access_order: VecDeque<K>,
}

impl<K, V> LocalLruCache<K, V>
where
    K: Eq + Hash + Clone,
{
    fn new(max_entries: usize) -> Self {
        Self {
            max_entries,
            entries: HashMap::new(),
            access_order: VecDeque::new(),
        }
    }

    fn len(&self) -> usize {
        self.entries.len()
    }

    fn clear(&mut self) {
        self.entries.clear();
        self.access_order.clear();
    }

    fn get(&mut self, key: &K) -> Option<&V> {
        if !self.entries.contains_key(key) {
            return None;
        }
        self.touch(key);
        self.entries.get(key)
    }

    fn put(&mut self, key: K, value: V) {
        if self.entries.contains_key(&key) {
            self.entries.remove(&key);
            self.remove_from_order(&key);
        }

        self.entries.insert(key.clone(), value);
        self.access_order.push_back(key);

        while self.entries.len() > self.max_entries {
            let Some(least_recent_key) = self.access_order.pop_front() else {
                break;
            };
            self.entries.remove(&least_recent_key);
        }
    }

    fn touch(&mut self, key: &K) {
        self.remove_from_order(key);
        self.access_order.push_back(key.clone());
    }

    fn remove_from_order(&mut self, key: &K) {
        if let Some(index) = self
            .access_order
            .iter()
            .position(|candidate| candidate == key)
        {
            self.access_order.remove(index);
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn approx_eq(a: f64, b: f64) -> bool {
        (a - b).abs() < 1e-6
    }

    #[test]
    fn cache_reuses_geometry_and_painter_by_key() {
        clear_serial_number_text_layout_cache();
        let data = SerialNumberData::default();

        let first = layout_serial_number_text(&data, None, None, None);
        let second = layout_serial_number_text(&data, None, None, None);

        assert_eq!(first.painter, second.painter);

        let stats = debug_serial_number_layout_cache_stats();
        assert_eq!(stats.geometry_build_count, 1);
        assert_eq!(stats.painter_build_count, 1);
        assert_eq!(stats.geometry_cache_entries, 1);
        assert_eq!(stats.painter_cache_entries, 1);
    }

    #[test]
    fn cache_reuses_geometry_but_splits_painter_by_color() {
        clear_serial_number_text_layout_cache();
        let data = SerialNumberData::default();
        let color_a = data.color.to_argb32();
        let color_b = color_a ^ 0x00FF_FFFF;

        let first = layout_serial_number_text(&data, Some(color_a), None, None);
        let second = layout_serial_number_text(&data, Some(color_b), None, None);

        assert_ne!(first.painter, second.painter);

        let stats = debug_serial_number_layout_cache_stats();
        assert_eq!(stats.geometry_build_count, 1);
        assert_eq!(stats.painter_build_count, 2);
        assert_eq!(stats.geometry_cache_entries, 1);
        assert_eq!(stats.painter_cache_entries, 2);
    }

    #[test]
    fn resolves_diameter_stroke_and_rect_consistently() {
        clear_serial_number_text_layout_cache();
        let mut data = SerialNumberData::default();
        data.font_size = 32.0;
        data.stroke_width = 2.0;

        let stroke = resolve_serial_number_stroke_width(&data, 0.0);
        assert!(approx_eq(stroke, 4.0));

        let diameter = resolve_serial_number_diameter(&data, 0.0, None);
        assert!(diameter > 0.0);

        let rect = resolve_serial_number_rect(DrawPoint::new(10.0, 20.0), &data, 0.0, None);
        assert!(approx_eq(rect.min_x, 10.0));
        assert!(approx_eq(rect.min_y, 20.0));
        assert!(approx_eq(rect.width(), diameter));
        assert!(approx_eq(rect.height(), diameter));
    }
}
