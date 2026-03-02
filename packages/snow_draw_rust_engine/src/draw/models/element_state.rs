#![allow(dead_code)]

use std::fmt;
use std::hash::{Hash, Hasher};
use std::sync::Arc;

use serde_json::Value;

use crate::draw::config::draw_config::ElementConfig;
use crate::draw::elements::core::element_data::{DynElementData, ElementData, ElementTypeId};
use crate::draw::types::draw_point::DrawPoint;
use crate::draw::types::draw_rect::DrawRect;

/// Element state (fully immutable-style value object).
#[derive(Clone)]
pub struct ElementState {
    pub id: String,
    pub rect: DrawRect,
    pub rotation: f64,
    pub opacity: f64,
    pub z_index: i64,
    pub data: Arc<dyn ElementData>,
}

impl ElementState {
    /// Creates an element state with explicit fields.
    pub fn new(
        id: impl Into<String>,
        rect: DrawRect,
        rotation: f64,
        opacity: f64,
        z_index: i64,
        data: Arc<dyn ElementData>,
    ) -> Self {
        Self {
            id: id.into(),
            rect,
            rotation,
            opacity,
            z_index,
            data,
        }
    }

    /// Returns this element's runtime type identifier.
    pub fn type_id(&self) -> ElementTypeId<DynElementData> {
        self.data.type_id()
    }

    /// Returns a copied state with selected fields replaced.
    pub fn copy_with(
        &self,
        id: Option<String>,
        rect: Option<DrawRect>,
        rotation: Option<f64>,
        opacity: Option<f64>,
        z_index: Option<i64>,
        data: Option<Arc<dyn ElementData>>,
    ) -> Self {
        Self {
            id: id.unwrap_or_else(|| self.id.clone()),
            rect: rect.unwrap_or(self.rect),
            rotation: rotation.unwrap_or(self.rotation),
            opacity: opacity.unwrap_or(self.opacity),
            z_index: z_index.unwrap_or(self.z_index),
            data: data.unwrap_or_else(|| Arc::clone(&self.data)),
        }
    }

    /// Returns a copied state translated by `(dx, dy)`.
    pub fn moved_by(&self, dx: f64, dy: f64) -> Self {
        self.copy_with(
            None,
            Some(self.rect.translate(DrawPoint::new(dx, dy))),
            None,
            None,
            None,
            None,
        )
    }

    /// Returns the center point of [`Self::rect`].
    pub fn center(&self) -> DrawPoint {
        self.rect.center()
    }

    /// Returns whether this element satisfies validity constraints.
    pub fn is_valid_with(&self, config: &ElementConfig) -> bool {
        self.rect.width() >= config.min_valid_size && self.rect.height() >= config.min_valid_size
    }

    /// Returns whether this element is valid with default configuration.
    pub fn is_valid(&self) -> bool {
        self.is_valid_with(&ElementConfig::default())
    }
}

impl PartialEq for ElementState {
    fn eq(&self, other: &Self) -> bool {
        self.id == other.id
            && self.rect == other.rect
            && self.rotation == other.rotation
            && self.opacity == other.opacity
            && self.z_index == other.z_index
            && element_data_eq(self.data.as_ref(), other.data.as_ref())
    }
}

impl Hash for ElementState {
    fn hash<H: Hasher>(&self, state: &mut H) {
        self.id.hash(state);
        self.rect.min_x.to_bits().hash(state);
        self.rect.min_y.to_bits().hash(state);
        self.rect.max_x.to_bits().hash(state);
        self.rect.max_y.to_bits().hash(state);
        self.rotation.to_bits().hash(state);
        self.opacity.to_bits().hash(state);
        self.z_index.hash(state);
        hash_element_data(self.data.as_ref(), state);
    }
}

impl fmt::Debug for ElementState {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        let type_id = self.type_id();
        f.debug_struct("ElementState")
            .field("id", &self.id)
            .field("rect", &self.rect)
            .field("rotation", &self.rotation)
            .field("opacity", &self.opacity)
            .field("z_index", &self.z_index)
            .field("type_id", &type_id.as_str())
            .finish()
    }
}

impl fmt::Display for ElementState {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        write!(
            f,
            "ElementState(id: {}, rect: {}, rotation: {}, opacity: {}, zIndex: {}, typeId: {})",
            self.id,
            self.rect,
            self.rotation,
            self.opacity,
            self.z_index,
            self.type_id()
        )
    }
}

fn element_data_eq(lhs: &dyn ElementData, rhs: &dyn ElementData) -> bool {
    let lhs_type = lhs.type_id();
    let rhs_type = rhs.type_id();
    lhs_type.as_str() == rhs_type.as_str()
        && json_values_equal(&lhs.to_json_value(), &rhs.to_json_value())
}

fn hash_element_data<H: Hasher>(data: &dyn ElementData, state: &mut H) {
    data.type_id().as_str().hash(state);
    hash_json_value(&data.to_json_value(), state);
}

fn hash_json_value<H: Hasher>(value: &Value, state: &mut H) {
    match value {
        Value::Null => 0_u8.hash(state),
        Value::Bool(v) => {
            1_u8.hash(state);
            v.hash(state);
        }
        Value::Number(v) => {
            2_u8.hash(state);
            if let Some(i) = v.as_i64() {
                0_u8.hash(state);
                i.hash(state);
            } else if let Some(u) = v.as_u64() {
                1_u8.hash(state);
                u.hash(state);
            } else if let Some(f) = v.as_f64() {
                2_u8.hash(state);
                f.to_bits().hash(state);
            } else {
                v.to_string().hash(state);
            }
        }
        Value::String(v) => {
            3_u8.hash(state);
            v.hash(state);
        }
        Value::Array(values) => {
            4_u8.hash(state);
            values.len().hash(state);
            for entry in values {
                hash_json_value(entry, state);
            }
        }
        Value::Object(values) => {
            5_u8.hash(state);
            values.len().hash(state);

            let mut entries = values.iter().collect::<Vec<_>>();
            entries.sort_unstable_by(|(left_key, _), (right_key, _)| left_key.cmp(right_key));

            for (key, entry) in entries {
                key.hash(state);
                hash_json_value(entry, state);
            }
        }
    }
}

fn json_values_equal(lhs: &Value, rhs: &Value) -> bool {
    match (lhs, rhs) {
        (Value::Null, Value::Null) => true,
        (Value::Bool(left), Value::Bool(right)) => left == right,
        (Value::Number(left), Value::Number(right)) => left == right,
        (Value::String(left), Value::String(right)) => left == right,
        (Value::Array(left), Value::Array(right)) => {
            left.len() == right.len()
                && left
                    .iter()
                    .zip(right.iter())
                    .all(|(left_value, right_value)| json_values_equal(left_value, right_value))
        }
        (Value::Object(left), Value::Object(right)) => {
            left.len() == right.len()
                && left.iter().all(|(key, left_value)| {
                    right
                        .get(key)
                        .is_some_and(|right_value| json_values_equal(left_value, right_value))
                })
        }
        _ => false,
    }
}
