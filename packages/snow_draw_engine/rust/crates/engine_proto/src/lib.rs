//! Protobuf contracts for the Snow Draw Rust engine ABI.

use prost::Message;
use thiserror::Error;

pub const ENGINE_SCHEMA_VERSION: u32 = 1;

#[derive(Debug, Error)]
pub enum ProtoError {
    #[error("decode failed: {0}")]
    Decode(#[from] prost::DecodeError),
}

pub fn encode_message<T: Message>(message: &T) -> Vec<u8> {
    message.encode_to_vec()
}

pub fn decode_message<T: Message + Default>(bytes: &[u8]) -> Result<T, ProtoError> {
    Ok(T::decode(bytes)?)
}

#[derive(Clone, Copy, Debug, PartialEq, Eq, prost::Enumeration)]
#[repr(i32)]
pub enum ElementType {
    Unknown = 0,
    Rectangle = 1,
    Arrow = 2,
    Line = 3,
    FreeDraw = 4,
    Filter = 5,
    Highlight = 6,
    Text = 7,
    SerialNumber = 8,
}

#[derive(Clone, Copy, Debug, PartialEq, Eq, prost::Enumeration)]
#[repr(i32)]
pub enum InteractionMode {
    Idle = 0,
    Creating = 1,
    Editing = 2,
    TextEditing = 3,
    BoxSelecting = 4,
    DragPending = 5,
}

#[derive(Clone, Copy, Debug, PartialEq, Eq, prost::Enumeration)]
#[repr(i32)]
pub enum EngineCommandKind {
    Unknown = 0,
    SelectElement = 1,
    ClearSelection = 2,
    SelectAll = 3,
    CreateElement = 4,
    UpdateCreatingElement = 5,
    AddArrowPoint = 6,
    FinishCreateElement = 7,
    CancelCreateElement = 8,
    DeleteElements = 9,
    DuplicateElements = 10,
    ChangeElementZIndex = 11,
    ChangeElementsZIndex = 12,
    UpdateElementsStyle = 13,
    UpdateGlobalElements = 14,
    CreateSerialNumberTextElements = 15,
    StartTextEdit = 16,
    UpdateTextEdit = 17,
    RefreshAutoResizeTextLayoutsAfterFontLoad = 18,
    FinishTextEdit = 19,
    CancelTextEdit = 20,
    StartEdit = 21,
    UpdateEdit = 22,
    FinishEdit = 23,
    CancelEdit = 24,
    SetDragPending = 25,
    ClearDragPending = 26,
    StartBoxSelect = 27,
    UpdateBoxSelect = 28,
    FinishBoxSelect = 29,
    CancelBoxSelect = 30,
    MoveCamera = 31,
    ZoomCamera = 32,
    Undo = 33,
    Redo = 34,
    ClearHistory = 35,
}

#[derive(Clone, Copy, Debug, PartialEq, Eq, prost::Enumeration)]
#[repr(i32)]
pub enum ZIndexOperation {
    BringToFront = 0,
    SendToBack = 1,
    BringForward = 2,
    SendBackward = 3,
}

#[derive(Clone, Copy, Debug, PartialEq, Eq, prost::Enumeration)]
#[repr(i32)]
pub enum FrameTaskKind {
    Unknown = 0,
    Rectangle = 1,
    Line = 2,
    Arrow = 3,
    FreeDraw = 4,
    Text = 5,
    SerialNumber = 6,
    Highlight = 7,
    Filter = 8,
    Background = 9,
    Grid = 10,
    SelectionOutline = 11,
    SelectionControls = 12,
    ArrowPointOverlay = 13,
    ArrowBindingHighlight = 14,
    HoverOutline = 15,
    SnapGuides = 16,
    BoxSelection = 17,
    HighlightMask = 18,
    Watermark = 19,
}

#[derive(Clone, Copy, Debug, PartialEq, Eq, prost::Enumeration)]
#[repr(i32)]
pub enum EngineEventKind {
    Unknown = 0,
    StateChanged = 1,
    ValidationFailed = 2,
    Error = 3,
    HistoryChanged = 4,
    Debug = 5,
}

#[derive(Clone, PartialEq, prost::Message)]
pub struct DrawPoint {
    #[prost(double, tag = "1")]
    pub x: f64,
    #[prost(double, tag = "2")]
    pub y: f64,
    #[prost(double, tag = "3")]
    pub pressure: f64,
    #[prost(uint64, tag = "4")]
    pub timestamp_us: u64,
}

#[derive(Clone, PartialEq, prost::Message)]
pub struct DrawRect {
    #[prost(double, tag = "1")]
    pub min_x: f64,
    #[prost(double, tag = "2")]
    pub min_y: f64,
    #[prost(double, tag = "3")]
    pub max_x: f64,
    #[prost(double, tag = "4")]
    pub max_y: f64,
}

#[derive(Clone, PartialEq, prost::Message)]
pub struct CameraState {
    #[prost(message, optional, tag = "1")]
    pub position: Option<DrawPoint>,
    #[prost(double, tag = "2")]
    pub zoom: f64,
}

#[derive(Clone, PartialEq, prost::Message)]
pub struct Element {
    #[prost(string, tag = "1")]
    pub id: String,
    #[prost(enumeration = "ElementType", tag = "2")]
    pub element_type: i32,
    #[prost(message, optional, tag = "3")]
    pub rect: Option<DrawRect>,
    #[prost(double, tag = "4")]
    pub rotation: f64,
    #[prost(double, tag = "5")]
    pub opacity: f64,
    #[prost(int32, tag = "6")]
    pub z_index: i32,
    #[prost(bytes = "vec", tag = "7")]
    pub payload: Vec<u8>,
}

#[derive(Clone, PartialEq, prost::Message)]
pub struct EngineConfig {
    #[prost(uint32, tag = "1")]
    pub schema_version: u32,
    #[prost(string, tag = "2")]
    pub locale_tag: String,
    #[prost(double, tag = "3")]
    pub scale_factor: f64,
    #[prost(uint64, tag = "4")]
    pub requested_capabilities: u64,
    #[prost(uint64, tag = "5")]
    pub deterministic_seed: u64,
}

#[derive(Clone, PartialEq, prost::Message)]
pub struct EngineSnapshot {
    #[prost(uint32, tag = "1")]
    pub schema_version: u32,
    #[prost(uint64, tag = "2")]
    pub document_version: u64,
    #[prost(uint64, tag = "3")]
    pub selection_version: u64,
    #[prost(enumeration = "InteractionMode", tag = "4")]
    pub interaction_mode: i32,
    #[prost(message, optional, tag = "5")]
    pub camera: Option<CameraState>,
    #[prost(message, repeated, tag = "6")]
    pub elements: Vec<Element>,
    #[prost(string, repeated, tag = "7")]
    pub selected_ids: Vec<String>,
    #[prost(uint64, tag = "8")]
    pub history_undo_len: u64,
    #[prost(uint64, tag = "9")]
    pub history_redo_len: u64,
    #[prost(bytes = "vec", tag = "10")]
    pub global_elements_payload: Vec<u8>,
}

#[derive(Clone, PartialEq, prost::Message)]
pub struct CreateElementCommand {
    #[prost(enumeration = "ElementType", tag = "1")]
    pub element_type: i32,
    #[prost(string, tag = "2")]
    pub element_id: String,
    #[prost(message, optional, tag = "3")]
    pub position: Option<DrawPoint>,
    #[prost(bytes = "vec", tag = "4")]
    pub initial_payload: Vec<u8>,
    #[prost(bool, tag = "5")]
    pub maintain_aspect_ratio: bool,
    #[prost(bool, tag = "6")]
    pub create_from_center: bool,
    #[prost(bool, tag = "7")]
    pub snap_override: bool,
}

#[derive(Clone, PartialEq, prost::Message)]
pub struct SelectElementCommand {
    #[prost(string, tag = "1")]
    pub element_id: String,
    #[prost(bool, tag = "2")]
    pub add_to_selection: bool,
    #[prost(message, optional, tag = "3")]
    pub position: Option<DrawPoint>,
}

#[derive(Clone, PartialEq, prost::Message)]
pub struct UpdateCreatingElementCommand {
    #[prost(message, repeated, tag = "1")]
    pub positions: Vec<DrawPoint>,
    #[prost(bool, tag = "2")]
    pub maintain_aspect_ratio: bool,
    #[prost(bool, tag = "3")]
    pub create_from_center: bool,
    #[prost(bool, tag = "4")]
    pub snap_override: bool,
}

#[derive(Clone, PartialEq, prost::Message)]
pub struct AddArrowPointCommand {
    #[prost(message, optional, tag = "1")]
    pub position: Option<DrawPoint>,
    #[prost(bool, tag = "2")]
    pub snap_override: bool,
}

#[derive(Clone, PartialEq, prost::Message)]
pub struct DeleteElementsCommand {
    #[prost(string, repeated, tag = "1")]
    pub element_ids: Vec<String>,
}

#[derive(Clone, PartialEq, prost::Message)]
pub struct UpdateElementsStyleCommand {
    #[prost(string, repeated, tag = "1")]
    pub element_ids: Vec<String>,
    #[prost(bytes = "vec", tag = "2")]
    pub style_payload: Vec<u8>,
}

#[derive(Clone, PartialEq, prost::Message)]
pub struct DuplicateElementsCommand {
    #[prost(string, repeated, tag = "1")]
    pub element_ids: Vec<String>,
    #[prost(double, tag = "2")]
    pub offset_x: f64,
    #[prost(double, tag = "3")]
    pub offset_y: f64,
}

#[derive(Clone, PartialEq, prost::Message)]
pub struct ChangeElementZIndexCommand {
    #[prost(string, tag = "1")]
    pub element_id: String,
    #[prost(enumeration = "ZIndexOperation", tag = "2")]
    pub operation: i32,
}

#[derive(Clone, PartialEq, prost::Message)]
pub struct ChangeElementsZIndexCommand {
    #[prost(string, repeated, tag = "1")]
    pub element_ids: Vec<String>,
    #[prost(enumeration = "ZIndexOperation", tag = "2")]
    pub operation: i32,
}

#[derive(Clone, PartialEq, prost::Message)]
pub struct UpdateGlobalElementsCommand {
    #[prost(bytes = "vec", tag = "1")]
    pub payload: Vec<u8>,
}

#[derive(Clone, PartialEq, prost::Message)]
pub struct CreateSerialNumberTextElementsCommand {
    #[prost(string, repeated, tag = "1")]
    pub element_ids: Vec<String>,
}

#[derive(Clone, PartialEq, prost::Message)]
pub struct StartTextEditCommand {
    #[prost(string, tag = "1")]
    pub element_id: String,
    #[prost(message, optional, tag = "2")]
    pub position: Option<DrawPoint>,
}

#[derive(Clone, PartialEq, prost::Message)]
pub struct UpdateTextEditCommand {
    #[prost(string, tag = "1")]
    pub text: String,
    #[prost(message, optional, tag = "2")]
    pub rect: Option<DrawRect>,
}

#[derive(Clone, PartialEq, prost::Message)]
pub struct FinishTextEditCommand {
    #[prost(string, tag = "1")]
    pub element_id: String,
    #[prost(string, tag = "2")]
    pub text: String,
    #[prost(bool, tag = "3")]
    pub is_new: bool,
}

#[derive(Clone, PartialEq, prost::Message)]
pub struct StartEditCommand {
    #[prost(string, tag = "1")]
    pub operation_id: String,
    #[prost(message, optional, tag = "2")]
    pub position: Option<DrawPoint>,
    #[prost(bytes = "vec", tag = "3")]
    pub params: Vec<u8>,
}

#[derive(Clone, PartialEq, prost::Message)]
pub struct UpdateEditCommand {
    #[prost(message, optional, tag = "1")]
    pub current_position: Option<DrawPoint>,
    #[prost(bytes = "vec", tag = "2")]
    pub modifiers: Vec<u8>,
}

#[derive(Clone, PartialEq, prost::Message)]
pub struct SetDragPendingCommand {
    #[prost(message, optional, tag = "1")]
    pub pointer_down_position: Option<DrawPoint>,
    #[prost(string, tag = "2")]
    pub intent: String,
}

#[derive(Clone, PartialEq, prost::Message)]
pub struct StartBoxSelectCommand {
    #[prost(message, optional, tag = "1")]
    pub start_position: Option<DrawPoint>,
}

#[derive(Clone, PartialEq, prost::Message)]
pub struct UpdateBoxSelectCommand {
    #[prost(message, optional, tag = "1")]
    pub current_position: Option<DrawPoint>,
}

#[derive(Clone, PartialEq, prost::Message)]
pub struct MoveCameraCommand {
    #[prost(double, tag = "1")]
    pub dx: f64,
    #[prost(double, tag = "2")]
    pub dy: f64,
}

#[derive(Clone, PartialEq, prost::Message)]
pub struct ZoomCameraCommand {
    #[prost(double, tag = "1")]
    pub scale: f64,
    #[prost(message, optional, tag = "2")]
    pub center: Option<DrawPoint>,
}

#[derive(Clone, PartialEq, prost::Message)]
pub struct EngineCommand {
    #[prost(enumeration = "EngineCommandKind", tag = "1")]
    pub kind: i32,
    #[prost(
        oneof = "engine_command::Payload",
        tags = "10, 11, 12, 13, 14, 15, 16, 17, 18, 19, 20, 21, 22, 23, 24, 25, 26, 27, 28, 29, 30"
    )]
    pub payload: Option<engine_command::Payload>,
}

