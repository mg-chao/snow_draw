//! Aggregated exports for the legacy input plugin system.
//!
//! This mirrors `draw/input/plugin_system.dart` from the Dart engine so callers
//! can import one module and access all input plugin pieces.

pub use super::middleware::default_middlewares::*;
pub use super::middleware::input_middleware::*;
pub use super::plugin_engine::*;
pub use super::plugin_input_coordinator::*;
pub use super::plugin_registry::*;
pub use super::plugins::box_select_plugin::*;
pub use super::plugins::create_plugin::*;
pub use super::plugins::edit_plugin::*;
pub use super::plugins::select_plugin::*;
pub use super::plugins::text_tool_plugin::*;
