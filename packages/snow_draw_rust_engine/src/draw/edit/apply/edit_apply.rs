#![allow(dead_code)]

use std::collections::{HashMap, HashSet};
use std::sync::Arc;

use crate::draw::core::coordinates::overlay_space::OverlaySpace;
use crate::draw::core::geometry::rotate_geometry::RotateGeometry;
use crate::draw::elements::core::element_data::ElementData;
use crate::draw::elements::types::arrow::arrow_data::{
    ArrowData, ArrowDataPatch, ElbowFixedSegment as ArrowDataElbowFixedSegment,
    NullableField as ArrowNullableField,
};
use crate::draw::elements::types::serial_number::serial_number_data::{
    SerialNumberData, SerialNumberDataPatch,
};
use crate::draw::elements::types::text::text_bounds::{
    clamp_text_rect_to_layout, fit_text_font_size_to_height,
};
use crate::draw::elements::types::text::text_data::{TextData, TextDataPatch};
use crate::draw::models::element_state::ElementState;
use crate::draw::types::draw_point::DrawPoint;
use crate::draw::types::draw_rect::DrawRect;
use crate::draw::types::edit_context::ResizeEditContext;
use crate::draw::types::element_geometry::{
    ElementMoveSnapshot, ElementResizeSnapshot, ElementRotateSnapshot,
};
use crate::draw::types::element_style::ArrowType;
use crate::draw::types::resize_mode::ResizeMode;

const RESIZE_TOLERANCE: f64 = 0.01;

/// Single-source-of-truth geometry application for edit operations.
///
/// This mirrors Dart `EditApply` so preview and commit paths can share the
/// same math.
#[derive(Clone, Copy, Debug, Default)]
pub struct EditApply;

impl EditApply {
    pub fn apply_move_to_elements(
        snapshots: &HashMap<String, ElementMoveSnapshot>,
        selected_ids: &HashSet<String>,
        dx: f64,
        dy: f64,
        current_elements_by_id: &HashMap<String, ElementState>,
    ) -> HashMap<String, ElementState> {
        let mut result = HashMap::with_capacity(selected_ids.len());
        let offset = DrawPoint::new(dx, dy);

        visit_selected_snapshots(
            selected_ids,
            snapshots,
            current_elements_by_id,
            |id, snapshot, current| {
                let new_center = snapshot.center.translate(offset);
                result.insert(
                    id.to_owned(),
                    current.copy_with(
                        None,
                        Some(rect_from_center(
                            new_center,
                            current.rect.width(),
                            current.rect.height(),
                        )),
                        None,
                        None,
                        None,
                        None,
                    ),
                );
            },
        );

        result
    }

    pub fn apply_rotate_to_elements(
        snapshots: &HashMap<String, ElementRotateSnapshot>,
        selected_ids: &HashSet<String>,
        pivot: DrawPoint,
        delta_angle: f64,
        current_elements_by_id: &HashMap<String, ElementState>,
    ) -> HashMap<String, ElementState> {
        let mut result = HashMap::with_capacity(selected_ids.len());

        visit_selected_snapshots(
            selected_ids,
            snapshots,
            current_elements_by_id,
            |id, snapshot, current| {
                if is_elbow_arrow_like(current.data.as_ref()) {
                    return;
                }

                let new_rotation = snapshot.rotation + delta_angle;
                let new_center = RotateGeometry::rotate_point(snapshot.center, pivot, delta_angle);
                result.insert(
                    id.to_owned(),
                    current.copy_with(
                        None,
                        Some(rect_from_center(
                            new_center,
                            current.rect.width(),
                            current.rect.height(),
                        )),
                        Some(new_rotation),
                        None,
                        None,
                        None,
                    ),
                );
            },
        );

        result
    }

