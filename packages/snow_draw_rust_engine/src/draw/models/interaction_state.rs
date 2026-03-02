#![allow(dead_code)]

use std::any::Any;
use std::fmt;
use std::sync::Arc;

use crate::draw::elements::core::element_data::ElementData;
use crate::draw::elements::types::text::text_data::TextData;
use crate::draw::models::edit_session_id::EditSessionId;
use crate::draw::models::element_state::ElementState;
use crate::draw::types::draw_point::DrawPoint;
use crate::draw::types::draw_rect::DrawRect;
use crate::draw::types::edit_context::EditContext;
use crate::draw::types::edit_operation_id::EditOperationId;
use crate::draw::types::edit_transform::EditTransform;
use crate::draw::types::snap_guides::SnapGuide;
use crate::draw::utils::list_equality::point_list_equals;

/// Stable interaction state for pointer/keyboard workflows.
#[derive(Clone, Debug, PartialEq)]
pub enum InteractionState {
    Idle(IdleState),
    DragPending(DragPendingState),
    Editing(EditingState),
    Creating(CreatingState),
    BoxSelecting(BoxSelectingState),
    TextEditing(TextEditingState),
}

impl Default for InteractionState {
    fn default() -> Self {
        Self::Idle(IdleState)
    }
}

/// Pending drag intent captured on pointer-down before movement threshold.
#[derive(Clone, Debug, PartialEq, Eq, Hash)]
pub enum PendingIntent {
    Select(PendingSelectIntent),
    Move(PendingMoveIntent),
}

impl From<PendingSelectIntent> for PendingIntent {
    fn from(value: PendingSelectIntent) -> Self {
        Self::Select(value)
    }
}

impl From<PendingMoveIntent> for PendingIntent {
    fn from(value: PendingMoveIntent) -> Self {
        Self::Move(value)
    }
}

/// Pending select intent.
#[derive(Clone, Debug, PartialEq, Eq, Hash)]
pub struct PendingSelectIntent {
    pub element_id: String,
    pub add_to_selection: bool,
}

impl PendingSelectIntent {
    pub fn new(element_id: impl Into<String>, add_to_selection: bool) -> Self {
        Self {
            element_id: element_id.into(),
            add_to_selection,
        }
    }
}

/// Pending move intent.
#[derive(Clone, Copy, Debug, Default, PartialEq, Eq, Hash)]
pub struct PendingMoveIntent;

/// Idle interaction state.
#[derive(Clone, Copy, Debug, Default, PartialEq, Eq, Hash)]
pub struct IdleState;

/// Drag state that has not yet crossed the drag threshold.
#[derive(Clone, Debug, PartialEq)]
pub struct DragPendingState {
    pub pointer_down_position: DrawPoint,
    pub intent: PendingIntent,
}

impl DragPendingState {
    pub fn new(pointer_down_position: DrawPoint, intent: PendingIntent) -> Self {
        Self {
            pointer_down_position,
            intent,
        }
    }
}

/// Active edit session state.
#[derive(Clone, Debug)]
pub struct EditingState {
    /// Stable id of the running edit operation.
    pub operation_id: EditOperationId,
    /// Stable id of the edit session stored in the owning store.
    pub session_id: EditSessionId,
    /// Immutable edit context captured at edit start.
    pub context: EditContext,
    /// Mutable part of an edit session (current delta/position/angle).
    pub current_transform: EditTransform,
    pub snap_guides: Vec<SnapGuide>,
}

impl PartialEq for EditingState {
    fn eq(&self, other: &Self) -> bool {
        self.operation_id == other.operation_id
            && self.session_id == other.session_id
            && self.context.start_position == other.context.start_position
            && self.context.start_bounds == other.context.start_bounds
            && self.context.selected_ids_at_start == other.context.selected_ids_at_start
            && self.context.selection_version == other.context.selection_version
            && self.context.elements_version == other.context.elements_version
            && self.current_transform == other.current_transform
            && self.snap_guides == other.snap_guides
    }
}

