#![allow(dead_code)]

use crate::draw::types::draw_point::DrawPoint;
use serde::{Deserialize, Serialize};
use std::fmt;

/// Axis-aligned rectangle in world space.
#[derive(Clone, Copy, Debug, Default, PartialEq, Serialize, Deserialize)]
pub struct DrawRect {
    pub min_x: f64,
    pub min_y: f64,
    pub max_x: f64,
    pub max_y: f64,
}

impl DrawRect {
    pub const fn new(min_x: f64, min_y: f64, max_x: f64, max_y: f64) -> Self {
        Self {
            min_x,
            min_y,
            max_x,
            max_y,
        }
    }

    pub fn from_points(a: DrawPoint, b: DrawPoint) -> Self {
        Self::new(a.x.min(b.x), a.y.min(b.y), a.x.max(b.x), a.y.max(b.y))
    }

    pub fn from_ltwh(left: f64, top: f64, width: f64, height: f64) -> Self {
        Self::new(left, top, left + width, top + height)
    }

    pub fn from_point(point: DrawPoint) -> Self {
        Self::from_points(point, point)
    }

    pub fn from_point_cloud(points: impl IntoIterator<Item = DrawPoint>) -> Self {
        let mut iter = points.into_iter();
        let Some(first) = iter.next() else {
            return Self::default();
        };

        let mut min_x = first.x;
        let mut min_y = first.y;
        let mut max_x = first.x;
        let mut max_y = first.y;

        for p in iter {
            min_x = min_x.min(p.x);
            min_y = min_y.min(p.y);
            max_x = max_x.max(p.x);
            max_y = max_y.max(p.y);
        }

        Self::new(min_x, min_y, max_x, max_y)
    }

    pub fn width(self) -> f64 {
        self.max_x - self.min_x
    }

    pub fn height(self) -> f64 {
        self.max_y - self.min_y
    }

    pub fn center_x(self) -> f64 {
        (self.min_x + self.max_x) / 2.0
    }

    pub fn center_y(self) -> f64 {
        (self.min_y + self.max_y) / 2.0
    }

    pub fn center(self) -> DrawPoint {
        DrawPoint::new(self.center_x(), self.center_y())
    }

    pub fn copy_with(
        self,
        min_x: Option<f64>,
        min_y: Option<f64>,
        max_x: Option<f64>,
        max_y: Option<f64>,
    ) -> Self {
        Self::new(
            min_x.unwrap_or(self.min_x),
            min_y.unwrap_or(self.min_y),
            max_x.unwrap_or(self.max_x),
            max_y.unwrap_or(self.max_y),
        )
    }

    pub fn translate(self, position: DrawPoint) -> Self {
        Self::new(
            self.min_x + position.x,
            self.min_y + position.y,
            self.max_x + position.x,
            self.max_y + position.y,
        )
    }

    pub fn expand_to_include(self, point: DrawPoint) -> Self {
        Self::new(
            self.min_x.min(point.x),
            self.min_y.min(point.y),
            self.max_x.max(point.x),
            self.max_y.max(point.y),
        )
    }

    pub fn expand_to_include_all(self, points: impl IntoIterator<Item = DrawPoint>) -> Self {
        points
            .into_iter()
            .fold(self, |acc, p| acc.expand_to_include(p))
    }

    pub fn contains_point(self, point: DrawPoint) -> bool {
        point.x >= self.min_x
            && point.x <= self.max_x
            && point.y >= self.min_y
            && point.y <= self.max_y
    }
}

impl fmt::Display for DrawRect {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        write!(
            f,
            "DrawRect(minX: {}, minY: {}, maxX: {}, maxY: {})",
            self.min_x, self.min_y, self.max_x, self.max_y
        )
    }
}
