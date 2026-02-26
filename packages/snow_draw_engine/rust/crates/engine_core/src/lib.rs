//! Headless Snow Draw engine core implemented in Rust.

use std::collections::{BTreeMap, BTreeSet, VecDeque};

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
    snapshot: EngineSnapshot,
    undo_stack: Vec<EngineSnapshot>,
    redo_stack: Vec<EngineSnapshot>,
    events: VecDeque<EngineEvent>,
    next_event_sequence: u64,
    next_element_sequence: u64,
    creating_element_id: Option<String>,
    text_edit_session: Option<TextEditSession>,
    box_select_start: Option<DrawPoint>,
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
}

#[derive(Debug, Clone)]
enum EditSessionOperation {
    Move,
    Resize { mode: ResizeMode },
    Rotate { pivot: DrawPoint, snap_angle: f64 },
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
            snapshot,
            undo_stack: Vec::new(),
            redo_stack: Vec::new(),
            events: VecDeque::new(),
            next_event_sequence: 1,
            next_element_sequence,
            creating_element_id: None,
            text_edit_session: None,
            box_select_start: None,
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
                self.emit_state_changed();
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
                self.sync_history_lengths();
                self.emit_history_changed();
            }
            EngineCommandKind::Unknown => {
                self.emit_debug(format!("command {kind:?} accepted as no-op"));
            }
        }

        Ok(())
    }

    pub fn get_snapshot(&self) -> EngineSnapshot {
        self.snapshot.clone()
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
        }

        if self.snapshot.interaction_mode == InteractionMode::BoxSelecting as i32 {
            tasks.push(FrameTask {
                kind: FrameTaskKind::BoxSelection as i32,
                element_id: String::new(),
                element_type: ElementType::Unknown as i32,
                payload: Vec::new(),
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
            opacity: 1.0,
            z_index,
            payload: if payload.initial_payload.is_empty() {
                default_element_payload(element_type)
            } else {
                payload.initial_payload
            },
        });

        self.sort_elements();
        self.snapshot.document_version += 1;
        self.set_selected(BTreeSet::from([id]));
        self.creating_element_id = self.snapshot.selected_ids.first().cloned();
        self.set_interaction_mode(InteractionMode::Creating);
    }

    fn apply_update_creating(&mut self, payload: UpdateCreatingElementCommand) {
        let Some(creating_id) = self.creating_element_id.clone() else {
            return;
        };
        let Some(last_position) = payload.positions.last().cloned() else {
            return;
        };
        let Some(element) = self.element_mut(&creating_id) else {
            return;
        };
        let start = element
            .rect
            .as_ref()
            .map(|rect| DrawPoint {
                x: rect.min_x,
                y: rect.min_y,
                pressure: 0.0,
                timestamp_us: 0,
            })
            .unwrap_or(DrawPoint {
                x: last_position.x,
                y: last_position.y,
                pressure: 0.0,
                timestamp_us: 0,
            });
        element.rect = Some(rect_from_points(
            start,
            last_position,
            payload.maintain_aspect_ratio,
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
        let Some(element) = self.element_mut(&creating_id) else {
            return;
        };
        if element.element_type != ElementType::Arrow as i32 {
            return;
        }

        let mut map = decode_json_map(&element.payload)
            .unwrap_or_else(|| default_element_payload_map(element.element_type));
        let points = map
            .entry("points".to_string())
            .or_insert_with(|| JsonValue::Array(Vec::new()));
        if let JsonValue::Array(entries) = points {
            entries.push(JsonValue::Object(JsonMap::from_iter([
                ("x".to_string(), JsonValue::from(position.x)),
                ("y".to_string(), JsonValue::from(position.y)),
            ])));
            element.payload = encode_json_map(&map);
            self.snapshot.document_version += 1;
        }
    }

    fn apply_finish_create(&mut self) {
        self.creating_element_id = None;
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
        let normalized = decode_json_map(&payload.payload)
            .map(|map| encode_json_map(&map))
            .unwrap_or(payload.payload);
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
        let mut next_z = self
            .snapshot
            .elements
            .iter()
            .map(|element| element.z_index)
            .max()
            .unwrap_or(-1)
            + 1;
        let mut created = Vec::new();

        for source in self.snapshot.elements.clone() {
            if !source_ids.contains(source.id.as_str()) {
                continue;
            }
            let id = format!("rust_{}", self.next_element_sequence);
            self.next_element_sequence += 1;
            let rect = source.rect.map(|source_rect| DrawRect {
                min_x: source_rect.min_x,
                min_y: source_rect.max_y + 8.0,
                max_x: source_rect.min_x + 120.0,
                max_y: source_rect.max_y + 32.0,
            });
            created.push(Element {
                id,
                element_type: ElementType::Text as i32,
                rect,
                rotation: 0.0,
                opacity: 1.0,
                z_index: next_z,
                payload: {
                    let mut map = default_element_payload_map(ElementType::Text as i32);
                    map.insert("text".to_string(), JsonValue::from(source.id.clone()));
                    encode_json_map(&map)
                },
            });
            next_z += 1;
        }

        if created.is_empty() {
            return;
        }
        self.snapshot.elements.extend(created);
        self.sort_elements();
        self.snapshot.document_version += 1;
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
            self.snapshot.elements.push(Element {
                id: element_id.clone(),
                element_type: ElementType::Text as i32,
                rect: Some(DrawRect {
                    min_x: point.x,
                    min_y: point.y,
                    max_x: point.x + 160.0,
                    max_y: point.y + 40.0,
                }),
                rotation: 0.0,
                opacity: 1.0,
                z_index,
                payload: default_element_payload(ElementType::Text as i32),
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

    fn apply_start_edit(&mut self, payload: engine_proto::StartEditCommand) {
        let operation_id = payload.operation_id.trim().to_string();
        let params = decode_json_map(&payload.params);
        let start = payload.position.unwrap_or(DrawPoint {
            x: 0.0,
            y: 0.0,
            pressure: 0.0,
            timestamp_us: 0,
        });
        let baseline_rects = self
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
        let baseline_rotations = self
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

        let operation =
            resolve_edit_operation(operation_id.as_str(), params.as_ref(), &baseline_rects);

        self.edit_session = Some(EditSession {
            operation,
            start_position: start,
            baseline_rects,
            baseline_rotations,
        });
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

        let changed = match session.operation {
            EditSessionOperation::Move => self.apply_update_move_edit(
                session.start_position,
                current,
                &session.baseline_rects,
            ),
            EditSessionOperation::Resize { mode } => self.apply_update_resize_edit(
                session.start_position,
                current,
                &session.baseline_rects,
                mode,
                modifiers.from_center,
            ),
            EditSessionOperation::Rotate { pivot, snap_angle } => self.apply_update_rotate_edit(
                session.start_position,
                current,
                pivot,
                snap_angle,
                modifiers.discrete_angle,
                &session.baseline_rects,
                &session.baseline_rotations,
            ),
            EditSessionOperation::Unknown => false,
        };

        if changed {
            self.snapshot.document_version += 1;
            self.set_interaction_mode(InteractionMode::Editing);
        }
    }

    fn apply_finish_edit(&mut self) {
        self.edit_session = None;
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
        if changed {
            self.snapshot.document_version += 1;
        }
        self.set_interaction_mode(InteractionMode::Idle);
    }

    fn apply_update_move_edit(
        &mut self,
        start: DrawPoint,
        current: DrawPoint,
        baseline_rects: &BTreeMap<String, DrawRect>,
    ) -> bool {
        let dx = current.x - start.x;
        let dy = current.y - start.y;
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
        from_center: bool,
    ) -> bool {
        let dx = current.x - start.x;
        let dy = current.y - start.y;
        let mut changed = false;
        let (move_left, move_right, move_top, move_bottom) = resize_mode_axes(mode);

        for (element_id, base_rect) in baseline_rects {
            let mut min_x = base_rect.min_x;
            let mut max_x = base_rect.max_x;
            let mut min_y = base_rect.min_y;
            let mut max_y = base_rect.max_y;

            if move_left {
                min_x += dx;
                if from_center {
                    max_x -= dx;
                }
            }
            if move_right {
                max_x += dx;
                if from_center {
                    min_x -= dx;
                }
            }
            if move_top {
                min_y += dy;
                if from_center {
                    max_y -= dy;
                }
            }
            if move_bottom {
                max_y += dy;
                if from_center {
                    min_y -= dy;
                }
            }

            let rect = normalize_rect(DrawRect {
                min_x,
                min_y,
                max_x,
                max_y,
            });
            if let Some(element) = self.element_mut(element_id) {
                element.rect = Some(rect);
                changed = true;
            }
        }

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

    fn apply_set_drag_pending(&mut self, payload: SetDragPendingCommand) {
        self.box_select_start = payload.pointer_down_position;
        self.set_interaction_mode(InteractionMode::DragPending);
    }

    fn apply_start_box_select(&mut self, payload: StartBoxSelectCommand) {
        self.box_select_start = payload.start_position;
        self.set_interaction_mode(InteractionMode::BoxSelecting);
    }

    fn apply_update_box_select(&mut self, payload: UpdateBoxSelectCommand) {
        let Some(start) = self.box_select_start.as_ref() else {
            return;
        };
        let current = payload.current_position.unwrap_or_else(|| start.clone());
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
        camera.zoom *= payload.scale;
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
        self.text_edit_session = None;
        self.box_select_start = None;
        self.edit_session = None;
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

fn default_element_payload(element_type: i32) -> Vec<u8> {
    encode_json_map(&default_element_payload_map(element_type))
}

fn decode_json_map(bytes: &[u8]) -> Option<JsonMap<String, JsonValue>> {
    let value = serde_json::from_slice::<JsonValue>(bytes).ok()?;
    value.as_object().cloned()
}

fn encode_json_map(map: &JsonMap<String, JsonValue>) -> Vec<u8> {
    serde_json::to_vec(map).unwrap_or_default()
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

fn rects_intersect(a: &DrawRect, b: &DrawRect) -> bool {
    !(a.max_x < b.min_x || a.min_x > b.max_x || a.max_y < b.min_y || a.min_y > b.max_y)
}

#[derive(Debug, Clone, Copy, Default)]
struct EditModifiersPayload {
    maintain_aspect_ratio: bool,
    from_center: bool,
    discrete_angle: bool,
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
        assert!(plan
            .tasks
            .iter()
            .any(|task| task.kind == FrameTaskKind::Text as i32));
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
