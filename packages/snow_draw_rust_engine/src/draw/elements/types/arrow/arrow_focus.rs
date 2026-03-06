#![allow(dead_code)]

use crate::draw::types::draw_point::DrawPoint;

use super::arrow_binding::ArrowBinding;

/// Lightweight focus snapshot for connector endpoint interactions.
#[derive(Clone, Debug, Default, PartialEq)]
pub struct ArrowFocus {
    pub position: Option<DrawPoint>,
    pub binding: Option<ArrowBinding>,
}
