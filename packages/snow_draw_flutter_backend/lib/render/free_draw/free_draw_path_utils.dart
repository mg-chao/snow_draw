import 'dart:ui';

import 'package:snow_draw_core/snow_draw_core.dart';

/// Converts normalized (0..1) points to local pixel-space offsets.
List<Offset> resolveFreeDrawLocalPoints({
  required DrawRect rect,
  required List<DrawPoint> points,
}) {
  final width = rect.width;
  final height = rect.height;
  return [
    for (final point in points) Offset(point.x * width, point.y * height),
  ];
}

/// Resolves per-point pressure values from normalized points.
///
/// Returns a list parallel to [points] with pressure in 0..1.
/// Points without pressure data get a default of 0.5.
List<double> resolveFreeDrawPressures({required List<DrawPoint> points}) => [
  for (final point in points)
    point.hasPressure ? point.pressure.clamp(0.0, 1.0) : 0.5,
];

/// Builds a smooth center-line path using Catmull-Rom splines.
///
/// Uses virtual phantom points at the endpoints so the curve
/// enters and exits with natural curvature instead of a straight
/// segment. This produces rounded start/end caps and smooth
/// transitions between straight-line and freehand segments.
Path buildFreeDrawSmoothPath(List<Offset> points) {
  if (points.length < 2) {
    return Path();
  }
  if (points.length == 2) {
    return Path()
      ..moveTo(points.first.dx, points.first.dy)
      ..lineTo(points.last.dx, points.last.dy);
  }

  final closed = points.first == points.last;
  final source = closed ? points.sublist(0, points.length - 1) : points;
  final smoothed = _smoothPoints(source, closed: closed);

  final path = Path()..moveTo(smoothed.first.dx, smoothed.first.dy);
  const tension = 0.5;
  final count = smoothed.length;

  if (closed) {
    for (var i = 0; i < count; i++) {
      final p0 = smoothed[(i - 1 + count) % count];
      final p1 = smoothed[i];
      final p2 = smoothed[(i + 1) % count];
      final p3 = smoothed[(i + 2) % count];

      final cp1 = p1 + (p2 - p0) * (tension / 6);
      final cp2 = p2 - (p3 - p1) * (tension / 6);
      path.cubicTo(cp1.dx, cp1.dy, cp2.dx, cp2.dy, p2.dx, p2.dy);
    }
    path.close();
    return path;
  }

  _addOpenCatmullRomSegments(path, smoothed);
  return path;
}

/// Incrementally extends a smooth path with new points.
///
/// Returns `null` if the inputs are too short or if a full rebuild
/// is needed (caller should fall back to [buildFreeDrawSmoothPath]).
Path? buildFreeDrawSmoothPathIncremental({
  required List<Offset> allPoints,
  required Path basePath,
  required int basePointCount,
}) {
  if (allPoints.length < 2 ||
      allPoints.first == allPoints.last ||
      basePointCount < 3 ||
      basePointCount > allPoints.length) {
    return null;
  }

  if (allPoints.length == basePointCount) {
    return Path()..addPath(basePath, Offset.zero);
  }
  return buildFreeDrawSmoothPath(allPoints);
}

/// Appends open (non-closed) Catmull-Rom cubic segments for all
/// points in [smoothed] to [path].
void _addOpenCatmullRomSegments(Path path, List<Offset> smoothed) {
  const tension = 0.5;
  final count = smoothed.length;
  if (count < 2) {
    return;
  }

  final phantomFirst = smoothed[0] + (smoothed[0] - smoothed[1]);
  final phantomLast =
      smoothed[count - 1] + (smoothed[count - 1] - smoothed[count - 2]);

  for (var i = 0; i < count - 1; i++) {
    final p0 = i == 0 ? phantomFirst : smoothed[i - 1];
    final p1 = smoothed[i];
    final p2 = smoothed[i + 1];
    final p3 = i + 2 < count ? smoothed[i + 2] : phantomLast;

    final cp1 = p1 + (p2 - p0) * (tension / 6);
    final cp2 = p2 - (p3 - p1) * (tension / 6);
    path.cubicTo(cp1.dx, cp1.dy, cp2.dx, cp2.dy, p2.dx, p2.dy);
  }
}

/// Smooths [points] using a 1-2-1 kernel with a double-buffer
/// swap to avoid per-iteration list allocations.
List<Offset> _smoothPoints(List<Offset> points, {required bool closed}) {
  if (points.length < 3) {
    return points;
  }

  const iterations = 3;
  final n = points.length;
  final lastIndex = n - 1;

  // Two pre-allocated buffers; swap between them each pass.
  var src = List<Offset>.of(points);
  var dst = List<Offset>.filled(n, Offset.zero);

  for (var iter = 0; iter < iterations; iter++) {
    if (closed) {
      for (var i = 0; i <= lastIndex; i++) {
        final prev = src[(i - 1 + n) % n];
        final curr = src[i];
        final next = src[(i + 1) % n];
        dst[i] = Offset(
          (prev.dx + curr.dx * 2 + next.dx) * 0.25,
          (prev.dy + curr.dy * 2 + next.dy) * 0.25,
        );
      }
    } else {
      // Keep endpoints pinned. The Catmull-Rom phantom points
      // handle smooth entry/exit curvature, so pulling the
      // endpoints inward would only flatten the rounded tips.
      dst[0] = src[0];
      dst[lastIndex] = src[lastIndex];
      for (var i = 1; i < lastIndex; i++) {
        final prev = src[i - 1];
        final curr = src[i];
        final next = src[i + 1];
        dst[i] = Offset(
          (prev.dx + curr.dx * 2 + next.dx) * 0.25,
          (prev.dy + curr.dy * 2 + next.dy) * 0.25,
        );
      }
    }

    // Swap buffers.
    final tmp = src;
    src = dst;
    dst = tmp;
  }

  return src;
}
