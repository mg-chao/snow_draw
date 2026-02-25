import '../../types/draw_rect.dart';
import '../../types/edit_context.dart';
import '../../types/edit_transform.dart';

/// Shared validation rules for edit operations.
///
/// Keeping this logic centralized reduces duplication and avoids subtle
/// inconsistencies across operations.
class EditValidation {
  const EditValidation._();

  static bool isValidContext(EditContext context) =>
      context.selectedIdsAtStart.isNotEmpty && context.hasSnapshots;

  static bool isValidBounds(DrawRect bounds) =>
      bounds.width > 0 && bounds.height > 0;

  /// Whether the compute pipeline should short-circuit and return null.
  ///
  /// Combines the context/bounds validation with the identity-transform
  /// check that every standard operation repeats in `computeResult`.
  static bool shouldSkipCompute({
    required EditContext context,
    required EditTransform transform,
    bool requireValidBounds = true,
  }) =>
      !isValidContext(context) ||
      (requireValidBounds && !isValidBounds(context.startBounds)) ||
      transform.isIdentity;
}
