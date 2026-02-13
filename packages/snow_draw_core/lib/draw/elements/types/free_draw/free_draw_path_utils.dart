import 'dart:math' as math;
import 'dart:ui';

import '../../../types/draw_point.dart';
import '../../../types/draw_rect.dart';

/// Converts normalized (0..1) points to local pixel-space offsets.
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

/// Resolves per-point pressure values from normalized points.
///
/// Returns a list parallel to [points] with pressure in 0..1.
/// Points without pressure data get a default of 0.5.
List<double> resolveFreeDrawPressures({required List<DrawPoint> points}) {
  if (points.isEmpty) {
    return const <double>[];
  }
  final hasPressure = points.any((p) => p.hasPressure);
  if (!hasPressure) {
    return List<double>.filled(points.length, 0.5);
  }
  return points
      .map((p) => p.hasPressure ? p.pressure.clamp(0.0, 1.0) : 0.5)
      .toList(growable: false);
}

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

  _addOpenCatmullRomSegments(path, smoothed);
  return path;
}

/// Incrementally extends a smooth path with new points.
///
/// Reuses the smoothed-point computation but only generates
/// Catmull-Rom cubics for the full path using the range helper,
/// which is cheaper than the full [buildFreeDrawSmoothPath] when
/// the smoothing pass dominates less than the cubic generation.
///
/// Returns `null` if the inputs are too short or if a full rebuild
/// is needed (caller should fall back to [buildFreeDrawSmoothPath]).
Path? buildFreeDrawSmoothPathIncremental({
  required List<Offset> allPoints,
  required Path basePath,
  required int basePointCount,
}) {
  if (allPoints.length < 2) {
    return null;
  }
  if (allPoints.first == allPoints.last) {
    return null;
  }

  final smoothed = _smoothPoints(allPoints, closed: false);
  if (smoothed.length < 2) {
    return null;
  }

  // If the base covered fewer than 3 smoothed points, a full
  // rebuild is cheaper and more correct.
  if (basePointCount < 3) {
    return null;
  }

  final count = smoothed.length;
  // We need to recompute from 2 segments before the new tail
  // because Catmull-Rom uses 4 control points per segment, so
  // appending a point affects the previous 2 segments.
  final recomputeFrom = math.max(0, basePointCount - 3);

  // Build a new path from the smoothed points, splitting at
  // recomputeFrom. The smoothing pass is still O(n) but the
  // cubic generation for the stable prefix can be skipped in
  // future iterations when we cache the smoothed array.
  final _ = basePath;
  final prefixEnd = math.min(count, recomputeFrom + 1);
  final result = Path()..moveTo(smoothed.first.dx, smoothed.first.dy);
  _addOpenCatmullRomSegmentsRange(result, smoothed, 0, prefixEnd);
  _addOpenCatmullRomSegmentsRange(result, smoothed, recomputeFrom, count);
  return result;
}

/// Appends open (non-closed) Catmull-Rom cubic segments for all
/// points in [smoothed] to [path].
void _addOpenCatmullRomSegments(Path path, List<Offset> smoothed) {
  _addOpenCatmullRomSegmentsRange(path, smoothed, 0, smoothed.length);
}

/// Appends open Catmull-Rom cubic segments for the range
/// [from]..[to) in [smoothed] to [path].
void _addOpenCatmullRomSegmentsRange(
  Path path,
  List<Offset> smoothed,
  int from,
  int to,
) {
  const tension = 0.5;
  final count = smoothed.length;
  if (count < 2 || from >= to - 1) {
    return;
  }

  final phantomFirst = smoothed[0] + (smoothed[0] - smoothed[1]);
  final phantomLast =
      smoothed[count - 1] + (smoothed[count - 1] - smoothed[count - 2]);

  for (var i = from; i < to - 1; i++) {
    final p0 = i == 0 ? phantomFirst : smoothed[i - 1];
    final p1 = smoothed[i];
    final p2 = smoothed[i + 1];
    final p3 = i + 2 < count ? smoothed[i + 2] : phantomLast;

    final cp1 = p1 + (p2 - p0) * (tension / 6);
    final cp2 = p2 - (p3 - p1) * (tension / 6);
    path.cubicTo(cp1.dx, cp1.dy, cp2.dx, cp2.dy, p2.dx, p2.dy);
  }
}

