import 'dart:ui';

import '../../../types/draw_point.dart';
import '../../../types/draw_rect.dart';

List<Offset> resolveFreeDrawLocalPoints({
  required DrawRect rect,
  required List<DrawPoint> points,
}) {
  if (points.isEmpty) {
    return const <Offset>[];
  }
  final width = rect.width;
  final height = rect.height;
  return points
      .map((point) => Offset(point.x * width, point.y * height))
      .toList(growable: false);
}

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
  if (smoothed.length < 2) {
    return Path();
  }

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

  for (var i = 0; i < count - 1; i++) {
    final p0 = i == 0 ? smoothed[i] : smoothed[i - 1];
    final p1 = smoothed[i];
    final p2 = smoothed[i + 1];
    final p3 = i + 2 < count ? smoothed[i + 2] : smoothed[i + 1];

    final cp1 = p1 + (p2 - p0) * (tension / 6);
    final cp2 = p2 - (p3 - p1) * (tension / 6);
    path.cubicTo(cp1.dx, cp1.dy, cp2.dx, cp2.dy, p2.dx, p2.dy);
  }
  return path;
}

List<Offset> _smoothPoints(List<Offset> points, {required bool closed}) {
  if (points.length < 3) {
    return points;
  }

  const iterations = 3;
  var working = List<Offset>.from(points);

  for (var iter = 0; iter < iterations; iter++) {
    final next = List<Offset>.from(working);
    final lastIndex = working.length - 1;

    if (closed) {
      for (var i = 0; i <= lastIndex; i++) {
        final prev = working[(i - 1 + working.length) % working.length];
        final curr = working[i];
        final nextPoint = working[(i + 1) % working.length];
        next[i] = Offset(
          (prev.dx + curr.dx * 2 + nextPoint.dx) * 0.25,
          (prev.dy + curr.dy * 2 + nextPoint.dy) * 0.25,
        );
      }
    } else {
      for (var i = 1; i < lastIndex; i++) {
        final prev = working[i - 1];
        final curr = working[i];
        final nextPoint = working[i + 1];
        next[i] = Offset(
          (prev.dx + curr.dx * 2 + nextPoint.dx) * 0.25,
          (prev.dy + curr.dy * 2 + nextPoint.dy) * 0.25,
        );
      }
      next[0] = working[0];
      next[lastIndex] = working[lastIndex];
    }

    working = next;
  }

  return working;
}
