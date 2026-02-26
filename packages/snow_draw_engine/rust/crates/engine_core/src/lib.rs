//! Headless Snow Draw engine core implemented in Rust.

mod v2;
pub use v2::EngineV2;

use std::collections::{BTreeMap, BTreeSet, VecDeque};

use base64::Engine as _;
use engine_proto::engine_command::Payload as CommandPayload;
use engine_proto::engine_event::Payload as EventPayload;
use engine_proto::{
    decode_message, default_camera_state, default_engine_config, default_engine_snapshot,
    encode_message, AddArrowPointCommand, CameraState, ChangeElementZIndexCommand,
    ChangeElementsZIndexCommand, CreateElementCommand, CreateSerialNumberTextElementsCommand,
    DrawPoint, DrawRect, DuplicateElementsCommand, Element, ElementType, EngineCommand,
    EngineCommandKind, EngineConfig, EngineError, EngineEvent, EngineEventKind, EngineSnapshot,
    FinishTextEditCommand, FramePlanRequest, FrameRenderPlan, FrameTask, FrameTaskKind,
    InteractionMode, MoveCameraCommand, SelectElementCommand, SetDragPendingCommand,
    StartBoxSelectCommand, StartTextEditCommand, UpdateBoxSelectCommand,
    UpdateCreatingElementCommand, UpdateEditCommand, UpdateElementsStyleCommand,
    UpdateGlobalElementsCommand, UpdateTextEditCommand, ZIndexOperation, ZoomCameraCommand,
};
use serde_json::{Map as JsonMap, Value as JsonValue};
use thiserror::Error;

const EVENT_QUEUE_LIMIT: usize = 2048;
const CAMERA_MIN_ZOOM: f64 = 0.1;
const CAMERA_MAX_ZOOM: f64 = 30.0;
const TEXT_MIN_WIDTH: f64 = 24.0;
const ARROW_POINT_LOOP_THRESHOLD: f64 = 9.0;
const RUNTIME_CONFIG_KEY: &str = "__runtimeConfig";
const RUNTIME_BOOTSTRAP_SNAPSHOT_KEY: &str = "__bootstrapSnapshotV1ProtoBase64";

#[derive(Debug, Error)]
pub enum EngineCoreError {
    #[error("invalid command payload for {0:?}")]
    InvalidPayload(EngineCommandKind),
    #[error("invalid zoom scale: {0}")]
    InvalidZoomScale(f64),
    #[error("decode failed: {0}")]
    Decode(String),
    #[error("internal error: {0}")]
    Internal(String),
}

impl EngineCoreError {
    pub fn code(&self) -> u32 {
        match self {
            Self::InvalidPayload(_) => 1001,
            Self::InvalidZoomScale(_) => 1002,
            Self::Decode(_) => 1003,
            Self::Internal(_) => 1099,
        }
    }

    pub fn to_proto(&self) -> EngineError {
        EngineError {
            code: self.code(),
            message: self.to_string(),
            details: format!("{self:?}"),
        }
    }
}

#[derive(Debug)]
pub struct Engine {
    config: EngineConfig,
    runtime_snap_config: RuntimeSnapConfig,
    runtime_style_defaults: RuntimeStyleDefaults,
    runtime_snap_guides: Vec<JsonValue>,
    snapshot: EngineSnapshot,
    undo_stack: Vec<EngineSnapshot>,
    redo_stack: Vec<EngineSnapshot>,
    events: VecDeque<EngineEvent>,
    next_event_sequence: u64,
    next_element_sequence: u64,
    creating_element_id: Option<String>,
    creating_start_position: Option<DrawPoint>,
    text_edit_session: Option<TextEditSession>,
    box_select_start: Option<DrawPoint>,
    box_select_current: Option<DrawPoint>,
    edit_session: Option<EditSession>,
}

#[derive(Debug, Clone)]
struct TextEditSession {
    element_id: String,
    is_new: bool,
    text: String,
    rect: Option<DrawRect>,
}

#[derive(Debug, Clone)]
struct EditSession {
    operation: EditSessionOperation,
    start_position: DrawPoint,
    baseline_rects: BTreeMap<String, DrawRect>,
    baseline_rotations: BTreeMap<String, f64>,
    baseline_payloads: BTreeMap<String, Vec<u8>>,
}

#[derive(Debug, Clone)]
enum EditSessionOperation {
    Move,
    Resize {
        mode: ResizeMode,
    },
    Rotate {
        pivot: DrawPoint,
        snap_angle: f64,
    },
    ArrowPoint {
        element_id: String,
        point_kind: ArrowPointKind,
        point_index: usize,
        delete_point_on_finish: bool,
    },
    Unknown,
}

#[derive(Debug, Clone, Copy)]
enum ResizeMode {
    TopLeft,
    TopRight,
    BottomLeft,
    BottomRight,
    Top,
    Bottom,
    Left,
    Right,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
enum ArrowPointKind {
    Turning,
    Addable,
    LoopStart,
    LoopEnd,
}

#[derive(Debug, Clone, Copy, PartialEq)]
struct RuntimeSnapConfig {
    grid_enabled: bool,
    object_enabled: bool,
    grid_size: f64,
    object_distance: f64,
}

impl Default for RuntimeSnapConfig {
    fn default() -> Self {
        Self {
            grid_enabled: false,
            object_enabled: false,
            grid_size: 20.0,
            object_distance: 8.0,
        }
    }
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
enum RuntimeSnappingMode {
    None,
    Object,
    Grid,
}

#[derive(Debug, Clone, Copy, Default)]
struct RuntimeSnapConfigPatch {
    grid_enabled: Option<bool>,
    object_enabled: Option<bool>,
    grid_size: Option<f64>,
    object_distance: Option<f64>,
}

#[derive(Debug, Clone, PartialEq, Default)]
struct RuntimeStyleDefaults {
    by_element_type: BTreeMap<i32, JsonMap<String, JsonValue>>,
}

impl RuntimeStyleDefaults {
    fn style_for_element_type(&self, element_type: i32) -> Option<&JsonMap<String, JsonValue>> {
        self.by_element_type
            .get(&normalize_element_type(element_type))
    }

    fn set_for_element_type(&mut self, element_type: i32, style: JsonMap<String, JsonValue>) {
        self.by_element_type
            .insert(normalize_element_type(element_type), style);
    }
}

#[derive(Debug, Clone)]
struct SnappedPointResult {
    point: DrawPoint,
    guides: Vec<JsonValue>,
}

#[derive(Debug, Clone, Copy)]
struct AnchorSnapMatch {
    offset: f64,
    reference: f64,
}

#[derive(Debug, Clone, Copy, Default)]
struct ObjectSnapResult {
    dx: f64,
    dy: f64,
    x_match: Option<AnchorSnapMatch>,
    y_match: Option<AnchorSnapMatch>,
}

impl Default for Engine {
    fn default() -> Self {
        Self::new(default_engine_config())
    }
}

impl Engine {
    pub fn new(config: EngineConfig) -> Self {
        let mut snapshot = default_engine_snapshot();
        snapshot.camera = Some(default_camera_state());
        snapshot.schema_version = config.schema_version;
        let next_element_sequence = config.deterministic_seed.max(1);
        Self {
            config,
            runtime_snap_config: RuntimeSnapConfig::default(),
            runtime_style_defaults: RuntimeStyleDefaults::default(),
            runtime_snap_guides: Vec::new(),
            snapshot,
            undo_stack: Vec::new(),
            redo_stack: Vec::new(),
            events: VecDeque::new(),
            next_event_sequence: 1,
            next_element_sequence,
            creating_element_id: None,
            creating_start_position: None,
            text_edit_session: None,
            box_select_start: None,
            box_select_current: None,
            edit_session: None,
        }
    }

    pub fn dispatch_bytes(&mut self, bytes: &[u8]) -> Result<(), EngineCoreError> {
        let command: EngineCommand =
            decode_message(bytes).map_err(|e| EngineCoreError::Decode(e.to_string()))?;
        self.dispatch(command)
    }

    pub fn dispatch_batch_bytes(
        &mut self,
        commands: impl IntoIterator<Item = Vec<u8>>,
    ) -> Result<(), EngineCoreError> {
        for command in commands {
            self.dispatch_bytes(&command)?;
        }
        Ok(())
    }

    pub fn dispatch(&mut self, command: EngineCommand) -> Result<(), EngineCoreError> {
        let kind = EngineCommandKind::try_from(command.kind).unwrap_or(EngineCommandKind::Unknown);

        match kind {
            EngineCommandKind::SelectElement => {
                let payload = extract_select_payload(kind, command.payload)?;
                self.record_history();
                self.apply_select(payload);
                self.emit_state_changed();
            }
            EngineCommandKind::ClearSelection => {
                self.record_history();
                self.apply_clear_selection();
                self.emit_state_changed();
            }
            EngineCommandKind::SelectAll => {
                self.record_history();
                self.apply_select_all();
                self.emit_state_changed();
            }
            EngineCommandKind::CreateElement => {
                let payload = extract_create_payload(kind, command.payload)?;
                self.record_history();
                self.apply_create(payload);
                self.emit_state_changed();
            }
            EngineCommandKind::UpdateCreatingElement => {
                if let Ok(payload) = extract_update_creating_payload(kind, command.payload) {
                    self.apply_update_creating(payload);
                    self.emit_state_changed();
                } else {
                    self.emit_debug(format!("command {kind:?} missing payload"));
                }
            }
            EngineCommandKind::AddArrowPoint => {
                if let Ok(payload) = extract_add_arrow_point_payload(kind, command.payload) {
                    self.apply_add_arrow_point(payload);
                    self.emit_state_changed();
                } else {
                    self.emit_debug(format!("command {kind:?} missing payload"));
                }
            }
            EngineCommandKind::FinishCreateElement => {
                self.apply_finish_create();
                self.emit_state_changed();
            }
            EngineCommandKind::CancelCreateElement => {
                self.record_history();
                self.apply_cancel_create();
                self.emit_state_changed();
            }
            EngineCommandKind::DeleteElements => {
                let payload = extract_delete_payload(kind, command.payload)?;
                self.record_history();
                self.apply_delete(payload.element_ids);
                self.emit_state_changed();
            }
            EngineCommandKind::DuplicateElements => {
                if let Ok(payload) = extract_duplicate_payload(kind, command.payload) {
                    self.record_history();
                    self.apply_duplicate(payload);
                    self.emit_state_changed();
                } else {
                    self.emit_debug(format!("command {kind:?} missing payload"));
                }
            }
            EngineCommandKind::ChangeElementZIndex => {
                if let Ok(payload) = extract_change_element_z_payload(kind, command.payload) {
                    self.record_history();
                    self.apply_change_element_z_index(payload);
                    self.emit_state_changed();
                } else {
                    self.emit_debug(format!("command {kind:?} missing payload"));
                }
            }
            EngineCommandKind::ChangeElementsZIndex => {
                if let Ok(payload) = extract_change_elements_z_payload(kind, command.payload) {
                    self.record_history();
                    self.apply_change_elements_z_index(payload);
                    self.emit_state_changed();
                } else {
                    self.emit_debug(format!("command {kind:?} missing payload"));
                }
            }
            EngineCommandKind::UpdateElementsStyle => {
                let payload = extract_update_style_payload(kind, command.payload)?;
                self.record_history();
                self.apply_update_style(payload);
                self.emit_state_changed();
            }
            EngineCommandKind::UpdateGlobalElements => {
                if let Ok(payload) = extract_update_global_payload(kind, command.payload) {
                    self.record_history();
                    self.apply_update_global_elements(payload);
                    self.emit_state_changed();
                } else {
                    self.emit_debug(format!("command {kind:?} missing payload"));
                }
            }
            EngineCommandKind::CreateSerialNumberTextElements => {
                if let Ok(payload) = extract_create_serial_text_payload(kind, command.payload) {
                    self.record_history();
                    self.apply_create_serial_number_text_elements(payload);
                    self.emit_state_changed();
                } else {
                    self.emit_debug(format!("command {kind:?} missing payload"));
                }
            }
            EngineCommandKind::StartTextEdit => {
                if let Ok(payload) = extract_start_text_edit_payload(kind, command.payload) {
                    self.apply_start_text_edit(payload);
                    self.emit_state_changed();
                } else {
                    self.emit_debug(format!("command {kind:?} missing payload"));
                }
            }
            EngineCommandKind::UpdateTextEdit => {
                if let Ok(payload) = extract_update_text_edit_payload(kind, command.payload) {
                    self.apply_update_text_edit(payload);
                    self.emit_state_changed();
                } else {
                    self.emit_debug(format!("command {kind:?} missing payload"));
                }
            }
            EngineCommandKind::RefreshAutoResizeTextLayoutsAfterFontLoad => {
                if self.apply_refresh_auto_resize_text_layouts_after_font_load() {
                    self.emit_state_changed();
                }
            }
            EngineCommandKind::FinishTextEdit => {
                if let Ok(payload) = extract_finish_text_edit_payload(kind, command.payload) {
                    self.record_history();
                    self.apply_finish_text_edit(payload);
                    self.emit_state_changed();
                } else {
                    self.emit_debug(format!("command {kind:?} missing payload"));
                }
            }
            EngineCommandKind::CancelTextEdit => {
                self.apply_cancel_text_edit();
                self.emit_state_changed();
            }
            EngineCommandKind::StartEdit => {
                if let Ok(payload) = extract_start_edit_payload(kind, command.payload) {
                    self.record_history();
                    self.apply_start_edit(payload);
                    self.emit_state_changed();
                } else {
                    self.emit_debug(format!("command {kind:?} missing payload"));
                }
            }
            EngineCommandKind::UpdateEdit => {
                if let Ok(payload) = extract_update_edit_payload(kind, command.payload) {
                    self.apply_update_edit(payload);
                    self.emit_state_changed();
                } else {
                    self.emit_debug(format!("command {kind:?} missing payload"));
                }
            }
            EngineCommandKind::FinishEdit => {
                self.apply_finish_edit();
                self.emit_state_changed();
            }
            EngineCommandKind::CancelEdit => {
                self.apply_cancel_edit();
                self.emit_state_changed();
            }
            EngineCommandKind::SetDragPending => {
                if let Ok(payload) = extract_set_drag_pending_payload(kind, command.payload) {
                    self.apply_set_drag_pending(payload);
                    self.emit_state_changed();
                } else {
                    self.emit_debug(format!("command {kind:?} missing payload"));
                }
            }
            EngineCommandKind::ClearDragPending => {
                self.set_interaction_mode(InteractionMode::Idle);
                self.emit_state_changed();
            }
            EngineCommandKind::StartBoxSelect => {
                if let Ok(payload) = extract_start_box_select_payload(kind, command.payload) {
                    self.apply_start_box_select(payload);
                    self.emit_state_changed();
                } else {
                    self.emit_debug(format!("command {kind:?} missing payload"));
                }
            }
            EngineCommandKind::UpdateBoxSelect => {
                if let Ok(payload) = extract_update_box_select_payload(kind, command.payload) {
                    self.apply_update_box_select(payload);
                    self.emit_state_changed();
                } else {
                    self.emit_debug(format!("command {kind:?} missing payload"));
                }
            }
            EngineCommandKind::FinishBoxSelect | EngineCommandKind::CancelBoxSelect => {
                self.box_select_start = None;
                self.box_select_current = None;
                self.set_interaction_mode(InteractionMode::Idle);
                self.emit_state_changed();
            }
            EngineCommandKind::MoveCamera => {
                let payload = extract_move_camera_payload(kind, command.payload)?;
                self.record_history();
                self.apply_move_camera(payload);
                self.emit_state_changed();
            }
            EngineCommandKind::ZoomCamera => {
                let payload = extract_zoom_camera_payload(kind, command.payload)?;
                if payload.scale <= 0.0 || !payload.scale.is_finite() {
                    let error = EngineCoreError::InvalidZoomScale(payload.scale);
                    self.emit_error(error.to_proto());
                    return Err(error);
                }
                self.record_history();
                self.apply_zoom_camera(payload);
                self.emit_state_changed();
            }
            EngineCommandKind::Undo => {
                self.apply_undo();
            }
            EngineCommandKind::Redo => {
                self.apply_redo();
            }
            EngineCommandKind::ClearHistory => {
                self.undo_stack.clear();
                self.redo_stack.clear();
                self.clear_runtime_snap_guides();
                self.sync_history_lengths();
                self.emit_history_changed();
            }
            EngineCommandKind::Unknown => {
                self.emit_debug(format!("command {kind:?} accepted as no-op"));
            }
        }

        Ok(())
    }

    pub(crate) fn apply_runtime_config_payload(&mut self, payload: &[u8]) -> bool {
        let Some(mut map) = decode_json_map(payload) else {
            return false;
        };
        let mut changed = false;
        if let Some(snapshot) = extract_bootstrap_snapshot_from_map(&mut map) {
            changed |= self.apply_bootstrap_snapshot(snapshot);
        }
        if let Some(patch) = extract_runtime_snap_config_patch(&mut map) {
            changed |= self.apply_runtime_snap_config_patch(patch);
        }
        if let Some(next_styles) = runtime_style_defaults_from_map(&map) {
            if self.runtime_style_defaults != next_styles {
                self.runtime_style_defaults = next_styles;
                changed = true;
            }
        }
        changed
    }

    fn apply_bootstrap_snapshot(&mut self, mut snapshot: EngineSnapshot) -> bool {
        sanitize_bootstrap_snapshot(&mut snapshot, self.config.schema_version);
        if self.snapshot == snapshot {
            return false;
        }

        self.snapshot = snapshot;
        self.undo_stack.clear();
        self.redo_stack.clear();
        self.sync_history_lengths();
        self.clear_runtime_snap_guides();
        self.creating_element_id = None;
        self.creating_start_position = None;
        self.text_edit_session = None;
        self.box_select_start = None;
        self.box_select_current = None;
        self.edit_session = None;
        self.reseed_next_element_sequence_from_snapshot();
        true
    }

    fn reseed_next_element_sequence_from_snapshot(&mut self) {
        let mut next = self.config.deterministic_seed.max(1);
        for element in &self.snapshot.elements {
            let Some(raw) = element.id.strip_prefix("rust_") else {
                continue;
            };
            let Some(parsed) = raw.parse::<u64>().ok() else {
                continue;
            };
            next = next.max(parsed.saturating_add(1));
        }
        self.next_element_sequence = next;
    }

    pub fn get_snapshot(&self) -> EngineSnapshot {
        self.snapshot.clone()
    }

    pub(crate) fn apply_text_metrics_layout(
        &mut self,
        element_id: &str,
        expected_text: &str,
        measured_width: f64,
        measured_height: f64,
        measured_line_height: f64,
    ) -> bool {
        let Some(element) = self.element_mut(element_id) else {
            return false;
        };
        if normalize_element_type(element.element_type) != ElementType::Text as i32 {
            return false;
        }

        let payload_map = decode_json_map(&element.payload)
            .unwrap_or_else(|| default_element_payload_map(ElementType::Text as i32));
        let auto_resize = payload_map
            .get("autoResize")
            .and_then(JsonValue::as_bool)
            .unwrap_or(true);
        if !auto_resize {
            return false;
        }

        let current_text = payload_map
            .get("text")
            .and_then(JsonValue::as_str)
            .unwrap_or_default();
        if current_text != expected_text {
            return false;
        }

        let Some(current_rect) = element.rect.as_ref() else {
            return false;
        };

        let fallback_metrics = fallback_text_metrics_for_payload(&payload_map, f64::INFINITY, None);
        let line_height =
            sanitize_positive_extent(measured_line_height, fallback_metrics.line_height.max(1.0));
        let layout_padding = resolve_text_layout_horizontal_padding(line_height) * 2.0;
        let content_width = sanitize_positive_extent(measured_width, fallback_metrics.width);
        let content_height = sanitize_positive_extent(measured_height, fallback_metrics.height);
        let width = sanitize_positive_extent(content_width + layout_padding, 1.0);
        let height = sanitize_positive_extent(content_height.max(line_height), line_height);

        let next_rect = DrawRect {
            min_x: current_rect.min_x,
            min_y: current_rect.min_y,
            max_x: current_rect.min_x + width.max(1.0),
            max_y: current_rect.min_y + height.max(1.0),
        };
        if rects_close(current_rect, &next_rect) {
            return false;
        }

        element.rect = Some(next_rect);
        self.snapshot.document_version += 1;
        self.emit_state_changed();
        true
    }

    pub fn get_snapshot_bytes(&self) -> Vec<u8> {
        encode_message(&self.snapshot)
    }

    pub fn build_frame_plan(&self, request: FramePlanRequest) -> FrameRenderPlan {
        let mut tasks = Vec::new();
        tasks.push(FrameTask {
            kind: FrameTaskKind::Background as i32,
            element_id: String::new(),
            element_type: ElementType::Unknown as i32,
            payload: Vec::new(),
        });
        tasks.push(FrameTask {
            kind: FrameTaskKind::Grid as i32,
            element_id: String::new(),
            element_type: ElementType::Unknown as i32,
            payload: Vec::new(),
        });

        if let Some(mask_payload) = highlight_mask_payload(&self.snapshot.global_elements_payload) {
            tasks.push(FrameTask {
                kind: FrameTaskKind::HighlightMask as i32,
                element_id: String::new(),
                element_type: ElementType::Unknown as i32,
                payload: mask_payload,
            });
        }

        if let Some(watermark_payload) = watermark_payload(&self.snapshot.global_elements_payload) {
            tasks.push(FrameTask {
                kind: FrameTaskKind::Watermark as i32,
                element_id: String::new(),
                element_type: ElementType::Unknown as i32,
                payload: watermark_payload,
            });
        }

        let mut sorted = self.snapshot.elements.clone();
        sorted.sort_by(|a, b| {
            a.z_index
                .cmp(&b.z_index)
                .then_with(|| a.id.as_str().cmp(b.id.as_str()))
        });

        for element in sorted {
            tasks.push(FrameTask {
                kind: map_frame_task_kind(element.element_type) as i32,
                element_id: element.id,
                element_type: element.element_type,
                payload: element.payload,
            });
        }

        if let Some(payload) = snap_guides_payload(
            &self.snapshot.global_elements_payload,
            self.snapshot.interaction_mode,
            &self.runtime_snap_guides,
        ) {
            tasks.push(FrameTask {
                kind: FrameTaskKind::SnapGuides as i32,
                element_id: String::new(),
                element_type: ElementType::Unknown as i32,
                payload,
            });
        }

        if let Some(payload) = hover_outline_payload(&self.snapshot) {
            tasks.push(FrameTask {
                kind: FrameTaskKind::HoverOutline as i32,
                element_id: String::new(),
                element_type: ElementType::Unknown as i32,
                payload,
            });
        }

        if !self.snapshot.selected_ids.is_empty() {
            tasks.push(FrameTask {
                kind: FrameTaskKind::SelectionOutline as i32,
                element_id: String::new(),
                element_type: ElementType::Unknown as i32,
                payload: Vec::new(),
            });
            tasks.push(FrameTask {
                kind: FrameTaskKind::SelectionControls as i32,
                element_id: String::new(),
                element_type: ElementType::Unknown as i32,
                payload: Vec::new(),
            });
            if let Some(payload) = arrow_point_overlay_payload(&self.snapshot) {
                tasks.push(FrameTask {
                    kind: FrameTaskKind::ArrowPointOverlay as i32,
                    element_id: String::new(),
                    element_type: ElementType::Unknown as i32,
                    payload,
                });
            }
        }
        if let Some(payload) = arrow_binding_highlight_payload(&self.snapshot) {
            tasks.push(FrameTask {
                kind: FrameTaskKind::ArrowBindingHighlight as i32,
                element_id: String::new(),
                element_type: ElementType::Unknown as i32,
                payload,
            });
        }

        if self.snapshot.interaction_mode == InteractionMode::BoxSelecting as i32 {
            let payload = self
                .box_select_start
                .as_ref()
                .zip(self.box_select_current.as_ref())
                .and_then(|(start, current)| box_selection_payload(start, current))
                .unwrap_or_default();
            tasks.push(FrameTask {
                kind: FrameTaskKind::BoxSelection as i32,
                element_id: String::new(),
                element_type: ElementType::Unknown as i32,
                payload,
            });
        }

        let scale = if request.scale_factor.is_finite() && request.scale_factor > 0.0 {
            request.scale_factor
        } else if self.config.scale_factor.is_finite() && self.config.scale_factor > 0.0 {
            self.config.scale_factor
        } else {
            1.0
        };

        FrameRenderPlan {
            schema_version: self.snapshot.schema_version,
            camera: self.snapshot.camera.clone(),
            scale_factor: scale,
            locale_tag: if request.locale_tag.is_empty() {
                self.config.locale_tag.clone()
            } else {
                request.locale_tag
            },
            tasks,
        }
    }

    pub fn build_frame_plan_bytes(&self, request_bytes: &[u8]) -> Result<Vec<u8>, EngineCoreError> {
        let request: FramePlanRequest =
            decode_message(request_bytes).map_err(|e| EngineCoreError::Decode(e.to_string()))?;
        Ok(encode_message(&self.build_frame_plan(request)))
    }

    pub fn poll_event(&mut self) -> Option<EngineEvent> {
        self.events.pop_front()
    }

    pub fn poll_event_bytes(&mut self) -> Option<Vec<u8>> {
        self.poll_event().map(|event| encode_message(&event))
    }

    fn record_history(&mut self) {
        self.undo_stack.push(self.snapshot.clone());
        self.redo_stack.clear();
        self.sync_history_lengths();
    }

    fn apply_runtime_snap_config_patch(&mut self, patch: RuntimeSnapConfigPatch) -> bool {
        let mut next = self.runtime_snap_config;
        let mut changed = false;
        if let Some(value) = patch.grid_enabled {
            if next.grid_enabled != value {
                next.grid_enabled = value;
                changed = true;
            }
        }
        if let Some(value) = patch.object_enabled {
            if next.object_enabled != value {
                next.object_enabled = value;
                changed = true;
            }
        }
        if let Some(value) = patch.grid_size {
            let resolved = sanitize_grid_size(value);
            if (next.grid_size - resolved).abs() > f64::EPSILON {
                next.grid_size = resolved;
                changed = true;
            }
        }
        if let Some(value) = patch.object_distance {
            let resolved = sanitize_snap_distance(value);
            if (next.object_distance - resolved).abs() > f64::EPSILON {
                next.object_distance = resolved;
                changed = true;
            }
        }
        if changed {
            self.runtime_snap_config = next;
        }
        changed
    }

    fn runtime_default_opacity_for_element_type(&self, element_type: i32) -> Option<f64> {
        let style_defaults = self
            .runtime_style_defaults
            .style_for_element_type(element_type)?;
        style_default_opacity_from_map(style_defaults)
    }

    fn resolve_runtime_default_payload_map_and_opacity(
        &self,
        element_type: i32,
    ) -> (JsonMap<String, JsonValue>, f64) {
        let mut payload_map = default_element_payload_map(element_type);
        let opacity = self
            .runtime_style_defaults
            .style_for_element_type(element_type)
            .map(|style_defaults| {
                apply_style_defaults_to_payload_map(element_type, &mut payload_map, style_defaults)
            })
            .unwrap_or(1.0);
        if normalize_element_type(element_type) == ElementType::SerialNumber as i32 {
            apply_next_serial_number_default(&self.snapshot.elements, &mut payload_map);
        }
        (payload_map, opacity)
    }

    fn resolve_runtime_snapping_mode(&self, snap_override: bool) -> RuntimeSnappingMode {
        if snap_override {
            return RuntimeSnappingMode::None;
        }
        if self.runtime_snap_config.object_enabled {
            if self.runtime_snap_config.grid_enabled {
                return RuntimeSnappingMode::Grid;
            }
            return RuntimeSnappingMode::Object;
        }
        if self.runtime_snap_config.grid_enabled {
            return RuntimeSnappingMode::Grid;
        }
        RuntimeSnappingMode::None
    }

    fn maybe_snap_point(
        &self,
        point: DrawPoint,
        mode: RuntimeSnappingMode,
        excluded_ids: &BTreeSet<String>,
    ) -> SnappedPointResult {
        match mode {
            RuntimeSnappingMode::None => SnappedPointResult {
                point,
                guides: Vec::new(),
            },
            RuntimeSnappingMode::Grid => {
                let snapped = DrawPoint {
                    x: snap_value_to_grid(point.x, self.runtime_snap_config.grid_size),
                    y: snap_value_to_grid(point.y, self.runtime_snap_config.grid_size),
                    pressure: point.pressure,
                    timestamp_us: point.timestamp_us,
                };
                SnappedPointResult {
                    guides: point_snap_guides(&point, &snapped),
                    point: snapped,
                }
            }
            RuntimeSnappingMode::Object => {
                let point_rect = DrawRect {
                    min_x: point.x,
                    min_y: point.y,
                    max_x: point.x,
                    max_y: point.y,
                };
                let snapped_result = self.object_snap_result_for_rect(&point_rect, excluded_ids);
                let snapped = DrawPoint {
                    x: point.x + snapped_result.dx,
                    y: point.y + snapped_result.dy,
                    pressure: point.pressure,
                    timestamp_us: point.timestamp_us,
                };
                SnappedPointResult {
                    guides: point_snap_guides(&point, &snapped),
                    point: snapped,
                }
            }
        }
    }

    fn object_snap_result_for_rect(
        &self,
        target_rect: &DrawRect,
        excluded_ids: &BTreeSet<String>,
    ) -> ObjectSnapResult {
        let max_distance = self.runtime_snap_config.object_distance;
        if max_distance <= 0.0 || !max_distance.is_finite() {
            return ObjectSnapResult::default();
        }

        let mut reference_anchors_x = Vec::new();
        let mut reference_anchors_y = Vec::new();
        for element in &self.snapshot.elements {
            if excluded_ids.contains(&element.id) {
                continue;
            }
            let Some(rect) = element.rect.as_ref() else {
                continue;
            };
            reference_anchors_x.extend(rect_axis_anchors_x(rect));
            reference_anchors_y.extend(rect_axis_anchors_y(rect));
        }
        if reference_anchors_x.is_empty() && reference_anchors_y.is_empty() {
            return ObjectSnapResult::default();
        }

        let target_anchors_x = rect_axis_anchors_x(target_rect);
        let target_anchors_y = rect_axis_anchors_y(target_rect);
        let x_match = best_anchor_match(&target_anchors_x, &reference_anchors_x, max_distance);
        let y_match = best_anchor_match(&target_anchors_y, &reference_anchors_y, max_distance);

        ObjectSnapResult {
            dx: x_match.map(|item| item.offset).unwrap_or(0.0),
            dy: y_match.map(|item| item.offset).unwrap_or(0.0),
            x_match,
            y_match,
        }
    }

    fn object_snap_resize_rect(
        &self,
        rect: DrawRect,
        mode: ResizeMode,
        from_center: bool,
        excluded_ids: &BTreeSet<String>,
    ) -> (DrawRect, Vec<JsonValue>) {
        if from_center {
            return (rect, Vec::new());
        }
        let max_distance = self.runtime_snap_config.object_distance;
        if max_distance <= 0.0 || !max_distance.is_finite() {
            return (rect, Vec::new());
        }

        let mut reference_anchors_x = Vec::new();
        let mut reference_anchors_y = Vec::new();
        for element in &self.snapshot.elements {
            if excluded_ids.contains(&element.id) {
                continue;
            }
            let Some(candidate) = element.rect.as_ref() else {
                continue;
            };
            reference_anchors_x.extend(rect_axis_anchors_x(candidate));
            reference_anchors_y.extend(rect_axis_anchors_y(candidate));
        }
        if reference_anchors_x.is_empty() && reference_anchors_y.is_empty() {
            return (rect, Vec::new());
        }

        let mut snapped = rect;
        let mut x_match = None;
        let mut y_match = None;
        let (move_left, move_right, move_top, move_bottom) = resize_mode_axes(mode);

        if move_left || move_right {
            let target_x = match (move_left, move_right) {
                (true, true) => vec![snapped.min_x, snapped.max_x],
                (true, false) => vec![snapped.min_x],
                (false, true) => vec![snapped.max_x],
                (false, false) => Vec::new(),
            };
            if !target_x.is_empty() {
                x_match = best_anchor_match(&target_x, &reference_anchors_x, max_distance);
                let offset = x_match.map(|item| item.offset).unwrap_or(0.0);
                apply_resize_horizontal_offset(&mut snapped, offset, move_left, move_right);
            }
        }

        if move_top || move_bottom {
            let target_y = match (move_top, move_bottom) {
                (true, true) => vec![snapped.min_y, snapped.max_y],
                (true, false) => vec![snapped.min_y],
                (false, true) => vec![snapped.max_y],
                (false, false) => Vec::new(),
            };
            if !target_y.is_empty() {
                y_match = best_anchor_match(&target_y, &reference_anchors_y, max_distance);
                let offset = y_match.map(|item| item.offset).unwrap_or(0.0);
                apply_resize_vertical_offset(&mut snapped, offset, move_top, move_bottom);
            }
        }

        let normalized = normalize_rect(snapped);
        let guides = rect_snap_guides_with_matches(&normalized, x_match, y_match);
        (normalized, guides)
    }

