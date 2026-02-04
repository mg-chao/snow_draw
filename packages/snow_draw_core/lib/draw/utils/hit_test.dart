import 'dart:math' as math;

import '../config/draw_config.dart';
import '../elements/core/element_data.dart';
import '../elements/core/element_registry_interface.dart';
import '../elements/core/element_type_id.dart';
import '../elements/types/arrow/arrow_like_data.dart';
import '../elements/types/serial_number/serial_number_data.dart';
import '../elements/types/text/text_data.dart';
import '../models/draw_state.dart';
import '../models/draw_state_view.dart';
import '../models/edit_enums.dart';
import '../models/element_state.dart';
import '../services/log/log_service.dart';
import '../types/draw_point.dart';
import '../types/draw_rect.dart';

final ModuleLogger _hitTestFallbackLog = LogService.fallback.element;
const _hitTestCacheSize = 4;
const _hitTestCacheGridSize = 4.0;
final _hitTestCache = _HitTestCache();

/// Hit test target.
enum HitTestTarget { none, handle, element, selectionPadding }

/// Hit test result.
class HitTestResult {
  const HitTestResult({
    this.elementId,
    this.handleType,
    this.cursorHint,
    this.selectionRotation,
    this.target = HitTestTarget.none,
    this.isInSelectionPadding = false,
  });

  /// Hit element id.
  final String? elementId;

  /// Hit handle type (when hitting selection handles).
  final HandleType? handleType;

  /// Suggested cursor type for the hit result.
  final CursorHint? cursorHint;

  /// Selection overlay rotation in radians (when hitting handles).
  final double? selectionRotation;

  /// Target type for the hit result.
  final HitTestTarget target;

  /// True if the position is inside the selection padded area.
  final bool isInSelectionPadding;

  /// True if either an element or a handle was hit.
  bool get isHit => target != HitTestTarget.none;

  /// True if a handle was hit.
  bool get isHandleHit => target == HitTestTarget.handle;

  /// True if an element body was hit.
  bool get isElementHit => target == HitTestTarget.element;

  /// True if the selection padding area was hit.
  bool get isSelectionPaddingHit => target == HitTestTarget.selectionPadding;

  /// Represents "no hit".
  static const none = HitTestResult(cursorHint: CursorHint.basic);

  @override
  String toString() =>
      'HitTestResult(elementId: $elementId, handleType: $handleType, '
      'cursorHint: $cursorHint, selectionRotation: $selectionRotation, '
      'target: $target, isInSelectionPadding: $isInSelectionPadding)';
}

/// Selection handle type.
enum HandleType {
  /// Top-left corner.
  topLeft,

  /// Top edge.
  top,

  /// Top-right corner.
  topRight,

  /// Right edge.
  right,

  /// Bottom-right corner.
  bottomRight,

  /// Bottom edge.
  bottom,

  /// Bottom-left corner.
  bottomLeft,

  /// Left edge.
  left,

  /// Rotation handle.
  rotate,
}

/// Cursor type hint for hit test results.
enum CursorHint {
  basic,
  move,
  resizeUpLeftDownRight,
  resizeUpRightDownLeft,
  resizeUp,
  resizeDown,
  resizeLeft,
  resizeRight,
  rotate,
}

/// Hit test utilities.
///
/// Detects whether a pointer position hits an element or selection handles.
class HitTest {
  const HitTest();

  /// Returns true if `position` is inside the current selection overlay
  /// bounds, including the visual padding area (and taking overlay rotation
  /// into account).
  bool isInSelectionPaddedArea({
    required DrawStateView stateView,
    required DrawPoint position,
    required SelectionConfig config,
  }) {
    final selection = stateView.effectiveSelection;
    final selectedIds = stateView.state.domain.selection.selectedIds;
    if (selectedIds.length == 1) {
      final element = stateView.state.domain.document.getElementById(
        selectedIds.first,
      );
      if (element != null && element.data is ArrowLikeData) {
        final data = element.data as ArrowLikeData;
        if (data.points.length == 2) {
          return false;
        }
      }
    }
    final context = _buildSelectionContext(
      selection: selection,
      position: position,
      config: config,
      cornerHandleOffset: 0,
    );
    if (context == null) {
      return false;
    }

    return _testPaddedSelectionAreaWithContext(context);
  }

