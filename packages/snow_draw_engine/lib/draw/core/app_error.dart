import 'package:meta/meta.dart';

enum ErrorSeverity { recoverable, degradable, fatal }

/// Shared error base for application-level failures.
@immutable
abstract class AppError implements Exception {
  const AppError();

  String get message => toString();
  ErrorSeverity get severity;
  Object? get cause => null;
}

/// Convenience base class with default message/cause handling.
@immutable
abstract class AppErrorBase extends AppError {
  const AppErrorBase();
}
