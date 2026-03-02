#![allow(dead_code)]

use std::collections::{HashMap, HashSet};

use crate::draw::config::canvas_config::{BoxSelectionConfig, CanvasConfig};
use crate::draw::config::draw_config::SelectionConfig;
use crate::draw::config::grid_config::GridConfig;
use crate::draw::config::highlight_config::HighlightMaskConfig;
use crate::draw::config::snap_config::SnapConfig;
use crate::draw::config::watermark_config::WatermarkConfig;
use crate::draw::elements::types::arrow::arrow_points::{ArrowPointHandle, ArrowPointUtils};
use crate::draw::elements::types::text::text_data::TextData;
use crate::draw::models::application_state::InteractionState;
use crate::draw::models::draw_state_view::{DrawStateView, ElementState};
use crate::draw::types::draw_rect::DrawRect;
use crate::draw::types::edit_operation_id::EditOperationIds;
use crate::draw::types::edit_transform::EditTransform;
use crate::draw::utils::arrow_binding_highlight::{
    resolve_arrow_binding_pair, resolve_arrow_point_highlight_binding_from_active_index,
};
use crate::draw::utils::arrow_point_metrics::{
    resolve_arrow_point_handle_size, resolve_arrow_point_loop_threshold,
};
use crate::draw::utils::binding_highlight_visibility::resolve_hover_binding_highlight_id;
use crate::draw::utils::camera_zoom::resolve_effective_zoom;
use crate::draw::utils::selection_calculator::SelectionCalculator;
use crate::draw::utils::single_selection_profile::resolve_single_selection_profile;

use super::super::planning::highlight_mask_visibility::is_highlight_mask_visible;
use super::super::planning::watermark_visibility::is_watermark_visible;
use super::super::rect_intersection::rects_intersect;
use super::frame_render_plan::FrameRenderPlan;
use super::render_tasks::{
    ArrowBindingHighlightRenderTask, ArrowPointOverlayRenderTask, BackgroundRenderTask,
    BoxSelectionRenderTask, FrameRenderTask, GridRenderTask, HighlightMaskRenderTask,
    HoverOutlineRenderTask, SelectionControlsRenderTask, SelectionOutlineRenderTask,
    SnapGuidesRenderTask, WatermarkRenderTask,
};

/// Transient UI-facing inputs that are not persisted in `DrawStateView`.
#[derive(Clone, Debug, PartialEq)]
pub struct FrameRenderTransientState {
    pub hovered_element_id: Option<String>,
    pub hovered_binding_element_id: Option<String>,
    pub hovered_arrow_handle: Option<ArrowPointHandle>,
    pub active_arrow_handle: Option<ArrowPointHandle>,
    pub arrow_delete_indicator_visible: bool,
    pub selection_config: Option<SelectionConfig>,
    pub hover_selection_config: Option<SelectionConfig>,
    pub box_selection_config: Option<BoxSelectionConfig>,
    pub snap_config: Option<SnapConfig>,
    pub canvas_config: Option<CanvasConfig>,
    pub grid_config: Option<GridConfig>,
    pub highlight_mask_config: Option<HighlightMaskConfig>,
    pub watermark_config: Option<WatermarkConfig>,
    pub box_selection_bounds: Option<DrawRect>,
    pub preview_elements_by_id: HashMap<String, ElementState>,
}

impl Default for FrameRenderTransientState {
    fn default() -> Self {
        Self {
            hovered_element_id: None,
            hovered_binding_element_id: None,
            hovered_arrow_handle: None,
            active_arrow_handle: None,
            arrow_delete_indicator_visible: false,
            selection_config: None,
            hover_selection_config: None,
            box_selection_config: None,
            snap_config: None,
            canvas_config: None,
            grid_config: None,
            highlight_mask_config: None,
            watermark_config: None,
            box_selection_bounds: None,
            preview_elements_by_id: HashMap::new(),
        }
    }
}

/// Builds deterministic frame render plans from `DrawStateView`.
#[derive(Clone, Copy, Debug, Default, PartialEq, Eq)]
pub struct FrameRenderPlanBuilder;

impl FrameRenderPlanBuilder {
    pub const fn new() -> Self {
        Self
    }

