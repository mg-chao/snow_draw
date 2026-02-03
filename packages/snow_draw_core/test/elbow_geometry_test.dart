import 'package:flutter_test/flutter_test.dart';
import 'package:snow_draw_core/draw/elements/types/arrow/elbow/elbow_geometry.dart';
import 'package:snow_draw_core/draw/elements/types/arrow/elbow/elbow_heading.dart';
import 'package:snow_draw_core/draw/types/draw_point.dart';

void main() {
  test('headingForVector prefers dominant axis and horizontal ties', () {
    expect(ElbowGeometry.headingForVector(10, 2), ElbowHeading.right);
    expect(ElbowGeometry.headingForVector(-10, 2), ElbowHeading.left);
    expect(ElbowGeometry.headingForVector(2, 10), ElbowHeading.down);
    expect(ElbowGeometry.headingForVector(2, -10), ElbowHeading.up);
    expect(ElbowGeometry.headingForVector(5, 5), ElbowHeading.right);
  });

  test('headingForSegment mirrors headingForVector', () {
    const start = DrawPoint.zero;
    expect(
      ElbowGeometry.headingForSegment(start, const DrawPoint(x: 40, y: 5)),
      ElbowHeading.right,
    );
    expect(
      ElbowGeometry.headingForSegment(start, const DrawPoint(x: -40, y: 5)),
      ElbowHeading.left,
    );
    expect(
      ElbowGeometry.headingForSegment(start, const DrawPoint(x: 5, y: 40)),
      ElbowHeading.down,
    );
  });

  test('manhattanDistance sums axis deltas', () {
    const a = DrawPoint.zero;
    const b = DrawPoint(x: 3, y: 4);
    expect(ElbowGeometry.manhattanDistance(a, b), 7);
  });

  test('isHorizontal flags segments with wider X delta', () {
    expect(
      ElbowGeometry.isHorizontal(DrawPoint.zero, const DrawPoint(x: 10, y: 1)),
      isTrue,
    );
    expect(
      ElbowGeometry.isHorizontal(DrawPoint.zero, const DrawPoint(x: 1, y: 10)),
      isFalse,
    );
  });
}
