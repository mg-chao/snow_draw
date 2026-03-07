#![allow(dead_code)]

use std::any::Any;
use std::fmt;
use std::sync::Arc;

use crate::draw::config::highlight_config::HighlightMaskConfig;
use crate::draw::config::watermark_config::WatermarkConfig;
use crate::draw::edit::core::edit_cancel_reason::EditCancelReason;
use crate::draw::edit::core::edit_modifiers::EditModifiers;
use crate::draw::edit::core::edit_operation_params::EditOperationParams;
use crate::draw::elements::core::element_data::{DynElementData, ElementData, ElementTypeId};
use crate::draw::history::history_metadata::{
    HistoryMetadata, HistoryRecordType as MetadataHistoryRecordType,
};
use crate::draw::history::recordable::{HistoryRecordType, Recordable};
use crate::draw::models::interaction_state::PendingIntent;
use crate::draw::types::draw_color::DrawColor;
use crate::draw::types::draw_point::DrawPoint;
use crate::draw::types::draw_rect::DrawRect;
use crate::draw::types::edit_operation_id::EditOperationId;
use crate::draw::types::element_style::{
    ArrowType, ArrowheadStyle, CanvasFilterType, ElementStyleUpdate, FillStyle, HighlightShape,
    StrokeStyle, TextHorizontalAlign, TextVerticalAlign,
};

use super::history_coalescing::{HistoryCoalescing, HistoryCoalescingProvider};
use super::history_policy::{HistoryPolicy, HistoryPolicyProvider};

/// Importance level used by input and dispatch middleware.
#[derive(Clone, Copy, Debug, Default, PartialEq, Eq, Hash)]
pub enum ActionCriticality {
    Critical,
    #[default]
    Important,
    Optional,
}

/// Common action metadata used by reducer/middleware pipelines.
pub trait DrawAction:
    Any + Send + Sync + HistoryPolicyProvider + HistoryCoalescingProvider
{
    /// Runtime downcast hook used by store middleware and reducer routing.
    fn as_any(&self) -> &dyn Any;

    /// Human-readable action name used by diagnostics and events.
    fn action_name(&self) -> &'static str {
        let type_name = std::any::type_name::<Self>();
        type_name.rsplit("::").next().unwrap_or(type_name)
    }

    /// Importance hint for scheduler/middleware layers.
    fn criticality(&self) -> ActionCriticality {
        ActionCriticality::Important
    }

    /// Whether this action should cancel an active edit session.
    fn conflicts_with_editing(&self) -> bool {
        false
    }
}

macro_rules! impl_draw_action_default {
    ($ty:ty) => {
        impl HistoryPolicyProvider for $ty {
            fn history_policy(&self) -> HistoryPolicy {
                HistoryPolicy::None
            }
        }
        impl HistoryCoalescingProvider for $ty {}
        impl DrawAction for $ty {
            fn as_any(&self) -> &dyn Any {
                self
            }
        }
    };
}

macro_rules! impl_draw_action_editing_conflict {
    ($ty:ty) => {
        impl HistoryPolicyProvider for $ty {
            fn history_policy(&self) -> HistoryPolicy {
                HistoryPolicy::None
            }
        }
        impl HistoryCoalescingProvider for $ty {}
        impl DrawAction for $ty {
            fn as_any(&self) -> &dyn Any {
                self
            }

            fn conflicts_with_editing(&self) -> bool {
                true
            }
        }
    };
}

macro_rules! impl_draw_action_history_recording {
    ($ty:ty) => {
        impl HistoryPolicyProvider for $ty {
            fn history_policy(&self) -> HistoryPolicy {
                HistoryPolicy::Record
            }
        }
        impl HistoryCoalescingProvider for $ty {}
        impl DrawAction for $ty {
            fn as_any(&self) -> &dyn Any {
                self
            }
        }
    };
}