    fn set_runtime_snap_guides(&mut self, guides: Vec<JsonValue>) {
        self.runtime_snap_guides = guides;
    }

    fn clear_runtime_snap_guides(&mut self) {
        self.runtime_snap_guides.clear();
    }

    fn apply_select(&mut self, payload: SelectElementCommand) {
        let mut selected = selected_set(&self.snapshot);
        if payload.add_to_selection {
            if !payload.element_id.is_empty() {
                selected.insert(payload.element_id);
            }
        } else {
            selected.clear();
            if !payload.element_id.is_empty() {
                selected.insert(payload.element_id);
            }
        }
        self.set_selected(selected);
    }

    fn apply_clear_selection(&mut self) {
        self.set_selected(BTreeSet::new());
    }

    fn apply_select_all(&mut self) {
        let selected = self
            .snapshot
            .elements
            .iter()
            .map(|element| element.id.clone())
            .collect::<BTreeSet<_>>();
        self.set_selected(selected);
    }

    fn apply_create(&mut self, payload: CreateElementCommand) {
        let element_type = normalize_element_type(payload.element_type);
        let id = if payload.element_id.trim().is_empty() {
            let generated = format!("rust_{}", self.next_element_sequence);
            self.next_element_sequence += 1;
            generated
        } else {
            payload.element_id
        };
        let snap_mode = self.resolve_runtime_snapping_mode(payload.snap_override);

        let point = payload.position.unwrap_or(DrawPoint {
            x: 0.0,
            y: 0.0,
            pressure: 0.0,
            timestamp_us: 0,
        });
        let snapped = self.maybe_snap_point(point, snap_mode, &BTreeSet::new());
        let point = snapped.point;
        self.set_runtime_snap_guides(snapped.guides);

        let z_index = self
            .snapshot
            .elements
            .iter()
            .map(|element| element.z_index)
            .max()
            .unwrap_or(-1)
            + 1;
        let default_opacity = self
            .runtime_default_opacity_for_element_type(element_type)
            .unwrap_or(1.0);
        let (resolved_payload, resolved_opacity) = if payload.initial_payload.is_empty() {
            let (payload_map, opacity) =
                self.resolve_runtime_default_payload_map_and_opacity(element_type);
            (encode_json_map(&payload_map), opacity)
        } else {
            (payload.initial_payload, default_opacity)
        };

        let rect = DrawRect {
            min_x: point.x,
            min_y: point.y,
            max_x: point.x + 120.0,
            max_y: point.y + 80.0,
        };

        self.snapshot.elements.push(Element {
            id: id.clone(),
            element_type,
            rect: Some(rect),
            rotation: 0.0,
            opacity: resolved_opacity,
            z_index,
            payload: resolved_payload,
        });

        self.sort_elements();
        self.snapshot.document_version += 1;
        self.set_selected(BTreeSet::from([id]));
        self.creating_element_id = self.snapshot.selected_ids.first().cloned();
        self.creating_start_position = Some(point);
        self.set_interaction_mode(InteractionMode::Creating);
    }

    fn apply_update_creating(&mut self, payload: UpdateCreatingElementCommand) {
        let Some(creating_id) = self.creating_element_id.clone() else {
            return;
        };
        let Some(last_position) = payload.positions.last().cloned() else {
            return;
        };
        let snap_mode = self.resolve_runtime_snapping_mode(payload.snap_override);
        let mut excluded_ids = BTreeSet::new();
        excluded_ids.insert(creating_id.clone());
        let snapped = self.maybe_snap_point(last_position, snap_mode, &excluded_ids);
        self.set_runtime_snap_guides(snapped.guides);
        let last_position = snapped.point;
        let creating_start_position = self.creating_start_position.clone();
        let Some(element) = self.element_mut(&creating_id) else {
            return;
        };
        let start = creating_start_position
            .or_else(|| {
                element.rect.as_ref().map(|rect| DrawPoint {
                    x: rect.min_x,
                    y: rect.min_y,
                    pressure: 0.0,
                    timestamp_us: 0,
                })
            })
            .unwrap_or(DrawPoint {
                x: last_position.x,
                y: last_position.y,
                pressure: 0.0,
                timestamp_us: 0,
            });
        element.rect = Some(create_rect_from_points(
            start,
            last_position,
            payload.maintain_aspect_ratio,
            payload.create_from_center,
        ));
        self.snapshot.document_version += 1;
    }

    fn apply_add_arrow_point(&mut self, payload: AddArrowPointCommand) {
        let Some(creating_id) = self.creating_element_id.clone() else {
            return;
        };
        let Some(position) = payload.position else {
            return;
        };
        let snap_mode = self.resolve_runtime_snapping_mode(payload.snap_override);
        let mut excluded_ids = BTreeSet::new();
        excluded_ids.insert(creating_id.clone());
        let snapped = self.maybe_snap_point(position, snap_mode, &excluded_ids);
        self.set_runtime_snap_guides(snapped.guides);
        let position = snapped.point;
        let Some(element) = self.element_mut(&creating_id) else {
            return;
        };
        let resolved_type = ElementType::try_from(normalize_element_type(element.element_type))
            .unwrap_or(ElementType::Unknown);
        if resolved_type != ElementType::Arrow && resolved_type != ElementType::Line {
            return;
        }
        let Some(rect) = element.rect.clone() else {
            return;
        };

        let mut map = decode_json_map(&element.payload)
            .unwrap_or_else(|| default_element_payload_map(element.element_type));
        let mut world_points = decode_arrow_points_world(&map, &rect);
        if world_points.len() < 2 {
            world_points = vec![
                DrawPoint {
                    x: rect.min_x,
                    y: rect.min_y,
                    pressure: 0.0,
                    timestamp_us: 0,
                },
                DrawPoint {
                    x: rect.max_x,
                    y: rect.max_y,
                    pressure: 0.0,
                    timestamp_us: 0,
                },
            ];
        }
        world_points.push(position);
        let next_rect = arrow_points_bounds(&world_points);
        map.insert(
            "points".to_string(),
            JsonValue::Array(encode_arrow_points_for_rect(&world_points, &next_rect)),
        );
        let next_payload = encode_json_map(&map);

        let mut changed = false;
        if element.payload != next_payload {
            element.payload = next_payload;
            changed = true;
        }
        if element.rect.as_ref() != Some(&next_rect) {
            element.rect = Some(next_rect);
            changed = true;
        }
        if changed {
            self.snapshot.document_version += 1;
        }
    }

    fn apply_finish_create(&mut self) {
        self.creating_element_id = None;
        self.creating_start_position = None;
        self.clear_runtime_snap_guides();
        self.set_interaction_mode(InteractionMode::Idle);
    }

    fn apply_cancel_create(&mut self) {
        if let Some(creating_id) = self.creating_element_id.clone() {
            let original_len = self.snapshot.elements.len();
            self.snapshot
                .elements
                .retain(|element| element.id != creating_id);
            if original_len != self.snapshot.elements.len() {
                self.snapshot.document_version += 1;
            }
        }
        self.creating_element_id = None;
        self.creating_start_position = None;
        self.clear_runtime_snap_guides();
        self.set_selected(BTreeSet::new());
        self.set_interaction_mode(InteractionMode::Idle);
    }

    fn apply_delete(&mut self, element_ids: Vec<String>) {
        if element_ids.is_empty() {
            return;
        }

        let ids = element_ids.into_iter().collect::<BTreeSet<_>>();
        let original_len = self.snapshot.elements.len();
        self.snapshot
            .elements
            .retain(|element| !ids.contains(element.id.as_str()));

        if self.snapshot.elements.len() != original_len {
            self.snapshot.document_version += 1;
            let mut selected = selected_set(&self.snapshot);
            selected.retain(|id| !ids.contains(id));
            self.set_selected(selected);
        }
    }

    fn apply_update_style(&mut self, payload: UpdateElementsStyleCommand) {
        if payload.element_ids.is_empty() {
            return;
        }
        let ids = payload.element_ids.into_iter().collect::<BTreeSet<_>>();
        let mut changed = false;
        let style_map = decode_json_map(&payload.style_payload);

        for element in &mut self.snapshot.elements {
            if !ids.contains(element.id.as_str()) {
                continue;
            }

            if let Some(style_map) = style_map.as_ref() {
                let mut element_map = decode_json_map(&element.payload)
                    .unwrap_or_else(|| default_element_payload_map(element.element_type));
                let mut payload_changed = false;
                for (key, value) in style_map {
                    if key == "opacity" {
                        if let Some(opacity) = value.as_f64() {
                            let clamped = opacity.clamp(0.0, 1.0);
                            if (element.opacity - clamped).abs() > f64::EPSILON {
                                element.opacity = clamped;
                                changed = true;
                            }
                        }
                        continue;
                    }

                    let target_key = normalize_style_field_key(element.element_type, key);
                    let should_write = match element_map.get(target_key) {
                        Some(current) => current != value,
                        None => true,
                    };
                    if should_write {
                        element_map.insert(target_key.to_string(), value.clone());
                        payload_changed = true;
                    }
                }
                if payload_changed {
                    element.payload = encode_json_map(&element_map);
                    changed = true;
                }
            } else if element.payload != payload.style_payload {
                // Preserve binary compatibility for callers that still send opaque style blobs.
                element.payload = payload.style_payload.clone();
                changed = true;
            }
        }

        if changed {
            self.snapshot.document_version += 1;
        }
    }

    fn apply_duplicate(&mut self, payload: DuplicateElementsCommand) {
        if payload.element_ids.is_empty() {
            return;
        }
        let ids = payload.element_ids.iter().collect::<BTreeSet<_>>();
        let mut clones = Vec::new();
        let mut selected = BTreeSet::new();
        let mut next_z = self
            .snapshot
            .elements
            .iter()
            .map(|element| element.z_index)
            .max()
            .unwrap_or(-1)
            + 1;

        for element in self.snapshot.elements.clone() {
            if !ids.contains(&element.id) {
                continue;
            }
            let id = format!("rust_{}", self.next_element_sequence);
            self.next_element_sequence += 1;
            let rect = element.rect.map(|rect| DrawRect {
                min_x: rect.min_x + payload.offset_x,
                min_y: rect.min_y + payload.offset_y,
                max_x: rect.max_x + payload.offset_x,
                max_y: rect.max_y + payload.offset_y,
            });
            clones.push(Element {
                id: id.clone(),
                element_type: element.element_type,
                rect,
                rotation: element.rotation,
                opacity: element.opacity,
                z_index: next_z,
                payload: element.payload.clone(),
            });
            selected.insert(id);
            next_z += 1;
        }

        if clones.is_empty() {
            return;
        }
        self.snapshot.elements.extend(clones);
        self.sort_elements();
        self.snapshot.document_version += 1;
        self.set_selected(selected);
    }

    fn apply_change_element_z_index(&mut self, payload: ChangeElementZIndexCommand) {
        if payload.element_id.is_empty() {
            return;
        }
        self.apply_change_elements_z_index(ChangeElementsZIndexCommand {
            element_ids: vec![payload.element_id],
            operation: payload.operation,
        });
    }

    fn apply_change_elements_z_index(&mut self, payload: ChangeElementsZIndexCommand) {
        if payload.element_ids.is_empty() {
            return;
        }

        let selected = payload.element_ids.into_iter().collect::<BTreeSet<_>>();
        if selected.is_empty() {
            return;
        }

        let operation =
            ZIndexOperation::try_from(payload.operation).unwrap_or(ZIndexOperation::BringToFront);
        let mut ordered = self.snapshot.elements.clone();
        ordered.sort_by(|a, b| {
            a.z_index
                .cmp(&b.z_index)
                .then_with(|| a.id.as_str().cmp(b.id.as_str()))
        });

        match operation {
            ZIndexOperation::BringToFront => {
                ordered.sort_by_key(|element| {
                    if selected.contains(element.id.as_str()) {
                        1
                    } else {
                        0
                    }
                });
            }
            ZIndexOperation::SendToBack => {
                ordered.sort_by_key(|element| {
                    if selected.contains(element.id.as_str()) {
                        0
                    } else {
                        1
                    }
                });
            }
            ZIndexOperation::BringForward => {
                if ordered.len() > 1 {
                    for index in (0..ordered.len() - 1).rev() {
                        let current = selected.contains(ordered[index].id.as_str());
                        let next = selected.contains(ordered[index + 1].id.as_str());
                        if current && !next {
                            ordered.swap(index, index + 1);
                        }
                    }
                }
            }
            ZIndexOperation::SendBackward => {
                if ordered.len() > 1 {
                    for index in 1..ordered.len() {
                        let current = selected.contains(ordered[index].id.as_str());
                        let prev = selected.contains(ordered[index - 1].id.as_str());
                        if current && !prev {
                            ordered.swap(index - 1, index);
                        }
                    }
                }
            }
        }

        for (index, element) in ordered.iter_mut().enumerate() {
            element.z_index = index as i32;
        }
        self.snapshot.elements = ordered;
        self.snapshot.document_version += 1;
    }

    fn apply_update_global_elements(&mut self, payload: UpdateGlobalElementsCommand) {
        let normalized = if let Some(mut map) = decode_json_map(&payload.payload) {
            if let Some(patch) = extract_runtime_snap_config_patch(&mut map) {
                self.apply_runtime_snap_config_patch(patch);
            }
            encode_global_payload_map(map)
        } else {
            payload.payload
        };
        if self.snapshot.global_elements_payload != normalized {
            self.snapshot.global_elements_payload = normalized;
            self.snapshot.document_version += 1;
        }
    }

    fn apply_create_serial_number_text_elements(
        &mut self,
        payload: CreateSerialNumberTextElementsCommand,
    ) {
        if payload.element_ids.is_empty() {
            return;
        }

        let source_ids = payload.element_ids.into_iter().collect::<BTreeSet<_>>();
        let focus_source_id = if source_ids.len() == 1 {
            source_ids.iter().next().cloned()
        } else {
            None
        };
        let mut next_z = self
            .snapshot
            .elements
            .iter()
            .map(|element| element.z_index)
            .max()
            .unwrap_or(-1)
            + 1;
        let mut created = Vec::new();
        let mut serial_payload_updates = Vec::new();
        let mut focus_text_id = None;
        let (text_payload_template, text_opacity) =
            self.resolve_runtime_default_payload_map_and_opacity(ElementType::Text as i32);

        for source in self.snapshot.elements.clone() {
            if !source_ids.contains(source.id.as_str()) {
                continue;
            }
            let source_id = source.id.clone();
            if normalize_element_type(source.element_type) != ElementType::SerialNumber as i32 {
                continue;
            }

            let mut serial_payload = decode_json_map(&source.payload)
                .unwrap_or_else(|| default_element_payload_map(ElementType::SerialNumber as i32));
            let existing_bound_id = serial_payload
                .get("textElementId")
                .and_then(JsonValue::as_str)
                .map(str::trim)
                .filter(|value| !value.is_empty())
                .map(ToOwned::to_owned);
            if let Some(bound_id) = existing_bound_id {
                let has_bound_text = self.snapshot.elements.iter().any(|element| {
                    element.id == bound_id
                        && normalize_element_type(element.element_type) == ElementType::Text as i32
                });
                if has_bound_text {
                    if focus_source_id.as_deref() == Some(source_id.as_str()) {
                        focus_text_id = Some(bound_id);
                    }
                    continue;
                }
            }

            let id = format!("rust_{}", self.next_element_sequence);
            self.next_element_sequence += 1;
            let text_payload = text_payload_template.clone();
            let rect = source.rect.as_ref().map(|source_rect| {
                resolve_serial_bound_text_rect(source_rect, &serial_payload, &text_payload)
            });
            created.push(Element {
                id: id.clone(),
                element_type: ElementType::Text as i32,
                rect,
                rotation: 0.0,
                opacity: text_opacity,
                z_index: next_z,
                payload: encode_json_map(&text_payload),
            });
            serial_payload.insert("textElementId".to_string(), JsonValue::from(id.clone()));
            serial_payload_updates.push((source_id.clone(), encode_json_map(&serial_payload)));
            if focus_source_id.as_deref() == Some(source_id.as_str()) {
                focus_text_id = Some(id);
            }
            next_z += 1;
        }

        let mut changed = false;
        for (serial_id, updated_payload) in serial_payload_updates {
            if let Some(element) = self.element_mut(&serial_id) {
                if element.payload != updated_payload {
                    element.payload = updated_payload;
                    changed = true;
                }
            }
        }
        if !created.is_empty() {
            self.snapshot.elements.extend(created);
            self.sort_elements();
            changed = true;
        }
        if changed {
            self.snapshot.document_version += 1;
        }
        if let Some(focused_text_id) = focus_text_id {
            let (text, rect) = self
                .snapshot
                .elements
                .iter()
                .find(|element| element.id == focused_text_id)
                .map(|element| {
                    let text = decode_json_map(&element.payload)
                        .and_then(|map| {
                            map.get("text")
                                .and_then(JsonValue::as_str)
                                .map(str::to_string)
                        })
                        .unwrap_or_default();
                    (text, element.rect.clone())
                })
                .unwrap_or_else(|| (String::new(), None));
            self.set_selected(BTreeSet::from([focused_text_id.clone()]));
            self.set_interaction_mode(InteractionMode::TextEditing);
            self.text_edit_session = Some(TextEditSession {
                element_id: focused_text_id,
                is_new: false,
                text,
                rect,
            });
        }
    }

    fn apply_start_text_edit(&mut self, payload: StartTextEditCommand) {
        let requested_id = payload.element_id.trim().to_string();
        let (element_id, is_new) = if requested_id.is_empty() {
            (format!("rust_{}", self.next_element_sequence), true)
        } else if self.element_index(&requested_id).is_some() {
            (requested_id, false)
        } else {
            (requested_id, true)
        };

        if is_new {
            if payload.element_id.trim().is_empty() {
                self.next_element_sequence += 1;
            }
            let point = payload.position.unwrap_or(DrawPoint {
                x: 0.0,
                y: 0.0,
                pressure: 0.0,
                timestamp_us: 0,
            });
            let z_index = self
                .snapshot
                .elements
                .iter()
                .map(|element| element.z_index)
                .max()
                .unwrap_or(-1)
                + 1;
            let (text_payload, text_opacity) =
                self.resolve_runtime_default_payload_map_and_opacity(ElementType::Text as i32);
            let fallback_layout =
                fallback_text_metrics_for_payload(&text_payload, f64::INFINITY, None);
            let initial_width = fallback_layout.width.max(TEXT_MIN_WIDTH).max(1.0);
            let initial_height = fallback_layout
                .height
                .max(fallback_layout.line_height)
                .max(1.0);
            self.snapshot.elements.push(Element {
                id: element_id.clone(),
                element_type: ElementType::Text as i32,
                rect: Some(DrawRect {
                    min_x: point.x,
                    min_y: point.y,
                    max_x: point.x + initial_width,
                    max_y: point.y + initial_height,
                }),
                rotation: 0.0,
                opacity: text_opacity,
                z_index,
                payload: encode_json_map(&text_payload),
            });
            self.sort_elements();
            self.snapshot.document_version += 1;
        }

        self.set_selected(BTreeSet::from([element_id.clone()]));
        self.set_interaction_mode(InteractionMode::TextEditing);
        self.text_edit_session = Some(TextEditSession {
            element_id,
            is_new,
            text: String::new(),
            rect: None,
        });
    }

    fn apply_update_text_edit(&mut self, payload: UpdateTextEditCommand) {
        let Some(session) = self.text_edit_session.as_mut() else {
            return;
        };
        session.text = payload.text.clone();
        session.rect = payload.rect.clone();
        let element_id = session.element_id.clone();
        let text = payload.text;
        let rect = payload.rect;
        if let Some(element) = self.element_mut(&element_id) {
            write_text_payload(element, &text);
            if let Some(rect) = rect {
                element.rect = Some(rect);
            }
            self.snapshot.document_version += 1;
        }
    }

    fn apply_finish_text_edit(&mut self, payload: FinishTextEditCommand) {
        let mut session = self.text_edit_session.take().unwrap_or(TextEditSession {
            element_id: payload.element_id.clone(),
            is_new: payload.is_new,
            text: payload.text.clone(),
            rect: None,
        });

        if !payload.element_id.trim().is_empty() {
            session.element_id = payload.element_id.clone();
        }
        session.is_new = payload.is_new;
        session.text = payload.text.clone();

        if session.text.trim().is_empty() && session.is_new {
            let original = self.snapshot.elements.len();
            self.snapshot
                .elements
                .retain(|element| element.id != session.element_id);
            if original != self.snapshot.elements.len() {
                self.snapshot.document_version += 1;
            }
        } else if let Some(element) = self.element_mut(&session.element_id) {
            write_text_payload(element, &session.text);
            if let Some(rect) = session.rect {
                element.rect = Some(rect);
            }
            self.snapshot.document_version += 1;
        }

        self.set_interaction_mode(InteractionMode::Idle);
    }

    fn apply_cancel_text_edit(&mut self) {
        if let Some(session) = self.text_edit_session.take() {
            if session.is_new {
                let original = self.snapshot.elements.len();
                self.snapshot
                    .elements
                    .retain(|element| element.id != session.element_id);
                if original != self.snapshot.elements.len() {
                    self.snapshot.document_version += 1;
                }
            }
        }
        self.set_interaction_mode(InteractionMode::Idle);
    }

    fn apply_refresh_auto_resize_text_layouts_after_font_load(&mut self) -> bool {
        let mut changed = false;

        for element in &mut self.snapshot.elements {
            if normalize_element_type(element.element_type) != ElementType::Text as i32 {
                continue;
            }

            let payload_map = decode_json_map(&element.payload)
                .unwrap_or_else(|| default_element_payload_map(ElementType::Text as i32));
            let auto_resize = payload_map
                .get("autoResize")
                .and_then(JsonValue::as_bool)
                .unwrap_or(true);
            if !auto_resize {
                continue;
            }

            let Some(current_rect) = element.rect.clone() else {
                continue;
            };
            let next_rect =
                resolve_auto_resize_text_rect(current_rect.min_x, current_rect.min_y, &payload_map);
            if rects_close(&current_rect, &next_rect) {
                continue;
            }

            element.rect = Some(next_rect);
            changed = true;
        }

        if changed {
            self.snapshot.document_version += 1;
        }

        changed
    }

    fn apply_start_edit(&mut self, payload: engine_proto::StartEditCommand) {
        let operation_id = payload.operation_id.trim().to_string();
        let params = decode_json_map(&payload.params);
        let start = payload.position.unwrap_or(DrawPoint {
            x: 0.0,
            y: 0.0,
            pressure: 0.0,
            timestamp_us: 0,
        });
        let mut baseline_rects = self
            .snapshot
            .selected_ids
            .iter()
            .filter_map(|id| {
                self.snapshot
                    .elements
                    .iter()
                    .find(|element| element.id == *id)
                    .and_then(|element| element.rect.clone())
                    .map(|rect| (id.clone(), rect))
            })
            .collect::<BTreeMap<_, _>>();
        let mut baseline_rotations = self
            .snapshot
            .selected_ids
            .iter()
            .filter_map(|id| {
                self.snapshot
                    .elements
                    .iter()
                    .find(|element| element.id == *id)
                    .map(|element| (id.clone(), element.rotation))
            })
            .collect::<BTreeMap<_, _>>();
        let mut baseline_payloads = self
            .snapshot
            .selected_ids
            .iter()
            .filter_map(|id| {
                self.snapshot
                    .elements
                    .iter()
                    .find(|element| element.id == *id)
                    .map(|element| (id.clone(), element.payload.clone()))
            })
            .collect::<BTreeMap<_, _>>();

        let mut operation =
            resolve_edit_operation(operation_id.as_str(), params.as_ref(), &baseline_rects);
        if let EditSessionOperation::ArrowPoint { element_id, .. } = &operation {
            if !baseline_rects.contains_key(element_id) {
                if let Some(element) = self
                    .snapshot
                    .elements
                    .iter()
                    .find(|entry| entry.id == *element_id)
                {
                    if let Some(rect) = element.rect.clone() {
                        baseline_rects.insert(element_id.clone(), rect);
                    }
                    baseline_rotations.insert(element_id.clone(), element.rotation);
                    baseline_payloads.insert(element_id.clone(), element.payload.clone());
                } else {
                    operation = EditSessionOperation::Unknown;
                }
            }
        }

        self.edit_session = Some(EditSession {
            operation,
            start_position: start,
            baseline_rects,
            baseline_rotations,
            baseline_payloads,
        });
        self.clear_runtime_snap_guides();
        self.set_interaction_mode(InteractionMode::Editing);
    }

    fn apply_update_edit(&mut self, payload: UpdateEditCommand) {
        let Some(session) = self.edit_session.as_ref().cloned() else {
            return;
        };
        let Some(current) = payload.current_position else {
            return;
        };
        let modifiers = parse_edit_modifiers(&payload.modifiers);

        let changed = match &session.operation {
            EditSessionOperation::Move => self.apply_update_move_edit(
                session.start_position,
                current,
                &session.baseline_rects,
                modifiers.snap_override,
            ),
            EditSessionOperation::Resize { mode } => self.apply_update_resize_edit(
                session.start_position,
                current,
                &session.baseline_rects,
                *mode,
                modifiers.maintain_aspect_ratio,
                modifiers.from_center,
                modifiers.snap_override,
            ),
            EditSessionOperation::Rotate { pivot, snap_angle } => self.apply_update_rotate_edit(
                session.start_position,
                current,
                pivot.clone(),
                *snap_angle,
                modifiers.discrete_angle,
                &session.baseline_rects,
                &session.baseline_rotations,
            ),
            EditSessionOperation::ArrowPoint {
                element_id,
                point_kind,
                point_index,
                delete_point_on_finish,
            } => self.apply_update_arrow_point_edit(
                current,
                &session,
                element_id.as_str(),
                *point_kind,
                *point_index,
                *delete_point_on_finish,
                modifiers.snap_override,
            ),
            EditSessionOperation::Unknown => {
                self.clear_runtime_snap_guides();
                false
            }
        };

        if changed {
            self.snapshot.document_version += 1;
            self.set_interaction_mode(InteractionMode::Editing);
        }
    }

    fn apply_finish_edit(&mut self) {
        let Some(session) = self.edit_session.take() else {
            self.set_interaction_mode(InteractionMode::Idle);
            return;
        };
        let mut changed = false;
        if let EditSessionOperation::ArrowPoint {
            element_id,
            point_kind,
            point_index,
            delete_point_on_finish,
        } = &session.operation
        {
            if *delete_point_on_finish {
                changed = self.apply_finish_arrow_point_edit(
                    &session,
                    element_id.as_str(),
                    *point_kind,
                    *point_index,
                );
            }
        }
        if changed {
            self.snapshot.document_version += 1;
        }
        self.clear_runtime_snap_guides();
        self.set_interaction_mode(InteractionMode::Idle);
    }

    fn apply_cancel_edit(&mut self) {
        let Some(session) = self.edit_session.take() else {
            self.set_interaction_mode(InteractionMode::Idle);
            return;
        };
        let mut changed = false;
        for (element_id, rect) in session.baseline_rects {
            if let Some(element) = self.element_mut(&element_id) {
                element.rect = Some(rect);
                changed = true;
            }
        }
        for (element_id, rotation) in session.baseline_rotations {
            if let Some(element) = self.element_mut(&element_id) {
                if (element.rotation - rotation).abs() > f64::EPSILON {
                    element.rotation = rotation;
                    changed = true;
                }
            }
        }
        for (element_id, payload) in session.baseline_payloads {
            if let Some(element) = self.element_mut(&element_id) {
                if element.payload != payload {
                    element.payload = payload;
                    changed = true;
                }
            }
        }
        if changed {
            self.snapshot.document_version += 1;
        }
        self.clear_runtime_snap_guides();
        self.set_interaction_mode(InteractionMode::Idle);
    }

    fn apply_update_move_edit(
        &mut self,
        start: DrawPoint,
        current: DrawPoint,
        baseline_rects: &BTreeMap<String, DrawRect>,
        snap_override: bool,
    ) -> bool {
        let base_dx = current.x - start.x;
        let base_dy = current.y - start.y;
        let mut dx = base_dx;
        let mut dy = base_dy;
        let snap_mode = self.resolve_runtime_snapping_mode(snap_override);
        let mut guides = Vec::new();
        if let Some(bounds) = selection_bounds_from_rects(baseline_rects) {
            match snap_mode {
                RuntimeSnappingMode::Grid => {
                    let snapped_min_x =
                        snap_value_to_grid(bounds.min_x + dx, self.runtime_snap_config.grid_size);
                    let snapped_min_y =
                        snap_value_to_grid(bounds.min_y + dy, self.runtime_snap_config.grid_size);
                    dx = snapped_min_x - bounds.min_x;
                    dy = snapped_min_y - bounds.min_y;
                    let x_coord = if (snapped_min_x - (bounds.min_x + base_dx)).abs() > f64::EPSILON
                    {
                        Some(snapped_min_x)
                    } else {
                        None
                    };
                    let y_coord = if (snapped_min_y - (bounds.min_y + base_dy)).abs() > f64::EPSILON
                    {
                        Some(snapped_min_y)
                    } else {
                        None
                    };
                    let snapped_bounds = DrawRect {
                        min_x: bounds.min_x + dx,
                        min_y: bounds.min_y + dy,
                        max_x: bounds.max_x + dx,
                        max_y: bounds.max_y + dy,
                    };
                    guides = rect_snap_guides_for_axes(&snapped_bounds, x_coord, y_coord);
                }
                RuntimeSnappingMode::Object => {
                    let moved_bounds = DrawRect {
                        min_x: bounds.min_x + dx,
                        min_y: bounds.min_y + dy,
                        max_x: bounds.max_x + dx,
                        max_y: bounds.max_y + dy,
                    };
                    let excluded_ids = baseline_rects.keys().cloned().collect::<BTreeSet<_>>();
                    let snap_result =
                        self.object_snap_result_for_rect(&moved_bounds, &excluded_ids);
                    dx += snap_result.dx;
                    dy += snap_result.dy;
                    let snapped_bounds = DrawRect {
                        min_x: bounds.min_x + dx,
                        min_y: bounds.min_y + dy,
                        max_x: bounds.max_x + dx,
                        max_y: bounds.max_y + dy,
                    };
                    guides = rect_snap_guides_with_matches(
                        &snapped_bounds,
                        snap_result.x_match,
                        snap_result.y_match,
                    );
                }
                RuntimeSnappingMode::None => {}
            }
        } else if !matches!(snap_mode, RuntimeSnappingMode::None) {
            let snapped = self.maybe_snap_point(current, snap_mode, &BTreeSet::new());
            dx = snapped.point.x - start.x;
            dy = snapped.point.y - start.y;
            guides = snapped.guides;
        }
        self.set_runtime_snap_guides(guides);
        let mut changed = false;
        for (element_id, base_rect) in baseline_rects {
            if let Some(element) = self.element_mut(element_id) {
                element.rect = Some(DrawRect {
                    min_x: base_rect.min_x + dx,
                    min_y: base_rect.min_y + dy,
                    max_x: base_rect.max_x + dx,
                    max_y: base_rect.max_y + dy,
                });
                changed = true;
            }
        }
        changed
    }