  /// Performs hit testing on the canvas.
  ///
  /// Returns information about the hit element or handle, if any.
  ///
  /// If [filterTypeId] is provided, only elements matching that type will
  /// be considered.
  HitTestResult test({
    required DrawStateView stateView,
    required DrawPoint position,
    required SelectionConfig config,
    required ElementRegistry registry,
    double? tolerance,
    ElementTypeId<ElementData>? filterTypeId,
  }) {
    final state = stateView.state;
    final actualTolerance = tolerance ?? config.interaction.handleTolerance;
    final quantizedX = _quantizePosition(position.x);
    final quantizedY = _quantizePosition(position.y);
    final cachedResult = _hitTestCache.lookup(
      state: state,
      config: config,
      tolerance: actualTolerance,
      filterTypeId: filterTypeId,
      positionX: quantizedX,
      positionY: quantizedY,
    );
    if (cachedResult != null) {
      return cachedResult;
    }

    final selection = stateView.effectiveSelection;
    final selectedIds = state.domain.selection.selectedIds;
    final document = state.domain.document;
    final boundTextIds = filterTypeId == SerialNumberData.typeIdToken
        ? _collectBoundTextIds(document.elements)
        : null;

    // Determine corner handle offset for single arrow selections.
    ArrowLikeData? singleSelectedArrow;
    if (selectedIds.length == 1) {
      final element = state.domain.document.getElementById(selectedIds.first);
      if (element != null) {
        final effectiveElement = stateView.effectiveElement(element);
        final data = effectiveElement.data;
        if (data is ArrowLikeData) {
          singleSelectedArrow = data;
        }
      }
    }
    final cornerHandleOffset = singleSelectedArrow != null ? 8 : 0;

    // Check if this is a single 2-point arrow selection.
    // For 2-point arrows, skip handle hit testing since all operations
    // can be performed through the point editor.
    final isSingleTwoPointArrow =
        singleSelectedArrow != null && singleSelectedArrow.points.length == 2;

    _SelectionHitContext? selectionContext;
    var isInSelectionPadding = false;
    // 1. Check selection handles first (skip for 2-point arrows).
    if (selection.hasSelection && !isSingleTwoPointArrow) {
      selectionContext = _buildSelectionContext(
        selection: selection,
        position: position,
        config: config,
        cornerHandleOffset: cornerHandleOffset,
      );
      if (selectionContext != null) {
        isInSelectionPadding = _testPaddedSelectionAreaWithContext(
          selectionContext,
        );
        final handleResult = _testHandles(
          context: selectionContext,
          position: position,
          tolerance: actualTolerance,
          config: config,
          isInSelectionPadding: isInSelectionPadding,
        );
        if (handleResult != null) {
          return _storeCache(
            result: handleResult,
            state: state,
            config: config,
            tolerance: actualTolerance,
            filterTypeId: filterTypeId,
            positionX: quantizedX,
            positionY: quantizedY,
          );
        }
      }
    }

    // 2. Check elements using spatial index (top-most first).
    final candidates = document.spatialIndex.searchPointEntries(
      position,
      actualTolerance,
    );
    for (final entry in candidates) {
      final candidate = document.getElementById(entry.id);
      if (candidate == null) {
        continue;
      }
      if (filterTypeId != null && candidate.typeId != filterTypeId) {
        if (!_allowsSerialBoundText(
          filterTypeId: filterTypeId,
          candidate: candidate,
          boundTextIds: boundTextIds,
        )) {
          continue;
        }
      }
      final element = stateView.effectiveElement(candidate);
      if (!_testElement(element, position, registry, actualTolerance)) {
        continue;
      }
      return _storeCache(
        result: HitTestResult(
          elementId: element.id,
          cursorHint: CursorHint.move,
          target: HitTestTarget.element,
          isInSelectionPadding: isInSelectionPadding,
        ),
        state: state,
        config: config,
        tolerance: actualTolerance,
        filterTypeId: filterTypeId,
        positionX: quantizedX,
        positionY: quantizedY,
      );
    }

    // 3. Check the padded selection area (allows dragging from padding).
    // (Used to support starting a move by dragging from the selection
    // padding area.) Skip for 2-point arrows.
    if (selectionContext != null && selectedIds.isNotEmpty) {
      if (isInSelectionPadding) {
        final firstSelectedId = selectedIds.first;
        return _storeCache(
          result: HitTestResult(
            elementId: firstSelectedId,
            cursorHint: CursorHint.move,
            target: HitTestTarget.selectionPadding,
            isInSelectionPadding: true,
          ),
          state: state,
          config: config,
          tolerance: actualTolerance,
          filterTypeId: filterTypeId,
          positionX: quantizedX,
          positionY: quantizedY,
        );
      }
    }

    return _storeCache(
      result: HitTestResult(
        cursorHint: HitTestResult.none.cursorHint,
        isInSelectionPadding: isInSelectionPadding,
      ),
      state: state,
      config: config,
      tolerance: actualTolerance,
      filterTypeId: filterTypeId,
      positionX: quantizedX,
      positionY: quantizedY,
    );
  }

