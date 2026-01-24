import 'package:meta/meta.dart';

import '../../core/app_error.dart';
import '../../core/error_context.dart';
import '../../types/edit_context.dart' show EditContext;
import '../../types/edit_operation_id.dart';
import '../../types/edit_transform.dart' show EditTransform;
import 'edit_operation_params.dart' show EditOperationParams;

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
  String toString() {
    final buffer = StringBuffer()
      ..writeln('EditContextTypeMismatchError:')
      ..writeln('  Operation: $operationName')
      ..writeln('  Expected context type: $expected')
      ..writeln('  Actual context type: $actual');

    if (additionalInfo != null) {
      buffer.writeln('  Additional info: $additionalInfo');
    }

    buffer
      ..writeln(
        '  This usually indicates a bug in the edit operation registry.',
      )
      ..writeln(
        '  Ensure that the correct operation is being dispatched for the '
        'context type.',
      );

    return buffer.toString();
  }
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
  String toString() {
    final buffer = StringBuffer()
      ..writeln('EditTransformTypeMismatchError:')
      ..writeln('  Operation: $operationName')
      ..writeln('  Expected transform type: $expected')
      ..writeln('  Actual transform type: $actual');

    if (additionalInfo != null) {
      buffer.writeln('  Additional info: $additionalInfo');
    }

    buffer.writeln(
      '  This usually indicates a state corruption or incorrect operation '
      'dispatch.',
    );

    return buffer.toString();
  }
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
  String toString() {
    final buffer = StringBuffer()
      ..writeln('EditParamsTypeMismatchError:')
      ..writeln('  Operation: $operationName')
      ..writeln('  Expected params type: $expected')
      ..writeln('  Actual params type: $actual');

    if (additionalInfo != null) {
      buffer.writeln('  Additional info: $additionalInfo');
    }

    buffer.writeln(
      '  This usually indicates a wrong edit intent mapping or parameters '
      'injection.',
    );

    return buffer.toString();
  }
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
    if (operationName == null) {
      return 'EditMissingDataError: Missing required data: $dataName';
    }
    return 'EditMissingDataError: [$operationName] Missing required data: '
        '$dataName';
  }
}

/// Thrown when a version conflict is detected during edit operations.
@immutable
class EditVersionConflictError extends EditError {
  const EditVersionConflictError({
    required this.conflictType,
    required this.expectedVersion,
    required this.actualVersion,
    this.operationId,
  });
  final String conflictType; // 'selection' | 'elements'
  final int expectedVersion;
  final int actualVersion;
  final EditOperationId? operationId;

  @override
  ErrorSeverity get severity => ErrorSeverity.recoverable;

  @override
  String toString() =>
      'EditVersionConflictError: $conflictType version mismatch '
      '(expected: $expectedVersion, actual: $actualVersion)';
}

enum SessionRestoreFailure { notEditing, unknownOperation, sessionDataInvalid }

/// Thrown when session restoration fails.
@immutable
class EditSessionRestoreError extends EditError {
  const EditSessionRestoreError({
    required this.failureType,
    this.operationId,
    this.additionalInfo,
  });
  final SessionRestoreFailure failureType;
  final EditOperationId? operationId;
  final String? additionalInfo;

  @override
  ErrorSeverity get severity => ErrorSeverity.fatal;

  @override
  String toString() {
    final buffer = StringBuffer('EditSessionRestoreError: $failureType');
    if (operationId != null) {
      buffer.write(' (operationId: $operationId)');
    }
    if (additionalInfo != null) {
      buffer.write(' - $additionalInfo');
    }
    return buffer.toString();
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
