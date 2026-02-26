use std::collections::{BTreeMap, VecDeque};

use engine_proto as v1;
use engine_proto::engine_event::Payload as V1EventPayload;
use engine_proto::ElementType as V1ElementType;
use engine_proto_v2 as v2;
use engine_proto_v2::engine_input::Payload as V2InputPayload;
use engine_proto_v2::engine_output::Payload as V2OutputPayload;
use serde_json::{Map as JsonMap, Value as JsonValue};

use crate::{Engine, EngineCoreError};

const CAP_EVENT_STREAM: u64 = 1 << 0;
const CAP_FRAME_PLAN: u64 = 1 << 1;
const CAP_DISPATCH_BATCH: u64 = 1 << 2;
const CAP_INPUT_PIPELINE: u64 = 1 << 3;
const CAP_TEXT_METRICS_HOST: u64 = 1 << 4;
const CAP_SUPPORTED: u64 = CAP_EVENT_STREAM
    | CAP_FRAME_PLAN
    | CAP_DISPATCH_BATCH
    | CAP_INPUT_PIPELINE
    | CAP_TEXT_METRICS_HOST;

#[derive(Debug)]
pub struct EngineV2 {
    engine: Engine,
    outputs: VecDeque<v2::EngineOutput>,
    next_sequence: u64,
    next_host_request_id: u64,
    locale_tag: String,
    scale_factor: f64,
    pending_text_metrics: BTreeMap<u64, PendingTextMetricsRequest>,
}

#[derive(Debug, Clone)]
struct PendingTextMetricsRequest {
    element_id: String,
    expected_text: String,
}

#[derive(Debug, Clone)]
struct TextMetricsTarget {
    element_id: String,
    expected_text: String,
    request: v2::TextMetricsRequest,
}

impl EngineV2 {
    pub fn from_init_request(init: v2::EngineInitRequest) -> Self {
        let mut config = v1::default_engine_config();
        if !init.locale_tag.trim().is_empty() {
            config.locale_tag = init.locale_tag.clone();
        }
        if init.scale_factor.is_finite() && init.scale_factor > 0.0 {
            config.scale_factor = init.scale_factor;
        }
        if init.deterministic_seed > 0 {
            config.deterministic_seed = init.deterministic_seed;
        }
        if init.schema_version > 0 {
            config.schema_version = init.schema_version;
        }
        config.requested_capabilities = init.requested_capabilities_mask;

        let locale_tag = config.locale_tag.clone();
        let scale_factor = config.scale_factor;
        let granted = if init.requested_capabilities_mask == 0 {
            CAP_SUPPORTED
        } else {
            init.requested_capabilities_mask & CAP_SUPPORTED
        };

        let mut engine = Self {
            engine: Engine::new(config),
            outputs: VecDeque::new(),
            next_sequence: 1,
            next_host_request_id: 1,
            locale_tag,
            scale_factor,
            pending_text_metrics: BTreeMap::new(),
        };

        engine.push_output(V2OutputPayload::InitAck(v2::EngineInitAck {
            abi_version: 2,
            schema_version: v2::ENGINE_V2_SCHEMA_VERSION,
            granted_capabilities_mask: granted,
            message: "engine_v2 ready".to_string(),
        }));

        engine
    }

    pub fn process_input_bytes(&mut self, bytes: &[u8]) -> Result<(), EngineCoreError> {
        let input = v2::decode_message::<v2::EngineInput>(bytes)
            .map_err(|error| EngineCoreError::Decode(error.to_string()))?;
        self.process_input(input)
    }

