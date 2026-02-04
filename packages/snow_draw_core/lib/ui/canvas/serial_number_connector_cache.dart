import 'dart:ui';

import '../../draw/elements/types/arrow/arrow_binding_resolver.dart' show ArrowBindingResolver;
import '../../draw/elements/types/serial_number/serial_number_binding.dart';
import '../../draw/elements/types/serial_number/serial_number_data.dart';
import '../../draw/elements/types/serial_number/serial_number_layout.dart';
import '../../draw/elements/types/text/text_data.dart';
import '../../draw/models/document_state.dart';
import '../../draw/models/draw_state_view.dart';
import '../../draw/models/element_state.dart';
import 'serial_number_connection_painter.dart';

/// Cached serial number connector resolver.
///
/// Maintains a cached index of serial number bindings and computed connectors
/// to avoid rebuilding on every paint cycle. Uses version-based invalidation
/// similar to [ArrowBindingResolver].
class SerialNumberConnectorCache {
  SerialNumberConnectorCache._();

  static final instance = SerialNumberConnectorCache._();

  var _cachedDocumentVersion = -1;
  Map<String, String> _bindingIndex = const {};
  Map<String, _CachedConnectorEntry> _connectorCache = const {};

  /// Resolves the connector map for rendering.
  ///
  /// Uses cached data when possible, rebuilding only when:
  /// - Document version changes
  /// - Preview elements affect bound serial numbers or text elements
  SerialNumberConnectorMap resolve(DrawStateView stateView) {
    final document = stateView.state.domain.document;
    final previewElementsById = stateView.previewElementsById;

    // Fast path: no elements
    if (document.elements.isEmpty && previewElementsById.isEmpty) {
      return const <String, List<SerialNumberTextConnector>>{};
    }

    // Check if we need to rebuild the binding index
    final documentVersion = document.elementsVersion;
    if (_shouldRebuildIndex(documentVersion)) {
      _rebuildBindingIndex(document);
      _cachedDocumentVersion = documentVersion;
    }

    // If no bindings exist, return empty
    if (_bindingIndex.isEmpty) {
      return const <String, List<SerialNumberTextConnector>>{};
    }

    // Determine which connectors need recomputation
    final affectedSerialIds = _resolveAffectedSerialIds(
      previewElementsById: previewElementsById,
    );

    // Build the result map
    return _buildConnectorMap(
      document: document,
      previewElementsById: previewElementsById,
      affectedSerialIds: affectedSerialIds,
    );
  }

  /// Invalidates the cache, forcing a full rebuild on next resolve.
  void invalidate() {
    _cachedDocumentVersion = -1;
    _bindingIndex = const {};
    _connectorCache = const {};
  }

  bool _shouldRebuildIndex(int documentVersion) {
    if (_cachedDocumentVersion == -1) {
      return true;
    }
    if (documentVersion < _cachedDocumentVersion) {
      // Version went backwards (e.g., undo), rebuild
      return true;
    }
    if (documentVersion != _cachedDocumentVersion) {
      return true;
    }
    return false;
  }

  void _rebuildBindingIndex(DocumentState document) {
    final newIndex = <String, String>{};
    _connectorCache = {};

    for (final element in document.elements) {
      final data = element.data;
      if (data is! SerialNumberData) {
        continue;
      }
      final textId = data.textElementId;
      if (textId == null) {
        continue;
      }
      // Verify the text element exists
      final textElement = document.getElementById(textId);
      if (textElement == null || textElement.data is! TextData) {
        continue;
      }
      newIndex[element.id] = textId;
    }

    _bindingIndex = newIndex;
  }

  Set<String> _resolveAffectedSerialIds({
    required Map<String, ElementState> previewElementsById,
  }) {
    if (previewElementsById.isEmpty) {
      return const {};
    }

    final affected = <String>{};

    for (final previewId in previewElementsById.keys) {
      // If the preview is a serial number with a binding, it's affected
      if (_bindingIndex.containsKey(previewId)) {
        affected.add(previewId);
        continue;
      }

      // If the preview is a text element bound to a serial number, find it
      for (final entry in _bindingIndex.entries) {
        if (entry.value == previewId) {
          affected.add(entry.key);
        }
      }
    }

    return affected;
  }

  SerialNumberConnectorMap _buildConnectorMap({
    required DocumentState document,
    required Map<String, ElementState> previewElementsById,
    required Set<String> affectedSerialIds,
  }) {
    final result = <String, List<SerialNumberTextConnector>>{};

    for (final entry in _bindingIndex.entries) {
      final serialId = entry.key;
      final textId = entry.value;

      // Get effective elements (preview or document)
      final serialElement =
          previewElementsById[serialId] ?? document.getElementById(serialId);
      if (serialElement == null) {
        continue;
      }

      final serialData = serialElement.data;
      if (serialData is! SerialNumberData) {
        continue;
      }

      final textElement =
          previewElementsById[textId] ?? document.getElementById(textId);
      if (textElement == null || textElement.data is! TextData) {
        continue;
      }

      // Check if we can use cached connector
      final isAffected = affectedSerialIds.contains(serialId);
      final cachedEntry = _connectorCache[serialId];

      SerialNumberTextConnector? connector;

      if (!isAffected && cachedEntry != null && previewElementsById.isEmpty) {
        // Use cached connector if not affected and no previews
        connector = cachedEntry.connector;
      } else {
        // Compute new connector
        connector = _computeConnector(
          serialElement: serialElement,
          serialData: serialData,
          textElement: textElement,
        );

        // Cache if no previews (stable state)
        if (previewElementsById.isEmpty && connector != null) {
          _connectorCache[serialId] = _CachedConnectorEntry(
            connector: connector,
          );
        }
      }

      if (connector != null) {
        result
            .putIfAbsent(textId, () => <SerialNumberTextConnector>[])
            .add(connector);
      }
    }

    return result;
  }

  SerialNumberTextConnector? _computeConnector({
    required ElementState serialElement,
    required SerialNumberData serialData,
    required ElementState textElement,
  }) {
    final lineWidth = resolveSerialNumberStrokeWidth(data: serialData);
    final connection = resolveSerialNumberTextConnection(
      serialElement: serialElement,
      textElement: textElement,
      lineWidth: lineWidth,
    );

    if (connection == null) {
      return null;
    }

    final opacity = (serialData.color.a * serialElement.opacity).clamp(
      0.0,
      1.0,
    );
    if (opacity <= 0 || lineWidth <= 0) {
      return null;
    }

    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = lineWidth
      ..color = serialData.color.withValues(alpha: opacity)
      ..strokeCap = StrokeCap.round
      ..isAntiAlias = true;

    return SerialNumberTextConnector(connection: connection, paint: paint);
  }
}

class _CachedConnectorEntry {
  const _CachedConnectorEntry({required this.connector});

  final SerialNumberTextConnector connector;
}
