#![allow(dead_code)]

/// Public entrypoint re-exports for backend-agnostic Snow Draw engine APIs.
///
/// This mirrors `snow_draw_engine.dart` by exposing the Rust module surface in
/// one place for consumers that prefer a single import path.
pub use crate::draw::actions::config_actions::*;
pub use crate::draw::actions::draw_actions::*;
pub use crate::draw::actions::history_coalescing::*;
pub use crate::draw::actions::history_policy::*;

pub use crate::draw::config::canvas_config::*;
pub use crate::draw::config::draw_config::*;
pub use crate::draw::config::element_config::*;
pub use crate::draw::config::grid_config::*;
pub use crate::draw::config::highlight_config::*;
pub use crate::draw::config::selection_config::*;
pub use crate::draw::config::snap_config::*;
pub use crate::draw::config::watermark_config::*;

pub use crate::draw::core::callbacks::*;
pub use crate::draw::core::coordinates::element_space::*;
pub use crate::draw::core::draw_context::*;
pub use crate::draw::core::error_context::*;

pub use crate::draw::edit::arrow::arrow_point_operation::*;
pub use crate::draw::edit::connector::connector_point_operation::*;
pub use crate::draw::edit::core::edit_operation_params::*;
pub use crate::draw::edit::edit_operations::*;
pub use crate::draw::elements::core::element_data::*;
pub use crate::draw::elements::core::element_definition::*;
pub use crate::draw::elements::core::element_hit_tester::*;
pub use crate::draw::elements::core::element_registry::*;
pub use crate::draw::elements::core::element_type_id::*;
pub use crate::draw::elements::core::typed_element_render_task_encoder::*;
pub use crate::draw::elements::registration::*;
pub use crate::draw::elements::text_rendering_cache_invalidation::*;
pub use crate::draw::elements::types::arrow::arrow_binding::*;
pub use crate::draw::elements::types::arrow::arrow_binding_policy::*;
pub use crate::draw::elements::types::arrow::arrow_binding_target_cache::*;
pub use crate::draw::elements::types::arrow::arrow_core::*;
pub use crate::draw::elements::types::arrow::arrow_core_bridge::*;
pub use crate::draw::elements::types::arrow::arrow_core_codec::*;
pub use crate::draw::elements::types::arrow::arrow_core_endpoint_drag::*;
pub use crate::draw::elements::types::arrow::arrow_core_geometry_adapter::*;
pub use crate::draw::elements::types::arrow::arrow_core_ops::*;
pub use crate::draw::elements::types::arrow::arrow_data::*;
pub use crate::draw::elements::types::arrow::arrow_focus::*;
pub use crate::draw::elements::types::arrow::arrow_geometry::*;
pub use crate::draw::elements::types::arrow::arrow_like_data::*;
pub use crate::draw::elements::types::arrow::arrow_points::*;
pub use crate::draw::elements::types::arrow::arrow_render_primitives::*;
pub use crate::draw::elements::types::arrow::arrow_scene::*;
pub use crate::draw::elements::types::arrow::elbow::ElbowRoutingData;
pub use crate::draw::elements::types::connector::connector_creation_strategy::*;
pub use crate::draw::elements::types::connector::connector_data::*;
pub use crate::draw::elements::types::connector::connector_data_codec::*;
pub use crate::draw::elements::types::connector::connector_geometry::*;
pub use crate::draw::elements::types::connector::connector_hit_tester::*;
pub use crate::draw::elements::types::connector::connector_points::*;
pub use crate::draw::elements::types::filter::filter_data::*;
pub use crate::draw::elements::types::free_draw::free_draw_creation_strategy::*;
pub use crate::draw::elements::types::free_draw::free_draw_data::*;
pub use crate::draw::elements::types::free_draw::free_draw_hit_tester::*;
pub use crate::draw::elements::types::highlight::highlight_data::*;
pub use crate::draw::elements::types::line::line_data::*;
pub use crate::draw::elements::types::rectangle::rectangle_data::*;
pub use crate::draw::elements::types::serial_number::serial_number_binding::*;
pub use crate::draw::elements::types::serial_number::serial_number_data::*;
pub use crate::draw::elements::types::text::text_data::*;
pub use crate::draw::elements::types::text::text_editing_geometry::*;
pub use crate::draw::elements::types::text::text_layout_constants::*;
pub use crate::draw::events::error_events::*;
pub use crate::draw::events::event_bus::*;
pub use crate::draw::events::state_events::*;

pub use crate::draw::input::input_event::*;
pub use crate::draw::input::plugin_system::*;
pub use crate::draw::input::policies::arrow_binding_preview_policy::*;
pub use crate::draw::input::policies::eraser_stroke_processor::*;
pub use crate::draw::input::policies::pointer_move_dispatch_policy::*;
pub use crate::draw::input::policies::selection_config_scaling_policy::*;
pub use crate::draw::input::policies::style_scroll_adjustment_policy::*;
pub use crate::draw::input::policies::tool_change_reset_policy::*;
pub use crate::draw::reducers::core::arrow_binding_sync::*;

pub use crate::draw::models::application_state::*;
pub use crate::draw::models::camera_state::*;
pub use crate::draw::models::document_state::*;
pub use crate::draw::models::domain_state::*;
pub use crate::draw::models::draw_state::*;
pub use crate::draw::models::draw_state_view::*;
pub use crate::draw::models::element_state::*;
pub use crate::draw::models::interaction_state::*;
pub use crate::draw::models::selection_state::*;
pub use crate::draw::models::view_state::*;

pub use crate::draw::render::planning::filter_segment_builder::*;
pub use crate::draw::render::planning::filter_segments::*;
pub use crate::draw::render::planning::highlight_mask_visibility::*;
pub use crate::draw::render::planning::serial_number_interaction_classifier::*;
pub use crate::draw::render::planning::visible_element_resolver::*;
pub use crate::draw::render::planning::watermark_visibility::*;
pub use crate::draw::render::tasks::frame_render_plan::*;
pub use crate::draw::render::tasks::frame_render_plan_builder::*;
pub use crate::draw::render::tasks::render_tasks::*;

pub use crate::draw::services::coordinate_service::*;
pub use crate::draw::services::draw_state_view_builder::*;
pub use crate::draw::services::log::log_config::*;
pub use crate::draw::services::log::log_service::*;
pub use crate::draw::services::text::text_metrics_service::*;

pub use crate::draw::store::draw_store::*;
pub use crate::draw::store::draw_store_interface::*;
pub use crate::draw::store::selector::*;

pub use crate::draw::types::draw_color::*;
pub use crate::draw::types::draw_point::*;
pub use crate::draw::types::draw_rect::*;
pub use crate::draw::types::edit_context::*;
pub use crate::draw::types::edit_operation_id::*;
pub use crate::draw::types::edit_transform::*;
pub use crate::draw::types::element_style::*;
pub use crate::draw::types::resize_mode::*;
pub use crate::draw::types::snap_guides::*;

pub use crate::draw::utils::arrow_binding_highlight::*;
pub use crate::draw::utils::binding_highlight_visibility::*;
pub use crate::draw::utils::edit_intent_detector::*;
pub use crate::draw::utils::hit_test::*;
pub use crate::draw::utils::lru_cache::*;
pub use crate::draw::utils::selection_calculator::*;
pub use crate::draw::utils::snapping_mode::*;

pub use crate::utils::id_generator::*;