    pub fn process_input(&mut self, input: v2::EngineInput) -> Result<(), EngineCoreError> {
        let Some(payload) = input.payload else {
            self.push_debug("engine_v2 input missing payload");
            return Ok(());
        };

        match payload {
            V2InputPayload::CommandEvent(event) => {
                if event.command_bytes.is_empty() {
                    self.push_debug("engine_v2 command_event missing command_bytes");
                    return Ok(());
                }

                let command = v1::decode_message::<v1::EngineCommand>(&event.command_bytes)
                    .map_err(|error| EngineCoreError::Decode(error.to_string()))?;
                let command_kind = v1::EngineCommandKind::try_from(command.kind)
                    .unwrap_or(v1::EngineCommandKind::Unknown);

                if let Err(error) = self.engine.dispatch(command) {
                    self.push_output(V2OutputPayload::Event(v2::EngineEvent {
                        kind: v2::EngineEventKind::Error as i32,
                        sequence: 0,
                        payload: Some(v2::engine_event::Payload::Error(v2::EngineError {
                            code: error.code(),
                            message: error.to_string(),
                            details: format!("{error:?}"),
                        })),
                    }));
                    return Err(error);
                }

                while let Some(event) = self.engine.poll_event() {
                    self.push_output(V2OutputPayload::Event(convert_event(event)));
                }

                let snapshot = self.emit_snapshot_state_and_frame();
                self.maybe_emit_text_metrics_requests(command_kind, &snapshot);
            }
            V2InputPayload::ConfigEvent(event) => {
                if !event.locale_tag.trim().is_empty() {
                    self.locale_tag = event.locale_tag;
                }
                if event.scale_factor.is_finite() && event.scale_factor > 0.0 {
                    self.scale_factor = event.scale_factor;
                }
                self.push_debug("engine_v2 config updated");
            }
            V2InputPayload::PointerEvent(event) => {
                self.push_output(V2OutputPayload::HostRequest(v2::HostRequest {
                    request_id: input.sequence,
                    payload: Some(v2::host_request::Payload::PointerHostRequest(
                        v2::PointerHostRequest { event: Some(event) },
                    )),
                }));
            }
            V2InputPayload::KeyboardEvent(event) => {
                self.push_output(V2OutputPayload::HostRequest(v2::HostRequest {
                    request_id: input.sequence,
                    payload: Some(v2::host_request::Payload::KeyboardHostRequest(
                        v2::KeyboardHostRequest { event: Some(event) },
                    )),
                }));
            }
            V2InputPayload::ToolEvent(event) => {
                self.push_output(V2OutputPayload::HostRequest(v2::HostRequest {
                    request_id: input.sequence,
                    payload: Some(v2::host_request::Payload::ToolHostRequest(
                        v2::ToolHostRequest { event: Some(event) },
                    )),
                }));
            }
            V2InputPayload::TextMetricsResponse(response) => {
                self.handle_text_metrics_response(response);
            }
        }

        Ok(())
    }

    pub fn poll_output(&mut self) -> Option<v2::EngineOutput> {
        self.outputs.pop_front()
    }

    pub fn poll_output_bytes(&mut self) -> Option<Vec<u8>> {
        self.poll_output().map(|output| v2::encode_message(&output))
    }

    fn emit_snapshot_state_and_frame(&mut self) -> v1::EngineSnapshot {
        let snapshot = self.engine.get_snapshot();
        self.push_output(V2OutputPayload::Snapshot(convert_snapshot(
            snapshot.clone(),
        )));
        self.push_output(V2OutputPayload::StateDelta(v2::EngineStateDelta {
            document_version: snapshot.document_version,
            selection_version: snapshot.selection_version,
            changed_element_ids: canonical_changed_element_ids(&snapshot),
        }));

        let plan = self.engine.build_frame_plan(v1::FramePlanRequest {
            viewport: None,
            locale_tag: self.locale_tag.clone(),
            scale_factor: self.scale_factor,
        });
        self.push_output(V2OutputPayload::FramePlan(convert_frame_plan(plan)));
        snapshot
    }

    fn next_text_metrics_request_id(&mut self) -> u64 {
        let request_id = self.next_host_request_id;
        self.next_host_request_id = self.next_host_request_id.saturating_add(1);
        request_id
    }

    fn maybe_emit_text_metrics_requests(
        &mut self,
        command_kind: v1::EngineCommandKind,
        snapshot: &v1::EngineSnapshot,
    ) {
        let targets =
            collect_text_metrics_targets(snapshot, command_kind, self.locale_tag.as_str());
        for target in targets {
            self.pending_text_metrics
                .retain(|_, pending| pending.element_id != target.element_id);

            let request_id = self.next_text_metrics_request_id();
            self.pending_text_metrics.insert(
                request_id,
                PendingTextMetricsRequest {
                    element_id: target.element_id.clone(),
                    expected_text: target.expected_text.clone(),
                },
            );

            self.push_output(V2OutputPayload::HostRequest(v2::HostRequest {
                request_id,
                payload: Some(v2::host_request::Payload::TextMetricsRequest(
                    target.request,
                )),
            }));
        }
    }