    #[allow(clippy::too_many_arguments)]
    pub fn apply_resize_to_elements(
        snapshots: &HashMap<String, ElementResizeSnapshot>,
        selected_ids: &HashSet<String>,
        context: &ResizeEditContext,
        new_selection_bounds: DrawRect,
        scale_x: f64,
        scale_y: f64,
        anchor: DrawPoint,
        current_elements_by_id: &HashMap<String, ElementState>,
    ) -> HashMap<String, ElementState> {
        let is_single_select = selected_ids.len() == 1;
        let has_rotation = context.has_rotation();
        let keep_text_center = points_match(anchor, context.base.start_bounds.center());
        let is_vertical_resize =
            matches!(context.resize_mode, ResizeMode::Top | ResizeMode::Bottom);

        let mut result = HashMap::with_capacity(selected_ids.len());

        visit_selected_snapshots(
            selected_ids,
            snapshots,
            current_elements_by_id,
            |id, snapshot, current| {
                let start_element = current.copy_with(
                    None,
                    Some(snapshot.rect),
                    Some(snapshot.rotation),
                    None,
                    None,
                    None,
                );

                let mut resized = apply_resize_geometry(
                    &start_element,
                    context.base.start_bounds,
                    new_selection_bounds,
                    scale_x,
                    scale_y,
                    anchor,
                    context.rotation,
                    is_single_select,
                    has_rotation,
                );

                let type_id = resized.data.type_id();
                match type_id.as_str() {
                    TextData::TYPE_ID_TOKEN => {
                        resized = apply_text_resize(
                            resized,
                            start_element.rect,
                            anchor,
                            keep_text_center,
                            is_vertical_resize,
                            scale_x,
                        );
                    }
                    SerialNumberData::TYPE_ID_TOKEN => {
                        resized = apply_serial_number_resize(resized, start_element.rect);
                    }
                    ArrowData::TYPE_ID_TOKEN => {
                        resized = apply_arrow_resize(resized, start_element.rect);
                    }
                    _ => {}
                }

                result.insert(id.to_owned(), resized);
            },
        );

        result
    }

    /// Returns a list where matching ids are replaced while preserving order.
    pub fn replace_elements_by_id(
        elements: Vec<ElementState>,
        replacements_by_id: &HashMap<String, ElementState>,
    ) -> Vec<ElementState> {
        if replacements_by_id.is_empty() || elements.is_empty() {
            return elements;
        }

        let mut updated_elements: Option<Vec<ElementState>> = None;
        for (index, current) in elements.iter().enumerate() {
            let Some(replacement) = replacements_by_id.get(&current.id) else {
                continue;
            };
            if replacement == current {
                continue;
            }

            if updated_elements.is_none() {
                updated_elements = Some(elements.clone());
            }
            if let Some(updated) = updated_elements.as_mut() {
                updated[index] = replacement.clone();
            }
        }

        updated_elements.unwrap_or(elements)
    }
}

fn visit_selected_snapshots<S, F>(
    selected_ids: &HashSet<String>,
    snapshots: &HashMap<String, S>,
    current_elements_by_id: &HashMap<String, ElementState>,
    mut visitor: F,
) where
    F: FnMut(&str, &S, &ElementState),
{
    for id in selected_ids {
        let Some(snapshot) = snapshots.get(id) else {
            continue;
        };
        let Some(current) = current_elements_by_id.get(id) else {
            continue;
        };
        visitor(id, snapshot, current);
    }
}

#[allow(clippy::too_many_arguments)]
fn apply_resize_geometry(
    element: &ElementState,
    start_bounds: DrawRect,
    new_selection_bounds: DrawRect,
    scale_x: f64,
    scale_y: f64,
    anchor: DrawPoint,
    overlay_rotation: f64,
    is_single_select: bool,
    has_rotation: bool,
) -> ElementState {
    if is_single_select
        && (has_rotation || start_bounds.width() == 0.0 || start_bounds.height() == 0.0)
    {
        return element.copy_with(None, Some(new_selection_bounds), None, None, None, None);
    }

    if has_rotation {
        return apply_multi_rotated_resize(
            element,
            start_bounds,
            new_selection_bounds,
            scale_x,
            scale_y,
            overlay_rotation,
        );
    }

    apply_direct_resize(element, anchor, scale_x, scale_y)
}

fn apply_direct_resize(
    element: &ElementState,
    anchor: DrawPoint,
    scale_x: f64,
    scale_y: f64,
) -> ElementState {
    let rect = element.rect;
    let x1 = anchor.x + (rect.min_x - anchor.x) * scale_x;
    let x2 = anchor.x + (rect.max_x - anchor.x) * scale_x;
    let y1 = anchor.y + (rect.min_y - anchor.y) * scale_y;
    let y2 = anchor.y + (rect.max_y - anchor.y) * scale_y;

    element.copy_with(
        None,
        Some(DrawRect::new(
            x1.min(x2),
            y1.min(y2),
            x1.max(x2),
            y1.max(y2),
        )),
        None,
        None,
        None,
        None,
    )
}

