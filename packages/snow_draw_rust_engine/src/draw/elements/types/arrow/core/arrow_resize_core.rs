#![allow(dead_code)]

use crate::draw::types::draw_point::DrawPoint;

pub type ResizeArrowDirection = &'static str;

pub fn get_resize_arrow_direction(
    transform_handle_type: Option<&str>,
    points: &[DrawPoint],
) -> ResizeArrowDirection {
    let Some(second_point) = points.get(1).copied() else {
        return "origin";
    };

    let px = second_point.x;
    let py = second_point.y;
    let is_resize_end = matches!(transform_handle_type, Some("nw") if px < 0.0 || py < 0.0)
        || matches!(transform_handle_type, Some("ne") if px >= 0.0)
        || matches!(transform_handle_type, Some("sw") if px <= 0.0)
        || matches!(transform_handle_type, Some("se") if px > 0.0 || py > 0.0);

    if is_resize_end {
        "end"
    } else {
        "origin"
    }
}
