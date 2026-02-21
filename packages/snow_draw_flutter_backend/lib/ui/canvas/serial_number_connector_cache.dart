import 'dart:ui';

import 'package:meta/meta.dart';

import 'package:snow_draw_core/draw/elements/types/serial_number/serial_number_binding.dart';
import 'package:snow_draw_core/draw/elements/types/serial_number/serial_number_data.dart';
import 'package:snow_draw_core/draw/elements/types/serial_number/serial_number_layout.dart';
import 'package:snow_draw_core/draw/elements/types/text/text_data.dart';
import 'package:snow_draw_core/draw/models/document_state.dart';
import 'package:snow_draw_core/draw/models/draw_state_view.dart';
import 'package:snow_draw_core/draw/models/element_state.dart';
import 'package:snow_draw_core/draw/utils/lru_cache.dart';
import '../../extensions/draw_color_extensions.dart';
import 'serial_number_connection_painter.dart';

/// Cached serial number connector resolver.
///
/// Maintains a cached index of serial number bindings and computed connectors
/// to avoid rebuilding on every paint cycle. Uses version-based invalidation
/// to avoid rebuilding the index when the document is unchanged.
class SerialNumberConnectorCache {
  SerialNumberConnectorCache._();

  static final instance = SerialNumberConnectorCache._();
  static const _emptySnapshot = SerialNumberConnectorSnapshot(
    connectorsByTextId: <String, List<SerialNumberTextConnector>>{},
    dynamicTextElementIds: <String>{},
  );

  var _cachedDocumentVersion = -1;
  Map<String, String> _bindingIndex = const {};
  Map<String, Set<String>> _reverseBindingIndex = const {};
  Map<String, _CachedConnectorEntry> _connectorCache = const {};

  /// Resolves connector data for rendering and interaction caching.
  ///
  /// Uses cached data when possible, rebuilding only when:
  /// - Document version changes
  /// - Preview elements affect bound serial numbers or text elements
  SerialNumberConnectorSnapshot resolve(
    DrawStateView stateView, {
    Map<String, ElementState>? previewElementsById,
    Set<String>? visibleTextElementIds,
  }) {
    final document = stateView.state.domain.document;
    final effectivePreviewElements =
        previewElementsById ?? stateView.previewElementsById;

    // Fast path: no elements
    if (document.elements.isEmpty && effectivePreviewElements.isEmpty) {
      return _emptySnapshot;
    }

    // Check if we need to rebuild the binding index
    final documentVersion = document.elementsVersion;
    if (_shouldRebuildIndex(documentVersion)) {
      _rebuildBindingIndex(document);
      _cachedDocumentVersion = documentVersion;
    }

    final visibleTextIds = _normalizeVisibleTextIds(
      document: document,
      previewElementsById: effectivePreviewElements,
      visibleTextElementIds: visibleTextElementIds,
    );

    if (visibleTextIds.isEmpty) {
      return _emptySnapshot;
    }

    final candidateSerialIds = _resolveCandidateSerialIds(
      previewElementsById: effectivePreviewElements,
      visibleTextIds: visibleTextIds,
    );
    if (candidateSerialIds.isEmpty) {
      return _emptySnapshot;
    }

    // Determine which connectors need recomputation and dynamic redraw.
    final affectedSerialIds = _resolveAffectedSerialIds(
      document: document,
      previewElementsById: effectivePreviewElements,
    );

    final dynamicTextElementIds = _resolveDynamicConnectorTextIds(
      affectedSerialIds: affectedSerialIds,
      document: document,
      previewElementsById: effectivePreviewElements,
      visibleTextIds: visibleTextIds,
    );

    // Build the connector snapshot.
    return _buildConnectorSnapshot(
      document: document,
      previewElementsById: effectivePreviewElements,
      affectedSerialIds: affectedSerialIds,
      candidateSerialIds: candidateSerialIds,
      visibleTextIds: visibleTextIds,
      dynamicTextElementIds: dynamicTextElementIds,
    );
  }

