#![allow(dead_code)]

use crate::draw::types::draw_point::DrawPoint;

/// Render-ready connector shaft primitives.
#[derive(Clone, Debug, Default, PartialEq)]
pub struct ArrowRenderPrimitives {
    pub shaft_points: Vec<DrawPoint>,
}
