import '../../../render/scene/render_scene.dart';
import '../../../types/draw_point.dart';
import '../../../types/draw_rect.dart';
import 'hit_test_geometry.dart';

/// Cubic-bezier control-point ratio used to approximate circular arcs.
const circularArcControlPointRatio = 0.5522847498307936;

/// Returns a path with an explicit close command.
RenderPath closeRenderPathIfNeeded(RenderPath path) {
  if (path.commands.isEmpty || path.commands.last is RenderClosePath) {
    return path;
  }
  return RenderPath(<RenderPathCommand>[
    ...path.commands,
    const RenderClosePath(),
  ]);
}

/// Builds a polyline path from [points].
RenderPath buildPolylineRenderPath(List<DrawPoint> points) {
  if (points.length < 2) {
    return const RenderPath(<RenderPathCommand>[]);
  }
  final commands = <RenderPathCommand>[RenderMoveTo(points.first)];
  for (final point in points.skip(1)) {
    commands.add(RenderLineTo(point));
  }
  return RenderPath(commands);
}

/// Builds a Catmull-Rom interpolated cubic path from [points].
///
/// Falls back to a polyline when fewer than three points are available.
RenderPath buildCatmullRomRenderPath(List<DrawPoint> points) {
  if (points.length < 3) {
    return buildPolylineRenderPath(points);
  }
  final commands = <RenderPathCommand>[RenderMoveTo(points.first)];
  for (var index = 0; index < points.length - 1; index += 1) {
    final segment = buildCatmullRomCubicSegment(points, index);
    commands.add(
      RenderCubicTo(
        control1: segment.control1,
        control2: segment.control2,
        end: segment.end,
      ),
    );
  }
  return RenderPath(commands);
}

/// Clamps rounded-rectangle corner radius to valid bounds.
double clampRoundedRectCornerRadius({
  required double cornerRadius,
  required double width,
  required double height,
}) {
  if (cornerRadius <= 0) {
    return 0;
  }
  final maxRadius = (width < height ? width : height) / 2;
  if (cornerRadius > maxRadius) {
    return maxRadius;
  }
  return cornerRadius;
}

/// Builds a centered rectangle path for [rect].
RenderPath buildCenteredRectPath(DrawRect rect) {
  final width = rect.width;
  final height = rect.height;
  final left = -width / 2;
  final top = -height / 2;
  final right = width / 2;
  final bottom = height / 2;
  return RenderPath(
    buildRectPathCommands(left: left, top: top, right: right, bottom: bottom),
  );
}

/// Builds a centered rounded-rectangle path for [rect].
RenderPath buildCenteredRoundedRectPath({
  required DrawRect rect,
  required double cornerRadius,
}) {
  final width = rect.width;
  final height = rect.height;
  final left = -width / 2;
  final top = -height / 2;
  final right = width / 2;
  final bottom = height / 2;
  final radius = clampRoundedRectCornerRadius(
    cornerRadius: cornerRadius,
    width: width,
    height: height,
  );
  return RenderPath(
    radius <= 0
        ? buildRectPathCommands(
            left: left,
            top: top,
            right: right,
            bottom: bottom,
          )
        : buildRoundedRectPathCommands(
            left: left,
            top: top,
            right: right,
            bottom: bottom,
            radius: radius,
          ),
  );
}

/// Builds rectangle path commands from bounds.
List<RenderPathCommand> buildRectPathCommands({
  required double left,
  required double top,
  required double right,
  required double bottom,
}) => <RenderPathCommand>[
  RenderMoveTo(DrawPoint(x: left, y: top)),
  RenderLineTo(DrawPoint(x: right, y: top)),
  RenderLineTo(DrawPoint(x: right, y: bottom)),
  RenderLineTo(DrawPoint(x: left, y: bottom)),
  const RenderClosePath(),
];

/// Builds rounded-rectangle path commands from bounds.
List<RenderPathCommand> buildRoundedRectPathCommands({
  required double left,
  required double top,
  required double right,
  required double bottom,
  required double radius,
}) {
  final controlOffset = radius * circularArcControlPointRatio;
  return <RenderPathCommand>[
    RenderMoveTo(DrawPoint(x: left + radius, y: top)),
    RenderLineTo(DrawPoint(x: right - radius, y: top)),
    RenderCubicTo(
      control1: DrawPoint(x: right - radius + controlOffset, y: top),
      control2: DrawPoint(x: right, y: top + radius - controlOffset),
      end: DrawPoint(x: right, y: top + radius),
    ),
    RenderLineTo(DrawPoint(x: right, y: bottom - radius)),
    RenderCubicTo(
      control1: DrawPoint(x: right, y: bottom - radius + controlOffset),
      control2: DrawPoint(x: right - radius + controlOffset, y: bottom),
      end: DrawPoint(x: right - radius, y: bottom),
    ),
    RenderLineTo(DrawPoint(x: left + radius, y: bottom)),
    RenderCubicTo(
      control1: DrawPoint(x: left + radius - controlOffset, y: bottom),
      control2: DrawPoint(x: left, y: bottom - radius + controlOffset),
      end: DrawPoint(x: left, y: bottom - radius),
    ),
    RenderLineTo(DrawPoint(x: left, y: top + radius)),
    RenderCubicTo(
      control1: DrawPoint(x: left, y: top + radius - controlOffset),
      control2: DrawPoint(x: left + radius - controlOffset, y: top),
      end: DrawPoint(x: left + radius, y: top),
    ),
    const RenderClosePath(),
  ];
}
