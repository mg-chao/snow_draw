#![allow(dead_code)]

use std::sync::Arc;

/// Callback type with no arguments and no return value.
///
/// Dart source:
/// `typedef VoidCallback = void Function();`
pub type VoidCallback = Arc<dyn Fn() + 'static>;

/// Creates a shared no-argument callback handle.
pub fn void_callback<F>(callback: F) -> VoidCallback
where
    F: Fn() + 'static,
{
    Arc::new(callback)
}
