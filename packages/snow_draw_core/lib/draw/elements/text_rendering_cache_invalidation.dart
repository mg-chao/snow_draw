import '../core/value_listenable.dart';
import '../services/text/text_metrics_service.dart';

final _textRenderingCacheRevision = ValueNotifier<int>(0);
final _registeredInvalidators = <TextRenderingCacheInvalidator>{};

/// Signature for backend-provided text rendering cache invalidation hooks.
typedef TextRenderingCacheInvalidator = void Function();

/// Notifies listeners whenever text rendering caches are invalidated.
///
/// Consumers can listen to this value and trigger a repaint so cached
/// `Paragraph`-based glyph shaping gets rebuilt after runtime font loading.
final ValueListenable<int> textRenderingCacheRevisionListenable =
    _textRenderingCacheRevision;

/// Registers a backend-specific [invalidator].
///
/// Registered callbacks are executed when [invalidateTextRenderingCaches] runs.
/// Duplicate callbacks are ignored.
void registerTextRenderingCacheInvalidator(
  TextRenderingCacheInvalidator invalidator,
) {
  _registeredInvalidators.add(invalidator);
}

/// Unregisters a previously added [invalidator].
void unregisterTextRenderingCacheInvalidator(
  TextRenderingCacheInvalidator invalidator,
) {
  _registeredInvalidators.remove(invalidator);
}

/// Clears all text-related rendering/layout caches and publishes a revision.
///
/// Call this after runtime font registration completes to avoid stale
/// fallback-glyph paragraphs being reused.
void invalidateTextRenderingCaches() {
  defaultTextMetricsService.clearCaches();
  for (final invalidator in _registeredInvalidators) {
    invalidator();
  }
  _textRenderingCacheRevision.value++;
}
