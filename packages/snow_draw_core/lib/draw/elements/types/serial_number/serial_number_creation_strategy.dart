import 'dart:math' as math;

import 'package:meta/meta.dart';

import '../../../config/draw_config.dart';
import '../../../elements/core/element_data.dart';
import '../../../models/draw_state.dart';
import '../../../models/interaction_state.dart';
import '../../../services/grid_snap_service.dart';
import '../../../types/draw_point.dart';
import '../../../types/draw_rect.dart';
import '../../../utils/snapping_mode.dart';
import '../../core/creation_strategy.dart';
import 'serial_number_data.dart';
import 'serial_number_layout.dart';

@immutable
class SerialNumberCreationStrategy extends CreationStrategy {
  const SerialNumberCreationStrategy();

  @override
  CreationUpdateResult start({
    required ElementData data,
    required DrawPoint startPosition,
  }) {
    final serialData = data is SerialNumberData
        ? data
        : const SerialNumberData();
    final layoutSignature = _SerialNumberLayoutSignature.fromData(serialData);
    final baseDiameter = _resolveBaseDiameter(serialData);
    final diameter = _resolveDiameterWithMin(
      baseDiameter: baseDiameter,
      minDiameter: ConfigDefaults.minCreateElementSize,
    );
    return CreationUpdateResult(
      data: serialData,
      rect: _rectFromCenter(startPosition, diameter),
      creationMode: _SerialNumberCreationMode(
        baseDiameter: baseDiameter,
        layoutSignature: layoutSignature,
      ),
    );
  }

  @override
  CreationUpdateResult update({
    required DrawState state,
    required DrawConfig config,
    required CreatingState creatingState,
    required DrawPoint currentPosition,
    required bool maintainAspectRatio,
    required bool createFromCenter,
    required SnappingMode snappingMode,
  }) {
    final serialData = creatingState.elementData is SerialNumberData
        ? creatingState.elementData as SerialNumberData
        : const SerialNumberData();
    final snappedPosition = snappingMode == SnappingMode.grid
        ? gridSnapService.snapPoint(
            point: currentPosition,
            gridSize: config.grid.size,
          )
        : currentPosition;
    final layoutSignature = _SerialNumberLayoutSignature.fromData(serialData);
    final cachedMode = creatingState.creationMode;
    final serialCreationMode =
        cachedMode is _SerialNumberCreationMode &&
            cachedMode.layoutSignature == layoutSignature
        ? cachedMode
        : null;
    final baseDiameter =
        serialCreationMode?.baseDiameter ?? _resolveBaseDiameter(serialData);
    final diameter = _resolveDiameterWithMin(
      baseDiameter: baseDiameter,
      minDiameter: config.element.minCreateSize,
    );
    final nextCreationMode =
        serialCreationMode ??
        _SerialNumberCreationMode(
          baseDiameter: baseDiameter,
          layoutSignature: layoutSignature,
        );
    return CreationUpdateResult(
      data: serialData,
      rect: _rectFromCenter(snappedPosition, diameter),
      creationMode: nextCreationMode,
    );
  }

  @override
  CreationFinishResult finish({
    required DrawConfig config,
    required CreatingState creatingState,
  }) {
    final rect = creatingState.currentRect;
    final minSize = config.element.minCreateSize;
    final updatedElement = creatingState.element.copyWith(rect: rect);
    final isValid =
        rect.width >= minSize &&
        rect.height >= minSize &&
        updatedElement.isValidWith(config.element);
    return CreationFinishResult(
      data: creatingState.elementData,
      rect: rect,
      shouldCommit: isValid,
    );
  }
}

double _resolveBaseDiameter(SerialNumberData data) =>
    resolveSerialNumberDiameter(data: data);

double _resolveDiameterWithMin({
  required double baseDiameter,
  required double minDiameter,
}) {
  if (!baseDiameter.isFinite) {
    return minDiameter;
  }
  return math.max(baseDiameter, minDiameter);
}

DrawRect _rectFromCenter(DrawPoint center, double size) => DrawRect(
  minX: center.x - size / 2,
  minY: center.y - size / 2,
  maxX: center.x + size / 2,
  maxY: center.y + size / 2,
);

@immutable
class _SerialNumberCreationMode extends CreationMode {
  const _SerialNumberCreationMode({
    required this.baseDiameter,
    required this.layoutSignature,
  });

  final double baseDiameter;
  final _SerialNumberLayoutSignature layoutSignature;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is _SerialNumberCreationMode &&
          other.baseDiameter == baseDiameter &&
          other.layoutSignature == layoutSignature;

  @override
  int get hashCode => Object.hash(baseDiameter, layoutSignature);
}

@immutable
class _SerialNumberLayoutSignature {
  const _SerialNumberLayoutSignature({
    required this.number,
    required this.fontSize,
    required this.fontFamily,
  });

  factory _SerialNumberLayoutSignature.fromData(SerialNumberData data) =>
      _SerialNumberLayoutSignature(
        number: data.number,
        fontSize: data.fontSize,
        fontFamily: _normalizeFontFamily(data.fontFamily),
      );

  final int number;
  final double fontSize;
  final String? fontFamily;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is _SerialNumberLayoutSignature &&
          other.number == number &&
          other.fontSize == fontSize &&
          other.fontFamily == fontFamily;

  @override
  int get hashCode => Object.hash(number, fontSize, fontFamily);
}

String? _normalizeFontFamily(String? fontFamily) {
  final trimmed = fontFamily?.trim();
  if (trimmed == null || trimmed.isEmpty) {
    return null;
  }
  return trimmed;
}