fn apply_multi_rotated_resize(
    element: &ElementState,
    start_bounds: DrawRect,
    new_selection_bounds: DrawRect,
    scale_x: f64,
    scale_y: f64,
    overlay_rotation: f64,
) -> ElementState {
    let start_center = start_bounds.center();
    let new_center = new_selection_bounds.center();

    let start_space = OverlaySpace::new(overlay_rotation, start_center);
    let new_space = OverlaySpace::new(overlay_rotation, new_center);

    let start_rect = element.rect;
    let start_center_world_of_element = start_rect.center();
    let start_center_local = start_space.from_world(start_center_world_of_element);

    let flip_x = scale_x < 0.0;
    let flip_y = scale_y < 0.0;
    let base_x = if flip_x {
        new_selection_bounds.max_x
    } else {
        new_selection_bounds.min_x
    };
    let base_y = if flip_y {
        new_selection_bounds.max_y
    } else {
        new_selection_bounds.min_y
    };

    let new_center_local = DrawPoint::new(
        base_x + (start_center_local.x - start_bounds.min_x) * scale_x,
        base_y + (start_center_local.y - start_bounds.min_y) * scale_y,
    );
    let new_center_world_of_element = new_space.to_world(new_center_local);

    let new_width = start_rect.width() * scale_x.abs();
    let new_height = start_rect.height() * scale_y.abs();

    element.copy_with(
        None,
        Some(rect_from_center(
            new_center_world_of_element,
            new_width,
            new_height,
        )),
        None,
        None,
        None,
        None,
    )
}

fn apply_text_resize(
    element: ElementState,
    start_rect: DrawRect,
    anchor: DrawPoint,
    keep_center: bool,
    is_vertical_resize: bool,
    scale_x: f64,
) -> ElementState {
    let Some(original_data) = decode_text_data(element.data.as_ref()) else {
        return element;
    };

    let mut data = original_data.clone();
    let mut rect = element.rect;
    let height_delta = (rect.height() - start_rect.height()).abs();
    let allow_width_scale = is_vertical_resize && (scale_x - 1.0).abs() <= RESIZE_TOLERANCE;

    if allow_width_scale && height_delta > RESIZE_TOLERANCE {
        let start_height = start_rect.height();
        if start_height > 0.0 {
            let height_scale = rect.height() / start_height;
            if height_scale.is_finite()
                && height_scale > 0.0
                && (height_scale - 1.0).abs() > RESIZE_TOLERANCE
            {
                let new_width = rect.width() * height_scale;
                if new_width.is_finite() && new_width > 0.0 {
                    let center_x = rect.center_x();
                    rect = rect.copy_with(
                        Some(center_x - new_width / 2.0),
                        None,
                        Some(center_x + new_width / 2.0),
                        None,
                    );
                }
            }
        }
    }

    if height_delta > RESIZE_TOLERANCE {
        let fitted_font_size = fit_text_font_size_to_height(
            &data,
            rect.height(),
            rect.width(),
            None,
            1.0,
            8,
            RESIZE_TOLERANCE,
        );
        if (fitted_font_size - data.font_size).abs() > RESIZE_TOLERANCE {
            data = data.copy_with(TextDataPatch {
                font_size: Some(fitted_font_size),
                ..TextDataPatch::default()
            });
        }
    }

    let clamped_rect =
        clamp_text_rect_to_layout(rect, start_rect, anchor, &data, None, keep_center);

    if data.auto_resize {
        data = data.copy_with(TextDataPatch {
            auto_resize: Some(false),
            ..TextDataPatch::default()
        });
    }

    if clamped_rect == element.rect && data == original_data {
        return element;
    }

    element.copy_with(
        None,
        Some(clamped_rect),
        None,
        None,
        None,
        Some(Arc::new(data)),
    )
}

