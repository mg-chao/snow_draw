use std::fs;
use std::path::{Path, PathBuf};

use engine_core::Engine;
use engine_proto::engine_command::Payload as CommandPayload;
use engine_proto::{
    default_engine_config, CreateElementCommand, DeleteElementsCommand, DrawPoint, ElementType,
    EngineCommand, EngineCommandKind, EngineEventKind, FramePlanRequest, FrameTaskKind,
    MoveCameraCommand, SelectElementCommand, UpdateElementsStyleCommand, ZoomCameraCommand,
};
use serde::Deserialize;

#[derive(Debug, Default, Deserialize)]
struct CorpusConfig {
    locale_tag: Option<String>,
    scale_factor: Option<f64>,
    deterministic_seed: Option<u64>,
}

#[derive(Debug, Default, Deserialize)]
struct FramePlanRequestInput {
    locale_tag: Option<String>,
    scale_factor: Option<f64>,
}

#[derive(Debug, Deserialize)]
struct ExpectedElement {
    id: String,
    element_type: String,
    z_index: i32,
}

#[derive(Debug, Default, Deserialize)]
struct CorpusExpected {
    #[serde(default)]
    document_version: u64,
    #[serde(default)]
    selection_version: u64,
    #[serde(default)]
    selected_ids: Vec<String>,
    #[serde(default)]
    elements: Vec<ExpectedElement>,
    #[serde(default)]
    history_undo_len: u64,
    #[serde(default)]
    history_redo_len: u64,
    #[serde(default)]
    frame_task_kinds: Vec<String>,
    #[serde(default)]
    event_kinds: Vec<String>,
}

#[derive(Debug, Deserialize)]
#[serde(tag = "type", rename_all = "snake_case")]
enum CorpusCommand {
    CreateElement {
        element_type: String,
        #[serde(default)]
        element_id: Option<String>,
        #[serde(default)]
        x: Option<f64>,
        #[serde(default)]
        y: Option<f64>,
        #[serde(default)]
        payload_hex: Option<String>,
    },
    SelectElement {
        element_id: String,
        #[serde(default)]
        add_to_selection: bool,
    },
    ClearSelection,
    SelectAll,
    DeleteElements {
        element_ids: Vec<String>,
    },
    UpdateElementsStyle {
        element_ids: Vec<String>,
        payload_hex: String,
    },
    MoveCamera {
        dx: f64,
        dy: f64,
    },
    ZoomCamera {
        scale: f64,
    },
    Undo,
    Redo,
    ClearHistory,
}

#[derive(Debug, Deserialize)]
struct CorpusCase {
    name: String,
    #[serde(default)]
    config: CorpusConfig,
    #[serde(default)]
    frame_plan_request: FramePlanRequestInput,
    commands: Vec<CorpusCommand>,
    expected: CorpusExpected,
}

#[test]
fn parity_corpus_traces_match_expected_outputs() {
    let mut files = fs::read_dir(corpus_dir())
        .expect("read parity corpus directory")
        .filter_map(Result::ok)
        .map(|entry| entry.path())
        .filter(|path| path.extension().is_some_and(|ext| ext == "json"))
        .collect::<Vec<_>>();
    files.sort();

    assert!(!files.is_empty(), "parity corpus is empty");

    for file in files {
        run_case(&file);
    }
}