  bool _allowsSerialBoundText({
    required ElementTypeId<ElementData>? filterTypeId,
    required ElementState candidate,
    required Set<String>? boundTextIds,
  }) {
    if (filterTypeId != SerialNumberData.typeIdToken) {
      return false;
    }
    if (candidate.data is! TextData) {
      return false;
    }
    return boundTextIds?.contains(candidate.id) ?? false;
  }

  Set<String> _collectBoundTextIds(List<ElementState> elements) {
    final boundTextIds = <String>{};
    for (final element in elements) {
      final data = element.data;
      if (data is SerialNumberData && data.textElementId != null) {
        boundTextIds.add(data.textElementId!);
      }
    }
    return boundTextIds;
  }

  /// Tests whether [position] hits any selection handle.
  HitTestResult? _testHandles({
    required _SelectionHitContext context,
    required DrawPoint position,
    required double tolerance,
    required SelectionConfig config,
    required bool isInSelectionPadding,
  }) {
    final bounds = context.bounds;
    final paddedBounds = context.paddedBounds;
    final handleBounds = context.handleBounds;
    final testPosition = context.testPosition;
    final rotation = context.rotation;
    final padding = config.padding;

    // Check rotation handle first (same position math as rendering).
    final margin = config.rotateHandleOffset;
    final rotateHandleX = bounds.centerX;
    final rotateHandleY = bounds.minY - padding - margin;
    if (_isNearRotatedPoint(
      position: position,
      localX: rotateHandleX,
      localY: rotateHandleY,
      context: context,
      tolerance: tolerance,
    )) {
      return HitTestResult(
        handleType: HandleType.rotate,
        cursorHint: CursorHint.rotate,
        selectionRotation: rotation,
        target: HitTestTarget.handle,
        isInSelectionPadding: isInSelectionPadding,
      );
    }

    // Check 4 corner handles first (higher priority for precise
    // resizing). Use handleBounds for corner positions.
    final minX = handleBounds.minX;
    final minY = handleBounds.minY;
    final maxX = handleBounds.maxX;
    final maxY = handleBounds.maxY;

    if (_isNearRotatedPoint(
      position: position,
      localX: minX,
      localY: minY,
      context: context,
      tolerance: tolerance,
    )) {
      return HitTestResult(
        handleType: HandleType.topLeft,
        cursorHint: _cursorHintForHandle(HandleType.topLeft),
        selectionRotation: rotation,
        target: HitTestTarget.handle,
        isInSelectionPadding: isInSelectionPadding,
      );
    }

    if (_isNearRotatedPoint(
      position: position,
      localX: maxX,
      localY: minY,
      context: context,
      tolerance: tolerance,
    )) {
      return HitTestResult(
        handleType: HandleType.topRight,
        cursorHint: _cursorHintForHandle(HandleType.topRight),
        selectionRotation: rotation,
        target: HitTestTarget.handle,
        isInSelectionPadding: isInSelectionPadding,
      );
    }

    if (_isNearRotatedPoint(
      position: position,
      localX: maxX,
      localY: maxY,
      context: context,
      tolerance: tolerance,
    )) {
      return HitTestResult(
        handleType: HandleType.bottomRight,
        cursorHint: _cursorHintForHandle(HandleType.bottomRight),
        selectionRotation: rotation,
        target: HitTestTarget.handle,
        isInSelectionPadding: isInSelectionPadding,
      );
    }

    if (_isNearRotatedPoint(
      position: position,
      localX: minX,
      localY: maxY,
      context: context,
      tolerance: tolerance,
    )) {
      return HitTestResult(
        handleType: HandleType.bottomLeft,
        cursorHint: _cursorHintForHandle(HandleType.bottomLeft),
        selectionRotation: rotation,
        target: HitTestTarget.handle,
        isInSelectionPadding: isInSelectionPadding,
      );
    }

    // Check 4 edges (excluding corner regions).
    // Perform edge checks in local space.
    if (_testTopEdge(paddedBounds, testPosition, tolerance)) {
      return HitTestResult(
        handleType: HandleType.top,
        cursorHint: CursorHint.resizeUp,
        selectionRotation: rotation,
        target: HitTestTarget.handle,
        isInSelectionPadding: isInSelectionPadding,
      );
    }
    if (_testRightEdge(paddedBounds, testPosition, tolerance)) {
      return HitTestResult(
        handleType: HandleType.right,
        cursorHint: CursorHint.resizeRight,
        selectionRotation: rotation,
        target: HitTestTarget.handle,
        isInSelectionPadding: isInSelectionPadding,
      );
    }
    if (_testBottomEdge(paddedBounds, testPosition, tolerance)) {
      return HitTestResult(
        handleType: HandleType.bottom,
        cursorHint: CursorHint.resizeDown,
        selectionRotation: rotation,
        target: HitTestTarget.handle,
        isInSelectionPadding: isInSelectionPadding,
      );
    }
    if (_testLeftEdge(paddedBounds, testPosition, tolerance)) {
      return HitTestResult(
        handleType: HandleType.left,
        cursorHint: CursorHint.resizeLeft,
        selectionRotation: rotation,
        target: HitTestTarget.handle,
        isInSelectionPadding: isInSelectionPadding,
      );
    }

    return null;
  }

