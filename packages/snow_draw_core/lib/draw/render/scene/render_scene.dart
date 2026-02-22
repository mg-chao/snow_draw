import 'package:meta/meta.dart';

import '../../types/draw_point.dart';
import '../../types/draw_rect.dart';

/// Backend-agnostic scene composed of render primitives.
@immutable
class RenderScene {
  /// Creates a render scene.
  const RenderScene({required this.primitives, this.cullRect});

  /// Ordered primitives to be painted.
  final List<RenderPrimitive> primitives;

  /// Optional culling rect hint in world space.
  final DrawRect? cullRect;
}

/// Base type for backend-agnostic render primitives.
sealed class RenderPrimitive {
  const RenderPrimitive();
}

/// Path drawing command stream.
@immutable
class RenderPath {
  /// Creates a render path.
  const RenderPath(this.commands);

  /// Path commands in order.
  final List<RenderPathCommand> commands;
}

/// Path command marker.
sealed class RenderPathCommand {
  const RenderPathCommand();
}

/// Move current point to [point].
@immutable
class RenderMoveTo extends RenderPathCommand {
  /// Creates a move command.
  const RenderMoveTo(this.point);

  /// Destination point.
  final DrawPoint point;
}

/// Draw a line to [point].
@immutable
class RenderLineTo extends RenderPathCommand {
  /// Creates a line command.
  const RenderLineTo(this.point);

  /// Destination point.
  final DrawPoint point;
}

/// Draw a quadratic bezier curve.
@immutable
class RenderQuadraticTo extends RenderPathCommand {
  /// Creates a quadratic curve command.
  const RenderQuadraticTo({required this.control, required this.end});

  /// Control point.
  final DrawPoint control;

  /// End point.
  final DrawPoint end;
}

/// Draw a cubic bezier curve.
@immutable
class RenderCubicTo extends RenderPathCommand {
  /// Creates a cubic curve command.
  const RenderCubicTo({
    required this.control1,
    required this.control2,
    required this.end,
  });

  /// First control point.
  final DrawPoint control1;

  /// Second control point.
  final DrawPoint control2;

  /// End point.
  final DrawPoint end;
}

/// Closes the current contour.
class RenderClosePath extends RenderPathCommand {
  /// Creates a close-path command.
  const RenderClosePath();
}

/// Stroke cap behavior for path strokes.
enum RenderStrokeCap { butt, round, square }

/// Stroke join behavior for path strokes.
enum RenderStrokeJoin { miter, round, bevel }

/// Text align behavior for text primitives.
enum RenderTextAlign { left, center, right }

/// Hatch fill pattern style.
enum RenderHatchPattern { line, crossLine }

/// Multiply-blend group primitive.
@immutable
class RenderBlendMultiplyGroupPrimitive extends RenderPrimitive {
  /// Creates a multiply-blend group primitive.
  const RenderBlendMultiplyGroupPrimitive({required this.child});

  /// Child scene that multiply blend applies to.
  final RenderScene child;
}

/// Stroke primitive for a path.
@immutable
class RenderPathStrokePrimitive extends RenderPrimitive {
  /// Creates a path stroke primitive.
  const RenderPathStrokePrimitive({
    required this.path,
    required this.colorArgb,
    required this.strokeWidth,
    this.strokeCap = RenderStrokeCap.butt,
    this.strokeJoin = RenderStrokeJoin.miter,
    this.dashPattern,
  });

  /// Path to stroke.
  final RenderPath path;

  /// ARGB color encoded in 32-bit integer.
  final int colorArgb;

  /// Stroke width in logical pixels.
  final double strokeWidth;

  /// Stroke cap style.
  final RenderStrokeCap strokeCap;

  /// Stroke join style.
  final RenderStrokeJoin strokeJoin;

  /// Optional dash pattern sequence.
  final List<double>? dashPattern;
}

/// Fill primitive for a path.
@immutable
class RenderPathFillPrimitive extends RenderPrimitive {
  /// Creates a path fill primitive.
  const RenderPathFillPrimitive({required this.path, required this.colorArgb});

  /// Path to fill.
  final RenderPath path;

  /// ARGB color encoded in 32-bit integer.
  final int colorArgb;
}

/// Pattern fill primitive for a clipped path.
@immutable
class RenderHatchPathFillPrimitive extends RenderPrimitive {
  /// Creates a hatch path fill primitive.
  const RenderHatchPathFillPrimitive({
    required this.path,
    required this.clipBounds,
    required this.colorArgb,
    required this.lineWidth,
    required this.spacing,
    required this.angleRadians,
    this.pattern = RenderHatchPattern.line,
  });

  /// Path used as clip region for hatch rendering.
  final RenderPath path;

  /// Bounds hint for hatch line generation.
  final DrawRect clipBounds;

  /// ARGB color encoded in 32-bit integer.
  final int colorArgb;

  /// Hatch line width in logical pixels.
  final double lineWidth;

  /// Hatch line spacing in logical pixels.
  final double spacing;

  /// Primary hatch angle in radians.
  final double angleRadians;

  /// Hatch pattern style.
  final RenderHatchPattern pattern;
}

/// Text run primitive.
@immutable
class RenderTextRunPrimitive extends RenderPrimitive {
  /// Creates a text-run primitive.
  const RenderTextRunPrimitive({
    required this.text,
    required this.origin,
    required this.fontSize,
    required this.colorArgb,
    this.fontFamily,
    this.strokeColorArgb,
    this.strokeWidth = 0,
    this.align = RenderTextAlign.left,
    this.maxWidth = double.infinity,
  });

