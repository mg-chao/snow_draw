use crate::draw::types::draw_point::DrawPoint;
use crate::draw::types::draw_rect::DrawRect;

/// Cached layout payload for 2-point arrow-like elements.
///
/// `rect` is in world space and `normalized_points` are rect-normalized.
#[derive(Clone, Debug, PartialEq)]
pub struct ArrowTwoPointLayout {
    pub rect: DrawRect,
    pub normalized_points: Vec<DrawPoint>,
}

impl ArrowTwoPointLayout {
    pub fn new(rect: DrawRect, normalized_points: Vec<DrawPoint>) -> Self {
        Self {
            rect,
            normalized_points,
        }
    }
}

/// Computes rect + normalized points for a 2-point arrow fast path.
///
/// This avoids the generic multi-point path bounds/normalization pipeline
/// during high-frequency create/edit updates.
pub fn compute_arrow_two_point_layout(first: DrawPoint, second: DrawPoint) -> ArrowTwoPointLayout {
    let rect = first.to_rect(second);
    let width = rect.width();
    let height = rect.height();

    let normalize_x = |x: f64| -> f64 {
        if width == 0.0 {
            0.0
        } else {
            (x - rect.min_x) / width
        }
    };
    let normalize_y = |y: f64| -> f64 {
        if height == 0.0 {
            0.0
        } else {
            (y - rect.min_y) / height
        }
    };

    ArrowTwoPointLayout::new(
        rect,
        vec![
            DrawPoint {
                x: normalize_x(first.x),
                y: normalize_y(first.y),
                pressure: first.pressure,
                timestamp: first.timestamp,
            },
            DrawPoint {
                x: normalize_x(second.x),
                y: normalize_y(second.y),
                pressure: second.pressure,
                timestamp: second.timestamp,
            },
        ],
    )
}
