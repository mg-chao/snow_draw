import '../../core/value_listenable.dart';

import 'system_font_service_stub.dart' as platform;

/// Service for discovering and loading system-installed fonts at runtime.
///
/// Core exposes a backend-agnostic no-op implementation so reducers and tests
/// can remain pure Dart. Flutter-specific font discovery/loading lives in
/// `snow_draw_flutter_backend`.
class SystemFontService {
  const SystemFontService._();

  /// Shared singleton instance.
  ///
  /// Font state (index, loaded families) is inherently global because
  /// `FontLoader` registers fonts into the engine-wide font collection.
  static const instance = SystemFontService._();

  /// Returns a sorted list of all font family names available on the
  /// host operating system.
  ///
  /// The core default returns an empty list.
  Future<List<String>> listFamilies() => platform.listFamiliesImpl();

  /// Ensures [family] is loaded into the Flutter font engine.
  ///
  /// The core default is a no-op.
  Future<void> ensureLoaded(String family) => platform.ensureLoadedImpl(family);

  /// Notifier that increments whenever the set of loaded families
  /// changes.
  ///
  /// UI layers can listen to this to trigger repaints after a runtime
  /// font registration completes.
  ValueListenable<int> get revision => platform.revisionNotifier;
}
