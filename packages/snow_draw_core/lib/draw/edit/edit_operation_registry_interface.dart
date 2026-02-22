import '../types/edit_operation_id.dart';
import 'core/edit_operation.dart';

abstract interface class EditOperationRegistry {
  EditOperation? getOperation(EditOperationId id);
  Iterable<EditOperation> get allOperations;
  Iterable<EditOperationId> get allOperationIds;
}