    /// Builds a frame plan for the current state.
    pub fn build(
        &self,
        view: &DrawStateView,
        scale_factor: f64,
        locale_tag: Option<&str>,
        transient_state: &FrameRenderTransientState,
    ) -> FrameRenderPlan {
        let mut tasks = Vec::<FrameRenderTask>::new();
        let effective_scale = resolve_effective_zoom(scale_factor);
        let camera = view.state.application.view.camera;

        let resolve_effective_element = |element: &ElementState| -> ElementState {
            transient_state
                .preview_elements_by_id
                .get(&element.id)
                .cloned()
                .unwrap_or_else(|| view.effective_element(element))
        };

        let resolve_effective_element_by_id = |id: &str| -> Option<ElementState> {
            let element = view.state.domain.document.get_element_by_id(id)?;
            Some(resolve_effective_element(element))
        };

        if let Some(canvas_config) = transient_state.canvas_config {
            tasks.push(FrameRenderTask::Background(BackgroundRenderTask::new(
                canvas_config.background_color,
            )));
        }

        if let Some(grid_config) = transient_state.grid_config {
            tasks.push(FrameRenderTask::Grid(GridRenderTask {
                enabled: grid_config.enabled,
                size: grid_config.size,
                line_width: grid_config.line_width,
                line_color: grid_config.line_color,
                line_opacity: grid_config.line_opacity,
                major_line_every: grid_config.major_line_every,
                major_line_opacity: grid_config.major_line_opacity,
                min_screen_spacing: grid_config.min_screen_spacing,
                min_render_spacing: grid_config.min_render_spacing,
            }));
        }

        if let Some(highlight_mask_config) = transient_state.highlight_mask_config {
            if is_highlight_mask_visible(
                view.highlight_mask_scene().has_highlights(),
                highlight_mask_config,
            ) {
                tasks.push(FrameRenderTask::HighlightMask(HighlightMaskRenderTask {
                    config: highlight_mask_config,
                    highlights: view.highlight_mask_scene().elements().to_vec(),
                }));
            }
        }

        if let Some(watermark_config) = transient_state.watermark_config.as_ref() {
            if is_watermark_visible(watermark_config) {
                tasks.push(FrameRenderTask::Watermark(WatermarkRenderTask {
                    config: watermark_config.clone(),
                }));
            }
        }

        if let Some(snap_config) = transient_state.snap_config {
            if !view.snap_guides.is_empty() && snap_config.show_guides {
                tasks.push(FrameRenderTask::SnapGuides(SnapGuidesRenderTask {
                    guides: view.snap_guides.clone(),
                    snap_config,
                }));
            }
        }

        let selected_ids = view.selected_ids();
        let selected_effective_elements = view
            .selected_elements()
            .into_iter()
            .map(|element| resolve_effective_element(&element))
            .collect::<Vec<_>>();
        let single_selection = resolve_single_selection_profile(selected_ids, |id| {
            resolve_effective_element_by_id(id)
        });
        let single_selected = single_selection.element.clone();

        if let (Some(hovered_element_id), Some(hover_selection_config)) = (
            transient_state.hovered_element_id.as_deref(),
            transient_state.hover_selection_config.as_ref(),
        ) {
            if !selected_ids.contains(hovered_element_id) {
                if let Some(effective_hovered) = resolve_effective_element_by_id(hovered_element_id)
                {
                    tasks.push(FrameRenderTask::HoverOutline(HoverOutlineRenderTask {
                        use_text_underline_style: effective_hovered.data.type_id().as_str()
                            == TextData::TYPE_ID_TOKEN,
                        element: effective_hovered,
                        config: hover_selection_config.clone(),
                    }));
                }
            }
        }

        if let Some(selection_config) = transient_state.selection_config.as_ref() {
            let effective_selection = view.effective_selection();
            if effective_selection.has_selection && effective_selection.bounds.is_some() {
                if selected_ids.len() > 1 {
                    for selected in &selected_effective_elements {
                        tasks.push(FrameRenderTask::SelectionOutline(
                            SelectionOutlineRenderTask {
                                bounds: selected.rect,
                                config: selection_config.clone(),
                                rotation: Some(selected.rotation),
                                rotation_center: Some(selected.rect.center()),
                                dashed: false,
                            },
                        ));
                    }
                }

                if !single_selection.is_two_point_arrow() {
                    let selection_bounds = effective_selection
                        .bounds
                        .expect("selection bounds should exist when has_selection is true");
                    tasks.push(FrameRenderTask::SelectionControls(
                        SelectionControlsRenderTask {
                            bounds: selection_bounds,
                            config: selection_config.clone(),
                            rotation: effective_selection.rotation,
                            rotation_center: effective_selection
                                .center
                                .or(Some(selection_bounds.center())),
                            dashed: selected_ids.len() > 1,
                            corner_handle_offset: single_selection.corner_handle_offset(),
                            show_rotation_handle: !single_selection.is_elbow_arrow(),
                        },
                    ));
                }
            }

            if let (Some(single_selected_element), Some(_arrow_data)) =
                (single_selected.clone(), single_selection.arrow_data)
            {
                let handle_tolerance =
                    selection_config.interaction.handle_tolerance / effective_scale;
                let loop_threshold = resolve_arrow_point_loop_threshold(handle_tolerance);
                let base_handle_size = selection_config.render.control_point_size / effective_scale;
                let handle_size = resolve_arrow_point_handle_size(base_handle_size);
                let overlay = ArrowPointUtils::build_overlay(
                    &single_selected_element,
                    loop_threshold,
                    Some(handle_size),
                );

                let mut handles = Vec::<ArrowPointHandle>::new();
                handles.extend(overlay.addable_points);
                handles.extend(overlay.turning_points);
                handles.extend(overlay.loop_points);
                if !handles.is_empty() {
                    tasks.push(FrameRenderTask::ArrowPointOverlay(
                        ArrowPointOverlayRenderTask {
                            handles,
                            selection_config: selection_config.clone(),
                            active_handle: transient_state.active_arrow_handle.clone(),
                            hovered_handle: transient_state.hovered_arrow_handle.clone(),
                            delete_indicator_visible: transient_state
                                .arrow_delete_indicator_visible,
                        },
                    ));
                }
            }

            let highlight_element_ids = self.resolve_arrow_binding_highlight_element_ids(
                view,
                transient_state,
                &resolve_effective_element,
            );
            if !highlight_element_ids.is_empty() {
                tasks.push(FrameRenderTask::ArrowBindingHighlight(
                    ArrowBindingHighlightRenderTask {
                        element_ids: highlight_element_ids,
                        stroke_color: selection_config.render.stroke_color,
                    },
                ));
            }

            if let (Some(single_selected_element), Some(hover_selection_config)) = (
                single_selected,
                transient_state.hover_selection_config.as_ref(),
            ) {
                if single_selection.is_text {
                    tasks.push(FrameRenderTask::SelectionOutline(
                        SelectionOutlineRenderTask {
                            bounds: single_selected_element.rect,
                            config: hover_selection_config.clone(),
                            rotation: Some(single_selected_element.rotation),
                            rotation_center: Some(single_selected_element.rect.center()),
                            dashed: false,
                        },
                    ));
                }
            }

            if let (Some(box_selection_bounds), Some(box_selection_config)) = (
                transient_state.box_selection_bounds,
                transient_state.box_selection_config,
            ) {
                let mut preview_elements = Vec::<ElementState>::new();
                for candidate in &view.state.domain.document.elements {
                    let effective = resolve_effective_element(candidate);
                    let aabb = SelectionCalculator::compute_element_world_aabb(&effective);
                    if rects_intersect(box_selection_bounds, aabb) {
                        preview_elements.push(effective);
                    }
                }

                tasks.push(FrameRenderTask::BoxSelection(BoxSelectionRenderTask {
                    bounds: box_selection_bounds,
                    config: box_selection_config,
                    selection_config: selection_config.clone(),
                    preview_elements,
                }));
            }
        }

        FrameRenderPlan::new(
            tasks,
            camera,
            effective_scale,
            locale_tag.map(str::to_owned),
        )
    }

