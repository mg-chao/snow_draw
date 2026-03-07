#![allow(dead_code)]

use crate::draw::elements::core::element_data::ElementData;
use crate::draw::elements::types::arrow::arrow_binding::{
    ArrowBinding as LineArrowBinding, ArrowBindingMode as LineArrowBindingMode,
};
use crate::draw::elements::types::arrow::arrow_data::{ArrowBinding, ArrowBindingMode, ArrowData};
use crate::draw::elements::types::line::line_data::LineData;
use crate::draw::types::element_style::ArrowType;
use serde_json::Value;

/// Shared binding snapshot for connector-style payloads.
#[derive(Clone, Debug, Default, PartialEq)]
pub struct ConnectorBindingPair {
    pub start_binding: Option<ArrowBinding>,
    pub end_binding: Option<ArrowBinding>,
}

/// Lightweight connector metadata that tolerates partially-invalid payloads.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub struct ConnectorSummary {
    pub points_len: usize,
    pub arrow_type: ArrowType,
}

/// Decoded runtime connector payload.
#[derive(Clone, Debug, PartialEq)]
pub enum ConnectorPayload {
    Arrow(ArrowData),
    Line(LineData),
}

impl ConnectorPayload {
    /// Returns the normalized point count for this connector payload.
    pub fn points_len(&self) -> usize {
        match self {
            Self::Arrow(data) => data.points.len(),
            Self::Line(data) => data.points.len(),
        }
    }

    /// Returns the resolved connector arrow type.
    pub fn arrow_type(&self) -> ArrowType {
        match self {
            Self::Arrow(data) => data.arrow_type,
            Self::Line(data) => data.arrow_type,
        }
    }

    /// Returns the connector endpoint bindings normalized into a shared shape.
    pub fn binding_pair(&self) -> ConnectorBindingPair {
        match self {
            Self::Arrow(data) => ConnectorBindingPair {
                start_binding: data.start_binding.clone(),
                end_binding: data.end_binding.clone(),
            },
            Self::Line(data) => ConnectorBindingPair {
                start_binding: data.start_binding.as_ref().map(normalize_line_binding),
                end_binding: data.end_binding.as_ref().map(normalize_line_binding),
            },
        }
    }

    /// Returns the bound start target id when present.
    pub fn start_binding_element_id(&self) -> Option<String> {
        self.binding_pair()
            .start_binding
            .map(|binding| binding.element_id)
    }

    /// Returns the bound end target id when present.
    pub fn end_binding_element_id(&self) -> Option<String> {
        self.binding_pair()
            .end_binding
            .map(|binding| binding.element_id)
    }
}

/// Returns true when `type_id` belongs to a connector-style payload.
pub fn is_connector_type_id(type_id: &str) -> bool {
    matches!(type_id, ArrowData::TYPE_ID_TOKEN | LineData::TYPE_ID_TOKEN)
}

/// Decodes a runtime element payload into a connector snapshot when possible.
pub fn decode_connector_payload(data: &dyn ElementData) -> Option<ConnectorPayload> {
    match data.type_id().as_str() {
        ArrowData::TYPE_ID_TOKEN => ArrowData::from_json(&data.to_json())
            .ok()
            .map(ConnectorPayload::Arrow),
        LineData::TYPE_ID_TOKEN => LineData::from_json(&data.to_json())
            .ok()
            .map(ConnectorPayload::Line),
        _ => None,
    }
}

/// Reads connector summary fields directly from serialized data.
///
/// Unlike [`decode_connector_payload`], this accepts degenerate connector
/// payloads so selection/hit-test layers keep matching Dart behavior.
pub fn read_connector_summary(data: &dyn ElementData) -> Option<ConnectorSummary> {
    let type_id = data.type_id();
    let type_id = type_id.as_str();
    if !is_connector_type_id(type_id) {
        return None;
    }

    let payload = data.to_json_value();
    let json = payload.as_object()?;
    let points_len = json.get("points").and_then(Value::as_array)?.len();
    let arrow_type = if type_id == LineData::TYPE_ID_TOKEN {
        ArrowType::Curved
    } else {
        json.get("arrowType")
            .and_then(Value::as_str)
            .and_then(parse_arrow_type_name)
            .unwrap_or(ArrowType::Straight)
    };

    Some(ConnectorSummary {
        points_len,
        arrow_type,
    })
}

fn normalize_line_binding(binding: &LineArrowBinding) -> ArrowBinding {
    ArrowBinding::new(
        binding.element_id.clone(),
        binding.anchor,
        normalize_line_binding_mode(binding.mode),
    )
}

fn normalize_line_binding_mode(mode: LineArrowBindingMode) -> ArrowBindingMode {
    match mode {
        LineArrowBindingMode::Inside => ArrowBindingMode::Inside,
        LineArrowBindingMode::Orbit => ArrowBindingMode::Orbit,
        LineArrowBindingMode::Skip => ArrowBindingMode::Skip,
    }
}

fn parse_arrow_type_name(raw: &str) -> Option<ArrowType> {
    match raw {
        "straight" => Some(ArrowType::Straight),
        "curved" => Some(ArrowType::Curved),
        "elbow" => Some(ArrowType::Elbow),
        _ => None,
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    use crate::draw::elements::types::arrow::arrow_binding::{
        ArrowBinding as LineArrowBinding, ArrowBindingMode,
    };
    use crate::draw::elements::types::arrow::arrow_data::NullableField as ArrowNullableField;
    use crate::draw::elements::types::arrow::arrow_data::{ArrowData, ArrowDataPatch};
    use crate::draw::elements::types::arrow::arrow_like_data::NullableField;
    use crate::draw::elements::types::line::line_data::{LineData, LineDataPatch};
    use crate::draw::types::draw_point::DrawPoint;
    use crate::draw::types::element_style::ArrowType;

    #[test]
    fn decode_connector_payload_accepts_line_data() {
        let line = LineData::default().copy_with(LineDataPatch {
            start_binding: NullableField::Value(LineArrowBinding::new(
                "rect-start",
                DrawPoint::new(0.0, 0.5),
                ArrowBindingMode::Orbit,
            )),
            end_binding: NullableField::Value(LineArrowBinding::new(
                "rect-end",
                DrawPoint::new(1.0, 0.5),
                ArrowBindingMode::Inside,
            )),
            ..LineDataPatch::default()
        });

        let decoded = decode_connector_payload(&line).expect("line connector payload");
        assert_eq!(decoded.points_len(), 2);
        assert_eq!(decoded.arrow_type(), ArrowType::Curved);
        assert_eq!(
            decoded.start_binding_element_id().as_deref(),
            Some("rect-start")
        );
        assert_eq!(
            decoded.end_binding_element_id().as_deref(),
            Some("rect-end")
        );
    }

    #[test]
    fn read_connector_summary_accepts_degenerate_arrow_payload() {
        let arrow = ArrowData::default().copy_with(ArrowDataPatch {
            points: Some(vec![DrawPoint::new(0.5, 0.5)]),
            start_binding: ArrowNullableField::Unset,
            end_binding: ArrowNullableField::Unset,
            fixed_segments: ArrowNullableField::Unset,
            start_is_special: ArrowNullableField::Unset,
            end_is_special: ArrowNullableField::Unset,
            ..ArrowDataPatch::default()
        });

        let summary = read_connector_summary(&arrow).expect("degenerate connector summary");
        assert_eq!(summary.points_len, 1);
        assert_eq!(summary.arrow_type, ArrowType::Straight);
    }
}