  /// Invalidates the cache, forcing a full rebuild on next resolve.
  void invalidate() {
    _cachedDocumentVersion = -1;
    _bindingIndex = const {};
    _reverseBindingIndex = const {};
    _connectorCache = const {};
  }

  bool _shouldRebuildIndex(int documentVersion) =>
      _cachedDocumentVersion != documentVersion;

  void _rebuildBindingIndex(DocumentState document) {
    final newIndex = <String, String>{};
    final newReverse = <String, Set<String>>{};
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
      (newReverse[textId] ??= <String>{}).add(element.id);
    }

    _bindingIndex = newIndex;
    _reverseBindingIndex = newReverse;
  }

  Set<String> _resolveAffectedSerialIds({
    required DocumentState document,
    required Map<String, ElementState> previewElementsById,
  }) {
    if (previewElementsById.isEmpty) {
      return const {};
    }

    final affected = <String>{};

    for (final preview in previewElementsById.values) {
      final previewId = preview.id;
      final persisted = document.getElementById(previewId);
      if (persisted != null && persisted == preview) {
        continue;
      }
      final previewData = preview.data;
      final previewHasBinding =
          previewData is SerialNumberData &&
          previewData.textElementId != null &&
          previewData.textElementId!.isNotEmpty;
      if (previewHasBinding || _bindingIndex.containsKey(previewId)) {
        affected.add(previewId);
      }

      // O(1) reverse lookup: text element -> bound serial numbers
      final boundSerials = _reverseBindingIndex[previewId];
      if (boundSerials != null) {
        affected.addAll(boundSerials);
      }
    }

    return affected;
  }

  SerialNumberConnectorSnapshot _buildConnectorSnapshot({
    required DocumentState document,
    required Map<String, ElementState> previewElementsById,
    required Set<String> affectedSerialIds,
    required Set<String> candidateSerialIds,
    required Set<String> visibleTextIds,
    required Set<String> dynamicTextElementIds,
  }) {
    final result = <String, List<SerialNumberTextConnector>>{};

    for (final serialId in candidateSerialIds) {
      final previewSerialElement = previewElementsById[serialId];
      final serialElement =
          previewSerialElement ?? document.getElementById(serialId);
      if (serialElement == null) {
        continue;
      }

      final serialData = serialElement.data;
      if (serialData is! SerialNumberData) {
        continue;
      }

      final textId = serialData.textElementId;
      if (textId == null ||
          textId.isEmpty ||
          !visibleTextIds.contains(textId)) {
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

      if (!isAffected && cachedEntry != null) {
        // Use cached connector whenever this serial is unaffected.
        connector = cachedEntry.connector;
      } else {
        // Compute new connector
        connector = _computeConnector(
          serialElement: serialElement,
          serialData: serialData,
          textElement: textElement,
        );

        // Cache only in stable document state.
        if (!isAffected && previewElementsById.isEmpty && connector != null) {
          _connectorCache[serialId] = _CachedConnectorEntry(
            textId: textId,
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

    if (result.isEmpty) {
      if (dynamicTextElementIds.isEmpty) {
        return _emptySnapshot;
      }
      return SerialNumberConnectorSnapshot(
        connectorsByTextId: const <String, List<SerialNumberTextConnector>>{},
        dynamicTextElementIds: dynamicTextElementIds,
      );
    }

    return SerialNumberConnectorSnapshot(
      connectorsByTextId: result,
      dynamicTextElementIds: dynamicTextElementIds,
    );
  }

  Set<String> _resolveDynamicConnectorTextIds({
    required Set<String> affectedSerialIds,
    required DocumentState document,
    required Map<String, ElementState> previewElementsById,
    required Set<String> visibleTextIds,
  }) {
    if (affectedSerialIds.isEmpty) {
      return const <String>{};
    }

    final dynamicTextIds = <String>{};

    for (final serialId in affectedSerialIds) {
      final previousTextId =
          _connectorCache[serialId]?.textId ?? _bindingIndex[serialId];
      if (previousTextId != null && visibleTextIds.contains(previousTextId)) {
        dynamicTextIds.add(previousTextId);
      }

      final effectiveSerial =
          previewElementsById[serialId] ?? document.getElementById(serialId);
      final data = effectiveSerial?.data;
      if (data is! SerialNumberData) {
        continue;
      }
      final textId = data.textElementId;
      if (textId == null ||
          textId.isEmpty ||
          !visibleTextIds.contains(textId)) {
        continue;
      }
      dynamicTextIds.add(textId);
    }

    if (dynamicTextIds.isEmpty) {
      return const <String>{};
    }
    return dynamicTextIds;
  }

  Set<String> _normalizeVisibleTextIds({
    required DocumentState document,
    required Map<String, ElementState> previewElementsById,
    required Set<String>? visibleTextElementIds,
  }) {
    if (visibleTextElementIds == null) {
      final allVisible = <String>{};
      for (final element in document.elements) {
        if (element.data is TextData && element.opacity > 0) {
          allVisible.add(element.id);
        }
      }
      for (final preview in previewElementsById.values) {
        if (preview.data is! TextData) {
          continue;
        }
        if (preview.opacity > 0) {
          allVisible.add(preview.id);
        } else {
          allVisible.remove(preview.id);
        }
      }
      return allVisible;
    }
    if (visibleTextElementIds.isEmpty) {
      return const <String>{};
    }

    final normalized = <String>{};
    for (final textId in visibleTextElementIds) {
      final preview = previewElementsById[textId];
      if (preview != null) {
        // Callers that pass explicit text ids may intentionally include
        // hidden editing previews so serial connectors remain visible while
        // the text glyphs are rendered by the input overlay.
        if (preview.data is TextData) {
          normalized.add(textId);
        }
        continue;
      }
      final element = document.getElementById(textId);
      if (element != null && element.data is TextData) {
        normalized.add(textId);
      }
    }
    return normalized;
  }

  Set<String> _resolveCandidateSerialIds({
    required Map<String, ElementState> previewElementsById,
    required Set<String> visibleTextIds,
  }) {
    final candidateSerialIds = <String>{};
    for (final textId in visibleTextIds) {
      final boundSerials = _reverseBindingIndex[textId];
      if (boundSerials != null) {
        candidateSerialIds.addAll(boundSerials);
      }
    }

    for (final preview in previewElementsById.values) {
      final data = preview.data;
      if (data is! SerialNumberData) {
        continue;
      }
      final textId = data.textElementId;
      if (textId == null || textId.isEmpty) {
        continue;
      }
      if (visibleTextIds.contains(textId)) {
        candidateSerialIds.add(preview.id);
      }
    }

    return candidateSerialIds;
  }

  SerialNumberTextConnector? _computeConnector({
    required ElementState serialElement,
    required SerialNumberData serialData,
    required ElementState textElement,
  }) {
    final lineWidth = resolveSerialNumberStrokeWidth(data: serialData);
    if (lineWidth <= 0) {
      return null;
    }

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
    if (opacity <= 0) {
      return null;
    }

    final color = serialData.color
        .withValues(alpha: opacity)
        .toFlutterColor();
    final paint = _paintCache.getOrCreate(
      _PaintKey(color: color, strokeWidth: lineWidth),
      () => Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = lineWidth
        ..color = color
        ..strokeCap = StrokeCap.round
        ..isAntiAlias = true,
    );

    return SerialNumberTextConnector(connection: connection, paint: paint);
  }

  static final _paintCache = LruCache<_PaintKey, Paint>(maxEntries: 32);
}

class _CachedConnectorEntry {
  const _CachedConnectorEntry({required this.textId, required this.connector});

  final String textId;
  final SerialNumberTextConnector connector;
}

@immutable
class _PaintKey {
  const _PaintKey({required this.color, required this.strokeWidth});

  final Color color;
  final double strokeWidth;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is _PaintKey &&
          other.color == color &&
          other.strokeWidth == strokeWidth;

  @override
  int get hashCode => Object.hash(color, strokeWidth);
}