macro_rules! impl_draw_action_conflict_history_recording {
    ($ty:ty) => {
        impl HistoryPolicyProvider for $ty {
            fn history_policy(&self) -> HistoryPolicy {
                HistoryPolicy::Record
            }
        }
        impl HistoryCoalescingProvider for $ty {}
        impl DrawAction for $ty {
            fn as_any(&self) -> &dyn Any {
                self
            }

            fn conflicts_with_editing(&self) -> bool {
                true
            }
        }
    };
}

#[derive(Clone, Debug, PartialEq)]
pub struct SelectElement {
    pub element_id: String,
    pub add_to_selection: bool,
    pub position: DrawPoint,
}

impl SelectElement {
    pub fn new(element_id: impl Into<String>, position: DrawPoint, add_to_selection: bool) -> Self {
        Self {
            element_id: element_id.into(),
            add_to_selection,
            position,
        }
    }
}

impl_draw_action_editing_conflict!(SelectElement);

#[derive(Clone, Copy, Debug, Default, PartialEq, Eq, Hash)]
pub struct ClearSelection;
impl_draw_action_editing_conflict!(ClearSelection);

#[derive(Clone, Copy, Debug, Default, PartialEq, Eq, Hash)]
pub struct SelectAll;
impl_draw_action_editing_conflict!(SelectAll);

#[derive(Clone)]
pub struct CreateElement {
    pub type_id: ElementTypeId<DynElementData>,
    pub initial_data: Option<Arc<dyn ElementData>>,
    pub position: DrawPoint,
    pub maintain_aspect_ratio: bool,
    pub create_from_center: bool,
    pub snap_override: bool,
}

impl CreateElement {
    #[allow(clippy::too_many_arguments)]
    pub fn new(
        type_id: ElementTypeId<DynElementData>,
        position: DrawPoint,
        initial_data: Option<Arc<dyn ElementData>>,
        maintain_aspect_ratio: bool,
        create_from_center: bool,
        snap_override: bool,
    ) -> Self {
        Self {
            type_id,
            initial_data,
            position,
            maintain_aspect_ratio,
            create_from_center,
            snap_override,
        }
    }
}

impl fmt::Debug for CreateElement {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        f.debug_struct("CreateElement")
            .field("type_id", &self.type_id.as_str())
            .field("has_initial_data", &self.initial_data.is_some())
            .field("position", &self.position)
            .field("maintain_aspect_ratio", &self.maintain_aspect_ratio)
            .field("create_from_center", &self.create_from_center)
            .field("snap_override", &self.snap_override)
            .finish()
    }
}

impl_draw_action_editing_conflict!(CreateElement);

#[derive(Clone, Debug, PartialEq)]
pub struct UpdateCreatingElement {
    pub positions: Vec<DrawPoint>,
    pub maintain_aspect_ratio: bool,
    pub create_from_center: bool,
    pub snap_override: bool,
}

impl UpdateCreatingElement {
    pub fn new(
        positions: Vec<DrawPoint>,
        maintain_aspect_ratio: bool,
        create_from_center: bool,
        snap_override: bool,
    ) -> Self {
        assert!(
            !positions.is_empty(),
            "UpdateCreatingElement.positions must not be empty"
        );
        Self {
            positions,
            maintain_aspect_ratio,
            create_from_center,
            snap_override,
        }
    }

    pub fn current_position(&self) -> DrawPoint {
        *self
            .positions
            .last()
            .expect("positions is guaranteed non-empty")
    }

    pub fn is_batch(&self) -> bool {
        self.positions.len() > 1
    }
}

impl_draw_action_editing_conflict!(UpdateCreatingElement);

#[derive(Clone, Copy, Debug, PartialEq)]
pub struct AddConnectorPoint {
    pub position: DrawPoint,
    pub snap_override: bool,
}

impl AddConnectorPoint {
    pub const fn new(position: DrawPoint, snap_override: bool) -> Self {
        Self {
            position,
            snap_override,
        }
    }
}

impl_draw_action_editing_conflict!(AddConnectorPoint);

pub type AddArrowPoint = AddConnectorPoint;

