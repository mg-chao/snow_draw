import 'dart:math' as math;

import 'arrow_geom.dart';
import 'arrow_types.dart';

const _bindableRoundnessLegacy = 1;
const _bindableRoundnessProportional = 2;
const _bindableRoundnessAdaptive = 3;

const _epsilon = 1e-9;
const _epsilonRadius = 1e-6;

typedef _BindingSide = String;

class _ZIndexedBindable {
  const _ZIndexedBindable({
    required this.bindable,
    required this.index,
    required this.zIndex,
  });

  final BindableState bindable;
  final int index;
  final double zIndex;
}

class _SectorConfig {
  const _SectorConfig({
    required this.centerAngle,
    required this.sectorWidth,
    required this.side,
  });

  final double centerAngle;
  final double sectorWidth;
  final _BindingSide side;
}

const _shapeSectors = <CanonicalBindableShape, List<_SectorConfig>>{
  'rectangle': <_SectorConfig>[
    _SectorConfig(centerAngle: 0, sectorWidth: 75, side: 'right'),
    _SectorConfig(centerAngle: 45, sectorWidth: 15, side: 'bottom-right'),
    _SectorConfig(centerAngle: 90, sectorWidth: 75, side: 'bottom'),
    _SectorConfig(centerAngle: 135, sectorWidth: 15, side: 'bottom-left'),
    _SectorConfig(centerAngle: 180, sectorWidth: 75, side: 'left'),
    _SectorConfig(centerAngle: 225, sectorWidth: 15, side: 'top-left'),
    _SectorConfig(centerAngle: 270, sectorWidth: 75, side: 'top'),
    _SectorConfig(centerAngle: 315, sectorWidth: 15, side: 'top-right'),
  ],
  'diamond': <_SectorConfig>[
    _SectorConfig(centerAngle: 0, sectorWidth: 15, side: 'right'),
    _SectorConfig(centerAngle: 45, sectorWidth: 75, side: 'bottom-right'),
    _SectorConfig(centerAngle: 90, sectorWidth: 15, side: 'bottom'),
    _SectorConfig(centerAngle: 135, sectorWidth: 75, side: 'bottom-left'),
    _SectorConfig(centerAngle: 180, sectorWidth: 15, side: 'left'),
    _SectorConfig(centerAngle: 225, sectorWidth: 75, side: 'top-left'),
    _SectorConfig(centerAngle: 270, sectorWidth: 15, side: 'top'),
    _SectorConfig(centerAngle: 315, sectorWidth: 75, side: 'top-right'),
  ],
  'ellipse': <_SectorConfig>[
    _SectorConfig(centerAngle: 0, sectorWidth: 15, side: 'right'),
    _SectorConfig(centerAngle: 45, sectorWidth: 75, side: 'bottom-right'),
    _SectorConfig(centerAngle: 90, sectorWidth: 15, side: 'bottom'),
    _SectorConfig(centerAngle: 135, sectorWidth: 75, side: 'bottom-left'),
    _SectorConfig(centerAngle: 180, sectorWidth: 15, side: 'left'),
    _SectorConfig(centerAngle: 225, sectorWidth: 75, side: 'top-left'),
    _SectorConfig(centerAngle: 270, sectorWidth: 15, side: 'top'),
    _SectorConfig(centerAngle: 315, sectorWidth: 75, side: 'top-right'),
  ],
};

bool isBindableBackgroundOpaque(BindableState bindable) =>
    bindable.backgroundOpaque ?? true;

bool isBindableBindingEnabled(BindableState bindable) =>
    bindable.bindingEnabled ?? true;

bool isBindableInteriorHitEnabled(BindableState bindable) =>
    bindable.interiorHitEnabled ?? true;

bool _hasFiniteZIndex(BindableState bindable) =>
    bindable.zIndex != null && bindable.zIndex!.isFinite;

bool _isPointWithinBounds(Point point, Bounds bounds) =>
    point[0] >= bounds[0] &&
    point[1] >= bounds[1] &&
    point[0] <= bounds[2] &&
    point[1] <= bounds[3];

