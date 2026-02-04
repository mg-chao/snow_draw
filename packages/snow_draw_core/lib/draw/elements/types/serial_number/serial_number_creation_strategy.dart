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
    final diameter = resolveSerialNumberDiameter(
      data: serialData,
      minDiameter: ConfigDefaults.minCreateElementSize,
    );
    return CreationUpdateResult(
      data: serialData,
      rect: _rectFromPosition(startPosition, diameter),
      creationMode: const RectCreationMode(),
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
    final diameter = resolveSerialNumberDiameter(
      data: serialData,
      minDiameter: config.element.minCreateSize,
    );
    return CreationUpdateResult(
      data: serialData,
      rect: _rectFromPosition(snappedPosition, diameter),
      creationMode: creatingState.creationMode,
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

DrawRect _rectFromPosition(DrawPoint origin, double size) => DrawRect(
  minX: origin.x,
  minY: origin.y,
  maxX: origin.x + size,
  maxY: origin.y + size,
);