#[derive(Clone, Copy, Debug, Default, PartialEq, Eq, Hash)]
pub struct FinishCreateElement;
impl_draw_action_conflict_history_recording!(FinishCreateElement);

#[derive(Clone, Copy, Debug, Default, PartialEq, Eq, Hash)]
pub struct CancelCreateElement;
impl_draw_action_editing_conflict!(CancelCreateElement);

#[derive(Clone, Debug, PartialEq, Eq, Hash)]
pub struct DeleteElements {
    pub element_ids: Vec<String>,
}

impl DeleteElements {
    pub fn new(element_ids: Vec<String>) -> Self {
        Self { element_ids }
    }
}

impl_draw_action_conflict_history_recording!(DeleteElements);

#[derive(Clone, Debug, PartialEq)]
pub struct DuplicateElements {
    pub element_ids: Vec<String>,
    pub offset_x: f64,
    pub offset_y: f64,
}

impl DuplicateElements {
    pub fn new(element_ids: Vec<String>, offset_x: f64, offset_y: f64) -> Self {
        Self {
            element_ids,
            offset_x,
            offset_y,
        }
    }
}

impl_draw_action_conflict_history_recording!(DuplicateElements);

#[derive(Clone, Copy, Debug, PartialEq, Eq, Hash)]
pub enum ZIndexOperation {
    BringToFront,
    SendToBack,
    BringForward,
    SendBackward,
}

#[derive(Clone, Debug, PartialEq, Eq, Hash)]
pub struct ChangeElementZIndex {
    pub element_id: String,
    pub operation: ZIndexOperation,
}

impl ChangeElementZIndex {
    pub fn new(element_id: impl Into<String>, operation: ZIndexOperation) -> Self {
        Self {
            element_id: element_id.into(),
            operation,
        }
    }
}

impl_draw_action_conflict_history_recording!(ChangeElementZIndex);

#[derive(Clone, Debug, PartialEq, Eq, Hash)]
pub struct ChangeElementsZIndex {
    pub element_ids: Vec<String>,
    pub operation: ZIndexOperation,
}

impl ChangeElementsZIndex {
    pub fn new(element_ids: Vec<String>, operation: ZIndexOperation) -> Self {
        Self {
            element_ids,
            operation,
        }
    }
}

impl_draw_action_conflict_history_recording!(ChangeElementsZIndex);

#[derive(Clone, Debug, PartialEq)]
pub struct UpdateElementsStyle {
    pub element_ids: Vec<String>,
    pub color: Option<DrawColor>,
    pub fill_color: Option<DrawColor>,
    pub stroke_width: Option<f64>,
    pub stroke_style: Option<StrokeStyle>,
    pub fill_style: Option<FillStyle>,
    pub filter_type: Option<CanvasFilterType>,
    pub filter_strength: Option<f64>,
    pub corner_radius: Option<f64>,
    pub arrow_type: Option<ArrowType>,
    pub start_arrowhead: Option<ArrowheadStyle>,
    pub end_arrowhead: Option<ArrowheadStyle>,
    pub font_size: Option<f64>,
    pub font_family: Option<String>,
    pub text_align: Option<TextHorizontalAlign>,
    pub vertical_align: Option<TextVerticalAlign>,
    pub opacity: Option<f64>,
    pub text_stroke_color: Option<DrawColor>,
    pub text_stroke_width: Option<f64>,
    pub highlight_shape: Option<HighlightShape>,
    pub serial_number: Option<i64>,
    pub history_coalescing: Option<HistoryCoalescing>,
}

