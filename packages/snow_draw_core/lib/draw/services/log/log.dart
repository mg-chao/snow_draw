/// Snow Draw logging system.
///
/// Provides unified log management with modular logs, multiple outputs, and
/// EventBus integration.
///
/// ## Basic usage
///
/// ```dart
/// // Create the logging service
/// final logService = LogService(
///   config: LogConfig.development,
/// );
///
/// // Get module loggers
/// final storeLog = logService.store;
/// final editLog = logService.edit;
///
/// // Write logs
/// storeLog.debug('Dispatching action');
/// storeLog.info('State updated');
/// storeLog.error('Operation failed', error, stackTrace);
/// ```
///
/// ## Integrate with DrawContext
///
/// ```dart
/// final context = DrawContext.withDefaults(
///   logService: LogService(),
/// );
///
/// // Access logs through context anywhere
/// context.log.store.debug('Message');
/// ```
///
/// ## Configuration
///
/// ```dart
/// // Development
/// LogConfig.development
///
/// // Production
/// LogConfig.production
///
/// // Custom
/// LogConfig(
///   minLevel: Level.info,
///   moduleLevels: {
///     LogModule.pipeline: Level.debug,
///   },
/// )
/// ```
library;

export 'log_config.dart';
export 'log_output.dart';
export 'log_service.dart';
