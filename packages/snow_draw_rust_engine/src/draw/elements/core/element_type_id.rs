use core::fmt;
use core::marker::PhantomData;

/// Strongly typed identifier for element types.
///
/// This mirrors Dart's `ElementTypeId<T>` wrapper by coupling a runtime string
/// value with a compile-time marker type.
#[derive(Clone, Debug, Hash)]
pub struct ElementTypeId<T: ?Sized> {
    value: String,
    marker: PhantomData<fn() -> T>,
}

impl<T: ?Sized> ElementTypeId<T> {
    /// Creates a new element type identifier from a string-like value.
    pub fn new(value: impl Into<String>) -> Self {
        Self {
            value: value.into(),
            marker: PhantomData,
        }
    }

    /// Returns the raw string identifier.
    pub fn as_str(&self) -> &str {
        &self.value
    }

    /// Consumes this identifier and returns the underlying string.
    pub fn into_inner(self) -> String {
        self.value
    }
}

impl<T: ?Sized> Eq for ElementTypeId<T> {}

impl<T: ?Sized, U: ?Sized> PartialEq<ElementTypeId<U>> for ElementTypeId<T> {
    fn eq(&self, other: &ElementTypeId<U>) -> bool {
        self.value == other.value
    }
}

impl<T: ?Sized> fmt::Display for ElementTypeId<T> {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        f.write_str(&self.value)
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
