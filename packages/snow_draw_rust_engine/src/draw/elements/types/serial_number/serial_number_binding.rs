#![allow(dead_code)]

use crate::draw::elements::core::element_data::ElementData as CoreElementData;
use crate::draw::elements::types::arrow::arrow_binding::ArrowBindingUtils;
use crate::draw::elements::types::serial_number::serial_number_data::SerialNumberData;
use crate::draw::elements::types::serial_number::serial_number_layout::resolve_serial_number_stroke_width;
use crate::draw::elements::types::text::text_data::TextData;
use crate::draw::elements::types::text::text_layout_constants::resolve_text_layout_horizontal_padding;
use crate::draw::models::element_state::ElementState;
use crate::draw::services::text::text_metrics_service::{
    FallbackTextMetricsService, TextLayoutRequest, TextMetricsService,
};
use crate::draw::types::draw_point::DrawPoint;
use crate::draw::types::draw_rect::DrawRect;
use crate::draw::utils::selection_calculator::SelectionCalculator;

const DEFAULT_TEXT_GAP: f64 = 18.0;
const GAP_STROKE_MULTIPLIER: f64 = 2.0;

/// Connection segment from a serial-number circle to its bound text.
#[derive(Clone, Copy, Debug, PartialEq)]
pub struct SerialNumberTextConnection {
    pub start: DrawPoint,
    pub end: DrawPoint,
    pub text_baseline_start: Option<DrawPoint>,
    pub text_baseline_end: Option<DrawPoint>,
}

/// Resolves the bound text rectangle placed to the right of a serial-number element.
///
/// Mirrors Dart `resolveSerialNumberBoundTextRect`.
pub fn resolve_serial_number_bound_text_rect(
    serial_element: &ElementState,
    serial_data: &SerialNumberData,
    text_data: &TextData,
    text_metrics_service: Option<&dyn TextMetricsService>,
    gap: Option<f64>,
) -> DrawRect {
    let fallback_service = FallbackTextMetricsService;
    let metrics_service = text_metrics_service.unwrap_or(&fallback_service);

    let layout = metrics_service.measure(&TextLayoutRequest::new(text_data, f64::INFINITY));
    let horizontal_padding = resolve_text_layout_horizontal_padding(layout.line_height);
    let width = layout.width + horizontal_padding * 2.0;
    let height = layout.height.max(layout.line_height);
    let stroke_width = resolve_serial_number_stroke_width(serial_data, 0.0);
    let resolved_gap =
        gap.unwrap_or_else(|| DEFAULT_TEXT_GAP.max(stroke_width * GAP_STROKE_MULTIPLIER));

    let rect = serial_element.rect;
    let min_x = rect.max_x + resolved_gap;
    let min_y = rect.center_y() - height / 2.0;

    DrawRect::new(min_x, min_y, min_x + width, min_y + height)
}

/// Resolves a leader line between a serial-number element and a text element.
///
/// Mirrors Dart `resolveSerialNumberTextConnection`.
pub fn resolve_serial_number_text_connection(
    serial_element: &ElementState,
    text_element: &ElementState,
    line_width: f64,
) -> Option<SerialNumberTextConnection> {
    if line_width <= 0.0 {
        return None;
    }

    let serial_rect = serial_element.rect;
    if serial_rect.width() <= 0.0 || serial_rect.height() <= 0.0 {
        return None;
    }

    let text_rect = SelectionCalculator::compute_element_world_aabb(text_element);
    if text_rect.width() <= 0.0 || text_rect.height() <= 0.0 {
        return None;
    }

    let attachment = resolve_text_attachment(serial_rect, text_rect);
    let center = serial_rect.center();
    let anchor = attachment.anchor;

    let dx = anchor.x - center.x;
    let dy = anchor.y - center.y;
    let distance = (dx * dx + dy * dy).sqrt();

    let radius = serial_rect.width().min(serial_rect.height()) / 2.0;
    let binding_gap = ArrowBindingUtils::resolve_binding_gap(serial_element);
    let start_offset = radius + binding_gap;
    let half_line_width = line_width / 2.0;
    if distance <= start_offset + half_line_width {
        return None;
    }

    let ux = dx / distance;
    let uy = dy / distance;
    let start = DrawPoint::new(center.x + ux * start_offset, center.y + uy * start_offset);
    let end = DrawPoint::new(
        anchor.x - ux * half_line_width,
        anchor.y - uy * half_line_width,
    );

    Some(SerialNumberTextConnection {
        start,
        end,
        text_baseline_start: attachment.text_baseline_start,
        text_baseline_end: attachment.text_baseline_end,
    })
}

#[derive(Clone, Copy, Debug, PartialEq)]
struct TextAttachment {
    anchor: DrawPoint,
    text_baseline_start: Option<DrawPoint>,
    text_baseline_end: Option<DrawPoint>,
}

