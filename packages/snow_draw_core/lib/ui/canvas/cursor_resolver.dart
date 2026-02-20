import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../draw/edit/arrow/arrow_point_operation.dart';
import '../../draw/edit/free_transform/free_transform_context.dart';
import '../../draw/models/interaction_state.dart';
import '../../draw/types/edit_context.dart';
import '../../draw/types/resize_mode.dart';
import '../../draw/utils/hit_test.dart';

const _rotatedHandleHints = <CursorHint>[
  CursorHint.resizeRight,
  CursorHint.resizeUpRightDownLeft,
  CursorHint.resizeUp,
  CursorHint.resizeUpLeftDownRight,
  CursorHint.resizeLeft,
  CursorHint.resizeUpRightDownLeft,
  CursorHint.resizeDown,
  CursorHint.resizeUpLeftDownRight,
];

class CursorResolver {
  const CursorResolver();

  MouseCursor resolveForHitTest(HitTestResult result) =>
      _cursorFromHint(_hintForHitTest(result));

  MouseCursor? resolveLockedCursor(InteractionState interaction) {
    if (interaction case EditingState(:final context)) {
      return switch (context) {
        ResizeEditContext(:final resizeMode, :final rotation) =>
          _cursorForResizeMode(resizeMode, rotation),
        RotateEditContext() || ArrowPointEditContext() => grabbingCursor(),
        MoveEditContext() => SystemMouseCursors.move,
        FreeTransformEditContext() => _cursorForFreeTransform(context),
        _ => SystemMouseCursors.move,
      };
    }
    return null;
  }

  CursorHint _hintForHitTest(HitTestResult result) {
    final handleType = result.handleType;
    if (handleType == null) {
      return result.cursorHint ??
          (result.elementId == null ? CursorHint.basic : CursorHint.move);
    }
    if (handleType == HandleType.rotate) {
      return result.cursorHint ?? CursorHint.rotate;
    }
    return _hintForRotatedHandle(handleType, result.selectionRotation ?? 0.0);
  }

  MouseCursor _cursorForFreeTransform(FreeTransformEditContext context) =>
      switch (context.currentMode) {
        FreeTransformMode.move => SystemMouseCursors.move,
        FreeTransformMode.rotate => grabbingCursor(),
        FreeTransformMode.resize => SystemMouseCursors.resizeUpLeftDownRight,
      };

  MouseCursor _cursorForResizeMode(ResizeMode mode, double rotation) {
    final handleType = switch (mode) {
      ResizeMode.topLeft => HandleType.topLeft,
      ResizeMode.topRight => HandleType.topRight,
      ResizeMode.bottomRight => HandleType.bottomRight,
      ResizeMode.bottomLeft => HandleType.bottomLeft,
      ResizeMode.top => HandleType.top,
      ResizeMode.bottom => HandleType.bottom,
      ResizeMode.left => HandleType.left,
      ResizeMode.right => HandleType.right,
    };
    return _cursorFromHint(_hintForRotatedHandle(handleType, rotation));
  }

  CursorHint _hintForRotatedHandle(HandleType handle, double rotation) {
    final baseAngle = _baseAngleForHandle(handle);
    final visualAngle = _normalizeAngle(baseAngle - rotation);
    return _hintForAngle(visualAngle);
  }

  double _baseAngleForHandle(HandleType handle) => switch (handle) {
    HandleType.right => 0,
    HandleType.topRight => math.pi / 4,
    HandleType.top => math.pi / 2,
    HandleType.topLeft => 3 * math.pi / 4,
    HandleType.left => math.pi,
    HandleType.bottomLeft => 5 * math.pi / 4,
    HandleType.bottom => 3 * math.pi / 2,
    HandleType.bottomRight => 7 * math.pi / 4,
    HandleType.rotate => throw ArgumentError.value(
      handle,
      'handle',
      'Rotate handle does not have a resize angle.',
    ),
  };

  double _normalizeAngle(double angle) {
    const twoPi = 2 * math.pi;
    final normalized = angle % twoPi;
    return normalized < 0 ? normalized + twoPi : normalized;
  }

  CursorHint _hintForAngle(double angle) {
    const step = math.pi / 8; // 22.5 degrees in radians.
    final sector =
        ((angle + step) / (math.pi / 4)).floor() % _rotatedHandleHints.length;
    return _rotatedHandleHints[sector];
  }

  MouseCursor _cursorFromHint(CursorHint hint) => switch (hint) {
    CursorHint.basic => SystemMouseCursors.basic,
    CursorHint.move => SystemMouseCursors.move,
    CursorHint.resizeUpLeftDownRight =>
      SystemMouseCursors.resizeUpLeftDownRight,
    CursorHint.resizeUpRightDownLeft =>
      SystemMouseCursors.resizeUpRightDownLeft,
    CursorHint.resizeUp => SystemMouseCursors.resizeUp,
    CursorHint.resizeDown => SystemMouseCursors.resizeDown,
    CursorHint.resizeLeft => SystemMouseCursors.resizeLeft,
    CursorHint.resizeRight => SystemMouseCursors.resizeRight,
    CursorHint.rotate => grabCursor(),
  };

  MouseCursor grabCursor() => _dragCursor(SystemMouseCursors.grab);

  MouseCursor grabbingCursor() => _dragCursor(SystemMouseCursors.grabbing);

  MouseCursor _dragCursor(MouseCursor cursor) {
    if (!kIsWeb && defaultTargetPlatform == TargetPlatform.windows) {
      return SystemMouseCursors.click;
    }
    return cursor;
  }
}
