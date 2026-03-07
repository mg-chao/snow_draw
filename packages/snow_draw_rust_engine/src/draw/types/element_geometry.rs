#![allow(dead_code)]

use crate::draw::types::draw_point::DrawPoint;
use crate::draw::types::draw_rect::DrawRect;
use serde::{Deserialize, Serialize};

/// Geometry snapshot used by move operations.
#[derive(Clone, Copy, Debug, PartialEq, Serialize, Deserialize)]
pub struct ElementMoveSnapshot {
    pub center: DrawPoint,
}

/// Geometry snapshot used by resize operations.
#[derive(Clone, Copy, Debug, PartialEq, Serialize, Deserialize)]
pub struct ElementResizeSnapshot {
    pub rect: DrawRect,
    pub rotation: f64,
}

impl ElementResizeSnapshot {
    pub fn center(self) -> DrawPoint {
        self.rect.center()
    }

    pub fn width(self) -> f64 {
        self.rect.width()
    }

    pub fn height(self) -> f64 {
        self.rect.height()
    }
}

/// Geometry snapshot used by rotate operations.
#[derive(Clone, Copy, Debug, PartialEq, Serialize, Deserialize)]
pub struct ElementRotateSnapshot {
    pub center: DrawPoint,
    pub rotation: f64,
}
