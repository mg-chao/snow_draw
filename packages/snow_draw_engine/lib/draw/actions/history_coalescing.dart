import 'package:meta/meta.dart';

/// Coalescing hint for high-frequency actions that should collapse history.
///
/// Actions with the same [key] dispatched within [window] are merged into a
/// single undo/redo entry.
@immutable
class HistoryCoalescing {
  const HistoryCoalescing({
    required this.key,
    this.window = const Duration(milliseconds: 220),
  }) : assert(key != '', 'key must not be empty');

  /// Stable group key used to match adjacent actions for coalescing.
  final String key;

  /// Maximum time gap allowed between adjacent actions in this group.
  final Duration window;
}

/// Optional interface for actions that want history coalescing behavior.
mixin HistoryCoalescingProvider {
  /// Returns a coalescing hint, or `null` to disable coalescing.
  HistoryCoalescing? get historyCoalescing => null;
}
