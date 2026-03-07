#![allow(dead_code)]

use crate::draw::models::camera_state::CameraState;
use crate::draw::types::draw_point::DrawPoint;
use crate::draw::utils::camera_zoom::resolve_effective_zoom;

/// Action payload for panning the camera.
#[derive(Clone, Copy, Debug, PartialEq)]
pub struct MoveCamera {
    pub dx: f64,
    pub dy: f64,
}

impl MoveCamera {
    pub const fn new(dx: f64, dy: f64) -> Self {
        Self { dx, dy }
    }
}

/// Action payload for zooming the camera.
#[derive(Clone, Copy, Debug, PartialEq)]
pub struct ZoomCamera {
    pub scale: f64,
    pub center: Option<DrawPoint>,
}

impl ZoomCamera {
    pub const fn new(scale: f64, center: Option<DrawPoint>) -> Self {
        Self { scale, center }
    }
}

/// Camera reducer action surface.
///
/// The full app-level action enum can be adapted into this shape by mapping
/// only the camera-related variants.
#[derive(Clone, Copy, Debug, PartialEq)]
pub enum DrawAction {
    MoveCamera(MoveCamera),
    ZoomCamera(ZoomCamera),
    Other,
}

impl From<MoveCamera> for DrawAction {
    fn from(value: MoveCamera) -> Self {
        Self::MoveCamera(value)
    }
}

impl From<ZoomCamera> for DrawAction {
    fn from(value: ZoomCamera) -> Self {
        Self::ZoomCamera(value)
    }
}

/// State adapter needed by [`camera_reducer`].
///
/// This keeps camera logic reusable across any state shape that can expose and
/// update camera state.
pub trait CameraReducerState: Clone {
    /// Returns the current camera.
    fn camera_state(&self) -> CameraState;

    /// Returns a copied state with `camera` applied.
    fn with_camera_state(&self, camera: CameraState) -> Self;
}

/// Reduces camera-related actions.
///
/// Returns `Some(next_state)` only when `action` is handled by this reducer.
pub fn camera_reducer<S>(state: &S, action: &DrawAction) -> Option<S>
where
    S: CameraReducerState,
{
    match *action {
        DrawAction::MoveCamera(action) => Some(handle_move_camera(state, action)),
        DrawAction::ZoomCamera(action) => Some(handle_zoom_camera(state, action)),
        DrawAction::Other => None,
    }
}

fn handle_move_camera<S>(state: &S, action: MoveCamera) -> S
where
    S: CameraReducerState,
{
    if action.dx == 0.0 && action.dy == 0.0 {
        return state.clone();
    }

    let next_camera = state.camera_state().translated(action.dx, action.dy);
    state.with_camera_state(next_camera)
}

fn handle_zoom_camera<S>(state: &S, action: ZoomCamera) -> S
where
    S: CameraReducerState,
{
    let camera = state.camera_state();
    let current_zoom = resolve_effective_zoom(camera.zoom);
    let target_zoom = CameraState::clamp_zoom(current_zoom * action.scale);
    if target_zoom == current_zoom {
        return state.clone();
    }

    let center = action.center.unwrap_or(camera.position);
    let zoom_ratio = target_zoom / current_zoom;
    let next_position = DrawPoint::new(
        camera.position.x + (center.x - camera.position.x) * (1.0 - zoom_ratio),
        camera.position.y + (center.y - camera.position.y) * (1.0 - zoom_ratio),
    );

    state.with_camera_state(camera.copy_with(Some(next_position), Some(target_zoom)))
}

#[cfg(test)]
mod tests {
    use super::*;

    #[derive(Clone, Copy, Debug, PartialEq)]
    struct TestDrawState {
        camera: CameraState,
    }

    impl CameraReducerState for TestDrawState {
        fn camera_state(&self) -> CameraState {
            self.camera
        }

        fn with_camera_state(&self, camera: CameraState) -> Self {
            Self { camera }
        }
    }

    #[test]
    fn move_camera_without_delta_returns_same_state() {
        let state = TestDrawState {
            camera: CameraState::new(DrawPoint::new(12.0, 34.0), 1.0),
        };
        let action = DrawAction::MoveCamera(MoveCamera::new(0.0, 0.0));

        let next = camera_reducer(&state, &action).expect("camera actions must be handled");

        assert_eq!(next, state);
    }

    #[test]
    fn move_camera_translates_position() {
        let state = TestDrawState {
            camera: CameraState::new(DrawPoint::new(10.0, -4.0), 1.0),
        };
        let action = DrawAction::MoveCamera(MoveCamera::new(3.0, -2.0));

        let next = camera_reducer(&state, &action).expect("camera actions must be handled");

        assert_eq!(next.camera.position, DrawPoint::new(13.0, -6.0));
        assert_eq!(next.camera.zoom, 1.0);
    }

    #[test]
    fn zoom_camera_keeps_center_anchored() {
        let state = TestDrawState {
            camera: CameraState::new(DrawPoint::new(10.0, 20.0), 1.0),
        };
        let action = DrawAction::ZoomCamera(ZoomCamera::new(2.0, Some(DrawPoint::new(12.0, 24.0))));

        let next = camera_reducer(&state, &action).expect("camera actions must be handled");

        assert_eq!(next.camera.zoom, 2.0);
        assert_eq!(next.camera.position, DrawPoint::new(8.0, 16.0));
    }

    #[test]
    fn zoom_camera_with_unchanged_target_zoom_returns_same_state() {
        let state = TestDrawState {
            camera: CameraState::new(DrawPoint::new(5.0, 7.0), 1.5),
        };
        let action = DrawAction::ZoomCamera(ZoomCamera::new(1.0, None));

        let next = camera_reducer(&state, &action).expect("camera actions must be handled");

        assert_eq!(next, state);
    }

    #[test]
    fn non_camera_action_is_not_handled() {
        let state = TestDrawState {
            camera: CameraState::INITIAL,
        };

        let next = camera_reducer(&state, &DrawAction::Other);

        assert!(next.is_none());
    }
}