bool isBindableVisibleAtPoint(Point point, BindableState bindable) {
  final visibilityBounds = bindable.visibilityBounds;
  return visibilityBounds == null ||
      _isPointWithinBounds(point, visibilityBounds);
}

List<BindableState> sortBindablesByZIndex(List<BindableState> bindables) {
  final hasExplicitZOrder = bindables.any(_hasFiniteZIndex);
  if (!hasExplicitZOrder) {
    return bindables;
  }

  final indexed =
      bindables
          .asMap()
          .entries
          .map(
            (entry) => _ZIndexedBindable(
              bindable: entry.value,
              index: entry.key,
              zIndex: _hasFiniteZIndex(entry.value)
                  ? entry.value.zIndex!
                  : entry.key.toDouble(),
            ),
          )
          .toList()
        ..sort((left, right) {
          if (left.zIndex != right.zIndex) {
            return left.zIndex.compareTo(right.zIndex);
          }
          return left.index.compareTo(right.index);
        });

  return indexed.map((item) => item.bindable).toList(growable: false);
}

num _resolveRoundnessType(BindableRoundnessType type) {
  if (type is num) {
    return type;
  }

  if (type is String) {
    switch (type) {
      case 'legacy':
        return _bindableRoundnessLegacy;
      case 'proportional':
        return _bindableRoundnessProportional;
      case 'adaptive':
        return _bindableRoundnessAdaptive;
    }
  }

  return 0;
}

double _pointSegmentDistance(Point p, Point a, Point b) {
  final abx = b[0] - a[0];
  final aby = b[1] - a[1];
  final apx = p[0] - a[0];
  final apy = p[1] - a[1];
  final abLenSq = abx * abx + aby * aby;
  if (abLenSq <= _epsilon) {
    return distance(p, a);
  }

  final t = clamp((apx * abx + apy * aby) / abLenSq, 0, 1);
  final projection = <double>[a[0] + abx * t, a[1] + aby * t];
  return distance(p, projection);
}

Point _unrotateToLocal(Point point, BindableState bindable) {
  final c = center(bindable.x, bindable.y, bindable.width, bindable.height);
  return unrotatePoint(point, c, bindable.angle);
}

List<Point> _getDiamondVertices(BindableState bindable) {
  final topX = (bindable.width / 2).floor() + 1;
  final rightY = (bindable.height / 2).floor() + 1;

  final top = <double>[bindable.x + topX, bindable.y];
  final right = <double>[bindable.x + bindable.width, bindable.y + rightY];
  final bottom = <double>[bindable.x + topX, bindable.y + bindable.height];
  final left = <double>[bindable.x, bindable.y + rightY];

  return <Point>[top, right, bottom, left];
}

bool _isPointInConvexPolygon(Point point, List<Point> vertices) {
  var referenceSign = 0;

  for (var index = 0; index < vertices.length; index += 1) {
    final from = vertices[index];
    final to = vertices[(index + 1) % vertices.length];
    final cross =
        (to[0] - from[0]) * (point[1] - from[1]) -
        (to[1] - from[1]) * (point[0] - from[0]);

    if (cross.abs() <= _epsilon) {
      continue;
    }

    final sign = cross > 0 ? 1 : -1;
    if (referenceSign == 0) {
      referenceSign = sign;
      continue;
    }

    if (sign != referenceSign) {
      return false;
    }
  }

  return true;
}

bool isPointInBindable(Point point, BindableState bindable) {
  final shape = canonicalizeBindableShape(bindable.shape);
  final local = _unrotateToLocal(point, bindable);
  final x = local[0];
  final y = local[1];

  if (shape == 'rectangle') {
    return x >= bindable.x &&
        y >= bindable.y &&
        x <= bindable.x + bindable.width &&
        y <= bindable.y + bindable.height;
  }

  if (shape == 'ellipse') {
    final cx = bindable.x + bindable.width / 2;
    final cy = bindable.y + bindable.height / 2;
    final rx = math.max(bindable.width / 2, _epsilonRadius);
    final ry = math.max(bindable.height / 2, _epsilonRadius);
    final nx = (x - cx) / rx;
    final ny = (y - cy) / ry;
    return nx * nx + ny * ny <= 1;
  }

  return _isPointInConvexPolygon(local, _getDiamondVertices(bindable));
}

