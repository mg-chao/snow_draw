import 'package:snow_draw_engine/draw/elements/types/arrow/arrow_binding.dart';
import 'package:test/test.dart';

void main() {
  group('ArrowBinding fixed-point normalization', () {
    test('nudges 0.5 fixed-point ratios away from center', () {
      final binding = ArrowBinding.fromJson(<String, dynamic>{
        'elementId': 'target-1',
        'anchor': <String, dynamic>{'x': 0.5, 'y': 0.5},
        'mode': ArrowBindingMode.orbit.name,
      });

      expect(binding.anchor.x, closeTo(0.5001, 1e-12));
      expect(binding.anchor.y, closeTo(0.5001, 1e-12));
    });

    test('falls back both ratios when any coordinate is non-finite', () {
      final binding = ArrowBinding.fromJson(<String, dynamic>{
        'elementId': 'target-2',
        'anchor': <String, dynamic>{'x': double.infinity, 'y': 0.75},
        'mode': ArrowBindingMode.inside.name,
      });

      expect(binding.anchor.x, closeTo(0.5001, 1e-12));
      expect(binding.anchor.y, closeTo(0.5001, 1e-12));
    });
  });
}
