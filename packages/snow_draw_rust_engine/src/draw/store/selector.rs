#![allow(dead_code)]

use std::sync::Arc;

use crate::draw::store::draw_store_interface::EqualityFn;

pub use crate::draw::store::draw_store_interface::StateSelector;

/// Simple functional state selector.
///
/// Uses a selector function to derive a state slice and an optional custom
/// equality function for change detection.
#[derive(Clone)]
pub struct SimpleSelector<S, T> {
    selector: Arc<dyn Fn(&S) -> T + Send + Sync + 'static>,
    equals: Option<EqualityFn<T>>,
}

impl<S, T> SimpleSelector<S, T> {
    /// Creates a selector that falls back to `PartialEq` for equality.
    pub fn new(selector: impl Fn(&S) -> T + Send + Sync + 'static) -> Self {
        Self {
            selector: Arc::new(selector),
            equals: None,
        }
    }

    /// Creates a selector with a custom equality comparator.
    pub fn with_equals(
        selector: impl Fn(&S) -> T + Send + Sync + 'static,
        equals: impl Fn(&T, &T) -> bool + Send + Sync + 'static,
    ) -> Self {
        Self {
            selector: Arc::new(selector),
            equals: Some(Arc::new(equals)),
        }
    }
}

impl<S, T> StateSelector<S, T> for SimpleSelector<S, T> {
    fn select(&self, state: &S) -> T {
        (self.selector)(state)
    }

    fn equals(&self, previous: &T, next: &T) -> bool
    where
        T: PartialEq,
    {
        self.equals
            .as_ref()
            .map_or_else(|| previous == next, |equals| equals(previous, next))
    }
}
