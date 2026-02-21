import '../core/value_listenable.dart';
import '../services/text/text_metrics_service.dart';

import 'types/serial_number/serial_number_layout.dart';
import 'types/text/text_renderer.dart';

final _textRenderingCacheRevision = ValueNotifier<int>(0);

/// Notifies listeners whenever text rendering caches are invalidated.
///
/// Consumers can listen to this value and trigger a repaint so cached
/// `Paragraph`-based glyph shaping gets rebuilt after runtime font loading.
final ValueListenable<int> textRenderingCacheRevisionListenable =
    _textRenderingCacheRevision;

/// Clears all text-related rendering/layout caches and publishes a revision.
///
/// Call this after runtime font registration completes to avoid stale
/// fallback-glyph paragraphs being reused.
void invalidateTextRenderingCaches() {
  defaultTextMetricsService.clearCaches();
  clearSerialNumberTextLayoutCache();
  TextRenderer.clearCaches();
  _textRenderingCacheRevision.value++;
}