fn run_case(path: &Path) {
    let json = fs::read_to_string(path).expect("read corpus case");
    let case: CorpusCase = serde_json::from_str(&json).expect("parse corpus case");

    let mut config = default_engine_config();
    if let Some(locale_tag) = case.config.locale_tag {
        config.locale_tag = locale_tag;
    }
    if let Some(scale_factor) = case.config.scale_factor {
        config.scale_factor = scale_factor;
    }
    if let Some(deterministic_seed) = case.config.deterministic_seed {
        config.deterministic_seed = deterministic_seed;
    }

    let mut engine = Engine::new(config);

    for command in case.commands {
        let command = to_engine_command(command);
        engine
            .dispatch(command)
            .unwrap_or_else(|err| panic!("{}: dispatch failed: {err}", case.name));
    }

    let snapshot = engine.get_snapshot();
    assert_eq!(
        snapshot.document_version, case.expected.document_version,
        "{}: document version mismatch",
        case.name
    );
    assert_eq!(
        snapshot.selection_version, case.expected.selection_version,
        "{}: selection version mismatch",
        case.name
    );
    assert_eq!(
        snapshot.selected_ids, case.expected.selected_ids,
        "{}: selected IDs mismatch",
        case.name
    );
    assert_eq!(
        snapshot.history_undo_len, case.expected.history_undo_len,
        "{}: undo history length mismatch",
        case.name
    );
    assert_eq!(
        snapshot.history_redo_len, case.expected.history_redo_len,
        "{}: redo history length mismatch",
        case.name
    );

    let mut expected_elements = case.expected.elements;
    expected_elements.sort_by(|a, b| a.id.cmp(&b.id));

    let mut actual_elements = snapshot.elements.clone();
    actual_elements.sort_by(|a, b| a.id.cmp(&b.id));

    assert_eq!(
        actual_elements.len(),
        expected_elements.len(),
        "{}: element count mismatch",
        case.name
    );

    for (actual, expected) in actual_elements.iter().zip(expected_elements.iter()) {
        assert_eq!(actual.id, expected.id, "{}: element ID mismatch", case.name);
        assert_eq!(
            element_type_name(actual.element_type),
            expected.element_type,
            "{}: element type mismatch for {}",
            case.name,
            expected.id
        );
        assert_eq!(
            actual.z_index, expected.z_index,
            "{}: z-index mismatch for {}",
            case.name, expected.id
        );
    }

    let plan = engine.build_frame_plan(FramePlanRequest {
        viewport: None,
        locale_tag: case.frame_plan_request.locale_tag.unwrap_or_default(),
        scale_factor: case.frame_plan_request.scale_factor.unwrap_or(0.0),
    });
    let actual_task_kinds = plan
        .tasks
        .iter()
        .map(|task| frame_task_kind_name(task.kind))
        .collect::<Vec<_>>();
    assert_eq!(
        actual_task_kinds, case.expected.frame_task_kinds,
        "{}: frame task kinds mismatch",
        case.name
    );

    let mut event_kinds = Vec::new();
    while let Some(event) = engine.poll_event() {
        event_kinds.push(event_kind_name(event.kind));
    }
    assert_eq!(
        event_kinds, case.expected.event_kinds,
        "{}: event sequence mismatch",
        case.name
    );
}

fn to_engine_command(command: CorpusCommand) -> EngineCommand {
    match command {
        CorpusCommand::CreateElement {
            element_type,
            element_id,
            x,
            y,
            payload_hex,
        } => EngineCommand {
            kind: EngineCommandKind::CreateElement as i32,
            payload: Some(CommandPayload::CreateElement(CreateElementCommand {
                element_type: parse_element_type(&element_type) as i32,
                element_id: element_id.unwrap_or_default(),
                position: match (x, y) {
                    (Some(x), Some(y)) => Some(DrawPoint {
                        x,
                        y,
                        pressure: 0.0,
                        timestamp_us: 0,
                    }),
                    _ => None,
                },
                initial_payload: payload_hex.map_or_else(Vec::new, |hex| parse_hex(&hex)),
            })),
        },
        CorpusCommand::SelectElement {
            element_id,
            add_to_selection,
        } => EngineCommand {
            kind: EngineCommandKind::SelectElement as i32,
            payload: Some(CommandPayload::SelectElement(SelectElementCommand {
                element_id,
                add_to_selection,
                position: None,
            })),
        },
        CorpusCommand::ClearSelection => EngineCommand {
            kind: EngineCommandKind::ClearSelection as i32,
            payload: None,
        },
        CorpusCommand::SelectAll => EngineCommand {
            kind: EngineCommandKind::SelectAll as i32,
            payload: None,
        },
        CorpusCommand::DeleteElements { element_ids } => EngineCommand {
            kind: EngineCommandKind::DeleteElements as i32,
            payload: Some(CommandPayload::DeleteElements(DeleteElementsCommand {
                element_ids,
            })),
        },
        CorpusCommand::UpdateElementsStyle {
            element_ids,
            payload_hex,
        } => EngineCommand {
            kind: EngineCommandKind::UpdateElementsStyle as i32,
            payload: Some(CommandPayload::UpdateElementsStyle(
                UpdateElementsStyleCommand {
                    element_ids,
                    style_payload: parse_hex(&payload_hex),
                },
            )),
        },
        CorpusCommand::MoveCamera { dx, dy } => EngineCommand {
            kind: EngineCommandKind::MoveCamera as i32,
            payload: Some(CommandPayload::MoveCamera(MoveCameraCommand { dx, dy })),
        },
        CorpusCommand::ZoomCamera { scale } => EngineCommand {
            kind: EngineCommandKind::ZoomCamera as i32,
            payload: Some(CommandPayload::ZoomCamera(ZoomCameraCommand {
                scale,
                center: None,
            })),
        },
        CorpusCommand::Undo => EngineCommand {
            kind: EngineCommandKind::Undo as i32,
            payload: None,
        },
        CorpusCommand::Redo => EngineCommand {
            kind: EngineCommandKind::Redo as i32,
            payload: None,
        },
        CorpusCommand::ClearHistory => EngineCommand {
            kind: EngineCommandKind::ClearHistory as i32,
            payload: None,
        },
    }
}

