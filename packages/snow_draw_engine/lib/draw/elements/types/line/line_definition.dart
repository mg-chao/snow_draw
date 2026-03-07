import '../../core/element_definition.dart';
import '../connector/connector_creation_strategy.dart';
import 'line_data.dart';
import 'line_hit_tester.dart';
import 'line_task_encoder.dart';

const lineDefinition = ElementDefinition<LineData>(
  typeId: LineData.typeIdToken,
  displayName: 'Line',
  hitTester: LineHitTester(),
  createDefaultData: LineData.new,
  fromJson: LineData.fromJson,
  creationStrategy: LineCreationStrategy(),
  taskEncoder: LineTaskEncoder(),
);
