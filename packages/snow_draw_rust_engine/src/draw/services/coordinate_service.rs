#![allow(dead_code)]

use crate::draw::models::camera_state::CameraState;
use crate::draw::types::draw_point::DrawPoint;
use std::hash::{Hash, Hasher};

/// Coordinate transformation service.
///
/// Unifies conversions between screen/widget coordinates and world
/// coordinates. World coordinates are what drawing elements use.
#[derive(Clone, Copy, Debug)]
pub struct CoordinateService {
    pub camera: CameraState,
    pub scale_factor: f64,
}

impl CoordinateService {
    /// Creates a new [`CoordinateService`].
    ///
    /// Panics if `scale_factor` is not finite or is less than or equal to zero.
    pub fn new(camera: CameraState, scale_factor: f64) -> Self {
        assert!(
            scale_factor.is_finite() && scale_factor > 0.0,
            "scale_factor must be finite and > 0"
        );

        Self {
            camera,
            scale_factor,
        }
    }

    /// Creates a service from a camera, defaulting `scale_factor` to camera zoom.
    pub fn from_camera(camera: CameraState, scale_factor: Option<f64>) -> Self {
        Self::new(camera, scale_factor.unwrap_or(camera.zoom))
    }

    fn inverse_scale_factor(self) -> f64 {
        1.0 / self.scale_factor
    }

    /// Screen/widget coordinates -> world coordinates.
    pub fn screen_to_world(self, screen_point: DrawPoint) -> DrawPoint {
        DrawPoint::new(
            (screen_point.x - self.camera.position.x) * self.inverse_scale_factor(),
            (screen_point.y - self.camera.position.y) * self.inverse_scale_factor(),
        )
    }

    /// World coordinates -> screen/widget coordinates.
    pub fn world_to_screen(self, world_point: DrawPoint) -> DrawPoint {
        DrawPoint::new(
            world_point.x * self.scale_factor + self.camera.position.x,
            world_point.y * self.scale_factor + self.camera.position.y,
        )
    }

    /// Screen distance -> world distance.
    pub fn screen_distance_to_world(self, screen_distance: f64) -> f64 {
        screen_distance * self.inverse_scale_factor()
    }

    /// World distance -> screen distance.
    pub fn world_distance_to_screen(self, world_distance: f64) -> f64 {
        world_distance * self.scale_factor
    }

    /// Returns a copied service with selected fields replaced.
    pub fn copy_with(self, camera: Option<CameraState>, scale_factor: Option<f64>) -> Self {
        Self::new(
            camera.unwrap_or(self.camera),
            scale_factor.unwrap_or(self.scale_factor),
        )
    }
}

impl PartialEq for CoordinateService {
    fn eq(&self, other: &Self) -> bool {
        self.camera == other.camera && self.scale_factor == other.scale_factor
    }
}

impl Hash for CoordinateService {
    fn hash<H: Hasher>(&self, state: &mut H) {
        self.camera.hash(state);
        self.scale_factor.to_bits().hash(state);
    }
}
