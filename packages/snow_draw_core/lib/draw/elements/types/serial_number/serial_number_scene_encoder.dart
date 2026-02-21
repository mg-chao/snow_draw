import 'dart:math' as math;
import 'dart:ui' as ui;

import '../../../config/draw_config.dart';
import '../../../models/element_state.dart';
import '../../../render/scene/render_scene.dart';
import '../../../types/draw_point.dart';
import '../../../types/draw_rect.dart';
import '../../../types/element_style.dart';
import '../../core/element_scene_encoder.dart';
import 'serial_number_data.dart';
import 'serial_number_layout.dart';

/// Encodes serial-number elements into backend-agnostic scene primitives.
///
/// Supports all current serial-number fill/stroke styles.
final class SerialNumberSceneEncoder
    implements ElementSceneEncoder<SerialNumberData> {
  /// Creates a serial-number scene encoder.
  const SerialNumberSceneEncoder();

  static const _kappa = 0.5522847498307936;
  static const _scaleTolerance = 0.0001;
  static const double _lineFillAngle = -math.pi / 4;
  static const _lineToSpacingRatio = 4.0;

  @override
  RenderScene encodeScene({
    required ElementState element,
    required double scaleFactor,
    String? localeTag,
  }) {
    assert(scaleFactor.isFinite, 'scaleFactor must be finite.');
    assert(
      localeTag == null || localeTag.isNotEmpty,
      'localeTag must be null or non-empty.',
    );

    final data = element.data;
    if (data is! SerialNumberData) {
      throw StateError(
        'SerialNumberSceneEncoder can only encode SerialNumberData (got '
        '${data.runtimeType})',
      );
    }

    final fillColorArgb = _applyElementOpacity(
      argb: data.fillColor.toARGB32(),
      elementOpacity: element.opacity,
    );
    final contentColorArgb = _applyElementOpacity(
      argb: data.color.toARGB32(),
      elementOpacity: element.opacity,
    );
    final shouldFill = _alphaOf(fillColorArgb) > 0;
    final shouldRenderContent = _alphaOf(contentColorArgb) > 0;
    if (!shouldFill && !shouldRenderContent) {
      return const RenderScene(primitives: <RenderPrimitive>[]);
    }
    final strokeWidth = resolveSerialNumberStrokeWidth(data: data);
    final shouldStroke = shouldRenderContent && strokeWidth > 0;

    final diameter = math.min(element.rect.width, element.rect.height);
    if (diameter <= 0 || !diameter.isFinite) {
      return const RenderScene(primitives: <RenderPrimitive>[]);
    }
    final radius = diameter / 2;
    final circlePath = _buildCirclePath(radius: radius);

    final localScene = SceneBuilder();
    if (shouldFill) {
      if (data.fillStyle == FillStyle.solid) {
        localScene.addPathFill(path: circlePath, colorArgb: fillColorArgb);
      } else {
        final hatch = _resolveHatchStyle(fontSize: data.fontSize);
        localScene.addHatchPathFill(
          path: circlePath,
          clipBounds: _localClipBounds(radius),
          colorArgb: fillColorArgb,
          lineWidth: hatch.lineWidth,
          spacing: hatch.spacing,
          angleRadians: _lineFillAngle,
          pattern: data.fillStyle == FillStyle.crossLine
              ? RenderHatchPattern.crossLine
              : RenderHatchPattern.line,
        );
      }
    }
    if (shouldStroke) {
      localScene.addPathStroke(
        path: circlePath,
        colorArgb: contentColorArgb,
        strokeWidth: strokeWidth,
        strokeCap: _strokeCapFor(data.strokeStyle),
        dashPattern: _dashPatternFor(
          strokeStyle: data.strokeStyle,
          strokeWidth: strokeWidth,
        ),
      );
    }
    if (shouldRenderContent) {
      final textLayout = layoutSerialNumberText(
        data: data,
        colorOverride: ui.Color(contentColorArgb),
        locale: _resolveLocale(localeTag),
      );
      final paintScale = textLayout.paintScale;
      if (paintScale > 0 && paintScale.isFinite) {
        final visualCenter =
            textLayout.visualBounds?.center ??
            ui.Offset(textLayout.size.width / 2, textLayout.size.height / 2);
        final localTextOrigin = DrawPoint(
          x: -visualCenter.dx / paintScale,
          y: -visualCenter.dy / paintScale,
        );
        final textRunScene = SceneBuilder()
          ..addTextRun(
            text: data.number.toString(),
            origin: localTextOrigin,
            fontSize: ConfigDefaults.defaultSerialNumberFontSize,
            colorArgb: contentColorArgb,
            fontFamily: data.fontFamily,
          );
        if ((paintScale - 1).abs() <= _scaleTolerance) {
          localScene.addPrimitive(textRunScene.build().primitives.single);
        } else {
          localScene.addTransform(
            child: textRunScene.build(),
            scaleX: paintScale,
            scaleY: paintScale,
          );
        }
      }
    }

    final sceneBuilder = SceneBuilder()
      ..addTransform(
        child: localScene.build(),
        translate: element.center,
        rotation: element.rotation,
      );
    return sceneBuilder.build(cullRect: element.rect);
  }

  static int _alphaOf(int argb) => (argb >>> 24) & 0xFF;

  static int _applyElementOpacity({
    required int argb,
    required double elementOpacity,
  }) {
    final baseAlpha = (argb >>> 24) & 0xFF;
    final scaledAlpha = (baseAlpha * elementOpacity.clamp(0.0, 1.0))
        .round()
        .clamp(0, 255);
    return (scaledAlpha << 24) | (argb & 0x00FFFFFF);
  }

  static List<double>? _dashPatternFor({
    required StrokeStyle strokeStyle,
    required double strokeWidth,
  }) => switch (strokeStyle) {
    StrokeStyle.solid => null,
    StrokeStyle.dashed => <double>[strokeWidth * 2.0, strokeWidth * 2.0 * 1.2],
    StrokeStyle.dotted => <double>[
      (strokeWidth * 0.01).clamp(0.01, double.infinity),
      (strokeWidth * 2.0).clamp(0.01, double.infinity),
    ],
  };

  static RenderStrokeCap _strokeCapFor(StrokeStyle strokeStyle) =>
      strokeStyle == StrokeStyle.solid
      ? RenderStrokeCap.butt
      : RenderStrokeCap.round;

  static DrawRect _localClipBounds(double radius) =>
      DrawRect(minX: -radius, minY: -radius, maxX: radius, maxY: radius);

  static ({double lineWidth, double spacing}) _resolveHatchStyle({
    required double fontSize,
  }) {
    final equivalentStrokeWidth = fontSize / 42;
    final lineWidth = (1 + (equivalentStrokeWidth - 1) * 0.6).clamp(0.5, 3.0);
    final spacing = (lineWidth * _lineToSpacingRatio).clamp(3.0, 18.0);
    return (lineWidth: lineWidth, spacing: spacing);
  }

  static RenderPath _buildCirclePath({required double radius}) {
    final control = radius * _kappa;
    return RenderPath(<RenderPathCommand>[
      RenderMoveTo(DrawPoint(x: radius, y: 0)),
      RenderCubicTo(
        control1: DrawPoint(x: radius, y: control),
        control2: DrawPoint(x: control, y: radius),
        end: DrawPoint(x: 0, y: radius),
      ),
      RenderCubicTo(
        control1: DrawPoint(x: -control, y: radius),
        control2: DrawPoint(x: -radius, y: control),
        end: DrawPoint(x: -radius, y: 0),
      ),
      RenderCubicTo(
        control1: DrawPoint(x: -radius, y: -control),
        control2: DrawPoint(x: -control, y: -radius),
        end: DrawPoint(x: 0, y: -radius),
      ),
      RenderCubicTo(
        control1: DrawPoint(x: control, y: -radius),
        control2: DrawPoint(x: radius, y: -control),
        end: DrawPoint(x: radius, y: 0),
      ),
      const RenderClosePath(),
    ]);
  }

  static ui.Locale? _resolveLocale(String? localeTag) {
    if (localeTag == null || localeTag.isEmpty) {
      return null;
    }
    final parts = localeTag
        .split(RegExp('[-_]'))
        .where((part) => part.isNotEmpty)
        .toList(growable: false);
    if (parts.isEmpty) {
      return null;
    }

    final languageCode = parts.first.toLowerCase();
    if (!RegExp(r'^[a-z]{2,8}$').hasMatch(languageCode)) {
      return null;
    }
    String? scriptCode;
    String? countryCode;
    for (final part in parts.skip(1)) {
      if (scriptCode == null && part.length == 4) {
        final normalizedScript =
            '${part[0].toUpperCase()}${part.substring(1).toLowerCase()}';
        if (!RegExp(r'^[A-Z][a-z]{3}$').hasMatch(normalizedScript)) {
          return null;
        }
        scriptCode = normalizedScript;
        continue;
      }
      if (countryCode == null && (part.length == 2 || part.length == 3)) {
        final normalizedCountry = part.toUpperCase();
        if (!RegExp(r'^[A-Z]{2}$|^\d{3}$').hasMatch(normalizedCountry)) {
          return null;
        }
        countryCode = normalizedCountry;
      }
    }

    return ui.Locale.fromSubtags(
      languageCode: languageCode,
      scriptCode: scriptCode,
      countryCode: countryCode,
    );
  }
}
