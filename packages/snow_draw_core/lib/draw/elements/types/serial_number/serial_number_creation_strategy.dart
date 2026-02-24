import 'package:meta/meta.dart';

import '../../../config/draw_config.dart';
import '../../../elements/core/element_data.dart';
import '../../../models/draw_state.dart';
import '../../../models/interaction_state.dart';
import '../../../services/text/text_metrics_service.dart';
import '../../../types/draw_point.dart';
import '../../../types/draw_rect.dart';
import '../../../utils/snapping_mode.dart';
import '../../../utils/string_normalization.dart';
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
    TextMetricsService textMetricsService = defaultTextMetricsService,
  }) {
    final serialData = _resolveSerialData(data);
    final baseDiameter = resolveSerialNumberDiameter(
      data: serialData,
      textMetricsService: textMetricsService,
    );
    final diameter = _resolveDiameterWithMin(
      baseDiameter: baseDiameter,
      minDiameter: ConfigDefaults.minCreateElementSize,
    );
    final mode = _SerialNumberCreationMode.fromData(
      data: serialData,
      baseDiameter: baseDiameter,
    );

    return CreationUpdateResult(
      data: serialData,
      rect: _rectFromCenter(startPosition, diameter),
      creationMode: mode,
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
    TextMetricsService textMetricsService = defaultTextMetricsService,
  }) {
    final serialData = _resolveSerialData(creatingState.elementData);
    final snappedPosition = snapCreationPoint(
      point: currentPosition,
      config: config,
      snappingMode: snappingMode,
    );
    final cachedMode = _resolveCreationMode(creatingState.creationMode);
    final reuseCachedMode = cachedMode?.matches(serialData) ?? false;
    final baseDiameter = reuseCachedMode
        ? cachedMode!.baseDiameter
        : resolveSerialNumberDiameter(
            data: serialData,
            textMetricsService: textMetricsService,
          );
    final diameter = _resolveDiameterWithMin(
      baseDiameter: baseDiameter,
      minDiameter: config.element.minCreateSize,
    );
    final nextCreationMode = reuseCachedMode
        ? cachedMode!
        : _SerialNumberCreationMode.fromData(
            data: serialData,
            baseDiameter: baseDiameter,
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
    TextMetricsService textMetricsService = defaultTextMetricsService,
  }) => finishCreationWithCurrentRect(
    config: config,
    creatingState: creatingState,
  );
}

SerialNumberData _resolveSerialData(ElementData data) =>
    data is SerialNumberData ? data : const SerialNumberData();

_SerialNumberCreationMode? _resolveCreationMode(CreationMode mode) =>
    mode is _SerialNumberCreationMode ? mode : null;

double _resolveDiameterWithMin({
  required double baseDiameter,
  required double minDiameter,
}) {
  if (!baseDiameter.isFinite) {
    return minDiameter;
  }
  return baseDiameter >= minDiameter ? baseDiameter : minDiameter;
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
    required this.number,
    required this.fontSize,
    required this.fontFamily,
  });

  factory _SerialNumberCreationMode.fromData({
    required SerialNumberData data,
    required double baseDiameter,
  }) => _SerialNumberCreationMode(
    baseDiameter: baseDiameter,
    number: data.number,
    fontSize: data.fontSize,
    fontFamily: normalizeOptionalTrimmedString(data.fontFamily),
  );

  final double baseDiameter;
  final int number;
  final double fontSize;
  final String? fontFamily;

  bool matches(SerialNumberData data) =>
      number == data.number &&
      fontSize == data.fontSize &&
      fontFamily == normalizeOptionalTrimmedString(data.fontFamily);
}