fn parse_element_type(value: &str) -> ElementType {
    match value {
        "rectangle" => ElementType::Rectangle,
        "arrow" => ElementType::Arrow,
        "line" => ElementType::Line,
        "free_draw" => ElementType::FreeDraw,
        "filter" => ElementType::Filter,
        "highlight" => ElementType::Highlight,
        "text" => ElementType::Text,
        "serial_number" => ElementType::SerialNumber,
        _ => ElementType::Unknown,
    }
}

fn element_type_name(value: i32) -> String {
    match ElementType::try_from(value).unwrap_or(ElementType::Unknown) {
        ElementType::Unknown => "unknown",
        ElementType::Rectangle => "rectangle",
        ElementType::Arrow => "arrow",
        ElementType::Line => "line",
        ElementType::FreeDraw => "free_draw",
        ElementType::Filter => "filter",
        ElementType::Highlight => "highlight",
        ElementType::Text => "text",
        ElementType::SerialNumber => "serial_number",
    }
    .to_string()
}

fn frame_task_kind_name(value: i32) -> String {
    match FrameTaskKind::try_from(value).unwrap_or(FrameTaskKind::Unknown) {
        FrameTaskKind::Unknown => "unknown",
        FrameTaskKind::Rectangle => "rectangle",
        FrameTaskKind::Line => "line",
        FrameTaskKind::Arrow => "arrow",
        FrameTaskKind::FreeDraw => "free_draw",
        FrameTaskKind::Text => "text",
        FrameTaskKind::SerialNumber => "serial_number",
        FrameTaskKind::Highlight => "highlight",
        FrameTaskKind::Filter => "filter",
        FrameTaskKind::Background => "background",
        FrameTaskKind::Grid => "grid",
        FrameTaskKind::SelectionOutline => "selection_outline",
        FrameTaskKind::SelectionControls => "selection_controls",
        FrameTaskKind::ArrowPointOverlay => "arrow_point_overlay",
        FrameTaskKind::ArrowBindingHighlight => "arrow_binding_highlight",
        FrameTaskKind::HoverOutline => "hover_outline",
        FrameTaskKind::SnapGuides => "snap_guides",
        FrameTaskKind::BoxSelection => "box_selection",
        FrameTaskKind::HighlightMask => "highlight_mask",
        FrameTaskKind::Watermark => "watermark",
    }
    .to_string()
}

fn event_kind_name(value: i32) -> String {
    match EngineEventKind::try_from(value).unwrap_or(EngineEventKind::Unknown) {
        EngineEventKind::Unknown => "unknown",
        EngineEventKind::StateChanged => "state_changed",
        EngineEventKind::ValidationFailed => "validation_failed",
        EngineEventKind::Error => "error",
        EngineEventKind::HistoryChanged => "history_changed",
        EngineEventKind::Debug => "debug",
    }
    .to_string()
}

fn parse_hex(value: &str) -> Vec<u8> {
    let raw = value.trim_start_matches("0x").trim();
    if raw.is_empty() {
        return Vec::new();
    }

    let normalized = if raw.len() % 2 == 0 {
        raw.to_string()
    } else {
        format!("0{raw}")
    };

    (0..normalized.len())
        .step_by(2)
        .map(|idx| u8::from_str_radix(&normalized[idx..idx + 2], 16).expect("valid hex payload"))
        .collect()
}

fn corpus_dir() -> PathBuf {
    PathBuf::from(env!("CARGO_MANIFEST_DIR")).join("../../parity/corpus")
}
