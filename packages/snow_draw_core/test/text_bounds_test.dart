import 'dart:math' as math;

import 'package:test/test.dart';
import 'package:snow_draw_core/draw/elements/types/text/text_bounds.dart';
import 'package:snow_draw_core/draw/elements/types/text/text_data.dart';
import 'package:snow_draw_core/draw/services/text/text_metrics_service.dart';
import 'package:snow_draw_core/draw/types/draw_point.dart';
import 'package:snow_draw_core/draw/types/draw_rect.dart';

void main() {
  test(
    'fitTextFontSizeToHeight scales up for tall targets with low iterations',
    () {
      const data = TextData(text: 'N', fontSize: 36);

      final fittedFontSize = fitTextFontSizeToHeight(
        data: data,
        targetHeight: 860,
        maxWidth: 420,
        maxIterations: 2,
      );
      final fittedHeight = resolveTextLayoutHeight(
        defaultTextMetricsService.measure(
          TextLayoutRequest(
            data: data.copyWith(fontSize: fittedFontSize),
            maxWidth: 420,
          ),
        ),
      );

      expect(fittedFontSize, greaterThan(200));
      expect(fittedHeight, greaterThan(200));
    },
  );

  test('fitTextFontSizeToHeight sanitizes non-finite source font sizes', () {
    const infData = TextData(text: 'A', fontSize: double.infinity);
    const nanData = TextData(text: 'A', fontSize: double.nan);

    final fittedFromInf = fitTextFontSizeToHeight(
      data: infData,
      targetHeight: 80,
      maxWidth: 200,
    );
    final fittedFromNan = fitTextFontSizeToHeight(
      data: nanData,
      targetHeight: 80,
      maxWidth: 200,
    );

    expect(fittedFromInf.isFinite, isTrue);
    expect(fittedFromInf, greaterThan(0));
    expect(fittedFromNan.isFinite, isTrue);
    expect(fittedFromNan, greaterThan(0));
  });

  test(
    'clampTextRectToLayout keeps left edge fixed for left-anchored clamps',
    () {
      const data = TextData(text: 'Long text for minimum width');
      const rect = DrawRect(minX: 10, minY: 20, maxX: 11, maxY: 28);
      const startRect = DrawRect(minX: 10, minY: 20, maxX: 11, maxY: 28);
      const anchor = DrawPoint(x: 5, y: 0);

      final clamped = clampTextRectToLayout(
        rect: rect,
        startRect: startRect,
        anchor: anchor,
        data: data,
      );

      expect(clamped.minX, rect.minX);
      expect(clamped.width, greaterThan(rect.width));
      expect(clamped.minY, rect.minY);
    },
  );

  test('clampTextRectToLayout uses the provided text metrics service', () {
    const data = TextData(text: '中文中文中文中文', fontSize: 20);
    const rect = DrawRect(minX: 0, minY: 0, maxX: 20, maxY: 24);
    const startRect = rect;
    const anchor = DrawPoint(x: 0, y: 0);

    final fallbackClamped = clampTextRectToLayout(
      rect: rect,
      startRect: startRect,
      anchor: anchor,
      data: data,
    );
    final customClamped = clampTextRectToLayout(
      rect: rect,
      startRect: startRect,
      anchor: anchor,
      data: data,
      textMetricsService: const _WideGlyphTextMetricsService(),
    );

    expect(customClamped.height, greaterThan(fallbackClamped.height));
  });
}

final class _WideGlyphTextMetricsService implements TextMetricsService {
  const _WideGlyphTextMetricsService();

  @override
  TextMetrics measure(TextLayoutRequest request) {
    final fontSize =
        request.data.fontSize <= 0 || !request.data.fontSize.isFinite
        ? 14.0
        : request.data.fontSize;
    final text = request.data.text.isEmpty ? ' ' : request.data.text;
    final maxWidth = request.maxWidth <= 0 || !request.maxWidth.isFinite
        ? 1.0
        : request.maxWidth;
    final lineHeight = fontSize * 1.2;
    final glyphWidth = fontSize;

    final lines = <TextLineMetrics>[];
    for (final logicalLine in text.split('\n')) {
      final graphemeCount = math.max(1, logicalLine.runes.length);
      final rawWidth = graphemeCount * glyphWidth;
      final wraps = math.max(1, (rawWidth / maxWidth).ceil());
      for (var i = 0; i < wraps; i++) {
        final remaining = rawWidth - (maxWidth * i);
        final lineWidth = i == wraps - 1 ? math.max(1.0, remaining) : maxWidth;
        lines.add(TextLineMetrics(width: lineWidth, height: lineHeight));
      }
    }

    var width = 0.0;
    for (final line in lines) {
      if (line.width > width) {
        width = line.width;
      }
    }

    return TextMetrics(
      width: width,
      height: lineHeight * lines.length,
      lineHeight: lineHeight,
      lines: List<TextLineMetrics>.unmodifiable(lines),
    );
  }

  @override
  void clearCaches() {}
}
