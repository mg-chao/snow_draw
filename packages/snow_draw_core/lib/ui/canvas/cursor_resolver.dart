import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../draw/edit/free_transform/free_transform_context.dart';
import '../../draw/models/interaction_state.dart';
import '../../draw/types/edit_context.dart';
import '../../draw/types/resize_mode.dart';
import '../../draw/utils/hit_test.dart';

class CursorResolver {
  const CursorResolver();

  MouseCursor resolveForHitTest(HitTestResult result) {
    final handleType = result.handleType;
    if (handleType != null && handleType != HandleType.rotate) {
      final rotation = result.selectionRotation ?? 0.0;
      return _cursorFromHint(_hintForRotatedHandle(handleType, rotation));
    }

    return _cursorFromHint(result.cursorHint ?? _hintFromResult(result));
  }

  MouseCursor? resolveLockedCursor(InteractionState interaction) {
    if (interaction is! EditingState) {
      return null;
    }

    final context = interaction.context;
    if (context is ResizeEditContext) {
      return _cursorForResizeMode(context.resizeMode, context.rotation);
    }
    if (context is RotateEditContext) {
      return _grabCursor();
    }
    if (context is MoveEditContext) {
      return SystemMouseCursors.move;
    }
    if (context is FreeTransformEditContext) {
      return _cursorForFreeTransform(context);
    }

    return SystemMouseCursors.move;
  }

  MouseCursor _cursorForFreeTransform(FreeTransformEditContext context) =>
      switch (context.currentMode) {
        FreeTransformMode.move => SystemMouseCursors.move,
        FreeTransformMode.rotate => _grabCursor(),
        FreeTransformMode.resize => _cursorFromHint(
          CursorHint.resizeUpLeftDownRight,
        ),
      };

  CursorHint _hintFromResult(HitTestResult result) {
    final handleType = result.handleType;
    if (handleType != null) {
      return _hintForHandle(handleType);
    }
    if (result.elementId != null) {
      return CursorHint.move;
    }
    return CursorHint.basic;
  }

  CursorHint _hintForHandle(HandleType handle) {
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

  MouseCursor _cursorForResizeMode(ResizeMode mode, double rotation) =>
      _cursorFromHint(
        _hintForRotatedHandle(_handleTypeForResizeMode(mode), rotation),
      );

  HandleType _handleTypeForResizeMode(ResizeMode mode) {
    switch (mode) {
      case ResizeMode.topLeft:
        return HandleType.topLeft;
      case ResizeMode.topRight:
        return HandleType.topRight;
      case ResizeMode.bottomRight:
        return HandleType.bottomRight;
      case ResizeMode.bottomLeft:
        return HandleType.bottomLeft;
      case ResizeMode.top:
        return HandleType.top;
      case ResizeMode.bottom:
        return HandleType.bottom;
      case ResizeMode.left:
        return HandleType.left;
      case ResizeMode.right:
        return HandleType.right;
    }
  }

  CursorHint _hintForRotatedHandle(HandleType handle, double rotation) {
    final baseAngle = _baseAngleForHandle(handle);
    final visualAngle = _normalizeAngle(baseAngle - rotation);
    return _hintForAngle(visualAngle);
  }

  double _baseAngleForHandle(HandleType handle) {
    switch (handle) {
      case HandleType.right:
        return 0;
      case HandleType.topRight:
        return math.pi / 4;
      case HandleType.top:
        return math.pi / 2;
      case HandleType.topLeft:
        return 3 * math.pi / 4;
      case HandleType.left:
        return math.pi;
      case HandleType.bottomLeft:
        return 5 * math.pi / 4;
      case HandleType.bottom:
        return 3 * math.pi / 2;
      case HandleType.bottomRight:
        return 7 * math.pi / 4;
      case HandleType.rotate:
        return 0;
    }
  }

  double _normalizeAngle(double angle) {
    const twoPi = 2 * math.pi;
    final normalized = angle % twoPi;
    return normalized < 0 ? normalized + twoPi : normalized;
  }

  CursorHint _hintForAngle(double angle) {
    const step = math.pi / 8; // 22.5 degrees in radians.
    final sector = ((angle + step) / (math.pi / 4)).floor() % 8;
    switch (sector) {
      case 0:
        return CursorHint.resizeRight;
      case 1:
        return CursorHint.resizeUpRightDownLeft;
      case 2:
        return CursorHint.resizeUp;
      case 3:
        return CursorHint.resizeUpLeftDownRight;
      case 4:
        return CursorHint.resizeLeft;
      case 5:
        return CursorHint.resizeUpRightDownLeft;
      case 6:
        return CursorHint.resizeDown;
      case 7:
        return CursorHint.resizeUpLeftDownRight;
    }
    return CursorHint.resizeRight;
  }

  MouseCursor _cursorFromHint(CursorHint hint) {
    switch (hint) {
      case CursorHint.basic:
        return SystemMouseCursors.basic;
      case CursorHint.move:
        return SystemMouseCursors.move;
      case CursorHint.resizeUpLeftDownRight:
        return SystemMouseCursors.resizeUpLeftDownRight;
      case CursorHint.resizeUpRightDownLeft:
        return SystemMouseCursors.resizeUpRightDownLeft;
      case CursorHint.resizeUp:
        return SystemMouseCursors.resizeUp;
      case CursorHint.resizeDown:
        return SystemMouseCursors.resizeDown;
      case CursorHint.resizeLeft:
        return SystemMouseCursors.resizeLeft;
      case CursorHint.resizeRight:
        return SystemMouseCursors.resizeRight;
      case CursorHint.rotate:
        return _grabCursor();
    }
  }

  MouseCursor _grabCursor() {
    if (!kIsWeb && defaultTargetPlatform == TargetPlatform.windows) {
      return SystemMouseCursors.click;
    }
    return SystemMouseCursors.grab;
  }
}
