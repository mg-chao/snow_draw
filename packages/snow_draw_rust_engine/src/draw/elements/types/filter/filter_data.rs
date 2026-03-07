#![allow(dead_code)]

use crate::draw::config::draw_config::{ConfigDefaults, ElementStyleConfig};
use crate::draw::elements::core::element_data::{DynElementData, ElementData, ElementTypeId};
use crate::draw::elements::core::element_style_configurable_data::ElementStyleConfigurableData;
use crate::draw::elements::core::element_style_updatable_data::ElementStyleUpdatableData;
use crate::draw::types::element_style::{CanvasFilterType, ElementStyleUpdate};
use serde_json::{Map, Value};
use thiserror::Error;

/// Immutable filter payload translated from Dart `FilterData`.
#[derive(Clone, Debug, PartialEq)]
pub struct FilterData {
    pub filter_type: CanvasFilterType,
    pub strength: f64,
}

/// Patch payload for [`FilterData::copy_with`].
#[derive(Clone, Debug, Default, PartialEq)]
pub struct FilterDataPatch {
    pub filter_type: Option<CanvasFilterType>,
    pub strength: Option<f64>,
}

impl FilterData {
    pub const TYPE_ID_TOKEN: &'static str = "filter";

    /// Creates a new filter payload and normalizes strength to `[0, 1]`.
    ///
    /// Mirrors Dart behavior:
    /// - `NaN` becomes `1.0`
    /// - values `<= 0` become `0.0`
    /// - values `>= 1` become `1.0`
    pub fn new(filter_type: CanvasFilterType, strength: f64) -> Self {
        Self {
            filter_type,
            strength: clamp_strength(strength),
        }
    }

    /// Decodes `FilterData` from JSON.
    pub fn from_json(json: &Map<String, Value>) -> Result<Self, FilterDataDecodeError> {
        Ok(Self::new(
            decode_required_filter_type(json, "type")?,
            decode_required_f64(json, "strength")?,
        ))
    }

    /// Decodes `FilterData` from a JSON value.
    pub fn from_json_value(value: &Value) -> Result<Self, FilterDataDecodeError> {
        let json = value.as_object().ok_or_else(|| {
            FilterDataDecodeError::invalid_field("filter", "expected JSON object payload")
        })?;
        Self::from_json(json)
    }

    /// Returns the strongly typed element id token for filter payloads.
    pub fn type_id_token() -> ElementTypeId<FilterData> {
        ElementTypeId::new(Self::TYPE_ID_TOKEN)
    }

    /// Returns an updated payload while preserving immutability.
    pub fn copy_with(&self, patch: FilterDataPatch) -> Self {
        Self::new(
            patch.filter_type.unwrap_or(self.filter_type),
            patch.strength.unwrap_or(self.strength),
        )
    }

    /// Serializes this payload to JSON.
    pub fn to_json_map(&self) -> Map<String, Value> {
        let mut json = Map::new();
        json.insert(
            "typeId".to_string(),
            Value::String(Self::TYPE_ID_TOKEN.to_string()),
        );
        json.insert(
            "type".to_string(),
            Value::String(filter_type_to_name(self.filter_type).to_string()),
        );
        json.insert("strength".to_string(), Value::from(self.strength));
        json
    }
}

impl Default for FilterData {
    fn default() -> Self {
        Self::new(
            ConfigDefaults::DEFAULT_FILTER_TYPE,
            ConfigDefaults::DEFAULT_FILTER_STRENGTH,
        )
    }
}

impl ElementData for FilterData {
    fn type_id(&self) -> ElementTypeId<DynElementData> {
        ElementTypeId::new(Self::TYPE_ID_TOKEN)
    }

    fn to_json(&self) -> Map<String, Value> {
        self.to_json_map()
    }
}

impl ElementStyleConfigurableData for FilterData {
    fn with_element_style(&self, style: ElementStyleConfig) -> Box<DynElementData> {
        Box::new(self.copy_with(FilterDataPatch {
            filter_type: Some(style.filter_type),
            strength: Some(style.filter_strength),
        }))
    }
}

