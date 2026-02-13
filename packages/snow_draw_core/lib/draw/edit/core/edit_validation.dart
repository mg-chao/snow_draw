import '../../types/draw_rect.dart';
import '../../types/edit_context.dart';
import 'edit_errors.dart';

/// Shared validation rules for edit operations.
///
/// Keeping this logic centralized reduces duplication and avoids subtle
/// inconsistencies across operations.
class EditValidation {
  const EditValidation._();

  /// Validates critical [EditContext] invariants and throws on failure.
  ///
  /// Prefer this over `assert` so release builds behave the same as debug
  /// builds.
  static void requireValidContext(
    EditContext context, {
    required String operationName,
  }) {
    if (context.selectedIdsAtStart.isEmpty) {
      throw EditMissingDataError(
        dataName: 'selectedIdsAtStart',
        operationName: operationName,
      );
    }
    if (!context.hasSnapshots) {
      throw EditMissingDataError(
        dataName: 'elementSnapshots',
        operationName: operationName,
      );
    }
  }

  static void requireValidBounds(
    DrawRect bounds, {
    required String operationName,
  }) {
    if (bounds.width <= 0 || bounds.height <= 0) {
      throw EditMissingDataError(
        dataName:
            'valid bounds (width=${bounds.width}, height=${bounds.height})',
        operationName: operationName,
      );
    }
  }

  static bool isValidContext(EditContext context) =>
      context.selectedIdsAtStart.isNotEmpty && context.hasSnapshots;

  static bool isValidBounds(DrawRect bounds) =>
      bounds.width > 0 && bounds.height > 0;

  static bool isValidForEdit(EditContext context) =>
      isValidContext(context) && isValidBounds(context.startBounds);
}