impl UpdateElementsStyle {
    pub fn style_update(&self) -> ElementStyleUpdate {
        ElementStyleUpdate {
            color: self.color,
            fill_color: self.fill_color,
            stroke_width: self.stroke_width,
            stroke_style: self.stroke_style,
            fill_style: self.fill_style,
            highlight_shape: self.highlight_shape,
            filter_type: self.filter_type,
            filter_strength: self.filter_strength,
            corner_radius: self.corner_radius,
            arrow_type: self.arrow_type,
            start_arrowhead: self.start_arrowhead,
            end_arrowhead: self.end_arrowhead,
            font_size: self.font_size,
            font_family: self.font_family.clone(),
            text_align: self.text_align,
            vertical_align: self.vertical_align,
            text_stroke_color: self.text_stroke_color,
            text_stroke_width: self.text_stroke_width,
            serial_number: self.serial_number,
        }
    }

    pub fn has_style_updates(&self) -> bool {
        !self.style_update().is_empty()
    }

    pub fn has_updates(&self) -> bool {
        self.has_style_updates() || self.opacity.is_some()
    }
}

impl HistoryPolicyProvider for UpdateElementsStyle {
    fn history_policy(&self) -> HistoryPolicy {
        HistoryPolicy::Record
    }
}

impl HistoryCoalescingProvider for UpdateElementsStyle {
    fn history_coalescing(&self) -> Option<&HistoryCoalescing> {
        self.history_coalescing.as_ref()
    }
}

impl DrawAction for UpdateElementsStyle {
    fn as_any(&self) -> &dyn Any {
        self
    }

    fn conflicts_with_editing(&self) -> bool {
        true
    }
}

#[derive(Clone, Debug, PartialEq)]
pub struct UpdateGlobalElements {
    pub highlight_mask: Option<HighlightMaskConfig>,
    pub watermark: Option<WatermarkConfig>,
    pub history_coalescing: Option<HistoryCoalescing>,
}

impl UpdateGlobalElements {
    pub fn has_updates(&self) -> bool {
        self.highlight_mask.is_some() || self.watermark.is_some()
    }
}

impl HistoryPolicyProvider for UpdateGlobalElements {
    fn history_policy(&self) -> HistoryPolicy {
        HistoryPolicy::Record
    }
}

impl HistoryCoalescingProvider for UpdateGlobalElements {
    fn history_coalescing(&self) -> Option<&HistoryCoalescing> {
        self.history_coalescing.as_ref()
    }
}

impl DrawAction for UpdateGlobalElements {
    fn as_any(&self) -> &dyn Any {
        self
    }

    fn conflicts_with_editing(&self) -> bool {
        true
    }
}

impl Recordable for UpdateGlobalElements {
    fn history_description(&self) -> String {
        let has_highlight_mask = self.highlight_mask.is_some();
        let has_watermark = self.watermark.is_some();

        if has_highlight_mask && !has_watermark {
            "Update highlight mask".to_string()
        } else if has_watermark && !has_highlight_mask {
            "Update watermark".to_string()
        } else {
            "Update global overlays".to_string()
        }
    }

    fn record_type(&self) -> HistoryRecordType {
        HistoryRecordType::Edit
    }
}

#[derive(Clone, Debug, PartialEq, Eq, Hash)]
pub struct CreateSerialNumberTextElements {
    pub element_ids: Vec<String>,
}

impl CreateSerialNumberTextElements {
    pub fn new(element_ids: Vec<String>) -> Self {
        Self { element_ids }
    }
}

impl_draw_action_conflict_history_recording!(CreateSerialNumberTextElements);

impl Recordable for CreateSerialNumberTextElements {
    fn history_description(&self) -> String {
        "Create serial number text".to_string()
    }

    fn record_type(&self) -> HistoryRecordType {
        HistoryRecordType::Create
    }
}

#[derive(Clone, Debug, PartialEq)]
pub struct StartTextEdit {
    pub element_id: Option<String>,
    pub position: DrawPoint,
}

impl StartTextEdit {
    pub fn new(position: DrawPoint, element_id: Option<String>) -> Self {
        Self {
            element_id,
            position,
        }
    }
}

impl_draw_action_editing_conflict!(StartTextEdit);

#[derive(Clone, Debug, PartialEq)]
pub struct UpdateTextEdit {
    pub text: String,
    pub rect: Option<DrawRect>,
}

