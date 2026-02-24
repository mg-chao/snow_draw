import 'package:meta/meta.dart';

import '../../core/app_error.dart';
import '../../core/error_context.dart';
import '../../types/edit_context.dart' show EditContext;
import '../../types/edit_transform.dart' show EditTransform;
import 'edit_operation_params.dart' show EditOperationParams;

String _buildTypeMismatchMessage({
  required String errorName,
  required String operationName,
  required String valueName,
  required Type expected,
  required Type actual,
  String? additionalInfo,
  Iterable<String> hints = const <String>[],
}) {
  final lines = <String>[
    '$errorName:',
    '  Operation: $operationName',
    '  Expected $valueName type: $expected',
    '  Actual $valueName type: $actual',
    if (additionalInfo != null) '  Additional info: $additionalInfo',
    for (final hint in hints) '  $hint',
  ];
  return lines.join('\n');
}

const _contextRegistryHint =
    'This usually indicates a bug in the edit operation registry.';
const _contextDispatchHint =
    'Ensure that the correct operation is being dispatched for the context '
    'type.';
const _transformDispatchHint =
    'This usually indicates a state corruption or incorrect operation '
    'dispatch.';
const _paramsMappingHint =
    'This usually indicates a wrong edit intent mapping or parameters '
    'injection.';

/// Edit system error base type.
@immutable
sealed class EditError extends AppErrorBase {
  const EditError();

  @override
  ErrorSeverity get severity;
}

/// Thrown when an [EditContext] of an unexpected type is provided to an
/// operation.
@immutable
class EditContextTypeMismatchError extends EditError {
  const EditContextTypeMismatchError({
    required this.expected,
    required this.actual,
    required this.operationName,
    this.additionalInfo,
  });
  final Type expected;
  final Type actual;
  final String operationName;
  final String? additionalInfo;

  @override
  ErrorSeverity get severity => ErrorSeverity.fatal;

  @override
  String toString() => _buildTypeMismatchMessage(
    errorName: 'EditContextTypeMismatchError',
    operationName: operationName,
    valueName: 'context',
    expected: expected,
    actual: actual,
    additionalInfo: additionalInfo,
    hints: const [_contextRegistryHint, _contextDispatchHint],
  );
}

/// Thrown when an [EditTransform] of an unexpected type is provided to an
/// operation.
@immutable
class EditTransformTypeMismatchError extends EditError {
  const EditTransformTypeMismatchError({
    required this.expected,
    required this.actual,
    required this.operationName,
    this.additionalInfo,
  });
  final Type expected;
  final Type actual;
  final String operationName;
  final String? additionalInfo;

  @override
  ErrorSeverity get severity => ErrorSeverity.fatal;

  @override
  String toString() => _buildTypeMismatchMessage(
    errorName: 'EditTransformTypeMismatchError',
    operationName: operationName,
    valueName: 'transform',
    expected: expected,
    actual: actual,
    additionalInfo: additionalInfo,
    hints: const [_transformDispatchHint],
  );
}

/// Thrown when an [EditOperationParams] of an unexpected type is provided.
@immutable
class EditParamsTypeMismatchError extends EditError {
  const EditParamsTypeMismatchError({
    required this.expected,
    required this.actual,
    required this.operationName,
    this.additionalInfo,
  });
  final Type expected;
  final Type actual;
  final String operationName;
  final String? additionalInfo;

  @override
  ErrorSeverity get severity => ErrorSeverity.fatal;

  @override
  String toString() => _buildTypeMismatchMessage(
    errorName: 'EditParamsTypeMismatchError',
    operationName: operationName,
    valueName: 'params',
    expected: expected,
    actual: actual,
    additionalInfo: additionalInfo,
    hints: const [_paramsMappingHint],
  );
}

/// Thrown when required edit-session data is missing.
@immutable
class EditMissingDataError extends EditError {
  const EditMissingDataError({required this.dataName, this.operationName});
  final String dataName;
  final String? operationName;

  @override
  ErrorSeverity get severity => ErrorSeverity.degradable;

  @override
  String toString() {
    final operationPrefix = operationName == null ? '' : '[$operationName] ';
    return 'EditMissingDataError: ${operationPrefix}Missing required data: '
        '$dataName';
  }
}

/// Wrapper for errors with additional context information.
@immutable
class EditErrorWithContext extends EditError {
  const EditErrorWithContext({required this.innerError, required this.context});
  final EditError innerError;
  final ErrorContext context;

  @override
  ErrorSeverity get severity => innerError.severity;

  @override
  String toString() => '$innerError\n$context';
}
