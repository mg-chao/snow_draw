#![allow(dead_code)]

use crate::draw::config::draw_config::ConfigDefaults;
use crate::draw::elements::types::connector::connector_points::ConnectorPointKind;
use crate::draw::types::draw_point::DrawPoint;
use crate::draw::types::draw_rect::DrawRect;
use crate::draw::types::resize_mode::ResizeMode;

/// Parameters for edit operations.
///
/// Mirrors the Dart `EditOperationParams` hierarchy using concrete structs
/// wrapped in an enum.
#[derive(Clone, Debug, PartialEq)]
pub enum EditOperationParams {
    Move(MoveOperationParams),
    Resize(ResizeOperationParams),
    Rotate(RotateOperationParams),
    ConnectorPoint(ConnectorPointOperationParams),
}

impl EditOperationParams {
    /// Returns the optional selection bounds captured at operation start.
    pub fn initial_selection_bounds(&self) -> Option<DrawRect> {
        match self {
            Self::Move(params) => params.initial_selection_bounds,
            Self::Resize(params) => params.initial_selection_bounds,
            Self::Rotate(params) => params.initial_selection_bounds,
            Self::ConnectorPoint(params) => params.initial_selection_bounds,
        }
    }

    /// Returns move params when this is a move operation.
    pub fn as_move(&self) -> Option<&MoveOperationParams> {
        let Self::Move(value) = self else {
            return None;
        };
        Some(value)
    }

    /// Returns resize params when this is a resize operation.
    pub fn as_resize(&self) -> Option<&ResizeOperationParams> {
        let Self::Resize(value) = self else {
            return None;
        };
        Some(value)
    }

    /// Returns rotate params when this is a rotate operation.
    pub fn as_rotate(&self) -> Option<&RotateOperationParams> {
        let Self::Rotate(value) = self else {
            return None;
        };
        Some(value)
    }

    /// Returns arrow-point params when this is an arrow-point operation.
    pub fn as_arrow_point(&self) -> Option<&ArrowPointOperationParams> {
        let Self::ConnectorPoint(value) = self else {
            return None;
        };
        Some(value)
    }

    /// Returns connector-point params when this is a connector-point operation.
    pub fn as_connector_point(&self) -> Option<&ConnectorPointOperationParams> {
        self.as_arrow_point()
    }
}

impl From<MoveOperationParams> for EditOperationParams {
    fn from(value: MoveOperationParams) -> Self {
        Self::Move(value)
    }
}

impl From<ResizeOperationParams> for EditOperationParams {
    fn from(value: ResizeOperationParams) -> Self {
        Self::Resize(value)
    }
}

impl From<RotateOperationParams> for EditOperationParams {
    fn from(value: RotateOperationParams) -> Self {
        Self::Rotate(value)
    }
}

impl From<ConnectorPointOperationParams> for EditOperationParams {
    fn from(value: ConnectorPointOperationParams) -> Self {
        Self::ConnectorPoint(value)
    }
}

/// Parameters for move operations.
#[derive(Clone, Copy, Debug, Default, PartialEq)]
pub struct MoveOperationParams {
    pub initial_selection_bounds: Option<DrawRect>,
}

impl MoveOperationParams {
    pub const fn new(initial_selection_bounds: Option<DrawRect>) -> Self {
        Self {
            initial_selection_bounds,
        }
    }
}

/// Parameters for resize operations.
#[derive(Clone, Copy, Debug, PartialEq)]
pub struct ResizeOperationParams {
    pub resize_mode: ResizeMode,
    pub handle_offset: Option<DrawPoint>,
    pub selection_padding: f64,
    pub initial_selection_bounds: Option<DrawRect>,
}

impl ResizeOperationParams {
    /// Creates params with Dart-equivalent defaults for optional fields.
    pub fn new(resize_mode: ResizeMode) -> Self {
        Self::with_options(resize_mode, None, 0.0, None)
    }

    /// Creates params with explicit optional values.
    pub fn with_options(
        resize_mode: ResizeMode,
        handle_offset: Option<DrawPoint>,
        selection_padding: f64,
        initial_selection_bounds: Option<DrawRect>,
    ) -> Self {
        assert!(
            selection_padding >= 0.0,
            "selection_padding must be non-negative"
        );

        Self {
            resize_mode,
            handle_offset,
            selection_padding,
            initial_selection_bounds,
        }
    }
}

/// Parameters for rotate operations.
#[derive(Clone, Copy, Debug, PartialEq)]
pub struct RotateOperationParams {
    pub start_rotation_angle: Option<f64>,
    pub rotation_snap_angle: f64,
    pub initial_selection_bounds: Option<DrawRect>,
}

impl RotateOperationParams {
    /// Creates params with Dart-equivalent defaults.
    pub fn new() -> Self {
        Self::with_options(None, ConfigDefaults::ROTATION_SNAP_ANGLE, None)
    }

    /// Creates params with explicit optional values.
    pub fn with_options(
        start_rotation_angle: Option<f64>,
        rotation_snap_angle: f64,
        initial_selection_bounds: Option<DrawRect>,
    ) -> Self {
        assert!(
            rotation_snap_angle >= 0.0,
            "rotation_snap_angle must be non-negative"
        );

        Self {
            start_rotation_angle,
            rotation_snap_angle,
            initial_selection_bounds,
        }
    }
}

impl Default for RotateOperationParams {
    fn default() -> Self {
        Self::new()
    }
}

/// Parameters for connector-point edit operations.
#[derive(Clone, Debug, PartialEq)]
pub struct ConnectorPointOperationParams {
    pub element_id: String,
    pub point_kind: ConnectorPointKind,
    pub point_index: usize,
    pub is_double_click: bool,
    pub initial_selection_bounds: Option<DrawRect>,
}

pub type ArrowPointOperationParams = ConnectorPointOperationParams;

impl ConnectorPointOperationParams {
    /// Creates params with Dart-equivalent defaults.
    pub fn new(
        element_id: impl Into<String>,
        point_kind: ConnectorPointKind,
        point_index: usize,
    ) -> Self {
        Self::with_options(element_id, point_kind, point_index, false, None)
    }

    /// Creates params with explicit optional values.
    pub fn with_options(
        element_id: impl Into<String>,
        point_kind: ConnectorPointKind,
        point_index: usize,
        is_double_click: bool,
        initial_selection_bounds: Option<DrawRect>,
    ) -> Self {
        let element_id = element_id.into();
        assert!(!element_id.is_empty(), "element_id must not be empty");

        Self {
            element_id,
            point_kind,
            point_index,
            is_double_click,
            initial_selection_bounds,
        }
    }
}
