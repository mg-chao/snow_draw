import 'package:meta/meta.dart';

import '../../../actions/draw_actions.dart';
import '../../../events/error_events.dart';
import '../middleware_base.dart';
import '../middleware_context.dart';

typedef ActionValidator =
    ValidationResult Function(DrawAction action, DispatchContext context);

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
  ValidationMiddleware({Map<Type, ActionValidator>? validators})
    : _validators = validators ?? _defaultValidators;

  static const Map<Type, ActionValidator> _defaultValidators = {
    CreateElement: _validateCreateElement,
    DeleteElements: _validateDeleteElements,
    DuplicateElements: _validateDuplicateElements,
    ChangeElementZIndex: _validateChangeElementZIndex,
    ChangeElementsZIndex: _validateChangeElementsZIndex,
    UpdateElementsStyle: _validateUpdateElementsStyle,
    UpdateGlobalElements: _validateUpdateGlobalElements,
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
    if (validator == null) {
      return next(context);
    }

    final result = validator(context.action, context);
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
    return context.withStop(message).withMetadata('validationError', message);
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
  DispatchContext _,
) =>
    _requireElementIds((action as DeleteElements).elementIds, 'DeleteElements');

ValidationResult _validateDuplicateElements(
  DrawAction action,
  DispatchContext _,
) => _requireElementIds(
  (action as DuplicateElements).elementIds,
  'DuplicateElements',
);

ValidationResult _validateChangeElementZIndex(
  DrawAction action,
  DispatchContext _,
) => _requireElementId(
  (action as ChangeElementZIndex).elementId,
  'ChangeElementZIndex',
);

ValidationResult _validateChangeElementsZIndex(
  DrawAction action,
  DispatchContext _,
) => _requireElementIds(
  (action as ChangeElementsZIndex).elementIds,
  'ChangeElementsZIndex',
);

ValidationResult _validateUpdateElementsStyle(
  DrawAction action,
  DispatchContext _,
) {
  final update = action as UpdateElementsStyle;
  if (update.elementIds.isEmpty) {
    return const ValidationResult.invalid(
      'UpdateElementsStyle requires elementIds',
    );
  }
  if (!_hasStyleUpdates(update)) {
    return const ValidationResult.invalid(
      'UpdateElementsStyle has no fields to update',
    );
  }
  return const ValidationResult.valid();
}

ValidationResult _validateUpdateGlobalElements(
  DrawAction action,
  DispatchContext _,
) {
  final update = action as UpdateGlobalElements;
  if (!update.hasUpdates) {
    return const ValidationResult.invalid(
      'UpdateGlobalElements has no fields to update',
    );
  }
  return const ValidationResult.valid();
}

ValidationResult _validateCreateSerialNumberTextElements(
  DrawAction action,
  DispatchContext _,
) => _requireElementIds(
  (action as CreateSerialNumberTextElements).elementIds,
  'CreateSerialNumberTextElements',
);

ValidationResult _validateSelectElement(DrawAction action, DispatchContext _) =>
    _requireElementId((action as SelectElement).elementId, 'SelectElement');

ValidationResult _validateZoomCamera(DrawAction action, DispatchContext _) {
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

ValidationResult _requireElementIds(
  List<String> elementIds,
  String actionName,
) {
  if (elementIds.isEmpty) {
    return ValidationResult.invalid('$actionName requires elementIds');
  }
  return const ValidationResult.valid();
}

ValidationResult _requireElementId(String elementId, String actionName) {
  if (elementId.trim().isEmpty) {
    return ValidationResult.invalid('$actionName needs elementId');
  }
  return const ValidationResult.valid();
}

bool _hasStyleUpdates(UpdateElementsStyle update) =>
    update.color != null ||
    update.fillColor != null ||
    update.strokeWidth != null ||
    update.strokeStyle != null ||
    update.fillStyle != null ||
    update.filterType != null ||
    update.filterStrength != null ||
    update.cornerRadius != null ||
    update.arrowType != null ||
    update.startArrowhead != null ||
    update.endArrowhead != null ||
    update.fontSize != null ||
    update.fontFamily != null ||
    update.textAlign != null ||
    update.verticalAlign != null ||
    update.opacity != null ||
    update.textStrokeColor != null ||
    update.textStrokeWidth != null ||
    update.highlightShape != null ||
    update.serialNumber != null;
