import 'package:snow_draw_core/draw/elements/text_rendering_cache_invalidation.dart';
import 'package:snow_draw_core/draw/elements/types/serial_number/serial_number_layout.dart';
import 'package:snow_draw_core/draw/elements/types/text/text_layout.dart';
import '../../render/legacy/serial_number_renderer.dart';
import '../../render/legacy/text_renderer.dart';

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
