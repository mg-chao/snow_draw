import 'edit_config.dart';

/// Edit configuration provider interface.
///
/// Provides access to edit configuration from different sources.
abstract interface class EditConfigProvider {
  /// Get the current edit configuration.
  EditConfig get editConfig;
}

/// Static configuration provider.
///
/// Uses a fixed configuration instance.
class StaticEditConfigProvider implements EditConfigProvider {
  const StaticEditConfigProvider(this.editConfig);
  @override
  final EditConfig editConfig;

  /// Use the default configuration.
  static const defaults = StaticEditConfigProvider(EditConfig.defaults);
}