    fn handle_text_metrics_response(&mut self, response: v2::TextMetricsResponse) {
        let Some(pending) = self.pending_text_metrics.remove(&response.request_id) else {
            self.push_debug(format!(
                "engine_v2 text metrics response ignored (unknown request_id={})",
                response.request_id
            ));
            return;
        };

        if !response.ok {
            let details = response
                .error
                .as_ref()
                .map(|error| error.message.clone())
                .unwrap_or_else(|| "unknown text metrics host error".to_string());
            self.push_debug(format!(
                "engine_v2 text metrics response rejected (request_id={}, reason={details})",
                response.request_id
            ));
            return;
        }

        let Some(metrics) = response.metrics else {
            self.push_debug(format!(
                "engine_v2 text metrics response missing metrics (request_id={})",
                response.request_id
            ));
            return;
        };

        if self.engine.apply_text_metrics_layout(
            pending.element_id.as_str(),
            pending.expected_text.as_str(),
            metrics.width,
            metrics.height,
        ) {
            while let Some(event) = self.engine.poll_event() {
                self.push_output(V2OutputPayload::Event(convert_event(event)));
            }
            let _ = self.emit_snapshot_state_and_frame();
        }
    }

    fn push_debug(&mut self, message: impl Into<String>) {
        self.push_output(V2OutputPayload::Event(v2::EngineEvent {
            kind: v2::EngineEventKind::Debug as i32,
            sequence: 0,
            payload: Some(v2::engine_event::Payload::Message(message.into())),
        }));
    }

    fn push_output(&mut self, payload: V2OutputPayload) {
        self.outputs.push_back(v2::EngineOutput {
            sequence: self.next_sequence,
            payload: Some(payload),
        });
        self.next_sequence += 1;
    }
}

fn canonical_changed_element_ids(snapshot: &v1::EngineSnapshot) -> Vec<String> {
    let mut changed = snapshot
        .elements
        .iter()
        .map(|element| element.id.clone())
        .collect::<Vec<_>>();
    changed.sort();
    changed.dedup();
    changed
}

fn collect_text_metrics_targets(
    snapshot: &v1::EngineSnapshot,
    command_kind: v1::EngineCommandKind,
    locale_tag: &str,
) -> Vec<TextMetricsTarget> {
    match command_kind {
        v1::EngineCommandKind::StartTextEdit | v1::EngineCommandKind::UpdateTextEdit => {
            let Some(selected_id) = snapshot.selected_ids.first() else {
                return Vec::new();
            };
            snapshot
                .elements
                .iter()
                .find(|element| element.id == *selected_id)
                .and_then(|element| build_text_metrics_target(element, locale_tag, false))
                .into_iter()
                .collect()
        }
        v1::EngineCommandKind::RefreshAutoResizeTextLayoutsAfterFontLoad => snapshot
            .elements
            .iter()
            .filter_map(|element| build_text_metrics_target(element, locale_tag, false))
            .collect(),
        _ => Vec::new(),
    }
}

fn build_text_metrics_target(
    element: &v1::Element,
    locale_tag: &str,
    is_resizing: bool,
) -> Option<TextMetricsTarget> {
    if V1ElementType::try_from(element.element_type).unwrap_or(V1ElementType::Unknown)
        != V1ElementType::Text
    {
        return None;
    }

    let payload = decode_json_object(&element.payload)?;
    let auto_resize = payload
        .get("autoResize")
        .and_then(JsonValue::as_bool)
        .unwrap_or(true);
    if !auto_resize {
        return None;
    }

    let text = json_string(&payload, "text", "");
    let font_size = json_f64(&payload, "fontSize", 21.0);
    let font_family = json_string(&payload, "fontFamily", "");
    let max_width = element
        .rect
        .as_ref()
        .map(|rect| (rect.max_x - rect.min_x).abs())
        .filter(|width| width.is_finite() && *width > 0.0)
        .unwrap_or(4096.0);

    Some(TextMetricsTarget {
        element_id: element.id.clone(),
        expected_text: text.clone(),
        request: v2::TextMetricsRequest {
            text,
            font_size,
            font_family,
            max_width,
            min_width: 0.0,
            locale_tag: locale_tag.to_string(),
            is_resizing,
        },
    })
}

