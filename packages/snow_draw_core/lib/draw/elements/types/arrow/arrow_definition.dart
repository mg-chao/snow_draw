import '../../core/element_definition.dart';
import 'arrow_creation_strategy.dart';
import 'arrow_data.dart';
import 'arrow_hit_tester.dart';
import 'arrow_task_encoder.dart';

final arrowDefinition = ElementDefinition<ArrowData>(
  typeId: ArrowData.typeIdToken,
  displayName: 'Arrow',
  hitTester: const ArrowHitTester(),
  createDefaultData: ArrowData.new,
  fromJson: ArrowData.fromJson,
  creationStrategy: const ArrowCreationStrategy(),
  taskEncoder: const ArrowTaskEncoder(),
);
