#![allow(dead_code)]

use std::collections::HashMap;
use std::sync::{Arc, Mutex, OnceLock};

use crate::draw::config::draw_config::{ConfigDefaults, DrawConfig};
use crate::draw::elements::core::creation_strategy::{
    finish_creation_with_current_rect, require_creating_element_data_type,
    require_creation_data_type, snap_creation_point, CreatingState, CreationFinishResult,
    CreationMode, CreationStrategy, CreationUpdateResult, DrawState, ElementData,
};
use crate::draw::elements::types::serial_number::serial_number_data::SerialNumberData as DomainSerialNumberData;
use crate::draw::types::draw_point::DrawPoint;
use crate::draw::types::draw_rect::DrawRect;
use crate::draw::types::edit_context::{default_text_metrics_service, TextMetricsService};
use crate::draw::utils::snapping_mode::SnappingMode;
use crate::draw::utils::string_normalization::normalize_optional_trimmed_string;

const SERIAL_NUMBER_PADDING_FACTOR: f64 = 0.26;
const APPROX_DIGIT_WIDTH_FACTOR: f64 = 0.62;

/// Creation strategy for serial-number elements.
///
/// This mirrors the Dart `SerialNumberCreationStrategy` behavior while keeping
/// the module compile-friendly before the serial-number layout module is fully
/// translated.
#[derive(Debug, Default, Clone, Copy)]
pub struct SerialNumberCreationStrategy;

impl SerialNumberCreationStrategy {
    pub const fn new() -> Self {
        Self
    }
}

impl CreationStrategy for SerialNumberCreationStrategy {
    fn start(
        &self,
        data: Arc<dyn ElementData>,
        start_position: DrawPoint,
        text_metrics_service: Option<Arc<dyn TextMetricsService>>,
    ) -> CreationUpdateResult {
        let text_metrics_service =
            text_metrics_service.unwrap_or_else(default_text_metrics_service);
        let serial_data = require_creation_data_type::<DomainSerialNumberData>(
            &data,
            "SerialNumberCreationStrategy.start",
        );
        let base_diameter = resolve_serial_number_diameter(serial_data, &text_metrics_service);
        let diameter =
            resolve_diameter_with_min(base_diameter, ConfigDefaults::MIN_CREATE_ELEMENT_SIZE);
        let mode = SerialNumberCreationMode::from_data(serial_data, base_diameter);

        // CreationMode currently has no serial-number payload variant.
        // Cache the translated mode so update can reuse the measured diameter
        // while keeping the public core creation model unchanged.
        cache_creation_mode_for_untracked_start(mode);

        CreationUpdateResult::new(
            data,
            rect_from_center(start_position, diameter),
            CreationMode::Rect,
            Vec::new(),
        )
    }

    fn update(
        &self,
        _state: &DrawState,
        config: &DrawConfig,
        creating_state: &CreatingState,
        current_position: DrawPoint,
        _maintain_aspect_ratio: bool,
        _create_from_center: bool,
        snapping_mode: SnappingMode,
        _snap_override_active: bool,
        text_metrics_service: Option<Arc<dyn TextMetricsService>>,
    ) -> CreationUpdateResult {
        let text_metrics_service =
            text_metrics_service.unwrap_or_else(default_text_metrics_service);
        let serial_data = require_creating_element_data_type::<DomainSerialNumberData>(
            creating_state,
            "SerialNumberCreationStrategy.update",
        );
        let snapped_position = snap_creation_point(current_position, config, snapping_mode);
        let cached_mode = resolve_creation_mode(creating_state);
        let reuse_cached_mode = cached_mode
            .as_ref()
            .map(|mode| mode.matches(serial_data))
            .unwrap_or(false);
        let base_diameter = if reuse_cached_mode {
            cached_mode
                .as_ref()
                .map(|mode| mode.base_diameter)
                .unwrap_or_default()
        } else {
            resolve_serial_number_diameter(serial_data, &text_metrics_service)
        };
        let diameter = resolve_diameter_with_min(base_diameter, config.element.min_create_size);
        let next_creation_mode = if reuse_cached_mode {
            cached_mode
                .unwrap_or_else(|| SerialNumberCreationMode::from_data(serial_data, base_diameter))
        } else {
            SerialNumberCreationMode::from_data(serial_data, base_diameter)
        };
        cache_creation_mode(&creating_state.element.id, next_creation_mode);

        CreationUpdateResult::new(
            creating_state.element_data(),
            rect_from_center(snapped_position, diameter),
            creating_state.creation_mode.clone(),
            Vec::new(),
        )
    }

