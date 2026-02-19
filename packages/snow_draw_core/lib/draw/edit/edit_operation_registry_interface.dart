import '../types/edit_operation_id.dart';
import 'core/edit_operation_base.dart';

abstract interface class EditOperationRegistry {
  EditOperationBase? getOperation(EditOperationId id);
  Iterable<EditOperationBase> get allOperations;
  Iterable<EditOperationId> get allOperationIds;
}
