#![allow(dead_code)]

pub mod adapters;
pub mod arrow_binding_core;
pub mod arrow_binding_lifecycle;
pub mod arrow_elbow_core;
pub mod arrow_engine;
pub mod arrow_focus_core;
pub mod arrow_geom;
pub mod arrow_hit_test;
pub mod arrow_order_core;
pub mod arrow_path_core;
pub mod arrow_relation_core;
pub mod arrow_render_core;
pub mod arrow_resize_core;
pub mod arrow_state_core;
pub mod arrow_types;
/// Mirrors the Dart `index.dart` barrel exports for arrow-core helpers.
///
/// Consumers can import `core::index::*` to access the flattened arrow-core
/// API surface instead of referencing each helper module individually.
pub mod index;