impl ElementStyleUpdatableData for FilterData {
    fn with_style_update(&self, update: ElementStyleUpdate) -> Box<DynElementData> {
        Box::new(self.copy_with(FilterDataPatch {
            filter_type: update.filter_type,
            strength: update.filter_strength,
        }))
    }
}

/// Decode failures for `FilterData` JSON payloads.
#[derive(Debug, Error)]
#[error("{message}")]
pub struct FilterDataDecodeError {
    message: String,
}

impl FilterDataDecodeError {
    fn invalid_field(field: &str, detail: &str) -> Self {
        Self {
            message: format!("Invalid `{field}`: {detail}"),
        }
    }
}

fn clamp_strength(strength: f64) -> f64 {
    if strength.is_nan() {
        1.0
    } else if strength <= 0.0 {
        0.0
    } else if strength >= 1.0 {
        1.0
    } else {
        strength
    }
}

fn decode_required_filter_type(
    json: &Map<String, Value>,
    field: &str,
) -> Result<CanvasFilterType, FilterDataDecodeError> {
    let raw = decode_required_string(json, field)?;
    filter_type_from_name(&raw)
        .ok_or_else(|| FilterDataDecodeError::invalid_field(field, "unsupported filter type value"))
}

fn decode_required_f64(
    json: &Map<String, Value>,
    field: &str,
) -> Result<f64, FilterDataDecodeError> {
    let value = json
        .get(field)
        .ok_or_else(|| FilterDataDecodeError::invalid_field(field, "field is missing"))?;
    value
        .as_f64()
        .ok_or_else(|| FilterDataDecodeError::invalid_field(field, "expected numeric value"))
}

fn decode_required_string(
    json: &Map<String, Value>,
    field: &str,
) -> Result<String, FilterDataDecodeError> {
    let value = json
        .get(field)
        .ok_or_else(|| FilterDataDecodeError::invalid_field(field, "field is missing"))?;
    value
        .as_str()
        .map(str::to_owned)
        .ok_or_else(|| FilterDataDecodeError::invalid_field(field, "expected string value"))
}

fn filter_type_to_name(filter_type: CanvasFilterType) -> &'static str {
    match filter_type {
        CanvasFilterType::Mosaic => "mosaic",
        CanvasFilterType::GaussianBlur => "gaussianBlur",
        CanvasFilterType::Grayscale => "grayscale",
        CanvasFilterType::Inversion => "inversion",
    }
}

fn filter_type_from_name(raw: &str) -> Option<CanvasFilterType> {
    match raw {
        "mosaic" => Some(CanvasFilterType::Mosaic),
        "gaussianBlur" => Some(CanvasFilterType::GaussianBlur),
        "grayscale" => Some(CanvasFilterType::Grayscale),
        "inversion" => Some(CanvasFilterType::Inversion),
        _ => None,
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn constructor_clamps_strength_like_dart() {
        assert_eq!(
            FilterData::new(CanvasFilterType::Mosaic, f64::NAN).strength,
            1.0
        );
        assert_eq!(
            FilterData::new(CanvasFilterType::Mosaic, -1.0).strength,
            0.0
        );
        assert_eq!(FilterData::new(CanvasFilterType::Mosaic, 2.0).strength, 1.0);
    }

    #[test]
    fn to_json_uses_dart_enum_names() {
        let data = FilterData::new(CanvasFilterType::GaussianBlur, 0.75);
        let json = data.to_json_map();

        assert_eq!(
            json.get("typeId"),
            Some(&Value::String("filter".to_string()))
        );
        assert_eq!(
            json.get("type"),
            Some(&Value::String("gaussianBlur".to_string()))
        );
        assert_eq!(json.get("strength"), Some(&Value::from(0.75)));
    }

    #[test]
    fn from_json_decodes_type_and_strength() {
        let mut json = Map::new();
        json.insert("type".to_string(), Value::String("inversion".to_string()));
        json.insert("strength".to_string(), Value::from(0.4));

        let data = FilterData::from_json(&json).expect("filter data should decode");
        assert_eq!(data.filter_type, CanvasFilterType::Inversion);
        assert_eq!(data.strength, 0.4);
    }
}