double _distanceToRectangleOutline(Point point, BindableState bindable) {
  final local = _unrotateToLocal(point, bindable);
  final minX = bindable.x;
  final minY = bindable.y;
  final maxX = bindable.x + bindable.width;
  final maxY = bindable.y + bindable.height;

  final inside =
      local[0] >= minX &&
      local[0] <= maxX &&
      local[1] >= minY &&
      local[1] <= maxY;

  if (inside) {
    return math.min(
      math.min((local[0] - minX).abs(), (maxX - local[0]).abs()),
      math.min((local[1] - minY).abs(), (maxY - local[1]).abs()),
    );
  }

  final clampedX = clamp(local[0], minX, maxX);
  final clampedY = clamp(local[1], minY, maxY);
  return distance(local, <double>[clampedX, clampedY]);
}

double _distanceToEllipseOutline(Point point, BindableState bindable) {
  final local = _unrotateToLocal(point, bindable);
  final cx = bindable.x + bindable.width / 2;
  final cy = bindable.y + bindable.height / 2;
  final rx = math.max(bindable.width / 2, _epsilonRadius);
  final ry = math.max(bindable.height / 2, _epsilonRadius);

  final dx = local[0] - cx;
  final dy = local[1] - cy;
  if (dx.abs() < _epsilon && dy.abs() < _epsilon) {
    return math.min(rx, ry);
  }

  final scale = 1 / math.sqrt((dx * dx) / (rx * rx) + (dy * dy) / (ry * ry));
  final projection = <double>[cx + dx * scale, cy + dy * scale];
  return distance(local, projection);
}

double _distanceToDiamondOutline(Point point, BindableState bindable) {
  final local = _unrotateToLocal(point, bindable);
  final vertices = _getDiamondVertices(bindable);
  final top = vertices[0];
  final right = vertices[1];
  final bottom = vertices[2];
  final left = vertices[3];

  final d1 = _pointSegmentDistance(local, top, right);
  final d2 = _pointSegmentDistance(local, right, bottom);
  final d3 = _pointSegmentDistance(local, bottom, left);
  final d4 = _pointSegmentDistance(local, left, top);

  return math.min(math.min(d1, d2), math.min(d3, d4));
}

double distanceToBindableOutline(Point point, BindableState bindable) {
  switch (canonicalizeBindableShape(bindable.shape)) {
    case 'rectangle':
      return _distanceToRectangleOutline(point, bindable);
    case 'ellipse':
      return _distanceToEllipseOutline(point, bindable);
    case 'diamond':
      return _distanceToDiamondOutline(point, bindable);
  }
  return double.nan;
}

double _resolveBindingHitThreshold(BindableState bindable, double tolerance) =>
    isBindableInteriorHitEnabled(bindable) ? tolerance : math.max(1, tolerance);

bool isPointNearBindableForBindingHit(
  Point point,
  BindableState bindable,
  double tolerance,
) {
  if (!isBindableBindingEnabled(bindable)) {
    return false;
  }
  if (!isBindableVisibleAtPoint(point, bindable)) {
    return false;
  }

  final threshold = _resolveBindingHitThreshold(bindable, tolerance);
  if (!isBindableInteriorHitEnabled(bindable)) {
    return distanceToBindableOutline(point, bindable) <= threshold;
  }

  return isPointInBindable(point, bindable) ||
      distanceToBindableOutline(point, bindable) <= threshold;
}