pub mod engine_command {
    #[derive(Clone, PartialEq, prost::Oneof)]
    pub enum Payload {
        #[prost(message, tag = "10")]
        CreateElement(super::CreateElementCommand),
        #[prost(message, tag = "11")]
        SelectElement(super::SelectElementCommand),
        #[prost(message, tag = "12")]
        DeleteElements(super::DeleteElementsCommand),
        #[prost(message, tag = "13")]
        UpdateElementsStyle(super::UpdateElementsStyleCommand),
        #[prost(message, tag = "14")]
        MoveCamera(super::MoveCameraCommand),
        #[prost(message, tag = "15")]
        ZoomCamera(super::ZoomCameraCommand),
        #[prost(message, tag = "16")]
        UpdateCreatingElement(super::UpdateCreatingElementCommand),
        #[prost(message, tag = "17")]
        AddArrowPoint(super::AddArrowPointCommand),
        #[prost(message, tag = "18")]
        DuplicateElements(super::DuplicateElementsCommand),
        #[prost(message, tag = "19")]
        ChangeElementZIndex(super::ChangeElementZIndexCommand),
        #[prost(message, tag = "20")]
        ChangeElementsZIndex(super::ChangeElementsZIndexCommand),
        #[prost(message, tag = "21")]
        UpdateGlobalElements(super::UpdateGlobalElementsCommand),
        #[prost(message, tag = "22")]
        CreateSerialNumberTextElements(super::CreateSerialNumberTextElementsCommand),
        #[prost(message, tag = "23")]
        StartTextEdit(super::StartTextEditCommand),
        #[prost(message, tag = "24")]
        UpdateTextEdit(super::UpdateTextEditCommand),
        #[prost(message, tag = "25")]
        FinishTextEdit(super::FinishTextEditCommand),
        #[prost(message, tag = "26")]
        StartEdit(super::StartEditCommand),
        #[prost(message, tag = "27")]
        UpdateEdit(super::UpdateEditCommand),
        #[prost(message, tag = "28")]
        SetDragPending(super::SetDragPendingCommand),
        #[prost(message, tag = "29")]
        StartBoxSelect(super::StartBoxSelectCommand),
        #[prost(message, tag = "30")]
        UpdateBoxSelect(super::UpdateBoxSelectCommand),
    }
}

