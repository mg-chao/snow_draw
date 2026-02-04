import 'dart:ui';

import '../../draw/elements/types/serial_number/serial_number_binding.dart';
import '../../draw/elements/types/serial_number/serial_number_data.dart';
import '../../draw/elements/types/serial_number/serial_number_layout.dart';
import '../../draw/elements/types/text/text_data.dart';
import '../../draw/models/draw_state_view.dart';
import '../../draw/models/element_state.dart';

class SerialNumberTextConnector {
  const SerialNumberTextConnector({
    required this.connection,
    required this.paint,
  });

  final SerialNumberTextConnection connection;
  final Paint paint;
}

typedef SerialNumberConnectorMap =
    Map<String, List<SerialNumberTextConnector>>;

SerialNumberConnectorMap buildSerialNumberConnectorMap(
  DrawStateView stateView,
) {
  final document = stateView.state.domain.document;
  if (document.elements.isEmpty) {
    return const <String, List<SerialNumberTextConnector>>{};
  }

  final elementsById = {
    ...document.elementMap,
    ...stateView.previewElementsById,
  };
  final connectors = <String, List<SerialNumberTextConnector>>{};

  for (final element in document.elements) {
    if (element.data is! SerialNumberData) {
      continue;
    }

    final effectiveSerial = stateView.effectiveElement(element);
    final serialData = effectiveSerial.data;
    if (serialData is! SerialNumberData) {
      continue;
    }

    final textId = serialData.textElementId;
    if (textId == null) {
      continue;
    }
    final textElement = elementsById[textId];
    if (textElement == null || textElement.data is! TextData) {
      continue;
    }

    final effectiveText = stateView.effectiveElement(textElement);
    final lineWidth = resolveSerialNumberStrokeWidth(data: serialData);
    final connection = resolveSerialNumberTextConnection(
      serialElement: effectiveSerial,
      textElement: effectiveText,
      lineWidth: lineWidth,
    );
    if (connection == null) {
      continue;
    }

    final opacity = (serialData.color.a * effectiveSerial.opacity).clamp(
      0.0,
      1.0,
    );
    if (opacity <= 0 || lineWidth <= 0) {
      continue;
    }

    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = lineWidth
      ..color = serialData.color.withValues(alpha: opacity)
      ..strokeCap = StrokeCap.round
      ..isAntiAlias = true;

    connectors
        .putIfAbsent(textId, () => <SerialNumberTextConnector>[])
        .add(SerialNumberTextConnector(connection: connection, paint: paint));
  }

  return connectors;
}

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
