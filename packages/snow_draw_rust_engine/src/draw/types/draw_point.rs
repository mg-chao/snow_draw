#![allow(dead_code)]

use crate::draw::types::draw_rect::DrawRect;
use serde::{Deserialize, Serialize};
use std::fmt;
use std::hash::{Hash, Hasher};
use std::ops::{Add, Div, Mul, Neg, Sub};

/// Immutable 2D point used by draw geometry.
#[derive(Clone, Copy, Debug, Default, Serialize, Deserialize)]
pub struct DrawPoint {
    pub x: f64,
    pub y: f64,

    /// Stylus / pointer pressure in the range `0..=1`.
    pub pressure: f64,

    /// Monotonic timestamp in microseconds.
    pub timestamp: i64,
}

impl DrawPoint {
    pub const ZERO: Self = Self {
        x: 0.0,
        y: 0.0,
        pressure: 0.0,
        timestamp: 0,
    };

    pub const fn new(x: f64, y: f64) -> Self {
        Self {
            x,
            y,
            pressure: 0.0,
            timestamp: 0,
        }
    }

    pub const fn with_pressure_and_timestamp(
        x: f64,
        y: f64,
        pressure: f64,
        timestamp: i64,
    ) -> Self {
        Self {
            x,
            y,
            pressure,
            timestamp,
        }
    }

    pub fn copy_with(
        self,
        x: Option<f64>,
        y: Option<f64>,
        pressure: Option<f64>,
        timestamp: Option<i64>,
    ) -> Self {
        Self {
            x: x.unwrap_or(self.x),
            y: y.unwrap_or(self.y),
            pressure: pressure.unwrap_or(self.pressure),
            timestamp: timestamp.unwrap_or(self.timestamp),
        }
    }

    pub fn translate(self, position: DrawPoint) -> Self {
        self + position
    }

    pub fn has_pressure(self) -> bool {
        self.pressure > 0.0
    }

    pub fn to_tuple(self) -> (f64, f64) {
        (self.x, self.y)
    }

    pub fn to_rect(self, other: DrawPoint) -> DrawRect {
        DrawRect::new(
            self.x.min(other.x),
            self.y.min(other.y),
            self.x.max(other.x),
            self.y.max(other.y),
        )
    }

    /// Computes the Euclidean distance to `other`.
    pub fn distance(self, other: DrawPoint) -> f64 {
        self.distance_squared(other).sqrt()
    }

    /// Computes squared distance to `other` without applying `sqrt`.
    pub fn distance_squared(self, other: DrawPoint) -> f64 {
        let dx = self.x - other.x;
        let dy = self.y - other.y;
        dx * dx + dy * dy
    }
}

impl Add for DrawPoint {
    type Output = DrawPoint;

    fn add(self, rhs: Self) -> Self::Output {
        DrawPoint::new(self.x + rhs.x, self.y + rhs.y)
    }
}

impl Sub for DrawPoint {
    type Output = DrawPoint;

    fn sub(self, rhs: Self) -> Self::Output {
        DrawPoint::new(self.x - rhs.x, self.y - rhs.y)
    }
}

impl Mul<f64> for DrawPoint {
    type Output = DrawPoint;

    fn mul(self, rhs: f64) -> Self::Output {
        DrawPoint::new(self.x * rhs, self.y * rhs)
    }
}

impl Div<f64> for DrawPoint {
    type Output = DrawPoint;

    fn div(self, rhs: f64) -> Self::Output {
        DrawPoint::new(self.x / rhs, self.y / rhs)
    }
}

impl Neg for DrawPoint {
    type Output = DrawPoint;

    fn neg(self) -> Self::Output {
        DrawPoint::new(-self.x, -self.y)
    }
}

impl From<(f64, f64)> for DrawPoint {
    fn from(value: (f64, f64)) -> Self {
        DrawPoint::new(value.0, value.1)
    }
}

impl PartialEq for DrawPoint {
    fn eq(&self, other: &Self) -> bool {
        self.x == other.x && self.y == other.y && self.pressure == other.pressure
    }
}

impl Eq for DrawPoint {}

impl Hash for DrawPoint {
    fn hash<H: Hasher>(&self, state: &mut H) {
        self.x.to_bits().hash(state);
        self.y.to_bits().hash(state);
        self.pressure.to_bits().hash(state);
    }
}

impl fmt::Display for DrawPoint {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        if self.has_pressure() {
            write!(
                f,
                "DrawPoint(x: {}, y: {}, p: {})",
                self.x, self.y, self.pressure
            )
        } else {
            write!(f, "DrawPoint(x: {}, y: {})", self.x, self.y)
        }
    }
}
