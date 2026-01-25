import '../config/draw_config.dart';
import '../core/coordinates/overlay_space.dart';
import '../elements/core/element_data.dart';
import '../elements/core/element_registry_interface.dart';
import '../elements/core/element_type_id.dart';
import '../elements/types/arrow/arrow_data.dart';
import '../models/draw_state_view.dart';
import '../models/edit_enums.dart';
import '../models/element_state.dart';
import '../services/log/log_service.dart';
import '../types/draw_point.dart';
import '../types/draw_rect.dart';
import 'handle_calculator.dart';

final ModuleLogger _hitTestFallbackLog = LogService.fallback.element;

/// Hit test result.
class HitTestResult {
  const HitTestResult({
    this.elementId,
    this.handleType,
    this.cursorHint,
    this.selectionRotation,
  });

  /// Hit element id.
  final String? elementId;

  /// Hit handle type (when hitting selection handles).
  final HandleType? handleType;

  /// Suggested cursor type for the hit result.
  final CursorHint? cursorHint;

  /// Selection overlay rotation in radians (when hitting handles).
  final double? selectionRotation;

  /// True if either an element or a handle was hit.
  bool get isHit => elementId != null || handleType != null;

  /// True if a handle was hit.
  bool get isHandleHit => handleType != null;

  /// Represents "no hit".
  static const none = HitTestResult(cursorHint: CursorHint.basic);

  @override
  String toString() =>
      'HitTestResult(elementId: $elementId, handleType: $handleType, '
      'cursorHint: $cursorHint, selectionRotation: $selectionRotation)';
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
    if (!selection.hasSelection) {
      return false;
    }

    final bounds = selection.bounds;
    if (bounds == null) {
      return false;
    }

    final rotation = selection.rotation ?? 0.0;
    final center = selection.center ?? bounds.center;

