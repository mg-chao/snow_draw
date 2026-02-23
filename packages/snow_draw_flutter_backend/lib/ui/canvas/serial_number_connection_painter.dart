import 'dart:ui';

import 'package:meta/meta.dart';

import 'package:snow_draw_core/snow_draw_core.dart';
import 'serial_number_connector_cache.dart';

class SerialNumberTextConnector {
  const SerialNumberTextConnector({
    required this.connection,
    required this.paint,
  });

  final SerialNumberTextConnection connection;
  final Paint paint;
}

typedef SerialNumberConnectorMap = Map<String, List<SerialNumberTextConnector>>;

/// Immutable snapshot of serial-number connector resolution for one frame.
@immutable
class SerialNumberConnectorSnapshot {
  const SerialNumberConnectorSnapshot({
    required this.connectorsByTextId,
    required this.dynamicTextElementIds,
  });

  /// Connectors grouped by bound text element id.
  final SerialNumberConnectorMap connectorsByTextId;

  /// Text ids whose connector visuals can change for this frame.
  ///
  /// Dynamic scene caching should treat these text elements as dynamic so
  /// connector removals and geometry updates are reflected immediately.
  final Set<String> dynamicTextElementIds;
}

/// Resolves serial-number connector data using the global cache.
///
/// This is the preferred method for rendering as it exposes both the
/// connector payload and the minimal dynamic text set for interaction caching.
SerialNumberConnectorSnapshot resolveSerialNumberConnectorSnapshot(
  DrawStateView stateView, {
  Map<String, ElementState>? previewElementsById,
  Set<String>? visibleTextElementIds,
}) => SerialNumberConnectorCache.instance.resolve(
  stateView,
  previewElementsById: previewElementsById,
  visibleTextElementIds: visibleTextElementIds,
);

/// Resolves only the serial-number connector map.
///
/// Prefer [resolveSerialNumberConnectorSnapshot] when interaction-scene
/// caching decisions need the dynamic connector text ids.
SerialNumberConnectorMap resolveSerialNumberConnectorMap(
  DrawStateView stateView, {
  Map<String, ElementState>? previewElementsById,
  Set<String>? visibleTextElementIds,
}) => resolveSerialNumberConnectorSnapshot(
  stateView,
  previewElementsById: previewElementsById,
  visibleTextElementIds: visibleTextElementIds,
).connectorsByTextId;

void drawSerialNumberConnectorsForText({
  required Canvas canvas,
  required String textElementId,
  required SerialNumberConnectorMap connectorsByTextId,
}) {
  final connectors = connectorsByTextId[textElementId];
  if (connectors == null) {
    return;
  }

  for (final connector in connectors) {
    final baselineStart = connector.connection.textBaselineStart;
    final baselineEnd = connector.connection.textBaselineEnd;
    if (baselineStart != null && baselineEnd != null) {
      canvas.drawLine(
        Offset(baselineStart.x, baselineStart.y),
        Offset(baselineEnd.x, baselineEnd.y),
        connector.paint,
      );
    }
    canvas.drawLine(
      Offset(connector.connection.start.x, connector.connection.start.y),
      Offset(connector.connection.end.x, connector.connection.end.y),
      connector.paint,
    );
  }
}