  _SelectionHitContext? _buildSelectionContext({
    required EffectiveSelection selection,
    required DrawPoint position,
    required SelectionConfig config,
    required num cornerHandleOffset,
  }) {
    if (!selection.hasSelection) {
      return null;
    }

    final bounds = selection.bounds;
    if (bounds == null) {
      return null;
    }

    final rotation = selection.rotation ?? 0.0;
    final origin = selection.center ?? bounds.center;
    final cos = rotation == 0.0 ? 1.0 : math.cos(rotation);
    final sin = rotation == 0.0 ? 0.0 : math.sin(rotation);
    final padding = config.padding;
    final cornerOffset = cornerHandleOffset.toDouble();
    final paddedBounds = DrawRect(
      minX: bounds.minX - padding,
      minY: bounds.minY - padding,
      maxX: bounds.maxX + padding,
      maxY: bounds.maxY + padding,
    );
    final handleBounds = DrawRect(
      minX: paddedBounds.minX - cornerOffset,
      minY: paddedBounds.minY - cornerOffset,
      maxX: paddedBounds.maxX + cornerOffset,
      maxY: paddedBounds.maxY + cornerOffset,
    );
    final testPosition = rotation == 0
        ? position
        : DrawPoint(
            x:
                origin.x +
                (position.x - origin.x) * cos +
                (position.y - origin.y) * sin,
            y:
                origin.y -
                (position.x - origin.x) * sin +
                (position.y - origin.y) * cos,
          );

    return _SelectionHitContext(
      bounds: bounds,
      rotation: rotation,
      origin: origin,
      cos: cos,
      sin: sin,
      paddedBounds: paddedBounds,
      handleBounds: handleBounds,
      testPosition: testPosition,
    );
  }

  bool _testPaddedSelectionAreaWithContext(_SelectionHitContext context) {
    final testPosition = context.testPosition;
    final paddedBounds = context.paddedBounds;
    return testPosition.x >= paddedBounds.minX &&
        testPosition.x <= paddedBounds.maxX &&
        testPosition.y >= paddedBounds.minY &&
        testPosition.y <= paddedBounds.maxY;
  }