impl EditingState {
    pub fn new(
        operation_id: EditOperationId,
        session_id: EditSessionId,
        context: EditContext,
        current_transform: EditTransform,
        snap_guides: Vec<SnapGuide>,
    ) -> Self {
        Self {
            operation_id,
            session_id,
            context,
            current_transform,
            snap_guides,
        }
    }

    pub fn with_transform(&self, transform: EditTransform, guides: Option<Vec<SnapGuide>>) -> Self {
        Self {
            operation_id: self.operation_id,
            session_id: self.session_id.clone(),
            context: self.context.clone(),
            current_transform: transform,
            snap_guides: guides.unwrap_or_else(|| self.snap_guides.clone()),
        }
    }

    /// Current (in-progress) applied rotation delta in radians.
    pub fn rotation_delta(&self) -> f64 {
        Self::rotation_delta_for(&self.current_transform)
    }

    fn rotation_delta_for(transform: &EditTransform) -> f64 {
        match transform {
            EditTransform::Rotate(rotate) => rotate.applied_angle,
            _ => 0.0,
        }
    }
}

/// Discriminator for creation mode within [`CreatingState`].
#[derive(Clone, Debug, PartialEq)]
pub enum CreationMode {
    Rect(RectCreationMode),
    Point(PointCreationMode),
}

impl Default for CreationMode {
    fn default() -> Self {
        Self::Rect(RectCreationMode)
    }
}

/// Rect-based creation mode (default for rectangles, text, etc.).
#[derive(Clone, Copy, Debug, Default, PartialEq, Eq, Hash)]
pub struct RectCreationMode;

/// Point-based creation mode (for arrows).
#[derive(Clone, Default)]
pub struct PointCreationMode {
    /// Fixed turning points in world coordinates.
    pub fixed_points: Vec<DrawPoint>,
    /// Current (preview) point in world coordinates.
    pub current_point: Option<DrawPoint>,
    /// Optional transient session payload.
    ///
    /// This is intentionally excluded from equality so reducers can attach
    /// mutable caches without forcing state churn.
    pub session_data: Option<Arc<dyn Any + Send + Sync>>,
}

impl PointCreationMode {
    pub fn new(
        fixed_points: Vec<DrawPoint>,
        current_point: Option<DrawPoint>,
        session_data: Option<Arc<dyn Any + Send + Sync>>,
    ) -> Self {
        Self {
            fixed_points,
            current_point,
            session_data,
        }
    }
}

impl PartialEq for PointCreationMode {
    fn eq(&self, other: &Self) -> bool {
        point_list_equals(&self.fixed_points, &other.fixed_points)
            && self.current_point == other.current_point
    }
}

impl fmt::Debug for PointCreationMode {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        f.debug_struct("PointCreationMode")
            .field("fixed_points_len", &self.fixed_points.len())
            .field("current_point", &self.current_point)
            .field("has_session_data", &self.session_data.is_some())
            .finish()
    }
}

/// In-progress element creation state.
#[derive(Clone, Debug, PartialEq)]
pub struct CreatingState {
    /// Draft element used while creating (not persisted until finish).
    pub element: ElementState,
    pub start_position: DrawPoint,
    pub current_rect: DrawRect,
    pub snap_guides: Vec<SnapGuide>,
    pub creation_mode: CreationMode,
}

impl CreatingState {
    pub fn new(
        element: ElementState,
        start_position: DrawPoint,
        current_rect: DrawRect,
        snap_guides: Vec<SnapGuide>,
        creation_mode: CreationMode,
    ) -> Self {
        Self {
            element,
            start_position,
            current_rect,
            snap_guides,
            creation_mode,
        }
    }

    /// Stable element id used while creating (not yet in the document).
    pub fn element_id(&self) -> &str {
        &self.element.id
    }

    /// Draft element data (UI-only, not persisted until creation finishes).
    pub fn element_data(&self) -> Arc<dyn ElementData> {
        Arc::clone(&self.element.data)
    }

    /// Draft element rect captured at creation start.
    pub fn element_rect(&self) -> DrawRect {
        self.element.rect
    }

    pub fn element_rotation(&self) -> f64 {
        self.element.rotation
    }

    pub fn element_opacity(&self) -> f64 {
        self.element.opacity
    }

