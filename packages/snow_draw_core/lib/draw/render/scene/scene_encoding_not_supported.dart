import 'package:meta/meta.dart';

/// Signals that scene encoding is unavailable for the current element state.
///
/// Backends should fall back to legacy element rendering when this is thrown.
@immutable
final class SceneEncodingNotSupported implements Exception {
  /// Creates an unsupported-scene encoding signal.
  const SceneEncodingNotSupported(this.reason);

  /// Human-readable explanation for diagnostics.
  final String reason;

  @override
  String toString() => 'SceneEncodingNotSupported($reason)';
}
