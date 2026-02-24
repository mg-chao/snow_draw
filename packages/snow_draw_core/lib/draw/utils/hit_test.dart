import 'dart:math' as math;

import '../config/draw_config.dart';
import '../elements/core/element_data.dart';
import '../elements/core/element_registry_interface.dart';
import '../elements/core/element_type_id.dart';
import '../elements/types/serial_number/serial_number_data.dart';
import '../elements/types/text/text_data.dart';
import '../models/draw_state.dart';
import '../models/draw_state_view.dart';
import '../models/element_state.dart';
import '../services/log/log_service.dart';
import '../types/draw_point.dart';
import '../types/draw_rect.dart';
import '../types/resize_mode.dart';
import 'single_selection_profile.dart';

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
    final document = stateView.state.domain.document;
    final singleSelection = resolveSingleSelectionProfile(
      selectedIds: selectedIds,
      resolveElementById: (id) {
        final element = document.getElementById(id);
        return element == null ? null : stateView.effectiveElement(element);
      },
    );
    if (singleSelection.isTwoPointArrow) {
      return false;
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
      registry: registry,
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
        ? document.boundTextIds
        : null;
    HitTestResult cache(HitTestResult result) => _storeCache(
      result: result,
      state: state,
      config: config,
      tolerance: actualTolerance,
      filterTypeId: filterTypeId,
      registry: registry,
      positionX: quantizedX,
      positionY: quantizedY,
    );

    // Determine corner handle offset for single arrow selections.
    final singleSelection = resolveSingleSelectionProfile(
      selectedIds: selectedIds,
      resolveElementById: (id) {
        final element = document.getElementById(id);
        return element == null ? null : stateView.effectiveElement(element);
      },
    );
    final cornerHandleOffset = singleSelection.cornerHandleOffset;

    // Check if this is a single 2-point arrow selection.
    // For 2-point arrows, skip handle hit testing since all operations
    // can be performed through the point editor.
    final isSingleTwoPointArrow = singleSelection.isTwoPointArrow;
    final isSingleElbowArrow = singleSelection.isElbowArrow;

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
          prioritizeMoveInSelectionPadding: singleSelection.isText,
          allowRotateHandle: !isSingleElbowArrow,
        );
        if (handleResult != null) {
          return cache(handleResult);
        }
      }
    }

    // 2. Check elements using spatial index (top-most first).
    ElementState? hitElement;
    document.visitElementsAtPointTopDown(position, actualTolerance, (
      candidate,
    ) {
      final passesFilter =
          filterTypeId == null ||
          candidate.typeId == filterTypeId ||
          (filterTypeId == SerialNumberData.typeIdToken &&
              candidate.data is TextData &&
              (boundTextIds?.contains(candidate.id) ?? false));
      if (!passesFilter) {
        return true;
      }
      final element = stateView.effectiveElement(candidate);
      if (!_testElement(element, position, registry, actualTolerance)) {
        return true;
      }
      hitElement = element;
      return false;
    });
    if (hitElement != null) {
      return cache(
        HitTestResult(
          elementId: hitElement!.id,
          cursorHint: CursorHint.move,
          target: HitTestTarget.element,
          isInSelectionPadding: isInSelectionPadding,
        ),
      );
    }

    // 3. Check the padded selection area (allows dragging from padding).
    // (Used to support starting a move by dragging from the selection
    // padding area.) Skip for 2-point arrows.
    if (selectionContext != null &&
        isInSelectionPadding &&
        selectedIds.isNotEmpty) {
      return cache(
        HitTestResult(
          elementId: selectedIds.first,
          cursorHint: CursorHint.move,
          target: HitTestTarget.selectionPadding,
          isInSelectionPadding: true,
        ),
      );
    }

    return cache(
      HitTestResult(
        cursorHint: HitTestResult.none.cursorHint,
        isInSelectionPadding: isInSelectionPadding,
      ),
    );
  }

  /// Tests whether [position] hits any selection handle.
  HitTestResult? _testHandles({
    required _SelectionHitContext context,
    required DrawPoint position,
    required double tolerance,
    required SelectionConfig config,
    required bool isInSelectionPadding,
    bool prioritizeMoveInSelectionPadding = false,
    bool allowRotateHandle = true,
  }) {
    // For selected text, keep move as the primary action while the pointer is
    // in the padded move area; only allow resize handles from outside.
    if (prioritizeMoveInSelectionPadding && isInSelectionPadding) {
      return null;
    }

    final bounds = context.bounds;
    final paddedBounds = context.paddedBounds;
    final handleBounds = context.handleBounds;
    final testPosition = context.testPosition;
    final rotation = context.rotation;
    final padding = config.padding;

    // Check rotation handle first (same position math as rendering).
    if (allowRotateHandle) {
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
        return _buildHandleHitResult(
          handle: HandleType.rotate,
          rotation: rotation,
          isInSelectionPadding: isInSelectionPadding,
        );
      }
    }

    final cornerHandle = _resolveCornerHandle(
      handleBounds: handleBounds,
      position: position,
      context: context,
      tolerance: tolerance,
    );
    if (cornerHandle != null) {
      return _buildHandleHitResult(
        handle: cornerHandle,
        rotation: rotation,
        isInSelectionPadding: isInSelectionPadding,
      );
    }

    final edgeHandle = _resolveEdgeHandle(
      paddedBounds: paddedBounds,
      position: testPosition,
      tolerance: tolerance,
    );
    if (edgeHandle != null) {
      return _buildHandleHitResult(
        handle: edgeHandle,
        rotation: rotation,
        isInSelectionPadding: isInSelectionPadding,
      );
    }

    return null;
  }

  HitTestResult _buildHandleHitResult({
    required HandleType handle,
    required double rotation,
    required bool isInSelectionPadding,
  }) => HitTestResult(
    handleType: handle,
    cursorHint: _cursorHintForHandle(handle),
    selectionRotation: rotation,
    target: HitTestTarget.handle,
    isInSelectionPadding: isInSelectionPadding,
  );

  HandleType? _resolveCornerHandle({
    required DrawRect handleBounds,
    required DrawPoint position,
    required _SelectionHitContext context,
    required double tolerance,
  }) {
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
      return HandleType.topLeft;
    }
    if (_isNearRotatedPoint(
      position: position,
      localX: maxX,
      localY: minY,
      context: context,
      tolerance: tolerance,
    )) {
      return HandleType.topRight;
    }
    if (_isNearRotatedPoint(
      position: position,
      localX: maxX,
      localY: maxY,
      context: context,
      tolerance: tolerance,
    )) {
      return HandleType.bottomRight;
    }
    if (_isNearRotatedPoint(
      position: position,
      localX: minX,
      localY: maxY,
      context: context,
      tolerance: tolerance,
    )) {
      return HandleType.bottomLeft;
    }

    return null;
  }

  HandleType? _resolveEdgeHandle({
    required DrawRect paddedBounds,
    required DrawPoint position,
    required double tolerance,
  }) {
    if (_testTopEdge(paddedBounds, position, tolerance)) {
      return HandleType.top;
    }
    if (_testRightEdge(paddedBounds, position, tolerance)) {
      return HandleType.right;
    }
    if (_testBottomEdge(paddedBounds, position, tolerance)) {
      return HandleType.bottom;
    }
    if (_testLeftEdge(paddedBounds, position, tolerance)) {
      return HandleType.left;
    }
    return null;
  }

  _SelectionHitContext? _buildSelectionContext({
    required EffectiveSelection selection,
    required DrawPoint position,
    required SelectionConfig config,
    required double cornerHandleOffset,
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
    final paddedBounds = DrawRect(
      minX: bounds.minX - padding,
      minY: bounds.minY - padding,
      maxX: bounds.maxX + padding,
      maxY: bounds.maxY + padding,
    );
    final handleBounds = DrawRect(
      minX: paddedBounds.minX - cornerHandleOffset,
      minY: paddedBounds.minY - cornerHandleOffset,
      maxX: paddedBounds.maxX + cornerHandleOffset,
      maxY: paddedBounds.maxY + cornerHandleOffset,
    );
    final testPosition = rotation == 0.0
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
    required ElementRegistry registry,
    required int positionX,
    required int positionY,
  }) {
    _hitTestCache.store(
      _HitTestCacheEntry(
        state: state,
        config: config,
        tolerance: tolerance,
        filterTypeId: filterTypeId,
        registry: registry,
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
    if (!_isNear(position.y, bounds.minY, tolerance)) {
      return false;
    }
    return position.x > bounds.minX + tolerance &&
        position.x < bounds.maxX - tolerance;
  }

  /// Tests whether the pointer hits the right edge (excluding corner regions).
  bool _testRightEdge(DrawRect bounds, DrawPoint position, double tolerance) {
    if (!_isNear(position.x, bounds.maxX, tolerance)) {
      return false;
    }
    return position.y > bounds.minY + tolerance &&
        position.y < bounds.maxY - tolerance;
  }

  /// Tests whether the pointer hits the bottom edge (excluding corner regions).
  bool _testBottomEdge(DrawRect bounds, DrawPoint position, double tolerance) {
    if (!_isNear(position.y, bounds.maxY, tolerance)) {
      return false;
    }
    return position.x > bounds.minX + tolerance &&
        position.x < bounds.maxX - tolerance;
  }

  /// Tests whether the pointer hits the left edge (excluding corner regions).
  bool _testLeftEdge(DrawRect bounds, DrawPoint position, double tolerance) {
    if (!_isNear(position.x, bounds.minX, tolerance)) {
      return false;
    }
    return position.y > bounds.minY + tolerance &&
        position.y < bounds.maxY - tolerance;
  }

  bool _isNear(double value, double target, double tolerance) =>
      (value - target).abs() <= tolerance;

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
    required this.registry,
    required this.positionX,
    required this.positionY,
    required this.result,
  });

  final DrawState state;
  final SelectionConfig config;
  final double tolerance;
  final ElementTypeId<ElementData>? filterTypeId;
  final ElementRegistry registry;
  final int positionX;
  final int positionY;
  final HitTestResult result;

  bool matches({
    required DrawState state,
    required SelectionConfig config,
    required double tolerance,
    required ElementTypeId<ElementData>? filterTypeId,
    required ElementRegistry registry,
    required int positionX,
    required int positionY,
  }) =>
      identical(this.state, state) &&
      this.positionX == positionX &&
      this.positionY == positionY &&
      this.tolerance == tolerance &&
      this.filterTypeId == filterTypeId &&
      identical(this.registry, registry) &&
      this.config == config;
}

class _HitTestCache {
  final _entries = <_HitTestCacheEntry>[];

  HitTestResult? lookup({
    required DrawState state,
    required SelectionConfig config,
    required double tolerance,
    required ElementTypeId<ElementData>? filterTypeId,
    required ElementRegistry registry,
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
        registry: registry,
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
