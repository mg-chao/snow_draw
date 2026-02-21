import '../types/edit_operation_id.dart';
import 'arrow/arrow_point_operation.dart';
import 'core/edit_operation_base.dart';
import 'edit_operation_registry_interface.dart';
import 'free_transform/free_transform_operation.dart';
import 'move/move_operation.dart';
import 'resize/resize_operation.dart';
import 'rotate/rotate_operation.dart';

/// Registry of configured edit operations.
class DefaultEditOperationRegistry implements EditOperationRegistry {
  DefaultEditOperationRegistry._(
    Map<EditOperationId, EditOperationBase> operations,
  ) : _operations = Map.unmodifiable(operations);

  factory DefaultEditOperationRegistry.withDefaults() =>
      DefaultEditOperationRegistry.custom(defaultOperations);

  factory DefaultEditOperationRegistry.custom(
    List<EditOperationBase> operations,
  ) => DefaultEditOperationRegistry._({
    for (final operation in operations) operation.id: operation,
  });

  factory DefaultEditOperationRegistry.empty() =>
      DefaultEditOperationRegistry._(
        const <EditOperationId, EditOperationBase>{},
      );
  final Map<EditOperationId, EditOperationBase> _operations;

  /// Default operation set (reused by tests and extension points).
  static const List<EditOperationBase> defaultOperations = [
    MoveOperation(),
    ArrowPointOperation(),
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
}