  HitTestResult _storeCache({
    required HitTestResult result,
    required DrawState state,
    required SelectionConfig config,
    required double tolerance,
    required ElementTypeId<ElementData>? filterTypeId,
    required int positionX,
    required int positionY,
  }) {
    _hitTestCache.store(
      _HitTestCacheEntry(
        state: state,
        config: config,
        tolerance: tolerance,
        filterTypeId: filterTypeId,
        positionX: positionX,
        positionY: positionY,
        result: result,
      ),
    );
    return result;
  }

  int _quantizePosition(double value) =>
      (value / _hitTestCacheGridSize).floor();

  /// Tests whether the pointer hits the element itself.
  bool _testElement(
    ElementState element,
    DrawPoint position,
    ElementRegistry registry,
    double tolerance,
  ) {
    final definition = registry.getDefinition(element.typeId);
    if (definition == null) {
      final message =
          'Unknown element type "${element.typeId}" '
          'encountered during hit test';
      _hitTestFallbackLog.warning(message, {'typeId': element.typeId});
      final rect = element.rect;
      return position.x >= rect.minX &&
          position.x <= rect.maxX &&
          position.y >= rect.minY &&
          position.y <= rect.maxY;
    }
    return definition.hitTester.hitTest(
      element: element,
      position: position,
      tolerance: tolerance,
    );
  }

  bool _isNearRotatedPoint({
    required DrawPoint position,
    required double localX,
    required double localY,
    required _SelectionHitContext context,
    required double tolerance,
  }) {
    if (context.rotation == 0) {
      return _isNearPointCoordinates(position, localX, localY, tolerance);
    }

    final origin = context.origin;
    final dx = localX - origin.x;
    final dy = localY - origin.y;
    final worldX = origin.x + dx * context.cos - dy * context.sin;
    final worldY = origin.y + dx * context.sin + dy * context.cos;
    return _isNearPointCoordinates(position, worldX, worldY, tolerance);
  }

  bool _isNearPointCoordinates(
    DrawPoint a,
    double bx,
    double by,
    double tolerance,
  ) {
    final dx = a.x - bx;
    final dy = a.y - by;
    return (dx * dx + dy * dy) <= tolerance * tolerance;
  }

  /// Tests whether the pointer hits the top edge (excluding corner regions).
  bool _testTopEdge(DrawRect bounds, DrawPoint position, double tolerance) {
    // Y coordinate is near the top edge.
    if (!_isNearY(position.y, bounds.minY, tolerance)) {
      return false;
    }
    // X coordinate is between left/right, excluding corner regions.
    final cornerOffset = tolerance; // Corner hit radius.
    return position.x > bounds.minX + cornerOffset &&
        position.x < bounds.maxX - cornerOffset;
  }

  /// Tests whether the pointer hits the right edge (excluding corner regions).
  bool _testRightEdge(DrawRect bounds, DrawPoint position, double tolerance) {
    // X coordinate is near the right edge.
    if (!_isNearX(position.x, bounds.maxX, tolerance)) {
      return false;
    }
    // Y coordinate is between top/bottom, excluding corner regions.
    final cornerOffset = tolerance;
    return position.y > bounds.minY + cornerOffset &&
        position.y < bounds.maxY - cornerOffset;
  }

  /// Tests whether the pointer hits the bottom edge (excluding corner regions).
  bool _testBottomEdge(DrawRect bounds, DrawPoint position, double tolerance) {
    // Y coordinate is near the bottom edge.
    if (!_isNearY(position.y, bounds.maxY, tolerance)) {
      return false;
    }
    // X coordinate is between left/right, excluding corner regions.
    final cornerOffset = tolerance;
    return position.x > bounds.minX + cornerOffset &&
        position.x < bounds.maxX - cornerOffset;
  }

  /// Tests whether the pointer hits the left edge (excluding corner regions).
  bool _testLeftEdge(DrawRect bounds, DrawPoint position, double tolerance) {
    // X coordinate is near the left edge.
    if (!_isNearX(position.x, bounds.minX, tolerance)) {
      return false;
    }
    // Y coordinate is between top/bottom, excluding corner regions.
    final cornerOffset = tolerance;
    return position.y > bounds.minY + cornerOffset &&
        position.y < bounds.maxY - cornerOffset;
  }