    fn finish(
        &self,
        _state: &DrawState,
        config: &DrawConfig,
        creating_state: &CreatingState,
        text_metrics_service: Option<Arc<dyn TextMetricsService>>,
    ) -> CreationFinishResult {
        let _ = text_metrics_service.unwrap_or_else(default_text_metrics_service);
        clear_creation_mode(&creating_state.element.id);
        finish_creation_with_current_rect(config, creating_state)
    }
}

fn resolve_creation_mode(creating_state: &CreatingState) -> Option<SerialNumberCreationMode> {
    lookup_creation_mode(&creating_state.element.id).or_else(take_untracked_start_mode)
}

fn resolve_diameter_with_min(base_diameter: f64, min_diameter: f64) -> f64 {
    let sanitized_min = if min_diameter.is_finite() {
        min_diameter.max(0.0)
    } else {
        0.0
    };
    if !base_diameter.is_finite() {
        return sanitized_min;
    }
    base_diameter.max(sanitized_min)
}

fn rect_from_center(center: DrawPoint, size: f64) -> DrawRect {
    let half = size / 2.0;
    DrawRect::new(
        center.x - half,
        center.y - half,
        center.x + half,
        center.y + half,
    )
}

fn resolve_serial_number_diameter(
    data: &DomainSerialNumberData,
    _text_metrics_service: &Arc<dyn TextMetricsService>,
) -> f64 {
    let font_size = sanitize_positive_extent(data.font_size, 0.0);
    if font_size <= 0.0 {
        return 0.0;
    }

    // `TextMetricsService` is still a marker trait in this crate, so use a
    // deterministic width/height approximation equivalent in spirit to Dart's
    // text-layout driven diameter.
    let digit_count = resolve_digit_count(data.number) as f64;
    let width = (digit_count * font_size * APPROX_DIGIT_WIDTH_FACTOR).max(font_size);
    let line_height = font_size.max(1.0);
    let text_height = line_height;
    let base_size = width.max(text_height);
    let padding = line_height * SERIAL_NUMBER_PADDING_FACTOR;
    let diameter = base_size + padding * 2.0;

    if diameter.is_finite() {
        diameter
    } else {
        0.0
    }
}

fn resolve_digit_count(number: i64) -> usize {
    let normalized = number.max(0);
    normalized.to_string().chars().count().max(1)
}

fn sanitize_positive_extent(value: f64, fallback: f64) -> f64 {
    if value.is_finite() && value > 0.0 {
        value
    } else {
        fallback
    }
}

fn creation_mode_store() -> &'static Mutex<HashMap<String, SerialNumberCreationMode>> {
    static STORE: OnceLock<Mutex<HashMap<String, SerialNumberCreationMode>>> = OnceLock::new();
    STORE.get_or_init(|| Mutex::new(HashMap::new()))
}

fn lookup_creation_mode(element_id: &str) -> Option<SerialNumberCreationMode> {
    let store = creation_mode_store()
        .lock()
        .expect("serial number creation mode mutex poisoned");
    store.get(element_id).cloned()
}

fn cache_creation_mode(element_id: &str, mode: SerialNumberCreationMode) {
    let mut store = creation_mode_store()
        .lock()
        .expect("serial number creation mode mutex poisoned");
    store.insert(element_id.to_owned(), mode);
}

fn clear_creation_mode(element_id: &str) {
    let mut store = creation_mode_store()
        .lock()
        .expect("serial number creation mode mutex poisoned");
    store.remove(element_id);
}

fn untracked_start_mode_store() -> &'static Mutex<Option<SerialNumberCreationMode>> {
    static STORE: OnceLock<Mutex<Option<SerialNumberCreationMode>>> = OnceLock::new();
    STORE.get_or_init(|| Mutex::new(None))
}

fn cache_creation_mode_for_untracked_start(mode: SerialNumberCreationMode) {
    let mut slot = untracked_start_mode_store()
        .lock()
        .expect("serial number untracked start mode mutex poisoned");
    *slot = Some(mode);
}

fn take_untracked_start_mode() -> Option<SerialNumberCreationMode> {
    let mut slot = untracked_start_mode_store()
        .lock()
        .expect("serial number untracked start mode mutex poisoned");
    slot.take()
}

#[derive(Clone, Debug, PartialEq)]
struct SerialNumberCreationMode {
    base_diameter: f64,
    number: i64,
    font_size: f64,
    font_family: Option<String>,
}

impl SerialNumberCreationMode {
    fn from_data(data: &DomainSerialNumberData, base_diameter: f64) -> Self {
        Self {
            base_diameter,
            number: data.number,
            font_size: data.font_size,
            font_family: normalize_optional_trimmed_string(data.font_family.as_deref()),
        }
    }

    fn matches(&self, data: &DomainSerialNumberData) -> bool {
        self.number == data.number
            && self.font_size == data.font_size
            && self.font_family == normalize_optional_trimmed_string(data.font_family.as_deref())
    }
}
