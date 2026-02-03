part of 'elbow_editing.dart';

/// Geometry helpers shared across elbow editing flows.

List<DrawPoint> _resolveLocalPoints(ElementState element, ArrowData data) {
  final resolved = ArrowGeometry.resolveWorldPoints(
    rect: element.rect,
    normalizedPoints: data.points,
  );
  return resolved
      .map((point) => DrawPoint(x: point.dx, y: point.dy))
      .toList(growable: false);
}

bool _pointsEqual(List<DrawPoint> a, List<DrawPoint> b) {
  if (a.length != b.length) {
    return false;
  }
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) {
      return false;
    }
  }
  return true;
}

bool _pointsEqualExceptEndpoints(List<DrawPoint> a, List<DrawPoint> b) {
  if (a.length != b.length || a.length < 2) {
    return false;
  }
  for (var i = 1; i < a.length - 1; i++) {
    if (a[i] != b[i]) {
      return false;
    }
  }
  return true;
}