impl UpdateTextEdit {
    pub fn new(text: impl Into<String>, rect: Option<DrawRect>) -> Self {
        Self {
            text: text.into(),
            rect,
        }
    }
}

impl_draw_action_default!(UpdateTextEdit);

#[derive(Clone, Copy, Debug, Default, PartialEq, Eq, Hash)]
pub struct RefreshAutoResizeTextLayoutsAfterFontLoad;
impl_draw_action_default!(RefreshAutoResizeTextLayoutsAfterFontLoad);

#[derive(Clone, Debug, PartialEq, Eq, Hash)]
pub struct FinishTextEdit {
    pub element_id: String,
    pub text: String,
    pub is_new: bool,
}

impl FinishTextEdit {
    pub fn new(element_id: impl Into<String>, text: impl Into<String>, is_new: bool) -> Self {
        Self {
            element_id: element_id.into(),
            text: text.into(),
            is_new,
        }
    }

    fn deletes_existing_text(&self) -> bool {
        self.text.trim().is_empty() && !self.is_new
    }
}

impl_draw_action_conflict_history_recording!(FinishTextEdit);

impl Recordable for FinishTextEdit {
    fn history_description(&self) -> String {
        if self.deletes_existing_text() {
            "Delete text".to_string()
        } else if self.is_new {
            "Create text".to_string()
        } else {
            "Edit text".to_string()
        }
    }

    fn record_type(&self) -> HistoryRecordType {
        if self.deletes_existing_text() {
            HistoryRecordType::Delete
        } else if self.is_new {
            HistoryRecordType::Create
        } else {
            HistoryRecordType::Edit
        }
    }
}

#[derive(Clone, Copy, Debug, Default, PartialEq, Eq, Hash)]
pub struct CancelTextEdit;
impl_draw_action_editing_conflict!(CancelTextEdit);

#[derive(Clone, Debug, PartialEq)]
pub struct StartEdit {
    pub operation_id: EditOperationId,
    pub position: DrawPoint,
    pub params: EditOperationParams,
}

impl StartEdit {
    pub fn new(
        operation_id: EditOperationId,
        position: DrawPoint,
        params: EditOperationParams,
    ) -> Self {
        Self {
            operation_id,
            position,
            params,
        }
    }
}

impl_draw_action_default!(StartEdit);

#[derive(Clone, Copy, Debug, PartialEq)]
pub struct UpdateEdit {
    pub current_position: DrawPoint,
    pub modifiers: EditModifiers,
}

impl UpdateEdit {
    pub const fn new(current_position: DrawPoint, modifiers: EditModifiers) -> Self {
        Self {
            current_position,
            modifiers,
        }
    }
}

impl_draw_action_default!(UpdateEdit);

#[derive(Clone, Debug, PartialEq)]
pub struct FinishEdit {
    pub metadata: Option<HistoryMetadata>,
}

impl FinishEdit {
    pub const fn new(metadata: Option<HistoryMetadata>) -> Self {
        Self { metadata }
    }
}

impl_draw_action_history_recording!(FinishEdit);

impl Recordable for FinishEdit {
    fn history_description(&self) -> String {
        self.metadata
            .as_ref()
            .map(|metadata| metadata.description().to_string())
            .unwrap_or_else(|| "Edit operation".to_string())
    }

    fn record_type(&self) -> HistoryRecordType {
        self.metadata
            .as_ref()
            .map(|metadata| map_history_record_type(metadata.record_type()))
            .unwrap_or(HistoryRecordType::Edit)
    }
}

#[derive(Clone, Copy, Debug, PartialEq, Eq, Hash)]
pub struct CancelEdit {
    pub reason: EditCancelReason,
}

impl CancelEdit {
    pub const fn new(reason: EditCancelReason) -> Self {
        Self { reason }
    }
}

impl Default for CancelEdit {
    fn default() -> Self {
        Self {
            reason: EditCancelReason::UserCancelled,
        }
    }
}

impl_draw_action_default!(CancelEdit);