fn convert_event(event: v1::EngineEvent) -> v2::EngineEvent {
    let payload = match event.payload {
        Some(V1EventPayload::Error(error)) => {
            Some(v2::engine_event::Payload::Error(v2::EngineError {
                code: error.code,
                message: error.message,
                details: error.details,
            }))
        }
        Some(V1EventPayload::Blob(blob)) => Some(v2::engine_event::Payload::Blob(blob)),
        Some(V1EventPayload::Message(message)) => Some(v2::engine_event::Payload::Message(message)),
        None => None,
    };

    v2::EngineEvent {
        kind: event.kind,
        sequence: event.sequence,
        payload,
    }
}

fn convert_snapshot(snapshot: v1::EngineSnapshot) -> v2::EngineSnapshot {
    v2::EngineSnapshot {
        schema_version: snapshot.schema_version,
        document_version: snapshot.document_version,
        selection_version: snapshot.selection_version,
        interaction_mode: snapshot.interaction_mode,
        camera: snapshot.camera.map(convert_camera),
        elements: snapshot.elements.into_iter().map(convert_element).collect(),
        selected_ids: snapshot.selected_ids,
        history_undo_len: snapshot.history_undo_len,
        history_redo_len: snapshot.history_redo_len,
        global_elements_payload: snapshot.global_elements_payload,
    }
}

fn convert_camera(camera: v1::CameraState) -> v2::CameraState {
    v2::CameraState {
        position: camera.position.map(convert_point),
        zoom: camera.zoom,
    }
}

fn convert_point(point: v1::DrawPoint) -> v2::DrawPoint {
    v2::DrawPoint {
        x: point.x,
        y: point.y,
        pressure: point.pressure,
        timestamp_us: point.timestamp_us,
    }
}

fn convert_rect(rect: v1::DrawRect) -> v2::DrawRect {
    v2::DrawRect {
        min_x: rect.min_x,
        min_y: rect.min_y,
        max_x: rect.max_x,
        max_y: rect.max_y,
    }
}

fn convert_element(element: v1::Element) -> v2::Element {
    v2::Element {
        id: element.id,
        element_type: element.element_type,
        rect: element.rect.map(convert_rect),
        rotation: element.rotation,
        opacity: element.opacity,
        z_index: element.z_index,
        payload: Some(convert_element_payload(
            element.element_type,
            element.payload,
        )),
    }
}

fn convert_raw_payload(payload: Vec<u8>) -> v2::ElementPayload {
    let value = if serde_json::from_slice::<JsonValue>(&payload).is_ok() {
        v2::element_payload::Payload::RawJsonPayload(payload)
    } else {
        v2::element_payload::Payload::RawBinaryPayload(payload)
    };
    v2::ElementPayload {
        payload: Some(value),
    }
}

fn convert_element_payload(element_type: i32, payload: Vec<u8>) -> v2::ElementPayload {
    let Some(map) = decode_json_object(&payload) else {
        return convert_raw_payload(payload);
    };

    let kind = V1ElementType::try_from(element_type).unwrap_or(V1ElementType::Unknown);

    let typed = match kind {
        V1ElementType::Rectangle => v2::element_payload::Payload::Rectangle(v2::RectanglePayload {
            color_argb32: json_u64(&map, "color", 0xFF1E1E1E),
            fill_color_argb32: json_u64(&map, "fillColor", 0),
            stroke_width: json_f64(&map, "strokeWidth", 2.0),
        }),
        V1ElementType::Arrow => v2::element_payload::Payload::Arrow(v2::ArrowPayload {
            points: json_points(&map, "points"),
            arrow_type: json_string_any(&map, &["arrowType", "lineType"], "straight"),
        }),
        V1ElementType::Line => v2::element_payload::Payload::Line(v2::LinePayload {
            points: json_points(&map, "points"),
            line_type: json_string_any(&map, &["lineType", "strokeStyle", "arrowType"], "solid"),
        }),
        V1ElementType::FreeDraw => v2::element_payload::Payload::FreeDraw(v2::FreeDrawPayload {
            points: json_points(&map, "points"),
        }),
        V1ElementType::Filter => v2::element_payload::Payload::Filter(v2::FilterPayload {
            filter_type: json_string_any(&map, &["filterType", "type"], "mosaic"),
            strength: json_f64(&map, "strength", 0.5),
        }),
        V1ElementType::Highlight => v2::element_payload::Payload::Highlight(v2::HighlightPayload {
            shape: json_string(&map, "shape", "rectangle"),
            color_argb32: json_u64(&map, "color", 0xFFF5222D),
        }),
        V1ElementType::Text => v2::element_payload::Payload::Text(v2::TextPayload {
            text: json_string(&map, "text", ""),
            font_size: json_f64(&map, "fontSize", 21.0),
            font_family: json_string(&map, "fontFamily", ""),
        }),
        V1ElementType::SerialNumber => {
            v2::element_payload::Payload::SerialNumber(v2::SerialNumberPayload {
                number: json_i32(&map, "number", 1),
                text_element_id: json_string(&map, "textElementId", ""),
            })
        }
        V1ElementType::Unknown => return convert_raw_payload(payload),
    };

    v2::ElementPayload {
        payload: Some(typed),
    }
}

