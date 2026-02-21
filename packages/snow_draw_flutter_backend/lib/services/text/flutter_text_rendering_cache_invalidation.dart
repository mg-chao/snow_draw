import 'package:snow_draw_core/draw/elements/text_rendering_cache_invalidation.dart';

import '../../render/text/serial_number_renderer.dart';
import '../../render/text/text_renderer.dart';
import 'flutter_serial_number_layout.dart';
import 'flutter_text_layout.dart';

var _isInstalled = false;

void _invalidateFlutterTextRenderingCaches() {
  clearTextLayoutCaches();
  clearSerialNumberTextLayoutCache();
  SerialNumberRenderer.clearCaches();
  TextRenderer.clearCaches();
}

/// Ensures Flutter-specific text rendering caches are wired into the core
/// invalidation flow.
void ensureFlutterTextRenderingCacheInvalidatorInstalled() {
  if (_isInstalled) {
    return;
  }
  registerTextRenderingCacheInvalidator(_invalidateFlutterTextRenderingCaches);
  _isInstalled = true;
}