  /// Text content.
  final String text;

  /// Text origin in world space.
  final DrawPoint origin;

  /// Font size in logical pixels.
  final double fontSize;

  /// ARGB color encoded in 32-bit integer.
  final int colorArgb;

  /// Optional font family hint.
  final String? fontFamily;

  /// Optional text stroke color encoded in 32-bit ARGB integer.
  final int? strokeColorArgb;

  /// Optional text stroke width in logical pixels.
  final double strokeWidth;

  /// Text alignment for multiline layouts.
  final RenderTextAlign align;

  /// Maximum layout width.
  final double maxWidth;
}

/// Clip-rect group primitive.
@immutable
class RenderClipRectPrimitive extends RenderPrimitive {
  /// Creates a clip-rect group.
  const RenderClipRectPrimitive({required this.clipRect, required this.child});

  /// Clipping rect.
  final DrawRect clipRect;

  /// Child scene clipped by [clipRect].
  final RenderScene child;
}

/// Transform group primitive.
@immutable
class RenderTransformPrimitive extends RenderPrimitive {
  /// Creates a transform group.
  const RenderTransformPrimitive({
    required this.child,
    this.translate = DrawPoint.zero,
    this.scaleX = 1,
    this.scaleY = 1,
    this.rotation = 0,
  });

  /// Child scene affected by this transform.
  final RenderScene child;

  /// Translation.
  final DrawPoint translate;

  /// Horizontal scale factor.
  final double scaleX;

  /// Vertical scale factor.
  final double scaleY;

  /// Rotation in radians.
  final double rotation;
}

/// Mutable builder for [RenderScene].
class SceneBuilder {
  final List<RenderPrimitive> _primitives = <RenderPrimitive>[];

  /// Adds an arbitrary primitive.
  void addPrimitive(RenderPrimitive primitive) {
    _primitives.add(primitive);
  }

  /// Adds a path stroke primitive.
  void addPathStroke({
    required RenderPath path,
    required int colorArgb,
    required double strokeWidth,
    RenderStrokeCap strokeCap = RenderStrokeCap.butt,
    RenderStrokeJoin strokeJoin = RenderStrokeJoin.miter,
    List<double>? dashPattern,
  }) {
    _primitives.add(
      RenderPathStrokePrimitive(
        path: path,
        colorArgb: colorArgb,
        strokeWidth: strokeWidth,
        strokeCap: strokeCap,
        strokeJoin: strokeJoin,
        dashPattern: dashPattern,
      ),
    );
  }

  /// Adds a path fill primitive.
  void addPathFill({required RenderPath path, required int colorArgb}) {
    _primitives.add(RenderPathFillPrimitive(path: path, colorArgb: colorArgb));
  }

  /// Adds a hatch-fill primitive clipped by a path.
  void addHatchPathFill({
    required RenderPath path,
    required DrawRect clipBounds,
    required int colorArgb,
    required double lineWidth,
    required double spacing,
    required double angleRadians,
    RenderHatchPattern pattern = RenderHatchPattern.line,
  }) {
    _primitives.add(
      RenderHatchPathFillPrimitive(
        path: path,
        clipBounds: clipBounds,
        colorArgb: colorArgb,
        lineWidth: lineWidth,
        spacing: spacing,
        angleRadians: angleRadians,
        pattern: pattern,
      ),
    );
  }

  /// Adds a text run primitive.
  void addTextRun({
    required String text,
    required DrawPoint origin,
    required double fontSize,
    required int colorArgb,
    String? fontFamily,
    int? strokeColorArgb,
    double strokeWidth = 0,
    RenderTextAlign align = RenderTextAlign.left,
    double maxWidth = double.infinity,
  }) {
    _primitives.add(
      RenderTextRunPrimitive(
        text: text,
        origin: origin,
        fontSize: fontSize,
        colorArgb: colorArgb,
        fontFamily: fontFamily,
        strokeColorArgb: strokeColorArgb,
        strokeWidth: strokeWidth,
        align: align,
        maxWidth: maxWidth,
      ),
    );
  }

  /// Adds a clip-rect group primitive.
  void addClipRect({required DrawRect clipRect, required RenderScene child}) {
    _primitives.add(RenderClipRectPrimitive(clipRect: clipRect, child: child));
  }

  /// Adds a transform group primitive.
  void addTransform({
    required RenderScene child,
    DrawPoint translate = DrawPoint.zero,
    double scaleX = 1,
    double scaleY = 1,
    double rotation = 0,
  }) {
    _primitives.add(
      RenderTransformPrimitive(
        child: child,
        translate: translate,
        scaleX: scaleX,
        scaleY: scaleY,
        rotation: rotation,
      ),
    );
  }

  /// Adds a multiply-blend filter group primitive.
  void addBlendMultiplyGroup({required RenderScene child}) {
    _primitives.add(RenderBlendMultiplyGroupPrimitive(child: child));
  }

  /// Builds an immutable [RenderScene].
  RenderScene build({DrawRect? cullRect}) => RenderScene(
    primitives: List<RenderPrimitive>.unmodifiable(_primitives),
    cullRect: cullRect,
  );

  /// Clears all queued primitives.
  void clear() => _primitives.clear();
}