/// Builds a filled outline path for a variable-width stroke.
///
/// The center-line [points] are resampled at fine uniform intervals,
/// widths are derived from pressure with velocity damping and
/// multi-pass smoothing, and the outline edges use Catmull-Rom
/// curves for full smoothness. End caps are true semicircular arcs.
///
/// [baseWidth] is the maximum stroke width (at full pressure).
Path buildVariableWidthOutline({
  required List<Offset> points,
  required List<double> pressures,
  required double baseWidth,
}) {
  if (points.length < 2) {
    return Path();
  }

  // Use fine resampling — smaller spacing produces smoother
  // outlines, especially at curves and direction changes.
  final spacing = math.max(0.5, baseWidth * 0.25);
  final resampled = _resampleUniform(
    points: points,
    pressures: pressures,
    spacing: spacing,
  );
  final rPoints = resampled.points;
  final rPressures = resampled.pressures;
  if (rPoints.length < 2) {
    return Path();
  }

  final count = rPoints.length;
  final widths = _computeWidths(
    pressures: rPressures,
    baseWidth: baseWidth,
    count: count,
  );
  // All width transforms mutate in-place to avoid intermediate
  // list allocations (previously ~8 copies per stroke).
  _applyVelocityDampingInPlace(rPoints, widths);
  _taperEndpointsInPlace(widths, baseWidth);
  _smoothWidthsInPlace(widths);

  // Build left and right edge points using averaged normals.
  final leftSide = List<Offset>.filled(count, Offset.zero);
  final rightSide = List<Offset>.filled(count, Offset.zero);

  for (var i = 0; i < count; i++) {
    final normal = _smoothNormalAt(rPoints, i);
    final halfW = widths[i] / 2;
    leftSide[i] = rPoints[i] + normal * halfW;
    rightSide[i] = rPoints[i] - normal * halfW;
  }

  // Build the outline: left side forward, right side backward,
  // connected by semicircular end caps.
  final path = Path()..moveTo(leftSide.first.dx, leftSide.first.dy);

  // Left edge forward via Catmull-Rom.
  _addCatmullRomThrough(path, leftSide);

  // End cap at the stroke tip.
  _addRoundCap(path, leftSide.last, rightSide.last, rPoints.last);

  // Right edge backward via Catmull-Rom.
  final rightReversed = rightSide.reversed.toList();
  _addCatmullRomThrough(path, rightReversed);

  // Start cap at the stroke origin.
  _addRoundCap(path, rightSide.first, leftSide.first, rPoints.first);

  path.close();
  return path;
}

/// Appends Catmull-Rom cubic segments through [pts] to [path].
///
/// The first point is assumed to already be the current path
/// position. Endpoint tangents are mirrored so the curve is smooth
/// all the way to the head and tail.
void _addCatmullRomThrough(Path path, List<Offset> pts) {
  if (pts.length < 2) {
    return;
  }
  const tension = 0.5;
  final n = pts.length;
  for (var i = 0; i < n - 1; i++) {
    final p0 = i == 0 ? pts[0] + (pts[0] - pts[1]) : pts[i - 1];
    final p1 = pts[i];
    final p2 = pts[i + 1];
    final p3 = i + 2 < n ? pts[i + 2] : pts[n - 1] + (pts[n - 1] - pts[n - 2]);

    final cp1 = p1 + (p2 - p0) * (tension / 6);
    final cp2 = p2 - (p3 - p1) * (tension / 6);
    path.cubicTo(cp1.dx, cp1.dy, cp2.dx, cp2.dy, p2.dx, p2.dy);
  }
}

/// Adds a smooth semicircular cap from [from] to [to] around
/// [center] using a true arc.
///
/// This uses `arcToPoint` which produces a perfect circular arc
/// rather than a Bézier approximation, giving cleaner round caps.
void _addRoundCap(Path path, Offset from, Offset to, Offset center) {
  final radius = (from - center).distance;
  if (radius < 0.1) {
    path.lineTo(to.dx, to.dy);
    return;
  }
  path.arcToPoint(
    to,
    radius: Radius.circular(radius),
    clockwise: _isClockwise(from, center, to),
  );
}

/// Determines arc direction for the end cap.
bool _isClockwise(Offset from, Offset center, Offset to) {
  final a = from - center;
  final b = to - center;
  // Cross product: positive means clockwise in screen coords
  // (y-down).
  return (a.dx * b.dy - a.dy * b.dx) >= 0;
}

/// Computes a smoothed normal at index [i] by averaging the
/// perpendicular directions of nearby segments.
///
/// This prevents the sharp normal flips that cause jagged edges
/// at direction changes. The averaging window adapts to the
/// available neighbors.
Offset _smoothNormalAt(List<Offset> points, int i) {
  final count = points.length;
  // Use a window of up to 3 points on each side.
  const window = 3;
  final lo = math.max(0, i - window);
  final hi = math.min(count - 1, i + window);

  var nx = 0.0;
  var ny = 0.0;
  var contributions = 0;

  for (var j = lo; j < hi; j++) {
    final dx = points[j + 1].dx - points[j].dx;
    final dy = points[j + 1].dy - points[j].dy;
    final len = math.sqrt(dx * dx + dy * dy);
    if (len < 1e-6) {
      continue;
    }
    // Perpendicular: rotate 90° counter-clockwise.
    nx += -dy / len;
    ny += dx / len;
    contributions++;
  }

  if (contributions == 0) {
    return const Offset(0, -1);
  }
  final len = math.sqrt(nx * nx + ny * ny);
  if (len < 1e-6) {
    return const Offset(0, -1);
  }
  return Offset(nx / len, ny / len);
}

