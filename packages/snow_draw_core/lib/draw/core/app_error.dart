import 'package:meta/meta.dart';

enum ErrorSeverity { recoverable, degradable, fatal }

/// Shared error base for application-level failures.
@immutable
abstract interface class AppError implements Exception {
  const AppError();

  String get message;
  ErrorSeverity get severity;
  Object? get cause;
}

/// Convenience base class with default message/cause handling.
@immutable
abstract class AppErrorBase implements AppError {
  const AppErrorBase();

  @override
  String get message => toString();

  @override
  Object? get cause => null;
}