#[derive(Clone, Debug, PartialEq)]
pub struct SetDragPending {
    pub pointer_down_position: DrawPoint,
    pub intent: PendingIntent,
}

impl SetDragPending {
    pub fn new(pointer_down_position: DrawPoint, intent: PendingIntent) -> Self {
        Self {
            pointer_down_position,
            intent,
        }
    }
}

impl_draw_action_editing_conflict!(SetDragPending);

#[derive(Clone, Copy, Debug, Default, PartialEq, Eq, Hash)]
pub struct ClearDragPending;
impl_draw_action_editing_conflict!(ClearDragPending);

#[derive(Clone, Copy, Debug, PartialEq)]
pub struct StartBoxSelect {
    pub start_position: DrawPoint,
}

impl StartBoxSelect {
    pub const fn new(start_position: DrawPoint) -> Self {
        Self { start_position }
    }
}

impl_draw_action_editing_conflict!(StartBoxSelect);

#[derive(Clone, Copy, Debug, PartialEq)]
pub struct UpdateBoxSelect {
    pub current_position: DrawPoint,
}

impl UpdateBoxSelect {
    pub const fn new(current_position: DrawPoint) -> Self {
        Self { current_position }
    }
}

impl_draw_action_editing_conflict!(UpdateBoxSelect);

#[derive(Clone, Copy, Debug, Default, PartialEq, Eq, Hash)]
pub struct FinishBoxSelect;
impl_draw_action_editing_conflict!(FinishBoxSelect);

#[derive(Clone, Copy, Debug, Default, PartialEq, Eq, Hash)]
pub struct CancelBoxSelect;
impl_draw_action_editing_conflict!(CancelBoxSelect);

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

impl_draw_action_default!(MoveCamera);

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

impl_draw_action_default!(ZoomCamera);

#[derive(Clone, Copy, Debug, Default, PartialEq, Eq, Hash)]
pub struct Undo;

impl HistoryPolicyProvider for Undo {
    fn history_policy(&self) -> HistoryPolicy {
        HistoryPolicy::Skip
    }
}

impl HistoryCoalescingProvider for Undo {}

impl DrawAction for Undo {
    fn as_any(&self) -> &dyn Any {
        self
    }

    fn criticality(&self) -> ActionCriticality {
        ActionCriticality::Critical
    }
}

#[derive(Clone, Copy, Debug, Default, PartialEq, Eq, Hash)]
pub struct Redo;

impl HistoryPolicyProvider for Redo {
    fn history_policy(&self) -> HistoryPolicy {
        HistoryPolicy::Skip
    }
}

impl HistoryCoalescingProvider for Redo {}

impl DrawAction for Redo {
    fn as_any(&self) -> &dyn Any {
        self
    }

    fn criticality(&self) -> ActionCriticality {
        ActionCriticality::Critical
    }
}

#[derive(Clone, Copy, Debug, Default, PartialEq, Eq, Hash)]
pub struct ClearHistory;

impl HistoryPolicyProvider for ClearHistory {
    fn history_policy(&self) -> HistoryPolicy {
        HistoryPolicy::Skip
    }
}

impl HistoryCoalescingProvider for ClearHistory {}

impl DrawAction for ClearHistory {
    fn as_any(&self) -> &dyn Any {
        self
    }

    fn criticality(&self) -> ActionCriticality {
        ActionCriticality::Critical
    }
}

fn map_history_record_type(value: MetadataHistoryRecordType) -> HistoryRecordType {
    match value {
        MetadataHistoryRecordType::Edit => HistoryRecordType::Edit,
        MetadataHistoryRecordType::Create => HistoryRecordType::Create,
        MetadataHistoryRecordType::Delete => HistoryRecordType::Delete,
        MetadataHistoryRecordType::Style => HistoryRecordType::Style,
        MetadataHistoryRecordType::Selection => HistoryRecordType::Selection,
        MetadataHistoryRecordType::Other => HistoryRecordType::Other,
    }
}
