import '../types/edit_operation_id.dart';
import 'core/edit_operation_base.dart';

/// EditOperationRegistry abstraction for testability.
abstract interface class EditOperationRegistry {
  EditOperationBase? getOperation(EditOperationId operationId);
  Iterable<EditOperationBase> get allOperations;
  Iterable<EditOperationId> get allOperationIds;
}