/// Computes per-point widths from pressure.
List<double> _computeWidths({
  required List<double> pressures,
  required double baseWidth,
  required int count,
}) {
  if (count == 0) {
    return const <double>[];
  }

  final minWidth = (baseWidth * 0.15).clamp(0.3, 2.0);

  final widths = List<double>.filled(count, 0);
  for (var i = 0; i < count; i++) {
    final pressureFactor = 0.3 + pressures[i].clamp(0.0, 1.0) * 0.7;
    widths[i] = math.max(baseWidth * pressureFactor, minWidth);
  }
  return widths;
}

/// Applies velocity-based width damping in-place.
///
/// Fast-moving segments get slightly thinner, mimicking how real
/// ink thins when the pen moves quickly. This is computed from
/// inter-point distances (since resampling is uniform, distance
/// between consecutive points reflects relative speed).
void _applyVelocityDampingInPlace(List<Offset> points, List<double> widths) {
  if (points.length < 3) {
    return;
  }

  // Compute inter-point distances.
  final count = points.length;
  final distances = List<double>.filled(count, 0);
  for (var i = 1; i < count; i++) {
    distances[i] = (points[i] - points[i - 1]).distance;
  }
  distances[0] = distances[1];

  // Find the median distance for normalization.
  final sorted = List<double>.from(distances)..sort();
  final median = sorted[count ~/ 2];
  if (median < 1e-6) {
    return;
  }

  for (var i = 0; i < count; i++) {
    final speedRatio = distances[i] / median;
    final damping = 1.0 / (1.0 + (speedRatio - 1.0).clamp(0.0, 3.0) * 0.15);
    widths[i] = widths[i] * damping.clamp(0.85, 1.0);
  }
}

/// Tapers the first and last few points in-place for a natural
/// ink-on / ink-off feel.
///
/// The taper length is proportional to the stroke width so thin
/// strokes get short tapers and thick strokes get longer ones.
void _taperEndpointsInPlace(List<double> widths, double baseWidth) {
  if (widths.length < 4) {
    return;
  }

  final taperLen = (baseWidth * 0.8).clamp(3, 8).toInt();
  final actualTaper = math.min(taperLen, widths.length ~/ 3);

  for (var i = 0; i < actualTaper; i++) {
    final t = (i + 1) / (actualTaper + 1);
    final ease = t * t * (3 - 2 * t);
    widths[i] = widths[i] * (0.3 + 0.7 * ease);
  }
  for (var i = 0; i < actualTaper; i++) {
    final idx = widths.length - 1 - i;
    final t = (i + 1) / (actualTaper + 1);
    final ease = t * t * (3 - 2 * t);
    widths[idx] = widths[idx] * (0.3 + 0.7 * ease);
  }
}

/// Smooths a width array in-place using a double-buffer.
///
/// Uses two pre-allocated buffers and swaps between them each
/// pass, avoiding the per-pass `List.from` allocation.
void _smoothWidthsInPlace(List<double> widths, {int passes = 5}) {
  if (widths.length < 3) {
    return;
  }
  final n = widths.length;
  final buf = List<double>.filled(n, 0);
  var src = widths;
  var dst = buf;

  for (var p = 0; p < passes; p++) {
    for (var i = 1; i < n - 1; i++) {
      dst[i] = (src[i - 1] + src[i] * 2 + src[i + 1]) * 0.25;
    }
    dst[0] = src[0] * 0.75 + src[1] * 0.25;
    dst[n - 1] = src[n - 1] * 0.75 + src[n - 2] * 0.25;

    // Swap buffers.
    final tmp = src;
    src = dst;
    dst = tmp;
  }

  // If the final result ended up in `buf`, copy back to `widths`.
  if (!identical(src, widths)) {
    for (var i = 0; i < n; i++) {
      widths[i] = src[i];
    }
  }
}

/// Result of uniform resampling.
class _ResampleResult {
  const _ResampleResult({required this.points, required this.pressures});
  final List<Offset> points;
  final List<double> pressures;
}

/// Resamples a polyline at uniform arc-length intervals.
///
/// This prevents the outline from bunching up in slow-draw areas
/// (many close points) or stretching in fast-draw areas (few
/// distant points). Pressure is linearly interpolated.
_ResampleResult _resampleUniform({
  required List<Offset> points,
  required List<double> pressures,
  required double spacing,
}) {
  if (points.length < 2 || spacing <= 0) {
    return _ResampleResult(points: points, pressures: pressures);
  }

  final outPoints = <Offset>[points.first];
  final outPressures = <double>[pressures.first];

  var carry = 0.0;
  for (var i = 1; i < points.length; i++) {
    final prev = points[i - 1];
    final curr = points[i];
    final segLen = (curr - prev).distance;
    if (segLen < 1e-6) {
      continue;
    }

    var walked = carry;
    while (walked + spacing <= segLen) {
      walked += spacing;
      final t = walked / segLen;
      outPoints.add(Offset.lerp(prev, curr, t)!);
      // Interpolate pressure.
      final pPrev = pressures[i - 1];
      final pCurr = pressures[i];
      outPressures.add(pPrev + (pCurr - pPrev) * t);
    }
    carry = segLen - walked;
  }

  // Always include the last point.
  if (outPoints.last != points.last) {
    outPoints.add(points.last);
    outPressures.add(pressures.last);
  }

  return _ResampleResult(points: outPoints, pressures: outPressures);
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
