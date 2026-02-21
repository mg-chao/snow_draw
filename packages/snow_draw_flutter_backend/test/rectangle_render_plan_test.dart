import 'package:flutter_test/flutter_test.dart';
import 'package:snow_draw_core/snow_draw_core.dart';
import 'package:snow_draw_flutter_backend/render/rectangle/rectangle_render_plan.dart';

void main() {
  group('RectangleRenderPlan', () {
    test('uses solid fast path for solid styles', () {
      final plan = RectangleRenderPlan.resolve(
        data: const RectangleData(
          fillColor: DrawColor(0x3300FF00),
          color: DrawColor(0xFF0000FF),
        ),
        elementOpacity: 1,
        shaderReady: true,
      );

      expect(plan.backend, RectangleRenderBackend.solidFastPath);
      expect(plan.shouldUseSolidFastPath, isTrue);
      expect(plan.shouldUseShader, isFalse);
      expect(plan.paintFill, isTrue);
      expect(plan.paintStroke, isTrue);
    });

    test('routes patterned styles to shader when available', () {
      final plan = RectangleRenderPlan.resolve(
        data: const RectangleData(
          strokeStyle: StrokeStyle.dashed,
          fillStyle: FillStyle.line,
        ),
        elementOpacity: 1,
        shaderReady: true,
      );

      expect(plan.backend, RectangleRenderBackend.shaderPattern);
      expect(plan.shouldUseShader, isTrue);
      expect(plan.shouldUseSolidFastPath, isFalse);
    });

    test('falls back to CPU patterns when shader is unavailable', () {
      final plan = RectangleRenderPlan.resolve(
        data: const RectangleData(
          strokeStyle: StrokeStyle.dotted,
          fillStyle: FillStyle.crossLine,
        ),
        elementOpacity: 1,
        shaderReady: false,
      );

      expect(plan.backend, RectangleRenderBackend.cpuPattern);
      expect(plan.shouldUseShader, isFalse);
      expect(plan.shouldUseSolidFastPath, isFalse);
    });

    test('disables fill and stroke painting when opacity resolves to zero', () {
      final plan = RectangleRenderPlan.resolve(
        data: const RectangleData(color: DrawColor(0x00000000)),
        elementOpacity: 0,
        shaderReady: true,
      );

      expect(plan.paintFill, isFalse);
      expect(plan.paintStroke, isFalse);
      expect(plan.backend, RectangleRenderBackend.solidFastPath);
    });
  });
}
