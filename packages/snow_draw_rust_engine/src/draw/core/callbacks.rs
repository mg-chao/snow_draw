#![allow(dead_code)]

/// Callback type with no arguments and no return value.
///
/// Dart source:
/// `typedef VoidCallback = void Function();`
pub type VoidCallback = Box<dyn FnMut()>;