#[derive(Clone, PartialEq, prost::Message)]
pub struct FramePlanRequest {
    #[prost(message, optional, tag = "1")]
    pub viewport: Option<DrawRect>,
    #[prost(string, tag = "2")]
    pub locale_tag: String,
    #[prost(double, tag = "3")]
    pub scale_factor: f64,
}

#[derive(Clone, PartialEq, prost::Message)]
pub struct FrameTask {
    #[prost(enumeration = "FrameTaskKind", tag = "1")]
    pub kind: i32,
    #[prost(string, tag = "2")]
    pub element_id: String,
    #[prost(enumeration = "ElementType", tag = "3")]
    pub element_type: i32,
    #[prost(bytes = "vec", tag = "4")]
    pub payload: Vec<u8>,
}

#[derive(Clone, PartialEq, prost::Message)]
pub struct FrameRenderPlan {
    #[prost(uint32, tag = "1")]
    pub schema_version: u32,
    #[prost(message, optional, tag = "2")]
    pub camera: Option<CameraState>,
    #[prost(double, tag = "3")]
    pub scale_factor: f64,
    #[prost(string, tag = "4")]
    pub locale_tag: String,
    #[prost(message, repeated, tag = "5")]
    pub tasks: Vec<FrameTask>,
}

#[derive(Clone, PartialEq, prost::Message)]
pub struct EngineError {
    #[prost(uint32, tag = "1")]
    pub code: u32,
    #[prost(string, tag = "2")]
    pub message: String,
    #[prost(string, tag = "3")]
    pub details: String,
}

