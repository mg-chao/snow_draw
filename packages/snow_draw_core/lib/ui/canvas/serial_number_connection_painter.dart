import 'dart:ui';

import 'package:meta/meta.dart';

import '../../draw/elements/types/serial_number/serial_number_binding.dart';
import '../../draw/elements/types/text/text_data.dart';
import '../../draw/models/draw_state_view.dart';
import '../../draw/models/element_state.dart';
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
  required ElementState textElement,
  required SerialNumberConnectorMap connectorsByTextId,
}) {
  if (textElement.data is! TextData || textElement.opacity <= 0) {
    return;
  }

  final connectors = connectorsByTextId[textElement.id];
  if (connectors == null || connectors.isEmpty) {
    return;
  }

  for (final connector in connectors) {
    final connection = connector.connection;
    final paint = connector.paint;
    final textBaselineStart = connection.textBaselineStart;
    final textBaselineEnd = connection.textBaselineEnd;
    if (textBaselineStart != null && textBaselineEnd != null) {
      canvas.drawLine(
        Offset(textBaselineStart.x, textBaselineStart.y),
        Offset(textBaselineEnd.x, textBaselineEnd.y),
        paint,
      );
    }
    canvas.drawLine(
      Offset(connection.start.x, connection.start.y),
      Offset(connection.end.x, connection.end.y),
      paint,
    );
  }
}
