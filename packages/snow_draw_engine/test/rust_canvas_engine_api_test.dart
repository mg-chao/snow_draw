import 'package:snow_draw_engine/rust_canvas_engine.dart';
import 'package:test/test.dart';

void main() {
  test('exports RustCanvasEngine API surface', () {
    expect(RustCanvasEngine.create, isA<Function>());
  });

  test('RustCanvasEngineException has readable toString', () {
    const exception = RustCanvasEngineException(
      'native failure',
      statusCode: 4,
    );
    expect(exception.toString(), contains('native failure'));
    expect(exception.toString(), contains('statusCode: 4'));
  });
}