#[derive(Clone, PartialEq, prost::Message)]
pub struct EngineEvent {
    #[prost(enumeration = "EngineEventKind", tag = "1")]
    pub kind: i32,
    #[prost(uint64, tag = "2")]
    pub sequence: u64,
    #[prost(oneof = "engine_event::Payload", tags = "10, 11, 12")]
    pub payload: Option<engine_event::Payload>,
}

pub mod engine_event {
    #[derive(Clone, PartialEq, prost::Oneof)]
    pub enum Payload {
        #[prost(message, tag = "10")]
        Error(super::EngineError),
        #[prost(bytes = "vec", tag = "11")]
        Blob(Vec<u8>),
        #[prost(string, tag = "12")]
        Message(String),
    }
}

pub fn default_draw_point() -> DrawPoint {
    DrawPoint {
        x: 0.0,
        y: 0.0,
        pressure: 0.0,
        timestamp_us: 0,
    }
}

pub fn default_camera_state() -> CameraState {
    CameraState {
        position: Some(default_draw_point()),
        zoom: 1.0,
    }
}

pub fn default_engine_config() -> EngineConfig {
    EngineConfig {
        schema_version: ENGINE_SCHEMA_VERSION,
        locale_tag: "en-US".to_string(),
        scale_factor: 1.0,
        requested_capabilities: 0,
        deterministic_seed: 0,
    }
}

pub fn default_engine_snapshot() -> EngineSnapshot {
    EngineSnapshot {
        schema_version: ENGINE_SCHEMA_VERSION,
        document_version: 0,
        selection_version: 0,
        interaction_mode: InteractionMode::Idle as i32,
        camera: Some(default_camera_state()),
        elements: Vec::new(),
        selected_ids: Vec::new(),
        history_undo_len: 0,
        history_redo_len: 0,
        global_elements_payload: Vec::new(),
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn roundtrip_snapshot() {
        let snapshot = default_engine_snapshot();
        let encoded = encode_message(&snapshot);
        let decoded: EngineSnapshot = decode_message(&encoded).expect("decode");
        assert_eq!(decoded.schema_version, ENGINE_SCHEMA_VERSION);
        assert_eq!(decoded.document_version, 0);
    }
}
