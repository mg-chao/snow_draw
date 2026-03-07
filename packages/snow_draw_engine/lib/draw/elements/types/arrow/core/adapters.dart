import 'arrow_types.dart';

ArrowState applyArrowPatch(ArrowState arrow, ArrowPatch patch) {
  final hasX = patch.containsKey('x');
  final hasY = patch.containsKey('y');
  final hasWidth = patch.containsKey('width');
  final hasHeight = patch.containsKey('height');
  final hasPoints = patch.containsKey('points');
  final hasStartBinding = patch.containsKey('startBinding');
  final hasEndBinding = patch.containsKey('endBinding');
  final hasFixedSegments = patch.containsKey('fixedSegments');
  final hasStartIsSpecial = patch.containsKey('startIsSpecial');
  final hasEndIsSpecial = patch.containsKey('endIsSpecial');

  return arrow.copyWith(
    x: hasX && patch['x'] is num ? (patch['x'] as num).toDouble() : null,
    y: hasY && patch['y'] is num ? (patch['y'] as num).toDouble() : null,
    width: hasWidth && patch['width'] is num
        ? (patch['width'] as num).toDouble()
        : null,
    height: hasHeight && patch['height'] is num
        ? (patch['height'] as num).toDouble()
        : null,
    points: hasPoints && patch['points'] is List
        ? (patch['points'] as List)
              .map((point) {
                if (point is List && point.length >= 2) {
                  final x = point[0];
                  final y = point[1];
                  if (x is num && y is num && x.isFinite && y.isFinite) {
                    return <double>[x.toDouble(), y.toDouble()];
                  }
                }
                return <double>[0, 0];
              })
              .toList(growable: false)
        : null,
    startBinding: hasStartBinding
        ? patch['startBinding'] as FixedPointBinding?
        : null,
    setStartBinding: hasStartBinding,
    endBinding: hasEndBinding
        ? patch['endBinding'] as FixedPointBinding?
        : null,
    setEndBinding: hasEndBinding,
    fixedSegments: hasFixedSegments
        ? (patch['fixedSegments'] as List?)
              ?.map((segment) => segment as FixedSegment)
              .toList(growable: false)
        : null,
    setFixedSegments: hasFixedSegments,
    startIsSpecial: hasStartIsSpecial ? patch['startIsSpecial'] as bool? : null,
    setStartIsSpecial: hasStartIsSpecial,
    endIsSpecial: hasEndIsSpecial ? patch['endIsSpecial'] as bool? : null,
    setEndIsSpecial: hasEndIsSpecial,
  );
}
