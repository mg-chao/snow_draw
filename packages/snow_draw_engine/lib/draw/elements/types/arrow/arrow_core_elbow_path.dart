import 'package:meta/meta.dart';

import '../../../types/draw_point.dart';

/// Base type for parsed arrow-core elbow SVG path commands.
@immutable
sealed class ArrowCoreElbowPathCommand {
  const ArrowCoreElbowPathCommand();
}

/// Parsed `M x y` command.
@immutable
final class ArrowCoreElbowMoveTo extends ArrowCoreElbowPathCommand {
  const ArrowCoreElbowMoveTo(this.point);

  final DrawPoint point;
}

/// Parsed `L x y` command.
@immutable
final class ArrowCoreElbowLineTo extends ArrowCoreElbowPathCommand {
  const ArrowCoreElbowLineTo(this.point);

  final DrawPoint point;
}

/// Parsed `Q cx cy x y` command.
@immutable
final class ArrowCoreElbowQuadraticTo extends ArrowCoreElbowPathCommand {
  const ArrowCoreElbowQuadraticTo({required this.control, required this.end});

  final DrawPoint control;
  final DrawPoint end;
}

/// Parses arrow-core elbow SVG [pathData] (`M`, `L`, `Q`) into commands.
///
/// Returns `null` when the payload is malformed.
List<ArrowCoreElbowPathCommand>? parseArrowCoreElbowPathCommands(
  String pathData,
) {
  final tokens = pathData
      .replaceAll(',', ' ')
      .trim()
      .split(RegExp(r'\s+'))
      .where((token) => token.isNotEmpty)
      .toList(growable: false);

  if (tokens.isEmpty) {
    return const <ArrowCoreElbowPathCommand>[];
  }

  final commands = <ArrowCoreElbowPathCommand>[];
  var index = 0;

  double? readNumber() {
    if (index >= tokens.length) {
      return null;
    }
    return double.tryParse(tokens[index++]);
  }

  while (index < tokens.length) {
    final token = tokens[index++];
    if (token.length != 1) {
      return null;
    }

    final command = token.toUpperCase();
    if (command == 'M' || command == 'L') {
      final x = readNumber();
      final y = readNumber();
      if (x == null || y == null) {
        return null;
      }
      final point = DrawPoint(x: x, y: y);
      commands.add(
        command == 'M'
            ? ArrowCoreElbowMoveTo(point)
            : ArrowCoreElbowLineTo(point),
      );
      continue;
    }

    if (command == 'Q') {
      final cx = readNumber();
      final cy = readNumber();
      final x = readNumber();
      final y = readNumber();
      if (cx == null || cy == null || x == null || y == null) {
        return null;
      }
      commands.add(
        ArrowCoreElbowQuadraticTo(
          control: DrawPoint(x: cx, y: cy),
          end: DrawPoint(x: x, y: y),
        ),
      );
      continue;
    }

    return null;
  }

  return List<ArrowCoreElbowPathCommand>.unmodifiable(commands);
}
