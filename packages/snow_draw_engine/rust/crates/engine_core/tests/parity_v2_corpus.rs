use std::fs;
use std::path::{Path, PathBuf};

use engine_core::EngineV2;
use engine_proto::engine_command::Payload as CommandPayload;
use engine_proto::{
    encode_message as encode_v1, CreateElementCommand, DrawPoint, ElementType, EngineCommand,
    EngineCommandKind, SelectElementCommand,
};
use engine_proto_v2::engine_input::Payload as InputPayload;
use engine_proto_v2::engine_output::Payload as OutputPayload;
use engine_proto_v2::{
    default_init_request, CommandEvent, EngineInput, EngineOutput, EngineSnapshot,
};
use serde::Deserialize;

#[derive(Debug, Deserialize)]
struct ExpectedElement {
    id: String,
    element_type: String,
    z_index: i32,
}

#[derive(Debug, Deserialize)]
struct CorpusExpected {
    document_version: u64,
    selection_version: u64,
    selected_ids: Vec<String>,
    elements: Vec<ExpectedElement>,
    output_kinds: Vec<String>,
}

#[derive(Debug, Deserialize)]
#[serde(tag = "type", rename_all = "snake_case")]
enum CorpusCommand {
    CreateElement {
        element_type: String,
        element_id: String,
        x: f64,
        y: f64,
    },
    SelectElement {
        element_id: String,
        #[serde(default)]
        add_to_selection: bool,
    },
}

#[derive(Debug, Deserialize)]
struct CorpusCase {
    name: String,
    commands: Vec<CorpusCommand>,
    expected: CorpusExpected,
}

#[test]
fn parity_v2_corpus_matches_expected_outputs() {
    let mut files = fs::read_dir(corpus_dir())
        .expect("read parity_v2 corpus directory")
        .filter_map(Result::ok)
        .map(|entry| entry.path())
        .filter(|path| path.extension().is_some_and(|ext| ext == "json"))
        .collect::<Vec<_>>();
    files.sort();

    assert!(!files.is_empty(), "parity_v2 corpus is empty");

    for file in files {
        run_case(&file);
    }
}

fn run_case(path: &Path) {
    let json = fs::read_to_string(path).expect("read corpus case");
    let case: CorpusCase = serde_json::from_str(&json).expect("parse corpus case");

    let mut engine = EngineV2::from_init_request(default_init_request());
    let first = engine.poll_output().expect("init ack output");
    assert!(matches!(first.payload, Some(OutputPayload::InitAck(_))));

    let mut output_kinds = Vec::new();
    let mut last_snapshot: Option<EngineSnapshot> = None;

    for command in case.commands {
        let v1_command = to_v1_command(command);
        let input = EngineInput {
            sequence: 1,
            payload: Some(InputPayload::CommandEvent(CommandEvent {
                command_bytes: encode_v1(&v1_command),
            })),
        };

        engine.process_input(input).expect("process input");

        while let Some(output) = engine.poll_output() {
            collect_output(&output, &mut output_kinds, &mut last_snapshot);
        }
    }

    assert_eq!(
        output_kinds, case.expected.output_kinds,
        "{}: output kinds mismatch",
        case.name
    );

    let snapshot = last_snapshot.expect("snapshot output");
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
        snapshot.elements.len(),
        case.expected.elements.len(),
        "{}: element count mismatch",
        case.name
    );

    let mut actual = snapshot.elements.clone();
    actual.sort_by(|a, b| a.id.cmp(&b.id));

    let mut expected = case.expected.elements;
    expected.sort_by(|a, b| a.id.cmp(&b.id));

    for (a, e) in actual.iter().zip(expected.iter()) {
        assert_eq!(a.id, e.id, "{}: element id mismatch", case.name);
        assert_eq!(a.z_index, e.z_index, "{}: z-index mismatch", case.name);
        assert_eq!(
            element_type_name(a.element_type),
            e.element_type,
            "{}: element type mismatch",
            case.name
        );
    }
}

fn collect_output(
    output: &EngineOutput,
    kinds: &mut Vec<String>,
    last_snapshot: &mut Option<EngineSnapshot>,
) {
    match output.payload.as_ref() {
        Some(OutputPayload::Event(_)) => kinds.push("event".to_string()),
        Some(OutputPayload::Snapshot(snapshot)) => {
            kinds.push("snapshot".to_string());
            *last_snapshot = Some(snapshot.clone());
        }
        Some(OutputPayload::StateDelta(_)) => kinds.push("state_delta".to_string()),
        Some(OutputPayload::FramePlan(_)) => kinds.push("frame_plan".to_string()),
        Some(OutputPayload::HostRequest(_)) => kinds.push("host_request".to_string()),
        Some(OutputPayload::InitAck(_)) => kinds.push("init_ack".to_string()),
        None => kinds.push("none".to_string()),
    }
}

fn to_v1_command(command: CorpusCommand) -> EngineCommand {
    match command {
        CorpusCommand::CreateElement {
            element_type,
            element_id,
            x,
            y,
        } => EngineCommand {
            kind: EngineCommandKind::CreateElement as i32,
            payload: Some(CommandPayload::CreateElement(CreateElementCommand {
                element_type: parse_element_type(&element_type) as i32,
                element_id,
                position: Some(DrawPoint {
                    x,
                    y,
                    pressure: 0.0,
                    timestamp_us: 0,
                }),
                initial_payload: Vec::new(),
                maintain_aspect_ratio: false,
                create_from_center: false,
                snap_override: false,
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
        ElementType::Rectangle => "rectangle",
        ElementType::Arrow => "arrow",
        ElementType::Line => "line",
        ElementType::FreeDraw => "free_draw",
        ElementType::Filter => "filter",
        ElementType::Highlight => "highlight",
        ElementType::Text => "text",
        ElementType::SerialNumber => "serial_number",
        ElementType::Unknown => "unknown",
    }
    .to_string()
}

fn corpus_dir() -> PathBuf {
    PathBuf::from(env!("CARGO_MANIFEST_DIR")).join("../../parity_v2/corpus")
}
