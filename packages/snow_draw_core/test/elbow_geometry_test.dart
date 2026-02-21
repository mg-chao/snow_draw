import 'package:test/test.dart';
import 'package:snow_draw_core/draw/elements/types/arrow/elbow/elbow_geometry.dart';
import 'package:snow_draw_core/draw/elements/types/arrow/elbow/elbow_heading.dart';
import 'package:snow_draw_core/draw/types/draw_point.dart';

void main() {
  test('headingForVector prefers dominant axis and horizontal ties', () {
    const cases = <({double dx, double dy, ElbowHeading expected})>[
      (dx: 10, dy: 2, expected: ElbowHeading.right),
      (dx: -10, dy: 2, expected: ElbowHeading.left),
      (dx: 2, dy: 10, expected: ElbowHeading.down),
      (dx: 2, dy: -10, expected: ElbowHeading.up),
      (dx: 5, dy: 5, expected: ElbowHeading.right),
    ];

    for (final testCase in cases) {
      expect(
        ElbowGeometry.headingForVector(testCase.dx, testCase.dy),
        testCase.expected,
      );
    }
  });

  test('headingForSegment mirrors headingForVector', () {
    const start = DrawPoint.zero;
    const cases = <({DrawPoint end, ElbowHeading expected})>[
      (end: DrawPoint(x: 40, y: 5), expected: ElbowHeading.right),
      (end: DrawPoint(x: -40, y: 5), expected: ElbowHeading.left),
      (end: DrawPoint(x: 5, y: 40), expected: ElbowHeading.down),
    ];

    for (final testCase in cases) {
      expect(
        ElbowGeometry.headingForSegment(start, testCase.end),
        testCase.expected,
      );
    }
  });

  test('manhattanDistance sums axis deltas', () {
    const a = DrawPoint.zero;
    const b = DrawPoint(x: 3, y: 4);
    expect(ElbowGeometry.manhattanDistance(a, b), 7);
  });

  test('isHorizontal flags segments with wider X delta', () {
    const cases = <({DrawPoint end, bool expected})>[
      (end: DrawPoint(x: 10, y: 1), expected: true),
      (end: DrawPoint(x: 1, y: 10), expected: false),
    ];

    for (final testCase in cases) {
      expect(
        ElbowGeometry.isHorizontal(DrawPoint.zero, testCase.end),
        testCase.expected,
      );
    }
  });
}
