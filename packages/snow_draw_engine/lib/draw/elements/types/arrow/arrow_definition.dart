import '../../core/element_definition.dart';
import '../connector/connector_creation_strategy.dart';
import '../connector/connector_hit_tester.dart';
import 'arrow_data.dart';
import 'arrow_task_encoder.dart';

const arrowDefinition = ElementDefinition<ArrowData>(
  typeId: ArrowData.typeIdToken,
  displayName: 'Arrow',
  hitTester: ConnectorHitTester(),
  createDefaultData: ArrowData.new,
  fromJson: ArrowData.fromJson,
  creationStrategy: ArrowCreationStrategy(),
  taskEncoder: ArrowTaskEncoder(),
);
