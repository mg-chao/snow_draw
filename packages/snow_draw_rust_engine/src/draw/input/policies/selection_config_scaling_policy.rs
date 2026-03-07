#![allow(dead_code)]

use crate::draw::config::draw_config::{
    SelectionConfig, SelectionInteractionConfig, SelectionRenderConfig,
};
use crate::draw::utils::camera_zoom::resolve_effective_zoom;

const IDENTITY_SCALE_EPSILON: f64 = 0.0001;

/// Scales `selection_config` for input hit-testing under `scale_factor`.
///
/// Invalid scale factors are treated as `1.0`.
pub fn scale_selection_config_for_input(
    selection_config: &SelectionConfig,
    scale_factor: f64,
) -> SelectionConfig {
    let effective_scale = resolve_effective_zoom(scale_factor);
    if (effective_scale - 1.0).abs() <= IDENTITY_SCALE_EPSILON {
        return selection_config.clone();
    }

    let render = &selection_config.render;
    let interaction = &selection_config.interaction;

    SelectionConfig {
        render: SelectionRenderConfig {
            stroke_width: render.stroke_width / effective_scale,
            stroke_color: render.stroke_color,
            corner_fill_color: render.corner_fill_color,
            corner_radius: render.corner_radius / effective_scale,
            control_point_size: render.control_point_size / effective_scale,
        },
        interaction: SelectionInteractionConfig {
            handle_tolerance: interaction.handle_tolerance / effective_scale,
            drag_threshold: interaction.drag_threshold / effective_scale,
        },
        padding: selection_config.padding / effective_scale,
        rotate_handle_offset: selection_config.rotate_handle_offset / effective_scale,
    }
}

#[cfg(test)]
mod tests {
    use super::scale_selection_config_for_input;
    use crate::draw::config::draw_config::SelectionConfig;

    const EPSILON: f64 = 1e-12;

    #[test]
    fn returns_same_values_for_identity_scale() {
        let config = SelectionConfig::default();
        let scaled = scale_selection_config_for_input(&config, 1.0);

        assert_eq!(scaled, config);
    }

    #[test]
    fn treats_invalid_scale_as_one() {
        let config = SelectionConfig::default();

        assert_eq!(scale_selection_config_for_input(&config, 0.0), config);
        assert_eq!(scale_selection_config_for_input(&config, f64::NAN), config);
        assert_eq!(
            scale_selection_config_for_input(&config, f64::NEG_INFINITY),
            config
        );
    }

    #[test]
    fn scales_hit_test_values_by_inverse_zoom() {
        let config = SelectionConfig::default();
        let scaled = scale_selection_config_for_input(&config, 2.0);

        assert_close(scaled.render.stroke_width, config.render.stroke_width / 2.0);
        assert_close(
            scaled.render.corner_radius,
            config.render.corner_radius / 2.0,
        );
        assert_close(
            scaled.render.control_point_size,
            config.render.control_point_size / 2.0,
        );
        assert_close(scaled.padding, config.padding / 2.0);
        assert_close(
            scaled.rotate_handle_offset,
            config.rotate_handle_offset / 2.0,
        );
        assert_close(
            scaled.interaction.handle_tolerance,
            config.interaction.handle_tolerance / 2.0,
        );
        assert_close(
            scaled.interaction.drag_threshold,
            config.interaction.drag_threshold / 2.0,
        );

        assert_eq!(scaled.render.stroke_color, config.render.stroke_color);
        assert_eq!(
            scaled.render.corner_fill_color,
            config.render.corner_fill_color
        );
    }

    fn assert_close(left: f64, right: f64) {
        assert!(
            (left - right).abs() <= EPSILON,
            "left={left}, right={right}"
        );
    }
}