BindableState? getHoveredBindable(
  Point point,
  List<BindableState> zOrderedBindables,
  double tolerance,
) {
  final bindables = sortBindablesByZIndex(zOrderedBindables);
  final candidates = <BindableState>[];

  for (var index = bindables.length - 1; index >= 0; index -= 1) {
    final bindable = bindables[index];
    final hit = isPointNearBindableForBindingHit(point, bindable, tolerance);
    if (!hit) {
      continue;
    }

    candidates.add(bindable);
    if (isBindableBackgroundOpaque(bindable)) {
      break;
    }
  }

  if (candidates.isEmpty) {
    return null;
  }

  if (candidates.length == 1) {
    return candidates[0];
  }

  final sortedByLegacySize = List<BindableState>.from(candidates)
    ..sort((a, b) {
      final left = b.width * b.width + b.height * b.height;
      final right = a.width * a.width + a.height * a.height;
      return left.compareTo(right);
    });

  return sortedByLegacySize.isEmpty ? null : sortedByLegacySize.removeLast();
}

List<BindableState> getBindablesOverPoint(
  Point point,
  List<BindableState> zOrderedBindables,
  double tolerance,
) => sortBindablesByZIndex(zOrderedBindables)
    .where(
      (bindable) =>
          isPointNearBindableForBindingHit(point, bindable, tolerance),
    )
    .toList(growable: false);

List<Point> _sampleOutlinePoints(BindableState bindable, double offset) {
  final shape = canonicalizeBindableShape(bindable.shape);
  final bindableCenter = center(
    bindable.x,
    bindable.y,
    bindable.width,
    bindable.height,
  );

  if (shape == 'diamond') {
    final vertices = _getDiamondVertices(bindable);
    final top = vertices[0];
    final right = vertices[1];
    final bottom = vertices[2];
    final left = vertices[3];

    return <Point>[
      rotatePoint(
        <double>[top[0], top[1] - offset],
        bindableCenter,
        bindable.angle,
      ),
      rotatePoint(
        <double>[right[0] + offset, right[1]],
        bindableCenter,
        bindable.angle,
      ),
      rotatePoint(
        <double>[bottom[0], bottom[1] + offset],
        bindableCenter,
        bindable.angle,
      ),
      rotatePoint(
        <double>[left[0] - offset, left[1]],
        bindableCenter,
        bindable.angle,
      ),
    ];
  }

  if (shape == 'ellipse') {
    final cx = bindable.x + bindable.width / 2;
    final cy = bindable.y + bindable.height / 2;
    final rx = bindable.width / 2;
    final ry = bindable.height / 2;

    return <Point>[
      rotatePoint(
        <double>[cx, cy - ry - offset],
        bindableCenter,
        bindable.angle,
      ),
      rotatePoint(
        <double>[cx + rx + offset, cy],
        bindableCenter,
        bindable.angle,
      ),
      rotatePoint(
        <double>[cx, cy + ry + offset],
        bindableCenter,
        bindable.angle,
      ),
      rotatePoint(
        <double>[cx - rx - offset, cy],
        bindableCenter,
        bindable.angle,
      ),
    ];
  }

  return <Point>[
    rotatePoint(
      <double>[bindable.x - offset, bindable.y - offset],
      bindableCenter,
      bindable.angle,
    ),
    rotatePoint(
      <double>[bindable.x + bindable.width + offset, bindable.y - offset],
      bindableCenter,
      bindable.angle,
    ),
    rotatePoint(
      <double>[
        bindable.x + bindable.width + offset,
        bindable.y + bindable.height + offset,
      ],
      bindableCenter,
      bindable.angle,
    ),
    rotatePoint(
      <double>[bindable.x - offset, bindable.y + bindable.height + offset],
      bindableCenter,
      bindable.angle,
    ),
  ];
}

bool isBindableInsideOtherBindable(
  BindableState innerBindable,
  BindableState outerBindable,
) {
  final offset =
      (-1 * math.max(innerBindable.width, innerBindable.height)) / 20;
  final innerSamples = _sampleOutlinePoints(innerBindable, offset);
  return innerSamples.every(
    (sample) => isPointInBindable(sample, outerBindable),
  );
}

bool isBindableElementInsideOtherBindable(
  BindableState innerBindable,
  BindableState outerBindable,
) => isBindableInsideOtherBindable(innerBindable, outerBindable);

