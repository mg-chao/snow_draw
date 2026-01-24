import '../types/edit_operation_id.dart';
import 'core/edit_operation_base.dart';
import 'edit_operation_registry_interface.dart';
import 'free_transform/free_transform_operation.dart';
import 'move/move_operation.dart';
import 'resize/resize_operation.dart';
import 'rotate/rotate_operation.dart';

/// Registry of configured edit operations.
class DefaultEditOperationRegistry implements EditOperationRegistry {
  DefaultEditOperationRegistry._(this._operations) {
    assert(_validateOperations(), 'Invalid operation registration');
  }

  factory DefaultEditOperationRegistry.withDefaults() =>
      DefaultEditOperationRegistry._({
        for (final op in defaultOperations) op.id: op,
      });

  factory DefaultEditOperationRegistry.custom(
    List<EditOperationBase> operations,
  ) => DefaultEditOperationRegistry._({for (final op in operations) op.id: op});

  factory DefaultEditOperationRegistry.empty() =>
      DefaultEditOperationRegistry._({});
  final Map<EditOperationId, EditOperationBase> _operations;

  /// Default operation set (reused by tests and extension points).
  static const List<EditOperationBase> defaultOperations = [
    MoveOperation(),
    ResizeOperation(),
    RotateOperation(),
    FreeTransformOperation(),
  ];

  @override
  EditOperationBase? getOperation(EditOperationId operationId) =>
      _operations[operationId];

  @override
  Iterable<EditOperationBase> get allOperations => _operations.values;

  @override
  Iterable<EditOperationId> get allOperationIds => _operations.keys;

  bool hasOperation(EditOperationId operationId) =>
      _operations.containsKey(operationId);

  int get operationCount => _operations.length;

  bool _validateOperations() {
    for (final entry in _operations.entries) {
      final id = entry.key;
      final operation = entry.value;
      if (operation.id != id) {
        throw StateError(
          'Operation ID mismatch: registered as $id but operation.id is '
          '${operation.id}',
        );
      }
    }
    return true;
  }
}