    return _testPaddedSelectionArea(bounds, position, config, rotation, center);
  }

  /// Performs hit testing on the canvas.
  ///
  /// Returns information about the hit element or handle, if any.
  ///
  /// If [filterTypeId] is provided, only elements matching that type will be considered.
  HitTestResult test({
    required DrawStateView stateView,
    required DrawPoint position,
    required SelectionConfig config,
    required ElementRegistry registry,
    double? tolerance,
    ElementTypeId<ElementData>? filterTypeId,
  }) {
    final state = stateView.state;
    final selection = stateView.effectiveSelection;
    final selectionState = state.domain.selection;
    final selectedIds = selectionState.selectedIds;

    final actualTolerance = tolerance ?? config.interaction.handleTolerance;

    // Determine corner handle offset for single arrow selections.
    final cornerHandleOffset = selectedIds.length == 1 &&
            stateView.selectedElements.isNotEmpty &&
            stateView.selectedElements.first.data is ArrowData
        ? 8.0
        : 0.0;

    // Check if this is a single 2-point arrow selection.
    // For 2-point arrows, skip handle hit testing since all operations
    // can be performed through the point editor.
    final isSingleTwoPointArrow = selectedIds.length == 1 &&
        stateView.selectedElements.isNotEmpty &&
        stateView.selectedElements.first.data is ArrowData &&
        (stateView.selectedElements.first.data as ArrowData).points.length == 2;

    // 1. Check selection handles first (skip for 2-point arrows).
    if (selection.hasSelection && !isSingleTwoPointArrow) {
      final bounds = selection.bounds;
      if (bounds != null) {
        // Use the same rotation/center as rendering.
        final rotation = selection.rotation ?? 0.0;
        final center = selection.center ?? bounds.center;

        final handleResult = _testHandles(
          bounds: bounds,
          position: position,
          tolerance: actualTolerance,
          config: config,
          rotation: rotation,
          center: center,
          cornerHandleOffset: cornerHandleOffset,
        );
        if (handleResult != null) {
          return handleResult;
        }
      }
    }

    // 2. Check elements using spatial index (top-most first).
    final document = state.domain.document;
    final candidates = document.getElementsAtPoint(position, actualTolerance)
      ..sort((a, b) {
        final indexA = document.getOrderIndex(a.id) ?? -1;
        final indexB = document.getOrderIndex(b.id) ?? -1;
        return indexB.compareTo(indexA);
      });

    // Filter candidates by type if filterTypeId is provided
    final filteredCandidates = filterTypeId != null
        ? candidates.where((element) => element.typeId == filterTypeId).toList()
        : candidates;

    for (final candidate in filteredCandidates) {
      final element = stateView.effectiveElement(candidate);
      if (_testElement(element, position, registry, actualTolerance)) {
        return HitTestResult(
          elementId: element.id,
          cursorHint: CursorHint.move,
        );
      }
    }

    // 3. Check the padded selection area (allows dragging from padding).
    // (Used to support starting a move by dragging from the selection
    // padding area.) Skip for 2-point arrows.
    if (selection.hasSelection && !isSingleTwoPointArrow) {
      final bounds = selection.bounds;
      if (bounds != null) {
        final rotation = selection.rotation ?? 0.0;
        final center = selection.center ?? bounds.center;

        if (_testPaddedSelectionArea(
          bounds,
          position,
          config,
          rotation,
          center,
        )) {
          // Use the first selected element id (move operation).
          if (selectedIds.isNotEmpty) {
            final firstSelectedId = selectedIds.first;
            return HitTestResult(
              elementId: firstSelectedId,
              cursorHint: CursorHint.move,
            );
          }
        }
      }
    }

    return HitTestResult.none;
  }

  /// Tests whether [position] hits any selection handle.
  HitTestResult? _testHandles({
    required DrawRect bounds,
    required DrawPoint position,
    required double tolerance,
    required SelectionConfig config,
    required double rotation,
    required DrawPoint center,
    double cornerHandleOffset = 0.0,
  }) {
    final space = OverlaySpace(rotation: rotation, origin: center);

    // Apply the same padding as rendering.
    final padding = config.padding;
    final paddedBounds = DrawRect(
      minX: bounds.minX - padding,
      minY: bounds.minY - padding,
      maxX: bounds.maxX + padding,
      maxY: bounds.maxY + padding,
    );

    // Apply additional offset to corner handles (for arrow elements).
    final handleBounds = DrawRect(
      minX: paddedBounds.minX - cornerHandleOffset,
      minY: paddedBounds.minY - cornerHandleOffset,
      maxX: paddedBounds.maxX + cornerHandleOffset,
      maxY: paddedBounds.maxY + cornerHandleOffset,
    );

    // Transform the pointer position into the overlay's un-rotated local
    // space.
    final testPosition = space.fromWorld(position);

    // Check rotation handle first (same position math as rendering).
    final margin = config.rotateHandleOffset;
    final rotateHandlePosition = HandleCalculator.getRotateHandlePosition(
      bounds: bounds,
      padding: padding,
      margin: margin,
    );
    // The rotation handle is defined in local space and rendered in world
    // space.
    final rotatedRotateHandle = space.toWorld(rotateHandlePosition);
    if (_isNearPoint(position, rotatedRotateHandle, tolerance)) {
      return HitTestResult(
        handleType: HandleType.rotate,
        cursorHint: CursorHint.rotate,
        selectionRotation: rotation,
      );
    }

    // Check 4 corner handles first (higher priority for precise
    // resizing). Use handleBounds for corner positions.
    final cornerHandles = <DrawPoint, HandleType>{
      DrawPoint(x: handleBounds.minX, y: handleBounds.minY): HandleType.topLeft,
      DrawPoint(x: handleBounds.maxX, y: handleBounds.minY):
          HandleType.topRight,
      DrawPoint(x: handleBounds.maxX, y: handleBounds.maxY):
          HandleType.bottomRight,
      DrawPoint(x: handleBounds.minX, y: handleBounds.maxY):
          HandleType.bottomLeft,
    };

    for (final entry in cornerHandles.entries) {
      // Corner handle positions are defined in local space.
      final rotatedCorner = space.toWorld(entry.key);
      if (_isNearPoint(position, rotatedCorner, tolerance)) {
        return HitTestResult(
          handleType: entry.value,
          cursorHint: _cursorHintForHandle(entry.value),
          selectionRotation: rotation,
        );
      }
    }

    // Check 4 edges (excluding corner regions).
    // Perform edge checks in local space.
    if (_testTopEdge(paddedBounds, testPosition, tolerance)) {
      return HitTestResult(
        handleType: HandleType.top,
        cursorHint: CursorHint.resizeUp,
        selectionRotation: rotation,
      );
    }
    if (_testRightEdge(paddedBounds, testPosition, tolerance)) {
      return HitTestResult(
        handleType: HandleType.right,
        cursorHint: CursorHint.resizeRight,
        selectionRotation: rotation,
      );
    }
    if (_testBottomEdge(paddedBounds, testPosition, tolerance)) {
      return HitTestResult(
        handleType: HandleType.bottom,
        cursorHint: CursorHint.resizeDown,
        selectionRotation: rotation,
      );
    }
    if (_testLeftEdge(paddedBounds, testPosition, tolerance)) {
      return HitTestResult(
        handleType: HandleType.left,
        cursorHint: CursorHint.resizeLeft,
        selectionRotation: rotation,
      );
    }

    return null;
  }

  /// Tests whether [position] hits the selection's padded area.
  ///
  /// When an element is selected, the selection bounds are expanded by
  /// `padding`. Hitting this padding area is treated as a selection hit so the
  /// user can move it.
  bool _testPaddedSelectionArea(
    DrawRect bounds,
    DrawPoint position,
    SelectionConfig config,
    double rotation,
    DrawPoint center,
  ) {
    final space = OverlaySpace(rotation: rotation, origin: center);

    final padding = config.padding;
    final paddedBounds = DrawRect(
      minX: bounds.minX - padding,
      minY: bounds.minY - padding,
      maxX: bounds.maxX + padding,
      maxY: bounds.maxY + padding,
    );

    // Transform the pointer position into the overlay's un-rotated local
    // space.
    final testPosition = space.fromWorld(position);

    return testPosition.x >= paddedBounds.minX &&
        testPosition.x <= paddedBounds.maxX &&
        testPosition.y >= paddedBounds.minY &&
        testPosition.y <= paddedBounds.maxY;
  }

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

  /// Returns true if [a] is within [tolerance] of [b].
  bool _isNearPoint(DrawPoint a, DrawPoint b, double tolerance) =>
      HandleCalculator.isPointInHandle(
        testPoint: a,
        handleCenter: b,
        tolerance: tolerance,
      );

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

/// Shared hit-test helper instance.
const hitTest = HitTest();
