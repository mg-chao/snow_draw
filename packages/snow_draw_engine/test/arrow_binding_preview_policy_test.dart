import 'package:snow_draw_engine/draw/config/draw_config.dart';
import 'package:snow_draw_engine/draw/elements/types/arrow/arrow_binding_snapper.dart';
import 'package:snow_draw_engine/draw/input/policies/arrow_binding_preview_policy.dart';
import 'package:snow_draw_engine/draw/utils/snapping_mode.dart';
import 'package:test/test.dart';

void main() {
  group('shouldPreviewArrowBinding', () {
    test('stays aligned with shared arrow binding snapper policy', () {
      const configs = <SnapConfig>[
        SnapConfig(enableArrowBinding: false),
        SnapConfig(),
        SnapConfig(enabled: true),
      ];

      for (final config in configs) {
        for (final mode in SnappingMode.values) {
          final policyResult = shouldPreviewArrowBinding(
            snapConfig: config,
            snappingMode: mode,
          );
          final sharedResult = ArrowBindingSnapper.shouldAttemptBinding(
            snapConfig: config,
            snappingMode: mode,
          );
          expect(
            policyResult,
            sharedResult,
            reason:
                'Expected preview policy to match shared snapper policy '
                '(enabled: ${config.enabled}, '
                'binding: ${config.enableArrowBinding}, mode: $mode)',
          );
        }
      }
    });
  });
}