fn decode_json_object(payload: &[u8]) -> Option<JsonMap<String, JsonValue>> {
    let value = serde_json::from_slice::<JsonValue>(payload).ok()?;
    value.as_object().cloned()
}

fn json_points(map: &JsonMap<String, JsonValue>, key: &str) -> Vec<v2::DrawPoint> {
    let Some(raw_points) = map.get(key).and_then(JsonValue::as_array) else {
        return Vec::new();
    };

    raw_points
        .iter()
        .filter_map(JsonValue::as_object)
        .map(|entry| {
            let timestamp_us = entry
                .get("timestampUs")
                .and_then(json_u64_value)
                .or_else(|| entry.get("timestamp_us").and_then(json_u64_value))
                .or_else(|| entry.get("timestamp").and_then(json_u64_value))
                .unwrap_or(0);
            v2::DrawPoint {
                x: entry
                    .get("x")
                    .and_then(JsonValue::as_f64)
                    .unwrap_or_default(),
                y: entry
                    .get("y")
                    .and_then(JsonValue::as_f64)
                    .unwrap_or_default(),
                pressure: entry
                    .get("pressure")
                    .and_then(JsonValue::as_f64)
                    .unwrap_or_default(),
                timestamp_us,
            }
        })
        .collect()
}

fn json_string_any(map: &JsonMap<String, JsonValue>, keys: &[&str], fallback: &str) -> String {
    for key in keys {
        if let Some(value) = map.get(*key).and_then(JsonValue::as_str) {
            return value.to_string();
        }
    }
    fallback.to_string()
}

fn json_string(map: &JsonMap<String, JsonValue>, key: &str, fallback: &str) -> String {
    map.get(key)
        .and_then(JsonValue::as_str)
        .unwrap_or(fallback)
        .to_string()
}

fn json_f64(map: &JsonMap<String, JsonValue>, key: &str, fallback: f64) -> f64 {
    map.get(key).and_then(JsonValue::as_f64).unwrap_or(fallback)
}

fn json_u64(map: &JsonMap<String, JsonValue>, key: &str, fallback: u64) -> u64 {
    map.get(key).and_then(json_u64_value).unwrap_or(fallback)
}

fn json_i32(map: &JsonMap<String, JsonValue>, key: &str, fallback: i32) -> i32 {
    map.get(key)
        .and_then(JsonValue::as_i64)
        .and_then(|value| i32::try_from(value).ok())
        .unwrap_or(fallback)
}

fn json_u64_value(value: &JsonValue) -> Option<u64> {
    if let Some(v) = value.as_u64() {
        return Some(v);
    }
    value.as_i64().and_then(|v| u64::try_from(v).ok())
}

fn convert_frame_plan(plan: v1::FrameRenderPlan) -> v2::FrameRenderPlan {
    v2::FrameRenderPlan {
        schema_version: plan.schema_version,
        camera: plan.camera.map(convert_camera),
        scale_factor: plan.scale_factor,
        locale_tag: plan.locale_tag,
        tasks: plan
            .tasks
            .into_iter()
            .map(|task| {
                let payload = if task.element_type == V1ElementType::Unknown as i32 {
                    convert_raw_payload(task.payload)
                } else {
                    convert_element_payload(task.element_type, task.payload)
                };
                v2::FrameTask {
                    kind: task.kind,
                    element_id: task.element_id,
                    element_type: task.element_type,
                    payload: Some(payload),
                }
            })
            .collect(),
    }
}

