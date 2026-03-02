#![allow(dead_code)]

use crate::draw::types::draw_point::DrawPoint;
use crate::draw::types::draw_rect::DrawRect;
use crate::draw::types::resize_mode::ResizeMode;
use crate::draw::utils::transforms::edit_transform_context::{EditTransformContext, OverlaySpace};

/// Output of resize bounds calculation.
#[derive(Clone, Copy, Debug, PartialEq)]
pub struct BoundsResult {
    pub bounds: DrawRect,
    pub flip_x: bool,
    pub flip_y: bool,
}

impl BoundsResult {
    pub const fn new(bounds: DrawRect, flip_x: bool, flip_y: bool) -> Self {
        Self {
            bounds,
            flip_x,
            flip_y,
        }
    }
}

/// Parameters for resize bounds calculation.
#[derive(Clone, Copy, Debug, PartialEq)]
pub struct ResizeBoundsParams {
    pub transform_context: EditTransformContext,
    pub mode: ResizeMode,
    pub current_pointer_world: DrawPoint,
    pub handle_offset_local: DrawPoint,
    pub selection_padding: f64,
    pub maintain_aspect_ratio: bool,
    pub resize_from_center: bool,
}

/// Calculates selection bounds during a resize drag.
pub fn calculate_resize_bounds(params: ResizeBoundsParams) -> BoundsResult {
    let ctx = params.transform_context;
    let space = ctx.overlay_space;
    let start_rect = ctx.start_bounds;

    let moving_bound_point_world = ctx
        .transform_pointer_with_offset(params.current_pointer_world, params.handle_offset_local)
        - ctx.get_padding_offset(params.mode, params.selection_padding);

    let anchor_world = ctx.get_anchor_point(params.mode, params.resize_from_center);
    let d_local = rotate_vector_to_local(space, moving_bound_point_world - anchor_world);
    let aspect_ratio = ctx.aspect_ratio();

    let (expected_dx, expected_dy) = expected_anchor_to_moving_direction_local(params.mode);
    let flip_x = !params.resize_from_center
        && expected_dx != 0
        && d_local.x != 0.0
        && axis_sign(d_local.x) != expected_dx;
    let flip_y = !params.resize_from_center
        && expected_dy != 0
        && d_local.y != 0.0
        && axis_sign(d_local.y) != expected_dy;

    let (new_width, new_height, new_center_world) = if params.resize_from_center {
        calculate_from_center_resize(
            params.mode,
            d_local,
            start_rect,
            ctx.center,
            params.maintain_aspect_ratio,
            aspect_ratio,
        )
    } else {
        calculate_from_anchor_resize(
            params.mode,
            d_local,
            start_rect,
            anchor_world,
            space,
            params.maintain_aspect_ratio,
            aspect_ratio,
        )
    };

    BoundsResult::new(
        rect_from_center(new_center_world, new_width, new_height),
        flip_x,
        flip_y,
    )
}

fn calculate_from_center_resize(
    mode: ResizeMode,
    d_local: DrawPoint,
    start_rect: DrawRect,
    start_center_world: DrawPoint,
    maintain_aspect_ratio: bool,
    aspect_ratio: Option<f64>,
) -> (f64, f64, DrawPoint) {
    match mode {
        ResizeMode::TopLeft
        | ResizeMode::TopRight
        | ResizeMode::BottomRight
        | ResizeMode::BottomLeft => {
            let mut half_width = d_local.x.abs();
            let mut half_height = d_local.y.abs();
            if maintain_aspect_ratio {
                if let Some(ratio) = aspect_ratio {
                    (half_width, half_height) =
                        lock_corner_size_to_aspect_ratio(half_width, half_height, ratio);
                }
            }
            (half_width * 2.0, half_height * 2.0, start_center_world)
        }
        ResizeMode::Left | ResizeMode::Right => {
            let width = d_local.x.abs() * 2.0;
            let height = if maintain_aspect_ratio {
                if let Some(ratio) = aspect_ratio {
                    width / ratio
                } else {
                    start_rect.height()
                }
            } else {
                start_rect.height()
            };
            (width, height, start_center_world)
        }
        ResizeMode::Top | ResizeMode::Bottom => {
            let height = d_local.y.abs() * 2.0;
            let width = if maintain_aspect_ratio {
                if let Some(ratio) = aspect_ratio {
                    height * ratio
                } else {
                    start_rect.width()
                }
            } else {
                start_rect.width()
            };
            (width, height, start_center_world)
        }
    }
}