    fn apply_update_resize_edit(
        &mut self,
        start: DrawPoint,
        current: DrawPoint,
        baseline_rects: &BTreeMap<String, DrawRect>,
        mode: ResizeMode,
        maintain_aspect_ratio: bool,
        from_center: bool,
        snap_override: bool,
    ) -> bool {
        let dx = current.x - start.x;
        let dy = current.y - start.y;
        let snap_mode = self.resolve_runtime_snapping_mode(snap_override);
        let mut changed = false;
        let mut guides = Vec::new();
        let (move_left, move_right, move_top, move_bottom) = resize_mode_axes(mode);
        let excluded_ids = baseline_rects.keys().cloned().collect::<BTreeSet<_>>();

        for (element_id, base_rect) in baseline_rects {
            let base_width = (base_rect.max_x - base_rect.min_x).abs().max(1.0);
            let base_height = (base_rect.max_y - base_rect.min_y).abs().max(1.0);
            let center = rect_center(base_rect);
            let axis_factor = if from_center { 2.0 } else { 1.0 };

            let signed_width = if move_left {
                base_width - dx * axis_factor
            } else if move_right {
                base_width + dx * axis_factor
            } else {
                base_width
            };
            let signed_height = if move_top {
                base_height - dy * axis_factor
            } else if move_bottom {
                base_height + dy * axis_factor
            } else {
                base_height
            };

            let mut width = signed_width.abs().max(1.0);
            let mut height = signed_height.abs().max(1.0);

            if maintain_aspect_ratio {
                let aspect_ratio = base_width / base_height;
                let horizontal_active = move_left || move_right;
                let vertical_active = move_top || move_bottom;

                if horizontal_active && vertical_active {
                    if (width / height) >= aspect_ratio {
                        height = (width / aspect_ratio).max(1.0);
                    } else {
                        width = (height * aspect_ratio).max(1.0);
                    }
                } else if horizontal_active {
                    height = (width / aspect_ratio).max(1.0);
                } else if vertical_active {
                    width = (height * aspect_ratio).max(1.0);
                }
            }

            let mut rect = if from_center {
                DrawRect {
                    min_x: center.x - width / 2.0,
                    min_y: center.y - height / 2.0,
                    max_x: center.x + width / 2.0,
                    max_y: center.y + height / 2.0,
                }
            } else {
                let anchor_x = if move_left {
                    base_rect.max_x
                } else if move_right {
                    base_rect.min_x
                } else {
                    center.x
                };
                let anchor_y = if move_top {
                    base_rect.max_y
                } else if move_bottom {
                    base_rect.min_y
                } else {
                    center.y
                };

                let width_positive = signed_width >= 0.0;
                let height_positive = signed_height >= 0.0;

                let (min_x, max_x) = if move_left {
                    if width_positive {
                        (anchor_x - width, anchor_x)
                    } else {
                        (anchor_x, anchor_x + width)
                    }
                } else if move_right {
                    if width_positive {
                        (anchor_x, anchor_x + width)
                    } else {
                        (anchor_x - width, anchor_x)
                    }
                } else {
                    (anchor_x - width / 2.0, anchor_x + width / 2.0)
                };

                let (min_y, max_y) = if move_top {
                    if height_positive {
                        (anchor_y - height, anchor_y)
                    } else {
                        (anchor_y, anchor_y + height)
                    }
                } else if move_bottom {
                    if height_positive {
                        (anchor_y, anchor_y + height)
                    } else {
                        (anchor_y - height, anchor_y)
                    }
                } else {
                    (anchor_y - height / 2.0, anchor_y + height / 2.0)
                };

                normalize_rect(DrawRect {
                    min_x,
                    min_y,
                    max_x,
                    max_y,
                })
            };
            if !from_center {
                if matches!(snap_mode, RuntimeSnappingMode::Grid) {
                    let unsnapped = rect.clone();
                    let snapped = snap_rect_to_grid(&rect, self.runtime_snap_config.grid_size);
                    let x_coord = if (snapped.min_x - unsnapped.min_x).abs() > f64::EPSILON
                        || (snapped.max_x - unsnapped.max_x).abs() > f64::EPSILON
                    {
                        Some(if move_left && !move_right {
                            snapped.min_x
                        } else if move_right && !move_left {
                            snapped.max_x
                        } else {
                            (snapped.min_x + snapped.max_x) * 0.5
                        })
                    } else {
                        None
                    };
                    let y_coord = if (snapped.min_y - unsnapped.min_y).abs() > f64::EPSILON
                        || (snapped.max_y - unsnapped.max_y).abs() > f64::EPSILON
                    {
                        Some(if move_top && !move_bottom {
                            snapped.min_y
                        } else if move_bottom && !move_top {
                            snapped.max_y
                        } else {
                            (snapped.min_y + snapped.max_y) * 0.5
                        })
                    } else {
                        None
                    };
                    guides.extend(rect_snap_guides_for_axes(&snapped, x_coord, y_coord));
                    rect = snapped;
                }
                if matches!(snap_mode, RuntimeSnappingMode::Object) {
                    let (snapped, snapped_guides) =
                        self.object_snap_resize_rect(rect, mode, from_center, &excluded_ids);
                    rect = snapped;
                    guides.extend(snapped_guides);
                }
            }
            if let Some(element) = self.element_mut(element_id) {
                element.rect = Some(rect);
                changed = true;
            }
        }

        self.set_runtime_snap_guides(dedupe_snap_guides(guides));
        changed
    }

    fn apply_update_rotate_edit(
        &mut self,
        start: DrawPoint,
        current: DrawPoint,
        pivot: DrawPoint,
        snap_angle: f64,
        discrete_angle: bool,
        baseline_rects: &BTreeMap<String, DrawRect>,
        baseline_rotations: &BTreeMap<String, f64>,
    ) -> bool {
        let start_angle = angle_between_points(&start, &pivot);
        let current_angle = angle_between_points(&current, &pivot);
        let mut delta = normalize_angle_radians(current_angle - start_angle);
        if discrete_angle && snap_angle > 0.0 {
            delta = (delta / snap_angle).round() * snap_angle;
        }

        self.clear_runtime_snap_guides();
        let mut changed = false;
        for (element_id, base_rect) in baseline_rects {
            if let Some(element) = self.element_mut(element_id) {
                let center = rect_center(base_rect);
                let rotated_center = rotate_point_around(&center, &pivot, delta);
                let width = base_rect.max_x - base_rect.min_x;
                let height = base_rect.max_y - base_rect.min_y;
                element.rect = Some(DrawRect {
                    min_x: rotated_center.x - width / 2.0,
                    min_y: rotated_center.y - height / 2.0,
                    max_x: rotated_center.x + width / 2.0,
                    max_y: rotated_center.y + height / 2.0,
                });
                if let Some(base_rotation) = baseline_rotations.get(element_id) {
                    element.rotation = base_rotation + delta;
                } else {
                    element.rotation += delta;
                }
                changed = true;
            }
        }
        changed
    }

    fn apply_update_arrow_point_edit(
        &mut self,
        current: DrawPoint,
        session: &EditSession,
        element_id: &str,
        point_kind: ArrowPointKind,
        point_index: usize,
        delete_point_on_finish: bool,
        snap_override: bool,
    ) -> bool {
        if delete_point_on_finish {
            return false;
        }
        let snap_mode = self.resolve_runtime_snapping_mode(snap_override);
        let mut excluded_ids = BTreeSet::new();
        excluded_ids.insert(element_id.to_string());
        let snapped = self.maybe_snap_point(current, snap_mode, &excluded_ids);
        self.set_runtime_snap_guides(snapped.guides);
        let current = snapped.point;

        let Some(base_rect) = session.baseline_rects.get(element_id) else {
            return false;
        };
        let Some(base_payload) = session.baseline_payloads.get(element_id) else {
            return false;
        };
        let Some(element_index) = self.element_index(element_id) else {
            return false;
        };

        let element_type = self.snapshot.elements[element_index].element_type;
        let resolved_type = ElementType::try_from(normalize_element_type(element_type))
            .unwrap_or(ElementType::Unknown);
        if resolved_type != ElementType::Arrow && resolved_type != ElementType::Line {
            return false;
        }

        let mut payload_map = decode_json_map(base_payload)
            .unwrap_or_else(|| default_element_payload_map(element_type));
        let world_points = decode_arrow_points_world(&payload_map, base_rect);
        let Some((next_world_points, moved_start_endpoint, moved_end_endpoint)) =
            resolve_arrow_point_update(world_points, point_kind, point_index, current)
        else {
            return false;
        };

        let next_rect = arrow_points_bounds(&next_world_points);
        payload_map.insert(
            "points".to_string(),
            JsonValue::Array(encode_arrow_points_for_rect(&next_world_points, &next_rect)),
        );
        if moved_start_endpoint {
            payload_map.remove("startBinding");
        }
        if moved_end_endpoint {
            payload_map.remove("endBinding");
        }
        let next_payload = encode_json_map(&payload_map);

        let mut changed = false;
        if self.snapshot.elements[element_index].payload != next_payload {
            self.snapshot.elements[element_index].payload = next_payload;
            changed = true;
        }
        if self.snapshot.elements[element_index].rect.as_ref() != Some(&next_rect) {
            self.snapshot.elements[element_index].rect = Some(next_rect);
            changed = true;
        }
        changed
    }

    fn apply_finish_arrow_point_edit(
        &mut self,
        session: &EditSession,
        element_id: &str,
        point_kind: ArrowPointKind,
        point_index: usize,
    ) -> bool {
        if point_kind != ArrowPointKind::Turning {
            return false;
        }

        let Some(base_rect) = session.baseline_rects.get(element_id) else {
            return false;
        };
        let Some(base_payload) = session.baseline_payloads.get(element_id) else {
            return false;
        };
        let Some(element_index) = self.element_index(element_id) else {
            return false;
        };

        let element_type = self.snapshot.elements[element_index].element_type;
        let resolved_type = ElementType::try_from(normalize_element_type(element_type))
            .unwrap_or(ElementType::Unknown);
        if resolved_type != ElementType::Arrow && resolved_type != ElementType::Line {
            return false;
        }

        let current_rect = self.snapshot.elements[element_index]
            .rect
            .clone()
            .unwrap_or_else(|| base_rect.clone());
        let mut payload_map = decode_json_map(&self.snapshot.elements[element_index].payload)
            .or_else(|| decode_json_map(base_payload))
            .unwrap_or_else(|| default_element_payload_map(element_type));
        let mut world_points = decode_arrow_points_world(&payload_map, &current_rect);
        if world_points.len() < 3 || point_index == 0 || point_index >= world_points.len() - 1 {
            return false;
        }

        world_points.remove(point_index);
        if world_points.len() < 2 {
            return false;
        }
        let next_rect = arrow_points_bounds(&world_points);
        payload_map.insert(
            "points".to_string(),
            JsonValue::Array(encode_arrow_points_for_rect(&world_points, &next_rect)),
        );
        let next_payload = encode_json_map(&payload_map);

        let mut changed = false;
        if self.snapshot.elements[element_index].payload != next_payload {
            self.snapshot.elements[element_index].payload = next_payload;
            changed = true;
        }
        if self.snapshot.elements[element_index].rect.as_ref() != Some(&next_rect) {
            self.snapshot.elements[element_index].rect = Some(next_rect);
            changed = true;
        }
        changed
    }

    fn apply_set_drag_pending(&mut self, payload: SetDragPendingCommand) {
        self.box_select_start = payload.pointer_down_position;
        self.box_select_current = None;
        self.set_interaction_mode(InteractionMode::DragPending);
    }

    fn apply_start_box_select(&mut self, payload: StartBoxSelectCommand) {
        self.box_select_current = payload.start_position.clone();
        self.box_select_start = payload.start_position;
        self.set_interaction_mode(InteractionMode::BoxSelecting);
    }

    fn apply_update_box_select(&mut self, payload: UpdateBoxSelectCommand) {
        let Some(start) = self.box_select_start.as_ref() else {
            return;
        };
        let current = payload.current_position.unwrap_or_else(|| start.clone());
        self.box_select_current = Some(current.clone());
        let rect = rect_from_points(start.clone(), current, false);

        let selected = self
            .snapshot
            .elements
            .iter()
            .filter(|element| {
                element
                    .rect
                    .as_ref()
                    .is_some_and(|candidate| rects_intersect(candidate, &rect))
            })
            .map(|element| element.id.clone())
            .collect::<BTreeSet<_>>();
        self.set_selected(selected);
    }

    fn apply_move_camera(&mut self, payload: MoveCameraCommand) {
        let camera = self
            .snapshot
            .camera
            .get_or_insert_with(CameraState::default);
        let position = camera.position.get_or_insert(DrawPoint {
            x: 0.0,
            y: 0.0,
            pressure: 0.0,
            timestamp_us: 0,
        });
        position.x += payload.dx;
        position.y += payload.dy;
    }

    fn apply_zoom_camera(&mut self, payload: ZoomCameraCommand) {
        let camera = self
            .snapshot
            .camera
            .get_or_insert_with(CameraState::default);
        let current_zoom = resolve_effective_zoom(camera.zoom);
        let target_zoom = clamp_zoom(current_zoom * payload.scale);
        if (target_zoom - current_zoom).abs() <= f64::EPSILON {
            return;
        }

        let position = camera.position.get_or_insert(DrawPoint {
            x: 0.0,
            y: 0.0,
            pressure: 0.0,
            timestamp_us: 0,
        });
        let center = payload.center.unwrap_or_else(|| position.clone());
        let zoom_ratio = target_zoom / current_zoom;
        position.x += (center.x - position.x) * (1.0 - zoom_ratio);
        position.y += (center.y - position.y) * (1.0 - zoom_ratio);
        camera.zoom = target_zoom;
    }

    fn apply_undo(&mut self) {
        if let Some(previous) = self.undo_stack.pop() {
            self.redo_stack.push(self.snapshot.clone());
            self.snapshot = previous;
            self.reset_ephemeral_state();
            self.sync_history_lengths();
            self.emit_history_changed();
            self.emit_state_changed();
        }
    }

    fn apply_redo(&mut self) {
        if let Some(next) = self.redo_stack.pop() {
            self.undo_stack.push(self.snapshot.clone());
            self.snapshot = next;
            self.reset_ephemeral_state();
            self.sync_history_lengths();
            self.emit_history_changed();
            self.emit_state_changed();
        }
    }

    fn reset_ephemeral_state(&mut self) {
        self.creating_element_id = None;
        self.creating_start_position = None;
        self.text_edit_session = None;
        self.box_select_start = None;
        self.box_select_current = None;
        self.edit_session = None;
        self.clear_runtime_snap_guides();
    }

    fn element_index(&self, element_id: &str) -> Option<usize> {
        self.snapshot
            .elements
            .iter()
            .position(|element| element.id == element_id)
    }

    fn element_mut(&mut self, element_id: &str) -> Option<&mut Element> {
        let index = self.element_index(element_id)?;
        self.snapshot.elements.get_mut(index)
    }

    fn sort_elements(&mut self) {
        self.snapshot.elements.sort_by(|a, b| {
            a.z_index
                .cmp(&b.z_index)
                .then_with(|| a.id.as_str().cmp(b.id.as_str()))
        });
    }

    fn set_interaction_mode(&mut self, mode: InteractionMode) {
        self.snapshot.interaction_mode = mode as i32;
        if !matches!(mode, InteractionMode::Creating | InteractionMode::Editing) {
            self.clear_runtime_snap_guides();
        }
    }

    fn set_selected(&mut self, selected: BTreeSet<String>) {
        let next = selected.into_iter().collect::<Vec<_>>();
        if next != self.snapshot.selected_ids {
            self.snapshot.selected_ids = next;
            self.snapshot.selection_version += 1;
        }
    }

    fn sync_history_lengths(&mut self) {
        self.snapshot.history_undo_len = self.undo_stack.len() as u64;
        self.snapshot.history_redo_len = self.redo_stack.len() as u64;
    }

    fn emit_state_changed(&mut self) {
        self.push_event(EngineEvent {
            kind: EngineEventKind::StateChanged as i32,
            sequence: 0,
            payload: None,
        });
    }

    fn emit_history_changed(&mut self) {
        self.push_event(EngineEvent {
            kind: EngineEventKind::HistoryChanged as i32,
            sequence: 0,
            payload: Some(EventPayload::Message(format!(
                "undo={},redo={}",
                self.snapshot.history_undo_len, self.snapshot.history_redo_len
            ))),
        });
    }

    fn emit_debug(&mut self, message: String) {
        self.push_event(EngineEvent {
            kind: EngineEventKind::Debug as i32,
            sequence: 0,
            payload: Some(EventPayload::Message(message)),
        });
    }

    fn emit_error(&mut self, error: EngineError) {
        self.push_event(EngineEvent {
            kind: EngineEventKind::Error as i32,
            sequence: 0,
            payload: Some(EventPayload::Error(error)),
        });
    }

