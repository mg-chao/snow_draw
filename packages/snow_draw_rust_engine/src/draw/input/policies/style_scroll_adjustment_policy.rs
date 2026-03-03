#![allow(dead_code)]

use crate::draw::elements::core::element_data::ElementData as CoreElementData;
use crate::draw::elements::types::arrow::arrow_data::ArrowData;
use crate::draw::elements::types::free_draw::free_draw_data::FreeDrawData;
use crate::draw::elements::types::line::line_data::LineData;
use crate::draw::elements::types::rectangle::rectangle_data::RectangleData;
use crate::draw::elements::types::serial_number::serial_number_data::SerialNumberData;
use crate::draw::elements::types::text::text_data::TextData;
use crate::draw::models::draw_state::DrawState;

const STEP_EPSILON: f64 = 0.01;

/// Returns the next stepped value from `steps` based on `current_value`.
///
/// When `decrease` is true, this walks the steps in reverse and finds the
/// closest step strictly below `current_value - STEP_EPSILON`. Otherwise it
/// finds the closest step strictly above `current_value + STEP_EPSILON`.
pub fn resolve_next_stepped_value(current_value: f64, steps: &[f64], decrease: bool) -> f64 {
    if steps.is_empty() {
        return current_value;
    }

    let threshold = if decrease {
        current_value - STEP_EPSILON
    } else {
        current_value + STEP_EPSILON
    };

    if decrease {
        for step in steps.iter().rev() {
            if *step < threshold {
                return *step;
            }
        }
        return steps[0];
    }

    for step in steps {
        if *step > threshold {
            return *step;
        }
    }

    steps[steps.len() - 1]
}

/// Minimal state capabilities required by style scroll adjustment policies.
///
/// This mirrors the Dart logic that iterates selected ids and resolves each
/// element payload by id.
pub trait StyleScrollAdjustmentState {
    fn selected_ids<'a>(&'a self) -> Box<dyn Iterator<Item = &'a str> + 'a>;

    fn get_element_data<'a>(&'a self, id: &str) -> Option<&'a dyn CoreElementData>;
}

impl StyleScrollAdjustmentState for DrawState {
    fn selected_ids<'a>(&'a self) -> Box<dyn Iterator<Item = &'a str> + 'a> {
        Box::new(
            self.domain
                .selection
                .selected_ids
                .iter()
                .map(String::as_str),
        )
    }

    fn get_element_data<'a>(&'a self, id: &str) -> Option<&'a dyn CoreElementData> {
        self.domain
            .document
            .get_element_by_id(id)
            .map(|element| element.data.as_ref())
    }
}

/// Resolves the average selected metric computed by `metric_resolver`.
pub fn resolve_average_selected_metric<S, F>(state: &S, metric_resolver: F) -> Option<f64>
where
    S: StyleScrollAdjustmentState,
    F: Fn(&dyn CoreElementData) -> Option<f64>,
{
    let mut count = 0_usize;
    let mut total = 0.0_f64;

    for id in state.selected_ids() {
        let Some(data) = state.get_element_data(id) else {
            continue;
        };

        let Some(metric) = metric_resolver(data) else {
            continue;
        };

        total += metric;
        count += 1;
    }

    if count == 0 {
        None
    } else {
        Some(total / count as f64)
    }
}

pub fn resolve_average_selected_rectangle_stroke_width<S>(state: &S) -> Option<f64>
where
    S: StyleScrollAdjustmentState,
{
    resolve_average_selected_metric(state, resolve_rectangle_stroke_width_metric)
}

pub fn resolve_average_selected_arrow_stroke_width<S>(state: &S) -> Option<f64>
where
    S: StyleScrollAdjustmentState,
{
    resolve_average_selected_metric(state, resolve_arrow_stroke_width_metric)
}

pub fn resolve_average_selected_line_stroke_width<S>(state: &S) -> Option<f64>
where
    S: StyleScrollAdjustmentState,
{
    resolve_average_selected_metric(state, resolve_line_stroke_width_metric)
}

pub fn resolve_average_selected_free_draw_stroke_width<S>(state: &S) -> Option<f64>
where
    S: StyleScrollAdjustmentState,
{
    resolve_average_selected_metric(state, resolve_free_draw_stroke_width_metric)
}

pub fn resolve_average_selected_font_size<S>(state: &S) -> Option<f64>
where
    S: StyleScrollAdjustmentState,
{
    resolve_average_selected_metric(state, resolve_font_size_metric)
}