fn resolve_text_attachment(serial_rect: DrawRect, text_rect: DrawRect) -> TextAttachment {
    let center_x = serial_rect.center_x();
    let is_above = text_rect.max_y < serial_rect.min_y;
    let is_below = text_rect.min_y > serial_rect.max_y;
    let centered_horizontally = center_x >= text_rect.min_x && center_x <= text_rect.max_x;

    if centered_horizontally {
        if is_above {
            return TextAttachment {
                anchor: DrawPoint::new(center_x, text_rect.max_y),
                text_baseline_start: None,
                text_baseline_end: None,
            };
        }
        if is_below {
            return TextAttachment {
                anchor: DrawPoint::new(center_x, text_rect.min_y),
                text_baseline_start: None,
                text_baseline_end: None,
            };
        }
    }

    let anchor_x = center_x.clamp(text_rect.min_x, text_rect.max_x);
    let baseline_y = text_rect.max_y;
    TextAttachment {
        anchor: DrawPoint::new(anchor_x, baseline_y),
        text_baseline_start: Some(DrawPoint::new(text_rect.min_x, baseline_y)),
        text_baseline_end: Some(DrawPoint::new(text_rect.max_x, baseline_y)),
    }
}

fn decode_text_data(data: &dyn CoreElementData) -> Option<TextData> {
    if data.type_id().as_str() != TextData::TYPE_ID_TOKEN {
        return None;
    }
    TextData::from_json(&data.to_json()).ok()
}

fn decode_serial_number_data(data: &dyn CoreElementData) -> Option<SerialNumberData> {
    if data.type_id().as_str() != SerialNumberData::TYPE_ID_TOKEN {
        return None;
    }
    SerialNumberData::from_json(&data.to_json()).ok()
}

#[cfg(test)]
mod tests {
    use super::{
        decode_serial_number_data, decode_text_data, resolve_serial_number_bound_text_rect,
        resolve_serial_number_text_connection,
    };
    use std::sync::Arc;

    use crate::draw::elements::types::serial_number::serial_number_data::SerialNumberData;
    use crate::draw::elements::types::text::text_data::{TextData, TextDataPatch};
    use crate::draw::models::element_state::ElementState;
    use crate::draw::services::text::text_metrics_service::FallbackTextMetricsService;
    use crate::draw::types::draw_rect::DrawRect;

    fn approx_eq(a: f64, b: f64) -> bool {
        (a - b).abs() < 1e-6
    }

    fn serial_element(id: &str, rect: DrawRect) -> ElementState {
        ElementState::new(id, rect, 0.0, 1.0, 0, Arc::new(SerialNumberData::default()))
    }

    fn text_element(id: &str, rect: DrawRect) -> ElementState {
        let data = TextData::default().copy_with(TextDataPatch {
            text: Some("text".to_string()),
            ..TextDataPatch::default()
        });
        ElementState::new(id, rect, 0.0, 1.0, 1, Arc::new(data))
    }

    #[test]
    fn resolves_bound_text_rect_to_the_right_with_default_gap() {
        let serial_element = serial_element("s1", DrawRect::new(0.0, 0.0, 20.0, 20.0));
        let serial_data =
            decode_serial_number_data(serial_element.data.as_ref()).expect("serial data");
        let text_data = TextData::default().copy_with(TextDataPatch {
            text: Some("12".to_string()),
            font_size: Some(16.0),
            ..TextDataPatch::default()
        });
        let metrics = FallbackTextMetricsService;

        let rect = resolve_serial_number_bound_text_rect(
            &serial_element,
            &serial_data,
            &text_data,
            Some(&metrics),
            None,
        );

        assert!(approx_eq(rect.min_x, 38.0));
        assert!(approx_eq(rect.min_y, 0.4));
        assert!(rect.width() > 0.0);
        assert!(rect.height() > 0.0);
    }

    #[test]
    fn resolves_text_connection_with_baseline_for_side_attachment() {
        let serial_element = serial_element("serial", DrawRect::new(0.0, 0.0, 20.0, 20.0));
        let text_element = text_element("text", DrawRect::new(30.0, 0.0, 50.0, 20.0));

        let connection = resolve_serial_number_text_connection(&serial_element, &text_element, 2.0)
            .expect("connection");
        assert!(connection.text_baseline_start.is_some());
        assert!(connection.text_baseline_end.is_some());
        assert!(connection.start.x < connection.end.x);
    }

    #[test]
    fn resolves_text_connection_without_baseline_for_above_attachment() {
        let serial_element = serial_element("serial", DrawRect::new(0.0, 0.0, 20.0, 20.0));
        let text_element = text_element("text", DrawRect::new(5.0, -35.0, 15.0, -25.0));

        let connection = resolve_serial_number_text_connection(&serial_element, &text_element, 2.0)
            .expect("connection");
        assert!(connection.text_baseline_start.is_none());
        assert!(connection.text_baseline_end.is_none());
    }

    #[test]
    fn decode_helpers_match_runtime_type_ids() {
        let text = text_element("text", DrawRect::new(0.0, 0.0, 10.0, 10.0));
        let serial = serial_element("serial", DrawRect::new(0.0, 0.0, 10.0, 10.0));

        assert!(decode_text_data(text.data.as_ref()).is_some());
        assert!(decode_serial_number_data(serial.data.as_ref()).is_some());
        assert!(decode_text_data(serial.data.as_ref()).is_none());
        assert!(decode_serial_number_data(text.data.as_ref()).is_none());
    }
}