fn calculate_from_anchor_resize(
    mode: ResizeMode,
    d_local: DrawPoint,
    start_rect: DrawRect,
    anchor_world: DrawPoint,
    space: OverlaySpace,
    maintain_aspect_ratio: bool,
    aspect_ratio: Option<f64>,
) -> (f64, f64, DrawPoint) {
    match mode {
        ResizeMode::TopLeft
        | ResizeMode::TopRight
        | ResizeMode::BottomRight
        | ResizeMode::BottomLeft => {
            let mut dx = d_local.x;
            let mut dy = d_local.y;

            if maintain_aspect_ratio {
                if let Some(ratio) = aspect_ratio {
                    let mut abs_width = dx.abs();
                    let mut abs_height = dy.abs();
                    (abs_width, abs_height) =
                        lock_corner_size_to_aspect_ratio(abs_width, abs_height, ratio);
                    dx = with_sign(abs_width, dx);
                    dy = with_sign(abs_height, dy);
                }
            }

            let moving_world = anchor_world + space.rotate_vector_to_world(DrawPoint::new(dx, dy));
            let center_world = midpoint(anchor_world, moving_world);
            (dx.abs(), dy.abs(), center_world)
        }
        ResizeMode::Left | ResizeMode::Right => {
            let dx = d_local.x;
            let moving_world = anchor_world + space.rotate_vector_to_world(DrawPoint::new(dx, 0.0));
            let width = dx.abs();
            let height = if maintain_aspect_ratio {
                if let Some(ratio) = aspect_ratio {
                    width / ratio
                } else {
                    start_rect.height()
                }
            } else {
                start_rect.height()
            };
            (width, height, midpoint(anchor_world, moving_world))
        }
        ResizeMode::Top | ResizeMode::Bottom => {
            let dy = d_local.y;
            let moving_world = anchor_world + space.rotate_vector_to_world(DrawPoint::new(0.0, dy));
            let height = dy.abs();
            let width = if maintain_aspect_ratio {
                if let Some(ratio) = aspect_ratio {
                    height * ratio
                } else {
                    start_rect.width()
                }
            } else {
                start_rect.width()
            };
            (width, height, midpoint(anchor_world, moving_world))
        }
    }
}

fn lock_corner_size_to_aspect_ratio(width: f64, height: f64, aspect_ratio: f64) -> (f64, f64) {
    if height == 0.0 || (width / height) >= aspect_ratio {
        (width, width / aspect_ratio)
    } else {
        (height * aspect_ratio, height)
    }
}

fn with_sign(magnitude: f64, value: f64) -> f64 {
    if value >= 0.0 {
        magnitude
    } else {
        -magnitude
    }
}

fn midpoint(a: DrawPoint, b: DrawPoint) -> DrawPoint {
    DrawPoint::new((a.x + b.x) / 2.0, (a.y + b.y) / 2.0)
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

fn expected_anchor_to_moving_direction_local(mode: ResizeMode) -> (i32, i32) {
    match mode {
        ResizeMode::TopLeft => (-1, -1),
        ResizeMode::TopRight => (1, -1),
        ResizeMode::BottomRight => (1, 1),
        ResizeMode::BottomLeft => (-1, 1),
        ResizeMode::Top => (0, -1),
        ResizeMode::Bottom => (0, 1),
        ResizeMode::Left => (-1, 0),
        ResizeMode::Right => (1, 0),
    }
}

fn axis_sign(value: f64) -> i32 {
    if value > 0.0 {
        1
    } else if value < 0.0 {
        -1
    } else {
        0
    }
}

fn rotate_vector_to_local(space: OverlaySpace, world_vector: DrawPoint) -> DrawPoint {
    rotate_vector(world_vector, -space.rotation)
}

fn rotate_vector(vector: DrawPoint, angle: f64) -> DrawPoint {
    if angle == 0.0 {
        return vector;
    }

    let cos_a = angle.cos();
    let sin_a = angle.sin();
    DrawPoint::new(
        vector.x * cos_a - vector.y * sin_a,
        vector.x * sin_a + vector.y * cos_a,
    )
}
