import 'package:flutter/foundation.dart';

import 'flutter_system_font_service_stub.dart'
    if (dart.library.io) 'flutter_system_font_service_io.dart'
    as platform;

/// Service for discovering and loading system-installed fonts at runtime.
///
/// Abstracts platform-specific font enumeration (Windows registry,
/// `fc-list`, macOS `system_profiler`) behind a single async API.
/// After a font family is loaded via [ensureLoaded], text-rendering caches are
/// invalidated so updated glyph shaping can take effect immediately.
class FlutterSystemFontService {
  const FlutterSystemFontService._();

  /// Shared singleton instance.
  static const instance = FlutterSystemFontService._();

  /// Returns a sorted list of available system font family names.
  Future<List<String>> listFamilies() => platform.listFamiliesImpl();

  /// Ensures [family] is loaded into the Flutter font engine.
  ///
  /// If the family was already loaded or is unavailable, this is a no-op.
  Future<void> ensureLoaded(String family) => platform.ensureLoadedImpl(family);

  /// Notifier that increments whenever loaded font families change.
  ValueListenable<int> get revision => platform.revisionNotifier;
}