  /// Returns true if [x] is within [tolerance] of [target].
  bool _isNearX(double x, double target, double tolerance) =>
      (x - target).abs() <= tolerance;

  /// Returns true if [y] is within [tolerance] of [target].
  bool _isNearY(double y, double target, double tolerance) =>
      (y - target).abs() <= tolerance;

  /// Maps a selection [handle] to a resize mode.
  ResizeMode? getResizeModeForHandle(HandleType handle) {
    switch (handle) {
      case HandleType.topLeft:
        return ResizeMode.topLeft;
      case HandleType.top:
        return ResizeMode.top;
      case HandleType.topRight:
        return ResizeMode.topRight;
      case HandleType.right:
        return ResizeMode.right;
      case HandleType.bottomRight:
        return ResizeMode.bottomRight;
      case HandleType.bottom:
        return ResizeMode.bottom;
      case HandleType.bottomLeft:
        return ResizeMode.bottomLeft;
      case HandleType.left:
        return ResizeMode.left;
      case HandleType.rotate:
        return null; // Rotate is not a resize operation.
    }
  }

  CursorHint _cursorHintForHandle(HandleType handle) {
    switch (handle) {
      case HandleType.topLeft:
      case HandleType.bottomRight:
        return CursorHint.resizeUpLeftDownRight;
      case HandleType.topRight:
      case HandleType.bottomLeft:
        return CursorHint.resizeUpRightDownLeft;
      case HandleType.top:
        return CursorHint.resizeUp;
      case HandleType.bottom:
        return CursorHint.resizeDown;
      case HandleType.left:
        return CursorHint.resizeLeft;
      case HandleType.right:
        return CursorHint.resizeRight;
      case HandleType.rotate:
        return CursorHint.rotate;
    }
  }
}

class _SelectionHitContext {
  const _SelectionHitContext({
    required this.bounds,
    required this.rotation,
    required this.origin,
    required this.cos,
    required this.sin,
    required this.paddedBounds,
    required this.handleBounds,
    required this.testPosition,
  });

  final DrawRect bounds;
  final double rotation;
  final DrawPoint origin;
  final double cos;
  final double sin;
  final DrawRect paddedBounds;
  final DrawRect handleBounds;
  final DrawPoint testPosition;
}

class _HitTestCacheEntry {
  const _HitTestCacheEntry({
    required this.state,
    required this.config,
    required this.tolerance,
    required this.filterTypeId,
    required this.positionX,
    required this.positionY,
    required this.result,
  });

  final DrawState state;
  final SelectionConfig config;
  final double tolerance;
  final ElementTypeId<ElementData>? filterTypeId;
  final int positionX;
  final int positionY;
  final HitTestResult result;

  bool matches({
    required DrawState state,
    required SelectionConfig config,
    required double tolerance,
    required ElementTypeId<ElementData>? filterTypeId,
    required int positionX,
    required int positionY,
  }) =>
      identical(this.state, state) &&
      this.positionX == positionX &&
      this.positionY == positionY &&
      this.tolerance == tolerance &&
      this.filterTypeId == filterTypeId &&
      this.config == config;
}

class _HitTestCache {
  final _entries = <_HitTestCacheEntry>[];

  HitTestResult? lookup({
    required DrawState state,
    required SelectionConfig config,
    required double tolerance,
    required ElementTypeId<ElementData>? filterTypeId,
    required int positionX,
    required int positionY,
  }) {
    for (var i = 0; i < _entries.length; i++) {
      final entry = _entries[i];
      if (entry.matches(
        state: state,
        config: config,
        tolerance: tolerance,
        filterTypeId: filterTypeId,
        positionX: positionX,
        positionY: positionY,
      )) {
        if (i != 0) {
          _entries
            ..removeAt(i)
            ..insert(0, entry);
        }
        return entry.result;
      }
    }
    return null;
  }

  void store(_HitTestCacheEntry entry) {
    if (_entries.length >= _hitTestCacheSize) {
      _entries.removeLast();
    }
    _entries.insert(0, entry);
  }
}

/// Shared hit-test helper instance.
const hitTest = HitTest();
