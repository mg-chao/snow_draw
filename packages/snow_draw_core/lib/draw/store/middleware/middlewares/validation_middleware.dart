import 'package:meta/meta.dart';

import '../../../actions/draw_actions.dart';
import '../../../events/error_events.dart';
import '../middleware_base.dart';
import '../middleware_context.dart';

/// Validation middleware that checks action preconditions.
///
/// Currently a no-op, but can be extended to validate:
/// - Action parameters
/// - State consistency
/// - Permission checks
///
/// Example:
/// ```dart
/// class CustomValidationMiddleware extends ValidationMiddleware {
///   @override
///   Future<DispatchContext> invoke(
///     DispatchContext context,
///     NextFunction next,
///   ) async {
///     // Custom validation logic
///     if (!isValid(context.action)) {
///       return context.withStop('Invalid action');
///     }
///     return super.invoke(context, next);
///   }
/// }
/// ```
typedef ActionValidator =
    ValidationResult Function(DrawAction action, DispatchContext context);

@immutable
class ValidationResult {
  const ValidationResult._(this.isValid, this.message);

  const ValidationResult.valid() : this._(true, null);

  const ValidationResult.invalid(String message) : this._(false, message);
  final bool isValid;
  final String? message;
}

class ValidationMiddleware extends MiddlewareBase {
  ValidationMiddleware({Map<Type, ActionValidator>? validators})
    : _validators = validators ?? _defaultValidators;
  static final Map<Type, ActionValidator> _defaultValidators = {
    CreateElement: _validateCreateElement,
    DeleteElements: _validateDeleteElements,
    DuplicateElements: _validateDuplicateElements,
    ChangeElementZIndex: _validateChangeElementZIndex,
    ChangeElementsZIndex: _validateChangeElementsZIndex,
    UpdateElementsStyle: _validateUpdateElementsStyle,
    CreateSerialNumberTextElements: _validateCreateSerialNumberTextElements,
    SelectElement: _validateSelectElement,
    ZoomCamera: _validateZoomCamera,
    Undo: _validateUndo,
    Redo: _validateRedo,
  };

  final Map<Type, ActionValidator> _validators;

  @override
  String get name => 'Validation';

  @override
  int get priority => 1000; // High priority - validate first

  @override
  Future<DispatchContext> invoke(
    DispatchContext context,
    NextFunction next,
  ) async {
    final validator = _validators[context.action.runtimeType];
    if (validator != null) {
      final result = validator(context.action, context);
      if (!result.isValid) {
        final message = result.message ?? 'Validation failed';
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
        final stoppedContext = context
            .withStop(message)
            .withMetadata('validationError', message);
        return stoppedContext;
      }
    }
    return next(context);
  }
}

ValidationResult _validateCreateElement(
  DrawAction action,
  DispatchContext context,
) {
  final create = action as CreateElement;
  if (!context.drawContext.elementRegistry.supports(create.typeId)) {
    return ValidationResult.invalid(
      'Unknown element type "${create.typeId.value}"',
    );
  }
  final initialData = create.initialData;
  if (initialData != null && initialData.typeId != create.typeId) {
    return const ValidationResult.invalid(
      'CreateElement initialData type does not match typeId',
    );
  }
  return const ValidationResult.valid();
}

ValidationResult _validateDeleteElements(
  DrawAction action,
  DispatchContext context,
) {
  final delete = action as DeleteElements;
  if (delete.elementIds.isEmpty) {
    return const ValidationResult.invalid('DeleteElements requires elementIds');
  }
  return const ValidationResult.valid();
}

ValidationResult _validateDuplicateElements(
  DrawAction action,
  DispatchContext context,
) {
  final duplicate = action as DuplicateElements;
  if (duplicate.elementIds.isEmpty) {
    return const ValidationResult.invalid(
      'DuplicateElements requires elementIds',
    );
  }
  return const ValidationResult.valid();
}

ValidationResult _validateChangeElementZIndex(
  DrawAction action,
  DispatchContext context,
) {
  final change = action as ChangeElementZIndex;
  if (change.elementId.trim().isEmpty) {
    return const ValidationResult.invalid(
      'ChangeElementZIndex needs elementId',
    );
  }
  return const ValidationResult.valid();
}

ValidationResult _validateChangeElementsZIndex(
  DrawAction action,
  DispatchContext context,
) {
  final change = action as ChangeElementsZIndex;
  if (change.elementIds.isEmpty) {
    return const ValidationResult.invalid(
      'ChangeElementsZIndex requires elementIds',
    );
  }
  return const ValidationResult.valid();
}

ValidationResult _validateUpdateElementsStyle(
  DrawAction action,
  DispatchContext context,
) {
  final update = action as UpdateElementsStyle;
  if (update.elementIds.isEmpty) {
    return const ValidationResult.invalid(
      'UpdateElementsStyle requires elementIds',
    );
  }
  if (update.color == null &&
      update.fillColor == null &&
      update.strokeWidth == null &&
      update.strokeStyle == null &&
      update.fillStyle == null &&
      update.filterType == null &&
      update.filterStrength == null &&
      update.cornerRadius == null &&
      update.arrowType == null &&
      update.startArrowhead == null &&
      update.endArrowhead == null &&
      update.fontSize == null &&
      update.fontFamily == null &&
      update.textAlign == null &&
      update.verticalAlign == null &&
      update.opacity == null &&
      update.textStrokeColor == null &&
      update.textStrokeWidth == null &&
      update.highlightShape == null &&
      update.serialNumber == null) {
    return const ValidationResult.invalid(
      'UpdateElementsStyle has no fields to update',
    );
  }
  return const ValidationResult.valid();
}

ValidationResult _validateCreateSerialNumberTextElements(
  DrawAction action,
  DispatchContext context,
) {
  final create = action as CreateSerialNumberTextElements;
  if (create.elementIds.isEmpty) {
    return const ValidationResult.invalid(
      'CreateSerialNumberTextElements requires elementIds',
    );
  }
  return const ValidationResult.valid();
}

ValidationResult _validateSelectElement(
  DrawAction action,
  DispatchContext context,
) {
  final select = action as SelectElement;
  if (select.elementId.trim().isEmpty) {
    return const ValidationResult.invalid('SelectElement needs elementId');
  }
  return const ValidationResult.valid();
}

ValidationResult _validateZoomCamera(
  DrawAction action,
  DispatchContext context,
) {
  final zoom = action as ZoomCamera;
  if (zoom.scale.isNaN || zoom.scale.isInfinite) {
    return const ValidationResult.invalid('ZoomCamera scale is invalid');
  }
  if (zoom.scale <= 0) {
    return const ValidationResult.invalid('ZoomCamera scale must be > 0');
  }
  return const ValidationResult.valid();
}

ValidationResult _validateUndo(DrawAction action, DispatchContext context) {
  if (!context.historyAvailability.canUndo) {
    return const ValidationResult.invalid('Cannot undo: history is empty');
  }
  return const ValidationResult.valid();
}

ValidationResult _validateRedo(DrawAction action, DispatchContext context) {
  if (!context.historyAvailability.canRedo) {
    return const ValidationResult.invalid('Cannot redo: no future history');
  }
  return const ValidationResult.valid();
}
