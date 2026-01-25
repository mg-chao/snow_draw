/// Stable identifier for an edit-domain operation (move/resize/rotate/...).
typedef EditOperationId = String;

/// Built-in edit operation ids.
///
/// These ids are used by the edit session state machine and the operation
/// registry. New operations should add a new id and register an operation
/// implementation, without requiring controller/reducer switches.
abstract final class EditOperationIds {
  static const move = 'move';
  static const resize = 'resize';
  static const rotate = 'rotate';
  static const freeTransform = 'free_transform';
  static const arrowPoint = 'arrow_point';
}
