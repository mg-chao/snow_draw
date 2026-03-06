#![allow(dead_code)]

use std::error::Error;
use std::fmt;

use crate::draw::types::draw_point::DrawPoint;
use serde_json::{Map, Value};

/// Decode failures for [`ElementDataCodec`] JSON helpers.
#[derive(Clone, Debug, PartialEq, Eq)]
pub struct ElementDataCodecError {
    message: String,
}

impl ElementDataCodecError {
    pub(crate) fn new(message: impl Into<String>) -> Self {
        Self {
            message: message.into(),
        }
    }
}

impl fmt::Display for ElementDataCodecError {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        f.write_str(&self.message)
    }
}

impl Error for ElementDataCodecError {}

/// Shared decode helpers for element JSON payloads.
pub struct ElementDataCodec;

impl ElementDataCodec {
    /// Decodes an enum by matching a JSON string against known variant names.
    ///
    /// `values` contains all enum variants and `name_of` returns each variant's
    /// wire/json name.
    pub fn decode_enum_by_name<T, F>(
        values: &[T],
        raw: &Value,
        field_name: Option<&str>,
        name_of: F,
    ) -> Result<T, ElementDataCodecError>
    where
        T: Copy,
        F: Fn(&T) -> &str,
    {
        let raw_name = raw.as_str().ok_or_else(|| {
            ElementDataCodecError::new(format!(
                "Expected a string enum value for {}",
                field_label(field_name)
            ))
        })?;

        for value in values {
            if name_of(value) == raw_name {
                return Ok(*value);
            }
        }

        Err(ElementDataCodecError::new(format!(
            "Unsupported enum value \"{raw_name}\" for {}",
            field_label(field_name)
        )))
    }

    /// Reads a JSON object from `raw`.
    pub fn as_json_map<'a>(
        raw: &'a Value,
        field_name: Option<&str>,
    ) -> Result<&'a Map<String, Value>, ElementDataCodecError> {
        raw.as_object().ok_or_else(|| {
            ElementDataCodecError::new(format!(
                "Expected a JSON map for {}",
                field_label(field_name)
            ))
        })
    }

    /// Reads a nullable JSON object from `raw`.
    pub fn as_nullable_json_map<'a>(
        raw: Option<&'a Value>,
        field_name: Option<&str>,
    ) -> Result<Option<&'a Map<String, Value>>, ElementDataCodecError> {
        let Some(raw) = raw else {
            return Ok(None);
        };
        if raw.is_null() {
            return Ok(None);
        }

        Self::as_json_map(raw, field_name).map(Some)
    }

    /// Decodes a nullable boolean field.
    pub fn decode_nullable_bool(
        raw: Option<&Value>,
        field_name: &str,
    ) -> Result<Option<bool>, ElementDataCodecError> {
        let Some(raw) = raw else {
            return Ok(None);
        };
        if raw.is_null() {
            return Ok(None);
        }

        let value = raw
            .as_bool()
            .ok_or_else(|| ElementDataCodecError::new(format!("Expected bool for {field_name}")))?;
        Ok(Some(value))
    }

    /// Decodes a required string field.
    pub fn decode_string(raw: &Value, field_name: &str) -> Result<String, ElementDataCodecError> {
        raw.as_str()
            .map(str::to_owned)
            .ok_or_else(|| ElementDataCodecError::new(format!("Expected string for {field_name}")))
    }

    /// Decodes a nullable string field.
    pub fn decode_nullable_string(
        raw: Option<&Value>,
        field_name: &str,
    ) -> Result<Option<String>, ElementDataCodecError> {
        let Some(raw) = raw else {
            return Ok(None);
        };
        if raw.is_null() {
            return Ok(None);
        }

        Self::decode_string(raw, field_name).map(Some)
    }

    /// Decodes a required bool field.
    pub fn decode_bool(raw: &Value, field_name: &str) -> Result<bool, ElementDataCodecError> {
        raw.as_bool()
            .ok_or_else(|| ElementDataCodecError::new(format!("Expected bool for {field_name}")))
    }

    /// Decodes a required numeric field.
    pub fn decode_double(raw: &Value, field_name: &str) -> Result<f64, ElementDataCodecError> {
        raw.as_f64().ok_or_else(|| {
            ElementDataCodecError::new(format!("Expected numeric value for {field_name}"))
        })
    }

    /// Decodes a required integer field.
    pub fn decode_int(raw: &Value, field_name: &str) -> Result<i64, ElementDataCodecError> {
        if let Some(value) = raw.as_i64() {
            return Ok(value);
        }

        if let Some(value) = raw.as_u64() {
            return i64::try_from(value).map_err(|_| {
                ElementDataCodecError::new(format!("Expected integer value for {field_name}"))
            });
        }

        Err(ElementDataCodecError::new(format!(
            "Expected integer value for {field_name}"
        )))
    }

    /// Decodes a required point payload with optional pressure support.
    pub fn decode_point(
        raw: &Value,
        field_name: &str,
        allow_pressure: bool,
        pressure_field_name: Option<&str>,
    ) -> Result<DrawPoint, ElementDataCodecError> {
        let point_map = Self::as_json_map(raw, Some(field_name))?;

        let x = point_map.get("x").and_then(Value::as_f64);
        let y = point_map.get("y").and_then(Value::as_f64);
        let (Some(x), Some(y)) = (x, y) else {
            return Err(ElementDataCodecError::new(format!(
                "{field_name} must provide numeric x/y"
            )));
        };

        if !allow_pressure {
            return Ok(DrawPoint::new(x, y));
        }

        let pressure_key = pressure_field_name.unwrap_or("p");
        let pressure_value = point_map.get(pressure_key);
        if let Some(raw_pressure) = pressure_value {
            if !raw_pressure.is_null() && raw_pressure.as_f64().is_none() {
                return Err(ElementDataCodecError::new(format!(
                    "{field_name} {pressure_key} must be numeric when provided"
                )));
            }
        }

        let pressure = pressure_value.and_then(Value::as_f64).unwrap_or(0.0);
        Ok(DrawPoint::with_pressure_and_timestamp(x, y, pressure, 0))
    }
}

fn field_label(field_name: Option<&str>) -> &str {
    field_name.unwrap_or("field")
}
