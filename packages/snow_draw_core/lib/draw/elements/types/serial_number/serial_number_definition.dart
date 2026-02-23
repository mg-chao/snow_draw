import '../../core/element_definition.dart';
import 'serial_number_creation_strategy.dart';
import 'serial_number_data.dart';
import 'serial_number_hit_tester.dart';
import 'serial_number_task_encoder.dart';

final serialNumberDefinition = ElementDefinition<SerialNumberData>(
  typeId: SerialNumberData.typeIdToken,
  displayName: 'Serial Number',
  hitTester: const SerialNumberHitTester(),
  createDefaultData: SerialNumberData.new,
  fromJson: SerialNumberData.fromJson,
  creationStrategy: const SerialNumberCreationStrategy(),
  taskEncoder: const SerialNumberTaskEncoder(),
);
