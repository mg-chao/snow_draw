#![allow(dead_code)]

use crate::draw::models::camera_state::CameraState;

use super::render_tasks::FrameRenderTask;

/// Immutable frame-level rendering plan produced by the engine.
#[derive(Clone, Debug, PartialEq)]
pub struct FrameRenderPlan {
    /// Ordered frame tasks to execute for the frame.
    pub tasks: Vec<FrameRenderTask>,
    /// Camera transform snapshot.
    pub camera: CameraState,
    /// Effective scale factor used for world/canvas transforms.
    pub scale_factor: f64,
    /// Optional locale hint for text layout/rendering.
    pub locale_tag: Option<String>,
}

impl FrameRenderPlan {
    pub fn new(
        tasks: Vec<FrameRenderTask>,
        camera: CameraState,
        scale_factor: f64,
        locale_tag: Option<String>,
    ) -> Self {
        Self {
            tasks,
            camera,
            scale_factor,
            locale_tag,
        }
    }

    pub fn empty() -> Self {
        Self::new(Vec::new(), CameraState::INITIAL, 1.0, None)
    }
}

impl Default for FrameRenderPlan {
    fn default() -> Self {
        Self::empty()
    }
}
