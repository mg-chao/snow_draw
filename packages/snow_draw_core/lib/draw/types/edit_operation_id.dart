/// Stable identifier for an edit-domain operation (move/resize/rotate/...).
typedef EditOperationId = String;

/// Built-in edit operation ids used by the edit session and operation registry.
final class EditOperationIds {
  EditOperationIds._();

  static const move = 'move';
  static const resize = 'resize';
  static const rotate = 'rotate';
  static const freeTransform = 'free_transform';
  static const arrowPoint = 'arrow_point';
}
