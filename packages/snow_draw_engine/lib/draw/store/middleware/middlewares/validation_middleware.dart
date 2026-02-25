import 'package:meta/meta.dart';

import '../../../actions/draw_actions.dart';
import '../../../events/error_events.dart';
import '../middleware_base.dart';
import '../middleware_context.dart';

@immutable
class ValidationResult {
  const ValidationResult.valid() : this._(isValid: true);

  const ValidationResult.invalid(String message)
    : this._(isValid: false, message: message);

  const ValidationResult._({required this.isValid, this.message});

  final bool isValid;
  final String? message;
}

class ValidationMiddleware extends MiddlewareBase {
  const ValidationMiddleware();

  @override
  String get name => 'Validation';

  @override
  int get priority => 1000; // High priority - validate first

  @override
  Future<DispatchContext> invoke(
    DispatchContext context,
    NextFunction next,
  ) async {
    final result = _validateAction(context);
    if (result.isValid) {
      return next(context);
    }

    final message = result.message!;
    context.drawContext.log.store.warning('Validation blocked action', {
      'action': context.action.runtimeType.toString(),
      'reason': message,
      'traceId': context.traceId,
    });
    context.drawContext.eventBus?.emitLazy(
      () => ValidationFailedEvent(
        action: context.action.runtimeType.toString(),
        reason: message,
        details: {'traceId': context.traceId},
      ),
    );
    return context.withStop(message);
  }

  ValidationResult _validateAction(DispatchContext context) {
    final action = context.action;
    return switch (action) {
      final CreateElement create => _validateCreateElement(create, context),
      final DeleteElements delete => _validateElementIds(
        delete.elementIds,
        'DeleteElements',
      ),
      final DuplicateElements duplicate => _validateElementIds(
        duplicate.elementIds,
        'DuplicateElements',
      ),
      final ChangeElementZIndex zIndex => _validateElementId(
        zIndex.elementId,
        'ChangeElementZIndex',
      ),
      final ChangeElementsZIndex zIndexBatch => _validateElementIds(
        zIndexBatch.elementIds,
        'ChangeElementsZIndex',
      ),
      final UpdateElementsStyle updateStyle => _validateUpdateElementsStyle(
        updateStyle,
      ),
      final UpdateGlobalElements updateGlobal => _validateUpdateGlobalElements(
        updateGlobal,
      ),
      final CreateSerialNumberTextElements createSerial => _validateElementIds(
        createSerial.elementIds,
        'CreateSerialNumberTextElements',
      ),
      final SelectElement select => _validateElementId(
        select.elementId,
        'SelectElement',
      ),
      final ZoomCamera zoom => _validateZoomCamera(zoom),
      Undo _ => _validateUndo(context),
      Redo _ => _validateRedo(context),
      _ => const ValidationResult.valid(),
    };
  }

  ValidationResult _validateCreateElement(
    CreateElement action,
    DispatchContext context,
  ) {
    if (!context.drawContext.elementRegistry.supports(action.typeId)) {
      return ValidationResult.invalid(
        'Unknown element type "${action.typeId.value}"',
      );
    }
    final initialData = action.initialData;
    if (initialData != null && initialData.typeId != action.typeId) {
      return const ValidationResult.invalid(
        'CreateElement initialData type does not match typeId',
      );
    }
    return const ValidationResult.valid();
  }

  ValidationResult _validateUpdateElementsStyle(UpdateElementsStyle action) {
    if (action.elementIds.isEmpty) {
      return const ValidationResult.invalid(
        'UpdateElementsStyle requires elementIds',
      );
    }
    if (!action.hasUpdates) {
      return const ValidationResult.invalid(
        'UpdateElementsStyle has no fields to update',
      );
    }
    return const ValidationResult.valid();
  }

  ValidationResult _validateUpdateGlobalElements(UpdateGlobalElements action) {
    if (!action.hasUpdates) {
      return const ValidationResult.invalid(
        'UpdateGlobalElements has no fields to update',
      );
    }
    return const ValidationResult.valid();
  }

  ValidationResult _validateZoomCamera(ZoomCamera action) {
    if (action.scale.isNaN || action.scale.isInfinite) {
      return const ValidationResult.invalid('ZoomCamera scale is invalid');
    }
    if (action.scale <= 0) {
      return const ValidationResult.invalid('ZoomCamera scale must be > 0');
    }
    return const ValidationResult.valid();
  }

  ValidationResult _validateUndo(DispatchContext context) {
    if (!context.historyManager.canUndo) {
      return const ValidationResult.invalid('Cannot undo: history is empty');
    }
    return const ValidationResult.valid();
  }

  ValidationResult _validateRedo(DispatchContext context) {
    if (!context.historyManager.canRedo) {
      return const ValidationResult.invalid('Cannot redo: no future history');
    }
    return const ValidationResult.valid();
  }

  ValidationResult _validateElementIds(List<String> elementIds, String action) {
    if (elementIds.isEmpty) {
      return ValidationResult.invalid('$action requires elementIds');
    }
    return const ValidationResult.valid();
  }

  ValidationResult _validateElementId(String elementId, String action) {
    if (elementId.trim().isEmpty) {
      return ValidationResult.invalid('$action needs elementId');
    }
    return const ValidationResult.valid();
  }
}