    fn push_event(&mut self, mut event: EngineEvent) {
        event.sequence = self.next_event_sequence;
        self.next_event_sequence += 1;
        if self.events.len() >= EVENT_QUEUE_LIMIT {
            self.events.pop_front();
        }
        self.events.push_back(event);
    }
}

fn normalize_element_type(element_type: i32) -> i32 {
    match ElementType::try_from(element_type).unwrap_or(ElementType::Unknown) {
        ElementType::Unknown => ElementType::Rectangle as i32,
        value => value as i32,
    }
}

fn point_value(x: f64, y: f64) -> JsonValue {
    JsonValue::Object(JsonMap::from_iter([
        ("x".to_string(), JsonValue::from(x)),
        ("y".to_string(), JsonValue::from(y)),
    ]))
}

fn default_element_payload_map(element_type: i32) -> JsonMap<String, JsonValue> {
    let kind = ElementType::try_from(normalize_element_type(element_type))
        .unwrap_or(ElementType::Rectangle);
    match kind {
        ElementType::Rectangle => JsonMap::from_iter([
            ("typeId".to_string(), JsonValue::from("rectangle")),
            ("cornerRadius".to_string(), JsonValue::from(4.0)),
            ("fillColor".to_string(), JsonValue::from(0u64)),
            ("color".to_string(), JsonValue::from(0xFF1E1E1Eu64)),
            ("strokeWidth".to_string(), JsonValue::from(2.0)),
            ("strokeStyle".to_string(), JsonValue::from("solid")),
            ("fillStyle".to_string(), JsonValue::from("solid")),
        ]),
        ElementType::Arrow => JsonMap::from_iter([
            ("typeId".to_string(), JsonValue::from("arrow")),
            (
                "points".to_string(),
                JsonValue::Array(vec![point_value(0.0, 0.0), point_value(1.0, 1.0)]),
            ),
            ("color".to_string(), JsonValue::from(0xFF1E1E1Eu64)),
            ("strokeWidth".to_string(), JsonValue::from(2.0)),
            ("strokeStyle".to_string(), JsonValue::from("solid")),
            ("arrowType".to_string(), JsonValue::from("straight")),
            ("startArrowhead".to_string(), JsonValue::from("none")),
            ("endArrowhead".to_string(), JsonValue::from("standard")),
        ]),
        ElementType::Line => JsonMap::from_iter([
            ("typeId".to_string(), JsonValue::from("line")),
            (
                "points".to_string(),
                JsonValue::Array(vec![point_value(0.0, 0.0), point_value(1.0, 1.0)]),
            ),
            ("color".to_string(), JsonValue::from(0xFF1E1E1Eu64)),
            ("fillColor".to_string(), JsonValue::from(0u64)),
            ("strokeWidth".to_string(), JsonValue::from(2.0)),
            ("strokeStyle".to_string(), JsonValue::from("solid")),
            ("fillStyle".to_string(), JsonValue::from("solid")),
            ("arrowType".to_string(), JsonValue::from("curved")),
            ("startArrowhead".to_string(), JsonValue::from("none")),
            ("endArrowhead".to_string(), JsonValue::from("none")),
        ]),
        ElementType::FreeDraw => JsonMap::from_iter([
            ("typeId".to_string(), JsonValue::from("free_draw")),
            (
                "points".to_string(),
                JsonValue::Array(vec![point_value(0.0, 0.0), point_value(1.0, 1.0)]),
            ),
            ("color".to_string(), JsonValue::from(0xFF1E1E1Eu64)),
            ("fillColor".to_string(), JsonValue::from(0u64)),
            ("strokeWidth".to_string(), JsonValue::from(2.0)),
            ("strokeStyle".to_string(), JsonValue::from("solid")),
            ("fillStyle".to_string(), JsonValue::from("solid")),
        ]),
        ElementType::Filter => JsonMap::from_iter([
            ("typeId".to_string(), JsonValue::from("filter")),
            ("type".to_string(), JsonValue::from("mosaic")),
            ("strength".to_string(), JsonValue::from(0.5)),
        ]),
        ElementType::Highlight => JsonMap::from_iter([
            ("typeId".to_string(), JsonValue::from("highlight")),
            ("shape".to_string(), JsonValue::from("rectangle")),
            ("color".to_string(), JsonValue::from(0xFFF5222Du64)),
            ("strokeColor".to_string(), JsonValue::from(0xFF000000u64)),
            ("strokeWidth".to_string(), JsonValue::from(0.0)),
        ]),
        ElementType::Text => JsonMap::from_iter([
            ("typeId".to_string(), JsonValue::from("text")),
            ("text".to_string(), JsonValue::from("")),
            ("color".to_string(), JsonValue::from(0xFF1E1E1Eu64)),
            ("fontSize".to_string(), JsonValue::from(21.0)),
            ("fontFamily".to_string(), JsonValue::from("")),
            ("horizontalAlign".to_string(), JsonValue::from("left")),
            ("verticalAlign".to_string(), JsonValue::from("center")),
            ("fillColor".to_string(), JsonValue::from(0u64)),
            ("fillStyle".to_string(), JsonValue::from("solid")),
            ("strokeColor".to_string(), JsonValue::from(0xFFF8F4ECu64)),
            ("strokeWidth".to_string(), JsonValue::from(0.0)),
            ("cornerRadius".to_string(), JsonValue::from(0.0)),
            ("autoResize".to_string(), JsonValue::from(true)),
        ]),
        ElementType::SerialNumber => JsonMap::from_iter([
            ("typeId".to_string(), JsonValue::from("serial_number")),
            ("number".to_string(), JsonValue::from(1)),
            ("color".to_string(), JsonValue::from(0xFF1E1E1Eu64)),
            ("fillColor".to_string(), JsonValue::from(0u64)),
            ("fillStyle".to_string(), JsonValue::from("solid")),
            ("fontSize".to_string(), JsonValue::from(16.0)),
            ("fontFamily".to_string(), JsonValue::from("")),
            ("strokeWidth".to_string(), JsonValue::from(2.0)),
            ("strokeStyle".to_string(), JsonValue::from("solid")),
            ("textElementId".to_string(), JsonValue::from("")),
        ]),
        ElementType::Unknown => JsonMap::new(),
    }
}

fn decode_json_map(bytes: &[u8]) -> Option<JsonMap<String, JsonValue>> {
    let value = serde_json::from_slice::<JsonValue>(bytes).ok()?;
    value.as_object().cloned()
}

fn encode_json_map(map: &JsonMap<String, JsonValue>) -> Vec<u8> {
    serde_json::to_vec(map).unwrap_or_default()
}

struct FallbackTextMetrics {
    width: f64,
    height: f64,
    line_height: f64,
}

fn fallback_text_metrics_for_payload(
    payload_map: &JsonMap<String, JsonValue>,
    max_width: f64,
    min_width: Option<f64>,
) -> FallbackTextMetrics {
    let font_size = payload_map
        .get("fontSize")
        .and_then(JsonValue::as_f64)
        .filter(|value| value.is_finite() && *value > 0.0)
        .unwrap_or(14.0);
    let line_height = sanitize_positive_extent(font_size * 1.2, 1.0);
    let glyph_width = sanitize_positive_extent(font_size * 0.6, 1.0);
    let raw_text = payload_map
        .get("text")
        .and_then(JsonValue::as_str)
        .unwrap_or_default();
    let text = if raw_text.is_empty() { " " } else { raw_text };
    let resolved_max_width = resolve_text_max_width(max_width);

    let mut line_widths = Vec::new();
    for line in text.split('\n') {
        append_fallback_line_metrics(&mut line_widths, line, glyph_width, resolved_max_width);
    }
    if line_widths.is_empty() {
        line_widths.push(glyph_width);
    }

    let mut width = line_widths.iter().copied().fold(0.0, f64::max);
    if let Some(min_width) = min_width.filter(|value| value.is_finite() && *value > 0.0) {
        let capped_min_width = if resolved_max_width.is_finite() {
            min_width.min(resolved_max_width)
        } else {
            min_width
        };
        if width < capped_min_width {
            width = capped_min_width;
        }
    }
    width = sanitize_positive_extent(width, glyph_width);
    let height = sanitize_positive_extent(line_height * line_widths.len() as f64, line_height);

    FallbackTextMetrics {
        width,
        height,
        line_height,
    }
}

fn append_fallback_line_metrics(
    line_widths: &mut Vec<f64>,
    line: &str,
    glyph_width: f64,
    max_width: f64,
) {
    let grapheme_count = line.chars().count().max(1) as f64;
    let raw_width = sanitize_positive_extent(grapheme_count * glyph_width, glyph_width);

    if !max_width.is_finite() {
        line_widths.push(raw_width);
        return;
    }

    let wraps = ((raw_width / max_width).ceil() as usize).max(1);
    for index in 0..wraps {
        let line_width = if index == wraps - 1 {
            let remaining = raw_width - (max_width * index as f64);
            sanitize_positive_extent(remaining, raw_width.min(max_width))
        } else {
            max_width
        };
        line_widths.push(sanitize_positive_extent(line_width, glyph_width));
    }
}

fn resolve_text_max_width(max_width: f64) -> f64 {
    if !max_width.is_finite() {
        return f64::INFINITY;
    }
    if max_width <= 0.0 {
        return 1.0;
    }
    max_width
}

fn resolve_text_layout_horizontal_padding(line_height: f64) -> f64 {
    let padding = line_height * 0.01;
    if padding.is_finite() {
        padding.max(0.0)
    } else {
        0.0
    }
}

fn sanitize_positive_extent(value: f64, fallback: f64) -> f64 {
    if value.is_finite() && value > 0.0 {
        return value;
    }
    fallback
}

fn resolve_auto_resize_text_rect(
    origin_x: f64,
    origin_y: f64,
    payload_map: &JsonMap<String, JsonValue>,
) -> DrawRect {
    let layout = fallback_text_metrics_for_payload(payload_map, f64::INFINITY, None);
    let horizontal_padding = resolve_text_layout_horizontal_padding(layout.line_height);
    let width = sanitize_positive_extent(layout.width + horizontal_padding * 2.0, 1.0);
    let height =
        sanitize_positive_extent(layout.height.max(layout.line_height), layout.line_height);

    DrawRect {
        min_x: origin_x,
        min_y: origin_y,
        max_x: origin_x + width,
        max_y: origin_y + height,
    }
}

fn rects_close(a: &DrawRect, b: &DrawRect) -> bool {
    const EPSILON: f64 = 1e-6;
    (a.min_x - b.min_x).abs() <= EPSILON
        && (a.min_y - b.min_y).abs() <= EPSILON
        && (a.max_x - b.max_x).abs() <= EPSILON
        && (a.max_y - b.max_y).abs() <= EPSILON
}

fn normalize_style_field_key(element_type: i32, key: &str) -> &str {
    match key {
        "textAlign" => "horizontalAlign",
        "textStrokeColor" => "strokeColor",
        "textStrokeWidth" => "strokeWidth",
        "filterType" => "type",
        "filterStrength" => "strength",
        "highlightShape" => "shape",
        "serialNumber" => "number",
        _ => {
            let _ = element_type;
            key
        }
    }
}

fn write_text_payload(element: &mut Element, text: &str) {
    let mut map = decode_json_map(&element.payload)
        .unwrap_or_else(|| default_element_payload_map(ElementType::Text as i32));
    map.insert("text".to_string(), JsonValue::from(text));
    element.payload = encode_json_map(&map);
}

fn resolve_serial_bound_text_rect(
    serial_rect: &DrawRect,
    serial_payload: &JsonMap<String, JsonValue>,
    text_payload: &JsonMap<String, JsonValue>,
) -> DrawRect {
    let font_size = text_payload
        .get("fontSize")
        .and_then(JsonValue::as_f64)
        .filter(|value| value.is_finite() && *value > 0.0)
        .unwrap_or(21.0);
    let line_height = (font_size * 1.2).max(1.0);
    let glyph_width = (font_size * 0.6).max(1.0);
    let text = text_payload
        .get("text")
        .and_then(JsonValue::as_str)
        .unwrap_or_default();
    let grapheme_count = text.chars().count().max(1) as f64;
    let horizontal_padding = line_height * 0.01;
    let text_width = (glyph_width * grapheme_count + horizontal_padding * 2.0).max(1.0);
    let text_height = line_height;
    let stroke_width = serial_payload
        .get("strokeWidth")
        .and_then(JsonValue::as_f64)
        .filter(|value| value.is_finite() && *value >= 0.0)
        .unwrap_or(2.0);
    let gap = 18.0_f64.max(stroke_width * 2.0);
    let min_x = serial_rect.max_x + gap;
    let min_y = ((serial_rect.min_y + serial_rect.max_y) / 2.0) - text_height / 2.0;

    DrawRect {
        min_x,
        min_y,
        max_x: min_x + text_width,
        max_y: min_y + text_height,
    }
}

fn highlight_mask_payload(global_payload: &[u8]) -> Option<Vec<u8>> {
    let map = decode_json_map(global_payload)?;
    let highlight_mask = map.get("highlightMask")?.as_object()?;
    let opacity = highlight_mask
        .get("maskOpacity")
        .and_then(JsonValue::as_f64)
        .unwrap_or(0.0);
    if opacity <= 0.0 {
        return None;
    }
    serde_json::to_vec(highlight_mask).ok()
}

fn watermark_payload(global_payload: &[u8]) -> Option<Vec<u8>> {
    let map = decode_json_map(global_payload)?;
    let watermark = map.get("watermark")?.as_object()?;
    let text = watermark
        .get("text")
        .and_then(JsonValue::as_str)
        .map(str::trim)
        .unwrap_or_default();
    let opacity = watermark
        .get("opacity")
        .and_then(JsonValue::as_f64)
        .unwrap_or(0.0);
    if text.is_empty() || opacity <= 0.0 {
        return None;
    }
    serde_json::to_vec(watermark).ok()
}

fn hover_outline_payload(snapshot: &EngineSnapshot) -> Option<Vec<u8>> {
    let map = decode_json_map(&snapshot.global_elements_payload)?;
    let (raw_element_id, use_text_underline_style) =
        if let Some(hover_outline) = map.get("hoverOutline").and_then(JsonValue::as_object) {
            (
                hover_outline.get("elementId").and_then(JsonValue::as_str)?,
                hover_outline
                    .get("useTextUnderlineStyle")
                    .and_then(JsonValue::as_bool)
                    .unwrap_or(false),
            )
        } else {
            (
                map.get("hoveredElementId").and_then(JsonValue::as_str)?,
                false,
            )
        };

    let element_id = raw_element_id.trim();
    if element_id.is_empty() {
        return None;
    }
    if snapshot
        .selected_ids
        .iter()
        .any(|selected_id| selected_id == element_id)
    {
        return None;
    }
    if !snapshot
        .elements
        .iter()
        .any(|element| element.id.as_str() == element_id)
    {
        return None;
    }

    let mut payload = JsonMap::new();
    payload.insert("elementId".to_string(), JsonValue::from(element_id));
    if use_text_underline_style {
        payload.insert("useTextUnderlineStyle".to_string(), JsonValue::from(true));
    }
    serde_json::to_vec(&payload).ok()
}

fn snap_guides_payload(
    global_payload: &[u8],
    interaction_mode: i32,
    runtime_guides: &[JsonValue],
) -> Option<Vec<u8>> {
    let mut guides = decode_json_map(global_payload)
        .map(|map| extract_snap_guides_from_map(&map))
        .unwrap_or_default();
    if interaction_mode_supports_runtime_snap_guides(interaction_mode) && !runtime_guides.is_empty()
    {
        guides.extend(runtime_guides.iter().cloned());
    }
    guides = dedupe_snap_guides(guides);
    if guides.is_empty() {
        return None;
    }

    let mut payload = JsonMap::new();
    payload.insert("guides".to_string(), JsonValue::Array(guides));
    serde_json::to_vec(&payload).ok()
}

fn extract_snap_guides_from_map(map: &JsonMap<String, JsonValue>) -> Vec<JsonValue> {
    if let Some(value) = map.get("snapGuides") {
        return match value {
            JsonValue::Array(entries) => entries.clone(),
            JsonValue::Object(payload) => payload
                .get("guides")
                .and_then(JsonValue::as_array)
                .cloned()
                .unwrap_or_default(),
            _ => Vec::new(),
        };
    }
    map.get("guides")
        .and_then(JsonValue::as_array)
        .cloned()
        .unwrap_or_default()
}

fn interaction_mode_supports_runtime_snap_guides(mode: i32) -> bool {
    matches!(
        InteractionMode::try_from(mode).unwrap_or(InteractionMode::Idle),
        InteractionMode::Creating | InteractionMode::Editing
    )
}

fn box_selection_payload(start: &DrawPoint, current: &DrawPoint) -> Option<Vec<u8>> {
    let rect = rect_from_points(start.clone(), current.clone(), false);
    let mut payload = JsonMap::new();
    payload.insert(
        "bounds".to_string(),
        JsonValue::Object(JsonMap::from_iter([
            ("minX".to_string(), JsonValue::from(rect.min_x)),
            ("minY".to_string(), JsonValue::from(rect.min_y)),
            ("maxX".to_string(), JsonValue::from(rect.max_x)),
            ("maxY".to_string(), JsonValue::from(rect.max_y)),
        ])),
    );
    serde_json::to_vec(&payload).ok()
}

fn arrow_point_overlay_payload(snapshot: &EngineSnapshot) -> Option<Vec<u8>> {
    let element = selected_arrow_like_element(snapshot)?;
    let rect = element.rect.as_ref()?;
    let payload_map = decode_json_map(&element.payload)?;
    let world_points = decode_arrow_points_world(&payload_map, rect);
    if world_points.len() < 2 {
        return None;
    }

    let arrow_type = payload_map
        .get("arrowType")
        .or_else(|| payload_map.get("lineType"))
        .and_then(JsonValue::as_str)
        .unwrap_or("straight");
    let mut addable_handles = Vec::new();
    let mut turning_handles = Vec::new();
    let mut loop_handles = Vec::new();

    if arrow_type.eq_ignore_ascii_case("elbow") {
        let fixed_segment_indices = parse_elbow_fixed_segment_indices(&payload_map);

        for index in 0..(world_points.len() - 1) {
            let start = &world_points[index];
            let end = &world_points[index + 1];
            addable_handles.push(frame_handle_payload(
                element.id.as_str(),
                "addable",
                index as i32,
                (start.x + end.x) / 2.0,
                (start.y + end.y) / 2.0,
                fixed_segment_indices.contains(&(index + 1)),
            ));
        }
        turning_handles.push(frame_handle_payload(
            element.id.as_str(),
            "turning",
            0,
            world_points[0].x,
            world_points[0].y,
            false,
        ));
        turning_handles.push(frame_handle_payload(
            element.id.as_str(),
            "turning",
            (world_points.len() - 1) as i32,
            world_points[world_points.len() - 1].x,
            world_points[world_points.len() - 1].y,
            false,
        ));
    } else {
        let loop_active = is_loop_active(&world_points, ARROW_POINT_LOOP_THRESHOLD);
        for index in 0..(world_points.len() - 1) {
            let midpoint = arrow_segment_midpoint(&world_points, arrow_type.as_ref(), index)
                .unwrap_or(DrawPoint {
                    x: (world_points[index].x + world_points[index + 1].x) / 2.0,
                    y: (world_points[index].y + world_points[index + 1].y) / 2.0,
                    pressure: 0.0,
                    timestamp_us: 0,
                });
            addable_handles.push(frame_handle_payload(
                element.id.as_str(),
                "addable",
                index as i32,
                midpoint.x,
                midpoint.y,
                false,
            ));
        }
        for (index, point) in world_points.iter().enumerate() {
            if loop_active && (index == 0 || index + 1 == world_points.len()) {
                continue;
            }
            turning_handles.push(frame_handle_payload(
                element.id.as_str(),
                "turning",
                index as i32,
                point.x,
                point.y,
                false,
            ));
        }
        if loop_active {
            loop_handles.push(frame_handle_payload(
                element.id.as_str(),
                "loopStart",
                0,
                world_points[0].x,
                world_points[0].y,
                false,
            ));
            loop_handles.push(frame_handle_payload(
                element.id.as_str(),
                "loopEnd",
                (world_points.len() - 1) as i32,
                world_points[world_points.len() - 1].x,
                world_points[world_points.len() - 1].y,
                false,
            ));
        }
    }

    let mut handles = Vec::new();
    handles.extend(addable_handles);
    handles.extend(turning_handles);
    handles.extend(loop_handles);
    if handles.is_empty() {
        return None;
    }

    let mut payload = JsonMap::new();
    payload.insert("handles".to_string(), JsonValue::Array(handles));
    payload.insert("deleteIndicatorVisible".to_string(), JsonValue::from(false));
    serde_json::to_vec(&payload).ok()
}

fn arrow_segment_midpoint(
    points: &[DrawPoint],
    arrow_type: &str,
    segment_index: usize,
) -> Option<DrawPoint> {
    if points.len() < 2 || segment_index >= points.len() - 1 {
        return None;
    }
    if arrow_type.eq_ignore_ascii_case("curved") && points.len() >= 3 {
        if let Some(point) = calculate_curve_draw_point(points, segment_index, 0.5) {
            return Some(point);
        }
    }
    let start = &points[segment_index];
    let end = &points[segment_index + 1];
    Some(DrawPoint {
        x: (start.x + end.x) / 2.0,
        y: (start.y + end.y) / 2.0,
        pressure: 0.0,
        timestamp_us: 0,
    })
}

#[derive(Clone)]
struct CubicSegment {
    start: DrawPoint,
    control1: DrawPoint,
    control2: DrawPoint,
    end: DrawPoint,
}

fn calculate_curve_draw_point(
    points: &[DrawPoint],
    segment_index: usize,
    t: f64,
) -> Option<DrawPoint> {
    if points.len() < 2 || segment_index >= points.len() - 1 {
        return None;
    }

    if points.len() < 3 {
        let p1 = &points[segment_index];
        let p2 = &points[segment_index + 1];
        return Some(DrawPoint {
            x: p1.x + (p2.x - p1.x) * t,
            y: p1.y + (p2.y - p1.y) * t,
            pressure: 0.0,
            timestamp_us: 0,
        });
    }

    let segment = build_cubic_segment(points, segment_index);
    Some(evaluate_cubic(&segment, t))
}

fn build_cubic_segment(points: &[DrawPoint], index: usize) -> CubicSegment {
    let p0 = if index == 0 {
        points[index].clone()
    } else {
        points[index - 1].clone()
    };
    let p1 = points[index].clone();
    let p2 = points[index + 1].clone();
    let p3 = if index + 2 < points.len() {
        points[index + 2].clone()
    } else {
        points[index + 1].clone()
    };

    let control1 = DrawPoint {
        x: p1.x + (p2.x - p0.x) / 6.0,
        y: p1.y + (p2.y - p0.y) / 6.0,
        pressure: 0.0,
        timestamp_us: 0,
    };
    let control2 = DrawPoint {
        x: p2.x - (p3.x - p1.x) / 6.0,
        y: p2.y - (p3.y - p1.y) / 6.0,
        pressure: 0.0,
        timestamp_us: 0,
    };

    CubicSegment {
        start: p1,
        control1,
        control2,
        end: p2,
    }
}

fn evaluate_cubic(segment: &CubicSegment, t: f64) -> DrawPoint {
    let mt = 1.0 - t;
    let mt2 = mt * mt;
    let t2 = t * t;
    let a = mt2 * mt;
    let b = 3.0 * mt2 * t;
    let c = 3.0 * mt * t2;
    let d = t2 * t;
    DrawPoint {
        x: segment.start.x * a
            + segment.control1.x * b
            + segment.control2.x * c
            + segment.end.x * d,
        y: segment.start.y * a
            + segment.control1.y * b
            + segment.control2.y * c
            + segment.end.y * d,
        pressure: 0.0,
        timestamp_us: 0,
    }
}

fn parse_elbow_fixed_segment_indices(payload: &JsonMap<String, JsonValue>) -> BTreeSet<usize> {
    let Some(entries) = payload.get("fixedSegments").and_then(JsonValue::as_array) else {
        return BTreeSet::new();
    };
    entries
        .iter()
        .filter_map(JsonValue::as_object)
        .filter_map(|entry| {
            entry
                .get("index")
                .and_then(JsonValue::as_u64)
                .and_then(|value| usize::try_from(value).ok())
                .or_else(|| {
                    entry
                        .get("index")
                        .and_then(JsonValue::as_i64)
                        .and_then(|value| usize::try_from(value).ok())
                })
        })
        .collect()
}

fn is_loop_active(points: &[DrawPoint], threshold: f64) -> bool {
    if points.len() < 2 || !threshold.is_finite() || threshold <= 0.0 {
        return false;
    }
    let Some(first) = points.first() else {
        return false;
    };
    let Some(last) = points.last() else {
        return false;
    };
    let dx = first.x - last.x;
    let dy = first.y - last.y;
    (dx * dx + dy * dy) <= threshold * threshold
}

fn arrow_binding_highlight_payload(snapshot: &EngineSnapshot) -> Option<Vec<u8>> {
    let mut ids = BTreeSet::new();
    if let Some(global_map) = decode_json_map(&snapshot.global_elements_payload) {
        if let Some(element_id) = resolve_hover_binding_highlight_id(&global_map) {
            ids.insert(element_id);
        }
    }

    if let Some(element) = selected_arrow_like_element(snapshot) {
        if let Some(payload_map) = decode_json_map(&element.payload) {
            for key in ["startBinding", "endBinding"] {
                let Some(binding) = payload_map.get(key).and_then(JsonValue::as_object) else {
                    continue;
                };
                let Some(element_id) = binding.get("elementId").and_then(JsonValue::as_str) else {
                    continue;
                };
                let trimmed = element_id.trim();
                if !trimmed.is_empty() {
                    ids.insert(trimmed.to_string());
                }
            }
        }
    }

    if ids.is_empty() {
        return None;
    }

    let mut payload = JsonMap::new();
    payload.insert(
        "elementIds".to_string(),
        JsonValue::Array(ids.into_iter().map(JsonValue::from).collect()),
    );
    serde_json::to_vec(&payload).ok()
}

fn resolve_hover_binding_highlight_id(map: &JsonMap<String, JsonValue>) -> Option<String> {
    // Match Dart behavior: hovering an arrow-point handle suppresses binding highlight.
    if map
        .get("hoveredArrowHandle")
        .map_or(false, |value| !value.is_null())
    {
        return None;
    }
    let hovered = map.get("hoveredBindingElementId")?.as_str()?.trim();
    if hovered.is_empty() {
        return None;
    }
    Some(hovered.to_string())
}

fn selected_arrow_like_element(snapshot: &EngineSnapshot) -> Option<&Element> {
    if snapshot.selected_ids.len() != 1 {
        return None;
    }
    let selected_id = snapshot.selected_ids.first()?;
    let element = snapshot
        .elements
        .iter()
        .find(|candidate| candidate.id == *selected_id)?;
    match ElementType::try_from(element.element_type).unwrap_or(ElementType::Unknown) {
        ElementType::Arrow | ElementType::Line => Some(element),
        _ => None,
    }
}

fn decode_arrow_points_world(
    payload: &JsonMap<String, JsonValue>,
    rect: &DrawRect,
) -> Vec<DrawPoint> {
    let Some(entries) = payload.get("points").and_then(JsonValue::as_array) else {
        return Vec::new();
    };

    let width = rect.max_x - rect.min_x;
    let height = rect.max_y - rect.min_y;
    let has_world_space_points = entries
        .iter()
        .filter_map(JsonValue::as_object)
        .any(|entry| {
            let Some(x) = entry.get("x").and_then(JsonValue::as_f64) else {
                return false;
            };
            let Some(y) = entry.get("y").and_then(JsonValue::as_f64) else {
                return false;
            };
            !is_normalized_coord(x) || !is_normalized_coord(y)
        });

    entries
        .iter()
        .filter_map(JsonValue::as_object)
        .filter_map(|entry| {
            let x = entry.get("x").and_then(JsonValue::as_f64)?;
            let y = entry.get("y").and_then(JsonValue::as_f64)?;
            let should_treat_as_normalized =
                !has_world_space_points || (is_normalized_coord(x) && is_normalized_coord(y));
            let world_x = if should_treat_as_normalized {
                rect.min_x + x * width
            } else {
                x
            };
            let world_y = if should_treat_as_normalized {
                rect.min_y + y * height
            } else {
                y
            };
            Some(DrawPoint {
                x: world_x,
                y: world_y,
                pressure: 0.0,
                timestamp_us: 0,
            })
        })
        .collect()
}

fn encode_arrow_points_for_rect(points: &[DrawPoint], rect: &DrawRect) -> Vec<JsonValue> {
    let width = rect.max_x - rect.min_x;
    let height = rect.max_y - rect.min_y;
    points
        .iter()
        .map(|point| {
            let normalized_x = if width.abs() <= f64::EPSILON {
                0.0
            } else {
                (point.x - rect.min_x) / width
            };
            let normalized_y = if height.abs() <= f64::EPSILON {
                0.0
            } else {
                (point.y - rect.min_y) / height
            };
            point_value(normalized_x, normalized_y)
        })
        .collect()
}

fn arrow_points_bounds(points: &[DrawPoint]) -> DrawRect {
    let mut iter = points.iter();
    let first = iter.next().cloned().unwrap_or(DrawPoint {
        x: 0.0,
        y: 0.0,
        pressure: 0.0,
        timestamp_us: 0,
    });
    let mut min_x = first.x;
    let mut min_y = first.y;
    let mut max_x = first.x;
    let mut max_y = first.y;
    for point in iter {
        min_x = min_x.min(point.x);
        min_y = min_y.min(point.y);
        max_x = max_x.max(point.x);
        max_y = max_y.max(point.y);
    }
    DrawRect {
        min_x,
        min_y,
        max_x,
        max_y,
    }
}

fn resolve_arrow_point_update(
    mut points: Vec<DrawPoint>,
    point_kind: ArrowPointKind,
    point_index: usize,
    target: DrawPoint,
) -> Option<(Vec<DrawPoint>, bool, bool)> {
    if points.len() < 2 {
        return None;
    }
    match point_kind {
        ArrowPointKind::Addable => {
            if point_index >= points.len() - 1 {
                return None;
            }
            points.insert(point_index + 1, target);
            Some((points, false, false))
        }
        ArrowPointKind::Turning => {
            if point_index >= points.len() {
                return None;
            }
            let moved_start_endpoint = point_index == 0;
            let moved_end_endpoint = point_index + 1 == points.len();
            points[point_index] = target;
            Some((points, moved_start_endpoint, moved_end_endpoint))
        }
        ArrowPointKind::LoopStart => {
            points[0] = target;
            Some((points, true, false))
        }
        ArrowPointKind::LoopEnd => {
            let last = points.len() - 1;
            points[last] = target;
            Some((points, false, true))
        }
    }
}

fn is_normalized_coord(value: f64) -> bool {
    value.is_finite() && (-1e-9..=1.0 + 1e-9).contains(&value)
}

fn frame_handle_payload(
    element_id: &str,
    kind: &str,
    index: i32,
    x: f64,
    y: f64,
    is_fixed: bool,
) -> JsonValue {
    JsonValue::Object(JsonMap::from_iter([
        ("elementId".to_string(), JsonValue::from(element_id)),
        ("kind".to_string(), JsonValue::from(kind)),
        ("index".to_string(), JsonValue::from(index)),
        ("position".to_string(), point_value(x, y)),
        ("isFixed".to_string(), JsonValue::from(is_fixed)),
    ]))
}

fn map_frame_task_kind(element_type: i32) -> FrameTaskKind {
    match ElementType::try_from(element_type).unwrap_or(ElementType::Unknown) {
        ElementType::Rectangle => FrameTaskKind::Rectangle,
        ElementType::Arrow => FrameTaskKind::Arrow,
        ElementType::Line => FrameTaskKind::Line,
        ElementType::FreeDraw => FrameTaskKind::FreeDraw,
        ElementType::Filter => FrameTaskKind::Filter,
        ElementType::Highlight => FrameTaskKind::Highlight,
        ElementType::Text => FrameTaskKind::Text,
        ElementType::SerialNumber => FrameTaskKind::SerialNumber,
        ElementType::Unknown => FrameTaskKind::Unknown,
    }
}

fn selected_set(snapshot: &EngineSnapshot) -> BTreeSet<String> {
    snapshot.selected_ids.iter().cloned().collect()
}

fn rect_from_points(start: DrawPoint, current: DrawPoint, keep_square: bool) -> DrawRect {
    let min_x = start.x.min(current.x);
    let min_y = start.y.min(current.y);
    let mut max_x = start.x.max(current.x);
    let mut max_y = start.y.max(current.y);

    if keep_square {
        let side = (max_x - min_x).abs().max((max_y - min_y).abs());
        max_x = min_x + side;
        max_y = min_y + side;
    }

    DrawRect {
        min_x,
        min_y,
        max_x,
        max_y,
    }
}

fn create_rect_from_points(
    start: DrawPoint,
    current: DrawPoint,
    keep_square: bool,
    from_center: bool,
) -> DrawRect {
    let dx = current.x - start.x;
    let dy = current.y - start.y;

    if keep_square {
        let side = dx.abs().max(dy.abs());
        if from_center {
            return DrawRect {
                min_x: start.x - side,
                min_y: start.y - side,
                max_x: start.x + side,
                max_y: start.y + side,
            };
        }

        let end_x = start.x + if dx >= 0.0 { side } else { -side };
        let end_y = start.y + if dy >= 0.0 { side } else { -side };
        return DrawRect {
            min_x: start.x.min(end_x),
            min_y: start.y.min(end_y),
            max_x: start.x.max(end_x),
            max_y: start.y.max(end_y),
        };
    }

    if from_center {
        return DrawRect {
            min_x: start.x - dx.abs(),
            min_y: start.y - dy.abs(),
            max_x: start.x + dx.abs(),
            max_y: start.y + dy.abs(),
        };
    }

    rect_from_points(start, current, false)
}

fn rects_intersect(a: &DrawRect, b: &DrawRect) -> bool {
    !(a.max_x < b.min_x || a.min_x > b.max_x || a.max_y < b.min_y || a.min_y > b.max_y)
}

fn resolve_effective_zoom(zoom: f64) -> f64 {
    if zoom.is_finite() && zoom > 0.0 {
        zoom
    } else {
        1.0
    }
}

fn clamp_zoom(zoom: f64) -> f64 {
    zoom.clamp(CAMERA_MIN_ZOOM, CAMERA_MAX_ZOOM)
}

fn sanitize_grid_size(value: f64) -> f64 {
    if value.is_finite() && value > 0.0 {
        value.max(1.0)
    } else {
        RuntimeSnapConfig::default().grid_size
    }
}

fn sanitize_snap_distance(value: f64) -> f64 {
    if value.is_finite() && value >= 0.0 {
        value
    } else {
        RuntimeSnapConfig::default().object_distance
    }
}

fn rect_axis_anchors_x(rect: &DrawRect) -> [f64; 3] {
    [rect.min_x, (rect.min_x + rect.max_x) * 0.5, rect.max_x]
}

fn rect_axis_anchors_y(rect: &DrawRect) -> [f64; 3] {
    [rect.min_y, (rect.min_y + rect.max_y) * 0.5, rect.max_y]
}

fn best_anchor_match(
    targets: &[f64],
    references: &[f64],
    max_distance: f64,
) -> Option<AnchorSnapMatch> {
    if targets.is_empty() || references.is_empty() {
        return None;
    }
    let mut best_match = None;
    let mut best_abs = max_distance + f64::EPSILON;
    for target in targets {
        for reference in references {
            let offset = *reference - *target;
            let abs = offset.abs();
            if abs > max_distance {
                continue;
            }
            if abs + f64::EPSILON < best_abs {
                best_abs = abs;
                best_match = Some(AnchorSnapMatch {
                    offset,
                    reference: *reference,
                });
            }
        }
    }
    if best_abs <= max_distance {
        best_match
    } else {
        None
    }
}

fn point_snap_guides(original: &DrawPoint, snapped: &DrawPoint) -> Vec<JsonValue> {
    let mut guides = Vec::new();
    let span = 60.0;
    if (snapped.x - original.x).abs() > f64::EPSILON {
        guides.push(vertical_snap_guide(
            snapped.x,
            snapped.y - span,
            snapped.y + span,
            Some((snapped.x, snapped.y)),
        ));
    }
    if (snapped.y - original.y).abs() > f64::EPSILON {
        guides.push(horizontal_snap_guide(
            snapped.y,
            snapped.x - span,
            snapped.x + span,
            Some((snapped.x, snapped.y)),
        ));
    }
    guides
}

fn rect_snap_guides_with_matches(
    rect: &DrawRect,
    x_match: Option<AnchorSnapMatch>,
    y_match: Option<AnchorSnapMatch>,
) -> Vec<JsonValue> {
    rect_snap_guides_for_axes(
        rect,
        x_match.map(|item| item.reference),
        y_match.map(|item| item.reference),
    )
}

fn rect_snap_guides_for_axes(
    rect: &DrawRect,
    x_coord: Option<f64>,
    y_coord: Option<f64>,
) -> Vec<JsonValue> {
    let mut guides = Vec::new();
    let padding = 24.0;
    let center = rect_center(rect);
    if let Some(x) = x_coord {
        guides.push(vertical_snap_guide(
            x,
            rect.min_y - padding,
            rect.max_y + padding,
            Some((x, center.y)),
        ));
    }
    if let Some(y) = y_coord {
        guides.push(horizontal_snap_guide(
            y,
            rect.min_x - padding,
            rect.max_x + padding,
            Some((center.x, y)),
        ));
    }
    guides
}

fn vertical_snap_guide(x: f64, start_y: f64, end_y: f64, marker: Option<(f64, f64)>) -> JsonValue {
    let mut map = JsonMap::new();
    map.insert("kind".to_string(), JsonValue::from("point"));
    map.insert("axis".to_string(), JsonValue::from("vertical"));
    map.insert("start".to_string(), point_value(x, start_y.min(end_y)));
    map.insert("end".to_string(), point_value(x, start_y.max(end_y)));
    if let Some((marker_x, marker_y)) = marker {
        map.insert(
            "markers".to_string(),
            JsonValue::Array(vec![point_value(marker_x, marker_y)]),
        );
    }
    JsonValue::Object(map)
}

fn horizontal_snap_guide(
    y: f64,
    start_x: f64,
    end_x: f64,
    marker: Option<(f64, f64)>,
) -> JsonValue {
    let mut map = JsonMap::new();
    map.insert("kind".to_string(), JsonValue::from("point"));
    map.insert("axis".to_string(), JsonValue::from("horizontal"));
    map.insert("start".to_string(), point_value(start_x.min(end_x), y));
    map.insert("end".to_string(), point_value(start_x.max(end_x), y));
    if let Some((marker_x, marker_y)) = marker {
        map.insert(
            "markers".to_string(),
            JsonValue::Array(vec![point_value(marker_x, marker_y)]),
        );
    }
    JsonValue::Object(map)
}

fn dedupe_snap_guides(guides: Vec<JsonValue>) -> Vec<JsonValue> {
    let mut deduped = Vec::new();
    let mut seen = BTreeSet::new();
    for guide in guides {
        let key = match serde_json::to_string(&guide) {
            Ok(serialized) => serialized,
            Err(_) => {
                deduped.push(guide);
                continue;
            }
        };
        if seen.insert(key) {
            deduped.push(guide);
        }
    }
    deduped
}

fn apply_resize_horizontal_offset(
    rect: &mut DrawRect,
    offset: f64,
    move_left: bool,
    move_right: bool,
) {
    if !offset.is_finite() || offset.abs() <= f64::EPSILON {
        return;
    }
    let width = (rect.max_x - rect.min_x).abs().max(1.0);
    if move_left && !move_right {
        let max_offset = (width - 1.0).max(0.0);
        rect.min_x += offset.min(max_offset);
        return;
    }
    if move_right && !move_left {
        let min_offset = -((width - 1.0).max(0.0));
        rect.max_x += offset.max(min_offset);
        return;
    }
    if move_left && move_right {
        rect.min_x += offset;
        rect.max_x += offset;
    }
}

fn apply_resize_vertical_offset(
    rect: &mut DrawRect,
    offset: f64,
    move_top: bool,
    move_bottom: bool,
) {
    if !offset.is_finite() || offset.abs() <= f64::EPSILON {
        return;
    }
    let height = (rect.max_y - rect.min_y).abs().max(1.0);
    if move_top && !move_bottom {
        let max_offset = (height - 1.0).max(0.0);
        rect.min_y += offset.min(max_offset);
        return;
    }
    if move_bottom && !move_top {
        let min_offset = -((height - 1.0).max(0.0));
        rect.max_y += offset.max(min_offset);
        return;
    }
    if move_top && move_bottom {
        rect.min_y += offset;
        rect.max_y += offset;
    }
}

fn snap_value_to_grid(value: f64, grid_size: f64) -> f64 {
    let size = sanitize_grid_size(grid_size);
    (value / size).round() * size
}

fn snap_rect_to_grid(rect: &DrawRect, grid_size: f64) -> DrawRect {
    normalize_rect(DrawRect {
        min_x: snap_value_to_grid(rect.min_x, grid_size),
        min_y: snap_value_to_grid(rect.min_y, grid_size),
        max_x: snap_value_to_grid(rect.max_x, grid_size),
        max_y: snap_value_to_grid(rect.max_y, grid_size),
    })
}

fn extract_runtime_snap_config_patch(
    map: &mut JsonMap<String, JsonValue>,
) -> Option<RuntimeSnapConfigPatch> {
    if let Some(value) = map.remove(RUNTIME_CONFIG_KEY) {
        return runtime_snap_config_patch_from_value(&value);
    }

    let mut runtime_map = JsonMap::new();
    for key in [
        "grid",
        "snap",
        "objectSnap",
        "gridEnabled",
        "gridSize",
        "objectSnapEnabled",
        "objectSnapDistance",
    ] {
        if let Some(value) = map.remove(key) {
            runtime_map.insert(key.to_string(), value);
        }
    }
    if runtime_map.is_empty() {
        return None;
    }
    runtime_snap_config_patch_from_map(&runtime_map)
}

fn extract_bootstrap_snapshot_from_map(
    map: &mut JsonMap<String, JsonValue>,
) -> Option<EngineSnapshot> {
    let encoded = map.remove(RUNTIME_BOOTSTRAP_SNAPSHOT_KEY)?;
    let encoded = encoded.as_str()?.trim();
    if encoded.is_empty() {
        return None;
    }
    let decoded = base64::engine::general_purpose::STANDARD
        .decode(encoded)
        .ok()?;
    decode_message::<EngineSnapshot>(&decoded).ok()
}

fn sanitize_bootstrap_snapshot(snapshot: &mut EngineSnapshot, schema_version: u32) {
    snapshot.schema_version = schema_version;
    if snapshot.camera.is_none() {
        snapshot.camera = Some(default_camera_state());
    }

    snapshot.elements.sort_by(|a, b| {
        a.z_index
            .cmp(&b.z_index)
            .then_with(|| a.id.as_str().cmp(b.id.as_str()))
    });

    let available_ids = snapshot
        .elements
        .iter()
        .map(|element| element.id.clone())
        .collect::<BTreeSet<_>>();
    snapshot
        .selected_ids
        .retain(|id| available_ids.contains(id));
    snapshot.selected_ids.sort();
    snapshot.selected_ids.dedup();

    snapshot.interaction_mode = InteractionMode::Idle as i32;
    snapshot.history_undo_len = 0;
    snapshot.history_redo_len = 0;
}

fn runtime_snap_config_patch_from_value(value: &JsonValue) -> Option<RuntimeSnapConfigPatch> {
    value
        .as_object()
        .and_then(runtime_snap_config_patch_from_map)
}

fn runtime_snap_config_patch_from_map(
    map: &JsonMap<String, JsonValue>,
) -> Option<RuntimeSnapConfigPatch> {
    let mut patch = RuntimeSnapConfigPatch::default();
    let mut found = false;

    if let Some(grid) = map.get("grid").and_then(JsonValue::as_object) {
        if let Some(enabled) = grid.get("enabled").and_then(JsonValue::as_bool) {
            patch.grid_enabled = Some(enabled);
            found = true;
        }
        if let Some(size) = grid.get("size").and_then(JsonValue::as_f64) {
            patch.grid_size = Some(size);
            found = true;
        }
    }

    if let Some(snap) = map.get("snap").and_then(JsonValue::as_object) {
        if let Some(enabled) = snap.get("enabled").and_then(JsonValue::as_bool) {
            patch.object_enabled = Some(enabled);
            found = true;
        }
        if let Some(distance) = snap.get("distance").and_then(JsonValue::as_f64) {
            patch.object_distance = Some(distance);
            found = true;
        }
    }
    if let Some(snap) = map.get("objectSnap").and_then(JsonValue::as_object) {
        if let Some(enabled) = snap.get("enabled").and_then(JsonValue::as_bool) {
            patch.object_enabled = Some(enabled);
            found = true;
        }
        if let Some(distance) = snap.get("distance").and_then(JsonValue::as_f64) {
            patch.object_distance = Some(distance);
            found = true;
        }
    }

    if let Some(enabled) = map.get("gridEnabled").and_then(JsonValue::as_bool) {
        patch.grid_enabled = Some(enabled);
        found = true;
    }
    if let Some(size) = map.get("gridSize").and_then(JsonValue::as_f64) {
        patch.grid_size = Some(size);
        found = true;
    }
    if let Some(enabled) = map.get("objectSnapEnabled").and_then(JsonValue::as_bool) {
        patch.object_enabled = Some(enabled);
        found = true;
    }
    if let Some(distance) = map.get("objectSnapDistance").and_then(JsonValue::as_f64) {
        patch.object_distance = Some(distance);
        found = true;
    }

    if found {
        Some(patch)
    } else {
        None
    }
}

fn runtime_style_defaults_from_map(
    map: &JsonMap<String, JsonValue>,
) -> Option<RuntimeStyleDefaults> {
    let source = map
        .get("runtime")
        .and_then(JsonValue::as_object)
        .unwrap_or(map);
    let styles = source.get("styles").and_then(JsonValue::as_object)?;
    let mut defaults = RuntimeStyleDefaults::default();
    let mut found = false;

    for (style_key, style_value) in styles {
        let Some(element_type) = style_defaults_element_type_for_key(style_key.as_str()) else {
            continue;
        };
        let Some(style_map) = style_value.as_object() else {
            continue;
        };
        let normalized_style = sanitize_runtime_style_defaults_map(style_map);
        defaults.set_for_element_type(element_type, normalized_style);
        found = true;
    }

    if found {
        Some(defaults)
    } else {
        None
    }
}

fn style_defaults_element_type_for_key(style_key: &str) -> Option<i32> {
    match style_key {
        "rectangle" => Some(ElementType::Rectangle as i32),
        "arrow" => Some(ElementType::Arrow as i32),
        "line" => Some(ElementType::Line as i32),
        "freeDraw" | "free_draw" => Some(ElementType::FreeDraw as i32),
        "text" => Some(ElementType::Text as i32),
        "serialNumber" | "serial_number" => Some(ElementType::SerialNumber as i32),
        "filter" => Some(ElementType::Filter as i32),
        "highlight" => Some(ElementType::Highlight as i32),
        _ => None,
    }
}

fn sanitize_runtime_style_defaults_map(
    style: &JsonMap<String, JsonValue>,
) -> JsonMap<String, JsonValue> {
    let mut normalized = JsonMap::new();
    for key in [
        "opacity",
        "serialNumber",
        "color",
        "fillColor",
        "strokeWidth",
        "strokeStyle",
        "fillStyle",
        "highlightShape",
        "filterType",
        "filterStrength",
        "cornerRadius",
        "arrowType",
        "startArrowhead",
        "endArrowhead",
        "fontSize",
        "fontFamily",
        "textAlign",
        "verticalAlign",
        "textStrokeColor",
        "textStrokeWidth",
    ] {
        let Some(value) = style.get(key) else {
            continue;
        };
        let normalized_value = if key == "fontFamily" && value.is_null() {
            JsonValue::from("")
        } else {
            value.clone()
        };
        normalized.insert(key.to_string(), normalized_value);
    }
    normalized
}

fn style_default_opacity_from_map(style_defaults: &JsonMap<String, JsonValue>) -> Option<f64> {
    style_defaults
        .get("opacity")
        .and_then(JsonValue::as_f64)
        .map(sanitize_opacity)
}

fn apply_style_defaults_to_payload_map(
    element_type: i32,
    payload_map: &mut JsonMap<String, JsonValue>,
    style_defaults: &JsonMap<String, JsonValue>,
) -> f64 {
    let mut opacity = 1.0;
    for (key, value) in style_defaults {
        if key == "opacity" {
            if let Some(parsed) = value.as_f64() {
                opacity = sanitize_opacity(parsed);
            }
            continue;
        }
        let normalized_key = normalize_style_field_key(element_type, key);
        let normalized_value = if key == "fontFamily" && value.is_null() {
            JsonValue::from("")
        } else {
            value.clone()
        };
        payload_map.insert(normalized_key.to_string(), normalized_value);
    }
    opacity
}

fn sanitize_opacity(value: f64) -> f64 {
    if !value.is_finite() {
        return 1.0;
    }
    value.clamp(0.0, 1.0)
}

fn apply_next_serial_number_default(
    elements: &[Element],
    payload_map: &mut JsonMap<String, JsonValue>,
) {
    let next_serial = resolve_next_serial_number(elements);
    let current_serial = payload_map
        .get("number")
        .and_then(json_i64_value)
        .unwrap_or(1);
    if current_serial < next_serial {
        payload_map.insert("number".to_string(), JsonValue::from(next_serial));
    }
}

fn resolve_next_serial_number(elements: &[Element]) -> i64 {
    let mut next_serial = 1_i64;
    for element in elements {
        if normalize_element_type(element.element_type) != ElementType::SerialNumber as i32 {
            continue;
        }
        let Some(payload_map) = decode_json_map(&element.payload) else {
            continue;
        };
        let Some(number) = payload_map.get("number").and_then(json_i64_value) else {
            continue;
        };
        if number >= next_serial {
            next_serial = number.saturating_add(1);
        }
    }
    next_serial.max(1)
}

fn json_i64_value(value: &JsonValue) -> Option<i64> {
    value
        .as_i64()
        .or_else(|| value.as_u64().and_then(|raw| i64::try_from(raw).ok()))
}

fn encode_global_payload_map(map: JsonMap<String, JsonValue>) -> Vec<u8> {
    if map.is_empty() {
        Vec::new()
    } else {
        encode_json_map(&map)
    }
}

#[derive(Debug, Clone, Copy, Default)]
struct EditModifiersPayload {
    maintain_aspect_ratio: bool,
    from_center: bool,
    discrete_angle: bool,
    snap_override: bool,
}

fn parse_edit_modifiers(bytes: &[u8]) -> EditModifiersPayload {
    let mut parsed = EditModifiersPayload::default();
    let Some(map) = decode_json_map(bytes) else {
        return parsed;
    };
    parsed.maintain_aspect_ratio = map
        .get("maintainAspectRatio")
        .and_then(JsonValue::as_bool)
        .unwrap_or(false);
    parsed.from_center = map
        .get("fromCenter")
        .and_then(JsonValue::as_bool)
        .unwrap_or(false);
    parsed.discrete_angle = map
        .get("discreteAngle")
        .and_then(JsonValue::as_bool)
        .unwrap_or(false);
    parsed.snap_override = map
        .get("snapOverride")
        .and_then(JsonValue::as_bool)
        .unwrap_or(false);
    parsed
}

fn resolve_edit_operation(
    operation_id: &str,
    params: Option<&JsonMap<String, JsonValue>>,
    baseline_rects: &BTreeMap<String, DrawRect>,
) -> EditSessionOperation {
    let kind = params
        .and_then(|map| map.get("type"))
        .and_then(JsonValue::as_str)
        .unwrap_or(operation_id);

    match kind {
        "move" => EditSessionOperation::Move,
        "resize" => {
            let mode = params
                .and_then(|map| map.get("resizeMode"))
                .and_then(JsonValue::as_str)
                .and_then(parse_resize_mode)
                .unwrap_or(ResizeMode::BottomRight);
            EditSessionOperation::Resize { mode }
        }
        "rotate" => {
            let pivot = selection_bounds_from_rects(baseline_rects)
                .map(|rect| rect_center(&rect))
                .unwrap_or(DrawPoint {
                    x: 0.0,
                    y: 0.0,
                    pressure: 0.0,
                    timestamp_us: 0,
                });
            let snap_angle = params
                .and_then(|map| map.get("rotationSnapAngle"))
                .and_then(JsonValue::as_f64)
                .unwrap_or(0.0);
            EditSessionOperation::Rotate { pivot, snap_angle }
        }
        "arrow_point" | "arrowPoint" => {
            let element_id = params
                .and_then(|map| map.get("elementId"))
                .and_then(JsonValue::as_str)
                .map(str::trim)
                .filter(|value| !value.is_empty())
                .map(ToOwned::to_owned);
            let point_kind = params
                .and_then(|map| map.get("pointKind"))
                .and_then(JsonValue::as_str)
                .and_then(parse_arrow_point_kind)
                .unwrap_or(ArrowPointKind::Turning);
            let point_index = params
                .and_then(|map| map.get("pointIndex"))
                .and_then(JsonValue::as_u64)
                .and_then(|index| usize::try_from(index).ok())
                .or_else(|| {
                    params
                        .and_then(|map| map.get("pointIndex"))
                        .and_then(JsonValue::as_i64)
                        .and_then(|index| usize::try_from(index).ok())
                })
                .unwrap_or(0);
            let is_double_click = params
                .and_then(|map| map.get("isDoubleClick"))
                .and_then(JsonValue::as_bool)
                .unwrap_or(false);
            let delete_point_on_finish =
                is_double_click && point_kind == ArrowPointKind::Turning && point_index > 0;

            if let Some(element_id) = element_id {
                EditSessionOperation::ArrowPoint {
                    element_id,
                    point_kind,
                    point_index,
                    delete_point_on_finish,
                }
            } else {
                EditSessionOperation::Unknown
            }
        }
        _ => EditSessionOperation::Unknown,
    }
}

fn parse_resize_mode(value: &str) -> Option<ResizeMode> {
    match value {
        "topLeft" => Some(ResizeMode::TopLeft),
        "topRight" => Some(ResizeMode::TopRight),
        "bottomLeft" => Some(ResizeMode::BottomLeft),
        "bottomRight" => Some(ResizeMode::BottomRight),
        "top" => Some(ResizeMode::Top),
        "bottom" => Some(ResizeMode::Bottom),
        "left" => Some(ResizeMode::Left),
        "right" => Some(ResizeMode::Right),
        _ => None,
    }
}

fn parse_arrow_point_kind(value: &str) -> Option<ArrowPointKind> {
    match value {
        "turning" => Some(ArrowPointKind::Turning),
        "addable" => Some(ArrowPointKind::Addable),
        "loopStart" | "loop_start" => Some(ArrowPointKind::LoopStart),
        "loopEnd" | "loop_end" => Some(ArrowPointKind::LoopEnd),
        _ => None,
    }
}

fn resize_mode_axes(mode: ResizeMode) -> (bool, bool, bool, bool) {
    match mode {
        ResizeMode::TopLeft => (true, false, true, false),
        ResizeMode::TopRight => (false, true, true, false),
        ResizeMode::BottomLeft => (true, false, false, true),
        ResizeMode::BottomRight => (false, true, false, true),
        ResizeMode::Top => (false, false, true, false),
        ResizeMode::Bottom => (false, false, false, true),
        ResizeMode::Left => (true, false, false, false),
        ResizeMode::Right => (false, true, false, false),
    }
}

fn normalize_rect(rect: DrawRect) -> DrawRect {
    DrawRect {
        min_x: rect.min_x.min(rect.max_x),
        min_y: rect.min_y.min(rect.max_y),
        max_x: rect.min_x.max(rect.max_x),
        max_y: rect.min_y.max(rect.max_y),
    }
}

fn selection_bounds_from_rects(rects: &BTreeMap<String, DrawRect>) -> Option<DrawRect> {
    let mut iter = rects.values();
    let first = iter.next()?;
    let mut bounds = first.clone();
    for rect in iter {
        bounds.min_x = bounds.min_x.min(rect.min_x);
        bounds.min_y = bounds.min_y.min(rect.min_y);
        bounds.max_x = bounds.max_x.max(rect.max_x);
        bounds.max_y = bounds.max_y.max(rect.max_y);
    }
    Some(bounds)
}

fn rect_center(rect: &DrawRect) -> DrawPoint {
    DrawPoint {
        x: (rect.min_x + rect.max_x) / 2.0,
        y: (rect.min_y + rect.max_y) / 2.0,
        pressure: 0.0,
        timestamp_us: 0,
    }
}

fn angle_between_points(point: &DrawPoint, pivot: &DrawPoint) -> f64 {
    (point.y - pivot.y).atan2(point.x - pivot.x)
}

fn normalize_angle_radians(angle: f64) -> f64 {
    let tau = std::f64::consts::TAU;
    let mut normalized = angle % tau;
    if normalized > std::f64::consts::PI {
        normalized -= tau;
    } else if normalized < -std::f64::consts::PI {
        normalized += tau;
    }
    normalized
}

fn rotate_point_around(point: &DrawPoint, pivot: &DrawPoint, angle: f64) -> DrawPoint {
    let dx = point.x - pivot.x;
    let dy = point.y - pivot.y;
    let sin = angle.sin();
    let cos = angle.cos();
    DrawPoint {
        x: pivot.x + dx * cos - dy * sin,
        y: pivot.y + dx * sin + dy * cos,
        pressure: 0.0,
        timestamp_us: 0,
    }
}

fn extract_create_payload(
    kind: EngineCommandKind,
    payload: Option<CommandPayload>,
) -> Result<CreateElementCommand, EngineCoreError> {
    match payload {
        Some(CommandPayload::CreateElement(value)) => Ok(value),
        _ => Err(EngineCoreError::InvalidPayload(kind)),
    }
}

fn extract_select_payload(
    kind: EngineCommandKind,
    payload: Option<CommandPayload>,
) -> Result<SelectElementCommand, EngineCoreError> {
    match payload {
        Some(CommandPayload::SelectElement(value)) => Ok(value),
        _ => Err(EngineCoreError::InvalidPayload(kind)),
    }
}

fn extract_delete_payload(
    kind: EngineCommandKind,
    payload: Option<CommandPayload>,
) -> Result<engine_proto::DeleteElementsCommand, EngineCoreError> {
    match payload {
        Some(CommandPayload::DeleteElements(value)) => Ok(value),
        _ => Err(EngineCoreError::InvalidPayload(kind)),
    }
}

fn extract_update_style_payload(
    kind: EngineCommandKind,
    payload: Option<CommandPayload>,
) -> Result<UpdateElementsStyleCommand, EngineCoreError> {
    match payload {
        Some(CommandPayload::UpdateElementsStyle(value)) => Ok(value),
        _ => Err(EngineCoreError::InvalidPayload(kind)),
    }
}

fn extract_move_camera_payload(
    kind: EngineCommandKind,
    payload: Option<CommandPayload>,
) -> Result<MoveCameraCommand, EngineCoreError> {
    match payload {
        Some(CommandPayload::MoveCamera(value)) => Ok(value),
        _ => Err(EngineCoreError::InvalidPayload(kind)),
    }
}

fn extract_zoom_camera_payload(
    kind: EngineCommandKind,
    payload: Option<CommandPayload>,
) -> Result<ZoomCameraCommand, EngineCoreError> {
    match payload {
        Some(CommandPayload::ZoomCamera(value)) => Ok(value),
        _ => Err(EngineCoreError::InvalidPayload(kind)),
    }
}

fn extract_update_creating_payload(
    kind: EngineCommandKind,
    payload: Option<CommandPayload>,
) -> Result<UpdateCreatingElementCommand, EngineCoreError> {
    match payload {
        Some(CommandPayload::UpdateCreatingElement(value)) => Ok(value),
        _ => Err(EngineCoreError::InvalidPayload(kind)),
    }
}

fn extract_add_arrow_point_payload(
    kind: EngineCommandKind,
    payload: Option<CommandPayload>,
) -> Result<AddArrowPointCommand, EngineCoreError> {
    match payload {
        Some(CommandPayload::AddArrowPoint(value)) => Ok(value),
        _ => Err(EngineCoreError::InvalidPayload(kind)),
    }
}

fn extract_duplicate_payload(
    kind: EngineCommandKind,
    payload: Option<CommandPayload>,
) -> Result<DuplicateElementsCommand, EngineCoreError> {
    match payload {
        Some(CommandPayload::DuplicateElements(value)) => Ok(value),
        _ => Err(EngineCoreError::InvalidPayload(kind)),
    }
}

fn extract_change_element_z_payload(
    kind: EngineCommandKind,
    payload: Option<CommandPayload>,
) -> Result<ChangeElementZIndexCommand, EngineCoreError> {
    match payload {
        Some(CommandPayload::ChangeElementZIndex(value)) => Ok(value),
        _ => Err(EngineCoreError::InvalidPayload(kind)),
    }
}

fn extract_change_elements_z_payload(
    kind: EngineCommandKind,
    payload: Option<CommandPayload>,
) -> Result<ChangeElementsZIndexCommand, EngineCoreError> {
    match payload {
        Some(CommandPayload::ChangeElementsZIndex(value)) => Ok(value),
        _ => Err(EngineCoreError::InvalidPayload(kind)),
    }
}

fn extract_update_global_payload(
    kind: EngineCommandKind,
    payload: Option<CommandPayload>,
) -> Result<UpdateGlobalElementsCommand, EngineCoreError> {
    match payload {
        Some(CommandPayload::UpdateGlobalElements(value)) => Ok(value),
        _ => Err(EngineCoreError::InvalidPayload(kind)),
    }
}

fn extract_create_serial_text_payload(
    kind: EngineCommandKind,
    payload: Option<CommandPayload>,
) -> Result<CreateSerialNumberTextElementsCommand, EngineCoreError> {
    match payload {
        Some(CommandPayload::CreateSerialNumberTextElements(value)) => Ok(value),
        _ => Err(EngineCoreError::InvalidPayload(kind)),
    }
}

fn extract_start_text_edit_payload(
    kind: EngineCommandKind,
    payload: Option<CommandPayload>,
) -> Result<StartTextEditCommand, EngineCoreError> {
    match payload {
        Some(CommandPayload::StartTextEdit(value)) => Ok(value),
        _ => Err(EngineCoreError::InvalidPayload(kind)),
    }
}

fn extract_update_text_edit_payload(
    kind: EngineCommandKind,
    payload: Option<CommandPayload>,
) -> Result<UpdateTextEditCommand, EngineCoreError> {
    match payload {
        Some(CommandPayload::UpdateTextEdit(value)) => Ok(value),
        _ => Err(EngineCoreError::InvalidPayload(kind)),
    }
}

fn extract_finish_text_edit_payload(
    kind: EngineCommandKind,
    payload: Option<CommandPayload>,
) -> Result<FinishTextEditCommand, EngineCoreError> {
    match payload {
        Some(CommandPayload::FinishTextEdit(value)) => Ok(value),
        _ => Err(EngineCoreError::InvalidPayload(kind)),
    }
}

fn extract_start_edit_payload(
    kind: EngineCommandKind,
    payload: Option<CommandPayload>,
) -> Result<engine_proto::StartEditCommand, EngineCoreError> {
    match payload {
        Some(CommandPayload::StartEdit(value)) => Ok(value),
        _ => Err(EngineCoreError::InvalidPayload(kind)),
    }
}

fn extract_update_edit_payload(
    kind: EngineCommandKind,
    payload: Option<CommandPayload>,
) -> Result<UpdateEditCommand, EngineCoreError> {
    match payload {
        Some(CommandPayload::UpdateEdit(value)) => Ok(value),
        _ => Err(EngineCoreError::InvalidPayload(kind)),
    }
}

fn extract_set_drag_pending_payload(
    kind: EngineCommandKind,
    payload: Option<CommandPayload>,
) -> Result<SetDragPendingCommand, EngineCoreError> {
    match payload {
        Some(CommandPayload::SetDragPending(value)) => Ok(value),
        _ => Err(EngineCoreError::InvalidPayload(kind)),
    }
}

fn extract_start_box_select_payload(
    kind: EngineCommandKind,
    payload: Option<CommandPayload>,
) -> Result<StartBoxSelectCommand, EngineCoreError> {
    match payload {
        Some(CommandPayload::StartBoxSelect(value)) => Ok(value),
        _ => Err(EngineCoreError::InvalidPayload(kind)),
    }
}

fn extract_update_box_select_payload(
    kind: EngineCommandKind,
    payload: Option<CommandPayload>,
) -> Result<UpdateBoxSelectCommand, EngineCoreError> {
    match payload {
        Some(CommandPayload::UpdateBoxSelect(value)) => Ok(value),
        _ => Err(EngineCoreError::InvalidPayload(kind)),
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn create_command(element_id: &str, element_type: ElementType) -> EngineCommand {
        EngineCommand {
            kind: EngineCommandKind::CreateElement as i32,
            payload: Some(CommandPayload::CreateElement(CreateElementCommand {
                element_type: element_type as i32,
                element_id: element_id.to_string(),
                position: Some(DrawPoint {
                    x: 10.0,
                    y: 20.0,
                    pressure: 0.0,
                    timestamp_us: 0,
                }),
                initial_payload: vec![1, 2, 3],
                maintain_aspect_ratio: false,
                create_from_center: false,
                snap_override: false,
            })),
        }
    }

    #[test]
    fn create_undo_redo_flow() {
        let mut engine = Engine::default();

        let command = create_command("rect-1", ElementType::Rectangle);

        engine.dispatch(command).expect("dispatch create");
        assert_eq!(engine.snapshot.elements.len(), 1);
        assert_eq!(engine.snapshot.history_undo_len, 1);

        engine
            .dispatch(EngineCommand {
                kind: EngineCommandKind::Undo as i32,
                payload: None,
            })
            .expect("undo");
        assert_eq!(engine.snapshot.elements.len(), 0);

        engine
            .dispatch(EngineCommand {
                kind: EngineCommandKind::Redo as i32,
                payload: None,
            })
            .expect("redo");
        assert_eq!(engine.snapshot.elements.len(), 1);
    }

    #[test]
    fn frame_plan_contains_background_and_elements() {
        let mut engine = Engine::default();
        engine
            .dispatch(create_command("text-1", ElementType::Text))
            .expect("create");

        let plan = engine.build_frame_plan(FramePlanRequest {
            viewport: None,
            locale_tag: "en-US".to_string(),
            scale_factor: 1.0,
        });

        assert!(!plan.tasks.is_empty());
        assert_eq!(plan.tasks[0].kind, FrameTaskKind::Background as i32);
        assert_eq!(plan.tasks[1].kind, FrameTaskKind::Grid as i32);
        assert!(plan
            .tasks
            .iter()
            .any(|task| task.kind == FrameTaskKind::Text as i32));
    }

    #[test]
    fn update_creating_create_from_center_uses_original_anchor() {
        let mut engine = Engine::default();
        engine
            .dispatch(create_command("center-create", ElementType::Rectangle))
            .expect("create");

        engine
            .dispatch(EngineCommand {
                kind: EngineCommandKind::UpdateCreatingElement as i32,
                payload: Some(CommandPayload::UpdateCreatingElement(
                    UpdateCreatingElementCommand {
                        positions: vec![DrawPoint {
                            x: 60.0,
                            y: 70.0,
                            pressure: 0.0,
                            timestamp_us: 0,
                        }],
                        maintain_aspect_ratio: false,
                        create_from_center: true,
                        snap_override: false,
                    },
                )),
            })
            .expect("first update");

        let rect = engine
            .snapshot
            .elements
            .iter()
            .find(|element| element.id == "center-create")
            .and_then(|element| element.rect.clone())
            .expect("updated rect");
        assert_eq!(rect.min_x, -40.0);
        assert_eq!(rect.min_y, -30.0);
        assert_eq!(rect.max_x, 60.0);
        assert_eq!(rect.max_y, 70.0);

        engine
            .dispatch(EngineCommand {
                kind: EngineCommandKind::UpdateCreatingElement as i32,
                payload: Some(CommandPayload::UpdateCreatingElement(
                    UpdateCreatingElementCommand {
                        positions: vec![DrawPoint {
                            x: 80.0,
                            y: 90.0,
                            pressure: 0.0,
                            timestamp_us: 0,
                        }],
                        maintain_aspect_ratio: false,
                        create_from_center: true,
                        snap_override: false,
                    },
                )),
            })
            .expect("second update");

        let rect = engine
            .snapshot
            .elements
            .iter()
            .find(|element| element.id == "center-create")
            .and_then(|element| element.rect.clone())
            .expect("updated rect");
        assert_eq!(rect.min_x, -60.0);
        assert_eq!(rect.min_y, -50.0);
        assert_eq!(rect.max_x, 80.0);
        assert_eq!(rect.max_y, 90.0);
    }

    #[test]
    fn action_coverage_all_command_kinds_dispatch_without_panic() {
        let mut engine = Engine::default();
        let commands = [
            EngineCommand {
                kind: EngineCommandKind::SelectElement as i32,
                payload: Some(CommandPayload::SelectElement(SelectElementCommand {
                    element_id: "missing".to_string(),
                    add_to_selection: false,
                    position: None,
                })),
            },
            EngineCommand {
                kind: EngineCommandKind::ClearSelection as i32,
                payload: None,
            },
            EngineCommand {
                kind: EngineCommandKind::SelectAll as i32,
                payload: None,
            },
            create_command("rect-coverage", ElementType::Rectangle),
            EngineCommand {
                kind: EngineCommandKind::UpdateCreatingElement as i32,
                payload: Some(CommandPayload::UpdateCreatingElement(
                    UpdateCreatingElementCommand {
                        positions: vec![DrawPoint {
                            x: 42.0,
                            y: 52.0,
                            pressure: 0.0,
                            timestamp_us: 0,
                        }],
                        maintain_aspect_ratio: false,
                        create_from_center: false,
                        snap_override: false,
                    },
                )),
            },
            EngineCommand {
                kind: EngineCommandKind::AddArrowPoint as i32,
                payload: Some(CommandPayload::AddArrowPoint(AddArrowPointCommand {
                    position: Some(DrawPoint {
                        x: 55.0,
                        y: 66.0,
                        pressure: 0.0,
                        timestamp_us: 0,
                    }),
                    snap_override: false,
                })),
            },
            EngineCommand {
                kind: EngineCommandKind::FinishCreateElement as i32,
                payload: None,
            },
            EngineCommand {
                kind: EngineCommandKind::CancelCreateElement as i32,
                payload: None,
            },
            EngineCommand {
                kind: EngineCommandKind::DeleteElements as i32,
                payload: Some(CommandPayload::DeleteElements(
                    engine_proto::DeleteElementsCommand {
                        element_ids: vec!["rect-coverage".to_string()],
                    },
                )),
            },
            EngineCommand {
                kind: EngineCommandKind::DuplicateElements as i32,
                payload: Some(CommandPayload::DuplicateElements(
                    DuplicateElementsCommand {
                        element_ids: vec!["rect-coverage".to_string()],
                        offset_x: 10.0,
                        offset_y: 10.0,
                    },
                )),
            },
            EngineCommand {
                kind: EngineCommandKind::ChangeElementZIndex as i32,
                payload: Some(CommandPayload::ChangeElementZIndex(
                    ChangeElementZIndexCommand {
                        element_id: "rect-coverage".to_string(),
                        operation: ZIndexOperation::BringToFront as i32,
                    },
                )),
            },
            EngineCommand {
                kind: EngineCommandKind::ChangeElementsZIndex as i32,
                payload: Some(CommandPayload::ChangeElementsZIndex(
                    ChangeElementsZIndexCommand {
                        element_ids: vec!["rect-coverage".to_string()],
                        operation: ZIndexOperation::SendToBack as i32,
                    },
                )),
            },
            EngineCommand {
                kind: EngineCommandKind::UpdateElementsStyle as i32,
                payload: Some(CommandPayload::UpdateElementsStyle(
                    UpdateElementsStyleCommand {
                        element_ids: vec!["rect-coverage".to_string()],
                        style_payload: vec![9, 9, 9],
                    },
                )),
            },
            EngineCommand {
                kind: EngineCommandKind::UpdateGlobalElements as i32,
                payload: Some(CommandPayload::UpdateGlobalElements(
                    UpdateGlobalElementsCommand {
                        payload: vec![1, 2, 3, 4],
                    },
                )),
            },
            EngineCommand {
                kind: EngineCommandKind::CreateSerialNumberTextElements as i32,
                payload: Some(CommandPayload::CreateSerialNumberTextElements(
                    CreateSerialNumberTextElementsCommand {
                        element_ids: vec!["rect-coverage".to_string()],
                    },
                )),
            },
            EngineCommand {
                kind: EngineCommandKind::StartTextEdit as i32,
                payload: Some(CommandPayload::StartTextEdit(StartTextEditCommand {
                    element_id: "text-coverage".to_string(),
                    position: Some(DrawPoint {
                        x: 0.0,
                        y: 0.0,
                        pressure: 0.0,
                        timestamp_us: 0,
                    }),
                })),
            },
            EngineCommand {
                kind: EngineCommandKind::UpdateTextEdit as i32,
                payload: Some(CommandPayload::UpdateTextEdit(UpdateTextEditCommand {
                    text: "hello".to_string(),
                    rect: None,
                })),
            },
            EngineCommand {
                kind: EngineCommandKind::RefreshAutoResizeTextLayoutsAfterFontLoad as i32,
                payload: None,
            },
            EngineCommand {
                kind: EngineCommandKind::FinishTextEdit as i32,
                payload: Some(CommandPayload::FinishTextEdit(FinishTextEditCommand {
                    element_id: "text-coverage".to_string(),
                    text: "world".to_string(),
                    is_new: false,
                })),
            },
            EngineCommand {
                kind: EngineCommandKind::CancelTextEdit as i32,
                payload: None,
            },
            EngineCommand {
                kind: EngineCommandKind::StartEdit as i32,
                payload: Some(CommandPayload::StartEdit(engine_proto::StartEditCommand {
                    operation_id: "move".to_string(),
                    position: Some(DrawPoint {
                        x: 0.0,
                        y: 0.0,
                        pressure: 0.0,
                        timestamp_us: 0,
                    }),
                    params: Vec::new(),
                })),
            },
            EngineCommand {
                kind: EngineCommandKind::UpdateEdit as i32,
                payload: Some(CommandPayload::UpdateEdit(UpdateEditCommand {
                    current_position: Some(DrawPoint {
                        x: 10.0,
                        y: 20.0,
                        pressure: 0.0,
                        timestamp_us: 0,
                    }),
                    modifiers: vec![9],
                })),
            },
            EngineCommand {
                kind: EngineCommandKind::FinishEdit as i32,
                payload: None,
            },
            EngineCommand {
                kind: EngineCommandKind::CancelEdit as i32,
                payload: None,
            },
            EngineCommand {
                kind: EngineCommandKind::SetDragPending as i32,
                payload: Some(CommandPayload::SetDragPending(SetDragPendingCommand {
                    pointer_down_position: Some(DrawPoint {
                        x: 0.0,
                        y: 0.0,
                        pressure: 0.0,
                        timestamp_us: 0,
                    }),
                    intent: "move".to_string(),
                })),
            },
            EngineCommand {
                kind: EngineCommandKind::ClearDragPending as i32,
                payload: None,
            },
            EngineCommand {
                kind: EngineCommandKind::StartBoxSelect as i32,
                payload: Some(CommandPayload::StartBoxSelect(StartBoxSelectCommand {
                    start_position: Some(DrawPoint {
                        x: 0.0,
                        y: 0.0,
                        pressure: 0.0,
                        timestamp_us: 0,
                    }),
                })),
            },
            EngineCommand {
                kind: EngineCommandKind::UpdateBoxSelect as i32,
                payload: Some(CommandPayload::UpdateBoxSelect(UpdateBoxSelectCommand {
                    current_position: Some(DrawPoint {
                        x: 100.0,
                        y: 100.0,
                        pressure: 0.0,
                        timestamp_us: 0,
                    }),
                })),
            },
            EngineCommand {
                kind: EngineCommandKind::FinishBoxSelect as i32,
                payload: None,
            },
            EngineCommand {
                kind: EngineCommandKind::CancelBoxSelect as i32,
                payload: None,
            },
            EngineCommand {
                kind: EngineCommandKind::MoveCamera as i32,
                payload: Some(CommandPayload::MoveCamera(MoveCameraCommand {
                    dx: 1.0,
                    dy: -1.0,
                })),
            },
            EngineCommand {
                kind: EngineCommandKind::ZoomCamera as i32,
                payload: Some(CommandPayload::ZoomCamera(ZoomCameraCommand {
                    scale: 1.1,
                    center: None,
                })),
            },
            EngineCommand {
                kind: EngineCommandKind::Undo as i32,
                payload: None,
            },
            EngineCommand {
                kind: EngineCommandKind::Redo as i32,
                payload: None,
            },
            EngineCommand {
                kind: EngineCommandKind::ClearHistory as i32,
                payload: None,
            },
        ];

        for command in commands {
            let result = engine.dispatch(command);
            assert!(result.is_ok());
        }
    }

    #[test]
    fn duplicate_and_zindex_are_deterministic() {
        let mut engine = Engine::default();
        engine
            .dispatch(create_command("z-a", ElementType::Rectangle))
            .expect("create z-a");
        engine
            .dispatch(create_command("z-b", ElementType::Rectangle))
            .expect("create z-b");

        engine
            .dispatch(EngineCommand {
                kind: EngineCommandKind::DuplicateElements as i32,
                payload: Some(CommandPayload::DuplicateElements(
                    DuplicateElementsCommand {
                        element_ids: vec!["z-a".to_string()],
                        offset_x: 4.0,
                        offset_y: 8.0,
                    },
                )),
            })
            .expect("duplicate");

        let duplicated = engine
            .snapshot
            .elements
            .iter()
            .find(|element| element.id.starts_with("rust_"))
            .expect("duplicated element exists")
            .id
            .clone();

        engine
            .dispatch(EngineCommand {
                kind: EngineCommandKind::ChangeElementZIndex as i32,
                payload: Some(CommandPayload::ChangeElementZIndex(
                    ChangeElementZIndexCommand {
                        element_id: duplicated.clone(),
                        operation: ZIndexOperation::SendToBack as i32,
                    },
                )),
            })
            .expect("send to back");

        let first = engine.snapshot.elements.first().expect("first element");
        assert_eq!(first.id, duplicated);
    }

    #[test]
    fn text_edit_session_updates_payload() {
        let mut engine = Engine::default();
        engine
            .dispatch(EngineCommand {
                kind: EngineCommandKind::StartTextEdit as i32,
                payload: Some(CommandPayload::StartTextEdit(StartTextEditCommand {
                    element_id: String::new(),
                    position: Some(DrawPoint {
                        x: 12.0,
                        y: 34.0,
                        pressure: 0.0,
                        timestamp_us: 0,
                    }),
                })),
            })
            .expect("start text edit");

        let edited_id = engine
            .snapshot
            .selected_ids
            .first()
            .expect("selected")
            .clone();

        engine
            .dispatch(EngineCommand {
                kind: EngineCommandKind::UpdateTextEdit as i32,
                payload: Some(CommandPayload::UpdateTextEdit(UpdateTextEditCommand {
                    text: "hello-rust".to_string(),
                    rect: None,
                })),
            })
            .expect("update text edit");

        engine
            .dispatch(EngineCommand {
                kind: EngineCommandKind::FinishTextEdit as i32,
                payload: Some(CommandPayload::FinishTextEdit(FinishTextEditCommand {
                    element_id: edited_id.clone(),
                    text: "hello-rust".to_string(),
                    is_new: true,
                })),
            })
            .expect("finish text edit");

        let element = engine
            .snapshot
            .elements
            .iter()
            .find(|element| element.id == edited_id)
            .expect("text element still present");
        let payload = serde_json::from_slice::<serde_json::Value>(&element.payload)
            .expect("text payload json");
        assert_eq!(
            payload.get("text").and_then(|value| value.as_str()),
            Some("hello-rust")
        );
        assert_eq!(
            engine.snapshot.interaction_mode,
            InteractionMode::Idle as i32
        );
    }

    #[test]
    fn apply_text_metrics_layout_updates_auto_resize_text_rect() {
        let mut engine = Engine::default();
        engine
            .dispatch(EngineCommand {
                kind: EngineCommandKind::CreateElement as i32,
                payload: Some(CommandPayload::CreateElement(CreateElementCommand {
                    element_type: ElementType::Text as i32,
                    element_id: "text-metrics".to_string(),
                    position: Some(DrawPoint {
                        x: 10.0,
                        y: 20.0,
                        pressure: 0.0,
                        timestamp_us: 0,
                    }),
                    initial_payload:
                        br#"{"typeId":"text","text":"hello","fontSize":20.0,"autoResize":true}"#
                            .to_vec(),
                    maintain_aspect_ratio: false,
                    create_from_center: false,
                    snap_override: false,
                })),
            })
            .expect("create text");
        let baseline_version = engine.snapshot.document_version;
        while engine.poll_event().is_some() {}

        assert!(engine.apply_text_metrics_layout("text-metrics", "hello", 88.0, 24.0, 24.0));
        assert!(!engine.apply_text_metrics_layout("text-metrics", "stale", 120.0, 40.0, 40.0));

        let element = engine
            .snapshot
            .elements
            .iter()
            .find(|element| element.id == "text-metrics")
            .expect("text element");
        let rect = element.rect.as_ref().expect("text rect");
        assert!(((rect.max_x - rect.min_x) - 88.48).abs() < 1e-9);
        assert!(((rect.max_y - rect.min_y) - 24.0).abs() < 1e-9);
        assert!(engine.snapshot.document_version > baseline_version);

        let event = engine.poll_event().expect("state changed event");
        assert_eq!(event.kind, EngineEventKind::StateChanged as i32);
    }

    #[test]
    fn refresh_auto_resize_text_layouts_recomputes_text_bounds() {
        let mut engine = Engine::default();
        engine
            .dispatch(EngineCommand {
                kind: EngineCommandKind::CreateElement as i32,
                payload: Some(CommandPayload::CreateElement(CreateElementCommand {
                    element_type: ElementType::Text as i32,
                    element_id: "refresh-auto".to_string(),
                    position: Some(DrawPoint {
                        x: 10.0,
                        y: 20.0,
                        pressure: 0.0,
                        timestamp_us: 0,
                    }),
                    initial_payload:
                        br#"{"typeId":"text","text":"hello","fontSize":20.0,"autoResize":true}"#
                            .to_vec(),
                    maintain_aspect_ratio: false,
                    create_from_center: false,
                    snap_override: false,
                })),
            })
            .expect("create auto text");
        engine
            .dispatch(EngineCommand {
                kind: EngineCommandKind::CreateElement as i32,
                payload: Some(CommandPayload::CreateElement(CreateElementCommand {
                    element_type: ElementType::Text as i32,
                    element_id: "refresh-fixed".to_string(),
                    position: Some(DrawPoint {
                        x: 200.0,
                        y: 120.0,
                        pressure: 0.0,
                        timestamp_us: 0,
                    }),
                    initial_payload:
                        br#"{"typeId":"text","text":"fixed","fontSize":20.0,"autoResize":false}"#
                            .to_vec(),
                    maintain_aspect_ratio: false,
                    create_from_center: false,
                    snap_override: false,
                })),
            })
            .expect("create fixed text");

        let auto_before = engine
            .snapshot
            .elements
            .iter()
            .find(|element| element.id == "refresh-auto")
            .and_then(|element| element.rect.clone())
            .expect("auto rect before");
        let fixed_before = engine
            .snapshot
            .elements
            .iter()
            .find(|element| element.id == "refresh-fixed")
            .and_then(|element| element.rect.clone())
            .expect("fixed rect before");
        let document_version_before = engine.snapshot.document_version;

        while engine.poll_event().is_some() {}

        engine
            .dispatch(EngineCommand {
                kind: EngineCommandKind::RefreshAutoResizeTextLayoutsAfterFontLoad as i32,
                payload: None,
            })
            .expect("refresh auto-resize text");

        let auto_after = engine
            .snapshot
            .elements
            .iter()
            .find(|element| element.id == "refresh-auto")
            .and_then(|element| element.rect.clone())
            .expect("auto rect after");
        let fixed_after = engine
            .snapshot
            .elements
            .iter()
            .find(|element| element.id == "refresh-fixed")
            .and_then(|element| element.rect.clone())
            .expect("fixed rect after");

        assert_ne!(auto_after, auto_before);
        assert_eq!(fixed_after, fixed_before);
        assert!(engine.snapshot.document_version > document_version_before);
        assert!(((auto_after.max_x - auto_after.min_x) - 60.48).abs() < 1e-9);
        assert!(((auto_after.max_y - auto_after.min_y) - 24.0).abs() < 1e-9);

        let event = engine.poll_event().expect("state changed event");
        assert_eq!(event.kind, EngineEventKind::StateChanged as i32);
        assert!(engine.poll_event().is_none());
    }

    #[test]
    fn box_select_selects_intersecting_elements() {
        let mut engine = Engine::default();
        engine
            .dispatch(create_command("box-a", ElementType::Rectangle))
            .expect("create box-a");
        engine
            .dispatch(EngineCommand {
                kind: EngineCommandKind::StartBoxSelect as i32,
                payload: Some(CommandPayload::StartBoxSelect(StartBoxSelectCommand {
                    start_position: Some(DrawPoint {
                        x: 0.0,
                        y: 0.0,
                        pressure: 0.0,
                        timestamp_us: 0,
                    }),
                })),
            })
            .expect("start box select");
        engine
            .dispatch(EngineCommand {
                kind: EngineCommandKind::UpdateBoxSelect as i32,
                payload: Some(CommandPayload::UpdateBoxSelect(UpdateBoxSelectCommand {
                    current_position: Some(DrawPoint {
                        x: 200.0,
                        y: 200.0,
                        pressure: 0.0,
                        timestamp_us: 0,
                    }),
                })),
            })
            .expect("update box select");
        assert!(engine.snapshot.selected_ids.iter().any(|id| id == "box-a"));
    }

    #[test]
    fn event_queue_is_ordered_and_monotonic() {
        let mut engine = Engine::default();
        for index in 0..64 {
            engine
                .dispatch(EngineCommand {
                    kind: EngineCommandKind::MoveCamera as i32,
                    payload: Some(CommandPayload::MoveCamera(MoveCameraCommand {
                        dx: index as f64,
                        dy: 0.0,
                    })),
                })
                .expect("move camera dispatch");
        }

        let mut last_sequence = 0;
        let mut count = 0;
        while let Some(event) = engine.poll_event() {
            assert!(event.sequence > last_sequence);
            last_sequence = event.sequence;
            count += 1;
        }

        assert!(count >= 64);
    }

    #[test]
    fn zoom_validation_emits_error_event() {
        let mut engine = Engine::default();
        let result = engine.dispatch(EngineCommand {
            kind: EngineCommandKind::ZoomCamera as i32,
            payload: Some(CommandPayload::ZoomCamera(ZoomCameraCommand {
                scale: 0.0,
                center: None,
            })),
        });
        assert!(result.is_err());

        let event = engine.poll_event().expect("error event");
        assert_eq!(event.kind, EngineEventKind::Error as i32);
    }

    #[test]
    fn zoom_camera_applies_center_and_clamps() {
        let mut engine = Engine::default();
        engine
            .dispatch(EngineCommand {
                kind: EngineCommandKind::MoveCamera as i32,
                payload: Some(CommandPayload::MoveCamera(MoveCameraCommand {
                    dx: 10.0,
                    dy: 20.0,
                })),
            })
            .expect("move");

        engine
            .dispatch(EngineCommand {
                kind: EngineCommandKind::ZoomCamera as i32,
                payload: Some(CommandPayload::ZoomCamera(ZoomCameraCommand {
                    scale: 2.0,
                    center: Some(DrawPoint {
                        x: 20.0,
                        y: 20.0,
                        pressure: 0.0,
                        timestamp_us: 0,
                    }),
                })),
            })
            .expect("zoom around center");

        let camera = engine.snapshot.camera.as_ref().expect("camera");
        let position = camera.position.as_ref().expect("position");
        assert!((camera.zoom - 2.0).abs() < 1e-9);
        assert!((position.x - 0.0).abs() < 1e-9);
        assert!((position.y - 20.0).abs() < 1e-9);

        engine
            .dispatch(EngineCommand {
                kind: EngineCommandKind::ZoomCamera as i32,
                payload: Some(CommandPayload::ZoomCamera(ZoomCameraCommand {
                    scale: 1000.0,
                    center: None,
                })),
            })
            .expect("zoom clamp max");
        let camera = engine.snapshot.camera.as_ref().expect("camera");
        assert!((camera.zoom - CAMERA_MAX_ZOOM).abs() < 1e-9);

        engine
            .dispatch(EngineCommand {
                kind: EngineCommandKind::ZoomCamera as i32,
                payload: Some(CommandPayload::ZoomCamera(ZoomCameraCommand {
                    scale: 0.001,
                    center: None,
                })),
            })
            .expect("zoom clamp min");
        let camera = engine.snapshot.camera.as_ref().expect("camera");
        assert!((camera.zoom - CAMERA_MIN_ZOOM).abs() < 1e-9);
    }

    #[test]
    fn create_default_payloads_are_json_for_all_builtin_types() {
        let mut engine = Engine::default();
        let builtins = [
            ElementType::Rectangle,
            ElementType::Arrow,
            ElementType::Line,
            ElementType::FreeDraw,
            ElementType::Filter,
            ElementType::Highlight,
            ElementType::Text,
            ElementType::SerialNumber,
        ];

        for (index, element_type) in builtins.into_iter().enumerate() {
            engine
                .dispatch(EngineCommand {
                    kind: EngineCommandKind::CreateElement as i32,
                    payload: Some(CommandPayload::CreateElement(CreateElementCommand {
                        element_type: element_type as i32,
                        element_id: format!("builtin-{index}"),
                        position: None,
                        initial_payload: Vec::new(),
                        maintain_aspect_ratio: false,
                        create_from_center: false,
                        snap_override: false,
                    })),
                })
                .expect("create builtin");
        }

        for element in &engine.snapshot.elements {
            let payload = serde_json::from_slice::<serde_json::Value>(&element.payload)
                .expect("json payload");
            assert!(payload.get("typeId").is_some());
        }
    }

    #[test]
    fn update_style_merges_json_payload_and_opacity() {
        let mut engine = Engine::default();
        engine
            .dispatch(create_command("rect-style", ElementType::Rectangle))
            .expect("create");

        engine
            .dispatch(EngineCommand {
                kind: EngineCommandKind::UpdateElementsStyle as i32,
                payload: Some(CommandPayload::UpdateElementsStyle(
                    UpdateElementsStyleCommand {
                        element_ids: vec!["rect-style".to_string()],
                        style_payload: br#"{"color":4278190335,"opacity":0.4}"#.to_vec(),
                    },
                )),
            })
            .expect("style update");

        let element = engine
            .snapshot
            .elements
            .iter()
            .find(|element| element.id == "rect-style")
            .expect("rect");
        let payload =
            serde_json::from_slice::<serde_json::Value>(&element.payload).expect("json payload");
        assert_eq!(
            payload.get("color").and_then(|value| value.as_u64()),
            Some(4278190335)
        );
        assert!((element.opacity - 0.4).abs() < f64::EPSILON);
    }

    #[test]
    fn create_serial_number_text_elements_binds_and_focuses_single_target() {
        let mut engine = Engine::default();
        engine
            .dispatch(create_command("serial-focus", ElementType::SerialNumber))
            .expect("create serial");
        let previous_document_version = engine.snapshot.document_version;

        engine
            .dispatch(EngineCommand {
                kind: EngineCommandKind::CreateSerialNumberTextElements as i32,
                payload: Some(CommandPayload::CreateSerialNumberTextElements(
                    CreateSerialNumberTextElementsCommand {
                        element_ids: vec!["serial-focus".to_string()],
                    },
                )),
            })
            .expect("create bound text");

        assert!(engine.snapshot.document_version > previous_document_version);
        let serial = engine
            .snapshot
            .elements
            .iter()
            .find(|element| element.id == "serial-focus")
            .expect("serial element");
        let serial_payload = decode_json_map(&serial.payload).expect("serial payload");
        let text_id = serial_payload
            .get("textElementId")
            .and_then(JsonValue::as_str)
            .map(str::to_string)
            .expect("textElementId");
        assert!(!text_id.is_empty());

        let text = engine
            .snapshot
            .elements
            .iter()
            .find(|element| element.id == text_id)
            .expect("bound text");
        assert_eq!(
            normalize_element_type(text.element_type),
            ElementType::Text as i32
        );
        assert_eq!(engine.snapshot.selected_ids, vec![text_id.clone()]);
        assert_eq!(
            engine.snapshot.interaction_mode,
            InteractionMode::TextEditing as i32
        );
        assert_eq!(
            engine
                .text_edit_session
                .as_ref()
                .map(|session| session.element_id.clone()),
            Some(text_id)
        );
        let serial_rect = serial.rect.as_ref().expect("serial rect");
        let text_rect = text.rect.as_ref().expect("text rect");
        assert!(text_rect.min_x >= serial_rect.max_x);
    }

    #[test]
    fn create_serial_number_text_elements_reuses_existing_binding() {
        let mut engine = Engine::default();
        engine
            .dispatch(EngineCommand {
                kind: EngineCommandKind::CreateElement as i32,
                payload: Some(CommandPayload::CreateElement(CreateElementCommand {
                    element_type: ElementType::Text as i32,
                    element_id: "serial-bound-text".to_string(),
                    position: Some(DrawPoint {
                        x: 120.0,
                        y: 40.0,
                        pressure: 0.0,
                        timestamp_us: 0,
                    }),
                    initial_payload: br#"{"typeId":"text","text":"bound"}"#.to_vec(),
                    maintain_aspect_ratio: false,
                    create_from_center: false,
                    snap_override: false,
                })),
            })
            .expect("create text");
        engine
            .dispatch(EngineCommand {
                kind: EngineCommandKind::CreateElement as i32,
                payload: Some(CommandPayload::CreateElement(CreateElementCommand {
                    element_type: ElementType::SerialNumber as i32,
                    element_id: "serial-reuse".to_string(),
                    position: Some(DrawPoint {
                        x: 10.0,
                        y: 10.0,
                        pressure: 0.0,
                        timestamp_us: 0,
                    }),
                    initial_payload: br#"{"typeId":"serial_number","number":7,"textElementId":"serial-bound-text"}"#.to_vec(),
                    maintain_aspect_ratio: false,
                    create_from_center: false,
                    snap_override: false,
                })),
            })
            .expect("create serial");
        let before_len = engine.snapshot.elements.len();
        let before_document_version = engine.snapshot.document_version;

        engine
            .dispatch(EngineCommand {
                kind: EngineCommandKind::CreateSerialNumberTextElements as i32,
                payload: Some(CommandPayload::CreateSerialNumberTextElements(
                    CreateSerialNumberTextElementsCommand {
                        element_ids: vec!["serial-reuse".to_string()],
                    },
                )),
            })
            .expect("reuse bound text");

        assert_eq!(engine.snapshot.elements.len(), before_len);
        assert_eq!(engine.snapshot.document_version, before_document_version);
        assert_eq!(
            engine.snapshot.selected_ids,
            vec!["serial-bound-text".to_string()]
        );
        assert_eq!(
            engine.snapshot.interaction_mode,
            InteractionMode::TextEditing as i32
        );
        assert_eq!(
            engine
                .text_edit_session
                .as_ref()
                .map(|session| session.element_id.as_str()),
            Some("serial-bound-text")
        );
    }

    #[test]
    fn frame_plan_adds_overlay_tasks_for_global_payloads() {
        let mut engine = Engine::default();
        engine
            .dispatch(create_command("rect-overlay", ElementType::Rectangle))
            .expect("create");
        engine
            .dispatch(EngineCommand {
                kind: EngineCommandKind::UpdateGlobalElements as i32,
                payload: Some(CommandPayload::UpdateGlobalElements(
                    UpdateGlobalElementsCommand {
                        payload: br#"{"highlightMask":{"maskColor":4278190080,"maskOpacity":0.5},"watermark":{"text":"CONFIDENTIAL","opacity":0.3}}"#.to_vec(),
                    },
                )),
            })
            .expect("update global");

        let plan = engine.build_frame_plan(FramePlanRequest {
            viewport: None,
            locale_tag: String::new(),
            scale_factor: 1.0,
        });

        assert!(plan
            .tasks
            .iter()
            .any(|task| task.kind == FrameTaskKind::HighlightMask as i32));
        assert!(plan
            .tasks
            .iter()
            .any(|task| task.kind == FrameTaskKind::Watermark as i32));
        assert!(plan
            .tasks
            .iter()
            .any(|task| task.kind == FrameTaskKind::SelectionOutline as i32));
    }

    #[test]
    fn frame_plan_emits_arrow_overlay_and_binding_highlight_payloads() {
        let mut engine = Engine::default();
        engine
            .dispatch(create_command("binding-target", ElementType::Rectangle))
            .expect("create target");
        engine
            .dispatch(EngineCommand {
                kind: EngineCommandKind::CreateElement as i32,
                payload: Some(CommandPayload::CreateElement(CreateElementCommand {
                    element_type: ElementType::Arrow as i32,
                    element_id: "arrow-overlay".to_string(),
                    position: Some(DrawPoint {
                        x: 20.0,
                        y: 20.0,
                        pressure: 0.0,
                        timestamp_us: 0,
                    }),
                    initial_payload: br#"{"typeId":"arrow","points":[{"x":0.0,"y":0.0},{"x":1.0,"y":1.0},{"x":1.0,"y":0.0}],"startBinding":{"elementId":"binding-target"}}"#.to_vec(),
                    maintain_aspect_ratio: false,
                    create_from_center: false,
                    snap_override: false,
                })),
            })
            .expect("create arrow");

        let plan = engine.build_frame_plan(FramePlanRequest {
            viewport: None,
            locale_tag: String::new(),
            scale_factor: 1.0,
        });

        let overlay = plan
            .tasks
            .iter()
            .find(|task| task.kind == FrameTaskKind::ArrowPointOverlay as i32)
            .expect("arrow overlay task");
        let overlay_payload =
            serde_json::from_slice::<serde_json::Value>(&overlay.payload).expect("overlay payload");
        let handles = overlay_payload
            .get("handles")
            .and_then(|value| value.as_array())
            .expect("overlay handles");
        assert_eq!(handles.len(), 5);
        assert_eq!(
            handles
                .first()
                .and_then(|value| value.get("kind"))
                .and_then(|value| value.as_str()),
            Some("addable")
        );
        assert!(!handles.iter().any(|entry| {
            entry.get("kind").and_then(|value| value.as_str()) == Some("loopStart")
        }));

        let binding = plan
            .tasks
            .iter()
            .find(|task| task.kind == FrameTaskKind::ArrowBindingHighlight as i32)
            .expect("binding highlight task");
        let binding_payload =
            serde_json::from_slice::<serde_json::Value>(&binding.payload).expect("binding payload");
        let ids = binding_payload
            .get("elementIds")
            .and_then(|value| value.as_array())
            .expect("binding ids");
        assert_eq!(ids.len(), 1);
        assert_eq!(
            ids.first().and_then(|value| value.as_str()),
            Some("binding-target")
        );
    }

    #[test]
    fn frame_plan_emits_arrow_binding_highlight_from_hover_payload_without_selection() {
        let mut engine = Engine::default();
        engine
            .dispatch(EngineCommand {
                kind: EngineCommandKind::ClearSelection as i32,
                payload: None,
            })
            .expect("clear selection");
        engine
            .dispatch(EngineCommand {
                kind: EngineCommandKind::UpdateGlobalElements as i32,
                payload: Some(CommandPayload::UpdateGlobalElements(
                    UpdateGlobalElementsCommand {
                        payload: br#"{"hoveredBindingElementId":"hover-binding-target"}"#.to_vec(),
                    },
                )),
            })
            .expect("update global payload");

        let plan = engine.build_frame_plan(FramePlanRequest {
            viewport: None,
            locale_tag: String::new(),
            scale_factor: 1.0,
        });
        let binding = plan
            .tasks
            .iter()
            .find(|task| task.kind == FrameTaskKind::ArrowBindingHighlight as i32)
            .expect("binding highlight task");
        let payload =
            serde_json::from_slice::<serde_json::Value>(&binding.payload).expect("binding payload");
        let ids = payload
            .get("elementIds")
            .and_then(|value| value.as_array())
            .expect("binding ids");
        assert_eq!(ids.len(), 1);
        assert_eq!(
            ids.first().and_then(|value| value.as_str()),
            Some("hover-binding-target")
        );
    }

    #[test]
    fn frame_plan_suppresses_hover_binding_highlight_when_handle_is_hovered() {
        let mut engine = Engine::default();
        engine
            .dispatch(EngineCommand {
                kind: EngineCommandKind::ClearSelection as i32,
                payload: None,
            })
            .expect("clear selection");
        engine
            .dispatch(EngineCommand {
                kind: EngineCommandKind::UpdateGlobalElements as i32,
                payload: Some(CommandPayload::UpdateGlobalElements(
                    UpdateGlobalElementsCommand {
                        payload: br#"{"hoveredBindingElementId":"hover-binding-target","hoveredArrowHandle":{"kind":"turning","index":0}}"#.to_vec(),
                    },
                )),
            })
            .expect("update global payload");

        let plan = engine.build_frame_plan(FramePlanRequest {
            viewport: None,
            locale_tag: String::new(),
            scale_factor: 1.0,
        });
        assert!(!plan
            .tasks
            .iter()
            .any(|task| task.kind == FrameTaskKind::ArrowBindingHighlight as i32));
    }

    #[test]
    fn frame_plan_arrow_overlay_emits_loop_handles_for_closed_paths() {
        let mut engine = Engine::default();
        engine
            .dispatch(EngineCommand {
                kind: EngineCommandKind::CreateElement as i32,
                payload: Some(CommandPayload::CreateElement(CreateElementCommand {
                    element_type: ElementType::Arrow as i32,
                    element_id: "arrow-loop".to_string(),
                    position: Some(DrawPoint {
                        x: 24.0,
                        y: 16.0,
                        pressure: 0.0,
                        timestamp_us: 0,
                    }),
                    initial_payload: br#"{"typeId":"arrow","arrowType":"straight","points":[{"x":0.0,"y":0.0},{"x":0.5,"y":1.0},{"x":0.04,"y":0.0}]}"#.to_vec(),
                    maintain_aspect_ratio: false,
                    create_from_center: false,
                    snap_override: false,
                })),
            })
            .expect("create loop arrow");

        let plan = engine.build_frame_plan(FramePlanRequest {
            viewport: None,
            locale_tag: String::new(),
            scale_factor: 1.0,
        });
        let overlay = plan
            .tasks
            .iter()
            .find(|task| task.kind == FrameTaskKind::ArrowPointOverlay as i32)
            .expect("arrow overlay task");
        let overlay_payload =
            serde_json::from_slice::<serde_json::Value>(&overlay.payload).expect("overlay payload");
        let handles = overlay_payload
            .get("handles")
            .and_then(|value| value.as_array())
            .expect("overlay handles");
        assert_eq!(handles.len(), 5);

        let loop_start_count = handles
            .iter()
            .filter(|entry| entry.get("kind").and_then(|value| value.as_str()) == Some("loopStart"))
            .count();
        let loop_end_count = handles
            .iter()
            .filter(|entry| entry.get("kind").and_then(|value| value.as_str()) == Some("loopEnd"))
            .count();
        let turning_indices = handles
            .iter()
            .filter(|entry| entry.get("kind").and_then(|value| value.as_str()) == Some("turning"))
            .filter_map(|entry| entry.get("index").and_then(|value| value.as_i64()))
            .collect::<Vec<_>>();
        assert_eq!(loop_start_count, 1);
        assert_eq!(loop_end_count, 1);
        assert_eq!(turning_indices, vec![1]);
    }

    #[test]
    fn frame_plan_arrow_overlay_uses_curved_segment_midpoint_for_addable_handles() {
        let mut engine = Engine::default();
        engine
            .dispatch(EngineCommand {
                kind: EngineCommandKind::CreateElement as i32,
                payload: Some(CommandPayload::CreateElement(CreateElementCommand {
                    element_type: ElementType::Arrow as i32,
                    element_id: "arrow-curved".to_string(),
                    position: Some(DrawPoint {
                        x: 10.0,
                        y: 10.0,
                        pressure: 0.0,
                        timestamp_us: 0,
                    }),
                    initial_payload: br#"{"typeId":"arrow","arrowType":"curved","points":[{"x":10.0,"y":10.0},{"x":110.0,"y":10.0},{"x":110.0,"y":110.0}]}"#.to_vec(),
                    maintain_aspect_ratio: false,
                    create_from_center: false,
                    snap_override: false,
                })),
            })
            .expect("create curved arrow");

        let plan = engine.build_frame_plan(FramePlanRequest {
            viewport: None,
            locale_tag: String::new(),
            scale_factor: 1.0,
        });
        let overlay = plan
            .tasks
            .iter()
            .find(|task| task.kind == FrameTaskKind::ArrowPointOverlay as i32)
            .expect("arrow overlay task");
        let overlay_payload =
            serde_json::from_slice::<serde_json::Value>(&overlay.payload).expect("overlay payload");
        let handles = overlay_payload
            .get("handles")
            .and_then(|value| value.as_array())
            .expect("overlay handles");
        let addable = handles
            .iter()
            .find(|entry| {
                entry.get("kind").and_then(|value| value.as_str()) == Some("addable")
                    && entry.get("index").and_then(|value| value.as_i64()) == Some(0)
            })
            .expect("first addable handle");
        let position = addable
            .get("position")
            .and_then(|value| value.as_object())
            .expect("addable position");
        let x = position
            .get("x")
            .and_then(|value| value.as_f64())
            .expect("x");
        let y = position
            .get("y")
            .and_then(|value| value.as_f64())
            .expect("y");

        assert!((x - 60.0).abs() < 1e-9);
        assert!((y - 3.75).abs() < 1e-9);
        // Curved midpoint should differ from straight-line midpoint (60, 10).
        assert!((y - 10.0).abs() > 1e-6);
    }

    #[test]
    fn frame_plan_arrow_overlay_emits_elbow_endpoint_turning_and_fixed_segments() {
        let mut engine = Engine::default();
        engine
            .dispatch(EngineCommand {
                kind: EngineCommandKind::CreateElement as i32,
                payload: Some(CommandPayload::CreateElement(CreateElementCommand {
                    element_type: ElementType::Arrow as i32,
                    element_id: "arrow-elbow".to_string(),
                    position: Some(DrawPoint {
                        x: 32.0,
                        y: 28.0,
                        pressure: 0.0,
                        timestamp_us: 0,
                    }),
                    initial_payload: br#"{"typeId":"arrow","arrowType":"elbow","points":[{"x":0.0,"y":0.0},{"x":0.5,"y":0.0},{"x":0.5,"y":0.8},{"x":1.0,"y":0.8}],"fixedSegments":[{"index":1},{"index":3}]}"#.to_vec(),
                    maintain_aspect_ratio: false,
                    create_from_center: false,
                    snap_override: false,
                })),
            })
            .expect("create elbow arrow");

        let plan = engine.build_frame_plan(FramePlanRequest {
            viewport: None,
            locale_tag: String::new(),
            scale_factor: 1.0,
        });
        let overlay = plan
            .tasks
            .iter()
            .find(|task| task.kind == FrameTaskKind::ArrowPointOverlay as i32)
            .expect("arrow overlay task");
        let overlay_payload =
            serde_json::from_slice::<serde_json::Value>(&overlay.payload).expect("overlay payload");
        let handles = overlay_payload
            .get("handles")
            .and_then(|value| value.as_array())
            .expect("overlay handles");
        assert_eq!(handles.len(), 5);

        let turning_indices = handles
            .iter()
            .filter(|entry| entry.get("kind").and_then(|value| value.as_str()) == Some("turning"))
            .filter_map(|entry| entry.get("index").and_then(|value| value.as_i64()))
            .collect::<Vec<_>>();
        assert_eq!(turning_indices, vec![0, 3]);
        assert!(!handles.iter().any(|entry| {
            let kind = entry.get("kind").and_then(|value| value.as_str());
            kind == Some("loopStart") || kind == Some("loopEnd")
        }));

        let fixed_addable_indices = handles
            .iter()
            .filter(|entry| entry.get("kind").and_then(|value| value.as_str()) == Some("addable"))
            .filter(|entry| {
                entry
                    .get("isFixed")
                    .and_then(|value| value.as_bool())
                    .unwrap_or(false)
            })
            .filter_map(|entry| entry.get("index").and_then(|value| value.as_i64()))
            .collect::<Vec<_>>();
        assert_eq!(fixed_addable_indices, vec![0, 2]);
    }

    #[test]
    fn frame_plan_emits_hover_outline_and_snap_guides_from_global_payload() {
        let mut engine = Engine::default();
        engine
            .dispatch(EngineCommand {
                kind: EngineCommandKind::CreateElement as i32,
                payload: Some(CommandPayload::CreateElement(CreateElementCommand {
                    element_type: ElementType::Text as i32,
                    element_id: "hover-target".to_string(),
                    position: Some(DrawPoint {
                        x: 20.0,
                        y: 20.0,
                        pressure: 0.0,
                        timestamp_us: 0,
                    }),
                    initial_payload: Vec::new(),
                    maintain_aspect_ratio: false,
                    create_from_center: false,
                    snap_override: false,
                })),
            })
            .expect("create text");
        engine
            .dispatch(EngineCommand {
                kind: EngineCommandKind::ClearSelection as i32,
                payload: None,
            })
            .expect("clear selection");
        engine
            .dispatch(EngineCommand {
                kind: EngineCommandKind::UpdateGlobalElements as i32,
                payload: Some(CommandPayload::UpdateGlobalElements(
                    UpdateGlobalElementsCommand {
                        payload: br#"{"hoverOutline":{"elementId":"hover-target","useTextUnderlineStyle":true},"snapGuides":[{"kind":"point","axis":"horizontal","start":{"x":0.0,"y":10.0},"end":{"x":100.0,"y":10.0}}]}"#.to_vec(),
                    },
                )),
            })
            .expect("update global overlays");

        let plan = engine.build_frame_plan(FramePlanRequest {
            viewport: None,
            locale_tag: String::new(),
            scale_factor: 1.0,
        });

        let hover = plan
            .tasks
            .iter()
            .find(|task| task.kind == FrameTaskKind::HoverOutline as i32)
            .expect("hover outline task");
        let hover_payload =
            serde_json::from_slice::<serde_json::Value>(&hover.payload).expect("hover payload");
        assert_eq!(
            hover_payload
                .get("elementId")
                .and_then(|value| value.as_str()),
            Some("hover-target")
        );
        assert_eq!(
            hover_payload
                .get("useTextUnderlineStyle")
                .and_then(|value| value.as_bool()),
            Some(true)
        );

        let guides = plan
            .tasks
            .iter()
            .find(|task| task.kind == FrameTaskKind::SnapGuides as i32)
            .expect("snap guides task");
        let guides_payload =
            serde_json::from_slice::<serde_json::Value>(&guides.payload).expect("guides payload");
        let entries = guides_payload
            .get("guides")
            .and_then(|value| value.as_array())
            .expect("guides list");
        assert_eq!(entries.len(), 1);
    }

    #[test]
    fn frame_plan_skips_hover_outline_for_selected_target() {
        let mut engine = Engine::default();
        engine
            .dispatch(EngineCommand {
                kind: EngineCommandKind::CreateElement as i32,
                payload: Some(CommandPayload::CreateElement(CreateElementCommand {
                    element_type: ElementType::Text as i32,
                    element_id: "hover-selected".to_string(),
                    position: Some(DrawPoint {
                        x: 12.0,
                        y: 12.0,
                        pressure: 0.0,
                        timestamp_us: 0,
                    }),
                    initial_payload: Vec::new(),
                    maintain_aspect_ratio: false,
                    create_from_center: false,
                    snap_override: false,
                })),
            })
            .expect("create text");
        engine
            .dispatch(EngineCommand {
                kind: EngineCommandKind::UpdateGlobalElements as i32,
                payload: Some(CommandPayload::UpdateGlobalElements(
                    UpdateGlobalElementsCommand {
                        payload: br#"{"hoverOutline":{"elementId":"hover-selected","useTextUnderlineStyle":true}}"#
                            .to_vec(),
                    },
                )),
            })
            .expect("update global overlays");

        let plan = engine.build_frame_plan(FramePlanRequest {
            viewport: None,
            locale_tag: String::new(),
            scale_factor: 1.0,
        });
        assert!(!plan
            .tasks
            .iter()
            .any(|task| task.kind == FrameTaskKind::HoverOutline as i32));
    }

    #[test]
    fn frame_plan_box_selection_payload_tracks_bounds() {
        let mut engine = Engine::default();
        engine
            .dispatch(EngineCommand {
                kind: EngineCommandKind::StartBoxSelect as i32,
                payload: Some(CommandPayload::StartBoxSelect(StartBoxSelectCommand {
                    start_position: Some(DrawPoint {
                        x: 12.0,
                        y: 18.0,
                        pressure: 0.0,
                        timestamp_us: 0,
                    }),
                })),
            })
            .expect("start box select");
        engine
            .dispatch(EngineCommand {
                kind: EngineCommandKind::UpdateBoxSelect as i32,
                payload: Some(CommandPayload::UpdateBoxSelect(UpdateBoxSelectCommand {
                    current_position: Some(DrawPoint {
                        x: 48.0,
                        y: 36.0,
                        pressure: 0.0,
                        timestamp_us: 0,
                    }),
                })),
            })
            .expect("update box select");

        let plan = engine.build_frame_plan(FramePlanRequest {
            viewport: None,
            locale_tag: String::new(),
            scale_factor: 1.0,
        });
        let task = plan
            .tasks
            .iter()
            .find(|entry| entry.kind == FrameTaskKind::BoxSelection as i32)
            .expect("box selection task");
        let payload =
            serde_json::from_slice::<serde_json::Value>(&task.payload).expect("box payload");
        let bounds = payload
            .get("bounds")
            .and_then(|value| value.as_object())
            .expect("bounds payload");
        assert_eq!(
            bounds.get("minX").and_then(|value| value.as_f64()),
            Some(12.0)
        );
        assert_eq!(
            bounds.get("minY").and_then(|value| value.as_f64()),
            Some(18.0)
        );
        assert_eq!(
            bounds.get("maxX").and_then(|value| value.as_f64()),
            Some(48.0)
        );
        assert_eq!(
            bounds.get("maxY").and_then(|value| value.as_f64()),
            Some(36.0)
        );
    }

    #[test]
    fn move_edit_updates_selected_rect_deterministically() {
        let mut engine = Engine::default();
        engine
            .dispatch(EngineCommand {
                kind: EngineCommandKind::CreateElement as i32,
                payload: Some(CommandPayload::CreateElement(CreateElementCommand {
                    element_type: ElementType::Rectangle as i32,
                    element_id: "move-target".to_string(),
                    position: Some(DrawPoint {
                        x: 0.0,
                        y: 0.0,
                        pressure: 0.0,
                        timestamp_us: 0,
                    }),
                    initial_payload: Vec::new(),
                    maintain_aspect_ratio: false,
                    create_from_center: false,
                    snap_override: false,
                })),
            })
            .expect("create");
        let original = engine
            .snapshot
            .elements
            .iter()
            .find(|element| element.id == "move-target")
            .and_then(|element| element.rect.clone())
            .expect("rect");

        engine
            .dispatch(EngineCommand {
                kind: EngineCommandKind::StartEdit as i32,
                payload: Some(CommandPayload::StartEdit(engine_proto::StartEditCommand {
                    operation_id: "move".to_string(),
                    position: Some(DrawPoint {
                        x: 0.0,
                        y: 0.0,
                        pressure: 0.0,
                        timestamp_us: 0,
                    }),
                    params: Vec::new(),
                })),
            })
            .expect("start edit");
        engine
            .dispatch(EngineCommand {
                kind: EngineCommandKind::UpdateEdit as i32,
                payload: Some(CommandPayload::UpdateEdit(UpdateEditCommand {
                    current_position: Some(DrawPoint {
                        x: 12.0,
                        y: -6.0,
                        pressure: 0.0,
                        timestamp_us: 0,
                    }),
                    modifiers: Vec::new(),
                })),
            })
            .expect("update edit");
        engine
            .dispatch(EngineCommand {
                kind: EngineCommandKind::FinishEdit as i32,
                payload: None,
            })
            .expect("finish edit");

        let moved = engine
            .snapshot
            .elements
            .iter()
            .find(|element| element.id == "move-target")
            .and_then(|element| element.rect.clone())
            .expect("moved rect");
        assert_eq!(moved.min_x, original.min_x + 12.0);
        assert_eq!(moved.min_y, original.min_y - 6.0);
    }

    #[test]
    fn resize_edit_updates_selected_rect() {
        let mut engine = Engine::default();
        engine
            .dispatch(EngineCommand {
                kind: EngineCommandKind::CreateElement as i32,
                payload: Some(CommandPayload::CreateElement(CreateElementCommand {
                    element_type: ElementType::Rectangle as i32,
                    element_id: "resize-target".to_string(),
                    position: Some(DrawPoint {
                        x: 10.0,
                        y: 10.0,
                        pressure: 0.0,
                        timestamp_us: 0,
                    }),
                    initial_payload: Vec::new(),
                    maintain_aspect_ratio: false,
                    create_from_center: false,
                    snap_override: false,
                })),
            })
            .expect("create");
        let original = engine
            .snapshot
            .elements
            .iter()
            .find(|element| element.id == "resize-target")
            .and_then(|element| element.rect.clone())
            .expect("rect");

        engine
            .dispatch(EngineCommand {
                kind: EngineCommandKind::StartEdit as i32,
                payload: Some(CommandPayload::StartEdit(engine_proto::StartEditCommand {
                    operation_id: "resize".to_string(),
                    position: Some(DrawPoint {
                        x: original.max_x,
                        y: original.max_y,
                        pressure: 0.0,
                        timestamp_us: 0,
                    }),
                    params: br#"{"type":"resize","resizeMode":"bottomRight"}"#.to_vec(),
                })),
            })
            .expect("start resize");
        engine
            .dispatch(EngineCommand {
                kind: EngineCommandKind::UpdateEdit as i32,
                payload: Some(CommandPayload::UpdateEdit(UpdateEditCommand {
                    current_position: Some(DrawPoint {
                        x: original.max_x + 25.0,
                        y: original.max_y + 10.0,
                        pressure: 0.0,
                        timestamp_us: 0,
                    }),
                    modifiers: Vec::new(),
                })),
            })
            .expect("update resize");

        let resized = engine
            .snapshot
            .elements
            .iter()
            .find(|element| element.id == "resize-target")
            .and_then(|element| element.rect.clone())
            .expect("resized rect");
        assert_eq!(resized.min_x, original.min_x);
        assert_eq!(resized.min_y, original.min_y);
        assert_eq!(resized.max_x, original.max_x + 25.0);
        assert_eq!(resized.max_y, original.max_y + 10.0);
    }

    #[test]
    fn resize_edit_honors_maintain_aspect_ratio_for_corner_handle() {
        let mut engine = Engine::default();
        engine
            .dispatch(EngineCommand {
                kind: EngineCommandKind::CreateElement as i32,
                payload: Some(CommandPayload::CreateElement(CreateElementCommand {
                    element_type: ElementType::Rectangle as i32,
                    element_id: "resize-ratio-corner".to_string(),
                    position: Some(DrawPoint {
                        x: 8.0,
                        y: 12.0,
                        pressure: 0.0,
                        timestamp_us: 0,
                    }),
                    initial_payload: Vec::new(),
                    maintain_aspect_ratio: false,
                    create_from_center: false,
                    snap_override: false,
                })),
            })
            .expect("create");
        let original = engine
            .snapshot
            .elements
            .iter()
            .find(|element| element.id == "resize-ratio-corner")
            .and_then(|element| element.rect.clone())
            .expect("rect");
        let original_ratio = (original.max_x - original.min_x) / (original.max_y - original.min_y);

        engine
            .dispatch(EngineCommand {
                kind: EngineCommandKind::StartEdit as i32,
                payload: Some(CommandPayload::StartEdit(engine_proto::StartEditCommand {
                    operation_id: "resize".to_string(),
                    position: Some(DrawPoint {
                        x: original.max_x,
                        y: original.max_y,
                        pressure: 0.0,
                        timestamp_us: 0,
                    }),
                    params: br#"{"type":"resize","resizeMode":"bottomRight"}"#.to_vec(),
                })),
            })
            .expect("start resize");
        engine
            .dispatch(EngineCommand {
                kind: EngineCommandKind::UpdateEdit as i32,
                payload: Some(CommandPayload::UpdateEdit(UpdateEditCommand {
                    current_position: Some(DrawPoint {
                        x: original.max_x + 40.0,
                        y: original.max_y + 5.0,
                        pressure: 0.0,
                        timestamp_us: 0,
                    }),
                    modifiers: br#"{"maintainAspectRatio":true}"#.to_vec(),
                })),
            })
            .expect("update resize");

        let resized = engine
            .snapshot
            .elements
            .iter()
            .find(|element| element.id == "resize-ratio-corner")
            .and_then(|element| element.rect.clone())
            .expect("resized rect");
        let width = resized.max_x - resized.min_x;
        let height = resized.max_y - resized.min_y;
        assert!(((width / height) - original_ratio).abs() < 1e-9);
        assert_eq!(resized.min_x, original.min_x);
        assert_eq!(resized.min_y, original.min_y);
    }

    #[test]
    fn resize_edit_honors_maintain_aspect_ratio_for_side_handle() {
        let mut engine = Engine::default();
        engine
            .dispatch(EngineCommand {
                kind: EngineCommandKind::CreateElement as i32,
                payload: Some(CommandPayload::CreateElement(CreateElementCommand {
                    element_type: ElementType::Rectangle as i32,
                    element_id: "resize-ratio-side".to_string(),
                    position: Some(DrawPoint {
                        x: 20.0,
                        y: 20.0,
                        pressure: 0.0,
                        timestamp_us: 0,
                    }),
                    initial_payload: Vec::new(),
                    maintain_aspect_ratio: false,
                    create_from_center: false,
                    snap_override: false,
                })),
            })
            .expect("create");
        let original = engine
            .snapshot
            .elements
            .iter()
            .find(|element| element.id == "resize-ratio-side")
            .and_then(|element| element.rect.clone())
            .expect("rect");
        let original_ratio = (original.max_x - original.min_x) / (original.max_y - original.min_y);
        let original_center_y = (original.min_y + original.max_y) / 2.0;

        engine
            .dispatch(EngineCommand {
                kind: EngineCommandKind::StartEdit as i32,
                payload: Some(CommandPayload::StartEdit(engine_proto::StartEditCommand {
                    operation_id: "resize".to_string(),
                    position: Some(DrawPoint {
                        x: original.max_x,
                        y: original_center_y,
                        pressure: 0.0,
                        timestamp_us: 0,
                    }),
                    params: br#"{"type":"resize","resizeMode":"right"}"#.to_vec(),
                })),
            })
            .expect("start resize");
        engine
            .dispatch(EngineCommand {
                kind: EngineCommandKind::UpdateEdit as i32,
                payload: Some(CommandPayload::UpdateEdit(UpdateEditCommand {
                    current_position: Some(DrawPoint {
                        x: original.max_x + 36.0,
                        y: original_center_y,
                        pressure: 0.0,
                        timestamp_us: 0,
                    }),
                    modifiers: br#"{"maintainAspectRatio":true}"#.to_vec(),
                })),
            })
            .expect("update resize");

        let resized = engine
            .snapshot
            .elements
            .iter()
            .find(|element| element.id == "resize-ratio-side")
            .and_then(|element| element.rect.clone())
            .expect("resized rect");
        let width = resized.max_x - resized.min_x;
        let height = resized.max_y - resized.min_y;
        let center_y = (resized.min_y + resized.max_y) / 2.0;
        assert!(((width / height) - original_ratio).abs() < 1e-9);
        assert!((center_y - original_center_y).abs() < 1e-9);
    }

    #[test]
    fn rotate_edit_updates_rotation_and_center() {
        let mut engine = Engine::default();
        engine
            .dispatch(EngineCommand {
                kind: EngineCommandKind::CreateElement as i32,
                payload: Some(CommandPayload::CreateElement(CreateElementCommand {
                    element_type: ElementType::Rectangle as i32,
                    element_id: "rotate-target".to_string(),
                    position: Some(DrawPoint {
                        x: 0.0,
                        y: 0.0,
                        pressure: 0.0,
                        timestamp_us: 0,
                    }),
                    initial_payload: Vec::new(),
                    maintain_aspect_ratio: false,
                    create_from_center: false,
                    snap_override: false,
                })),
            })
            .expect("create");
        let original = engine
            .snapshot
            .elements
            .iter()
            .find(|element| element.id == "rotate-target")
            .expect("element")
            .clone();
        let original_rect = original.rect.clone().expect("rect");
        let center = DrawPoint {
            x: (original_rect.min_x + original_rect.max_x) / 2.0,
            y: (original_rect.min_y + original_rect.max_y) / 2.0,
            pressure: 0.0,
            timestamp_us: 0,
        };

        engine
            .dispatch(EngineCommand {
                kind: EngineCommandKind::StartEdit as i32,
                payload: Some(CommandPayload::StartEdit(engine_proto::StartEditCommand {
                    operation_id: "rotate".to_string(),
                    position: Some(DrawPoint {
                        x: center.x + 100.0,
                        y: center.y,
                        pressure: 0.0,
                        timestamp_us: 0,
                    }),
                    params: br#"{"type":"rotate","rotationSnapAngle":0.0}"#.to_vec(),
                })),
            })
            .expect("start rotate");
        engine
            .dispatch(EngineCommand {
                kind: EngineCommandKind::UpdateEdit as i32,
                payload: Some(CommandPayload::UpdateEdit(UpdateEditCommand {
                    current_position: Some(DrawPoint {
                        x: center.x,
                        y: center.y + 100.0,
                        pressure: 0.0,
                        timestamp_us: 0,
                    }),
                    modifiers: Vec::new(),
                })),
            })
            .expect("update rotate");

        let rotated = engine
            .snapshot
            .elements
            .iter()
            .find(|element| element.id == "rotate-target")
            .expect("rotated element");
        assert!(rotated.rotation > original.rotation);
        let rotated_rect = rotated.rect.clone().expect("rotated rect");
        let rotated_center = DrawPoint {
            x: (rotated_rect.min_x + rotated_rect.max_x) / 2.0,
            y: (rotated_rect.min_y + rotated_rect.max_y) / 2.0,
            pressure: 0.0,
            timestamp_us: 0,
        };
        assert!((rotated_center.x - center.x).abs() < 1e-9);
        assert!((rotated_center.y - center.y).abs() < 1e-9);
    }

    #[test]
    fn add_arrow_point_normalizes_payload_and_updates_rect() {
        let mut engine = Engine::default();
        engine
            .dispatch(EngineCommand {
                kind: EngineCommandKind::CreateElement as i32,
                payload: Some(CommandPayload::CreateElement(CreateElementCommand {
                    element_type: ElementType::Arrow as i32,
                    element_id: "add-point-arrow".to_string(),
                    position: Some(DrawPoint {
                        x: 20.0,
                        y: 30.0,
                        pressure: 0.0,
                        timestamp_us: 0,
                    }),
                    initial_payload: Vec::new(),
                    maintain_aspect_ratio: false,
                    create_from_center: false,
                    snap_override: false,
                })),
            })
            .expect("create arrow");

        engine
            .dispatch(EngineCommand {
                kind: EngineCommandKind::AddArrowPoint as i32,
                payload: Some(CommandPayload::AddArrowPoint(AddArrowPointCommand {
                    position: Some(DrawPoint {
                        x: 220.0,
                        y: 140.0,
                        pressure: 0.0,
                        timestamp_us: 0,
                    }),
                    snap_override: false,
                })),
            })
            .expect("add point");

        let element = engine
            .snapshot
            .elements
            .iter()
            .find(|entry| entry.id == "add-point-arrow")
            .expect("arrow element");
        let rect = element.rect.as_ref().expect("arrow rect");
        assert_eq!(rect.max_x, 220.0);
        assert_eq!(rect.max_y, 140.0);

        let payload = decode_json_map(&element.payload).expect("arrow payload");
        let world_points = decode_arrow_points_world(&payload, rect);
        assert_eq!(world_points.len(), 3);
        assert!((world_points[2].x - 220.0).abs() < 1e-9);
        assert!((world_points[2].y - 140.0).abs() < 1e-9);
    }

    #[test]
    fn arrow_point_edit_turning_updates_endpoint_and_clears_binding() {
        let mut engine = Engine::default();
        engine
            .dispatch(EngineCommand {
                kind: EngineCommandKind::CreateElement as i32,
                payload: Some(CommandPayload::CreateElement(CreateElementCommand {
                    element_type: ElementType::Arrow as i32,
                    element_id: "arrow-point-turning".to_string(),
                    position: Some(DrawPoint {
                        x: 40.0,
                        y: 50.0,
                        pressure: 0.0,
                        timestamp_us: 0,
                    }),
                    initial_payload: br#"{"typeId":"arrow","points":[{"x":0.0,"y":0.0},{"x":1.0,"y":1.0},{"x":1.0,"y":0.0}],"startBinding":{"elementId":"start-target"},"endBinding":{"elementId":"end-target"}}"#.to_vec(),
                    maintain_aspect_ratio: false,
                    create_from_center: false,
                    snap_override: false,
                })),
            })
            .expect("create arrow");

        engine
            .dispatch(EngineCommand {
                kind: EngineCommandKind::StartEdit as i32,
                payload: Some(CommandPayload::StartEdit(engine_proto::StartEditCommand {
                    operation_id: "arrowPoint".to_string(),
                    position: Some(DrawPoint {
                        x: 40.0,
                        y: 50.0,
                        pressure: 0.0,
                        timestamp_us: 0,
                    }),
                    params: br#"{"type":"arrow_point","elementId":"arrow-point-turning","pointKind":"turning","pointIndex":0}"#.to_vec(),
                })),
            })
            .expect("start edit");

        engine
            .dispatch(EngineCommand {
                kind: EngineCommandKind::UpdateEdit as i32,
                payload: Some(CommandPayload::UpdateEdit(UpdateEditCommand {
                    current_position: Some(DrawPoint {
                        x: 10.0,
                        y: 8.0,
                        pressure: 0.0,
                        timestamp_us: 0,
                    }),
                    modifiers: Vec::new(),
                })),
            })
            .expect("update edit");

        let element = engine
            .snapshot
            .elements
            .iter()
            .find(|entry| entry.id == "arrow-point-turning")
            .expect("arrow element");
        let rect = element.rect.as_ref().expect("arrow rect");
        let payload = decode_json_map(&element.payload).expect("arrow payload");
        assert!(payload.get("startBinding").is_none());
        assert!(payload.get("endBinding").is_some());
        let world_points = decode_arrow_points_world(&payload, rect);
        assert_eq!(world_points.len(), 3);
        assert!((world_points[0].x - 10.0).abs() < 1e-9);
        assert!((world_points[0].y - 8.0).abs() < 1e-9);
    }

    #[test]
    fn arrow_point_edit_addable_inserts_new_point() {
        let mut engine = Engine::default();
        engine
            .dispatch(EngineCommand {
                kind: EngineCommandKind::CreateElement as i32,
                payload: Some(CommandPayload::CreateElement(CreateElementCommand {
                    element_type: ElementType::Arrow as i32,
                    element_id: "arrow-point-addable".to_string(),
                    position: Some(DrawPoint {
                        x: 0.0,
                        y: 0.0,
                        pressure: 0.0,
                        timestamp_us: 0,
                    }),
                    initial_payload:
                        br#"{"typeId":"arrow","points":[{"x":0.0,"y":0.0},{"x":1.0,"y":1.0}]}"#
                            .to_vec(),
                    maintain_aspect_ratio: false,
                    create_from_center: false,
                    snap_override: false,
                })),
            })
            .expect("create arrow");

        engine
            .dispatch(EngineCommand {
                kind: EngineCommandKind::StartEdit as i32,
                payload: Some(CommandPayload::StartEdit(engine_proto::StartEditCommand {
                    operation_id: "arrowPoint".to_string(),
                    position: Some(DrawPoint {
                        x: 60.0,
                        y: 60.0,
                        pressure: 0.0,
                        timestamp_us: 0,
                    }),
                    params: br#"{"type":"arrow_point","elementId":"arrow-point-addable","pointKind":"addable","pointIndex":0}"#.to_vec(),
                })),
            })
            .expect("start edit");

        engine
            .dispatch(EngineCommand {
                kind: EngineCommandKind::UpdateEdit as i32,
                payload: Some(CommandPayload::UpdateEdit(UpdateEditCommand {
                    current_position: Some(DrawPoint {
                        x: 80.0,
                        y: 30.0,
                        pressure: 0.0,
                        timestamp_us: 0,
                    }),
                    modifiers: Vec::new(),
                })),
            })
            .expect("update edit");

        let element = engine
            .snapshot
            .elements
            .iter()
            .find(|entry| entry.id == "arrow-point-addable")
            .expect("arrow element");
        let rect = element.rect.as_ref().expect("arrow rect");
        let payload = decode_json_map(&element.payload).expect("arrow payload");
        let world_points = decode_arrow_points_world(&payload, rect);
        assert_eq!(world_points.len(), 3);
        assert!((world_points[1].x - 80.0).abs() < 1e-9);
        assert!((world_points[1].y - 30.0).abs() < 1e-9);
    }

    #[test]
    fn arrow_point_double_click_delete_applies_on_finish() {
        let mut engine = Engine::default();
        engine
            .dispatch(EngineCommand {
                kind: EngineCommandKind::CreateElement as i32,
                payload: Some(CommandPayload::CreateElement(CreateElementCommand {
                    element_type: ElementType::Arrow as i32,
                    element_id: "arrow-point-delete".to_string(),
                    position: Some(DrawPoint {
                        x: 0.0,
                        y: 0.0,
                        pressure: 0.0,
                        timestamp_us: 0,
                    }),
                    initial_payload: br#"{"typeId":"arrow","points":[{"x":0.0,"y":0.0},{"x":0.5,"y":0.5},{"x":1.0,"y":1.0}]}"#.to_vec(),
                    maintain_aspect_ratio: false,
                    create_from_center: false,
                    snap_override: false,
                })),
            })
            .expect("create arrow");

        engine
            .dispatch(EngineCommand {
                kind: EngineCommandKind::StartEdit as i32,
                payload: Some(CommandPayload::StartEdit(engine_proto::StartEditCommand {
                    operation_id: "arrowPoint".to_string(),
                    position: Some(DrawPoint {
                        x: 70.0,
                        y: 70.0,
                        pressure: 0.0,
                        timestamp_us: 0,
                    }),
                    params: br#"{"type":"arrow_point","elementId":"arrow-point-delete","pointKind":"turning","pointIndex":1,"isDoubleClick":true}"#.to_vec(),
                })),
            })
            .expect("start edit");
        engine
            .dispatch(EngineCommand {
                kind: EngineCommandKind::FinishEdit as i32,
                payload: None,
            })
            .expect("finish edit");

        let element = engine
            .snapshot
            .elements
            .iter()
            .find(|entry| entry.id == "arrow-point-delete")
            .expect("arrow element");
        let rect = element.rect.as_ref().expect("arrow rect");
        let payload = decode_json_map(&element.payload).expect("arrow payload");
        let world_points = decode_arrow_points_world(&payload, rect);
        assert_eq!(world_points.len(), 2);
    }

    #[test]
    fn cancel_edit_restores_arrow_point_payload_and_rect() {
        let mut engine = Engine::default();
        engine
            .dispatch(EngineCommand {
                kind: EngineCommandKind::CreateElement as i32,
                payload: Some(CommandPayload::CreateElement(CreateElementCommand {
                    element_type: ElementType::Arrow as i32,
                    element_id: "arrow-point-cancel".to_string(),
                    position: Some(DrawPoint {
                        x: 12.0,
                        y: 18.0,
                        pressure: 0.0,
                        timestamp_us: 0,
                    }),
                    initial_payload: br#"{"typeId":"arrow","points":[{"x":0.0,"y":0.0},{"x":1.0,"y":1.0},{"x":1.0,"y":0.0}]}"#.to_vec(),
                    maintain_aspect_ratio: false,
                    create_from_center: false,
                    snap_override: false,
                })),
            })
            .expect("create arrow");

        let original = engine
            .snapshot
            .elements
            .iter()
            .find(|entry| entry.id == "arrow-point-cancel")
            .expect("arrow element")
            .clone();

        engine
            .dispatch(EngineCommand {
                kind: EngineCommandKind::StartEdit as i32,
                payload: Some(CommandPayload::StartEdit(engine_proto::StartEditCommand {
                    operation_id: "arrowPoint".to_string(),
                    position: Some(DrawPoint {
                        x: 12.0,
                        y: 18.0,
                        pressure: 0.0,
                        timestamp_us: 0,
                    }),
                    params: br#"{"type":"arrow_point","elementId":"arrow-point-cancel","pointKind":"turning","pointIndex":0}"#.to_vec(),
                })),
            })
            .expect("start edit");
        engine
            .dispatch(EngineCommand {
                kind: EngineCommandKind::UpdateEdit as i32,
                payload: Some(CommandPayload::UpdateEdit(UpdateEditCommand {
                    current_position: Some(DrawPoint {
                        x: -25.0,
                        y: -30.0,
                        pressure: 0.0,
                        timestamp_us: 0,
                    }),
                    modifiers: Vec::new(),
                })),
            })
            .expect("update edit");
        engine
            .dispatch(EngineCommand {
                kind: EngineCommandKind::CancelEdit as i32,
                payload: None,
            })
            .expect("cancel edit");

        let restored = engine
            .snapshot
            .elements
            .iter()
            .find(|entry| entry.id == "arrow-point-cancel")
            .expect("restored arrow");
        assert_eq!(restored.rect, original.rect);
        assert_eq!(restored.payload, original.payload);
    }

    #[test]
    fn runtime_config_payload_updates_snap_config_without_touching_snapshot_versions() {
        let mut engine = Engine::default();
        let initial_document_version = engine.snapshot.document_version;
        let initial_selection_version = engine.snapshot.selection_version;

        let changed = engine.apply_runtime_config_payload(
            br#"{"grid":{"enabled":true,"size":10.0},"snap":{"enabled":false,"distance":6.5}}"#,
        );

        assert!(changed);
        assert!(engine.runtime_snap_config.grid_enabled);
        assert!(!engine.runtime_snap_config.object_enabled);
        assert!((engine.runtime_snap_config.grid_size - 10.0).abs() < 1e-9);
        assert!((engine.runtime_snap_config.object_distance - 6.5).abs() < 1e-9);
        assert_eq!(engine.snapshot.document_version, initial_document_version);
        assert_eq!(engine.snapshot.selection_version, initial_selection_version);
    }

    #[test]
    fn runtime_config_payload_bootstrap_snapshot_replaces_state() {
        let mut engine = Engine::default();
        engine
            .dispatch(create_command("legacy", ElementType::Rectangle))
            .expect("create legacy element");
        assert!(!engine.snapshot.elements.is_empty());

        let bootstrap_snapshot = EngineSnapshot {
            schema_version: 999,
            document_version: 42,
            selection_version: 9,
            interaction_mode: InteractionMode::Editing as i32,
            camera: Some(CameraState {
                position: Some(DrawPoint {
                    x: 320.0,
                    y: -140.0,
                    pressure: 0.0,
                    timestamp_us: 0,
                }),
                zoom: 2.5,
            }),
            elements: vec![Element {
                id: "bootstrap-rect".to_string(),
                element_type: ElementType::Rectangle as i32,
                rect: Some(DrawRect {
                    min_x: 100.0,
                    min_y: 120.0,
                    max_x: 260.0,
                    max_y: 300.0,
                }),
                rotation: 0.25,
                opacity: 0.66,
                z_index: 10,
                payload: br#"{"typeId":"rectangle","color":4278255360}"#.to_vec(),
            }],
            selected_ids: vec!["bootstrap-rect".to_string(), "missing".to_string()],
            history_undo_len: 7,
            history_redo_len: 3,
            global_elements_payload: br#"{"watermark":{"text":"bootstrapped","opacity":0.2}}"#
                .to_vec(),
        };
        let encoded_snapshot = encode_message(&bootstrap_snapshot);
        let payload = serde_json::json!({
            RUNTIME_BOOTSTRAP_SNAPSHOT_KEY:
                base64::engine::general_purpose::STANDARD.encode(encoded_snapshot),
        })
        .to_string();

        let changed = engine.apply_runtime_config_payload(payload.as_bytes());
        assert!(changed);

        assert_eq!(engine.snapshot.schema_version, engine.config.schema_version);
        assert_eq!(engine.snapshot.document_version, 42);
        assert_eq!(engine.snapshot.selection_version, 9);
        assert_eq!(engine.snapshot.elements.len(), 1);
        assert_eq!(engine.snapshot.elements[0].id, "bootstrap-rect");
        let camera = engine.snapshot.camera.as_ref().expect("camera");
        assert!((camera.zoom - 2.5).abs() < 1e-9);
        assert_eq!(camera.position.as_ref().expect("camera position").x, 320.0);
        assert_eq!(
            engine.snapshot.interaction_mode,
            InteractionMode::Idle as i32
        );
        assert_eq!(
            engine.snapshot.selected_ids,
            vec!["bootstrap-rect".to_string()]
        );
        assert!(!engine.snapshot.global_elements_payload.is_empty());
        assert_eq!(engine.snapshot.history_undo_len, 0);
        assert_eq!(engine.snapshot.history_redo_len, 0);
        assert_eq!(engine.undo_stack.len(), 0);
        assert_eq!(engine.redo_stack.len(), 0);
        assert_eq!(engine.next_element_sequence, 1);
    }

    #[test]
    fn runtime_config_payload_applies_style_defaults_to_create_element() {
        let mut engine = Engine::default();
        assert!(engine.apply_runtime_config_payload(
            br#"{"styles":{"rectangle":{"opacity":0.35,"color":4289379276,"fillColor":255,"strokeWidth":5.0,"strokeStyle":"dashed","fillStyle":"line","cornerRadius":12.0}}}"#,
        ));

        engine
            .dispatch(EngineCommand {
                kind: EngineCommandKind::CreateElement as i32,
                payload: Some(CommandPayload::CreateElement(CreateElementCommand {
                    element_type: ElementType::Rectangle as i32,
                    element_id: "style-create-rect".to_string(),
                    position: Some(DrawPoint {
                        x: 10.0,
                        y: 20.0,
                        pressure: 0.0,
                        timestamp_us: 0,
                    }),
                    initial_payload: Vec::new(),
                    maintain_aspect_ratio: false,
                    create_from_center: false,
                    snap_override: false,
                })),
            })
            .expect("create rectangle");

        let element = engine
            .snapshot
            .elements
            .iter()
            .find(|entry| entry.id == "style-create-rect")
            .expect("created rectangle");
        let payload = decode_json_map(&element.payload).expect("rectangle payload");
        assert!((element.opacity - 0.35).abs() < 1e-9);
        assert_eq!(
            payload.get("color").and_then(JsonValue::as_u64),
            Some(4289379276)
        );
        assert_eq!(
            payload.get("fillColor").and_then(JsonValue::as_u64),
            Some(255)
        );
        assert_eq!(
            payload.get("strokeWidth").and_then(JsonValue::as_f64),
            Some(5.0)
        );
        assert_eq!(
            payload.get("strokeStyle").and_then(JsonValue::as_str),
            Some("dashed"),
        );
        assert_eq!(
            payload.get("fillStyle").and_then(JsonValue::as_str),
            Some("line"),
        );
        assert_eq!(
            payload.get("cornerRadius").and_then(JsonValue::as_f64),
            Some(12.0),
        );
    }

    #[test]
    fn runtime_config_payload_applies_text_style_defaults_to_new_text_edit() {
        let mut engine = Engine::default();
        assert!(engine.apply_runtime_config_payload(
            br#"{"styles":{"text":{"opacity":0.4,"fontSize":60.0,"fontFamily":"Fira Code","textAlign":"center","verticalAlign":"bottom","color":4279312947}}}"#,
        ));

        engine
            .dispatch(EngineCommand {
                kind: EngineCommandKind::StartTextEdit as i32,
                payload: Some(CommandPayload::StartTextEdit(StartTextEditCommand {
                    element_id: String::new(),
                    position: Some(DrawPoint {
                        x: 40.0,
                        y: 50.0,
                        pressure: 0.0,
                        timestamp_us: 0,
                    }),
                })),
            })
            .expect("start text edit");

        let element_id = engine
            .snapshot
            .selected_ids
            .first()
            .cloned()
            .expect("selected text id");
        let element = engine
            .snapshot
            .elements
            .iter()
            .find(|entry| entry.id == element_id)
            .expect("new text element");
        let payload = decode_json_map(&element.payload).expect("text payload");
        let rect = element.rect.as_ref().expect("text rect");

        assert!((element.opacity - 0.4).abs() < 1e-9);
        assert_eq!(
            payload.get("fontSize").and_then(JsonValue::as_f64),
            Some(60.0)
        );
        assert_eq!(
            payload.get("fontFamily").and_then(JsonValue::as_str),
            Some("Fira Code"),
        );
        assert_eq!(
            payload.get("horizontalAlign").and_then(JsonValue::as_str),
            Some("center"),
        );
        assert_eq!(
            payload.get("verticalAlign").and_then(JsonValue::as_str),
            Some("bottom"),
        );
        assert_eq!(
            payload.get("color").and_then(JsonValue::as_u64),
            Some(4279312947)
        );
        let width = rect.max_x - rect.min_x;
        let height = rect.max_y - rect.min_y;
        assert!(width >= TEXT_MIN_WIDTH);
        assert!(width < 80.0);
        assert!(height >= 60.0);
    }

    #[test]
    fn create_serial_number_text_elements_uses_runtime_text_style_defaults() {
        let mut engine = Engine::default();
        assert!(engine.apply_runtime_config_payload(
            br#"{"styles":{"text":{"opacity":0.25,"fontSize":30.0,"fontFamily":"Fira Code","textAlign":"right","verticalAlign":"top","color":4278255873}}}"#,
        ));

        engine
            .dispatch(EngineCommand {
                kind: EngineCommandKind::CreateElement as i32,
                payload: Some(CommandPayload::CreateElement(CreateElementCommand {
                    element_type: ElementType::SerialNumber as i32,
                    element_id: "serial-styled".to_string(),
                    position: Some(DrawPoint {
                        x: 20.0,
                        y: 30.0,
                        pressure: 0.0,
                        timestamp_us: 0,
                    }),
                    initial_payload: Vec::new(),
                    maintain_aspect_ratio: false,
                    create_from_center: false,
                    snap_override: false,
                })),
            })
            .expect("create serial number");

        engine
            .dispatch(EngineCommand {
                kind: EngineCommandKind::CreateSerialNumberTextElements as i32,
                payload: Some(CommandPayload::CreateSerialNumberTextElements(
                    CreateSerialNumberTextElementsCommand {
                        element_ids: vec!["serial-styled".to_string()],
                    },
                )),
            })
            .expect("create serial text");

        let serial = engine
            .snapshot
            .elements
            .iter()
            .find(|entry| entry.id == "serial-styled")
            .expect("serial");
        let serial_payload = decode_json_map(&serial.payload).expect("serial payload");
        let text_id = serial_payload
            .get("textElementId")
            .and_then(JsonValue::as_str)
            .expect("bound text id");
        let text = engine
            .snapshot
            .elements
            .iter()
            .find(|entry| entry.id == text_id)
            .expect("bound text");
        let text_payload = decode_json_map(&text.payload).expect("text payload");

        assert!((text.opacity - 0.25).abs() < 1e-9);
        assert_eq!(
            text_payload.get("fontSize").and_then(JsonValue::as_f64),
            Some(30.0),
        );
        assert_eq!(
            text_payload.get("fontFamily").and_then(JsonValue::as_str),
            Some("Fira Code"),
        );
        assert_eq!(
            text_payload
                .get("horizontalAlign")
                .and_then(JsonValue::as_str),
            Some("right"),
        );
        assert_eq!(
            text_payload
                .get("verticalAlign")
                .and_then(JsonValue::as_str),
            Some("top"),
        );
        assert_eq!(
            text_payload.get("color").and_then(JsonValue::as_u64),
            Some(4278255873),
        );
    }

    #[test]
    fn create_and_update_creating_respect_grid_snap_override() {
        let mut engine = Engine::default();
        assert!(engine.apply_runtime_config_payload(br#"{"grid":{"enabled":true,"size":10.0}}"#,));

        engine
            .dispatch(EngineCommand {
                kind: EngineCommandKind::CreateElement as i32,
                payload: Some(CommandPayload::CreateElement(CreateElementCommand {
                    element_type: ElementType::Rectangle as i32,
                    element_id: "snap-create".to_string(),
                    position: Some(DrawPoint {
                        x: 13.0,
                        y: 27.0,
                        pressure: 0.0,
                        timestamp_us: 0,
                    }),
                    initial_payload: Vec::new(),
                    maintain_aspect_ratio: false,
                    create_from_center: false,
                    snap_override: false,
                })),
            })
            .expect("create");
        engine
            .dispatch(EngineCommand {
                kind: EngineCommandKind::UpdateCreatingElement as i32,
                payload: Some(CommandPayload::UpdateCreatingElement(
                    UpdateCreatingElementCommand {
                        positions: vec![DrawPoint {
                            x: 46.0,
                            y: 44.0,
                            pressure: 0.0,
                            timestamp_us: 0,
                        }],
                        maintain_aspect_ratio: false,
                        create_from_center: false,
                        snap_override: false,
                    },
                )),
            })
            .expect("update");
        let snapped = engine
            .snapshot
            .elements
            .iter()
            .find(|entry| entry.id == "snap-create")
            .and_then(|entry| entry.rect.clone())
            .expect("snapped rect");
        assert_eq!(snapped.min_x, 10.0);
        assert_eq!(snapped.min_y, 30.0);
        assert_eq!(snapped.max_x, 50.0);
        assert_eq!(snapped.max_y, 40.0);

        engine
            .dispatch(EngineCommand {
                kind: EngineCommandKind::CancelCreateElement as i32,
                payload: None,
            })
            .expect("cancel");
        engine
            .dispatch(EngineCommand {
                kind: EngineCommandKind::CreateElement as i32,
                payload: Some(CommandPayload::CreateElement(CreateElementCommand {
                    element_type: ElementType::Rectangle as i32,
                    element_id: "no-snap-create".to_string(),
                    position: Some(DrawPoint {
                        x: 13.0,
                        y: 27.0,
                        pressure: 0.0,
                        timestamp_us: 0,
                    }),
                    initial_payload: Vec::new(),
                    maintain_aspect_ratio: false,
                    create_from_center: false,
                    snap_override: true,
                })),
            })
            .expect("create no snap");
        let unsnapped = engine
            .snapshot
            .elements
            .iter()
            .find(|entry| entry.id == "no-snap-create")
            .and_then(|entry| entry.rect.clone())
            .expect("unsnapped rect");
        assert_eq!(unsnapped.min_x, 13.0);
        assert_eq!(unsnapped.min_y, 27.0);
    }

    #[test]
    fn move_edit_applies_grid_snap_unless_snap_override_is_enabled() {
        let mut engine = Engine::default();
        assert!(engine.apply_runtime_config_payload(br#"{"grid":{"enabled":true,"size":10.0}}"#,));

        engine
            .dispatch(EngineCommand {
                kind: EngineCommandKind::CreateElement as i32,
                payload: Some(CommandPayload::CreateElement(CreateElementCommand {
                    element_type: ElementType::Rectangle as i32,
                    element_id: "snap-move".to_string(),
                    position: Some(DrawPoint {
                        x: 0.0,
                        y: 0.0,
                        pressure: 0.0,
                        timestamp_us: 0,
                    }),
                    initial_payload: Vec::new(),
                    maintain_aspect_ratio: false,
                    create_from_center: false,
                    snap_override: true,
                })),
            })
            .expect("create");
        engine
            .dispatch(EngineCommand {
                kind: EngineCommandKind::FinishCreateElement as i32,
                payload: None,
            })
            .expect("finish create");

        engine
            .dispatch(EngineCommand {
                kind: EngineCommandKind::StartEdit as i32,
                payload: Some(CommandPayload::StartEdit(engine_proto::StartEditCommand {
                    operation_id: "move".to_string(),
                    position: Some(DrawPoint {
                        x: 0.0,
                        y: 0.0,
                        pressure: 0.0,
                        timestamp_us: 0,
                    }),
                    params: br#"{"type":"move"}"#.to_vec(),
                })),
            })
            .expect("start move");
        engine
            .dispatch(EngineCommand {
                kind: EngineCommandKind::UpdateEdit as i32,
                payload: Some(CommandPayload::UpdateEdit(UpdateEditCommand {
                    current_position: Some(DrawPoint {
                        x: 13.0,
                        y: 27.0,
                        pressure: 0.0,
                        timestamp_us: 0,
                    }),
                    modifiers: br#"{"snapOverride":false}"#.to_vec(),
                })),
            })
            .expect("move snapped");
        let snapped = engine
            .snapshot
            .elements
            .iter()
            .find(|entry| entry.id == "snap-move")
            .and_then(|entry| entry.rect.clone())
            .expect("snapped rect");
        assert_eq!(snapped.min_x, 10.0);
        assert_eq!(snapped.min_y, 30.0);

        engine
            .dispatch(EngineCommand {
                kind: EngineCommandKind::CancelEdit as i32,
                payload: None,
            })
            .expect("cancel edit");

        engine
            .dispatch(EngineCommand {
                kind: EngineCommandKind::StartEdit as i32,
                payload: Some(CommandPayload::StartEdit(engine_proto::StartEditCommand {
                    operation_id: "move".to_string(),
                    position: Some(DrawPoint {
                        x: 0.0,
                        y: 0.0,
                        pressure: 0.0,
                        timestamp_us: 0,
                    }),
                    params: br#"{"type":"move"}"#.to_vec(),
                })),
            })
            .expect("start move no snap");
        engine
            .dispatch(EngineCommand {
                kind: EngineCommandKind::UpdateEdit as i32,
                payload: Some(CommandPayload::UpdateEdit(UpdateEditCommand {
                    current_position: Some(DrawPoint {
                        x: 13.0,
                        y: 27.0,
                        pressure: 0.0,
                        timestamp_us: 0,
                    }),
                    modifiers: br#"{"snapOverride":true}"#.to_vec(),
                })),
            })
            .expect("move no snap");
        let unsnapped = engine
            .snapshot
            .elements
            .iter()
            .find(|entry| entry.id == "snap-move")
            .and_then(|entry| entry.rect.clone())
            .expect("unsnapped rect");
        assert_eq!(unsnapped.min_x, 13.0);
        assert_eq!(unsnapped.min_y, 27.0);
    }

    #[test]
    fn create_and_update_creating_apply_object_snap_when_enabled() {
        let mut engine = Engine::default();

        engine
            .dispatch(EngineCommand {
                kind: EngineCommandKind::CreateElement as i32,
                payload: Some(CommandPayload::CreateElement(CreateElementCommand {
                    element_type: ElementType::Rectangle as i32,
                    element_id: "snap-reference".to_string(),
                    position: Some(DrawPoint {
                        x: 50.0,
                        y: 50.0,
                        pressure: 0.0,
                        timestamp_us: 0,
                    }),
                    initial_payload: Vec::new(),
                    maintain_aspect_ratio: false,
                    create_from_center: false,
                    snap_override: true,
                })),
            })
            .expect("create reference");
        engine
            .dispatch(EngineCommand {
                kind: EngineCommandKind::FinishCreateElement as i32,
                payload: None,
            })
            .expect("finish reference");

        assert!(engine.apply_runtime_config_payload(
            br#"{"grid":{"enabled":false},"snap":{"enabled":true,"distance":8.0}}"#,
        ));

        engine
            .dispatch(EngineCommand {
                kind: EngineCommandKind::CreateElement as i32,
                payload: Some(CommandPayload::CreateElement(CreateElementCommand {
                    element_type: ElementType::Rectangle as i32,
                    element_id: "snap-target".to_string(),
                    position: Some(DrawPoint {
                        x: 44.0,
                        y: 47.0,
                        pressure: 0.0,
                        timestamp_us: 0,
                    }),
                    initial_payload: Vec::new(),
                    maintain_aspect_ratio: false,
                    create_from_center: false,
                    snap_override: false,
                })),
            })
            .expect("create target");

        engine
            .dispatch(EngineCommand {
                kind: EngineCommandKind::UpdateCreatingElement as i32,
                payload: Some(CommandPayload::UpdateCreatingElement(
                    UpdateCreatingElementCommand {
                        positions: vec![DrawPoint {
                            x: 109.0,
                            y: 89.0,
                            pressure: 0.0,
                            timestamp_us: 0,
                        }],
                        maintain_aspect_ratio: false,
                        create_from_center: false,
                        snap_override: false,
                    },
                )),
            })
            .expect("update target");

        let snapped = engine
            .snapshot
            .elements
            .iter()
            .find(|entry| entry.id == "snap-target")
            .and_then(|entry| entry.rect.clone())
            .expect("snapped target rect");
        assert_eq!(snapped.min_x, 50.0);
        assert_eq!(snapped.min_y, 50.0);
        assert_eq!(snapped.max_x, 110.0);
        assert_eq!(snapped.max_y, 90.0);
    }

    #[test]
    fn move_edit_applies_object_snap_when_enabled() {
        let mut engine = Engine::default();

        engine
            .dispatch(EngineCommand {
                kind: EngineCommandKind::CreateElement as i32,
                payload: Some(CommandPayload::CreateElement(CreateElementCommand {
                    element_type: ElementType::Rectangle as i32,
                    element_id: "snap-reference".to_string(),
                    position: Some(DrawPoint {
                        x: 100.0,
                        y: 100.0,
                        pressure: 0.0,
                        timestamp_us: 0,
                    }),
                    initial_payload: Vec::new(),
                    maintain_aspect_ratio: false,
                    create_from_center: false,
                    snap_override: true,
                })),
            })
            .expect("create reference");
        engine
            .dispatch(EngineCommand {
                kind: EngineCommandKind::FinishCreateElement as i32,
                payload: None,
            })
            .expect("finish reference");

        engine
            .dispatch(EngineCommand {
                kind: EngineCommandKind::CreateElement as i32,
                payload: Some(CommandPayload::CreateElement(CreateElementCommand {
                    element_type: ElementType::Rectangle as i32,
                    element_id: "snap-move-object".to_string(),
                    position: Some(DrawPoint {
                        x: 0.0,
                        y: 0.0,
                        pressure: 0.0,
                        timestamp_us: 0,
                    }),
                    initial_payload: Vec::new(),
                    maintain_aspect_ratio: false,
                    create_from_center: false,
                    snap_override: true,
                })),
            })
            .expect("create move object");
        engine
            .dispatch(EngineCommand {
                kind: EngineCommandKind::FinishCreateElement as i32,
                payload: None,
            })
            .expect("finish move object");

        assert!(engine.apply_runtime_config_payload(
            br#"{"grid":{"enabled":false},"snap":{"enabled":true,"distance":8.0}}"#,
        ));

        engine
            .dispatch(EngineCommand {
                kind: EngineCommandKind::StartEdit as i32,
                payload: Some(CommandPayload::StartEdit(engine_proto::StartEditCommand {
                    operation_id: "move".to_string(),
                    position: Some(DrawPoint {
                        x: 0.0,
                        y: 0.0,
                        pressure: 0.0,
                        timestamp_us: 0,
                    }),
                    params: br#"{"type":"move"}"#.to_vec(),
                })),
            })
            .expect("start move object");
        engine
            .dispatch(EngineCommand {
                kind: EngineCommandKind::UpdateEdit as i32,
                payload: Some(CommandPayload::UpdateEdit(UpdateEditCommand {
                    current_position: Some(DrawPoint {
                        x: 96.0,
                        y: 95.0,
                        pressure: 0.0,
                        timestamp_us: 0,
                    }),
                    modifiers: br#"{"snapOverride":false}"#.to_vec(),
                })),
            })
            .expect("update move object");

        let snapped = engine
            .snapshot
            .elements
            .iter()
            .find(|entry| entry.id == "snap-move-object")
            .and_then(|entry| entry.rect.clone())
            .expect("snapped move object");
        assert_eq!(snapped.min_x, 100.0);
        assert_eq!(snapped.min_y, 100.0);
    }

    #[test]
    fn resize_edit_applies_object_snap_when_enabled() {
        let mut engine = Engine::default();

        engine
            .dispatch(EngineCommand {
                kind: EngineCommandKind::CreateElement as i32,
                payload: Some(CommandPayload::CreateElement(CreateElementCommand {
                    element_type: ElementType::Rectangle as i32,
                    element_id: "snap-reference".to_string(),
                    position: Some(DrawPoint {
                        x: 200.0,
                        y: 40.0,
                        pressure: 0.0,
                        timestamp_us: 0,
                    }),
                    initial_payload: Vec::new(),
                    maintain_aspect_ratio: false,
                    create_from_center: false,
                    snap_override: true,
                })),
            })
            .expect("create reference");
        engine
            .dispatch(EngineCommand {
                kind: EngineCommandKind::FinishCreateElement as i32,
                payload: None,
            })
            .expect("finish reference");

        engine
            .dispatch(EngineCommand {
                kind: EngineCommandKind::CreateElement as i32,
                payload: Some(CommandPayload::CreateElement(CreateElementCommand {
                    element_type: ElementType::Rectangle as i32,
                    element_id: "snap-resize-object".to_string(),
                    position: Some(DrawPoint {
                        x: 0.0,
                        y: 40.0,
                        pressure: 0.0,
                        timestamp_us: 0,
                    }),
                    initial_payload: Vec::new(),
                    maintain_aspect_ratio: false,
                    create_from_center: false,
                    snap_override: true,
                })),
            })
            .expect("create resize object");
        engine
            .dispatch(EngineCommand {
                kind: EngineCommandKind::FinishCreateElement as i32,
                payload: None,
            })
            .expect("finish resize object");

        assert!(engine.apply_runtime_config_payload(
            br#"{"grid":{"enabled":false},"snap":{"enabled":true,"distance":8.0}}"#,
        ));

        engine
            .dispatch(EngineCommand {
                kind: EngineCommandKind::StartEdit as i32,
                payload: Some(CommandPayload::StartEdit(engine_proto::StartEditCommand {
                    operation_id: "resize".to_string(),
                    position: Some(DrawPoint {
                        x: 120.0,
                        y: 80.0,
                        pressure: 0.0,
                        timestamp_us: 0,
                    }),
                    params: br#"{"type":"resize","resizeMode":"right"}"#.to_vec(),
                })),
            })
            .expect("start resize object");
        engine
            .dispatch(EngineCommand {
                kind: EngineCommandKind::UpdateEdit as i32,
                payload: Some(CommandPayload::UpdateEdit(UpdateEditCommand {
                    current_position: Some(DrawPoint {
                        x: 197.0,
                        y: 80.0,
                        pressure: 0.0,
                        timestamp_us: 0,
                    }),
                    modifiers: br#"{"snapOverride":false}"#.to_vec(),
                })),
            })
            .expect("update resize object");

        let snapped = engine
            .snapshot
            .elements
            .iter()
            .find(|entry| entry.id == "snap-resize-object")
            .and_then(|entry| entry.rect.clone())
            .expect("snapped resize object");
        assert_eq!(snapped.min_x, 0.0);
        assert_eq!(snapped.max_x, 200.0);
    }

    #[test]
    fn resize_edit_from_center_skips_grid_snapping() {
        let mut engine = Engine::default();
        assert!(engine.apply_runtime_config_payload(
            br#"{"grid":{"enabled":true,"size":10.0},"snap":{"enabled":true,"distance":8.0}}"#,
        ));

        engine
            .dispatch(EngineCommand {
                kind: EngineCommandKind::CreateElement as i32,
                payload: Some(CommandPayload::CreateElement(CreateElementCommand {
                    element_type: ElementType::Rectangle as i32,
                    element_id: "center-grid-target".to_string(),
                    position: Some(DrawPoint {
                        x: 0.0,
                        y: 0.0,
                        pressure: 0.0,
                        timestamp_us: 0,
                    }),
                    initial_payload: Vec::new(),
                    maintain_aspect_ratio: false,
                    create_from_center: false,
                    snap_override: true,
                })),
            })
            .expect("create target");
        engine
            .dispatch(EngineCommand {
                kind: EngineCommandKind::FinishCreateElement as i32,
                payload: None,
            })
            .expect("finish target");
        engine
            .dispatch(EngineCommand {
                kind: EngineCommandKind::StartEdit as i32,
                payload: Some(CommandPayload::StartEdit(engine_proto::StartEditCommand {
                    operation_id: "resize".to_string(),
                    position: Some(DrawPoint {
                        x: 100.0,
                        y: 50.0,
                        pressure: 0.0,
                        timestamp_us: 0,
                    }),
                    params: br#"{"type":"resize","resizeMode":"right"}"#.to_vec(),
                })),
            })
            .expect("start resize");
        engine
            .dispatch(EngineCommand {
                kind: EngineCommandKind::UpdateEdit as i32,
                payload: Some(CommandPayload::UpdateEdit(UpdateEditCommand {
                    current_position: Some(DrawPoint {
                        x: 103.0,
                        y: 50.0,
                        pressure: 0.0,
                        timestamp_us: 0,
                    }),
                    modifiers: br#"{"fromCenter":true,"snapOverride":false}"#.to_vec(),
                })),
            })
            .expect("update resize");

        let unsnapped = engine
            .snapshot
            .elements
            .iter()
            .find(|entry| entry.id == "center-grid-target")
            .and_then(|entry| entry.rect.clone())
            .expect("center-grid rect");
        assert_eq!(unsnapped.min_x, -3.0);
        assert_eq!(unsnapped.max_x, 123.0);

        let plan = engine.build_frame_plan(FramePlanRequest {
            viewport: None,
            locale_tag: String::new(),
            scale_factor: 1.0,
        });
        assert!(!plan
            .tasks
            .iter()
            .any(|task| task.kind == FrameTaskKind::SnapGuides as i32));
    }

    #[test]
    fn resize_edit_from_center_skips_object_snapping() {
        let mut engine = Engine::default();
        engine
            .dispatch(EngineCommand {
                kind: EngineCommandKind::CreateElement as i32,
                payload: Some(CommandPayload::CreateElement(CreateElementCommand {
                    element_type: ElementType::Rectangle as i32,
                    element_id: "center-object-reference".to_string(),
                    position: Some(DrawPoint {
                        x: 200.0,
                        y: 40.0,
                        pressure: 0.0,
                        timestamp_us: 0,
                    }),
                    initial_payload: Vec::new(),
                    maintain_aspect_ratio: false,
                    create_from_center: false,
                    snap_override: true,
                })),
            })
            .expect("create reference");
        engine
            .dispatch(EngineCommand {
                kind: EngineCommandKind::FinishCreateElement as i32,
                payload: None,
            })
            .expect("finish reference");
        engine
            .dispatch(EngineCommand {
                kind: EngineCommandKind::CreateElement as i32,
                payload: Some(CommandPayload::CreateElement(CreateElementCommand {
                    element_type: ElementType::Rectangle as i32,
                    element_id: "center-object-target".to_string(),
                    position: Some(DrawPoint {
                        x: 0.0,
                        y: 40.0,
                        pressure: 0.0,
                        timestamp_us: 0,
                    }),
                    initial_payload: Vec::new(),
                    maintain_aspect_ratio: false,
                    create_from_center: false,
                    snap_override: true,
                })),
            })
            .expect("create target");
        engine
            .dispatch(EngineCommand {
                kind: EngineCommandKind::FinishCreateElement as i32,
                payload: None,
            })
            .expect("finish target");

        assert!(engine.apply_runtime_config_payload(
            br#"{"grid":{"enabled":false},"snap":{"enabled":true,"distance":8.0}}"#,
        ));

        engine
            .dispatch(EngineCommand {
                kind: EngineCommandKind::StartEdit as i32,
                payload: Some(CommandPayload::StartEdit(engine_proto::StartEditCommand {
                    operation_id: "resize".to_string(),
                    position: Some(DrawPoint {
                        x: 100.0,
                        y: 80.0,
                        pressure: 0.0,
                        timestamp_us: 0,
                    }),
                    params: br#"{"type":"resize","resizeMode":"right"}"#.to_vec(),
                })),
            })
            .expect("start resize");
        engine
            .dispatch(EngineCommand {
                kind: EngineCommandKind::UpdateEdit as i32,
                payload: Some(CommandPayload::UpdateEdit(UpdateEditCommand {
                    current_position: Some(DrawPoint {
                        x: 197.0,
                        y: 80.0,
                        pressure: 0.0,
                        timestamp_us: 0,
                    }),
                    modifiers: br#"{"fromCenter":true,"snapOverride":false}"#.to_vec(),
                })),
            })
            .expect("update resize");

        let unsnapped = engine
            .snapshot
            .elements
            .iter()
            .find(|entry| entry.id == "center-object-target")
            .and_then(|entry| entry.rect.clone())
            .expect("center-object rect");
        assert_eq!(unsnapped.min_x, -97.0);
        assert_eq!(unsnapped.max_x, 217.0);

        let plan = engine.build_frame_plan(FramePlanRequest {
            viewport: None,
            locale_tag: String::new(),
            scale_factor: 1.0,
        });
        assert!(!plan
            .tasks
            .iter()
            .any(|task| task.kind == FrameTaskKind::SnapGuides as i32));
    }

    #[test]
    fn frame_plan_emits_runtime_grid_snap_guides_during_create() {
        let mut engine = Engine::default();
        assert!(engine.apply_runtime_config_payload(br#"{"grid":{"enabled":true,"size":10.0}}"#,));

        engine
            .dispatch(EngineCommand {
                kind: EngineCommandKind::CreateElement as i32,
                payload: Some(CommandPayload::CreateElement(CreateElementCommand {
                    element_type: ElementType::Rectangle as i32,
                    element_id: "snap-guides-grid".to_string(),
                    position: Some(DrawPoint {
                        x: 13.0,
                        y: 27.0,
                        pressure: 0.0,
                        timestamp_us: 0,
                    }),
                    initial_payload: Vec::new(),
                    maintain_aspect_ratio: false,
                    create_from_center: false,
                    snap_override: false,
                })),
            })
            .expect("create with grid snap");

        let plan = engine.build_frame_plan(FramePlanRequest {
            viewport: None,
            locale_tag: String::new(),
            scale_factor: 1.0,
        });
        let snap_guides = plan
            .tasks
            .iter()
            .find(|task| task.kind == FrameTaskKind::SnapGuides as i32)
            .expect("runtime grid snap guides task");
        let payload =
            serde_json::from_slice::<serde_json::Value>(&snap_guides.payload).expect("payload");
        let guides = payload
            .get("guides")
            .and_then(serde_json::Value::as_array)
            .expect("guides");
        assert!(guides.len() >= 2);
        assert!(guides.iter().any(|guide| {
            guide.get("axis").and_then(serde_json::Value::as_str) == Some("vertical")
        }));
        assert!(guides.iter().any(|guide| {
            guide.get("axis").and_then(serde_json::Value::as_str) == Some("horizontal")
        }));

        engine
            .dispatch(EngineCommand {
                kind: EngineCommandKind::FinishCreateElement as i32,
                payload: None,
            })
            .expect("finish create");
        let idle_plan = engine.build_frame_plan(FramePlanRequest {
            viewport: None,
            locale_tag: String::new(),
            scale_factor: 1.0,
        });
        assert!(!idle_plan
            .tasks
            .iter()
            .any(|task| task.kind == FrameTaskKind::SnapGuides as i32));
    }

    #[test]
    fn frame_plan_emits_runtime_object_snap_guides_during_move_edit() {
        let mut engine = Engine::default();

        engine
            .dispatch(EngineCommand {
                kind: EngineCommandKind::CreateElement as i32,
                payload: Some(CommandPayload::CreateElement(CreateElementCommand {
                    element_type: ElementType::Rectangle as i32,
                    element_id: "snap-guide-reference".to_string(),
                    position: Some(DrawPoint {
                        x: 100.0,
                        y: 100.0,
                        pressure: 0.0,
                        timestamp_us: 0,
                    }),
                    initial_payload: Vec::new(),
                    maintain_aspect_ratio: false,
                    create_from_center: false,
                    snap_override: true,
                })),
            })
            .expect("create reference");
        engine
            .dispatch(EngineCommand {
                kind: EngineCommandKind::FinishCreateElement as i32,
                payload: None,
            })
            .expect("finish reference");
        engine
            .dispatch(EngineCommand {
                kind: EngineCommandKind::CreateElement as i32,
                payload: Some(CommandPayload::CreateElement(CreateElementCommand {
                    element_type: ElementType::Rectangle as i32,
                    element_id: "snap-guide-target".to_string(),
                    position: Some(DrawPoint {
                        x: 0.0,
                        y: 0.0,
                        pressure: 0.0,
                        timestamp_us: 0,
                    }),
                    initial_payload: Vec::new(),
                    maintain_aspect_ratio: false,
                    create_from_center: false,
                    snap_override: true,
                })),
            })
            .expect("create target");
        engine
            .dispatch(EngineCommand {
                kind: EngineCommandKind::FinishCreateElement as i32,
                payload: None,
            })
            .expect("finish target");
        assert!(engine.apply_runtime_config_payload(
            br#"{"grid":{"enabled":false},"snap":{"enabled":true,"distance":8.0}}"#,
        ));

        engine
            .dispatch(EngineCommand {
                kind: EngineCommandKind::StartEdit as i32,
                payload: Some(CommandPayload::StartEdit(engine_proto::StartEditCommand {
                    operation_id: "move".to_string(),
                    position: Some(DrawPoint {
                        x: 0.0,
                        y: 0.0,
                        pressure: 0.0,
                        timestamp_us: 0,
                    }),
                    params: br#"{"type":"move"}"#.to_vec(),
                })),
            })
            .expect("start move");
        engine
            .dispatch(EngineCommand {
                kind: EngineCommandKind::UpdateEdit as i32,
                payload: Some(CommandPayload::UpdateEdit(UpdateEditCommand {
                    current_position: Some(DrawPoint {
                        x: 96.0,
                        y: 95.0,
                        pressure: 0.0,
                        timestamp_us: 0,
                    }),
                    modifiers: br#"{"snapOverride":false}"#.to_vec(),
                })),
            })
            .expect("update move");

        let plan = engine.build_frame_plan(FramePlanRequest {
            viewport: None,
            locale_tag: String::new(),
            scale_factor: 1.0,
        });
        let snap_guides = plan
            .tasks
            .iter()
            .find(|task| task.kind == FrameTaskKind::SnapGuides as i32)
            .expect("runtime object snap guides task");
        let payload =
            serde_json::from_slice::<serde_json::Value>(&snap_guides.payload).expect("payload");
        let guides = payload
            .get("guides")
            .and_then(serde_json::Value::as_array)
            .expect("guides");
        assert!(!guides.is_empty());

        engine
            .dispatch(EngineCommand {
                kind: EngineCommandKind::CancelEdit as i32,
                payload: None,
            })
            .expect("cancel move");
        let idle_plan = engine.build_frame_plan(FramePlanRequest {
            viewport: None,
            locale_tag: String::new(),
            scale_factor: 1.0,
        });
        assert!(!idle_plan
            .tasks
            .iter()
            .any(|task| task.kind == FrameTaskKind::SnapGuides as i32));
    }

    #[test]
    fn event_queue_is_bounded() {
        let mut engine = Engine::default();
        for _ in 0..(EVENT_QUEUE_LIMIT + 128) {
            engine
                .dispatch(EngineCommand {
                    kind: EngineCommandKind::MoveCamera as i32,
                    payload: Some(CommandPayload::MoveCamera(MoveCameraCommand {
                        dx: 1.0,
                        dy: 0.0,
                    })),
                })
                .expect("dispatch");
        }

        let mut count = 0;
        while engine.poll_event().is_some() {
            count += 1;
        }
        assert_eq!(count, EVENT_QUEUE_LIMIT);
    }
}