    /// Convenience wrapper that uses an empty transient-state payload.
    pub fn build_with_defaults(
        &self,
        view: &DrawStateView,
        scale_factor: f64,
        locale_tag: Option<&str>,
    ) -> FrameRenderPlan {
        self.build(
            view,
            scale_factor,
            locale_tag,
            &FrameRenderTransientState::default(),
        )
    }

    fn resolve_arrow_binding_highlight_element_ids(
        &self,
        view: &DrawStateView,
        transient_state: &FrameRenderTransientState,
        resolve_effective_element: &dyn Fn(&ElementState) -> ElementState,
    ) -> Vec<String> {
        let mut highlight_ids = HashSet::<String>::new();

        self.add_highlight_element_id(
            &mut highlight_ids,
            resolve_hover_binding_highlight_id(
                transient_state.hovered_binding_element_id.clone(),
                transient_state.hovered_arrow_handle.clone(),
            ),
        );

        match &view.state.application.interaction {
            InteractionState::Editing(interaction)
                if interaction.operation_id == EditOperationIds::ARROW_POINT =>
            {
                if let EditTransform::ArrowPoint(transform) = &interaction.current_transform {
                    if let Some(selected_id) = view.selected_ids().iter().next() {
                        if let Some(element) =
                            view.state.domain.document.get_element_by_id(selected_id)
                        {
                            let effective = resolve_effective_element(element);
                            if let Some(bindings) =
                                resolve_arrow_binding_pair(effective.data.as_ref())
                            {
                                let highlight =
                                    resolve_arrow_point_highlight_binding_from_active_index(
                                        transform.points.len(),
                                        transform.active_index,
                                        &bindings,
                                        Some(&interaction.current_transform),
                                    );
                                self.add_highlight_element_id(
                                    &mut highlight_ids,
                                    highlight.map(|value| value.element_id),
                                );
                            }
                        }
                    }
                }
            }
            InteractionState::Creating(interaction) if interaction.is_point_creation() => {
                if let Some(bindings) =
                    resolve_arrow_binding_pair(interaction.element.data.as_ref())
                {
                    self.add_highlight_element_id(
                        &mut highlight_ids,
                        bindings.start_binding.map(|value| value.element_id),
                    );
                    self.add_highlight_element_id(
                        &mut highlight_ids,
                        bindings.end_binding.map(|value| value.element_id),
                    );
                }
            }
            _ => {}
        }

        highlight_ids.into_iter().collect()
    }

    fn add_highlight_element_id(&self, target: &mut HashSet<String>, element_id: Option<String>) {
        let Some(element_id) = element_id else {
            return;
        };
        if element_id.is_empty() {
            return;
        }
        target.insert(element_id);
    }
}
