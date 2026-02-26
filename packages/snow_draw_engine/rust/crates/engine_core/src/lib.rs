//! Headless Snow Draw engine core implemented in Rust.

use std::collections::{BTreeSet, VecDeque};

use engine_proto::engine_command::Payload as CommandPayload;
use engine_proto::engine_event::Payload as EventPayload;
use engine_proto::{
    decode_message, default_camera_state, default_engine_config, default_engine_snapshot,
    encode_message, CameraState, CreateElementCommand, DrawPoint, DrawRect, Element, ElementType,
    EngineCommand, EngineCommandKind, EngineConfig, EngineError, EngineEvent, EngineEventKind,
    EngineSnapshot, FramePlanRequest, FrameRenderPlan, FrameTask, FrameTaskKind, MoveCameraCommand,
    SelectElementCommand, UpdateElementsStyleCommand, ZoomCameraCommand,
};
use thiserror::Error;

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
        Self {
            config,
            snapshot,
            undo_stack: Vec::new(),
            redo_stack: Vec::new(),
            events: VecDeque::new(),
            next_event_sequence: 1,
            next_element_sequence: 1,
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
            EngineCommandKind::DeleteElements => {
                let payload = extract_delete_payload(kind, command.payload)?;
                self.record_history();
                self.apply_delete(payload.element_ids);
                self.emit_state_changed();
            }
            EngineCommandKind::UpdateElementsStyle => {
                let payload = extract_update_style_payload(kind, command.payload)?;
                self.record_history();
                self.apply_update_style(payload);
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
            _ => {
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
                kind: FrameTaskKind::SelectionControls as i32,
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
            element_type: if payload.element_type == 0 {
                ElementType::Rectangle as i32
            } else {
                payload.element_type
            },
            rect: Some(rect),
            rotation: 0.0,
            opacity: 1.0,
            z_index,
            payload: payload.initial_payload,
        });

        self.sort_elements();
        self.snapshot.document_version += 1;
        self.set_selected(BTreeSet::from([id]));
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

        for element in &mut self.snapshot.elements {
            if ids.contains(element.id.as_str()) {
                element.payload = payload.style_payload.clone();
                changed = true;
            }
        }

        if changed {
            self.snapshot.document_version += 1;
        }
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
            self.sync_history_lengths();
            self.emit_history_changed();
            self.emit_state_changed();
        }
    }

    fn apply_redo(&mut self) {
        if let Some(next) = self.redo_stack.pop() {
            self.undo_stack.push(self.snapshot.clone());
            self.snapshot = next;
            self.sync_history_lengths();
            self.emit_history_changed();
            self.emit_state_changed();
        }
    }

    fn sort_elements(&mut self) {
        self.snapshot.elements.sort_by(|a, b| {
            a.z_index
                .cmp(&b.z_index)
                .then_with(|| a.id.as_str().cmp(b.id.as_str()))
        });
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
        self.events.push_back(event);
    }
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
                payload: None,
            },
            EngineCommand {
                kind: EngineCommandKind::AddArrowPoint as i32,
                payload: None,
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
                payload: None,
            },
            EngineCommand {
                kind: EngineCommandKind::ChangeElementZIndex as i32,
                payload: None,
            },
            EngineCommand {
                kind: EngineCommandKind::ChangeElementsZIndex as i32,
                payload: None,
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
                payload: None,
            },
            EngineCommand {
                kind: EngineCommandKind::CreateSerialNumberTextElements as i32,
                payload: None,
            },
            EngineCommand {
                kind: EngineCommandKind::StartTextEdit as i32,
                payload: None,
            },
            EngineCommand {
                kind: EngineCommandKind::UpdateTextEdit as i32,
                payload: None,
            },
            EngineCommand {
                kind: EngineCommandKind::RefreshAutoResizeTextLayoutsAfterFontLoad as i32,
                payload: None,
            },
            EngineCommand {
                kind: EngineCommandKind::FinishTextEdit as i32,
                payload: None,
            },
            EngineCommand {
                kind: EngineCommandKind::CancelTextEdit as i32,
                payload: None,
            },
            EngineCommand {
                kind: EngineCommandKind::StartEdit as i32,
                payload: None,
            },
            EngineCommand {
                kind: EngineCommandKind::UpdateEdit as i32,
                payload: None,
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
                payload: None,
            },
            EngineCommand {
                kind: EngineCommandKind::ClearDragPending as i32,
                payload: None,
            },
            EngineCommand {
                kind: EngineCommandKind::StartBoxSelect as i32,
                payload: None,
            },
            EngineCommand {
                kind: EngineCommandKind::UpdateBoxSelect as i32,
                payload: None,
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
}
