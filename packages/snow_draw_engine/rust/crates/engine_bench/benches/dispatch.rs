use criterion::{criterion_group, criterion_main, Criterion};
use engine_core::Engine;
use engine_proto::engine_command::Payload;
use engine_proto::{
    encode_message, CreateElementCommand, DrawPoint, ElementType, EngineCommand, EngineCommandKind,
};

fn bench_dispatch_create(c: &mut Criterion) {
    let command = EngineCommand {
        kind: EngineCommandKind::CreateElement as i32,
        payload: Some(Payload::CreateElement(CreateElementCommand {
            element_type: ElementType::Rectangle as i32,
            element_id: "bench-element".to_string(),
            position: Some(DrawPoint {
                x: 32.0,
                y: 64.0,
                pressure: 0.0,
                timestamp_us: 0,
            }),
            initial_payload: Vec::new(),
        })),
    };
    let encoded = encode_message(&command);

    c.bench_function("dispatch_create_element", |b| {
        b.iter(|| {
            let mut engine = Engine::default();
            let _ = engine.dispatch_bytes(&encoded);
        });
    });
}

criterion_group!(dispatch_benches, bench_dispatch_create);
criterion_main!(dispatch_benches);