fn resolve_rectangle_stroke_width_metric(data: &dyn CoreElementData) -> Option<f64> {
    if data.type_id().as_str() != RectangleData::TYPE_ID_TOKEN {
        return None;
    }
    RectangleData::from_json_value(&data.to_json_value())
        .ok()
        .map(|decoded| decoded.stroke_width)
}

fn resolve_arrow_stroke_width_metric(data: &dyn CoreElementData) -> Option<f64> {
    if data.type_id().as_str() != ArrowData::TYPE_ID_TOKEN {
        return None;
    }
    ArrowData::from_json_value(&data.to_json_value())
        .ok()
        .map(|decoded| decoded.stroke_width)
}

fn resolve_line_stroke_width_metric(data: &dyn CoreElementData) -> Option<f64> {
    if data.type_id().as_str() != LineData::TYPE_ID_TOKEN {
        return None;
    }
    LineData::from_json_value(&data.to_json_value())
        .ok()
        .map(|decoded| decoded.stroke_width)
}

fn resolve_free_draw_stroke_width_metric(data: &dyn CoreElementData) -> Option<f64> {
    if data.type_id().as_str() != FreeDrawData::TYPE_ID_TOKEN {
        return None;
    }
    FreeDrawData::from_json_value(&data.to_json_value())
        .ok()
        .map(|decoded| decoded.stroke_width)
}

fn resolve_font_size_metric(data: &dyn CoreElementData) -> Option<f64> {
    if data.type_id().as_str() == TextData::TYPE_ID_TOKEN {
        return TextData::from_json_value(&data.to_json_value())
            .ok()
            .map(|decoded| decoded.font_size);
    }

    if data.type_id().as_str() == SerialNumberData::TYPE_ID_TOKEN {
        return SerialNumberData::from_json_value(&data.to_json_value())
            .ok()
            .map(|decoded| decoded.font_size);
    }

    None
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::collections::HashMap;

    #[derive(Default)]
    struct TestState {
        selected_ids: Vec<String>,
        elements_by_id: HashMap<String, Box<dyn CoreElementData>>,
    }

    impl TestState {
        fn with_selected_ids(mut self, ids: &[&str]) -> Self {
            self.selected_ids = ids.iter().map(|id| (*id).to_string()).collect();
            self
        }

        fn with_element(mut self, id: &str, data: impl CoreElementData + 'static) -> Self {
            self.elements_by_id.insert(id.to_string(), Box::new(data));
            self
        }
    }

    impl StyleScrollAdjustmentState for TestState {
        fn selected_ids<'a>(&'a self) -> Box<dyn Iterator<Item = &'a str> + 'a> {
            Box::new(self.selected_ids.iter().map(String::as_str))
        }

        fn get_element_data<'a>(&'a self, id: &str) -> Option<&'a dyn CoreElementData> {
            self.elements_by_id.get(id).map(|value| value.as_ref())
        }
    }

    #[test]
    fn next_stepped_value_returns_current_when_steps_are_empty() {
        assert_eq!(resolve_next_stepped_value(3.0, &[], false), 3.0);
        assert_eq!(resolve_next_stepped_value(3.0, &[], true), 3.0);
    }

    #[test]
    fn next_stepped_value_moves_up_or_down_with_epsilon() {
        let steps = [1.0, 2.0, 3.0, 4.0];

        assert_eq!(resolve_next_stepped_value(2.0, &steps, false), 3.0);
        assert_eq!(resolve_next_stepped_value(2.0, &steps, true), 1.0);

        assert_eq!(resolve_next_stepped_value(4.0, &steps, false), 4.0);
        assert_eq!(resolve_next_stepped_value(1.0, &steps, true), 1.0);
    }

    #[test]
    fn resolves_type_specific_selected_average_metric() {
        let state = TestState::default()
            .with_selected_ids(&["r1", "r2", "t1", "missing"])
            .with_element(
                "r1",
                RectangleData {
                    stroke_width: 2.0,
                    ..RectangleData::default()
                },
            )
            .with_element(
                "r2",
                RectangleData {
                    stroke_width: 4.0,
                    ..RectangleData::default()
                },
            )
            .with_element(
                "t1",
                TextData {
                    font_size: 24.0,
                    ..TextData::default()
                },
            );

        assert_eq!(
            resolve_average_selected_rectangle_stroke_width(&state),
            Some(3.0)
        );
        assert_eq!(resolve_average_selected_font_size(&state), Some(24.0));
    }

    #[test]
    fn returns_none_when_no_selected_metric_is_available() {
        let state = TestState::default()
            .with_selected_ids(&["text"])
            .with_element("text", TextData::default());

        assert_eq!(resolve_average_selected_arrow_stroke_width(&state), None);
    }
}
