import 'dart:ui';

import 'package:snow_draw_engine/snow_draw_engine.dart';

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

/// Builds a center-line path from persisted free-draw points.
///
/// The input points are already finalized at creation finish time, so this
/// path builder only applies Catmull-Rom conversion and does not run any
/// additional smoothing passes.
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
  final resolvedPoints = closed ? points.sublist(0, points.length - 1) : points;

  final path = Path()..moveTo(resolvedPoints.first.dx, resolvedPoints.first.dy);
  const tension = 0.5;
  final count = resolvedPoints.length;

  if (closed) {
    for (var i = 0; i < count; i++) {
      final p0 = resolvedPoints[(i - 1 + count) % count];
      final p1 = resolvedPoints[i];
      final p2 = resolvedPoints[(i + 1) % count];
      final p3 = resolvedPoints[(i + 2) % count];

      final cp1 = p1 + (p2 - p0) * (tension / 6);
      final cp2 = p2 - (p3 - p1) * (tension / 6);
      path.cubicTo(cp1.dx, cp1.dy, cp2.dx, cp2.dy, p2.dx, p2.dy);
    }
    path.close();
    return path;
  }

  _addOpenCatmullRomSegments(path, resolvedPoints);
  return path;
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
