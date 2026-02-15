import 'package:flutter/foundation.dart';

import 'system_font_service_stub.dart'
    if (dart.library.io) 'system_font_service_io.dart'
    as platform;

/// Service for discovering and loading system-installed fonts at runtime.
///
/// Abstracts platform-specific font enumeration (Windows registry,
/// `fc-list`, macOS system_profiler) behind a single async API.
/// After a font family is loaded via [ensureLoaded], Flutter's engine
/// can shape text with it and the text-rendering caches are
/// automatically invalidated.
class SystemFontService {
  SystemFontService._();

  static final _instance = SystemFontService._();

  /// Shared singleton instance.
  ///
  /// Font state (index, loaded families) is inherently global because
  /// `FontLoader` registers fonts into the engine-wide font collection.
  static SystemFontService get instance => _instance;

  /// Returns a sorted list of all font family names available on the
  /// host operating system.
  ///
  /// The result is cached after the first successful index build.
  /// On platforms without `dart:io` (web) this returns an empty list.
  Future<List<String>> listFamilies() => platform.listFamiliesImpl();

  /// Ensures [family] is loaded into the Flutter font engine.
  ///
  /// If the family has already been loaded or is not found in the
  /// system font index, this completes immediately. Concurrent calls
  /// for the same family are coalesced into a single load operation.
  Future<void> ensureLoaded(String family) => platform.ensureLoadedImpl(family);

  /// Notifier that increments whenever the set of loaded families
  /// changes.
  ///
  /// UI layers can listen to this to trigger repaints after a runtime
  /// font registration completes.
  ValueListenable<int> get revision => platform.revisionNotifier;
}