#[cfg(test)]
mod tests {
    use engine_proto::engine_command::Payload as V1CommandPayload;
    use engine_proto::{
        CreateElementCommand, DrawPoint, ElementType, EngineCommand, EngineCommandKind,
        StartTextEditCommand, UpdateTextEditCommand,
    };

    use super::*;

    #[test]
    fn init_ack_is_emitted_first() {
        let mut engine = EngineV2::from_init_request(v2::default_init_request());
        let first = engine.poll_output().expect("init output");
        assert!(matches!(first.payload, Some(V2OutputPayload::InitAck(_))));
    }

    #[test]
    fn command_input_emits_snapshot() {
        let mut engine = EngineV2::from_init_request(v2::default_init_request());
        let _ = engine.poll_output();

        let command = EngineCommand {
            kind: EngineCommandKind::CreateElement as i32,
            payload: Some(V1CommandPayload::CreateElement(CreateElementCommand {
                element_type: ElementType::Rectangle as i32,
                element_id: "v2-rect".to_string(),
                position: Some(DrawPoint {
                    x: 12.0,
                    y: 16.0,
                    pressure: 0.0,
                    timestamp_us: 0,
                }),
                initial_payload: Vec::new(),
                maintain_aspect_ratio: false,
                create_from_center: false,
                snap_override: false,
            })),
        };

        let input = v2::EngineInput {
            sequence: 1,
            payload: Some(V2InputPayload::CommandEvent(v2::CommandEvent {
                command_bytes: v1::encode_message(&command),
            })),
        };

        engine.process_input(input).expect("process input");

        let mut saw_snapshot = false;
        while let Some(output) = engine.poll_output() {
            if matches!(output.payload, Some(V2OutputPayload::Snapshot(_))) {
                saw_snapshot = true;
                break;
            }
        }
        assert!(saw_snapshot);
    }

    #[test]
    fn pointer_input_emits_typed_host_request() {
        let mut engine = EngineV2::from_init_request(v2::default_init_request());
        let _ = engine.poll_output();

        engine
            .process_input(v2::EngineInput {
                sequence: 42,
                payload: Some(V2InputPayload::PointerEvent(v2::PointerEvent {
                    pointer_id: 7,
                    phase: v2::PointerPhase::Move as i32,
                    position: Some(v2::DrawPoint {
                        x: 10.0,
                        y: 20.0,
                        pressure: 0.0,
                        timestamp_us: 0,
                    }),
                    buttons: 1,
                    modifiers: 0,
                })),
            })
            .expect("process pointer");

        let output = engine.poll_output().expect("host request output");
        match output.payload {
            Some(V2OutputPayload::HostRequest(request)) => {
                assert_eq!(request.request_id, 42);
                assert!(matches!(
                    request.payload,
                    Some(v2::host_request::Payload::PointerHostRequest(_))
                ));
            }
            _ => panic!("expected host request output"),
        }
    }

    #[test]
    fn update_text_edit_emits_text_metrics_host_request() {
        let mut engine = EngineV2::from_init_request(v2::default_init_request());
        let _ = engine.poll_output();

        let start = EngineCommand {
            kind: EngineCommandKind::StartTextEdit as i32,
            payload: Some(V1CommandPayload::StartTextEdit(StartTextEditCommand {
                element_id: String::new(),
                position: Some(DrawPoint {
                    x: 10.0,
                    y: 20.0,
                    pressure: 0.0,
                    timestamp_us: 0,
                }),
            })),
        };
        engine
            .process_input(v2::EngineInput {
                sequence: 1,
                payload: Some(V2InputPayload::CommandEvent(v2::CommandEvent {
                    command_bytes: v1::encode_message(&start),
                })),
            })
            .expect("start text edit");
        while engine.poll_output().is_some() {}

        let update = EngineCommand {
            kind: EngineCommandKind::UpdateTextEdit as i32,
            payload: Some(V1CommandPayload::UpdateTextEdit(UpdateTextEditCommand {
                text: "metrics".to_string(),
                rect: None,
            })),
        };
        engine
            .process_input(v2::EngineInput {
                sequence: 2,
                payload: Some(V2InputPayload::CommandEvent(v2::CommandEvent {
                    command_bytes: v1::encode_message(&update),
                })),
            })
            .expect("update text edit");

        let mut found_request: Option<(u64, v2::TextMetricsRequest)> = None;
        while let Some(output) = engine.poll_output() {
            let Some(V2OutputPayload::HostRequest(request)) = output.payload else {
                continue;
            };
            if let Some(v2::host_request::Payload::TextMetricsRequest(payload)) = request.payload {
                found_request = Some((request.request_id, payload));
            }
        }

        let (request_id, request) = found_request.expect("text metrics host request");
        assert!(request_id > 0);
        assert_eq!(request.text, "metrics");
        assert!((request.font_size - 21.0).abs() < 1e-9);
        assert!((request.max_width - 160.0).abs() < 1e-9);
    }

