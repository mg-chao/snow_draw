use std::fmt;
use std::hash::{Hash, Hasher};
use std::marker::PhantomData;

use serde::{Deserialize, Serialize};
use serde_json::{Map, Value};

/// Strongly typed identifier for element types.
///
/// This mirrors Dart's `ElementTypeId<T>` wrapper while using Rust type
/// parameters for compile-time association.
#[derive(Serialize, Deserialize)]
pub struct ElementTypeId<T: ?Sized> {
    value: String,
    #[serde(skip)]
    marker: PhantomData<fn() -> T>,
}

impl<T: ?Sized> ElementTypeId<T> {
    /// Creates a new element type identifier.
    pub fn new(value: impl Into<String>) -> Self {
        Self {
            value: value.into(),
            marker: PhantomData,
        }
    }

    /// Returns the raw identifier value.
    pub fn as_str(&self) -> &str {
        &self.value
    }
}

impl<T: ?Sized> From<String> for ElementTypeId<T> {
    fn from(value: String) -> Self {
        Self::new(value)
    }
}

impl<T: ?Sized> From<&str> for ElementTypeId<T> {
    fn from(value: &str) -> Self {
        Self::new(value)
    }
}

impl<T: ?Sized> fmt::Display for ElementTypeId<T> {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        f.write_str(&self.value)
    }
}

impl<T: ?Sized> Clone for ElementTypeId<T> {
    fn clone(&self) -> Self {
        Self::new(self.value.clone())
    }
}

impl<T: ?Sized> fmt::Debug for ElementTypeId<T> {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        f.debug_tuple("ElementTypeId").field(&self.value).finish()
    }
}

impl<T: ?Sized> PartialEq for ElementTypeId<T> {
    fn eq(&self, other: &Self) -> bool {
        self.value == other.value
    }
}

impl<T: ?Sized> Eq for ElementTypeId<T> {}

impl<T: ?Sized> Hash for ElementTypeId<T> {
    fn hash<H: Hasher>(&self, state: &mut H) {
        self.value.hash(state);
    }
}

/// Object-safe trait object alias for element payloads.
pub type DynElementData = dyn ElementData;

/// Type-specific, immutable element payload.
///
/// Implementors should be immutable value types that can serialize themselves
/// into a JSON object.
pub trait ElementData: Send + Sync {
    /// Stable runtime identifier for this element type.
    fn type_id(&self) -> ElementTypeId<DynElementData>;

    /// Serializes the data payload.
    fn to_json(&self) -> Map<String, Value>;

    /// Serializes the data payload as a full JSON value.
    fn to_json_value(&self) -> Value {
        Value::Object(self.to_json())
    }
}