    pub fn element_z_index(&self) -> i64 {
        self.element.z_index
    }

    /// Fixed points for point-based creation (arrows).
    pub fn fixed_points(&self) -> &[DrawPoint] {
        match &self.creation_mode {
            CreationMode::Point(mode) => &mode.fixed_points,
            CreationMode::Rect(_) => &[],
        }
    }

    /// Current preview point for point-based creation.
    pub fn current_point(&self) -> Option<DrawPoint> {
        match &self.creation_mode {
            CreationMode::Point(mode) => mode.current_point,
            CreationMode::Rect(_) => None,
        }
    }

    /// Whether this is a point-based creation (arrow-like workflow).
    pub fn is_point_creation(&self) -> bool {
        matches!(self.creation_mode, CreationMode::Point(_))
    }

    pub fn copy_with(
        &self,
        element: Option<ElementState>,
        start_position: Option<DrawPoint>,
        current_rect: Option<DrawRect>,
        snap_guides: Option<Vec<SnapGuide>>,
        creation_mode: Option<CreationMode>,
    ) -> Self {
        Self {
            element: element.unwrap_or_else(|| self.element.clone()),
            start_position: start_position.unwrap_or(self.start_position),
            current_rect: current_rect.unwrap_or(self.current_rect),
            snap_guides: snap_guides.unwrap_or_else(|| self.snap_guides.clone()),
            creation_mode: creation_mode.unwrap_or_else(|| self.creation_mode.clone()),
        }
    }
}

/// Drag-box selection interaction state.
#[derive(Clone, Copy, Debug, PartialEq)]
pub struct BoxSelectingState {
    pub start_position: DrawPoint,
    pub current_position: DrawPoint,
}

impl BoxSelectingState {
    pub fn new(start_position: DrawPoint, current_position: DrawPoint) -> Self {
        Self {
            start_position,
            current_position,
        }
    }

    pub fn copy_with(
        &self,
        start_position: Option<DrawPoint>,
        current_position: Option<DrawPoint>,
    ) -> Self {
        Self {
            start_position: start_position.unwrap_or(self.start_position),
            current_position: current_position.unwrap_or(self.current_position),
        }
    }

    pub fn bounds(&self) -> DrawRect {
        DrawRect::new(
            self.start_position.x.min(self.current_position.x),
            self.start_position.y.min(self.current_position.y),
            self.start_position.x.max(self.current_position.x),
            self.start_position.y.max(self.current_position.y),
        )
    }
}

/// Text editing interaction state.
#[derive(Clone, Debug, PartialEq)]
pub struct TextEditingState {
    pub element_id: String,
    pub draft_data: TextData,
    pub rect: DrawRect,
    pub is_new: bool,
    pub opacity: f64,
    pub rotation: f64,
    pub initial_cursor_position: Option<DrawPoint>,
}

impl TextEditingState {
    #[allow(clippy::too_many_arguments)]
    pub fn new(
        element_id: impl Into<String>,
        draft_data: TextData,
        rect: DrawRect,
        is_new: bool,
        opacity: f64,
        rotation: f64,
        initial_cursor_position: Option<DrawPoint>,
    ) -> Self {
        Self {
            element_id: element_id.into(),
            draft_data,
            rect,
            is_new,
            opacity,
            rotation,
            initial_cursor_position,
        }
    }

    pub fn copy_with(
        &self,
        draft_data: Option<TextData>,
        rect: Option<DrawRect>,
        is_new: Option<bool>,
        opacity: Option<f64>,
        rotation: Option<f64>,
        initial_cursor_position: Option<DrawPoint>,
    ) -> Self {
        Self {
            element_id: self.element_id.clone(),
            draft_data: draft_data.unwrap_or_else(|| self.draft_data.clone()),
            rect: rect.unwrap_or(self.rect),
            is_new: is_new.unwrap_or(self.is_new),
            opacity: opacity.unwrap_or(self.opacity),
            rotation: rotation.unwrap_or(self.rotation),
            initial_cursor_position: initial_cursor_position.or(self.initial_cursor_position),
        }
    }
}