Point getBindingSideMidPoint(
  ({String elementId, Point fixedPoint}) binding,
  BindableState bindable,
) {
  final shape = canonicalizeBindableShape(bindable.shape);
  final side = _getShapeSide(normalizeFixedPoint(binding.fixedPoint), shape);
  final bindableCenter = center(
    bindable.x,
    bindable.y,
    bindable.width,
    bindable.height,
  );
  const offset = 0.01;
  const offsetDiagonal = offset * 0.707;

  Point midPoint(Point a, Point b) => <double>[
    (a[0] + b[0]) / 2,
    (a[1] + b[1]) / 2,
  ];

  double getCornerRadius(double size) {
    final roundness = bindable.roundness;
    if (roundness == null) {
      return 0;
    }

    final roundnessType = _resolveRoundnessType(roundness.type);
    if (roundnessType == _bindableRoundnessProportional ||
        roundnessType == _bindableRoundnessLegacy) {
      return size * 0.25;
    }

    if (roundnessType == _bindableRoundnessAdaptive) {
      final fixedRadius = roundness.value ?? 32;
      final cutoffSize = fixedRadius / 0.25;
      if (size <= cutoffSize) {
        return size * 0.25;
      }
      return fixedRadius;
    }

    return 0;
  }

  if (shape == 'diamond') {
    final topX = (bindable.width / 2).floor() + 1;
    const topY = 0;
    final rightX = bindable.width;
    final rightY = (bindable.height / 2).floor() + 1;
    final bottomX = topX;
    final bottomY = bindable.height;
    const leftX = 0;
    final leftY = rightY;

    final verticalRadius = bindable.roundness != null
        ? getCornerRadius((topX - leftX).abs().toDouble())
        : (topX - leftX) * 0.01;
    final horizontalRadius = bindable.roundness != null
        ? getCornerRadius((rightY - topY).abs().toDouble())
        : (rightY - topY) * 0.01;

    final top = <double>[bindable.x + topX, bindable.y + topY];
    final right = <double>[bindable.x + rightX, bindable.y + rightY];
    final bottom = <double>[bindable.x + bottomX, bindable.y + bottomY];
    final left = <double>[bindable.x + leftX, bindable.y + leftY];

    final rightCorner = <Point>[
      <double>[right[0] - verticalRadius, right[1] - horizontalRadius],
      right,
      right,
      <double>[right[0] - verticalRadius, right[1] + horizontalRadius],
    ];
    final bottomCorner = <Point>[
      <double>[bottom[0] + verticalRadius, bottom[1] - horizontalRadius],
      bottom,
      bottom,
      <double>[bottom[0] - verticalRadius, bottom[1] - horizontalRadius],
    ];
    final leftCorner = <Point>[
      <double>[left[0] + verticalRadius, left[1] + horizontalRadius],
      left,
      left,
      <double>[left[0] + verticalRadius, left[1] - horizontalRadius],
    ];
    final topCorner = <Point>[
      <double>[top[0] - verticalRadius, top[1] + horizontalRadius],
      top,
      top,
      <double>[top[0] + verticalRadius, top[1] + horizontalRadius],
    ];

    final bottomRight = <Point>[rightCorner[3], bottomCorner[0]];
    final bottomLeft = <Point>[bottomCorner[3], leftCorner[0]];
    final topLeft = <Point>[leftCorner[3], topCorner[0]];
    final topRight = <Point>[topCorner[3], rightCorner[0]];

    Point bezierPoint(List<Point> curve, double t) {
      final oneMinusT = 1 - t;
      final b0 = oneMinusT * oneMinusT * oneMinusT;
      final b1 = 3 * oneMinusT * oneMinusT * t;
      final b2 = 3 * oneMinusT * t * t;
      final b3 = t * t * t;

      return <double>[
        b0 * curve[0][0] +
            b1 * curve[1][0] +
            b2 * curve[2][0] +
            b3 * curve[3][0],
        b0 * curve[0][1] +
            b1 * curve[1][1] +
            b2 * curve[2][1] +
            b3 * curve[3][1],
      ];
    }

    Point legacyDiamondCornerSample(int flatCornerIndex) {
      const steps = 50;
      final i = flatCornerIndex;
      final t0 = ((i - 1) < 0 ? 0 : i - 1) / steps;
      final t1 = i / steps;
      final t2 = (i + 1) / steps;
      final p0 = bezierPoint(rightCorner, t0);
      final p1 = bezierPoint(rightCorner, t1);
      final p2 = bezierPoint(rightCorner, t2);

      return <double>[
        p1[0] + ((p2[0] - p0[0]) * 0.5) / 3,
        p1[1] + ((p2[1] - p0[1]) * 0.5) / 3,
      ];
    }

    var x = 0.0;
    var y = 0.0;

    switch (side) {
      case 'left':
        final p = legacyDiamondCornerSample(2);
        x = p[0] - offset;
        y = p[1];
        break;
      case 'right':
        final p = legacyDiamondCornerSample(0);
        x = p[0] + offset;
        y = p[1];
        break;
      case 'top':
        final p = legacyDiamondCornerSample(3);
        x = p[0];
        y = p[1] - offset;
        break;
      case 'bottom':
        final p = legacyDiamondCornerSample(1);
        x = p[0];
        y = p[1] + offset;
        break;
      case 'top-right':
        final p = midPoint(topRight[0], topRight[1]);
        x = p[0] + offsetDiagonal;
        y = p[1] - offsetDiagonal;
        break;
      case 'bottom-right':
        final p = midPoint(bottomRight[0], bottomRight[1]);
        x = p[0] + offsetDiagonal;
        y = p[1] + offsetDiagonal;
        break;
      case 'bottom-left':
        final p = midPoint(bottomLeft[0], bottomLeft[1]);
        x = p[0] - offsetDiagonal;
        y = p[1] + offsetDiagonal;
        break;
      case 'top-left':
      default:
        final p = midPoint(topLeft[0], topLeft[1]);
        x = p[0] - offsetDiagonal;
        y = p[1] - offsetDiagonal;
        break;
    }

    return rotatePoint(<double>[x, y], bindableCenter, bindable.angle);
  }

  if (shape == 'ellipse') {
    final ellipseCenterX = bindable.x + bindable.width / 2;
    final ellipseCenterY = bindable.y + bindable.height / 2;
    final radiusX = bindable.width / 2;
    final radiusY = bindable.height / 2;

    var x = 0.0;
    var y = 0.0;

    switch (side) {
      case 'top':
        x = ellipseCenterX;
        y = ellipseCenterY - radiusY - offset;
        break;
      case 'right':
        x = ellipseCenterX + radiusX + offset;
        y = ellipseCenterY;
        break;
      case 'bottom':
        x = ellipseCenterX;
        y = ellipseCenterY + radiusY + offset;
        break;
      case 'left':
        x = ellipseCenterX - radiusX - offset;
        y = ellipseCenterY;
        break;
      case 'top-right':
        const angle = -math.pi / 4;
        x = ellipseCenterX + radiusX * math.cos(angle) + offsetDiagonal;
        y = ellipseCenterY + radiusY * math.sin(angle) - offsetDiagonal;
        break;
      case 'bottom-right':
        const angle = math.pi / 4;
        x = ellipseCenterX + radiusX * math.cos(angle) + offsetDiagonal;
        y = ellipseCenterY + radiusY * math.sin(angle) + offsetDiagonal;
        break;
      case 'bottom-left':
        const angle = (3 * math.pi) / 4;
        x = ellipseCenterX + radiusX * math.cos(angle) - offsetDiagonal;
        y = ellipseCenterY + radiusY * math.sin(angle) + offsetDiagonal;
        break;
      case 'top-left':
      default:
        const angle = (-3 * math.pi) / 4;
        x = ellipseCenterX + radiusX * math.cos(angle) - offsetDiagonal;
        y = ellipseCenterY + radiusY * math.sin(angle) - offsetDiagonal;
        break;
    }

    return rotatePoint(<double>[x, y], bindableCenter, bindable.angle);
  }

  var radius = getCornerRadius(math.min(bindable.width, bindable.height));
  if (radius == 0) {
    radius = 0.01;
  }

  final top = <Point>[
    <double>[bindable.x + radius, bindable.y],
    <double>[bindable.x + bindable.width - radius, bindable.y],
  ];
  final right = <Point>[
    <double>[bindable.x + bindable.width, bindable.y + radius],
    <double>[
      bindable.x + bindable.width,
      bindable.y + bindable.height - radius,
    ],
  ];
  final bottom = <Point>[
    <double>[bindable.x + radius, bindable.y + bindable.height],
    <double>[
      bindable.x + bindable.width - radius,
      bindable.y + bindable.height,
    ],
  ];
  final left = <Point>[
    <double>[bindable.x, bindable.y + bindable.height - radius],
    <double>[bindable.x, bindable.y + radius],
  ];

  final topLeftCorner = <Point>[left[1], top[0]];
  final topRightCorner = <Point>[top[1], right[0]];
  final bottomRightCorner = <Point>[right[1], bottom[1]];
  final bottomLeftCorner = <Point>[bottom[0], left[0]];

  var x = 0.0;
  var y = 0.0;

  switch (side) {
    case 'top':
      final p = midPoint(top[0], top[1]);
      x = p[0];
      y = p[1] - offset;
      break;
    case 'right':
      final p = midPoint(right[0], right[1]);
      x = p[0] + offset;
      y = p[1];
      break;
    case 'bottom':
      final p = midPoint(bottom[0], bottom[1]);
      x = p[0];
      y = p[1] + offset;
      break;
    case 'left':
      final p = midPoint(left[0], left[1]);
      x = p[0] - offset;
      y = p[1];
      break;
    case 'top-left':
      final p = midPoint(topLeftCorner[0], topLeftCorner[1]);
      x = p[0] - offsetDiagonal;
      y = p[1] - offsetDiagonal;
      break;
    case 'top-right':
      final p = midPoint(topRightCorner[0], topRightCorner[1]);
      x = p[0] + offsetDiagonal;
      y = p[1] - offsetDiagonal;
      break;
    case 'bottom-right':
      final p = midPoint(bottomRightCorner[0], bottomRightCorner[1]);
      x = p[0] + offsetDiagonal;
      y = p[1] + offsetDiagonal;
      break;
    case 'bottom-left':
    default:
      final p = midPoint(bottomLeftCorner[0], bottomLeftCorner[1]);
      x = p[0] - offsetDiagonal;
      y = p[1] + offsetDiagonal;
      break;
  }

  return rotatePoint(<double>[x, y], bindableCenter, bindable.angle);
}

