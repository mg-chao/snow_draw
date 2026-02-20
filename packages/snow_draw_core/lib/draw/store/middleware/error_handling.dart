import 'package:meta/meta.dart';

/// Recovery action to take when an error occurs.
enum RecoveryAction {
  /// Stop the entire pipeline and return an error context.
  stop,

  /// Skip the middleware and continue.
  skip,

  /// Propagate the error up the call stack.
  propagate,
}

/// Simple error handler that chooses a recovery action.
@immutable
class ErrorHandler {
  const ErrorHandler({this.logger});

  final void Function(String message, Object error, StackTrace stackTrace)?
  logger;

  RecoveryAction handle(Object error, StackTrace stackTrace) {
    if (error is FormatException) {
      logger?.call('Skipping middleware after format error', error, stackTrace);
      return RecoveryAction.skip;
    }

    logger?.call('Stopping pipeline due to error', error, stackTrace);
    return RecoveryAction.stop;
  }
}
