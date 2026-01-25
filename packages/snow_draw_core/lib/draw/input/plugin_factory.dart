import '../elements/core/element_data.dart';
import '../elements/core/element_type_id.dart';
import 'plugin_core.dart';
import 'plugins/arrow_create_plugin.dart';
import 'plugins/box_select_plugin.dart';
import 'plugins/create_plugin.dart';
import 'plugins/edit_plugin.dart';
import 'plugins/select_plugin.dart';
import 'plugins/text_tool_plugin.dart';

/// Plugin factory.
///
/// Creates standard plugins.
class PluginFactory {
  const PluginFactory();

  /// Create a PluginContext from ControllerDependencies.
  PluginContext createPluginContext(ControllerDependencies dependencies) =>
      PluginContext(
        stateProvider: () => dependencies.currentState,
        contextProvider: () => dependencies.context,
        selectionConfigProvider: () => dependencies.selectionConfig,
        dispatcher: dependencies.dispatch,
      );

  /// Create an edit plugin.
  EditPlugin createEditPlugin({
    InputRoutingPolicy routingPolicy = InputRoutingPolicy.defaultPolicy,
  }) => EditPlugin(routingPolicy: routingPolicy);

  /// Create a create plugin.
  CreatePlugin createCreatePlugin({
    ElementTypeId<ElementData>? currentToolTypeId,
    InputRoutingPolicy routingPolicy = InputRoutingPolicy.defaultPolicy,
  }) => CreatePlugin(
    currentToolTypeId: currentToolTypeId,
        routingPolicy: routingPolicy,
      );

  /// Create an arrow create plugin.
  ArrowCreatePlugin createArrowCreatePlugin({
    ElementTypeId<ElementData>? currentToolTypeId,
    InputRoutingPolicy routingPolicy = InputRoutingPolicy.defaultPolicy,
  }) => ArrowCreatePlugin(
    currentToolTypeId: currentToolTypeId,
    routingPolicy: routingPolicy,
  );

  /// Create a box select plugin.
  BoxSelectPlugin createBoxSelectPlugin({
    InputRoutingPolicy routingPolicy = InputRoutingPolicy.defaultPolicy,
  }) => BoxSelectPlugin(routingPolicy: routingPolicy);

  /// Create a select plugin.
  SelectPlugin createSelectPlugin({
    ElementTypeId<ElementData>? currentToolTypeId,
    InputRoutingPolicy routingPolicy = InputRoutingPolicy.defaultPolicy,
  }) => SelectPlugin(
    currentToolTypeId: currentToolTypeId,
    routingPolicy: routingPolicy,
  );

  /// Create a text tool plugin.
  TextToolPlugin createTextToolPlugin({
    ElementTypeId<ElementData>? currentToolTypeId,
    InputRoutingPolicy routingPolicy = InputRoutingPolicy.defaultPolicy,
  }) => TextToolPlugin(
    currentToolTypeId: currentToolTypeId,
    routingPolicy: routingPolicy,
  );

  /// Create all standard plugins.
  ///
  /// Returns plugins sorted by priority.
  List<InputPlugin> createStandardPlugins({
    ElementTypeId<ElementData>? currentToolTypeId,
    InputRoutingPolicy routingPolicy = InputRoutingPolicy.defaultPolicy,
  }) => [
    EditPlugin(routingPolicy: routingPolicy),
    TextToolPlugin(
      currentToolTypeId: currentToolTypeId,
      routingPolicy: routingPolicy,
    ),
    ArrowCreatePlugin(
      currentToolTypeId: currentToolTypeId,
      routingPolicy: routingPolicy,
    ),
    CreatePlugin(
      currentToolTypeId: currentToolTypeId,
      routingPolicy: routingPolicy,
    ),
    SelectPlugin(
      currentToolTypeId: currentToolTypeId,
      routingPolicy: routingPolicy,
    ),
    BoxSelectPlugin(routingPolicy: routingPolicy),
  ];
}

const pluginFactory = PluginFactory();