double _normalizeDegrees(double degrees) => ((degrees % 360) + 360) % 360;

_BindingSide _getShapeSide(Point fixedPoint, CanonicalBindableShape shape) {
  final config = _shapeSectors[shape];
  if (config == null) {
    throw StateError('Unsupported bindable shape: $shape');
  }
  final centeredX = fixedPoint[0] - 0.5;
  final centeredY = fixedPoint[1] - 0.5;
  final radians = math.atan2(centeredY, centeredX);
  final degrees = _normalizeDegrees((radians * 180) / math.pi);

  for (final sector in config) {
    final half = sector.sectorWidth / 2;
    final start = _normalizeDegrees(sector.centerAngle - half);
    final end = _normalizeDegrees(sector.centerAngle + half);
    final inRange = start <= end
        ? degrees >= start && degrees <= end
        : degrees >= start || degrees <= end;
    if (inRange) {
      return sector.side;
    }
  }

  var nearest = config[0];
  var nearestDistance = double.infinity;
  for (final sector in config) {
    var distanceToSector = (degrees - sector.centerAngle).abs();
    if (distanceToSector > 180) {
      distanceToSector = 360 - distanceToSector;
    }
    if (distanceToSector < nearestDistance) {
      nearestDistance = distanceToSector;
      nearest = sector;
    }
  }

  return nearest.side;
}