fn apply_serial_number_resize(element: ElementState, start_rect: DrawRect) -> ElementState {
    let Some(original_data) = decode_serial_number_data(element.data.as_ref()) else {
        return element;
    };

    let mut data = original_data.clone();
    let start_diameter = start_rect.width().min(start_rect.height());
    let next_diameter = element.rect.width().min(element.rect.height());

    if start_diameter > 0.0 && next_diameter > 0.0 {
        let scale = next_diameter / start_diameter;
        if scale.is_finite() && scale > 0.0 {
            let next_font_size = data.font_size * scale;
            if (next_font_size - data.font_size).abs() > RESIZE_TOLERANCE {
                data = data.copy_with(SerialNumberDataPatch {
                    font_size: Some(next_font_size),
                    ..SerialNumberDataPatch::default()
                });
            }
        }
    }

    if data == original_data {
        return element;
    }

    element.copy_with(None, None, None, None, None, Some(Arc::new(data)))
}

fn apply_arrow_resize(element: ElementState, start_rect: DrawRect) -> ElementState {
    let Some(data) = decode_arrow_data(element.data.as_ref()) else {
        return element;
    };
    let Some(fixed_segments) = data.fixed_segments.as_deref() else {
        return element;
    };
    if data.arrow_type != ArrowType::Elbow || fixed_segments.is_empty() {
        return element;
    }

    let scaled = scale_fixed_segments(fixed_segments, start_rect, element.rect);
    if fixed_segments == scaled.as_slice() {
        return element;
    }

    let updated_data = data.copy_with(ArrowDataPatch {
        fixed_segments: ArrowNullableField::Value(scaled),
        ..ArrowDataPatch::default()
    });

    element.copy_with(None, None, None, None, None, Some(Arc::new(updated_data)))
}

fn scale_fixed_segments(
    fixed_segments: &[ArrowDataElbowFixedSegment],
    old_rect: DrawRect,
    new_rect: DrawRect,
) -> Vec<ArrowDataElbowFixedSegment> {
    fixed_segments
        .iter()
        .map(|segment| ArrowDataElbowFixedSegment {
            index: segment.index,
            start: scale_point(segment.start, old_rect, new_rect),
            end: scale_point(segment.end, old_rect, new_rect),
        })
        .collect()
}

fn rect_from_center(center: DrawPoint, width: f64, height: f64) -> DrawRect {
    let half_width = width / 2.0;
    let half_height = height / 2.0;
    DrawRect::new(
        center.x - half_width,
        center.y - half_height,
        center.x + half_width,
        center.y + half_height,
    )
}

fn scale_point(point: DrawPoint, old_rect: DrawRect, new_rect: DrawRect) -> DrawPoint {
    let old_width = old_rect.width();
    let old_height = old_rect.height();
    let new_width = new_rect.width();
    let new_height = new_rect.height();
    let nx = if old_width == 0.0 {
        0.0
    } else {
        (point.x - old_rect.min_x) / old_width
    };
    let ny = if old_height == 0.0 {
        0.0
    } else {
        (point.y - old_rect.min_y) / old_height
    };

    DrawPoint::new(
        new_rect.min_x + nx * new_width,
        new_rect.min_y + ny * new_height,
    )
}

fn points_match(a: DrawPoint, b: DrawPoint) -> bool {
    a.x == b.x && a.y == b.y
}

fn is_elbow_arrow_like(data: &dyn ElementData) -> bool {
    decode_arrow_data(data).is_some_and(|arrow_data| arrow_data.arrow_type == ArrowType::Elbow)
}

fn decode_text_data(data: &dyn ElementData) -> Option<TextData> {
    if data.type_id().as_str() != TextData::TYPE_ID_TOKEN {
        return None;
    }
    TextData::from_json(&data.to_json()).ok()
}

fn decode_serial_number_data(data: &dyn ElementData) -> Option<SerialNumberData> {
    if data.type_id().as_str() != SerialNumberData::TYPE_ID_TOKEN {
        return None;
    }
    SerialNumberData::from_json(&data.to_json()).ok()
}

fn decode_arrow_data(data: &dyn ElementData) -> Option<ArrowData> {
    if data.type_id().as_str() != ArrowData::TYPE_ID_TOKEN {
        return None;
    }
    ArrowData::from_json(&data.to_json()).ok()
}
