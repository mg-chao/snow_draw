#![allow(dead_code)]

use crate::draw::types::draw_point::DrawPoint;
use crate::draw::types::draw_rect::DrawRect;

/// Computes geometry for create-drag interactions.
pub struct CreateCalculator;

impl CreateCalculator {
    /// Calculates the rectangle created by dragging from a start position.
    ///
    /// When `maintain_aspect_ratio` is `true`, the created rect is forced to a square.
    /// When `create_from_center` is `true`, drag distance expands symmetrically from
    /// the start position as center.
    pub fn calculate_create_rect(
        start_position: DrawPoint,
        current_position: DrawPoint,
        maintain_aspect_ratio: bool,
        create_from_center: bool,
    ) -> DrawRect {
        let dx = current_position.x - start_position.x;
        let dy = current_position.y - start_position.y;

        if maintain_aspect_ratio {
            let side = dx.abs().max(dy.abs());

            if create_from_center {
                return DrawRect::new(
                    start_position.x - side,
                    start_position.y - side,
                    start_position.x + side,
                    start_position.y + side,
                );
            }

            let end_x = start_position.x + if dx > 0.0 { side } else { -side };
            let end_y = start_position.y + if dy > 0.0 { side } else { -side };
            return DrawRect::new(
                start_position.x.min(end_x),
                start_position.y.min(end_y),
                start_position.x.max(end_x),
                start_position.y.max(end_y),
            );
        }

        if create_from_center {
            return DrawRect::new(
                start_position.x - dx.abs(),
                start_position.y - dy.abs(),
                start_position.x + dx.abs(),
                start_position.y + dy.abs(),
            );
        }

        DrawRect::new(
            start_position.x.min(current_position.x),
            start_position.y.min(current_position.y),
            start_position.x.max(current_position.x),
            start_position.y.max(current_position.y),
        )
    }
}
