import 'dart:ui';

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

/// Resolves the serial number connector map using the global cache.
///
/// This is the preferred method for rendering as it uses version-based
/// caching to avoid recomputing connectors on every paint cycle.
SerialNumberConnectorMap resolveSerialNumberConnectorMap(
  DrawStateView stateView,
) => SerialNumberConnectorCache.instance.resolve(stateView);

void drawSerialNumberConnectorsForText({
  required Canvas canvas,
  required ElementState textElement,
  required SerialNumberConnectorMap connectorsByTextId,
}) {
  if (textElement.data is! TextData) {
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