    #[test]
    fn text_metrics_response_updates_snapshot_layout() {
        let mut engine = EngineV2::from_init_request(v2::default_init_request());
        let _ = engine.poll_output();

        let start = EngineCommand {
            kind: EngineCommandKind::StartTextEdit as i32,
            payload: Some(V1CommandPayload::StartTextEdit(StartTextEditCommand {
                element_id: String::new(),
                position: Some(DrawPoint {
                    x: 24.0,
                    y: 36.0,
                    pressure: 0.0,
                    timestamp_us: 0,
                }),
            })),
        };
        engine
            .process_input(v2::EngineInput {
                sequence: 10,
                payload: Some(V2InputPayload::CommandEvent(v2::CommandEvent {
                    command_bytes: v1::encode_message(&start),
                })),
            })
            .expect("start text edit");

        let mut edited_id = String::new();
        while let Some(output) = engine.poll_output() {
            if let Some(V2OutputPayload::Snapshot(snapshot)) = output.payload {
                edited_id = snapshot.selected_ids.first().cloned().unwrap_or_default();
            }
        }
        assert!(!edited_id.is_empty());

        let update = EngineCommand {
            kind: EngineCommandKind::UpdateTextEdit as i32,
            payload: Some(V1CommandPayload::UpdateTextEdit(UpdateTextEditCommand {
                text: "hello-v2".to_string(),
                rect: None,
            })),
        };
        engine
            .process_input(v2::EngineInput {
                sequence: 11,
                payload: Some(V2InputPayload::CommandEvent(v2::CommandEvent {
                    command_bytes: v1::encode_message(&update),
                })),
            })
            .expect("update text edit");

        let mut request_id = None;
        while let Some(output) = engine.poll_output() {
            let Some(V2OutputPayload::HostRequest(request)) = output.payload else {
                continue;
            };
            if matches!(
                request.payload,
                Some(v2::host_request::Payload::TextMetricsRequest(_))
            ) {
                request_id = Some(request.request_id);
            }
        }
        let request_id = request_id.expect("request id");

        engine
            .process_input(v2::EngineInput {
                sequence: 12,
                payload: Some(V2InputPayload::TextMetricsResponse(
                    v2::TextMetricsResponse {
                        request_id,
                        ok: true,
                        metrics: Some(v2::TextMetricsResult {
                            width: 88.0,
                            height: 24.0,
                            line_height: 24.0,
                            lines: vec![v2::TextMetricsLine {
                                width: 88.0,
                                height: 24.0,
                            }],
                        }),
                        error: None,
                    },
                )),
            })
            .expect("text metrics response");

        let mut snapshot_after_response = None;
        while let Some(output) = engine.poll_output() {
            if let Some(V2OutputPayload::Snapshot(snapshot)) = output.payload {
                snapshot_after_response = Some(snapshot);
            }
        }

        let snapshot = snapshot_after_response.expect("snapshot after response");
        let text = snapshot
            .elements
            .iter()
            .find(|element| element.id == edited_id)
            .expect("text element in snapshot");
        let rect = text.rect.as_ref().expect("text rect");
        assert!(((rect.max_x - rect.min_x) - 88.0).abs() < 1e-9);
        assert!(((rect.max_y - rect.min_y) - 24.0).abs() < 1e-9);
    }
}
