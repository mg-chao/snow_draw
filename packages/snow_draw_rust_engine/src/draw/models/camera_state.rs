#![allow(dead_code)]

use crate::draw::types::draw_point::DrawPoint;
use serde::{Deserialize, Serialize};
use std::fmt;
use std::hash::{Hash, Hasher};

/// Camera transform state (pan + zoom) for the drawing viewport.
#[derive(Clone, Copy, Debug, Serialize, Deserialize)]
pub struct CameraState {
    /// Camera position in world-space coordinates.
    pub position: DrawPoint,

    /// Camera zoom scale.
    pub zoom: f64,
}

impl CameraState {
    /// Minimum supported zoom value.
    pub const MIN_ZOOM: f64 = 0.1;

    /// Maximum supported zoom value.
    pub const MAX_ZOOM: f64 = 30.0;

    /// Default camera state used on document/load reset.
    pub const INITIAL: Self = Self::new(DrawPoint::ZERO, 1.0);

    pub const fn new(position: DrawPoint, zoom: f64) -> Self {
        Self { position, zoom }
    }

    /// Clamps a zoom value into the valid camera range.
    pub fn clamp_zoom(zoom: f64) -> f64 {
        zoom.clamp(Self::MIN_ZOOM, Self::MAX_ZOOM)
    }

    /// Returns a copied state with selected fields replaced.
    pub fn copy_with(self, position: Option<DrawPoint>, zoom: Option<f64>) -> Self {
        Self {
            position: position.unwrap_or(self.position),
            zoom: zoom.unwrap_or(self.zoom),
        }
    }

    /// Returns a copied state translated by `(dx, dy)`.
    pub fn translated(self, dx: f64, dy: f64) -> Self {
        self.copy_with(
            Some(DrawPoint::new(self.position.x + dx, self.position.y + dy)),
            None,
        )
    }
}

impl Default for CameraState {
    fn default() -> Self {
        Self::INITIAL
    }
}

impl PartialEq for CameraState {
    fn eq(&self, other: &Self) -> bool {
        self.position == other.position && self.zoom == other.zoom
    }
}

impl Hash for CameraState {
    fn hash<H: Hasher>(&self, state: &mut H) {
        self.position.hash(state);
        self.zoom.to_bits().hash(state);
    }
}

impl fmt::Display for CameraState {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        write!(
            f,
            "CameraState(position: {}, zoom: {})",
            self.position, self.zoom
        )
    }
}
