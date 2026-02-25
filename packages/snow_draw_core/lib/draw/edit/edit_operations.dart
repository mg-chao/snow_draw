import '../types/edit_operation_id.dart';
import 'arrow/arrow_point_operation.dart';
import 'core/edit_operation.dart';
import 'move/move_operation.dart';
import 'resize/resize_operation.dart';
import 'rotate/rotate_operation.dart';

/// Registry of configured edit operations.
class DefaultEditOperationRegistry {
  DefaultEditOperationRegistry._(Map<EditOperationId, EditOperation> operations)
    : _operations = Map.unmodifiable(operations);

  factory DefaultEditOperationRegistry.withDefaults() =>
      DefaultEditOperationRegistry.custom(defaultOperations);

  factory DefaultEditOperationRegistry.custom(List<EditOperation> operations) =>
      DefaultEditOperationRegistry._({
        for (final operation in operations) operation.id: operation,
      });

  factory DefaultEditOperationRegistry.empty() =>
      DefaultEditOperationRegistry._(const <EditOperationId, EditOperation>{});
  final Map<EditOperationId, EditOperation> _operations;

  /// Default operation set (reused by tests and extension points).
  static const List<EditOperation> defaultOperations = [
    MoveOperation(),
    ArrowPointOperation(),
    ResizeOperation(),
    RotateOperation(),
  ];

  EditOperation? getOperation(EditOperationId operationId) =>
      _operations[operationId];

  Iterable<EditOperation> get allOperations => _operations.values;

  Iterable<EditOperationId> get allOperationIds => _operations.keys;

  bool hasOperation(EditOperationId operationId) =>
      _operations.containsKey(operationId);

  int get operationCount => _operations.length;
}
