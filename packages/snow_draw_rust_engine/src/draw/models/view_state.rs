#![allow(dead_code)]

use crate::draw::models::camera_state::CameraState;
use serde::{Deserialize, Serialize};
use std::fmt;

/// View/camera state for the viewport layer.
#[derive(Clone, Copy, Debug, PartialEq, Hash, Serialize, Deserialize)]
pub struct ViewState {
    /// Current camera transform.
    pub camera: CameraState,
}

impl ViewState {
    /// Default view state used for initialization.
    pub const INITIAL: Self = Self::new(CameraState::INITIAL);

    pub const fn new(camera: CameraState) -> Self {
        Self { camera }
    }

    /// Returns a copied state with selected fields replaced.
    pub fn copy_with(self, camera: Option<CameraState>) -> Self {
        Self {
            camera: camera.unwrap_or(self.camera),
        }
    }
}

impl Default for ViewState {
    fn default() -> Self {
        Self::INITIAL
    }
}

impl fmt::Display for ViewState {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        write!(f, "ViewState(camera: {})", self.camera)
    }
}
